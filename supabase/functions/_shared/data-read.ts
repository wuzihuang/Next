import { z } from "npm:zod@3.25.76";
import {
  DATA_METRICS,
  definitions,
  MAX_DAY_SPAN,
  MAX_TICK_DAYS,
  METRICS,
  pageRows,
  queryMetrics,
  stampColumn,
  type DataMetric,
  type Metric,
} from "./metric-query.ts";
import { addDays, dayBounds, type Ctx } from "./sources.ts";

export {
  DATA_METRICS,
  MAX_DAY_SPAN,
  MAX_TICK_DAYS,
  TICK_METRICS,
  type DataMetric,
  type TickMetric,
} from "./metric-query.ts";

/// Inclusive day count of a from→to window, at least 1.
export function spanDays(from: string, to: string): number {
  const days = Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000) + 1;
  return Number.isFinite(days) ? Math.max(1, days) : 1;
}

const BLOCKED_TABLES = new Set([
  "ai_turns",
  "screen_frames",
  "profiles",
  "request_budgets",
  "ai_quotas",
  "ai_model_calls",
]);

// ⚠️ Permissive on purpose. `metric: z.enum(DATA_METRICS)` threw
// AI_InvalidToolArgumentsError on a guessed name ("fatMassKg" before it existed) and the
// SDK turns that into a dead turn — the panel falls back over a spelling. The name is
// checked in readData(), which answers with the list of real ones.
export const dataReadSchema = z.object({
  metric: z.coerce.string().describe("A metric id from data.catalog"),
  from: z.coerce.string().optional(),
  to: z.coerce.string().optional(),
  bucketMinutes: z.coerce.number().int().min(5).max(120).optional(),
});

export type DataReadRequest = z.infer<typeof dataReadSchema>;

export type CatalogRow = {
  metric: string;
  unit: string;
  grain: string;
  origin: string;
  says?: string;
  table: string;
  maxDays: number;
  coverage?: { from: string | null; to: string | null } | null;
};

export function dataCatalog(): CatalogRow[] {
  return DATA_METRICS.filter((metric) => {
    const def = definitions[metric];
    return !BLOCKED_TABLES.has(def.table);
  }).map((metric) => {
    const def = definitions[metric];
    return {
      metric,
      unit: def.unit,
      grain: def.grain,
      origin: def.origin,
      says: def.says,
      table: def.table,
      maxDays: def.maxDays ?? (def.grain === "tick" ? MAX_TICK_DAYS : MAX_DAY_SPAN),
    };
  });
}

export async function catalogForUser(ctx: Ctx): Promise<CatalogRow[]> {
  const rows = dataCatalog();
  const coverage = new Map<string, { from: string | null; to: string | null }>();
  for (const row of rows) {
    if (row.table === "unsupported" || coverage.has(row.table)) continue;
    coverage.set(row.table, await coverageForTable(ctx, row.metric as DataMetric));
  }
  return rows.map((row) => ({
    ...row,
    coverage: row.table === "unsupported" ? null : coverage.get(row.table) ?? null,
  }));
}

async function coverageForTable(
  ctx: Ctx,
  metric: DataMetric,
): Promise<{ from: string | null; to: string | null }> {
  const def = definitions[metric];
  const stamp = def.timestamp || def.grain === "tick"
    ? stampColumn(def)
    : "user_day";
  try {
    const first = await ctx.db.from(def.table)
      .select(stamp)
      .eq("user_id", ctx.userId)
      .order(stamp, { ascending: true })
      .limit(1)
      .maybeSingle();
    const last = await ctx.db.from(def.table)
      .select(stamp)
      .eq("user_id", ctx.userId)
      .order(stamp, { ascending: false })
      .limit(1)
      .maybeSingle();
    return {
      from: stampOf(first, stamp),
      to: stampOf(last, stamp),
    };
  } catch {
    return { from: null, to: null };
  }
}

function stampOf(
  result: { data?: unknown; error?: unknown } | null | undefined,
  stamp: string,
): string | null {
  if (!result || result.error) return null;
  const row = result.data as Record<string, unknown> | null | undefined;
  return dayStamp(row?.[stamp]);
}

function dayStamp(value: unknown): string | null {
  if (typeof value !== "string" || value.length < 10) return null;
  return value.slice(0, 10);
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
  const metric = request.metric as DataMetric;
  const def = definitions[metric];
  // A name the registry does not have comes back as the list of names it does have.
  if (!def) {
    return {
      ok: false as const,
      error: "UNKNOWN_METRIC",
      say: `"${request.metric}" is not a metric. Read one of: ${DATA_METRICS.join(", ")}.`,
    };
  }
  const from = request.from ?? ctx.dayKey;
  const to = request.to ?? ctx.dayKey;
  if (BLOCKED_TABLES.has(def.table)) {
    return { ok: false as const, error: "UNKNOWN_METRIC" };
  }
  const maxDays = def.maxDays ?? (def.grain === "tick" ? MAX_TICK_DAYS : MAX_DAY_SPAN);
  const span = (Date.parse(to) - Date.parse(from)) / 86_400_000 + 1;
  const truncated = Number.isFinite(span) && span > maxDays;
  const end = truncated ? addDays(from, maxDays - 1) : to;
  if (def.grain === "tick") {
    return await readTicks(ctx, metric, from, end, truncated, request.bucketMinutes);
  }
  if (!(METRICS as readonly string[]).includes(metric)) {
    return { ok: false as const, error: "UNKNOWN_METRIC" };
  }
  const result = await queryMetrics(ctx, {
    metrics: [metric as Metric],
    from,
    to: end,
    timezone: ctx.tz,
  });
  if (!result.ok) return result;
  // ⚠️ The window the read actually covered, in the two units a person says it in. Asked
  // for twelve weeks of composition and finding two days, the model wrote "12 周窗口内仅 2 天
  // 有记录" — true, honest, and thrown away as an untraceable 12, because a span was
  // derivable for a series of timestamps and not for the range the read was given.
  const windowDays = spanDays(from, end);
  return {
    ok: true as const,
    data: result.data.map((row) => ({
      ...row,
      truncated,
      stats: { ...row.stats, days: windowDays, weeks: Math.round(windowDays / 7) },
      evidence: {
        ...row.evidence,
        to: end,
        status: truncated && row.evidence.status === "complete"
          ? "partial"
          : row.evidence.status,
      },
    })),
  };
}

async function readTicks(
  ctx: Ctx,
  metric: DataMetric,
  from: string,
  to: string,
  truncated: boolean,
  bucketMinutes?: number,
) {
  const def = definitions[metric];
  const lo = dayBounds(from, ctx.tz).start.toISOString();
  const hi = dayBounds(to, ctx.tz).end.toISOString();
  let rows: Record<string, unknown>[];
  try {
    rows = await pageRows((offset) =>
      ctx.db.from("raw_samples")
        .select("ts, temp, hrv, cal, dis")
        .eq("user_id", ctx.userId)
        .gte("ts", lo)
        .lt("ts", hi)
        .order("ts")
        .range(offset, offset + 999)
    );
  } catch (error) {
    const code = error instanceof Error ? error.message : "QUERY_FAILED";
    return {
      ok: false as const,
      error: code === "RANGE_TOO_DENSE" ? "RANGE_TOO_DENSE" : "QUERY_FAILED",
    };
  }
  const numeric = rows.flatMap((row) => {
    const value = row[def.column];
    if (typeof value !== "number" || !Number.isFinite(value)) return [];
    if (typeof row.ts !== "string") return [];
    return [{ ts: row.ts, value }];
  });
  const points = bucketTicks(
    numeric,
    bucketMinutes ?? def.bucketMinutes ?? 30,
    def.agg ?? "mean",
  );
  const cap = 60;
  const windowDays = spanDays(from, to);
  const clipped = points.length > cap;
  const kept = clipped ? points.slice(0, cap) : points;
  const values = kept.map((point) => point.value);
  const partial = truncated || clipped;
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
        // ⚠️ The window this read covered, in the two units a person says it in. Asked for
        // twelve weeks of composition and finding two days, the model wrote "12 周窗口内仅 2
        // 天有记录" — true, honest, and thrown away as an untraceable 12, because a span was
        // derivable for a series of timestamps and not for the range the read was given.
        days: windowDays,
        weeks: Math.round(windowDays / 7),
      },
      truncated: partial,
      evidence: {
        id: `${metric}:${from}:${to}`,
        metric,
        unit: def.unit,
        from,
        to,
        timezone: ctx.tz,
        source: def.table,
        origin: def.origin,
        status: values.length ? (partial ? "partial" : "complete") : "absent",
        says: def.says,
      },
    }],
  };
}
