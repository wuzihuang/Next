import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { compareMetrics } from "./metric-compare.ts";
import type { Ctx } from "./sources.ts";
function context(count: number): Ctx {
  const rows = Array.from(
    { length: count },
    (_, i) => ({
      user_day: `2026-09-0${i + 1}`,
      reserve_score: 10 + i * 2,
      training_load: 1 + i,
      day_fuel: { kcal_in: 100 + i * 10, kcal_out: 150 + i * 10 },
    }),
  );
  const db = {
    rpc: () => Promise.resolve({ data: [], error: null }),
    from() {
      const q = {
        select() {
          return q;
        },
        eq() {
          return q;
        },
        gte() {
          return q;
        },
        lte() {
          return q;
        },
        order() {
          return q;
        },
        range() {
          return Promise.resolve({ data: rows, error: null });
        },
      };
      return q;
    },
  };
  return {
    db: db as unknown as Ctx["db"],
    userId: "u",
    dayKey: "2026-09-07",
    tz: "UTC",
  };
}
Deno.test("server comparison aligns observed days and reports correlation without causal claim", async () => {
  const result = await compareMetrics(context(7), {
    left: "bodyBattery",
    right: "trainingLoad",
    from: "2026-09-01",
    to: "2026-09-07",
  });
  if (!result.ok) throw Error("failed");
  assertEquals(result.data.alignedDays, 7);
  assertEquals(result.data.association.pearsonR, 1);
  assertEquals(result.data.difference, null);
});
Deno.test("insufficient overlap suppresses association but compatible units retain measured difference", async () => {
  const result = await compareMetrics(context(3), {
    left: "intakeKcal",
    right: "burnKcal",
    from: "2026-09-01",
    to: "2026-09-07",
  });
  if (!result.ok) throw Error("failed");
  assertEquals(result.data.association.pearsonR, null);
  assertEquals(result.data.association.reason, "insufficient_overlap");
  assertEquals(result.data.difference?.mean, -50);
});
