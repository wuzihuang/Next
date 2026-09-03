import { tool } from "npm:ai@4.3.16";
import { z } from "npm:zod@3.25.76";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
// ⚠️ A value import, not `import type`: record() constructs a trial ledger to measure a
// return before harvesting it. As a type-only import the class was erased at runtime, `new`
// threw, generateText caught it, and every turn came back MODEL_UNAVAILABLE.
import { NumberLedger } from "./ledger.ts";
import { fetchAs, sourceList, SOURCE_BY_ID, SOURCE_IDS, type Ctx } from "./sources.ts";

/// F4 §03 · eight read tools. All read-only, all through the caller's JWT.
/// Return values are three-state, never two: ok+data, ok+null, and not-ok.
/// "no data" is an assertion and the screen writes ——; "the tool broke" is silence and
/// she may not mention that dimension at all this turn.
type Ok<T> = { ok: true; data: T | null };
type Err = { ok: false };
type Res<T> = Ok<T> | Err;

export function buildTools(db: SupabaseClient, userId: string, ledger: NumberLedger,
                           cal: { dayKey: string; tz: string } = { dayKey: new Date().toISOString().slice(0, 10), tz: "UTC" }) {
  const ctx: Ctx = { db, userId, dayKey: cal.dayKey, tz: cal.tz };
  // F7 rule 11 · 「账本容量硬上限 N ≤ 60，服务端实时计数，超配按固定顺序降级并带 trimmed:true」.
  // The series goes first, halved from the old end until the return fits; the model is told.
  const CAP = 60;
  const record = <T>(name: string, value: Res<T>) => {
    if (!value.ok || value.data === null) return value;
    const fits = (d: unknown) => {
      const trial = new NumberLedger(); trial.harvest(d, name);
      return ledger.size + trial.size <= CAP;
    };
    let data: unknown = value.data;
    const d = data as Record<string, unknown>;
    if (!fits(data) && Array.isArray(d?.points)) {
      let pts = d.points as unknown[];
      while (pts.length > 2 && !fits({ ...d, points: pts })) pts = pts.slice(Math.ceil(pts.length / 2));
      data = { ...d, points: pts, trimmed: true };
    }
    ledger.harvest(data, name);
    return { ok: true, data } as Res<T>;
  };

  return {
    "day.get": tool({
      description: "今天（或指定用户日）的四个上屏数字与来源标记。",
      parameters: z.object({ dayKey: z.string().describe("YYYY-MM-DD") }),
      execute: async ({ dayKey }) => {
        const { data, error } = await db
          .from("daily_results")
          .select("training_load, reserve_score, fuel_balance_kcal, daily_direction, the_call, the_call_confidence, id")
          .eq("user_id", userId).eq("user_day", dayKey).maybeSingle();
        if (error) return { ok: false } as Err;
        if (!data) return record("day.get", { ok: true, data: null });

        const { data: fuel } = await db.from("day_fuel")
          .select("intake_state, kcal_in, kcal_out, slot_states, target_in")
          .eq("result_id", data.id).maybeSingle();
        // F7 §08 · the numbers she will want to say are computed here, not derived by her.
        const targetKcal = fuel?.target_in ?? null;
        const remainingKcal = (targetKcal != null && fuel?.kcal_in != null) ? targetKcal - fuel.kcal_in : null;

        return record("day.get", {
          ok: true,
          data: {
            trainingLoad: data.training_load,
            bodyBattery: data.reserve_score,
            fuel: {
              intakeKcal: fuel?.kcal_in ?? null,
              burnKcal: fuel?.kcal_out ?? null,
              deltaKcal: data.fuel_balance_kcal,
              targetKcal,
              remainingKcal,
              slotState: fuel?.slot_states ?? null,
            },
            dailyDirection: data.daily_direction,
            composition: { call: data.the_call, confidence: data.the_call_confidence },
          },
        });
      },
    }),

    "range.get": tool({
      description: "一段时间的某个指标序列。跨度硬上限 90 天，超了服务端自己截断。",
      parameters: z.object({
        metric: z.enum(["trainingLoad", "bodyBattery", "intakeKcal", "deltaKcal", "weight"]),
        from: z.string(), to: z.string(),
      }),
      execute: async ({ metric, from, to }) => {
        const column = {
          trainingLoad: "training_load", bodyBattery: "reserve_score",
          intakeKcal: "fuel_balance_kcal", deltaKcal: "fuel_balance_kcal", weight: "",
        }[metric];

        if (metric === "weight") {
          const { data, error } = await db.from("weigh_ins")
            .select("measured_at, weight_kg").eq("user_id", userId)
            .gte("measured_at", from).lte("measured_at", to)
            .order("measured_at").limit(90);
          if (error) return { ok: false } as Err;
          return record("range.get", {
            ok: true,
            data: {
              points: (data ?? []).map((r) => ({ dayKey: r.measured_at, value: r.weight_kg })),
              truncated: (data?.length ?? 0) >= 90,
            },
          });
        }

        const { data, error } = await db.from("daily_results")
          .select(`user_day, ${column}`).eq("user_id", userId)
          .gte("user_day", from).lte("user_day", to)
          .order("user_day").limit(90);
        if (error) return { ok: false } as Err;
        const rows = (data ?? []) as unknown as Record<string, unknown>[];
        const points = rows.map((r) => ({ dayKey: r.user_day, value: (r[column] as number | null) ?? null }));
        // F7 §08 · 「她想说的差值，服务端必须提前替她算好」. With pairwise derivation gone from the
        // ledger, "today vs the seven-day mean" has to arrive as a number, or it is not said.
        // null stays null: an absent day does not become 0 in a mean, and a delta against
        // nothing is nothing (补屏 rule 09).
        const vals = points.map((p) => p.value).filter((v): v is number => v != null);
        const latest = points.length ? points[points.length - 1].value : null;
        const mean = vals.length ? Math.round((vals.reduce((a, b) => a + b, 0) / vals.length) * 10) / 10 : null;
        const half = Math.floor(points.length / 2);
        const meanOf = (ps: typeof points) => { const v = ps.map((p) => p.value).filter((x): x is number => x != null); return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null; };
        const prevMean = half ? meanOf(points.slice(0, half)) : null, thisMean = half ? meanOf(points.slice(half)) : null;
        const r1 = (x: number | null) => (x == null ? null : Math.round(x * 10) / 10);
        return record("range.get", {
          ok: true,
          data: {
            // A missing day is a null point, never a 0, and never interpolated.
            points,
            agg: { latest, mean, min: vals.length ? Math.min(...vals) : null, max: vals.length ? Math.max(...vals) : null, days: vals.length },
            dlt: {
              latestVsMean: latest != null && mean != null ? r1(latest - mean) : null,
              thisHalfVsPrevHalf: thisMean != null && prevMean != null ? r1(thisMean - prevMean) : null,
            },
            truncated: rows.length >= 90,
          },
        });
      },
    }),

    "profile.get": tool({
      description: "档案。onboarding 之后必然存在，查不到属于严重故障。",
      parameters: z.object({}),
      execute: async () => {
        const { data, error } = await db.from("profiles")
          .select("sex, birth_date, height_cm, goal, units_metric, timezone")
          .eq("user_id", userId).maybeSingle();
        if (error || !data) return { ok: false } as Err;
        const { data: w } = await db.from("weigh_ins")
          .select("weight_kg, source").eq("user_id", userId)
          .order("measured_at", { ascending: false }).limit(1).maybeSingle();
        return record("profile.get", {
          ok: true,
          data: {
            sex: data.sex,
            birthYear: data.birth_date ? Number(String(data.birth_date).slice(0, 4)) : null,
            heightCm: data.height_cm,
            weightKg: w?.weight_kg ?? null,
            weightSource: w?.source === "health" ? "HEALTHKIT" : "MANUAL",
            goal: data.goal,
            units: data.units_metric ? "METRIC" : "IMPERIAL",
            timezone: data.timezone,
            dayStartHour: 4,
          },
        });
      },
    }),

    "device.capabilities": tool({
      description: "手环连接状态与能力表。FunctionStatus 原值，不压成 bool。",
      parameters: z.object({}),
      execute: async () => {
        const { data, error } = await db.from("devices")
          .select("battery_percent, firmware_version, last_origin_sync_at, unbound_at, id")
          .eq("user_id", userId).is("unbound_at", null).maybeSingle();
        if (error) return { ok: false } as Err;
        if (!data) return record("device.capabilities", { ok: true, data: null });
        const { data: caps } = await db.from("device_capabilities")
          .select("functions").eq("device_id", data.id).maybeSingle();
        return record("device.capabilities", {
          ok: true,
          data: {
            connected: true,
            batteryPercent: data.battery_percent,
            firmwareVersion: data.firmware_version,
            lastSyncAt: data.last_origin_sync_at,
            functions: caps?.functions ?? {},
          },
        });
      },
    }),

    "meals.openSlots": tool({
      description: "四个餐位的状态。⚠️ 没记的槽是 OPEN，不是 0 kcal。",
      parameters: z.object({ dayKey: z.string() }),
      execute: async ({ dayKey }) => {
        const { data, error } = await db.from("meals")
          .select("slot, kcal, confidence").eq("user_id", userId)
          .eq("user_day", dayKey).is("deleted_at", null);
        if (error) return { ok: false } as Err;
        const all = ["BREAKFAST", "LUNCH", "DINNER", "SNACK"];
        const logged = data ?? [];
        const taken = new Set(logged.map((m) => m.slot));
        return record("meals.openSlots", {
          ok: true,
          data: {
            open: all.filter((s) => !taken.has(s)),
            logged: logged.map((m) => ({ slot: m.slot, kcal: m.kcal, confidence: m.confidence })),
            dayState: logged.length === 0 ? "UNLOGGED" : (taken.size >= 4 ? "CONFIRMED" : "PARTIAL"),
          },
        });
      },
    }),

    "meals.search": tool({
      description: "在这个用户自己最近 30 天的记录里搜。搜不到就是搜不到，不许拿相似的顶上。",
      parameters: z.object({ query: z.string(), limit: z.number().int().max(20).default(10) }),
      execute: async ({ query, limit }) => {
        const since = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10);
        const { data, error } = await db.from("meals")
          .select("logged_at, text_input, kcal, protein_g, carb_g, fat_g")
          .eq("user_id", userId).is("deleted_at", null)
          .gte("user_day", since).ilike("text_input", `%${query}%`).limit(limit);
        if (error) return { ok: false } as Err;
        return record("meals.search", {
          ok: true,
          data: {
            hits: (data ?? []).map((m) => ({
              loggedAt: m.logged_at, label: m.text_input, kcal: m.kcal,
              macros: { p: m.protein_g, c: m.carb_g, f: m.fat_g },
            })),
          },
        });
      },
    }),

    "measurement.latest": tool({
      description: "最近几次测量。⚠️ BATTERY_CHECK 是产品概念，SDK 里没有对应接口。",
      parameters: z.object({
        kind: z.enum(["BIA", "BATTERY_CHECK"]), n: z.number().int().max(10).default(3),
      }),
      execute: async ({ kind, n }) => {
        if (kind === "BIA") {
          const { data, error } = await db.from("body_composition")
            .select("measured_at, body_fat_pct, fat_mass_kg, lean_body_mass_kg, measurement_source, derived_fields")
            .eq("user_id", userId).order("measured_at", { ascending: false }).limit(n);
          if (error) return { ok: false } as Err;
          return record("measurement.latest", { ok: true, data: { samples: data ?? [] } });
        }
        const { data, error } = await db.from("reserve_samples")
          .select("ts, value, source").eq("user_id", userId)
          .order("ts", { ascending: false }).limit(n);
        if (error) return { ok: false } as Err;
        return record("measurement.latest", { ok: true, data: { samples: data ?? [] } });
      },
    }),

    // 07 · the ninth read. The same catalogue the chart tools draw from, returned as the
    // numbers a sentence may use: aggregates and a short tail of points. The chart itself
    // is drawn by screen.render.<type> naming the same source — the series never has to
    // be copied through the model.
    "series.get": tool({
      description: "按数据源读一组数：agg 里的 latest/mean/min/max/count 用来写字，points 是最后几个点。要画图时把同一个 source 交给 screen.render.*。数据源：\n" + sourceList(),
      parameters: z.object({ source: z.enum(SOURCE_IDS) }),
      execute: async ({ source }) => {
        const src = SOURCE_BY_ID.get(source);
        if (!src) return { ok: false } as Err;
        const r = await fetchAs(source, src.kind, ctx);
        if (!r) return record("series.get", { ok: true, data: null });
        const d = r.data as Record<string, unknown>;
        const tail = (xs: unknown) => (Array.isArray(xs) ? xs.slice(-8) : undefined);
        return record("series.get", {
          ok: true,
          data: {
            agg: r.agg, hero: r.hero ?? null, unit: r.unit ?? null, window: r.window,
            points: tail(d.series) ?? tail(d.bins) ?? tail(d.parts) ?? tail(d.rows) ?? tail(d.minutes) ?? null,
          },
        });
      },
    }),

    // ⚠️ The one tool that deliberately does not go through `record`. Every other return is
    // harvested into the ledger; this one must not be, or the previous frame's numbers become
    // citable sources and a stale value can be carried forward for as long as the model keeps
    // repeating it. Seen working: a turn tried to re-assert 13.1 after reading it out of the
    // last frame's sentence, and rule 08 rejected the whole frame because it was never a
    // number in anything fetched that turn. Wrapping this in `record` would silently undo that.
    "screen.last": tool({
      description: "上一帧说了什么，避免连着两轮说同一句。null 是正常的。",
      parameters: z.object({}),
      execute: async () => {
        const { data, error } = await db.from("screen_frames")
          .select("widget_tree, created_at, expires_at").eq("user_id", userId)
          .order("created_at", { ascending: false }).limit(1).maybeSingle();
        if (error) return { ok: false } as Err;
        return {
          ok: true,
          data: {
            envelope: data?.widget_tree ?? null,
            renderedAt: data?.created_at ?? null,
            expiresAt: data?.expires_at ?? null,
          },
        };
      },
    }),
  };
}
