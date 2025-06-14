;; Education Provider Verification Contract
;; Manages registration, verification, and reputation of educational providers

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-insufficient-reputation (err u104))

;; Data Variables
(define-data-var next-provider-id uint u1)
(define-data-var min-reputation-score uint u50)

;; Data Maps
(define-map providers uint {
    name: (string-ascii 100),
    description: (string-ascii 500),
    website: (string-ascii 200),
    contact-email: (string-ascii 100),
    verification-status: (string-ascii 20),
    reputation-score: uint,
    registration-date: uint,
    last-updated: uint,
    credentials-issued: uint,
    verified-by: principal
})

(define-map provider-addresses principal uint)
(define-map verification-requests uint {
    provider-id: uint,
    requested-by: principal,
    request-date: uint,
    status: (string-ascii 20),
    notes: (string-ascii 500)
})

(define-map reputation-history uint (list 50 {
    date: uint,
    score-change: int,
    reason: (string-ascii 100),
    updated-by: principal
}))

;; Provider registration function
(define-public (register-provider
    (name (string-ascii 100))
    (description (string-ascii 500))
    (website (string-ascii 200))
    (contact-email (string-ascii 100)))
    (let ((provider-id (var-get next-provider-id))
          (current-block block-height))
        (asserts! (is-none (map-get? provider-addresses tx-sender)) err-already-exists)
        (map-set providers provider-id {
            name: name,
            description: description,
            website: website,
            contact-email: contact-email,
            verification-status: "pending",
            reputation-score: u0,
            registration-date: current-block,
            last-updated: current-block,
            credentials-issued: u0,
            verified-by: tx-sender
        })
        (map-set provider-addresses tx-sender provider-id)
        (var-set next-provider-id (+ provider-id u1))
        (ok provider-id)))

;; Verify provider (admin only)
(define-public (verify-provider (provider-id uint) (status (string-ascii 20)))
    (let ((provider (unwrap! (map-get? providers provider-id) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (or (is-eq status "verified")
                     (is-eq status "rejected")
                     (is-eq status "pending")) err-invalid-status)
        (map-set providers provider-id (merge provider {
            verification-status: status,
            last-updated: block-height,
            verified-by: tx-sender
        }))
        (ok true)))

;; Update provider information
(define-public (update-provider-info
    (provider-id uint)
    (name (string-ascii 100))
    (description (string-ascii 500))
    (website (string-ascii 200))
    (contact-email (string-ascii 100)))
    (let ((provider (unwrap! (map-get? providers provider-id) err-not-found))
          (caller-provider-id (unwrap! (map-get? provider-addresses tx-sender) err-not-found)))
        (asserts! (is-eq provider-id caller-provider-id) err-owner-only)
        (map-set providers provider-id (merge provider {
            name: name,
            description: description,
            website: website,
            contact-email: contact-email,
            last-updated: block-height
        }))
        (ok true)))

;; Update reputation score
(define-public (update-reputation (provider-id uint) (score-change int) (reason (string-ascii 100)))
    (let ((provider (unwrap! (map-get? providers provider-id) err-not-found))
          (current-score (get reputation-score provider))
          (new-score (if (> score-change 0)
                        (+ current-score (to-uint score-change))
                        (if (>= current-score (to-uint (- 0 score-change)))
                            (- current-score (to-uint (- 0 score-change)))
                            u0)))
          (history (default-to (list) (map-get? reputation-history provider-id))))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set providers provider-id (merge provider {
            reputation-score: new-score,
            last-updated: block-height
        }))
        (map-set reputation-history provider-id
            (unwrap! (as-max-len? (append history {
                date: block-height,
                score-change: score-change,
                reason: reason,
                updated-by: tx-sender
            }) u50) (err u999)))
        (ok new-score)))

;; Increment credentials issued count
(define-public (increment-credentials-issued (provider-id uint))
    (let ((provider (unwrap! (map-get? providers provider-id) err-not-found)))
        (map-set providers provider-id (merge provider {
            credentials-issued: (+ (get credentials-issued provider) u1),
            last-updated: block-height
        }))
        (ok true)))

;; Request verification
(define-public (request-verification (provider-id uint) (notes (string-ascii 500)))
    (let ((request-id (var-get next-provider-id)))
        (unwrap! (map-get? providers provider-id) err-not-found)
        (map-set verification-requests request-id {
            provider-id: provider-id,
            requested-by: tx-sender,
            request-date: block-height,
            status: "pending",
            notes: notes
        })
        (ok request-id)))

;; Read-only functions
(define-read-only (get-provider (provider-id uint))
    (map-get? providers provider-id))

(define-read-only (get-provider-by-address (address principal))
    (match (map-get? provider-addresses address)
        provider-id (map-get? providers provider-id)
        none))

(define-read-only (get-provider-reputation (provider-id uint))
    (match (map-get? providers provider-id)
        provider (some (get reputation-score provider))
        none))

(define-read-only (is-provider-verified (provider-id uint))
    (match (map-get? providers provider-id)
        provider (is-eq (get verification-status provider) "verified")
        false))

(define-read-only (get-reputation-history (provider-id uint))
    (map-get? reputation-history provider-id))

(define-read-only (get-verification-request (request-id uint))
    (map-get? verification-requests request-id))

(define-read-only (get-total-providers)
    (- (var-get next-provider-id) u1))

(define-read-only (get-min-reputation-score)
    (var-get min-reputation-score))

;; Admin functions
(define-public (set-min-reputation-score (score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set min-reputation-score score)
        (ok true)))

(define-public (process-verification-request (request-id uint) (status (string-ascii 20)))
    (let ((request (unwrap! (map-get? verification-requests request-id) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set verification-requests request-id (merge request {
            status: status
        }))
        (ok true)))
