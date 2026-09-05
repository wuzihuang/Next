import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { cors, json } from "./db.ts";
export type BudgetEndpoint =
  | "metric-read"
  | "meal-commit"
  | "meal-operation"
  | "turn"
  | "archive-data"
  | "export"
  | "account-delete";
/** serviceOwner is only for an already authenticated internal service worker. SQL
 * independently denies its privileged RPC to every authenticated/anonymous user. */
export async function enforceRequestBudget(
  db: SupabaseClient,
  endpoint: BudgetEndpoint,
  serviceOwner?: string,
): Promise<Response | null> {
  try {
    const result = serviceOwner
      ? await db.rpc("consume_internal_request_budget", {
        p_owner: serviceOwner,
        p_endpoint: endpoint,
      })
      : await db.rpc("consume_request_budget", { p_endpoint: endpoint });
    if (result.error || typeof result.data?.allowed !== "boolean") {
      return json({ error: "REQUEST_BUDGET_UNAVAILABLE" }, 503);
    }
    if (result.data.allowed) return null;
    const retry = Math.min(
      60,
      Math.max(1, Number(result.data.retry_after) || 60),
    );
    return new Response(
      JSON.stringify({ error: "RATE_LIMITED", retry_after: retry }),
      {
        status: 429,
        headers: {
          ...cors,
          "Content-Type": "application/json",
          "Retry-After": String(retry),
        },
      },
    );
  } catch {
    return json({ error: "REQUEST_BUDGET_UNAVAILABLE" }, 503);
  }
}
