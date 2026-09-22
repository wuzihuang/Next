import { enforceRequestBudget } from "../_shared/rate-limit.ts";
// F4 §02 · POST /v1/account/delete.
// Sessions are revoked immediately and deletion_requested_at is stamped.
// ⚠️ Screen frames, tool traces and any meal photos in Storage go on the same delete list.
// Missing one of them is a legal event, not a bug — and 11's "There is no undo" has to
// line up with this timing exactly.

import { ARCHIVE_BUCKET } from "../_shared/archive.ts";
import { MEAL_PHOTO_BUCKET } from "../_shared/meal-estimate.ts";
import {
  cors,
  currentUserId,
  json,
  serviceClient,
  userClient,
} from "../_shared/db.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const userId = await currentUserId(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const limited = await enforceRequestBudget(userClient(req), "account-delete");
  if (limited) return limited;
  const body = await req.json().catch(() => ({}));
  // The client's second confirmation is the literal string DELETE.
  if (body.confirm !== "DELETE") return json({ error: "E_SCHEMA" }, 422);

  const db = serviceClient();

  const tombstone = await db.from("profiles")
    .update({ deletion_requested_at: new Date().toISOString() })
    .eq("user_id", userId);
  if (tombstone.error) return json({ error: "DELETE_RETRY_REQUIRED" }, 503);

  // Tombstoning blocks new archive preparation and authenticated object writes.
  // Remove prefix contents, including a pending worker's uploaded object, before
  // removing manifests/user. A racing worker compensates if finalization fails.
  // The header's promise, kept literally: the evidence archive and the meal photos are the
  // two places this account's bytes live outside PostgreSQL, and both empty before the rows.
  for (const bucket of [ARCHIVE_BUCKET, MEAL_PHOTO_BUCKET]) {
    while (true) {
      const objects = await db.storage.from(bucket).list(userId, {
        limit: 100,
      });
      if (objects.error) return json({ error: "DELETE_RETRY_REQUIRED" }, 503);
      if (!objects.data.length) break;
      const removed = await db.storage.from(bucket).remove(
        objects.data.map((o) => `${userId}/${o.name}`),
      );
      if (removed.error) return json({ error: "DELETE_RETRY_REQUIRED" }, 503);
    }
  }

  for (
    const table of [
      "sample_archives",
      "band_rr_evidence",
      "screen_frames",
      "ai_turns",
      "analytics_events",
      "call_changes",
      "meals",
      "meal_favorites",
      "weigh_ins",
      "body_composition",
      "balance_checks",
      "sport_heart_rate_samples",
      "oxygen_samples",
      "response_samples",
      "raw_samples",
      "reserve_samples",
      "night_score",
      "sleep_nights",
      "night_hrv",
      "daily_results",
      "sync_runs",
      "device_capabilities",
      "devices",
      "push_tokens",
    ]
  ) {
    const result = await db.from(table).delete().eq("user_id", userId);
    if (result.error) return json({ error: "DELETE_RETRY_REQUIRED" }, 503);
  }

  await db.auth.admin.signOut(userId, "global").catch(() => {});
  const deleted = await db.auth.admin.deleteUser(userId);
  if (deleted.error) return json({ error: "DELETE_RETRY_REQUIRED" }, 503);

  return json({ deleted: true });
});
