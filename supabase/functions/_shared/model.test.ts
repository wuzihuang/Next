import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { model, modelChain, withModelFallback } from "./model.ts";

Deno.test("streamed compatible model requests the terminal usage chunk", async () => {
  const originalFetch = globalThis.fetch;
  let requestBody: Record<string, unknown> = {};
  globalThis.fetch = (_input, init) => {
    requestBody = JSON.parse(String((init as { body?: unknown })?.body));
    return Promise.resolve(
      new Response('data: {"choices":[],"usage":{"prompt_tokens":100,"completion_tokens":10}}\n\ndata: [DONE]\n\n', {
        headers: { "content-type": "text/event-stream" },
      }),
    );
  };
  try {
    const result = await model("test-usage-model").doStream({
      inputFormat: "prompt",
      mode: { type: "regular" },
      prompt: [{ role: "user", content: [{ type: "text", text: "hi" }] }],
    });
    const reader = result.stream.getReader();
    while (!(await reader.read()).done) { /* drain terminal accounting chunk */ }
    assertEquals(requestBody.stream_options, { include_usage: true });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("Grok uses the documented chat endpoint and the only fallback is DashScope Qwen", async () => {
  const vars = ["GROK_BASE_URL", "GROK_API_KEY", "GROK_MODEL", "DASHSCOPE_MODEL", "DASHSCOPE_FALLBACK_MODELS", "AI_GATEWAY_API_KEY"];
  const previous = vars.map(key => Deno.env.get(key));
  const originalFetch = globalThis.fetch;
  const requests: { url: string; model: string; auth: string | null }[] = [];
  try {
    Deno.env.set("GROK_BASE_URL", "https://grok.invalid/v1/");
    Deno.env.set("GROK_API_KEY", "test-only");
    Deno.env.delete("GROK_MODEL");
    Deno.env.delete("DASHSCOPE_MODEL");
    Deno.env.set("DASHSCOPE_FALLBACK_MODELS", "kimi-k3,deepseek-v4-flash");
    Deno.env.set("AI_GATEWAY_API_KEY", "old-gateway-must-not-win");
    assertEquals(modelChain(), ["grok-4.6", "qwen3.8-flash"]);
    globalThis.fetch = (url, init) => {
      const body = JSON.parse(String(init?.body));
      requests.push({ url: String(url), model: body.model, auth: new Headers(init?.headers).get("Authorization") });
      if (requests.length === 1) return Promise.resolve(Response.json({ error: { message: "unavailable" } }, { status: 503 }));
      return Promise.resolve(Response.json({ choices: [{ message: { content: "connected" }, finish_reason: "stop" }], usage: { prompt_tokens: 10, completion_tokens: 2 } }));
    };
    const out = await withModelFallback(id => model(id).doGenerate({
      inputFormat: "prompt", mode: { type: "regular" },
      prompt: [{ role: "user", content: [{ type: "text", text: "hello" }] }],
    }));
    assertEquals(out.modelId, "qwen3.8-flash");
    assertEquals(out.result.text, "connected");
    assertEquals(requests.map(r => r.url), ["https://grok.invalid/v1/chat/completions", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"]);
    assertEquals(requests[0].auth, "Bearer test-only");
  } finally {
    globalThis.fetch = originalFetch;
    vars.forEach((key, i) => previous[i] === undefined ? Deno.env.delete(key) : Deno.env.set(key, previous[i]!));
  }
});

Deno.test("cancellation and accounting failures never trigger another model", async () => {
  let calls = 0;
  const controller = new AbortController();
  await assertRejects(() => withModelFallback(() => {
    calls++;
    controller.abort();
    return Promise.reject(Object.assign(new Error("timeout"), { name: "TimeoutError" }));
  }, controller.signal));
  assertEquals(calls, 1);
  await assertRejects(() => withModelFallback(() => {
    calls++;
    return Promise.reject(new Error("AI_USAGE_UNAVAILABLE"));
  }));
  assertEquals(calls, 2);
});
