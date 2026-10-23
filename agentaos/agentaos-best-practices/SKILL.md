---
name: agentaos-best-practices
description: Starting point for any AgentaOS integration, covering what a merchant of record does, the four core objects (product or payment link, checkout, subscription, webhook event), API keys and test vs live mode, the @agentaos/pay SDK, the REST base URL and x-api-key auth, the money model, rate limits, idempotency, and the canonical product to checkout to webhook flow. Use when starting a new AgentaOS integration, initializing the AgentaOS client, choosing between a shared buyer link and a server-created checkout, or unsure which AgentaOS skill applies.
---

# AgentaOS Integration Guide

AgentaOS is a billing and payments platform and the merchant of record (MoR) for every sale. The buyer pays AgentaOS, AgentaOS charges and remits VAT or sales tax, issues the invoice and receipt, handles refunds and disputes, and pays the merchant out. Your code creates products and checkouts, then reacts to signed webhook events.

This skill is the orientation layer. The other skills in this pack go deep on one topic each.

## When to use this skill

- Starting a new AgentaOS integration and choosing an architecture
- Installing and initializing `@agentaos/pay`, or calling the REST API from another language
- Understanding test vs live keys, the money model, rate limits or idempotency
- Deciding which skill in this pack to load next

## Which skill next

| Task | Skill |
|------|-------|
| Buy button, hosted or embedded checkout, one-off payment | `checkout-integration` |
| Monthly or yearly plans, trials, plan changes, cancel, credits | `subscription-integration` |
| Receiving and verifying events, fulfillment, idempotency | `webhook-integration` |
| Next.js App Router route handlers | `nextjs-integration` |
| App that signs users in with Better Auth | `better-auth-integration` |
| Letting an AI agent run the account over MCP | `mcp-usage` |
| Terminal, scripts, CI with the `agenta` CLI | `cli-usage` |
| Test cards, test mode, go-live checklist | `testing-and-go-live` |
| Refund requests, chargebacks, dispute events | `refunds-and-disputes` |
| Moving from Stripe, Paddle, Lemon Squeezy, Creem or Gumroad | `migrate-from-stripe-paddle-lemonsqueezy` |

---

## Core concepts

| Term | What it is | Where its id comes from |
|------|------------|-------------------------|
| **Product** (API: **payment link**) | A reusable priced thing: one-time, or a subscription plan billed `month` or `year`. Created once, paid many times. Its UUID is the `linkId`. | `paymentLinks.create()` returns `id`; dashboard: **Building this into your site?** then **Copy ID** |
| **Buyer link** | The product's public URL, `https://app.agentaos.ai/pay/<token>`. Anyone can open it. Carries no app user id. | `checkoutUrl` on the payment link |
| **Checkout** (API path: `/gateway/sessions`) | One payment attempt by one buyer. Can carry your `metadata` (your user id). Status `open`, `completed`, `expired` or `cancelled`. | `checkouts.create()` returns `sessionId` and `checkoutUrl` |
| **Subscription** | Created by AgentaOS when a buyer pays a subscription product. There is no create endpoint. | `metadata.subscriptionId` on the first `checkout.session.completed`; `subscriptions.list()` |
| **Webhook event** | A signed POST to your server, for example `checkout.session.completed`. | Settings, Developers, Webhooks |

Three ids that are easy to mix up:

- `linkId` is the product UUID. It is not the token at the end of the buyer link.
- The `checkout.session.completed` event sends `link_id` as the buyer-link token, not the UUID. Subscription events send `link_id` as the UUID.
- `sessionId` identifies one checkout. Use it as the fulfillment and deduplication key.

---

## Setup

### 1. Get an API key

In the dashboard at https://app.agentaos.ai, open **Developers, API keys** and click **Generate Test Key** (test mode) or **Generate Live Key** (live mode). The key is shown once.

| Prefix | Mode | Data |
|--------|------|------|
| `sk_test_` | Test | Test data only. No real money, no business verification needed. |
| `sk_live_` | Live | Real money. The business must be verified. |

The prefix selects the mode. There is no mode parameter and one base URL for both. Test and live data are separate: a record from the other mode returns `404`.

```bash
# .env (never commit)
AGENTAOS_API_KEY=sk_test_...
AGENTAOS_WEBHOOK_SECRET=whsec_...
```

### 2. Install the SDK (TypeScript / Node.js)

```bash
npm install @agentaos/pay
```

- Node.js 20 or later. ESM only. Zero runtime dependencies.
- Backend only. The constructor throws if it detects `window` or `document`. Never ship the key to a browser or mobile app.

```typescript
import { AgentaOS } from '@agentaos/pay';

export const agentaos = new AgentaOS(process.env.AGENTAOS_API_KEY!, {
  timeout: 30_000, // per attempt, ms (default)
  maxRetries: 2,   // retries on 5xx and network errors (default)
});
```

Resources: `checkouts`, `paymentLinks`, `subscriptions`, `invoices`, `customers`, `transactions`, `webhooks`.

### 3. Or call REST directly (any language)

```bash
curl https://api.agentaos.ai/api/v1/gateway/payment-links \
  -H "x-api-key: $AGENTAOS_API_KEY"
```

- Base URL: `https://api.agentaos.ai/api/v1`
- Auth: `x-api-key` header. API keys have no bearer form.
- Bodies: JSON, camelCase fields (`successUrl`, `billingInterval`). Unknown fields are rejected with `400`. Max body 512 KB.
- Responses: mostly snake_case (`created_at`, `amount_override`), plus computed camelCase fields like `checkoutUrl`. Subscriptions and Customers are camelCase throughout. The SDK camelCases everything for you.

---

## The canonical flow

```
1. Create the product once      POST /gateway/payment-links   (or the dashboard)
2. Buyer clicks Buy
   a. Anonymous buyer           send them to the product's checkoutUrl (buyer link)
   b. Logged-in user            POST /gateway/sessions with linkId + metadata, redirect to checkoutUrl
3. Buyer pays on the hosted (or embedded) checkout
4. AgentaOS POSTs checkout.session.completed to your webhook
5. Your server verifies the signature, dedupes on sessionId, unlocks access
```

```typescript
// 1. Once, at setup time (or in the dashboard)
const product = await agentaos.paymentLinks.create({
  name: 'Pro',
  amount: 29,              // currency units: 29 = EUR 29.00
  currency: 'EUR',
  type: 'subscription',
  billingInterval: 'month',
});
// Store product.id as PRO_LINK_ID

// 2b. When a logged-in user clicks Buy
const checkout = await agentaos.checkouts.create({
  linkId: process.env.PRO_LINK_ID!,
  buyerEmail: user.email,
  metadata: { customerId: user.id }, // camelCase keys
  successUrl: 'https://yourapp.com/thanks',
});
// redirect to checkout.checkoutUrl
```

The redirect to `successUrl` (with `?sessionId=` appended) is not proof of payment. Proof is the verified webhook event or `checkouts.retrieve(sessionId).status === 'completed'`.

---

## Money model

| Form | Where | Example |
|------|-------|---------|
| Decimal currency units (number) | Every `amount` you send; `amount` on a payment link; `amount_override`; invoice `amount` | `49.99` = EUR 49.99 |
| Integer minor units (number) | Any field ending in `Minor`: `unitAmountMinor`, `dueTodayMinor`, `amountMinor` | `1999` = EUR 19.99 |
| String | `amount` inside a webhook event's `data` | `"49.99"` |

Never send `amount: 4900` expecting cents. That is 4,900 units of the currency. Currencies for fiat sales are `EUR` and `USD`.

---

## Rate limits

- 60 requests per 60 seconds, per client IP, per endpoint (lower on a few platform endpoints).
- Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`. Over the limit: `429` with `Retry-After` (seconds).
- All checkouts your server creates share one budget: 60 `POST /gateway/sessions` per minute. Create a checkout when the buyer clicks Buy, not on page view.
- The SDK retries a `429` once inline when `Retry-After` is 60 seconds or less.

## Idempotency

- `POST /gateway/sessions` accepts an optional `Idempotency-Key` header (or `idempotencyKey` in the body). A retry with the same key returns the first checkout.
- `POST /gateway/subscriptions/{id}/credits` requires it.
- No other endpoint reads it. A retried `POST /gateway/payment-links` can create a duplicate: list first, then retry.
- The SDK sends a fresh key on every POST and reuses it on its own retries. You cannot set it, except `subscriptions.credit()` which requires `idempotencyKey`.

## Errors

Every error is JSON with `statusCode`, `message`, `timestamp`, `requestId` (also the `x-request-id` header), sometimes `errors[]` (validation) and `code`. Branch on `code` when present, never on `message`. The SDK throws typed subclasses of `AgentaOSError`: `ValidationError`, `AuthenticationError`, `PermissionError`, `NotFoundError`, `RateLimitError`, `IdempotencyError` (any `409`), `ApiError`, `TimeoutError`, `WebhookVerificationError`.

```typescript
import { AgentaOSError, ValidationError, RateLimitError } from '@agentaos/pay';

try {
  await agentaos.checkouts.create({ amount: 49.99, currency: 'EUR' });
} catch (err) {
  if (err instanceof ValidationError) console.error(err.errors);        // [{ field, message }]
  else if (err instanceof RateLimitError) console.error(err.retryAfter); // milliseconds
  else if (err instanceof AgentaOSError) console.error(err.status, err.code, err.requestId);
  else throw err;
}
```

---

## What AgentaOS handles vs what you build

| AgentaOS | You |
|----------|-----|
| Hosted and embedded checkout, card, Apple Pay, Google Pay, bank transfer on EUR | Creating products once and checkouts per buyer |
| VAT and sales tax, invoices, receipts, buyer emails | Storing `subscriptionId` and access state per user |
| Recurring billing, retries on failed renewals | Webhook endpoint with signature check and dedupe |
| Refunds (on request) and dispute responses | Billing UI in your app (there is no hosted customer portal) |
| Payouts to your bank account | Checking `livemode` before fulfilling |

Pricing and fees: see https://agentaos.ai/pricing.

---

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Creating a product per buyer | Create each product once; create a checkout per buyer |
| Sending logged-in users the `/pay/...` buyer link | It carries no `metadata`. Create a checkout with `linkId` + `metadata` |
| Unlocking on the success redirect | Unlock on the verified webhook or `checkouts.retrieve()` status |
| Passing the buyer-link token as `linkId` | `linkId` is the product UUID (`id`) |
| `amount: 2900` for EUR 29 | `amount: 29` |
| `snake_case` metadata keys | `verify()` camelCases them: `user_id` comes back as `userId`. Use camelCase |
| `http://` or `localhost` success URLs | `successUrl`, `cancelUrl`, `webhookUrl` must be `https://` |
| Using `@agentaos/pay` in client code | Server only; the constructor throws in a browser |
| Creating a checkout on every page view | Rate limit is shared across all buyers; create on click |
| Sending card numbers to the API | Cards are typed only into the checkout page |

## Docs

- Introduction (base URL, auth, money model, rate limits, idempotency): https://docs.agentaos.ai/api-reference/introduction
- SDK overview: https://docs.agentaos.ai/sdk/pay-overview
- SDK errors: https://docs.agentaos.ai/sdk/pay-errors
- Error codes: https://docs.agentaos.ai/api-reference/error-codes
- How merchant of record works: https://docs.agentaos.ai/mor/how-it-works
- OpenAPI: https://docs.agentaos.ai/openapi.json
- Docs index for LLMs: https://docs.agentaos.ai/llms.txt (full text: https://docs.agentaos.ai/llms-full.txt)
