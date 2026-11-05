/**
 * PaymentGatewayResource_Test
 * ---------------------------
 * Covers Option B (the exposed REST resource) by setting up RestContext with a
 * RestRequest/RestResponse and exercising the POST (charge/refund) and GET
 * (status/list) routes against the shared PaymentGatewayHttpMock. Also covers
 * validation (400), not-found (404) and timeout (503) paths.
 */
@isTest
private class PaymentGatewayResource_Test {

    private static RestRequest newRequest(String method, String uri) {
        RestRequest req = new RestRequest();
        req.httpMethod = method;
        req.requestURI = uri;
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return req;
    }

    @isTest
    static void testPostChargeSuccess() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        RestRequest req = newRequest('POST', '/services/apexrest/payments/charge');
        req.addHeader('Idempotency-Key', 'idem-xyz');
        req.requestBody = Blob.valueOf('{"amount":100.00,"currencyCode":"USD","source":"tok_test"}');

        Test.startTest();
        PaymentGatewayResource.doPost();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, 'Charge returns 200');
        String body = RestContext.response.responseBody.toString();
        Assert.isTrue(body.contains('txn_1001'), 'Response body carries transaction id');
        Assert.isTrue(body.contains('"success":true'), 'Response flags success');
    }

    @isTest
    static void testPostRefundSuccess() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        RestRequest req = newRequest('POST', '/services/apexrest/payments/refund');
        req.requestBody = Blob.valueOf('{"transactionId":"txn_1001","amount":25.00,"reason":"test"}');

        Test.startTest();
        PaymentGatewayResource.doPost();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, 'Refund returns 200');
        Assert.isTrue(RestContext.response.responseBody.toString().contains('refunded'), 'Refund status present');
    }

    @isTest
    static void testPostValidationError() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        RestRequest req = newRequest('POST', '/services/apexrest/payments/charge');
        req.requestBody = Blob.valueOf('{"currencyCode":"USD"}'); // no amount

        Test.startTest();
        PaymentGatewayResource.doPost();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode, 'Missing amount -> 400');
    }

    @isTest
    static void testPostUnsupportedOperation() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        RestRequest req = newRequest('POST', '/services/apexrest/payments/explode');
        req.requestBody = Blob.valueOf('{"amount":1}');

        Test.startTest();
        PaymentGatewayResource.doPost();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode, 'Unsupported POST op -> 400');
    }

    @isTest
    static void testPostInvalidJson() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        RestRequest req = newRequest('POST', '/services/apexrest/payments/charge');
        req.requestBody = Blob.valueOf('not-json');

        Test.startTest();
        PaymentGatewayResource.doPost();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode, 'Invalid JSON -> 400');
    }

    @isTest
    static void testGetStatusSuccess() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        RestRequest req = newRequest('GET', '/services/apexrest/payments/status');
        req.addParameter('transactionId', 'txn_1001');

        Test.startTest();
        PaymentGatewayResource.doGet();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, 'Status returns 200');
        Assert.isTrue(RestContext.response.responseBody.toString().contains('succeeded'), 'Status present');
    }

    @isTest
    static void testGetStatusMissingParam() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        newRequest('GET', '/services/apexrest/payments/status');

        Test.startTest();
        PaymentGatewayResource.doGet();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode, 'Missing transactionId -> 400');
    }

    @isTest
    static void testGetStatusNotFound() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.NOT_FOUND));
        RestRequest req = newRequest('GET', '/services/apexrest/payments/status');
        req.addParameter('transactionId', 'txn_missing');

        Test.startTest();
        PaymentGatewayResource.doGet();
        Test.stopTest();

        Assert.areEqual(404, RestContext.response.statusCode, 'Unknown transaction -> 404');
    }

    @isTest
    static void testGetListWithPaging() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        RestRequest req = newRequest('GET', '/services/apexrest/payments/transactions');
        req.addParameter('pageSize', '2');
        req.addParameter('status', 'succeeded');

        Test.startTest();
        PaymentGatewayResource.doGet();
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode, 'List returns 200');
        String body = RestContext.response.responseBody.toString();
        Assert.isTrue(body.contains('cursor_page_2'), 'Next page token present');
        Assert.isTrue(body.contains('transactionsJson'), 'List payload present');
    }

    @isTest
    static void testGetTimeout() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.TIMEOUT));
        RestRequest req = newRequest('GET', '/services/apexrest/payments/status');
        req.addParameter('transactionId', 'txn_1001');

        Test.startTest();
        PaymentGatewayResource.doGet();
        Test.stopTest();

        Assert.areEqual(503, RestContext.response.statusCode, 'Timeout -> 503');
    }

    @isTest
    static void testGetUnsupportedOperation() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        newRequest('GET', '/services/apexrest/payments/wobble');

        Test.startTest();
        PaymentGatewayResource.doGet();
        Test.stopTest();

        Assert.areEqual(400, RestContext.response.statusCode, 'Unsupported GET op -> 400');
    }
}
