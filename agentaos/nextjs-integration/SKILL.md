---
name: nextjs-integration
description: AgentaOS in Next.js App Router with @agentaos/pay, covering a server-only client module, a checkout route handler and server action that create a checkout from a product linkId with the signed-in user's id in metadata, a success page that confirms with checkouts.retrieve, a webhook route handler that reads the raw body with req.text() and verifies X-AgentaOS-Signature with agentaos.webhooks.verify(), the Node.js runtime requirement, env vars, cancel and plan-change server actions, and the embedded checkout React component. Use when adding AgentaOS payments, a paywall, subscriptions or webhooks to a Next.js 13+ app with the app/ directory.
---

# AgentaOS in Next.js (App Router)

There is no AgentaOS-specific Next.js adapter. Use `@agentaos/pay` directly inside route handlers, server actions and server components. The SDK is server-only and ESM-only, which fits the App Router.

## When to use this skill

- Adding a Buy or Upgrade button to a Next.js App Router app
- Writing the webhook route handler
- Confirming payment on a success page
- Adding cancel and upgrade actions to a billing page
- Embedding the checkout in a client component

For concepts (products vs checkouts, ids, money model) see `agentaos-best-practices`. For event details see `webhook-integration`.

---

## Setup

```bash
npm install @agentaos/pay
# optional, for the embedded checkout
npm install @agentaos/checkout
```

```bash
# .env.local (never commit)
AGENTAOS_API_KEY=sk_test_...
AGENTAOS_WEBHOOK_SECRET=whsec_...
PRO_LINK_ID=4cbb8f52-7cf2-4480-8c66-34f794cd23d0
PRO_PLUS_LINK_ID=...
APP_URL=https://yourapp.com
```

Never prefix these with `NEXT_PUBLIC_`. The API key grants full access to payments, customers and invoices.

### Server-only client

```typescript
// lib/agentaos.ts
import 'server-only';
import { AgentaOS } from '@agentaos/pay';

export const agentaos = new AgentaOS(process.env.AGENTAOS_API_KEY!);
```

`import 'server-only'` makes the build fail if a client component imports this file. The SDK constructor also throws if it detects `window` or `document`.

Use the Node.js runtime for every route that imports the SDK. It needs Node.js 20+ and uses `node:crypto` for verification:

```typescript
export const runtime = 'nodejs';
```

---

## Checkout route handler

```typescript
// app/api/checkout/route.ts
import { NextResponse } from 'next/server';
import { agentaos } from '@/lib/agentaos';
import { getCurrentUser, saveUser } from '@/lib/auth'; // your own

export const runtime = 'nodejs';

export async function POST() {
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: 'Sign in first' }, { status: 401 });

  // Reuse an open checkout on double click (rate limit is 60 creates/min per IP, shared)
  if (user.pendingSessionId) {
    const pending = await agentaos.checkouts.retrieve(user.pendingSessionId);
    if (pending.status === 'open') return NextResponse.redirect(pending.checkoutUrl, 303);
  }

  const checkout = await agentaos.checkouts.create({
    linkId: process.env.PRO_LINK_ID!,
    buyerEmail: user.email,
    metadata: { customerId: user.id },               // camelCase keys
    successUrl: `${process.env.APP_URL}/billing/success`, // https only; ?sessionId= is appended
    cancelUrl: `${process.env.APP_URL}/pricing`,
  });

  await saveUser(user.id, { pendingSessionId: checkout.sessionId });
  return NextResponse.redirect(checkout.checkoutUrl, 303);
}
```

```tsx
// app/pricing/page.tsx
export default function Pricing() {
  return (
    <form action="/api/checkout" method="post">
      <button type="submit">Upgrade to Pro</button>
    </form>
  );
}
```

### Same thing as a server action

```typescript
// app/billing/actions.ts
'use server';
import { redirect } from 'next/navigation';
import { agentaos } from '@/lib/agentaos';
import { getCurrentUser } from '@/lib/auth';

export async function startCheckout() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  const checkout = await agentaos.checkouts.create({
    linkId: process.env.PRO_LINK_ID!,
    buyerEmail: user.email,
    metadata: { customerId: user.id },
    successUrl: `${process.env.APP_URL}/billing/success`,
  });
  redirect(checkout.checkoutUrl);
}
```

Call `redirect()` outside any `try` block: it works by throwing.

---

## Success page (server component)

The redirect alone is not proof. Read the checkout and check ownership.

```tsx
// app/billing/success/page.tsx
import { agentaos } from '@/lib/agentaos';
import { getCurrentUser } from '@/lib/auth';
import { grantProOnce } from '@/lib/billing';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export default async function Success({ searchParams }: { searchParams: Promise<{ sessionId?: string }> }) {
  const { sessionId } = await searchParams; // Next 15: searchParams is a Promise; in Next 13/14 it is a plain object
  const user = await getCurrentUser();
  if (!sessionId || !user) return <p>Not found</p>;

  const checkout = await agentaos.checkouts.retrieve(sessionId);
  if (checkout.metadata.customerId !== user.id) return <p>Not found</p>;

  if (checkout.status === 'completed') {
    const subscriptionId = typeof checkout.metadata.subscriptionId === 'string' ? checkout.metadata.subscriptionId : null;
    await grantProOnce({ userId: user.id, subscriptionId, sessionId });
    return <p>You are on Pro.</p>;
  }
  if (checkout.status === 'open') return <p>Still processing. Refresh in a moment.</p>;
  return <p>This checkout {checkout.status}. Try again from the pricing page.</p>;
}
```

A free-trial checkout can stay `open` for a short time after the buyer returns.

---

## Webhook route handler

```typescript
// app/api/webhooks/agentaos/route.ts
import { WebhookVerificationError } from '@agentaos/pay';
import { agentaos } from '@/lib/agentaos';
import { grantProOnce, recordRenewalOnce, syncSubscription } from '@/lib/billing';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(req: Request) {
  const rawBody = await req.text(); // raw body; do NOT call req.json() first
  const signature = req.headers.get('x-agentaos-signature') ?? '';

  let event;
  try {
    event = agentaos.webhooks.verify(rawBody, signature, process.env.AGENTAOS_WEBHOOK_SECRET!);
  } catch (err) {
    if (err instanceof WebhookVerificationError) return new Response('Invalid signature', { status: 400 });
    return new Response('Webhook processing failed', { status: 500 });
  }

  const isLiveServer = process.env.AGENTAOS_API_KEY!.startsWith('sk_live_');
  if ('livemode' in event.data && event.data.livemode !== isLiveServer) return new Response('ignored', { status: 200 });

  switch (event.type) {
    case 'checkout.session.completed': {
      const { sessionId, metadata } = event.data;
      const subscriptionId = typeof metadata.subscriptionId === 'string' ? metadata.subscriptionId : null;
      if (typeof metadata.customerId === 'string') {
        await grantProOnce({ userId: metadata.customerId, subscriptionId, sessionId });
      } else if (subscriptionId) {
        await recordRenewalOnce({ subscriptionId, sessionId }); // renewals carry no customerId
      }
      break;
    }
    case 'subscription.updated':
    case 'subscription.canceled':
    case 'subscription.payment_failed':
    case 'subscription.renewed':
      await syncSubscription(event.data.id, event.data.status, event.data.currentPeriodEnd);
      break;
  }

  return new Response('ok', { status: 200 });
}
```

Register `https://yourapp.com/api/webhooks/agentaos` in **Settings, Developers, Webhooks** and copy the secret. Make sure middleware (auth, i18n, rewrites) does not intercept or redirect this path: AgentaOS treats any `3xx` as a failed delivery and does not follow it.

`grantProOnce` and `recordRenewalOnce` must be idempotent on `sessionId` (a unique constraint in your database), because the success page and the webhook both report the first payment, and deliveries retry.

---

## Billing page actions

```typescript
// app/billing/actions.ts
'use server';
import { revalidatePath } from 'next/cache';
import { agentaos } from '@/lib/agentaos';
import { getCurrentUser } from '@/lib/auth';

export async function cancelPlan() {
  const user = await getCurrentUser();
  if (!user?.subscriptionId) return;
  await agentaos.subscriptions.cancel(user.subscriptionId); // at period end, no refund
  revalidatePath('/billing');
}

export async function quoteUpgrade() {
  const user = await getCurrentUser();
  if (!user?.subscriptionId) return null;
  return agentaos.subscriptions.previewPlanChange(user.subscriptionId, process.env.PRO_PLUS_LINK_ID!);
}

export async function confirmUpgrade(prorationDate: number) {
  const user = await getCurrentUser();
  if (!user?.subscriptionId) return;
  await agentaos.subscriptions.changePlan(user.subscriptionId, {
    targetLinkId: process.env.PRO_PLUS_LINK_ID!,
    prorationDate, // from the quote the user saw
  });
  revalidatePath('/billing');
}
```

Show `quote.dueTodayMinor` and `quote.nextInvoiceMinor` (minor units) to the user before calling `confirmUpgrade`. There is no hosted customer portal; this page is the portal.

Invoice PDF download:

```typescript
// app/api/invoices/[id]/route.ts
import { agentaos } from '@/lib/agentaos';
import { getCurrentUser } from '@/lib/auth';
export const runtime = 'nodejs';

export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await getCurrentUser();
  if (!user?.subscriptionId) return new Response('Not found', { status: 404 });
  const invoices = await agentaos.subscriptions.invoices(user.subscriptionId);
  const invoice = invoices.find((i) => i.id === id);
  if (!invoice) return new Response('Not found', { status: 404 });
  const pdf = await agentaos.invoices.downloadPdf(id); // Buffer
  return new Response(new Uint8Array(pdf), {
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': `attachment; filename="invoice-${invoice.invoiceNumber}.pdf"`,
    },
  });
}
```

---

## Embedded checkout (client component)

```tsx
// app/pricing/embedded.tsx
'use client';
import { AgentaOSCheckout } from '@agentaos/checkout/react';

export function EmbeddedCheckout({ sessionId }: { sessionId: string }) {
  return (
    <AgentaOSCheckout
      session={sessionId}               // created on the server with checkouts.create
      onEvent={(e) => console.log(e.name, e.data)}
    />
  );
}
```

Create the checkout in a server action or route handler and pass only `sessionId` to the client. Add your origin under **Settings, Developers, Approved sites** (test products also load on `localhost`). The `checkout.completed` browser event is not proof of payment; confirm on the server.

---

## Local development

- AgentaOS does not deliver webhooks to `localhost`. Use a public HTTPS tunnel to `http://localhost:3000` and register `https://<tunnel>/api/webhooks/agentaos`.
- `successUrl` and `cancelUrl` must be `https://`. `https://localhost` is refused; use your tunnel URL as `APP_URL`, or serve on `https://127.0.0.1` with a self-signed certificate (`next dev --experimental-https` can generate one).

---

## Common mistakes

| Mistake | Fix |
|---------|-----|
| `await req.json()` in the webhook route | `await req.text()`, verify, then use the returned event |
| Edge runtime on SDK routes | `export const runtime = 'nodejs'` |
| Importing `lib/agentaos.ts` in a `'use client'` file | Keep it server-only; pass ids or URLs to the client |
| `NEXT_PUBLIC_AGENTAOS_API_KEY` | Never expose the key |
| Static rendering of the success page | `dynamic = 'force-dynamic'`, read `sessionId` per request |
| `redirect()` inside `try/catch` | Call it after the try block |
| Middleware redirecting `/api/webhooks/...` | Exclude the webhook path from middleware matchers |
| Creating a checkout in a server component on render | Create on form submit; rate limit is shared |

## Docs

- SDK overview: https://docs.agentaos.ai/sdk/pay-overview
- SDK checkouts: https://docs.agentaos.ai/sdk/pay-checkouts
- SDK webhooks: https://docs.agentaos.ai/sdk/pay-webhooks
- SDK subscriptions: https://docs.agentaos.ai/sdk/pay-subscriptions
- Paywall for logged-in users (reference flow): https://docs.agentaos.ai/sdk/paywall-for-logged-in-users
- Embedded checkout: https://docs.agentaos.ai/payments/embedded-checkout
- Event reference: https://docs.agentaos.ai/webhooks/events
