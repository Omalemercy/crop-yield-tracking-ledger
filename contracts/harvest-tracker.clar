;; harvest-tracker
;; A contract that manages the recording and verification of crop production data on the Stacks blockchain
;; This contract enables farmers to document their agricultural production from planting to harvest,
;; creating transparency in the food supply chain and providing verifiable production metrics.

;; ERROR CODES
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-FIELD-NOT-FOUND (err u101))
(define-constant ERR-FIELD-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-COORDINATES (err u103))
(define-constant ERR-PLANTING-NOT-FOUND (err u104))
(define-constant ERR-PLANTING-ALREADY-EXISTS (err u105))
(define-constant ERR-ESTIMATE-INVALID (err u106))
(define-constant ERR-HARVEST-ALREADY-RECORDED (err u107))
(define-constant ERR-VERIFIER-NOT-REGISTERED (err u108))
(define-constant ERR-ALREADY-VERIFIED (err u109))
(define-constant ERR-INVALID-YIELD-AMOUNT (err u110))

;; DATA STRUCTURES

;; Map of registered field IDs to field information
(define-map fields
  { id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    size: uint,  ;; in square meters
    latitude: int,  ;; multiplied by 10^6 for precision
    longitude: int, ;; multiplied by 10^6 for precision
    registration-date: uint
  }
)

;; Map of planting records for each field
(define-map plantings
  { field-id: uint, planting-id: uint }
  {
    crop-type: (string-ascii 50),
    variety: (string-ascii 50),
    planting-date: uint,
    expected-harvest-date: uint
  }
)

;; Map of yield estimates for each planting
(define-map yield-estimates
  { field-id: uint, planting-id: uint, estimate-id: uint }
  {
    date: uint,
    estimated-yield: uint,  ;; in kilograms
    notes: (string-ascii 200)
  }
)

;; Map of harvest records for each planting
(define-map harvests
  { field-id: uint, planting-id: uint }
  {
    harvest-date: uint,
    actual-yield: uint,  ;; in kilograms
    quality-notes: (string-ascii 200),
    verified: bool
  }
)

;; Map of authorized verifiers
(define-map verifiers
  { verifier: principal }
  {
    name: (string-ascii 50),
    organization: (string-ascii 50),
    verification-authority: (string-ascii 50)
  }
)

;; Counters for IDs
(define-data-var next-field-id uint u1)
(define-data-var next-planting-id-map (map uint uint) {})
(define-data-var next-estimate-id-map (map { field-id: uint, planting-id: uint } uint) {})

;; PRIVATE FUNCTIONS

;; Get the next field ID and increment counter
(define-private (get-and-increment-field-id)
  (let ((current-id (var-get next-field-id)))
    (var-set next-field-id (+ current-id u1))
    current-id
  )
)

;; Get the next planting ID for a field and increment counter
(define-private (get-and-increment-planting-id (field-id uint))
  (let (
    (current-id (default-to u1 (map-get? next-planting-id-map field-id)))
  )
    (map-set next-planting-id-map field-id (+ current-id u1))
    current-id
  )
)

;; Get the next estimate ID for a field/planting and increment counter
(define-private (get-and-increment-estimate-id (field-id uint) (planting-id uint))
  (let (
    (key { field-id: field-id, planting-id: planting-id })
    (current-id (default-to u1 (map-get? next-estimate-id-map key)))
  )
    (map-set next-estimate-id-map key (+ current-id u1))
    current-id
  )
)

;; Check if the sender is the field owner
(define-private (is-field-owner (field-id uint))
  (let ((field-info (map-get? fields { id: field-id })))
    (if (is-some field-info)
      (is-eq (get owner (unwrap-panic field-info)) tx-sender)
      false
    )
  )
)

;; Validate coordinates are within reasonable range
(define-private (are-coordinates-valid (latitude int) (longitude int))
  (and
    (and (>= latitude (* (- 90) (pow 10 6))) (<= latitude (* 90 (pow 10 6))))
    (and (>= longitude (* (- 180) (pow 10 6))) (<= longitude (* 180 (pow 10 6))))
  )
)

;; READ-ONLY FUNCTIONS

;; Get field information by ID
(define-read-only (get-field (field-id uint))
  (map-get? fields { id: field-id })
)

;; Get planting information
(define-read-only (get-planting (field-id uint) (planting-id uint))
  (map-get? plantings { field-id: field-id, planting-id: planting-id })
)

;; Get yield estimate
(define-read-only (get-yield-estimate (field-id uint) (planting-id uint) (estimate-id uint))
  (map-get? yield-estimates { field-id: field-id, planting-id: planting-id, estimate-id: estimate-id })
)

;; Get harvest information
(define-read-only (get-harvest (field-id uint) (planting-id uint))
  (map-get? harvests { field-id: field-id, planting-id: planting-id })
)

;; Check if a principal is a registered verifier
(define-read-only (is-verifier (address principal))
  (is-some (map-get? verifiers { verifier: address }))
)

;; Get verifier information
(define-read-only (get-verifier-info (address principal))
  (map-get? verifiers { verifier: address })
)

;; PUBLIC FUNCTIONS

;; Register a new field
(define-public (register-field 
    (name (string-ascii 50)) 
    (size uint)
    (latitude int)
    (longitude int)
  )
  (let ((field-id (get-and-increment-field-id)))
    ;; Validate coordinates
    (asserts! (are-coordinates-valid latitude longitude) ERR-INVALID-COORDINATES)
    
    ;; Add the field to the map
    (map-set fields
      { id: field-id }
      {
        owner: tx-sender,
        name: name,
        size: size,
        latitude: latitude,
        longitude: longitude,
        registration-date: block-height
      }
    )
    
    ;; Return success with the field ID
    (ok field-id)
  )
)

;; Transfer field ownership
(define-public (transfer-field-ownership (field-id uint) (new-owner principal))
  (let ((field-info (map-get? fields { id: field-id })))
    ;; Check that the field exists
    (asserts! (is-some field-info) ERR-FIELD-NOT-FOUND)
    
    ;; Check that sender is the current owner
    (asserts! (is-field-owner field-id) ERR-NOT-AUTHORIZED)
    
    ;; Update the field ownership
    (map-set fields
      { id: field-id }
      (merge (unwrap-panic field-info) { owner: new-owner })
    )
    
    (ok true)
  )
)

;; Record a new planting on a field
(define-public (record-planting
    (field-id uint)
    (crop-type (string-ascii 50))
    (variety (string-ascii 50))
    (planting-date uint)
    (expected-harvest-date uint)
  )
  (let (
    (field-info (map-get? fields { id: field-id }))
    (planting-id (get-and-increment-planting-id field-id))
  )
    ;; Check that the field exists
    (asserts! (is-some field-info) ERR-FIELD-NOT-FOUND)
    
    ;; Check that sender is the field owner
    (asserts! (is-field-owner field-id) ERR-NOT-AUTHORIZED)
    
    ;; Record the planting
    (map-set plantings
      { field-id: field-id, planting-id: planting-id }
      {
        crop-type: crop-type,
        variety: variety,
        planting-date: planting-date,
        expected-harvest-date: expected-harvest-date
      }
    )
    
    (ok planting-id)
  )
)

;; Record a yield estimate for a planting
(define-public (record-yield-estimate
    (field-id uint)
    (planting-id uint)
    (estimated-yield uint)
    (notes (string-ascii 200))
  )
  (let (
    (field-info (map-get? fields { id: field-id }))
    (planting-info (map-get? plantings { field-id: field-id, planting-id: planting-id }))
    (estimate-id (get-and-increment-estimate-id field-id planting-id))
  )
    ;; Check that the field exists
    (asserts! (is-some field-info) ERR-FIELD-NOT-FOUND)
    
    ;; Check that the planting exists
    (asserts! (is-some planting-info) ERR-PLANTING-NOT-FOUND)
    
    ;; Check that sender is the field owner
    (asserts! (is-field-owner field-id) ERR-NOT-AUTHORIZED)
    
    ;; Validate estimate amount is reasonable (simple non-zero check)
    (asserts! (> estimated-yield u0) ERR-INVALID-YIELD-AMOUNT)
    
    ;; Record the yield estimate
    (map-set yield-estimates
      { field-id: field-id, planting-id: planting-id, estimate-id: estimate-id }
      {
        date: block-height,
        estimated-yield: estimated-yield,
        notes: notes
      }
    )
    
    (ok estimate-id)
  )
)

;; Record final harvest for a planting
(define-public (record-harvest
    (field-id uint)
    (planting-id uint)
    (actual-yield uint)
    (quality-notes (string-ascii 200))
  )
  (let (
    (field-info (map-get? fields { id: field-id }))
    (planting-info (map-get? plantings { field-id: field-id, planting-id: planting-id }))
    (existing-harvest (map-get? harvests { field-id: field-id, planting-id: planting-id }))
  )
    ;; Check that the field exists
    (asserts! (is-some field-info) ERR-FIELD-NOT-FOUND)
    
    ;; Check that the planting exists
    (asserts! (is-some planting-info) ERR-PLANTING-NOT-FOUND)
    
    ;; Check that a harvest hasn't already been recorded
    (asserts! (is-none existing-harvest) ERR-HARVEST-ALREADY-RECORDED)
    
    ;; Check that sender is the field owner
    (asserts! (is-field-owner field-id) ERR-NOT-AUTHORIZED)
    
    ;; Validate harvest amount is reasonable (simple non-zero check)
    (asserts! (> actual-yield u0) ERR-INVALID-YIELD-AMOUNT)
    
    ;; Record the harvest
    (map-set harvests
      { field-id: field-id, planting-id: planting-id }
      {
        harvest-date: block-height,
        actual-yield: actual-yield,
        quality-notes: quality-notes,
        verified: false
      }
    )
    
    (ok true)
  )
)

;; Register as a verifier (in a real system, this might require approval from an admin)
(define-public (register-verifier 
    (name (string-ascii 50)) 
    (organization (string-ascii 50))
    (verification-authority (string-ascii 50))
  )
  (map-set verifiers
    { verifier: tx-sender }
    {
      name: name,
      organization: organization,
      verification-authority: verification-authority
    }
  )
  
  (ok true)
)

;; Verify a harvest (must be called by a registered verifier)
(define-public (verify-harvest (field-id uint) (planting-id uint))
  (let (
    (harvest-info (map-get? harvests { field-id: field-id, planting-id: planting-id }))
    (is-valid-verifier (is-verifier tx-sender))
  )
    ;; Check that the harvest exists
    (asserts! (is-some harvest-info) ERR-PLANTING-NOT-FOUND)
    
    ;; Check that the caller is a registered verifier
    (asserts! is-valid-verifier ERR-VERIFIER-NOT-REGISTERED)
    
    ;; Check that the harvest hasn't already been verified
    (asserts! (not (get verified (unwrap-panic harvest-info))) ERR-ALREADY-VERIFIED)
    
    ;; Update the harvest record with verification
    (map-set harvests
      { field-id: field-id, planting-id: planting-id }
      (merge (unwrap-panic harvest-info) { verified: true })
    )
    
    (ok true)
  )
)