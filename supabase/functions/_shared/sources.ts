import { readSnapshot, acceptSnapshot } from "./metric-snapshot.ts";
// 07 · 09 · the data behind every chart, fetched by the server rather than copied by the model.
//
// A chart tool names a source; the source reads this user's rows through the turn's own JWT
// (RLS applies), buckets them to the width of a 314-pt panel, and hands back the exact shape
// the renderer eats. The model never transcribes a series — it chooses one. What it may say
// about it is the `agg` block, which the render tool harvests into the number ledger.
//
// null means "no data": the panel writes —— and the model picks another chart. Never 0.

import type { ReadContext } from "./read-context.ts";
import { addDays, dayBounds, dayOf, hhmm, weekday, zoned } from "./calendar.ts";
import { queryMetrics, type Metric } from "./metric-query.ts";
export { addDays, dayBounds, dayOf, weekday, zoned } from "./calendar.ts";
import { readSampleHistory } from "./archive.ts";
import { SEED_MEAL_VERSION } from "./db.ts";

export type Point = [string, number];

export type ChartData =
  /// `mark` is a horizontal threshold (a zone floor); `marks` are x indices worth naming
  /// (the minute a meal started, the minute the curve came back to baseline). Both are
  /// optional and only the two 2026-09-06 curves send them.
  | { kind: "curve"; series: Point[]; split?: number; mark?: number; marks?: number[] }
  | { kind: "pair"; hi: Point[]; lo: Point[]; a?: string; b?: string }
  | { kind: "column"; bins: Point[]; unit?: string; total?: number }
  | { kind: "arc"; value: number; goal: number; unit: string }
  | { kind: "gauge"; value: number; zones: [number, number, string][] }
  | { kind: "stack"; parts: Point[] }
  | { kind: "grid"; rows: number; cols: number; cells: number[][]; scale: number; rowLabels?: string[]; colLabels?: string[] }
  | { kind: "strip"; minutes?: number[]; current_zone?: number; lanes?: [number, number][]; from?: string; to?: string }
  | { kind: "rows"; rows: { label: string; value: string; spark?: number[] }[] }
  /// One total plus the sub-scores that make it, each against its own full value. Not a
  /// stack: the parts are independent readings, they do not add up to the total.
  | { kind: "meter"; value: number; max: number; parts: { label: string; value: number; max: number }[] }
  /// A beat-to-beat cloud: (this interval, the next) in milliseconds, the box to draw it in,
  /// and the readings that go beside it — the cloud alone is a shape, not a reading.
  | { kind: "scatter"; points: [number, number][]; lo: number; hi: number; stats: { label: string; value: string }[] }
  /// A closed verdict: which one of `options` it landed on, and how much evidence backs it.
  | { kind: "verdict"; word: string; options: string[]; confidence: number; steps: number }
  /// One sample per beat, drawn as a trace. `hz` is what the renderer times the sweep by.
  | { kind: "trace"; samples: number[]; hz: number };

export type Kind = ChartData["kind"];

export interface SourceResult {
  evidence?: Record<string, unknown>;
  data: ChartData;
  /// The numbers the model may say out loud about this chart. Harvested into the ledger.
  agg: Record<string, number | null>;
  /// What the panel prints as the big number when the model does not name one.
  hero?: string;
  unit?: string;
  /// The window in words — "TODAY", "7 DAYS", "12 WEEKS" — for a footer or a tag line.
  window: string;
}

export interface Ctx extends ReadContext {
  cache?: Map<string, Promise<SourceResult | null>>;
}

export interface Source {
  id: string;
  kind: Kind;
  /// One line for the tool's enum description: what the chart will show.
  says: string;
  fetch(ctx: Ctx): Promise<SourceResult | null>;
}

// ---------------------------------------------------------------- calendar helpers

function mmdd(dayKey: string): string { return dayKey.slice(5); }

const r1 = (x: number) => Math.round(x * 10) / 10;
const mean = (xs: number[]) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;

function stats(values: number[]): Record<string, number | null> {
  const vals = values.filter((v) => Number.isFinite(v));
  if (!vals.length) return { latest: null, mean: null, min: null, max: null, count: 0 };
  const m = mean(vals)!;
  return {
    latest: vals[vals.length - 1], mean: r1(m), mean0: Math.round(m),
    min: Math.min(...vals), max: Math.max(...vals), count: vals.length,
  };
}

// ---------------------------------------------------------------- rows

interface RawRow { ts: string; heart: number | null; stress: number | null; step: number | null }

/// ⚠️ PostgREST answers at most 1,000 rows per request whatever the range says; a week of
/// five-minute ticks is 2,016. Page until a short page comes back.
async function pageAll<T>(q: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>): Promise<T[] | null> {
  const out: T[] = [];
  for (let from = 0; from < 20_000; from += 1000) {
    const { data, error } = await q(from, from + 999);
    if (error) throw new Error("SOURCE_QUERY_FAILED");
    out.push(...(data ?? []));
    if ((data?.length ?? 0) < 1000) return out;
  }
  throw new Error("SOURCE_RANGE_TOO_DENSE");
}

async function rawSamples(ctx: Ctx, fromDay: string, toDay: string): Promise<RawRow[] | null> {
  const lo = dayBounds(fromDay, ctx.tz).start.toISOString();
  const hi = dayBounds(toDay, ctx.tz).end.toISOString();
  return await readSampleHistory(ctx.db, ctx.userId, lo, hi) as unknown as RawRow[];
}

interface DayRow {
  user_day: string; training_load: number | null; reserve_score: number | null; fuel_balance_kcal: number | null;
  day_fuel: unknown; daily_training: unknown; reserve_daily: unknown;
}

// deno-lint-ignore no-explicit-any
const one = (x: unknown): any => (Array.isArray(x) ? x[0] : x) ?? null;

async function dayRows(ctx: Ctx, fromDay: string, toDay: string): Promise<DayRow[] | null> {
  const { data, error } = await ctx.db.from("daily_results")
    .select("user_day, training_load, reserve_score, fuel_balance_kcal, " +
      "day_fuel(kcal_in, kcal_out, target_in, protein_g, carb_g, fat_g, protein_in_g, carb_in_g, fat_in_g), " +
      "daily_training(zone_minutes, peak_hr, segments, session_count), " +
      "reserve_daily(current_value, wake_value, min_value, night_inputs)")
    .eq("user_id", ctx.userId).gte("user_day", fromDay).lte("user_day", toDay).order("user_day");
  if (error) throw new Error("SOURCE_QUERY_FAILED");
  return (data ?? []) as unknown as DayRow[];
}

/// Every day of the window, present or not — a missing day is a null point, never a 0.
function window(ctx: Ctx, days: number): string[] {
  const end = ctx.to ?? ctx.dayKey;
  const start = ctx.from ?? addDays(end, 1-days);
  const count = Math.floor((Date.parse(end)-Date.parse(start))/864e5)+1;
  if (!Number.isFinite(count) || count < 1 || count > 366) throw new Error("INVALID_RANGE");
  return Array.from({ length: count }, (_, i) => addDays(start, i));
}

// ---------------------------------------------------------------- intraday buckets

function bucketIntraday(rows: RawRow[], ctx: Ctx, col: "heart" | "stress" | "step", minutes: number, how: "mean" | "sum") {
  const { start } = dayBounds(ctx.dayKey, ctx.tz);
  const n = Math.ceil(24 * 60 / minutes);
  const acc: number[][] = Array.from({ length: n }, () => []);
  for (const r of rows) {
    const v = r[col];
    if (v == null || (col !== "step" && v <= 0)) continue;
    const i = Math.floor((Date.parse(r.ts) - start.getTime()) / (minutes * 60_000));
    if (i >= 0 && i < n) acc[i].push(v);
  }
  const labelOf = (i: number) => hhmm(new Date(start.getTime() + i * minutes * 60_000).toISOString(), ctx.tz);
  const points: Point[] = [];
  let lastFilled = -1;
  acc.forEach((xs, i) => { if (xs.length) lastFilled = i; });
  for (let i = 0; i <= lastFilled; i++) {
    const xs = acc[i];
    if (!xs.length) continue;
    points.push([labelOf(i), how === "sum" ? xs.reduce((a, b) => a + b, 0) : Math.round(mean(xs)!)]);
  }
  return points;
}

function intraday(col: "heart" | "stress", unit: string): Source["fetch"] {
  return async (ctx) => {
    const rows = await rawSamples(ctx, ctx.dayKey, ctx.dayKey);
    if (!rows) return null;
    const series = bucketIntraday(rows, ctx, col, 30, "mean");
    if (series.length < 2) return null;
    const raw = rows.map((r) => r[col]).filter((v): v is number => v != null && v > 0);
    const s = stats(raw);
    const peak = rows.reduce<RawRow | null>((best, r) => (r[col] != null && r[col]! > (best?.[col] ?? -1) ? r : best), null);
    return {
      data: { kind: "curve", series },
      agg: { ...s, points: series.length },
      hero: `${s.latest} ${unit}`.trim(), unit, window: "TODAY",
      ...(peak ? { peakAt: hhmm(peak.ts, ctx.tz) } : {}),
    } as SourceResult;
  };
}

// ---------------------------------------------------------------- the catalogue

export const SOURCES: Source[] = [
  {
    id: "heart.today", kind: "curve", says: "今天的心率曲线，30 分钟一点（bpm）",
    fetch: intraday("heart", "bpm"),
  },
  {
    id: "stress.today", kind: "curve", says: "今天的压力曲线，30 分钟一点（0–100）",
    fetch: intraday("stress", ""),
  },
  {
    id: "bodyBattery.today", kind: "curve", says: "今天的 BODY BATTERY 曲线：夜里充、白天放（0–100）",
    async fetch(ctx) {
      const { start, end } = dayBounds(ctx.dayKey, ctx.tz);
      const { data, error } = await ctx.db.from("reserve_samples").select("ts, value")
        .eq("user_id", ctx.userId).gte("ts", start.toISOString()).lt("ts", end.toISOString())
        .order("ts").limit(1000);
      if (error) throw new Error("SOURCE_QUERY_FAILED");
      const rows = (data ?? []) as { ts: string; value: number }[];
      if (rows.length < 2) return null;
      const series = bucketIntraday(rows.map((r) => ({ ts: r.ts, heart: r.value, stress: null, step: null })), ctx, "heart", 30, "mean");
      if (series.length < 2) return null;
      // 13 col 01 · the night in violet, the day so far in lime: the split is the wake peak,
      // the highest point in the first part of the day.
      const head = series.slice(0, Math.max(2, Math.ceil(series.length * 0.45)));
      let split = 0;
      head.forEach((p, i) => { if (p[1] >= head[split][1]) split = i; });
      const vals = rows.map((r) => r.value);
      const s = stats(vals);
      return {
        data: { kind: "curve", series, split },
        agg: { ...s, wake: series[split][1], points: series.length },
        hero: `${s.latest}`, unit: "%", window: "TODAY",
      };
    },
  },
  {
    id: "steps.today", kind: "column", says: "今天的步数，两小时一柱",
    async fetch(ctx) {
      const rows = await rawSamples(ctx, ctx.dayKey, ctx.dayKey);
      if (!rows) return null;
      const bins = bucketIntraday(rows, ctx, "step", 120, "sum");
      const total = bins.reduce((a, b) => a + b[1], 0);
      if (!bins.length || total <= 0) return null;
      const peak = bins.reduce((best, b) => (b[1] > best[1] ? b : best), bins[0]);
      return {
        data: { kind: "column", bins, unit: "steps", total },
        agg: { total, peak: peak[1], bins: bins.length },
        hero: `${total} steps`, unit: "steps", window: "TODAY",
      };
    },
  },
  {
    id: "steps.7d", kind: "column", says: "最近 7 天每天的步数",
    async fetch(ctx) {
      const days = window(ctx, 7);
      const rows = await rawSamples(ctx, days[0], ctx.dayKey);
      if (!rows) return null;
      const sums = new Map<string, number>();
      for (const r of rows) if (r.step != null && r.step >= 0) sums.set(dayOf(r.ts, ctx.tz), (sums.get(dayOf(r.ts, ctx.tz)) ?? 0) + r.step);
      if (!sums.size) return null;
      const bins: Point[] = days.filter(d=>sums.has(d)).map((d) => [weekday(d), sums.get(d)!]);
      const vals = days.map((d) => sums.get(d)).filter((v): v is number => v != null);
      const s = stats(vals);
      return {
        data: { kind: "column", bins, unit: "steps", total: vals.reduce((a, b) => a + b, 0) },
        agg: { ...s, today: sums.get(ctx.dayKey) ?? null, days: vals.length, windowDays: days.length, total: vals.reduce((a, b) => a + b, 0) },
        evidence:{missingDays:days.filter(d=>!sums.has(d)),status:sums.size<days.length?"partial":"complete"},
        hero: `${s.mean0} avg`, unit: "steps", window: "7 DAYS",
      };
    },
  },
  ...dailySeries("trainingLoad", "TRAINING LOAD", "", [7, 30]),
  ...dailySeries("bodyBattery", "BODY BATTERY", "%", [7, 30]),
  ...dailySeries("intakeKcal", "EATEN", "kcal", [7, 30]),
  {
    id: "deltaKcal.7d", kind: "column", says: "最近 7 天每天吃进减消耗（kcal，有正有负）",
    async fetch(ctx) {
      const { reading, days } = await readMetricWindow(ctx, "deltaKcal", 7);
      const present = observedPoints(reading);
      if (present.length < 2) return null;
      const bins: Point[] = present.map((p) => [weekday(p.dayKey), p.value]);
      const vals = bins.map((b) => b[1]);
      const net = vals.reduce((a, b) => a + b, 0);
      return {
        data: { kind: "column", bins, unit: "kcal", total: net },
        agg: { ...reading.stats, net, up: vals.filter((v) => v > 0).length, down: vals.filter((v) => v < 0).length, windowDays: days.length },
        evidence: reading.evidence,
        hero: `${net > 0 ? "+" : ""}${net} kcal`, unit: "kcal", window: `${days.length} DAYS`,
      };
    },
  },
  ...[30, 90].map<Source>((n) => ({
    id: `weight.${n}d`, kind: "curve", says: `最近 ${n} 天的体重（kg）`,
    async fetch(ctx) {
      const { reading, days } = await readMetricWindow(ctx, "weight", n);
      const present = observedPoints(reading);
      if (present.length < 2) return null;
      const series: Point[] = present.map((p) => [mmdd(dayOf(p.dayKey, ctx.tz)), p.value]);
      return {
        data: { kind: "curve", series },
        agg: { ...reading.stats, first: present[0].value, change: reading.stats.firstToLastObservedChange, days: days.length },
        evidence: reading.evidence,
        hero: reading.stats.latest == null ? "——" : `${reading.stats.latest} kg`, unit: "kg", window: `${days.length} DAYS`,
      };
    },
  })),
  {
    id: "heart.range.7d", kind: "pair", says: "最近 7 天每天心率的最高与最低两条线",
    async fetch(ctx) {
      const days = window(ctx, 7);
      const rows = await rawSamples(ctx, days[0], ctx.dayKey);
      if (!rows) return null;
      const by = new Map<string, number[]>();
      for (const r of rows) if (r.heart && r.heart > 0) (by.get(dayOf(r.ts, ctx.tz)) ?? by.set(dayOf(r.ts, ctx.tz), []).get(dayOf(r.ts, ctx.tz))!).push(r.heart);
      const present = days.filter((d) => by.has(d));
      if (present.length < 2) return null;
      const hi: Point[] = present.map((d) => [weekday(d), Math.max(...by.get(d)!)]);
      const lo: Point[] = present.map((d) => [weekday(d), Math.min(...by.get(d)!)]);
      return {
        data: { kind: "pair", hi, lo, a: "MAX", b: "MIN" },
        agg: { hiLatest: hi[hi.length - 1][1], loLatest: lo[lo.length - 1][1], hiMax: Math.max(...hi.map((p) => p[1])), loMin: Math.min(...lo.map((p) => p[1])), days: present.length, windowDays: 7 },
        hero: `${lo[lo.length - 1][1]}–${hi[hi.length - 1][1]}`, unit: "bpm", window: "7 DAYS",
      };
    },
  },
  ...(["heart", "step"] as const).map<Source>((col) => ({
    id: col === "heart" ? "heart.heat.7d" : "steps.heat.7d", kind: "grid",
    says: col === "heart" ? "最近 7 天 × 每两小时的心率热力图" : "最近 7 天 × 每两小时的步数热力图",
    async fetch(ctx) {
      const days = window(ctx, 7);
      const rows = await rawSamples(ctx, days[0], ctx.dayKey);
      if (!rows) return null;
      const acc: number[][][] = days.map(() => Array.from({ length: 12 }, () => []));
      for (const r of rows) {
        const v = r[col];
        if (v == null || v <= 0) continue;
        const d = dayOf(r.ts, ctx.tz);
        const di = days.indexOf(d);
        if (di < 0) continue;
        const ci = Math.floor((Date.parse(r.ts) - dayBounds(d, ctx.tz).start.getTime()) / 7_200_000);
        if (ci >= 0 && ci < 12) acc[di][ci].push(v);
      }
      const raw = acc.map((row) => row.map((xs) => xs.length ? (col === "step" ? xs.reduce((a, b) => a + b, 0) : mean(xs)!) : null));
      const flat = raw.flat().filter((v): v is number => v != null);
      if (flat.length < 4) return null;
      const lo = Math.min(...flat), hi = Math.max(...flat), span = Math.max(hi - lo, 1);
      const cells = raw.map((row) => row.map((v) => v == null ? 0 : 1 + Math.min(3, Math.floor((v - lo) / span * 4))));
      let best = { d: 0, c: 0, v: -1 };
      raw.forEach((row, d) => row.forEach((v, c) => { if (v != null && v > best.v) best = { d, c, v }; }));
      const hour = (c: number) => hhmm(new Date(dayBounds(days[best.d], ctx.tz).start.getTime() + c * 7_200_000).toISOString(), ctx.tz);
      return {
        data: { kind: "grid", rows: 7, cols: 12, cells, scale: 4, rowLabels: days.map(weekday), colLabels: Array.from({ length: 12 }, (_, c) => hour(c)) },
        agg: { peak: Math.round(best.v), min: Math.round(lo), max: Math.round(hi), days: 7 },
        hero: `${weekday(days[best.d])} ${hour(best.c)}–${hour(best.c + 1)}`, window: "7 DAYS",
      };
    },
  })),
  {
    id: "zones.today", kind: "strip", says: "今天五个心率区间各多少分钟",
    async fetch(ctx) {
      const rows = await dayRows(ctx, ctx.dayKey, ctx.dayKey);
      const t = one(rows?.[0]?.daily_training);
      const minutes: number[] = t?.zone_minutes ?? [];
      if (minutes.length !== 5 || minutes.every((m) => !m)) return null;
      const top = minutes.indexOf(Math.max(...minutes));
      return {
        data: { kind: "strip", minutes, current_zone: top + 1 },
        agg: { z1: minutes[0], z2: minutes[1], z3: minutes[2], z4: minutes[3], z5: minutes[4], total: minutes.reduce((a, b) => a + b, 0), elevated: minutes.slice(1).reduce((a, b) => a + b, 0), peakHr: t?.peak_hr ?? null },
        hero: `Z${top + 1} · ${minutes[top]} min`, window: "TODAY",
      };
    },
  },
  {
    id: "segments.today", kind: "rows", says: "今天训练负荷的构成：每一段抬高的心率贡献了多少",
    async fetch(ctx) {
      const rows = await dayRows(ctx, ctx.dayKey, ctx.dayKey);
      const day = rows?.[0];
      const segs: { name: string; minutes: number | null; avg_hr: number | null; delta: number | null; at: string; all_day: boolean }[] =
        one(day?.daily_training)?.segments ?? [];
      if (!day || !segs.length) return null;
      const items = segs.slice(0, 5).map((s) => ({
        label: s.all_day ? s.name : `${hhmm(s.at, ctx.tz)} ${s.name}`,
        value: s.delta == null ? "——" : `+${s.delta}`,
      }));
      const agg: Record<string, number | null> = { load: day.training_load, sessions: segs.filter((s) => !s.all_day).length };
      segs.forEach((s, i) => { agg[`seg${i}Delta`] = s.delta; agg[`seg${i}Minutes`] = s.minutes; agg[`seg${i}AvgHr`] = s.avg_hr; });
      return { data: { kind: "rows", rows: items }, agg, hero: `${day.training_load ?? "——"}`, window: "TODAY" };
    },
  },
  {
    id: "load.today", kind: "arc", says: "今天的 TRAINING LOAD，满值 21",
    async fetch(ctx) {
      const { reading } = await readMetricWindow(ctx, "trainingLoad", 1);
      const v = reading.stats.latest;
      if (v == null) return null;
      // F7 §08 · the remainder is a number the ring's own caption asks for («还差多少»),
      // so the server computes it. The model may not subtract: 21 − 2.6 came back as an
      // untraceable 18.4 and threw the whole frame away.
      return { data: { kind: "arc", value: v, goal: 21, unit: "" }, agg: { value: v, goal: 21, left: r1(21 - v), pct: Math.round(v / 21 * 100) }, evidence: reading.evidence, hero: `${v}`, window: reading.evidence.to === ctx.dayKey ? "TODAY" : reading.evidence.to };
    },
  },
  {
    id: "battery.now", kind: "arc", says: "此刻的 BODY BATTERY，0–100",
    async fetch(ctx) {
      const rows = await dayRows(ctx, ctx.dayKey, ctx.dayKey);
      const rd = one(rows?.[0]?.reserve_daily);
      const v = rd?.current_value ?? rows?.[0]?.reserve_score ?? null;
      if (v == null) return null;
      return { data: { kind: "arc", value: v, goal: 100, unit: "%" }, agg: { value: v, goal: 100, left: r1(100 - v), wake: rd?.wake_value ?? null, min: rd?.min_value ?? null, sinceWake: rd?.wake_value != null ? v - rd.wake_value : null }, hero: `${v}`, unit: "%", window: "NOW" };
    },
  },
  {
    id: "protein.today", kind: "arc", says: "今天吃进的蛋白质对目标（g）",
    async fetch(ctx) {
      const f = one((await dayRows(ctx, ctx.dayKey, ctx.dayKey))?.[0]?.day_fuel);
      if (f?.protein_in_g == null || !f?.protein_g) return null;
      return { data: { kind: "arc", value: f.protein_in_g, goal: f.protein_g, unit: "g" }, agg: { eaten: f.protein_in_g, target: f.protein_g, left: Math.max(0, f.protein_g - f.protein_in_g), pct: Math.round(f.protein_in_g / f.protein_g * 100) }, hero: `${f.protein_in_g}g`, unit: "g", window: "TODAY" };
    },
  },
  {
    id: "kcal.today", kind: "arc", says: "今天吃进的热量对目标（kcal）",
    async fetch(ctx) {
      const f = one((await dayRows(ctx, ctx.dayKey, ctx.dayKey))?.[0]?.day_fuel);
      if (f?.kcal_in == null || !f?.target_in) return null;
      return { data: { kind: "arc", value: f.kcal_in, goal: f.target_in, unit: "" }, agg: { eaten: f.kcal_in, target: f.target_in, left: f.target_in - f.kcal_in, pct: Math.round(f.kcal_in / f.target_in * 100) }, hero: `${f.kcal_in}`, unit: "kcal", window: "TODAY" };
    },
  },
  {
    id: "stress.now", kind: "gauge", says: "最近一次压力读数，分区 REST / MID / HIGH",
    async fetch(ctx) {
      const { start, end } = dayBounds(ctx.dayKey, ctx.tz);
      const { data, error } = await ctx.db.from("raw_samples").select("ts, stress")
        .eq("user_id", ctx.userId).gte("ts", start.toISOString()).lt("ts", end.toISOString())
        .gt("stress", 0).order("ts", { ascending: false }).limit(1).maybeSingle();
      if (error) throw new Error("SOURCE_QUERY_FAILED");
      if (!data) return null;
      const v = data.stress as number;
      const zone = v < 40 ? "REST" : v < 70 ? "MID" : "HIGH";
      return { data: { kind: "gauge", value: v, zones: [[0, 40, "REST"], [40, 70, "MID"], [70, 100, "HIGH"]] }, agg: { value: v }, hero: `${v} · ${zone}`, window: hhmm(data.ts, ctx.tz) };
    },
  },
  {
    id: "meals.today", kind: "rows", says: "今天记了哪几餐，各多少 kcal",
    async fetch(ctx) {
      const { data, error } = await ctx.db.from("meals").select("slot, logged_at, text_input, kcal, protein_g")
        .eq("user_id", ctx.userId).eq("user_day", ctx.dayKey).is("deleted_at", null)
        .neq("model_version", SEED_MEAL_VERSION).order("logged_at");
      if (error) throw new Error("SOURCE_QUERY_FAILED");
      if (!data?.length) return null;
      const rows = data.slice(0, 5).map((m) => ({ label: `${m.slot} · ${m.text_input ?? ""}`.slice(0, 28), value: m.kcal == null ? "——" : `${m.kcal}` }));
      const total = data.reduce((a, m) => a + (m.kcal ?? 0), 0);
      const agg: Record<string, number | null> = { total, meals: data.length, protein: data.reduce((a, m) => a + (m.protein_g ?? 0), 0) };
      data.forEach((m) => { agg[m.slot.toLowerCase()] = m.kcal; });
      return { data: { kind: "rows", rows }, agg, hero: `${total} kcal`, unit: "kcal", window: "TODAY" };
    },
  },
  {
    id: "mealsBySlot.today", kind: "column", says: "今天每一餐的 kcal 柱（没记的餐不画）",
    async fetch(ctx) {
      const { data, error } = await ctx.db.from("meals").select("slot, kcal")
        .eq("user_id", ctx.userId).eq("user_day", ctx.dayKey).is("deleted_at", null)
        .neq("model_version", SEED_MEAL_VERSION);
      if (error) throw new Error("SOURCE_QUERY_FAILED");
      if (!data?.length) return null;
      const order = ["BREAKFAST", "LUNCH", "DINNER", "SNACK"];
      const by = new Map<string, number>();
      for (const m of data) if (m.kcal != null) by.set(m.slot, (by.get(m.slot) ?? 0) + m.kcal);
      const bins: Point[] = order.filter((s) => by.has(s)).map((s) => [s.slice(0, 5), by.get(s)!]);
      if (!bins.length) return null;
      const total = bins.reduce((a, b) => a + b[1], 0);
      const agg: Record<string, number | null> = { total, meals: bins.length };
      bins.forEach((b) => { agg[b[0].toLowerCase()] = b[1]; });
      return { data: { kind: "column", bins, unit: "kcal", total }, agg, hero: `${total} kcal`, unit: "kcal", window: "TODAY" };
    },
  },
  {
    id: "macros.today", kind: "stack", says: "今天三大营养素吃进对目标（g），hero 是缺口最大的那个",
    async fetch(ctx) {
      const f = one((await dayRows(ctx, ctx.dayKey, ctx.dayKey))?.[0]?.day_fuel);
      if (!f || f.protein_in_g == null) return null;
      const parts: Point[] = [["PRO", f.protein_in_g ?? 0], ["CARB", f.carb_in_g ?? 0], ["FAT", f.fat_in_g ?? 0]];
      const gaps = [["PRO", (f.protein_g ?? 0) - (f.protein_in_g ?? 0)], ["CARB", (f.carb_g ?? 0) - (f.carb_in_g ?? 0)], ["FAT", (f.fat_g ?? 0) - (f.fat_in_g ?? 0)]] as Point[];
      const gap = gaps.reduce((b, g) => (g[1] > b[1] ? g : b), gaps[0]);
      return {
        data: { kind: "stack", parts },
        agg: {
          proteinIn: f.protein_in_g, proteinTarget: f.protein_g, proteinLeft: Math.max(0, gaps[0][1]), proteinPct: f.protein_g ? Math.round((f.protein_in_g ?? 0) / f.protein_g * 100) : null,
          carbIn: f.carb_in_g, carbTarget: f.carb_g, carbLeft: Math.max(0, gaps[1][1]), carbPct: f.carb_g ? Math.round((f.carb_in_g ?? 0) / f.carb_g * 100) : null,
          fatIn: f.fat_in_g, fatTarget: f.fat_g, fatLeft: Math.max(0, gaps[2][1]), fatPct: f.fat_g ? Math.round((f.fat_in_g ?? 0) / f.fat_g * 100) : null,
          gap: Math.max(0, gap[1]),
        },
        hero: gap[1] > 0 ? `${gap[1]} G ${gap[0]} SHORT` : "ALL THREE MET", unit: "g", window: "TODAY",
      };
    },
  },
  {
    id: "balance.today", kind: "stack", says: "今天吃进 vs 消耗（kcal）；没记录的一天返回空，不当 0",
    async fetch(ctx) {
      const f = one((await dayRows(ctx, ctx.dayKey, ctx.dayKey))?.[0]?.day_fuel);
      if (!f || f.kcal_in == null || f.kcal_out == null) return null;
      const net = f.kcal_in - f.kcal_out;
      return { data: { kind: "stack", parts: [["IN", f.kcal_in], ["OUT", f.kcal_out]] }, agg: { in: f.kcal_in, out: f.kcal_out, net, target: f.target_in ?? null, left: f.target_in != null ? f.target_in - f.kcal_in : null }, hero: `${net > 0 ? "+" : ""}${net}`, unit: "kcal", window: "TODAY" };
    },
  },
  {
    id: "weighins.7d", kind: "grid", says: "最近 7 天哪几天称了体重",
    async fetch(ctx) {
      const { reading, days } = await readMetricWindow(ctx, "weight", 7);
      const have = new Set(observedPoints(reading).map((p) => dayOf(p.dayKey, ctx.tz)));
      const cells: number[][] = [days.map((d) => (have.has(d) ? 1 : 0))];
      const filled = cells[0].reduce((a, b) => a + b, 0);
      if (!filled) return null;
      return { data: { kind: "grid", rows: 1, cols: days.length, cells, scale: 1, colLabels: days.map(weekday) }, agg: { filled, total: days.length }, evidence: reading.evidence, hero: `${filled} OF ${days.length}`, window: `${days.length} DAYS` };
    },
  },
  {
    id: "mealsLogged.7d", kind: "grid", says: "最近 7 天哪几天记了餐",
    async fetch(ctx) {
      const days = window(ctx, 7);
      const { data, error } = await ctx.db.from("meals").select("user_day")
        .eq("user_id", ctx.userId).is("deleted_at", null).neq("model_version", SEED_MEAL_VERSION)
        .gte("user_day", days[0]).lte("user_day", ctx.dayKey);
      if (error) throw new Error("SOURCE_QUERY_FAILED");
      const have = new Set((data ?? []).map((m) => m.user_day));
      const cells: number[][] = [days.map((d) => (have.has(d) ? 1 : 0))];
      const filled = cells[0].reduce((a, b) => a + b, 0);
      if (!filled) return null;
      return { data: { kind: "grid", rows: 1, cols: 7, cells, scale: 1, colLabels: days.map(weekday) }, agg: { filled, total: 7 }, hero: `${filled} OF 7`, window: "7 DAYS" };
    },
  },
  {
    id: "vitals.7d", kind: "rows", says: "心率、压力、步数三行，每行带最近 7 天的小折线",
    async fetch(ctx) {
      const days = window(ctx, 7);
      const rows = await rawSamples(ctx, days[0], ctx.dayKey);
      if (!rows?.length) return null;
      const by = new Map<string, RawRow[]>();
      for (const r of rows) { const d = dayOf(r.ts, ctx.tz); (by.get(d) ?? by.set(d, []).get(d)!).push(r); }
      const daily = (col: "heart" | "stress" | "step", how: "mean" | "sum") => days.map((d) => {
        const xs = (by.get(d) ?? []).map((r) => r[col]).filter((v): v is number => v != null && (how === "sum" || v > 0));
        return xs.length ? (how === "sum" ? xs.reduce((a, b) => a + b, 0) : Math.round(mean(xs)!)) : null;
      });
      const hr = daily("heart", "mean"), st = daily("stress", "mean"), sp = daily("step", "sum");
      const last = (xs: (number | null)[]) => [...xs].reverse().find((v) => v != null) ?? null;
      const spark = (xs: (number | null)[]) => xs.filter((v): v is number => v != null);
      const items = [
        { label: "HR", value: last(hr) == null ? "——" : `${last(hr)} bpm`, spark: spark(hr) },
        { label: "STRESS", value: last(st) == null ? "——" : `${last(st)}`, spark: spark(st) },
        { label: "STEPS", value: last(sp) == null ? "——" : `${last(sp)}`, spark: spark(sp) },
      ].filter((r) => r.spark.length >= 2);
      if (!items.length) return null;
      return { data: { kind: "rows", rows: items }, agg: { hr: last(hr), stress: last(st), steps: last(sp), hrMean: mean(spark(hr)) == null ? null : Math.round(mean(spark(hr))!), stepsMean: mean(spark(sp)) == null ? null : Math.round(mean(spark(sp))!), days: 7 }, window: "7 DAYS" };
    },
  },
  ...composition(),
  {
    id: "sleep.mix", kind: "stack", says: "上一夜的深睡 / 浅睡 / 清醒各多少分钟",
    async fetch(ctx) {
      const { data, error } = await ctx.db.from("sleep_nights")
        .select("user_day, total_minutes, deep_minutes, light_minutes, wake_count, sleep_line")
        .eq("user_id", ctx.userId).eq("user_day", ctx.dayKey)
        .order("user_day", { ascending: false }).limit(1).maybeSingle();
      if (error) throw new Error("SOURCE_QUERY_FAILED");
      if (!data?.total_minutes) return null;
      const deep = data.deep_minutes, light = data.light_minutes;
      if (deep == null || light == null) return null;
      const runs = data.sleep_line ? String(data.sleep_line).split(",").map(run=>run.split(":").map(Number)) : [];
      const validRuns = runs.length > 0 && runs.every(([stage,minutes])=>Number.isInteger(stage)&&stage>=0&&stage<=4&&Number.isFinite(minutes)&&minutes>0);
      const awake = validRuns ? runs.filter(([stage])=>stage===3||stage===4).reduce((n,run)=>n+run[1],0) : null;
      const rem = validRuns ? runs.filter(([stage])=>stage===2).reduce((n,run)=>n+run[1],0) : null;
      const parts: Point[] = [["DEEP", deep], ["LIGHT", light], ...(rem===null?[]:[["REM",rem] as Point]), ...(awake===null?[]:[["AWAKE",awake] as Point])];
      const h = Math.floor(data.total_minutes / 60), m = data.total_minutes % 60;
      return {
        data: { kind: "stack", parts },
        agg: {
          total: data.total_minutes, hours: h, minutes: m, deep, light, awake, rem,
          wakes: data.wake_count ?? 0,
          deepPct: Math.round(deep / data.total_minutes * 100),
          lightPct: Math.round(light / data.total_minutes * 100),
        },
        hero: `${h}H${String(m).padStart(2, "0")}`, unit: "min", window: ctx.dayKey,
      };
    },
  },
  {
    id: "sleep.stages", kind: "strip", says: "上一夜的睡眠分期，按分钟画成清醒 / 浅睡 / 深睡三条泳道",
    async fetch(ctx) {
      const { data: night, error } = await ctx.db.from("sleep_nights")
        .select("user_day,sleep_line,sleep_start,wake_at")
        .eq("user_id",ctx.userId).eq("user_day",ctx.dayKey).maybeSingle();
      if (error) throw new Error("SOURCE_QUERY_FAILED");
      if (!night?.sleep_line || !night.sleep_start || !night.wake_at) return null;
      const runs = String(night.sleep_line).split(",").map(run => run.split(":").map(Number));
      if (runs.some(([stage,minutes]) => !Number.isInteger(stage)||stage<0||stage>4||!Number.isFinite(minutes)||minutes<=0)) return null;
      // SDK 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake. Preserve REM explicitly.
      const lanes: [number,number][] = runs.map(([stage,minutes]) => [stage===0?2:stage===1?1:stage===2?3:0,minutes]);
      const total = runs.reduce((sum,run)=>sum+run[1],0);
      const sum = (level:number) => lanes.filter(run=>run[0]===level).reduce((n,run)=>n+run[1],0);
      return {data:{kind:"strip",lanes,from:hhmm(night.sleep_start,ctx.tz),to:hhmm(night.wake_at,ctx.tz)},
        agg:{total,deep:sum(2),light:sum(1),rem:sum(3),awake:sum(0)},unit:"min",window:ctx.dayKey,
        evidence:{metric:"sleepStages",dayKey:ctx.dayKey,source:"sleep_nights.sleep_line",timezone:ctx.tz}};

    },
  },
  {
    id: "o2.night", kind: "curve", says: "上一夜睡眠窗口内的自动血氧曲线（均值与最低，不是呼吸暂停分级）",
    async fetch(ctx) {
      const { data: night, error: nightError } = await ctx.db.from("sleep_nights")
        .select("sleep_start,wake_at")
        .eq("user_id", ctx.userId).eq("user_day", ctx.dayKey).maybeSingle();
      if (nightError) throw new Error("SOURCE_QUERY_FAILED");
      const lo = (night?.sleep_start as string | undefined)
        ?? zoned(addDays(ctx.dayKey, -1), 18, ctx.tz).toISOString();
      const hi = (night?.wake_at as string | undefined)
        ?? zoned(ctx.dayKey, 12, ctx.tz).toISOString();
      const { data, error } = await ctx.db.from("oxygen_samples").select("ts, spo2")
        .eq("user_id", ctx.userId).gte("ts", lo).lt("ts", hi).order("ts").limit(400);
      if (error) throw new Error("SOURCE_QUERY_FAILED");
      if (!data || data.length < 6) return null;
      const rows = data as { ts: string; spo2: number }[];
      const series: Point[] = rows.map((r) => [hhmm(r.ts, ctx.tz), r.spo2]);
      const vals = rows.map((r) => r.spo2);
      const st = stats(vals);
      return {
        data: { kind: "curve", series },
        agg: { ...st },
        hero: `${st.mean0}%`, unit: "%", window: "LAST NIGHT",
      };
    },
  },
  {
    id: "hrv.7d", kind: "curve", says: "最近 7 天每天的 HRV（ms）",
    async fetch(ctx) {
      const days = window(ctx, 7);
      const rows = await dayRows(ctx,days[0],days.at(-1)!);
      if (!rows) return null;
      const by = new Map<string,number[]>();
      for(const row of rows){const inputs=one(one(row.reserve_daily)?.night_inputs);if(typeof inputs?.hrv==="number")by.set(row.user_day,[inputs.hrv]);}
      const present = days.filter((d) => by.has(d));
      if (!present.length) return null;
      const series: Point[] = present.map((d) => [weekday(d), Math.round(mean(by.get(d)!)!)]);
      const st = stats(series.map((p) => p[1]));
      return {
        data: { kind: "curve", series },
        agg: { ...st, days: present.length, windowDays: 7, readings: rows.length },
        hero: `${st.latest} ms`, unit: "ms", window: "7 DAYS",
      };
    },
  },
  {
    id: "events.today", kind: "rows", says: "今天按时间发生了什么：餐、抬高心率的时段、称重、体成分",
    async fetch(ctx) {
      const { start, end } = dayBounds(ctx.dayKey, ctx.tz);
      const lo = start.toISOString(), hi = end.toISOString();
      const [meals, days, weighs, comps] = await Promise.all([
        ctx.db.from("meals").select("slot, logged_at, kcal").eq("user_id", ctx.userId).eq("user_day", ctx.dayKey).is("deleted_at", null).neq("model_version", SEED_MEAL_VERSION),
        dayRows(ctx, ctx.dayKey, ctx.dayKey),
        ctx.db.from("weigh_ins").select("measured_at, weight_kg").eq("user_id", ctx.userId).gte("measured_at", lo).lt("measured_at", hi),
        ctx.db.from("body_composition").select("measured_at, body_fat_pct").eq("user_id", ctx.userId).gte("measured_at", lo).lt("measured_at", hi),
      ]);
      const ev: { t: string; label: string; value: string; n: number | null }[] = [];
      for (const m of meals.data ?? []) ev.push({ t: m.logged_at, label: m.slot, value: m.kcal == null ? "——" : `${m.kcal}`, n: m.kcal });
      for (const s of (one(days?.[0]?.daily_training)?.segments ?? []) as { name: string; at: string; delta: number | null; all_day: boolean }[]) {
        if (!s.all_day) ev.push({ t: s.at, label: s.name, value: s.delta == null ? "——" : `+${s.delta}`, n: s.delta });
      }
      for (const w of weighs.data ?? []) ev.push({ t: w.measured_at, label: "WEIGH-IN", value: `${Number(w.weight_kg)} kg`, n: Number(w.weight_kg) });
      for (const c of comps.data ?? []) ev.push({ t: c.measured_at, label: "BODY COMP", value: c.body_fat_pct == null ? "——" : `${Number(c.body_fat_pct)} %`, n: c.body_fat_pct == null ? null : Number(c.body_fat_pct) });
      if (!ev.length) return null;
      ev.sort((a, b) => Date.parse(a.t) - Date.parse(b.t));
      const rows = ev.slice(0, 6).map((e) => ({ label: `${hhmm(e.t, ctx.tz)} ${e.label}`, value: e.value }));
      // What a caption counts: how many meals, how many elevated blocks, how many readings.
      const agg: Record<string, number | null> = {
        count: ev.length,
        meals: (meals.data ?? []).length,
        mealsKcal: (meals.data ?? []).reduce((a, m) => a + (m.kcal ?? 0), 0),
        segments: ev.filter((e) => e.label.endsWith("HR") || e.label.endsWith("SESSION") || e.label.endsWith("BLOCK")).length,
        weighIns: (weighs.data ?? []).length, comps: (comps.data ?? []).length,
      };
      ev.forEach((e, i) => { agg[`e${i}`] = e.n; });
      return { data: { kind: "rows", rows }, agg, hero: `${ev.length}`, window: "TODAY" };
    },
  },
  ...gaps(),
];

/// The band writes one band_rr_evidence row per HRV sample — a handful of intervals each —
/// so a reading is a run of rows, not one. This gathers the newest run: every row inside
/// `minutes` of the latest one, oldest first, concatenated.
///
/// The filter is AutonomicBalance's own: 300 ms is 200 bpm and 2000 ms is 30 bpm, and one
/// dropped or doubled beat moves SD1 more than the wearer's state does. Twelve clean
/// intervals is the same floor the app refuses to draw under.
const RR_MIN_INTERVALS = 12;
async function recentIntervals(ctx: Ctx, minutes: number, notAfter?: string): Promise<{ beats: number[]; at: string } | null> {
  let q = ctx.db.from("band_rr_evidence").select("ts, rr_ms").eq("user_id", ctx.userId);
  if (notAfter) q = q.lte("ts", notAfter);
  const { data, error } = await q.order("ts", { ascending: false }).limit(60);
  if (error) throw new Error("SOURCE_QUERY_FAILED");
  const rows = (data ?? []) as { ts: string; rr_ms: number[] }[];
  if (!rows.length) return null;
  const newest = Date.parse(rows[0].ts);
  const run = rows.filter((r) => newest - Date.parse(r.ts) <= minutes * 60_000).reverse();
  const beats = run.flatMap((r) => (r.rr_ms ?? []).map(Number))
    .filter((v) => v >= 300 && v <= 2000);
  return beats.length >= RR_MIN_INTERVALS ? { beats, at: rows[0].ts } : null;
}

// ---------------------------------------------------------------- 2026-09-06 gap audit
//
// Six tables the database filled and no chart ever read, plus the tachogram that finally
// gives `wave` a source. Nothing here invents a number: each source returns null when the
// rows are not there, which is what makes the panel say —— instead of 0.
//
// ⚠️ Two things the audit got wrong on paper and the schema corrected:
//   · daily_training.curve is [[epoch, cumulative TRAINING LOAD], …] at five minutes —
//     the load accumulating through the day, not a session heart-rate trace.
//   · `ecg` is marked unsupported in metric-query.ts: the band does not produce it. The
//     trace `wave` wanted is band_rr_evidence.rr_ms, a real ordered interval series.
function gaps(): Source[] {
  return [
    {
      id: "sleep.score.night", kind: "meter",
      says: "上一夜的睡眠总分，以及时长 / 结构 / 恢复 / 规律四个子分（0–100）",
      async fetch(ctx) {
        const from = addDays(ctx.dayKey, -1);
        const { data, error } = await ctx.db.from("night_score")
          .select("user_day, score, duration_score, architecture_score, recovery_score, regularity_score")
          .eq("user_id", ctx.userId).gte("user_day", from).lte("user_day", ctx.dayKey)
          .order("user_day", { ascending: false }).limit(1);
        if (error) throw new Error("SOURCE_QUERY_FAILED");
        const row = (data ?? [])[0] as Record<string, number | string | null> | undefined;
        if (!row || row.score == null) return null;
        const named: [string, string][] = [
          ["DURATION", "duration_score"], ["ARCHITECTURE", "architecture_score"],
          ["RECOVERY", "recovery_score"], ["REGULARITY", "regularity_score"],
        ];
        // A sub-score that was not computed is absent, not zero: it is dropped.
        const parts = named
          .filter(([, k]) => row[k] != null)
          .map(([label, k]) => ({ label, value: Number(row[k]), max: 100 }));
        if (!parts.length) return null;
        const worst = parts.reduce((a, b) => (b.value < a.value ? b : a));
        const agg: Record<string, number | null> = { score: Number(row.score), parts: parts.length, worst: worst.value };
        for (const p of parts) agg[p.label.toLowerCase()] = p.value;
        return {
          data: { kind: "meter", value: Number(row.score), max: 100, parts },
          agg, hero: `${row.score}`, window: "LAST NIGHT",
        };
      },
    },
    {
      id: "balance.check.last", kind: "scatter",
      says: "上一次平衡测试的逐拍散点（Poincaré），带 SDNN、主导侧与静息占比",
      async fetch(ctx) {
        const { data, error } = await ctx.db.from("balance_checks")
          .select("measured_at, lead, rest_share, sd1_ms, sd2_ms, sdnn_ms, heart_rate, beat_count, algo_version")
          .eq("user_id", ctx.userId).order("measured_at", { ascending: false }).limit(1);
        if (error) throw new Error("SOURCE_QUERY_FAILED");
        const check = (data ?? [])[0] as Record<string, string | number | null> | undefined;
        if (!check) return null;
        // The cloud itself is the interval run; the summary row does not carry the beats.
        const run = await recentIntervals(ctx, 10, String(check.measured_at));
        if (!run) return null;
        const rr = run.beats;
        const points: [number, number][] = [];
        for (let i = 1; i < rr.length; i++) points.push([rr[i - 1], rr[i]]);
        if (points.length < RR_MIN_INTERVALS) return null;
        const flat = points.flat();
        const lo = Math.min(...flat), hi = Math.max(...flat);
        return {
          data: {
            kind: "scatter", points, lo: Math.floor(lo / 50) * 50, hi: Math.ceil(hi / 50) * 50,
            stats: [
              { label: "SDNN", value: `${Math.round(Number(check.sdnn_ms))} ms` },
              { label: "LEAD", value: String(check.lead).toUpperCase() },
              { label: "REST SHARE", value: `${Number(check.rest_share)} %` },
            ],
          },
          agg: {
            sdnn: Number(check.sdnn_ms), sd1: Number(check.sd1_ms), sd2: Number(check.sd2_ms),
            restShare: Number(check.rest_share), beats: Number(check.beat_count),
            heartRate: check.heart_rate == null ? null : Number(check.heart_rate),
            pairs: points.length,
          },
          hero: `${Math.round(Number(check.sdnn_ms))} ms`, unit: "ms",
          window: String(check.lead).toUpperCase(),
        };
      },
    },
    {
      id: "sync.status.7d", kind: "grid",
      says: "最近 7 天每个域的同步状态：完整 / 部分 / 失败 / 没采到 / 不支持",
      async fetch(ctx) {
        const days = window(ctx, 7);
        const { data, error } = await ctx.db.from("sync_domain_status")
          .select("user_day, domain, status")
          .eq("user_id", ctx.userId).gte("user_day", days[0]).lte("user_day", ctx.dayKey);
        if (error) throw new Error("SOURCE_QUERY_FAILED");
        const rows = (data ?? []) as { user_day: string; domain: string; status: string }[];
        if (!rows.length) return null;
        // 0 not_collected · 1 unsupported · 2 failed · 3 partial · 4 complete. The order is
        // the palette's order on the panel, worst to best; 0 is also the never-attempted cell.
        const CODE: Record<string, number> = { not_collected: 0, unsupported: 1, failed: 2, partial: 3, complete: 4 };
        const domains = [...new Set(rows.map((r) => r.domain))].sort();
        const state = new Map(rows.map((r) => [`${r.domain}|${r.user_day}`, CODE[r.status] ?? 0]));
        const cells = domains.map((d) => days.map((day) => state.get(`${d}|${day}`) ?? 0));
        const flat = cells.flat();
        return {
          data: {
            kind: "grid", rows: domains.length, cols: days.length, cells, scale: 4,
            rowLabels: domains.map((d) => d.toUpperCase()), colLabels: days.map(weekday),
          },
          agg: {
            complete: flat.filter((c) => c === 4).length, partial: flat.filter((c) => c === 3).length,
            failed: flat.filter((c) => c === 2).length, unsupported: flat.filter((c) => c === 1).length,
            missing: flat.filter((c) => c === 0).length,
            domains: domains.length, windowDays: days.length, cells: flat.length,
          },
          hero: `${flat.filter((c) => c !== 4).length}`, window: "7 DAYS",
        };
      },
    },
    {
      id: "composition.call", kind: "verdict",
      says: "体成分的判定（RECOMP / CUT / BULK / DRIFT / NO_CHANGE）与它的置信度",
      async fetch(ctx) {
        const from = addDays(ctx.dayKey, -14);
        const { data, error } = await ctx.db.from("daily_results")
          .select("user_day, the_call, the_call_confidence")
          .eq("user_id", ctx.userId).gte("user_day", from).lte("user_day", ctx.dayKey)
          .not("the_call", "is", null).order("user_day", { ascending: false }).limit(1);
        if (error) throw new Error("SOURCE_QUERY_FAILED");
        const row = (data ?? [])[0] as { user_day: string; the_call: string; the_call_confidence: string | null } | undefined;
        if (!row) return null;
        // What the verdict rests on: how many times she actually stood on the scale.
        const weighs = await ctx.db.from("weigh_ins").select("measured_at")
          .eq("user_id", ctx.userId)
          .gte("measured_at", zoned(from, 4, ctx.tz).toISOString())
          .lt("measured_at", dayBounds(ctx.dayKey, ctx.tz).end.toISOString());
        if (weighs.error) throw new Error("SOURCE_QUERY_FAILED");
        const STEPS: Record<string, number> = { PENDING: 1, MEDIUM: 2, HIGH: 3 };
        const confidence = STEPS[row.the_call_confidence ?? "PENDING"] ?? 1;
        return {
          data: {
            kind: "verdict", word: row.the_call,
            options: ["RECOMP", "CUT", "BULK", "DRIFT", "NO_CHANGE"],
            confidence, steps: 3,
          },
          agg: { confidence, weighIns: (weighs.data ?? []).length, windowDays: 14 },
          hero: row.the_call, window: "14 DAYS",
        };
      },
    },
    {
      id: "load.curve.today", kind: "curve",
      says: "今天训练负荷是怎么攒起来的：五分钟一点的累积曲线（0–21），标出 21 的满值线",
      async fetch(ctx) {
        // ⚠️ Not through dayRows: its nested select lists daily_training's small columns and
        // deliberately leaves `curve` out, so reading it from there is always undefined —
        // which is exactly how this source shipped returning NULL against real rows. The
        // jsonb is fetched here, for the one chart that wants it.
        const day = await ctx.db.from("daily_results").select("id")
          .eq("user_id", ctx.userId).eq("user_day", ctx.dayKey).limit(1);
        if (day.error) throw new Error("SOURCE_QUERY_FAILED");
        const resultId = (day.data ?? [])[0]?.id;
        if (!resultId) return null;
        const { data, error } = await ctx.db.from("daily_training")
          .select("curve, peak_hr, zone_minutes").eq("result_id", resultId).limit(1);
        if (error) throw new Error("SOURCE_QUERY_FAILED");
        const t = (data ?? [])[0] as { curve: unknown; peak_hr: number | null; zone_minutes: number[] | null } | undefined;
        const raw = (t?.curve ?? []) as [number, number][];
        if (!Array.isArray(raw) || raw.length < 2) return null;
        const series: Point[] = raw
          .filter((p) => Array.isArray(p) && p.length >= 2 && p[1] != null)
          .map((p) => [hhmm(new Date(Number(p[0]) * 1000).toISOString(), ctx.tz), Number(p[1])]);
        if (series.length < 2) return null;
        const zone = (t?.zone_minutes ?? []) as number[];
        const vals = series.map((p) => p[1]);
        const s = stats(vals);
        return {
          // The full value is 21, the same ceiling ring uses; the panel draws it as a line.
          data: { kind: "curve", series, mark: 21 },
          agg: {
            ...s, peakHr: t?.peak_hr ?? null, points: series.length,
            z4: zone[3] ?? null, z5: zone[4] ?? null,
            hardMinutes: (zone[3] ?? 0) + (zone[4] ?? 0),
          },
          hero: `${s.latest}`, window: "TODAY",
        };
      },
    },
    {
      id: "response.meal.last", kind: "curve",
      says: "最近一餐之后的腕上光学反应指数（无量纲，不是血糖）：开饭一刻与回到基线的一刻都标出来",
      async fetch(ctx) {
        const { start, end } = dayBounds(ctx.dayKey, ctx.tz);
        const meals = await ctx.db.from("meals").select("logged_at, slot")
          .eq("user_id", ctx.userId).gte("logged_at", start.toISOString()).lt("logged_at", end.toISOString())
          .order("logged_at", { ascending: false }).limit(1);
        if (meals.error) throw new Error("SOURCE_QUERY_FAILED");
        const meal = (meals.data ?? [])[0] as { logged_at: string; slot: string } | undefined;
        if (!meal) return null;
        const at = Date.parse(meal.logged_at);
        // ⚠️ The band samples this roughly every half hour, not every minute. A 30-minute
        // baseline window and a six-point floor — the shape a dense signal would want —
        // never once filled against real rows. The window is the cadence's, not a
        // continuous monitor's: 90 minutes before for a baseline, three hours after for the
        // response, and at least one sample on each side or there is no index to compute.
        const { data, error } = await ctx.db.from("response_samples").select("ts, optical")
          .eq("user_id", ctx.userId)
          .gte("ts", new Date(at - 90 * 60_000).toISOString())
          .lt("ts", new Date(at + 180 * 60_000).toISOString())
          .order("ts").limit(400);
        if (error) throw new Error("SOURCE_QUERY_FAILED");
        const rows = (data ?? []) as { ts: string; optical: number }[];
        if (rows.length < 4) return null;
        const before = rows.filter((r) => Date.parse(r.ts) < at).map((r) => r.optical);
        const baseline = mean(before);
        if (baseline == null || baseline <= 0) return null;
        if (rows.length - before.length < 2) return null;
        // Unitless on purpose: the index is the rise over this meal's own baseline, never
        // a vendor scalar and never a lab unit. The table's comment is the rule.
        const series: Point[] = rows.map((r) => [hhmm(r.ts, ctx.tz), Math.round((r.optical / baseline - 1) * 100)]);
        const startIdx = rows.findIndex((r) => Date.parse(r.ts) >= at);
        if (startIdx < 0) return null;
        // ⚠️ The peak is the meal's peak, so it is searched from the meal forward. Searching
        // the whole series let a quiet pre-meal sample win and printed "peak at −86 min" —
        // a number that is not wrong by a little, it is describing the wrong event.
        let peakIdx = startIdx;
        for (let i = startIdx; i < series.length; i++) if (series[i][1] > series[peakIdx][1]) peakIdx = i;
        const backIdx = series.findIndex((p, i) => i > peakIdx && p[1] <= 5);
        const marks = [startIdx, backIdx].filter((i) => i >= 0);
        const minsFrom = (i: number) => Math.round((Date.parse(rows[i].ts) - at) / 60_000);
        return {
          data: { kind: "curve", series, marks },
          agg: {
            peak: series[peakIdx][1], peakAfterMin: minsFrom(peakIdx),
            settleMin: backIdx >= 0 ? minsFrom(backIdx) : null,
            points: series.length, baselineSamples: before.length,
          },
          hero: `${series[peakIdx][1] > 0 ? "+" : ""}${series[peakIdx][1]}`,
          window: meal.slot.toUpperCase(),
        };
      },
    },
    {
      id: "rr.tachogram.last", kind: "trace",
      says: "上一段逐拍间期（RR，毫秒）按拍号画成一条迹线——band_rr_evidence 的原始数组",
      async fetch(ctx) {
        const run = await recentIntervals(ctx, 10);
        if (!run) return null;
        const beats = run.beats;
        const s = stats(beats);
        // The trace renderer eats samples + hz; a tachogram is one sample per beat, so the
        // rate is the mean beat rate rather than a fixed sampling frequency.
        const hz = s.mean ? r1(1000 / s.mean) : 1;
        return {
          data: { kind: "trace", samples: beats, hz },
          agg: { ...s, beats: beats.length, hz },
          hero: `${beats.length}`, unit: "ms", window: "LAST READING",
        };
      },
    },
  ];
}

/// A daily metric over 7 or 30 days, as a curve (line) or a column (days). One source id
/// serves both: the chart decides the kind it wants, see `fetchAs`.
function dailySeries(id: string, label: string, unit: string, pick: (r: DayRow) => number | null, spans: number[]): Source[] {
  return spans.map((n) => ({
    id: `${id}.${n}d`, kind: "curve",
    says: `最近 ${n} 天每天的 ${label}${unit ? `（${unit}）` : ""}`,
    async fetch(ctx) {
      const days = window(ctx, n);
      const rows = await dayRows(ctx, days[0], ctx.dayKey);
      if (!rows) return null;
      const by = new Map(rows.map((r) => [r.user_day, pick(r)]));
      const present = days.filter((d) => by.get(d) != null);
      if (present.length < 2) return null;
      const series: Point[] = present.map((d) => [n <= 7 ? weekday(d) : mmdd(d), Number(by.get(d))]);
      const vals = series.map((p) => p[1]);
      const s = stats(vals);
      const half = Math.floor(vals.length / 2);
      const prev = mean(vals.slice(0, half)), curr = mean(vals.slice(half));
      return {
        data: { kind: "curve", series },
        agg: { ...s, today: by.get(ctx.dayKey) ?? null, days: present.length, windowDays: n, thisHalfVsPrevHalf: prev != null && curr != null ? r1(curr - prev) : null, latestVsMean: s.latest != null && s.mean != null ? r1(s.latest - s.mean) : null },
        hero: `${s.latest}${unit === "%" ? "%" : ""}`, unit, window: `${n} DAYS`,
      };
    },
  }));
}

function composition(): Source[] {
  interface Comp { measured_at: string; body_fat_pct: number | null; fat_mass_kg: number | null; lean_body_mass_kg: number | null }
  const load = async (ctx: Ctx, weeks: number): Promise<Comp[] | null> => {
    const from = dayBounds(ctx.from ?? addDays(ctx.to ?? ctx.dayKey, 1 - 7 * weeks), ctx.tz).start.toISOString();
    const data = await pageAll<Comp>((lo,hi) => ctx.db.from("body_composition")
      .select("measured_at, body_fat_pct, fat_mass_kg, lean_body_mass_kg")
      .eq("user_id", ctx.userId).gte("measured_at", from).lt("measured_at",dayBounds(ctx.to ?? ctx.dayKey,ctx.tz).end.toISOString()).order("measured_at").order("id").range(lo,hi));
    return (data ?? []).map((r) => ({ ...r, body_fat_pct: r.body_fat_pct == null ? null : Number(r.body_fat_pct), fat_mass_kg: r.fat_mass_kg == null ? null : Number(r.fat_mass_kg), lean_body_mass_kg: r.lean_body_mass_kg == null ? null : Number(r.lean_body_mass_kg) }));
  };
  return [
    {
      id: "composition.dual", kind: "pair", says: "12 周脂肪量 vs 瘦体重两条线（kg）",
      async fetch(ctx) {
        const rows = (await load(ctx, 12))?.filter((r) => r.fat_mass_kg != null && r.lean_body_mass_kg != null);
        if (!rows || rows.length < 2) return null;
        const hi: Point[] = rows.map((r) => [mmdd(dayOf(r.measured_at, ctx.tz)), r.lean_body_mass_kg!]);
        const lo: Point[] = rows.map((r) => [mmdd(dayOf(r.measured_at, ctx.tz)), r.fat_mass_kg!]);
        const f = rows[0], l = rows[rows.length - 1];
        return {
          data: { kind: "pair", hi: lo, lo: hi, a: "FAT", b: "LEAN" },
          agg: { fat: l.fat_mass_kg, lean: l.lean_body_mass_kg, fatPct: l.body_fat_pct, fatChange: r1(l.fat_mass_kg! - f.fat_mass_kg!), leanChange: r1(l.lean_body_mass_kg! - f.lean_body_mass_kg!), readings: rows.length, weeks: 12 },
          hero: l.body_fat_pct == null ? `${l.fat_mass_kg} kg fat` : `${l.body_fat_pct} % fat`, window: "12 WEEKS",
        };
      },
    },
    {
      id: "composition.delta", kind: "column", says: "两次体成分之间脂肪量的变化，一柱一次，有正有负（kg）",
      async fetch(ctx) {
        const rows = (await load(ctx, 12))?.filter((r) => r.fat_mass_kg != null);
        if (!rows || rows.length < 3) return null;
        const bins: Point[] = [];
        for (let i = 1; i < rows.length; i++) bins.push([mmdd(dayOf(rows[i].measured_at, ctx.tz)), r1(rows[i].fat_mass_kg! - rows[i - 1].fat_mass_kg!)]);
        const last = bins;
        const vals = last.map((b) => b[1]);
        const net = r1(vals.reduce((a, b) => a + b, 0));
        return {
          data: { kind: "column", bins: last, unit: "kg", total: net },
          agg: { net, up: vals.filter((v) => v > 0).length, down: vals.filter((v) => v < 0).length, readings: last.length, fat: rows[rows.length - 1].fat_mass_kg, weeks: 12 },
          hero: `${net > 0 ? "+" : ""}${net} kg`, unit: "kg", window: `${last.length} READINGS`,
        };
      },
    },
    {
      id: "composition.recomp", kind: "grid", says: "12 周 × 7 天的格子：每次测量脂肪往下（亮）还是往上（暗）",
      async fetch(ctx) {
        const rows = (await load(ctx, 12))?.filter((r) => r.fat_mass_kg != null);
        if (!rows || rows.length < 3) return null;
        const days = window(ctx, 84);
        const state = new Map<string, number>();
        for (let i = 1; i < rows.length; i++) {
          const d = rows[i].fat_mass_kg! - rows[i - 1].fat_mass_kg!;
          state.set(dayOf(rows[i].measured_at, ctx.tz), d < -0.05 ? 3 : d > 0.05 ? 1 : 2);
        }
        // 7 rows (weekday) × 12 columns (weeks), oldest week left.
        const cells: number[][] = Array.from({ length: 7 }, () => Array(12).fill(0));
        days.forEach((d, i) => { cells[i % 7][Math.floor(i / 7)] = state.get(d) ?? 0; });
        const down = [...state.values()].filter((s) => s === 3).length, up = [...state.values()].filter((s) => s === 1).length;
        return {
          data: { kind: "grid", rows: 7, cols: 12, cells, scale: 3 },
          agg: { down, up, measured: state.size, weeks: 12, fatChange: r1(rows[rows.length - 1].fat_mass_kg! - rows[0].fat_mass_kg!) },
          hero: `${down} DOWN · ${up} UP`, window: "12 WEEKS",
        };
      },
    },
  ];
}

export const SOURCE_IDS = SOURCES.map((s) => s.id) as [string, ...string[]];
export const SOURCE_BY_ID = new Map(SOURCES.map((s) => [s.id, s]));

export function sourceList(ids: string[] = SOURCE_IDS): string {
  return ids.map((id) => `${id} — ${SOURCE_BY_ID.get(id)?.says ?? ""}`).join("\n");
}

/// Fetch a source and, where the chart wants a different kind than the source's own
/// (a daily series drawn as columns, a column drawn as a line), convert the shape.
export async function fetchAs(id: string, kind: Kind, ctx: Ctx): Promise<SourceResult | null> {
  const src = SOURCE_BY_ID.get(id);
  if (!src) return null;
  const key = JSON.stringify([ctx.userId, id, ctx.dayKey, ctx.tz, ctx.from, ctx.to]);
  let pending = ctx.cache?.get(key);
  if (!pending) {
    pending = (async () => {
      const to = ctx.to ?? ctx.dayKey;
      const span = id.startsWith("composition.") ? 84 : Number(id.match(/\.(\d+)d$/)?.[1] ?? 1);
      const from = ctx.from ?? addDays(to,1-span);
      const before = await readSnapshot(ctx,from,to);
      const result = await src.fetch(ctx);
      acceptSnapshot(ctx,before,await readSnapshot(ctx,from,to));
      if (!result) return null;
      const digest = await crypto.subtle.digest("SHA-256",new TextEncoder().encode(JSON.stringify([key,result])));
      const revision = Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,"0")).join("");
      return {...result,evidence:{...result.evidence,id:revision,metric:id,dayKey:ctx.dayKey,from,to,timezone:ctx.tz,unit:result.unit??null,observedAt:new Date().toISOString()}};
    })();
    ctx.cache?.set(key, pending);
  }
  const r = await pending;
  if (!r) return null;
  if (r.data.kind === kind) return r;
  if (r.data.kind === "curve" && kind === "column") return { ...r, data: { kind: "column", bins: r.data.series, unit: r.unit }, hero: r.agg.mean != null ? `${r.agg.mean} avg` : r.hero };
  if (r.data.kind === "column" && kind === "curve") return { ...r, data: { kind: "curve", series: r.data.bins } };
  return null;
}
