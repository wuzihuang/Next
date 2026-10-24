import { enforceRequestBudget } from "../_shared/rate-limit.ts";
// F4 §02 · POST /v1/account/delete.
// Sessions are revoked immediately and deletion_requested_at is stamped.
// ⚠️ Screen frames, tool traces and any meal photos in Storage go on the same delete list.
// Missing one of them is a legal event, not a bug — and 11's "There is no undo" has to
// line up with this timing exactly.

import { ARCHIVE_BUCKET } from "../_shared/archive.ts";
import { MEAL_PHOTO_BUCKET } from "../_shared/meal-estimate.ts";
import { FEEDBACK_BUCKET } from "../_shared/feedback.ts";
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
  // The header's promise, kept literally: the evidence archive, the meal photos and the
  // screenshots sent with REPORT A PROBLEM are where this account's bytes live outside
  // PostgreSQL, and all of them empty before the rows.
  for (const bucket of [ARCHIVE_BUCKET, MEAL_PHOTO_BUCKET, FEEDBACK_BUCKET]) {
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

  // Every user table cascades from auth.users. The RPC deletes the user inside a
  // calculation-maintenance window, so raw_samples does not invalidate a day per row —
  // table by table over PostgREST that took longer than the phones wait.
  const purged = await db.rpc("purge_account", { p_owner: userId });
  if (purged.error || purged.data?.deleted !== true) {
    console.error("account-delete: purge failed", purged.error?.message);
    return json({ error: "DELETE_RETRY_REQUIRED" }, 503);
  }

  return json({ deleted: true });
});
