// F4 §02 · POST /v1/export → GET. Five NDJSON files plus a README of the field meanings,
// zipped into a private bucket; the GET returns a URL signed for fifteen minutes.
// ⚠️ The export never contains the raw prompt text from tool_trace.

import { userClient, currentUserId, cors, json } from "../_shared/db.ts";

const TABLES = [
  ["measurements", "body_composition"],
  ["meals", "meals"],
  ["daily_rollup", "daily_results"],
  ["weigh_ins", "weigh_ins"],
] as const;

const README = `NEXTBODY DATA EXPORT

measurements.ndjson   one row per body-composition measurement.
                      measurement_source: device_bia | health_scale | manual
                      derived_fields lists the values multiplied out rather than measured.
meals.ndjson          append-only. A row with deleted_at set was edited or removed;
                      the replacement is a separate row with its own client_op_id.
daily_rollup.ndjson   one row per user day (local 04:00 -> 04:00).
                      training_load 0-21, reserve_score 0-100, and the algo_version
                      that produced them.
weigh_ins.ndjson      the weight series, independent of any BIA reading.
profile.ndjson        your profile plus per-field provenance.

A null is not a zero. Where a value is null we did not know it; where it is 0 you told us
it was 0.
`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const userId = await currentUserId(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const db = userClient(req);
  const parts: Record<string, string> = { "README.txt": README };

  for (const [name, table] of TABLES) {
    const { data } = await db.from(table).select("*").eq("user_id", userId).limit(20000);
    parts[`${name}.ndjson`] = (data ?? []).map((r) => JSON.stringify(r)).join("\n");
  }
  const { data: profile } = await db.from("profiles")
    .select("*").eq("user_id", userId).maybeSingle();
  parts["profile.ndjson"] = profile ? JSON.stringify(profile) : "";

  return json({
    generated_at: new Date().toISOString(),
    files: Object.entries(parts).map(([name, body]) => ({ name, bytes: body.length })),
    // The client streams the parts straight down; a real deployment writes the zip to a
    // private bucket and returns a signed URL valid for fifteen minutes.
    payload: parts,
  });
});
