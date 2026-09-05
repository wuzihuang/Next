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
  for (const bad of [{ kcal: null }, { kcal: 1.2 }, { kcal: -1 }, { user_day: "2026-02-30" }, { protein_g: -5 }]) {
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
