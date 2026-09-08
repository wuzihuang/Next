// ADR 0020 · the user day is local midnight → midnight, and this is the third copy of
// that rule (Postgres has nb.user_day_bounds, the phone has UserDay). It was the only
// copy with no test, and it is the one whose failure mode db.ts itself warns about: a
// day key off by one names a day with no row, every read tool comes back empty, and the
// turn reads as a model problem rather than a calendar problem.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { userDayKey } from "./db.ts";
import { dayBounds, dayOf } from "./calendar.ts";

const SH = "Asia/Shanghai";

Deno.test("the small hours belong to the day the clock shows", () => {
  assertEquals(userDayKey(SH, new Date("2026-09-07T18:30:00Z")), "2026-09-08"); // 02:30 local
  assertEquals(dayOf("2026-09-07T18:30:00Z", SH), "2026-09-08");
});

Deno.test("an evening instant stays on its own day", () => {
  assertEquals(userDayKey(SH, new Date("2026-09-07T14:00:00Z")), "2026-09-07"); // 22:00 local
  assertEquals(dayOf("2026-09-07T14:00:00Z", SH), "2026-09-07");
});

Deno.test("a UTC date west of Greenwich is not the user's day", () => {
  // 2026-09-07T02:00Z is still the 6th in Los Angeles; slicing the ISO string would
  // have named the 7th and asked the ledger about a day nobody has lived yet.
  assertEquals(userDayKey("America/Los_Angeles", new Date("2026-09-07T02:00:00Z")), "2026-09-06");
});

Deno.test("bounds open and close on local midnight", () => {
  const { start, end } = dayBounds("2026-09-07", SH);
  assertEquals(start.toISOString(), "2026-09-06T16:00:00.000Z");
  assertEquals(end.toISOString(), "2026-09-07T16:00:00.000Z");
});

Deno.test("the three helpers agree on the same instant", () => {
  const instant = "2026-09-07T19:45:00Z"; // 03:45 local on the 8th
  const key = dayOf(instant, SH);
  assertEquals(key, userDayKey(SH, new Date(instant)));
  const { start, end } = dayBounds(key, SH);
  const at = new Date(instant);
  assertEquals(at >= start && at < end, true);
});
