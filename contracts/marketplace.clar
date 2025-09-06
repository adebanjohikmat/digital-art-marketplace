
;; title: marketplace
;; version: 1.0.0
;; summary: Digital Art NFT Marketplace Contract
;; description: Facilitates buying, selling, and trading of digital art NFTs with escrow functionality

;; Import NFT contract (reference for internal calls)
;; Note: In real deployment, this would reference the deployed NFT contract

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-ALREADY-LISTED (err u202))
(define-constant ERR-NOT-OWNER (err u203))
(define-constant ERR-INSUFFICIENT-FUNDS (err u204))
(define-constant ERR-INVALID-PRICE (err u205))
(define-constant ERR-SELF-TRANSFER (err u206))
(define-constant ERR-LISTING-EXPIRED (err u207))
(define-constant ERR-INVALID-ROYALTY (err u208))
(define-constant ERR-TRANSFER-FAILED (err u209))
(define-constant ERR-MARKETPLACE-PAUSED (err u210))
(define-constant ERR-INVALID-OFFER (err u211))

(define-constant MARKETPLACE-FEE-BPS u250) ;; 2.5%
(define-constant MAX-ROYALTY-BPS u1000)    ;; 10%
(define-constant BPS-BASE u10000)          ;; 100%
(define-constant MIN-PRICE u1000000)       ;; 1 STX minimum
(define-constant LISTING-DURATION u144)    ;; ~24 hours in blocks

;; Data variables
(define-data-var marketplace-enabled bool true)
(define-data-var total-volume uint u0)
(define-data-var total-sales uint u0)
(define-data-var marketplace-fee-bps uint MARKETPLACE-FEE-BPS)
(define-data-var fee-recipient principal CONTRACT-OWNER)

;; Data maps

;; Active listings
(define-map listings
  { token-id: uint }
  {
    seller: principal,
    price: uint,
    created-at: uint,
    expires-at: uint,
    royalty-recipient: (optional principal),
    royalty-bps: uint
  }
)

;; Sales history
(define-map sales-history
  { sale-id: uint }
  {
    token-id: uint,
    seller: principal,
    buyer: principal,
    price: uint,
    marketplace-fee: uint,
    royalty-fee: uint,
    sold-at: uint
  }
)

;; Offer system
(define-map offers
  { token-id: uint, offeror: principal }
  {
    amount: uint,
    expires-at: uint,
    created-at: uint
  }
)

;; User statistics
(define-map user-stats
  { user: principal }
  {
    items-sold: uint,
    items-bought: uint,
    total-volume-sold: uint,
    total-volume-bought: uint
  }
)

;; Sale counter for unique sale IDs
(define-data-var sale-id-nonce uint u0)

;; Public functions

;; List NFT for sale
(define-public (list-nft (token-id uint) (price uint) (royalty-recipient (optional principal)) (royalty-bps uint))
  (let
    (
      (listing-info (map-get? listings { token-id: token-id }))
      (expires-at (+ block-height LISTING-DURATION))
    )
    ;; Validation checks
    (asserts! (var-get marketplace-enabled) ERR-MARKETPLACE-PAUSED)
    (asserts! (is-none listing-info) ERR-ALREADY-LISTED)
    (asserts! (>= price MIN-PRICE) ERR-INVALID-PRICE)
    (asserts! (<= royalty-bps MAX-ROYALTY-BPS) ERR-INVALID-ROYALTY)
    
    ;; Verify ownership (simplified - in real implementation would call NFT contract)
    ;; For this demo, we assume tx-sender owns the token
    
    ;; Create listing
    (map-set listings
      { token-id: token-id }
      {
        seller: tx-sender,
        price: price,
        created-at: block-height,
        expires-at: expires-at,
        royalty-recipient: royalty-recipient,
        royalty-bps: royalty-bps
      }
    )
    
    (print {
      event: "nft-listed",
      token-id: token-id,
      seller: tx-sender,
      price: price,
      expires-at: expires-at
    })
    
    (ok true)
  )
)

;; Buy listed NFT
(define-public (buy-nft (token-id uint))
  (let
    (
      (listing-info (unwrap! (map-get? listings { token-id: token-id }) ERR-NOT-FOUND))
      (seller (get seller listing-info))
      (price (get price listing-info))
      (royalty-recipient (get royalty-recipient listing-info))
      (royalty-bps (get royalty-bps listing-info))
      (marketplace-fee (/ (* price (var-get marketplace-fee-bps)) BPS-BASE))
      (royalty-fee (/ (* price royalty-bps) BPS-BASE))
      (seller-proceeds (- price (+ marketplace-fee royalty-fee)))
      (new-sale-id (+ (var-get sale-id-nonce) u1))
      (current-volume (var-get total-volume))
      (current-sales (var-get total-sales))
    )
    ;; Validation checks
    (asserts! (var-get marketplace-enabled) ERR-MARKETPLACE-PAUSED)
    (asserts! (<= block-height (get expires-at listing-info)) ERR-LISTING-EXPIRED)
    (asserts! (not (is-eq tx-sender seller)) ERR-SELF-TRANSFER)
    (asserts! (>= (stx-get-balance tx-sender) price) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer STX to seller
    (try! (stx-transfer? seller-proceeds tx-sender seller))
    
    ;; Transfer marketplace fee
    (try! (stx-transfer? marketplace-fee tx-sender (var-get fee-recipient)))
    
    ;; Transfer royalty if applicable
    (match royalty-recipient
      recipient (try! (stx-transfer? royalty-fee tx-sender recipient))
      true ;; No royalty recipient
    )
    
    ;; In real implementation, transfer NFT ownership would happen here
    ;; (contract-call? .nft-minting transfer token-id seller tx-sender)
    
    ;; Remove listing
    (map-delete listings { token-id: token-id })
    
    ;; Record sale
    (map-set sales-history
      { sale-id: new-sale-id }
      {
        token-id: token-id,
        seller: seller,
        buyer: tx-sender,
        price: price,
        marketplace-fee: marketplace-fee,
        royalty-fee: royalty-fee,
        sold-at: block-height
      }
    )
    
    ;; Update user statistics
    (update-user-stats seller tx-sender price)
    
    ;; Update global statistics
    (var-set sale-id-nonce new-sale-id)
    (var-set total-volume (+ current-volume price))
    (var-set total-sales (+ current-sales u1))
    
    (print {
      event: "nft-sold",
      token-id: token-id,
      seller: seller,
      buyer: tx-sender,
      price: price,
      sale-id: new-sale-id
    })
    
    (ok new-sale-id)
  )
)

;; Cancel listing
(define-public (cancel-listing (token-id uint))
  (let
    (
      (listing-info (unwrap! (map-get? listings { token-id: token-id }) ERR-NOT-FOUND))
    )
    ;; Only seller or contract owner can cancel
    (asserts! (or (is-eq tx-sender (get seller listing-info))
                  (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    
    ;; Remove listing
    (map-delete listings { token-id: token-id })
    
    (print {
      event: "listing-cancelled",
      token-id: token-id,
      seller: (get seller listing-info)
    })
    
    (ok true)
  )
)

;; Make offer on NFT
(define-public (make-offer (token-id uint) (amount uint) (duration uint))
  (let
    (
      (expires-at (+ block-height duration))
      (existing-offer (map-get? offers { token-id: token-id, offeror: tx-sender }))
    )
    ;; Validation
    (asserts! (>= amount MIN-PRICE) ERR-INVALID-PRICE)
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR-INSUFFICIENT-FUNDS)
    (asserts! (<= duration u1008) ERR-INVALID-OFFER) ;; Max 7 days
    
    ;; If existing offer, return the old amount first
    (match existing-offer
      old-offer (begin
        (try! (stx-transfer? (get amount old-offer) (as-contract tx-sender) tx-sender))
        true
      )
      true
    )
    
    ;; Escrow the offer amount
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Store offer
    (map-set offers
      { token-id: token-id, offeror: tx-sender }
      {
        amount: amount,
        expires-at: expires-at,
        created-at: block-height
      }
    )
    
    (print {
      event: "offer-made",
      token-id: token-id,
      offeror: tx-sender,
      amount: amount,
      expires-at: expires-at
    })
    
    (ok true)
  )
)

;; Accept offer
(define-public (accept-offer (token-id uint) (offeror principal))
  (let
    (
      (offer-info (unwrap! (map-get? offers { token-id: token-id, offeror: offeror }) ERR-NOT-FOUND))
      (amount (get amount offer-info))
      (marketplace-fee (/ (* amount (var-get marketplace-fee-bps)) BPS-BASE))
      (seller-proceeds (- amount marketplace-fee))
      (new-sale-id (+ (var-get sale-id-nonce) u1))
    )
    ;; Validation - only owner can accept (simplified)
    ;; (asserts! (is-eq tx-sender (unwrap! (get-nft-owner token-id) ERR-NOT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (<= block-height (get expires-at offer-info)) ERR-LISTING-EXPIRED)
    
    ;; Transfer funds from escrow
    (try! (as-contract (stx-transfer? seller-proceeds tx-sender tx-sender)))
    (try! (as-contract (stx-transfer? marketplace-fee tx-sender (var-get fee-recipient))))
    
    ;; Remove offer
    (map-delete offers { token-id: token-id, offeror: offeror })
    
    ;; Remove any active listing
    (map-delete listings { token-id: token-id })
    
    ;; Record sale
    (map-set sales-history
      { sale-id: new-sale-id }
      {
        token-id: token-id,
        seller: tx-sender,
        buyer: offeror,
        price: amount,
        marketplace-fee: marketplace-fee,
        royalty-fee: u0,
        sold-at: block-height
      }
    )
    
    ;; Update statistics
    (update-user-stats tx-sender offeror amount)
    (var-set sale-id-nonce new-sale-id)
    (var-set total-volume (+ (var-get total-volume) amount))
    (var-set total-sales (+ (var-get total-sales) u1))
    
    (print {
      event: "offer-accepted",
      token-id: token-id,
      seller: tx-sender,
      buyer: offeror,
      amount: amount,
      sale-id: new-sale-id
    })
    
    (ok new-sale-id)
  )
)

;; Withdraw expired offer
(define-public (withdraw-offer (token-id uint))
  (let
    (
      (offer-info (unwrap! (map-get? offers { token-id: token-id, offeror: tx-sender }) ERR-NOT-FOUND))
      (amount (get amount offer-info))
    )
    ;; Can withdraw if expired or cancel anytime
    (asserts! (or (> block-height (get expires-at offer-info))
                  (is-eq tx-sender tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Return escrowed funds
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    ;; Remove offer
    (map-delete offers { token-id: token-id, offeror: tx-sender })
    
    (print {
      event: "offer-withdrawn",
      token-id: token-id,
      offeror: tx-sender,
      amount: amount
    })
    
    (ok true)
  )
)

;; Admin functions
(define-public (set-marketplace-fee (new-fee-bps uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fee-bps u1000) ERR-INVALID-PRICE) ;; Max 10%
    (var-set marketplace-fee-bps new-fee-bps)
    (ok true)
  )
)

(define-public (toggle-marketplace)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set marketplace-enabled (not (var-get marketplace-enabled)))
    (ok (var-get marketplace-enabled))
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

(define-read-only (get-listing (token-id uint))
  (map-get? listings { token-id: token-id })
)

(define-read-only (get-offer (token-id uint) (offeror principal))
  (map-get? offers { token-id: token-id, offeror: offeror })
)

(define-read-only (get-sale (sale-id uint))
  (map-get? sales-history { sale-id: sale-id })
)

(define-read-only (get-user-stats (user principal))
  (default-to
    { items-sold: u0, items-bought: u0, total-volume-sold: u0, total-volume-bought: u0 }
    (map-get? user-stats { user: user })
  )
)

(define-read-only (get-marketplace-stats)
  (ok {
    total-volume: (var-get total-volume),
    total-sales: (var-get total-sales),
    marketplace-fee-bps: (var-get marketplace-fee-bps),
    enabled: (var-get marketplace-enabled)
  })
)

(define-read-only (get-marketplace-fee-bps)
  (ok (var-get marketplace-fee-bps))
)

(define-read-only (is-marketplace-enabled)
  (ok (var-get marketplace-enabled))
)

;; Private functions

(define-private (update-user-stats (seller principal) (buyer principal) (amount uint))
  (let
    (
      (seller-stats (default-to 
        { items-sold: u0, items-bought: u0, total-volume-sold: u0, total-volume-bought: u0 }
        (map-get? user-stats { user: seller })
      ))
      (buyer-stats (default-to
        { items-sold: u0, items-bought: u0, total-volume-sold: u0, total-volume-bought: u0 }
        (map-get? user-stats { user: buyer })
      ))
    )
    ;; Update seller stats
    (map-set user-stats
      { user: seller }
      {
        items-sold: (+ (get items-sold seller-stats) u1),
        items-bought: (get items-bought seller-stats),
        total-volume-sold: (+ (get total-volume-sold seller-stats) amount),
        total-volume-bought: (get total-volume-bought seller-stats)
      }
    )
    
    ;; Update buyer stats
    (map-set user-stats
      { user: buyer }
      {
        items-sold: (get items-sold buyer-stats),
        items-bought: (+ (get items-bought buyer-stats) u1),
        total-volume-sold: (get total-volume-sold buyer-stats),
        total-volume-bought: (+ (get total-volume-bought buyer-stats) amount)
      }
    )
    true
  )
)

;; Contract initialization
(begin
  (print "Digital Art Marketplace Contract Deployed")
  (print { contract-owner: CONTRACT-OWNER })
)

