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
