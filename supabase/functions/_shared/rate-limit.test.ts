import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { enforceRequestBudget } from "./rate-limit.ts";
Deno.test("exhausted request budget returns HTTP429 with bounded retry metadata", async () => {
  const db = {
    rpc() {
      return Promise.resolve({
        data: { allowed: false, retry_after: 42 },
        error: null,
      });
    },
  } as unknown as SupabaseClient;
  const response = await enforceRequestBudget(db, "metric-read");
  assertEquals(response?.status, 429);
  assertEquals(response?.headers.get("Retry-After"), "42");
});
Deno.test("request budget failure fails closed instead of starting expensive work", async () => {
  const db = {
    rpc() {
      return Promise.resolve({ data: null, error: new Error("offline") });
    },
  } as unknown as SupabaseClient;
  assertEquals((await enforceRequestBudget(db, "archive-data"))?.status, 503);
});
Deno.test("available user and scheduler budgets use distinct permission-checked RPCs", async () => {
  const names: string[] = [];
  const db = {
    rpc(name: string) {
      names.push(name);
      return Promise.resolve({ data: { allowed: true }, error: null });
    },
  } as unknown as SupabaseClient;
  assertEquals(await enforceRequestBudget(db, "turn"), null);
  assertEquals(await enforceRequestBudget(db, "archive-data", "owner"), null);
  assertEquals(names, [
    "consume_request_budget",
    "consume_internal_request_budget",
  ]);
});
