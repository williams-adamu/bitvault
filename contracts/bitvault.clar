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