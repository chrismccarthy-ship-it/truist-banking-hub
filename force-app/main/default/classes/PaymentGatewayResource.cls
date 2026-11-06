/**
 * PaymentGatewayResource  --  OPTION B (Exposed REST endpoint)
 * ------------------------------------------------------------
 * Publishes the Payment Gateway as a Salesforce REST resource at
 *   /services/apexrest/payments/*
 *
 * Routing (the trailing path segment selects the use case):
 *   POST /payments/charge      -> create a charge        (body: JSON)
 *   POST /payments/refund      -> refund a transaction   (body: JSON)
 *   GET  /payments/status?transactionId=...              -> single status
 *   GET  /payments/transactions?pageSize=&pageToken=&status=  -> paged list
 *
 * The RESPONSE BODY flexes per use case (charge/refund/status/list each return
 * a different JSON shape), and the HTTP status code is set appropriately:
 *   200  success
 *   400  input validation failure
 *   404  transaction not found
 *   503  gateway timeout / unreachable
 *   (gateway's own code, e.g. 402, is passed through on a gateway error)
 *
 * AUTHENTICATION: this endpoint relies on the Salesforce platform's standard
 * authentication for Apex REST -- an OAuth access token / session obtained via
 * a Connected App (or a named Salesforce session). We deliberately add NO
 * custom authentication here; callers authenticate to Salesforce the same way
 * they would for any Apex REST resource. The OUTBOUND leg to the gateway is
 * authenticated separately by the Named Credential used in PaymentGatewayService.
 *
 * All business logic / callouts are delegated to PaymentGatewayService.
 */
@RestResource(urlMapping='/payments/*')
global with sharing class PaymentGatewayResource {

    @HttpPost
    global static void doPost() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        String op = operationFromUri(request);
        PaymentGatewayService service = new PaymentGatewayService();

        Map<String, Object> body = parseBody(request);
        if (body == null) {
            writeError(response, 400, 'VALIDATION_ERROR', 'Request body must be valid JSON.');
            return;
        }

        if (op == 'charge') {
            PaymentGatewayDTO.ChargeRequest dto = new PaymentGatewayDTO.ChargeRequest();
            dto.amount = toDecimal(body.get('amount'));
            dto.currencyCode = toStr(body.get('currencyCode'));
            dto.source = toStr(body.get('source'));
            dto.description = toStr(body.get('description'));
            dto.idempotencyKey = idempotencyKey(request, body);
            PaymentGatewayDTO.ChargeResult r = service.charge(dto);
            response.statusCode = httpStatusFor(r);
            response.responseBody = Blob.valueOf(JSON.serialize(r));
        } else if (op == 'refund') {
            PaymentGatewayDTO.RefundRequest dto = new PaymentGatewayDTO.RefundRequest();
            dto.transactionId = toStr(body.get('transactionId'));
            dto.amount = toDecimal(body.get('amount'));
            dto.reason = toStr(body.get('reason'));
            dto.idempotencyKey = idempotencyKey(request, body);
            PaymentGatewayDTO.RefundResult r = service.refund(dto);
            response.statusCode = httpStatusFor(r);
            response.responseBody = Blob.valueOf(JSON.serialize(r));
        } else {
            writeError(response, 400, 'VALIDATION_ERROR',
                'Unsupported POST operation. Use /payments/charge or /payments/refund.');
        }
    }

    @HttpGet
    global static void doGet() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        String op = operationFromUri(request);
        PaymentGatewayService service = new PaymentGatewayService();
        Map<String, String> params = request.params;

        if (op == 'status') {
            String txnId = (params == null) ? null : params.get('transactionId');
            if (String.isBlank(txnId)) {
                writeError(response, 400, 'VALIDATION_ERROR', 'Query parameter transactionId is required.');
                return;
            }
            PaymentGatewayDTO.StatusRequest dto = new PaymentGatewayDTO.StatusRequest();
            dto.transactionId = txnId;
            PaymentGatewayDTO.StatusResult r = service.getStatus(dto);
            response.statusCode = httpStatusFor(r);
            response.responseBody = Blob.valueOf(JSON.serialize(r));
        } else if (op == 'transactions' || op == 'list') {
            PaymentGatewayDTO.ListRequest dto = new PaymentGatewayDTO.ListRequest();
            if (params != null) {
                String size = params.get('pageSize');
                if (String.isNotBlank(size) && size.isNumeric()) {
                    dto.pageSize = Integer.valueOf(size);
                }
                dto.pageToken = params.get('pageToken');
                dto.statusFilter = params.get('status');
            }
            PaymentGatewayDTO.ListResult r = service.listTransactions(dto);
            response.statusCode = httpStatusFor(r);
            response.responseBody = Blob.valueOf(JSON.serialize(r));
        } else {
            writeError(response, 400, 'VALIDATION_ERROR',
                'Unsupported GET operation. Use /payments/status or /payments/transactions.');
        }
    }

    // ========================= HELPERS ======================================

    /** Extracts the trailing path segment after '/payments/' as the operation. */
    private static String operationFromUri(RestRequest request) {
        String uri = (request == null || request.requestURI == null) ? '' : request.requestURI;
        String op = uri.substringAfterLast('/payments/');
        if (String.isBlank(op)) {
            op = uri.substringAfterLast('/');
        }
        return op == null ? '' : op.toLowerCase();
    }

    /**
     * Maps a structured result to the HTTP status code to return:
     * success -> 200, validation -> 400, not found -> 404,
     * timeout/unreachable -> 503, otherwise the gateway's own code (default 502).
     */
    private static Integer httpStatusFor(PaymentGatewayDTO.GatewayResult r) {
        if (r.success) {
            return 200;
        }
        if (r.statusCode != null) {
            return r.statusCode;
        }
        return 502;
    }

    private static Map<String, Object> parseBody(RestRequest request) {
        if (request == null || request.requestBody == null) {
            return new Map<String, Object>();
        }
        String raw = request.requestBody.toString();
        if (String.isBlank(raw)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(raw);
            return (parsed instanceof Map<String, Object>)
                ? (Map<String, Object>) parsed
                : null;
        } catch (Exception e) {
            return null;
        }
    }

    /** Prefer an Idempotency-Key HTTP header, fall back to a body field. */
    private static String idempotencyKey(RestRequest request, Map<String, Object> body) {
        if (request != null && request.headers != null) {
            String h = request.headers.get('Idempotency-Key');
            if (String.isNotBlank(h)) {
                return h;
            }
        }
        return toStr(body.get('idempotencyKey'));
    }

    private static void writeError(RestResponse response, Integer statusCode, String errorCode, String message) {
        response.statusCode = statusCode;
        PaymentGatewayDTO.GatewayResult err = new PaymentGatewayDTO.GatewayResult();
        err.success = false;
        err.statusCode = statusCode;
        err.errorCode = errorCode;
        err.errorMessage = message;
        response.responseBody = Blob.valueOf(JSON.serialize(err));
    }

    private static String toStr(Object o) {
        return (o == null) ? null : String.valueOf(o);
    }

    private static Decimal toDecimal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Decimal) {
            return (Decimal) o;
        }
        try {
            return Decimal.valueOf(String.valueOf(o));
        } catch (Exception e) {
            return null;
        }
    }
}
