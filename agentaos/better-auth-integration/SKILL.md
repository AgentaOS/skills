---
name: better-auth-integration
description: AgentaOS plugin for Better Auth (@agentaos/better-auth) covering the agentaos() server plugin with an @agentaos/pay client, the products slug-to-linkId allowlist, successUrl, webhookSecret and onEvent, the agentaosClient() browser plugin, authClient.agentaos.checkout({ slug }), the three endpoints it mounts (POST /api/auth/agentaos/checkout, GET /api/auth/agentaos/subscriptions, POST /api/auth/agentaos/webhook), and idempotent, livemode-aware event handling. Use when an app signs users in with Better Auth and needs AgentaOS checkout, subscriptions or webhooks tied to the signed-in user; for other auth stacks use checkout-integration and webhook-integration.
---

# AgentaOS + Better Auth

`@agentaos/better-auth` connects AgentaOS to the users of a Better Auth app. A signed-in user starts a checkout by product slug; their email is prefilled and their user id goes into the checkout `metadata`. Webhook events are verified and handed to your `onEvent` with the matching `userId`.

## When to use this skill

- The app already uses Better Auth (`better-auth`)
- You want "Upgrade" to start a checkout for the signed-in user without writing checkout code
- You want verified AgentaOS events delivered with the user id resolved

If the app does not use Better Auth, use `checkout-integration` + `webhook-integration` (or `nextjs-integration`).

---

## What the plugin adds

| Endpoint | What it does |
|----------|--------------|
| `POST /api/auth/agentaos/checkout` | Starts a checkout for the signed-in user. Email prefilled, user id in `metadata`. |
| `GET /api/auth/agentaos/subscriptions` | Lists the signed-in user's subscriptions. The user's email must be verified. |
| `POST /api/auth/agentaos/webhook` | Verifies each AgentaOS event's signature and passes it to `onEvent`. |

A user can only buy a product listed in `products`, by its `slug`. Product, price and return URLs come from your server config, never from the browser.

---

## Step 1: Prepare AgentaOS

1. In the dashboard, create the products users can buy. On each product page copy the link ID (**Building this into your site?**, **Copy ID**). This is the UUID, not the `/pay/` token.
2. **Developers, API keys**: create a key. `sk_test_` works in test mode.
3. **Settings, Developers, Webhooks**: set the URL to `https://your-domain.com/api/auth/agentaos/webhook`. Click **Reveal signing secret** and copy it.

```bash
# .env
AGENTAOS_API_KEY=sk_test_...
AGENTAOS_WEBHOOK_SECRET=whsec_...
```

## Step 2: Install

```bash
npm install @agentaos/better-auth @agentaos/pay
```

## Step 3: Add the server plugin

```typescript
// auth.ts
import { AgentaOS } from '@agentaos/pay';
import { agentaos } from '@agentaos/better-auth';
import { betterAuth } from 'better-auth';

export const auth = betterAuth({
  // ...your existing config (database, emailAndPassword, socialProviders)
  plugins: [
    agentaos({
      client: new AgentaOS(process.env.AGENTAOS_API_KEY!),
      products: [
        { slug: 'pro', productId: process.env.PRO_LINK_ID! },
        { slug: 'pro-yearly', productId: process.env.PRO_YEARLY_LINK_ID! },
      ],
      successUrl: 'https://your-domain.com/thanks',
      webhookSecret: process.env.AGENTAOS_WEBHOOK_SECRET,
      onEvent: async ({ event, userId }) => {
        // see Step 5
      },
    }),
  ],
});
```

`successUrl` must be `https://`.

## Step 4: Start a checkout from the browser

```typescript
// auth-client.ts
import { createAuthClient } from 'better-auth/client';
import { agentaosClient } from '@agentaos/better-auth/client';

export const authClient = createAuthClient({ plugins: [agentaosClient()] });
```

```typescript
// on the Upgrade button
const { data, error } = await authClient.agentaos.checkout({ slug: 'pro' });
if (error) {
  showError(error.message);
} else {
  window.location.href = data!.url;
}
```

In test mode, pay with `4242 4242 4242 4242`, any future expiry, any CVC.

## Step 5: Handle events

`onEvent` receives every event after its signature is checked. For `checkout.session.completed`, `userId` is the user who started the checkout.

```typescript
onEvent: async ({ event, userId }) => {
  const isLiveServer = process.env.AGENTAOS_API_KEY!.startsWith('sk_live_');
  if ('livemode' in event.data && event.data.livemode !== isLiveServer) return; // ignore test events in live

  if (event.type === 'checkout.session.completed' && userId) {
    const { sessionId, linkId, metadata } = event.data;
    // linkId here is the buyer-link token of the product, not its UUID
    await db.transaction(async (tx) => {
      const inserted = await tx.processedSessions.insertIgnore({ sessionId }); // unique on sessionId
      if (!inserted) return; // already granted
      await tx.entitlements.grant({
        userId,
        productToken: linkId,
        subscriptionId: typeof metadata.subscriptionId === 'string' ? metadata.subscriptionId : null,
      });
    });
  }

  if (event.type === 'subscription.canceled') {
    await db.entitlements.revokeBySubscription(event.data.id);
  }
},
```

Rules:

- Give the product once per checkout: save `event.data.sessionId` and skip repeats. Events can arrive more than once.
- Check `event.data.livemode`. Test and live events share one endpoint.
- `checkout.session.completed` sends `linkId` as the product's buyer-link token (the last part of its `/pay/` URL), not the UUID you configured as `productId`. Map tokens to slugs in your config, or store `metadata.subscriptionId` and resolve the plan from `subscriptions.list()` (its `linkId` is the UUID).
- Renewals fire `checkout.session.completed` without your metadata, so `userId` may be absent on renewals. Match them by `metadata.subscriptionId`, which you stored on the first payment.
- A free-trial start has `amount: "0"`. Treat it as "trial started".

Full event list and payloads: see `webhook-integration`.

## Step 6: Show the user's subscriptions

The plugin mounts `GET /api/auth/agentaos/subscriptions` for the signed-in user (verified email required). The docs do not document the response shape or a typed client method for it, so inspect the response in your app before relying on fields. For managing a subscription (cancel, plan change), call `@agentaos/pay` from your server with the stored subscription id; see `subscription-integration`.

---

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Passing price or productId from the browser | Only `slug` comes from the browser; products live in server config |
| `productId` set to the `/pay/` token | Use the product's link ID (UUID) |
| Webhook URL left at a custom path | It must be `https://your-domain.com/api/auth/agentaos/webhook` (adjust if your Better Auth base path differs) |
| Granting access twice | Dedupe on `sessionId` |
| Comparing event `linkId` to `productId` | Different values: token vs UUID |
| Expecting subscriptions for unverified emails | The endpoint requires a verified email |
| Using `@agentaos/pay` in the browser | Server only |

## Docs

- Better Auth plugin: https://docs.agentaos.ai/sdk/better-auth
- Event reference: https://docs.agentaos.ai/webhooks/events
- SDK subscriptions: https://docs.agentaos.ai/sdk/pay-subscriptions
- Test mode: https://docs.agentaos.ai/getting-started/test-mode
