# Payment Gateway Integration

A shared-service integration scaffold that exposes one payment gateway through
**two delivery options** over a **single service and DTO layer**. The response
body deliberately flexes per use case (charge, refund, status,
list-transactions-with-paging) while error handling, auth, timeouts, paging, and
idempotency are handled once, in the shared layer.

## Architecture at a glance

```
                       ┌─────────────────────────────┐
  Flow / Agentforce ──▶│ Option A: PaymentGatewayAction│┐
                       │   (@InvocableMethod)          ││
                       └─────────────────────────────┘│
                                                        ├──▶ PaymentGatewayService ──▶ callout:Payment_Gateway
  External caller   ──▶┌─────────────────────────────┐│    (shared callout layer)     (Named + External Credential)
  (OAuth session)      │ Option B: PaymentGatewayResource│    + PaymentGatewayDTO
                       │   (@RestResource /payments/*) │┘    (shared request/result DTOs)
                       └─────────────────────────────┘
```

- **PaymentGatewayDTO** — shared request/result DTOs. A common `GatewayResult`
  base carries `success` / `statusCode` / `errorCode` / `errorMessage`; each
  operation has a result subclass that adds only its own fields.
- **PaymentGatewayService** (`with sharing`) — the only class that performs
  callouts. One method per operation (`charge`, `refund`, `getStatus`,
  `listTransactions`).
- **Option A / Option B** — thin adapters. They translate their input into DTOs,
  call the service, and translate the result into their own output format.

## The two options — when to use each

| | Option A — Invocable action | Option B — REST resource |
|---|---|---|
| Class | `PaymentGatewayAction` | `PaymentGatewayResource` |
| Surface | `@InvocableMethod` (Flow, and Agentforce via the `Truist_PaymentGatewayAction` GenAiFunction) | `@RestResource(urlMapping='/payments/*')` |
| Caller | Internal Salesforce automation / the agent planner | External systems and front-ends calling Salesforce |
| Invocation | One `operation` field switches the use case; bulk-safe (`List<Request>` in, `List<Response>` out) | HTTP verb + trailing path segment selects the use case |
| Output | Flat `@InvocableVariable` fields; list results as a `transactionsJson` String (invocable vars can't carry complex collections) | JSON body whose shape flexes per use case |
| Auth | Runs as the Salesforce user/automation already authenticated in-platform | Platform session / OAuth access token from a Connected App |

**Use Option A** when the caller is already inside Salesforce — a screen/record
Flow, or an Agentforce topic that needs to charge, refund, check status, or page
through transactions. It is bulk-safe and returns errors as data, so the planner
or Flow never has to catch an exception.

**Use Option B** when the caller is an external application that should reach the
gateway *through* Salesforce (to inherit Salesforce auth, logging, and sharing)
rather than integrating with the gateway directly.

Both call the same service, so behavior stays consistent regardless of entry
point.

## How the response body flexes per use case

The gateway supports four operations, and each returns a different shape:

| Operation | Key response fields |
|---|---|
| `charge` | `transactionId`, `status` |
| `refund` | `refundId`, `transactionId`, `status` |
| `status` | `transactionId`, `status` |
| `list-transactions-with-paging` | `transactionsJson` (JSON array), `nextPageToken` |

- **Option A** exposes every possible field as an `@InvocableVariable` and
  populates only the ones relevant to the requested operation. The transaction
  list is returned as a JSON String in `transactionsJson`.
- **Option B** serializes the operation's result DTO directly, so the JSON body
  naturally contains only that operation's fields plus the shared
  `success` / `statusCode` / `errorCode` / `errorMessage`.

Routing for Option B:

| Request | Operation |
|---|---|
| `POST /services/apexrest/payments/charge` | charge (JSON body) |
| `POST /services/apexrest/payments/refund` | refund (JSON body) |
| `GET  /services/apexrest/payments/status?transactionId=...` | status |
| `GET  /services/apexrest/payments/transactions?pageSize=&pageToken=&status=` | paged list |

## Cross-cutting considerations

### Authentication
- **Outbound (both options → gateway):** handled by the Named Credential
  `callout:Payment_Gateway`, which references the `Payment_Gateway` External
  Credential configured for the **OAuth 2.0 client-credentials** flow with a
  named principal (`PaymentGatewayPrincipal`). The Client Id/Secret are entered
  in the Setup UI only and are **never** stored in source. Grant the
  `Payment_Gateway_Access` permission set so a user's callouts can use the
  principal.
- **Inbound (Option B):** standard Salesforce Apex REST authentication — an
  OAuth access token / session from a Connected App. No custom authentication is
  added in the resource; callers authenticate to Salesforce the normal way.

### Timeouts
Every callout sets `req.setTimeout(120000)` explicitly — the maximum 120-second
synchronous window. A timeout surfaces as a structured `503` /
`GATEWAY_TIMEOUT` result (not an exception), with a message advising the caller
to retry using the same idempotency key.

### Idempotency
`charge` and `refund` accept an optional **Idempotency-Key**. The service sends
it as the `Idempotency-Key` header so the gateway can de-duplicate safe retries
and avoid double-charging. Option B reads the key from the `Idempotency-Key`
HTTP header first, then from the request body. Always send a stable key per
logical operation so a retry after a timeout is safe.

### Paging
`list-transactions-with-paging` uses **cursor-based** paging. The caller passes
an optional `pageSize` and a `pageToken` (cursor); a blank token means the first
page. The service returns `nextPageToken`; keep calling with that token until it
comes back blank to walk every page. Cursor paging avoids the skipped/duplicated
rows that offset paging suffers when the underlying data changes between calls.

### Error handling
The service never leaks stack traces. Non-2xx gateway responses, connection
failures, and timeouts are all caught and mapped to a structured result:

| Situation | `statusCode` | `errorCode` |
|---|---|---|
| Input validation failed | 400 | `VALIDATION_ERROR` |
| Transaction not found | 404 | `NOT_FOUND` |
| Gateway rejected the request | gateway's own code (e.g. 402) | `GATEWAY_ERROR` / gateway code |
| Timeout | 503 | `GATEWAY_TIMEOUT` |
| Gateway unreachable | 503 | `GATEWAY_UNAVAILABLE` |
| Unexpected | 500 | `UNEXPECTED_ERROR` |

Option B maps these directly onto `RestContext.response.statusCode`; Option A
returns them as data on the `Response`.

### Data access
The service performs **no SOQL and no DML** — it only makes HTTP callouts, so
there is no CRUD/FLS surface today. If persistence is added later (e.g. logging a
`Payment__c`), enforce CRUD/FLS at that point (`WITH USER_MODE` or
`Security.stripInaccessible`) and keep the classes `with sharing`.

## Per-org setup checklist

1. **Named Credential** `Payment_Gateway`: set the real `Url` (placeholder is
   `https://REPLACE_ME.payments.example.com`).
2. **External Credential** `Payment_Gateway`: set `TokenEndpointUrl` and `Scope`,
   then enter the **Client Id** and **Client Secret** on the
   `PaymentGatewayPrincipal` principal in Setup (never in metadata).
3. Assign the **`Payment_Gateway_Access`** permission set to the relevant users /
   integration user / Agentforce user.
4. (Option B) Configure a **Connected App** for the external callers that will
   authenticate to the Salesforce REST endpoint.
