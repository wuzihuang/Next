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
