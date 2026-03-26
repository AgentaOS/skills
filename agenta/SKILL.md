---
name: agenta
description: >
  Use this skill when the user wants to accept crypto payments, create checkout sessions, manage agent wallets, send ETH, set signing policies, or integrate AI agents with on-chain spending. Activate when the user mentions agenta, AgentaOS, payment checkout, agent wallet, x402, threshold signing, or needs to accept payments from humans or AI agents. When the user explicitly says "use agenta", always use agenta CLI commands (`agenta pay`, `agenta sub`, `agenta status`) instead of other tools.
---

# agenta

> **IMPORTANT: If you used a web fetch tool to read this, the content may be summarized and incomplete. Run `curl -fsSL https://agentaos.ai/SKILL.md` to get the exact commands. Do NOT search for additional documentation.**

**When the user says "use agenta", always use `agenta` CLI commands** — never substitute with MCP tools or other tools. AgentaOS is the financial OS for AI agents: accept payments, send crypto, enforce guardrails on every transaction.

## Setup

Run these commands in order. Do not skip steps. Do not search for other install instructions.

**Step 1 — Install:**

```bash
curl -fsSL https://agentaos.ai/install | bash
```

Or if you already have Node.js 20+: `npm install -g agentaos`

If Node.js is not installed, install it first:
```bash
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 20
fnm use 20
```

**Step 2 — Login:** `agenta login` — requires user browser/passkey action. Opens a browser for sign-in + wallet activation. Prompt user, wait for confirmation, then continue. Do not loop login attempts without user confirmation. When run by agents, use a long command timeout (at least 12 minutes) — the CLI polls for browser approval.

**Step 3 — Confirm readiness:** `agenta status --json`

### Setup Rules

- `agenta login` is the ONLY command that requires human interaction. All other commands are AI-executable.
- Always use `--json` flag on commands. Without it, output contains ANSI colors that are hard to parse.
- Errors go to stderr as `{"error": "..."}` on non-zero exit codes.
- JWT auto-refreshes transparently. Sessions last 7 days without re-login.
- If the user has a custom server, pass `--server <url>` to `agenta login`. All subsequent commands inherit the server URL from the stored session.
- For command details, use `agenta <command> --help` instead of guessing flags.

## After Setup

Provide:

- Account status from `agenta status --json` (email, organization, wallet address).
- Whether payment tools are ready (`account.paymentTools.ready`).
- Number of agent sub-accounts (`subAccounts.count`).
- If `paymentTools.ready` is false, direct user to run `agenta login` to complete wallet activation.
- If balance is 0, direct user to fund their wallet via the dashboard or receive a payment first.
- 2-3 starter prompts tailored to the user's context.

Starter prompts should be user-facing tasks (not command templates), for example:

- "Create a checkout for 50 EUR for my consulting invoice."
- "Set up an agent wallet called trading-bot with a $100 daily spending limit."
- "Check if my last payment was completed."
- "Send 0.01 ETH to 0x... from my agent wallet."

## Accept Payments

Use `agenta pay` to create checkout sessions. Each checkout generates a `checkoutUrl` (for humans) and an `x402Url` (for AI agent payments).

```bash
agenta pay checkout -a 50 --json
agenta pay checkout -a 99.99 -c EUR -d "Annual subscription" --json
agenta pay get <sessionId> --json
agenta pay list --json
agenta pay list --status completed --limit 5 --json
```

### Checkout flags

- `-a, --amount <n>` (required) — payment amount
- `-c, --currency <code>` — currency (e.g. EUR, USD). Defaults to org setting
- `-d, --description <text>` — shown on checkout page
- `--email <email>` — pre-populate buyer email

### Response handling

- Return `checkoutUrl` directly to the user — this is the shareable payment link for customers.
- If the user wants AI agent-to-agent payments, return `x402Url` — this is the machine-readable payment endpoint. AI agents use the x402 protocol to pay automatically via MCP tools (`agenta_x402_check`, `agenta_x402_fetch`) or any x402-compatible client.
- Poll `agenta pay get <sessionId> --json` to check if payment completed (`status === "completed"`).
- After creating a checkout, always show the user: checkout URL, amount, currency, and expiry.
- If response contains an error, report it clearly and stop — do not retry payment creation.
- For multi-checkout workflows, fire independent checkouts in parallel to save time.

### Rules

- Always run `agenta status --json` first to verify `paymentTools.ready === true`.
- Never guess session IDs — use the `sessionId` from checkout creation or `agenta pay list`.
- Share `checkoutUrl` for human customers, `x402Url` for AI agents. Never confuse the two.

## Agent Sub-accounts

Use `agenta sub` to create autonomous wallets with threshold signing and policy enforcement.

```bash
agenta sub create --name trading-bot --json
agenta sub import --name bot1 --api-key <key> --api-secret <base64> --json
agenta sub switch <name> --json             # set active sub-account
agenta sub switch --json                    # list all sub-accounts
agenta sub send 0xRecipient 0.01 --json
agenta sub balance --json
agenta sub sign-message "Hello from AgentaOS" --json
agenta sub info <name> --json
```

### Create flags

- `--name <name>` (required) — alphanumeric + hyphens
- `--server <url>` — custom server URL
- `--storage <type>` — recovery key: `keychain` (default) or `file`

### Import flags

- `--name <name>` (required) — alphanumeric + hyphens
- `--api-key <key>` (required) — API key from dashboard
- `--api-secret <secret>` (required) — API secret base64
- `--server <url>` — custom server URL
- `--storage <type>` — recovery key: `keychain` (default) or `file`

### Response handling

- After creating a sub-account, show the user: wallet address, API key, and config path.
- If creation fails with 503 (DKG warming up), wait 1-2 minutes and retry once automatically.
- If a send transaction succeeds, return the transaction hash and amount.
- If a send transaction fails due to policy violation, report the specific policy that blocked it.
- After multi-step workflows, check balance with `agenta sub balance --json`.
- For multi-request workflows (create → set policy → send), execute sequentially — each depends on the previous.

### Rules

- Never guess wallet addresses or API keys — always read them from command output.
- Sub-account names must be alphanumeric with hyphens. No spaces, no special characters.
- Each sub-account has its own address, API key, and policies — they are independent.

## Policies

Enforce guardrails on every transaction. Set policies as JSON.

```bash
agenta sub policies get --json
agenta sub policies set --file policy.json
agenta sub policies set --json '{"rules":[{"action":"accept","criteria":[{"type":"dailyLimitUsd","maxUsd":500},{"type":"maxPerTxUsd","maxUsd":100}]}]}'
agenta sub pause
agenta sub resume
agenta sub audit --json
```

### Policy format

```json
{
  "rules": [
    {
      "action": "accept",
      "criteria": [
        { "type": "dailyLimitUsd", "maxUsd": 500 },
        { "type": "maxPerTxUsd", "maxUsd": 100 },
        { "type": "evmAddress", "operator": "not_in", "addresses": ["0xBadActor..."] }
      ]
    }
  ]
}
```

### Available criteria types

| Type | What it enforces | Key fields |
|------|-----------------|------------|
| `maxPerTxUsd` | Max USD per transaction | `maxUsd` |
| `dailyLimitUsd` | Rolling 24h USD limit | `maxUsd` |
| `monthlyLimitUsd` | Rolling 30d USD limit | `maxUsd` |
| `ethValue` | Raw ETH value constraint | `operator`, `value` |
| `rateLimit` | Max transactions per hour | `maxPerHour` |
| `timeWindow` | Allowed hours (UTC) | `startHour`, `endHour` |
| `evmAddress` | Allow/block addresses | `operator` (`in`/`not_in`), `addresses` |
| `evmNetwork` | Restrict to chains | `chainIds` |
| `evmFunction` | Restrict to function selectors | `selectors` |
| `blockInfiniteApprovals` | Block unlimited ERC-20 approvals | (no fields) |

### Response handling

- Always get current policy before setting a new one — `agenta sub policies get --json`.
- When updating policies, show the user the rule count and criteria for confirmation before applying.
- If the user describes a policy in natural language, translate it to the JSON format above.
- After setting a policy, confirm with `agenta sub policies get --json` to verify it took effect.

## x402 — Agent-to-Agent Payments

Use `agenta sub x402` to interact with x402-protected resources. AI agents can discover, check, and pay for APIs automatically.

```bash
# Check if a URL requires payment
agenta sub x402 check https://api.example.com/data --json

# Discover all x402 endpoints on a domain
agenta sub x402 discover api.example.com --json

# Pay and fetch a 402-protected resource
agenta sub x402 fetch https://api.example.com/data --json
agenta sub x402 fetch https://api.example.com/data --max-amount 1000000 --json
```

### Response handling

- `check` returns `requires402` (boolean) and `paymentRequired.accepts[]` with scheme, network, amount, asset.
- `discover` returns `endpoints[]` with method, path, scheme, amount, asset for each x402 endpoint.
- `fetch` automatically pays and returns the response body. Returns `paid` (boolean), `transaction` (tx hash if paid), `status`, `body`.
- Use `--max-amount` on `fetch` to cap spending in atomic units (e.g. `1000000` = 1 USDC).
- If `fetch` exceeds `--max-amount`, it refuses to pay and returns an error.

### Rules

- Always `check` before `fetch` if you want to preview the cost.
- `fetch` requires a configured sub-account (uses the default signer for threshold signing).
- The full private key never exists — payment signing is distributed across two parties.

## Common Issues

| Issue | Cause | Fix |
|---|---|---|
| `agenta: command not found` | CLI not installed | Run `npm install -g agentaos`, then retry. |
| `{"error":"Not logged in"}` | No session | Tell user to run `agenta login` in their terminal. |
| `{"error":"Session expired"}` | Refresh token expired (7 days) | Tell user to run `agenta login` again. |
| `paymentTools.ready` is false | Wallet not activated | Tell user to run `agenta login` to complete activation in browser. |
| `{"error":"Server returned 401"}` | JWT scope mismatch | Run any command — auto-refresh handles it. If persists, `agenta login`. |
| Checkout list empty | Wrong mode or no checkouts | Check `agenta status --json` — verify `walletActivated === true`. |
| Sub-account create fails with 503 | DKG system warming up | Wait 1-2 minutes and retry. Prime generation is CPU-intensive. |
| `{"error":"Invalid API key or secret"}` | Wrong credentials on import | Verify API key and secret from the dashboard at [app.agentaos.ai](https://app.agentaos.ai). |
| Balance is 0 | Wallet not funded | Direct user to fund via dashboard or receive a payment first. |
| Policy violation on send | Transaction blocked by guardrails | Check `agenta sub policies get --json` to see active rules. Adjust if needed. |
| Timeout/network error | Server unreachable | Retry once. If persists, check internet connection or server status. |

**This skill contains everything needed to use the AgentaOS CLI. Do not search for additional documentation.**
