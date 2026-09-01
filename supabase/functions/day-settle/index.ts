// F4 §02 · POST /v1/day/settle — service_role only, driven by pg_cron + pg_net.
// ⚠️ F2 §01 · the window decides how many pages to pull: a normal daytime settle needs one,
// but the closing settle always straddles two. Missing the second page does not error —
// it just quietly loses the small hours, which is why this is the easiest thing to get wrong.

import { serviceClient, cors, json } from "../_shared/db.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const secret = req.headers.get("x-settle-secret");
  if (secret !== Deno.env.get("SETTLE_SECRET")) return json({ error: "FORBIDDEN" }, 403);

  const { user_id, day_key } = await req.json();
  const db = serviceClient();

  const { data: already } = await db.from("daily_results")
    .select("computed_at, inputs_hash")
    .eq("user_id", user_id).eq("user_day", day_key).maybeSingle();

  const { data, error } = await db.rpc("settle_day", { p_user: user_id, p_user_day: day_key });
  if (error) return json({ error: error.message }, 500);

  const { data: after } = await db.from("daily_results")
    .select("inputs_hash").eq("user_id", user_id).eq("user_day", day_key).maybeSingle();

  // inputs_hash unchanged and already settled → a replay, not a recompute.
  if (already && after && already.inputs_hash === after.inputs_hash) {
    return json({ code: "IDEMPOTENT_REPLAY", result_id: data });
  }
  return json({ result_id: data });
});
