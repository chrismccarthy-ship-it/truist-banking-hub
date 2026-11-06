/**
 * PaymentGatewayAction_Test
 * -------------------------
 * Covers Option A (the invocable action) across all four use cases plus the
 * timeout path, the gateway-error path, and bulk invocation. Uses the shared
 * PaymentGatewayHttpMock. PNB pattern: Positive (charge/refund/status/list),
 * Negative (timeout, gateway error, bad operation, validation), Bulk (250).
 */
@isTest
private class PaymentGatewayAction_Test {

    private static PaymentGatewayAction.Request chargeRequest() {
        PaymentGatewayAction.Request r = new PaymentGatewayAction.Request();
        r.operation = 'charge';
        r.amount = 100.00;
        r.currencyCode = 'USD';
        r.source = 'tok_test_visa';
        r.description = 'Unit test charge';
        r.idempotencyKey = 'idem-123';
        return r;
    }

    @isTest
    static void testChargeSuccess() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        Test.startTest();
        List<PaymentGatewayAction.Response> out =
            PaymentGatewayAction.execute(new List<PaymentGatewayAction.Request>{ chargeRequest() });
        Test.stopTest();

        Assert.areEqual(1, out.size(), 'One response expected');
        Assert.isTrue(out[0].success, 'Charge should succeed');
        Assert.areEqual('txn_1001', out[0].transactionId, 'Transaction id mapped');
        Assert.areEqual('succeeded', out[0].status, 'Status mapped');
    }

    @isTest
    static void testRefundSuccess() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        PaymentGatewayAction.Request r = new PaymentGatewayAction.Request();
        r.operation = 'refund';
        r.transactionId = 'txn_1001';
        r.amount = 25.00;
        r.reason = 'customer request';
        r.idempotencyKey = 'idem-refund-1';

        Test.startTest();
        List<PaymentGatewayAction.Response> out =
            PaymentGatewayAction.execute(new List<PaymentGatewayAction.Request>{ r });
        Test.stopTest();

        Assert.isTrue(out[0].success, 'Refund should succeed');
        Assert.areEqual('refunded', out[0].status, 'Refund status mapped');
        Assert.areEqual('txn_1001', out[0].transactionId, 'Transaction id mapped');
    }

    @isTest
    static void testStatusSuccess() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        PaymentGatewayAction.Request r = new PaymentGatewayAction.Request();
        r.operation = 'status';
        r.transactionId = 'txn_1001';

        Test.startTest();
        List<PaymentGatewayAction.Response> out =
            PaymentGatewayAction.execute(new List<PaymentGatewayAction.Request>{ r });
        Test.stopTest();

        Assert.isTrue(out[0].success, 'Status should succeed');
        Assert.areEqual('succeeded', out[0].status, 'Status mapped');
    }

    @isTest
    static void testListWithPaging() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        PaymentGatewayAction.Request r = new PaymentGatewayAction.Request();
        r.operation = 'list-transactions-with-paging';
        r.pageSize = 2;
        r.pageToken = null;
        r.statusFilter = 'succeeded';

        Test.startTest();
        List<PaymentGatewayAction.Response> out =
            PaymentGatewayAction.execute(new List<PaymentGatewayAction.Request>{ r });
        Test.stopTest();

        Assert.isTrue(out[0].success, 'List should succeed');
        Assert.areEqual('cursor_page_2', out[0].nextPageToken, 'Next page token mapped');
        Assert.isNotNull(out[0].transactionsJson, 'Transactions JSON populated');
        Assert.isTrue(out[0].transactionsJson.contains('txn_1001'), 'JSON carries transactions');
    }

    @isTest
    static void testTimeoutPath() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.TIMEOUT));
        Test.startTest();
        List<PaymentGatewayAction.Response> out =
            PaymentGatewayAction.execute(new List<PaymentGatewayAction.Request>{ chargeRequest() });
        Test.stopTest();

        Assert.isFalse(out[0].success, 'Timeout should not succeed');
        Assert.areEqual(503, out[0].statusCode, 'Timeout mapped to 503');
        Assert.isNotNull(out[0].errorMessage, 'Structured error message returned');
    }

    @isTest
    static void testGatewayErrorPath() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.GATEWAY_ERROR));
        Test.startTest();
        List<PaymentGatewayAction.Response> out =
            PaymentGatewayAction.execute(new List<PaymentGatewayAction.Request>{ chargeRequest() });
        Test.stopTest();

        Assert.isFalse(out[0].success, 'Gateway error should not succeed');
        Assert.areEqual(402, out[0].statusCode, 'Gateway status code passed through');
        Assert.isNotNull(out[0].errorMessage, 'Error message returned');
    }

    @isTest
    static void testValidationAndUnknownOperation() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));

        PaymentGatewayAction.Request badOp = new PaymentGatewayAction.Request();
        badOp.operation = 'teleport';

        PaymentGatewayAction.Request badCharge = new PaymentGatewayAction.Request();
        badCharge.operation = 'charge';
        badCharge.amount = null; // invalid

        Test.startTest();
        List<PaymentGatewayAction.Response> out = PaymentGatewayAction.execute(
            new List<PaymentGatewayAction.Request>{ badOp, badCharge }
        );
        Test.stopTest();

        Assert.areEqual(400, out[0].statusCode, 'Unknown operation -> 400');
        Assert.isFalse(out[0].success, 'Unknown operation fails');
        Assert.areEqual(400, out[1].statusCode, 'Missing amount -> 400 validation');
        Assert.isFalse(out[1].success, 'Invalid charge fails');
    }

    @isTest
    static void testBulkInvocation() {
        Test.setMock(HttpCalloutMock.class, new PaymentGatewayHttpMock(PaymentGatewayHttpMock.Mode.SUCCESS));
        // One callout per request, so bulk size stays under the 100-callout-per-
        // transaction governor limit that applies to callout-backed invocables.
        final Integer bulkSize = 50;
        List<PaymentGatewayAction.Request> requests = new List<PaymentGatewayAction.Request>();
        for (Integer i = 0; i < bulkSize; i++) {
            requests.add(chargeRequest());
        }
        Test.startTest();
        List<PaymentGatewayAction.Response> out = PaymentGatewayAction.execute(requests);
        Test.stopTest();

        Assert.areEqual(bulkSize, out.size(), 'One response per request (bulk-safe)');
        Assert.isTrue(out[0].success, 'Bulk responses succeed');
        Assert.isTrue(out[bulkSize - 1].success, 'Last bulk response succeeds');
    }

    @isTest
    static void testEmptyAndNullInput() {
        Assert.areEqual(0, PaymentGatewayAction.execute(null).size(), 'Null input -> empty list');
        Assert.areEqual(
            0,
            PaymentGatewayAction.execute(new List<PaymentGatewayAction.Request>()).size(),
            'Empty input -> empty list'
        );
    }
}
