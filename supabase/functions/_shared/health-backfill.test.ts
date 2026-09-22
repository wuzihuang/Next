import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildTools } from "./tools.ts";
import { NumberLedger } from "./ledger.ts";

type Row = Record<string, unknown>;
function reader(tables: Record<string, Row[]>) {
  const db = {
    from(table: string) {
      let rows = tables[table] ?? [];
      const query = {
        select() { return query; },
        eq(key: string, value: unknown) { rows = rows.filter((r) => r[key] === value); return query; },
        gte(key: string, value: string) { rows = rows.filter((r) => String(r[key]) >= value); return query; },
        lte(key: string, value: string) { rows = rows.filter((r) => String(r[key]) <= value); return query; },
        order() { return query; },
        limit(n: number) { rows = rows.slice(0, n); return query; },
        then(resolve: (value: unknown) => unknown) { return Promise.resolve({ data: rows, error: null }).then(resolve); },
      };
      return query;
    },
  };
  const tools = buildTools(db as never, "owner", new NumberLedger(), { dayKey: "2026-09-20", tz: "UTC" });
  return async (entity: string) => await tools.find.execute!({ entity, day: "today" }, {} as never) as {
    ok: boolean; data: { items: Row[]; count: number };
  };
}

Deno.test("find shows a saved manual workout before settlement without inventing load or leaking another user", async () => {
  const find = reader({ manual_sport_sessions: [
    { user_id: "owner", id: "saved", user_day: "2026-09-20", started_at: "2026-09-20T17:00:00Z", ended_at: "2026-09-20T18:00:00Z", sport_mode: 0 },
    { user_id: "other", id: "private", user_day: "2026-09-20" },
  ] });
  const result = await find("sport_session");
  assertEquals(result.ok, true);
  assertEquals(result.data.count, 1);
  assertEquals(result.data.items[0].session_id, "saved");
  assertEquals(result.data.items[0].source, "manual");
  assertEquals(result.data.items[0].load_delta, null);
  assertEquals(result.data.items[0].calculation_pending, true);
});

Deno.test("find presents settled manual contributions once and preserves missing evidence", async () => {
  const find = reader({
    manual_sport_sessions: [{ user_id: "owner", id: "saved", user_day: "2026-09-20" }],
    daily_results: [{ user_id: "owner", user_day: "2026-09-20", daily_training: { evidence: { sessions: [
      { session_id: "saved", source: "manual", load_delta: null, data_status: "missing" },
    ] } } }],
  });
  const result = await find("sport_session");
  assertEquals(result.data.count, 1);
  assertEquals(result.data.items[0].source, "manual");
  assertEquals(result.data.items[0].load_delta, null);
  assertEquals(result.data.items[0].data_status, "missing");
});

Deno.test("find distinguishes reported sleep from device measurements", async () => {
  const find = reader({ sleep_nights: [{ user_id: "owner", user_day: "2026-09-20", total_minutes: 480,
    sleep_start: "2026-09-19T23:00:00Z", wake_at: "2026-09-20T07:00:00Z", raw: { source: "user_reported" } }] });
  const result = await find("sleep_night");
  assertEquals(result.data.items[0].source, "user_reported");
  assertEquals(result.data.items[0].score, null);
});
