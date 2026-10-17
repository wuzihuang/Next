import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { NumberLedger } from "./ledger.ts";
Deno.test("measurement claim must match value and metric, unit, interval and revision", () => {
  const ledger = new NumberLedger();
  const evidence = {
    id: "e1",
    metric: "intakeKcal",
    unit: "kcal",
    from: "2026-09-03",
    to: "2026-09-04",
  };
  ledger.registerEvidence(evidence, { mean: 1800 });
  assertEquals(ledger.hasClaim({ ...evidence, value: 1800 }), true);
  assertEquals(
    ledger.hasClaim({ ...evidence, metric: "deltaKcal", value: 1800 }),
    false,
  );
  assertEquals(
    ledger.hasClaim({ ...evidence, from: "2026-09-02", value: 1800 }),
    false,
  );
  assertEquals(ledger.hasClaim({ ...evidence, unit: "g", value: 1800 }), false);
  assertEquals(ledger.hasClaim({ ...evidence, id: "old", value: 1800 }), false);
});

Deno.test("a rejected claim names the scope that was read, so the render retry can fix it", () => {
  const ledger = new NumberLedger();
  const evidence = { id: "e1", metric: "sleepScore", unit: "", from: "2026-09-16", to: "2026-09-17" };
  ledger.registerEvidence(evidence, { points: [74, 79] });
  assertEquals(ledger.claimMismatch({ ...evidence, value: 79 }), null);
  const narrowed = ledger.claimMismatch({ ...evidence, from: "2026-09-17", value: 79 })!;
  assertEquals(narrowed.includes('"from":"2026-09-16","to":"2026-09-17"'), true);
  assertEquals(ledger.claimMismatch({ ...evidence, value: 88 })!.startsWith("Value 88"), true);
  assertEquals(ledger.claimMismatch({ ...evidence, id: "old", value: 79 })!.includes('"old"'), true);
});
