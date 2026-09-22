// RevenueCat webhook. The Authorization header is the shared secret from the
// RevenueCat dashboard. JWT is off: this is not a user request.
import {
  applyBillingSnapshot,
  eventClaimsIntro,
  fetchRevenueCatSubscriber,
  revenueCatEventOwners,
  snapshotFromRevenueCatSubscriber,
  webhookAuthorized,
} from "../_shared/billing.ts";
import { cors, json } from "../_shared/db.ts";

type WebhookDependencies = {
  fetchSubscriber: typeof fetchRevenueCatSubscriber;
  applySnapshot: typeof applyBillingSnapshot;
};

export async function handleRevenueCatWebhook(req: Request, deps: WebhookDependencies = {
  fetchSubscriber: fetchRevenueCatSubscriber,
  applySnapshot: applyBillingSnapshot,
}): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  if (!Deno.env.get("REVENUECAT_WEBHOOK_SECRET")) {
    return json({ error: "BILLING_WEBHOOK_UNCONFIGURED" }, 503);
  }
  if (!webhookAuthorized(req)) return json({ error: "UNAUTHORIZED" }, 401);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "E_SCHEMA" }, 422);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json({ error: "E_SCHEMA" }, 422);
  }
  const event = (body as { event?: unknown }).event;
  if (!event || typeof event !== "object" || Array.isArray(event)) {
    return json({ error: "E_SCHEMA" }, 422);
  }
  const payload = event as Record<string, unknown>;

  const type = String(payload.type ?? "").toUpperCase();
  const owners = revenueCatEventOwners(payload);
  if (owners.length === 0 || type === "TEST") return json({ ok: true, ignored: true });
  try {
    for (const owner of owners) {
      const customer = await deps.fetchSubscriber(owner);
      if (!customer) return json({ error: "BILLING_SYNC_UNAVAILABLE" }, 503);
      const snapshot = snapshotFromRevenueCatSubscriber(owner, customer.subscriber, customer.observedAt);
      snapshot.introClaimed ||= customer.introClaimed === true || eventClaimsIntro(payload, owner);
      await deps.applySnapshot(snapshot);
    }
    return json({ ok: true, type });
  } catch {
    // Non-2xx makes RevenueCat retry; acknowledge only persisted state.
    return json({ error: "BILLING_SYNC_UNAVAILABLE" }, 503);
  }
}

if (import.meta.main) {
  Deno.serve((req) => handleRevenueCatWebhook(req));
}
