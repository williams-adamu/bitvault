;; BitVault: Decentralized Digital Asset Registry
;;
;; A revolutionary content ownership protocol built on the Stacks blockchain,
;; leveraging Bitcoin's security to create an immutable registry of digital assets.
;; BitVault enables creators to establish verifiable ownership of their digital
;; content through cryptographic proof, fostering a trustless ecosystem for
;; intellectual property management.
;;
;; Key Features:
;; - Immutable ownership records anchored to Bitcoin
;; - Content authenticity verification through cryptographic hashing
;; - Seamless ownership transfers with automatic provenance tracking
;; - Gas-efficient batch operations for content creators

;; PROTOCOL CONSTANTS & ERROR DEFINITIONS

;; Protocol administrator (deployer receives initial control)
(define-constant PROTOCOL_ADMIN tx-sender)

;; Input validation constants
(define-constant MAX_ASSET_ID u999999999) ;; Maximum allowed asset ID
(define-constant MIN_TITLE_LENGTH u1)
(define-constant MAX_TITLE_LENGTH u256)
(define-constant MIN_DESCRIPTION_LENGTH u0)
(define-constant MAX_DESCRIPTION_LENGTH u1024)

;; Comprehensive error handling system
(define-constant ERR_UNAUTHORIZED_ACCESS (err u1001))
(define-constant ERR_ASSET_NOT_FOUND (err u1002))
(define-constant ERR_DUPLICATE_ASSET_HASH (err u1003))
(define-constant ERR_INVALID_PARAMETERS (err u1004))
(define-constant ERR_OWNERSHIP_TRANSFER_FAILED (err u1005))
(define-constant ERR_ASSET_DEACTIVATED (err u1006))
(define-constant ERR_INVALID_ASSET_ID (err u1007))
(define-constant ERR_INVALID_STRING_LENGTH (err u1008))

;; STATE VARIABLES

;; Global asset counter - tracks the next available asset ID
(define-data-var global-asset-counter uint u1)

;; Protocol statistics
(define-data-var total-registered-assets uint u0)
(define-data-var total-ownership-transfers uint u0)

;; CORE DATA STRUCTURES

;; Primary asset registry - maps asset IDs to comprehensive metadata
(define-map digital-asset-registry
  { asset-id: uint }
  {
    owner: principal, ;; Current owner of the digital asset
    asset-title: (string-ascii 256), ;; Human-readable asset title
    asset-description: (string-ascii 1024), ;; Detailed asset description
    content-fingerprint: (buff 32), ;; SHA-256 hash of the content
    media-type: (string-ascii 64), ;; MIME type or content category
    registration-block: uint, ;; Block height when asset was registered
    last-modified-block: uint, ;; Block height of last update
    status: bool, ;; Asset active status (true = active)
  }
)

;; Hash-to-ID mapping for efficient content lookup and duplicate prevention
(define-map fingerprint-to-asset
  { content-fingerprint: (buff 32) }
  { asset-id: uint }
)

;; Creator portfolio tracking - enables efficient portfolio queries
(define-map creator-portfolio
  { creator: principal }
  {
    total-assets: uint, ;; Number of assets owned by creator
    first-registration-block: uint, ;; Block height of first asset registration
  }
)

;; VALIDATION HELPER FUNCTIONS

;; Validates asset ID is within acceptable range
(define-private (validate-asset-id (asset-id uint))
  (and (> asset-id u0) (<= asset-id MAX_ASSET_ID))
)

;; Validates string length is within bounds
(define-private (validate-string-length
    (str (string-ascii 1024))
    (min-len uint)
    (max-len uint)
  )
  (let ((str-len (len str)))
    (and (>= str-len min-len) (<= str-len max-len))
  )
)

;; Validates title string
(define-private (validate-title (title (string-ascii 256)))
  (validate-string-length title MIN_TITLE_LENGTH MAX_TITLE_LENGTH)
)

;; Validates description string
(define-private (validate-description (description (string-ascii 1024)))
  (validate-string-length description MIN_DESCRIPTION_LENGTH
    MAX_DESCRIPTION_LENGTH
  )
)

;; Sanitizes and validates asset description with explicit bounds checking
(define-private (sanitize-description (raw-description (string-ascii 1024)))
  (let ((desc-len (len raw-description)))
    (if (and (>= desc-len MIN_DESCRIPTION_LENGTH) (<= desc-len MAX_DESCRIPTION_LENGTH))
      (ok raw-description)
      ERR_INVALID_STRING_LENGTH
    )
  )
)

;; CORE PROTOCOL FUNCTIONS

;; Registers a new digital asset on the BitVault protocol
(define-public (register-digital-asset
    (asset-title (string-ascii 256))
    (asset-description (string-ascii 1024))
    (content-fingerprint (buff 32))
    (media-type (string-ascii 64))
  )
  (let (
      (new-asset-id (var-get global-asset-counter))
      (current-block stacks-block-height)
      (existing-fingerprint (map-get? fingerprint-to-asset { content-fingerprint: content-fingerprint }))
      (creator-stats (map-get? creator-portfolio { creator: tx-sender }))
      (desc-len (len asset-description))
    )
    ;; Input validation - ensure data integrity
    (asserts! (validate-title asset-title) ERR_INVALID_PARAMETERS)
    (asserts!
      (and (>= desc-len MIN_DESCRIPTION_LENGTH) (<= desc-len MAX_DESCRIPTION_LENGTH))
      ERR_INVALID_STRING_LENGTH
    )
    (asserts! (> (len content-fingerprint) u0) ERR_INVALID_PARAMETERS)
    (asserts! (> (len media-type) u0) ERR_INVALID_PARAMETERS)
    (asserts! (validate-asset-id new-asset-id) ERR_INVALID_ASSET_ID)

    ;; Prevent duplicate content registration
    (asserts! (is-none existing-fingerprint) ERR_DUPLICATE_ASSET_HASH)

    ;; Create immutable asset record with validated data
    (map-set digital-asset-registry { asset-id: new-asset-id } {
      owner: tx-sender,
      asset-title: asset-title,
      asset-description: asset-description,
      content-fingerprint: content-fingerprint,
      media-type: media-type,
      registration-block: current-block,
      last-modified-block: current-block,
      status: true,
    })

    ;; Establish fingerprint-to-ID mapping for O(1) lookups
    (map-set fingerprint-to-asset { content-fingerprint: content-fingerprint } { asset-id: new-asset-id })

    ;; Update creator portfolio statistics
    (match creator-stats
      existing-stats
      ;; Update existing creator record
      (map-set creator-portfolio { creator: tx-sender } {
        total-assets: (+ (get total-assets existing-stats) u1),
        first-registration-block: (get first-registration-block existing-stats),
      })
      ;; Initialize new creator record
      (map-set creator-portfolio { creator: tx-sender } {
        total-assets: u1,
        first-registration-block: current-block,
      })
    )

    ;; Update global protocol statistics
    (var-set global-asset-counter (+ new-asset-id u1))
    (var-set total-registered-assets (+ (var-get total-registered-assets) u1))

    ;; Return the newly assigned asset ID
    (ok new-asset-id)
  )
)

;; Transfers ownership of a digital asset to a new principal
(define-public (transfer-asset-ownership
    (asset-id uint)
    (new-owner principal)
  )
  (let (
      (asset-record (unwrap! (map-get? digital-asset-registry { asset-id: asset-id })
        ERR_ASSET_NOT_FOUND
      ))
      (current-owner (get owner asset-record))
      (current-block stacks-block-height)
    )
    ;; Input validation
    (asserts! (validate-asset-id asset-id) ERR_INVALID_ASSET_ID)
    ;; Ownership verification - only current owner can transfer
    (asserts! (is-eq tx-sender current-owner) ERR_UNAUTHORIZED_ACCESS)
    ;; Prevent self-transfers (optimization)
    (asserts! (not (is-eq current-owner new-owner)) ERR_INVALID_PARAMETERS)
    ;; Ensure asset is active
    (asserts! (get status asset-record) ERR_ASSET_DEACTIVATED)

    ;; Execute ownership transfer
    (map-set digital-asset-registry { asset-id: asset-id }
      (merge asset-record {
        owner: new-owner,
        last-modified-block: current-block,
      })
    )

    ;; Update portfolio statistics for both parties
    (let (
        (old-owner-stats (unwrap-panic (map-get? creator-portfolio { creator: current-owner })))
        (new-owner-stats (map-get? creator-portfolio { creator: new-owner }))
      )
      ;; Decrement previous owner's asset count
      (map-set creator-portfolio { creator: current-owner }
        (merge old-owner-stats { total-assets: (- (get total-assets old-owner-stats) u1) })
      )

      ;; Update new owner's portfolio
      (match new-owner-stats
        existing-stats
        ;; Increment existing owner's count
        (map-set creator-portfolio { creator: new-owner }
          (merge existing-stats { total-assets: (+ (get total-assets existing-stats) u1) })
        )
        ;; Initialize new owner's portfolio
        (map-set creator-portfolio { creator: new-owner } {
          total-assets: u1,
          first-registration-block: current-block,
        })
      )
    )

    ;; Track global transfer statistics
    (var-set total-ownership-transfers (+ (var-get total-ownership-transfers) u1))

    (ok true)
  )
)

;; Updates metadata for an existing digital asset
(define-public (update-asset-metadata
    (asset-id uint)
    (asset-title (string-ascii 256))
    (asset-description (string-ascii 1024))
  )
  (let (
      (asset-record (unwrap! (map-get? digital-asset-registry { asset-id: asset-id })
        ERR_ASSET_NOT_FOUND
      ))
      (desc-len (len asset-description))
    )
    ;; Input validation
    (asserts! (validate-asset-id asset-id) ERR_INVALID_ASSET_ID)
    (asserts! (validate-title asset-title) ERR_INVALID_PARAMETERS)
    (asserts!
      (and (>= desc-len MIN_DESCRIPTION_LENGTH) (<= desc-len MAX_DESCRIPTION_LENGTH))
      ERR_INVALID_STRING_LENGTH
    )
    ;; Ownership verification
    (asserts! (is-eq tx-sender (get owner asset-record)) ERR_UNAUTHORIZED_ACCESS)
    ;; Ensure asset is active
    (asserts! (get status asset-record) ERR_ASSET_DEACTIVATED)

    ;; Execute metadata update with validated data
    (map-set digital-asset-registry { asset-id: asset-id }
      (merge asset-record {
        asset-title: asset-title,
        asset-description: asset-description,
        last-modified-block: stacks-block-height,
      })
    )

    (ok true)
  )
)

;; Deactivates a digital asset (soft delete for provenance preservation)
(define-public (archive-digital-asset (asset-id uint))
  (let ((asset-record (unwrap! (map-get? digital-asset-registry { asset-id: asset-id })
      ERR_ASSET_NOT_FOUND
    )))
    ;; Input validation
    (asserts! (validate-asset-id asset-id) ERR_INVALID_ASSET_ID)
    ;; Ownership verification
    (asserts! (is-eq tx-sender (get owner asset-record)) ERR_UNAUTHORIZED_ACCESS)
    ;; Prevent double-deactivation
    (asserts! (get status asset-record) ERR_ASSET_DEACTIVATED)

    ;; Archive the asset (preserves historical record)
    (map-set digital-asset-registry { asset-id: asset-id }
      (merge asset-record {
        status: false,
        last-modified-block: stacks-block-height,
      })
    )

    (ok true)
  )
)

;; QUERY INTERFACE (READ-ONLY FUNCTIONS)

;; Retrieves complete asset information by ID
(define-read-only (fetch-asset-details (asset-id uint))
  (if (validate-asset-id asset-id)
    (map-get? digital-asset-registry { asset-id: asset-id })
    none
  )
)

;; Locates asset by its content fingerprint
(define-read-only (find-asset-by-fingerprint (content-fingerprint (buff 32)))
  (match (map-get? fingerprint-to-asset { content-fingerprint: content-fingerprint })
    fingerprint-record (let ((asset-id (get asset-id fingerprint-record)))
      (if (validate-asset-id asset-id)
        (map-get? digital-asset-registry { asset-id: asset-id })
        none
      )
    )
    none
  )
)

;; Verifies ownership of a specific digital asset
(define-read-only (validate-asset-ownership
    (asset-id uint)
    (claimed-owner principal)
  )
  (if (validate-asset-id asset-id)
    (match (map-get? digital-asset-registry { asset-id: asset-id })
      asset-record (is-eq (get owner asset-record) claimed-owner)
      false
    )
    false
  )
)

;; Retrieves creator's portfolio statistics
(define-read-only (get-creator-asset-count (creator principal))
  (default-to u0
    (get total-assets (map-get? creator-portfolio { creator: creator }))
  )
)

;; Checks if an asset exists and is currently active
(define-read-only (is-asset-operational (asset-id uint))
  (if (validate-asset-id asset-id)
    (match (map-get? digital-asset-registry { asset-id: asset-id })
      asset-record (get status asset-record)
      false
    )
    false
  )
)

;; Returns the next asset ID that will be assigned
(define-read-only (peek-next-asset-id)
  (var-get global-asset-counter)
)

;; Validates uniqueness of a content fingerprint
(define-read-only (verify-fingerprint-uniqueness (content-fingerprint (buff 32)))
  (is-none (map-get? fingerprint-to-asset { content-fingerprint: content-fingerprint }))
)

;; PROTOCOL ANALYTICS & METRICS

;; Returns comprehensive protocol statistics
(define-read-only (get-protocol-metrics)
  {
    total-assets-registered: (var-get total-registered-assets),
    total-ownership-transfers: (var-get total-ownership-transfers),
    next-asset-id: (var-get global-asset-counter),
  }
)

;; Retrieves creator's registration history
(define-read-only (get-creator-profile (creator principal))
  (map-get? creator-portfolio { creator: creator })
)

;; UTILITY FUNCTIONS

;; Checks if a principal is the protocol administrator
(define-read-only (is-protocol-admin (principal-address principal))
  (is-eq principal-address PROTOCOL_ADMIN)
)

;; Validates asset existence without revealing details
(define-read-only (asset-exists (asset-id uint))
  (if (validate-asset-id asset-id)
    (is-some (map-get? digital-asset-registry { asset-id: asset-id }))
    false
  )
)
