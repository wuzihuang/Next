import { z } from "npm:zod@3.25.76";
import { type Metric, METRICS, queryMetrics } from "./metric-query.ts";
import { dayOf } from "./calendar.ts";
import type { ReadContext as Ctx } from "./read-context.ts";
// ⚠️ Strings, not enums, for the same reason data.read stopped using one: a misremembered
// metric name must come back as a tool result the model can fix, never as
// AI_InvalidToolArgumentsError — that kills the turn.
export const metricComparisonSchema = z.object({
  left: z.coerce.string().describe("A day-grain metric id"),
  right: z.coerce.string().describe("A day-grain metric id"),
  from: z.coerce.string(),
  to: z.coerce.string(),
  timezone: z.coerce.string().optional(),
});
export async function compareMetrics(
  ctx: Ctx,
  request: {
    left: string;
    right: string;
    from: string;
    to: string;
    timezone?: string;
  },
) {
  const unknown = [request.left, request.right].filter((m) => !(METRICS as readonly string[]).includes(m));
  if (unknown.length) {
    return {
      ok: false as const,
      error: "UNKNOWN_METRIC",
      say: `${unknown.map((m) => `"${m}"`).join(" and ")} ${unknown.length > 1 ? "are" : "is"} not a metric. Compare two of: ${METRICS.join(", ")}.`,
    };
  }
  const result = await queryMetrics(ctx, {
    metrics: [request.left as Metric, request.right as Metric],
    from: request.from,
    to: request.to,
    timezone: request.timezone,
  });
  if (!result.ok) return result;
  const [left, right] = result.data;
  const daily = (points: typeof left.points) =>
    new Map(
      points.filter((p) => p.value !== null).map((p) => [
        p.dayKey.length === 10
          ? p.dayKey
          : dayOf(p.dayKey, request.timezone ?? ctx.tz),
        p.value!,
      ]),
    );
  const a = daily(left.points), b = daily(right.points);
  const pairs = [...a].filter(([day]) => b.has(day)).sort(([x], [y]) =>
    x.localeCompare(y)
  ).map(([day, x]) => ({ day, left: x, right: b.get(day)! }));
  const n = pairs.length,
    mean = (xs: number[]) =>
      xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;
  const mx = mean(pairs.map((p) => p.left)),
    my = mean(pairs.map((p) => p.right));
  const xx = pairs.reduce((s, p) => s + (p.left - (mx ?? 0)) ** 2, 0),
    yy = pairs.reduce((s, p) => s + (p.right - (my ?? 0)) ** 2, 0);
  const cov = pairs.reduce(
    (s, p) => s + (p.left - (mx ?? 0)) * (p.right - (my ?? 0)),
    0,
  );
  const qualityOK = ![left, right].some((r) =>
    r.evidence.status === "stale" || r.evidence.status === "unsupported"
  );
  const reason = !qualityOK
    ? "unsettled_or_unsupported"
    : n < 7
    ? "insufficient_overlap"
    : xx === 0 || yy === 0
    ? "constant_series"
    : null;
  const pearsonR = reason === null
    ? Math.max(-1, Math.min(1, cov / Math.sqrt(xx * yy)))
    : null;
  const sameUnit = left.evidence.unit === right.evidence.unit;
  const differences = sameUnit
    ? pairs.map((p) => ({ day: p.day, value: p.left - p.right }))
    : [];
  const difference = sameUnit
    ? {
      mean: mean(differences.map((p) => p.value)),
      latest: differences.at(-1)?.value ?? null,
      points: differences,
    }
    : null;
  const prefix = `${left.evidence.id}:${right.evidence.id}`;
  const common = { from: request.from, to: request.to };
  return {
    ok: true as const,
    data: {
      readings: result.data,
      alignedDays: n,
      requestedDays:
        (Date.parse(request.to) - Date.parse(request.from)) / 864e5 + 1,
      alignment:
        "user_day; latest recorded observation per day; absent days excluded",
      pairs,
      association: {
        pearsonR,
        reason,
        minimumDays: 7,
        interpretation: "association_only_not_causation",
      },
      difference,
      evidence: {
        association: {
          ...common,
          id: prefix + ":r",
          metric: `correlation:${request.left}:${request.right}`,
          unit: "r",
        },
        difference: sameUnit
          ? {
            ...common,
            id: prefix + ":difference",
            metric: `difference:${request.left}:${request.right}`,
            unit: left.evidence.unit,
          }
          : null,
      },
    },
  };
}
