// After a store purchase the client asks us to re-read RevenueCat and write
// billing_entitlements. The phone never sends product state — we fetch it.
import { currentUserId, cors, json } from "../_shared/db.ts";
import {
  applyBillingSnapshot,
  fetchRevenueCatSubscriber,
  snapshotFromRevenueCatSubscriber,
} from "../_shared/billing.ts";

type BillingSyncDependencies = {
  authenticate: typeof currentUserId;
  fetchSubscriber: typeof fetchRevenueCatSubscriber;
  applySnapshot: typeof applyBillingSnapshot;
};

export async function handleBillingSync(req: Request, deps: BillingSyncDependencies = {
  authenticate: currentUserId,
  fetchSubscriber: fetchRevenueCatSubscriber,
  applySnapshot: applyBillingSnapshot,
}): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  const userId = await deps.authenticate(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);
  if (!Deno.env.get("REVENUECAT_SECRET_API_KEY") || !Deno.env.get("REVENUECAT_PROJECT_ID")) {
    return json({ error: "BILLING_SYNC_UNCONFIGURED" }, 503);
  }
  try {
    const customer = await deps.fetchSubscriber(userId);
    if (!customer) return json({ error: "BILLING_SYNC_UNAVAILABLE" }, 503);
    const snapshot = snapshotFromRevenueCatSubscriber(userId, customer.subscriber, customer.observedAt);
    snapshot.introClaimed ||= customer.introClaimed === true;
    await deps.applySnapshot(snapshot);
    return json({ ok: true });
  } catch {
    return json({ error: "BILLING_SYNC_UNAVAILABLE" }, 503);
  }
}

if (import.meta.main) {
  Deno.serve((req) => handleBillingSync(req));
}
