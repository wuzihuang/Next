import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  periodClaimsIntro,
  revenueCatEventOwners,
  eventClaimsIntro,
  snapshotFromRevenueCatSubscriber,
} from "./billing.ts";

Deno.test("trial and intro periods claim the free month", () => {
  assertEquals(periodClaimsIntro("TRIAL"), true);
  assertEquals(periodClaimsIntro("intro"), true);
  assertEquals(periodClaimsIntro("normal"), false);
});

Deno.test("webhook resolves health UUID aliases and both transfer sides", () => {
  const owner = "aaaaaaaa-1111-1111-1111-111111111111";
  assertEquals(revenueCatEventOwners({app_user_id: "$RCAnonymousID:abc", aliases: [owner, owner]}), [owner]);
  assertEquals(revenueCatEventOwners({type: "TRANSFER", transferred_from: [owner], transferred_to: ["$RCAnonymousID:abc"]}), [owner]);
  assertEquals(eventClaimsIntro({environment: "PRODUCTION", store: "APP_STORE", type: "INITIAL_PURCHASE", product_id: "hoop_pro_monthly", period_type: "NORMAL"}), false);
  assertEquals(eventClaimsIntro({environment: "PRODUCTION", store: "APP_STORE", product_id: "other", period_type: "TRIAL"}), false);
  assertEquals(eventClaimsIntro({environment: "PRODUCTION", store: "APP_STORE", product_id: "hoop_pro_monthly", period_type: "TRIAL"}), true);
  assertEquals(eventClaimsIntro({environment: "PRODUCTION", store: "APP_STORE", product_id: "monthly", period_type: "TRIAL"}), true);
  assertEquals(eventClaimsIntro({environment: "PRODUCTION", store: "APP_STORE", product_id: "monthly", period_type: "NORMAL"}), false);
});

Deno.test("the former RevenueCat pro entitlement cannot grant the local AI capability", () => {
  const snapshot = snapshotFromRevenueCatSubscriber("owner", {
    entitlements: {pro: {product_identifier: "hoop_pro_monthly", expires_date: "2099-01-01T00:00:00Z"}},
    subscriptions: {hoop_pro_monthly: {expires_date: "2099-01-01T00:00:00Z", period_type: "normal"}},
  });
  assertEquals(snapshot.productId, null);
  assertEquals(snapshot.expiresAt, "1970-01-01T00:00:00.000Z");
});

Deno.test("next_pro reads the Test Store monthly subscription and its trial", () => {
  const snapshot = snapshotFromRevenueCatSubscriber("owner", {
    entitlements: {next_pro: {product_identifier: "monthly", expires_date: "2099-01-01T00:00:00Z"}},
    subscriptions: {monthly: {expires_date: "2099-01-01T00:00:00Z", period_type: "trial", store: "test_store"}},
  });
  assertEquals(snapshot.productId, "monthly");
  assertEquals(snapshot.store, "test_store");
  assertEquals(snapshot.expiresAt, "2099-01-01T00:00:00Z");
  assertEquals(snapshot.introClaimed, true);
});

Deno.test("Test Store monthly without next_pro never creates lifetime or active access", () => {
  const snapshot = snapshotFromRevenueCatSubscriber("owner", {
    entitlements: {}, subscriptions: {monthly: {expires_date: null, period_type: "trial"}},
  });
  assertEquals(snapshot.productId, null);
  assertEquals(snapshot.expiresAt, "1970-01-01T00:00:00.000Z");
  assertEquals(snapshot.introClaimed, true);
});

Deno.test("a subscriber payload with an active entitlement is Pro", () => {
  const snapshot = snapshotFromRevenueCatSubscriber(
    "aaaaaaaa-1111-1111-1111-111111111111",
    {
      original_app_user_id: "aaaaaaaa-1111-1111-1111-111111111111",
      entitlements: {
        next_pro: {
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

Deno.test("a paid subscription does not invent a trial claim or a missing entitlement", () => {
  const snapshot = snapshotFromRevenueCatSubscriber("owner", {
    entitlements: {}, subscriptions: { hoop_pro_monthly: {period_type: "normal", expires_date: "2099-01-01T00:00:00Z"} },
  });
  assertEquals(snapshot.productId, null);
  assertEquals(snapshot.expiresAt, "1970-01-01T00:00:00.000Z");
  assertEquals(snapshot.introClaimed, false);
});

Deno.test("store grace expiry keeps Pro through the paid billing grace period", () => {
  const snapshot = snapshotFromRevenueCatSubscriber("owner", {
    entitlements: { next_pro: { product_identifier: "hoop_pro_monthly", expires_date: "2026-09-01T00:00:00Z" } },
    subscriptions: { hoop_pro_monthly: { period_type: "normal", grace_period_expires_date: "2026-09-20T00:00:00Z" } },
  });
  assertEquals(snapshot.expiresAt, "2026-09-20T00:00:00Z");
  assertEquals(snapshot.introClaimed, false);
});
