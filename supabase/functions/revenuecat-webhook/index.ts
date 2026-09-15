// RevenueCat webhook. The Authorization header is the shared secret from the
// RevenueCat dashboard. JWT is off: this is not a user request.
import {
  applyBillingSnapshot,
  snapshotFromRevenueCatEvent,
  webhookAuthorized,
} from "../_shared/billing.ts";
import { cors, json } from "../_shared/db.ts";

export async function handleRevenueCatWebhook(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  if (!Deno.env.get("REVENUECAT_WEBHOOK_SECRET")) {
    return json({ error: "BILLING_WEBHOOK_UNCONFIGURED" }, 503);
  }
  if (!webhookAuthorized(req)) return json({ error: "UNAUTHORIZED" }, 401);

  let body: { event?: Record<string, unknown> };
  try {
    body = await req.json();
  } catch {
    return json({ error: "E_SCHEMA" }, 422);
  }
  const event = body.event;
  if (!event || typeof event !== "object") return json({ error: "E_SCHEMA" }, 422);

  const type = String(event.type ?? "").toUpperCase();
  if (type === "TRANSFER") {
    const fromIds = Array.isArray(event.transferred_from) ? event.transferred_from : [];
    for (const id of fromIds) {
      const snapshot = snapshotFromRevenueCatEvent({
        ...event,
        type: "EXPIRATION",
        app_user_id: id,
        expiration_at_ms: Date.now(),
        will_renew: false,
      });
      if (snapshot) await applyBillingSnapshot(snapshot);
    }
    const toIds = Array.isArray(event.transferred_to) ? event.transferred_to : [];
    for (const id of toIds) {
      const snapshot = snapshotFromRevenueCatEvent({ ...event, app_user_id: id, type: "RENEWAL" });
      if (snapshot) await applyBillingSnapshot(snapshot);
    }
    return json({ ok: true, type });
  }

  const snapshot = snapshotFromRevenueCatEvent(event);
  if (!snapshot) return json({ ok: true, ignored: true });
  await applyBillingSnapshot(snapshot);
  return json({ ok: true, type });
}

if (import.meta.main) {
  Deno.serve(handleRevenueCatWebhook);
}
