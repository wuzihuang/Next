// Authenticated portable NDJSON export. Fail closed if any hot or cold partition is
// unreadable; a partial download must never look like a complete account export.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { readSampleHistory } from "../_shared/archive.ts";
import { cors, currentUserId, json, userClient } from "../_shared/db.ts";
import { enforceRequestBudget } from "../_shared/rate-limit.ts";

const TABLES: {
  name: string;
  table: string;
  keys: string[];
  select?: string;
  ownerColumn?: string;
}[] = [
  { name: "measurements", table: "body_composition", keys: ["id"] },
  // ADR 0010 · 平衡检查的摘要行。只有摘要，没有逐拍序列可导。
  { name: "balance_checks", table: "balance_checks", keys: ["id"] },
  { name: "meals", table: "meals", keys: ["id"] },
  { name: "daily_rollup", table: "daily_results", keys: ["user_day"] },
  { name: "weigh_ins", table: "weigh_ins", keys: ["id"] },
  { name: "night_hrv", table: "night_hrv", keys: ["user_day"] },
  { name: "oxygen_samples", table: "oxygen_samples", keys: ["ts", "src"] },
  { name: "response_samples", table: "response_samples", keys: ["ts", "src"],
    select: "ts,sampled_tz,src" },
  { name: "sleep_nights", table: "sleep_nights", keys: ["user_day"] },
  { name: "night_score", table: "night_score", keys: ["user_day"] },
  { name: "day_fuel", table: "day_fuel", keys: ["result_id"] },
  { name: "daily_training", table: "daily_training", keys: ["result_id"] },
  { name: "reserve_daily", table: "reserve_daily", keys: ["result_id"] },
  { name: "reserve_samples", table: "reserve_samples", keys: ["ts"] },
  { name: "conversations", table: "conversations", keys: ["id"] },
  {
    name: "conversation_messages",
    table: "conversation_messages",
    keys: ["id"],
  },
  {
    name: "ai_turns",
    table: "ai_turns",
    keys: ["id"],
    select:
      "id,user_id,created_at,user_text,frame_id,model_version,latency_ms,outcome,conversation_id",
  },
  {
    name: "screen_frames",
    table: "screen_frames",
    keys: ["id"],
    select:
      "id,user_id,created_at,expires_at,trigger,widget_tree,theme,model_version,latency_ms",
  },
  { name: "devices", table: "devices", keys: ["id"] },
  {
    name: "device_capabilities",
    table: "device_capabilities",
    keys: ["device_id"],
    select: "*,devices!inner(user_id)",
    ownerColumn: "devices.user_id",
  },
  {
    name: "band_ingestion_sources",
    table: "band_ingestion_sources",
    keys: ["device_key", "mapping_version"],
  },
  { name: "fasted_days", table: "fasted_days", keys: ["user_day"] },
  { name: "meal_operations", table: "meal_operations", keys: ["operation_id"] },
  { name: "call_changes", table: "call_changes", keys: ["id"] },
  { name: "consents", table: "consents", keys: ["id"] },
  { name: "sync_runs", table: "sync_runs", keys: ["id"] },
  {
    name: "sync_domain_status",
    table: "sync_domain_status",
    keys: ["device_key", "user_day", "domain"],
  },
];
const README = `NEXTBODY DATA EXPORT

Each .ndjson file contains canonical account-owned rows, one JSON object per line.
measurements is body_composition; daily_rollup is daily_results. Detail tables join
on result_id. A user day runs local 04:00 to 04:00. Null is unknown, never zero.
meals retains original and soft-deleted/amended records, including operation IDs.
sleep_nights includes actual sleep stage runs and recorded sleep/wake times.
night_score is the settled sleep score for each night with its four group scores and the measured inputs behind them; a group score is a weighted mean over the inputs that existed.
oxygen_samples contains overnight automatic SpO2, not an apnea grade.
response_samples contains timestamps of wrist optical meal-response points, not a blood test and not a concentration.
conversations and conversation_messages retain complete original stored messages;
summary is a bounded deterministic excerpt, not a replacement for those originals.
ai_turns and screen_frames omit tool traces, which may contain raw tool prompts.
raw_samples and band_rr_evidence include verified cold history; hot corrections win.
A failed partition or exceeded export budget returns an error, never a partial export.
`;
export interface ExportDependencies {
  authenticate: (request: Request) => Promise<string | null>;
  client: (request: Request) => SupabaseClient;
  history: typeof readSampleHistory;
  budget: (db: SupabaseClient) => Promise<Response | null>;
}
const defaults: ExportDependencies = {
  authenticate: currentUserId,
  client: userClient,
  history: readSampleHistory,
  budget: (db) => enforceRequestBudget(db, "export"),
};
const PAGE = 1000, MAX_ROWS = 100000, MAX_BYTES = 128 * 1024 * 1024;
async function readTable(
  db: SupabaseClient,
  userId: string,
  table: typeof TABLES[number],
) {
  const rows: Record<string, unknown>[] = [];
  for (let offset = 0;; offset += PAGE) {
    let query = db.from(table.table).select(table.select ?? "*").eq(
      table.ownerColumn ?? "user_id",
      userId,
    );
    for (const key of table.keys) query = query.order(key);
    const { data, error } = await query.range(offset, offset + PAGE - 1);
    if (error) throw Error("EXPORT_QUERY_FAILED");
    const page = (data ?? []) as unknown as Record<string, unknown>[];
    if (rows.length + page.length > MAX_ROWS) {
      throw Error("EXPORT_BUDGET_EXCEEDED");
    }
    rows.push(...page);
    if (page.length < PAGE) return rows;
  }
}
export async function handleExport(
  req: Request,
  deps = defaults,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST" && req.method !== "GET") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }
  try {
    const userId = await deps.authenticate(req);
    if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);
    const db = deps.client(req), limited = await deps.budget(db);
    if (limited) return limited;
    const { data: profile, error: profileError } = await db.from("profiles")
      .select("*").eq("user_id", userId).maybeSingle();
    if (profileError) throw Error("EXPORT_QUERY_FAILED");
    if (profile?.deletion_requested_at) {
      return json({ error: "ACCOUNT_DELETING" }, 403);
    }
    // Withdrawal stops analysis and collection; it does not remove the right to export
    // one's own retained records. No granted-consent requirement on this boundary.
    const generatedAt = new Date().toISOString();
    const payload: Record<string, string> = { "README.txt": README };
    let bytes = new TextEncoder().encode(README).length;
    const append = (name: string, rows: unknown[]) => {
      const body = rows.map((row) => JSON.stringify(row)).join("\n");
      bytes += new TextEncoder().encode(body).length;
      if (bytes > MAX_BYTES) throw Error("EXPORT_BUDGET_EXCEEDED");
      payload[name + ".ndjson"] = body;
    };
    append("profile", profile ? [profile] : []);
    for (const table of TABLES) {
      append(table.name, await readTable(db, userId, table));
    }
    for (const domain of ["raw_samples", "band_rr_evidence"] as const) {
      const rows = await deps.history(
        db,
        userId,
        "1970-01-01T00:00:00Z",
        generatedAt,
        domain,
      );
      if (rows.length > MAX_ROWS) throw Error("EXPORT_BUDGET_EXCEEDED");
      append(domain, rows);
    }
    return json({
      generated_at: generatedAt,
      files: Object.entries(payload).map(([name, body]) => ({
        name,
        bytes: new TextEncoder().encode(body).length,
      })),
      payload,
    });
  } catch (error) {
    return json({
      error:
        error instanceof Error && error.message === "EXPORT_BUDGET_EXCEEDED"
          ? "EXPORT_BUDGET_EXCEEDED"
          : "EXPORT_UNAVAILABLE",
      message:
        "The complete export could not be read. No partial export was returned; retry or request a bounded export.",
    }, 503);
  }
}
if (import.meta.main) Deno.serve((req) => handleExport(req));
