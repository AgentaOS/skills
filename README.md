# AgentaOS Skills

Agent skills for [AgentaOS](https://agentaos.ai), the merchant-of-record billing platform: products, checkout, subscriptions, webhooks, invoices and tax. Each skill teaches an AI coding agent (Claude Code, Cursor, Codex, Windsurf, and others) one part of an AgentaOS integration, with real TypeScript and curl examples and links to the exact docs pages.

## Install

### Skills CLI (any agent)

Install every skill:

```bash
npx skills add AgentaOS/skills
```

Or one skill:

```bash
npx skills add AgentaOS/skills --skill agentaos-best-practices
npx skills add AgentaOS/skills --skill webhook-integration
npx skills add AgentaOS/skills --skill subscription-integration checkout-integration
```

### Claude Code

Add the marketplace:

```text
/plugin marketplace add AgentaOS/skills
```

Install the whole pack, or single skills:

```text
/plugin install agentaos-pack@agentaos-skills
/plugin install checkout-integration@agentaos-skills
/plugin install webhook-integration@agentaos-skills
```

Install either `agentaos-pack` or individual skills, not both.

On Claude Code 2.1.275 or later, one line adds the marketplace and installs a plugin:

```text
/plugin install agentaos-pack --marketplace AgentaOS/skills
/plugin install agentaos-best-practices --marketplace AgentaOS/skills
/plugin install checkout-integration --marketplace AgentaOS/skills
/plugin install subscription-integration --marketplace AgentaOS/skills
/plugin install webhook-integration --marketplace AgentaOS/skills
/plugin install nextjs-integration --marketplace AgentaOS/skills
/plugin install better-auth-integration --marketplace AgentaOS/skills
/plugin install mcp-usage --marketplace AgentaOS/skills
/plugin install cli-usage --marketplace AgentaOS/skills
/plugin install testing-and-go-live --marketplace AgentaOS/skills
/plugin install refunds-and-disputes --marketplace AgentaOS/skills
/plugin install migrate-from-stripe-paddle-lemonsqueezy --marketplace AgentaOS/skills
/plugin install agenta --marketplace AgentaOS/skills
```

For the AgentaOS MCP server (run your account from Claude Code), install the main plugin as well:

```bash
claude plugins marketplace add AgentaOS/agentaos
claude plugins install agentaos@agentaos
```

### Cursor, Windsurf and other tools

Pull a skill folder into your project:

```bash
npx degit AgentaOS/skills/agentaos/checkout-integration .cursor/skills/checkout-integration
npx degit AgentaOS/skills/agentaos/webhook-integration .cursor/skills/webhook-integration
```

Or the whole pack:

```bash
npx degit AgentaOS/skills/agentaos .cursor/skills/agentaos
```

Then reference it in the chat:

```text
@.cursor/skills/checkout-integration/SKILL.md Add a Pro plan checkout for logged-in users
```

For Windsurf, Codex and other agents, copy the folder wherever your tool reads rules or skills, and reference the `SKILL.md` file.

## Available skills

### Getting started

| Skill | Description |
|-------|-------------|
| [agentaos-best-practices](./agentaos/agentaos-best-practices/) | Orientation: core objects, API keys, test vs live, SDK setup, money model, rate limits, idempotency, errors |
| [testing-and-go-live](./agentaos/testing-and-go-live/) | Test cards, test webhooks, verification, Copy to live, launch checklist |
| [agenta](./agenta/) | Front door: 30-second setup on MCP, CLI or SDK, and routing to the skills below |

### Accepting payments

| Skill | Description |
|-------|-------------|
| [checkout-integration](./agentaos/checkout-integration/) | Products (payment links), buyer links, server-created checkouts, embedded checkout |
| [subscription-integration](./agentaos/subscription-integration/) | Plans, trials, status gating, plan changes, cancel and resume, credits |
| [webhook-integration](./agentaos/webhook-integration/) | X-AgentaOS-Signature verification, all event types, dedupe, retries |
| [refunds-and-disputes](./agentaos/refunds-and-disputes/) | Refund requests, chargebacks, dispute events |

### Frameworks

| Skill | Description |
|-------|-------------|
| [nextjs-integration](./agentaos/nextjs-integration/) | Next.js App Router route handlers, server actions, webhook route |
| [better-auth-integration](./agentaos/better-auth-integration/) | The `@agentaos/better-auth` plugin |

### Agents and tooling

| Skill | Description |
|-------|-------------|
| [mcp-usage](./agentaos/mcp-usage/) | Hosted and local MCP server, the 31 `agenta_*` tools, safety rules |
| [cli-usage](./agentaos/cli-usage/) | The `agenta` CLI, login, `--json` output, every command |
| [migrate-from-stripe-paddle-lemonsqueezy](./agentaos/migrate-from-stripe-paddle-lemonsqueezy/) | Moving from Stripe, Paddle, Lemon Squeezy, Creem or Gumroad |

## Repository layout

```text
agentaos/<skill>/SKILL.md   the skills pack
agenta/SKILL.md             entry-point skill (kept for existing installs)
.claude-plugin/marketplace.json
install.sh                  agenta CLI installer
```

## Sources

Every fact in these skills comes from the AgentaOS docs. If a skill and the docs disagree, the docs win; please open an issue.

- Docs: https://docs.agentaos.ai
- Docs index for LLMs: https://docs.agentaos.ai/llms.txt
- OpenAPI: https://docs.agentaos.ai/openapi.json
- SDK: [`@agentaos/pay`](https://www.npmjs.com/package/@agentaos/pay)
- CLI: [`agentaos`](https://www.npmjs.com/package/agentaos)
- Main repository: https://github.com/AgentaOS/agentaos
- Pricing: https://agentaos.ai/pricing
