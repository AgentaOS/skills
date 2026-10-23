---
name: agentaos-cli-usage
description: The AgentaOS agenta CLI (npm package agentaos), covering install via curl or npm, device-code browser login (agenta login, session in ~/.agenta, the only human step), agenta status and go-live next steps, --json output for agents and scripts, and every command group (products, pay, subscriptions with change-plan and credits, discounts, customers, invoices and receipts, verify, audit, businesses with --business). Use when running AgentaOS from a terminal, a coding agent without MCP, or a script; when the user says "use agenta"; or when translating an agenta_* MCP tool call to its CLI command.
---

# AgentaOS CLI (`agenta`)

The `agenta` CLI ships as the `agentaos` npm package and installs two equivalent binaries: `agenta` and `agentaos`. It runs the same operations as the MCP server against your logged-in account. Use it for one-off invoices, quick tests, support work, and agents that run shell commands.

The CLI authenticates with a browser login session, not an API key. For a backend or a CI job that must use a key, use `@agentaos/pay` or the REST API with `sk_test_` / `sk_live_` (see `agentaos-best-practices`), or the local MCP server (see `agentaos-mcp-usage`).

## When to use this skill

- Installing the CLI and logging in
- Creating products, checkouts, discount codes from the terminal
- Looking up subscriptions, customers, invoices; cancelling or changing a plan
- Submitting business verification
- An agent asked to "use agenta"

---

## Install

Requires Node.js 20+ (macOS, Linux, Windows via WSL).

```bash
curl -fsSL https://agentaos.ai/install | bash
# or
npm install -g agentaos

agenta --version
```

No Node yet:

```bash
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 20
fnm use 20
```

## Log in (the only human step)

```bash
agenta login            # optional: --server <url>, defaults to $AGENTA_SERVER or https://api.agentaos.ai
```

Device-code flow: the CLI opens a verification URL and prints a code; the user signs in and approves in the browser; the CLI polls for up to 10 minutes. A new email creates the account. The session is stored in `~/.agenta/session.json` (mode 0600) and refreshes automatically.

Agent rules:

- Ask the user to approve in the browser, then wait. Use a command timeout of at least 10 minutes. Do not loop login attempts.
- If already logged in, `agenta login` does nothing; `agenta logout` first to switch accounts.
- Sessions made with `agenta login` run in test mode unless the request asks for live.

## Status first

```bash
agenta status --json   # alias: agenta whoami
```

Key fields: `account.authenticated`, `account.organization`, `account.paymentTools.ready` (true once signed in: test payments work), `goLive.canGoLive`, `goLive.progress`, `goLive.verification.state`, `goLive.next.command` and `goLive.next.why` (`command` is null when the step happens in the dashboard).

Not logged in prints `{"account":{"authenticated":false,"reason":"not-logged-in","next":"agenta login"}}` (or `reason: "session-expired"`) and exits 0. Check `authenticated`, not the exit code.

## Output rules

- Pass `--json` on every command an agent runs. JSON is also automatic when stdout is not a terminal.
- Without `--json`, the CLI prints the same plain sentence the MCP tool returns.
- `agenta <command> --help` for flags; do not guess.
- Fields ending in `Minor` are integer minor units (`1999` = EUR 19.99). Plain `amount` is decimal.

---

## Commands

### Products (a product is an API payment link; its `id` is the `linkId`)

```bash
agenta products create --name "Launch Kit" -a 49 -c EUR -d "One sentence buyers see" --json
agenta products create --name "Pro" -a 29 -c EUR --subscription --interval month \
  --trial-days 14 --success-url https://yourapp.com/thanks --cancel-url https://yourapp.com/pricing --json
agenta products list --limit 20 --json
```

- `-a` is currency units (`29` = EUR 29.00). `-c` is `EUR` or `USD`.
- `--subscription` needs `--interval month|year`. `--trial-days` 1 to 730, plans only.
- Return URLs must be `https://`; http and localhost are refused before sending.
- Products created from the CLI are test-mode products. Live products are created in the dashboard (or copied with **Copy to live**) once the merchant is live.
- Output: `id` (linkId), `checkoutUrl` (buyer link), `type`, `billingInterval`, `amount`, `currency`, `status`.

### Checkouts

```bash
agenta pay checkout -a 49.99 -c EUR -d "Consulting fee, October" --email buyer@example.com --json
agenta pay get <sessionId> --json
agenta pay list --status completed --limit 5 --json
```

- Checkouts expire after 30 minutes by default. Share `checkoutUrl`.
- `status`: `open`, `completed`, `expired`, `cancelled`. Poll `pay get` to confirm payment.
- `amount` on `pay get` can be `null` when the checkout used its product's own amount.
- Never guess a `sessionId`; use the one returned or `pay list`.

### Subscriptions

```bash
agenta subscriptions list --limit 20 --json
agenta subscriptions list --code LAUNCH20 --json        # who a discount code brought in
agenta subscriptions cancel <id> --json                 # at period end, no refund
agenta subscriptions change-plan <id> --to <linkId> --dry-run --json   # quote
agenta subscriptions change-plan <id> --to <linkId> --json             # apply
agenta subscriptions credit <id> -a 10 --reason "Two days of downtime" --json
agenta subscriptions credits <id> --json
```

- `change-plan` quotes then applies with the quote's `prorationDate`. Always run `--dry-run` first and show the user `dueTodayMinor` and `nextInvoiceMinor`. Target: same currency, same interval, different plan; subscription `active` or `trialing`. Re-run with the current plan's id to revert a scheduled downgrade.
- `credit` takes a decimal amount, needs an owner or admin session, and each run is a new credit (running twice gives two credits).

### Discount codes

```bash
agenta discounts create --code LAUNCH20 --percent-off 20 --json
agenta discounts create --code SAVE5 --amount-off 5.00 --max-redemptions 100 --expires-at 2026-12-31 --json
agenta discounts create --code ALICE --json            # tracking only, changes no price
agenta discounts list --json
agenta discounts show <id> --json                      # the only command that shows what it takes off and usage
agenta discounts archive <id> --json
```

`--percent-off` (1 to 99) or `--amount-off`, not both. Codes take money off the first invoice. Terms are fixed once created; archive and create a new one to change them.

### Customers and invoices

```bash
agenta customers list --json
agenta invoices list --json
agenta invoices receipt <invoiceId> -o receipt.pdf
agenta invoices send-receipt <invoiceId> --json
```

### Verification and audit

```bash
agenta verify declaration --json     # read the five statements to the user
agenta verify submit --legal-name <name> --registration-number <number> --country <code> \
  --street <street> --city <city> --url <url> --accept-declaration [options]   # ask the user for every value
agenta verify status --json
agenta verify resubmit --json        # after AgentaOS asked for changes
agenta audit request --help          # the free Revenue & Pricing Audit; needs your pricing page URL
agenta audit show --json
```

Never invent legal names, registration numbers or addresses. Accept the declaration only after the user confirmed each statement.

### Platforms

`agenta businesses list|get|create|invite|revoke-invite|id-link`. Add `--business <id>` to any command to act as a business you manage.

---

## MCP tool to CLI mapping

The commands mirror the `agenta_*` tools 1:1. `agenta_products_create {"trialDays":14}` is `agenta products create --trial-days 14`; an `id` or `sessionId` key is the positional argument; `dryRun: true` is `--dry-run`. With `--json` the output is the tool's `structuredContent`.

## Common issues

| Issue | Fix |
|-------|-----|
| `agenta: command not found` | `npm install -g agentaos`, or open a new shell after the curl install |
| `authenticated: false`, `not-logged-in` or `session-expired` | Ask the user to run `agenta login` |
| `--success-url must be an https:// URL` | Use an https URL |
| `--subscription needs --interval` | Add `--interval month` or `--interval year` |
| Live money not arriving | `agenta status --json`, follow `goLive.next`; live needs a verified business |
| Want key-based auth in CI | Use `@agentaos/pay` or `npx -y agentaos` (MCP) with `AGENTAOS_GATEWAY_KEY` |

## Docs

- Install: https://docs.agentaos.ai/cli/install
- Login: https://docs.agentaos.ai/cli/login
- Status: https://docs.agentaos.ai/cli/status
- Products: https://docs.agentaos.ai/cli/products
- Pay: https://docs.agentaos.ai/cli/pay
- Subscriptions: https://docs.agentaos.ai/cli/subscriptions
- Discounts: https://docs.agentaos.ai/cli/discounts
- Invoices: https://docs.agentaos.ai/cli/invoices
- Verify: https://docs.agentaos.ai/cli/verify
