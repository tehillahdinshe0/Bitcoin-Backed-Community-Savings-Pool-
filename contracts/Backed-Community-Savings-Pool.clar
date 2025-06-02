(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-POOL-LOCKED (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-NOT-MEMBER (err u103))
(define-constant ERR-POOL-INACTIVE (err u104))
(define-constant ERR-ALREADY-MEMBER (err u105))
(define-constant MIN-DEPOSIT-AMOUNT u1000000)
(define-constant LOCK-PERIOD u144)

(define-data-var pool-active bool false)
(define-data-var total-deposits uint u0)
(define-data-var current-rotation uint u0)
(define-data-var lock-height uint u0)
(define-data-var member-count uint u0)

(define-map pool-members principal 
  {
    joined-height: uint,
    total-deposited: uint,
    withdrawal-status: bool,
    last-withdrawal-height: uint
  }
)

(define-public (initialize-pool)
  (begin
    (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
    (var-set pool-active true)
    (var-set lock-height stacks-block-height)
    (ok true)))

(define-public (join-pool)
  (begin
    (asserts! (var-get pool-active) ERR-POOL-INACTIVE)
    (asserts! (is-none (map-get? pool-members tx-sender)) ERR-ALREADY-MEMBER)
    (map-set pool-members tx-sender
      {
        joined-height: stacks-block-height,
        total-deposited: u0,
        withdrawal-status: false,
        last-withdrawal-height: u0
      })
    (var-set member-count (+ (var-get member-count) u1))
    (ok true)))

(define-public (deposit (amount uint))
  (begin
    (asserts! (>= amount MIN-DEPOSIT-AMOUNT) ERR-INVALID-AMOUNT)
    (asserts! (is-some (map-get? pool-members tx-sender)) ERR-NOT-MEMBER)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set pool-members tx-sender
      (merge (unwrap-panic (map-get? pool-members tx-sender))
        { total-deposited: (+ (get total-deposited (unwrap-panic (map-get? pool-members tx-sender))) amount) }))
    (var-set total-deposits (+ (var-get total-deposits) amount))
    (ok true)))

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
        (withdrawal-amount (/ (var-get total-deposits) (var-get member-count))))
    (asserts! (get withdrawal-status member-data) ERR-NOT-AUTHORIZED)
    (asserts! (>= stacks-block-height (+ (var-get lock-height) LOCK-PERIOD)) ERR-POOL-LOCKED)
    (try! (as-contract (stx-transfer? withdrawal-amount (as-contract tx-sender) tx-sender)))
    (map-set pool-members tx-sender
      (merge member-data 
        {
          withdrawal-status: false,
          last-withdrawal-height: stacks-block-height
        }))
    (var-set current-rotation (+ (var-get current-rotation) u1))
    (ok true)))

(define-read-only (get-pool-info)
  (ok {
    active: (var-get pool-active),
    total-deposits: (var-get total-deposits),
    current-rotation: (var-get current-rotation),
    lock-height: (var-get lock-height),
    member-count: (var-get member-count)
  }))

(define-read-only (get-member-info (member principal))
  (ok (unwrap! (map-get? pool-members member) ERR-NOT-MEMBER)))
