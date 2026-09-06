import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { streamText } from "npm:ai@4.3.16";
import {
  convertArrayToReadableStream,
  MockLanguageModelV1,
} from "npm:ai@4.3.16/test";
import { handleTurn, type TurnDependencies } from "./index.ts";

const operationId = "11111111-1111-4111-8111-111111111111";
const conversationId = "22222222-2222-4222-8222-222222222222";
const image = "data:image/png;base64,YQ==";
const render = {
  name: "screen.render.text",
  args: { title: "TODAY", sentence: "Take a break", headline: "REST" },
};
const ready = { name: "workflow.ready", args: {} };
type Call = { name: string; args: Record<string, unknown> };
type Step = { calls?: Call[]; text?: string };

function request(body: Record<string, unknown> = {}): Request {
  return new Request("http://localhost/turn", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "Idempotency-Key": operationId,
    },
    body: JSON.stringify({
      text: "how is my heart",
      locale: "en-US",
      dayKey: "2026-09-05",
      ...body,
    }),
  });
}

function harness(steps: Step[], overrides: Partial<TurnDependencies> = {}) {
  const saved: Record<string, unknown>[] = [];
  const usages: unknown[] = [];
  const activeTools: string[][] = [];
  const prompts: unknown[] = [];
  const events: string[] = [];
  let frame: unknown;
  const db = {
    from(table: string) {
      const result = () =>
        table === "screen_frames"
          ? { data: { widget_tree: frame }, error: null }
          : table === "consents"
          ? { data: { choice: "granted" }, error: null }
          : table === "profiles"
          ? {
            data: {
              locale: "en-US",
              timezone: "UTC",
              deletion_requested_at: null,
            },
            error: null,
          }
          : { data: null, error: null };
      const q = {
        select() {
          return q;
        },
        eq() {
          return q;
        },
        gte() {
          return q;
        },
        lte() {
          return q;
        },
        order() {
          return q;
        },
        limit() {
          return q;
        },
        range() {
          return q;
        },
        maybeSingle() {
          return Promise.resolve(result());
        },
        single() {
          return Promise.resolve(result());
        },
        then(resolve: (value: unknown) => unknown) {
          return Promise.resolve({ data: [], error: null, count: 0 }).then(
            resolve,
          );
        },
      };
      return q;
    },
    rpc(name: string, args?: Record<string, unknown>) {
      if (name === "claim_ai_turn") {
        return Promise.resolve({ data: { status: "claimed" }, error: null });
      }
      if (name === "record_claimed_ai_turn") {
        saved.push(args!);
        frame = args!.p_envelope;
        return Promise.resolve({ data: { frame_id: "frame" }, error: null });
      }
      return Promise.resolve({ data: [], error: null });
    },
  };
  const mock = new MockLanguageModelV1({
    doStream: (options) => {
      const index = activeTools.length;
      activeTools.push(
        options.mode.type === "regular"
          ? (options.mode.tools ?? []).map((t) => t.name)
          : [],
      );
      prompts.push(options.prompt);
      events.push("model");
      const step = steps[index];
      if (!step) throw new Error("Unexpected additional model step");
      return Promise.resolve({
        rawCall: { rawPrompt: null, rawSettings: {} },
        stream: convertArrayToReadableStream([
          ...(step.text
            ? [{ type: "text-delta" as const, textDelta: step.text }]
            : []),
          ...(step.calls ?? []).map((call, i) => ({
            type: "tool-call" as const,
            toolCallType: "function" as const,
            toolCallId: `step-${index}-call-${i}`,
            toolName: call.name,
            args: JSON.stringify(call.args),
          })),
          {
            type: "finish" as const,
            finishReason: step.calls?.length
              ? "tool-calls" as const
              : "stop" as const,
            usage: { promptTokens: 10 + index, completionTokens: 2 + index },
            providerMetadata: { test: { cachedPromptTokens: 2 } },
          },
        ]),
      });
    },
  });
  const deps: TurnDependencies = {
    authenticate: () => Promise.resolve("u"),
    client: () => db as never,
    budget: () => Promise.resolve(null),
    quota: (_db, id) => {
      assertEquals(id, operationId);
      events.push("quota");
      return Promise.resolve({ allowed: true, remaining: 9 });
    },
    spend: () => {
      events.push("spend");
      return Promise.resolve(true);
    },
    streamText: (options) => {
      assertEquals(options.toolChoice, "auto", "Thinking providers reject forced tool choice");
      return streamText({ ...options, model: mock });
    },
    generateObject: () => {
      throw new Error("Unrequested vision or meal model");
    },
    recordUsage: (_db, usage) => {
      usages.push(usage);
      events.push("usage");
      return Promise.resolve();
    },
    ...overrides,
  };
  return { deps, saved, usages, activeTools, prompts, events };
}

function assertSuccess(body: string) {
  assert(body.includes("event: screen.render"), body);
  assert(body.includes("event: done"), body);
  assertEquals(body.includes("event: error"), false, body);
}

Deno.test("count and amount admission denials never call any model", async () => {
  for (const reason of ["count", "spend"] as const) {
    const h = harness([], {
      quota: () => Promise.resolve({ allowed: false, reason }),
    });
    const response = await handleTurn(request(), h.deps);
    const body = await response.text();
    assert(body.includes("RATE_LIMITED"), body);
    assertEquals(h.activeTools.length, 0);
    assertEquals(h.usages.length, 0);
  }
});

Deno.test("spend check before generation prevents a model call after admission", async () => {
  const h = harness([], { spend: () => Promise.resolve(false) });
  const body = await (await handleTurn(request(), h.deps)).text();
  assert(body.includes("event: error"), body);
  assertEquals(h.activeTools.length, 0);
  assertEquals(h.usages.length, 0);
});

Deno.test("real SDK reads and declares ready then renders in two steps with complete usage", async () => {
  const h = harness([{ calls: [{ name: "data.catalog", args: {} }, ready] }, {
    calls: [render],
  }]);
  const body = await (await handleTurn(request(), h.deps)).text();
  assertSuccess(body);
  assertEquals(h.activeTools.length, 2);
  assert(h.activeTools[0].includes("data.catalog"));
  assertEquals(h.activeTools[0].includes(render.name), false);
  assert(h.activeTools[1].includes(render.name));
  assertEquals(h.activeTools[1].includes("data.catalog"), false);
  assertEquals(h.usages, [
    { promptTokens: 8, cachedTokens: 2, completionTokens: 2 },
    { promptTokens: 9, cachedTokens: 2, completionTokens: 3 },
  ]);
  assertEquals(h.saved.length, 1);
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "text");
  assertEquals((h.saved[0].p_trace as { tool: string }[]).map((x) => x.tool), [
    "data.catalog",
    "workflow.ready",
    render.name,
  ]);
  assertEquals(h.events.slice(0, 3), ["quota", "spend", "model"]);
});

Deno.test("an attached image does not automatically invoke a vision or meal model", async () => {
  const h = harness([{ calls: [ready] }, { calls: [render] }]);
  assertSuccess(await (await handleTurn(request({ image }), h.deps)).text());
  assert(h.activeTools[0].includes("image.inspect"));
  assertEquals(h.usages.length, 2);
});

Deno.test("meal generation runs only after model-selected meal.estimate", async () => {
  let generated = 0;
  const h = harness([
    { calls: [{ name: "meal.estimate", args: {} }] },
    { calls: [ready] },
    { calls: [render] },
  ], {
    generateObject: (() => {
      generated++;
      return Promise.resolve({
        object: {
          name: "Rice",
          kcal: 200,
          protein_g: 4,
          carb_g: 42,
          fat_g: 1,
          confidence: "MEDIUM",
        },
        usage: { promptTokens: 5, completionTokens: 6 },
      });
    }) as unknown as TurnDependencies["generateObject"],
  });
  assertSuccess(
    await (await handleTurn(request({ text: "I ate rice", image }), h.deps))
      .text(),
  );
  assertEquals(generated, 1);
  assertEquals(h.activeTools.length, 3);
  assertEquals(h.usages.length, 4);
  assertEquals(
    (h.saved[0].p_trace as { tool: string }[])[0].tool,
    "meal.estimate",
  );
});

Deno.test("inactive render calls cannot bypass the read phase", async () => {
  const h = harness([{ calls: [render] }, { calls: [ready] }, {
    calls: [render],
  }]);
  assertSuccess(await (await handleTurn(request(), h.deps)).text());
  assertEquals(h.activeTools.length, 3);
  assertEquals((h.saved[0].p_trace as { tool: string }[]).map((x) => x.tool), [
    "workflow.ready",
    render.name,
  ]);
});

Deno.test("model-selected range is persisted without parsing question dates", async () => {
  const range = { from: "2026-08-24", to: "2026-08-30" };
  const h = harness([{ calls: [{ name: "workflow.ready", args: { range } }] }, {
    calls: [{ name: render.name, args: { sub: "Rest well." } }],
  }]);
  assertSuccess(
    await (await handleTurn(
      request({
        surface: "chat",
        conversation_id: conversationId,
        text: "那昨天呢？",
      }),
      h.deps,
    )).text(),
  );
  assertEquals(h.saved[0].p_query_context, {
    ...range,
    dayKey: range.to,
    queryText: "那昨天呢？",
    explicitRange: true,
  });
  assert(JSON.stringify(h.prompts[0]).includes("2026-09-05"));
});

Deno.test("ordinary chat may answer directly without data or render tools", async () => {
  const h = harness([{ text: "Hello, how can I help?" }]);
  assertSuccess(
    await (await handleTurn(
      request({ surface: "chat", text: "Hello" }),
      h.deps,
    )).text(),
  );
  assertEquals(h.activeTools.length, 1);
  assertEquals(h.saved[0].p_trace, []);
  assertEquals(h.usages.length, 1);
});

Deno.test("unregistered legacy tools cannot execute or produce a successful frame", async () => {
  const h = harness([{ calls: [{ name: "legacy.food.route", args: {} }] }]);
  const body = await (await handleTurn(request(), h.deps)).text();
  assert(body.includes("event: error"), body);
  assertEquals(body.includes("event: screen.render"), false);
  assertEquals(h.saved[0].p_trace, []);
  assertEquals(h.activeTools.length, 1);
});

Deno.test("food output uses the selected tool draft rather than model-supplied nutrition", async () => {
  const h = harness([
    { calls: [{ name: "meal.estimate", args: {} }, ready] },
    { calls: [{ name: "screen.render.food", args: { title: "MEAL DRAFT", sentence: "Review this estimate", name: "Fake", kcal: 9999, protein_g: 9999, carb_g: 9999, fat_g: 9999 } }] },
  ], {
    generateObject: (() => Promise.resolve({ object: { name: "Rice", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, confidence: "MEDIUM" }, usage: { promptTokens: 5, completionTokens: 6 } })) as unknown as TurnDependencies["generateObject"],
  });
  assertSuccess(await (await handleTurn(request({text:"Record this rice"}),h.deps)).text());
  const frame = h.saved[0].p_envelope as { data: Record<string, unknown>; action:string };
  assertEquals(frame.data.name,"Rice");
  assertEquals(frame.data.kcal,200);
  assertEquals(frame.data.macros,{p:4,c:42,f:1});
  assertEquals(frame.data.draft_id,operationId);
  assertEquals(frame.data.requires_confirmation,true);
  assertEquals(frame.action,"CONFIRM");
});

Deno.test("accounting failure stops before the next model step", async () => {
  const h = harness([{calls:[ready]}],{recordUsage:()=>Promise.reject(new Error("AI_USAGE_UNAVAILABLE"))});
  const body=await (await handleTurn(request(),h.deps)).text();
  assert(body.includes("event: error"));
  assertEquals(body.includes("event: screen.render"),false);
  assertEquals(h.activeTools.length,1);
});

Deno.test("spend is checked again after the first model step is settled", async () => {
  let checks=0;
  const h=harness([{calls:[ready]}],{spend:()=>Promise.resolve(++checks===1)});
  const body=await (await handleTurn(request(),h.deps)).text();
  assert(body.includes("event: error"));
  assertEquals(h.activeTools.length,1);
  assertEquals(h.usages.length,1);
});
