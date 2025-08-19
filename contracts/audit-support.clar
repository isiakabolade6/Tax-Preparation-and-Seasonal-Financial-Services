;; Audit Support Contract
;; Manages IRS audit cases, representation, and resolution tracking

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-CASE-NOT-FOUND (err u501))
(define-constant ERR-CASE-EXISTS (err u502))
(define-constant ERR-INVALID-INPUT (err u503))
(define-constant ERR-INVALID-STATUS (err u504))
(define-constant ERR-CASE-CLOSED (err u505))

;; Case type constants
(define-constant CASE-CORRESPONDENCE u1)
(define-constant CASE-OFFICE-AUDIT u2)
(define-constant CASE-FIELD-AUDIT u3)
(define-constant CASE-APPEALS u4)
(define-constant CASE-COLLECTION u5)

;; Case status constants
(define-constant STATUS-OPEN u1)
(define-constant STATUS-IN-PROGRESS u2)
(define-constant STATUS-PENDING-RESPONSE u3)
(define-constant STATUS-RESOLVED u4)
(define-constant STATUS-CLOSED u5)

;; Resolution type constants
(define-constant RESOLUTION-NO-CHANGE u1)
(define-constant RESOLUTION-AGREED u2)
(define-constant RESOLUTION-PARTIALLY-AGREED u3)
(define-constant RESOLUTION-APPEALED u4)
(define-constant RESOLUTION-SETTLED u5)

;; Data structures
(define-map audit-cases
  { case-id: uint }
  {
    client-id: uint,
    preparer: principal,
    case-type: uint,
    tax-year: uint,
    irs-notice-hash: (string-ascii 64),
    case-status: uint,
    opened-date: uint,
    due-date: uint,
    closed-date: (optional uint),
    resolution-type: (optional uint),
    amount-disputed: uint,
    amount-resolved: uint,
    last-updated: uint
  }
)

(define-map case-communications
  { case-id: uint, communication-id: uint }
  {
    sender: principal,
    recipient-hash: (string-ascii 64),
    message-hash: (string-ascii 128),
    communication-type: (string-ascii 32),
    sent-date: uint,
    response-required: bool,
    response-due-date: (optional uint)
  }
)

(define-map case-documents
  { case-id: uint, document-id: uint }
  {
    document-hash: (string-ascii 64),
    document-type: (string-ascii 32),
    uploaded-by: principal,
    upload-date: uint,
    is-submitted-to-irs: bool,
    submission-date: (optional uint)
  }
)

(define-map representation-agreements
  { case-id: uint }
  {
    client: principal,
    preparer: principal,
    power-of-attorney-hash: (string-ascii 64),
    representation-scope: (string-ascii 128),
    fee-agreement: uint,
    signed-date: uint,
    is-active: bool
  }
)

(define-data-var next-case-id uint u1)
(define-data-var next-communication-id uint u1)
(define-data-var next-document-id uint u1)

;; Read-only functions
(define-read-only (get-audit-case (case-id uint))
  (map-get? audit-cases { case-id: case-id })
)

(define-read-only (get-case-communication (case-id uint) (communication-id uint))
  (map-get? case-communications { case-id: case-id, communication-id: communication-id })
)

(define-read-only (get-case-document (case-id uint) (document-id uint))
  (map-get? case-documents { case-id: case-id, document-id: document-id })
)

(define-read-only (get-representation-agreement (case-id uint))
  (map-get? representation-agreements { case-id: case-id })
)

(define-read-only (is-case-active (case-id uint))
  (let ((case-data (unwrap! (get-audit-case case-id) false)))
    (< (get case-status case-data) STATUS-CLOSED)
  )
)

(define-read-only (get-next-case-id)
  (var-get next-case-id)
)

;; Public functions
(define-public (create-audit-case
  (client-id uint)
  (case-type uint)
  (tax-year uint)
  (irs-notice-hash (string-ascii 64))
  (due-date uint)
  (amount-disputed uint))
  (let ((case-id (var-get next-case-id)))
    (asserts! (> client-id u0) ERR-INVALID-INPUT)
    (asserts! (<= case-type u5) ERR-INVALID-INPUT)
    (asserts! (> case-type u0) ERR-INVALID-INPUT)
    (asserts! (> tax-year u2000) ERR-INVALID-INPUT)
    (asserts! (< tax-year u2100) ERR-INVALID-INPUT)
    (asserts! (> (len irs-notice-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> due-date block-height) ERR-INVALID-INPUT)

    (map-set audit-cases
      { case-id: case-id }
      {
        client-id: client-id,
        preparer: tx-sender,
        case-type: case-type,
        tax-year: tax-year,
        irs-notice-hash: irs-notice-hash,
        case-status: STATUS-OPEN,
        opened-date: block-height,
        due-date: due-date,
        closed-date: none,
        resolution-type: none,
        amount-disputed: amount-disputed,
        amount-resolved: u0,
        last-updated: block-height
      }
    )

    (var-set next-case-id (+ case-id u1))
    (ok case-id)
  )
)

(define-public (update-case-status (case-id uint) (new-status uint))
  (let ((case-data (unwrap! (get-audit-case case-id) ERR-CASE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get preparer case-data)) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-status u5) ERR-INVALID-STATUS)
    (asserts! (> new-status u0) ERR-INVALID-STATUS)

    (map-set audit-cases
      { case-id: case-id }
      (merge case-data { case-status: new-status, last-updated: block-height })
    )
    (ok true)
  )
)

(define-public (add-case-communication
  (case-id uint)
  (recipient-hash (string-ascii 64))
  (message-hash (string-ascii 128))
  (communication-type (string-ascii 32))
  (response-required bool)
  (response-due-date (optional uint)))
  (let ((case-data (unwrap! (get-audit-case case-id) ERR-CASE-NOT-FOUND))
        (communication-id (var-get next-communication-id)))
    (asserts! (is-eq tx-sender (get preparer case-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-case-active case-id) ERR-CASE-CLOSED)
    (asserts! (> (len recipient-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> (len message-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> (len communication-type) u0) ERR-INVALID-INPUT)

    (map-set case-communications
      { case-id: case-id, communication-id: communication-id }
      {
        sender: tx-sender,
        recipient-hash: recipient-hash,
        message-hash: message-hash,
        communication-type: communication-type,
        sent-date: block-height,
        response-required: response-required,
        response-due-date: response-due-date
      }
    )

    (var-set next-communication-id (+ communication-id u1))
    (ok communication-id)
  )
)

(define-public (add-case-document
  (case-id uint)
  (document-hash (string-ascii 64))
  (document-type (string-ascii 32)))
  (let ((case-data (unwrap! (get-audit-case case-id) ERR-CASE-NOT-FOUND))
        (document-id (var-get next-document-id)))
    (asserts! (is-eq tx-sender (get preparer case-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-case-active case-id) ERR-CASE-CLOSED)
    (asserts! (> (len document-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> (len document-type) u0) ERR-INVALID-INPUT)

    (map-set case-documents
      { case-id: case-id, document-id: document-id }
      {
        document-hash: document-hash,
        document-type: document-type,
        uploaded-by: tx-sender,
        upload-date: block-height,
        is-submitted-to-irs: false,
        submission-date: none
      }
    )

    (var-set next-document-id (+ document-id u1))
    (ok document-id)
  )
)

(define-public (create-representation-agreement
  (case-id uint)
  (client principal)
  (power-of-attorney-hash (string-ascii 64))
  (representation-scope (string-ascii 128))
  (fee-agreement uint))
  (let ((case-data (unwrap! (get-audit-case case-id) ERR-CASE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get preparer case-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len power-of-attorney-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> (len representation-scope) u0) ERR-INVALID-INPUT)
    (asserts! (> fee-agreement u0) ERR-INVALID-INPUT)

    (map-set representation-agreements
      { case-id: case-id }
      {
        client: client,
        preparer: tx-sender,
        power-of-attorney-hash: power-of-attorney-hash,
        representation-scope: representation-scope,
        fee-agreement: fee-agreement,
        signed-date: block-height,
        is-active: true
      }
    )
    (ok true)
  )
)

(define-public (resolve-case
  (case-id uint)
  (resolution-type uint)
  (amount-resolved uint))
  (let ((case-data (unwrap! (get-audit-case case-id) ERR-CASE-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get preparer case-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-case-active case-id) ERR-CASE-CLOSED)
    (asserts! (<= resolution-type u5) ERR-INVALID-INPUT)
    (asserts! (> resolution-type u0) ERR-INVALID-INPUT)
    (asserts! (<= amount-resolved (get amount-disputed case-data)) ERR-INVALID-INPUT)

    (map-set audit-cases
      { case-id: case-id }
      (merge case-data {
        case-status: STATUS-RESOLVED,
        resolution-type: (some resolution-type),
        amount-resolved: amount-resolved,
        closed-date: (some block-height),
        last-updated: block-height
      })
    )
    (ok true)
  )
)

(define-public (submit-document-to-irs (case-id uint) (document-id uint))
  (let ((case-data (unwrap! (get-audit-case case-id) ERR-CASE-NOT-FOUND))
        (document (unwrap! (get-case-document case-id document-id) ERR-INVALID-INPUT)))
    (asserts! (is-eq tx-sender (get preparer case-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-case-active case-id) ERR-CASE-CLOSED)

    (map-set case-documents
      { case-id: case-id, document-id: document-id }
      (merge document {
        is-submitted-to-irs: true,
        submission-date: (some block-height)
      })
    )
    (ok true)
  )
)
