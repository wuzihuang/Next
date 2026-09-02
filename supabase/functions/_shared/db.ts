import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";

/// F4 §01 · the tool bodies build their client from this turn's JWT, so RLS applies and
/// the agent never holds a service_role key.
export function userClient(req: Request): SupabaseClient {
  const auth = req.headers.get("Authorization") ?? "";
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false } },
  );
}

/// Only the settle job and the retention prune use this.
/// ⚠️ service_role bypasses RLS: every statement must carry its own `where user_id = $1`.
export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

export async function currentUserId(req: Request): Promise<string | null> {
  const db = userClient(req);
  const { data } = await db.auth.getUser();
  return data.user?.id ?? null;
}

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, idempotency-key",
  "Access-Control-Allow-Methods": "POST, GET, DELETE, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

/// F2 rule 03 · one calendar. A user day runs local 04:00 → 04:00 the next day.
///
/// ⚠️ This is not `new Date().toISOString().slice(0, 10)`. That is the UTC date, and for
/// anyone west of Greenwich it names a day the user has not reached — the turn then asks
/// every read tool about a day with no row, the ledger stays empty, and *every* number the
/// model writes comes back UNTRACEABLE_NUMBER. The failure looks like a model problem and
/// is a calendar problem.
export function userDayKey(timezone: string, at: Date = new Date()): string {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", hour12: false,
  });
  const p = Object.fromEntries(fmt.formatToParts(at).map((x) => [x.type, x.value]));
  const midnight = Date.parse(`${p.year}-${p.month}-${p.day}T00:00:00Z`);
  // Before 04:00 still belongs to the day that opened yesterday.
  const start = Number(p.hour) < 4 ? midnight - 86_400_000 : midnight;
  return new Date(start).toISOString().slice(0, 10);
}

/// The signed-in user's timezone, or UTC. Every day boundary in the product is cut in it.
export async function userTimezone(db: SupabaseClient, userId: string): Promise<string> {
  const { data } = await db.from("profiles").select("timezone").eq("user_id", userId).maybeSingle();
  return data?.timezone ?? "UTC";
}
