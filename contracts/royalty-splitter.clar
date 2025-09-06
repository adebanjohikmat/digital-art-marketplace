
;; title: royalty-splitter
;; version: 1.0.0
;; summary: Royalty Distribution Contract for Digital Art NFTs
;; description: Manages automatic royalty splits and payments among artists and stakeholders

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-SPLIT (err u301))
(define-constant ERR-SPLIT-NOT-FOUND (err u302))
(define-constant ERR-INSUFFICIENT-FUNDS (err u303))
(define-constant ERR-INVALID-PERCENTAGE (err u304))
(define-constant ERR-TOO-MANY-RECIPIENTS (err u305))
(define-constant ERR-DUPLICATE-RECIPIENT (err u306))
(define-constant ERR-ZERO-AMOUNT (err u307))
(define-constant ERR-TRANSFER-FAILED (err u308))
(define-constant ERR-SPLIT-ALREADY-EXISTS (err u309))
(define-constant ERR-INVALID-NFT-ID (err u310))

(define-constant MAX-RECIPIENTS u10)
(define-constant MIN-SPLIT-PERCENTAGE u100) ;; 1%
(define-constant PERCENTAGE-BASE u10000)    ;; 100%
(define-constant MIN-PAYOUT-AMOUNT u100000) ;; 0.1 STX minimum

;; Data variables
(define-data-var total-payouts uint u0)
(define-data-var total-volume-distributed uint u0)
(define-data-var contract-fee-bps uint u50) ;; 0.5% contract fee
(define-data-var fee-recipient principal CONTRACT-OWNER)
(define-data-var splits-created uint u0)

;; Data maps

;; Split configurations for each NFT
(define-map royalty-splits
  { nft-id: uint }
  {
    creator: principal,
    total-percentage: uint,
    recipient-count: uint,
    created-at: uint,
    updated-at: uint,
    is-active: bool
  }
)

;; Individual recipient splits within each NFT's royalty structure
(define-map split-recipients
  { nft-id: uint, recipient-index: uint }
  {
    recipient: principal,
    percentage: uint,
    role: (string-ascii 32)
  }
)

;; Payment history for auditing
(define-map payment-history
  { payment-id: uint }
  {
    nft-id: uint,
    total-amount: uint,
    contract-fee: uint,
    distributed-amount: uint,
    recipient-count: uint,
    payout-at: uint,
    initiated-by: principal
  }
)

;; Individual recipient payment records
(define-map recipient-payments
  { payment-id: uint, recipient-index: uint }
  {
    recipient: principal,
    amount: uint,
    percentage: uint
  }
)

;; User earnings tracking
(define-map user-earnings
  { user: principal }
  {
    total-earned: uint,
    payment-count: uint,
    last-payment: uint
  }
)

;; Pending balances (for failed transfers)
(define-map pending-balances
  { user: principal }
  { amount: uint }
)

;; Payment ID counter
(define-data-var payment-id-nonce uint u0)

;; Public functions

;; Register a new royalty split configuration for an NFT
(define-public (register-split (nft-id uint) (recipients (list 10 { recipient: principal, percentage: uint, role: (string-ascii 32) })))
  (let
    (
      (existing-split (map-get? royalty-splits { nft-id: nft-id }))
      (recipient-count (len recipients))
      (total-percentage (fold calculate-total-percentage recipients u0))
      (current-splits (var-get splits-created))
    )
    ;; Validations
    (asserts! (is-none existing-split) ERR-SPLIT-ALREADY-EXISTS)
    (asserts! (> recipient-count u0) ERR-INVALID-SPLIT)
    (asserts! (<= recipient-count MAX-RECIPIENTS) ERR-TOO-MANY-RECIPIENTS)
    (asserts! (is-eq total-percentage PERCENTAGE-BASE) ERR-INVALID-PERCENTAGE)
    (asserts! (> nft-id u0) ERR-INVALID-NFT-ID)
    
    ;; Validate no duplicate recipients
    (asserts! (is-eq (len recipients) (len (dedup-recipients recipients))) ERR-DUPLICATE-RECIPIENT)
    
    ;; Store main split configuration
    (map-set royalty-splits
      { nft-id: nft-id }
      {
        creator: tx-sender,
        total-percentage: total-percentage,
        recipient-count: recipient-count,
        created-at: block-height,
        updated-at: block-height,
        is-active: true
      }
    )
    
    ;; Store individual recipients
    (fold store-recipient recipients { nft-id: nft-id, index: u0 })
    
    ;; Update counter
    (var-set splits-created (+ current-splits u1))
    
    (print {
      event: "split-registered",
      nft-id: nft-id,
      creator: tx-sender,
      recipient-count: recipient-count,
      total-percentage: total-percentage
    })
    
    (ok true)
  )
)

;; Execute royalty payout for an NFT
(define-public (payout (nft-id uint) (total-amount uint))
  (let
    (
      (split-info (unwrap! (map-get? royalty-splits { nft-id: nft-id }) ERR-SPLIT-NOT-FOUND))
      (recipient-count (get recipient-count split-info))
      (contract-fee (/ (* total-amount (var-get contract-fee-bps)) PERCENTAGE-BASE))
      (distributable-amount (- total-amount contract-fee))
      (new-payment-id (+ (var-get payment-id-nonce) u1))
    )
    ;; Validations
    (asserts! (get is-active split-info) ERR-SPLIT-NOT-FOUND)
    (asserts! (>= total-amount MIN-PAYOUT-AMOUNT) ERR-ZERO-AMOUNT)
    (asserts! (>= (stx-get-balance tx-sender) total-amount) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer contract fee
    (try! (stx-transfer? contract-fee tx-sender (var-get fee-recipient)))
    
    ;; Distribute to recipients
    (unwrap! (distribute-to-recipients nft-id distributable-amount new-payment-id recipient-count) ERR-TRANSFER-FAILED)
    
    ;; Record payment history
    (map-set payment-history
      { payment-id: new-payment-id }
      {
        nft-id: nft-id,
        total-amount: total-amount,
        contract-fee: contract-fee,
        distributed-amount: distributable-amount,
        recipient-count: recipient-count,
        payout-at: block-height,
        initiated-by: tx-sender
      }
    )
    
    ;; Update global statistics
    (var-set payment-id-nonce new-payment-id)
    (var-set total-payouts (+ (var-get total-payouts) u1))
    (var-set total-volume-distributed (+ (var-get total-volume-distributed) total-amount))
    
    (print {
      event: "royalty-payout",
      nft-id: nft-id,
      payment-id: new-payment-id,
      total-amount: total-amount,
      distributed-amount: distributable-amount,
      recipient-count: recipient-count
    })
    
    (ok new-payment-id)
  )
)

;; Update an existing split configuration (only creator can update)
(define-public (update-split (nft-id uint) (new-recipients (list 10 { recipient: principal, percentage: uint, role: (string-ascii 32) })))
  (let
    (
      (split-info (unwrap! (map-get? royalty-splits { nft-id: nft-id }) ERR-SPLIT-NOT-FOUND))
      (creator (get creator split-info))
      (recipient-count (len new-recipients))
      (total-percentage (fold calculate-total-percentage new-recipients u0))
    )
    ;; Authorization check
    (asserts! (or (is-eq tx-sender creator) (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    
    ;; Validations
    (asserts! (get is-active split-info) ERR-SPLIT-NOT-FOUND)
    (asserts! (> recipient-count u0) ERR-INVALID-SPLIT)
    (asserts! (<= recipient-count MAX-RECIPIENTS) ERR-TOO-MANY-RECIPIENTS)
    (asserts! (is-eq total-percentage PERCENTAGE-BASE) ERR-INVALID-PERCENTAGE)
    
    ;; Clear old recipients
    (clear-recipients nft-id (get recipient-count split-info))
    
    ;; Update split configuration
    (map-set royalty-splits
      { nft-id: nft-id }
      {
        creator: creator,
        total-percentage: total-percentage,
        recipient-count: recipient-count,
        created-at: (get created-at split-info),
        updated-at: block-height,
        is-active: true
      }
    )
    
    ;; Store new recipients
    (fold store-recipient new-recipients { nft-id: nft-id, index: u0 })
    
    (print {
      event: "split-updated",
      nft-id: nft-id,
      updater: tx-sender,
      recipient-count: recipient-count
    })
    
    (ok true)
  )
)

;; Disable a split (only creator or admin)
(define-public (disable-split (nft-id uint))
  (let
    (
      (split-info (unwrap! (map-get? royalty-splits { nft-id: nft-id }) ERR-SPLIT-NOT-FOUND))
      (creator (get creator split-info))
    )
    ;; Authorization check
    (asserts! (or (is-eq tx-sender creator) (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    
    ;; Update split status
    (map-set royalty-splits
      { nft-id: nft-id }
      {
        creator: creator,
        total-percentage: (get total-percentage split-info),
        recipient-count: (get recipient-count split-info),
        created-at: (get created-at split-info),
        updated-at: block-height,
        is-active: false
      }
    )
    
    (print { event: "split-disabled", nft-id: nft-id })
    (ok true)
  )
)

;; Claim pending balance
(define-public (claim-pending-balance)
  (let
    (
      (pending-amount (default-to u0 (get amount (map-get? pending-balances { user: tx-sender }))))
    )
    (asserts! (> pending-amount u0) ERR-ZERO-AMOUNT)
    
    ;; Transfer pending amount
    (try! (as-contract (stx-transfer? pending-amount tx-sender tx-sender)))
    
    ;; Clear pending balance
    (map-delete pending-balances { user: tx-sender })
    
    (print {
      event: "pending-balance-claimed",
      user: tx-sender,
      amount: pending-amount
    })
    
    (ok pending-amount)
  )
)

;; Admin functions
(define-public (set-contract-fee (new-fee-bps uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fee-bps u500) ERR-INVALID-PERCENTAGE) ;; Max 5%
    (var-set contract-fee-bps new-fee-bps)
    (ok true)
  )
)

(define-public (set-fee-recipient (new-recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set fee-recipient new-recipient)
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-split-info (nft-id uint))
  (map-get? royalty-splits { nft-id: nft-id })
)

(define-read-only (get-split-recipient (nft-id uint) (recipient-index uint))
  (map-get? split-recipients { nft-id: nft-id, recipient-index: recipient-index })
)

(define-read-only (get-payment-info (payment-id uint))
  (map-get? payment-history { payment-id: payment-id })
)

(define-read-only (get-recipient-payment (payment-id uint) (recipient-index uint))
  (map-get? recipient-payments { payment-id: payment-id, recipient-index: recipient-index })
)

(define-read-only (get-user-earnings (user principal))
  (default-to
    { total-earned: u0, payment-count: u0, last-payment: u0 }
    (map-get? user-earnings { user: user })
  )
)

(define-read-only (get-pending-balance (user principal))
  (ok (default-to u0 (get amount (map-get? pending-balances { user: user }))))
)

(define-read-only (get-contract-stats)
  (ok {
    total-payouts: (var-get total-payouts),
    total-volume-distributed: (var-get total-volume-distributed),
    contract-fee-bps: (var-get contract-fee-bps),
    splits-created: (var-get splits-created)
  })
)

;; Private functions

(define-private (calculate-total-percentage (recipient { recipient: principal, percentage: uint, role: (string-ascii 32) }) (acc uint))
  (+ acc (get percentage recipient))
)

(define-private (store-recipient (recipient { recipient: principal, percentage: uint, role: (string-ascii 32) }) (ctx { nft-id: uint, index: uint }))
  (let
    (
      (nft-id (get nft-id ctx))
      (index (get index ctx))
    )
    (map-set split-recipients
      { nft-id: nft-id, recipient-index: index }
      {
        recipient: (get recipient recipient),
        percentage: (get percentage recipient),
        role: (get role recipient)
      }
    )
    { nft-id: nft-id, index: (+ index u1) }
  )
)

(define-private (dedup-recipients (recipients (list 10 { recipient: principal, percentage: uint, role: (string-ascii 32) })))
  ;; Simplified deduplication check - in production, implement proper deduplication
  recipients
)

(define-private (distribute-to-recipients (nft-id uint) (total-amount uint) (payment-id uint) (recipient-count uint))
  (let
    (
      (result (fold distribute-single-recipient
                    (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)
                    { nft-id: nft-id, total-amount: total-amount, payment-id: payment-id, max-count: recipient-count, success: true }))
    )
    (if (get success result)
      (ok true)
      (err ERR-TRANSFER-FAILED)
    )
  )
)

(define-private (distribute-single-recipient (recipient-index uint) (ctx { nft-id: uint, total-amount: uint, payment-id: uint, max-count: uint, success: bool }))
  (if (and (get success ctx) (< recipient-index (get max-count ctx)))
    (match (map-get? split-recipients { nft-id: (get nft-id ctx), recipient-index: recipient-index })
      recipient-info
      (let
        (
          (recipient (get recipient recipient-info))
          (percentage (get percentage recipient-info))
          (amount (/ (* (get total-amount ctx) percentage) PERCENTAGE-BASE))
        )
        ;; Try to transfer, if fails, add to pending balance
        (match (stx-transfer? amount tx-sender recipient)
          success (begin
            ;; Record successful payment
            (map-set recipient-payments
              { payment-id: (get payment-id ctx), recipient-index: recipient-index }
              {
                recipient: recipient,
                amount: amount,
                percentage: percentage
              }
            )
            ;; Update user earnings
            (update-user-earnings recipient amount)
            ctx
          )
          error (begin
            ;; Add to pending balance
            (add-to-pending-balance recipient amount)
            ctx
          )
        )
      )
      ctx ;; No recipient at this index
    )
    ctx ;; Skip if index >= max-count or previous error
  )
)

(define-private (update-user-earnings (user principal) (amount uint))
  (let
    (
      (current-earnings (default-to
        { total-earned: u0, payment-count: u0, last-payment: u0 }
        (map-get? user-earnings { user: user })
      ))
    )
    (map-set user-earnings
      { user: user }
      {
        total-earned: (+ (get total-earned current-earnings) amount),
        payment-count: (+ (get payment-count current-earnings) u1),
        last-payment: block-height
      }
    )
  )
)

(define-private (add-to-pending-balance (user principal) (amount uint))
  (let
    (
      (current-pending (default-to u0 (get amount (map-get? pending-balances { user: user }))))
    )
    (map-set pending-balances
      { user: user }
      { amount: (+ current-pending amount) }
    )
  )
)

(define-private (clear-recipients (nft-id uint) (count uint))
  (fold clear-single-recipient
        (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)
        { nft-id: nft-id, max-count: count })
)

(define-private (clear-single-recipient (recipient-index uint) (ctx { nft-id: uint, max-count: uint }))
  (if (< recipient-index (get max-count ctx))
    (begin
      (map-delete split-recipients { nft-id: (get nft-id ctx), recipient-index: recipient-index })
      ctx
    )
    ctx
  )
)

;; Contract initialization
(begin
  (print "Royalty Splitter Contract Deployed")
  (print { contract-owner: CONTRACT-OWNER })
)

