import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  assertBindings, bindableMetrics, candidateBindings, catalogVersion, FAST_BINDINGS, FAST_METRICS,
  resolveWindow, type FastBinding,
} from "./chart-selection.ts";
import { SKILL_BY_TYPE } from "./skills.ts";
import { SOURCE_BY_ID } from "./sources.ts";

Deno.test("every admitted binding is a chart and a source that really exist and belong together", () => {
  assertBindings();
  for (const binding of FAST_BINDINGS) {
    const skill = SKILL_BY_TYPE.get(binding.type);
    assert(skill, binding.id);
    assert(skill.sources.includes(binding.source), `${binding.type} does not declare ${binding.source}`);
    assert(SOURCE_BY_ID.has(binding.source), binding.source);
  }
});

Deno.test("a binding that drifts from the registries fails at load", () => {
  const bad = (patch: Partial<FastBinding>): FastBinding[] => [{ ...FAST_BINDINGS[0], ...patch }];
  assertThrows(() => assertBindings(bad({ id: "ring:nope", source: "nope" })));
  // The chart must itself declare the source: a line cannot be filled from a ring's source.
  assertThrows(() => assertBindings(bad({ id: "line:kcal.today", type: "line" })));
  // A rolling source's span may not disagree with the window it is admitted for.
  assertThrows(() => assertBindings([{ ...FAST_BINDINGS.find((b) => b.id === "line:intakeKcal.7d")!, spanDays: 30 }]));
});

Deno.test("the catalogue version changes when the candidates change", () => {
  const before = catalogVersion();
  assertEquals(before, catalogVersion(), "stable for the same catalogue");
  const changed = catalogVersion(FAST_BINDINGS.slice(1));
  assert(before !== changed, "a removed binding must change the version a threshold was tuned against");
});

Deno.test("windows are resolved from the turn's own day; calendar periods are not rolling windows", () => {
  assertEquals(resolveWindow("TODAY", "2026-09-20"), { from: "2026-09-20", to: "2026-09-20", label: "TODAY", spanDays: 1 });
  assertEquals(resolveWindow("YESTERDAY", "2026-09-20"), { from: "2026-09-19", to: "2026-09-19", label: "YESTERDAY", spanDays: 1 });
  assertEquals(resolveWindow("LAST_7_USER_DAYS", "2026-09-20")?.from, "2026-09-14");
  assertEquals(resolveWindow("LAST_30_USER_DAYS", "2026-09-20")?.from, "2026-08-22");
  // The night that ended this morning belongs to the current user day, which is what the
  // sleep sources read. It never becomes a day range of its own.
  assertEquals(resolveWindow("LAST_NIGHT", "2026-09-20"), { from: "2026-09-20", to: "2026-09-20", label: "LAST_NIGHT", spanDays: 1 });
  // "Last week" and "this month" arrive as EXPLICIT_DATE_CANDIDATE, and nothing resolves
  // them: a calendar period is not seven or thirty rolling days.
  assertEquals(resolveWindow("EXPLICIT_DATE_CANDIDATE", "2026-09-20"), null);
  assertEquals(resolveWindow("UNSPECIFIED", "2026-09-20"), null);
  assertEquals(resolveWindow("OTHER_OR_AMBIGUOUS", "2026-09-20"), null);
});

Deno.test("a month boundary and a leap day resolve by real dates", () => {
  assertEquals(resolveWindow("LAST_7_USER_DAYS", "2026-03-03")?.from, "2026-02-25");
  assertEquals(resolveWindow("YESTERDAY", "2026-03-01")?.from, "2026-02-28");
  assertEquals(resolveWindow("YESTERDAY", "2028-03-01")?.from, "2028-02-29");
});

Deno.test("candidates are the bindings that match all three, and an unsupported window has none", () => {
  const today = candidateBindings("intakeKcal", "TODAY", "TARGET_PROGRESS");
  assertEquals(today.map((b) => b.id), ["ring:kcal.today"]);
  // Seven days of weight has no source: weight is .30d and .90d. The request must go to
  // the model rather than be answered over thirty days.
  assertEquals(candidateBindings("weight", "LAST_7_USER_DAYS", "TREND"), []);
  assertEquals(candidateBindings("weight", "LAST_30_USER_DAYS", "TREND").map((b) => b.id), ["line:weight.30d"]);
  // Seven days of sleep has no source at all, in any presentation.
  for (const presentation of ["TREND", "DAILY_COMPARISON", "SCALAR", "NO_PREFERENCE"] as const) {
    assertEquals(candidateBindings("sleepStructure", "LAST_7_USER_DAYS", presentation), []);
  }
  // The presentation picks between two legal charts over the same window.
  assertEquals(candidateBindings("intakeKcal", "LAST_7_USER_DAYS", "TREND").map((b) => b.id), ["line:intakeKcal.7d"]);
  assertEquals(candidateBindings("intakeKcal", "LAST_7_USER_DAYS", "DAILY_COMPARISON").map((b) => b.id), ["days:intakeKcal.7d"]);
  // A 7-day request never lands on a 30-day source.
  for (const binding of candidateBindings("intakeKcal", "LAST_7_USER_DAYS", "TREND")) {
    assertEquals(binding.spanDays, 7);
  }
});

Deno.test("every metric offered to the router can be drawn at least one way", () => {
  const bindable = bindableMetrics();
  for (const metric of Object.keys(FAST_METRICS)) {
    assert(bindable.has(metric as keyof typeof FAST_METRICS), `${metric} has no binding and must not be offered`);
  }
});
