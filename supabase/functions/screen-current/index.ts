// F4 §02 · GET /v1/screen/current — cold start, foregrounding and reconnect all pull the
// panel back from here instead of asking the model again.
// ⚠️ DELETE does not blank the panel: it falls back to the battery widget, because
// 07 says the panel is never allowed to be empty.

import { userClient, currentUserId, cors, json } from "../_shared/db.ts";
import { batteryFallback } from "../_shared/contract.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const userId = await currentUserId(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const db = userClient(req);

  if (req.method === "DELETE") {
    const { data } = await db.from("daily_results")
      .select("reserve_score").eq("user_id", userId)
      .order("user_day", { ascending: false }).limit(1).maybeSingle();
    return json({ envelope: batteryFallback(data?.reserve_score ?? null) });
  }

  const { data } = await db.from("screen_frames")
    .select("widget_tree, created_at, expires_at").eq("user_id", userId)
    .order("created_at", { ascending: false }).limit(1).maybeSingle();

  if (!data || (data.expires_at && new Date(data.expires_at) < new Date())) {
    const { data: latest } = await db.from("daily_results")
      .select("reserve_score").eq("user_id", userId)
      .order("user_day", { ascending: false }).limit(1).maybeSingle();
    return json({ envelope: batteryFallback(latest?.reserve_score ?? null), expired: true });
  }

  return json({
    envelope: data.widget_tree, renderedAt: data.created_at, expiresAt: data.expires_at,
  });
});
