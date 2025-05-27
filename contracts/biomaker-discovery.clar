;; Biomarker Discovery Contract
;; Manages aging-related biomarker discoveries and peer review

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-discovery-exists (err u201))
(define-constant err-discovery-not-found (err u202))
(define-constant err-invalid-status (err u203))
(define-constant err-not-authorized (err u204))
(define-constant err-already-reviewed (err u205))

;; Data Variables
(define-data-var next-discovery-id uint u1)
(define-data-var reward-pool uint u1000000)

;; Discovery Status Constants
(define-constant status-submitted u1)
(define-constant status-peer-review u2)
(define-constant status-validated u3)
(define-constant status-rejected u4)

;; Data Maps
(define-map discoveries
  { discovery-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    discoverer: principal,
    institution-id: uint,
    status: uint,
    reward-amount: uint,
    peer-reviews: uint,
    positive-reviews: uint,
    created-at: uint,
    validated-at: (optional uint)
  }
)

(define-map peer-reviews
  { discovery-id: uint, reviewer: principal }
  {
    approved: bool,
    review-date: uint,
    comments: (string-ascii 300)
  }
)

(define-map reviewer-permissions
  { reviewer: principal }
  { authorized: bool }
)

;; Public Functions

;; Submit a new biomarker discovery
(define-public (submit-discovery
    (name (string-ascii 100))
    (description (string-ascii 500))
    (institution-id uint)
    (reward-amount uint))
  (let
    (
      (discovery-id (var-get next-discovery-id))
      (caller tx-sender)
    )
    (asserts! (> reward-amount u0) err-invalid-status)

    (map-set discoveries
      { discovery-id: discovery-id }
      {
        name: name,
        description: description,
        discoverer: caller,
        institution-id: institution-id,
        status: status-submitted,
        reward-amount: reward-amount,
        peer-reviews: u0,
        positive-reviews: u0,
        created-at: block-height,
        validated-at: none
      }
    )

    (var-set next-discovery-id (+ discovery-id u1))
    (ok discovery-id)
  )
)

;; Submit peer review
(define-public (submit-peer-review
    (discovery-id uint)
    (approved bool)
    (comments (string-ascii 300)))
  (let
    (
      (caller tx-sender)
      (discovery (unwrap! (map-get? discoveries { discovery-id: discovery-id }) err-discovery-not-found))
    )
    (asserts! (is-authorized-reviewer caller) err-not-authorized)
    (asserts! (is-none (map-get? peer-reviews { discovery-id: discovery-id, reviewer: caller })) err-already-reviewed)

    (map-set peer-reviews
      { discovery-id: discovery-id, reviewer: caller }
      {
        approved: approved,
        review-date: block-height,
        comments: comments
      }
    )

    (let
      (
        (new-review-count (+ (get peer-reviews discovery) u1))
        (new-positive-count (+ (get positive-reviews discovery) (if approved u1 u0)))
      )
      (map-set discoveries
        { discovery-id: discovery-id }
        (merge discovery
          {
            peer-reviews: new-review-count,
            positive-reviews: new-positive-count,
            status: (if (>= new-review-count u3) status-peer-review (get status discovery))
          }
        )
      )
    )
    (ok true)
  )
)

;; Validate discovery (after sufficient peer reviews)
(define-public (validate-discovery (discovery-id uint))
  (let
    (
      (discovery (unwrap! (map-get? discoveries { discovery-id: discovery-id }) err-discovery-not-found))
      (caller tx-sender)
    )
    (asserts! (is-authorized-reviewer caller) err-not-authorized)
    (asserts! (>= (get peer-reviews discovery) u3) err-invalid-status)
    (asserts! (>= (get positive-reviews discovery) u2) err-invalid-status)

    (map-set discoveries
      { discovery-id: discovery-id }
      (merge discovery
        {
          status: status-validated,
          validated-at: (some block-height)
        }
      )
    )
    (ok true)
  )
)

;; Reject discovery
(define-public (reject-discovery (discovery-id uint))
  (let
    (
      (discovery (unwrap! (map-get? discoveries { discovery-id: discovery-id }) err-discovery-not-found))
      (caller tx-sender)
    )
    (asserts! (is-authorized-reviewer caller) err-not-authorized)

    (map-set discoveries
      { discovery-id: discovery-id }
      (merge discovery { status: status-rejected })
    )
    (ok true)
  )
)

;; Add authorized reviewer (owner only)
(define-public (add-reviewer (reviewer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set reviewer-permissions { reviewer: reviewer } { authorized: true })
    (ok true)
  )
)

;; Remove reviewer (owner only)
(define-public (remove-reviewer (reviewer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set reviewer-permissions { reviewer: reviewer } { authorized: false })
    (ok true)
  )
)

;; Read-only Functions

;; Get discovery details
(define-read-only (get-discovery (discovery-id uint))
  (map-get? discoveries { discovery-id: discovery-id })
)

;; Get peer review
(define-read-only (get-peer-review (discovery-id uint) (reviewer principal))
  (map-get? peer-reviews { discovery-id: discovery-id, reviewer: reviewer })
)

;; Check if reviewer is authorized
(define-read-only (is-authorized-reviewer (reviewer principal))
  (default-to false (get authorized (map-get? reviewer-permissions { reviewer: reviewer })))
)

;; Get next discovery ID
(define-read-only (get-next-discovery-id)
  (var-get next-discovery-id)
)

;; Get discovery status
(define-read-only (get-discovery-status (discovery-id uint))
  (match (map-get? discoveries { discovery-id: discovery-id })
    discovery (get status discovery)
    u0
  )
)

;; Check if discovery is validated
(define-read-only (is-discovery-validated (discovery-id uint))
  (match (map-get? discoveries { discovery-id: discovery-id })
    discovery (is-eq (get status discovery) status-validated)
    false
  )
)
