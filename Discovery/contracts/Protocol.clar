;; Crypto Signal Discovery Protocol - Version 2
;; Enhanced implementation with security controls and more features

;; Constants
(define-constant ERR-NOT-PROTOCOL-ADMIN (err u1))
(define-constant ERR-PROTOCOL-NOT-ACTIVE (err u2))
(define-constant ERR-INVALID-OPPORTUNITY (err u3))
(define-constant ERR-ALREADY-VALIDATED (err u4))
(define-constant ERR-INCORRECT-VERIFICATION-KEY (err u5))
(define-constant ERR-COOLING-PERIOD-ACTIVE (err u6))
(define-constant ERR-INSUFFICIENT-FUNDS (err u7))
(define-constant ERR-INVALID-PARAMETER (err u8))
(define-constant ERR-OPPORTUNITY-EXISTS (err u9))
(define-constant MAX-OPPORTUNITY-ID u100) ;; Maximum allowed opportunity ID

;; Data Variables
(define-data-var protocol-admin principal tx-sender)
(define-data-var protocol-active bool false)
(define-data-var current-epoch uint u0)
(define-data-var membership-cost uint u1000000) ;; 1 STX
(define-data-var total-rewards-pool uint u0)
(define-data-var current-network-height uint u0) ;; Block height tracking for cooling periods

;; Opportunity Structure
(define-map market-opportunities
    uint
    {
        insight: (string-utf8 256),
        verification-key: (buff 32),
        cooling-end: uint,           ;; Cooling period end block height
        reward-amount: uint,
        validated: bool
    }
)

;; Analyst Performance Tracking
(define-map analyst-metrics
    principal
    {
        current-opportunity: uint,
        validated-opportunities: (list 10 uint),
        last-action: uint,
        total-validated: uint
    }
)

;; Opportunity Validations
(define-map opportunity-validations
    {opportunity: uint, analyst: principal}
    {
        verification-attempts: uint,
        validated-at: (optional uint)
    }
)

;; Authorization
(define-private (is-admin)
    (is-eq tx-sender (var-get protocol-admin)))

;; Block Height Management
(define-public (update-network-height (new-height uint))
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        (asserts! (>= new-height (var-get current-network-height)) ERR-INVALID-PARAMETER)
        (var-set current-network-height new-height)
        (ok true)))

;; Protocol Management Functions
(define-public (activate-protocol)
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        (var-set protocol-active true)
        (var-set current-epoch u0)
        (var-set total-rewards-pool u0)
        (ok true)))

(define-public (add-opportunity
    (opportunity-id uint)
    (insight (string-utf8 256))
    (verification-key (buff 32))
    (cooling-end uint)
    (reward-amount uint))
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        
        ;; Validate opportunity-id is within acceptable range
        (asserts! (<= opportunity-id MAX-OPPORTUNITY-ID) ERR-INVALID-PARAMETER)
        
        ;; Check if opportunity already exists to prevent overwriting
        (asserts! (is-none (map-get? market-opportunities opportunity-id)) ERR-OPPORTUNITY-EXISTS)
        
        ;; Validate cooling end is in the future
        (asserts! (>= cooling-end (var-get current-network-height)) ERR-INVALID-PARAMETER)
        
        ;; Validate verification key is not empty
        (asserts! (> (len verification-key) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate insight is not empty
        (asserts! (> (len insight) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate reward amount is a positive amount
        (asserts! (> reward-amount u0) ERR-INVALID-PARAMETER)
        
        ;; Set the opportunity data
        (map-set market-opportunities opportunity-id
            {
                insight: insight,
                verification-key: verification-key,
                cooling-end: cooling-end,
                reward-amount: reward-amount,
                validated: false
            })
            
        ;; Calculate new rewards pool safely
        (let ((new-pool (+ (var-get total-rewards-pool) reward-amount)))
            ;; Make sure the addition doesn't overflow
            (asserts! (>= new-pool (var-get total-rewards-pool)) ERR-INVALID-PARAMETER)
            ;; Update the total rewards pool
            (var-set total-rewards-pool new-pool))
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
                validated-opportunities: (list),
                last-action: (var-get current-network-height),
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
        (current-height (var-get current-network-height))
        )
        ;; Check opportunity availability
        (asserts! (var-get protocol-active) ERR-PROTOCOL-NOT-ACTIVE)
        (asserts! (>= current-height (get cooling-end opportunity)) ERR-COOLING-PERIOD-ACTIVE)
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
                        validated-opportunities: (unwrap! (as-max-len? 
                            (append (get validated-opportunities analyst) opportunity-id) u10)
                            ERR-INVALID-PARAMETER),
                        last-action: current-height,
                        total-validated: (+ (get total-validated analyst) u1)
                    }))
                
                ;; Record validation
                (map-set opportunity-validations
                    {opportunity: opportunity-id, analyst: tx-sender}
                    {
                        verification-attempts: u1,
                        validated-at: (some current-height)
                    })
                
                ;; Distribute reward
                (try! (stx-transfer? (get reward-amount opportunity) (var-get protocol-admin) tx-sender))
                
                (ok true))
            ERR-INCORRECT-VERIFICATION-KEY)))

;; Read-only functions
(define-read-only (get-opportunity-insight (opportunity-id uint))
    (match (map-get? market-opportunities opportunity-id)
        opportunity (if (>= (var-get current-network-height) (get cooling-end opportunity))
            (ok (get insight opportunity))
            ERR-COOLING-PERIOD-ACTIVE)
        ERR-INVALID-OPPORTUNITY))

(define-read-only (get-analyst-status (analyst principal))
    (map-get? analyst-metrics analyst))

(define-read-only (get-opportunity-validation-status (opportunity-id uint) (analyst principal))
    (map-get? opportunity-validations {opportunity: opportunity-id, analyst: analyst}))

(define-read-only (get-current-network-height)
    (var-get current-network-height))

(define-read-only (get-protocol-stats)
    {
        active: (var-get protocol-active),
        current-epoch: (var-get current-epoch),
        total-rewards-pool: (var-get total-rewards-pool),
        membership-cost: (var-get membership-cost),
        current-network-height: (var-get current-network-height)
    })