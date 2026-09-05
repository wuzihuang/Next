import { enforceRequestBudget } from "../_shared/rate-limit.ts";
import { cors, currentUserId, json, userClient } from "../_shared/db.ts";
import { metricRequestSchema, queryMetrics } from "../_shared/metric-query.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

export interface MetricReadDependencies {
  authenticate: (request: Request) => Promise<string | null>;
  client: (request: Request) => SupabaseClient;
  read: typeof queryMetrics;
  budget: (request: Request) => Promise<Response | null>;
}
const dependencies: MetricReadDependencies = {
  authenticate: currentUserId,
  client: userClient,
  read: queryMetrics,
  budget: (request) => enforceRequestBudget(userClient(request), "metric-read"),
};

/** UI and AI use the same account-scoped formal readings. No privileged DB client. */
export async function handleMetricRead(
  req: Request,
  deps = dependencies,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") {
    return json({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405);
  }
  try {
    const userId = await deps.authenticate(req);
    if (!userId) return json({ ok: false, error: "UNAUTHENTICATED" }, 401);
    const limited = await deps.budget(req);
    if (limited) return limited;
    const text = await req.text();
    if (text.length > 4096) {
      return json({ ok: false, error: "REQUEST_TOO_LARGE" }, 413);
    }
    let body: unknown;
    try {
      body = JSON.parse(text);
    } catch {
      return json({ ok: false, error: "INVALID_BODY" }, 422);
    }
    const parsed = metricRequestSchema.safeParse(body);
    if (!parsed.success) return json({ ok: false, error: "INVALID_BODY" }, 422);
    const db = deps.client(req);
    const [consent, profile] = await Promise.all([
      db.from("consents").select("choice").eq("user_id", userId).order(
        "decided_at",
        { ascending: false },
      ).limit(1).maybeSingle(),
      db.from("profiles").select("timezone,deletion_requested_at").eq(
        "user_id",
        userId,
      )
        .maybeSingle(),
    ]);
    if (consent.error || profile.error) {
      return json({ ok: false, error: "ACCESS_CHECK_UNAVAILABLE" }, 503);
    }
    if (profile.data?.deletion_requested_at) {
      return json({ ok: false, error: "ACCOUNT_DELETING" }, 403);
    }
    if (consent.data?.choice !== "granted") {
      return json({ ok: false, error: "consent_withdrawn" }, 403);
    }
    const tz = parsed.data.timezone ?? profile.data?.timezone ?? "UTC";
    const result = await deps.read({
      db,
      userId,
      dayKey: parsed.data.to,
      tz,
      cache: new Map(),
    }, parsed.data);
    if (!result.ok) {
      return json(
        result,
        result.error === "SNAPSHOT_CHANGED"
          ? 409
          : result.error === "QUERY_FAILED"
          ? 503
          : 422,
      );
    }
    return json(result);
  } catch {
    // No SQL details or token values leave this boundary.
    return json({ ok: false, error: "READ_UNAVAILABLE" }, 503);
  }
}

if (import.meta.main) Deno.serve((req) => handleMetricRead(req));
