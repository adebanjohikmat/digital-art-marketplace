
;; title: nft-minting
;; version: 1.0.0
;; summary: Digital Art NFT Minting Contract
;; description: Handles creation and management of digital art NFTs with metadata and royalty support

;; Define the NFT token
(define-non-fungible-token art-token uint)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TOKEN-EXISTS (err u101))
(define-constant ERR-TOKEN-NOT-FOUND (err u102))
(define-constant ERR-INVALID-ROYALTY (err u103))
(define-constant ERR-SUPPLY-LIMIT-REACHED (err u104))
(define-constant ERR-INVALID-METADATA (err u105))
(define-constant ERR-TRANSFER-FAILED (err u106))
(define-constant ERR-MINT-LIMIT-REACHED (err u107))
(define-constant ERR-INVALID-RECIPIENT (err u108))

(define-constant MAX-SUPPLY u10000)
(define-constant MAX-ROYALTY-BPS u1000) ;; 10%
(define-constant MAX-MINT-PER-USER u50)

;; Data variables
(define-data-var token-id-nonce uint u0)
(define-data-var base-uri (string-ascii 256) "https://api.digital-art-marketplace.com/metadata/")
(define-data-var contract-uri (string-ascii 256) "https://api.digital-art-marketplace.com/contract")
(define-data-var mint-price uint u1000000) ;; 1 STX in micro-STX
(define-data-var minting-enabled bool true)
(define-data-var total-supply uint u0)

;; Data maps
(define-map token-metadata
  { token-id: uint }
  {
    title: (string-ascii 64),
    description: (string-ascii 256),
    image-url: (string-ascii 256),
    creator: principal,
    royalty-bps: uint,
    created-at: uint,
    attributes: (string-ascii 512)
  }
)

(define-map user-mint-count
  { user: principal }
  { count: uint }
)

(define-map authorized-minters
  { minter: principal }
  { authorized: bool }
)

(define-map token-creators
  { token-id: uint }
  { creator: principal }
)

;; Public functions

;; Mint new NFT with metadata
(define-public (mint (recipient principal) (title (string-ascii 64)) (description (string-ascii 256)) 
                    (image-url (string-ascii 256)) (royalty-bps uint) (attributes (string-ascii 512)))
  (let
    (
      (new-token-id (+ (var-get token-id-nonce) u1))
      (current-supply (var-get total-supply))
      (user-count (default-to u0 (get count (map-get? user-mint-count { user: tx-sender }))))
    )
    ;; Validation checks
    (asserts! (var-get minting-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (< current-supply MAX-SUPPLY) ERR-SUPPLY-LIMIT-REACHED)
    (asserts! (<= royalty-bps MAX-ROYALTY-BPS) ERR-INVALID-ROYALTY)
    (asserts! (< user-count MAX-MINT-PER-USER) ERR-MINT-LIMIT-REACHED)
    (asserts! (> (len title) u0) ERR-INVALID-METADATA)
    (asserts! (> (len image-url) u0) ERR-INVALID-METADATA)
    (asserts! (not (is-eq recipient CONTRACT-OWNER)) ERR-INVALID-RECIPIENT)
    
    ;; Transfer mint price to contract owner
    (try! (stx-transfer? (var-get mint-price) tx-sender CONTRACT-OWNER))
    
    ;; Mint the NFT
    (try! (nft-mint? art-token new-token-id recipient))
    
    ;; Store metadata
    (map-set token-metadata
      { token-id: new-token-id }
      {
        title: title,
        description: description,
        image-url: image-url,
        creator: tx-sender,
        royalty-bps: royalty-bps,
        created-at: block-height,
        attributes: attributes
      }
    )
    
    ;; Store creator mapping
    (map-set token-creators
      { token-id: new-token-id }
      { creator: tx-sender }
    )
    
    ;; Update user mint count
    (map-set user-mint-count
      { user: tx-sender }
      { count: (+ user-count u1) }
    )
    
    ;; Update contract state
    (var-set token-id-nonce new-token-id)
    (var-set total-supply (+ current-supply u1))
    
    (print {
      event: "mint",
      token-id: new-token-id,
      recipient: recipient,
      creator: tx-sender,
      title: title
    })
    
    (ok new-token-id)
  )
)

;; Admin mint (free mint by authorized minters)
(define-public (admin-mint (recipient principal) (title (string-ascii 64)) (description (string-ascii 256))
                          (image-url (string-ascii 256)) (royalty-bps uint) (attributes (string-ascii 512)))
  (let
    (
      (new-token-id (+ (var-get token-id-nonce) u1))
      (current-supply (var-get total-supply))
    )
    ;; Check authorization
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) 
                  (default-to false (get authorized (map-get? authorized-minters { minter: tx-sender })))) 
              ERR-NOT-AUTHORIZED)
    
    ;; Validation checks
    (asserts! (< current-supply MAX-SUPPLY) ERR-SUPPLY-LIMIT-REACHED)
    (asserts! (<= royalty-bps MAX-ROYALTY-BPS) ERR-INVALID-ROYALTY)
    (asserts! (> (len title) u0) ERR-INVALID-METADATA)
    (asserts! (> (len image-url) u0) ERR-INVALID-METADATA)
    
    ;; Mint the NFT
    (try! (nft-mint? art-token new-token-id recipient))
    
    ;; Store metadata
    (map-set token-metadata
      { token-id: new-token-id }
      {
        title: title,
        description: description,
        image-url: image-url,
        creator: tx-sender,
        royalty-bps: royalty-bps,
        created-at: block-height,
        attributes: attributes
      }
    )
    
    ;; Store creator mapping
    (map-set token-creators
      { token-id: new-token-id }
      { creator: tx-sender }
    )
    
    ;; Update contract state
    (var-set token-id-nonce new-token-id)
    (var-set total-supply (+ current-supply u1))
    
    (print {
      event: "admin-mint",
      token-id: new-token-id,
      recipient: recipient,
      creator: tx-sender,
      title: title
    })
    
    (ok new-token-id)
  )
)

;; Transfer NFT
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (nft-transfer? art-token token-id sender recipient)
  )
)

;; Burn NFT (only owner can burn)
(define-public (burn (token-id uint))
  (let
    (
      (owner (unwrap! (nft-get-owner? art-token token-id) ERR-TOKEN-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender owner) ERR-NOT-AUTHORIZED)
    (nft-burn? art-token token-id owner)
  )
)

;; Admin functions
(define-public (set-base-uri (new-uri (string-ascii 256)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set base-uri new-uri)
    (ok true)
  )
)

(define-public (set-mint-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set mint-price new-price)
    (ok true)
  )
)

(define-public (toggle-minting)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set minting-enabled (not (var-get minting-enabled)))
    (ok (var-get minting-enabled))
  )
)

(define-public (authorize-minter (minter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-minters { minter: minter } { authorized: true })
    (ok true)
  )
)

(define-public (revoke-minter (minter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-delete authorized-minters { minter: minter })
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-token-metadata (token-id uint))
  (map-get? token-metadata { token-id: token-id })
)

(define-read-only (get-token-uri (token-id uint))
  (ok (some (concat (var-get base-uri) (uint-to-ascii token-id))))
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? art-token token-id))
)

(define-read-only (get-total-supply)
  (ok (var-get total-supply))
)

(define-read-only (get-max-supply)
  (ok MAX-SUPPLY)
)

(define-read-only (get-mint-price)
  (ok (var-get mint-price))
)

(define-read-only (get-base-uri)
  (ok (var-get base-uri))
)

(define-read-only (is-minting-enabled)
  (ok (var-get minting-enabled))
)

(define-read-only (get-user-mint-count (user principal))
  (ok (default-to u0 (get count (map-get? user-mint-count { user: user }))))
)

(define-read-only (is-authorized-minter (minter principal))
  (ok (default-to false (get authorized (map-get? authorized-minters { minter: minter }))))
)

(define-read-only (get-token-creator (token-id uint))
  (ok (get creator (map-get? token-creators { token-id: token-id })))
)

;; Private functions

(define-private (uint-to-ascii (value uint))
  (if (<= value u9)
    (unwrap-panic (element-at "0123456789" value))
    "token" ;; Simple fallback for larger numbers
  )
)

;; Contract initialization
(begin
  (print "Digital Art NFT Minting Contract Deployed")
  (print { contract-owner: CONTRACT-OWNER })
)

