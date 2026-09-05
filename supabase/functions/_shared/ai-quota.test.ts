import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { consumeAiQuota, recordAiUsage } from "./ai-quota.ts";

Deno.test("a spend ceiling is a daily refusal, not an outage", async () => {
  const decision = await consumeAiQuota({
    rpc: () =>
      Promise.resolve({
        data: { allowed: false, reason: "spend", remaining: 4 },
        error: null,
      }),
  } as never, "turn");
  assertEquals(decision, { allowed: false, reason: "spend" });
});

Deno.test("recorded usage keeps prompt, cached and completion tokens apart", async () => {
  let args: Record<string, unknown> = {};
  await recordAiUsage({
    rpc: (_name: string, payload: Record<string, unknown>) => {
      args = payload;
      return Promise.resolve({ data: null, error: null });
    },
  } as never, {
    endpoint: "asr",
    modelId: "qwen3-asr-flash",
    usage: { promptTokens: 80, cachedTokens: 10, completionTokens: 4 },
  });
  assertEquals(args.p_endpoint, "asr");
  assertEquals(args.p_model, "qwen3-asr-flash");
  assertEquals(args.p_prompt, 80);
  assertEquals(args.p_cached, 10);
  assertEquals(args.p_completion, 4);
  assertEquals(args.p_cost_fen, 1);
  assertEquals(/^\d{4}-\d{2}-\d{2}$/.test(String(args.p_user_day)), true);
  assertEquals(args.p_turn, null);
  assertEquals(args.p_latency, null);
});
