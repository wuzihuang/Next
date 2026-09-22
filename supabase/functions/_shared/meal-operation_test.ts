import { assertEquals } from "jsr:@std/assert@1";
import { handleMealWrite, type MealWriteDependencies } from "./meal-operation.ts";

const op = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const meal = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const base = { draft_id: op, user_day: "2026-09-04", slot: "LUNCH", name: "Rice", kcal: 500 };
function request(body: unknown): Request {
  return new Request("http://localhost/meal", { method: "POST", body: JSON.stringify(body) });
}
function dependencies(): MealWriteDependencies {
  return { authenticate: () => Promise.resolve("owner"), existingMeal: () => Promise.resolve(null),
    apply: (_req, args) => Promise.resolve({ error: null, data: {
      operation_id: args.p_operation_id, client_op_id: args.p_operation_id,
      meal_id: args.p_meal_id, id: args.p_meal_id,
    } }) };
}
Deno.test("legacy create retries use a stable row id and retain an existing accepted row", async () => {
  const first = await (await handleMealWrite(request(base), "create", dependencies())).json();
  assertEquals(first.id, op);
  const existing = await (await handleMealWrite(request(base), "create", {
    ...dependencies(), existingMeal: () => Promise.resolve(meal),
  })).json();
  assertEquals(existing.id, meal);
});
Deno.test("invalid nutrients and impossible dates never reach storage", async () => {
  for (const bad of [{ kcal: null }, { kcal: 100000.1 }, { kcal: -1 }, { user_day: "2026-02-30" }, { protein_g: -5 }]) {
    const response = await handleMealWrite(request({ ...base, ...bad }), "create", {
      ...dependencies(), apply: () => { throw new Error("must not call"); },
    });
    assertEquals(response.status, 422);
  }
});
Deno.test("conflicting retries return 409 without database details; mismatched receipts are not success", async () => {
  const conflict = await handleMealWrite(request(base), "create", {
    ...dependencies(), apply: () => Promise.resolve({ data: null, error: { code: "23505", message: "private row details" } }),
  });
  assertEquals(conflict.status, 409);
  assertEquals(await conflict.json(), { error: "OPERATION_CONFLICT" });
  const mismatch = await handleMealWrite(request(base), "create", {
    ...dependencies(), apply: () => Promise.resolve({ data: { operation_id: meal }, error: null }),
  });
  assertEquals(mismatch.status, 503);
});
Deno.test("amendment preserves replacement and deletion rejects unexpected replacement payload", async () => {
  const { draft_id: _, ...replacement } = base;
  let received: unknown;
  const response = await handleMealWrite(request({ operation_id: op, kind: "amend", meal_id: meal,
    replacement: { ...replacement, id: op } }), "operation", {
    ...dependencies(), apply: (req, args) => { received = args.p_payload; return dependencies().apply(req, args); },
  });
  assertEquals(response.status, 200);
  assertEquals((received as Record<string, unknown>).kcal, 500);
  const invalid = await handleMealWrite(request({ operation_id: op, kind: "delete", meal_id: meal,
    replacement }), "operation", dependencies());
  assertEquals(invalid.status, 422);
});

Deno.test("amendment forwards logged_at and rejects an unparseable eating time", async () => {
  const { draft_id: _, ...replacement } = base;
  const loggedAt = "2026-09-06T16:40:00Z";
  let received: unknown;
  const response = await handleMealWrite(request({ operation_id: op, kind: "amend", meal_id: meal,
    replacement: { ...replacement, id: op, protein_g: 28, carb_g: 40, fat_g: 12, logged_at: loggedAt } }),
    "operation", {
      ...dependencies(), apply: (_req, args) => {
        received = args.p_payload;
        return dependencies().apply(_req, args);
      },
    });
  assertEquals(response.status, 200);
  assertEquals((received as Record<string, unknown>).logged_at, loggedAt);
  assertEquals((received as Record<string, unknown>).protein_g, 28);
  const bad = await handleMealWrite(request({ operation_id: op, kind: "amend", meal_id: meal,
    replacement: { ...replacement, id: op, logged_at: "not-a-time" } }), "operation", {
    ...dependencies(), apply: () => { throw new Error("must not call"); },
  });
  assertEquals(bad.status, 422);
});

Deno.test("legacy canonical reconciliation requires every stored field to match", async () => {
  const fields = { user_day: "2026-09-04", slot: "LUNCH", name: "Rice", kcal: 500,
    protein_g: 30, carb_g: 60, fat_g: 10, confidence: "LOW", model_version: "model-v1" };
  const stored = { id: meal, ...fields };
  let applied: string | undefined;
  const deps = { ...dependencies(), canonicalMeal: () => Promise.resolve(stored),
    apply: (req: Request, args: Parameters<MealWriteDependencies["apply"]>[1]) => {
      applied = args.p_meal_id; return dependencies().apply(req, args);
    } };
  const response = await handleMealWrite(request({ ...fields, draft_id: op, id: op, reconcile_only: true }), "create", deps);
  assertEquals(response.status, 200);
  assertEquals(applied, meal);
  assertEquals((await response.json()).requested_meal_id, op);
  for (const key of ["name", "user_day", "slot", "kcal", "protein_g", "carb_g", "fat_g", "confidence", "model_version"]) {
    const changed = { ...stored, [key]: typeof stored[key as keyof typeof stored] === "number" ? 999 : "different" };
    applied = undefined;
    const conflict = await handleMealWrite(request({ ...fields, draft_id: op, id: op, reconcile_only: true }), "create",
      { ...deps, canonicalMeal: () => Promise.resolve(changed) });
    assertEquals(conflict.status, 409);
    assertEquals(applied, undefined);
  }
  const absent = await handleMealWrite(request({ ...fields, draft_id: op, id: op, reconcile_only: true }), "create",
    { ...deps, canonicalMeal: () => Promise.resolve(null) });
  assertEquals(absent.status, 409);
});

Deno.test("manual meal retry compares recorded instants across database timestamp formats", async () => {
  const fields = { user_day: "2026-09-04", slot: "LUNCH", name: "Rice", kcal: 500,
    protein_g: 0, carb_g: 0, fat_g: 0, confidence: "HIGH", model_version: "manual-entry-v1",
    logged_at: "2026-09-04T12:30:00Z" };
  for (const [savedAt, expected] of [["2026-09-04T12:30:00+00:00", 200],
    ["2026-09-04T08:30:00-04:00", 200], ["2026-09-04T12:31:00+00:00", 409]] as const) {
    const response = await handleMealWrite(request({ ...fields, draft_id: op, id: meal }), "create", {
      ...dependencies(), canonicalMeal: () => Promise.resolve({ id: meal, ...fields, logged_at: savedAt }),
    });
    assertEquals(response.status, expected);
  }
});

Deno.test("fractional nutrients survive create validation", async () => {
  const nutrients = { kcal: 123.4, protein_g: 23.6, carb_g: 8.2, fat_g: 2.5,
    fiber_g: 1.3, sugar_g: 0.2, sodium_mg: 45.7 };
  let received: unknown;
  const response = await handleMealWrite(request({ ...base, ...nutrients }), "create", {
    ...dependencies(), apply: (_req, args) => {
      received = args.p_payload;
      return Promise.resolve({ data: { operation_id: op, client_op_id: op, meal_id: op, id: op }, error: null });
    },
  });
  assertEquals(response.status, 200);
  for (const [key, value] of Object.entries(nutrients)) {
    assertEquals((received as Record<string, unknown>)[key], value);
  }
});
