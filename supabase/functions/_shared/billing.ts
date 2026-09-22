import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { billingEnvironmentAllowed } from "./billing-environment.ts";
import { json, serviceClient } from "./db.ts";
import { fetchRevenueCatV2, type RevenueCatCustomer } from "./billing-revenuecat-v2.ts";

// RevenueCat's catalog identifier maps to the existing local `pro` AI capability.
// The trusted SQL writer owns that local name; it is never a client/RC input.
export const REVENUECAT_PRO_ENTITLEMENT = "next_pro";
export { ALL_PRO_PRODUCT_IDS, PRO_PRODUCT_IDS, TEST_STORE_PRO_PRODUCT_IDS } from "./billing-product-ids.ts";
import { ALL_PRO_PRODUCT_IDS } from "./billing-product-ids.ts";
// Kept for the tests and callers that name the original plan.
export const PRO_PRODUCT_ID = "hoop_pro_monthly";
export const TEST_STORE_PRO_PRODUCT_ID = "monthly";

export type EntitlementDecision =
  | { allowed: true; introClaimed: boolean }
  | { allowed: false; introClaimed: boolean; reason: "missing" | "expired" | "unavailable" };

export type BillingSnapshot = {
  owner: string;
  observedAt: string;
  productId: string | null;
  store: string | null;
  periodType: string | null;
  expiresAt: string | null;
  willRenew: boolean;
  introClaimed: boolean;
  rcAppUserId: string | null;
};

export async function requireProEntitlement(
  db: SupabaseClient,
): Promise<EntitlementDecision> {
  try {
    const { data, error } = await db.auth.getUser();
    if (error || !data.user) {
      return { allowed: false, introClaimed: false, reason: "unavailable" };
    }
    const result = await serviceClient().rpc("require_pro_entitlement_trusted", {
      p_owner: data.user.id,
    });
    if (result.error || typeof result.data?.allowed !== "boolean") {
      return { allowed: false, introClaimed: false, reason: "unavailable" };
    }
    const introClaimed = result.data.intro_claimed === true;
    if (result.data.allowed) return { allowed: true, introClaimed };
    return {
      allowed: false,
      introClaimed,
      reason: result.data.reason === "expired" ? "expired" : "missing",
    };
  } catch {
    return { allowed: false, introClaimed: false, reason: "unavailable" };
  }
}

export function subscriptionRequiredResponse(
  decision: Extract<EntitlementDecision, { allowed: false }>,
): Response {
  return json(
    {
      error: "SUBSCRIPTION_REQUIRED",
      intro_claimed: decision.introClaimed,
    },
    402,
  );
}

export function periodClaimsIntro(periodType: string | null | undefined): boolean {
  const period = (periodType ?? "").toLowerCase();
  return period === "trial" || period === "intro" || period === "introductory";
}

export async function applyBillingSnapshot(snapshot: BillingSnapshot): Promise<void> {
  const result = await serviceClient().rpc("apply_billing_entitlement_trusted", {
    p_owner: snapshot.owner,
    p_observed_at: snapshot.observedAt,
    p_product_id: snapshot.productId,
    p_store: snapshot.store,
    p_period_type: snapshot.periodType,
    p_expires_at: snapshot.expiresAt,
    p_will_renew: snapshot.willRenew,
    p_intro_claimed: snapshot.introClaimed,
    p_rc_app_user_id: snapshot.rcAppUserId,
  });
  if (result.error) throw new Error(`BILLING_APPLY_FAILED: ${result.error.message}`);
}

// Events identify accounts and preserve historical trial evidence. Access is
// always refreshed from RevenueCat, never inferred from a partial event.
export function revenueCatEventOwners(event: Record<string, unknown>): string[] {
  const ids = String(event.type).toUpperCase() === "TRANSFER"
    ? [...(Array.isArray(event.transferred_from) ? event.transferred_from : []),
       ...(Array.isArray(event.transferred_to) ? event.transferred_to : [])]
    : [event.app_user_id, event.original_app_user_id,
       ...(Array.isArray(event.aliases) ? event.aliases : [])];
  return [...new Set(ids.map(asUuid).filter((id): id is string => id !== null))];
}

export function eventClaimsIntro(event: Record<string, unknown>, owner?: string): boolean {
  return billingEnvironmentAllowed(owner, event) &&
    ALL_PRO_PRODUCT_IDS.includes(String(event.product_id)) &&
    periodClaimsIntro(asString(event.period_type));
}

export function snapshotFromRevenueCatSubscriber(
  owner: string,
  subscriber: Record<string, unknown>,
  observedAt = new Date().toISOString(),
): BillingSnapshot {
  const entitlements = asRecord(subscriber.entitlements);
  const pro = asRecord(entitlements?.[REVENUECAT_PRO_ENTITLEMENT]);
  const subscriptions = asRecord(subscriber.subscriptions);
  // Without an entitlement naming the product, the first known plan the subscriber holds.
  const knownProductId = ALL_PRO_PRODUCT_IDS.find(id => asRecord(subscriptions?.[id]) != null) ?? null;
  const known_ = knownProductId ? asRecord(subscriptions?.[knownProductId]) : null;
  const productId = asString(pro?.product_identifier) ??
    asString(pro?.product_id) ??
    knownProductId;
  const subscription = (productId ? asRecord(subscriptions?.[productId]) : null) ?? known_;
  const periodType = asString(pro?.period_type) ?? asString(subscription?.period_type);
  const expiresAt = asString(pro?.expires_date) ?? asString(subscription?.expires_date);
  const unsubscribed = subscription?.unsubscribe_detected_at != null;
  const known = pro != null && productId != null;
  return {
    owner,
    observedAt,
    productId: known ? productId : null,
    store: normalizeStore(asString(subscription?.store) ?? asString(pro?.store)),
    periodType,
    // A subscriber with no product must not look like a lifetime grant
    // (`expires_at` null + leftover `product_id`). Stamp a past expiry.
    expiresAt: known ? (asString(subscription?.grace_period_expires_date) ?? expiresAt) : "1970-01-01T00:00:00.000Z",
    willRenew: !unsubscribed && expiresAt != null,
    introClaimed: periodClaimsIntro(periodType),
    rcAppUserId: owner,
  };
}

export function webhookAuthorized(req: Request): boolean {
  const expected = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
  if (!expected) return false;
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  return timingSafeEqual(token, expected) || timingSafeEqual(header, expected);
}

export async function fetchRevenueCatSubscriber(
  appUserId: string,
): Promise<RevenueCatCustomer | null> {
  const key = Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? "";
  const project = Deno.env.get("REVENUECAT_PROJECT_ID") ?? "";
  if (!key || !project) return null;
  return await fetchRevenueCatV2(appUserId, project, key);
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function asUuid(value: unknown): string | null {
  const text = asString(value);
  if (!text) return null;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
    ? text
    : null;
}

function normalizeStore(value: string | null): string | null {
  if (!value) return null;
  const store = value.toLowerCase();
  if (store === "app_store" || store === "mac_app_store" || store === "apple") return "app_store";
  if (store === "play_store" || store === "play") return "play_store";
  return store;
}

function timingSafeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
