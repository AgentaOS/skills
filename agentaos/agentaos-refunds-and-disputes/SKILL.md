---
name: agentaos-refunds-and-disputes
description: AgentaOS refunds and disputes as merchant of record, covering how a merchant requests a refund (Request refund on the sale page, or POST /gateway/transactions/{id}/refund-request), approval or decline by AgentaOS, full refunds only (no partial refunds), balance effects, the dispute and chargeback lifecycle, dispute.created and dispute.closed webhooks (no event for a lost dispute), sending evidence by replying to the dispute email, the reserve, what is not a refund (cancel, credits, void), and how to avoid disputes. Use when a buyer asks for money back, when handling dispute webhooks, revoking or restoring access after a chargeback, or explaining refund and dispute costs.
---

# AgentaOS Refunds and Disputes

AgentaOS is the merchant of record, so AgentaOS sends every refund and answers every dispute with the buyer's bank. The merchant asks for a refund; AgentaOS approves and executes it. For disputes, the merchant supplies evidence by email; AgentaOS responds to the bank.

This skill covers only what the AgentaOS docs describe. Anything not listed here (partial refunds, refund webhooks, a refund status API, programmatic dispute evidence) is not supported or not documented.

## When to use this skill

- A buyer wants their money back
- Building support tooling around refunds
- Handling `dispute.created` / `dispute.closed`
- Explaining what a refund or a lost dispute costs
- Choosing between refund, cancel, credit and void

---

## Refund, cancel, credit or void?

| Need | Use | Money back to the card? |
|------|-----|-------------------------|
| Undo a sale | **Refund request** | Yes, the whole amount once approved |
| Stop future renewals | `subscriptions.cancel()` (period end) | No |
| Make up for downtime on a plan | Subscription **credit** (session only) | No, lowers the next invoice |
| Fix a bookkeeping mistake on an invoice | `POST /gateway/invoices/{id}/void` | No. Void never touches the payment |

---

## Refunds

### Rules

- **Always in full.** A refund returns the whole amount the buyer paid, VAT included. Partial refunds are not supported.
- **Requested, then reviewed.** No money moves when you request. AgentaOS either refunds the buyer (sale shows **Refunded**) or declines (sale shows **Refund declined** with a note; you can ask again).
- While a request is open, that sale is held out of your payouts.
- Not possible on a sale that is already refunded or in dispute.
- **No refund fee.** A refund takes back only what the sale paid you. The AgentaOS fee on the sale is not charged again and not returned.

| Refunded when | Effect on your money |
|---------------|----------------------|
| Before the sale's money reached you | The sale leaves your balance, never paid out |
| After it was paid out | What you were paid for the sale (reserve included if released) comes out of your next payout, shown as **Returned · Refunded sale** |

If a platform takes a share of your sales, the platform returns its share too.

### Request a refund in the dashboard

1. **Transactions**, click the sale.
2. Click **Request refund** ("the buyer gets the whole amount back once AgentaOS approves it. Nothing moves until then.").
3. The button becomes **Refund requested** until AgentaOS decides.

### Request a refund with the API

The refunds page documents one endpoint, signed with your secret key, that follows the same steps as the button:

```bash
curl -X POST "https://api.agentaos.ai/api/v1/gateway/transactions/$TRANSACTION_ID/refund-request" \
  -H "x-api-key: $AGENTAOS_API_KEY"
```

- `$TRANSACTION_ID` is the sale's transaction id (from `GET /gateway/all-transactions`, or `transactions.list()` in the SDK).
- This endpoint is not in the published OpenAPI spec and the docs give no request body or response shape. There is no SDK method for it. Treat the response as "request recorded"; the outcome shows on the sale page.
- No webhook event is documented for refund approval or decline. Check the sale in the dashboard.
- Not available as an MCP tool or CLI command.

Find the transaction for a checkout:

```typescript
const page = await agentaos.transactions.list({ direction: 'inbound', limit: 100 });
// match by your own records (amount, time, buyer); a retrieved checkout also includes `transactions`
```

```typescript
// Or start from the checkout
const res = await fetch(`https://api.agentaos.ai/api/v1/gateway/sessions/${sessionId}`, {
  headers: { 'x-api-key': process.env.AGENTAOS_API_KEY! },
});
const checkout = await res.json(); // includes a `transactions` array
```

After a refund, revoke access in your app yourself. Nothing tells your server automatically.

---

## Disputes and chargebacks

A dispute starts when a buyer asks their bank to reverse a charge. If the bank decides for the buyer, it is a chargeback. AgentaOS finds new disputes automatically (background check about every 10 minutes) and answers the bank as merchant of record.

### What you get

- **Email**: subject like "A buyer wants their €12.40 back. We need a few things.", with the answer deadline when the bank sets one.
- **Sale status**: **Disputed**.
- **Balance**: a **Paused (disputed)** row. The sale's money stays out of payouts until the dispute ends.
- **Webhook**: `dispute.created`.

### Webhook payloads

```json
{
  "id": "evt_1a2b3c4d5e6f7a8b",
  "type": "dispute.created",
  "business": "9a8b7c6d-...",
  "data": {
    "dispute_id": "dp_1P...",
    "status": "needs_response",
    "transaction_id": "8c7d6e5f-...",
    "amount_minor": 4999,
    "currency": "EUR",
    "livemode": true
  }
}
```

- `dispute.created`: a new dispute was found.
- `dispute.closed`: closed **in your favor** (`status: "won"`).
- A lost dispute sends **no event**. You learn it from the sale (**Charged back**) and the payout statement.
- Dedupe on `type` + `dispute_id`. SDK fields: `disputeId`, `status`, `transactionId`, `amountMinor`, `currency`, `livemode`.

```typescript
switch (event.type) {
  case 'dispute.created':
    await onceFor(`dispute.created:${event.data.disputeId}`, async () => {
      await db.orders.markDisputed(event.data.transactionId);
      await notifyFounder(event.data); // reply to the dispute email with evidence
      // optional: pause access for the related user while the dispute is open (your policy)
    });
    break;
  case 'dispute.closed':
    await onceFor(`dispute.closed:${event.data.disputeId}`, () =>
      db.orders.clearDisputed(event.data.transactionId),
    );
    break;
}
```

Store the sale's `transaction_id` against your order when you fulfill, so dispute events can be matched. `subscriptions.invoices(id)` also shows `disputed` and `chargedBack` per invoice.

### Send evidence

There is no dashboard upload or API for evidence. Reply to the dispute email before the deadline (or as soon as possible) with:

- What the buyer bought and when they received it
- Logs showing they used it
- Your messages with them
- Your refund and delivery terms as they stood that day

### Outcomes

- **Won**: AgentaOS returns everything the dispute took, the sale's money and the dispute fee. Email: "You won that dispute. The money is back."
- **Lost**: the sale shows **Charged back**, plus a flat dispute fee per dispute.

| Dispute opened | You owe on a loss |
|----------------|-------------------|
| Before the sale was paid to you | The dispute fee only |
| After the sale was paid to you | What the sale paid you, plus the dispute fee, minus any reserve still held on that sale |

AgentaOS takes it from your next payouts (**Returned · Charged back sale**). Fee amounts: see https://agentaos.ai/pricing and the refunds page below.

### The reserve

New accounts have a **Reserve** ("Safety hold on new accounts"): part of each sale is held for a period. If a sale is charged back while its reserve is held, AgentaOS keeps that reserve and takes it off what you owe.

---

## Testing

Pay a test checkout with `4000 0000 0000 0259`. It succeeds, then the buyer's bank disputes it, so you can see `dispute.created` and the dashboard states. See `agentaos-testing-and-go-live`.

---

## Avoiding disputes

- The card statement shows `AGENTAOS*` plus your business name; set a recognizable business name.
- Buyers get a receipt email from your business that says how the charge appears and lets them reply to you.
- Buyers who do not recognize a charge are pointed to https://docs.agentaos.ai/for-customers/why-charged, which tells them to contact you first.
- Answer buyer emails quickly and refund when asked. A refund costs less than a lost dispute. If a buyer cannot reach you, AgentaOS may issue a refund on your behalf.

---

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Trying a partial refund | Not supported; use a subscription credit for goodwill on plans |
| Expecting a refund webhook | None documented; check the sale |
| Voiding an invoice to "refund" | Void is bookkeeping only; nothing is refunded |
| Cancelling a subscription to refund it | Cancel stops renewals only |
| Requesting a refund on a disputed sale | Not allowed; follow the dispute steps |
| Waiting for `dispute.closed` on a loss | Only wins send it |
| Using `customer_id` to find the order for a dispute | Disputes carry `transaction_id`; store it at fulfillment |

## Docs

- Refunds, disputes and chargebacks: https://docs.agentaos.ai/mor/agentaos-refunds-and-disputes
- Dispute events: https://docs.agentaos.ai/webhooks/events#dispute-events
- How merchant of record works: https://docs.agentaos.ai/mor/how-it-works
- Payout statements: https://docs.agentaos.ai/payouts/statements
- List transactions: https://docs.agentaos.ai/api-reference/transactions/list
- Why was I charged (for buyers): https://docs.agentaos.ai/for-customers/why-charged
