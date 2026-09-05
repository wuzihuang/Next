import { readSnapshot, acceptSnapshot } from "./metric-snapshot.ts";
// 07 · 09 · the data behind every chart, fetched by the server rather than copied by the model.
//
// A chart tool names a source; the source reads this user's rows through the turn's own JWT
// (RLS applies), buckets them to the width of a 314-pt panel, and hands back the exact shape
// the renderer eats. The model never transcribes a series — it chooses one. What it may say
// about it is the `agg` block, which the render tool harvests into the number ledger.
//
// null means "no data": the panel writes —— and the model picks another chart. Never 0.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { readSampleHistory } from "./archive.ts";
import { SEED_MEAL_VERSION } from "./db.ts";

export type Point = [string, number];

export type ChartData =
  | { kind: "curve"; series: Point[]; split?: number }
  | { kind: "pair"; hi: Point[]; lo: Point[]; a?: string; b?: string }
  | { kind: "column"; bins: Point[]; unit?: string; total?: number }
  | { kind: "arc"; value: number; goal: number; unit: string }
  | { kind: "gauge"; value: number; zones: [number, number, string][] }
  | { kind: "stack"; parts: Point[] }
  | { kind: "grid"; rows: number; cols: number; cells: number[][]; scale: number; rowLabels?: string[]; colLabels?: string[] }
  | { kind: "strip"; minutes?: number[]; current_zone?: number; lanes?: [number, number][]; from?: string; to?: string }
  | { kind: "rows"; rows: { label: string; value: string; spark?: number[] }[] };

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

export interface Ctx {
  db: SupabaseClient;
  userId: string;
  /// The user day being asked about, YYYY-MM-DD in the user's calendar.
  dayKey: string;
  tz: string;
  from?: string;
  to?: string;
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

const WD = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

function tzParts(at: Date, tz: string) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
  });
  const p = Object.fromEntries(fmt.formatToParts(at).map((x) => [x.type, x.value]));
  return {
    year: Number(p.year), month: Number(p.month), day: Number(p.day),
    hour: Number(p.hour), minute: Number(p.minute), second: Number(p.second),
  };
}

function offsetMs(at: Date, tz: string): number {
  const p = tzParts(at, tz);
  return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - at.getTime();
}

/// The instant of `hour:00` local time on `dayKey` in `tz`. Two passes settle a DST edge.
export function zoned(dayKey: string, hour: number, tz: string): Date {
  const [y, m, d] = dayKey.split("-").map(Number);
  const wall = Date.UTC(y, m - 1, d, hour);
  let guess = wall;
  for (let i = 0; i < 2; i++) guess = wall - offsetMs(new Date(guess), tz);
  return new Date(guess);
}

/// F2 rule 03 · a user day runs local 04:00 → 04:00 the next day.
export function dayBounds(dayKey: string, tz: string): { start: Date; end: Date } {
  return { start: zoned(dayKey, 4, tz), end: zoned(addDays(dayKey, 1), 4, tz) };
}

export function addDays(dayKey: string, n: number): string {
  const [y, m, d] = dayKey.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

export function weekday(dayKey: string): string {
  const [y, m, d] = dayKey.split("-").map(Number);
  return WD[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
}

function hhmm(iso: string, tz: string): string {
  const p = tzParts(new Date(iso), tz);
  return `${String(p.hour).padStart(2, "0")}:${String(p.minute).padStart(2, "0")}`;
}

function mmdd(dayKey: string): string { return dayKey.slice(5); }

/// Which user day an instant belongs to, as a key. Before 04:00 is still yesterday.
export function dayOf(iso: string, tz: string): string {
  const at = new Date(iso);
  const p = tzParts(at, tz);
  const midnight = Date.UTC(p.year, p.month - 1, p.day);
  const start = p.hour < 4 ? midnight - 86_400_000 : midnight;
  return new Date(start).toISOString().slice(0, 10);
}

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
  ...dailySeries("trainingLoad", "TRAINING LOAD", "", (r) => r.training_load, [7, 30]),
  ...dailySeries("bodyBattery", "BODY BATTERY", "%", (r) => r.reserve_score, [7, 30]),
  ...dailySeries("intakeKcal", "EATEN", "kcal", (r) => one(r.day_fuel)?.kcal_in ?? null, [7, 30]),
  {
    id: "deltaKcal.7d", kind: "column", says: "最近 7 天每天吃进减消耗（kcal，有正有负）",
    async fetch(ctx) {
      const days = window(ctx, 7);
      const rows = await dayRows(ctx, days[0], ctx.dayKey);
      if (!rows) return null;
      const byDay = new Map(rows.map((r) => [r.user_day, r.fuel_balance_kcal]));
      const present = days.filter((d) => byDay.get(d) != null);
      if (present.length < 2) return null;
      const bins: Point[] = present.map((d) => [weekday(d), byDay.get(d)!]);
      const vals = bins.map((b) => b[1]);
      const s = stats(vals);
      const net = vals.reduce((a, b) => a + b, 0);
      return {
        data: { kind: "column", bins, unit: "kcal", total: net },
        agg: { ...s, net, up: vals.filter((v) => v > 0).length, down: vals.filter((v) => v < 0).length, windowDays: 7 },
        hero: `${net > 0 ? "+" : ""}${net} kcal`, unit: "kcal", window: "7 DAYS",
      };
    },
  },
  ...[30, 90].map<Source>((n) => ({
    id: `weight.${n}d`, kind: "curve", says: `最近 ${n} 天的体重（kg）`,
    async fetch(ctx) {
      const from = zoned(ctx.from ?? addDays(ctx.dayKey, 1 - n), 4, ctx.tz).toISOString();
      const data = await pageAll<{measured_at:string;weight_kg:number}>((lo,hi) => ctx.db.from("weigh_ins").select("measured_at, weight_kg")
        .eq("user_id", ctx.userId).gte("measured_at", from).lt("measured_at",dayBounds(ctx.to ?? ctx.dayKey,ctx.tz).end.toISOString()).order("measured_at").order("id").range(lo,hi));
      const rows = (data ?? []) as { measured_at: string; weight_kg: number }[];
      if (rows.length < 2) return null;
      const series: Point[] = rows.map((r) => [mmdd(dayOf(r.measured_at, ctx.tz)), Number(r.weight_kg)]);
      const vals = series.map((p) => p[1]);
      const s = stats(vals);
      return {
        data: { kind: "curve", series },
        agg: { ...s, first: vals[0], change: r1(vals[vals.length - 1] - vals[0]), days: n },
        hero: `${s.latest} kg`, unit: "kg", window: `${n} DAYS`,
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
      const hour = (c: number) => String((4 + c * 2) % 24).padStart(2, "0");
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
      const rows = await dayRows(ctx, ctx.dayKey, ctx.dayKey);
      const v = rows?.[0]?.training_load;
      if (v == null) return null;
      return { data: { kind: "arc", value: v, goal: 21, unit: "" }, agg: { value: v, goal: 21, pct: Math.round(v / 21 * 100) }, hero: `${v}`, window: "TODAY" };
    },
  },
  {
    id: "battery.now", kind: "arc", says: "此刻的 BODY BATTERY，0–100",
    async fetch(ctx) {
      const rows = await dayRows(ctx, ctx.dayKey, ctx.dayKey);
      const rd = one(rows?.[0]?.reserve_daily);
      const v = rd?.current_value ?? rows?.[0]?.reserve_score ?? null;
      if (v == null) return null;
      return { data: { kind: "arc", value: v, goal: 100, unit: "%" }, agg: { value: v, wake: rd?.wake_value ?? null, min: rd?.min_value ?? null, sinceWake: rd?.wake_value != null ? v - rd.wake_value : null }, hero: `${v}`, unit: "%", window: "NOW" };
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
      const days = window(ctx, 7);
      const from = dayBounds(days[0], ctx.tz).start.toISOString();
      const { data, error } = await ctx.db.from("weigh_ins").select("measured_at").eq("user_id", ctx.userId).gte("measured_at", from);
      if (error) throw new Error("SOURCE_QUERY_FAILED");
      const have = new Set((data ?? []).map((w) => dayOf(w.measured_at, ctx.tz)));
      const cells: number[][] = [days.map((d) => (have.has(d) ? 1 : 0))];
      const filled = cells[0].reduce((a, b) => a + b, 0);
      if (!filled) return null;
      return { data: { kind: "grid", rows: 1, cols: 7, cells, scale: 1, colLabels: days.map(weekday) }, agg: { filled, total: 7 }, hero: `${filled} OF 7`, window: "7 DAYS" };
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
];

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
    const from = zoned(ctx.from ?? addDays(ctx.dayKey, -7 * weeks), 4, ctx.tz).toISOString();
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
