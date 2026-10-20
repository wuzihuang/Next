import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { z } from "npm:zod@3.25.76";
import { addDays } from "../_shared/calendar.ts";
import { SEED_MEAL_VERSION, userDayKey } from "../_shared/db.ts";
import { definitions, METRICS, type Metric, queryMetrics } from "../_shared/metric-query.ts";

export interface Access {
  userId: string;
  clientId: string;
  clientName: string;
  canWrite: boolean;
  timezone: string;
}

export interface ToolContext {
  db: SupabaseClient;
  access: Access;
  now: Date;
  newId: () => string;
}

export type ToolOutcome = { ok: true; data: unknown } | { ok: false; error: string; message: string };

interface ToolDefinition {
  name: string;
  title: string;
  description: string;
  inputSchema: Record<string, unknown>;
  annotations: Record<string, boolean>;
  run: (ctx: ToolContext, args: unknown) => Promise<ToolOutcome>;
}

const READABLE = METRICS.filter((m) => !definitions[m].unsupported) as Metric[];
const Day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const SLOTS = ["BREAKFAST", "LUNCH", "DINNER", "SNACK"] as const;
const MAX_MEAL_DAYS = 31;
const WRITE_DENIED =
  "The person has not allowed this assistant to log meals. They can turn it on in the NextBody app under Profile → AI assistants, or reconnect and tick the meal-logging box.";

const NOTES: Partial<Record<Metric, string>> = {
  trainingLoad: "Daily training load on a 0–21 product scale, settled by the server. Not minutes, not a single workout.",
  bodyBattery: "Body battery reserve, 0–100, settled by the server. A product estimate, not a clinical measure.",
  intakeKcal: "Calories eaten that day from logged meals.",
  burnKcal: "Product burn (resting + measured activity), not the band's raw calorie field.",
  deltaKcal: "Intake minus burn for the day.",
  proteinG: "Protein eaten that day from logged meals, grams.",
  weight: "Each weigh-in, kilograms.",
  nightHRV: "The night's RMSSD over the recorded sleep window, ms. Belongs to the night ending on that day.",
  hrvBaseline: "Personal HRV baseline the body battery compares against, ms.",
  nightRHR: "Resting heart rate during the night ending on that day, bpm.",
  sleepMinutes: "Recorded sleep minutes for the night ending on that morning.",
};

function fail(error: string, message: string): ToolOutcome {
  return { ok: false, error, message };
}

function round(value: number | null | undefined, digits = 1): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  const f = 10 ** digits;
  return Math.round(value * f) / f;
}

function dbFailure(error: { code?: string; message?: string }): ToolOutcome {
  const reason = String(error.message ?? "").slice(0, 120);
  if (error.code === "42501" || error.code === "28000") {
    if (reason.includes("MCP_WRITE_NOT_GRANTED")) return fail("WRITE_NOT_ALLOWED", WRITE_DENIED);
    if (reason.includes("CONSENT_WITHDRAWN")) {
      return fail("CONSENT_WITHDRAWN", "The person has paused data collection in the NextBody app, so nothing can be logged.");
    }
    return fail("NOT_AUTHORIZED", reason || "Not authorized.");
  }
  if (error.code === "P0002") return fail("NOT_FOUND", "No such meal on this account.");
  if (error.code === "23505") return fail("CONFLICT", "This request id was already used for a different meal. Use a new request_id.");
  if (error.code?.startsWith("22") || error.code === "23514") return fail("REJECTED", reason || "The meal was rejected.");
  return fail("UNAVAILABLE", "NextBody could not complete this right now. Try again shortly.");
}

function slotAt(at: Date, timezone: string): (typeof SLOTS)[number] {
  const hour = Number(
    new Intl.DateTimeFormat("en-US", { timeZone: timezone, hour: "numeric", hourCycle: "h23" }).format(at),
  );
  if (hour >= 4 && hour < 11) return "BREAKFAST";
  if (hour >= 11 && hour < 15) return "LUNCH";
  if (hour >= 15 && hour < 21) return "DINNER";
  return "SNACK";
}

function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(to) - Date.parse(from)) / 864e5);
}

async function settleBack(ctx: ToolContext, userDay: string): Promise<boolean> {
  const back = daysBetween(userDay, userDayKey(ctx.access.timezone, ctx.now));
  if (back < 0 || back > 6) return false;
  const { error } = await ctx.db.rpc("settle_now", { p_days: back });
  return !error;
}

type SeriesItem = {
  metric: Metric;
  points: { dayKey: string; value: number | null }[];
  stats: { count: number; mean: number | null; min: number | null; max: number | null; latest: number | null };
  evidence: { unit: string; origin: string; status: string; freshness: string; coverage: { missingDays: string[] | null } };
};

function series(item: SeriesItem): Record<string, unknown> {
  const def = definitions[item.metric];
  return {
    metric: item.metric,
    unit: item.evidence.unit,
    origin: item.evidence.origin,
    status: item.evidence.status,
    freshness: item.evidence.freshness,
    note: NOTES[item.metric] ?? def.says ?? null,
    points: item.points.map((p) => ({ at: p.dayKey, value: round(p.value, 2) })),
    stats: {
      count: item.stats.count,
      mean: round(item.stats.mean, 2),
      min: round(item.stats.min, 2),
      max: round(item.stats.max, 2),
      latest: round(item.stats.latest, 2),
    },
    missingDays: item.evidence.coverage.missingDays,
  };
}

async function readSeries(
  ctx: ToolContext,
  metrics: Metric[],
  from: string,
  to: string,
): Promise<{ ok: true; items: SeriesItem[] } | { ok: false; outcome: ToolOutcome }> {
  const result = await queryMetrics(
    { db: ctx.db, userId: ctx.access.userId, dayKey: to, tz: ctx.access.timezone },
    { metrics, from, to, timezone: ctx.access.timezone },
  );
  if (!result.ok) {
    const recovery = "recovery" in result ? String(result.recovery) : "Check the dates and try again.";
    return { ok: false, outcome: fail(result.error, recovery) };
  }
  return { ok: true, items: result.data as unknown as SeriesItem[] };
}

const ReadMetricsArgs = z.object({
  metrics: z.array(z.enum(READABLE as [Metric, ...Metric[]])).min(1).max(8),
  from: Day,
  to: Day,
}).strict();

async function readMetricsTool(ctx: ToolContext, raw: unknown): Promise<ToolOutcome> {
  const parsed = ReadMetricsArgs.safeParse(raw);
  if (!parsed.success) return fail("INVALID_ARGUMENTS", parsed.error.issues.map((i) => i.message).join("; "));
  const read = await readSeries(ctx, parsed.data.metrics, parsed.data.from, parsed.data.to);
  if (!read.ok) return read.outcome;
  return { ok: true, data: { timezone: ctx.access.timezone, series: read.items.map(series) } };
}

function listMetricsTool(ctx: ToolContext): Promise<ToolOutcome> {
  return Promise.resolve({
    ok: true,
    data: {
      timezone: ctx.access.timezone,
      today: userDayKey(ctx.access.timezone, ctx.now),
      metrics: READABLE.map((m) => ({
        metric: m,
        unit: definitions[m].unit,
        origin: definitions[m].origin,
        grain: definitions[m].grain,
        maxDays: definitions[m].maxDays ?? null,
        note: NOTES[m] ?? definitions[m].says ?? null,
      })),
    },
  });
}

const DayArgs = z.object({ date: Day.optional() }).strict();

async function daySummaryTool(ctx: ToolContext, raw: unknown): Promise<ToolOutcome> {
  const parsed = DayArgs.safeParse(raw ?? {});
  if (!parsed.success) return fail("INVALID_ARGUMENTS", "date must be YYYY-MM-DD.");
  const day = parsed.data.date ?? userDayKey(ctx.access.timezone, ctx.now);
  const groups: Metric[][] = [
    ["trainingLoad", "trainingTarget", "bodyBattery", "activeMinutes", "dayDistance", "wearRun"],
    ["intakeKcal", "burnKcal", "deltaKcal", "proteinG", "sleepScore", "sleepMinutes", "nightHRV", "nightRHR"],
  ];
  const values: Record<string, unknown> = {};
  for (const metrics of groups) {
    const read = await readSeries(ctx, metrics, day, day);
    if (!read.ok) return read.outcome;
    for (const item of read.items) {
      values[item.metric] = {
        value: round(item.stats.latest, 2),
        unit: item.evidence.unit,
        status: item.evidence.status,
      };
    }
  }
  return {
    ok: true,
    data: {
      date: day,
      timezone: ctx.access.timezone,
      values,
      note: "status 'absent' means nothing was recorded or settled — unknown, never zero.",
    },
  };
}

const STAGES: Record<string, string> = { "0": "deep", "1": "light", "2": "rem", "3": "insomnia", "4": "awake" };

async function sleepNightTool(ctx: ToolContext, raw: unknown): Promise<ToolOutcome> {
  const parsed = DayArgs.safeParse(raw ?? {});
  if (!parsed.success) return fail("INVALID_ARGUMENTS", "date must be YYYY-MM-DD.");
  const day = parsed.data.date ?? userDayKey(ctx.access.timezone, ctx.now);
  const [night, score] = await Promise.all([
    ctx.db.from("sleep_nights")
      .select("user_day,sleep_start,wake_at,total_minutes,deep_minutes,light_minutes,wake_count,sleep_line,corrected_start,corrected_end,raw")
      .eq("user_id", ctx.access.userId).eq("user_day", day).maybeSingle(),
    ctx.db.from("night_score")
      .select("score,duration_score,architecture_score,recovery_score,regularity_score,personal_weight,score_version,computed_at")
      .eq("user_id", ctx.access.userId).eq("user_day", day).maybeSingle(),
  ]);
  if (night.error || score.error) return fail("UNAVAILABLE", "Sleep could not be read right now.");
  if (!night.data) {
    return { ok: true, data: { date: day, recorded: false, note: "No night recorded ending on this morning." } };
  }
  const row = night.data as Record<string, unknown>;
  const rawRow = (row.raw ?? {}) as Record<string, unknown>;
  const stages = typeof row.sleep_line === "string" && row.sleep_line
    ? row.sleep_line.split(",").map((part) => {
      const [stage, minutes] = part.split(":");
      return { stage: STAGES[stage] ?? `stage_${stage}`, minutes: Number(minutes) };
    })
    : null;
  const reported = rawRow.source === "user_reported";
  return {
    ok: true,
    data: {
      date: day,
      recorded: true,
      source: reported ? "user_reported" : "band",
      corrected: row.corrected_start != null,
      sleepStart: row.sleep_start ?? null,
      wakeAt: row.wake_at ?? null,
      totalMinutes: row.total_minutes ?? null,
      deepMinutes: row.deep_minutes ?? null,
      lightMinutes: row.light_minutes ?? null,
      wakeCount: row.wake_count ?? null,
      stageLine: stages,
      score: score.data ?? null,
      notes: [
        "stageLine is the band's own ordered sequence of stages; a night without 'rem' was not measuring REM, it does not mean no REM sleep.",
        reported ? "This night was reported by the person; stages were not measured." : null,
        "The sleep score is a 0–100 product score, not a clinical result.",
      ].filter((n) => n !== null),
    },
  };
}

const ListMealsArgs = z.object({ from: Day.optional(), to: Day.optional() }).strict();

async function listMealsTool(ctx: ToolContext, raw: unknown): Promise<ToolOutcome> {
  const parsed = ListMealsArgs.safeParse(raw ?? {});
  if (!parsed.success) return fail("INVALID_ARGUMENTS", "from/to must be YYYY-MM-DD.");
  const today = userDayKey(ctx.access.timezone, ctx.now);
  const to = parsed.data.to ?? today;
  const from = parsed.data.from ?? addDays(to, -6);
  if (from > to) return fail("INVALID_RANGE", "from must not be after to.");
  if (daysBetween(from, to) >= MAX_MEAL_DAYS) {
    return fail("RANGE_TOO_LARGE", `Ask for at most ${MAX_MEAL_DAYS} days at a time.`);
  }
  const { data, error } = await ctx.db.from("meals")
    .select("id,user_day,slot,logged_at,text_input,portion,kcal,protein_g,carb_g,fat_g,fiber_g,sugar_g,sodium_mg,confidence,meal_group_id,model_version")
    .eq("user_id", ctx.access.userId).is("deleted_at", null)
    .gte("user_day", from).lte("user_day", to)
    .order("logged_at").limit(500);
  if (error) return fail("UNAVAILABLE", "Meals could not be read right now.");
  const meals = (data ?? []).filter((m) => m.model_version !== SEED_MEAL_VERSION).map((m) => ({
    id: m.id,
    day: m.user_day,
    slot: m.slot,
    loggedAt: m.logged_at,
    name: m.text_input,
    portion: m.portion ?? null,
    kcal: m.kcal,
    proteinG: m.protein_g,
    carbG: m.carb_g,
    fatG: m.fat_g,
    fiberG: m.fiber_g,
    sugarG: m.sugar_g,
    sodiumMg: m.sodium_mg,
    confidence: m.confidence,
    plateId: m.meal_group_id ?? null,
  }));
  return {
    ok: true,
    data: {
      from,
      to,
      timezone: ctx.access.timezone,
      meals,
      note: "null nutrients are unknown, not zero. Rows sharing plateId were logged together as one plate.",
    },
  };
}

const Nutrient = z.number().finite().min(0).max(100000);
const MealItem = z.object({
  name: z.string().trim().min(1).max(200),
  portion: z.string().trim().min(1).max(64).optional(),
  kcal: z.number().finite().min(0).max(10000),
  protein_g: Nutrient,
  carb_g: Nutrient,
  fat_g: Nutrient,
  fiber_g: Nutrient.nullable().optional(),
  sugar_g: Nutrient.nullable().optional(),
  sodium_mg: Nutrient.nullable().optional(),
}).strict();
const LogMealArgs = z.object({
  items: z.array(MealItem).min(1).max(12),
  eaten_at: z.string().max(64).refine((v) => Number.isFinite(Date.parse(v)), "eaten_at must be an ISO 8601 time").optional(),
  slot: z.enum(SLOTS).optional(),
  confidence: z.enum(["LOW", "MEDIUM", "HIGH"]).optional(),
  request_id: z.string().uuid().optional(),
}).strict();

async function logMealTool(ctx: ToolContext, raw: unknown): Promise<ToolOutcome> {
  if (!ctx.access.canWrite) return fail("WRITE_NOT_ALLOWED", WRITE_DENIED);
  const parsed = LogMealArgs.safeParse(raw);
  if (!parsed.success) {
    return fail("INVALID_ARGUMENTS", parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; "));
  }
  const args = parsed.data;
  const eatenAt = args.eaten_at ? new Date(args.eaten_at) : ctx.now;
  if (eatenAt.getTime() > ctx.now.getTime() + 5 * 60_000) {
    return fail("INVALID_ARGUMENTS", "eaten_at is in the future.");
  }
  const tz = ctx.access.timezone;
  const userDay = userDayKey(tz, eatenAt);
  const today = userDayKey(tz, ctx.now);
  if (daysBetween(userDay, today) > 6) {
    return fail("INVALID_ARGUMENTS", "Meals can be logged for today and the previous 6 days only.");
  }
  const slot = args.slot ?? slotAt(eatenAt, tz);
  const source = `mcp:${ctx.access.clientName || ctx.access.clientId}`.slice(0, 256);
  const items = args.items.map((item) => {
    const row: Record<string, unknown> = {
      user_day: userDay,
      slot,
      name: item.name,
      kcal: round(item.kcal),
      protein_g: round(item.protein_g),
      carb_g: round(item.carb_g),
      fat_g: round(item.fat_g),
      confidence: args.confidence ?? "MEDIUM",
      model_version: source,
    };
    // A plate replays only if its items are byte-identical, so a retry without eaten_at
    // must not carry a fresh clock reading; the database stamps it instead.
    if (args.eaten_at) row.logged_at = eatenAt.toISOString();
    if (item.portion) row.portion = item.portion;
    for (const key of ["fiber_g", "sugar_g", "sodium_mg"] as const) {
      const value = item[key];
      if (typeof value === "number") row[key] = round(value);
    }
    return row;
  });
  const groupId = (args.request_id ?? ctx.newId()).toLowerCase();
  const { data, error } = await ctx.db.rpc("apply_meal_plate", { p_group_id: groupId, p_items: items });
  if (error) return dbFailure(error);
  const settled = await settleBack(ctx, userDay);
  const receipt = (data ?? {}) as { meal_ids?: string[]; replay?: boolean };
  return {
    ok: true,
    data: {
      plateId: groupId,
      mealIds: receipt.meal_ids ?? [],
      replay: receipt.replay === true,
      day: userDay,
      slot,
      totalKcal: round(items.reduce((sum, i) => sum + (i.kcal as number), 0)),
      dayTotalsUpdated: settled,
      note: settled
        ? "Logged. The day's intake has been recalculated."
        : "Logged. The day's intake will update at the next sync.",
    },
  };
}

const DeleteMealArgs = z.object({
  meal_id: z.string().uuid().optional(),
  plate_id: z.string().uuid().optional(),
}).strict().refine((v) => Boolean(v.meal_id) !== Boolean(v.plate_id), "Pass exactly one of meal_id or plate_id.");

async function deleteMealTool(ctx: ToolContext, raw: unknown): Promise<ToolOutcome> {
  if (!ctx.access.canWrite) return fail("WRITE_NOT_ALLOWED", WRITE_DENIED);
  const parsed = DeleteMealArgs.safeParse(raw);
  if (!parsed.success) return fail("INVALID_ARGUMENTS", parsed.error.issues.map((i) => i.message).join("; "));
  let query = ctx.db.from("meals").select("id,user_day")
    .eq("user_id", ctx.access.userId).is("deleted_at", null);
  query = parsed.data.meal_id
    ? query.eq("id", parsed.data.meal_id.toLowerCase())
    : query.eq("meal_group_id", parsed.data.plate_id!.toLowerCase());
  const { data: rows, error } = await query.limit(12);
  if (error) return fail("UNAVAILABLE", "Meals could not be read right now.");
  if (!rows?.length) return fail("NOT_FOUND", "No such meal on this account (it may already be deleted).");
  const deleted: string[] = [];
  for (const row of rows) {
    const result = await ctx.db.rpc("apply_meal_operation", {
      p_operation_id: ctx.newId(),
      p_kind: "delete",
      p_meal_id: row.id,
      p_payload: {},
    });
    if (result.error) {
      const outcome = dbFailure(result.error);
      return deleted.length && !outcome.ok
        ? fail(outcome.error, `${outcome.message} ${deleted.length} of ${rows.length} rows were already deleted.`)
        : outcome;
    }
    deleted.push(row.id);
  }
  const settled = await settleBack(ctx, String(rows[0].user_day));
  return { ok: true, data: { deletedMealIds: deleted, day: rows[0].user_day, dayTotalsUpdated: settled } };
}

const metricEnum = { type: "string", enum: READABLE };
const dateProp = { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$" };
const nutrientProp = { type: "number", minimum: 0 };

export const TOOLS: ToolDefinition[] = [
  {
    name: "list_metrics",
    title: "List NextBody metrics",
    description:
      "Lists every metric read_metrics can return, with unit, whether it is measured or derived, and what it means. Also returns the person's timezone and today's date in it. Call this first when unsure which metric to read.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, openWorldHint: false },
    run: (ctx) => listMetricsTool(ctx),
  },
  {
    name: "read_metrics",
    title: "Read metrics over a date range",
    description:
      "Reads up to 8 metrics for an inclusive range of the person's local days (YYYY-MM-DD, at most 366 days). Day-grain metrics return one point per day; weigh-ins, body composition and overnight SpO2 return one point per measurement. A null value or status 'absent' means nothing was recorded — report it as unknown, never as 0. Derived values (training load, body battery, sleep score, calories) are NextBody product estimates, not clinical measurements. status 'stale' means a recalculation is pending.",
    inputSchema: {
      type: "object",
      properties: {
        metrics: { type: "array", items: metricEnum, minItems: 1, maxItems: 8 },
        from: dateProp,
        to: dateProp,
      },
      required: ["metrics", "from", "to"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
    run: readMetricsTool,
  },
  {
    name: "get_day_summary",
    title: "Summarise one day",
    description:
      "One local day at a glance: training load and target, body battery, active minutes, distance, wear run, calories in/out and balance, protein, and the night that ended that morning (sleep score, minutes, night HRV, night resting heart rate). Defaults to today in the person's timezone.",
    inputSchema: { type: "object", properties: { date: dateProp }, additionalProperties: false },
    annotations: { readOnlyHint: true, openWorldHint: false },
    run: daySummaryTool,
  },
  {
    name: "get_sleep_night",
    title: "Read one night of sleep",
    description:
      "The night that ended on the morning of a local day (default today): sleep window, totals, the band's ordered stage line (deep / light / rem / awake), and the settled 0–100 sleep score with its four group scores (duration, architecture, recovery, regularity). Says whether the night was recorded by the band or reported by the person.",
    inputSchema: { type: "object", properties: { date: dateProp }, additionalProperties: false },
    annotations: { readOnlyHint: true, openWorldHint: false },
    run: sleepNightTool,
  },
  {
    name: "list_meals",
    title: "List logged meals",
    description:
      "Meals the person logged between two local days (default: the last 7 days, at most 31). Each row has name, portion, calories, protein/carbs/fat and, when known, fiber/sugar/sodium. Null nutrients are unknown, not zero. Rows with the same plateId were logged together.",
    inputSchema: { type: "object", properties: { from: dateProp, to: dateProp }, additionalProperties: false },
    annotations: { readOnlyHint: true, openWorldHint: false },
    run: listMealsTool,
  },
  {
    name: "log_meal",
    title: "Log a meal",
    description:
      "Logs what the person ate as one plate (1–12 foods) into NextBody, then recalculates that day's intake. You estimate the nutrition: give each food a name, a portion phrase (e.g. '1 bowl', '200 g'), kcal and protein/carbs/fat in grams. Give fiber_g, sugar_g, sodium_mg only when you actually know them; omit them otherwise — never send 0 for unknown. eaten_at defaults to now (ISO 8601 with offset); only today and the previous 6 local days are accepted. slot defaults from the local time (breakfast 04–11, lunch 11–15, dinner 15–21, otherwise snack). Pass a fresh request_id (UUID) and reuse it only when retrying the same call. Confirm the foods and amounts with the person before calling. Requires the person to have allowed meal logging for this assistant.",
    inputSchema: {
      type: "object",
      properties: {
        items: {
          type: "array",
          minItems: 1,
          maxItems: 12,
          items: {
            type: "object",
            properties: {
              name: { type: "string", minLength: 1, maxLength: 200 },
              portion: { type: "string", minLength: 1, maxLength: 64 },
              kcal: { type: "number", minimum: 0, maximum: 10000 },
              protein_g: nutrientProp,
              carb_g: nutrientProp,
              fat_g: nutrientProp,
              fiber_g: nutrientProp,
              sugar_g: nutrientProp,
              sodium_mg: nutrientProp,
            },
            required: ["name", "kcal", "protein_g", "carb_g", "fat_g"],
            additionalProperties: false,
          },
        },
        eaten_at: { type: "string", description: "ISO 8601 time the food was eaten, e.g. 2026-10-18T12:30:00-06:00" },
        slot: { type: "string", enum: SLOTS },
        confidence: { type: "string", enum: ["LOW", "MEDIUM", "HIGH"], description: "How sure you are of the estimate." },
        request_id: { type: "string", format: "uuid" },
      },
      required: ["items"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    run: logMealTool,
  },
  {
    name: "delete_meal",
    title: "Delete a logged meal",
    description:
      "Deletes one logged food (meal_id) or a whole plate (plate_id) from the last 7 local days, then recalculates that day's intake. Get ids from list_meals. Confirm with the person first. Requires the person to have allowed meal logging for this assistant.",
    inputSchema: {
      type: "object",
      properties: {
        meal_id: { type: "string", format: "uuid" },
        plate_id: { type: "string", format: "uuid" },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    run: deleteMealTool,
  },
];
