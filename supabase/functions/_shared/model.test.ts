import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { model } from "./model.ts";

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
