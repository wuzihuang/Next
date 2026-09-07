// ADR 0018 · phone tools. The model calls them like any tool; the phone runs them.
//
// The edge function cannot reach the band, so a phone tool call suspends the turn: the
// server sends `tool.request`, stores the conversation, closes the stream, and the phone
// resumes the turn with the result under the same Idempotency-Key. Every result is
// `{ ok, code, data }` so the model can say whether the alarm was actually set.
//
// `confirm` is fixed here, not chosen by the model: starting a session, setting an alarm
// and logging a meal wait for a tap on the phone; the rest run at once.

import { z } from "npm:zod@3.25.76";
import { TARGETS } from "./contract.ts";

export const PHONE_PAGES = [...TARGETS, "device", "plan", "sleep", "heart"] as const;

export interface PhoneToolDef {
  name: string;
  description: string;
  parameters: z.ZodTypeAny;
  confirm: boolean;
  /// Codes the phone may return besides OK. Listed in the description so the model can
  /// read a failure without guessing.
  codes: string[];
}

const COMMON_CODES = ["APP_BACKGROUND", "CANCELLED", "TIMEOUT"];
const BAND_CODES = ["BAND_DISCONNECTED", "BAND_ERROR", ...COMMON_CODES];

// ⚠️ Nothing in a tool's parameters may reject. Seen on production twice in one sweep:
// `screen.render.food` with {"kcal":"350"} and `workflow.ready` with a JSON *string* for
// `range` both raised AI_InvalidToolArgumentsError, and the SDK turns that into a dead turn
// — the panel falls to the battery frame because the model quoted a number or typed a
// bracket. So every parameter here is permissive, and `normalizePhoneArgs` below decides:
// it either hands the phone clean arguments or returns a sentence the model can act on.
const loose = z.coerce.string();

/// "7:00" / "7:5" / "7" / "700" / "0700" / "7点30分" → "07:00" … ; anything else → null.
export function normalizeTime(raw: unknown): string | null {
  const s = String(raw ?? "").trim();
  let h: number, min: number, m: RegExpMatchArray | null;
  if ((m = s.match(/^(\d{1,2})\s*[:：.点]\s*(\d{1,2})\s*分?$/))) { h = Number(m[1]); min = Number(m[2]); }
  else if ((m = s.match(/^(\d{1,2})\s*[点时]?$/))) { h = Number(m[1]); min = 0; }
  else if ((m = s.match(/^(\d{3,4})$/))) { h = Number(m[1].slice(0, -2)); min = Number(m[1].slice(-2)); }
  else return null;
  if (h > 23 || min > 59) return null;
  return `${String(h).padStart(2, "0")}:${String(min).padStart(2, "0")}`;
}

const EN_DAYS: Record<string, number> = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };
const ZH_DAYS: Record<string, number> = { "日": 0, "天": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6 };

/// [1,2,3] / ["MON","FRI"] / ["周一","周五"] / "1,2,3" / "工作日" / ["工作日"] → sorted 0–6.
///
/// ⚠️ A phrase has to be read before its characters. 「工作日」 ends in 日, so a per-character
/// pass turned "weekdays" into Sunday, and 「周一到周五」 into Friday alone — the band was
/// handed [2,3,4] while the answer on screen said Monday to Friday. Phrases first, then
/// items, and a Chinese weekday only counts with its 周/星期/礼拜 prefix or standing alone.
export function normalizeDays(raw: unknown): number[] {
  if (raw == null) return [];
  // ⚠️ The model writes an array as its JSON text about as often as an array:
  // {"days":"[1, 2, 3, 4, 5]"} split on commas left "[1" and "5]", which are not numbers,
  // and Monday-to-Friday reached the band as Tuesday-to-Thursday. Parse it, and strip the
  // brackets and quotes off whatever survives.
  let value: unknown = raw;
  if (typeof value === "string" && /^\s*\[/.test(value)) {
    try { value = JSON.parse(value); } catch { /* fall through to splitting */ }
  }
  const items = (Array.isArray(value) ? value.map((x) => String(x ?? "")) : String(value).split(/[,，、;；\s]+/))
    .map((x) => x.replace(/[[\]"'`]/g, "").trim()).filter(Boolean);
  const joined = items.join(",").toLowerCase();
  if (/weekday|工作日|周一到周五|周一至周五|mon\s*-\s*fri/.test(joined)) return [1, 2, 3, 4, 5];
  if (/weekend|周末/.test(joined)) return [0, 6];
  if (/every\s?day|daily|每天|天天|everyday/.test(joined)) return [0, 1, 2, 3, 4, 5, 6];
  const out = new Set<number>();
  for (const item of items) {
    const s = item.toLowerCase();
    if (/^\d+$/.test(s)) { const n = Number(s); if (n >= 0 && n <= 6) out.add(n); continue; }
    const en = Object.entries(EN_DAYS).find(([k]) => s.startsWith(k));
    if (en) { out.add(en[1]); continue; }
    const zh = item.match(/[周星期礼拜]\s*([一二三四五六日天])/) ?? item.match(/^([一二三四五六日天])$/);
    if (zh) out.add(ZH_DAYS[zh[1]]);
  }
  return [...out].sort((a, b) => a - b);
}

const SPORTS = ["run", "walk", "ride", "strength", "other"] as const;
const SPORT_WORDS: Record<string, typeof SPORTS[number]> = {
  run: "run", running: "run", jog: "run", 跑步: "run", 跑: "run",
  walk: "walk", walking: "walk", 散步: "walk", 走路: "walk",
  ride: "ride", cycling: "ride", cycle: "ride", bike: "ride", biking: "ride", 骑行: "ride", 骑车: "ride",
  strength: "strength", lifting: "strength", weights: "strength", gym: "strength", 力量: "strength",
};
export function normalizeSport(raw: unknown): typeof SPORTS[number] {
  const s = String(raw ?? "").trim().toLowerCase();
  if ((SPORTS as readonly string[]).includes(s)) return s as typeof SPORTS[number];
  for (const [word, sport] of Object.entries(SPORT_WORDS)) if (s.includes(word)) return sport;
  return "other";
}

const SLOTS = ["BREAKFAST", "LUNCH", "DINNER", "SNACK"] as const;
const SLOT_WORDS: Record<string, typeof SLOTS[number]> = {
  breakfast: "BREAKFAST", 早餐: "BREAKFAST", 早饭: "BREAKFAST",
  lunch: "LUNCH", 午餐: "LUNCH", 午饭: "LUNCH", 中饭: "LUNCH",
  dinner: "DINNER", supper: "DINNER", 晚餐: "DINNER", 晚饭: "DINNER",
  snack: "SNACK", 加餐: "SNACK", 零食: "SNACK",
};
/// Undefined means "the phone picks by the clock", which is a legal answer.
export function normalizeSlot(raw: unknown): typeof SLOTS[number] | undefined {
  const s = String(raw ?? "").trim();
  if (!s) return undefined;
  const upper = s.toUpperCase();
  if ((SLOTS as readonly string[]).includes(upper)) return upper as typeof SLOTS[number];
  const lower = s.toLowerCase();
  for (const [word, slot] of Object.entries(SLOT_WORDS)) if (lower.includes(word)) return slot;
  return undefined;
}

export const PHONE_TOOLS: PhoneToolDef[] = [
  {
    name: "device.find",
    description: "Make the band vibrate so the user can find it. Only when the user asks where the band is.",
    parameters: z.object({}),
    confirm: false,
    codes: BAND_CODES,
  },
  {
    name: "device.sync",
    description: "Pull the band's latest data to the phone and the cloud now. Use when the user asks to sync or when they say today's numbers look stale. Returns the last synced time; reread the data afterwards if the answer depends on it.",
    parameters: z.object({}),
    confirm: false,
    codes: BAND_CODES,
  },
  {
    name: "device.alarm.set",
    description: "Set an alarm on the band. days is 0–6 (Sunday=0); empty means once. The user confirms on the phone before it is written. Returns the band's alarm list after the write.",
    parameters: z.object({
      time: loose.describe("HH:MM, 24-hour"),
      days: z.any().optional().describe("0–6 with Sunday=0, e.g. [1,2,3,4,5]; omit or [] for once"),
      label: loose.optional(),
    }),
    confirm: true,
    codes: ["ALARM_SLOTS_FULL", "UNSUPPORTED", ...BAND_CODES],
  },
  {
    name: "device.alarm.delete",
    description: "Delete one band alarm by its id from the device state or a previous device.alarm.set result. The user confirms on the phone.",
    parameters: z.object({ alarm_id: loose.describe("the id from device state or a previous set") }),
    confirm: true,
    codes: ["ALARM_NOT_FOUND", ...BAND_CODES],
  },
  {
    name: "sport.start",
    description: "Start a live sport session on the band and phone. The user confirms on the phone. Fails with SESSION_ACTIVE if one is already running.",
    parameters: z.object({ sport: loose.optional().describe(`one of ${SPORTS.join(" / ")}`) }),
    confirm: true,
    codes: ["SESSION_ACTIVE", ...BAND_CODES],
  },
  {
    name: "sport.stop",
    description: "Stop the live sport session that is running. The user confirms on the phone.",
    parameters: z.object({}),
    confirm: true,
    codes: ["NO_SESSION", ...BAND_CODES],
  },
  {
    name: "meal.log",
    description: "Save the meal draft from meal.estimate as a logged meal for the slot. Call meal.estimate first; the user confirms on the phone. Returns the saved meal id.",
    parameters: z.object({ slot: loose.optional().describe(`one of ${SLOTS.join(" / ")}; omit and the phone picks by the clock`) }),
    confirm: true,
    codes: ["ESTIMATE_REQUIRED", "FASTED_DAY", ...COMMON_CODES],
  },
  {
    name: "balance_check.start",
    description: "Open the balance check flow on the phone. The phone reports whether the user completed it.",
    parameters: z.object({}),
    confirm: false,
    codes: ["ABANDONED", ...BAND_CODES],
  },
  {
    name: "body_scan.start",
    description: "Open the body composition scan flow on the phone. The phone reports whether the user completed it.",
    parameters: z.object({}),
    confirm: false,
    codes: ["ABANDONED", ...BAND_CODES],
  },
  {
    name: "app.open",
    description: `Open a page of the app: one of ${PHONE_PAGES.join(" / ")}. Only when the user asks to see or open something.`,
    parameters: z.object({ page: loose.describe(`one of ${PHONE_PAGES.join(" / ")}`) }),
    confirm: false,
    codes: COMMON_CODES,
  },
];

export const PHONE_TOOL_BY_NAME = new Map(PHONE_TOOLS.map((t) => [t.name, t]));

/// Clean arguments for the phone, or one sentence telling the model what to fix. Called in
/// the tool body, where a complaint is a result the model can act on rather than a throw.
export function normalizePhoneArgs(
  name: string,
  args: Record<string, unknown>,
): { ok: true; args: Record<string, unknown> } | { ok: false; say: string } {
  switch (name) {
    case "device.alarm.set": {
      const at = normalizeTime(args.time);
      if (!at) return { ok: false, say: `"${args.time}" is not a time. Call again with time as HH:MM on a 24-hour clock, e.g. "07:00".` };
      return { ok: true, args: { time: at, days: normalizeDays(args.days), ...(args.label ? { label: String(args.label).slice(0, 20) } : {}) } };
    }
    case "device.alarm.delete": {
      const id = String(args.alarm_id ?? "").trim();
      if (!id) return { ok: false, say: "alarm_id is required. Take it from source_data.device.alarms or from a device.alarm.set result." };
      return { ok: true, args: { alarm_id: id.slice(0, 40) } };
    }
    case "sport.start":
      return { ok: true, args: { sport: normalizeSport(args.sport) } };
    case "meal.log": {
      const slot = normalizeSlot(args.slot);
      return { ok: true, args: { ...(slot ? { slot } : {}) } };
    }
    case "app.open": {
      const page = String(args.page ?? "").trim().toLowerCase();
      const match = PHONE_PAGES.find((p) => p.toLowerCase() === page);
      if (!match) return { ok: false, say: `"${args.page}" is not a page. Call again with one of: ${PHONE_PAGES.join(", ")}.` };
      return { ok: true, args: { page: match } };
    }
    default:
      return { ok: true, args: {} };
  }
}

export function phoneToolDescription(t: PhoneToolDef): string {
  return `${t.description} Runs on the phone${t.confirm ? " after the user confirms" : ""}. Result codes: OK / ${t.codes.join(" / ")}.`;
}

/// What the phone sends back with the resumed turn.
export const phoneToolResult = z.object({
  call_id: z.string().min(1).max(80),
  ok: z.boolean(),
  code: z.string().min(1).max(40),
  data: z.record(z.any()).optional(),
  message: z.string().max(200).optional(),
}).strict();

export type PhoneToolResult = z.infer<typeof phoneToolResult>;

/// What the server sends as `tool.request`.
export interface PhoneToolRequest {
  call_id: string;
  name: string;
  args: Record<string, unknown>;
  confirm: boolean;
  /// The turn state expires at this instant; a later resume is TURN_STATE_LOST.
  resume_by: string;
}
