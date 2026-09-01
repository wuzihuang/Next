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
