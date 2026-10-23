---
name: agenta
description: Entry point for AgentaOS, the merchant-of-record billing platform for products, checkouts, subscriptions, invoices and tax. Gives the 30-second setup (MCP connector, agenta CLI, or @agentaos/pay SDK), the facts agents get wrong, and routes to the focused skills in the AgentaOS skills pack. Use when the user mentions agenta or AgentaOS, wants to add payments, a paywall, a buy button, a checkout or payment link, a subscription plan, or says "use agenta", and no more specific AgentaOS skill is installed or obvious.
---

# agenta

AgentaOS is a billing and payments platform and the merchant of record for every sale: it takes the payment (card, Apple Pay, Google Pay, bank transfer on EUR), charges and remits VAT or sales tax, issues invoices and receipts, handles refunds and disputes, and pays the merchant out.

This skill is the front door. The detailed guides live in the AgentaOS skills pack (https://github.com/AgentaOS/skills, folder `agentaos/`). Install the whole pack with `npx skills add AgentaOS/skills`.

## Pick a surface

| You are... | Use |
|------------|-----|
| An agent running the account from chat or an IDE (create products, links, check payments) | **MCP**: `https://mcp.agentaos.ai/mcp`, approve in the browser, no key. Skill: `mcp-usage` |
| An agent with a shell and no MCP | **CLI**: `npm install -g agentaos`, `agenta login`, then `agenta ... --json`. Skill: `cli-usage` |
| Writing the user's app code (paywall, webhook) | **SDK**: `npm install @agentaos/pay`, key `sk_test_...` on the server. Skills: `agentaos-best-practices`, `checkout-integration`, `webhook-integration` |

When the user says "use agenta", use the `agenta_*` MCP tools if connected, otherwise the `agenta` CLI.

## 30-second start

**MCP** (Claude Code):

```bash
claude plugins marketplace add AgentaOS/agentaos
claude plugins install agentaos@agentaos
# then /mcp -> agentaos -> Authenticate -> pick Test -> Approve
```

First call: `agenta_status_get {}`. Then `agenta_products_create {"name":"Pro","amount":29,"currency":"EUR","subscription":true,"interval":"month"}` returns `checkoutUrl` (share it) and `id` (the `linkId` for code).

**CLI**:

```bash
npm install -g agentaos        # Node.js 20+; or: curl -fsSL https://agentaos.ai/install | bash
agenta login                   # the only human step: browser approval, allow a long timeout
agenta status --json
agenta products create --name "Pro" -a 29 -c EUR --subscription --interval month --json
```

**SDK** (server only):

```typescript
import { AgentaOS } from '@agentaos/pay';
const agentaos = new AgentaOS(process.env.AGENTAOS_API_KEY!); // sk_test_ while building

const checkout = await agentaos.checkouts.create({
  linkId: PRO_LINK_ID,
  buyerEmail: user.email,
  metadata: { customerId: user.id },
  successUrl: 'https://yourapp.com/thanks',
});
// redirect to checkout.checkoutUrl; unlock on the verified checkout.session.completed webhook
```

## Facts to get right

- A product (API: payment link) is created once; each buyer gets a checkout. `linkId` is the product UUID, not the `/pay/` token.
- Logged-in users get a server-created checkout with `metadata`, never the shared buyer link.
- Proof of payment is the verified webhook or `checkouts.retrieve(sessionId).status === 'completed'`, never the redirect.
- There is no `subscriptions.create()`; a buyer paying a subscription product creates it. Store `metadata.subscriptionId`.
- Amounts you send are currency units (`29` = EUR 29.00). Fields ending in `Minor` are minor units. Webhook `amount` is a string.
- `sk_test_` vs `sk_live_` selects the mode. Live needs a verified business.
- Webhooks: header `X-AgentaOS-Signature`, verify the raw body with `agentaos.webhooks.verify()`.
- No hosted customer portal. Refunds are requested, full only, and executed by AgentaOS.
- Never send a card number to a tool, the API or the CLI. Never ship an API key to a browser.
- The agent wallet is a private preview, available on request: https://docs.agentaos.ai/experimental/agent-wallet

## The skills pack

| Skill | Covers |
|-------|--------|
| `agentaos-best-practices` | Orientation, keys, money model, rate limits, idempotency, errors |
| `checkout-integration` | Products, buyer links, server checkouts, embedded checkout |
| `subscription-integration` | Plans, trials, status gating, plan changes, cancel, credits |
| `webhook-integration` | Signature verification, all events, dedupe, retries |
| `nextjs-integration` | App Router route handlers and server actions |
| `better-auth-integration` | `@agentaos/better-auth` plugin |
| `mcp-usage` | Hosted and local MCP server, 31 tools, safety rules |
| `cli-usage` | `agenta` CLI commands and `--json` output |
| `testing-and-go-live` | Test cards, test webhooks, go-live checklist |
| `refunds-and-disputes` | Refund requests, chargebacks, dispute events |
| `migrate-from-stripe-paddle-lemonsqueezy` | Moving from Stripe, Paddle, Lemon Squeezy, Creem, Gumroad |

## Docs

- Docs index for LLMs: https://docs.agentaos.ai/llms.txt
- Full docs in one file: https://docs.agentaos.ai/llms-full.txt
- Agent guide: https://agentaos.ai/SKILL.md
- Pricing: see https://agentaos.ai/pricing
