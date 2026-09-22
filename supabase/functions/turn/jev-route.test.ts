// ADR 0031 · the fast route through the real /turn entry point.
//
// These tests call handleTurn itself, with the real router, the real source registry, the
// real render tool, the real ledger and the real envelope audit. Only the database, the
// provider HTTP call and the general model are substituted — and the general model is
// substituted by something that throws, because the whole claim of the fast route is that
// it is never called.

import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleTurn, type TurnDependencies } from "./index.ts";
import { streamText } from "npm:ai@4.3.16";
import { convertArrayToReadableStream, MockLanguageModelV1 } from "npm:ai@4.3.16/test";
import { JEV_ENDPOINT } from "../_shared/typesafe.ts";
import { routingQuestions, type JevAttempt } from "../_shared/decision-router.ts";

const operationId = "11111111-1111-4111-8111-111111111111";
const DAY = "2026-09-20";

const JEV_ENV = {
  TYPESAFE_API_KEY: "test-key",
  TYPESAFE_MODEL: "jev-1.13.0",
  JEV_MODE: "on",
  JEV_TASK_ALLOWLIST: "fast.single_read,assisted.read_with_explanation",
  // The tasks have no independent evaluation yet, so the tests state the override the
  // same way a developer's machine has to.
  JEV_ALLOW_UNEVALUATED: "true",
};

function withEnv<T>(values: Record<string, string>, run: () => Promise<T>): Promise<T> {
  const previous = Object.keys(values).map((key) => [key, Deno.env.get(key)] as const);
  for (const [key, value] of Object.entries(values)) Deno.env.set(key, value);
  const restore = () => {
    for (const [key, value] of previous) value === undefined ? Deno.env.delete(key) : Deno.env.set(key, value);
  };
  return run().finally(restore);
}

/// A full, valid provider body for the real question set: every option the server offered
/// carries a probability, because the adapter refuses a distribution that does not.
function jevAnswers(choices: Record<string, string> = {}) {
  const questions = routingQuestions();
  const picked: Record<string, string> = {
    request_scope: "SINGLE_READ",
    metric: "intakeKcal",
    time_range: "TODAY",
    presentation: "TARGET_PROGRESS",
    ...choices,
  };
  const answers = Object.fromEntries(Object.entries(questions).map(([id, question]) => {
    const choice = picked[id];
    return [id, {
      type: "choice",
      choice,
      confidence: 1,
      probabilities: Object.fromEntries(Object.keys(question.criteria).map((option) => [option, option === choice ? 1 : 0])),
    }];
  }));
  return { model: "jev-1.13.0", answers, usage: { input_tokens: 1304, output_tokens: 354 } };
}

type Provider = { status?: number; body?: unknown };

function stubProvider(provider: Provider) {
  const original = globalThis.fetch;
  const calls: unknown[] = [];
  globalThis.fetch = (url, init) => {
    if (String(url).startsWith(JEV_ENDPOINT)) {
      calls.push(JSON.parse(String((init as { body?: unknown })?.body)));
      return Promise.resolve(new Response(JSON.stringify(provider.body ?? jevAnswers()), {
        status: provider.status ?? 200,
        headers: { "x-typesafe-request-id": "req_test" },
      }));
    }
    return original(url, init);
  };
  return { calls, restore: () => { globalThis.fetch = original; } };
}

const FUEL_ROWS: Record<string, unknown[]> = {
  daily_results: [{ user_day: DAY, training_load: 6, day_fuel: [{ kcal_in: 1450, target_in: 2100, protein_g: 120, protein_in_g: 80 }] }],
};

function harness(rows: Record<string, unknown[]> = FUEL_ROWS, overrides: Partial<TurnDependencies> = {}) {
  const saved: Record<string, unknown>[] = [];
  let published: unknown = null;
  const attempts: JevAttempt[] = [];
  const usages: { modelId: string; usage: unknown }[] = [];
  const db = {
    from(table: string) {
      const result = () =>
        table === "screen_frames"
          ? { data: { widget_tree: published }, error: null }
          : table === "consents"
          ? { data: { choice: "granted" }, error: null }
          : table === "profiles"
          ? { data: { locale: "zh-CN", timezone: "UTC", deletion_requested_at: null }, error: null }
          : { data: (rows[table] ?? [])[0] ?? null, error: null };
      const q: Record<string, unknown> = {};
      for (const method of ["select", "eq", "gte", "lte", "lt", "gt", "order", "limit", "range", "is", "in"]) {
        q[method] = () => q;
      }
      q.maybeSingle = () => Promise.resolve(result());
      q.single = q.maybeSingle;
      q.then = (resolve: (v: unknown) => unknown) =>
        Promise.resolve({ data: rows[table] ?? [], error: null, count: 0 }).then(resolve);
      return q;
    },
    rpc(name: string, args?: Record<string, unknown>) {
      if (name === "claim_ai_turn") return Promise.resolve({ data: { status: "claimed" }, error: null });
      if (name === "load_ai_turn_state") return Promise.resolve({ data: null, error: null });
      if (name === "record_claimed_ai_turn") {
        saved.push(structuredClone(args!));
        published = structuredClone(args!.p_envelope);
        return Promise.resolve({ data: { frame_id: "frame" }, error: null });
      }
      if (name === "renew_ai_turn") return Promise.resolve({ data: true, error: null });
      return Promise.resolve({ data: [], error: null });
    },
  };
  const deps: TurnDependencies = {
    authenticate: () => Promise.resolve("u"),
    client: () => db as never,
    budget: () => Promise.resolve(null),
    quota: () => Promise.resolve({ allowed: true, remaining: 9 }),
    entitlement: () => Promise.resolve({ allowed: true as const, introClaimed: false }),
    spend: () => Promise.resolve(true),
    streamText: () => { throw new Error("the fast route must not call a general model"); },
    generateObject: () => { throw new Error("the fast route must not call a general model"); },
    recordUsage: (_db, usage, modelId) => { usages.push({ modelId, usage }); return Promise.resolve(); },
    recordProviderAttempt: (_db, attempt) => { attempts.push(attempt); return Promise.resolve(); },
    bannedPatterns: [],
    ...overrides,
  };
  return { deps, saved, attempts, usages };
}

function request(body: Record<string, unknown> = {}): Request {
  return new Request("http://localhost/turn", {
    method: "POST",
    headers: { "content-type": "application/json", "Idempotency-Key": operationId },
    body: JSON.stringify({ text: "今天吃了多少热量", locale: "zh-CN", dayKey: DAY, ...body }),
  });
}

Deno.test("Jev chooses the tool and the chart; the model does the work with a narrowed surface", async () => {
  const provider = stubProvider({});
  try {
    const { body, h, seen } = await withEnv(JEV_ENV, async () => {
      const seen: { tools: string[]; prompt: string }[] = [];
      const mock = new MockLanguageModelV1({
        doStream: (options) => {
          seen.push({
            tools: options.mode.type === "regular" ? (options.mode.tools ?? []).map((t) => t.name) : [],
            prompt: JSON.stringify(options.prompt),
          });
          return Promise.resolve({
            rawCall: { rawPrompt: null, rawSettings: {} },
            stream: convertArrayToReadableStream([
              {
                type: "tool-call" as const, toolCallType: "function" as const, toolCallId: "c1",
                toolName: "screen.render",
                args: JSON.stringify({
                  type: "ring", source: "kcal.today",
                  title: "摄入 · 今天", sentence: "1450kcal，离目标还差 650",
                }),
              },
              { type: "finish" as const, finishReason: "tool-calls" as const, usage: { promptTokens: 900, completionTokens: 40 } },
            ]),
          });
        },
      });
      const h = harness(FUEL_ROWS, {
        streamText: (options) => streamText({ ...options, model: mock }),
      });
      const response = await handleTurn(request(), h.deps);
      return { body: await response.text(), h, seen };
    });
    assertStringIncludes(body, "event: screen.render");
    assertEquals(body.includes("event: error"), false, body);

    // One model step, not the three to six a turn spends deciding for itself.
    assertEquals(seen.length, 1);
    // The surface it was given: read, find, the web check, the chosen chart, the empty-data
    // text frame. No phone tools, no meal estimate, no other chart.
    assertEquals(seen[0].tools.sort(), ["find", "read", "screen.render", "screen.render.text", "web.search"]);
    // It was told what was decided, including the resolved window.
    assertStringIncludes(seen[0].prompt, "<routing>");
    assertStringIncludes(seen[0].prompt, 'source=\\"kcal.today\\"');
    assertStringIncludes(seen[0].prompt, DAY);
    assertStringIncludes(seen[0].prompt, "Call read directly");
    assertStringIncludes(seen[0].prompt, 'metric=\\"intakeKcal\\"');

    // The frame is the chart Jev chose, filled by the server from the source.
    const frame = h.saved[0].p_envelope as Record<string, unknown>;
    assertEquals(frame.type, "ring");
    assertEquals(frame.sentence, "1450kcal，离目标还差 650");
    // One Jev batch, one model step, both accounted for.
    assertEquals(h.attempts.length, 1);
    assertEquals(h.attempts[0].usage?.promptTokens, 1304);
    assertEquals(h.usages.length, 1);
  } finally {
    provider.restore();
  }
});

Deno.test("JEV_TEMPLATE_FAST answers the same request with no model at all", async () => {
  const provider = stubProvider({});
  try {
    const { body, h } = await withEnv({ ...JEV_ENV, JEV_TEMPLATE_FAST: "true" }, async () => {
      // Throws if a general model is touched.
      const h = harness();
      const response = await handleTurn(request(), h.deps);
      return { body: await response.text(), h };
    });
    assertStringIncludes(body, "event: screen.render");
    assertEquals(body.includes("event: error"), false, body);
    const frame = h.saved[0].p_envelope as Record<string, unknown>;
    assertEquals(frame.type, "ring");
    assertEquals(frame.sentence, "1450kcal / 目标 2100kcal");
    assertEquals(h.usages, [], "no general-model usage, because none ran");
    assertEquals((h.saved[0].p_trace as { tool: string }[]).map((t) => t.tool), ["workflow.ready", "screen.render"]);
  } finally {
    provider.restore();
  }
});

Deno.test("a provider failure leaves the ordinary model turn untouched", async () => {
  const provider = stubProvider({ status: 529, body: { detail: { error_type: "overloaded", message: "retry shortly" } } });
  try {
    const { body, h, steps } = await withEnv(JEV_ENV, async () => {
      const steps: string[] = [];
      const h = harness(FUEL_ROWS, {
        streamText: ((options: { messages: unknown[] }) => {
          steps.push("model");
          // The model still has the whole request, unchanged.
          assertStringIncludes(JSON.stringify(options.messages), "今天吃了多少热量");
          throw Object.assign(new Error("stub"), { name: "AI_APICallError" });
        }) as unknown as TurnDependencies["streamText"],
      });
      const response = await handleTurn(request(), h.deps);
      return { body: await response.text(), h, steps };
    });
    // The turn continued into the model path rather than returning a hard provider error.
    assert(steps.length > 0, "the model must still run after a provider failure");
    assertStringIncludes(body, "event: done");
    // The attempt is on the record with its failure. An overloaded provider returned no
    // usage and did not serve the request, so there is nothing to bill and nothing unknown.
    assertEquals(h.attempts.length, 1);
    assertEquals(h.attempts[0].usage, null);
    assertEquals(h.attempts[0].costUnknown, false);
    assertEquals(h.attempts[0].failure, "PROVIDER_UNAVAILABLE");
  } finally {
    provider.restore();
  }
});

Deno.test("off is off: no provider request at all", async () => {
  const provider = stubProvider({});
  try {
    await withEnv({ ...JEV_ENV, JEV_MODE: "off" }, async () => {
      const h = harness(FUEL_ROWS, {
        streamText: (() => { throw Object.assign(new Error("stub"), { name: "AI_APICallError" }); }) as unknown as TurnDependencies["streamText"],
      });
      await (await handleTurn(request(), h.deps)).text();
      assertEquals(provider.calls.length, 0);
      assertEquals(h.attempts.length, 0);
    });
  } finally {
    provider.restore();
  }
});

Deno.test("shadow performs no online call in this version", async () => {
  const provider = stubProvider({});
  try {
    await withEnv({ ...JEV_ENV, JEV_MODE: "shadow", JEV_SHADOW_SAMPLE_RATE: "1" }, async () => {
      const h = harness(FUEL_ROWS, {
        streamText: (() => { throw Object.assign(new Error("stub"), { name: "AI_APICallError" }); }) as unknown as TurnDependencies["streamText"],
      });
      await (await handleTurn(request(), h.deps)).text();
      // Online shadow would charge the user's own spend cap for a decision they never see.
      assertEquals(provider.calls.length, 0);
      assertEquals(h.attempts.length, 0);
    });
  } finally {
    provider.restore();
  }
});

Deno.test("an image request, a chat surface and a phone resume never reach the provider", async () => {
  for (const body of [
    { image: "data:image/png;base64,YQ==" },
    { surface: "chat", history: [] },
    { surface: "plan" },
  ]) {
    const provider = stubProvider({});
    try {
      await withEnv(JEV_ENV, async () => {
        const h = harness(FUEL_ROWS, {
          streamText: (() => { throw Object.assign(new Error("stub"), { name: "AI_APICallError" }); }) as unknown as TurnDependencies["streamText"],
          generateObject: (() => { throw Object.assign(new Error("stub"), { name: "AI_APICallError" }); }) as unknown as TurnDependencies["generateObject"],
        });
        await (await handleTurn(request(body), h.deps)).text();
        assertEquals(provider.calls.length, 0, JSON.stringify(body));
      });
    } finally {
      provider.restore();
    }
  }
});

Deno.test("a request the router refuses falls through to the model with everything intact", async () => {
  const refuses = jevAnswers({ request_scope: "WRITE_OR_ACTION" });
  const provider = stubProvider({ body: refuses });
  try {
    await withEnv(JEV_ENV, async () => {
      let modelRan = false;
      const h = harness(FUEL_ROWS, {
        streamText: (() => {
          modelRan = true;
          throw Object.assign(new Error("stub"), { name: "AI_APICallError" });
        }) as unknown as TurnDependencies["streamText"],
      });
      await (await handleTurn(request({ text: "把今天的午餐删掉" }), h.deps)).text();
      assertEquals(provider.calls.length, 1);
      assert(modelRan, "a write request is the model's, with its confirmations");
      // The refused decision is still a billed attempt.
      assertEquals(h.attempts[0].usage?.promptTokens, 1304);
    });
  } finally {
    provider.restore();
  }
});

Deno.test("an attempt that cannot be put on the books stops paid work", async () => {
  const provider = stubProvider({});
  try {
    const { body, modelRan } = await withEnv(JEV_ENV, async () => {
      let modelRan = false;
      const h = harness({ daily_results: [] }, {
        recordProviderAttempt: () => Promise.reject(new Error("accounting down")),
        streamText: (() => { modelRan = true; throw new Error("unreachable"); }) as unknown as TurnDependencies["streamText"],
      });
      const response = await handleTurn(request(), h.deps);
      return { body: await response.text(), modelRan };
    });
    assertEquals(modelRan, false, "no paid fallback once a charge could not be recorded");
    assertStringIncludes(body, "event: error");
    assertStringIncludes(body, "fallback_frame");
  } finally {
    provider.restore();
  }
});

Deno.test("no data under a supported binding falls back to the model, not to a zero", async () => {
  const provider = stubProvider({});
  try {
    await withEnv(JEV_ENV, async () => {
      let modelRan = false;
      const h = harness({ daily_results: [] }, {
        streamText: (() => {
          modelRan = true;
          throw Object.assign(new Error("stub"), { name: "AI_APICallError" });
        }) as unknown as TurnDependencies["streamText"],
      });
      const body = await (await handleTurn(request(), h.deps)).text();
      assert(modelRan, "an empty source is the model's to explain");
      assertEquals(body.includes('"value":0'), false, body);
    });
  } finally {
    provider.restore();
  }
});

for (const recover of [true, false]) {
  Deno.test(`guided output ${recover ? "repairs a rejected frame followed by prose" : "stops after one prose reminder"}`, async () => {
    const provider = stubProvider({});
    try {
      let calls = 0;
      const { body, h } = await withEnv(JEV_ENV, async () => {
        const mock = new MockLanguageModelV1({
          doStream: (options) => {
            calls += 1;
            const render = recover && calls !== 2;
            if (recover && calls === 3) assertStringIncludes(JSON.stringify(options.prompt), "No frame was published");
            return Promise.resolve({
              rawCall: { rawPrompt: null, rawSettings: {} },
              stream: convertArrayToReadableStream([
                ...(render ? [{
                  type: "tool-call" as const, toolCallType: "function" as const, toolCallId: `c${calls}`,
                  toolName: "screen.render",
                  args: JSON.stringify({ type: "ring", source: "kcal.today", title: "今天摄入",
                    sentence: calls === 1 ? "已记录 1450kcal" : "摄入 1450kcal" }),
                }] : [{ type: "text-delta" as const, textDelta: "今天摄入 1450kcal。" }]),
                { type: "finish" as const, finishReason: render ? "tool-calls" as const : "stop" as const,
                  usage: { promptTokens: 900, completionTokens: 40 } },
              ]),
            });
          },
        });
        const h = harness(FUEL_ROWS, { bannedPatterns: [/已记录/],
          streamText: (options) => streamText({ ...options, model: mock }) });
        const response = await handleTurn(request(), h.deps);
        return { body: await response.text(), h };
      });
      assertEquals(calls, recover ? 3 : 2);
      assertEquals(h.attempts.length, 1, "a render repair must not reclassify the request");
      assertEquals(h.usages.length, calls, "each additional model step is accounted for");
      assertEquals(body.includes("event: error"), !recover, body);
      if (recover) {
        assertStringIncludes(body, "event: screen.render");
        assertEquals((h.saved[0].p_envelope as Record<string, unknown>).sentence, "摄入 1450kcal");
      }
    } finally { provider.restore(); }
  });
}
