// F4 §02 · POST /v1/meal/commit — the agent's only write tool, and it can only commit a
// draft it produced in this same turn. Editing or deleting a meal never comes through here;
// those are RLS writes straight from the client (F3).

import { userClient, currentUserId, cors, json } from "../_shared/db.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const userId = await currentUserId(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const db = userClient(req);
  const body = await req.json();
  const opId = req.headers.get("Idempotency-Key") ?? body.draft_id ?? crypto.randomUUID();

  // ⚠️ client_op_id is a uuid column, so a malformed Idempotency-Key came back as Postgres's
  // own `invalid input syntax for type uuid: "…"` — a 400 carrying database internals and the
  // caller's key, for a request this endpoint should simply refuse. Not minted silently either:
  // replacing a bad key with a fresh one would turn a client's retry into a duplicate meal,
  // which is the one thing the key exists to prevent.
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(opId)) {
    return json({ error: "E_SCHEMA", reason: "BAD_IDEMPOTENCY_KEY" }, 422);
  }

  // A 0 kcal meal does not exist; writing 0 means the parser failed.
  if (!body.kcal || body.kcal <= 0) return json({ error: "E_SCHEMA" }, 422);

  const { data, error } = await db.from("meals").insert({
    user_id: userId,
    user_day: body.user_day,
    slot: body.slot,
    text_input: body.name ?? body.text,
    kcal: body.kcal,
    protein_g: body.protein_g,
    carb_g: body.carb_g,
    fat_g: body.fat_g,
    confidence: body.confidence ?? "MEDIUM",
    model_version: body.model_version,
    client_op_id: opId,
  }).select("id").single();

  // The unique index on (user_id, client_op_id) makes a replay a no-op rather than a duplicate.
  if (error && !error.message.includes("duplicate")) return json({ error: error.message }, 400);
  return json({ id: data?.id ?? null, replay: !!error });
});
