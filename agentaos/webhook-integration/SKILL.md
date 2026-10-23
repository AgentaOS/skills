---
name: webhook-integration
description: AgentaOS webhook handling, covering endpoint registration in Settings, Developers, Webhooks, the whsec_ signing secret, X-AgentaOS-Signature (t=,v1= HMAC-SHA256 over the raw body) verification with agentaos.webhooks.verify() from @agentaos/pay or by hand in any language, the 12 event types (checkout.session.completed, subscription.created, renewed, updated, payment_failed, canceled, dispute.created, closed, send.completed, send.failed, account.updated, webhook.test), payload fields, per-event deduplication keys, delivery and retries, livemode checks, and local testing through a tunnel. Use when receiving AgentaOS events, verifying signatures, fulfilling orders, or syncing subscription state.
---

# AgentaOS Webhook Integration

AgentaOS POSTs a signed JSON event to your server when money or account state changes. Build fulfillment on webhooks, not on the browser redirect: the buyer can close the tab before the redirect fires.

## When to use this skill

- Setting up the endpoint that receives AgentaOS events
- Verifying `X-AgentaOS-Signature`
- Unlocking access on `checkout.session.completed`
- Tracking renewals, failed payments, plan changes and cancellations
- Making the handler safe against retries and duplicates
- Testing webhooks locally

---

## Core concepts

- **Raw body.** The signature is computed over the exact bytes received. Parse JSON only after verification.
- **One secret per account.** `whsec_...`, from **Settings, Developers, Webhooks**, **Reveal signing secret**. It stays the same when you change the URL. **Rotate secret** invalidates the old one immediately.
- **One account URL**, plus an optional per-checkout or per-link `webhookUrl` that receives only that payment's `checkout.session.completed`.
- **Test and live events go to the same endpoint.** Check `data.livemode`.
- **At-least-once delivery.** Deduplicate.

---

## Step 1: Register the endpoint

1. Open https://app.agentaos.ai, **Settings, Developers, Webhooks**.
2. Enter an HTTPS URL, for example `https://myshop.com/webhooks`, click **Save**.
3. Click **Reveal signing secret**, copy `whsec_...`.
4. Store it as `AGENTAOS_WEBHOOK_SECRET`. Never commit, log or send it to a client.

AgentaOS refuses `localhost` and private addresses (`10.0.0.0/8`, `192.168.0.0/16` and similar) without attempting delivery. For local development, expose your server with a public HTTPS tunnel and register the tunnel URL.

Per-payment URL (optional):

```typescript
await agentaos.checkouts.create({ linkId, webhookUrl: 'https://myshop.com/webhooks/orders' });
```

Routing of `checkout.session.completed`: the checkout's `webhookUrl`, else its payment link's, else the account URL. Only the first match receives it. Every other event goes to the account URL. If no URL applies, nothing is sent and no error shows.

---

## Step 2: Verify the signature

Header format:

```
X-AgentaOS-Signature: t=1770379200,v1=5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd
```

`v1` is the hex HMAC-SHA256 of `{t}.{raw body}` keyed with the signing secret.

### SDK (Express)

```typescript
import express from 'express';
import { AgentaOS, WebhookVerificationError } from '@agentaos/pay';

const agentaos = new AgentaOS(process.env.AGENTAOS_API_KEY!);
const app = express();

// express.raw() on this route only, BEFORE any JSON parser
app.post('/webhooks', express.raw({ type: 'application/json' }), async (req, res) => {
  let event;
  try {
    event = agentaos.webhooks.verify(
      req.body,                                      // raw Buffer or string
      req.headers['x-agentaos-signature'] as string,
      process.env.AGENTAOS_WEBHOOK_SECRET!,
      // toleranceSec, default 300
    );
  } catch (err) {
    if (err instanceof WebhookVerificationError) return res.status(400).send('Invalid signature');
    return res.status(500).send('Webhook processing failed');
  }

  await handleEvent(event); // store or enqueue quickly
  res.sendStatus(200);
});

app.use(express.json()); // other routes
```

`verify()` runs locally, no network call. It parses `t` and `v1`, rejects a timestamp older than `toleranceSec` or in the future by any amount, compares in constant time, then returns the event with every key camelCased (including keys inside `metadata`). Any failure throws `WebhookVerificationError`. Keep the server clock synced with NTP, or every event fails.

### Manual (Node, no SDK)

```typescript
import { createHmac, timingSafeEqual } from 'node:crypto';

export function verifyAgentaOS(rawBody: string, header: string, secret: string, toleranceSec = 300): boolean {
  const parts = Object.fromEntries(header.split(',').map((p) => p.split('=', 2) as [string, string]));
  const t = Number(parts.t);
  if (!t || !parts.v1) return false;
  const age = Math.floor(Date.now() / 1000) - t;
  if (age < 0 || age > toleranceSec) return false;
  const expected = createHmac('sha256', secret).update(`${t}.${rawBody}`).digest('hex');
  const a = Buffer.from(expected);
  const b = Buffer.from(parts.v1);
  return a.length === b.length && timingSafeEqual(a, b);
}
```

### Python

```python
import hmac, hashlib, time

def verify_webhook(body: str, signature: str, secret: str, tolerance_sec: int = 300) -> bool:
    parts = dict(p.split("=", 1) for p in signature.split(","))
    timestamp = int(parts["t"])
    age = int(time.time()) - timestamp
    if age < 0 or age > tolerance_sec:
        return False
    expected = hmac.new(secret.encode(), f"{timestamp}.{body}".encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, parts["v1"])
```

Go and PHP versions are on https://docs.agentaos.ai/payments/webhooks. Always use a constant-time compare.

Manual verification returns snake_case keys (`session_id`, `link_id`). The SDK returns camelCase (`sessionId`, `linkId`).

---

## Step 3: Handle events

| Event | Fires when | Do |
|-------|------------|----|
| `checkout.session.completed` | A checkout is paid (card, bank transfer, stablecoin); a free trial starts (`amount: "0"`, `trial: true`); a trial with a trial price starts; a renewal, first post-trial charge or upgrade charge succeeds; a credit pays a renewal in full (`amount: "0"`) | Fulfill or unlock |
| `subscription.created` | Subscription becomes `active` or `trialing` for the first time | Store `id` with the user |
| `subscription.renewed` | A charge after the first one succeeds | Extend access to `current_period_end` |
| `subscription.payment_failed` | Status becomes `past_due` or `unpaid` | Ask the subscriber to update their card |
| `subscription.updated` | Cancel scheduled or resumed; upgrade applied; downgrade scheduled, reverted or taking over | Store as latest state |
| `subscription.canceled` | Status becomes `canceled` | Remove access |
| `dispute.created` | AgentaOS finds a new dispute | Mark order disputed; reply to the dispute email with evidence |
| `dispute.closed` | A dispute closes in your favor (a lost dispute sends no event) | Clear the disputed mark |
| `send.completed` / `send.failed` | An outbound stablecoin send you started confirms or fails | Mark payout paid / retry |
| `account.updated` | A business's verification changes (live mode only) | Show the next step from `verification` |
| `webhook.test` | **Send test event** in the dashboard | Confirm your endpoint verifies it |

Envelope: `{ id, type, business, data }`. The event `id` stays the same across retries, but the SDK `WebhookEvent` type does not declare `id` yet.

### `checkout.session.completed` data (wire names)

`link_id` (buyer-link token, not the UUID; `null` without a link), `session_id`, `amount` (string), `currency`, `rail` (`card` | `sepa` | `crypto`), `tx_hash`, `vendor_reference`, `payer`, `payer_type` (`human` | `agent`), `customer_id` (AgentaOS's buyer id, not yours), `buyer_email`, `buyer_name`, `network`, `livemode`, `overpaid_by_cents`, `trial` (only on free-trial start), `trial_end`, `metadata`.

The SDK's `CheckoutCompletedData` type does not yet declare `rail`, `vendorReference`, `customerId`, `buyerEmail`, `buyerName`, `overpaidByCents`, `trial`, `trialEnd`, and types `txHash`, `payer`, `linkId` as `string` although they can be `null`. Widen the type:

```typescript
import type { CheckoutCompletedData } from '@agentaos/pay';

type CheckoutCompletedWire = CheckoutCompletedData & {
  customerId: string | null;
  buyerEmail: string | null;
  trial?: true;
  trialEnd?: string | null;
};
```

### A complete handler

```typescript
import type { WebhookEvent } from '@agentaos/pay';

const IS_LIVE_SERVER = process.env.AGENTAOS_API_KEY!.startsWith('sk_live_');

async function handleEvent(event: WebhookEvent) {
  if ('livemode' in event.data && event.data.livemode !== IS_LIVE_SERVER) return; // test vs live

  switch (event.type) {
    case 'checkout.session.completed': {
      const data = event.data as CheckoutCompletedWire;
      const { sessionId, metadata } = data;
      await onceFor(`checkout:${sessionId}`, async () => {
        if (data.trial) return startTrial(metadata.customerId, metadata.subscriptionId);
        if (typeof metadata.customerId === 'string') return grantAccess(metadata.customerId, metadata.subscriptionId);
        if (typeof metadata.subscriptionId === 'string') return recordRenewal(metadata.subscriptionId); // renewal
        return fulfillOrder(sessionId, data.amount);
      });
      break;
    }
    case 'subscription.created':
    case 'subscription.renewed':
    case 'subscription.payment_failed':
    case 'subscription.canceled':
      await onceFor(`${event.type}:${event.data.id}:${event.data.currentPeriodEnd}`, () =>
        syncSubscription(event.data),
      );
      break;
    case 'subscription.updated':
      await syncSubscription(event.data); // no dedupe key: apply as latest state
      break;
    case 'dispute.created':
    case 'dispute.closed':
      await onceFor(`${event.type}:${event.data.disputeId}`, () => markDispute(event.data));
      break;
  }
}
```

`onceFor(key, fn)` is your own helper backed by a table with a unique constraint on `key`.

---

## Deduplication keys

| Event | Key |
|-------|-----|
| `checkout.session.completed` | `data.session_id` |
| `send.completed`, `send.failed` | `data.transaction_id` |
| `subscription.created`, `renewed`, `payment_failed`, `canceled` | `type` + `data.id` + `data.current_period_end` |
| `subscription.updated` | None. Apply as the latest state |
| `dispute.created`, `dispute.closed` | `type` + `data.dispute_id` |

Two events about the same subscription can arrive in either order.

---

## Delivery and retries

- POST with `Content-Type: application/json`, 10-second timeout per attempt.
- Up to 3 attempts, waiting 1 second then 2 seconds. Same signature and `t` on all three.
- Non-`2xx`, timeout, network error and any `3xx` (redirects are not followed) count as failures.
- After 3 failures the event is marked `failed` in **Settings, Developers, Webhooks**. An owner or admin can resend it with **Retry webhook**; the resend is signed again with a new `t`.
- Respond `200` right after verifying and storing. Do emails and external calls afterwards.

---

## Testing

1. Run your server locally and expose it with a public HTTPS tunnel.
2. Register `https://<tunnel>/webhooks` and copy the secret.
3. Click **Send test event**: you should receive `webhook.test` with `message: "Test event from AgentaOS"`.
4. Pay a test checkout with `4242 4242 4242 4242` and watch `checkout.session.completed` arrive.
5. POST a payload with a wrong signature and confirm you return `400`.

You can also sign your own sample payloads with the secret to unit test the route: compute `v1 = HMAC_SHA256(secret, "${t}.${body}")` and send `t=<t>,v1=<v1>`.

---

## Common mistakes

| Mistake | Fix |
|---------|-----|
| `express.json()` or a framework body parser runs before verification | Use the raw body (`express.raw`, `await req.text()`) |
| Re-stringifying parsed JSON to verify | Verify the original bytes |
| `===` to compare signatures | Constant-time compare |
| No dedupe | Unique constraint on the key per event type |
| Unlocking for renewals by `metadata.customerId` | Renewals carry `metadata.subscriptionId` and `subscriptionCycle: true`, not your metadata |
| Using `customer_id` as your user id | It is AgentaOS's id. Put yours in `metadata` |
| Comparing `link_id` from checkout events to your product UUID | Checkout events send the buyer-link token; subscription events send the UUID |
| Waiting for a "dispute lost" event | None is sent |
| Ignoring `livemode` | Test and live share one endpoint |
| Returning `302` to the webhook | Redirects count as failures |
| Server clock drift | Sync with NTP; future timestamps are rejected |

## Docs

- Webhooks (setup, verification in TS, Python, Go, PHP): https://docs.agentaos.ai/payments/webhooks
- Event reference: https://docs.agentaos.ai/webhooks/events
- Signature format: https://docs.agentaos.ai/api-reference/webhooks
- SDK webhooks: https://docs.agentaos.ai/sdk/pay-webhooks
- Receive webhooks in Express: https://docs.agentaos.ai/sdk/handle-webhooks
