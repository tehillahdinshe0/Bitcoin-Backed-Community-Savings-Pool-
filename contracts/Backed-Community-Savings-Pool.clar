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
(define-constant ERR-EMERGENCY-COOLDOWN (err u110))
(define-constant ERR-INSUFFICIENT-DEPOSIT (err u111))
(define-constant ERR-NO-REFERRAL-REWARDS (err u113))
(define-constant ERR-INVALID-REFERRER (err u112))
(define-constant ERR-ANALYTICS-DISABLED (err u114))
(define-constant ERR-INVALID-PERIOD (err u115))

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
(define-constant EMERGENCY-COOLDOWN u1008)

(define-constant BRONZE-PENALTY u30)
(define-constant SILVER-PENALTY u25)
(define-constant GOLD-PENALTY u15)
(define-constant PLATINUM-PENALTY u10)

(define-constant BRONZE-REFERRAL u2)
(define-constant SILVER-REFERRAL u3)
(define-constant GOLD-REFERRAL u4)
(define-constant PLATINUM-REFERRAL u5)

(define-constant LOCK-REWARD-MULTIPLIER-1 u110)
(define-constant LOCK-REWARD-MULTIPLIER-2 u120)
(define-constant LOCK-REWARD-MULTIPLIER-3 u135)
(define-constant LOCK-REWARD-MULTIPLIER-4 u150)
(define-constant LOCK-PERIOD-TIER-1 u4320)
(define-constant LOCK-PERIOD-TIER-2 u8640)
(define-constant LOCK-PERIOD-TIER-3 u17280)
(define-constant LOCK-PERIOD-TIER-4 u34560)

(define-data-var pool-active bool false)
(define-data-var total-deposits uint u0)
(define-data-var current-rotation uint u0)
(define-data-var lock-height uint u0)
(define-data-var member-count uint u0)
(define-data-var interest-pool uint u0)
(define-data-var last-interest-distribution uint u0)
(define-data-var proposal-count uint u0)
(define-data-var analytics-enabled bool true)
(define-data-var total-transactions uint u0)
(define-data-var pool-creation-height uint u0)
(define-data-var analytics-last-update uint u0)

(define-map pool-members principal 
  {
    joined-height: uint,
    total-deposited: uint,
    withdrawal-status: bool,
    last-withdrawal-height: uint,
    deposit-blocks: uint,
    accumulated-interest: uint,
    tier: uint,
    voting-power: uint,
    last-emergency-withdrawal: uint,
    referrer: (optional principal),
    referral-rewards: uint,
    total-referrals: uint,
    locked-amount: uint,
    lock-expiry-height: uint,
    lock-tier: uint
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

;; === ANALYTICS SYSTEM ===
(define-map pool-analytics-daily uint
  {
    date-block: uint,
    total-deposits-snapshot: uint,
    member-count-snapshot: uint,
    transactions-count: uint,
    average-deposit: uint,
    interest-distributed: uint
  }
)

(define-map member-analytics-monthly {member: principal, month-block: uint}
  {
    deposits-made: uint,
    total-deposited: uint,
    withdrawals-made: uint,
    total-withdrawn: uint,
    interest-earned: uint,
    tier-changes: uint,
    referrals-made: uint
  }
)

(define-map pool-performance-metrics uint
  {
    period-start: uint,
    period-end: uint,
    growth-rate: uint,
    retention-rate: uint,
    average-member-value: uint,
    total-interest-paid: uint,
    emergency-withdrawals: uint
  }
)

(define-public (initialize-pool)
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
    (var-set pool-active true)
    (var-set lock-height stacks-block-height)
    (var-set last-interest-distribution stacks-block-height)
    (var-set pool-creation-height stacks-block-height)
    (var-set analytics-last-update stacks-block-height)
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

(define-private (get-emergency-penalty (tier uint))
  (if (is-eq tier u4)
    PLATINUM-PENALTY
    (if (is-eq tier u3)
      GOLD-PENALTY
      (if (is-eq tier u2)
        SILVER-PENALTY
        BRONZE-PENALTY))))

(define-private (get-referral-rate (tier uint))
  (if (is-eq tier u4)
    PLATINUM-REFERRAL
    (if (is-eq tier u3)
      GOLD-REFERRAL
      (if (is-eq tier u2)
        SILVER-REFERRAL
        BRONZE-REFERRAL))))

(define-private (get-lock-multiplier (lock-tier uint))
  (if (is-eq lock-tier u4)
    LOCK-REWARD-MULTIPLIER-4
    (if (is-eq lock-tier u3)
      LOCK-REWARD-MULTIPLIER-3
      (if (is-eq lock-tier u2)
        LOCK-REWARD-MULTIPLIER-2
        LOCK-REWARD-MULTIPLIER-1))))

(define-private (get-lock-period (lock-tier uint))
  (if (is-eq lock-tier u4)
    LOCK-PERIOD-TIER-4
    (if (is-eq lock-tier u3)
      LOCK-PERIOD-TIER-3
      (if (is-eq lock-tier u2)
        LOCK-PERIOD-TIER-2
        LOCK-PERIOD-TIER-1))))

;; === ANALYTICS PRIVATE FUNCTIONS ===
(define-private (record-transaction)
  (begin
    (var-set total-transactions (+ (var-get total-transactions) u1))
    (var-set analytics-last-update stacks-block-height)))

(define-private (update-daily-analytics)
  (let ((current-day (/ stacks-block-height u144))
        (current-total (var-get total-deposits))
        (current-members (var-get member-count))
        (avg-deposit (if (> current-members u0) (/ current-total current-members) u0)))
    (map-set pool-analytics-daily current-day
      {
        date-block: stacks-block-height,
        total-deposits-snapshot: current-total,
        member-count-snapshot: current-members,
        transactions-count: (var-get total-transactions),
        average-deposit: avg-deposit,
        interest-distributed: (var-get interest-pool)
      })))

(define-private (update-member-monthly-analytics (member principal) (deposit-amount uint) (action (string-ascii 20)))
  (let ((current-month (/ stacks-block-height u4320))
        (analytics-key {member: member, month-block: current-month})
        (current-analytics (default-to 
                          {deposits-made: u0, total-deposited: u0, withdrawals-made: u0,
                           total-withdrawn: u0, interest-earned: u0, tier-changes: u0, referrals-made: u0}
                          (map-get? member-analytics-monthly analytics-key))))
    (if (is-eq action "deposit")
      (map-set member-analytics-monthly analytics-key
        (merge current-analytics
          {
            deposits-made: (+ (get deposits-made current-analytics) u1),
            total-deposited: (+ (get total-deposited current-analytics) deposit-amount)
          }))
      (if (is-eq action "withdraw")
        (map-set member-analytics-monthly analytics-key
          (merge current-analytics
            {
              withdrawals-made: (+ (get withdrawals-made current-analytics) u1),
              total-withdrawn: (+ (get total-withdrawn current-analytics) deposit-amount)
            }))
        true))))

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
          voting-power: voting-power,
          last-emergency-withdrawal: u0,
          referrer: none,
          referral-rewards: u0,
          total-referrals: u0,
          locked-amount: u0,
          lock-expiry-height: u0,
          lock-tier: u0
        })
      (map-set deposit-history tx-sender (list {amount: initial-deposit, block-height: stacks-block-height}))
      (var-set member-count (+ (var-get member-count) u1))
      (var-set total-deposits (+ (var-get total-deposits) initial-deposit))
      (record-transaction)
      (update-daily-analytics)
      (update-member-monthly-analytics tx-sender initial-deposit "deposit")
      (ok member-tier))))

(define-public (join-pool-with-referrer (initial-deposit uint) (referrer-address principal))
  (begin
    (asserts! (var-get pool-active) ERR-POOL-INACTIVE)
    (asserts! (is-none (map-get? pool-members tx-sender)) ERR-ALREADY-MEMBER)
    (asserts! (>= initial-deposit BRONZE-MIN) ERR-INVALID-AMOUNT)
    (asserts! (is-some (map-get? pool-members referrer-address)) ERR-INVALID-REFERRER)
    (asserts! (not (is-eq tx-sender referrer-address)) ERR-INVALID-REFERRER)
    (let ((member-tier (determine-tier initial-deposit))
          (voting-power (get governance-weight (unwrap-panic (map-get? tier-benefits member-tier))))
          (referrer-data (unwrap-panic (map-get? pool-members referrer-address)))
          (referrer-tier (get tier referrer-data))
          (referral-rate (get-referral-rate referrer-tier))
          (referral-reward (/ (* initial-deposit referral-rate) u100)))
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
          voting-power: voting-power,
          last-emergency-withdrawal: u0,
          referrer: (some referrer-address),
          referral-rewards: u0,
          total-referrals: u0,
          locked-amount: u0,
          lock-expiry-height: u0,
          lock-tier: u0
        })
      (map-set pool-members referrer-address
        (merge referrer-data
          {
            referral-rewards: (+ (get referral-rewards referrer-data) referral-reward),
            total-referrals: (+ (get total-referrals referrer-data) u1)
          }))
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
      (record-transaction)
      (update-daily-analytics)
      (update-member-monthly-analytics tx-sender amount "deposit")
      (ok new-tier))))

(define-read-only (calculate-interest-share (member principal))
  (let ((member-data (default-to 
                       {joined-height: u0, total-deposited: u0, withdrawal-status: false, 
                        last-withdrawal-height: u0, deposit-blocks: u0, accumulated-interest: u0,
                        tier: u1, voting-power: u0, last-emergency-withdrawal: u0,
                        referrer: none, referral-rewards: u0, total-referrals: u0,
                        locked-amount: u0, lock-expiry-height: u0, lock-tier: u0}
                       (map-get? pool-members member))))
    (let ((base (if (> (get deposit-blocks member-data) u0)
                  (/ (* (var-get interest-pool) (get deposit-blocks member-data)) (var-get total-deposits))
                  u0))
          (active-lock (and (> (get locked-amount member-data) u0)
                            (< stacks-block-height (get lock-expiry-height member-data)))))
      (if active-lock
        (/ (* base (get-lock-multiplier (get lock-tier member-data))) u100)
        base))))

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
        (withdrawal-amount (get total-deposited member-data))
        (active-lock (and (> (get locked-amount member-data) u0)
                          (< stacks-block-height (get lock-expiry-height member-data)))))
    (asserts! (get withdrawal-status member-data) ERR-NOT-AUTHORIZED)
    (asserts! (>= stacks-block-height (+ (var-get lock-height) LOCK-PERIOD)) ERR-POOL-LOCKED)
    (asserts! (not active-lock) ERR-POOL-LOCKED)
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
    (record-transaction)
    (update-daily-analytics)
    (update-member-monthly-analytics tx-sender withdrawal-amount "withdraw")
    (ok true)))

(define-public (emergency-withdrawal (amount uint))
  (let ((member-data (unwrap! (map-get? pool-members tx-sender) ERR-NOT-MEMBER))
        (member-tier (get tier member-data))
        (total-deposited (get total-deposited member-data))
        (last-emergency (get last-emergency-withdrawal member-data)))
    (asserts! (> total-deposited u0) ERR-INSUFFICIENT-DEPOSIT)
    (asserts! (>= total-deposited amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (>= (- stacks-block-height last-emergency) EMERGENCY-COOLDOWN) ERR-EMERGENCY-COOLDOWN)
    (let ((penalty-rate (get-emergency-penalty member-tier))
          (penalty-amount (/ (* amount penalty-rate) u100))
          (withdrawal-amount (- amount penalty-amount)))
      (try! (as-contract (stx-transfer? withdrawal-amount (as-contract tx-sender) tx-sender)))
      (map-set pool-members tx-sender
        (merge member-data
          {
            total-deposited: (- total-deposited amount),
            last-emergency-withdrawal: stacks-block-height,
            deposit-blocks: (- (get deposit-blocks member-data) (* amount (- stacks-block-height (get joined-height member-data))))
          }))
      (var-set total-deposits (- (var-get total-deposits) amount))
      (var-set interest-pool (+ (var-get interest-pool) penalty-amount))
      (ok {withdrawal: withdrawal-amount, penalty: penalty-amount}))))

(define-public (claim-referral-rewards)
  (let ((member-data (unwrap! (map-get? pool-members tx-sender) ERR-NOT-MEMBER))
        (reward-amount (get referral-rewards member-data)))
    (asserts! (> reward-amount u0) ERR-NO-REFERRAL-REWARDS)
    (try! (as-contract (stx-transfer? reward-amount (as-contract tx-sender) tx-sender)))
    (map-set pool-members tx-sender
      (merge member-data
        { referral-rewards: u0 }))
    (ok reward-amount)))

(define-public (lock-deposit (lock-amount uint) (lock-tier-level uint))
  (let ((member-data (unwrap! (map-get? pool-members tx-sender) ERR-NOT-MEMBER))
        (current-total-deposited (get total-deposited member-data))
        (lock-period (get-lock-period lock-tier-level)))
    (asserts! (and (>= lock-tier-level u1) (<= lock-tier-level u4)) ERR-INVALID-AMOUNT)
    (asserts! (> lock-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= lock-amount current-total-deposited) ERR-INSUFFICIENT-BALANCE)
    (asserts! (is-eq (get locked-amount member-data) u0) ERR-POOL-LOCKED)
    (map-set pool-members tx-sender
      (merge member-data
        {
          locked-amount: lock-amount,
          lock-expiry-height: (+ stacks-block-height lock-period),
          lock-tier: lock-tier-level
        }))
    (ok {
      locked-amount: lock-amount,
      lock-expiry-height: (+ stacks-block-height lock-period),
      lock-tier: lock-tier-level,
      reward-multiplier: (get-lock-multiplier lock-tier-level)
    })))

(define-public (unlock-deposit)
  (let ((member-data (unwrap! (map-get? pool-members tx-sender) ERR-NOT-MEMBER))
        (locked-amount (get locked-amount member-data))
        (lock-expiry (get lock-expiry-height member-data)))
    (asserts! (> locked-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= stacks-block-height lock-expiry) ERR-POOL-LOCKED)
    (map-set pool-members tx-sender
      (merge member-data
        {
          locked-amount: u0,
          lock-expiry-height: u0,
          lock-tier: u0
        }))
    (ok true)))

;; === ANALYTICS PUBLIC FUNCTIONS ===
(define-public (generate-performance-report (period-id uint))
  (let ((current-total (var-get total-deposits))
        (current-members (var-get member-count))
        (pool-age (- stacks-block-height (var-get pool-creation-height)))
        (avg-member-value (if (> current-members u0) (/ current-total current-members) u0)))
    (asserts! (var-get analytics-enabled) ERR-ANALYTICS-DISABLED)
    (map-set pool-performance-metrics period-id
      {
        period-start: (var-get analytics-last-update),
        period-end: stacks-block-height,
        growth-rate: (if (> pool-age u0) (/ (* current-total u100) pool-age) u0),
        retention-rate: (if (> current-members u0) (/ (* current-members u100) current-members) u100),
        average-member-value: avg-member-value,
        total-interest-paid: (var-get interest-pool),
        emergency-withdrawals: u0 ;; This would be tracked separately in a full implementation
      })
    (var-set analytics-last-update stacks-block-height)
    (ok true)))

(define-public (toggle-analytics)
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
    (var-set analytics-enabled (not (var-get analytics-enabled)))
    (ok (var-get analytics-enabled))))

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

(define-read-only (get-member-deposit-blocks (member principal))
  (get deposit-blocks (default-to 
                        {joined-height: u0, total-deposited: u0, withdrawal-status: false,
                         last-withdrawal-height: u0, deposit-blocks: u0, accumulated-interest: u0,
                         tier: u1, voting-power: u0, last-emergency-withdrawal: u0,
                         referrer: none, referral-rewards: u0, total-referrals: u0,
                         locked-amount: u0, lock-expiry-height: u0, lock-tier: u0}
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

(define-read-only (get-emergency-withdrawal-info (member principal))
  (let ((member-data (unwrap! (map-get? pool-members member) ERR-NOT-MEMBER))
        (member-tier (get tier member-data))
        (last-emergency (get last-emergency-withdrawal member-data)))
    (ok {
      penalty-rate: (get-emergency-penalty member-tier),
      cooldown-remaining: (if (>= (- stacks-block-height last-emergency) EMERGENCY-COOLDOWN) 
                            u0 
                            (- EMERGENCY-COOLDOWN (- stacks-block-height last-emergency))),
      eligible: (>= (- stacks-block-height last-emergency) EMERGENCY-COOLDOWN)
    })))

(define-read-only (get-referral-info (member principal))
  (let ((member-data (unwrap! (map-get? pool-members member) ERR-NOT-MEMBER))
        (member-tier (get tier member-data)))
    (ok {
      referrer: (get referrer member-data),
      referral-rewards: (get referral-rewards member-data),
      total-referrals: (get total-referrals member-data),
      referral-rate: (get-referral-rate member-tier)
    })))

(define-read-only (get-lock-status (member principal))
  (let ((member-data (unwrap! (map-get? pool-members member) ERR-NOT-MEMBER))
        (locked-amount (get locked-amount member-data))
        (lock-expiry (get lock-expiry-height member-data))
        (lock-tier-value (get lock-tier member-data)))
    (ok {
      locked-amount: locked-amount,
      lock-expiry-height: lock-expiry,
      lock-tier: lock-tier-value,
      lock-multiplier: (if (> locked-amount u0) (get-lock-multiplier lock-tier-value) u100),
      blocks-remaining: (if (> locked-amount u0) 
                          (if (>= stacks-block-height lock-expiry) u0 (- lock-expiry stacks-block-height))
                          u0),
      is-locked: (if (> locked-amount u0) true false)
    })))

;; === ANALYTICS READ-ONLY FUNCTIONS ===
(define-read-only (get-daily-analytics (day-id uint))
  (ok (map-get? pool-analytics-daily day-id)))

(define-read-only (get-member-monthly-analytics (member principal) (month-id uint))
  (ok (map-get? member-analytics-monthly {member: member, month-block: month-id})))

(define-read-only (get-performance-metrics (period-id uint))
  (ok (map-get? pool-performance-metrics period-id)))

(define-read-only (get-pool-growth-summary)
  (let ((current-total (var-get total-deposits))
        (current-members (var-get member-count))
        (pool-age (- stacks-block-height (var-get pool-creation-height)))
        (total-txs (var-get total-transactions)))
    (ok {
      pool-age-blocks: pool-age,
      total-members: current-members,
      total-deposits: current-total,
      total-transactions: total-txs,
      average-deposit-per-member: (if (> current-members u0) (/ current-total current-members) u0),
      transactions-per-day: (if (> pool-age u0) (/ (* total-txs u144) pool-age) u0),
      analytics-enabled: (var-get analytics-enabled),
      last-update: (var-get analytics-last-update)
    })))

(define-read-only (get-member-analytics-summary (member principal))
  (let ((member-data (unwrap! (map-get? pool-members member) ERR-NOT-MEMBER))
        (current-month (/ stacks-block-height u4320))
        (monthly-data (default-to 
                      {deposits-made: u0, total-deposited: u0, withdrawals-made: u0,
                       total-withdrawn: u0, interest-earned: u0, tier-changes: u0, referrals-made: u0}
                      (map-get? member-analytics-monthly {member: member, month-block: current-month}))))
    (ok {
      member-tier: (get tier member-data),
      total-deposited: (get total-deposited member-data),
      member-since: (get joined-height member-data),
      monthly-deposits: (get deposits-made monthly-data),
      monthly-deposited-amount: (get total-deposited monthly-data),
      monthly-withdrawals: (get withdrawals-made monthly-data),
      accumulated-interest: (get accumulated-interest member-data),
      referral-rewards: (get referral-rewards member-data),
      total-referrals: (get total-referrals member-data)
    })))

(define-read-only (calculate-pool-health-score)
  (let ((current-members (var-get member-count))
        (current-total (var-get total-deposits))
        (pool-age (- stacks-block-height (var-get pool-creation-height)))
        (interest-ratio (if (> current-total u0) (/ (* (var-get interest-pool) u100) current-total) u0)))
    (ok {
      member-diversity-score: (if (> current-members u10) u100 (* current-members u10)),
      deposit-stability-score: (if (> pool-age u1440) u100 (/ (* pool-age u100) u1440)),
      interest-health-score: (if (> interest-ratio u20) u100 (* interest-ratio u5)),
      overall-health-score: (/ (+ 
                                 (if (> current-members u10) u100 (* current-members u10))
                                 (if (> pool-age u1440) u100 (/ (* pool-age u100) u1440))
                                 (if (> interest-ratio u20) u100 (* interest-ratio u5))
                                ) u3)
    })))
