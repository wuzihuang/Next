// F4 §02 · POST /v1/account/delete.
// Sessions are revoked immediately and deletion_requested_at is stamped.
// ⚠️ Screen frames, tool traces and any meal photos in Storage go on the same delete list.
// Missing one of them is a legal event, not a bug — and 11's "There is no undo" has to
// line up with this timing exactly.

import { serviceClient, currentUserId, cors, json } from "../_shared/db.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const userId = await currentUserId(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const body = await req.json().catch(() => ({}));
  // The client's second confirmation is the literal string DELETE.
  if (body.confirm !== "DELETE") return json({ error: "E_SCHEMA" }, 422);

  const db = serviceClient();

  await db.from("profiles")
    .update({ deletion_requested_at: new Date().toISOString() })
    .eq("user_id", userId);

  for (const table of ["screen_frames", "ai_turns", "analytics_events", "meals",
                       "weigh_ins", "body_composition", "raw_samples", "reserve_samples",
                       "sleep_nights", "daily_results", "sync_runs", "devices"]) {
    await db.from(table).delete().eq("user_id", userId);
  }

  await db.auth.admin.signOut(userId, "global").catch(() => {});
  await db.auth.admin.deleteUser(userId).catch(() => {});

  return json({ deleted: true });
});
