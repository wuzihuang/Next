import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleBillingSync } from "./index.ts";

Deno.test("billing-sync without a session is refused", async () => {
  const response = await handleBillingSync(
    new Request("http://localhost/billing-sync", { method: "POST" }),
  );
  assertEquals(response.status, 401);
});
