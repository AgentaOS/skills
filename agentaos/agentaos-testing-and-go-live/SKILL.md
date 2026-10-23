---
name: agentaos-testing-and-go-live
description: AgentaOS test mode and production launch, covering sk_test_ vs sk_live_ keys, the dashboard Test/Live switch, test cards (4242 success, 0002 decline, 9995 insufficient funds, 3155 3D Secure, 0259 dispute), test invoices, receipts and emails, test webhooks and the livemode field, tunnels for local webhooks, embedding on localhost, business verification, Copy to live for products, live buyer links, deploying the live key, and a pre-launch checklist. Use when testing payment flows end to end, simulating declines or disputes, preparing to accept real money, or debugging why live payments do not work.
---

# AgentaOS Testing and Go-Live

Test mode is a full copy of AgentaOS with test money: products, checkouts, invoices, receipts, emails and webhooks all work, and nothing real moves. Every new account starts in test mode and needs no business verification there. Going live means: verify the business, copy products to live, swap the key.

## When to use this skill

- Writing or running end-to-end tests of a checkout and webhook flow
- Simulating a decline, 3D Secure, or a dispute
- Receiving test webhooks on a local machine
- Preparing the launch checklist
- Debugging "it works in test but not in live"

---

## Test vs live

| | Test | Live |
|--|------|------|
| API key prefix | `sk_test_` | `sk_live_` |
| Money | None | Real |
| Business verification | Not needed | Required |
| Data | Test only | Live only |
| Webhook `livemode` | `false` | `true` |

- One base URL for both. The key decides the mode.
- Test and live data are fully separate. A test product, checkout, customer or invoice is invisible in live, and an id from the other mode returns `404`.
- Dashboard: the **Test / Live** switch is at the bottom of the sidebar. In test mode a strip says "Test mode · No real payments are processed".
- Create a test key: switch to **Test**, **Developers, API keys**, **Generate Test Key**.

---

## Test cards

Use any future expiry and any CVC. Type or paste them only into the card field of the checkout page; never send a card number to the API, a script or support.

| Card | Result |
|------|--------|
| `4242 4242 4242 4242` | Payment succeeds |
| `4000 0000 0000 0002` | "Your card has been declined." |
| `4000 0000 0000 9995` | Declined, insufficient funds |
| `4000 0025 0000 3155` | 3D Secure challenge. Complete it: success. Fail it: "Your bank couldn't confirm it's you." |
| `4000 0000 0000 0259` | Succeeds, then the buyer's bank disputes it later (use it to test `dispute.created`) |

A test checkout shows a banner: "Test payment · 4242 4242 4242 4242 · any expiry · any CVC".

## Test documents

- Success page: "Test payment: no money was paid. This invoice and receipt are not valid."
- Invoice PDF: **TEST** badge, "TEST MODE: not a tax invoice. No money was paid.", number starts with `TEST-`.
- Receipt PDF: **TEST** badge, "TEST MODE: not a valid receipt."
- Emails: subject starts with `[TEST]`.

---

## End-to-end test plan

### 1. One-time product

```bash
export AGENTAOS_API_KEY=sk_test_...

curl -X POST https://api.agentaos.ai/api/v1/gateway/payment-links \
  -H "x-api-key: $AGENTAOS_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"Test Kit","amount":9,"currency":"EUR","successUrl":"https://<your-tunnel>/thanks"}'
# open checkoutUrl, pay with 4242...
```

Expect: redirect to `/thanks?sessionId=...`, `checkout.session.completed` at your webhook with `livemode: false`, an invoice in the dashboard with a TEST badge.

### 2. Server-created checkout with metadata

```typescript
const checkout = await agentaos.checkouts.create({
  linkId: TEST_LINK_ID,
  buyerEmail: 'qa+1@example.com',
  metadata: { customerId: 'test-user-1' },
});
// pay it, then:
const after = await agentaos.checkouts.retrieve(checkout.sessionId);
assert(after.status === 'completed');
assert(after.metadata.customerId === 'test-user-1');
```

### 3. Subscription with trial

Create a plan with `trialPeriodDays`, subscribe with `4242`. Expect `subscription.created` with `status: "trialing"` and `checkout.session.completed` with `amount: "0"` and `trial: true`. `subscriptions.list()` shows `trialing`, `currentPeriodEnd` = trial end. The docs do not describe a way to fast-forward a trial or a renewal in test mode, so test renewal handling by signing sample events yourself (step 6).

### 4. Declines and 3D Secure

Pay with `...0002`, `...9995` and `...3155`. Expect no `checkout.session.completed` for the declines, and your app shows no access.

### 5. Dispute

Pay with `4000 0000 0000 0259`. Disputes are picked up by a background check (about every 10 minutes). Expect `dispute.created` with `status` such as `needs_response`.

### 6. Webhook handler unit tests

Sign your own payloads with the test secret so tests do not depend on delivery:

```typescript
import { createHmac } from 'node:crypto';

export function signForTest(body: object, secret: string) {
  const raw = JSON.stringify(body);
  const t = Math.floor(Date.now() / 1000);
  const v1 = createHmac('sha256', secret).update(`${t}.${raw}`).digest('hex');
  return { raw, header: `t=${t},v1=${v1}` };
}

// renewal: no customerId, has subscriptionId + subscriptionCycle
const { raw, header } = signForTest({
  id: 'evt_test_1',
  type: 'checkout.session.completed',
  business: 'biz',
  data: {
    session_id: 's_renewal_1', amount: '29.00', currency: 'EUR', livemode: false,
    metadata: { subscriptionId: 'sub-uuid', subscriptionCycle: true },
  },
}, process.env.AGENTAOS_WEBHOOK_SECRET!);
// POST raw with X-AgentaOS-Signature: header => expect 200, and 200 again with no second grant
```

Also assert: a wrong signature returns `400`, a replay of the same `session_id` does not grant twice.

### 7. Real delivery to your machine

AgentaOS does not deliver to `localhost` or private addresses. Expose your server with a public HTTPS tunnel, set the tunnel URL in **Settings, Developers, Webhooks**, then click **Send test event** (`webhook.test`). Failed deliveries show in the same screen and can be resent with **Retry webhook**.

### 8. Embedded checkout locally

Test products' embedded checkout loads on `localhost` and `127.0.0.1` on any port, over http or https, without adding them to Approved sites.

---

## Go live

### 1. Verify the business

Dashboard **Go live** page: **Create your first product** (done after a paid test checkout), **Verify your business**, **Go live**. The form takes about 5 minutes and asks for legal name, registration number (companies), address, and a live page where buyers can see the price. A person reviews it, usually within 24 to 48 hours. CLI equivalent: `agenta verify declaration`, `agenta verify submit ...`, `agenta verify status`. MCP: `agenta_verify_submit`.

### 2. Switch to live

When verified, click **Go live** on the Go live page, or use the sidebar switch.

### 3. Copy products to live

Products do not move by themselves. For each product: switch to **Test**, open it, click **Copy to live**. The live copy keeps name, price, description, image, tax setting, success and cancel URLs and trial, but gets a new buyer link and a new id. A product's own `webhookUrl` is not copied. Later edits to the test product do not reach the live copy.

Then update your config: live `linkId` values and live buyer links everywhere (site, emails, social).

### 4. Deploy the live key

Switch the dashboard to **Live**, **Developers, API keys**, **Generate Live Key** (`sk_live_`). Replace the test key in your production environment. Code does not change.

### 5. Bank account and identity check

Not needed for the first sale. Needed before the first payout: add a bank account (**Balances, Payout accounts**) and complete the identity check (owner or admin, live mode).

### What changes for buyers

- Real cards are charged; test cards stop working.
- The card statement shows `AGENTAOS*` plus your business name.
- Invoices, receipts and emails lose the TEST markings.

---

## Pre-launch checklist

- [ ] Business verified (`agenta status --json` shows `goLive.canGoLive: true`)
- [ ] Each product copied to live; live `linkId`s in production config
- [ ] Live buyer links replace test links everywhere
- [ ] `sk_live_` key deployed; no `sk_test_` key in production
- [ ] `successUrl`, `cancelUrl`, `webhookUrl` are `https://` URLs on the live site
- [ ] Webhook handler verifies the signature on the raw body
- [ ] Handler ignores `livemode: false` on the live server
- [ ] Dedupe on `sessionId` with a unique constraint
- [ ] Access is never granted from the redirect alone
- [ ] Renewals matched by stored `subscriptionId`
- [ ] Production origin added to Approved sites (if embedding)
- [ ] Bank account added before the first payout
- [ ] Pricing reviewed: see https://agentaos.ai/pricing

---

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Live key with test `linkId`s | Copy products to live and use the new ids; a test id returns `404` with a live key |
| Sharing the test buyer link after launch | Live copies have new links |
| Fulfilling test events on the live server | Check `livemode` |
| Expecting webhooks at `http://localhost` | Use a public HTTPS tunnel |
| `successUrl` on `http://` | https only |
| Expecting the product's `webhookUrl` to carry over | It is not copied; live events go to the account webhook URL |
| Waiting on a bank account to launch | Not required to sell; required before payout |

## Docs

- Test mode and testing: https://docs.agentaos.ai/getting-started/test-mode
- Go live: https://docs.agentaos.ai/guides/go-live
- Verify your business: https://docs.agentaos.ai/mor/verification
- Webhooks: https://docs.agentaos.ai/payments/webhooks
- Quickstart: https://docs.agentaos.ai/getting-started/quickstart
- Payouts: https://docs.agentaos.ai/payouts/overview
