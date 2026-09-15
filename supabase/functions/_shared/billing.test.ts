import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  periodClaimsIntro,
  snapshotFromRevenueCatEvent,
  snapshotFromRevenueCatSubscriber,
} from "./billing.ts";

Deno.test("trial and intro periods claim the free month", () => {
  assertEquals(periodClaimsIntro("TRIAL"), true);
  assertEquals(periodClaimsIntro("intro"), true);
  assertEquals(periodClaimsIntro("normal"), false);
});

Deno.test("a trial purchase event maps onto the health account UUID", () => {
  const snapshot = snapshotFromRevenueCatEvent({
    type: "INITIAL_PURCHASE",
    app_user_id: "aaaaaaaa-1111-1111-1111-111111111111",
    product_id: "hoop_pro_monthly",
    period_type: "TRIAL",
    expiration_at_ms: Date.parse("2026-10-15T00:00:00Z"),
    store: "APP_STORE",
    will_renew: true,
  });
  assertEquals(snapshot?.owner, "aaaaaaaa-1111-1111-1111-111111111111");
  assertEquals(snapshot?.introClaimed, true);
  assertEquals(snapshot?.productId, "hoop_pro_monthly");
  assertEquals(snapshot?.store, "app_store");
  assertEquals(snapshot?.expiresAt, "2026-10-15T00:00:00.000Z");
});

Deno.test("an anonymous RevenueCat id is not written as a health account", () => {
  assertEquals(snapshotFromRevenueCatEvent({
    type: "INITIAL_PURCHASE",
    app_user_id: "$RCAnonymousID:abc",
    product_id: "hoop_pro_monthly",
  }), null);
});

Deno.test("expiration keeps intro_claimed and writes a past expiry", () => {
  const snapshot = snapshotFromRevenueCatEvent({
    type: "EXPIRATION",
    app_user_id: "aaaaaaaa-1111-1111-1111-111111111111",
    product_id: "hoop_pro_monthly",
    period_type: "NORMAL",
    expiration_at_ms: Date.parse("2026-09-01T00:00:00Z"),
  });
  assertEquals(snapshot?.introClaimed, false);
  assertEquals(snapshot?.expiresAt, "2026-09-01T00:00:00.000Z");
  assertEquals(snapshot?.willRenew, false);
});

Deno.test("a subscriber payload with an active entitlement is Pro", () => {
  const snapshot = snapshotFromRevenueCatSubscriber(
    "aaaaaaaa-1111-1111-1111-111111111111",
    {
      original_app_user_id: "aaaaaaaa-1111-1111-1111-111111111111",
      entitlements: {
        pro: {
          expires_date: "2026-10-15T00:00:00Z",
          product_identifier: "hoop_pro_monthly",
          period_type: "trial",
        },
      },
      subscriptions: {
        hoop_pro_monthly: {
          expires_date: "2026-10-15T00:00:00Z",
          period_type: "trial",
          store: "app_store",
        },
      },
    },
  );
  assertEquals(snapshot.introClaimed, true);
  assertEquals(snapshot.willRenew, true);
  assertEquals(snapshot.productId, "hoop_pro_monthly");
});

Deno.test("a subscriber with no product is not a lifetime grant", () => {
  const snapshot = snapshotFromRevenueCatSubscriber(
    "aaaaaaaa-1111-1111-1111-111111111111",
    {
      original_app_user_id: "aaaaaaaa-1111-1111-1111-111111111111",
      entitlements: {},
      subscriptions: {},
    },
  );
  assertEquals(snapshot.productId, null);
  assertEquals(snapshot.introClaimed, false);
  assertEquals(snapshot.willRenew, false);
  assertEquals(snapshot.expiresAt != null, true);
});
