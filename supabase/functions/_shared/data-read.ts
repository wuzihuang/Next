import { z } from "npm:zod@3.25.76";
import {
  definitions,
  METRICS,
  queryMetrics,
  type Metric,
} from "./metric-query.ts";
import { addDays, dayBounds, type Ctx } from "./sources.ts";

export const TICK_METRICS = [
  "skinTemp",
  "tickHrv",
  "vendorCalories",
  "distance",
] as const;
export type TickMetric = typeof TICK_METRICS[number];
export const DATA_METRICS = [...METRICS, ...TICK_METRICS] as const;
export type DataMetric = typeof DATA_METRICS[number];

export type TickDefinition = {
  table: "raw_samples";
  column: string;
  unit: string;
  grain: "tick";
  origin: "measured";
  bucketMinutes: number;
  agg: "mean" | "sum";
  says: string;
};

export const TICK_DEFINITIONS: Record<TickMetric, TickDefinition> = {
  skinTemp: {
    table: "raw_samples",
    column: "temp",
    unit: "°C",
    grain: "tick",
    origin: "measured",
    bucketMinutes: 30,
    agg: "mean",
    says: "Wrist skin temperature in °C. Not core body temperature.",
  },
  tickHrv: {
    table: "raw_samples",
    column: "hrv",
    unit: "ms",
    grain: "tick",
    origin: "measured",
    bucketMinutes: 30,
    agg: "mean",
    says: "RMSSD in ms for this tick, from the band's RR intervals.",
  },
  vendorCalories: {
    table: "raw_samples",
    column: "cal",
    unit: "kcal",
    grain: "tick",
    origin: "measured",
    bucketMinutes: 120,
    agg: "sum",
    says:
      "Wrist-reported calories for the tick. Not the product burn (day_fuel.kcal_out) and not a title of 消耗.",
  },
  distance: {
    table: "raw_samples",
    column: "dis",
    unit: "m",
    grain: "tick",
    origin: "measured",
    bucketMinutes: 120,
    agg: "sum",
    says: "Distance in metres for the tick.",
  },
};

const BLOCKED_TABLES = new Set([
  "ai_turns",
  "screen_frames",
  "profiles",
  "request_budgets",
  "ai_quotas",
  "ai_model_calls",
]);

export const MAX_TICK_DAYS = 2;

export const dataReadSchema = z.object({
  metric: z.enum(DATA_METRICS),
  from: z.string().optional(),
  to: z.string().optional(),
  bucketMinutes: z.number().int().min(5).max(120).optional(),
});

export type DataReadRequest = z.infer<typeof dataReadSchema>;

export function dataCatalog(): {
  metric: string;
  unit: string;
  grain: string;
  origin: string;
  says?: string;
  table: string;
  maxDays: number;
}[] {
  const day = METRICS.filter((metric) => {
    const def = definitions[metric];
    return !BLOCKED_TABLES.has(def.table);
  }).map((metric) => {
    const def = definitions[metric];
    return {
      metric,
      unit: def.unit,
      grain: def.grain ?? (def.timestamp ? "measurement" : "day"),
      origin: def.origin ??
        (def.unsupported
          ? "unknown"
          : def.table === "daily_results" || def.table === "body_composition"
          ? "derived"
          : "measured"),
      says: def.says,
      table: def.table,
      maxDays: 366,
    };
  });
  const ticks = TICK_METRICS.map((metric) => {
    const def = TICK_DEFINITIONS[metric];
    return {
      metric,
      unit: def.unit,
      grain: def.grain,
      origin: def.origin,
      says: def.says,
      table: def.table,
      maxDays: MAX_TICK_DAYS,
    };
  });
  return [...day, ...ticks];
}

export function bucketTicks(
  rows: { ts: string; value: number }[],
  minutes: number,
  agg: "mean" | "sum",
): { ts: string; value: number }[] {
  const width = minutes * 60_000;
  const groups = new Map<number, number[]>();
  for (const row of rows) {
    const key = Math.floor(Date.parse(row.ts) / width) * width;
    const values = groups.get(key) ?? [];
    values.push(row.value);
    groups.set(key, values);
  }
  return [...groups.entries()].sort((a, b) => a[0] - b[0]).map(([ts, values]) => ({
    ts: new Date(ts).toISOString(),
    value: agg === "sum"
      ? values.reduce((sum, value) => sum + value, 0)
      : values.reduce((sum, value) => sum + value, 0) / values.length,
  }));
}

export async function readData(ctx: Ctx, request: DataReadRequest) {
  const metric = request.metric;
  const from = request.from ?? ctx.dayKey;
  const to = request.to ?? ctx.dayKey;
  if (BLOCKED_TABLES.has(tableFor(metric))) {
    return { ok: false as const, error: "UNKNOWN_METRIC" };
  }
  if (isTickMetric(metric)) {
    return await readTicks(ctx, metric, from, to, request.bucketMinutes);
  }
  const result = await queryMetrics(ctx, {
    metrics: [metric as Metric],
    from,
    to,
    timezone: ctx.tz,
  });
  if (!result.ok) return result;
  return {
    ok: true as const,
    data: result.data.map((row) => ({ ...row, truncated: false })),
  };
}

function tableFor(metric: DataMetric): string {
  if (isTickMetric(metric)) return TICK_DEFINITIONS[metric].table;
  return definitions[metric as Metric].table;
}

function isTickMetric(metric: string): metric is TickMetric {
  return (TICK_METRICS as readonly string[]).includes(metric);
}

async function readTicks(
  ctx: Ctx,
  metric: TickMetric,
  from: string,
  to: string,
  bucketMinutes?: number,
) {
  const def = TICK_DEFINITIONS[metric];
  const span = (Date.parse(to) - Date.parse(from)) / 86_400_000 + 1;
  const truncated = span > MAX_TICK_DAYS;
  const end = truncated ? addDays(from, MAX_TICK_DAYS - 1) : to;
  const lo = dayBounds(from, ctx.tz).start.toISOString();
  const hi = dayBounds(end, ctx.tz).end.toISOString();
  const rows: Record<string, unknown>[] = [];
  for (let offset = 0;; offset += 1000) {
    if (offset >= 100000) {
      return { ok: false as const, error: "RANGE_TOO_DENSE" };
    }
    const { data, error } = await ctx.db.from("raw_samples")
      .select("ts, temp, hrv, cal, dis")
      .eq("user_id", ctx.userId)
      .gte("ts", lo)
      .lt("ts", hi)
      .order("ts")
      .range(offset, offset + 999);
    if (error) return { ok: false as const, error: "QUERY_FAILED" };
    const page = (data ?? []) as unknown as Record<string, unknown>[];
    rows.push(...page);
    if (page.length < 1000) break;
  }
  const numeric = rows.flatMap((row) => {
    const value = row[def.column];
    if (typeof value !== "number" || !Number.isFinite(value)) return [];
    if (typeof row.ts !== "string") return [];
    return [{ ts: row.ts, value }];
  });
  const points = bucketTicks(
    numeric,
    bucketMinutes ?? def.bucketMinutes,
    def.agg,
  );
  const cap = 60;
  const clipped = points.length > cap;
  const kept = clipped ? points.slice(0, cap) : points;
  const values = kept.map((point) => point.value);
  return {
    ok: true as const,
    data: [{
      metric,
      points: kept.map((point) => ({
        dayKey: point.ts,
        value: point.value,
      })),
      stats: {
        count: values.length,
        mean: values.length
          ? values.reduce((sum, value) => sum + value, 0) / values.length
          : null,
        min: values.length ? Math.min(...values) : null,
        max: values.length ? Math.max(...values) : null,
        latest: values.at(-1) ?? null,
      },
      truncated: truncated || clipped,
      evidence: {
        id: `${metric}:${from}:${end}`,
        metric,
        unit: def.unit,
        from,
        to: end,
        timezone: ctx.tz,
        source: def.table,
        origin: def.origin,
        status: values.length ? (truncated || clipped ? "partial" : "complete") : "absent",
        says: def.says,
      },
    }],
  };
}
