import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleTurn, type TurnDependencies } from "./index.ts";

function request(text = "how is my heart"): Request {
  return new Request("http://localhost/turn", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ text, locale: "en-US" }),
  });
}

function deps(overrides: Partial<TurnDependencies> = {}): TurnDependencies {
  const db = {
    from(table: string) {
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
        order() {
          return q;
        },
        limit() {
          return q;
        },
        maybeSingle() {
          if (table === "consents") {
            return Promise.resolve({ data: { choice: "granted" }, error: null });
          }
          if (table === "profiles") {
            return Promise.resolve({
              data: { locale: "en-US", timezone: "UTC", deletion_requested_at: null },
              error: null,
            });
          }
          return Promise.resolve({ data: null, error: null });
        },
        then(resolve: (value: unknown) => unknown) {
          return Promise.resolve({ data: [], error: null, count: 0 }).then(resolve);
        },
      };
      return q;
    },
    rpc(name: string) {
      if (name === "claim_ai_turn") {
        return Promise.resolve({ data: { status: "claimed" }, error: null });
      }
      if (name === "release_ai_turn") {
        return Promise.resolve({ data: null, error: null });
      }
      return Promise.resolve({ data: [], error: null });
    },
  };
  return {
    authenticate: () => Promise.resolve("u"),
    client: () => db as never,
    budget: () => Promise.resolve(null),
    quota: () => Promise.resolve({ allowed: true as const, remaining: 9 }),
    streamText: () => {
      throw new Error("model must not run");
    },
    generateObject: () => {
      throw new Error("vision must not run");
    },
    recordUsage: () => Promise.resolve(),
    ...overrides,
  };
}

Deno.test("an exhausted daily allowance never starts the model", async () => {
  let streamed = false;
  const response = await handleTurn(
    request(),
    deps({
      quota: () => Promise.resolve({ allowed: false, reason: "count" }),
      streamText: () => {
        streamed = true;
        throw new Error("model must not run");
      },
    }),
  );
  assertEquals(streamed, false);
  const text = await response.text();
  assertEquals(response.headers.get("Content-Type")?.includes("event-stream"), true);
  assertEquals(text.includes("RATE_LIMITED"), true);
  assertEquals(text.includes("SLOW DOWN"), true);
});

Deno.test("an allowed turn starts the model after the daily allowance is claimed", async () => {
  let streamed = false;
  const response = await handleTurn(
    request(),
    deps({
      streamText: () => {
        streamed = true;
        return { fullStream: (async function* () {})() } as never;
      },
    }),
  );
  const text = await response.text();
  assertEquals(streamed, true);
  assertEquals(text.includes("event: state"), true);
});
