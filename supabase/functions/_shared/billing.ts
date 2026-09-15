import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { json, serviceClient } from "./db.ts";

export const PRO_ENTITLEMENT = "pro";
export const PRO_PRODUCT_ID = "hoop_pro_monthly";

export type EntitlementDecision =
  | { allowed: true; introClaimed: boolean }
  | { allowed: false; introClaimed: boolean; reason: "missing" | "expired" | "unavailable" };

export type BillingSnapshot = {
  owner: string;
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

export function snapshotFromRevenueCatEvent(
  event: Record<string, unknown>,
): BillingSnapshot | null {
  const owner = asUuid(event.app_user_id) ?? asUuid(event.original_app_user_id);
  if (!owner) return null;
  const type = String(event.type ?? "").toUpperCase();
  const periodType = asString(event.period_type);
  const expiresAt = msToIso(event.expiration_at_ms);
  const expired = type === "EXPIRATION" || type === "SUBSCRIPTION_PAUSED";
  return {
    owner,
    productId: asString(event.product_id) ?? PRO_PRODUCT_ID,
    store: normalizeStore(asString(event.store)),
    periodType,
    expiresAt: expired ? (expiresAt ?? new Date().toISOString()) : expiresAt,
    willRenew: event.will_renew === true ||
      (event.unsubscribe_detected_at == null && !expired && type !== "CANCELLATION"),
    introClaimed: periodClaimsIntro(periodType) || type === "INITIAL_PURCHASE",
    rcAppUserId: owner,
  };
}

export function snapshotFromRevenueCatSubscriber(
  owner: string,
  subscriber: Record<string, unknown>,
): BillingSnapshot {
  const entitlements = asRecord(subscriber.entitlements);
  const pro = asRecord(entitlements?.[PRO_ENTITLEMENT]);
  const subscriptions = asRecord(subscriber.subscriptions);
  const monthly = asRecord(subscriptions?.[PRO_PRODUCT_ID]);
  const productId = asString(pro?.product_identifier) ??
    asString(pro?.product_id) ??
    (monthly ? PRO_PRODUCT_ID : null);
  const subscription = (productId ? asRecord(subscriptions?.[productId]) : null) ?? monthly;
  const periodType = asString(pro?.period_type) ?? asString(subscription?.period_type);
  const expiresAt = asString(pro?.expires_date) ?? asString(subscription?.expires_date);
  const unsubscribed = subscription?.unsubscribe_detected_at != null;
  const known = pro != null || subscription != null;
  return {
    owner,
    productId,
    store: normalizeStore(asString(subscription?.store) ?? asString(pro?.store)),
    periodType,
    // A subscriber with no product must not look like a lifetime grant
    // (`expires_at` null + leftover `product_id`). Stamp a past expiry.
    expiresAt: expiresAt ?? (known ? null : new Date().toISOString()),
    willRenew: !unsubscribed && expiresAt != null,
    introClaimed: periodClaimsIntro(periodType) || known,
    rcAppUserId: asString(subscriber.original_app_user_id) ?? owner,
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
): Promise<Record<string, unknown> | null> {
  const key = Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? "";
  if (!key) return null;
  const res = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
    { headers: { Authorization: `Bearer ${key}` } },
  );
  if (!res.ok) return null;
  const body = await res.json() as { subscriber?: Record<string, unknown> };
  return body.subscriber ?? null;
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

function msToIso(value: unknown): string | null {
  const ms = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(ms) || ms <= 0) return null;
  return new Date(ms).toISOString();
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
