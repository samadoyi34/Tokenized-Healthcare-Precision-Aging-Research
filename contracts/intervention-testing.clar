;; Intervention Testing Contract
;; Manages anti-aging intervention trials and outcomes

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-trial-exists (err u301))
(define-constant err-trial-not-found (err u302))
(define-constant err-invalid-phase (err u303))
(define-constant err-not-authorized (err u304))
(define-constant err-trial-not-active (err u305))

;; Data Variables
(define-data-var next-trial-id uint u1)

;; Trial Phase Constants
(define-constant phase-preclinical u1)
(define-constant phase-i u2)
(define-constant phase-ii u3)
(define-constant phase-iii u4)
(define-constant phase-completed u5)
(define-constant phase-terminated u6)

;; Data Maps
(define-map trials
  { trial-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    principal-investigator: principal,
    institution-id: uint,
    phase: uint,
    participant-count: uint,
    duration-days: uint,
    start-date: uint,
    end-date: (optional uint),
    success-criteria: (string-ascii 300),
    status: uint,
    efficacy-score: uint,
    safety-score: uint
  }
)

(define-map trial-participants
  { trial-id: uint, participant: principal }
  {
    enrolled-date: uint,
    completion-status: bool,
    outcome-score: uint
  }
)

(define-map trial-outcomes
  { trial-id: uint }
  {
    primary-endpoint-met: bool,
    secondary-endpoints-met: uint,
    adverse-events: uint,
    dropout-rate: uint,
    statistical-significance: bool
  }
)

(define-map investigators
  { investigator: principal }
  { authorized: bool }
)

;; Public Functions

;; Start a new intervention trial
(define-public (start-trial
    (name (string-ascii 100))
    (description (string-ascii 500))
    (institution-id uint)
    (phase uint)
    (duration-days uint)
    (success-criteria (string-ascii 300)))
  (let
    (
      (trial-id (var-get next-trial-id))
      (caller tx-sender)
    )
    (asserts! (is-authorized-investigator caller) err-not-authorized)
    (asserts! (and (>= phase phase-preclinical) (<= phase phase-iii)) err-invalid-phase)

    (map-set trials
      { trial-id: trial-id }
      {
        name: name,
        description: description,
        principal-investigator: caller,
        institution-id: institution-id,
        phase: phase,
        participant-count: u0,
        duration-days: duration-days,
        start-date: block-height,
        end-date: none,
        success-criteria: success-criteria,
        status: u1,
        efficacy-score: u0,
        safety-score: u100
      }
    )

    (var-set next-trial-id (+ trial-id u1))
    (ok trial-id)
  )
)

;; Enroll participant in trial
(define-public (enroll-participant (trial-id uint))
  (let
    (
      (caller tx-sender)
      (trial (unwrap! (map-get? trials { trial-id: trial-id }) err-trial-not-found))
    )
    (asserts! (is-eq (get status trial) u1) err-trial-not-active)

    (map-set trial-participants
      { trial-id: trial-id, participant: caller }
      {
        enrolled-date: block-height,
        completion-status: false,
        outcome-score: u0
      }
    )

    (map-set trials
      { trial-id: trial-id }
      (merge trial { participant-count: (+ (get participant-count trial) u1) })
    )
    (ok true)
  )
)

;; Update participant outcome
(define-public (update-participant-outcome
    (trial-id uint)
    (participant principal)
    (outcome-score uint)
    (completed bool))
  (let
    (
      (caller tx-sender)
      (trial (unwrap! (map-get? trials { trial-id: trial-id }) err-trial-not-found))
      (participant-data (unwrap! (map-get? trial-participants { trial-id: trial-id, participant: participant }) err-trial-not-found))
    )
    (asserts! (is-eq caller (get principal-investigator trial)) err-not-authorized)

    (map-set trial-participants
      { trial-id: trial-id, participant: participant }
      (merge participant-data
        {
          outcome-score: outcome-score,
          completion-status: completed
        }
      )
    )
    (ok true)
  )
)

;; Complete trial and record outcomes
(define-public (complete-trial
    (trial-id uint)
    (primary-endpoint-met bool)
    (secondary-endpoints-met uint)
    (adverse-events uint)
    (dropout-rate uint)
    (statistical-significance bool))
  (let
    (
      (caller tx-sender)
      (trial (unwrap! (map-get? trials { trial-id: trial-id }) err-trial-not-found))
    )
    (asserts! (is-eq caller (get principal-investigator trial)) err-not-authorized)
    (asserts! (is-eq (get status trial) u1) err-trial-not-active)

    (map-set trials
      { trial-id: trial-id }
      (merge trial
        {
          status: phase-completed,
          end-date: (some block-height),
          efficacy-score: (if primary-endpoint-met u100 u0)
        }
      )
    )

    (map-set trial-outcomes
      { trial-id: trial-id }
      {
        primary-endpoint-met: primary-endpoint-met,
        secondary-endpoints-met: secondary-endpoints-met,
        adverse-events: adverse-events,
        dropout-rate: dropout-rate,
        statistical-significance: statistical-significance
      }
    )
    (ok true)
  )
)

;; Advance trial phase
(define-public (advance-trial-phase (trial-id uint))
  (let
    (
      (caller tx-sender)
      (trial (unwrap! (map-get? trials { trial-id: trial-id }) err-trial-not-found))
      (current-phase (get phase trial))
    )
    (asserts! (is-eq caller (get principal-investigator trial)) err-not-authorized)
    (asserts! (< current-phase phase-iii) err-invalid-phase)

    (map-set trials
      { trial-id: trial-id }
      (merge trial { phase: (+ current-phase u1) })
    )
    (ok true)
  )
)

;; Add authorized investigator (owner only)
(define-public (add-investigator (investigator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set investigators { investigator: investigator } { authorized: true })
    (ok true)
  )
)

;; Read-only Functions

;; Get trial details
(define-read-only (get-trial (trial-id uint))
  (map-get? trials { trial-id: trial-id })
)

;; Get trial outcomes
(define-read-only (get-trial-outcomes (trial-id uint))
  (map-get? trial-outcomes { trial-id: trial-id })
)

;; Get participant data
(define-read-only (get-participant-data (trial-id uint) (participant principal))
  (map-get? trial-participants { trial-id: trial-id, participant: participant })
)

;; Check if investigator is authorized
(define-read-only (is-authorized-investigator (investigator principal))
  (default-to false (get authorized (map-get? investigators { investigator: investigator })))
)

;; Get next trial ID
(define-read-only (get-next-trial-id)
  (var-get next-trial-id)
)

;; Check if trial is active
(define-read-only (is-trial-active (trial-id uint))
  (match (map-get? trials { trial-id: trial-id })
    trial (is-eq (get status trial) u1)
    false
  )
)
