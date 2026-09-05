import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleMeal, type MealDependencies } from "./index.ts";

function request(body: unknown): Request {
  return new Request("http://localhost/meal", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

function deps(overrides: Partial<MealDependencies> = {}): MealDependencies {
  const db = {
    from() {
      const q = {
        select() {
          return q;
        },
        eq() {
          return q;
        },
        order() {
          return q;
        },
        limit() {
          return q;
        },
        maybeSingle() {
          return Promise.resolve({ data: { choice: "granted" }, error: null });
        },
      };
      return q;
    },
  };
  return {
    authenticate: () => Promise.resolve("u"),
    client: () => db as never,
    budget: () => Promise.resolve(null),
    quota: () => Promise.resolve({ allowed: true as const }),
    generateObject: () => {
      throw new Error("model must not run");
    },
    recordUsage: () => Promise.resolve(),
    ...overrides,
  };
}

Deno.test("an exhausted daily allowance never calls the meal model", async () => {
  let generated = false;
  const response = await handleMeal(
    request({ text: "rice", locale: "en-US" }),
    deps({
      quota: () => Promise.resolve({ allowed: false, reason: "count" }),
      generateObject: () => {
        generated = true;
        return Promise.resolve({ object: {}, usage: {} }) as never;
      },
    }),
  );
  assertEquals(response.status, 429);
  assertEquals(generated, false);
  const body = await response.json();
  assertEquals(body.error, "RATE_LIMITED");
  assertEquals(body.fallback_frame.title, "SLOW DOWN");
});

Deno.test("a allowed meal records token usage from the model result", async () => {
  const recorded: unknown[] = [];
  const response = await handleMeal(
    request({ text: "rice", locale: "en-US" }),
    deps({
      generateObject: () =>
        Promise.resolve({
          object: {
            name: "Rice",
            kcal: 200,
            protein_g: 4,
            carb_g: 40,
            fat_g: 1,
            confidence: "HIGH",
          },
          usage: { promptTokens: 100, completionTokens: 20 },
        }) as never,
      recordUsage: (_db, usage) => {
        recorded.push(usage);
        return Promise.resolve();
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, [{
    promptTokens: 100,
    cachedTokens: 0,
    completionTokens: 20,
  }]);
});
