// docs/plans/2026-09-09-ai-tool-surface.md · the entity table behind `find` / `write` / `do`.
//
// Four operative tools replace the eight read tools and eleven phone tools: `find` reads
// records and state, `read` reads metric series, `write` changes any entity, `do` runs a
// verb or navigates. What the model learns is this table — entity × op × fields — not a
// list of names. It is the single source for the tool descriptions, the prompt section
// and the phone's dispatch vocabulary.
//
// ⚠️ Nothing here may reject (see phone-tools.ts): every parameter is loose, every value
// is normalized in `execute()`, and a value that cannot be rescued becomes one sentence
// the model can act on. Ids are never invented: they come from a `find` result, from the
// device state that rides with the turn, or from a `match` the server resolves.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { normalizeDays, normalizeSlot, normalizeTime } from "./normalize.ts";
import { SEED_MEAL_VERSION } from "./db.ts";
import { addDays } from "./calendar.ts";

export type Op = "create" | "update" | "delete" | "restore";
export type Where = "phone" | "server";

export interface EntityDef {
  /// One line for the model: what the entity is and what `find` returns.
  find: string;
  /// Per op: the fields line for the model. Absent op = not writable.
  ops: Partial<Record<Op, string>>;
  /// Which side runs the write.
  where: Where;
  /// `match` keys the server can resolve into an id.
  match?: string[];
}

export const ENTITIES: Record<string, EntityDef> = {
  meal: {
    find: "meals of a day or range: id, slot, name, kcal, protein_g, carb_g, fat_g, at, editable (7 days); plus open_slots of the day. find keys: day | from+to, slot, query.",
    ops: {
      create: "name, kcal, protein_g?, carb_g?, fat_g?, slot?, day?, at? — omit all to save this turn's meal.estimate draft",
      update: "any of name, kcal, protein_g, carb_g, fat_g, slot, at (the day cannot change)",
      delete: "id or match",
      restore: "id of a meal deleted this session",
    },
    where: "phone", match: ["day", "slot", "query"],
  },
  day: {
    find: "one user day: training load, body battery, fuel in/out/target/remaining, open and logged slots, direction, the call. find key: day.",
    ops: { update: "fasted: true — marks today fasted and clears its meals" },
    where: "phone",
  },
  weigh_in: {
    find: "weigh-ins in a range: id, kg, source, at. find keys: day | from+to.",
    ops: { create: "weight, unit? (kg | lb), at?", delete: "id or match" },
    where: "phone", match: ["day"],
  },
  measurement: {
    find: "body scans and balance checks in a range: id, kind (body_scan | balance_check), at, key values. find keys: from+to, kind.",
    ops: {},
    where: "server",
  },
  alarm: {
    find: "band alarms: id, time, days (0=Sunday), enabled, label. Already in source_data.availability.device.alarms.",
    ops: {
      create: "time (HH:MM), days? (0–6, phrases like weekdays), label?",
      update: "id or match, then any of enabled, time, days, label",
      delete: "id or match",
    },
    where: "phone", match: ["time", "label"],
  },
  band_setting: {
    find: "automatic measurement slots on the band: slot, on, interval_min, allowed intervals.",
    ops: { update: "slot (heart_rate | blood_pressure | meal_response | stress | blood_oxygen | temperature | lorentz | hrv | sleep | blood_components), on?, interval_min?" },
    where: "phone",
  },
  hr_alarm: {
    find: "the band's heart-rate alarm: on, low, high.",
    ops: { update: "on, low?, high?" },
    where: "phone",
  },
  sync_cadence: {
    find: "how often this phone reads the band: minutes.",
    ops: { update: "minutes (5 | 10 | 15 | 30 | 60)" },
    where: "phone",
  },
  profile: {
    find: "name, sex, birth year, height_cm, weight_kg, goal (CUT | RECOMP | BULK), units, language, timezone.",
    ops: { update: "any of name, goal, units (metric | imperial), language (en | zh), height_cm, birth_date, sex" },
    where: "phone",
  },
  notification: {
    find: "notification switches: morning, training, meals, wrap, energy, band, quiet; and system permission.",
    ops: { update: "kind, on" },
    where: "phone",
  },
  haptics: {
    find: "the phone's haptic feedback (vibration of the phone, not the band): on/off.",
    ops: { update: "on" },
    where: "phone",
  },
  plan: {
    find: "the day's advice: title, summary, numbered tasks. find key: day.",
    ops: {},
    where: "server",
  },
  memory: {
    find: "what the system remembers: summary and dated facts (index, text, at).",
    ops: { create: "text — one stable fact", delete: "index | query | all: true" },
    where: "server",
  },
  sleep_night: {
    find: "recorded nights in a range: day, start, end (local clock), minutes, score, corrected, and the band's own window when a correction stands. find keys: day | from+to.",
    ops: {
      create: "day (wake date), start and end as local HH:MM. Backfill a missing night within 30 days; real observations are recovered automatically, unmeasured stages stay unknown",
      update: "day, then start and end as local clock times (HH:MM) — the night's own start and end; or clear: true to drop a correction and give the band its window back",
    },
    where: "phone",
  },
  sport_session: {
    find: "recorded and backfilled training sessions per day: day, start, minutes, peak, load, data coverage. find keys: day | from+to.",
    ops: { create: "day (start date), start and end as local HH:MM, mode? (sport). Backfill a completed session within 30 days, end earlier than start means next day. Reuses measured data and recalculates load without double counting; missing measurements stay unknown" },
    where: "phone",
  },
  chat_session: {
    find: "chat sessions saved on this phone: id, title, updated_at.",
    ops: { create: "—", delete: "id | all: true" },
    where: "phone",
  },
  device: {
    find: "band identity, battery, firmware, capabilities and sync state.",
    ops: {},
    where: "server",
  },
  screen: {
    find: "what the panel shows now: type, title, whether a food plate is on the record.",
    ops: { delete: "— clears the panel" },
    where: "phone",
  },
  metric: {
    find: "the catalog of metric ids `read` accepts, with units, grain and coverage.",
    ops: {},
    where: "server",
  },
};

export const ENTITY_NAMES = Object.keys(ENTITIES);
export const FIND_ENTITIES = ENTITY_NAMES;
export const WRITE_ENTITIES = ENTITY_NAMES.filter((n) => Object.keys(ENTITIES[n].ops).length > 0);

/// Confirm is fixed here by (entity, op), never chosen by the model. A delete is always
/// confirmed with the record named; settings that are cheap to reverse are not.
export function confirmFor(entity: string, op: Op, fields: Record<string, unknown>): boolean {
  switch (entity) {
    case "meal": return op !== "restore" && op !== "create";
    case "day": return true;
    case "weigh_in": return true;
    case "alarm": return true;
    case "band_setting": return true;
    // #28 · a corrected night moves the sleep score and the night's charge with it.
    case "sleep_night": return true;
    case "sport_session": return true;
    case "hr_alarm": return true;
    case "profile": return ["height_cm", "birth_date", "sex"].some((k) => fields[k] != null);
    case "memory": return fields.all === true;
    case "chat_session": return op === "delete";
    default: return false;
  }
}

// ---------------------------------------------------------------- normalizers

const num = (v: unknown): number | null => {
  if (v == null || v === "") return null;
  const n = Number(String(v).replace(/[^\d.\-]/g, ""));
  return Number.isFinite(n) ? n : null;
};
const int = (v: unknown): number | null => { const n = num(v); return n == null ? null : Math.round(n); };
const str = (v: unknown): string | undefined => {
  if (v == null) return undefined;
  const s = String(v).trim();
  return s.length ? s : undefined;
};
const bool = (v: unknown): boolean | null => {
  if (typeof v === "boolean") return v;
  const s = String(v ?? "").trim().toLowerCase();
  if (["true", "1", "on", "yes", "开", "打开", "开启", "enable", "enabled"].includes(s)) return true;
  if (["false", "0", "off", "no", "关", "关闭", "disable", "disabled"].includes(s)) return false;
  return null;
};

/// "today" / "yesterday" / "今天" / "昨天" / "前天" / YYYY-MM-DD → YYYY-MM-DD, relative to the turn's day.
export function normalizeDay(raw: unknown, today: string): string | null {
  if (raw == null || raw === "") return null;
  const s = String(raw).trim().toLowerCase();
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  if (["today", "今天", "今日"].includes(s)) return today;
  if (["yesterday", "昨天"].includes(s)) return addDays(today, -1);
  if (["前天", "day before yesterday"].includes(s)) return addDays(today, -2);
  const m = s.match(/^(\d{1,2})[/-](\d{1,2})$/);
  if (m) return `${today.slice(0, 4)}-${m[1].padStart(2, "0")}-${m[2].padStart(2, "0")}`;
  return null;
}

const GOAL_WORDS: Record<string, string> = {
  cut: "CUT", endurance: "CUT", 减脂: "CUT", 耐力: "CUT", 减重: "CUT",
  recomp: "RECOMP", 塑形: "RECOMP", 重组: "RECOMP",
  bulk: "BULK", strength: "BULK", 增肌: "BULK", 力量: "BULK",
};
const SLOT_KINDS: Record<string, string> = {
  heart_rate: "heartRate", heartrate: "heartRate", heart: "heartRate", 心率: "heartRate",
  blood_pressure: "bloodPressure", bloodpressure: "bloodPressure", 血压: "bloodPressure",
  meal_response: "bloodGlucose", response: "bloodGlucose", blood_glucose: "bloodGlucose", 进餐反应: "bloodGlucose", 血糖: "bloodGlucose",
  stress: "stress", 压力: "stress",
  blood_oxygen: "bloodOxygen", spo2: "bloodOxygen", oxygen: "bloodOxygen", 血氧: "bloodOxygen",
  temperature: "temperature", temp: "temperature", 体温: "temperature",
  lorentz: "lorentz",
  hrv: "hrv",
  sleep: "scientificSleep", scientific_sleep: "scientificSleep", 睡眠: "scientificSleep",
  blood_components: "bloodComponents", 血液成分: "bloodComponents",
};
const NOTIFY_KINDS = ["morning", "training", "meals", "wrap", "energy", "band", "quiet"];
const NOTIFY_WORDS: Record<string, string> = {
  morning: "morning", 早晨: "morning", 早上: "morning",
  training: "training", 训练: "training", workout: "training",
  meals: "meals", meal: "meals", 吃饭: "meals", 餐: "meals", 饮食: "meals",
  wrap: "wrap", daily: "wrap", 收束: "wrap", 总结: "wrap",
  energy: "energy", reserve: "energy", battery: "energy", 电量: "energy",
  band: "band", device: "band", 手环: "band",
  quiet: "quiet", dnd: "quiet", 免打扰: "quiet",
};

export type Normalized = { ok: true; args: Record<string, unknown> } | { ok: false; say: string };

/// Clean `write` arguments, or one sentence. `today` is the turn's user day.
export function normalizeWrite(raw: Record<string, unknown>, today: string): Normalized & { entity?: string; op?: Op } {
  const entity = String(raw.entity ?? "").trim().toLowerCase().replace(/[-\s]/g, "_");
  const def = ENTITIES[entity];
  if (!def) return { ok: false, say: `"${raw.entity}" is not an entity. Use one of: ${WRITE_ENTITIES.join(", ")}.` };
  const opRaw = String(raw.op ?? "").trim().toLowerCase();
  const op = ({ add: "create", log: "create", new: "create", create: "create", set: "update", edit: "update", change: "update", update: "update", toggle: "update", remove: "delete", delete: "delete", clear: "delete", undelete: "restore", restore: "restore" } as Record<string, Op>)[opRaw];
  if (!op || !def.ops[op]) {
    return { ok: false, say: `${entity} supports: ${Object.keys(def.ops).join(", ") || "no writes"}. Use one of those as op.` };
  }
  const fields = (raw.fields && typeof raw.fields === "object" && !Array.isArray(raw.fields) ? raw.fields : parseObject(raw.fields)) as Record<string, unknown>;
  const match = (raw.match && typeof raw.match === "object" && !Array.isArray(raw.match) ? raw.match : parseObject(raw.match)) as Record<string, unknown>;
  const id = str(raw.id) ?? str(fields.id) ?? str(match.id);
  const out: Record<string, unknown> = { entity, op };
  if (id) out.id = id.slice(0, 80);
  const needsTarget = op !== "create" && !(entity === "day" || entity === "screen" || entity === "haptics" || entity === "sync_cadence" || entity === "hr_alarm" || entity === "profile" || entity === "notification" || entity === "band_setting" || entity === "sleep_night" || (entity === "memory" && (match.all === true || fields.all === true || fields.query != null || fields.index != null)) || (entity === "chat_session" && (fields.all === true || match.all === true)));
  const cleanMatch: Record<string, unknown> = {};
  for (const key of def.match ?? []) {
    const v = key === "day" ? normalizeDay(match[key] ?? match.date, today) : str(match[key]);
    if (v != null) cleanMatch[key] = v;
  }
  if (entity === "meal" && cleanMatch.slot) cleanMatch.slot = normalizeSlot(cleanMatch.slot) ?? cleanMatch.slot;
  if (entity === "alarm" && cleanMatch.time) cleanMatch.time = normalizeTime(cleanMatch.time) ?? cleanMatch.time;
  if (needsTarget && !id && Object.keys(cleanMatch).length === 0) {
    return { ok: false, say: `${op} ${entity} needs an id from a find result${def.match ? ` or a match with ${def.match.join(" / ")}` : ""}.` };
  }
  if (Object.keys(cleanMatch).length) out.match = cleanMatch;

  const f: Record<string, unknown> = {};
  if (entity === "sleep_night" || entity === "sport_session") {
    const day = normalizeDay(fields.day ?? fields.date ?? match.day, today);
    if (day) {
      const parsed = new Date(`${day}T00:00:00Z`);
      if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== day) {
        return { ok: false, say: "Use a valid calendar date as YYYY-MM-DD." };
      }
      if (day > today || day < addDays(today, -30)) {
        return { ok: false, say: "Sleep and sport records must be within the past 30 days, including today. Future records cannot be saved." };
      }
    }
  }
  switch (entity) {
    case "meal": {
      const name = str(fields.name) ?? str(fields.text) ?? str(fields.dish);
      const kcal = num(fields.kcal);
      if (name) f.name = name.slice(0, 200);
      if (kcal != null) {
        if (kcal <= 0 || kcal > 100000) return { ok: false, say: "kcal must be a positive number of calories." };
        f.kcal = kcal;
      }
      for (const k of ["protein_g", "carb_g", "fat_g"]) { const v = num(fields[k]); if (v != null && v >= 0 && v <= 100000) f[k] = v; }
      const slot = normalizeSlot(fields.slot); if (slot) f.slot = slot;
      const day = normalizeDay(fields.day ?? fields.date, today); if (day) f.day = day;
      const at = normalizeTime(fields.at ?? fields.time); if (at) f.at = at;
      if (op === "update" && Object.keys(f).length === 0) return { ok: false, say: "update meal needs at least one field: name, kcal, protein_g, carb_g, fat_g, slot, at." };
      if (op === "create" && (name || kcal != null) && !(name && kcal != null)) return { ok: false, say: "create meal needs both name and kcal, or no fields at all to save this turn's meal.estimate draft." };
      break;
    }
    case "day": {
      const fasted = bool(fields.fasted);
      if (fasted !== true) return { ok: false, say: "update day only supports fasted: true." };
      f.fasted = true;
      f.day = normalizeDay(fields.day ?? match.day, today) ?? today;
      break;
    }
    case "weigh_in": {
      if (op === "create") {
        const w = num(fields.weight ?? fields.kg ?? fields.weight_kg);
        if (w == null) return { ok: false, say: "create weigh_in needs weight." };
        const unit = String(fields.unit ?? (fields.lb != null ? "lb" : "kg")).toLowerCase();
        const kg = unit.startsWith("lb") || unit.startsWith("pound") || unit === "磅" ? w * 0.45359237 : w;
        if (kg < 20 || kg > 300) return { ok: false, say: "weight must be between 20 and 300 kg (44–661 lb)." };
        f.weight_kg = Math.round(kg * 10) / 10;
        const at = normalizeTime(fields.at ?? fields.time); if (at) f.at = at;
        const day = normalizeDay(fields.day ?? fields.date, today); if (day) f.day = day;
      }
      break;
    }
    case "alarm": {
      const time = normalizeTime(fields.time);
      if (fields.time != null && !time) return { ok: false, say: `"${fields.time}" is not a time. Use HH:MM on a 24-hour clock, e.g. "07:00".` };
      if (op === "create" && !time) return { ok: false, say: "create alarm needs time as HH:MM." };
      if (time) f.time = time;
      if (fields.days != null) f.days = normalizeDays(fields.days);
      else if (op === "create") f.days = [];
      const label = str(fields.label); if (label) f.label = label.slice(0, 20);
      const on = bool(fields.enabled ?? fields.on); if (on != null) f.enabled = on;
      if (op === "update" && Object.keys(f).length === 0) return { ok: false, say: "update alarm needs at least one of enabled, time, days, label." };
      break;
    }
    case "band_setting": {
      const key = String(fields.slot ?? fields.kind ?? "").trim().toLowerCase().replace(/[\s-]/g, "_");
      const kind = SLOT_KINDS[key] ?? Object.entries(SLOT_KINDS).find(([w]) => key.includes(w))?.[1];
      if (!kind) return { ok: false, say: `slot must be one of: ${[...new Set(Object.values(SLOT_KINDS))].join(", ")}.` };
      f.slot = kind;
      const on = bool(fields.on ?? fields.enabled); if (on != null) f.on = on;
      const interval = int(fields.interval_min ?? fields.interval ?? fields.minutes); if (interval != null && interval >= 0) f.interval_min = interval;
      if (f.on == null && f.interval_min == null) return { ok: false, say: "update band_setting needs on or interval_min." };
      break;
    }
    case "sleep_night": {
      const day = normalizeDay(fields.day ?? fields.date ?? match.day, today);
      if (!day) return { ok: false, say: `${op} sleep_night needs day: "yesterday", "today" or YYYY-MM-DD. A night is filed under the day it was woken on.` };
      f.day = day;
      if (bool(fields.clear ?? fields.reset) === true) {
        if (op !== "update") return { ok: false, say: "clear is only supported when updating an existing sleep_night." };
        f.clear = true; break;
      }
      const start = normalizeTime(fields.start ?? fields.sleep_start ?? fields.from);
      const end = normalizeTime(fields.end ?? fields.wake_at ?? fields.wake ?? fields.to);
      if (!start || !end) return { ok: false, say: `${op} sleep_night needs start and end as local clock times, e.g. start "23:30", end "07:00".` };
      if (start === end) return { ok: false, say: "start and end cannot be the same time." };
      f.start = start; f.end = end;
      break;
    }
    case "sport_session": {
      const day = normalizeDay(fields.day ?? fields.date ?? match.day, today);
      if (!day) return { ok: false, say: "create sport_session needs day (the date the session started)." };
      const start = normalizeTime(fields.start ?? fields.from);
      const end = normalizeTime(fields.end ?? fields.to);
      if (!start || !end || start === end) return { ok: false, say: "create sport_session needs distinct start and end as local HH:MM. Clarify ambiguous morning/evening times before writing." };
      f.day = day; f.start = start; f.end = end;
      f.mode = normalizeSportMode(fields.mode ?? fields.sport);
      break;
    }
    case "hr_alarm": {
      const on = bool(fields.on ?? fields.enabled); if (on != null) f.on = on;
      const low = int(fields.low); if (low != null) f.low = low;
      const high = int(fields.high); if (high != null) f.high = high;
      if (f.on == null && f.low == null && f.high == null) return { ok: false, say: "update hr_alarm needs on, low or high." };
      break;
    }
    case "sync_cadence": {
      const minutes = int(fields.minutes ?? fields.interval_min);
      if (!minutes || ![5, 10, 15, 30, 60].includes(minutes)) return { ok: false, say: "minutes must be 5, 10, 15, 30 or 60." };
      f.minutes = minutes;
      break;
    }
    case "profile": {
      const name = str(fields.name ?? fields.display_name); if (name) f.name = name.slice(0, 40);
      if (fields.goal != null) {
        const g = String(fields.goal).trim().toLowerCase();
        const goal = GOAL_WORDS[g] ?? Object.entries(GOAL_WORDS).find(([w]) => g.includes(w))?.[1] ?? (["CUT", "RECOMP", "BULK"].includes(g.toUpperCase()) ? g.toUpperCase() : undefined);
        if (!goal) return { ok: false, say: "goal must be CUT, RECOMP or BULK." };
        f.goal = goal;
      }
      if (fields.units != null) {
        const u = String(fields.units).toLowerCase();
        f.units = /imperial|lb|pound|ft|磅/.test(u) ? "imperial" : "metric";
      }
      if ((fields.language ?? fields.locale) != null) {
        const l = String(fields.language ?? fields.locale).toLowerCase();
        f.language = /zh|chin|中文|中/.test(l) ? "zh" : "en";
      }
      const h = num(fields.height_cm ?? fields.height); if (h != null) { if (h < 100 || h > 250) return { ok: false, say: "height_cm must be between 100 and 250." }; f.height_cm = Math.round(h * 10) / 10; }
      const birth = str(fields.birth_date ?? fields.birthday); if (birth) { if (!/^\d{4}-\d{2}-\d{2}$/.test(birth)) return { ok: false, say: "birth_date must be YYYY-MM-DD." }; f.birth_date = birth; }
      if (fields.sex != null) {
        const s = String(fields.sex).toLowerCase();
        f.sex = /^(m|male|man|男)/.test(s) ? "male" : /^(f|female|woman|女)/.test(s) ? "female" : undefined;
        if (!f.sex) return { ok: false, say: "sex must be male or female." };
      }
      if (Object.keys(f).length === 0) return { ok: false, say: "update profile needs at least one of name, goal, units, language, height_cm, birth_date, sex." };
      break;
    }
    case "notification": {
      const key = String(fields.kind ?? fields.type ?? "").trim().toLowerCase();
      const kind = NOTIFY_KINDS.includes(key) ? key : NOTIFY_WORDS[key] ?? Object.entries(NOTIFY_WORDS).find(([w]) => key.includes(w))?.[1];
      if (!kind) return { ok: false, say: `kind must be one of: ${NOTIFY_KINDS.join(", ")}.` };
      const on = bool(fields.on ?? fields.enabled);
      if (on == null) return { ok: false, say: "update notification needs on: true or false." };
      f.kind = kind; f.on = on;
      break;
    }
    case "haptics": {
      const on = bool(fields.on ?? fields.enabled);
      if (on == null) return { ok: false, say: "update haptics needs on: true or false." };
      f.on = on;
      break;
    }
    case "memory": {
      if (op === "create") {
        const text = str(fields.text ?? fields.fact);
        if (!text) return { ok: false, say: "create memory needs text: one stable fact about the person." };
        f.text = text.slice(0, 160);
      } else {
        if (fields.all === true || match.all === true) f.all = true;
        const index = int(fields.index ?? match.index); if (index != null) f.index = index;
        const query = str(fields.query ?? match.query); if (query) f.query = query;
        if (!f.all && f.index == null && !f.query) return { ok: false, say: "delete memory needs index, query or all: true." };
      }
      break;
    }
    case "chat_session": {
      if (op === "delete" && (fields.all === true || match.all === true)) f.all = true;
      break;
    }
    case "screen": break;
  }
  out.fields = f;
  return { ok: true, args: out, entity, op };
}

function parseObject(v: unknown): Record<string, unknown> {
  if (typeof v !== "string") return {};
  try { const o = JSON.parse(v); return o && typeof o === "object" && !Array.isArray(o) ? o : {}; } catch { return {}; }
}

// ---------------------------------------------------------------- match resolution

export type Candidate = { id: string; label: string };
export type Resolution = { ok: true; id: string; label: string } | { ok: false; code: "NOT_FOUND" | "AMBIGUOUS"; say: string; candidates?: Candidate[] };

type DeviceAlarms = { id: string; time: string; days: number[]; enabled: boolean; label?: string }[] | undefined;

/// Turn a `match` into one id, on the server, before the phone sees the call. Zero hits and
/// several hits are both sentences; the phone only ever receives an id.
export async function resolveMatch(
  entity: string, match: Record<string, unknown>, ctx: { db: SupabaseClient; userId: string; dayKey: string; tz?: string; locale?: string },
  alarms: DeviceAlarms,
): Promise<Resolution> {
  let candidates: Candidate[] = [];
  const zh = String(ctx.locale ?? "").startsWith("zh");
  const slotWord = (s: unknown) => zh ? ({ BREAKFAST: "早餐", LUNCH: "午餐", DINNER: "晚餐", SNACK: "加餐" } as Record<string, string>)[String(s)] ?? String(s) : String(s);
  const clock = (iso: string | null | undefined) => clockIn(iso, ctx.tz ?? "UTC");
  switch (entity) {
    case "meal": {
      const day = (match.day as string | undefined) ?? ctx.dayKey;
      let q = ctx.db.from("meals").select("id, slot, text_input, kcal, logged_at").eq("user_id", ctx.userId)
        .eq("user_day", day).is("deleted_at", null).neq("model_version", SEED_MEAL_VERSION);
      if (match.slot) q = q.eq("slot", String(match.slot));
      const { data, error } = await q.order("logged_at");
      if (error) return { ok: false, code: "NOT_FOUND", say: "The meal list could not be read. Try find meal first." };
      let rows = data ?? [];
      if (match.query) {
        const needle = String(match.query).toLowerCase();
        const tokens = needle.split(/[\s,，、]+/).filter(Boolean);
        const hit = rows.filter((r) => { const t = String(r.text_input ?? "").toLowerCase(); return t.includes(needle) || tokens.some((k) => t.includes(k)); });
        if (hit.length) rows = hit;
        else rows = [];
      }
      candidates = rows.map((r) => ({ id: r.id, label: `${clock(r.logged_at)} · ${slotWord(r.slot)} · ${r.text_input} · ${r.kcal ?? "——"} kcal` }));
      break;
    }
    case "weigh_in": {
      const day = (match.day as string | undefined) ?? ctx.dayKey;
      const { data, error } = await ctx.db.from("weigh_ins").select("id, weight_kg, measured_at, source").eq("user_id", ctx.userId)
        .gte("measured_at", `${day}T00:00:00Z`).lt("measured_at", `${addDays(day, 1)}T00:00:00Z`).order("measured_at");
      if (error) return { ok: false, code: "NOT_FOUND", say: "Weigh-ins could not be read." };
      const sourceWord = (x: unknown) => zh ? ({ manual: "手动", health: "Apple 健康", band: "手环" } as Record<string, string>)[String(x)] ?? String(x) : String(x);
      candidates = (data ?? []).map((r) => ({ id: r.id, label: `${day} ${clock(r.measured_at)} · ${r.weight_kg} kg · ${sourceWord(r.source)}` }));
      break;
    }
    case "alarm": {
      const list = alarms ?? [];
      candidates = list
        .filter((a) => (!match.time || a.time === match.time) && (!match.label || String(a.label ?? "").toLowerCase().includes(String(match.label).toLowerCase())))
        .map((a) => ({ id: a.id, label: `${a.time} · ${a.days.length ? a.days.join(",") : "once"}${a.label ? ` · ${a.label}` : ""}` }));
      break;
    }
    default:
      return { ok: false, code: "NOT_FOUND", say: `${entity} has no match keys; use an id from find.` };
  }
  if (candidates.length === 1) return { ok: true, id: candidates[0].id, label: candidates[0].label };
  if (candidates.length === 0) return { ok: false, code: "NOT_FOUND", say: `No ${entity} matches ${JSON.stringify(match)}. Do not invent one; tell the user nothing matched or call find ${entity}.` };
  return { ok: false, code: "AMBIGUOUS", say: `${candidates.length} ${entity}s match. Call write again with one id, or ask which: ${candidates.map((c) => `${c.id.slice(0, 8)}… = ${c.label}`).join("; ")}.`, candidates };
}

/// HH:MM on the user's own clock, never a UTC "Z" the confirm dialog would print.
export function clockIn(iso: string | null | undefined, tz: string): string {
  if (!iso) return "--:--";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "--:--";
  try {
    return new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", minute: "2-digit", hour12: false }).format(d);
  } catch {
    return `${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")}Z`;
  }
}

// ---------------------------------------------------------------- `do`

export const PAGES = [
  "home", "home.vitals", "training", "fuel", "bodyBattery", "composition", "profile", "measurements",
  "device", "device.battery", "device.autoMonitor", "sportMode", "chat", "plan", "aiMemory",
  "vitals.sleep", "vitals.heart", "vitals.stress", "vitals.temp", "vitals.steps", "vitals.distance", "vitals.active", "vitals.hrv", "vitals.response",
] as const;
export const SHEETS = [
  "weighIn", "profileEdit", "goal", "units", "language", "notifications", "appleHealth",
  "bandAlarms", "findHoop", "bandAutoMonitor", "syncCadence", "feedback", "about", "privacy", "plusMenu",
  // Opened only; the last tap stays with the user.
  "deleteAccount", "signOut", "unbind", "disconnect", "firmware",
] as const;
export const WINDOWS = ["DAY", "WEEK", "MONTH"] as const;
const PAGE_ALIASES: Record<string, string> = {
  sleep: "vitals.sleep", heart: "vitals.heart", stress: "vitals.stress", steps: "vitals.steps", hrv: "vitals.hrv",
  battery: "bodyBattery", body_battery: "bodyBattery", bodybattery: "bodyBattery", calories: "fuel", food: "fuel", meals: "fuel",
  settings: "profile", me: "profile", memory: "aiMemory", coach: "chat", advice: "plan", suggestions: "plan",
  band: "device", hoop: "device", vitals: "home.vitals", page2: "home.vitals", alarms: "sheet:bandAlarms", weigh: "sheet:weighIn",
  首页: "home", 训练: "training", 饮食: "fuel", 身体电量: "bodyBattery", 体成分: "composition", 我的: "profile", 设备: "device", 手环: "device", 建议: "plan", 记忆: "aiMemory", 聊天: "chat", 睡眠: "vitals.sleep", 心率: "vitals.heart", 压力: "vitals.stress",
};

export const ACTIONS: Record<string, { params: string; confirm: boolean; codes: string[] }> = {
  "device.find": { params: "stop?: true", confirm: false, codes: ["BAND_DISCONNECTED", "BAND_ERROR"] },
  "device.sync": { params: "—", confirm: false, codes: ["BAND_DISCONNECTED", "BUSY", "SYNC_PARTIAL"] },
  "sport.start": { params: "mode (any catalogued sport, e.g. run / outdoor cycle / yoga / swim)", confirm: true, codes: ["SESSION_ACTIVE", "BAND_DISCONNECTED", "BAND_ERROR"] },
  "sport.stop": { params: "—", confirm: true, codes: ["NO_SESSION"] },
  "measure.start": { params: "kind (balance_check | body_scan | heart_rate). SpO2, temperature and blood pressure have no on-demand measurement: the band samples them automatically (SpO2 overnight); read them with read instead", confirm: false, codes: ["UNSUPPORTED", "BAND_DISCONNECTED", "ABANDONED", "BUSY"] },
  "plan.refresh": { params: "—", confirm: false, codes: ["CONSENT_REQUIRED"] },
  "panel.confirm": { params: "— saves the food draft the panel is showing", confirm: true, codes: ["NO_DRAFT", "FASTED_DAY"] },
  "panel.dismiss": { params: "—", confirm: false, codes: [] },
  "app.open": { params: `page (${PAGES.join(" | ")}), window? (DAY | WEEK | MONTH), day? (YYYY-MM-DD), sheet? (${SHEETS.join(" | ")}), session? (chat id)`, confirm: false, codes: ["UNKNOWN_PAGE"] },
  "app.back": { params: "—", confirm: false, codes: [] },
  "app.home": { params: "—", confirm: false, codes: [] },
  "chat.new": { params: "—", confirm: false, codes: [] },
  "undo": { params: "— reverses the last write this session made", confirm: false, codes: ["NOTHING_TO_UNDO"] },
};
export const ACTION_NAMES = Object.keys(ACTIONS);
/// Actions whose ok:true backs a "started / stopped / saved" sentence.
export const WRITE_ACTIONS = new Set(["sport.start", "sport.stop", "panel.confirm", "undo", "plan.refresh"]);

const SPORT_WORDS: [RegExp, string][] = [
  [/indoor\s*run|treadmill|室内跑/, "Indoor run"], [/run|jog|跑/, "Outdoor run"],
  [/indoor\s*walk|室内走/, "Indoor walk"], [/walk|散步|走路|步行/, "Outdoor walk"],
  [/hik|徒步|爬山|登山/, "Hiking"], [/stationary|spin|动感单车/, "Stationary bike"], [/cycl|bike|ride|骑/, "Outdoor cycle"],
  [/ellip|椭圆/, "Elliptical"], [/row|划船/, "Rowing machine"], [/swim|游泳/, "Swim"], [/yoga|瑜伽/, "Yoga"],
  [/jump\s*rope|skip|跳绳/, "Jump rope"], [/basket|篮球/, "Basketball"], [/football|soccer|足球/, "Football"],
  [/badminton|羽毛球/, "Badminton"], [/tennis|网球/, "Tennis"], [/table\s*tennis|ping|乒乓/, "Table tennis"],
  [/hiit/, "HIIT"], [/lift|weight|strength|gym|力量|举铁|撸铁/, "Weightlifting"], [/squat|深蹲/, "Squat training"],
  [/dance|跳舞/, "Dance"], [/box|拳击/, "Boxing"], [/climb|攀岩/, "Rock climbing"], [/stair|爬楼/, "Stair climb"],
  [/ski|滑雪/, "Ski"], [/aerobic|有氧/, "Aerobics"], [/fitness|健身/, "Fitness"],
];
export function normalizeSportMode(raw: unknown): string {
  const s = String(raw ?? "").trim().toLowerCase();
  if (!s) return "Common";
  for (const [re, name] of SPORT_WORDS) if (re.test(s)) return name;
  return s.length > 1 ? s.charAt(0).toUpperCase() + s.slice(1) : "Common";
}

const MEASURE_KINDS: Record<string, string> = {
  balance_check: "balance_check", balance: "balance_check", ecg: "balance_check", 平衡: "balance_check",
  body_scan: "body_scan", body_composition: "body_scan", scan: "body_scan", composition: "body_scan", 体成分: "body_scan", 体脂: "body_scan",
  heart_rate: "heart_rate", heart: "heart_rate", hr: "heart_rate", 心率: "heart_rate",
  blood_oxygen: "blood_oxygen", spo2: "blood_oxygen", oxygen: "blood_oxygen", 血氧: "blood_oxygen",
  temperature: "temperature", temp: "temperature", 体温: "temperature",
  blood_pressure: "blood_pressure", bp: "blood_pressure", 血压: "blood_pressure",
};

export function normalizeDo(raw: Record<string, unknown>, today: string): Normalized & { action?: string } {
  const action = String(raw.action ?? "").trim().toLowerCase().replace(/\s+/g, "");
  const known = ACTIONS[action] ? action : ACTION_NAMES.find((n) => n.replace(".", "") === action.replace(".", ""));
  if (!known) return { ok: false, say: `"${raw.action}" is not an action. Use one of: ${ACTION_NAMES.join(", ")}.` };
  const args: Record<string, unknown> = { action: known };
  const p = (raw.params && typeof raw.params === "object" ? raw.params : parseObject(raw.params)) as Record<string, unknown>;
  const get = (k: string) => raw[k] ?? p[k];
  switch (known) {
    case "device.find": if (bool(get("stop")) === true) args.stop = true; break;
    case "sport.start": args.mode = normalizeSportMode(get("mode") ?? get("sport")); break;
    case "measure.start": {
      const k = String(get("kind") ?? get("type") ?? "").trim().toLowerCase().replace(/[\s-]/g, "_");
      const kind = MEASURE_KINDS[k] ?? Object.entries(MEASURE_KINDS).find(([w]) => k.includes(w))?.[1];
      if (!kind) return { ok: false, say: `kind must be one of: balance_check, body_scan, heart_rate.` };
      // The band has no on-demand SpO2 / temperature / blood-pressure measurement: those are
      // automatic samples. Say so instead of opening a screen that measures something else.
      if (["blood_oxygen", "temperature", "blood_pressure"].includes(kind)) {
        return { ok: false, say: `${kind} cannot be measured on demand; the band samples it automatically (SpO2 overnight). Answer with read (bloodOxygen / skinTemp) or explain there is no manual measurement.` };
      }
      args.kind = kind;
      break;
    }
    case "app.open": {
      const pageRaw = String(get("page") ?? get("target") ?? "").trim();
      const sheetRaw = str(get("sheet"));
      const windowRaw = str(get("window") ?? get("range"));
      const dayRaw = get("day") ?? get("date");
      const session = str(get("session"));
      let page = resolvePage(pageRaw);
      let sheet = sheetRaw ? resolveSheet(sheetRaw) : undefined;
      if (page?.startsWith("sheet:")) { sheet = page.slice(6); page = undefined; }
      if (sheetRaw && !sheet) return { ok: false, say: `"${sheetRaw}" is not a sheet. Use one of: ${SHEETS.join(", ")}.` };
      if (pageRaw && !page && !sheet) return { ok: false, say: `"${pageRaw}" is not a page. Use one of: ${PAGES.join(", ")}.` };
      if (!page && !sheet && !windowRaw) return { ok: false, say: `app.open needs page, sheet or window.` };
      if (page) args.page = page;
      if (sheet) args.sheet = sheet;
      if (windowRaw) {
        const w = windowRaw.toUpperCase().replace(/^(今天|日|天|today)$/i, "DAY").replace(/^(本周|周|week|7d)$/i, "WEEK").replace(/^(本月|月|month|30d)$/i, "MONTH");
        if (!(WINDOWS as readonly string[]).includes(w)) return { ok: false, say: "window must be DAY, WEEK or MONTH." };
        args.window = w;
      }
      const day = normalizeDay(dayRaw, today); if (day) args.day = day;
      if (session) args.session = session.slice(0, 80);
      break;
    }
    default: break;
  }
  return { ok: true, args, action: known };
}

function resolvePage(raw: string): string | undefined {
  if (!raw) return undefined;
  const s = raw.trim();
  const exact = PAGES.find((p) => p.toLowerCase() === s.toLowerCase());
  if (exact) return exact;
  const alias = PAGE_ALIASES[s.toLowerCase()] ?? PAGE_ALIASES[s];
  if (alias) return alias;
  if (/^vitals[./]/i.test(s)) { const m = s.slice(7).toLowerCase(); return PAGES.find((p) => p === `vitals.${m}`); }
  return undefined;
}
function resolveSheet(raw: string): string | undefined {
  const s = raw.trim().toLowerCase().replace(/[\s_-]/g, "");
  return SHEETS.find((x) => x.toLowerCase() === s);
}

// ---------------------------------------------------------------- prompt text

/// The entity table as the model reads it. One line per entity; ≤ 30 lines in all.
export function entityPrompt(): string {
  const rows = ENTITY_NAMES.map((n) => {
    const d = ENTITIES[n];
    const ops = Object.entries(d.ops).map(([op, fields]) => `${op}{${fields}}`).join(" · ");
    return `- ${n} · find: ${d.find}${ops ? `\n  write: ${ops}` : ""}`;
  });
  const acts = ACTION_NAMES.map((a) => `${a}{${ACTIONS[a].params}}`).join(" · ");
  return `ENTITIES (find / write)\n${rows.join("\n")}\n\nACTIONS (do)\n${acts}`;
}

export function findDescription(): string {
  return `Find records or state by entity. entity: ${FIND_ENTITIES.join(" | ")}. Optional id, day, from, to, query, kind, slot, limit. Returns items with id and label; use those ids in write. Personal entities need consent and may report LOCAL_UPLOADS_PENDING.`;
}
export function writeDescription(): string {
  return `Create, update, delete or restore one record or setting. entity: ${WRITE_ENTITIES.join(" | ")}. op: create | update | delete | restore. Target by id (from find or device state) or match {${[...new Set(ENTITY_NAMES.flatMap((n) => ENTITIES[n].match ?? []))].join(", ")}}. fields per entity are listed in ENTITIES. Runs on the phone (some entities on the server); a confirm is fixed per entity and op. Returns ok / code / data.record / undo. Only ok:true means it happened.`;
}
export function doDescription(): string {
  return `Run one action on the phone: ${ACTION_NAMES.join(" | ")}. Parameters are listed in ACTIONS. Returns ok / code / data. sport.start, sport.stop and panel.confirm wait for the user's tap.`;
}
