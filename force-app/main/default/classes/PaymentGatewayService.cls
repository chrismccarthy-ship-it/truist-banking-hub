/**
 * PaymentGatewayService
 * ---------------------
 * Shared OUTBOUND CALLOUT layer for the Payment Gateway integration. This is
 * the single service both delivery options delegate to:
 *   - Option A: PaymentGatewayAction  (@InvocableMethod)
 *   - Option B: PaymentGatewayResource (@RestResource)
 *
 * Integration pattern: authenticated outbound REST callout via a Named
 * Credential ('callout:Payment_Gateway') that references an External
 * Credential (OAuth 2.0 client-credentials). NO secrets appear in this code or
 * in metadata -- the Client Id/Secret are entered in the Setup UI only.
 *
 * Operational safeguards implemented here:
 *  - Explicit req.setTimeout(120000) on every callout (max platform timeout).
 *  - Idempotency-Key header support so safe retries do not double-charge.
 *  - Cursor/pageToken based paging; nextPageToken returned to the caller.
 *  - CalloutException / timeouts are caught and converted to STRUCTURED errors
 *    on the result DTO. Stack traces are never leaked to callers.
 *
 * Data access note: this service performs NO SOQL and NO DML -- it only makes
 * HTTP callouts, so there is no CRUD/FLS surface here. If a future change adds
 * persistence (e.g. logging a Payment__c record), enforce CRUD/FLS at that
 * point using WITH USER_MODE on DML/SOQL or Security.stripInaccessible, and
 * keep this class 'with sharing' so row-level access is respected.
 */
public with sharing class PaymentGatewayService {

    // Named Credential reference. The Url + auth live in metadata/Setup, never here.
    @TestVisible
    private static final String NAMED_CREDENTIAL = 'callout:Payment_Gateway';

    // Explicit, maximum synchronous callout timeout (120 seconds, in ms).
    @TestVisible
    private static final Integer TIMEOUT_MS = 120000;

    // Relative resource paths on the gateway (base Url comes from the Named Credential).
    private static final String PATH_CHARGES      = '/v1/charges';
    private static final String PATH_REFUNDS      = '/v1/refunds';
    private static final String PATH_TRANSACTIONS = '/v1/transactions';

    // ========================= CHARGE =======================================
    public PaymentGatewayDTO.ChargeResult charge(PaymentGatewayDTO.ChargeRequest input) {
        PaymentGatewayDTO.ChargeResult result = new PaymentGatewayDTO.ChargeResult();
        if (input == null || input.amount == null || input.amount <= 0) {
            setValidationError(result, 'A positive amount is required to create a charge.');
            return result;
        }
        Map<String, Object> payload = new Map<String, Object>{
            'amount'      => input.amount,
            'currency'    => input.currencyCode,
            'source'      => input.source,
            'description' => input.description
        };
        HttpRequest req = buildRequest('POST', PATH_CHARGES, JSON.serialize(payload), input.idempotencyKey);
        try {
            HttpResponse res = new Http().send(req);
            result.statusCode = res.getStatusCode();
            if (isSuccess(res.getStatusCode())) {
                Map<String, Object> body = parse(res.getBody());
                result.success = true;
                result.transactionId = str(body.get('id'));
                result.status = str(body.get('status'));
            } else {
                applyGatewayError(result, res);
            }
        } catch (System.CalloutException ce) {
            applyCalloutException(result, ce);
        } catch (Exception ex) {
            applyUnexpected(result);
        }
        return result;
    }

    // ========================= REFUND =======================================
    public PaymentGatewayDTO.RefundResult refund(PaymentGatewayDTO.RefundRequest input) {
        PaymentGatewayDTO.RefundResult result = new PaymentGatewayDTO.RefundResult();
        if (input == null || String.isBlank(input.transactionId)) {
            setValidationError(result, 'A transactionId is required to issue a refund.');
            return result;
        }
        Map<String, Object> payload = new Map<String, Object>{
            'transactionId' => input.transactionId,
            'amount'        => input.amount, // null => full refund
            'reason'        => input.reason
        };
        HttpRequest req = buildRequest('POST', PATH_REFUNDS, JSON.serialize(payload), input.idempotencyKey);
        try {
            HttpResponse res = new Http().send(req);
            result.statusCode = res.getStatusCode();
            if (isSuccess(res.getStatusCode())) {
                Map<String, Object> body = parse(res.getBody());
                result.success = true;
                result.refundId = str(body.get('id'));
                result.transactionId = str(body.get('transactionId'));
                result.status = str(body.get('status'));
            } else {
                applyGatewayError(result, res);
            }
        } catch (System.CalloutException ce) {
            applyCalloutException(result, ce);
        } catch (Exception ex) {
            applyUnexpected(result);
        }
        return result;
    }

    // ========================= STATUS =======================================
    public PaymentGatewayDTO.StatusResult getStatus(PaymentGatewayDTO.StatusRequest input) {
        PaymentGatewayDTO.StatusResult result = new PaymentGatewayDTO.StatusResult();
        if (input == null || String.isBlank(input.transactionId)) {
            setValidationError(result, 'A transactionId is required to look up status.');
            return result;
        }
        String path = PATH_TRANSACTIONS + '/' + EncodingUtil.urlEncode(input.transactionId, 'UTF-8');
        HttpRequest req = buildRequest('GET', path, null, null);
        try {
            HttpResponse res = new Http().send(req);
            result.statusCode = res.getStatusCode();
            if (isSuccess(res.getStatusCode())) {
                Map<String, Object> body = parse(res.getBody());
                result.success = true;
                result.transactionId = str(body.get('id'));
                result.status = str(body.get('status'));
            } else {
                applyGatewayError(result, res);
            }
        } catch (System.CalloutException ce) {
            applyCalloutException(result, ce);
        } catch (Exception ex) {
            applyUnexpected(result);
        }
        return result;
    }

    // ============== LIST TRANSACTIONS (with cursor paging) ==================
    public PaymentGatewayDTO.ListResult listTransactions(PaymentGatewayDTO.ListRequest input) {
        PaymentGatewayDTO.ListResult result = new PaymentGatewayDTO.ListResult();
        PaymentGatewayDTO.ListRequest safe = (input == null) ? new PaymentGatewayDTO.ListRequest() : input;

        List<String> qs = new List<String>();
        if (safe.pageSize != null && safe.pageSize > 0) {
            qs.add('pageSize=' + EncodingUtil.urlEncode(String.valueOf(safe.pageSize), 'UTF-8'));
        }
        if (String.isNotBlank(safe.pageToken)) {
            qs.add('pageToken=' + EncodingUtil.urlEncode(safe.pageToken, 'UTF-8'));
        }
        if (String.isNotBlank(safe.statusFilter)) {
            qs.add('status=' + EncodingUtil.urlEncode(safe.statusFilter, 'UTF-8'));
        }
        String path = PATH_TRANSACTIONS + (qs.isEmpty() ? '' : ('?' + String.join(qs, '&')));

        HttpRequest req = buildRequest('GET', path, null, null);
        try {
            HttpResponse res = new Http().send(req);
            result.statusCode = res.getStatusCode();
            if (isSuccess(res.getStatusCode())) {
                Map<String, Object> body = parse(res.getBody());
                result.success = true;
                // Preserve the data array as a JSON string (invocable-friendly).
                Object data = body.get('data');
                result.transactionsJson = (data == null) ? '[]' : JSON.serialize(data);
                result.nextPageToken = str(body.get('nextPageToken'));
            } else {
                applyGatewayError(result, res);
            }
        } catch (System.CalloutException ce) {
            applyCalloutException(result, ce);
        } catch (Exception ex) {
            applyUnexpected(result);
        }
        return result;
    }

    // ========================= HELPERS ======================================

    private HttpRequest buildRequest(String method, String path, String body, String idempotencyKey) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + path);
        req.setMethod(method);
        req.setTimeout(TIMEOUT_MS); // explicit 120000 ms
        req.setHeader('Accept', 'application/json');
        if (body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }
        // Idempotency-Key lets the gateway de-duplicate safe retries (no double charge).
        if (String.isNotBlank(idempotencyKey)) {
            req.setHeader('Idempotency-Key', idempotencyKey);
        }
        return req;
    }

    private Boolean isSuccess(Integer statusCode) {
        return statusCode != null && statusCode >= 200 && statusCode < 300;
    }

    private Map<String, Object> parse(String body) {
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(body);
            return (parsed instanceof Map<String, Object>)
                ? (Map<String, Object>) parsed
                : new Map<String, Object>();
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    private String str(Object o) {
        return (o == null) ? null : String.valueOf(o);
    }

    private void setValidationError(PaymentGatewayDTO.GatewayResult r, String message) {
        r.success = false;
        r.statusCode = 400;
        r.errorCode = 'VALIDATION_ERROR';
        r.errorMessage = message;
    }

    /**
     * Maps a non-2xx gateway response to a structured error. We surface the
     * gateway's own status code and (when present) its error code, but we do
     * NOT echo arbitrary gateway internals back verbatim.
     */
    private void applyGatewayError(PaymentGatewayDTO.GatewayResult r, HttpResponse res) {
        r.success = false;
        r.statusCode = res.getStatusCode();
        r.errorCode = 'GATEWAY_ERROR';
        String message = 'The payment gateway rejected the request.';
        try {
            Map<String, Object> body = parse(res.getBody());
            Object err = body.get('error');
            if (err instanceof Map<String, Object>) {
                Map<String, Object> em = (Map<String, Object>) err;
                if (em.get('code') != null) {
                    r.errorCode = String.valueOf(em.get('code'));
                }
                if (em.get('message') != null) {
                    message = String.valueOf(em.get('message'));
                }
            }
        } catch (Exception ignored) {
            // Fall back to the generic message; never leak parsing internals.
        }
        if (res.getStatusCode() == 404) {
            r.errorCode = 'NOT_FOUND';
            message = 'The requested transaction was not found.';
        }
        r.errorMessage = message;
    }

    /**
     * Converts a CalloutException (connection failure or read timeout) into a
     * structured 503-style error. Timeouts are the common case for the 120s
     * window; the generic message tells the caller it is safe to retry with the
     * same idempotency key.
     */
    private void applyCalloutException(PaymentGatewayDTO.GatewayResult r, System.CalloutException ce) {
        r.success = false;
        String m = (ce.getMessage() == null) ? '' : ce.getMessage().toLowerCase();
        if (m.contains('time')) {
            r.statusCode = 503;
            r.errorCode = 'GATEWAY_TIMEOUT';
            r.errorMessage = 'The payment gateway did not respond in time. Retry with the same idempotency key.';
        } else {
            r.statusCode = 503;
            r.errorCode = 'GATEWAY_UNAVAILABLE';
            r.errorMessage = 'The payment gateway could not be reached. Please try again shortly.';
        }
    }

    private void applyUnexpected(PaymentGatewayDTO.GatewayResult r) {
        r.success = false;
        r.statusCode = 500;
        r.errorCode = 'UNEXPECTED_ERROR';
        r.errorMessage = 'An unexpected error occurred while contacting the payment gateway.';
    }
}
