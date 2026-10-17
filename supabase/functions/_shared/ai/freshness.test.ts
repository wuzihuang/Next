import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { clientFreshness, freshnessContext } from "./freshness.ts";
Deno.test("freshness metadata accepts bounded state, never local measured values", () => {
  assertEquals(clientFreshness.safeParse({status:"pending",pending_operations:2,domains:[],checked_at:"2026-09-04T12:00:00Z"}).success,true);
  assertEquals(clientFreshness.safeParse({status:"ready",heart:72}).success,false);
});
Deno.test("pending client writes and failed server checks cannot become ready", () => {
  const result = freshnessContext({status:"pending",pending_operations:1}, [{pending:false}],false);
  assertEquals(result.status,"partial");
  assertEquals(freshnessContext(undefined,[],true).status,"query_failed");
  assertEquals(freshnessContext({status:"ready"},[{pending:true}],false).status,"partial");
});
