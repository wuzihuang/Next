import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { generateObject, streamText } from "npm:ai@4.3.16";
import {
  convertArrayToReadableStream,
  MockLanguageModelV1,
} from "npm:ai@4.3.16/test";
import { handleTurn, HEARTBEAT_MS, MEAL_SEARCH_CAP_MS, type TurnDependencies } from "./index.ts";

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
type TurnStorage = { state: unknown; frame?: unknown };
type PersistenceBehavior = {
  rows?: Record<string, unknown[]>;
  store?: TurnStorage;
  fail?: string[];
  mealWriteDenied?: boolean;
  beforeClear?: () => Promise<void>;
  preflightReplay?: { text: string; conversationId?: string | null };
};

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

function harness(steps: Step[], overrides: Partial<TurnDependencies> = {}, stored?: unknown,
  persistence: PersistenceBehavior = {}) {
  const saved: Record<string, unknown>[] = [];
  const upserts: { table: string; row: unknown }[] = [];
  const states: Record<string, unknown>[] = [];
  const usages: unknown[] = [];
  const activeTools: string[][] = [];
  const prompts: unknown[] = [];
  const events: string[] = [];
  const rpcCalls: string[] = [];
  const tables: string[] = [];
  const webQueries: string[] = [];
  const storage = persistence.store ?? { state: structuredClone(stored ?? null) };
  const db = {
    from(table: string) {
      tables.push(table);
      const result = () =>
        table === "screen_frames"
          ? { data: { widget_tree: storage.frame }, error: null }
          : table === "ai_turns" && storage.frame && persistence.preflightReplay
          ? { data: { id: operationId, frame_id: "frame", user_text: persistence.preflightReplay.text,
            conversation_id: persistence.preflightReplay.conversationId ?? null }, error: null }
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
          : { data: persistence.rows?.[table]?.[0] ?? null, error: null };
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
        is() {
          return q;
        },
        upsert(row: unknown) {
          upserts.push({ table, row });
          return Promise.resolve({ data: null, error: null });
        },
        maybeSingle() {
          return Promise.resolve(result());
        },
        single() {
          return Promise.resolve(result());
        },
        then(resolve: (value: unknown) => unknown) {
          return Promise.resolve({ data: persistence.rows?.[table] ?? [], error: null, count: 0 }).then(
            resolve,
          );
        },
      };
      return q;
    },
    async rpc(name: string, args?: Record<string, unknown>) {
      rpcCalls.push(name);
      if (persistence.fail?.includes(name)) {
        return { data: null, error: { message: "test persistence failure" } };
      }
      if (name === "claim_ai_turn") {
        return { data: storage.frame
          ? { status: "replay", frame_id: "frame" }
          : { status: "claimed" }, error: null };
      }
      if (name === "save_ai_turn_state") {
        storage.state = structuredClone(args!.p_state);
        states.push(structuredClone(args!.p_state) as Record<string, unknown>);
        return { data: null, error: null };
      }
      if (name === "load_ai_turn_state") {
        return { data: structuredClone(storage.state), error: null };
      }
      if (name === "clear_ai_turn_state") {
        await persistence.beforeClear?.();
        storage.state = null;
        return { data: null, error: null };
      }
      if (name === "renew_ai_turn") {
        return { data: true, error: null };
      }
      if (name === "record_claimed_ai_turn") {
        saved.push(structuredClone(args!));
        storage.frame = structuredClone(args!.p_envelope);
        return { data: { frame_id: "frame" }, error: null };
      }
      if (name === "apply_meal_plate") {
        if (persistence.mealWriteDenied) return { data: null, error: { code: "42501" } };
        return { data: { meal_ids: (args?.p_items as unknown[]).map((_, i) =>
          `33333333-3333-4333-8333-${String(i + 1).padStart(12, "0")}`) }, error: null };
      }
      if (name === "apply_meal_operation") {
        return {
          data: {
            operation_id: args?.p_operation_id,
            client_op_id: args?.p_operation_id,
            meal_id: args?.p_meal_id,
          },
          error: null,
        };
      }
      return { data: [], error: null };
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
    entitlement: () => {
      events.push("entitlement");
      return Promise.resolve({ allowed: true as const, introClaimed: false });
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
    searchWeb: (query, _locale, _signal, dependencies) => {
      webQueries.push(query);
      return Promise.resolve(dependencies.recordUsage({ promptTokens: 4, cachedTokens: 0, completionTokens: 3 }, "qwen3.8-flash")).then(() => ({
        ok: true, data: { query, answer: "Reference serving: 200 kcal [ref_1]", sources: [{ index: 1, title: "Food reference", url: "https://example.org/nutrition" }] },
      }));
    },
    recordUsage: (_db, usage) => {
      usages.push(usage);
      events.push("usage");
      return Promise.resolve();
    },
    recordProviderAttempt: () => Promise.resolve(),
    ...overrides,
  };
  return { deps, saved, usages, activeTools, prompts, events, upserts, states, storage, rpcCalls, tables, webQueries };
}

function assertSuccess(body: string) {
  assert(body.includes("event: screen.render"), body);
  assert(body.includes("event: done"), body);
  assertEquals(body.includes("event: error"), false, body);
}

Deno.test("a missing Pro entitlement never consumes quota or calls a model", async () => {
  const h = harness([], {
    entitlement: () => Promise.resolve({
      allowed: false as const,
      introClaimed: false,
      reason: "missing",
    }),
    quota: () => {
      throw new Error("quota must not run without Pro");
    },
  });
  const response = await handleTurn(request(), h.deps);
  assertEquals(response.status, 402);
  const body = await response.json();
  assertEquals(body.error, "SUBSCRIPTION_REQUIRED");
  assertEquals(body.intro_claimed, false);
  assertEquals(h.activeTools.length, 0);
  assertEquals(h.usages.length, 0);
});

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
  const h = harness([{ calls: [{ name: "find", args: { entity: "metric" } }, ready] }, {
    calls: [render],
  }]);
  const body = await (await handleTurn(request(), h.deps)).text();
  assertSuccess(body);
  assertEquals(h.activeTools.length, 2);
  assert(h.activeTools[0].includes("find"));
  assertEquals(h.activeTools[0].includes(render.name), true);
  assert(h.activeTools[1].includes(render.name));
  assertEquals(h.activeTools[1].includes("find"), false);
  assertEquals(h.usages, [
    { promptTokens: 8, cachedTokens: 2, completionTokens: 2 },
    { promptTokens: 9, cachedTokens: 2, completionTokens: 3 },
  ]);
  assertEquals(h.saved.length, 1);
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "text");
  assertEquals((h.saved[0].p_trace as { tool: string }[]).map((x) => x.tool), [
    "find",
    "workflow.ready",
    render.name,
  ]);
  assertEquals(h.events.slice(0, 4), ["entitlement", "quota", "spend", "model"]);
  assertEquals(body.includes("event: coach.handoff"), false);
});

Deno.test("an attached image does not automatically invoke a vision or meal model", async () => {
  const h = harness([{ calls: [ready] }, { calls: [render] }]);
  assertSuccess(await (await handleTurn(request({ image }), h.deps)).text());
  assert(h.activeTools[0].includes("image.inspect"));
  assertEquals(h.usages.length, 2);
});

Deno.test("a dense order screenshot passes actual SDK image validation and reaches the answer", async () => {
  const visibleText = "米饭一份，鸡肉一份，蔬菜一份；".repeat(30);
  const imageModel = new MockLanguageModelV1({ defaultObjectGenerationMode: "json", doGenerate: () => Promise.resolve({
    text: JSON.stringify({ summary: "订单内容".repeat(100), visibleText, objects: Array(15).fill("菜品"), numericFacts: Array.from({ length: 24 }, (_, i) => i) }),
    finishReason: "stop", usage: { promptTokens: 100, completionTokens: 500 },
    rawCall: { rawPrompt: null, rawSettings: {} },
  }) });
  const h = harness([{ calls: [{ name: "image.inspect", args: {} }] }, { text: "已识别订单里的食物，可以继续估算。" }], {
    generateObject: ((options: Parameters<typeof generateObject>[0]) => generateObject({ ...options, model: imageModel })) as typeof generateObject,
  });
  assertSuccess(await (await handleTurn(request({ text: "这个是我今天中午吃的食物", image, surface: "chat" }), h.deps)).text());
  assertEquals(h.activeTools.length, 2);
  assertEquals(h.usages.length, 3);
});

Deno.test("invalid image JSON falls back to Qwen and can still finish the chat", async () => {
  const ids: string[] = [];
  const h = harness([{ calls: [{ name: "image.inspect", args: {} }] }, { text: "图中有米饭和鸡肉。" }], {
    generateObject: ((options: Parameters<typeof generateObject>[0]) => {
      ids.push(options.model.modelId);
      return generateObject({ ...options, model: new MockLanguageModelV1({ defaultObjectGenerationMode: "json", doGenerate: () => Promise.resolve({
        text: ids.length === 1 ? '{"summary":42}' : '{"summary":"米饭和鸡肉","visibleText":null}',
        finishReason: "stop", usage: { promptTokens: 20, completionTokens: 10 }, rawCall: { rawPrompt: null, rawSettings: {} },
      }) }) });
    }) as typeof generateObject,
  });
  assertSuccess(await (await handleTurn(request({ image, surface: "chat" }), h.deps)).text());
  assertEquals(ids, ["grok-4.6", "qwen3.8-flash"]);
});

Deno.test("two invalid image results return a tool limitation instead of killing the reply", async () => {
  let attempts = 0;
  const h = harness([{ calls: [{ name: "image.inspect", args: {} }] }, { text: "这张图片暂时无法可靠识别，请补充菜名。" }], {
    generateObject: () => {
      attempts++;
      return Promise.reject(Object.assign(new Error("response did not match schema"), { name: "AI_NoObjectGeneratedError" }));
    },
  });
  assertSuccess(await (await handleTurn(request({ image, surface: "chat" }), h.deps)).text());
  assertEquals(attempts, 2);
  assert(JSON.stringify(h.prompts[1]).includes("IMAGE_READ_FAILED"));
});

Deno.test("provider failure after a completed read continues on Qwen without repeating the read", async () => {
  const h = harness([{ calls: [{ name: "find", args: { entity: "metric" } }] }, { calls: [render] }]);
  const original = h.deps.streamText;
  const ids: string[] = [];
  h.deps.streamText = options => {
    ids.push(options.model.modelId);
    if (ids.length === 2) throw Object.assign(new Error("503"), { name: "AI_APICallError" });
    return original(options);
  };
  assertSuccess(await (await handleTurn(request(), h.deps)).text());
  assertEquals(ids, ["grok-4.6", "grok-4.6", "qwen3.8-flash"]);
  assertEquals((h.saved[0].p_trace as { tool: string }[]).map(t => t.tool), ["find", render.name]);
  assertEquals(h.saved[0].p_model, "qwen3.8-flash/2026-09");
});

Deno.test("a provider stream failure after a tool has started never repeats that step", async () => {
  const h = harness([]);
  let attempts = 0;
  h.deps.streamText = options => {
    attempts++;
    return streamText({ ...options, model: new MockLanguageModelV1({ doStream: () => Promise.resolve({
      rawCall: { rawPrompt: null, rawSettings: {} },
      stream: new ReadableStream({
        async start(controller) {
          controller.enqueue({ type: "tool-call", toolCallType: "function", toolCallId: "one-call", toolName: "find", args: '{"entity":"metric"}' });
          await new Promise(resolve => setTimeout(resolve, 10));
          controller.enqueue({ type: "error", error: Object.assign(new Error("stream failed"), { name: "AI_APICallError" }) });
          controller.close();
        },
      }),
    }) }) });
  };
  const body = await (await handleTurn(request(), h.deps)).text();
  assert(body.includes("MODEL_UNAVAILABLE"));
  assertEquals(attempts, 1);
  assertEquals((h.saved[0].p_trace as { tool: string }[]).map(t => t.tool), ["find"]);
});

Deno.test("meal generation runs only after model-selected meal.estimate", async () => {
  let generated = 0;
  const h = harness([
    { calls: [{ name: "meal.estimate", args: { reference_query: "rice nutrition" } }] },
    { calls: [ready] },
    { calls: [render] },
  ], {
    generateObject: (() => {
      generated++;
      return Promise.resolve({
        object: {
          items: [{ name: "Rice", portion: "1 bowl", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1 }],
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
  assertEquals(h.activeTools.length, 1);
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "food");
  assertEquals((h.saved[0].p_envelope as { handoff?: string }).handoff, undefined);
  assertEquals(
    (h.saved[0].p_trace as { tool: string }[])[0].tool,
    "meal.estimate",
  );
});

Deno.test("inactive render calls cannot bypass the read phase", async () => {
  const h = harness([{ calls: [{ name: "screen.render", args: { type: "line", title: "HEART", sentence: "Your week", source: "hr.7d" } }] }, { calls: [ready] }, {
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
  assertEquals(h.activeTools[0].includes("workflow.coach"), false);
});

const coach = { name: "workflow.coach", args: {} };

Deno.test("English and Chinese panel small talk hand off once and answer in Coach without reads", async () => {
  for (const [locale, text, answer] of [
    ["en-US", "  I've had a rough day. Can we just talk?  ", "Of course. What has been weighing on you?"],
    ["zh-CN", "  今天有点心烦，可以陪我聊聊吗？  ", "可以，慢慢说。今天发生了什么让你心烦的事？"],
  ]) {
    const h = harness([{ calls: [coach] }, { text: answer }]);
    const body = await (await handleTurn(request({ text, locale, conversation_id: conversationId,
      freshness: { status: "pending", pending_operations: 2 } }), h.deps)).text();
    assertSuccess(body);
    assertEquals(body.match(/event: coach\.handoff/g)?.length, 1);
    assert(body.indexOf("event: coach.handoff") < body.indexOf("event: screen.render"));
    assertEquals(h.activeTools.length, 2);
    assert(h.activeTools[0].includes(coach.name));
    assertEquals(h.activeTools[1].includes(coach.name), false);
    assertEquals(h.events.filter(e => e === "quota").length, 1);
    assertEquals(h.usages.length, 2);
    assertEquals(h.webQueries, []);
    assertEquals(h.rpcCalls.includes("settle_now"), false);
    assertEquals(h.rpcCalls.includes("calculation_status"), false);
    assertEquals(h.tables.includes("sync_domain_status"), false);
    assertEquals(h.saved[0].p_text, text);
    assertEquals(h.saved[0].p_conversation, conversationId);
    assertEquals(h.saved[0].p_trace, [{ tool: coach.name, args: {} }]);
    assertEquals((h.saved[0].p_envelope as { handoff: string; data: { sub: string } }).handoff, "chat");
    assertEquals((h.saved[0].p_envelope as { data: { sub: string } }).data.sub, answer);
    const secondPrompt = h.prompts[1] as { role: string; content: string | { type: string; text?: string }[] }[];
    const system = secondPrompt.find(message => message.role === "system")!.content as string;
    assert(system.includes(locale === "zh-CN" ? "你是 AI 教练" : "You are AI Coach"));
    assertEquals(system.includes("S0 IDENTITY"), false);
    const user = secondPrompt.find(message => message.role === "user")!.content as { text: string }[];
    assert(user[0].text.startsWith(`${text}\n\n<turn_context>`), user[0].text);
  }
});

Deno.test("handoff installs Coach text rendering and retains the attached image for model-selected inspection", async () => {
  const original = "This photo reminds me of a friend. Can we talk about it?";
  const answer = "We can talk about your friend. 2 + 2 = 4.";
  let inspected = 0;
  const h = harness([{ calls: [coach] }, { calls: [{ name: "image.inspect", args: {} }] },
    { calls: [{ name: "screen.render.text", args: { sub: answer } }] }], {
    generateObject: ((options: { messages: { content: { image?: string; text?: string }[] }[] }) => {
      inspected += 1;
      assertEquals(options.messages[0].content[0].image, image);
      assertEquals(options.messages[0].content[1].text, `<user_text>\n${original}\n</user_text>`);
      return Promise.resolve({ object: { summary: "A keepsake", objects: [], numericFacts: [] }, usage: { promptTokens: 5, completionTokens: 3 } });
    }) as unknown as TurnDependencies["generateObject"],
  });
  const body = await (await handleTurn(request({ text: original, image }), h.deps)).text();
  assertSuccess(body);
  assertEquals(inspected, 1);
  assertEquals(h.usages.length, 4);
  assertEquals(h.events.filter(e => e === "quota").length, 1);
  assertEquals((h.saved[0].p_envelope as { handoff: string; data: { sub: string } }).handoff, "chat");
  assertEquals((h.saved[0].p_envelope as { data: { sub: string } }).data.sub, answer);
  assertEquals(h.rpcCalls.includes("settle_now"), false);
});

Deno.test("both replay paths reopen Coach before replaying the completed answer without admission or model calls", async () => {
  const text = "Can we chat?";
  const first = harness([{ calls: [coach] }, { text: "I'm listening." }]);
  assertSuccess(await (await handleTurn(request({ text, conversation_id: conversationId }), first.deps)).text());
  for (const preflightReplay of [undefined, { text, conversationId }]) {
    const replay = harness([], {}, undefined, { store: first.storage, preflightReplay });
    const body = await (await handleTurn(request({ text, conversation_id: conversationId }), replay.deps)).text();
    assertSuccess(body);
    assertEquals(body.match(/event: coach\.handoff/g)?.length, 1);
    assert(body.indexOf("event: coach.handoff") < body.indexOf("event: screen.render"));
    assert(body.includes('"replay":true'));
    assertEquals(replay.activeTools.length, 0);
    assertEquals(replay.usages.length, 0);
    assertEquals(replay.events.includes("quota"), false);
  }
});

Deno.test("failure after handoff persists a Coach fallback that still reopens Coach on replay", async () => {
  let spendChecks = 0;
  const first = harness([{ calls: [coach] }], { spend: () => Promise.resolve(++spendChecks === 1) });
  const text = "I'm feeling lonely.";
  const body = await (await handleTurn(request({ text }), first.deps)).text();
  assert(body.includes("event: coach.handoff"), body);
  assert(body.includes("event: error"), body);
  assert(body.includes('"handoff":"chat"'), body);
  const frame = first.saved[0].p_envelope as { title: string; handoff: string; data: { sub: string } };
  assertEquals(frame.handoff, "chat");
  assertEquals(frame.title, "AI COACH");
  assert(frame.data.sub.includes("couldn't complete"));
  const replay = harness([], {}, undefined, { store: first.storage });
  const replayBody = await (await handleTurn(request({ text }), replay.deps)).text();
  assertSuccess(replayBody);
  assert(replayBody.indexOf("event: coach.handoff") < replayBody.indexOf("event: screen.render"));
  assertEquals(replay.events.includes("quota"), false);
});

Deno.test("handoff cannot race reads, phone actions, readiness or a panel render in a real SDK step", async () => {
  const concurrent = [{ name: "find", args: { entity: "metric" } }, { name: "do", args: { action: "device.find" } }, ready, render];
  const h = harness([{ calls: [coach, ...concurrent] }, { text: "I'm here to listen." }]);
  const body = await (await handleTurn(request({ text: "Can we just talk?" }), h.deps)).text();
  assertSuccess(body);
  assertEquals(h.saved[0].p_trace, [{ tool: coach.name, args: {} }]);
  assertEquals(h.states.length, 0);
  assertEquals(h.webQueries, []);
  for (const first of [{ name: "find", args: { entity: "metric" } }, render]) {
    const reverse = harness([{ calls: [first, coach] }, { calls: [render] }]);
    const reverseBody = await (await handleTurn(request(), reverse.deps)).text();
    assertSuccess(reverseBody);
    assertEquals(reverseBody.includes("event: coach.handoff"), false);
    assertEquals((reverse.saved[0].p_envelope as { handoff?: string }).handoff, undefined);
  }
});

Deno.test("handoff rejects model-authored forwarding content", async () => {
  const h = harness([{ calls: [{ name: coach.name, args: { text: "Rewritten user message" } }] }]);
  const body = await (await handleTurn(request({ text: "My original message" }), h.deps)).text();
  assert(body.includes("event: error"), body);
  assertEquals(body.includes("event: coach.handoff"), false);
  assertEquals(h.saved[0].p_text, "My original message");
  assertEquals((h.saved[0].p_envelope as { handoff?: string }).handoff, undefined);
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
    { calls: [{ name: "meal.estimate", args: { reference_query: "rice nutrition" } }, ready] },
    { calls: [{ name: "screen.render.food", args: { title: "MEAL DRAFT", sentence: "Review this estimate", name: "Fake", kcal: 9999, protein_g: 9999, carb_g: 9999, fat_g: 9999 } }] },
  ], {
    generateObject: (() => Promise.resolve({ object: { items: [{ name: "Rice", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, portion: "1 bowl" }], confidence: "MEDIUM" }, usage: { promptTokens: 5, completionTokens: 6 } })) as unknown as TurnDependencies["generateObject"],
  });
  assertSuccess(await (await handleTurn(request({text:"Record this rice"}),h.deps)).text());
  const frame = h.saved[0].p_envelope as { data: Record<string, unknown>; action:string };
  assertEquals(frame.data.name,"Rice");
  assertEquals(frame.data.kcal,200);
  assertEquals(frame.data.macros,{p:4,c:42,f:1});
  assertEquals(frame.data.draft_id,operationId);
  assertEquals(frame.data.requires_confirmation,false);
  assertEquals(frame.data.committed,true);
  assertEquals(frame.action,"OPEN FUEL");
});

Deno.test("food draft references from production render directly after estimation", async () => {
  for (const locale of ["en-US", "zh-CN"]) {
    // Both failed production turns sent a draft reference without name/title/sentence.
    const foodReference = { name: "screen.render.food", args: {
      draft_id: operationId, slot: "DINNER", confidence: "LOW", action: "CONFIRM",
    } };
    const h = harness([
      { calls: [{ name: "meal.estimate", args: { reference_query: "rice nutrition" } }] },
      { calls: [foodReference] },
      { calls: [ready] },
      { calls: [foodReference] },
    ], {
      generateObject: (() => Promise.resolve({
        object: { items: [{ name: "Rice rolls", kcal: 600, protein_g: 20, carb_g: 90, fat_g: 18, portion: "1 bowl" }], confidence: "LOW" },
        usage: { promptTokens: 5, completionTokens: 6 },
      })) as unknown as TurnDependencies["generateObject"],
    });
    const body = await (await handleTurn(request({
      text: "我晚上吃了两个肠粉，还有一碗那个什么肠粉虾饺面。", locale,
    }), h.deps)).text();
    assertSuccess(body);
    assertEquals(h.activeTools.length, 1);
    assertEquals((h.saved[0].p_trace as { tool: string }[]).map(x => x.tool), [
      "meal.estimate",
    ]);
    const frame = h.saved[0].p_envelope as { type: string; target: string; data: Record<string, unknown>; action: string };
    assertEquals(frame.type, "food");
    assertEquals(frame.target, "fuel");
    assertEquals(frame.data.name, "Rice rolls");
    assertEquals(frame.data.kcal, 600);
    assertEquals(frame.data.macros, { p: 20, c: 90, f: 18 });
    assertEquals(frame.data.draft_id, operationId);
    assertEquals(frame.data.requires_confirmation, false);
    assertEquals(frame.data.committed, true);
    assertEquals(frame.action, locale === "zh-CN" ? "打开热量" : "OPEN FUEL");
    assertEquals(h.states.length, 0, "A draft render never dispatches a meal write");
  }
});

Deno.test("food reference without an estimate returns a recoverable tool result", async () => {
  const h = harness([
    { calls: [ready] },
    { calls: [{ name: "screen.render.food", args: { draft_id: operationId } }] },
    { calls: [render] },
  ]);
  assertSuccess(await (await handleTurn(request({ text: "Record food" }), h.deps)).text());
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "text");
  assertEquals(h.states.length, 0);
});

Deno.test("failed panel requests show an explicit failure instead of body battery", async () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const storage: TurnStorage = { state: null };
    const h = harness([{ calls: [{ name: "meal.estimate", args: { reference_query: "rice nutrition" } }] }], {
      generateObject: () => { throw new Error("Meal provider unavailable"); },
    }, undefined, { store: storage });
    const body = await (await handleTurn(request({ text: "Record food", locale }), h.deps)).text();
    assert(body.includes("event: error"), body);
    const frame = h.saved[0].p_envelope as { type: string; title: string; sentence: string; data: Record<string, unknown> };
    assertEquals(frame.type, "text");
    assertEquals(frame.title, locale === "zh-CN" ? "请求未完成" : "REQUEST FAILED");
    assertEquals(frame.data.level, undefined);
    assert(frame.sentence.includes(locale === "zh-CN" ? "重试" : "Try again"));
    assertEquals(h.states.length, 0);
    // A repeated operation must replay the same honest failure frame.
    const replay = harness([], {}, undefined, { store: storage });
    const replayBody = await (await handleTurn(request({ text: "Record food", locale }), replay.deps)).text();
    assert(replayBody.includes('"replay":true'), replayBody);
    assertEquals(replay.activeTools.length, 0);
    assertEquals(replayBody.includes("BODY BATTERY"), false);
  }
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

// ADR 0018 · phone tools suspend the turn; the phone resumes it with a result.

const alarm = { name: "write", args: { entity: "alarm", op: "create", fields: { time: "07:00", days: [1, 2, 3, 4, 5] } } };

Deno.test("a phone tool suspends the turn with tool.request and stores the conversation", async () => {
  const h = harness([{ calls: [alarm] }]);
  const body = await (await handleTurn(request({ text: "set an alarm at 7" }), h.deps)).text();
  assert(body.includes("event: tool.request"), body);
  assert(body.includes('"name":"write"'), body);
  assert(body.includes('"entity":"alarm"'), body);
  assert(body.includes('"confirm":true'), body);
  assert(body.includes('"suspended":true'), body);
  assertEquals(body.includes("event: screen.render"), false);
  assertEquals(h.activeTools.length, 1);
  assert(h.activeTools[0].includes("write"));
  assertEquals(h.saved.length, 0, "a suspended turn is not persisted as a frame");
  assertEquals(h.states.length, 1);
  const state = h.states[0] as { workflow: { phase: string }; pending: { name: string; call_id: string }; resumes: number };
  assertEquals(state.workflow.phase, "act");
  assertEquals(state.pending.name, "write");
  assertEquals(state.resumes, 1);
  assertEquals(h.events.filter((e) => e === "quota").length, 1);
});

Deno.test("a resumed turn hands the phone's result to the model and renders without paying again", async () => {
  const first = harness([{ calls: [alarm] }]);
  await (await handleTurn(request({ text: "set an alarm at 7" }), first.deps)).text();
  const stored = first.states[0] as { pending: { call_id: string } };
  const h = harness([{ calls: [ready] }, { calls: [render] }], {}, stored);
  const body = await (await handleTurn(request({
    text: "set an alarm at 7",
    tool_result: { call_id: stored.pending.call_id, ok: true, code: "OK", data: { alarms: [{ id: "3", time: "07:00" }] } },
  }), h.deps)).text();
  assertSuccess(body);
  assertEquals(h.events.filter((e) => e === "quota").length, 0, "resume does not consume the allowance");
  // The model's first resumed step starts in act: phone tools and ready, no reads.
  assert(h.activeTools[0].includes("workflow.ready"));
  assertEquals(h.activeTools[0].includes("read"), false);
  const resumedPrompt = JSON.stringify(h.prompts[0]);
  assert(resumedPrompt.includes('"code":"OK"'), resumedPrompt);
  assertEquals(resumedPrompt.includes("suspended"), false, "the placeholder result is replaced");
  const trace = h.saved[0].p_trace as { tool: string; result?: { ok: boolean } }[];
  assertEquals(trace[0].tool, "write");
  assertEquals(trace[1].result?.ok, true);
});

Deno.test("a handed-off turn preserves its original panel identity and Coach state through phone suspension", async () => {
  const original = { surface: "panel", text: "Let's talk through my morning, and set an alarm at 7.", conversation_id: conversationId };
  const first = harness([{ calls: [coach] }, { calls: [alarm] }]);
  const body = await (await handleTurn(request(original), first.deps)).text();
  assert(body.includes("event: coach.handoff"), body);
  assert(body.includes("event: tool.request"), body);
  assert(body.indexOf("event: coach.handoff") < body.indexOf("event: tool.request"));
  const state = first.states[0] as { surface: string; effectiveSurface: string; workflow: { coachHandoff: boolean; completedSteps: number }; pending: { call_id: string } };
  assertEquals(state.surface, "panel");
  assertEquals(state.effectiveSurface, "chat");
  assertEquals(state.workflow.coachHandoff, true);
  assertEquals(state.workflow.completedSteps, 2);
  assertEquals(first.events.filter(e => e === "quota").length, 1);
  const tool_result = { call_id: state.pending.call_id, ok: true, code: "OK" };
  const conflict = harness([], {}, state);
  const rejected = await handleTurn(request({ ...original, surface: "chat", tool_result }), conflict.deps);
  assertEquals(rejected.status, 409);
  assertEquals(conflict.activeTools.length, 0);
  const resumed = harness([{ text: "Your alarm is set. How are you feeling about the morning?" }], {}, undefined, { store: first.storage });
  const resumedBody = await (await handleTurn(request({ ...original, tool_result }), resumed.deps)).text();
  assertSuccess(resumedBody);
  assert(resumedBody.indexOf("event: coach.handoff") < resumedBody.indexOf("event: screen.render"));
  assertEquals(resumed.activeTools[0].includes(coach.name), false);
  assertEquals(resumed.events.includes("quota"), false);
  assertEquals(resumed.usages.length, 1);
  assertEquals(resumed.saved[0].p_text, original.text);
  assertEquals(resumed.saved[0].p_conversation, conversationId);
  assertEquals((resumed.saved[0].p_envelope as { handoff: string }).handoff, "chat");
  assert(JSON.stringify(resumed.prompts[0]).includes("You are AI Coach"));
  assertEquals(first.storage.state, null);
});

Deno.test("three phone-tool suspensions survive successive requests, then completion replays", async () => {
  const store: TurnStorage = { state: null };
  let toolResult: { call_id: string; ok: boolean; code: string } | undefined;
  let admissions = 0;
  for (let hop = 0; hop < 3; hop++) {
    const h = harness([{ calls: [alarm] }], {}, undefined, { store });
    const body = await (await handleTurn(request({ tool_result: toolResult }), h.deps)).text();
    assert(body.includes("event: tool.request"), body);
    assert(store.state, "the next request must load the newly saved suspension");
    const state = store.state as { pending: { call_id: string }; resumes: number };
    assertEquals(state.resumes, hop + 1);
    assertEquals(h.rpcCalls.includes("clear_ai_turn_state"), false);
    assert(h.rpcCalls.includes("release_ai_turn"));
    admissions += h.events.filter((event) => event === "quota").length;
    toolResult = { call_id: state.pending.call_id, ok: true, code: "OK" };
  }
  const last = harness([{ calls: [ready] }, { calls: [render] }], {}, undefined, { store });
  const body = await (await handleTurn(request({ tool_result: toolResult }), last.deps)).text();
  assertSuccess(body);
  assertEquals(store.state, null, "terminal persistence retires the suspension");
  assertEquals(last.events.includes("quota"), false);
  assertEquals(admissions, 1, "the operation pays once across all phone tools");

  const replay = harness([], {}, undefined, { store });
  const replayBody = await (await handleTurn(request({ tool_result: toolResult }), replay.deps)).text();
  assertSuccess(replayBody);
  assert(replayBody.includes('"replay":true'));
  assertEquals(replay.activeTools.length, 0);
  assertEquals(replay.events.includes("quota"), false);
});

Deno.test("completion awaits state cleanup before releasing its lease", async () => {
  const first = harness([{ calls: [alarm] }]);
  await (await handleTurn(request(), first.deps)).text();
  const store = first.storage;
  const callId = (store.state as { pending: { call_id: string } }).pending.call_id;
  let notifyClear!: () => void;
  let allowClear!: () => void;
  const clearing = new Promise<void>((resolve) => { notifyClear = resolve; });
  const canClear = new Promise<void>((resolve) => { allowClear = resolve; });
  const h = harness([{ calls: [ready] }, { calls: [render] }], {}, undefined, {
    store,
    beforeClear: async () => { notifyClear(); await canClear; },
  });
  const body = (await handleTurn(request({
    tool_result: { call_id: callId, ok: true, code: "OK" },
  }), h.deps)).text();
  await clearing;
  const releasedEarly = h.rpcCalls.includes("release_ai_turn");
  allowClear();
  assertSuccess(await body);
  assertEquals(releasedEarly, false);
  assertEquals(store.state, null);
  assert(h.rpcCalls.indexOf("record_claimed_ai_turn") < h.rpcCalls.indexOf("clear_ai_turn_state"));
  assert(h.rpcCalls.includes("release_ai_turn"));
});

Deno.test("failed terminal persistence keeps the original suspension available for retry", async () => {
  const first = harness([{ calls: [alarm] }]);
  await (await handleTurn(request(), first.deps)).text();
  const store = first.storage;
  const original = structuredClone(store.state);
  const callId = (store.state as { pending: { call_id: string } }).pending.call_id;
  const h = harness([{ calls: [ready] }, { calls: [render] }], {}, undefined, {
    store, fail: ["record_claimed_ai_turn"],
  });
  const body = await (await handleTurn(request({
    tool_result: { call_id: callId, ok: true, code: "OK" },
  }), h.deps)).text();
  assert(body.includes("TURN_UNAVAILABLE"), body);
  assertEquals(h.rpcCalls.includes("clear_ai_turn_state"), false);
  assert(h.rpcCalls.includes("release_ai_turn"));
  assertEquals(store.state, original, "resumption must not mutate the durable snapshot");

  const retry = harness([{ calls: [ready] }, { calls: [render] }], {}, undefined, { store });
  assertSuccess(await (await handleTurn(request({
    tool_result: { call_id: callId, ok: true, code: "OK" },
  }), retry.deps)).text());
  assertEquals(retry.events.includes("quota"), false);
  assertEquals(store.state, null);
});

Deno.test("failed resuspension retires old state only when its fallback is durably saved", async () => {
  for (const terminalFails of [false, true]) {
    const first = harness([{ calls: [alarm] }]);
    await (await handleTurn(request(), first.deps)).text();
    const store = first.storage;
    const original = structuredClone(store.state);
    const callId = (store.state as { pending: { call_id: string } }).pending.call_id;
    const h = harness([{ calls: [alarm] }], {}, undefined, {
      store, fail: ["save_ai_turn_state", ...(terminalFails ? ["record_claimed_ai_turn"] : [])],
    });
    const body = await (await handleTurn(request({
      tool_result: { call_id: callId, ok: true, code: "OK" },
    }), h.deps)).text();
    assertEquals(body.includes("event: tool.request"), false);
    assert(body.includes(terminalFails ? "TURN_UNAVAILABLE" : "SUSPEND_FAILED"), body);
    assertEquals(store.state, terminalFails ? original : null);
    assertEquals(h.rpcCalls.includes("clear_ai_turn_state"), !terminalFails);
    assert(h.rpcCalls.includes("release_ai_turn"));
  }
});

Deno.test("state-read failure releases the lease without starting another operation", async () => {
  const h = harness([], {}, undefined, { fail: ["load_ai_turn_state"] });
  const response = await handleTurn(request(), h.deps);
  assertEquals(response.status, 503);
  assert((await response.text()).includes("TURN_STATE_UNAVAILABLE"));
  assertEquals(h.events.includes("quota"), false);
  assertEquals(h.activeTools.length, 0);
  assertEquals(h.rpcCalls.includes("clear_ai_turn_state"), false);
  assert(h.rpcCalls.includes("release_ai_turn"));
});

Deno.test("an unexpected pre-stream failure releases the claimed lease", async () => {
  const h = harness([], {
    quota: () => Promise.reject(new Error("test admission connection failure")),
  });
  const response = await handleTurn(request(), h.deps);
  assertEquals(response.status, 503);
  assert((await response.text()).includes("TURN_UNAVAILABLE"));
  assertEquals(h.activeTools.length, 0);
  assertEquals(h.rpcCalls.includes("clear_ai_turn_state"), false);
  assert(h.rpcCalls.includes("release_ai_turn"));
});

Deno.test("cleanup failure preserves the durable terminal response and releases the lease", async () => {
  for (const throws of [false, true]) {
    const first = harness([{ calls: [alarm] }]);
    await (await handleTurn(request(), first.deps)).text();
    const store = first.storage;
    const callId = (store.state as { pending: { call_id: string } }).pending.call_id;
    const h = harness([{ calls: [ready] }, { calls: [render] }], {}, undefined, {
      store,
      fail: throws ? [] : ["clear_ai_turn_state"],
      beforeClear: throws ? () => Promise.reject(new Error("test cleanup failure")) : undefined,
    });
    assertSuccess(await (await handleTurn(request({
      tool_result: { call_id: callId, ok: true, code: "OK" },
    }), h.deps)).text());
    assert(store.frame);
    assert(store.state, "failed cleanup leaves the expiring snapshot intact");
    assert(h.rpcCalls.includes("release_ai_turn"));
    const replay = harness([], {}, undefined, { store });
    assertSuccess(await (await handleTurn(request(), replay.deps)).text());
    assertEquals(replay.activeTools.length, 0);
  }
});

Deno.test("a resume whose call id does not match the stored request is refused", async () => {
  const first = harness([{ calls: [alarm] }]);
  await (await handleTurn(request({ text: "set an alarm at 7" }), first.deps)).text();
  const h = harness([], {}, first.states[0]);
  const response = await handleTurn(request({
    text: "set an alarm at 7", tool_result: { call_id: "other", ok: true, code: "OK" },
  }), h.deps);
  assertEquals(response.status, 409);
  assert((await response.text()).includes("TOOL_RESULT_MISMATCH"));
  assertEquals(h.activeTools.length, 0);
  assertEquals(h.storage.state, first.storage.state);
  assertEquals(h.rpcCalls.includes("clear_ai_turn_state"), false);
  assert(h.rpcCalls.includes("release_ai_turn"));
});

Deno.test("a meal create without an estimate or fields fails inside the turn instead of reaching the phone", async () => {
  const h = harness([{ calls: [{ name: "write", args: { entity: "meal", op: "create" } }, ready] }, { calls: [render] }]);
  const body = await (await handleTurn(request({ text: "log it" }), h.deps)).text();
  assertSuccess(body);
  assertEquals(body.includes("event: tool.request"), false);
  assertEquals(h.states.length, 0);
});

// ADR 0018 · the plan surface prefetches and renders in one step.

Deno.test("the advice surface starts in render and saves an honest empty result without filler", async () => {
  const h = harness([{
    calls: [{ name: "plan.render", args: {
      title: "NO ADJUSTMENT", summary: "There are no recent observations to support a specific suggestion.",
      tasks: [],
    } }],
  }]);
  const body = await (await handleTurn(request({ surface: "plan", text: "" }), h.deps)).text();
  assertSuccess(body);
  assertEquals(h.activeTools.length, 1);
  assertEquals(h.activeTools[0].includes("plan.render"), true);
  assertEquals(h.activeTools[0].includes("read"), false);
  assertEquals(h.activeTools[0].includes("screen.render.text"), false);
  assertEquals(h.activeTools[0].includes("workflow.coach"), false);
  assertEquals(body.includes("event: coach.handoff"), false);
  assertEquals(h.upserts.length, 1);
  assertEquals(h.upserts[0].table, "daily_plans");
  const frame = h.saved[0].p_envelope as { type: string; target: string; data: { tasks: unknown[] } };
  assertEquals(frame.type, "plan");
  assertEquals(frame.target, "plan");
  assertEquals(frame.data.tasks.length, 0);
  assert(JSON.stringify(h.prompts[0]).includes("plan_context"));
  assertEquals(h.tables.includes("plan_task_checks"), false);
});

Deno.test("advice repairs ungrounded filler and persists only the supported result with sources", async () => {
  const bad = { name: "plan.render", args: { title: "ADVICE", summary: "Prioritize recovery.", tasks: [
    { title: "Sync data", sub: "Sync data", basis: "Need more data" },
  ] } };
  const good = { name: "plan.render", args: { title: "ADVICE", summary: "A short night makes recovery the priority.", tasks: [
    { title: "Reduce evening light", sub: "Dim bright screens during your wind-down so tonight has a quieter start.",
      basis: "09-05 sleep lasted 354 min.", evidence_ids: ["sleep_minutes:2026-09-05"], reference_ids: ["sleep"] },
  ] } };
  const h = harness([{ calls: [bad] }, { calls: [good] }], {}, undefined, { rows: {
    sleep_nights: [{ user_day: "2026-09-05", total_minutes: 354, sleep_start: "2026-09-05T00:00:00Z", wake_at: "2026-09-05T05:54:00Z" }],
  } });
  assertSuccess(await (await handleTurn(request({ surface: "plan", text: "" }), h.deps)).text());
  assertEquals(h.activeTools.length, 2);
  assertEquals(h.upserts.length, 1);
  const frame = h.saved[0].p_envelope as { data: { tasks: { title: string; sources: unknown[] }[]; web_sources: unknown[] } };
  assertEquals(frame.data.tasks[0].title, "Reduce evening light");
  assertEquals(frame.data.tasks[0].sources.length, 1);
  assertEquals(frame.data.web_sources.length, 1);
  assertEquals(h.webQueries.length, 0, "reviewed public guidance does not transmit private health facts");
});

Deno.test("device state rides in as evidence: a battery number in the sentence audits", async () => {
  const h = harness([{ calls: [ready] }, {
    calls: [{ name: "screen.render.text", args: { title: "BAND", sentence: "Battery at 63 right now.", headline: "63" } }],
  }]);
  const body = await (await handleTurn(request({
    text: "battery?",
    freshness: { status: "ready", device: { connected: true, battery_percent: 63, alarms: [] } },
  }), h.deps)).text();
  assertSuccess(body);
  const prompt = JSON.stringify(h.prompts[0]);
  assert(prompt.includes("battery_percent") && prompt.includes("63"), prompt);
});

Deno.test("alarm and direct result skip health prefetch and repeated memory hydration", async () => {
  const first = harness([{ calls: [alarm] }]);
  await (await handleTurn(request({ text: "set an alarm at 7" }), first.deps)).text();
  assertEquals(first.rpcCalls.includes("calculation_status"), false);
  assertEquals(first.rpcCalls.includes("settle_now"), false);
  assertEquals(first.tables.includes("sync_domain_status"), false);
  assertEquals(first.webQueries.length, 0);
  const stored = first.states[0] as { pending: { call_id: string } };
  const resumed = harness([{ calls: [render] }], {}, stored);
  assertSuccess(await (await handleTurn(request({ text: "set an alarm at 7",
    tool_result: { call_id: stored.pending.call_id, ok: true, code: "OK" },
  }), resumed.deps)).text());
  assertEquals(resumed.activeTools.length, 1);
  assertEquals(resumed.tables.includes("user_memory"), false);
  assertEquals(resumed.tables.includes("sync_domain_status"), false);
  assertEquals(resumed.rpcCalls.includes("calculation_status"), false);
});

Deno.test("external factual search supplies sources without fetching personal health history", async () => {
  const h = harness([{ calls: [{ name: "web.search", args: { query: "rice nutrition" } }] },
    { calls: [{ name: "screen.render.text", args: { title: "REFERENCE", sentence: "Reference serving: 200 kcal", headline: "NUTRITION" } }] }]);
  assertSuccess(await (await handleTurn(request({ text: "How many calories in rice?" }), h.deps)).text());
  assertEquals(h.webQueries, ["rice nutrition"]);
  assertEquals(h.rpcCalls.includes("calculation_status"), false);
  assertEquals(h.tables.includes("meals"), false);
  assertEquals((h.saved[0].p_envelope as { data: Record<string, unknown> }).data.web_sources,
    [{ index: 1, title: "Food reference", url: "https://example.org/nutrition" }]);
  assertEquals(h.usages.length, 3);
});

Deno.test("repeated parallel web requests share one search and one usage receipt", async () => {
  const call = { name: "web.search", args: { query: "rice nutrition" } };
  const h = harness([{ calls: [call, call] }, { calls: [render] }]);
  assertSuccess(await (await handleTurn(request(), h.deps)).text());
  assertEquals(h.webQueries.length, 1);
  assertEquals(h.usages.length, 3);
});

Deno.test("a failed web check still produces a meal draft, with no source claims", async () => {
  const h = harness([{ calls: [{ name: "meal.estimate", args: { reference_query: "rice nutrition" } }] },
    { calls: [{ name: "screen.render.food", args: { title: "RICE", sentence: "About 200 kcal.", name: "Rice", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, action: "CONFIRM" } }] }], {
      searchWeb: () => Promise.resolve({ ok: false, error: "SEARCH_NOT_VERIFIED", say: "No sources." }),
      generateObject: (() => Promise.resolve({
        object: { items: [{ name: "Rice", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, portion: "1 bowl" }], confidence: "MEDIUM" },
        usage: { promptTokens: 5, completionTokens: 6 },
      })) as unknown as TurnDependencies["generateObject"],
    });
  assertSuccess(await (await handleTurn(request({ text: "Log rice" }), h.deps)).text());
  assertEquals((h.saved[0].p_envelope as { data: Record<string, unknown> }).data.web_sources, undefined);
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "food");
});

Deno.test("a common dish is estimated without any web search", async () => {
  const h = harness([{ calls: [{ name: "meal.estimate", args: {} }] },
    { calls: [{ name: "screen.render.food", args: { title: "RICE", sentence: "About 200 kcal.", name: "Rice", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, action: "CONFIRM" } }] }], {
      searchWeb: () => { throw new Error("a common dish must not wait on the web"); },
      generateObject: (() => Promise.resolve({
        object: { items: [{ name: "Rice", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, portion: "1 bowl" }], confidence: "MEDIUM" },
        usage: { promptTokens: 5, completionTokens: 6 },
      })) as unknown as TurnDependencies["generateObject"],
    });
  assertSuccess(await (await handleTurn(request({ text: "I ate a bowl of rice" }), h.deps)).text());
  assertEquals(h.webQueries.length, 0);
});

Deno.test("a number the system remembers about the person passes the audit", async () => {
  const remembered = { name: "screen.render.text", args: { title: "PROTEIN", sentence: "Your target is 150 to 180 g a day.", headline: "150 G" } };
  const h = harness([{ calls: [ready] }, { calls: [remembered] }], {}, undefined, { rows: {
    user_memory: [{ summary: "Bulking; daily protein target 150-180g.", facts: [] }],
  } });
  assertSuccess(await (await handleTurn(request({ text: "what is my protein target" }), h.deps)).text());
});

Deno.test("pending local uploads prepare only when a personal data read needs them", async () => {
  const getDay = { name: "find", args: { entity: "day", day: "2026-09-05" } };
  const first = harness([{ calls: [getDay] }, { calls: [{ name: "health.prepare", args: {} }] }]);
  const original = { text: "How am I doing today?", freshness: { status: "pending", pending_operations: 2 } };
  const body = await (await handleTurn(request(original), first.deps)).text();
  assert(body.includes('"name":"health.prepare"'));
  assertEquals(first.tables.includes("daily_results"), false);
  assertEquals(first.rpcCalls.includes("settle_now"), false);
  const state = first.states[0] as { pending: { call_id: string }; workflow: { phase: string } };
  assertEquals(state.workflow.phase, "read");
  const resumed = harness([{ calls: [getDay, ready] }, { calls: [render] }], {}, state);
  assertSuccess(await (await handleTurn(request({ ...original,
    tool_result: { call_id: state.pending.call_id, ok: true, code: "OK", data: { status: "ready", pending_operations: 0 } },
  }), resumed.deps)).text());
  assertEquals(resumed.rpcCalls.filter(name => name === "calculation_status").length, 1);
  assertEquals(resumed.tables.includes("daily_results"), true);
});

Deno.test("web facts cannot satisfy a personal measurement claim", async () => {
  const h = harness([{ calls: [{ name: "web.search", args: { query: "rice nutrition" } }, ready] },
    { calls: [{ name: "screen.render.metric", args: { title: "HEART", sentence: "Measured 200", value: "200", label: "BPM", claims: [
      { id: "web", metric: "heartRate", unit: "bpm", from: "2026-09-05", to: "2026-09-05", value: 200 },
    ] } }] }, { calls: [render] }]);
  assertSuccess(await (await handleTurn(request(), h.deps)).text());
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "text");
});

// ADR 0022 · the advice face generates one day's set in the background.

const advicePlan = { name: "plan.render", args: {
  title: "NO ADJUSTMENT", summary: "There are no recent observations to support a specific suggestion.", tasks: [],
} };

function abortableRequest(body: Record<string, unknown>, signal: AbortSignal): Request {
  return new Request("http://localhost/turn", {
    method: "POST", signal,
    headers: { "content-type": "application/json", "Idempotency-Key": operationId },
    body: JSON.stringify({ text: "how is my heart", locale: "en-US", dayKey: "2026-09-05", ...body }),
  });
}

async function settle(until: () => boolean, ms = 3_000) {
  const deadline = Date.now() + ms;
  while (!until() && Date.now() < deadline) await new Promise((r) => setTimeout(r, 10));
}

Deno.test("a live turn is kept alive by heartbeats, not a wall-clock budget", () => {
  assertEquals(HEARTBEAT_MS, 8_000);
  assertEquals(MEAL_SEARCH_CAP_MS, 4_000);
});

Deno.test("an advice turn keeps generating after the phone aborts its request and saves the day's set", async () => {
  const h = harness([{ calls: [advicePlan] }]);
  const aborter = new AbortController();
  const response = await handleTurn(abortableRequest({ surface: "plan", text: "" }, aborter.signal), h.deps);
  aborter.abort();
  assertSuccess(await response.text());
  assertEquals(h.upserts.map((u) => u.table), ["daily_plans"]);
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "plan");
  assertEquals(h.rpcCalls.filter((n) => n === "release_ai_turn").length, 1);
});

Deno.test("a panel turn still ends with its request", async () => {
  const h = harness([{ calls: [ready] }, { calls: [render] }]);
  const aborter = new AbortController();
  const response = await handleTurn(abortableRequest({}, aborter.signal), h.deps);
  aborter.abort();
  const body = await response.text();
  assert(body.includes("event: error"), body);
  assertEquals(h.upserts.length, 0);
});

Deno.test("a chat turn keeps generating after the phone aborts its request", async () => {
  const h = harness([{ text: "Got it, I am still here." }]);
  const aborter = new AbortController();
  const response = await handleTurn(
    abortableRequest({ surface: "chat", conversation_id: conversationId, text: "Hello" }, aborter.signal),
    h.deps,
  );
  aborter.abort();
  assertSuccess(await response.text());
  assertEquals((h.saved[0].p_envelope as { data: { sub: string } }).data.sub, "Got it, I am still here.");
});

Deno.test("an advice turn finishes its durable result after the reader cancels the stream", async () => {
  const h = harness([{ calls: [advicePlan] }]);
  const response = await handleTurn(request({ surface: "plan", text: "" }), h.deps);
  await response.body!.cancel();
  await settle(() => h.rpcCalls.includes("release_ai_turn"));
  assertEquals(h.upserts.map((u) => u.table), ["daily_plans"]);
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "plan");
});

Deno.test("long-lived advice and panel turns renew their lease before another model step", async () => {
  const plan = harness([{ calls: [advicePlan] }], { leaseRenewAfterMs: 0 });
  assertSuccess(await (await handleTurn(request({ surface: "plan", text: "" }), plan.deps)).text());
  assert(plan.rpcCalls.includes("renew_ai_turn"), plan.rpcCalls.join(","));
  assert(plan.rpcCalls.indexOf("renew_ai_turn") < plan.rpcCalls.indexOf("record_claimed_ai_turn"));
  const panel = harness([{ calls: [ready] }, { calls: [render] }], { leaseRenewAfterMs: 0 });
  assertSuccess(await (await handleTurn(request(), panel.deps)).text());
  assert(panel.rpcCalls.includes("renew_ai_turn"), panel.rpcCalls.join(","));
  assert(panel.rpcCalls.indexOf("renew_ai_turn") < panel.rpcCalls.indexOf("record_claimed_ai_turn"));
});

Deno.test("an advice turn whose lease was taken over stops before publishing a set", async () => {
  const h = harness([{ calls: [advicePlan] }], { leaseRenewAfterMs: 0 }, undefined, { fail: ["renew_ai_turn"] });
  const body = await (await handleTurn(request({ surface: "plan", text: "" }), h.deps)).text();
  assert(body.includes("event: error"), body);
  assertEquals(h.upserts.length, 0);
  assertEquals((h.saved[0].p_envelope as { type: string; target: string }).target, "plan");
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "text");
});

Deno.test("a turn writes an SSE comment heartbeat while a tool keeps the stream silent", async () => {
  const h = harness([{ calls: [{ name: "web.search", args: { query: "pork knuckle rice kcal" } }] }, { calls: [render] }], {
    heartbeatMs: 5,
    searchWeb: async () => {
      await new Promise((resolve) => setTimeout(resolve, 40));
      return { ok: true, data: { query: "pork knuckle rice kcal", answer: "About 700 kcal a bowl.", sources: [] } };
    },
  });
  const body = await (await handleTurn(request(), h.deps)).text();
  assert(body.includes(": ping\n\n"), body);
  assert(body.includes("event: screen.render"), body);
  assertEquals(body.match(/: ping/g)!.length >= 3, true, body);
  for (const line of body.split("\n")) {
    if (line.startsWith(":")) continue;
    assert(line === "" || line.startsWith("event: ") || line.startsWith("data: "), line);
  }
});

Deno.test("a banned phrase comes back to the model as an objection and the rewrite renders", async () => {
  const judged = { name: "screen.render.text", args: { title: "FAT", sentence: "Fat share is 偏高 today.", headline: "FAT" } };
  const h = harness([{ calls: [ready] }, { calls: [judged] }, { calls: [render] }], { bannedPatterns: [/偏高/] });
  const body = await (await handleTurn(request(), h.deps)).text();
  assertSuccess(body);
  assertEquals(h.activeTools.length, 3);
  assert(!body.includes("偏高"), body);
});

Deno.test("an untraceable number comes back as an objection and the rewrite renders", async () => {
  const invented = { name: "screen.render.text", args: { title: "PROTEIN", sentence: "Aim for 173 g today.", headline: "173 G" } };
  const h = harness([{ calls: [ready] }, { calls: [invented] }, { calls: [render] }]);
  assertSuccess(await (await handleTurn(request(), h.deps)).text());
  assertEquals(h.activeTools.length, 3);
});

Deno.test("after two objections the verdict stands as an audit failure", async () => {
  const invented = { name: "screen.render.text", args: { title: "PROTEIN", sentence: "Aim for 173 g today.", headline: "173 G" } };
  const h = harness([{ calls: [ready] }, { calls: [invented] }, { calls: [invented] }, { calls: [invented] }]);
  const body = await (await handleTurn(request(), h.deps)).text();
  assert(body.includes('"reason":"UNTRACEABLE_NUMBER"'), body);
  assertEquals(h.activeTools.length, 4);
});

Deno.test("a food frame that cites the draft as a claim renders in one step", async () => {
  // ⚠️ The draft is harvested for traceability but never registered as measurement
  // evidence, so a claim citing it can never match. The model attached one anyway and
  // every meal paid an extra model round trip for the rejection; a branded meal that also
  // waited on the web then ran past the turn deadline and came back MODEL_UNAVAILABLE.
  const cited = { name: "screen.render.food", args: {
    title: "LATTE", sentence: "About 200 kcal.", action: "CONFIRM",
    claims: [{ id: "meal.estimate", metric: "kcal", unit: "kcal", from: null, to: "2026-09-09", value: 200 }],
  } };
  const h = harness([{ calls: [{ name: "meal.estimate", args: {} }] }, { calls: [cited] }], {
    generateObject: (() => Promise.resolve({
      object: { items: [{ name: "Latte", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, portion: "1 bowl" }], confidence: "MEDIUM" },
      usage: { promptTokens: 5, completionTokens: 6 },
    })) as unknown as TurnDependencies["generateObject"],
  });
  const body = await (await handleTurn(request({ text: "I had a latte" }), h.deps)).text();
  assertSuccess(body);
  assertEquals(h.activeTools.length, 1);
  assertEquals((h.saved[0].p_trace as { tool: string }[]).map(x => x.tool), ["meal.estimate"]);
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "food");
});

Deno.test("a completed meal draft still renders when the model step dies afterwards", async () => {
  const h = harness([]);
  h.deps.generateObject = (() => Promise.resolve({
    object: { items: [{ name: "Rice", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, portion: "1 bowl" }], confidence: "MEDIUM" },
    usage: { promptTokens: 5, completionTokens: 6 },
  })) as unknown as TurnDependencies["generateObject"];
  h.deps.streamText = (options) =>
    streamText({
      ...options,
      model: new MockLanguageModelV1({
        doStream: () =>
          Promise.resolve({
            rawCall: { rawPrompt: null, rawSettings: {} },
            stream: new ReadableStream({
              async start(controller) {
                controller.enqueue({
                  type: "tool-call",
                  toolCallType: "function",
                  toolCallId: "meal",
                  toolName: "meal.estimate",
                  args: "{}",
                });
                await new Promise((resolve) => setTimeout(resolve, 10));
                controller.enqueue({
                  type: "error",
                  error: Object.assign(new Error("stream failed"), { name: "AI_APICallError" }),
                });
                controller.close();
              },
            }),
          }),
      }),
    });
  const body = await (await handleTurn(request({ text: "I ate rice" }), h.deps)).text();
  assertSuccess(body);
  const frame = h.saved[0].p_envelope as { type: string; data: { name: string; kcal: number } };
  assertEquals(frame.type, "food");
  assertEquals(frame.data.name, "Rice");
  assertEquals(frame.data.kcal, 200);
});

Deno.test("a meal search that times out still leaves the model its own estimate", async () => {
  const h = harness([{ calls: [{ name: "meal.estimate", args: { reference_query: "latte nutrition" } }] },
    { calls: [{ name: "screen.render.food", args: { title: "LATTE", sentence: "About 200 kcal.", name: "Latte", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, action: "CONFIRM" } }] }], {
      searchWeb: () => Promise.reject(new DOMException("Signal timed out.", "TimeoutError")),
      generateObject: (() => Promise.resolve({
        object: { items: [{ name: "Latte", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1, portion: "1 bowl" }], confidence: "MEDIUM" },
        usage: { promptTokens: 5, completionTokens: 6 },
      })) as unknown as TurnDependencies["generateObject"],
    });
  assertSuccess(await (await handleTurn(request({ text: "I had a latte" }), h.deps)).text());
  assertEquals((h.saved[0].p_envelope as { type: string }).type, "food");
});

// #27 · the day's set is the one turn nobody asked for: it runs when the day opens and
// after a sync. So it may say a thing and it may not do one. `workflow.reread` used to
// drop this surface into the read phase, where the phone tools live, and that is where
// "turn blood-oxygen auto-measurement on" came from after every sync.
Deno.test("the advice surface carries no phone tools, before or after a reread", async () => {
  const h = harness([
    { calls: [{ name: "workflow.reread", args: {} }] },
    { calls: [{ name: "write", args: {
      entity: "band_setting", op: "update", fields: { slot: "blood_oxygen", on: true },
    } }] },
    { calls: [advicePlan] },
  ]);
  const body = await (await handleTurn(request({ surface: "plan", text: "" }), h.deps)).text();
  assertSuccess(body);
  assert(h.activeTools.length >= 2);
  for (const step of h.activeTools) {
    assertEquals(step.includes("write"), false, step.join(","));
    assertEquals(step.includes("do"), false, step.join(","));
  }
  // Nothing was handed to the phone and nothing was suspended waiting for it.
  assertEquals(body.includes("event: tool.request"), false);
  assertEquals(h.states.length, 0);
  assertEquals(h.upserts[0].table, "daily_plans");
});

Deno.test("a subscription expiring during phone suspension prevents resumed model work", async () => {
  const first = harness([{ calls: [alarm] }]);
  await (await handleTurn(request({ text: "set an alarm at 7" }), first.deps)).text();
  const stored = first.states[0] as { pending: { call_id: string } };
  const h = harness([], {
    entitlement: () => Promise.resolve({allowed: false, introClaimed: true, reason: "expired"}),
    quota: () => { throw new Error("must not consume quota"); },
  }, stored);
  const response = await handleTurn(request({text: "set an alarm at 7", tool_result: {
    call_id: stored.pending.call_id, ok: true, code: "OK", data: {},
  }}), h.deps);
  assertEquals(response.status, 402);
  assertEquals(await response.json(), {error: "SUBSCRIPTION_REQUIRED", intro_claimed: true});
  assertEquals(h.activeTools.length, 0);
});

Deno.test("an explicitly submitted typed meal survives disconnect and uses detached runtime work", async () => {
  const h = harness([{ calls: [{ name: "meal.estimate", args: {} }] }], {
    generateObject: (() => Promise.resolve({
      object: { items: [{ name: "Rice", portion: "1 bowl", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1 }], confidence: "MEDIUM" },
      usage: { promptTokens: 5, completionTokens: 6 },
    })) as unknown as TurnDependencies["generateObject"],
  });
  const runtime = globalThis as typeof globalThis & { EdgeRuntime?: { waitUntil(work: Promise<unknown>): void } };
  const previous = runtime.EdgeRuntime;
  const detached: Promise<unknown>[] = [];
  runtime.EdgeRuntime = { waitUntil: (work) => { detached.push(work); } };
  try {
    const abort = new AbortController();
    const req = new Request(request({ text: "I ate rice", intent: "meal" }), { signal: abort.signal });
    const response = await handleTurn(req, h.deps);
    abort.abort();
    await response.body!.cancel();
    await Promise.all(detached);
    assertEquals(detached.length, 1);
    assert(h.rpcCalls.includes("apply_meal_plate"));
    const frame = h.saved[0].p_envelope as { type: string; data: { committed: boolean } };
    assertEquals(frame.type, "food");
    assertEquals(frame.data.committed, true);
  } finally { runtime.EdgeRuntime = previous; }
});

Deno.test("a stalled meal has a bounded explicit failure instead of permanent THINKING", async () => {
  const h = harness([{ calls: [{ name: "meal.estimate", args: {} }] }], {
    mealTimeoutMs: 5,
    generateObject: ((options: { abortSignal: AbortSignal }) => new Promise((_, reject) => {
      if (options.abortSignal.aborted) reject(options.abortSignal.reason);
      else options.abortSignal.addEventListener("abort", () => reject(options.abortSignal.reason), { once: true });
    })) as unknown as TurnDependencies["generateObject"],
  });
  const response = await (await handleTurn(request({ text: "I ate rice", intent: "meal" }), h.deps)).text();
  assert(response.includes("event: error"));
  assert(response.includes("event: done"));
  assert(!h.rpcCalls.includes("apply_meal_plate"));
});

Deno.test("withdrawn cloud-write permission is a visible failure, never a confirmation", async () => {
  const h = harness([{ calls: [{ name: "meal.estimate", args: {} }] }], {
    generateObject: (() => Promise.resolve({
      object: { items: [{ name: "Rice", portion: "1 bowl", kcal: 200, protein_g: 4, carb_g: 42, fat_g: 1 }], confidence: "MEDIUM" },
      usage: { promptTokens: 5, completionTokens: 6 },
    })) as unknown as TurnDependencies["generateObject"],
  }, undefined, { mealWriteDenied: true });
  const response = await (await handleTurn(request({ text: "I ate rice", intent: "meal" }), h.deps)).text();
  assert(response.includes("event: error"));
  assert(response.includes("data collection consent"));
  assert(!response.includes('"committed":true'));
  assert(!response.includes("CONFIRM"));
});
