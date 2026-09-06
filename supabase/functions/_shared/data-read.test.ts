import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  bucketTicks,
  catalogForUser,
  dataCatalog,
  MAX_TICK_DAYS,
  readData,
} from "./data-read.ts";
import { queryMetrics, TICK_METRICS } from "./metric-query.ts";
import type { Ctx } from "./sources.ts";

function context(
  tables: Record<string, Record<string, unknown>[]>,
  fail = false,
): Ctx {
  const db = {
    rpc: () => Promise.resolve({ data: [], error: null }),
    from(table: string) {
      let rows = [...(tables[table] ?? [])];
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
        order(k: string, opts?: { ascending?: boolean }) {
          const asc = opts?.ascending !== false;
          rows = [...rows].sort((a, b) => {
            const av = String(a[k] ?? "");
            const bv = String(b[k] ?? "");
            return asc ? av.localeCompare(bv) : bv.localeCompare(av);
          });
          return q;
        },
        limit(n: number) {
          rows = rows.slice(0, n);
          return q;
        },
        range(a: number, b: number) {
          lo = a;
          hi = b;
          return q;
        },
        maybeSingle() {
          return Promise.resolve({
            data: rows[0] ?? null,
            error: fail ? { message: "offline" } : null,
          });
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

Deno.test("a missing activity-minute day stays null and is not a zero", async () => {
  const result = await queryMetrics(context({
    daily_results: [{
      user_id: "u",
      user_day: "2026-09-04",
      daily_training: { active_minutes: 40, distance_m: 1200 },
    }],
  }), {
    metrics: ["activeMinutes", "dayDistance"],
    from: "2026-09-04",
    to: "2026-09-05",
  });
  assertEquals(result.ok, true);
  if (!result.ok) throw Error("failed");
  assertEquals(result.data[0].points, [
    { dayKey: "2026-09-04", value: 40 },
    { dayKey: "2026-09-05", value: null },
  ]);
  assertEquals(result.data[0].evidence.origin, "derived");
  assertEquals(result.data[1].points[0].value, 1200);
});

Deno.test("overnight oxygen is a measured sample, not an unsupported gap", async () => {
  const result = await queryMetrics(context({
    oxygen_samples: [{
      user_id: "u",
      ts: "2026-09-04T22:00:00.000Z",
      spo2: 96,
    }],
  }), {
    metrics: ["bloodOxygen"],
    from: "2026-09-04",
    to: "2026-09-04",
  });
  assertEquals(result.ok, true);
  if (!result.ok) throw Error("failed");
  assertEquals(result.data[0].stats.latest, 96);
  assertEquals(result.data[0].evidence.origin, "measured");
  assertEquals(result.data[0].evidence.status, "complete");
});

Deno.test("overnight oxygen clips to the sleep window when a night exists", async () => {
  const inside = await queryMetrics(context({
    oxygen_samples: [{
      user_id: "u",
      ts: "2026-09-04T22:30:00.000Z",
      spo2: 94,
    }, {
      user_id: "u",
      ts: "2026-09-04T18:00:00.000Z",
      spo2: 99,
    }],
    sleep_nights: [{
      user_id: "u",
      user_day: "2026-09-04",
      sleep_start: "2026-09-04T22:00:00.000Z",
      wake_at: "2026-09-05T06:00:00.000Z",
    }],
  }), {
    metrics: ["bloodOxygen"],
    from: "2026-09-04",
    to: "2026-09-04",
  });
  assertEquals(inside.ok, true);
  if (!inside.ok) throw Error("failed");
  assertEquals(inside.data[0].stats.latest, 94);
  assertEquals(inside.data[0].stats.count, 1);
});

Deno.test("five-minute ticks bucket to forty-eight half-hour means and twelve two-hour sums", () => {
  const start = Date.parse("2026-09-04T04:00:00.000Z");
  const rows = Array.from({ length: 288 }, (_, i) => ({
    ts: new Date(start + i * 300_000).toISOString(),
    value: 2,
  }));
  assertEquals(bucketTicks(rows, 30, "mean").length, 48);
  assertEquals(bucketTicks(rows, 120, "sum").length, 12);
  assertEquals(bucketTicks(rows, 120, "sum")[0].value, 48);
});

Deno.test("each tick metric asks itself, a missing day, and a truncated range", async () => {
  const start = Date.parse("2026-09-04T04:00:00.000Z");
  const samples = Array.from({ length: 12 }, (_, i) => ({
    user_id: "u",
    ts: new Date(start + i * 300_000).toISOString(),
    temp: 36.5,
    hrv: 40,
    cal: 2,
    dis: 10,
  }));
  const ctx = context({ raw_samples: samples });
  for (const metric of TICK_METRICS) {
    const present = await readData(ctx, {
      metric,
      from: "2026-09-04",
      to: "2026-09-04",
    });
    assertEquals(present.ok, true);
    if (!present.ok) throw Error("failed");
    assertEquals(present.data[0].stats.count > 0, true);
    assertEquals(present.data[0].evidence.origin, "measured");

    const missing = await readData(ctx, {
      metric,
      from: "2026-09-05",
      to: "2026-09-05",
    });
    assertEquals(missing.ok, true);
    if (!missing.ok) throw Error("failed");
    assertEquals(missing.data[0].stats.count, 0);
    assertEquals(missing.data[0].evidence.status, "absent");

    const wide = await readData(ctx, {
      metric,
      from: "2026-09-01",
      to: "2026-09-08",
    });
    assertEquals(wide.ok, true);
    if (!wide.ok) throw Error("failed");
    assertEquals(wide.data[0].truncated, true);
    assertEquals(MAX_TICK_DAYS, 2);
  }
});

Deno.test("a day grain longer than the registry cap truncates instead of refusing", async () => {
  const result = await readData(context({ daily_results: [] }), {
    metric: "trainingLoad",
    from: "2025-01-01",
    to: "2026-09-04",
  });
  assertEquals(result.ok, true);
  if (!result.ok) throw Error("failed");
  assertEquals(result.data[0].truncated, true);
  assertEquals(result.data[0].evidence.to, "2026-01-01");
});

Deno.test("the catalogue lists wrist-reported calories and never the system's own ledger tables", () => {
  const catalog = dataCatalog();
  assertEquals(catalog.some((row) => row.metric === "vendorCalories"), true);
  assertEquals(catalog.some((row) => row.metric === "wearRun"), true);
  assertEquals(
    catalog.find((row) => row.metric === "vendorCalories")?.says?.includes(
      "day_fuel.kcal_out",
    ),
    true,
  );
  assertEquals(catalog.some((row) => row.table === "ai_turns"), false);
  assertEquals(catalog.some((row) => row.table === "screen_frames"), false);
  assertEquals(catalog.some((row) => row.table === "profiles"), false);
  assertEquals(
    catalog.find((row) => row.metric === "vendorCalories")?.maxDays,
    MAX_TICK_DAYS,
  );
});

Deno.test("the catalogue reports the actual span of rows this user has", async () => {
  const catalog = await catalogForUser(context({
    raw_samples: [{
      user_id: "u",
      ts: "2026-09-02T04:00:00.000Z",
      temp: 36.2,
    }, {
      user_id: "u",
      ts: "2026-09-04T08:00:00.000Z",
      temp: 36.4,
    }],
    daily_results: [{
      user_id: "u",
      user_day: "2026-09-03",
      training_load: 12,
    }],
  }));
  const ticks = catalog.find((row) => row.metric === "skinTemp");
  assertEquals(ticks?.coverage, { from: "2026-09-02", to: "2026-09-04" });
  const load = catalog.find((row) => row.metric === "trainingLoad");
  assertEquals(load?.coverage, { from: "2026-09-03", to: "2026-09-03" });
});
