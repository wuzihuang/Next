import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchRevenueCatV2 } from "./billing-revenuecat-v2.ts";
import { snapshotFromRevenueCatSubscriber } from "./billing.ts";
const root = "/v2/projects/project";
const customer = `${root}/customers/owner`;
const expiry = Date.parse("2099-01-01T00:00:00Z");
const list = (items: unknown[], next_page: string | null = null) => ({items, next_page});
const sub = (extra = {}) => ({id: "s1", product_id: "p1", status: "active", gives_access: true,
  current_period_starts_at: 1234, current_period_ends_at: expiry, ends_at: expiry,
  auto_renewal_status: "will_renew", environment: "production", store: "app_store", entitlements: list([{id: "e1", lookup_key: "next_pro"}]), ...extra});
function fixture(overrides: Record<string, unknown> = {}) {
  const routes: Record<string, unknown> = {
    [`${root}/entitlements`]: list([{id: "e1", lookup_key: "next_pro"}]),
    [`${customer}/subscriptions`]: list([sub()]),
    [`${customer}/active_entitlements`]: list([{entitlement_id: "e1", expires_at: expiry}]),
    [`${customer}/events`]: list([]),
    [`${root}/products/p1`]: {store_identifier: "hoop_pro_monthly"}, ...overrides,
  };
  return ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input));
    assertEquals(url.origin, "https://api.revenuecat.com");
    assertEquals((init?.headers as Record<string, string>).Authorization, "Bearer key");
    const body = routes[url.pathname + (url.searchParams.has("starting_after") ? url.search : "")] ?? routes[url.pathname];
    if (body === undefined) throw Error("unexpected resource");
    return Promise.resolve(body instanceof Response ? body : Response.json(body));
  }) as typeof fetch;
}
const read = (overrides: Record<string, unknown> = {}) => fetchRevenueCatV2("owner", "project", "key", fixture(overrides));
Deno.test("v2 maps next_pro product, actual expiry and renewal", async () => {
  const r = await read(); assertEquals(r !== null, true);
  const s = snapshotFromRevenueCatSubscriber("owner", r!.subscriber);
  assertEquals(s.productId, "hoop_pro_monthly"); assertEquals(s.expiresAt, "2099-01-01T00:00:00.000Z");
  assertEquals(s.willRenew, true); assertEquals(r!.introClaimed, false);
});
Deno.test("v2 yearly plan grants next_pro and its trial claims the intro", async () => {
  const r = await read({[`${root}/products/p1`]: {store_identifier: "hoop_pro_yearly"},
    [`${customer}/subscriptions`]: list([sub({status: "trialing"})])});
  const s = snapshotFromRevenueCatSubscriber("owner", r!.subscriber);
  assertEquals(s.productId, "hoop_pro_yearly"); assertEquals(s.periodType, "trial");
  assertEquals(s.expiresAt, "2099-01-01T00:00:00.000Z"); assertEquals(r!.introClaimed, true);
  const events = await read({[`${customer}/events`]: list([{body: {environment: "PRODUCTION", store: "APP_STORE", product_id: "yearly", period_type: "TRIAL"}}])});
  assertEquals(events!.introClaimed, true);
});
Deno.test("v2 Test Store monthly trial claims intro", async () => {
  Deno.env.set("REVENUECAT_TEST_ACCOUNT_ALLOWLIST", "owner");
  const r = await read({[`${customer}/subscriptions`]: list([sub({status: "trialing", store: "test_store", environment: "sandbox"})]),
    [`${root}/products/p1`]: {store_identifier: "monthly"}});
  const s = snapshotFromRevenueCatSubscriber("owner", r!.subscriber);
  Deno.env.delete("REVENUECAT_TEST_ACCOUNT_ALLOWLIST");
  assertEquals(s.productId, "monthly"); assertEquals(s.periodType, "trial"); assertEquals(r!.introClaimed, true);
});
Deno.test("v2 grace uses entitlement expiry; cancelled access does not renew", async () => {
  const r = await read({[`${customer}/subscriptions`]: list([sub({status: "in_grace_period", ends_at: 1,
    current_period_ends_at: 1, auto_renewal_status: "will_not_renew"})]),
    [`${root}/subscriptions/s1/transactions`]: list([{product_store_identifier: "hoop_pro_monthly", effective_expiration_date: expiry}])});
  const s = snapshotFromRevenueCatSubscriber("owner", r!.subscriber);
  assertEquals(s.expiresAt, "2099-01-01T00:00:00.000Z"); assertEquals(s.willRenew, false);
});
Deno.test("v2 expired trial history survives without active entitlements", async () => {
  const r = await read({[`${customer}/subscriptions`]: list([sub({status: "expired", gives_access: false})]),
    [`${customer}/active_entitlements`]: list([]),
    [`${customer}/events`]: list([{body: {environment: "PRODUCTION", store: "APP_STORE", product_id: "monthly", period_type: "TRIAL"}}])});
  assertEquals(r!.introClaimed, true);
  const s = snapshotFromRevenueCatSubscriber("owner", r!.subscriber);
  assertEquals(s.productId, null); assertEquals(s.expiresAt, "1970-01-01T00:00:00.000Z");
});
Deno.test("v2 traverses catalog, subscription, nested entitlement, active and event pages", async () => {
  const r = await read({
    [`${root}/entitlements`]: list([], `${root}/entitlements?starting_after=0`),
    [`${root}/entitlements?starting_after=0`]: list([{id: "e1", lookup_key: "next_pro"}]),
    [`${customer}/subscriptions`]: list([], `${customer}/subscriptions?starting_after=0`),
    [`${customer}/subscriptions?starting_after=0`]: list([sub({entitlements: list([], `${root}/subscriptions/s1/entitlements?starting_after=0`)})]),
    [`${root}/subscriptions/s1/entitlements?starting_after=0`]: list([{id: "e1"}]),
    [`${customer}/active_entitlements`]: list([], `${customer}/active_entitlements?starting_after=0`),
    [`${customer}/active_entitlements?starting_after=0`]: list([{entitlement_id: "e1", expires_at: expiry}]),
    [`${customer}/events`]: list([], `${customer}/events?starting_after=0`),
    [`${customer}/events?starting_after=0`]: list([{body: {environment: "PRODUCTION", store: "APP_STORE", product_id: "hoop_pro_monthly", period_type: "TRIAL"}}]),
  });
  assertEquals(r!.introClaimed, true);
  assertEquals(snapshotFromRevenueCatSubscriber("owner", r!.subscriber).productId, "hoop_pro_monthly");
});
Deno.test("v2 old pro, missing product, paused and inconsistent snapshots deny access", async () => {
  for (const overrides of [
    {[`${customer}/subscriptions`]: list([sub({gives_access: false, status: "paused", ends_at: null})])},
    {[`${customer}/subscriptions`]: list([sub({product_id: null})])},
    {[`${customer}/subscriptions`]: list([sub({entitlements: list([{id: "old", lookup_key: "pro"}])})])},
    {[`${customer}/active_entitlements`]: list([])},
  ]) {
    const r = await read(overrides); assertEquals(snapshotFromRevenueCatSubscriber("owner", r!.subscriber).productId, null);
  }
});
Deno.test("v2 unknown UUID is empty only after verified project and customer 404", async () => {
  const r = await read({[`${customer}/subscriptions`]: Response.json({type: "resource_missing"}, {status: 404}),
    [customer]: Response.json({type: "resource_missing"}, {status: 404})});
  assertEquals(r!.subscriber, {}); assertEquals(r!.introClaimed, false);
});
Deno.test("v2 partial failure, malformed page, foreign cursors and loops fail closed", async () => {
  for (const bad of [Response.json({}, {status: 403}), Response.json({}, {status: 429}),
    {items: "invalid"}, list([], "https://evil.example/steal"),
    list([], `${customer}/events?limit=100`), list([], `${root}/customers/other/events`)]) {
    assertEquals(await read({[`${customer}/events`]: bad}), null);
  }
});

Deno.test("unallowlisted sandbox and Test Store cannot grant AI or consume intro", async () => {
  Deno.env.delete("REVENUECAT_TEST_ACCOUNT_ALLOWLIST");
  for (const evidence of [
    {store: "test_store", environment: "sandbox"},
    {store: "rc_test_store", environment: "sandbox"},
    {store: "test_store", environment: "production"},
    {store: "app_store", environment: undefined},
  ]) {
    const r = await read({[`${customer}/subscriptions`]: list([sub({...evidence, status: "trialing"})]),
      [`${customer}/events`]: list([{body: {...evidence, product_id: "monthly", period_type: "TRIAL"}}])});
    assertEquals(r!.introClaimed, false);
    assertEquals(snapshotFromRevenueCatSubscriber("owner", r!.subscriber).productId, null);
  }
});
Deno.test("App Store sandbox (TestFlight, App Review) grants Pro without an allowlist", async () => {
  Deno.env.delete("REVENUECAT_TEST_ACCOUNT_ALLOWLIST");
  const r = await read({[`${customer}/subscriptions`]: list([sub({environment: "sandbox", status: "trialing"})])});
  assertEquals(r!.introClaimed, true);
  assertEquals(snapshotFromRevenueCatSubscriber("owner", r!.subscriber).productId, "hoop_pro_monthly");
});
Deno.test("a different allowlisted account does not enable this owner's sandbox", async () => {
  Deno.env.set("REVENUECAT_TEST_ACCOUNT_ALLOWLIST", "some-other-owner");
  const r = await read({[`${customer}/subscriptions`]: list([sub({store: "test_store", environment: "sandbox", status: "trialing"})])});
  Deno.env.delete("REVENUECAT_TEST_ACCOUNT_ALLOWLIST");
  assertEquals(r!.introClaimed, false);
  assertEquals(snapshotFromRevenueCatSubscriber("owner", r!.subscriber).productId, null);
});
Deno.test("aggregated sandbox expiry cannot extend a real purchase or its grace", async () => {
  for (const grace of [false, true]) {
    const ownEnd = Date.parse("2028-01-01T00:00:00Z");
    const r = await read({
      [`${customer}/subscriptions`]: list([
        sub({ends_at: grace ? 1 : ownEnd, status: grace ? "in_grace_period" : "active"}),
        sub({id: "test", environment: "sandbox", store: "test_store", status: "trialing", ends_at: expiry}),
      ]),
      [`${root}/subscriptions/s1/transactions`]: list([], `${root}/subscriptions/s1/transactions?starting_after=0`),
      [`${root}/subscriptions/s1/transactions?starting_after=0`]: list([{product_store_identifier: "hoop_pro_monthly", effective_expiration_date: ownEnd}]),
    });
    assertEquals(r!.introClaimed, false);
    assertEquals(snapshotFromRevenueCatSubscriber("owner", r!.subscriber).expiresAt, "2028-01-01T00:00:00.000Z");
  }
});
