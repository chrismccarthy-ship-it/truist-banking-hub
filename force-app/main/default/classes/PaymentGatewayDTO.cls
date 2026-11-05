/**
 * PaymentGatewayDTO
 * -----------------
 * Shared request / result Data Transfer Objects for the Payment Gateway
 * integration scaffold. These POJOs are the single DTO layer consumed by BOTH
 * delivery options:
 *   - Option A: PaymentGatewayAction  (@InvocableMethod for Flow / Agentforce)
 *   - Option B: PaymentGatewayResource (@RestResource exposed endpoint)
 *
 * Both options delegate to PaymentGatewayService, which speaks in these DTOs.
 *
 * Design notes:
 *  - The RESPONSE SHAPE flexes per use case: each operation has its own result
 *    subclass that adds only the fields that operation can populate. They all
 *    share a common GatewayResult base (success / statusCode / error fields) so
 *    callers can handle errors uniformly.
 *  - No secrets live here. No SObjects, DML, or SOQL. Pure data holders.
 */
public with sharing class PaymentGatewayDTO {

    // ---- Operation identifiers (string switch keys) ------------------------
    public static final String OP_CHARGE = 'charge';
    public static final String OP_REFUND = 'refund';
    public static final String OP_STATUS = 'status';
    public static final String OP_LIST   = 'list-transactions-with-paging';

    // ======================= REQUEST DTOs ===================================

    /** Create a charge against the gateway. */
    public class ChargeRequest {
        public Decimal amount;          // required, > 0 (minor-unit aware per gateway)
        public String currencyCode;     // ISO 4217, e.g. 'USD'
        public String source;           // tokenized payment method reference (never raw PAN)
        public String description;      // optional, human-readable memo
        public String idempotencyKey;   // optional but strongly recommended for retries
    }

    /** Refund a prior charge (full or partial). */
    public class RefundRequest {
        public String transactionId;    // required, the charge to refund
        public Decimal amount;          // null => full refund, else partial amount
        public String reason;           // optional
        public String idempotencyKey;   // optional but strongly recommended for retries
    }

    /** Fetch the current status of a single transaction. */
    public class StatusRequest {
        public String transactionId;    // required
    }

    /** List transactions using cursor-based paging. */
    public class ListRequest {
        public Integer pageSize;        // optional, gateway-capped
        public String pageToken;        // optional cursor; null/blank => first page
        public String statusFilter;     // optional status filter, e.g. 'succeeded'
    }

    // ======================= RESULT DTOs ====================================

    /**
     * Common base for all results. Errors are returned as DATA on this object
     * (never thrown and never carrying a raw stack trace).
     */
    public virtual class GatewayResult {
        public Boolean success = false;
        public Integer statusCode;      // gateway/HTTP status (200 ok, 400, 404, 402/gateway, 503 timeout)
        public String errorCode;        // stable machine code, e.g. 'VALIDATION_ERROR'
        public String errorMessage;     // safe, customer-presentable message (no internals)
    }

    /** Result of a charge. */
    public class ChargeResult extends GatewayResult {
        public String transactionId;
        public String status;           // e.g. 'succeeded', 'pending'
    }

    /** Result of a refund. */
    public class RefundResult extends GatewayResult {
        public String refundId;
        public String transactionId;
        public String status;           // e.g. 'refunded', 'pending'
    }

    /** Result of a status lookup. */
    public class StatusResult extends GatewayResult {
        public String transactionId;
        public String status;
    }

    /**
     * Result of a paged list. The transaction collection is carried as a JSON
     * String (transactionsJson) because invocable variables cannot carry
     * arbitrary complex collections; the REST option returns it inline.
     */
    public class ListResult extends GatewayResult {
        public String transactionsJson; // JSON array of transaction objects
        public String nextPageToken;    // cursor for the next page; null => last page
    }
}
