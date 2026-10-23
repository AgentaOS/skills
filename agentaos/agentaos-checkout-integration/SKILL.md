---
name: agentaos-checkout-integration
description: AgentaOS checkout integration, covering products as reusable payment links (POST /gateway/payment-links, paymentLinks.create), shared buyer links, server-created checkout sessions (POST /gateway/sessions, checkouts.create) with linkId, metadata, buyer prefill, amountOverride and Idempotency-Key, standalone one-time checkouts, success and cancel URLs, status polling, and the embedded inline or overlay checkout (@agentaos/checkout, agentaos.js). Use when building a Buy button, pricing page, paywall checkout, one-off invoice payment, or embedding the checkout on your own page; use agentaos-subscription-integration for what happens after a plan is bought.
---

# AgentaOS Checkout Integration

A buyer always pays on the AgentaOS checkout: hosted at `https://app.agentaos.ai/...`, or embedded on your page. Card, Apple Pay and Google Pay (on supporting devices), and bank transfer on EUR sales. AgentaOS calculates VAT from the buyer's country and issues the invoice.

## When to use this skill

- Creating a product (one-time or subscription) and getting its buyer link
- Creating a checkout from your server for a logged-in user, with your own `metadata`
- Charging an amount your server computes (standalone checkout)
- Prefilling buyer email, country, company, VAT ID
- Embedding the checkout inline or as an overlay
- Checking whether a checkout was paid

---

## Core concepts

- **Product = payment link.** A reusable template with a fixed price. `id` is the `linkId`, `checkoutUrl` is the buyer link (`/pay/<token>`). Every visitor to the buyer link gets their own checkout.
- **Checkout = session.** One payment attempt. Statuses: `open`, `completed`, `expired`, `cancelled`. Default expiry 1800 seconds (range 300 to 86400). Checkouts eligible for bank transfer get a 48-hour window regardless.
- **Standalone checkout.** No `linkId`, you pass `amount`. Always a one-time payment: `checkouts.create()` has no `type` field. To sell a plan, pass a subscription product's `linkId`.

## Choose the pattern

| The app... | Use |
|------------|-----|
| Has no login, or sells to anyone (landing page, link in bio, invoice) | **Shared buyer link.** Put the product's `checkoutUrl` behind an `<a href>`. No server code. |
| Has logged-in users and must know which user paid | **Server-created checkout** with `linkId` + `metadata`, then webhook |
| Wants the checkout on its own page | **Embedded checkout** with a buyer link, or with a server-created `sessionId` |

---

## Step 1: Create the product (once)

Create it in the dashboard (**Products, New product**), with the CLI, MCP, or the API. Do this once per price, not per buyer. Monthly and yearly Pro are two products.

**SDK**

```typescript
import { AgentaOS } from '@agentaos/pay';
const agentaos = new AgentaOS(process.env.AGENTAOS_API_KEY!);

const product = await agentaos.paymentLinks.create({
  name: 'Launch Kit',
  amount: 49,                 // currency units, min 0.01, max 1,000,000
  currency: 'EUR',            // 'EUR' | 'USD'; defaults to your org's currency
  description: 'One sentence buyers see',
  successUrl: 'https://yourapp.com/thanks',
  cancelUrl: 'https://yourapp.com/pricing',
});

console.log(product.id);          // linkId (UUID), store it in config
console.log(product.checkoutUrl); // https://app.agentaos.ai/pay/<token>
```

**cURL**

```bash
curl -X POST https://api.agentaos.ai/api/v1/gateway/payment-links \
  -H "x-api-key: $AGENTAOS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Launch Kit",
    "amount": 49,
    "currency": "EUR",
    "description": "One sentence buyers see",
    "successUrl": "https://yourapp.com/thanks",
    "cancelUrl": "https://yourapp.com/pricing"
  }'
```

Payment link fields from the API reference: `amount` (required), `currency`, `name`, `description`, `imageUrl`, `type` (`one_time` | `subscription`), `billingInterval` (`month` | `year`, required for subscription), `trialPeriodDays` (1 to 730, subscription only), `maxUses`, `taxRateId`, `checkoutFields`, `webhookUrl`, `successUrl`, `cancelUrl`, `expiresAt`, `metadata` (up to 8 KB).

`POST /gateway/payment-links` does not read `Idempotency-Key`. If the request times out, list payment links before retrying, or you may create a duplicate.

Custom fields on the checkout page:

```typescript
await agentaos.paymentLinks.create({
  amount: 29.99,
  currency: 'EUR',
  description: 'Pro plan',
  checkoutFields: [
    { key: 'company', label: 'Company', type: 'text', required: false },
    { key: 'seats', label: 'Seats', type: 'select', required: true, options: ['1', '5', '10'] },
  ],
});
```

Other payment link operations: `paymentLinks.list({ limit, offset })`, `paymentLinks.retrieve(id)`, `PATCH /gateway/payment-links/{id}` (partial update), `paymentLinks.cancel(id)` (soft cancel: no new checkouts, history stays; existing subscriptions are unaffected).

---

## Step 2a: Shared buyer link (no server code)

```html
<a href="https://app.agentaos.ai/pay/<token>">Buy Launch Kit</a>
```

The buyer pays, gets a receipt and invoice by email, and lands on `successUrl?sessionId=<id>`. You learn who paid only from the email they typed. If the app must know which of its users paid, use Step 2b.

---

## Step 2b: Server-created checkout (logged-in users)

When the user clicks Buy, create a checkout from the `linkId`, attach your user id, redirect.

**SDK**

```typescript
const checkout = await agentaos.checkouts.create({
  linkId: process.env.PRO_LINK_ID!,  // product UUID, not the /pay/ token
  buyerEmail: user.email,            // prefilled and locked on the checkout
  buyerCountry: user.country,        // optional, ISO-2, drives VAT
  metadata: { customerId: user.id }, // camelCase keys, max 8 KB
  successUrl: 'https://yourapp.com/thanks',
  cancelUrl: 'https://yourapp.com/pricing',
});

await db.users.update(user.id, { pendingSessionId: checkout.sessionId });
return redirect(checkout.checkoutUrl);
```

**cURL** (with an idempotency key so a retry does not create a second checkout)

```bash
curl -X POST https://api.agentaos.ai/api/v1/gateway/sessions \
  -H "x-api-key: $AGENTAOS_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: upgrade-user_123-2026-10-23" \
  -d '{
    "linkId": "4cbb8f52-7cf2-4480-8c66-34f794cd23d0",
    "buyerEmail": "buyer@example.com",
    "metadata": { "customerId": "user_123" },
    "successUrl": "https://yourapp.com/thanks"
  }'
```

Reuse an open checkout when the user clicks twice, instead of creating another (saves your rate-limit budget):

```typescript
if (user.pendingSessionId) {
  const pending = await agentaos.checkouts.retrieve(user.pendingSessionId);
  if (pending.status === 'open') return redirect(pending.checkoutUrl);
}
```

A checkout from a `linkId` inherits the product's amount, currency, description and URLs. `amountOverride` changes the amount for this checkout only.

### Prefill buyer details

```typescript
await agentaos.checkouts.create({
  linkId: PRO_LINK_ID,
  buyerEmail: 'jane@acme.com',   // max 320
  buyerName: 'Jane Doe',         // max 200
  buyerCompany: 'Acme GmbH',     // max 200
  buyerCountry: 'DE',            // ISO 3166-1 alpha-2
  buyerVat: 'DE123456789',       // max 20
  buyerAddress: 'Hauptstrasse 1, Berlin', // max 500
});
```

A field you fill in is shown as "Set by" your business and cannot be changed by the buyer. Company, VAT and address print on the invoice.

---

## Step 2c: Standalone checkout (amount computed on your server)

```typescript
const checkout = await agentaos.checkouts.create({
  amount: 49.99,
  currency: 'EUR',
  description: 'Order #123',   // max 1000 chars
  successUrl: 'https://shop.com/success',
  cancelUrl: 'https://shop.com/cart',
  webhookUrl: 'https://shop.com/webhooks', // optional per-checkout endpoint
  expiresIn: 3600,
  dueDate: '2026-11-30',       // printed on the invoice only
  metadata: { orderId: 'order-123' },
});
```

```bash
curl -X POST https://api.agentaos.ai/api/v1/gateway/sessions \
  -H "x-api-key: $AGENTAOS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "amount": 49.99, "currency": "EUR", "description": "Order #123" }'
```

---

## Step 3: Confirm payment

Prefer the webhook (see `agentaos-webhook-integration`). Polling works as a fallback and on the success page:

```typescript
// /thanks?sessionId=...
const checkout = await agentaos.checkouts.retrieve(sessionId);
if (checkout.metadata.customerId !== currentUser.id) return notFound();
if (checkout.status === 'completed') {
  await grantAccessOnce(sessionId, currentUser.id, checkout.metadata.subscriptionId);
}
// 'open' => show "Still processing" with a refresh; 'expired' | 'cancelled' => offer to retry
```

The create and list responses carry `amount_override` (null unless set), not a computed `amount`. Retrieve returns a computed `amount`, plus `transactions` and `invoices`.

List and cancel:

```typescript
const page = await agentaos.checkouts.list({ status: 'completed', limit: 10, offset: 0 });
await agentaos.checkouts.cancel(sessionId); // only while 'open'; a payment already in flight can still complete
```

```bash
curl "https://api.agentaos.ai/api/v1/gateway/sessions?status=completed&limit=10" -H "x-api-key: $AGENTAOS_API_KEY"
curl -X POST https://api.agentaos.ai/api/v1/gateway/sessions/<sessionId>/cancel -H "x-api-key: $AGENTAOS_API_KEY"
```

---

## Embedded checkout

The same checkout on your page. VAT, trials, discount codes and 3D Secure work as on the hosted page. Browser only.

Before you start:

1. **Settings, Developers, Approved sites**: add each origin, for example `https://acme.com`. Test products also load on `localhost` and `127.0.0.1` without being added. Live products load only on approved sites.
2. **Settings, Business, Checkout appearance**: button color, font, corners, background.

**Script tag**

```html
<script src="https://app.agentaos.ai/v1/agentaos.js"></script>
<div id="checkout"></div>
<script>
  const checkout = AgentaOS.checkout.open({
    link: 'https://app.agentaos.ai/pay/<token>',
    target: '#checkout',            // omit for an overlay
    onEvent: (e) => console.log(e.name, e.data),
  });
</script>
```

**npm**

```bash
pnpm add @agentaos/checkout
```

```typescript
import { loadAgentaOS } from '@agentaos/checkout';
const agentaos = await loadAgentaOS(); // null on the server
agentaos?.checkout.open({ link, target: '#checkout', onEvent });
```

**React**

```tsx
import { AgentaOSCheckout, useAgentaOSCheckout } from '@agentaos/checkout/react';

// Inline; changing `link` (Monthly/Yearly toggle) updates the open checkout
<AgentaOSCheckout link={yearly ? YEARLY_LINK : MONTHLY_LINK} email={user.email} onEvent={onEvent} />

// Overlay from a button
const { open } = useAgentaOSCheckout();
<button onClick={() => open({ link: STARTER_LINK })}>Buy</button>
```

Options: `link` or `session` (a server-created `sessionId`, use for logged-in users), `target`, `email`, `country`, `successUrl` (`string` or `false` to stay on the page), `onEvent`. `open()` returns `{ update({ link | session }), close() }`.

Events:

| `name` | `data` |
|--------|--------|
| `checkout.loaded` | `{ product: { name, type, billingInterval, trialDays }, currency, testMode }` |
| `checkout.completed` | `{ sessionId, kind: 'payment' \| 'trial' \| 'bank_transfer', email, amountMinor, currency, successUrl }` |
| `checkout.closed` | `{}` |
| `checkout.error` | `{ code: 'not_loaded' \| 'not_found' \| 'unavailable', message }` |

`not_loaded` after 10 seconds usually means the site is not approved. A bank transfer never navigates the page, because the buyer needs the bank details on screen. A browser event is never proof of payment: confirm with the webhook or `checkouts.retrieve()`, once per `sessionId` (a reload of a finished checkout sends `checkout.completed` again).

---

## Discount codes at checkout

Buyers type a code in the checkout's **Discount code** field. Codes are created in the dashboard, CLI (`agenta discounts create`) or MCP. On a subscription, the discount applies to the first invoice only. See https://docs.agentaos.ai/payments/discount-codes.

---

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Passing `type: 'subscription'` to `checkouts.create()` | No such field. Create a subscription product and pass its `linkId` |
| `linkId` set to the `/pay/<token>` | Use the product `id` (UUID), dashboard **Copy ID** |
| One product per buyer | One product per price; one checkout per buyer |
| Creating a checkout on every page render | Create on click; 60 `POST /gateway/sessions` per minute per IP, shared |
| Retrying `POST /gateway/payment-links` blindly | It is not idempotent; list first |
| Unlocking on `checkout.completed` browser event or the redirect | Verify server side |
| `http://localhost` as `successUrl` | Must be `https://`; use an https tunnel or `https://127.0.0.1` with a local cert |
| Expecting a plain `amount` on the create response | Create returns `amount_override`; call retrieve for the computed `amount` |
| Embedding on an unapproved origin | Add it under Approved sites |

## Docs

- Checkouts (concept): https://docs.agentaos.ai/payments/checkouts
- Products and payment links: https://docs.agentaos.ai/payments/payment-links
- SDK checkouts: https://docs.agentaos.ai/sdk/pay-checkouts
- SDK payment links: https://docs.agentaos.ai/sdk/pay-payment-links
- API, create a payment link: https://docs.agentaos.ai/api-reference/payment-links/create
- API, create a checkout: https://docs.agentaos.ai/api-reference/checkouts/create
- API, retrieve a checkout: https://docs.agentaos.ai/api-reference/checkouts/retrieve
- Embedded checkout: https://docs.agentaos.ai/payments/embedded-checkout
- Paywall demo for logged-in users: https://docs.agentaos.ai/sdk/paywall-for-logged-in-users
