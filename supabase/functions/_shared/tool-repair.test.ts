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
const call = (args: string, tools: ToolSet = panel, toolName = "screen.render.text") => repairTextToolCall({
  system: undefined, messages: [], tools, parameterSchema: () => ({}),
  toolCall: { toolCallType: "function", toolCallId: "call-1", toolName, args },
  error: new InvalidToolArgumentsError({ toolName, toolArgs: args, cause: new Error("Invalid arguments") }),
});

Deno.test("repairs production text call missing headline without changing facts", async () => {
  const args = { title: "TODAY", sentence: "Take a short break", hero: "——" };
  const schema = panel["screen.render.text"].parameters as z.ZodTypeAny;
  assert(!schema.safeParse(args).success);
  const repaired = await call(JSON.stringify(args));
  assert(repaired);
  assertEquals(repaired.toolCallId, "call-1");
  assertEquals(JSON.parse(repaired.args), { ...args, headline: "TODAY" });
  assert(schema.safeParse(JSON.parse(repaired.args)).success);
  assertEquals(args, { title: "TODAY", sentence: "Take a short break", hero: "——" });
});

Deno.test("uses a fixed heading when title is empty", async () => {
  const repaired = await call(JSON.stringify({ title: "", sentence: "Rest" }));
  assert(repaired);
  assertEquals(JSON.parse(repaired.args).headline, "AI COACH");
});

Deno.test("recovers chat answer from existing sentence", async () => {
  const repaired = await call(JSON.stringify({ title: "AI COACH", sentence: "Here is your answer." }), chat);
  assert(repaired);
  assertEquals(JSON.parse(repaired.args), { sub: "Here is your answer." });
});

Deno.test("rejects malformed, incomplete, wrong-type, and oversized text calls", async () => {
  for (const args of ["{", "null", "[]", "3", '{"hero":"80"}', '{"title":7,"sentence":"Rest"}', '{"title":"A","sentence":"Rest","headline":4}']) {
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

Deno.test("streamText repairs invalid arguments before executing the render tool", async () => {
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
