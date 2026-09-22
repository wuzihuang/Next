import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { askJev, JEV_ENDPOINT, jevConfig, usageOf, type JevChoiceQuestion } from "./typesafe.ts";

const config = {
  mode: "on" as const,
  model: "jev-1.13.0",
  apiKey: "test-key",
  timeoutMs: 1500,
  totalWaitMs: 2500,
  maxCallsPerTurn: 2,
  shadowSampleRate: 0,
  assistedEnabled: false,
  templateFast: false,
};

const questions: Record<string, JevChoiceQuestion> = {
  scope: {
    type: "choice",
    instructions: "Classify.",
    criteria: { READ: "a read", WRITE: "a write", UNKNOWN: "cannot tell" },
  },
};

/// The exact body shape the live API returned on 2026-09-20.
function body(overrides: Record<string, unknown> = {}) {
  return {
    model: "jev-1.13.0",
    answers: {
      scope: { type: "choice", choice: "READ", confidence: 0.81, probabilities: { READ: 0.88, WRITE: 0.12, UNKNOWN: 0.0 } },
    },
    usage: { input_tokens: 513, output_tokens: 80 },
    ...overrides,
  };
}

function reply(value: unknown, init: ResponseInit = {}): typeof fetch {
  return () => Promise.resolve(new Response(typeof value === "string" ? value : JSON.stringify(value), {
    status: 200, headers: { "x-typesafe-request-id": "req_test" }, ...init,
  }));
}

Deno.test("a valid choice answer carries the distribution, the margin and the served model", async () => {
  let sent: Record<string, unknown> = {};
  const result = await askJev({
    state: { request: { text: "今天吃了多少" } }, questions, config,
    fetch: (url, init) => {
      assertEquals(String(url), JEV_ENDPOINT);
      assertEquals(new Headers(init?.headers).get("Authorization"), "Bearer test-key");
      sent = JSON.parse(String((init as { body?: unknown })?.body));
      return reply(body())(url, init);
    },
  });
  assert(result.ok);
  assertEquals(sent.model, "jev-1.13.0");
  assertEquals(result.model, "jev-1.13.0");
  assertEquals(result.requestId, "req_test");
  assertEquals(result.answers.scope.choice, "READ");
  // Three separate fields: confidence is not the selected probability, and the margin is
  // the distance to the runner-up.
  assertEquals(result.answers.scope.confidence, 0.81);
  assertEquals(result.answers.scope.probabilities.READ, 0.88);
  assertEquals(Math.round(result.answers.scope.margin * 100), 76);
  // Jev bills input tokens only; the underscore names are mapped explicitly.
  assertEquals(result.usage, { promptTokens: 513, cachedTokens: 0, completionTokens: 80 });
});

Deno.test("an illegal answer is refused rather than repaired, and its usage is still billed", async () => {
  const cases: [string, unknown][] = [
    ["an option we never offered", body({ answers: { scope: { type: "choice", choice: "DELETE", confidence: 1, probabilities: { READ: 0.5, WRITE: 0.5, UNKNOWN: 0 } } } })],
    ["a missing question", body({ answers: {} })],
    ["the wrong answer type", body({ answers: { scope: { type: "noul", noul: 0.9 } } })],
    ["a distribution that does not sum to one", body({ answers: { scope: { type: "choice", choice: "READ", confidence: 0.9, probabilities: { READ: 0.5, WRITE: 0.1, UNKNOWN: 0.1 } } } })],
    ["a probability out of range", body({ answers: { scope: { type: "choice", choice: "READ", confidence: 0.9, probabilities: { READ: 1.4, WRITE: -0.4, UNKNOWN: 0 } } } })],
    ["a confidence out of range", body({ answers: { scope: { type: "choice", choice: "READ", confidence: 2, probabilities: { READ: 1, WRITE: 0, UNKNOWN: 0 } } } })],
    ["an option missing from the distribution", body({ answers: { scope: { type: "choice", choice: "READ", confidence: 0.9, probabilities: { READ: 1, WRITE: 0 } } } })],
    ["another model version than the pinned one", body({ model: "jev-1.14.0" })],
  ];
  for (const [name, payload] of cases) {
    const result = await askJev({ state: {}, questions, config, fetch: reply(payload) });
    assertEquals(result.ok, false, name);
    if (result.ok) continue;
    assertEquals(result.failure, "INVALID_RESPONSE", name);
    assertEquals(result.usage?.promptTokens, 513, `${name}: a billed call is never free`);
  }
});

Deno.test("truncated JSON is an invalid response, not a crash", async () => {
  const result = await askJev({ state: {}, questions, config, fetch: reply('{"model":"jev-1.13.0","ans') });
  assert(!result.ok);
  assertEquals(result.failure, "INVALID_RESPONSE");
  assertEquals(result.usage, null);
});

Deno.test("status codes map to distinct, bounded failures", async () => {
  const cases: [number, string][] = [
    [401, "AUTH"], [403, "AUTH"], [422, "REQUEST_REJECTED"], [400, "REQUEST_REJECTED"],
    [429, "RATE_LIMITED"], [529, "PROVIDER_UNAVAILABLE"], [500, "PROVIDER_UNAVAILABLE"],
  ];
  let calls = 0;
  for (const [status, failure] of cases) {
    const result = await askJev({
      state: {}, questions, config,
      fetch: () => {
        calls += 1;
        return Promise.resolve(new Response(JSON.stringify({ detail: { error_type: "x", message: "y" } }), { status }));
      },
    });
    assert(!result.ok);
    assertEquals(result.failure, failure, `HTTP ${status}`);
    assertEquals(result.status, status);
  }
  // One attempt each: the foreground never retries a provider.
  assertEquals(calls, cases.length);
});

Deno.test("our own budget is a timeout; the turn's cancellation is not", async () => {
  const slow: typeof fetch = (_url, init) =>
    new Promise((_resolve, reject) => {
      (init as { signal?: AbortSignal })?.signal?.addEventListener("abort", () =>
        reject(Object.assign(new Error("aborted"), { name: "AbortError" })));
    });

  const timedOut = await askJev({ state: {}, questions, config, timeoutMs: 5, fetch: slow });
  assert(!timedOut.ok);
  assertEquals(timedOut.failure, "TIMEOUT");
  // Aborted in flight: the provider may have served and billed it.
  assertEquals(timedOut.costUnknown, true);

  const turn = new AbortController();
  const cancelled = askJev({ state: {}, questions, config, signal: turn.signal, fetch: slow });
  turn.abort();
  const result = await cancelled;
  assert(!result.ok);
  assertEquals(result.failure, "CANCELLED");
  // A cancelled turn is not a cost to chase; it is a turn that is going away.
  assertEquals(result.costUnknown, false);
});

Deno.test("a missing key is never a request", async () => {
  let called = false;
  const result = await askJev({
    state: {}, questions, config: { ...config, apiKey: null },
    fetch: () => { called = true; return Promise.resolve(new Response("{}")); },
  });
  assert(!result.ok);
  assertEquals(result.failure, "NOT_CONFIGURED");
  assertEquals(called, false);
});

Deno.test("usage is read only from the provider's own field names", () => {
  assertEquals(usageOf({ usage: { input_tokens: 10, output_tokens: 3 } }), { promptTokens: 10, cachedTokens: 0, completionTokens: 3 });
  // promptTokens is the OpenAI-compatible name; Jev never sends it, and guessing would
  // record a paid call as free.
  assertEquals(usageOf({ usage: { promptTokens: 10 } }), null);
  assertEquals(usageOf({ usage: { input_tokens: 10 } }), { promptTokens: 10, cachedTokens: 0, completionTokens: 0 });
  assertEquals(usageOf({}), null);
});

Deno.test("configuration defaults to off, and a missing key forces off", () => {
  const env = (values: Record<string, string>) => (key: string) => values[key];
  assertEquals(jevConfig(env({})).mode, "off");
  assertEquals(jevConfig(env({ JEV_MODE: "on" })).mode, "off", "no key, no calls");
  assertEquals(jevConfig(env({ JEV_MODE: "on", TYPESAFE_API_KEY: "k" })).mode, "on");
  assertEquals(jevConfig(env({ JEV_MODE: "nonsense", TYPESAFE_API_KEY: "k" })).mode, "off");
  const tuned = jevConfig(env({ TYPESAFE_API_KEY: "k", JEV_TIMEOUT_MS: "900", JEV_MAX_CALLS_PER_TURN: "1" }));
  assertEquals(tuned.timeoutMs, 900);
  assertEquals(tuned.maxCallsPerTurn, 1);
  assertEquals(jevConfig(env({ TYPESAFE_API_KEY: "k", JEV_TIMEOUT_MS: "-5" })).timeoutMs, 1500);
  assertEquals(jevConfig(env({ TYPESAFE_API_KEY: "k" })).model, "jev-1.13.0");
});
