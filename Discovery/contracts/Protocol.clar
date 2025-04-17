;; Crypto Signal Discovery Protocol - Version 1
;; Basic implementation with core functionality

;; Constants
(define-constant ERR-NOT-PROTOCOL-ADMIN (err u1))
(define-constant ERR-PROTOCOL-NOT-ACTIVE (err u2))
(define-constant ERR-INVALID-OPPORTUNITY (err u3))
(define-constant ERR-ALREADY-VALIDATED (err u4))
(define-constant ERR-INCORRECT-VERIFICATION-KEY (err u5))

;; Data Variables
(define-data-var protocol-admin principal tx-sender)
(define-data-var protocol-active bool false)
(define-data-var membership-cost uint u1000000) ;; 1 STX

;; Opportunity Structure
(define-map market-opportunities
    uint
    {
        insight: (string-utf8 256),
        verification-key: (buff 32),
        reward-amount: uint,
        validated: bool
    }
)

;; Analyst Performance Tracking
(define-map analyst-metrics
    principal
    {
        current-opportunity: uint,
        total-validated: uint
    }
)

;; Authorization
(define-private (is-admin)
    (is-eq tx-sender (var-get protocol-admin)))

;; Protocol Management Functions
(define-public (activate-protocol)
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        (var-set protocol-active true)
        (ok true)))

(define-public (add-opportunity
    (opportunity-id uint)
    (insight (string-utf8 256))
    (verification-key (buff 32))
    (reward-amount uint))
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        
        ;; Validate parameters
        (asserts! (> (len verification-key) u0) (err u100))
        (asserts! (> (len insight) u0) (err u101))
        (asserts! (> reward-amount u0) (err u102))
        
        ;; Set the opportunity data
        (map-set market-opportunities opportunity-id
            {
                insight: insight,
                verification-key: verification-key,
                reward-amount: reward-amount,
                validated: false
            })
        (ok true)))

;; Analyst Onboarding
(define-public (join-protocol)
    (begin
        (asserts! (var-get protocol-active) ERR-PROTOCOL-NOT-ACTIVE)
        ;; Require membership cost
        (try! (stx-transfer? (var-get membership-cost) tx-sender (var-get protocol-admin)))
        
        (map-set analyst-metrics tx-sender
            {
                current-opportunity: u0,
                total-validated: u0
            })
        (ok true)))

;; Opportunity Validation Functions
(define-public (validate-opportunity
    (opportunity-id uint)
    (verification-proof (buff 32)))
    (let (
        (opportunity (unwrap! (map-get? market-opportunities opportunity-id) ERR-INVALID-OPPORTUNITY))
        (analyst (unwrap! (map-get? analyst-metrics tx-sender) ERR-INVALID-OPPORTUNITY))
        )
        ;; Check opportunity availability
        (asserts! (var-get protocol-active) ERR-PROTOCOL-NOT-ACTIVE)
        (asserts! (not (get validated opportunity)) ERR-ALREADY-VALIDATED)
        
        ;; Verify proof - directly compare the keys
        (if (is-eq verification-proof (get verification-key opportunity))
            (begin
                ;; Update opportunity status
                (map-set market-opportunities opportunity-id
                    (merge opportunity {validated: true}))
                
                ;; Update analyst metrics
                (map-set analyst-metrics tx-sender
                    (merge analyst {
                        current-opportunity: (+ opportunity-id u1),
                        total-validated: (+ (get total-validated analyst) u1)
                    }))
                
                ;; Distribute reward
                (try! (stx-transfer? (get reward-amount opportunity) (var-get protocol-admin) tx-sender))
                
                (ok true))
            ERR-INCORRECT-VERIFICATION-KEY)))

;; Read-only functions
(define-read-only (get-opportunity-insight (opportunity-id uint))
    (match (map-get? market-opportunities opportunity-id)
        opportunity (ok (get insight opportunity))
        ERR-INVALID-OPPORTUNITY))

(define-read-only (get-analyst-status (analyst principal))
    (map-get? analyst-metrics analyst))

(define-read-only (get-protocol-status)
    (var-get protocol-active))