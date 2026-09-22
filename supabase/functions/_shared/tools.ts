import { compareMetrics, metricComparisonSchema } from "./metric-compare.ts";
import { catalogForUser, dataReadSchema, readData } from "./data-read.ts";
import { clockIn, FIND_ENTITIES, findDescription, normalizeDay } from "./entities.ts";
import type { DeviceState } from "./freshness.ts";
import { loadMemory } from "./memory.ts";
import { tool } from "npm:ai@4.3.16";
import { z } from "npm:zod@3.25.76";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
// ⚠️ A value import, not `import type`: record() constructs a trial ledger to measure a
// return before harvesting it. As a type-only import the class was erased at runtime, `new`
// threw, generateText caught it, and every turn came back MODEL_UNAVAILABLE.
import { NumberLedger } from "./ledger.ts";
import { SEED_MEAL_VERSION } from "./db.ts";
import type { Ctx } from "./sources.ts";

/// Read tools for a turn. All read-only, all through the caller's JWT.
/// Two tools: `read` is the metric registry (series, stats, evidence), `find` returns
/// records and state by entity, each with an id the model can hand to `write`.
/// Return values are three-state, never two: ok+data, ok+null, and not-ok.
type Ok<T> = { ok: true; data: T | null };
type Err = { ok: false };
type Res<T> = Ok<T> | Err;

export const READ_TOOL = "read";
export const FIND_TOOL = "find";
/// Entities whose `find` reads personal health data (consent, freshness gate).
export const PERSONAL_ENTITIES = new Set(["meal", "day", "weigh_in", "measurement", "plan", "sport_session", "sleep_night", "profile"]);

export function buildTools(db: SupabaseClient, userId: string, ledger: NumberLedger,
                           cal: { dayKey: string; tz: string } = { dayKey: new Date().toISOString().slice(0, 10), tz: "UTC" },
                           sharedCtx?: Ctx, device?: DeviceState) {
  const ctx: Ctx = sharedCtx ?? { db, userId, dayKey: cal.dayKey, tz: cal.tz, cache: new Map() };
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

  const legacy = {
    "day.get": tool({
      description: "今天（或指定用户日）的四个上屏数字与来源标记。",
      parameters: z.object({ dayKey: z.string().describe("YYYY-MM-DD") }),
      execute: async ({ dayKey }) => {
        const { data, error } = await db
          .from("daily_results")
          .select("training_load, reserve_score, fuel_balance_kcal, daily_direction, the_call, the_call_confidence, id, daily_training(evidence)")
          .eq("user_id", userId).eq("user_day", dayKey).maybeSingle();
        if (error) return { ok: false } as Err;
        if (!data) return record("day.get", { ok: true, data: null });

        const { data: fuel, error: fuelError } = await db.from("day_fuel")
          .select("intake_state, kcal_in, kcal_out, slot_states, target_in, bmr_full_kcal, active_kcal, resting_source, goal_offset_kcal")
          .eq("result_id", data.id).maybeSingle();
        if (fuelError) return { ok: false } as Err;
        // F7 §08 · the numbers she will want to say are computed here, not derived by her.
        const targetKcal = fuel?.target_in ?? null;
        const remainingKcal = (targetKcal != null && fuel?.kcal_in != null) ? targetKcal - fuel.kcal_in : null;
        // #29 · TARGET = resting (whole day) + activity measured so far + goal offset, never
        // under the sex floor. The three parts travel with it so the sentence can account
        // for the number instead of restating it.
        const restingKcal = fuel?.bmr_full_kcal ?? null;
        const activeKcal = fuel?.active_kcal ?? null;
        const goalOffsetKcal = fuel?.goal_offset_kcal ?? null;
        const restingSource = fuel?.resting_source ?? null;
        const training = Array.isArray(data.daily_training) ? data.daily_training[0] : data.daily_training;
        const target = training?.evidence?.target ?? null;

        return record("day.get", {
          ok: true,
          data: {
            trainingLoad: data.training_load,
            trainingTarget: target,
            remainingLoad: typeof target?.target === "number" && typeof data.training_load === "number"
              ? Math.round(Math.max(0, target.target - data.training_load) * 10) / 10 : null,
            trainingSessions: training?.evidence?.sessions ?? [],
            bodyBattery: data.reserve_score,
            fuel: {
              intakeKcal: fuel?.kcal_in ?? null,
              burnKcal: fuel?.kcal_out ?? null,
              deltaKcal: data.fuel_balance_kcal,
              targetKcal,
              remainingKcal,
              restingKcal,
              activeKcal,
              goalOffsetKcal,
              restingSource,
              slotState: fuel?.slot_states ?? null,
              // F7 §08 · a number the sentence will want has to arrive as a number. "All 4
              // meals still open" was rejected as untraceable because the count of open
              // slots lived only in the shape of a jsonb object.
              openSlots: fuel?.slot_states
                ? Object.values(fuel.slot_states as Record<string, unknown>).filter((v) => v === "OPEN" || v === null).length
                : 4,
              loggedSlots: fuel?.slot_states
                ? Object.values(fuel.slot_states as Record<string, unknown>).filter((v) => v !== "OPEN" && v !== null).length
                : 0,
            },
            dailyDirection: data.daily_direction,
            composition: { call: data.the_call, confidence: data.the_call_confidence },
          },
        });
      },
    }),

    "metric.compare": tool({
      description:"Compare two metrics on aligned user days. Server computes compatible-unit differences and correlation only with at least seven overlapping nonconstant days; never claims causation. Timestamped measurements use last recorded value per user day.",
      parameters:metricComparisonSchema,
      execute:async(args)=>{
        const result=await compareMetrics(ctx,args);
        if(result.ok){
          for(const reading of result.data.readings)ledger.registerEvidence(reading.evidence,{stats:reading.stats,points:reading.points});
          ledger.registerEvidence(result.data.evidence.association,{value:result.data.association.pearsonR});
          if(result.data.evidence.difference)ledger.registerEvidence(result.data.evidence.difference,result.data.difference);
        }
        return result;
      },
    }),
    "data.read": tool({
      description:
        "Read one health metric over an inclusive user-day range. Day grains align missing days as null. Tick grains are bucketed by the server. Wrist-reported calories are not the product burn.",
      parameters: dataReadSchema,
      execute: async (args) => {
        const result = await readData(ctx, args);
        if (result.ok) {
          for (const reading of result.data) {
            ledger.registerEvidence(reading.evidence as import("./ledger.ts").MeasurementEvidence, {
              stats: reading.stats,
              points: reading.points,
            });
          }
          return record("data.read", { ok: true, data: result.data.length === 1 ? result.data[0] : result.data });
        }
        return result;
      },
    }),
    "data.catalog": tool({
      description:
        "List readable health metrics, their units, grain and origin. System tables are not listed.",
      parameters: z.object({}),
      execute: async () => {
        const data = await catalogForUser(ctx);
        return { ok: true, data };
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
          .eq("user_day", dayKey).is("deleted_at", null).neq("model_version", SEED_MEAL_VERSION);
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
          .eq("user_id", userId).is("deleted_at", null).neq("model_version", SEED_MEAL_VERSION)
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

  };
  // deno-lint-ignore no-explicit-any
  const run = (name: keyof typeof legacy, args: any) => (legacy[name].execute as any)(args, {} as never);
  const today = ctx.dayKey;
  const range = (a: Record<string, unknown>) => {
    const day = normalizeDay(a.day ?? a.dayKey ?? a.date, today);
    const from = normalizeDay(a.from, today) ?? day ?? today;
    const to = normalizeDay(a.to, today) ?? day ?? from;
    return { from: from <= to ? from : to, to: from <= to ? to : from, day: day ?? today };
  };
  const limit = (a: Record<string, unknown>) => Math.max(1, Math.min(50, Number(a.limit) || 20));
  const phone = (device as DeviceState & { settings?: Record<string, unknown> } | undefined)?.settings ?? null;
  const notOnPhone = (what: string) => ({ ok: false, code: "NOT_AVAILABLE", say: `${what} is only known to the phone and did not arrive with this turn. Ask the user to open the app page instead.` });

  const find = async (raw: Record<string, unknown>) => {
    const entity = String(raw.entity ?? "").trim().toLowerCase().replace(/[-\s]/g, "_");
    if (!FIND_ENTITIES.includes(entity)) return { ok: false, say: `"${raw.entity}" is not an entity. Use one of: ${FIND_ENTITIES.join(", ")}.` };
    const r = range(raw);
    switch (entity) {
      case "day": return run("day.get", { dayKey: r.day });
      case "profile": return run("profile.get", {});
      case "metric": return run("data.catalog", {});
      case "device": {
        const caps = await run("device.capabilities", {});
        return { ok: true, data: { ...(caps.ok ? caps.data ?? {} : {}), state: device ?? null } };
      }
      case "alarm":
        // No `alarms` key means the phone has not read the band's list this session — that
        // is "unknown", never "none". The phone reads it in the background for the next turn.
        if (!device?.alarms) return { ok: true, data: null, say: "The band's alarm list has not been read yet this session. Say so (write ——); do not say there are no alarms. Opening the alarms sheet or the next turn will have it." };
        return { ok: true, data: { items: device.alarms.map((a) => ({ ...a, label: a.label ?? "" })), count: device.alarms.length } };
      case "meal": {
        const query = raw.query != null ? String(raw.query) : "";
        const slot = raw.slot != null ? String(raw.slot).toUpperCase() : "";
        let q = db.from("meals").select("id, user_day, slot, text_input, kcal, protein_g, carb_g, fat_g, logged_at")
          .eq("user_id", userId).gte("user_day", r.from).lte("user_day", r.to).is("deleted_at", null).neq("model_version", SEED_MEAL_VERSION);
        if (query) q = q.ilike("text_input", `%${query}%`);
        if (slot) q = q.eq("slot", slot);
        const { data, error } = await q.order("logged_at").limit(limit(raw));
        if (error) return { ok: false } as Err;
        const editableFrom = new Date(Date.parse(today) - 6 * 864e5).toISOString().slice(0, 10);
        const items = (data ?? []).map((m) => ({
          id: m.id, day: m.user_day, slot: m.slot, name: m.text_input, kcal: m.kcal,
          protein_g: m.protein_g, carb_g: m.carb_g, fat_g: m.fat_g, at: m.logged_at,
          editable: m.user_day >= editableFrom && m.user_day <= today,
          label: `${m.user_day} · ${m.slot} · ${m.text_input} · ${m.kcal ?? "——"} kcal`,
        }));
        const slots = r.from === r.to ? await run("meals.openSlots", { dayKey: r.from }) : null;
        return record("find.meal", { ok: true, data: { items, count: items.length, ...(slots?.ok && slots.data ? { open_slots: slots.data.open, day_state: slots.data.dayState } : {}) } });
      }
      case "weigh_in": {
        const { data, error } = await db.from("weigh_ins").select("id, weight_kg, source, measured_at").eq("user_id", userId)
          .gte("measured_at", `${r.from}T00:00:00Z`).lt("measured_at", `${new Date(Date.parse(r.to) + 864e5).toISOString().slice(0, 10)}T00:00:00Z`)
          .order("measured_at", { ascending: false }).limit(limit(raw));
        if (error) return { ok: false } as Err;
        const items = (data ?? []).map((w) => ({ id: w.id, kg: w.weight_kg, source: w.source, at: w.measured_at, label: `${String(w.measured_at).slice(0, 16)} · ${w.weight_kg} kg · ${w.source}` }));
        return record("find.weigh_in", { ok: true, data: { items, count: items.length } });
      }
      case "measurement": {
        const kind = raw.kind != null ? String(raw.kind).toLowerCase() : "";
        const items: Record<string, unknown>[] = [];
        if (!kind || kind.includes("scan") || kind.includes("comp")) {
          const { data } = await db.from("body_composition").select("id, measured_at, body_fat_pct, fat_mass_kg, lean_body_mass_kg, input_weight_kg, measurement_source")
            .eq("user_id", userId).gte("user_day", r.from).lte("user_day", r.to).order("measured_at", { ascending: false }).limit(limit(raw));
          for (const m of data ?? []) items.push({ id: m.id, kind: "body_scan", at: m.measured_at, body_fat_pct: m.body_fat_pct, fat_mass_kg: m.fat_mass_kg, lean_mass_kg: m.lean_body_mass_kg, weight_kg: m.input_weight_kg, source: m.measurement_source, label: `${String(m.measured_at).slice(0, 16)} · body scan · ${m.body_fat_pct ?? "——"} %` });
        }
        if (!kind || kind.includes("balance") || kind.includes("check")) {
          const { data } = await db.from("balance_checks").select("id, measured_at, lead, rest_share, sdnn_ms, heart_rate")
            .eq("user_id", userId).gte("user_day", r.from).lte("user_day", r.to).order("measured_at", { ascending: false }).limit(limit(raw));
          for (const b of data ?? []) items.push({ id: b.id, kind: "balance_check", at: b.measured_at, lead: b.lead, rest_share: b.rest_share, sdnn_ms: b.sdnn_ms, heart_rate: b.heart_rate, label: `${String(b.measured_at).slice(0, 16)} · balance check · ${b.lead}` });
        }
        items.sort((a, b) => String(b.at).localeCompare(String(a.at)));
        return record("find.measurement", { ok: true, data: { items, count: items.length } });
      }
      case "plan": {
        const { data, error } = await db.from("daily_plans").select("user_day, title, summary, tasks, created_at").eq("user_id", userId).eq("user_day", r.day).maybeSingle();
        if (error) return { ok: false } as Err;
        if (!data) return { ok: true, data: null };
        const tasks = (Array.isArray(data.tasks) ? data.tasks : []).map((t: Record<string, unknown>, i: number) => ({ index: i + 1, id: t.id, title: t.title, sub: t.sub, basis: t.basis }));
        return record("find.plan", { ok: true, data: { day: data.user_day, title: data.title, summary: data.summary, tasks, count: tasks.length, made_at: data.created_at } });
      }
      case "memory": {
        const doc = await loadMemory(db, userId);
        if (!doc) return { ok: true, data: null };
        const query = raw.query != null ? String(raw.query).toLowerCase() : "";
        const facts = doc.facts.map((f, i) => ({ index: i, text: f.text, at: f.at, source: f.source })).filter((f) => !query || f.text.toLowerCase().includes(query));
        return { ok: true, data: { summary: doc.summary, facts, count: facts.length } };
      }
      case "sport_session": {
        const [{ data, error }, manual] = await Promise.all([
          db.from("daily_results").select("user_day, training_load, daily_training(segments, session_count, active_minutes, peak_hr, evidence)")
            .eq("user_id", userId).gte("user_day", r.from).lte("user_day", r.to).order("user_day", { ascending: false }).limit(limit(raw)),
          db.from("manual_sport_sessions").select("id, user_day, started_at, ended_at, sport_mode")
            .eq("user_id", userId).gte("user_day", r.from).lte("user_day", r.to).order("user_day", { ascending: false }).limit(limit(raw)),
        ]);
        if (error || manual.error) return { ok: false } as Err;
        const items: Record<string, unknown>[] = [];
        const settled = new Set<string>();
        for (const d of data ?? []) {
          const t = Array.isArray(d.daily_training) ? d.daily_training[0] : d.daily_training;
          if (Array.isArray(t?.evidence?.sessions)) {
            for (const session of t.evidence.sessions) {
              settled.add(session.session_id);
              items.push({ ...session,
                id: `${d.user_day}#${session.session_id}`, day: d.user_day, source: session.source ?? "recorded_session" });
            }
            continue;
          }
          const segments = Array.isArray(t?.segments) ? t.segments : [];
          if (!segments.length) continue;
          for (const [i, seg] of segments.entries()) items.push({ id: `${d.user_day}#${i + 1}`, day: d.user_day, ...seg, label: `${d.user_day} · segment ${i + 1}` });
        }
        for (const session of manual.data ?? []) {
          if (settled.has(session.id)) continue;
          items.push({ id: `${session.user_day}#${session.id}`, session_id: session.id, day: session.user_day,
            started_at: session.started_at, ended_at: session.ended_at, sport_mode: session.sport_mode,
            source: "manual", calculation_pending: true, load_delta: null,
            label: `${session.user_day} · ${clockIn(session.started_at, ctx.tz)}→${clockIn(session.ended_at, ctx.tz)}` });
        }
        return record("find.sport_session", { ok: true, data: { items, count: items.length } });
      }
      case "sleep_night": {
        // #28 · the window this night publishes, and — when the user has corrected it —
        // the band's own window beside it, so the answer can say which one it is reading.
        const { data, error } = await db.from("sleep_nights")
          .select("user_day, total_minutes, sleep_start, wake_at, corrected_start, corrected_at, raw")
          .eq("user_id", userId).gte("user_day", r.from).lte("user_day", r.to)
          .order("user_day", { ascending: false }).limit(limit(raw));
        if (error) return { ok: false } as Err;
        const { data: scores } = await db.from("night_score").select("user_day, score")
          .eq("user_id", userId).gte("user_day", r.from).lte("user_day", r.to);
        const scoreOf = new Map((scores ?? []).map((n) => [n.user_day, n.score]));
        const items = (data ?? []).map((n) => {
          const recorded = (n.raw ?? {}) as Record<string, unknown>;
          return {
            id: n.user_day, day: n.user_day,
            start: clockIn(n.sleep_start, ctx.tz), end: clockIn(n.wake_at, ctx.tz),
            start_at: n.sleep_start, end_at: n.wake_at,
            minutes: n.total_minutes, score: scoreOf.get(n.user_day) ?? null,
            source: recorded.source ?? "device",
            corrected: n.corrected_start != null, corrected_at: n.corrected_at ?? null,
            ...(n.corrected_start != null
              ? { band_start: clockIn(recorded.recorded_start as string, ctx.tz), band_end: clockIn(recorded.recorded_end as string, ctx.tz) }
              : {}),
            label: `${n.user_day} · ${clockIn(n.sleep_start, ctx.tz)}→${clockIn(n.wake_at, ctx.tz)}${n.corrected_start != null ? " · corrected" : ""}`,
          };
        });
        return record("find.sleep_night", { ok: true, data: { items, count: items.length } });
      }
      case "band_setting": return phone?.auto_monitor ? { ok: true, data: { items: phone.auto_monitor } } : notOnPhone("band_setting");
      case "hr_alarm": return phone?.hr_alarm ? { ok: true, data: phone.hr_alarm } : notOnPhone("hr_alarm");
      case "sync_cadence": return phone?.sync_cadence != null ? { ok: true, data: { minutes: phone.sync_cadence } } : notOnPhone("sync_cadence");
      case "notification": return phone?.notifications ? { ok: true, data: phone.notifications } : notOnPhone("notification");
      case "haptics": return phone?.haptics != null ? { ok: true, data: { on: phone.haptics } } : notOnPhone("haptics");
      case "screen": return phone?.screen ? { ok: true, data: phone.screen } : { ok: true, data: null };
      case "chat_session": return phone?.chat_sessions ? { ok: true, data: { items: phone.chat_sessions } } : notOnPhone("chat_session");
      default: return { ok: false, say: `find ${entity} is not implemented.` };
    }
  };

  return {
    [READ_TOOL]: tool({
      description: "Read one health metric over an inclusive user-day range (metric id from find metric). Day grains align missing days as null; tick grains are bucketed by the server. Give two ids in metrics to compare them on aligned days (differences and, with ≥7 overlapping days, correlation; never causation). Wrist-reported calories are not the product burn.",
      parameters: z.object({
        metric: z.any().optional().describe("a metric id, e.g. bodyBattery / nightHRV / weight / intakeKcal"),
        metrics: z.any().optional().describe("two metric ids to compare, e.g. [\"sleepMinutes\",\"bodyBattery\"]"),
        from: z.any().optional().describe("YYYY-MM-DD; defaults to the turn's day"),
        to: z.any().optional().describe("YYYY-MM-DD"),
        bucketMinutes: z.any().optional().describe("5–120, tick metrics only"),
      }),
      // `run` returns the legacy tool's own promise; there is nothing here to await.
      execute: (raw) => {
        let list: unknown = raw.metrics;
        if (typeof list === "string" && /^\s*\[/.test(list)) { try { list = JSON.parse(list); } catch { /* keep */ } }
        const ids = (Array.isArray(list) ? list : typeof list === "string" ? list.split(/[,，\s]+/) : []).map((x) => String(x).trim()).filter(Boolean);
        const r = range(raw);
        if (ids.length >= 2) return run("metric.compare", { left: ids[0], right: ids[1], from: r.from, to: r.to });
        const metric = String(raw.metric ?? ids[0] ?? "").trim();
        if (!metric) return { ok: false, say: "read needs metric (one id) or metrics (two ids). Call find metric for the catalog." };
        const bucket = raw.bucketMinutes != null && Number.isFinite(Number(raw.bucketMinutes)) ? Math.max(5, Math.min(120, Number(raw.bucketMinutes))) : undefined;
        return run("data.read", { metric, from: r.from, to: r.to, ...(bucket ? { bucketMinutes: bucket } : {}) });
      },
    }),
    [FIND_TOOL]: tool({
      description: findDescription(),
      parameters: z.object({
        entity: z.coerce.string().describe(FIND_ENTITIES.join(" / ")),
        id: z.any().optional(),
        day: z.any().optional().describe("YYYY-MM-DD, today, yesterday"),
        from: z.any().optional(), to: z.any().optional(),
        query: z.any().optional().describe("text to match, e.g. a dish name"),
        slot: z.any().optional(), kind: z.any().optional(), limit: z.any().optional(),
      }),
      execute: (raw) => find(raw ?? {}),
    }),
  };
}
