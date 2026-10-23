---
name: agentaos-subscription-integration
description: AgentaOS subscriptions, covering subscription products (type subscription, billingInterval month or year, trialPeriodDays), how a subscription is created by the buyer at checkout (no create endpoint), linking it to your user via metadata.subscriptionId, statuses (trialing, active, past_due, unpaid, canceled and more), access gating, free and paid trials, upgrade and downgrade with plan-change preview and prorationDate, cancel at period end and resume, subscriber credits, per-subscription invoices, and renewal webhooks. Use when selling a monthly or yearly plan, building a paywall, handling trials, renewals or failed payments, or adding cancel and upgrade buttons; use agentaos-checkout-integration to start the purchase.
---

# AgentaOS Subscription Integration

A subscription starts when a buyer pays a subscription product on the checkout. AgentaOS, as merchant of record, then charges the buyer every cycle, adds VAT where owed, and issues an invoice and receipt per cycle. Your job: link the subscription to your user, gate access on its status, and offer cancel and plan change.

## When to use this skill

- Creating monthly or yearly plans, with or without a free trial
- Linking a new subscription to a user in your database
- Gating features on subscription status
- Handling renewals, failed renewals and cancellations from webhooks
- Building upgrade, downgrade, cancel and resume actions
- Giving a subscriber credit against their next invoice

---

## Core concepts

- **No create.** There is no `subscriptions.create()` and no `POST /gateway/subscriptions`. A buyer paying a `type: 'subscription'` product creates it.
- **The link to your user is `subscriptionId`.** It arrives as `metadata.subscriptionId` on the first `checkout.session.completed` (and on `checkouts.retrieve()`). Store it. Renewal events and `subscriptions.list()` do not carry your `metadata`.
- **No retrieve by id.** Page through `subscriptions.list()` and match on `id`.
- **Trials belong to the product**, set with `trialPeriodDays`.
- **Plan changes stay in one currency and one interval.** Monthly EUR to monthly EUR only.
- **Amounts on subscriptions are minor units**: `unitAmountMinor: 1999` = EUR 19.99, tax included.
- **Every field on subscriptions is camelCase** on the wire too.

### Statuses

| Status | Meaning | Grant access? |
|--------|---------|---------------|
| `trialing` | In a trial, card saved, nothing charged yet | Yes |
| `active` | Billing normally | Yes |
| `past_due` | A renewal charge failed and is being retried | Your choice (grace period) |
| `unpaid` | Renewal retries exhausted | No |
| `canceled` | Ended, no more charges | No |
| `paused` | Billing paused | No |
| `incomplete` | First payment not completed yet | No |
| `incomplete_expired` | First payment never completed | No |

Status is read from the card processor on a schedule (every 5 minutes for subscriptions), so a change appears after the next check. Webhook events never carry `incomplete` or `incomplete_expired`.

---

## Step 1: Create the plans (once)

**SDK**

```typescript
import { AgentaOS } from '@agentaos/pay';
const agentaos = new AgentaOS(process.env.AGENTAOS_API_KEY!);

const pro = await agentaos.paymentLinks.create({
  name: 'Pro',
  amount: 29,                 // currency units, before VAT
  currency: 'EUR',
  type: 'subscription',
  billingInterval: 'month',   // 'month' | 'year', required for subscription
  trialPeriodDays: 14,        // optional, 1 to 730
});
// pro.id => PRO_LINK_ID, pro.checkoutUrl => buyer link
```

**cURL**

```bash
curl -X POST https://api.agentaos.ai/api/v1/gateway/payment-links \
  -H "x-api-key: $AGENTAOS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"Pro","amount":29,"currency":"EUR","type":"subscription","billingInterval":"month","trialPeriodDays":14}'
```

**CLI**

```bash
agenta products create --name "Pro" -a 29 -c EUR --subscription --interval month --trial-days 14 --json
```

Make one product per price and interval: "Pro monthly" and "Pro yearly" are two products. For upgrades, create the higher plan in the same currency and interval.

A paid trial (a price for the whole trial period) is set with **Trial price** on the product in the dashboard. The API reference for `POST /gateway/payment-links` does not list a trial price field.

---

## Step 2: Check out a logged-in user

```typescript
const checkout = await agentaos.checkouts.create({
  linkId: process.env.PRO_LINK_ID!,
  buyerEmail: user.email,
  metadata: { customerId: user.id },
  successUrl: 'https://yourapp.com/billing/success',
});
return redirect(checkout.checkoutUrl);
```

Do not send logged-in users the plan's `/pay/` buyer link: it carries no `metadata`.

---

## Step 3: Store the subscription id

From the webhook (preferred; see `agentaos-webhook-integration`):

```typescript
if (event.type === 'checkout.session.completed') {
  const { sessionId, metadata } = event.data;
  const subscriptionId = typeof metadata.subscriptionId === 'string' ? metadata.subscriptionId : null;

  if (typeof metadata.customerId === 'string') {
    // First payment or trial start: your metadata is present
    await grantOnce(sessionId, () =>
      db.users.update(metadata.customerId, { subscriptionId, plan: 'pro' }),
    );
  } else if (subscriptionId) {
    // Renewal, first charge after a trial, or upgrade charge: AgentaOS's own metadata
    await grantOnce(sessionId, () => recordRenewal(subscriptionId));
  }
}
```

Or from the success page with `checkouts.retrieve(sessionId)` once `status === 'completed'`. For a free-trial checkout, `status` may stay `open` for a short time before turning `completed`.

---

## Step 4: Gate access

```typescript
import type { Subscription } from '@agentaos/pay';

export async function findSubscription(id: string | null): Promise<Subscription | null> {
  if (!id) return null;
  for (let offset = 0; ; offset += 100) {
    const page = await agentaos.subscriptions.list({ limit: 100, offset });
    const found = page.items.find((s) => s.id === id);
    if (found) return found;
    if (!page.hasMore) return null;
  }
}

export function hasAccess(sub: Subscription | null): boolean {
  return sub?.status === 'active' || sub?.status === 'trialing';
}
```

Paging through every subscription on each request is expensive and counts against the 60 requests per minute limit. Cache the status on your user and update it from `subscription.*` webhooks; read the API as a fallback.

Useful fields: `id`, `status`, `planName`, `billingInterval`, `unitAmountMinor`, `currency`, `currentPeriodEnd` (next charge, or trial end while trialing), `cancelAtPeriodEnd`, `effectiveCancelDate`, `canceledAt`, `pendingPlanChange` (`{ linkId, planName, unitAmountMinor, effectiveAt }` when a downgrade waits), `linkId` (current plan UUID), `discount` (`{ code, kind }`), `customerEmail`, `customerName`.

```bash
curl "https://api.agentaos.ai/api/v1/gateway/subscriptions?limit=100&offset=0" \
  -H "x-api-key: $AGENTAOS_API_KEY"
```

`subscriptions.list({ discountCode: 'LAUNCH20' })` filters to subscribers who used a code (CLI: `agenta subscriptions list --code LAUNCH20`).

---

## Webhook events for subscriptions

| What happens | Events |
|--------------|--------|
| Buyer pays the first period | `subscription.created` + `checkout.session.completed`, either order |
| Buyer starts a free trial | `subscription.created` (`status: "trialing"`) + `checkout.session.completed` with `amount: "0"`, `trial: true`, `trial_end` |
| Buyer starts a trial with a trial price | `subscription.created` + `checkout.session.completed` with the amount charged, no `trial` field |
| Trial ends and first charge succeeds | `checkout.session.completed` + `subscription.renewed` |
| Later period paid | `checkout.session.completed` + `subscription.renewed` |
| Renewal charge fails | `subscription.payment_failed` (status `past_due` or `unpaid`) |
| Cancel scheduled or resumed, plan changed | `subscription.updated` |
| Subscription ends | `subscription.canceled` |

All `subscription.*` events share one `data` shape: `id`, `status`, `plan_name`, `currency`, `amount_minor`, `current_period_end`, `cancel_at_period_end`, `link_id` (UUID), `pending_plan`, `discount`, `customer_email`, `customer_name`, `livemode`. The SDK returns them camelCased. Events can arrive out of order: store `subscription.updated` as the latest state, and treat a trial start (`amount: "0"`) as "trial started", not money received.

Recommended handling:

```typescript
switch (event.type) {
  case 'subscription.renewed':
    await db.subscriptions.extend(event.data.id, event.data.currentPeriodEnd);
    break;
  case 'subscription.payment_failed':
    await notifyUpdateCard(event.data.id, event.data.customerEmail); // your own email
    break;
  case 'subscription.updated':
  case 'subscription.canceled':
    await db.subscriptions.setStatus(event.data.id, event.data.status, event.data.cancelAtPeriodEnd);
    break;
}
```

AgentaOS sends no card-update link or hosted customer portal. Tell the subscriber in your own email or UI.

---

## Plan changes (upgrade, downgrade, revert)

Always quote first, show the quote, then apply with the quote's `prorationDate` so the charge equals the quote.

**SDK**

```typescript
const quote = await agentaos.subscriptions.previewPlanChange(subscriptionId, PRO_PLUS_LINK_ID);
// quote.direction: 'upgrade' | 'downgrade' | 'revert'
// quote.dueTodayMinor, quote.dueTodayVatMinor, quote.effectiveAt
// quote.nextInvoiceMinor, quote.nextInvoiceVatMinor, quote.nextInvoiceAt, quote.prorationDate

const result = await agentaos.subscriptions.changePlan(subscriptionId, {
  targetLinkId: PRO_PLUS_LINK_ID,
  prorationDate: quote.prorationDate,
});
```

**cURL**

```bash
curl "https://api.agentaos.ai/api/v1/gateway/subscriptions/$SUB_ID/plan-change/preview?targetLinkId=$PRO_PLUS_LINK_ID" \
  -H "x-api-key: $AGENTAOS_API_KEY"

curl -X POST "https://api.agentaos.ai/api/v1/gateway/subscriptions/$SUB_ID/plan-change" \
  -H "x-api-key: $AGENTAOS_API_KEY" -H "Content-Type: application/json" \
  -d '{"targetLinkId":"'$PRO_PLUS_LINK_ID'","prorationDate":1788434542}'
```

**CLI** (quote and apply in one command)

```bash
agenta subscriptions change-plan <subscriptionId> --to <linkId> --dry-run --json
agenta subscriptions change-plan <subscriptionId> --to <linkId> --json
```

- **Upgrade** (new plan costs more): the prorated difference is charged on the saved card now, the new price applies at once. During a free trial the amount due today is 0.
- **Downgrade** (same or lower price): nothing charged today. The switch happens at `effectiveAt` (period end). Until then the subscription shows `pendingPlanChange`; keep gating on the current plan.
- **Revert**: change to the current plan while a downgrade is pending. Nothing charged, `pendingPlanChange` becomes null. Targeting the plan that is already pending returns `400` ("already scheduled").
- Requires `active` or `trialing`, same currency, same interval. Otherwise `400`.
- While the buyer has unspent credit, preview and change return `400` until the next invoice.
- Each change fires `subscription.updated`.

---

## Cancel and resume

```typescript
const res = await agentaos.subscriptions.cancel(subscriptionId);
// { status: 'active', cancelAtPeriodEnd: true, effectiveCancelDate: '2026-09-06', currentPeriodEnd: '...' }
```

```bash
curl -X POST "https://api.agentaos.ai/api/v1/gateway/subscriptions/$SUB_ID/cancel" \
  -H "x-api-key: $AGENTAOS_API_KEY"

# Undo a scheduled cancel before the period ends
curl -X POST "https://api.agentaos.ai/api/v1/gateway/subscriptions/$SUB_ID/resume" \
  -H "x-api-key: $AGENTAOS_API_KEY"
```

- Cancel takes effect at the end of the current period. The subscriber keeps access until then. Nothing is refunded. A repeat call is a no-op.
- Build for period-end cancellation. The SDK, CLI, dashboard and paywall demo docs state there is no immediate cancel; the API reference mentions an `atPeriodEnd: false` body field. Do not rely on immediate cancellation.
- Cancel returns `400` if the subscription never completed a first charge.
- Resume is only valid while a cancel is scheduled; otherwise `400`. The SDK reference does not document a `resume()` method, so call the REST endpoint.
- Cancel fires `subscription.updated` right away, and `subscription.canceled` when the period ends. Resume fires `subscription.updated`.

---

## Credits

A credit lowers the subscriber's next invoice. It is not a refund: no money goes back to the card.

- Only an owner or admin from a signed-in session (dashboard, `agenta login`, or MCP connection) can give or list credits. **An API key is refused with `403`**, so a backend using `sk_...` cannot do this.
- `amountMinor` is integer minor units of the subscription's currency, at most the next invoice.
- `POST /gateway/subscriptions/{id}/credits` requires an `Idempotency-Key`. Reuse the same key on retry; a new key gives a second credit.
- The subscription must be `active` or `trialing`, not scheduled to cancel, with no pending plan change.
- Unspent credit belongs to the buyer and is shared by all their subscriptions with you.

```bash
agenta subscriptions credit <subscriptionId> -a 10 --reason "Two days of downtime" --json
agenta subscriptions credits <subscriptionId> --json
```

---

## Invoices for one subscription

```typescript
const invoices = await agentaos.subscriptions.invoices(subscriptionId); // newest first, latest 100
// { id, invoiceNumber, status, issuedAt, amount (currency units), currency, disputed, chargedBack }

const pdf = await agentaos.invoices.downloadPdf(invoices[0].id);   // Buffer
const receipt = await agentaos.invoices.getReceipt(invoices[0].id); // Buffer
```

Check the invoice belongs to the signed-in user's subscription before streaming the PDF. A subscription in a free trial has no invoice until the first charge.

---

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Calling `subscriptions.create()` | Does not exist. Buyer pays a subscription product |
| Matching renewals by `metadata.customerId` | Renewals carry AgentaOS metadata. Match by `metadata.subscriptionId` |
| Treating the trial-start event as revenue | `amount: "0"` and `trial: true` mean trial started |
| Gating on `pendingPlanChange` | Gate on the current `planName` / `linkId` until `effectiveAt` |
| Applying a plan change without a quote | Preview, show the amounts, apply with `prorationDate` |
| Changing between monthly and yearly | Not supported as a plan change; same interval and currency only |
| Giving credits with an API key | Session only; use the dashboard, CLI or MCP |
| Promising a refund on cancel | Cancel never refunds; refunds are a separate request (see `agentaos-refunds-and-disputes`) |
| Building a "manage billing" link to a hosted portal | There is none; build cancel and upgrade with the API |
| Mixing units | `unitAmountMinor` is minor units; invoice `amount` is currency units; webhook `amount` is a string |

## Docs

- Subscriptions (concept): https://docs.agentaos.ai/payments/subscriptions
- SDK subscriptions: https://docs.agentaos.ai/sdk/pay-subscriptions
- Sell a subscription (guide): https://docs.agentaos.ai/guides/sell-a-subscription
- API, list subscriptions: https://docs.agentaos.ai/api-reference/subscriptions/list
- API, preview a plan change: https://docs.agentaos.ai/api-reference/subscriptions/plan-change-preview
- API, change the plan: https://docs.agentaos.ai/api-reference/subscriptions/plan-change
- API, cancel: https://docs.agentaos.ai/api-reference/subscriptions/cancel
- API, resume: https://docs.agentaos.ai/api-reference/subscriptions/resume
- API, credits: https://docs.agentaos.ai/api-reference/subscriptions/credits-create
- API, subscription invoices: https://docs.agentaos.ai/api-reference/subscriptions/invoices
- Event order for subscriptions: https://docs.agentaos.ai/webhooks/events#event-order-for-subscriptions
- Paywall demo: https://docs.agentaos.ai/sdk/paywall-for-logged-in-users
