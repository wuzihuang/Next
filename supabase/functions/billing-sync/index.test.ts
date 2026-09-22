import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleBillingSync } from "./index.ts";
import type { BillingSnapshot } from "../_shared/billing.ts";

Deno.test("billing-sync without a session is refused", async () => {
  const response = await handleBillingSync(
    new Request("http://localhost/billing-sync", { method: "POST" }),
  );
  assertEquals(response.status, 401);
});

Deno.test("billing-sync ignores phone product state and fetches only the authenticated health account", async () => {
  Deno.env.set("REVENUECAT_SECRET_API_KEY", "test-key");
  Deno.env.set("REVENUECAT_PROJECT_ID", "test-project");
  const owner = "aaaaaaaa-1111-1111-1111-111111111111";
  const fetched: string[] = [];
  const snapshots: BillingSnapshot[] = [];
  const response = await handleBillingSync(new Request("http://localhost/billing-sync", {
    method: "POST",
    body: JSON.stringify({owner: "another-user", product_id: "hoop_pro_monthly", expires_at: null, intro_claimed: true}),
  }), {
    authenticate: () => Promise.resolve(owner),
    fetchSubscriber: (userId) => {
      fetched.push(userId);
      return Promise.resolve({subscriber: {}, observedAt: "2026-09-15T00:00:00Z"});
    },
    applySnapshot: (snapshot) => { snapshots.push(snapshot); return Promise.resolve(); },
  });
  assertEquals(response.status, 200);
  assertEquals(fetched, [owner]);
  assertEquals(snapshots.length, 1);
  assertEquals(snapshots[0].owner, owner);
  assertEquals(snapshots[0].rcAppUserId, owner);
  assertEquals(snapshots[0].productId, null);
  assertEquals(snapshots[0].expiresAt, "1970-01-01T00:00:00.000Z");
  assertEquals(snapshots[0].introClaimed, false);
});

Deno.test("billing-sync never acknowledges an unavailable provider or failed ledger write", async () => {
  Deno.env.set("REVENUECAT_SECRET_API_KEY", "test-key");
  Deno.env.set("REVENUECAT_PROJECT_ID", "test-project");
  for (const fetchFails of [true, false]) {
    let writes = 0;
    const response = await handleBillingSync(new Request("http://localhost/billing-sync", {method: "POST"}), {
      authenticate: () => Promise.resolve("aaaaaaaa-1111-1111-1111-111111111111"),
      fetchSubscriber: () => Promise.resolve(fetchFails ? null : {subscriber: {}, observedAt: "2026-09-15T00:00:00Z"}),
      applySnapshot: () => { writes++; return Promise.reject(new Error("ledger unavailable")); },
    });
    assertEquals(response.status, 503);
    assertEquals(writes, fetchFails ? 0 : 1);
  }
});
