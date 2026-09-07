import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { auditFrame, NumberLedger } from "./ledger.ts";

function frame(sentence: string, data: Record<string, unknown> = {}) {
  return { type: "text", title: "T", sentence, data } as Record<string, unknown>;
}

Deno.test("a month-day date is an axis, not a claim", () => {
  const ledger = new NumberLedger();
  ledger.harvest({ protein_g: 32 }, "meals");
  ledger.seal();
  for (const said of ["9-04 早餐蛋白 32g", "9/5 早餐蛋白 32g", "09-05 早餐蛋白 32g", "12/31 早餐蛋白 32g"]) {
    assertEquals(auditFrame(frame(said), ledger), { ok: true }, said);
  }
});

Deno.test("a numeric range is still audited in full", () => {
  const ledger = new NumberLedger();
  ledger.harvest({ low: 12.5, high: 16.5 }, "range");
  ledger.seal();
  // ⚠️ The date whitelist must not eat the middle of 12.5-16.5 and leave 12 and 5 behind.
  assertEquals(auditFrame(frame("建议范围 12.5-16.5"), ledger), { ok: true });
  const strict = new NumberLedger();
  strict.harvest({ low: 12.5 }, "range");
  strict.seal();
  assertEquals(auditFrame(frame("建议范围 12.5-16.5"), strict), { ok: false, value: 16.5 });
});

Deno.test("a number nobody returned is rejected however it is phrased", () => {
  const ledger = new NumberLedger();
  ledger.harvest({ minutes: 432 }, "sleep");
  ledger.seal();
  assertEquals(auditFrame(frame("睡了 432 分钟"), ledger), { ok: true });
  // The same night said in hours is a conversion, and conversions are not derivations.
  const converted = auditFrame(frame("睡了 7 小时 12 分"), ledger);
  assert(!converted.ok);
});

Deno.test("13-40 is not a date and is audited", () => {
  const ledger = new NumberLedger();
  ledger.seedConstants();
  ledger.seal();
  assertEquals(auditFrame(frame("13-40"), ledger), { ok: false, value: 13 });
});
