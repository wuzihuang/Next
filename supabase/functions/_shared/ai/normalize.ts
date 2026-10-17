// Value normalizers shared by phone-tools.ts and entities.ts. Nothing here throws.

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

