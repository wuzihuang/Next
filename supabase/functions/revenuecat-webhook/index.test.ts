import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleRevenueCatWebhook } from "./index.ts";

function request(body: unknown, secret = "hook-secret"): Request {
  return new Request("http://localhost/revenuecat-webhook", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

Deno.test("a missing webhook secret fails closed", async () => {
  Deno.env.delete("REVENUECAT_WEBHOOK_SECRET");
  const response = await handleRevenueCatWebhook(request({ event: { type: "TEST" } }));
  assertEquals(response.status, 503);
});

Deno.test("a wrong Authorization is refused", async () => {
  Deno.env.set("REVENUECAT_WEBHOOK_SECRET", "hook-secret");
  const response = await handleRevenueCatWebhook(request({ event: { type: "TEST" } }, "nope"));
  assertEquals(response.status, 401);
});

Deno.test("an anonymous app user id is acknowledged and ignored", async () => {
  Deno.env.set("REVENUECAT_WEBHOOK_SECRET", "hook-secret");
  const response = await handleRevenueCatWebhook(request({
    event: {
      type: "INITIAL_PURCHASE",
      app_user_id: "$RCAnonymousID:abc",
      product_id: "hoop_pro_monthly",
    },
  }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.ignored, true);
});

Deno.test("malformed webhook envelopes are rejected before accessing the provider or ledger", async () => {
  Deno.env.set("REVENUECAT_WEBHOOK_SECRET", "hook-secret");
  for (const body of [null, [], "event", {}, {event: null}, {event: []}, {event: "RENEWAL"}]) {
    const response = await handleRevenueCatWebhook(request(body), {
      fetchSubscriber: () => { throw new Error("must not fetch malformed events"); },
      applySnapshot: () => { throw new Error("must not persist malformed events"); },
    });
    assertEquals(response.status, 422);
    assertEquals(await response.json(), {error: "E_SCHEMA"});
  }
});

Deno.test("delayed expiration refreshes current state instead of revoking a renewed purchase", async () => {
  Deno.env.set("REVENUECAT_WEBHOOK_SECRET", "hook-secret");
  const snapshots: unknown[] = [];
  const response = await handleRevenueCatWebhook(request({event: {
    type: "EXPIRATION", environment: "PRODUCTION", store: "APP_STORE", app_user_id: "aaaaaaaa-1111-1111-1111-111111111111", expiration_at_ms: 1,
    product_id: "hoop_pro_monthly", period_type: "TRIAL",
  }}), {
    fetchSubscriber: () => Promise.resolve({subscriber: {
      entitlements: {next_pro: {product_identifier: "hoop_pro_monthly", expires_date: "2099-01-01T00:00:00Z"}},
    }, observedAt: "2026-09-15T00:00:00Z"}),
    applySnapshot: (snapshot) => { snapshots.push(snapshot); return Promise.resolve(); },
  });
  assertEquals(response.status, 200);
  assertEquals((snapshots[0] as {expiresAt: string}).expiresAt, "2099-01-01T00:00:00Z");
  assertEquals((snapshots[0] as {introClaimed: boolean}).introClaimed, true);
});

Deno.test("transfer refreshes source and recipient without inventing lifetime access", async () => {
  Deno.env.set("REVENUECAT_WEBHOOK_SECRET", "hook-secret");
  const owners: string[] = [];
  const snapshots: {productId: string | null; expiresAt: string | null}[] = [];
  const from = "aaaaaaaa-1111-1111-1111-111111111111";
  const to = "aaaaaaaa-2222-2222-2222-222222222222";
  const response = await handleRevenueCatWebhook(request({event: {
    type: "TRANSFER", transferred_from: [from], transferred_to: [to],
  }}), {
    fetchSubscriber: (owner) => {owners.push(owner); return Promise.resolve({subscriber: {}, observedAt: "2026-09-15T00:00:00Z"});},
    applySnapshot: (snapshot) => {snapshots.push(snapshot); return Promise.resolve();},
  });
  assertEquals(response.status, 200);
  assertEquals(owners, [from, to]);
  assertEquals(snapshots.every(s => s.productId === null && s.expiresAt === "1970-01-01T00:00:00.000Z"), true);
});

Deno.test("provider or ledger failures remain retryable", async () => {
  Deno.env.set("REVENUECAT_WEBHOOK_SECRET", "hook-secret");
  for (const failsFetch of [true, false]) {
    const response = await handleRevenueCatWebhook(request({event: {type: "RENEWAL", app_user_id: "aaaaaaaa-1111-1111-1111-111111111111"}}), {
      fetchSubscriber: () => Promise.resolve(failsFetch ? null : {subscriber: {}, observedAt: "2026-09-15T00:00:00Z"}),
      applySnapshot: () => Promise.reject(new Error("ledger unavailable")),
    });
    assertEquals(response.status, 503);
  }
});

Deno.test("sandbox webhook cannot permanently claim intro for an unallowlisted UUID", async () => {
  Deno.env.set("REVENUECAT_WEBHOOK_SECRET", "hook-secret");
  Deno.env.delete("REVENUECAT_TEST_ACCOUNT_ALLOWLIST");
  const snapshots: {introClaimed: boolean}[] = [];
  const response = await handleRevenueCatWebhook(request({event: {
    type: "INITIAL_PURCHASE", app_user_id: "aaaaaaaa-1111-1111-1111-111111111111",
    product_id: "monthly", period_type: "TRIAL", store: "TEST_STORE", environment: "SANDBOX",
  }}), {
    fetchSubscriber: () => Promise.resolve({subscriber: {}, observedAt: "2026-09-15T00:00:00Z"}),
    applySnapshot: snapshot => {snapshots.push(snapshot); return Promise.resolve();},
  });
  assertEquals(response.status, 200);
  assertEquals(snapshots[0].introClaimed, false);
});
