---
name: migrate-from-stripe-paddle-lemonsqueezy
description: Moving payments to AgentaOS from Stripe, Paddle, Lemon Squeezy, Creem or Gumroad, covering the @agentaos/migrate CLI (dry run, apply, --switch-code, summary.md, products.csv, skipped.csv, redirects.csv, subscribers.csv) for Paddle, Lemon Squeezy, Creem and Gumroad, a manual path for Stripe, a concept and code mapping (prices to payment links, Checkout Sessions to /gateway/sessions, Stripe-Signature to X-AgentaOS-Signature, customer portal to your own billing page), what moves and what does not (saved cards never move), subscriber cut-over timed to renewal dates, and swapping buy links in code. Use when the user wants to migrate, switch or move products, plans, discount codes, subscribers or code from another billing provider to AgentaOS.
---

# Migrate to AgentaOS

Two paths:

- **Paddle, Lemon Squeezy, Creem, Gumroad**: run `npx @agentaos/migrate`. It reads the old account (GET requests only), never changes or cancels anything there, and creates the products, plans and codes on AgentaOS.
- **Stripe**: the migrate tool does not read Stripe. Recreate products by hand or with a short script, then port the code using the mapping below.

Say this before starting, in plain words: **saved cards do not move.** The old provider holds them and does not hand them over. Each subscriber subscribes once on the new link, timed to their renewal date, so nobody pays twice. Do not promise a card transfer.

## When to use this skill

- "Migrate to AgentaOS", "switch from Paddle", "move off Lemon Squeezy", "leave Gumroad", "replace Stripe Checkout"
- Importing products, plans, trials and discount codes
- Moving active subscribers without double charging
- Porting checkout and webhook code

---

## What moves

| | Paddle / Lemon Squeezy / Creem / Gumroad (tool) | Stripe (manual) |
|--|--|--|
| Products, prices, monthly and yearly plans, trials | Moved | Recreate as payment links |
| Discount codes | Moved where AgentaOS can express them | Recreate with `agenta discounts create` |
| Active subscribers | Listed with plan, renewal date and new link | Export from Stripe yourself |
| Saved cards | Never | Never |
| Quarterly or weekly billing, currencies other than EUR or USD, free or pay-what-you-want products | Left behind in `skipped.csv` with a reason | Not supported on AgentaOS |

AgentaOS plans bill `month` or `year`, in `EUR` or `USD`.

---

## Path A: the migrate tool (Paddle, Lemon Squeezy, Creem, Gumroad)

### 1. Ask which provider, if not stated

### 2. Keys go in the environment, never in the chat or a flag

Ask the user to set them in their own terminal:

| Provider | Env var |
|----------|---------|
| Paddle | `PADDLE_API_KEY` (read permissions) |
| Lemon Squeezy | `LEMONSQUEEZY_API_KEY` |
| Creem | `CREEM_API_KEY` |
| Gumroad | `GUMROAD_ACCESS_TOKEN` |
| AgentaOS | `AGENTAOS_API_KEY` from app.agentaos.ai, **Developers, API keys**. Start with `sk_test_`. |

If the user pastes a key into the chat, do not repeat it, and suggest they rotate it.

### 3. Dry run

```bash
npx @agentaos/migrate --from paddle          # or lemonsqueezy | creem | gumroad
npx @agentaos/migrate --from paddle --test   # Paddle sandbox or Creem test mode
```

### 4. Show the plan

Read `agentaos-migration/summary.md`: how many products, codes and subscribers, and every line of `skipped.csv` with its reason. Ask what to do with each skipped item (usually recreate it by hand on a monthly or yearly cadence, or set a EUR or USD price).

### 5. Apply only after the user says yes

```bash
npx @agentaos/migrate --from paddle --apply
npx @agentaos/migrate --from paddle --apply --switch-code   # if they have subscribers
```

`--switch-code` creates one discount code, capped at the number of subscribers and valid for 60 days, that makes the first AgentaOS invoice free, because subscribers already paid the old provider for the current period. Re-running is safe: it finds what it already created.

### 6. Check it

Open one new link from `products.csv`, pay with `4242 4242 4242 4242`. With MCP connected, `agenta_products_list` (or `agenta products list --json`) shows the new products.

### 7. Swap links in code

`redirects.csv` maps each old buy link to the new one. Search the repo for the old URLs, or the old price or variant ids from `products.csv`, and replace them.

### 8. Move subscribers

`subscribers.csv` has each subscriber's plan, renewal date and new link; `email-to-subscribers.md` has a short email. The user sends it from their own email, a week or two before each renewal. You never send email for them. Rows with a note need a decision first (for example a Gumroad tier).

### 9. Close the loop

When a subscriber pays on AgentaOS, the user cancels that subscriber's old subscription at the end of the paid period, in the old provider's dashboard.

---

## Path B: Stripe (manual)

### 1. Recreate products

One AgentaOS product per Stripe recurring or one-time price you still sell (EUR or USD, monthly or yearly):

```typescript
import { AgentaOS } from '@agentaos/pay';
const agentaos = new AgentaOS(process.env.AGENTAOS_API_KEY!); // sk_test_ first

const plans = [
  { name: 'Pro', amount: 29, interval: 'month' as const, trialDays: 14 },
  { name: 'Pro (annual)', amount: 290, interval: 'year' as const },
];

for (const p of plans) {
  const link = await agentaos.paymentLinks.create({
    name: p.name,
    amount: p.amount,           // currency units, NOT cents (Stripe unit_amount 2900 => 29)
    currency: 'EUR',
    type: 'subscription',
    billingInterval: p.interval,
    ...(p.trialDays ? { trialPeriodDays: p.trialDays } : {}),
  });
  console.log(p.name, link.id, link.checkoutUrl); // save the id as the new price reference
}
```

`POST /gateway/payment-links` is not idempotent: if a run fails halfway, list existing links before re-running.

### 2. Map the concepts

| Stripe | AgentaOS |
|--------|----------|
| Product + Price | Product = payment link (one price each). `id` = `linkId` |
| Payment Link | The product's `checkoutUrl` (buyer link) |
| Checkout Session `stripe.checkout.sessions.create` | `agentaos.checkouts.create()` / `POST /gateway/sessions` |
| `price` / `line_items` | `linkId` (one product per checkout) or `amount` (standalone, one-time) |
| `client_reference_id`, session `metadata` | `metadata` (camelCase keys), returned on `checkout.session.completed` |
| `customer_email` | `buyerEmail` |
| `success_url` with `{CHECKOUT_SESSION_ID}` | `successUrl`; AgentaOS appends `?sessionId=` itself |
| `mode: 'subscription'` | A product with `type: 'subscription'` |
| `trial_period_days` | `trialPeriodDays` on the product |
| Coupons, promotion codes | Discount codes: 1 to 99 percent or a fixed amount, first invoice only on subscriptions |
| `Stripe-Signature` + `constructEvent` | `X-AgentaOS-Signature` + `agentaos.webhooks.verify()` |
| `checkout.session.completed` | `checkout.session.completed` (also fires for renewals and trial starts) |
| `invoice.paid` (renewal) | `subscription.renewed` + `checkout.session.completed` |
| `invoice.payment_failed` | `subscription.payment_failed` |
| `customer.subscription.updated` / `deleted` | `subscription.updated` / `subscription.canceled` |
| `charge.dispute.created` | `dispute.created` |
| `stripe.subscriptions.update` (price change) | `previewPlanChange` then `changePlan` with `prorationDate` |
| `stripe.subscriptions.update({ cancel_at_period_end: true })` | `subscriptions.cancel()` |
| `stripe.refunds.create` | Refund request (full only, reviewed by AgentaOS); see `refunds-and-disputes` |
| Customer Portal | Not available. Build cancel and upgrade into your app |
| Tax (Stripe Tax) | Handled by AgentaOS as merchant of record |
| `sk_test_` / `sk_live_` | Same prefixes, AgentaOS keys |

### 3. Port the checkout

```typescript
// Before (Stripe)
// const session = await stripe.checkout.sessions.create({
//   mode: 'subscription', line_items: [{ price: PRICE_ID, quantity: 1 }],
//   customer_email: user.email, client_reference_id: user.id,
//   success_url: `${APP_URL}/success?session_id={CHECKOUT_SESSION_ID}`,
// });

// After (AgentaOS)
const checkout = await agentaos.checkouts.create({
  linkId: PRO_LINK_ID,
  buyerEmail: user.email,
  metadata: { customerId: user.id },
  successUrl: `${APP_URL}/success`,   // arrives as /success?sessionId=...
});
return redirect(checkout.checkoutUrl);
```

### 4. Port the webhook

```typescript
// Before: stripe.webhooks.constructEvent(rawBody, req.headers['stripe-signature'], whsec)
const event = agentaos.webhooks.verify(
  rawBody,                                   // raw body, same rule as Stripe
  req.headers['x-agentaos-signature'] as string,
  process.env.AGENTAOS_WEBHOOK_SECRET!,
);
```

Differences that bite:

- Renewals arrive as `checkout.session.completed` without your metadata; match them by `metadata.subscriptionId` stored on the first payment.
- Dedupe on `data.sessionId` (the SDK `WebhookEvent` type does not declare the event `id` yet).
- Event keys are camelCased by `verify()`, including metadata keys.
- No `customer` object or `cus_` id to store; store `subscriptionId` and your own user id.
- Amounts: webhook `amount` is a string in currency units; subscription fields ending in `Minor` are minor units.

### 5. Move subscribers

Same cut-over as Path A: export active subscribers from Stripe (plan, email, current period end), email each a new link shortly before their renewal, and cancel the Stripe subscription at period end once they have paid on AgentaOS. Cards stay at Stripe.

A discount code cannot take the whole price off (`percentOff` is 1 to 99). The docs' answer for a free first period is a free trial: for example a separate "switch" plan with `trialPeriodDays`, so subscribers who move early are not charged until their already-paid period ends. Check the trial length against each subscriber's renewal date before sending links.

---

## Going live

Everything works in test mode first. Live money needs the AgentaOS business verified: `agenta status --json` or `agenta_status_get` says what is left. Then re-run Path A step 5 with an `sk_live_` key, or copy test products with **Copy to live** in the dashboard (live copies get new ids and links). See `testing-and-go-live`.

## Card transfer

Moving saved cards directly is only possible between card processors that both agree, takes weeks, and merchant of record providers do not offer it. If the user insists, send them to contact@agentaos.ai. Do not promise it.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Promising cards will move | They never move; subscribers re-subscribe once |
| Applying before the user reviewed `summary.md` and `skipped.csv` | Dry run, review, then `--apply` |
| Keys passed as flags or pasted in chat | Environment variables only |
| Copying Stripe `unit_amount` (cents) into `amount` | Divide by 100: `amount` is currency units |
| Cancelling the old subscription immediately | Cancel at the end of the period they already paid |
| Expecting quarterly or weekly plans | Monthly or yearly only |
| Looking for a hosted customer portal | Build billing actions with `@agentaos/pay` |

## Docs

- Migrate CLI on npm: https://www.npmjs.com/package/@agentaos/migrate
- Products and payment links: https://docs.agentaos.ai/payments/payment-links
- Checkouts: https://docs.agentaos.ai/payments/checkouts
- Webhooks and events: https://docs.agentaos.ai/payments/webhooks, https://docs.agentaos.ai/webhooks/events
- Subscriptions: https://docs.agentaos.ai/payments/subscriptions
- Discount codes: https://docs.agentaos.ai/payments/discount-codes
- Go live: https://docs.agentaos.ai/guides/go-live
