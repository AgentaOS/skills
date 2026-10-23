---
name: agentaos-mcp-usage
description: How and when to use the AgentaOS MCP server safely, covering the hosted server at https://mcp.agentaos.ai/mcp with browser OAuth approval (Test or Live chosen at approval, no key pasted) for Claude Code, Cursor, Claude.ai and ChatGPT, the local npx -y agentaos server with AGENTAOS_GATEWAY_KEY for headless agents and CI, the 31 agenta_* tools (status, audit, verification, products, checkouts, subscriptions, credits, discount codes, customers, invoices, businesses), answer format, test-mode safety rules, switching to live, disconnecting, and troubleshooting. Use when connecting an AI agent to an AgentaOS account, choosing which agenta_* tool to call, or debugging a missing or failing MCP connection.
---

# AgentaOS MCP Usage

The AgentaOS MCP server gives an AI agent the same operations as the `agenta` CLI. One catalog backs both, so each tool has a matching command with the same inputs and the same answer. Use it to run the account from chat or from a coding agent: create products and checkouts, check payments, manage subscriptions and discount codes, read customers and invoices, and file verification.

The MCP server operates the account. It does not write your app's integration code; for that, use `@agentaos/pay` (see `agentaos-checkout-integration`, `agentaos-webhook-integration`).

## When to use this skill

- Connecting Claude Code, Cursor, Claude.ai, ChatGPT or another MCP client to AgentaOS
- Running AgentaOS from a headless agent or CI job
- Picking the right `agenta_*` tool and its inputs
- Fixing "no agenta tools", "Invalid API key" or approval errors

---

## Connect

### Hosted server (any client that can open a browser)

URL: `https://mcp.agentaos.ai/mcp`. You approve once on an AgentaOS page and pick **Test mode** or **Live mode** there. You paste no key. A new email creates the account during approval.

**Claude Code** (plugin adds the server and the integration skill):

```bash
claude plugins marketplace add AgentaOS/agentaos
claude plugins install agentaos@agentaos
```

Then type `/mcp`, choose `agentaos`, **Authenticate**, pick Test or Live, **Approve**. Check with:

```bash
claude mcp list
# agentaos: https://mcp.agentaos.ai/mcp (HTTP) - Connected
```

**Cursor**: **Settings, MCP, Add server**:

```json
{
  "mcpServers": {
    "agentaos": { "url": "https://mcp.agentaos.ai/mcp" }
  }
}
```

**Claude.ai / Claude desktop**: **Customize, Connectors, Add custom connector**, paste the URL.
**ChatGPT**: **Settings, Connectors, Create**, paste the URL.

Approval creates an API key on the account, named after the client, for the mode you picked. It appears under **Developers, API keys**.

### Local server (headless agents, CI)

Needs Node.js 20+. Create a test key: dashboard in test mode, **Developers, API keys**, **Connect an AI agent**, **Other**, **Generate one named Other agent**, **Create key**. Copy it (shown once).

```json
{
  "mcpServers": {
    "agentaos": {
      "command": "npx",
      "args": ["-y", "agentaos"],
      "env": { "AGENTAOS_GATEWAY_KEY": "sk_test_your-key" }
    }
  }
}
```

Claude Code equivalent:

```bash
claude mcp add agentaos-local -e AGENTAOS_GATEWAY_KEY=sk_test_your-key -- npx -y agentaos
```

Keep the key in the MCP config's env or your secret store, never in the chat or a repo.

---

## Safety rules

1. **First call, always:** `agenta_status_get` with `{}`. It says whether test payments work, where go-live stands (`goLive.progress`), and the one next step (`goLive.next`).
2. **Stay in test mode while building.** A test connection or `sk_test_` key sees and creates test data only. It cannot move real money.
3. **Live is chosen at approval.** To switch, disconnect and approve again with **Live mode**. Live sales also need a verified business.
4. **Never retry a create blindly.** If a create call fails with `... failed: ...`, report it and stop. Products and checkouts are not idempotent through the tools.
5. **Quote before charging.** For plan changes call `agenta_subscriptions_change_plan` with `dryRun: true`, show the user the amounts, apply only after they agree.
6. **Ask, never invent, legal details** for verification. Pass `acceptDeclaration: true` only after the user confirmed the statements from `agenta_verify_declaration`.
7. **Never send a card number** to any tool. Cards are typed only into the checkout page.
8. **Confirm before destructive actions**: cancelling a subscription, archiving a discount code.

---

## Answers

Every tool answers twice: a plain sentence for the merchant (`content`, the same sentence the CLI prints) and the result as JSON (`structuredContent`, the same JSON as `agenta ... --json`). Say the sentence to the user and add the link and next step. Use the JSON for code. Do not paste raw JSON as the answer.

Inputs are camelCase JSON keys (`successUrl`, `trialDays`, `dryRun`). A validation error lists every missing field at once and names the CLI flag (`--success-url`); the JSON key is its camelCase. Fix all of them, ask the user for what you do not know, then call once more.

---

## Tools (31)

### Account and going live

| Tool | What it does |
|------|--------------|
| `agenta_status_get` | Account and go-live overview, with the next step |
| `agenta_audit_request` | Ask for the free Revenue & Pricing Audit (`url` required) |
| `agenta_audit_show` | Where the audit stands, and the report once it exists |
| `agenta_verify_declaration` | The five statements you attest to |
| `agenta_verify_submit` | Submit business verification for live payments |
| `agenta_verify_status` | Where verification stands |
| `agenta_verify_resubmit` | Send verification back after requested changes |

### Products and checkouts

| Tool | What it does | Example input |
|------|--------------|---------------|
| `agenta_products_create` | Create a one-time product or a plan | `{"name":"Pro","amount":29,"currency":"EUR","subscription":true,"interval":"month","trialDays":14,"successUrl":"https://yourapp.com/thanks"}` |
| `agenta_products_list` | List products and plans | `{"limit":20}` |
| `agenta_pay_checkout` | Create a checkout and get the link | `{"amount":50,"currency":"EUR","description":"Consulting, October"}` |
| `agenta_pay_get` | Paid, open, expired or cancelled? | `{"sessionId":"<id>"}` |
| `agenta_pay_list` | List checkouts | `{"status":"completed","limit":5}` |

`agenta_products_create` returns `id` (the `linkId` for server-side checkouts and plan changes) and `checkoutUrl` (the buyer link). `subscription: true` needs `interval` `month` or `year`. Return URLs must be `https://`.

### Subscriptions and discount codes

| Tool | What it does |
|------|--------------|
| `agenta_subscriptions_list` | List subscriptions (filter by `code`) |
| `agenta_subscriptions_cancel` | Cancel at the end of the current period |
| `agenta_subscriptions_change_plan` | Move to another plan (`id`, `to`, optional `dryRun`) |
| `agenta_subscriptions_credit` | Credit against the next invoice (`id`, `amount`, `reason`) |
| `agenta_subscriptions_credits` | Credits given and unspent balance |
| `agenta_discounts_create` | Create a code buyers type at checkout (`code`, optional percent or amount off) |
| `agenta_discounts_list` | List codes |
| `agenta_discounts_show` | What one code takes off and how many used it |
| `agenta_discounts_archive` | Stop a code (existing subscribers keep their discount) |

### Customers and invoices

| Tool | What it does |
|------|--------------|
| `agenta_customers_list` | Everyone who has paid you |
| `agenta_invoices_list` | Invoices, newest first |
| `agenta_invoices_receipt` | Receipt PDF for a paid invoice |
| `agenta_invoices_send_receipt` | Re-send the receipt email to the buyer on file |

### Businesses you manage (platforms only)

`agenta_businesses_list`, `agenta_businesses_get`, `agenta_businesses_create`, `agenta_businesses_invite`, `agenta_businesses_revoke_invite`, `agenta_businesses_id_link`. Every tool also takes an optional `business` input (a business id) to act as that business.

Not available as tools: refunds (requested from the sale page in the dashboard; see `agentaos-refunds-and-disputes`), webhook configuration, API key management, payouts.

---

## Typical flows

**"Add a EUR 29/month Pro plan and give me the link"**

1. `agenta_status_get` `{}`
2. `agenta_products_create` `{"name":"Pro","amount":29,"currency":"EUR","subscription":true,"interval":"month"}`
3. Tell the user the price, the `checkoutUrl`, and that `id` is the `linkId` for server code.

**"Was the consulting invoice paid?"**

1. `agenta_pay_list` `{"limit":10}` to find the session, or use the `sessionId` from creation
2. `agenta_pay_get` `{"sessionId":"..."}` and report `status`

**"Upgrade ana@example.com to Pro Plus"**

1. `agenta_subscriptions_list` `{}` and find her subscription `id`
2. `agenta_products_list` `{}` and find the Pro Plus `id`
3. `agenta_subscriptions_change_plan` `{"id":"...","to":"...","dryRun":true}` and show the quote
4. After a yes, the same call without `dryRun`

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No `agenta_*` tools | Not connected | Claude Code: `/mcp`, `agentaos`, Authenticate. Elsewhere: add `https://mcp.agentaos.ai/mcp` |
| `... failed: Invalid API key` / "The key may have been revoked" | Key revoked under Developers, API keys | Reconnect and approve again |
| "This approval link expired" | More than 10 minutes between adding and approving | Add the connector again |
| "The connection was declined in AgentaOS" | Approval not clicked | Add again, click **Approve** |
| Live money not arriving | Connected as Test, or business not verified | `agenta_status_get`, follow `goLive.next`; reconnect as Live once verified |
| `--success-url must be an https:// URL` | http or localhost | Use the deployed https URL |
| Local server fails to start | Node.js < 20 or missing `AGENTAOS_GATEWAY_KEY` | Upgrade Node, set the env var |

Disconnect: **Developers, API keys**, delete the key named after the client, **Confirm**.

## Docs

- MCP server (setup and tools): https://docs.agentaos.ai/mcp/setup
- Connect Claude.ai or ChatGPT: https://docs.agentaos.ai/mcp/remote-connector
- Let an AI agent run your store: https://docs.agentaos.ai/guides/ai-agent
- Build with AI agents: https://docs.agentaos.ai/agents/overview
- Agent guide file: https://agentaos.ai/SKILL.md
