import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { checkAiSpend, consumeAiQuota, recordAiUsage } from "./ai-quota.ts";

const owner = "aaaaaaaa-1111-1111-1111-111111111111";
const operation = "bbbbbbbb-1111-1111-1111-111111111111";
const userDb = {
  auth: { getUser: () => Promise.resolve({ data: { user: { id: owner } }, error: null }) },
} as never;

type RpcRequest = { path: string; args: Record<string, unknown>; authorization: string | null };
async function withTrustedRpc(
  response: unknown,
  run: (requests: RpcRequest[]) => Promise<void>,
  status = 200,
): Promise<void> {
  const originalFetch = globalThis.fetch;
  const oldUrl = Deno.env.get("SUPABASE_URL");
  const oldKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const requests: RpcRequest[] = [];
  Deno.env.set("SUPABASE_URL", "https://quota-test.invalid");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-key");
  globalThis.fetch = (input, init) => {
    const options = init as { body?: unknown; headers?: HeadersInit };
    requests.push({
      path: new URL(String(input)).pathname,
      args: JSON.parse(String(options.body)),
      authorization: new Headers(options.headers).get("Authorization"),
    });
    // Resolved rather than `async`: the stub awaits nothing, but `fetch` still has to
    // hand back a promise.
    return Promise.resolve(
      new Response(JSON.stringify(response), { status, headers: { "content-type": "application/json" } }),
    );
  };
  try {
    await run(requests);
  } finally {
    globalThis.fetch = originalFetch;
    if (oldUrl === undefined) Deno.env.delete("SUPABASE_URL"); else Deno.env.set("SUPABASE_URL", oldUrl);
    if (oldKey === undefined) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY"); else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", oldKey);
  }
}

Deno.test("spend refusal uses authenticated owner and trusted service admission", async () => {
  await withTrustedRpc({ allowed: false, reason: "spend", remaining: 4 }, async (requests) => {
    assertEquals(await consumeAiQuota(userDb, "turn", operation), { allowed: false, reason: "spend" });
    assertEquals(requests, [{
      path: "/rest/v1/rpc/consume_ai_quota_trusted",
      args: { p_owner: owner, p_endpoint: "turn", p_operation: operation },
      authorization: "Bearer test-service-key",
    }]);
  });
});

Deno.test("recording sends tokens and audio seconds without caller-selected amount or day", async () => {
  await withTrustedRpc(null, async (requests) => {
    await recordAiUsage(userDb, {
      endpoint: "asr", modelId: "qwen3-asr-flash",
      usage: { promptTokens: 80, cachedTokens: 10, completionTokens: 4, audioSeconds: 12.5 },
    });
    assertEquals(requests, [{
      path: "/rest/v1/rpc/record_ai_usage_trusted",
      args: {
        p_owner: owner, p_endpoint: "asr", p_model: "qwen3-asr-flash",
        p_prompt: 80, p_cached: 10, p_completion: 4, p_audio_seconds: 12.5,
        p_turn: null, p_latency: null,
      },
      authorization: "Bearer test-service-key",
    }]);
  });
});

Deno.test("inter-step spend check does not consume an operation", async () => {
  await withTrustedRpc({ allowed: true, remaining: 0 }, async (requests) => {
    assertEquals(await checkAiSpend(userDb), { allowed: true, remaining: 0 });
    assertEquals(requests[0].path, "/rest/v1/rpc/check_ai_spend_trusted");
    assertEquals(requests[0].args, { p_owner: owner });
  });
});

Deno.test("accounting failure throws so the workflow cannot silently keep spending", async () => {
  await withTrustedRpc({ message: "ledger unavailable", code: "XX000" }, async () => {
    await assertRejects(() => recordAiUsage(userDb, {
      endpoint: "turn", modelId: "qwen3.8-flash",
      usage: { promptTokens: 80, cachedTokens: 0, completionTokens: 4 },
    }), Error, "AI_USAGE_UNAVAILABLE: ledger unavailable");
  }, 500);
});

Deno.test("unverified user cannot trigger a service admission or accounting write", async () => {
  const anonymous = { auth: { getUser: () => Promise.resolve({ data: { user: null }, error: null }) } } as never;
  await withTrustedRpc(null, async (requests) => {
    assertEquals(await consumeAiQuota(anonymous, "turn", operation), { allowed: false, reason: "unavailable" });
    await assertRejects(() => recordAiUsage(anonymous, {
      endpoint: "turn", modelId: "qwen3.8-flash",
      usage: { promptTokens: 80, cachedTokens: 0, completionTokens: 4 },
    }), Error, "AI_USAGE_UNAUTHENTICATED");
    assertEquals(requests.length, 0);
  });
});
