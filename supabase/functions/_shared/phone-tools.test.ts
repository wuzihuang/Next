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
  const bad = normalizePhoneArgs("device.alarm.set", { time: "sometime" });
  assertEquals(bad.ok, false);
  assert(!bad.ok && bad.say.includes("HH:MM"), JSON.stringify(bad));
  const page = normalizePhoneArgs("app.open", { page: "settings" });
  assertEquals(page.ok, false);
  assert(!page.ok && page.say.includes("fuel"), JSON.stringify(page));
});

Deno.test("clean arguments reach the phone in the shape the band needs", () => {
  const alarm = normalizePhoneArgs("device.alarm.set", { time: "7:5", days: "工作日", label: "x".repeat(40) });
  assert(alarm.ok);
  assertEquals(alarm.args.time, "07:05");
  assertEquals(alarm.args.days, [1, 2, 3, 4, 5]);
  assertEquals(String(alarm.args.label).length, 20);
  const open = normalizePhoneArgs("app.open", { page: "FUEL" });
  assert(open.ok);
  assertEquals(open.args.page, "fuel");
  const meal = normalizePhoneArgs("meal.log", { slot: "午饭" });
  assert(meal.ok);
  assertEquals(meal.args.slot, "LUNCH");
});
