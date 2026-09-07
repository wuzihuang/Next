import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { InvalidToolArgumentsError, streamText, type ToolSet } from "npm:ai@4.3.16";
import { MockLanguageModelV1, convertArrayToReadableStream } from "npm:ai@4.3.16/test";
import { z } from "npm:zod@3.25.76";
import { buildChartTools } from "./charts.ts";
import { NumberLedger } from "./ledger.ts";
import type { Ctx } from "./sources.ts";
import { repairTextToolCall } from "./tool-repair.ts";

const panel = buildChartTools({} as Ctx, new NumberLedger(), () => {});
const chat = { "screen.render.text": { parameters: z.object({ sub: z.string().min(1).max(16000) }) } };
const opts = { toolCallId: "call-1", messages: [] } as never;
const call = (args: string, tools: ToolSet = panel, toolName = "screen.render.text") => repairTextToolCall({
  system: undefined, messages: [], tools, parameterSchema: () => ({}),
  toolCall: { toolCallType: "function", toolCallId: "call-1", toolName, args },
  error: new InvalidToolArgumentsError({ toolName, toolArgs: args, cause: new Error("Invalid arguments") }),
});

// ADR 0018 · a missing or mistyped slot must never throw out of the tool call: the SDK
// turns AI_InvalidToolArgumentsError into a dead turn, and the panel falls to the battery
// frame over one word. The schema tolerates it; execute() decides.

Deno.test("a text call with no headline parses and falls back to the title", async () => {
  const args = { title: "TODAY", sentence: "Take a short break", hero: "——" };
  const schema = panel["screen.render.text"].parameters as z.ZodTypeAny;
  assert(schema.safeParse(args).success, "a missing headline must not fail validation");
  assertEquals(await call(JSON.stringify(args)), null, "nothing left to repair");
  const frames: Record<string, unknown>[] = [];
  const tools = buildChartTools({} as Ctx, new NumberLedger(), (f) => frames.push(f as never));
  assertEquals(await tools["screen.render.text"].execute!(args, opts), { rendered: true, type: "text", hero: "——" });
  assertEquals((frames[0].data as { headline: string }).headline, "TODAY");
});

Deno.test("a chart with no title or sentence asks for them back instead of throwing", async () => {
  const tools = buildChartTools({} as Ctx, new NumberLedger(), () => {});
  const schema = tools["screen.render.food"].parameters as z.ZodTypeAny;
  const args = { name: "Rice", kcal: 200 };
  assert(schema.safeParse(args).success);
  const result = await tools["screen.render.food"].execute!(args, opts) as { rendered: boolean; error: string; say: string };
  assertEquals(result.rendered, false);
  assertEquals(result.error, "MISSING_TEXT");
  assert(result.say.includes("title") && result.say.includes("sentence"), result.say);
});

Deno.test("stringified numbers are coerced rather than rejected", async () => {
  const frames: Record<string, unknown>[] = [];
  const tools = buildChartTools({} as Ctx, new NumberLedger(), (f) => frames.push(f as never));
  // Seen on production: {"kcal":"350","protein":"18"} killed the whole turn.
  const args = { title: "MEAL", sentence: "About 350 kcal.", name: "Congee", kcal: "350", protein_g: "18" };
  const parsed = (tools["screen.render.food"].parameters as z.ZodTypeAny).safeParse(args);
  assert(parsed.success);
  assertEquals(parsed.data.kcal, 350);
  await tools["screen.render.food"].execute!(parsed.data, opts);
  assertEquals((frames[0].data as { kcal: number }).kcal, 350);
  const metric = (tools["screen.render.metric"].parameters as z.ZodTypeAny).safeParse({ title: "HR", sentence: "72 now.", value: 72 });
  assert(metric.success);
  assertEquals(metric.data.value, "72");
});

Deno.test("recovers chat answer from existing sentence", async () => {
  const repaired = await call(JSON.stringify({ title: "AI COACH", sentence: "Here is your answer." }), chat);
  assert(repaired);
  assertEquals(JSON.parse(repaired.args), { sub: "Here is your answer." });
});

Deno.test("rejects malformed, incomplete, wrong-type, and oversized text calls", async () => {
  for (const args of ["{", "null", "[]", "3", '{"title":7,"sentence":"Rest"}', '{"title":"A","sentence":"Rest","headline":4}']) {
    assertEquals(await call(args), null);
  }
  for (const args of [{ sentence: "" }, { sentence: "x".repeat(16001) }, { sub: 5, sentence: "Rest" }]) {
    assertEquals(await call(JSON.stringify(args), chat), null);
  }
});

Deno.test("does not repair other tools or invent missing measurements", async () => {
  assertEquals(await call('{"title":"Heart rate","sentence":"Rest"}', panel, "screen.render.metric"), null);
  assertEquals(await call("{}", {}, "unknown"), null);
  assertEquals(await call('{"headline":"Known","title":"A","sentence":"Rest"}'), null);
});

Deno.test("a text call with no headline still renders, with the title in its place", async () => {
  const frames: unknown[] = [];
  const tools = buildChartTools({} as Ctx, new NumberLedger(), (frame) => frames.push(frame));
  const result = streamText({
    model: new MockLanguageModelV1({
      doStream: () => Promise.resolve({
        rawCall: { rawPrompt: null, rawSettings: {} },
        stream: convertArrayToReadableStream([
          { type: "tool-call", toolCallType: "function", toolCallId: "call-1", toolName: "screen.render.text", args: JSON.stringify({ title: "TODAY", sentence: "Take a break", hero: "——" }) },
          { type: "finish", finishReason: "tool-calls", usage: { promptTokens: 1, completionTokens: 1 } },
        ]),
      }),
    }),
    prompt: "Hello", tools,
    experimental_repairToolCall: repairTextToolCall,
  });
  for await (const chunk of result.fullStream) assert(chunk.type !== "error");
  assertEquals(frames.length, 1);
  assertEquals((frames[0] as { data: { headline: string } }).data.headline, "TODAY");
});
