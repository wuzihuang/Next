import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  normalizeDays, normalizePhoneArgs, normalizeSlot, normalizeSport, normalizeTime, PHONE_TOOLS,
} from "./phone-tools.ts";

// ADR 0018 · a tool parameter that rejects kills the turn, and the panel falls to the
// battery frame because the model typed "7:00" instead of "07:00". Nothing here throws.

Deno.test("no phone tool parameter can reject what the model actually sends", () => {
  const junk: Record<string, unknown> = {
    time: 700, days: "weekdays", label: 5, alarm_id: 3, sport: "Cycling", slot: "午餐", page: "FUEL",
  };
  for (const tool of PHONE_TOOLS) {
    const parsed = tool.parameters.safeParse(junk);
    assert(parsed.success, `${tool.name} rejected ${JSON.stringify(junk)}`);
  }
});

Deno.test("times are read the way a person writes them", () => {
  for (const [raw, want] of [["07:00", "07:00"], ["7:00", "07:00"], ["7", "07:00"], ["23:59", "23:59"],
                             ["7点", "07:00"], ["7：30", "07:30"], [700, "07:00"]] as [unknown, string][]) {
    assertEquals(normalizeTime(raw), want, String(raw));
  }
  for (const raw of ["25:00", "07:60", "morning", "", null]) assertEquals(normalizeTime(raw), null, String(raw));
});

Deno.test("days arrive as numbers, names, a list or a phrase", () => {
  assertEquals(normalizeDays([1, 2, 3]), [1, 2, 3]);
  assertEquals(normalizeDays(["1", "MON", "sat"]), [1, 6]);
  assertEquals(normalizeDays("1,2,3"), [1, 2, 3]);
  assertEquals(normalizeDays(["Mon", "Tue", "Wed", "Thu", "Fri"]), [1, 2, 3, 4, 5]);
  assertEquals(normalizeDays(["周一", "周三", "周日"]), [0, 1, 3]);
  assertEquals(normalizeDays("每天"), [0, 1, 2, 3, 4, 5, 6]);
  assertEquals(normalizeDays(undefined), []);
  assertEquals(normalizeDays(["nonsense"]), []);
});

// ⚠️ Production, 2026-09-06: the screen said Monday to Friday and the band was handed
// Tuesday, Wednesday and Thursday. 「工作日」 ends in 日; a per-character pass read the
// phrase as its last character.
Deno.test("a weekday phrase is read as a phrase, in either language and either shape", () => {
  for (const raw of ["weekdays", "工作日", ["工作日"], "周一到周五", "周一至周五", ["weekday"], "Mon-Fri"]) {
    assertEquals(normalizeDays(raw), [1, 2, 3, 4, 5], JSON.stringify(raw));
  }
  for (const raw of ["周末", ["weekend"]]) assertEquals(normalizeDays(raw), [0, 6], JSON.stringify(raw));
  // ⚠️ Production, 2026-09-06: {"days":"[1, 2, 3, 4, 5]"} — the array as its own JSON text.
  // Splitting it on commas dropped "[1" and "5]" and set the alarm for Tue/Wed/Thu.
  assertEquals(normalizeDays("[1, 2, 3, 4, 5]"), [1, 2, 3, 4, 5]);
  assertEquals(normalizeDays('["MON","FRI"]'), [1, 5]);
  assertEquals(normalizeDays("[0]"), [0]);
  // A bare 日 still means Sunday when it stands alone or carries its prefix.
  assertEquals(normalizeDays(["日"]), [0]);
  assertEquals(normalizeDays(["星期日"]), [0]);
});

Deno.test("a sport or a slot said in either language lands on the enum", () => {
  assertEquals(normalizeSport("cycling"), "ride");
  assertEquals(normalizeSport("骑行"), "ride");
  assertEquals(normalizeSport("Running"), "run");
  assertEquals(normalizeSport("kayak"), "other");
  assertEquals(normalizeSlot("午餐"), "LUNCH");
  assertEquals(normalizeSlot("Dinner"), "DINNER");
  // No slot is a legal answer: the phone picks by the clock.
  assertEquals(normalizeSlot(""), undefined);
  assertEquals(normalizeSlot("brunch"), undefined);
});

Deno.test("an argument that cannot be rescued comes back as a sentence, not a throw", () => {
  const bad = normalizePhoneArgs("write", { entity: "alarm", op: "create", fields: { time: "sometime" } });
  assertEquals(bad.ok, false);
  assert(!bad.ok && bad.say.includes("HH:MM"), JSON.stringify(bad));
  const page = normalizePhoneArgs("do", { action: "app.open", page: "nowhere" });
  assertEquals(page.ok, false);
  assert(!page.ok && page.say.includes("fuel"), JSON.stringify(page));
  const entity = normalizePhoneArgs("write", { entity: "unicorn", op: "create" });
  assert(!entity.ok && entity.say.includes("meal"), JSON.stringify(entity));
  const target = normalizePhoneArgs("write", { entity: "meal", op: "delete" });
  assert(!target.ok && target.say.includes("match"), JSON.stringify(target));
});

Deno.test("clean arguments reach the phone in the shape the band needs", () => {
  const alarm = normalizePhoneArgs("write", { entity: "alarm", op: "create", fields: { time: "7:5", days: "工作日", label: "x".repeat(40) } });
  assert(alarm.ok);
  const fields = alarm.args.fields as Record<string, unknown>;
  assertEquals(fields.time, "07:05");
  assertEquals(fields.days, [1, 2, 3, 4, 5]);
  assertEquals(String(fields.label).length, 20);
  assertEquals(alarm.confirm, true);
  const open = normalizePhoneArgs("do", { action: "app.open", page: "FUEL" });
  assert(open.ok);
  assertEquals(open.args.page, "fuel");
  assertEquals(open.confirm, false);
  const meal = normalizePhoneArgs("write", { entity: "meal", op: "create", fields: "{}" });
  assert(meal.ok);
  assertEquals(meal.args.fields, {});
});

// docs/plans/2026-09-09-ai-tool-surface.md · "删除我今天吃的猪脚饭" is one call with a match.
Deno.test("a meal delete by match carries the resolved keys and asks for a confirm", () => {
  const del = normalizePhoneArgs("write", { entity: "meal", op: "delete", match: { day: "today", query: "猪脚饭" } }, "2026-09-09");
  assert(del.ok);
  assertEquals(del.args.match, { day: "2026-09-09", query: "猪脚饭" });
  assertEquals(del.confirm, true);
  const move = normalizePhoneArgs("write", { entity: "meal", op: "update", match: { day: "yesterday", slot: "午餐" }, fields: { slot: "晚餐" } }, "2026-09-09");
  assert(move.ok);
  assertEquals(move.args.match, { day: "2026-09-08", slot: "LUNCH" });
  assertEquals((move.args.fields as Record<string, unknown>).slot, "DINNER");
  const fasted = normalizePhoneArgs("write", { entity: "day", op: "update", fields: { fasted: "true" } }, "2026-09-09");
  assert(fasted.ok && fasted.confirm);
  assertEquals(fasted.args.fields, { fasted: true, day: "2026-09-09" });
});

Deno.test("settings, memory and navigation normalize without a confirm", () => {
  const notif = normalizePhoneArgs("write", { entity: "notification", op: "update", fields: { kind: "吃饭", on: "off" } });
  assert(notif.ok && !notif.confirm);
  assertEquals(notif.args.fields, { kind: "meals", on: false });
  const memory = normalizePhoneArgs("write", { entity: "memory", op: "create", fields: { text: "膝盖有旧伤" } });
  assert(memory.ok && !memory.confirm);
  const goal = normalizePhoneArgs("write", { entity: "profile", op: "update", fields: { goal: "增肌" } });
  assert(goal.ok && !goal.confirm);
  assertEquals((goal.args.fields as Record<string, unknown>).goal, "BULK");
  const height = normalizePhoneArgs("write", { entity: "profile", op: "update", fields: { height_cm: "178" } });
  assert(height.ok && height.confirm);
  const week = normalizePhoneArgs("do", { action: "app.open", window: "本周" });
  assert(week.ok);
  assertEquals(week.args.window, "WEEK");
  const sheet = normalizePhoneArgs("do", { action: "app.open", page: "alarms" });
  assert(sheet.ok);
  assertEquals(sheet.args.sheet, "bandAlarms");
  const sport = normalizePhoneArgs("do", { action: "sport.start", mode: "骑车" });
  assert(sport.ok && sport.confirm);
  assertEquals(sport.args.mode, "Outdoor cycle");
  const undo = normalizePhoneArgs("do", { action: "undo" });
  assert(undo.ok && !undo.confirm);
});

// #28 · "把昨晚睡觉时间改成 23:30 到 7:00" is one write, and it is always confirmed:
// the night's score and the charge it fed move with the window.
Deno.test("a corrected night is one confirmed write of two clock times", () => {
  const zh = normalizePhoneArgs("write", {
    entity: "sleep_night", op: "update", fields: { day: "昨天", start: "23:30", end: "7:00" },
  }, "2026-09-10");
  assert(zh.ok && zh.confirm);
  assertEquals(zh.args.fields, { day: "2026-09-09", start: "23:30", end: "07:00" });

  const clear = normalizePhoneArgs("write", {
    entity: "sleep_night", op: "update", fields: { day: "2026-09-08", clear: "true" },
  }, "2026-09-10");
  assert(clear.ok && clear.confirm);
  assertEquals(clear.args.fields, { day: "2026-09-08", clear: true });

  // A night is named by the day it was woken on, and half a window is not a correction.
  const noDay = normalizePhoneArgs("write", { entity: "sleep_night", op: "update", fields: { start: "23:30", end: "07:00" } }, "2026-09-10");
  assert(!noDay.ok);
  const half = normalizePhoneArgs("write", { entity: "sleep_night", op: "update", fields: { day: "today", start: "23:30" } }, "2026-09-10");
  assert(!half.ok);
  const same = normalizePhoneArgs("write", { entity: "sleep_night", op: "update", fields: { day: "today", start: "07:00", end: "7" } }, "2026-09-10");
  assert(!same.ok);
});
