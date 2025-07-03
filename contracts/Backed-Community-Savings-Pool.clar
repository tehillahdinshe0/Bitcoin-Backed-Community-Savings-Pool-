(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-POOL-LOCKED (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-NOT-MEMBER (err u103))
(define-constant ERR-POOL-INACTIVE (err u104))
(define-constant ERR-ALREADY-MEMBER (err u105))
(define-constant ERR-INSUFFICIENT-BALANCE (err u106))
(define-constant ERR-INSUFFICIENT-TIER (err u107))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u108))
(define-constant ERR-ALREADY-VOTED (err u109))

(define-constant MIN-DEPOSIT-AMOUNT u100000)
(define-constant BRONZE-MIN u1000000)
(define-constant SILVER-MIN u5000000)
(define-constant GOLD-MIN u10000000)
(define-constant PLATINUM-MIN u25000000)

(define-constant BRONZE-MULTIPLIER u100)
(define-constant SILVER-MULTIPLIER u125)
(define-constant GOLD-MULTIPLIER u150)
(define-constant PLATINUM-MULTIPLIER u200)

(define-constant LOCK-PERIOD u144)
(define-constant INTEREST-RATE u5)
(define-constant BLOCKS-PER-CYCLE u1000)
(define-constant PROPOSAL-DURATION u1008)

(define-data-var pool-active bool false)
(define-data-var total-deposits uint u0)
(define-data-var current-rotation uint u0)
(define-data-var lock-height uint u0)
(define-data-var member-count uint u0)
(define-data-var interest-pool uint u0)
(define-data-var last-interest-distribution uint u0)
(define-data-var proposal-count uint u0)

(define-map pool-members principal 
  {
    joined-height: uint,
    total-deposited: uint,
    withdrawal-status: bool,
    last-withdrawal-height: uint,
    deposit-blocks: uint,
    accumulated-interest: uint,
    tier: uint,
    voting-power: uint
  }
)

(define-map deposit-history principal (list 50 {amount: uint, block-height: uint}))

(define-map tier-benefits uint
  {
    name: (string-ascii 20),
    min-deposit: uint,
    reward-multiplier: uint,
    early-withdrawal: bool,
    governance-weight: uint
  }
)

(define-map governance-proposals uint
  {
    proposer: principal,
    title: (string-ascii 50),
    description: (string-ascii 200),
    votes-for: uint,
    votes-against: uint,
    end-height: uint,
    executed: bool,
    proposal-type: uint
  }
)

(define-map member-votes {proposal-id: uint, voter: principal} bool)

(define-public (initialize-pool)
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
    (var-set pool-active true)
    (var-set lock-height stacks-block-height)
    (var-set last-interest-distribution stacks-block-height)
    (map-set tier-benefits u1 {name: "Bronze", min-deposit: BRONZE-MIN, reward-multiplier: BRONZE-MULTIPLIER, early-withdrawal: false, governance-weight: u1})
    (map-set tier-benefits u2 {name: "Silver", min-deposit: SILVER-MIN, reward-multiplier: SILVER-MULTIPLIER, early-withdrawal: false, governance-weight: u2})
    (map-set tier-benefits u3 {name: "Gold", min-deposit: GOLD-MIN, reward-multiplier: GOLD-MULTIPLIER, early-withdrawal: true, governance-weight: u3})
    (map-set tier-benefits u4 {name: "Platinum", min-deposit: PLATINUM-MIN, reward-multiplier: PLATINUM-MULTIPLIER, early-withdrawal: true, governance-weight: u5})
    (ok true)))

(define-private (determine-tier (amount uint))
  (if (>= amount PLATINUM-MIN)
    u4
    (if (>= amount GOLD-MIN)
      u3
      (if (>= amount SILVER-MIN)
        u2
        u1))))

(define-public (join-pool (initial-deposit uint))
  (begin
    (asserts! (var-get pool-active) ERR-POOL-INACTIVE)
    (asserts! (is-none (map-get? pool-members tx-sender)) ERR-ALREADY-MEMBER)
    (asserts! (>= initial-deposit BRONZE-MIN) ERR-INVALID-AMOUNT)
    (let ((member-tier (determine-tier initial-deposit))
          (voting-power (get governance-weight (unwrap-panic (map-get? tier-benefits member-tier)))))
      (try! (stx-transfer? initial-deposit tx-sender (as-contract tx-sender)))
      (map-set pool-members tx-sender
        {
          joined-height: stacks-block-height,
          total-deposited: initial-deposit,
          withdrawal-status: false,
          last-withdrawal-height: u0,
          deposit-blocks: u0,
          accumulated-interest: u0,
          tier: member-tier,
          voting-power: voting-power
        })
      (map-set deposit-history tx-sender (list {amount: initial-deposit, block-height: stacks-block-height}))
      (var-set member-count (+ (var-get member-count) u1))
      (var-set total-deposits (+ (var-get total-deposits) initial-deposit))
      (ok member-tier))))

(define-public (deposit (amount uint))
  (begin
    (asserts! (>= amount MIN-DEPOSIT-AMOUNT) ERR-INVALID-AMOUNT)
    (asserts! (is-some (map-get? pool-members tx-sender)) ERR-NOT-MEMBER)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((current-member (unwrap-panic (map-get? pool-members tx-sender)))
          (current-history (default-to (list) (map-get? deposit-history tx-sender)))
          (new-total (+ (get total-deposited current-member) amount))
          (new-tier (determine-tier new-total))
          (new-voting-power (get governance-weight (unwrap-panic (map-get? tier-benefits new-tier)))))
      (map-set pool-members tx-sender
        (merge current-member
          { 
            total-deposited: new-total,
            tier: new-tier,
            voting-power: new-voting-power,
            deposit-blocks: (+ (get deposit-blocks current-member) (* amount (- stacks-block-height (get joined-height current-member))))
          }))
      (map-set deposit-history tx-sender
        (unwrap-panic (as-max-len? (append current-history {amount: amount, block-height: stacks-block-height}) u50)))
      (var-set total-deposits (+ (var-get total-deposits) amount))
      (ok new-tier))))

(define-public (distribute-interest)
  (begin
    (asserts! (>= (- stacks-block-height (var-get last-interest-distribution)) BLOCKS-PER-CYCLE) ERR-POOL-LOCKED)
    (let ((interest-amount (/ (* (var-get total-deposits) INTEREST-RATE) u100)))
      (var-set interest-pool (+ (var-get interest-pool) interest-amount))
      (var-set last-interest-distribution stacks-block-height)
      (ok interest-amount))))

(define-public (claim-interest)
  (let ((member-data (unwrap! (map-get? pool-members tx-sender) ERR-NOT-MEMBER))
        (member-share (calculate-interest-share tx-sender)))
    (asserts! (> member-share u0) ERR-INSUFFICIENT-BALANCE)
    (try! (as-contract (stx-transfer? member-share (as-contract tx-sender) tx-sender)))
    (map-set pool-members tx-sender
      (merge member-data
        { accumulated-interest: u0 }))
    (var-set interest-pool (- (var-get interest-pool) member-share))
    (ok member-share)))

(define-public (request-withdrawal)
  (begin
    (asserts! (is-some (map-get? pool-members tx-sender)) ERR-NOT-MEMBER)
    (asserts! (>= stacks-block-height (+ (var-get lock-height) LOCK-PERIOD)) ERR-POOL-LOCKED)
    (map-set pool-members tx-sender
      (merge (unwrap-panic (map-get? pool-members tx-sender))
        { withdrawal-status: true }))
    (ok true)))

(define-public (process-withdrawal)
  (let ((member-data (unwrap! (map-get? pool-members tx-sender) ERR-NOT-MEMBER))
        (withdrawal-amount (get total-deposited member-data)))
    (asserts! (get withdrawal-status member-data) ERR-NOT-AUTHORIZED)
    (asserts! (>= stacks-block-height (+ (var-get lock-height) LOCK-PERIOD)) ERR-POOL-LOCKED)
    (try! (as-contract (stx-transfer? withdrawal-amount (as-contract tx-sender) tx-sender)))
    (map-set pool-members tx-sender
      (merge member-data 
        {
          withdrawal-status: false,
          last-withdrawal-height: stacks-block-height,
          total-deposited: u0,
          deposit-blocks: u0
        }))
    (var-set total-deposits (- (var-get total-deposits) withdrawal-amount))
    (var-set current-rotation (+ (var-get current-rotation) u1))
    (ok true)))

(define-public (create-proposal (title (string-ascii 50)) (description (string-ascii 200)) (proposal-type uint))
  (let ((member-data (unwrap! (map-get? pool-members tx-sender) ERR-NOT-MEMBER))
        (proposal-id (+ (var-get proposal-count) u1)))
    (asserts! (>= (get tier member-data) u2) ERR-INSUFFICIENT-TIER)
    (map-set governance-proposals proposal-id
      {
        proposer: tx-sender,
        title: title,
        description: description,
        votes-for: u0,
        votes-against: u0,
        end-height: (+ stacks-block-height PROPOSAL-DURATION),
        executed: false,
        proposal-type: proposal-type
      })
    (var-set proposal-count proposal-id)
    (ok proposal-id)))

(define-public (vote-proposal (proposal-id uint) (vote-for bool))
  (let ((member-data (unwrap! (map-get? pool-members tx-sender) ERR-NOT-MEMBER))
        (proposal-data (unwrap! (map-get? governance-proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
        (vote-key {proposal-id: proposal-id, voter: tx-sender}))
    (asserts! (is-none (map-get? member-votes vote-key)) ERR-ALREADY-VOTED)
    (asserts! (< stacks-block-height (get end-height proposal-data)) ERR-POOL-LOCKED)
    (let ((voting-power (get voting-power member-data)))
      (map-set member-votes vote-key true)
      (if vote-for
        (map-set governance-proposals proposal-id
          (merge proposal-data
            { votes-for: (+ (get votes-for proposal-data) voting-power) }))
        (map-set governance-proposals proposal-id
          (merge proposal-data
            { votes-against: (+ (get votes-against proposal-data) voting-power) })))
      (ok true))))

(define-read-only (calculate-interest-share (member principal))
  (let ((member-data (default-to 
                       {joined-height: u0, total-deposited: u0, withdrawal-status: false, 
                        last-withdrawal-height: u0, deposit-blocks: u0, accumulated-interest: u0,
                        tier: u1, voting-power: u0}
                       (map-get? pool-members member))))
    (if (> (get deposit-blocks member-data) u0)
        (/ (* (var-get interest-pool) (get deposit-blocks member-data)) 
           (var-get total-deposits))
        u0)))

(define-read-only (get-member-deposit-blocks (member principal))
  (get deposit-blocks (default-to 
                        {joined-height: u0, total-deposited: u0, withdrawal-status: false,
                         last-withdrawal-height: u0, deposit-blocks: u0, accumulated-interest: u0,
                         tier: u1, voting-power: u0}
                        (map-get? pool-members member))))

(define-read-only (get-pool-info)
  (ok {
    active: (var-get pool-active),
    total-deposits: (var-get total-deposits),
    current-rotation: (var-get current-rotation),
    lock-height: (var-get lock-height),
    member-count: (var-get member-count),
    interest-pool: (var-get interest-pool),
    last-interest-distribution: (var-get last-interest-distribution),
    proposal-count: (var-get proposal-count)
  }))

(define-read-only (get-member-info (member principal))
  (ok (unwrap! (map-get? pool-members member) ERR-NOT-MEMBER)))

(define-read-only (get-member-interest (member principal))
  (ok (calculate-interest-share member)))

(define-read-only (get-tier-benefits (tier-id uint))
  (ok (unwrap! (map-get? tier-benefits tier-id) ERR-INVALID-AMOUNT)))

(define-read-only (get-proposal-info (proposal-id uint))
  (ok (unwrap! (map-get? governance-proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
