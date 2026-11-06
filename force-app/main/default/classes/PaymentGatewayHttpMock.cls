/**
 * PaymentGatewayHttpMock
 * ----------------------
 * Shared HttpCalloutMock for both PaymentGatewayAction_Test and
 * PaymentGatewayResource_Test. Construct it with a Mode to drive the scenario:
 *   SUCCESS       -> 2xx with a per-endpoint success body (charge/refund/status/list)
 *   TIMEOUT       -> throws CalloutException('Read timed out') to simulate the
 *                    120s read timeout (service maps this to a 503 result)
 *   GATEWAY_ERROR -> 402 with a gateway error envelope (card_declined)
 *   NOT_FOUND     -> 404 with a not-found envelope
 */
@isTest
public class PaymentGatewayHttpMock implements HttpCalloutMock {

    public enum Mode { SUCCESS, TIMEOUT, GATEWAY_ERROR, NOT_FOUND }

    private final Mode mode;

    public PaymentGatewayHttpMock(Mode mode) {
        this.mode = mode;
    }

    public HttpResponse respond(HttpRequest req) {
        if (mode == Mode.TIMEOUT) {
            // Simulate a read timeout; the service catches CalloutException.
            CalloutException timeout = new CalloutException();
            timeout.setMessage('Read timed out after 120000 ms');
            throw timeout;
        }

        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');

        if (mode == Mode.GATEWAY_ERROR) {
            res.setStatusCode(402);
            res.setBody('{"error":{"code":"card_declined","message":"Your card was declined."}}');
            return res;
        }

        if (mode == Mode.NOT_FOUND) {
            res.setStatusCode(404);
            res.setBody('{"error":{"code":"not_found","message":"No such transaction."}}');
            return res;
        }

        // SUCCESS: vary the body by method + path so the response shape flexes.
        String method = req.getMethod();
        String endpoint = req.getEndpoint();

        if (method == 'POST' && endpoint.contains('/charges')) {
            res.setStatusCode(200);
            res.setBody('{"id":"txn_1001","status":"succeeded"}');
        } else if (method == 'POST' && endpoint.contains('/refunds')) {
            res.setStatusCode(200);
            res.setBody('{"id":"rfnd_5001","transactionId":"txn_1001","status":"refunded"}');
        } else if (method == 'GET' && endpoint.contains('/transactions/')) {
            res.setStatusCode(200);
            res.setBody('{"id":"txn_1001","status":"succeeded"}');
        } else if (method == 'GET' && endpoint.contains('/transactions')) {
            res.setStatusCode(200);
            res.setBody('{"data":[{"id":"txn_1001","status":"succeeded"},{"id":"txn_1002","status":"pending"}],"nextPageToken":"cursor_page_2"}');
        } else {
            res.setStatusCode(200);
            res.setBody('{}');
        }
        return res;
    }
}
