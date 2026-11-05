/**
 * PaymentGatewayAction  --  OPTION A (Invocable action)
 * -----------------------------------------------------
 * Exposes the Payment Gateway as a single @InvocableMethod so it can be called
 * from Flow and, via a GenAiFunction wrapper, from Agentforce.
 *
 * One action, many use cases: the 'operation' input switches between
 * charge / refund / status / list-transactions-with-paging, and the Response
 * populates only the fields relevant to that operation (its shape flexes per
 * use case). For the list operation, results are returned as a JSON String in
 * 'transactionsJson' because invocable variables cannot carry arbitrary
 * complex collections.
 *
 * Agentforce grounding: the @InvocableVariable labels/descriptions below are
 * what the planner reads to decide when and how to call this action, so they
 * are written for the planner, not just for developers.
 *
 * Errors are returned as DATA (success=false + errorMessage), never thrown, so
 * Flow/Agentforce never sees an unhandled exception. Bulk-safe: one Response is
 * returned per Request, in order.
 *
 * All business logic / callouts are delegated to PaymentGatewayService.
 */
public with sharing class PaymentGatewayAction {

    @InvocableMethod(
        label='Payment Gateway Action'
        category='Payments'
        description='Charge, refund, get status, or list transactions (with paging) through the payment gateway. Set operation to one of: charge, refund, status, list-transactions-with-paging.'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }
        PaymentGatewayService service = new PaymentGatewayService();
        for (Request req : requests) {
            responses.add(process(req, service));
        }
        return responses;
    }

    private static Response process(Request req, PaymentGatewayService service) {
        Response resp = new Response();
        try {
            String op = (req == null || req.operation == null) ? '' : req.operation.trim().toLowerCase();
            switch on op {
                when 'charge' {
                    PaymentGatewayDTO.ChargeRequest dto = new PaymentGatewayDTO.ChargeRequest();
                    dto.amount = req.amount;
                    dto.currencyCode = req.currencyCode;
                    dto.source = req.source;
                    dto.description = req.description;
                    dto.idempotencyKey = req.idempotencyKey;
                    PaymentGatewayDTO.ChargeResult r = service.charge(dto);
                    resp.success = r.success;
                    resp.statusCode = r.statusCode;
                    resp.transactionId = r.transactionId;
                    resp.status = r.status;
                    resp.errorMessage = r.errorMessage;
                }
                when 'refund' {
                    PaymentGatewayDTO.RefundRequest dto = new PaymentGatewayDTO.RefundRequest();
                    dto.transactionId = req.transactionId;
                    dto.amount = req.amount;
                    dto.reason = req.reason;
                    dto.idempotencyKey = req.idempotencyKey;
                    PaymentGatewayDTO.RefundResult r = service.refund(dto);
                    resp.success = r.success;
                    resp.statusCode = r.statusCode;
                    resp.transactionId = r.transactionId;
                    resp.status = r.status;
                    resp.errorMessage = r.errorMessage;
                }
                when 'status' {
                    PaymentGatewayDTO.StatusRequest dto = new PaymentGatewayDTO.StatusRequest();
                    dto.transactionId = req.transactionId;
                    PaymentGatewayDTO.StatusResult r = service.getStatus(dto);
                    resp.success = r.success;
                    resp.statusCode = r.statusCode;
                    resp.transactionId = r.transactionId;
                    resp.status = r.status;
                    resp.errorMessage = r.errorMessage;
                }
                when 'list-transactions-with-paging', 'list' {
                    PaymentGatewayDTO.ListRequest dto = new PaymentGatewayDTO.ListRequest();
                    dto.pageSize = req.pageSize;
                    dto.pageToken = req.pageToken;
                    dto.statusFilter = req.statusFilter;
                    PaymentGatewayDTO.ListResult r = service.listTransactions(dto);
                    resp.success = r.success;
                    resp.statusCode = r.statusCode;
                    resp.transactionsJson = r.transactionsJson;
                    resp.nextPageToken = r.nextPageToken;
                    resp.errorMessage = r.errorMessage;
                }
                when else {
                    resp.success = false;
                    resp.statusCode = 400;
                    resp.errorMessage = 'Unsupported operation. Use one of: charge, refund, status, list-transactions-with-paging.';
                }
            }
        } catch (Exception e) {
            // Defensive: errors are always returned as data, never thrown.
            resp.success = false;
            resp.statusCode = 500;
            resp.errorMessage = 'An unexpected error occurred while processing the request.';
        }
        return resp;
    }

    // =========================== REQUEST ====================================
    public class Request {
        @InvocableVariable(
            label='Operation'
            description='Which payment operation to run: charge, refund, status, or list-transactions-with-paging.'
            required=true
        )
        public String operation;

        @InvocableVariable(label='Amount' description='Charge or partial-refund amount. For a full refund, leave blank.')
        public Decimal amount;

        @InvocableVariable(label='Currency Code' description='ISO 4217 currency code for a charge, e.g. USD.')
        public String currencyCode;

        @InvocableVariable(label='Payment Source' description='Tokenized payment method reference for a charge. Never a raw card number.')
        public String source;

        @InvocableVariable(label='Description' description='Optional memo describing the charge.')
        public String description;

        @InvocableVariable(label='Transaction Id' description='Gateway transaction id. Required for refund and status operations.')
        public String transactionId;

        @InvocableVariable(label='Refund Reason' description='Optional reason supplied with a refund.')
        public String reason;

        @InvocableVariable(label='Idempotency Key' description='Optional unique key so retries of charge/refund are not processed twice.')
        public String idempotencyKey;

        @InvocableVariable(label='Page Size' description='For list-transactions-with-paging: maximum transactions to return in this page.')
        public Integer pageSize;

        @InvocableVariable(label='Page Token' description='For list-transactions-with-paging: cursor returned by a prior call. Leave blank for the first page.')
        public String pageToken;

        @InvocableVariable(label='Status Filter' description='For list-transactions-with-paging: optional status to filter by, e.g. succeeded.')
        public String statusFilter;
    }

    // =========================== RESPONSE ===================================
    public class Response {
        @InvocableVariable(label='Success' description='True when the operation succeeded.')
        public Boolean success = false;

        @InvocableVariable(label='Status Code' description='Gateway/HTTP status code for the operation.')
        public Integer statusCode;

        @InvocableVariable(label='Status' description='Transaction status for charge/refund/status operations, e.g. succeeded or refunded.')
        public String status;

        @InvocableVariable(label='Transaction Id' description='The affected transaction id for charge/refund/status operations.')
        public String transactionId;

        @InvocableVariable(label='Next Page Token' description='For the list operation: cursor to pass back to retrieve the next page. Blank when there are no more pages.')
        public String nextPageToken;

        @InvocableVariable(label='Transactions JSON' description='For the list operation: a JSON array string of the returned transactions.')
        public String transactionsJson;

        @InvocableVariable(label='Error Message' description='Populated when success is false. Safe, customer-presentable description of the failure.')
        public String errorMessage;
    }
}
