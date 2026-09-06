import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { queryMetrics } from "./metric-query.ts";
import type { Ctx } from "./sources.ts";
function context(
  tables: Record<string, Record<string, unknown>[]>,
  fail = false,
): Ctx {
  const db = {
    rpc: () => Promise.resolve({ data: [], error: null }),
    from(table: string) {
      let rows = tables[table] ?? [];
      let lo = 0, hi = 999;
      const q = {
        select() {
          return q;
        },
        eq(k: string, v: unknown) {
          rows = rows.filter((r) => r[k] === v);
          return q;
        },
        gte(k: string, v: string) {
          rows = rows.filter((r) => String(r[k]) >= v);
          return q;
        },
        lte(k: string, v: string) {
          rows = rows.filter((r) => String(r[k]) <= v);
          return q;
        },
        lt(k: string, v: string) {
          rows = rows.filter((r) => String(r[k]) < v);
          return q;
        },
        order() {
          return q;
        },
        range(a: number, b: number) {
          lo = a;
          hi = b;
          return q;
        },
        then(resolve: (v: unknown) => unknown) {
          return Promise.resolve({
            data: rows.slice(lo, hi + 1),
            error: fail ? { message: "offline" } : null,
          }).then(resolve);
        },
      };
      return q;
    },
  };
  return {
    db: db as unknown as Ctx["db"],
    userId: "u",
    dayKey: "2026-09-04",
    tz: "UTC",
  };
}
Deno.test("metric read distinguishes intake from balance, aligns missing days and binds evidence", async () => {
  const ctx = context({
    daily_results: [{
      user_id: "u",
      user_day: "2026-09-03",
      id: "r",
      fuel_balance_kcal: -300,
      day_fuel: { kcal_in: 1800 },
    }],
  });
  const result = await queryMetrics(ctx, {
    metrics: ["intakeKcal", "deltaKcal"],
    from: "2026-09-03",
    to: "2026-09-04",
  });
  assertEquals(result.ok, true);
  if (!result.ok) throw Error("failed");
  assertEquals(result.data[0].points, [{ dayKey: "2026-09-03", value: 1800 }, {
    dayKey: "2026-09-04",
    value: null,
  }]);
  assertEquals(result.data[1].stats.min, -300);
  assertEquals(result.data[0].evidence.metric, "intakeKcal");
  assertEquals(result.data[0].evidence.unit, "kcal");
});
Deno.test("query failure is not an empty healthy dataset", async () => {
  const result = await queryMetrics(context({}, true), {
    metrics: ["intakeKcal"],
    from: "2026-09-03",
    to: "2026-09-04",
  });
  assertEquals(result.ok, false);
});
Deno.test("full pagination preserves middle anomaly and final-day observations", async () => {
  const rows = Array.from(
    { length: 1002 },
    (_, i) => ({
      user_id: "u",
      measured_at: new Date(Date.parse("2026-09-03T04:00:00Z") + i * 60000)
        .toISOString(),
      weight_kg: i === 500 ? 99 : 70,
    }),
  );
  const result = await queryMetrics(context({ weigh_ins: rows }), {
    metrics: ["weight"],
    from: "2026-09-03",
    to: "2026-09-03",
  });
  assertEquals(result.ok, true);
  if (!result.ok) throw Error("failed");
  assertEquals(result.data[0].stats.count, 1002);
  assertEquals(result.data[0].stats.max, 99);
});
Deno.test("metric evidence cache reuses exact request and never crosses user or range", async () => {
  const ctx = context({ daily_results: [] });
  const args = {
    metrics: ["bodyBattery" as const],
    from: "2026-09-03",
    to: "2026-09-04",
  };
  const a = await queryMetrics(ctx, args), b = await queryMetrics(ctx, args);
  assertEquals(a === b, true);
});
Deno.test("oversized history asks caller to split range instead of claiming absent data", async () => {
  const result = await queryMetrics(context({}), {
    metrics: ["weight"],
    from: "2020-01-01",
    to: "2026-09-04",
  });
  assertEquals(result.ok, false);
  if (result.ok) throw Error("expected bounded read");
  assertEquals(result.error, "RANGE_TOO_LARGE");
});
Deno.test("formal daily points expose result revision and computation timestamp", async () => {
  const result = await queryMetrics(
    context({
      daily_results: [{
        user_id: "u",
        user_day: "2026-09-04",
        result_revision: "r1",
        computed_at: "2026-09-04T12:00:00Z",
        reserve_score: 65,
      }],
    }),
    { metrics: ["bodyBattery"], from: "2026-09-04", to: "2026-09-04" },
  );
  assertEquals(result.ok, true);
  if (!result.ok) throw Error("failed");
  assertEquals(result.data[0].points[0], {
    dayKey: "2026-09-04",
    value: 65,
    resultRevision: "r1",
    computedAt: "2026-09-04T12:00:00Z",
  });
});
Deno.test("a concurrent calculation change returns retryable failure rather than mixed evidence", async () => {
  const ctx = context({ daily_results: [] });
  let calls = 0;
  ctx.db.rpc = (() =>
    Promise.resolve({
      data: [{ result_revision: ++calls === 1 ? "old" : "new" }],
      error: null,
    })) as unknown as typeof ctx.db.rpc;
  const args = {
    metrics: ["bodyBattery" as const],
    from: "2026-09-04",
    to: "2026-09-04",
  };
  const first = await queryMetrics(ctx, args);
  assertEquals(first.ok, false);
  if (first.ok) throw Error("mixed read");
  assertEquals(first.error, "SNAPSHOT_CHANGED");
  const retry = await queryMetrics(ctx, args);
  assertEquals(retry.ok, true);
});
Deno.test("read metadata distinguishes partial, stale, absent and unsupported without inventing timestamps", async () => {
  const ctx = context({
    daily_results: [{
      user_id: "u",
      user_day: "2026-09-03",
      reserve_score: 40,
      algo_version: "calc-1",
      computed_at: "2026-09-03T12:00:00Z",
    }],
  });
  const result = await queryMetrics(ctx, {
    metrics: ["bodyBattery"],
    from: "2026-09-03",
    to: "2026-09-04",
  });
  if (!result.ok) throw Error("failed");
  assertEquals(result.data[0].evidence.status, "partial");
  assertEquals(result.data[0].evidence.origin, "derived");
  assertEquals(result.data[0].evidence.actualRange, {
    from: "2026-09-03",
    to: "2026-09-03",
  });
  assertEquals(result.data[0].evidence.measuredAt, null);
  ctx.db.rpc = (() =>
    Promise.resolve({
      data: [{ pending: true }],
      error: null,
    })) as unknown as typeof ctx.db.rpc;
  const stale = await queryMetrics({ ...ctx }, {
    metrics: ["bodyBattery"],
    from: "2026-09-03",
    to: "2026-09-04",
  });
  if (!stale.ok) throw Error("failed");
  assertEquals(stale.data[0].evidence.status, "stale");
});
Deno.test("overnight oxygen is collected as measured samples rather than an unsupported hole", async () => {
  const result = await queryMetrics(context({
    oxygen_samples: [{
      user_id: "u",
      ts: "2026-09-04T22:00:00.000Z",
      spo2: 97,
    }],
  }), {
    metrics: ["bloodOxygen"],
    from: "2026-09-04",
    to: "2026-09-04",
  });
  if (!result.ok) throw Error("expected overnight oxygen");
  assertEquals(result.data[0].stats.latest, 97);
  assertEquals(result.data[0].evidence.status, "complete");
  assertEquals(result.data[0].evidence.origin, "measured");
});
Deno.test("separate successful reads in one turn cannot mix different day revisions", async () => {
  const ctx = context({ daily_results: [] });
  let version = "A";
  ctx.db.rpc = (() =>
    Promise.resolve({
      data: [{ user_day: "2026-09-04", result_revision: version }],
      error: null,
    })) as unknown as typeof ctx.db.rpc;
  assertEquals(
    (await queryMetrics(ctx, {
      metrics: ["bodyBattery"],
      from: "2026-09-04",
      to: "2026-09-04",
    })).ok,
    true,
  );
  version = "B";
  const result = await queryMetrics(ctx, {
    metrics: ["intakeKcal"],
    from: "2026-09-04",
    to: "2026-09-04",
  });
  assertEquals(result.ok, false);
  if (result.ok) throw Error("mixed");
  assertEquals(result.error, "SNAPSHOT_CHANGED");
});
Deno.test("full-range changes are computed by server without treating missing endpoint as zero", async () => {
  const result = await queryMetrics(
    context({
      daily_results: [
        { user_id: "u", user_day: "2026-09-01", reserve_score: 40 },
        { user_id: "u", user_day: "2026-09-02", reserve_score: 60 },
        { user_id: "u", user_day: "2026-09-03", reserve_score: 80 },
      ],
    }),
    { metrics: ["bodyBattery"], from: "2026-09-01", to: "2026-09-04" },
  );
  if (!result.ok) throw Error("failed");
  assertEquals(result.data[0].stats.firstToLastObservedChange, 40);
  assertEquals(result.data[0].stats.latestVsMean, null);
  assertEquals(result.data[0].stats.secondHalfVsFirstHalf, 30);
});

Deno.test("wear run of zero is absent, not a live count", async () => {
  const result = await queryMetrics(
    context({
      daily_results: [
        { user_id: "u", user_day: "2026-09-03", wear_run: 4 },
        { user_id: "u", user_day: "2026-09-04", wear_run: 0 },
      ],
    }),
    { metrics: ["wearRun"], from: "2026-09-03", to: "2026-09-04" },
  );
  if (!result.ok) throw Error("failed");
  assertEquals(result.data[0].points, [
    { dayKey: "2026-09-03", value: 4 },
    { dayKey: "2026-09-04", value: null },
  ]);
});
