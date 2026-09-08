import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { readData } from "./data-read.ts";
import { type Ctx, fetchAs } from "./sources.ts";

type Row = Record<string, unknown>;

function fixture(tables: Record<string, Row[]>, overrides: Partial<Ctx> = {}) {
  const reads = new Map<string, number>();
  const state = { revision: "revision-1", pending: false };
  const db = {
    rpc: () => Promise.resolve({
      data: [{ user_day: "2026-09-03", result_revision: state.revision, pending: state.pending }],
      error: null,
    }),
    from(table: string) {
      let rows = [...(tables[table] ?? [])], lo = 0, hi = 999;
      const orders: { key: string; ascending: boolean }[] = [];
      const q = {
        select: () => q,
        eq(key: string, value: unknown) {
          rows = rows.filter((row) => row[key] === value);
          return q;
        },
        gte(key: string, value: string) {
          rows = rows.filter((row) => String(row[key]) >= value);
          return q;
        },
        lte(key: string, value: string) {
          rows = rows.filter((row) => String(row[key]) <= value);
          return q;
        },
        lt(key: string, value: string) {
          rows = rows.filter((row) => String(row[key]) < value);
          return q;
        },
        order(key: string, options?: { ascending?: boolean }) {
          orders.push({ key, ascending: options?.ascending !== false });
          return q;
        },
        range(a: number, b: number) { lo = a; hi = b; return q; },
        then<T>(resolve: (value: { data: Row[]; error: null }) => T) {
          reads.set(table, (reads.get(table) ?? 0) + 1);
          rows.sort((a, b) => {
            for (const { key, ascending } of orders) {
              const compared = String(a[key]).localeCompare(String(b[key]));
              if (compared) return ascending ? compared : -compared;
            }
            return 0;
          });
          return Promise.resolve({ data: rows.slice(lo, hi + 1), error: null }).then(resolve);
        },
      };
      return q;
    },
  };
  const ctx: Ctx = {
    db: db as unknown as Ctx["db"], userId: "u", dayKey: "2026-09-08", tz: "UTC",
    from: "2026-09-03", to: "2026-09-04", cache: new Map(), ...overrides,
  };
  return { ctx, reads, state };
}

Deno.test("weight read and chart share midnight records, the historical window and evidence", async () => {
  const { ctx, reads } = fixture({ weigh_ins: [
    { user_id: "u", id: "0", measured_at: "2026-09-02T23:59:00Z", weight_kg: 99 },
    { user_id: "u", id: "1", measured_at: "2026-09-03T01:00:00Z", weight_kg: 80 },
    { user_id: "u", id: "2", measured_at: "2026-09-03T05:00:00Z", weight_kg: 79 },
    { user_id: "u", id: "3", measured_at: "2026-09-04T05:00:00Z", weight_kg: 78 },
    { user_id: "u", id: "4", measured_at: "2026-09-05T00:00:00Z", weight_kg: 77 },
    { user_id: "other", id: "5", measured_at: "2026-09-03T01:00:00Z", weight_kg: 100 },
  ] });
  const read = await readData(ctx, { metric: "weight", from: ctx.from, to: ctx.to });
  if (!read.ok) throw Error("formal read failed");
  const chart = await fetchAs("weight.30d", "curve", ctx);
  if (!chart || chart.data.kind !== "curve") throw Error("chart failed");
  assertEquals(read.data[0].points.map((point) => point.value), [80, 79, 78]);
  assertEquals(chart.data.series.map((point) => point[1]), [80, 79, 78]);
  const stats = read.data[0].stats;
  if (!("firstToLastObservedChange" in stats)) throw Error("missing measurement statistics");
  assertEquals(chart.agg.change, stats.firstToLastObservedChange);
  assertEquals(chart.agg.change, -2);
  assertEquals(chart.evidence, read.data[0].evidence);
  assertEquals(chart.evidence?.origin, "measured");
  assertEquals(chart.window, "2 DAYS");
  assertEquals(reads.get("weigh_ins"), 1, "reading then drawing reuses one formal snapshot");
});

Deno.test("daily chart preserves missing days and calendar-half statistics from the formal read", async () => {
  const { ctx } = fixture({ daily_results: [
    { user_id: "u", user_day: "2026-09-01", reserve_score: 40, result_revision: "r1" },
    { user_id: "u", user_day: "2026-09-02", reserve_score: 60, result_revision: "r1" },
    { user_id: "u", user_day: "2026-09-03", reserve_score: 80, result_revision: "r1" },
    { user_id: "u", user_day: "2026-09-05", reserve_score: 99, result_revision: "r2" },
  ] }, { from: "2026-09-01", to: "2026-09-04" });
  const read = await readData(ctx, { metric: "bodyBattery", from: ctx.from, to: ctx.to });
  if (!read.ok) throw Error("formal read failed");
  const chart = await fetchAs("bodyBattery.7d", "curve", ctx);
  if (!chart || chart.data.kind !== "curve") throw Error("chart failed");
  assertEquals(read.data[0].points.map((point) => point.value), [40, 60, 80, null]);
  assertEquals(chart.data.series.map((point) => point[1]), [40, 60, 80]);
  const stats = read.data[0].stats;
  if (!("secondHalfVsFirstHalf" in stats)) throw Error("missing daily statistics");
  assertEquals(chart.agg.thisHalfVsPrevHalf, stats.secondHalfVsFirstHalf);
  assertEquals(chart.agg.thisHalfVsPrevHalf, 30);
  assertEquals(chart.agg.latest, null);
  assertEquals(chart.hero, "——");
  assertEquals(chart.evidence, read.data[0].evidence);
  assertEquals(chart.evidence?.status, "partial");
  assertEquals(chart.evidence?.coverage, { observations: 3, expectedDays: 4, missingDays: ["2026-09-04"] });
  assertEquals(chart.window, "4 DAYS");
});

Deno.test("chart projections retain stale status, algorithm version and origin", async () => {
  const { ctx, state } = fixture({ daily_results: [
    { user_id: "u", user_day: "2026-09-03", training_load: 2, algo_version: "tl-2.2", result_revision: "r1" },
    { user_id: "u", user_day: "2026-09-04", training_load: 4, algo_version: "tl-2.2", result_revision: "r1" },
  ] });
  state.pending = true;
  const read = await readData(ctx, { metric: "trainingLoad", from: ctx.from, to: ctx.to });
  if (!read.ok) throw Error("formal read failed");
  const chart = await fetchAs("trainingLoad.7d", "column", ctx);
  assertEquals(chart?.evidence, read.data[0].evidence);
  assertEquals(chart?.evidence?.status, "stale");
  assertEquals(chart?.evidence?.algorithmVersions, ["tl-2.2"]);
  assertEquals(chart?.evidence?.origin, "derived");
});

Deno.test("a calculation revision changing between reading and drawing rejects mixed evidence", async () => {
  const { ctx, state } = fixture({ daily_results: [
    { user_id: "u", user_day: "2026-09-03", training_load: 2, result_revision: "r1" },
    { user_id: "u", user_day: "2026-09-04", training_load: 4, result_revision: "r1" },
  ] });
  const read = await readData(ctx, { metric: "trainingLoad", from: ctx.from, to: ctx.to });
  assertEquals(read.ok, true);
  state.revision = "revision-2";
  await assertRejects(() => fetchAs("trainingLoad.7d", "curve", ctx), Error, "SNAPSHOT_CHANGED");
});

Deno.test("a chart's default span ends at the explicitly requested historical day", async () => {
  const { ctx } = fixture({ weigh_ins: [
    { user_id: "u", id: "1", measured_at: "2026-08-06T01:00:00Z", weight_kg: 81 },
    { user_id: "u", id: "2", measured_at: "2026-09-04T05:00:00Z", weight_kg: 78 },
    { user_id: "u", id: "3", measured_at: "2026-09-07T05:00:00Z", weight_kg: 77 },
  ] }, { from: undefined, to: "2026-09-04" });
  const chart = await fetchAs("weight.30d", "curve", ctx);
  if (!chart || chart.data.kind !== "curve") throw Error("chart failed");
  assertEquals(chart.data.series.map((point) => point[1]), [81, 78]);
  assertEquals(chart.evidence?.from, "2026-08-06");
  assertEquals(chart.evidence?.to, "2026-09-04");
});

Deno.test("weight projections use local midnight across a daylight-saving day", async () => {
  const { ctx } = fixture({ weigh_ins: [
    { user_id: "u", id: "0", measured_at: "2026-03-08T04:59:00Z", weight_kg: 99 },
    { user_id: "u", id: "1", measured_at: "2026-03-08T05:00:00Z", weight_kg: 80 },
    { user_id: "u", id: "2", measured_at: "2026-03-09T03:59:00Z", weight_kg: 79 },
    { user_id: "u", id: "3", measured_at: "2026-03-09T04:00:00Z", weight_kg: 78 },
  ] }, { from: "2026-03-08", to: "2026-03-08", tz: "America/New_York" });
  const read = await readData(ctx, { metric: "weight", from: ctx.from, to: ctx.to });
  if (!read.ok) throw Error("formal read failed");
  const chart = await fetchAs("weight.30d", "curve", ctx);
  if (!chart || chart.data.kind !== "curve") throw Error("chart failed");
  assertEquals(chart.data.series.map((point) => point[1]), [80, 79]);
  assertEquals(chart.evidence, read.data[0].evidence);
});
