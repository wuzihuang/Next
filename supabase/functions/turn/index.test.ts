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
type TurnStorage = { state: unknown; frame?: unknown };
type PersistenceBehavior = {
  store?: TurnStorage;
  fail?: string[];
  beforeClear?: () => Promise<void>;
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
  const storage = persistence.store ?? { state: structuredClone(stored ?? null) };
  const db = {
    from(table: string) {
      const result = () =>
        table === "screen_frames"
          ? { data: { widget_tree: storage.frame }, error: null }
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
          return Promise.resolve({ data: [], error: null, count: 0 }).then(
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
      if (name === "record_claimed_ai_turn") {
        saved.push(structuredClone(args!));
        storage.frame = structuredClone(args!.p_envelope);
        return { data: { frame_id: "frame" }, error: null };
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
  return { deps, saved, usages, activeTools, prompts, events, upserts, states, storage, rpcCalls };
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

// ADR 0018 · phone tools suspend the turn; the phone resumes it with a result.

const alarm = { name: "device.alarm.set", args: { time: "07:00", days: [1, 2, 3, 4, 5] } };

Deno.test("a phone tool suspends the turn with tool.request and stores the conversation", async () => {
  const h = harness([{ calls: [alarm] }]);
  const body = await (await handleTurn(request({ text: "set an alarm at 7" }), h.deps)).text();
  assert(body.includes("event: tool.request"), body);
  assert(body.includes('"name":"device.alarm.set"'), body);
  assert(body.includes('"confirm":true'), body);
  assert(body.includes('"suspended":true'), body);
  assertEquals(body.includes("event: screen.render"), false);
  assertEquals(h.activeTools.length, 1);
  assert(h.activeTools[0].includes("device.alarm.set"));
  assertEquals(h.saved.length, 0, "a suspended turn is not persisted as a frame");
  assertEquals(h.states.length, 1);
  const state = h.states[0] as { workflow: { phase: string }; pending: { name: string; call_id: string }; resumes: number };
  assertEquals(state.workflow.phase, "act");
  assertEquals(state.pending.name, "device.alarm.set");
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
  assertEquals(h.activeTools[0].includes("data.read"), false);
  const resumedPrompt = JSON.stringify(h.prompts[0]);
  assert(resumedPrompt.includes('"code":"OK"'), resumedPrompt);
  assertEquals(resumedPrompt.includes("suspended"), false, "the placeholder result is replaced");
  const trace = h.saved[0].p_trace as { tool: string; result?: { ok: boolean } }[];
  assertEquals(trace[0].tool, "device.alarm.set");
  assertEquals(trace[1].result?.ok, true);
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

Deno.test("meal.log without an estimate fails inside the turn instead of reaching the phone", async () => {
  const h = harness([{ calls: [{ name: "meal.log", args: {} }, ready] }, { calls: [render] }]);
  const body = await (await handleTurn(request({ text: "log it" }), h.deps)).text();
  assertSuccess(body);
  assertEquals(body.includes("event: tool.request"), false);
  assertEquals(h.states.length, 0);
});

// ADR 0018 · the plan surface prefetches and renders in one step.

Deno.test("the plan surface starts in render with plan.render and saves the plan row", async () => {
  const h = harness([{
    calls: [{ name: "plan.render", args: {
      title: "EASY DAY", summary: "Yesterday was light; keep it easy and sleep early.",
      tasks: [
        { id: "bed", title: "Bed by 23:00", sub: "Lights out before eleven" },
        { id: "walk", title: "Walk", sub: "Thirty minutes at lunch" },
        { id: "protein", title: "Protein", sub: "Add one portion at dinner" },
      ],
    } }],
  }]);
  const body = await (await handleTurn(request({ surface: "plan", text: "" }), h.deps)).text();
  assertSuccess(body);
  assertEquals(h.activeTools.length, 1);
  assertEquals(h.activeTools[0].includes("plan.render"), true);
  assertEquals(h.activeTools[0].includes("data.read"), false);
  assertEquals(h.activeTools[0].includes("screen.render.text"), false);
  assertEquals(h.upserts.length, 1);
  assertEquals(h.upserts[0].table, "daily_plans");
  const frame = h.saved[0].p_envelope as { type: string; target: string; data: { tasks: unknown[] } };
  assertEquals(frame.type, "plan");
  assertEquals(frame.target, "plan");
  assertEquals(frame.data.tasks.length, 3);
  assert(JSON.stringify(h.prompts[0]).includes("plan_context"));
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
