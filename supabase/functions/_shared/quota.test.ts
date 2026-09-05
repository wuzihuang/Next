import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  AI_DAILY_GRANT,
  AI_QUOTA_CAP,
  availableQuota,
  consumeQuota,
  type QuotaState,
} from "./quota.ts";

function state(remaining: number, settledDay: string): QuotaState {
  return { remaining, settledDay };
}

Deno.test("a new account starts the day with ten turns", () => {
  assertEquals(availableQuota(null, "2026-09-05"), AI_DAILY_GRANT);
  const first = consumeQuota(null, "2026-09-05");
  assertEquals(first.allowed, true);
  assertEquals(first.next, state(9, "2026-09-05"));
});

Deno.test("the tenth same-day turn is allowed and the eleventh is refused", () => {
  let current: QuotaState | null = null;
  for (let n = 0; n < 10; n++) {
    const step = consumeQuota(current, "2026-09-05");
    assertEquals(step.allowed, true);
    current = step.next;
  }
  assertEquals(current, state(0, "2026-09-05"));
  const eleventh = consumeQuota(current, "2026-09-05");
  assertEquals(eleventh.allowed, false);
  assertEquals(eleventh.next, state(0, "2026-09-05"));
});

Deno.test("unused turns roll into the next day without a cron job", () => {
  const afterFive = consumeQuota(state(5, "2026-09-05"), "2026-09-06");
  assertEquals(afterFive.allowed, true);
  assertEquals(afterFive.next, state(14, "2026-09-06"));
});

Deno.test("unused balance never exceeds twenty", () => {
  const afterIdle = consumeQuota(state(10, "2026-08-01"), "2026-09-05");
  assertEquals(afterIdle.allowed, true);
  assertEquals(afterIdle.next.remaining, AI_QUOTA_CAP - 1);
  assertEquals(afterIdle.next.settledDay, "2026-09-05");
  assertEquals(availableQuota(state(10, "2026-08-01"), "2026-09-05"), AI_QUOTA_CAP);
});

Deno.test("a day of zero remaining still grants ten the next morning", () => {
  const nextDay = consumeQuota(state(0, "2026-09-05"), "2026-09-06");
  assertEquals(nextDay.allowed, true);
  assertEquals(nextDay.next, state(9, "2026-09-06"));
});
