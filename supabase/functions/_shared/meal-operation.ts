import { z } from "npm:zod@3.25.76";
import { cors, json } from "./db.ts";

const UUID = z.string().uuid().transform((value) => value.toLowerCase());
const Day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine((value) => {
  const date = new Date(`${value}T12:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
});
const Fields = z.object({
  user_day: Day,
  slot: z.enum(["BREAKFAST", "LUNCH", "DINNER", "SNACK"]),
  name: z.string().min(1).max(8000),
  kcal: z.number().int().positive().max(100000),
  protein_g: z.number().int().min(0).max(100000).default(0),
  carb_g: z.number().int().min(0).max(100000).default(0),
  fat_g: z.number().int().min(0).max(100000).default(0),
  logged_at: z.string().min(10).max(64).refine((value) => Number.isFinite(Date.parse(value))).optional(),
  confidence: z.enum(["LOW", "MEDIUM", "HIGH"]).default("MEDIUM"),
  model_version: z.string().max(256).default(""),
});
export const MealCommit = Fields.extend({ draft_id: UUID, id: UUID.optional() });
export const MealOperation = z.discriminatedUnion("kind", [
  z.object({ operation_id: UUID, kind: z.literal("delete"), meal_id: UUID }).strict(),
  z.object({ operation_id: UUID, kind: z.literal("amend"), meal_id: UUID,
    replacement: Fields.extend({ id: UUID }).strict() }).strict(),
]);
export type MealWriteDependencies = {
  authenticate(req: Request): Promise<string | null>;
  budget?(req: Request): Promise<Response | null>;
  existingMeal(req: Request, operationId: string): Promise<string | null>;
  canonicalMeal?(req: Request, operationId: string): Promise<Record<string, unknown> | null>;
  apply(req: Request, args: { p_operation_id: string; p_kind: string; p_meal_id: string; p_payload: unknown }):
    Promise<{ data: unknown; error: { code?: string; message?: string } | null }>;
};

export async function handleMealWrite(req: Request, mode: "create" | "operation", deps: MealWriteDependencies): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  if (!await deps.authenticate(req)) return json({ error: "UNAUTHENTICATED" }, 401);
  const limited=await deps.budget?.(req);
  if(limited)return limited;
  let raw: unknown;
  try {
    const text = await req.text();
    if (text.length > 32000) return json({ error: "PAYLOAD_TOO_LARGE" }, 413);
    raw = JSON.parse(text);
  } catch { return json({ error: "E_SCHEMA" }, 422); }
  let operationId: string, kind: string, mealId: string, payload: unknown;
  let requestedMealId: string | undefined;
  try {
    if (mode === "create") {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) return json({ error: "E_SCHEMA" }, 422);
      const source = raw as Record<string, unknown>;
      const parsed = MealCommit.safeParse({ ...source, name: source.name ?? source.text,
        draft_id: req.headers.get("Idempotency-Key") ?? source.draft_id });
      if (!parsed.success) return json({ error: "E_SCHEMA" }, 422);
      const { id, draft_id, ...fields } = parsed.data;
      operationId = draft_id; kind = "create";
      // Legacy clients did not send a row id. Reuse an existing row, or choose a stable id.
      const canonical = await deps.canonicalMeal?.(req, draft_id);
      if (canonical) {
        if (canonical.deleted_at != null || !Object.entries(fields).every(([key, value]) => canonical[key] === value)
          || typeof canonical.id !== "string") return json({ error: "OPERATION_CONFLICT" }, 409);
        mealId = canonical.id;
        if (id && id !== mealId) requestedMealId = id;
      } else {
        // Recovery probes may acknowledge an identical existing record, never create one.
        if (source.reconcile_only === true) return json({ error: "NO_CANONICAL_MATCH" }, 409);
        mealId = id ?? await deps.existingMeal(req, draft_id) ?? draft_id;
      }
      payload = fields;
    } else {
      const parsed = MealOperation.safeParse(raw);
      if (!parsed.success) return json({ error: "E_SCHEMA" }, 422);
      operationId = parsed.data.operation_id; kind = parsed.data.kind; mealId = parsed.data.meal_id;
      payload = parsed.data.kind === "amend" ? parsed.data.replacement : {};
    }
    const { data, error } = await deps.apply(req, {
      p_operation_id: operationId, p_kind: kind, p_meal_id: mealId, p_payload: payload,
    });
    if (error) {
      if (error.code === "23505") return json({ error: "OPERATION_CONFLICT" }, 409);
      if (error.code === "P0002") return json({ error: "MEAL_NOT_FOUND" }, 404);
      if (error.code === "42501" || error.code === "28000") return json({ error: "NOT_AUTHORIZED" }, 403);
      if (error.code?.startsWith("22") || error.code === "23514") return json({ error: "E_SCHEMA" }, 422);
      return json({ error: "MEAL_WRITE_UNAVAILABLE" }, 503);
    }
    const receipt = data as Record<string, unknown> | null;
    if (receipt?.operation_id !== operationId || receipt?.client_op_id !== operationId || receipt?.meal_id !== mealId) {
      return json({ error: "INVALID_ACKNOWLEDGMENT" }, 503);
    }
    return json({ ...receipt, ...(requestedMealId ? { requested_meal_id: requestedMealId } : {}) });
  } catch { return json({ error: "MEAL_WRITE_UNAVAILABLE" }, 503); }
}
