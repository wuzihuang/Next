import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { safeWebSources, searchWeb, SEARCH_MODEL } from "./web-search.ts";

const source = { index: 1, title: "Official nutrition", url: "https://example.org/nutrition" };
const usage = { input_tokens: 100, output_tokens: 20, prompt_tokens_details: { cached_tokens: 40 } };
function stream(chunks: unknown[]): Response {
  const bytes = new TextEncoder().encode(chunks.map(chunk => `event:result\r\ndata:${JSON.stringify(chunk)}\r\n\r\n`).join(""));
  // Split inside Chinese text, JSON and CRLF delimiters to match network chunking.
  return new Response(new ReadableStream({ start(controller) {
    for (let at = 0; at < bytes.length; at += 7) controller.enqueue(bytes.slice(at, at + 7));
    controller.close();
  } }));
}
function chunk(text: string, finish = "null", sources: unknown[] = []) {
  return { output: { choices: [{ message: { content: [{ text }] }, finish_reason: finish }],
    search_info: { search_results: sources } }, usage };
}

Deno.test("native search forces Qwen web lookup, preserves sources and meters cumulative usage once", async () => {
  const requests: Record<string, unknown>[] = [], recorded: unknown[] = [];
  const result = await searchWeb("苹果每100克营养", "zh-CN", new AbortController().signal, {
    apiKey: "test-key",
    fetch: ((_url, options) => {
      requests.push(JSON.parse(String(options?.body)));
      assertEquals(new Headers(options?.headers).get("X-DashScope-SSE"), "enable");
      return Promise.resolve(stream([chunk("每100克", "null", [source]), chunk("约52千卡 [ref_1]", "stop")]));
    }) as typeof fetch,
    recordUsage: (value, model) => { recorded.push({ value, model }); return Promise.resolve(); },
  });
  assert(result.ok);
  assertEquals(result.data.answer, "每100克约52千卡 [ref_1]");
  assertEquals(result.data.sources, [source]);
  assertEquals((requests[0].parameters as Record<string, unknown>).enable_search, true);
  assertEquals((requests[0].parameters as { search_options: { forced_search: boolean } }).search_options.forced_search, true);
  assertEquals(recorded, [{ value: { promptTokens: 60, cachedTokens: 40, completionTokens: 20 }, model: SEARCH_MODEL }]);
});

Deno.test("unverified or interrupted searches never return an answer as verified evidence", async () => {
  for (const chunks of [[chunk("An uncited answer", "stop")], [chunk("Partial answer", "null", [source])],
    [chunk("Partial", "null", [source]), { code: "ProviderFailure", message: "private provider detail" }]]) {
    let records = 0;
    const result = await searchWeb("public question", "en-US", new AbortController().signal, {
      apiKey: "test", fetch: (() => Promise.resolve(stream(chunks))) as typeof fetch,
      recordUsage: () => { records++; return Promise.resolve(); },
    });
    assertEquals(result.ok, false);
    assertEquals(records, 1);
    assert(!JSON.stringify(result).includes("private provider detail"));
    assert(!JSON.stringify(result).includes("Partial answer"));
  }
});

Deno.test("search accounting failure is fatal rather than a recoverable search failure", async () => {
  await assertRejects(() => searchWeb("public question", "en-US", new AbortController().signal, {
    apiKey: "test", fetch: (() => Promise.resolve(stream([chunk("Verified", "stop", [source])]))) as typeof fetch,
    recordUsage: () => Promise.reject(new Error("AI_USAGE_UNAVAILABLE")),
  }), Error, "AI_USAGE_UNAVAILABLE");
});

Deno.test("source URLs reject executable schemes, credentials, duplicates and malformed values", () => {
  assertEquals(safeWebSources([source, source, { ...source, index: 2, url: "javascript:alert(1)" },
    { ...source, index: 3, url: "https://secret@example.org/" }, { index: 4, url: "broken" }]), [source]);
});

Deno.test("invalid public queries never reach the provider", async () => {
  for (const query of [" ", "q".repeat(601)]) {
    assertEquals((await searchWeb(query, "en-US", new AbortController().signal, {
      apiKey: "test", fetch: (() => { throw new Error("must not fetch"); }) as typeof fetch,
      recordUsage: () => { throw new Error("must not meter"); },
    })).ok, false);
  }
});
