import { acceptSnapshot, readSnapshot } from "./metric-snapshot.ts";
import { z } from "npm:zod@3.25.76";
import { addDays, dayBounds, dayOf } from "./calendar.ts";
import type { ReadContext as Ctx } from "./read-context.ts";

export const METRICS = [
  "trainingLoad",
  "bodyBattery",
  "intakeKcal",
  "burnKcal",
  "deltaKcal",
  "proteinG",
  "weight",
  "bodyFatPct",
  "fatMassKg",
  "leanMassKg",
  "nightHRV",
  "hrvBaseline",
  "nightRHR",
  "sleepMinutes",
  "sleepScore",
  "bloodOxygen",
  "bloodPressure",
  "ecg",
  "activeMinutes",
  "dayDistance",
  "wearRun",
] as const;
export const metricRequestSchema = z.object({
  metrics: z.array(z.enum(METRICS)).min(1).max(8),
  from: z.string(),
  to: z.string(),
  timezone: z.string().optional(),
});
export type Metric = typeof METRICS[number];
export interface MetricRequest {
  metrics: Metric[];
  from: string;
  to: string;
  timezone?: string;
}
type Row = Record<string, unknown>;
const one = (x: unknown): Row => (Array.isArray(x) ? x[0] : x) as Row ?? {};
export type MetricOrigin = "measured" | "derived" | "unknown";
export type MetricGrain = "day" | "measurement" | "tick";
export type MetricDefinition = {
  table: string;
  column: string;
  unit: string;
  nested?: string;
  timestamp?: boolean;
  timestampColumn?: string;
  unsupported?: boolean;
  origin: MetricOrigin;
  grain: MetricGrain;
  measuredAtColumn?: string;
  says?: string;
  checksStale?: boolean;
  clipToSleep?: boolean;
  bucketMinutes?: number;
  agg?: "mean" | "sum";
  maxDays?: number;
  absentZero?: boolean;
};
export const TICK_METRICS = [
  "skinTemp",
  "tickHrv",
  "vendorCalories",
  "distance",
] as const;
export type TickMetric = typeof TICK_METRICS[number];
export const DATA_METRICS = [...METRICS, ...TICK_METRICS] as const;
export type DataMetric = typeof DATA_METRICS[number];
export const MAX_TICK_DAYS = 2;
export const MAX_DAY_SPAN = 366;
export const definitions: Record<DataMetric, MetricDefinition> = {
  trainingLoad: {
    table: "daily_results",
    column: "training_load",
    unit: "load",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
  },
  bodyBattery: {
    table: "daily_results",
    column: "reserve_score",
    unit: "%",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
  },
  intakeKcal: {
    table: "daily_results",
    column: "kcal_in",
    nested: "day_fuel",
    unit: "kcal",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
  },
  burnKcal: {
    table: "daily_results",
    column: "kcal_out",
    nested: "day_fuel",
    unit: "kcal",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
  },
  deltaKcal: {
    table: "daily_results",
    column: "fuel_balance_kcal",
    unit: "kcal",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
  },
  proteinG: {
    table: "daily_results",
    column: "protein_in_g",
    nested: "day_fuel",
    unit: "g",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
  },
  weight: {
    table: "weigh_ins",
    column: "weight_kg",
    unit: "kg",
    timestamp: true,
    origin: "measured",
    grain: "measurement",
    measuredAtColumn: "measured_at",
    maxDays: MAX_DAY_SPAN,
  },
  bodyFatPct: {
    table: "body_composition",
    column: "body_fat_pct",
    unit: "%",
    timestamp: true,
    origin: "derived",
    grain: "measurement",
    measuredAtColumn: "measured_at",
    maxDays: MAX_DAY_SPAN,
  },
  // ⚠️ `composition.dual` draws 脂肪量 vs 瘦体重, but only lean mass was readable: asked for
  // the 12-week comparison the model guessed the name "fatMassKg", the enum rejected it and
  // the turn died. A number the screen draws has to be a number the model can read.
  fatMassKg: {
    table: "body_composition",
    column: "fat_mass_kg",
    unit: "kg",
    timestamp: true,
    origin: "derived",
    grain: "measurement",
    measuredAtColumn: "measured_at",
    maxDays: MAX_DAY_SPAN,
  },
  leanMassKg: {
    table: "body_composition",
    column: "lean_body_mass_kg",
    unit: "kg",
    timestamp: true,
    origin: "derived",
    grain: "measurement",
    measuredAtColumn: "measured_at",
    maxDays: MAX_DAY_SPAN,
  },
  nightHRV: {
    table: "daily_results",
    column: "hrv",
    nested: "reserve_daily",
    unit: "ms",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
  },
  hrvBaseline: {
    table: "daily_results",
    column: "hrv_base",
    nested: "reserve_daily",
    unit: "ms",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
  },
  nightRHR: {
    table: "daily_results",
    column: "rhr",
    nested: "reserve_daily",
    unit: "bpm",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
  },
  sleepMinutes: {
    table: "sleep_nights",
    column: "total_minutes",
    unit: "min",
    origin: "measured",
    grain: "day",
    measuredAtColumn: "wake_at",
    maxDays: MAX_DAY_SPAN,
  },
  // ⚠️ ADR 0008 settles a 0–100 score every night and the sleep page prints it, but the
  // read registry did not list it: asked to compare sleep with training load, the model
  // answered "there is no sleep score in the system" and fell back to duration.
  sleepScore: {
    table: "night_score",
    column: "score",
    unit: "",
    origin: "derived",
    grain: "day",
    measuredAtColumn: "computed_at",
    maxDays: MAX_DAY_SPAN,
    says: "ADR 0008 · the settled sleep score, 0–100, from duration, architecture, recovery and regularity. Derived, not a measurement.",
  },
  bloodOxygen: {
    table: "oxygen_samples",
    column: "spo2",
    unit: "%",
    timestamp: true,
    timestampColumn: "ts",
    origin: "measured",
    grain: "measurement",
    measuredAtColumn: "ts",
    clipToSleep: true,
    maxDays: MAX_DAY_SPAN,
    says: "Overnight automatic SpO2. Not a daytime reading and not an apnea grade.",
  },
  bloodPressure: {
    table: "unsupported",
    column: "",
    unit: "mmHg",
    unsupported: true,
    origin: "unknown",
    grain: "measurement",
  },
  ecg: {
    table: "unsupported",
    column: "",
    unit: "mV",
    unsupported: true,
    origin: "unknown",
    grain: "measurement",
  },
  activeMinutes: {
    table: "daily_results",
    column: "active_minutes",
    nested: "daily_training",
    unit: "min",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
    says: "Minutes where movement reached moderate intensity. Not training load.",
  },
  dayDistance: {
    table: "daily_results",
    column: "distance_m",
    nested: "daily_training",
    unit: "m",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
    says: "Settled distance for the user day, in metres.",
  },
  wearRun: {
    table: "daily_results",
    column: "wear_run",
    unit: "days",
    origin: "derived",
    grain: "day",
    checksStale: true,
    maxDays: MAX_DAY_SPAN,
    absentZero: true,
    says:
      "Consecutive worn days ending on this user day. Null when the run is not live. A count, never a streak to keep.",
  },
  skinTemp: {
    table: "raw_samples",
    column: "temp",
    unit: "°C",
    timestamp: true,
    timestampColumn: "ts",
    origin: "measured",
    grain: "tick",
    measuredAtColumn: "ts",
    bucketMinutes: 30,
    agg: "mean",
    maxDays: MAX_TICK_DAYS,
    says: "Wrist skin temperature in °C. Not core body temperature.",
  },
  tickHrv: {
    table: "raw_samples",
    column: "hrv",
    unit: "ms",
    timestamp: true,
    timestampColumn: "ts",
    origin: "measured",
    grain: "tick",
    measuredAtColumn: "ts",
    bucketMinutes: 30,
    agg: "mean",
    maxDays: MAX_TICK_DAYS,
    says: "RMSSD in ms for this tick, from the band's RR intervals.",
  },
  vendorCalories: {
    table: "raw_samples",
    column: "cal",
    unit: "kcal",
    timestamp: true,
    timestampColumn: "ts",
    origin: "measured",
    grain: "tick",
    measuredAtColumn: "ts",
    bucketMinutes: 120,
    agg: "sum",
    maxDays: MAX_TICK_DAYS,
    says:
      "Wrist-reported calories for the tick. Not the product burn (day_fuel.kcal_out) and not a title of 消耗.",
  },
  distance: {
    table: "raw_samples",
    column: "dis",
    unit: "m",
    timestamp: true,
    timestampColumn: "ts",
    origin: "measured",
    grain: "tick",
    measuredAtColumn: "ts",
    bucketMinutes: 120,
    agg: "sum",
    maxDays: MAX_TICK_DAYS,
    says: "Distance in metres for the tick.",
  },
};

export async function pageRows(
  fetchPage: (
    offset: number,
  ) => PromiseLike<{ data: unknown[] | null; error: unknown }>,
): Promise<Row[]> {
  const rows: Row[] = [];
  for (let offset = 0;; offset += 1000) {
    if (offset >= 100_000) throw Error("RANGE_TOO_DENSE");
    const { data, error } = await fetchPage(offset);
    if (error) throw Error("QUERY_FAILED");
    const page = (data ?? []) as Row[];
    rows.push(...page);
    if (page.length < 1000) break;
  }
  return rows;
}
function dailyResultsSelect(metrics: readonly Metric[]): string {
  const cols = new Set([
    "user_day",
    "id",
    "result_revision",
    "computed_at",
    "calculation_as_of",
    "input_revision",
    "algo_version",
  ]);
  const nested = new Map<string, Set<string>>();
  for (const metric of metrics) {
    const def = definitions[metric];
    if (def.table !== "daily_results" || def.unsupported) continue;
    if (def.nested === "reserve_daily") {
      const set = nested.get("reserve_daily") ?? new Set();
      set.add("night_inputs");
      nested.set("reserve_daily", set);
    } else if (def.nested) {
      const set = nested.get(def.nested) ?? new Set();
      set.add(def.column);
      nested.set(def.nested, set);
    } else if (def.column) {
      cols.add(def.column);
    }
  }
  let select = [...cols].join(",");
  for (const [rel, fields] of nested) {
    select += `,${rel}(${[...fields].join(",")})`;
  }
  return select;
}

export function stampColumn(def: MetricDefinition): string {
  return def.timestampColumn ?? "measured_at";
}

function validDay(day: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(day) && Number.isFinite(Date.parse(day)) &&
    new Date(day).toISOString().slice(0, 10) === day;
}
async function clipSleepWindows(
  ctx: Ctx,
  metrics: readonly Metric[],
  tables: Map<string, Row[]>,
  from: string,
  to: string,
) {
  const clipped = metrics.filter((metric) => definitions[metric].clipToSleep);
  if (clipped.length === 0) return;
  const nights = (await pageRows((offset) =>
    ctx.db.from("sleep_nights")
      .select("sleep_start,wake_at")
      .eq("user_id", ctx.userId)
      .gte("user_day", from)
      .lte("user_day", to)
      .order("user_day")
      .range(offset, offset + 999)
  )).flatMap((row) => {
    if (typeof row.sleep_start !== "string" || typeof row.wake_at !== "string") {
      return [];
    }
    return [{ start: row.sleep_start, end: row.wake_at }];
  });
  if (nights.length === 0) return;
  for (const metric of clipped) {
    const def = definitions[metric];
    const stamp = stampColumn(def);
    const rows = tables.get(def.table) ?? [];
    tables.set(
      def.table,
      rows.filter((row) => {
        const ts = Date.parse(String(row[stamp] ?? ""));
        if (!Number.isFinite(ts)) return false;
        return nights.some((night) => {
          const lo = Date.parse(night.start);
          const hi = Date.parse(night.end);
          return Number.isFinite(lo) && Number.isFinite(hi) && ts >= lo && ts < hi;
        });
      }),
    );
  }
}

async function fetchMetrics(ctx: Ctx, request: MetricRequest) {
  const { from, to } = request, tz = request.timezone ?? ctx.tz;
  if (
    !validDay(from) || !validDay(to) || from > to ||
    request.metrics.length < 1 || request.metrics.length > 8 ||
    request.metrics.some((m) => !definitions[m])
  ) return { ok: false as const, error: "INVALID_RANGE" };
  if ((Date.parse(to) - Date.parse(from)) / 864e5 > 365) {
    return {
      ok: false as const,
      error: "RANGE_TOO_LARGE",
      maxDays: 366,
      recovery: "Split into adjacent ranges of at most 366 days.",
    };
  }
  try {
    new Intl.DateTimeFormat("en", { timeZone: tz }).format();
  } catch {
    return { ok: false as const, error: "INVALID_TIMEZONE" };
  }
  const days = Array.from({
    length: (Date.parse(to) - Date.parse(from)) / 864e5 + 1,
  }, (_, i) => addDays(from, i));
  try {
    const before = await readSnapshot(ctx, from, to);
    const tables = new Map<string, Row[]>();
    for (const metric of request.metrics) {
      const def = definitions[metric];
      if (tables.has(def.table)) continue;
      if (def.unsupported) {
        tables.set(def.table, []);
        continue;
      }
      const stamp = stampColumn(def);
      const select = def.table === "daily_results"
        ? dailyResultsSelect(request.metrics)
        : "*";
      const rows = await pageRows((offset) => {
        let q = ctx.db.from(def.table).select(select).eq("user_id", ctx.userId);
        q = def.timestamp
          ? q.gte(stamp, dayBounds(from, tz).start.toISOString()).lt(
            stamp,
            dayBounds(to, tz).end.toISOString(),
          )
          : q.gte("user_day", from).lte("user_day", to);
        const ordered = q.order(def.timestamp ? stamp : "user_day");
        const paged = def.timestamp && stamp === "measured_at"
          ? ordered.order("id")
          : ordered;
        return paged.range(offset, offset + 999);
      });
      tables.set(def.table, rows);
    }
    await clipSleepWindows(ctx, request.metrics, tables, from, to);
    const data = await Promise.all(request.metrics.map(async (metric) => {
      const def = definitions[metric], rows = tables.get(def.table)!;
      const value = (r: Row) => {
        const parent = def.nested === "reserve_daily"
          ? one(one(r.reserve_daily).night_inputs)
          : def.nested
          ? one(r[def.nested])
          : r;
        const v = parent[def.column];
        const n = typeof v === "number" && Number.isFinite(v) ? v : null;
        if (n === 0 && def.absentZero) return null;
        return n;
      };
      const by = new Map(rows.map((r) => [String(r.user_day), value(r)]));
      const revisions = new Map(
        rows.map((r) => [String(r.user_day), {
          ...(r.result_revision
            ? { resultRevision: String(r.result_revision) }
            : {}),
          ...(r.computed_at ? { computedAt: String(r.computed_at) } : {}),
        }]),
      );
      const points: {
        dayKey: string;
        value: number | null;
        resultRevision?: string;
        computedAt?: string;
      }[] = def.unsupported
        ? []
        : def.timestamp
        ? rows.map((r) => ({
          dayKey: String(r[stampColumn(def)] ?? r.measured_at),
          value: value(r),
        }))
        : days.map((dayKey) => ({
          dayKey,
          value: by.get(dayKey) ?? null,
          ...revisions.get(dayKey),
        }));
      const vals = points.flatMap((p) => p.value === null ? [] : [p.value]);
      const meanOf = (values: number[]) =>
        values.length
          ? values.reduce((sum, v) => sum + v, 0) / values.length
          : null;
      const average = meanOf(vals), latest = points.at(-1)?.value ?? null;
      const split = addDays(from, Math.floor(days.length / 2));
      const halfValues = (first: boolean) =>
        points.filter((p) =>
          (p.dayKey.length === 10 ? p.dayKey : dayOf(p.dayKey, tz)) < split ===
            first
        ).flatMap((p) => p.value === null ? [] : [p.value]);
      const firstHalf = meanOf(halfValues(true)),
        secondHalf = meanOf(halfValues(false));
      const stats = {
        firstToLastObservedChange: vals.length >= 2
          ? vals.at(-1)! - vals[0]
          : null,
        latestVsMean: latest !== null && average !== null
          ? latest - average
          : null,
        secondHalfVsFirstHalf:
          days.length >= 2 && firstHalf !== null && secondHalf !== null
            ? secondHalf - firstHalf
            : null,
        count: vals.length,
        mean: vals.length
          ? vals.reduce((a, b) => a + b, 0) / vals.length
          : null,
        min: vals.length ? Math.min(...vals) : null,
        max: vals.length ? Math.max(...vals) : null,
        latest: points.at(-1)?.value ?? null,
      };
      const present = points.filter((p) => p.value !== null);
      const timestamp = (key: string) =>
        rows.map((r) => r[key]).filter((v): v is string =>
          typeof v === "string" && Number.isFinite(Date.parse(v))
        ).sort().at(-1) ?? null;
      const derived = def.origin === "derived";
      const partial = !def.timestamp && present.length < days.length;
      const stale = Boolean(def.checksStale) &&
        before.some((r: Row) => r.pending === true);
      // The evidence revision identifies the exact queried values, metric, unit and interval.
      const signature = JSON.stringify({
        metric,
        from,
        to,
        tz,
        points,
        ids: rows.map((r) =>
          r.result_revision ?? r.id ?? r.collected_at ?? null
        ),
      });
      const hash = await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(signature),
      );
      const id = Array.from(
        new Uint8Array(hash),
        (b) => b.toString(16).padStart(2, "0"),
      ).join("");
      return {
        metric,
        points,
        stats,
        evidence: {
          id,
          metric,
          unit: def.unit,
          from,
          to,
          timezone: tz,
          source: def.unsupported ? null : def.table,
          definitionVersion: "metric-v1",
          observedAt: new Date().toISOString(),
          coverage: {
            observations: vals.length,
            expectedDays: def.timestamp ? null : days.length,
            missingDays: def.timestamp
              ? null
              : days.filter((d) => by.get(d) == null),
          },
          status: def.unsupported
            ? "unsupported"
            : !vals.length
            ? "absent"
            : stale
            ? "stale"
            : partial
            ? "partial"
            : "complete",
          origin: def.origin,
          actualRange: present.length
            ? { from: present[0].dayKey, to: present.at(-1)!.dayKey }
            : null,
          algorithmVersions: [
            ...new Set(
              rows.map((r) => r.algo_version).filter((v): v is string =>
                typeof v === "string"
              ),
            ),
          ],
          baselineNightCounts: def.nested === "reserve_daily"
            ? rows.map((r) => ({
              dayKey: r.user_day,
              nights: one(one(r.reserve_daily).night_inputs).hrv_nights ?? null,
            }))
            : null,
          computedAt: timestamp("computed_at"),
          measuredAt: timestamp(def.measuredAtColumn ?? stampColumn(def)),
          uploadedAt: timestamp("collected_at"),
          collectionCoverage: def.timestamp
            ? "unknown"
            : partial
            ? "partial"
            : "complete",
          freshness: stale
            ? "pending_calculation"
            : derived
            ? "current_revision"
            : "unknown",
          calculation: before,
        },
      };
    }));
    acceptSnapshot(ctx, before, await readSnapshot(ctx, from, to));
    return { ok: true as const, data };
  } catch (error) {
    if (error instanceof Error && error.message === "SNAPSHOT_CHANGED") {
      return {
        ok: false as const,
        error: "SNAPSHOT_CHANGED",
        recovery:
          "Restart analysis with a fresh context; data changed during retrieval.",
      };
    }
    if (error instanceof Error && error.message === "RANGE_TOO_DENSE") {
      return {
        ok: false as const,
        error: "RANGE_TOO_DENSE",
        recovery: "Request a shorter time range.",
      };
    }
    return {
      ok: false as const,
      error: "QUERY_FAILED",
      status: "query_failed",
    };
  }
}

// Per-request-context ownership: never shared across accounts or turns.
const queryCache = new WeakMap<
  Ctx,
  Map<string, ReturnType<typeof fetchMetrics>>
>();
export function queryMetrics(ctx: Ctx, request: MetricRequest) {
  let cache = queryCache.get(ctx);
  if (!cache) {
    cache = new Map();
    queryCache.set(ctx, cache);
  }
  const key = JSON.stringify([ctx.userId, ctx.tz, request]);
  const existing = cache.get(key);
  if (existing) return existing;
  const pending = fetchMetrics(ctx, request).then((result) => {
    if (!result.ok) cache.delete(key);
    return result;
  });
  cache.set(key, pending);
  return pending;
}
