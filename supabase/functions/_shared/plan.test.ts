import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { adviceEvidence, type EvidenceRow } from "./advice-evidence.ts";
import { addDays } from "./calendar.ts";
import { planContext, PlanArgs, validateAdvice, type PlanContext } from "./plan.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";

const today = "2026-09-08", now = new Date("2026-09-08T12:00:00Z");
const days = Array.from({ length: 8 }, (_, i) => ({ user_day: addDays(today, i - 7), training_load: i === 6 ? 18 : i === 7 ? 2 : 9 }));
const sleeps = [{ user_day: today, total_minutes: 354, sleep_start: "2026-09-08T00:00:00Z", wake_at: "2026-09-08T05:54:00Z" }];
const context = (): PlanContext => ({ window: { from: "2026-08-25", to: today, today }, observed_at: now.toISOString(),
  evidence: adviceEvidence(days, sleeps, [], today, now), recent_suggestions: [], failed: [], pending_days: [], instruction: "" });
const suggestion = () => PlanArgs.parse({ title: "Protect recovery", summary: "A shorter night follows heavier load.", tasks: [{
  title: "Ease the hard session", sub: "Keep the next session comfortable enough to talk through, and reassess how you feel after warming up.",
  basis: "09-07 load was 18 versus a personal median of 9; the completed night was 354 min.",
  evidence_ids: ["training_load:2026-09-07", "sleep_minutes:2026-09-08"], reference_ids: ["recovery"],
}] });

Deno.test("advice compares completed load against prior days, excluding today and the evaluated day", () => {
  const evidence = context().evidence;
  const load = evidence.find(e => e.id === "training_load:2026-09-07")!;
  assertEquals(load.comparison, { median: 9, delta: 9, observations: 6, kind: "prior_completed_days" });
  assertEquals(load.context?.completed_day, true);
  assertEquals(evidence.find(e => e.id === "training_load:2026-09-08")?.context?.completed_day, false);
  assertEquals(evidence.find(e => e.id === "training_load:2026-09-08")?.comparison, undefined, "a partial day has no full-day comparison");
  assertEquals(adviceEvidence(days.slice(-3), [], [], today, now)[0].comparison, undefined);
});

Deno.test("training advice receives the same sleep target and recorded session contributions as the app", () => {
  const target = { target: 9.5, lower: 7.5, upper: 11.5, sleep_minutes: 330, recovery_score: 62 };
  const session = { session_id: "session-1", load_delta: 2.7, displayed_delta: 2.7, observed_seconds: 1800 };
  const rows = [{ user_day: today, training_load: 10, daily_training: { evidence: { target, sessions: [session] } } }];
  const load = adviceEvidence(rows, [], [], today, now)[0];
  assertEquals(load.context?.suggested_target, 9.5);
  assertEquals(load.context?.remaining_to_target, 0);
  assertEquals(load.context?.target_basis, target);
  assertEquals(load.context?.recorded_sessions, [session]);
  assertEquals(adviceEvidence([{ user_day: today, training_load: 10 }], [], [], today, now)[0].context?.remaining_to_target, null);
});

Deno.test("advice excludes missing, future and zero sleep and does not infer protein from unlogged food", () => {
  assertEquals(adviceEvidence([], [], [], today, now), []);
  assertEquals(adviceEvidence([], [{ ...sleeps[0], wake_at: "2026-09-08T13:00:00Z" }], [], today, now), []);
  assertEquals(adviceEvidence([], [{ ...sleeps[0], total_minutes: 0 }], [], today, now), []);
  const unlogged = adviceEvidence([{ user_day: today, day_fuel: { intake_state: "UNLOGGED", protein_in_g: 0 } }], [], [], today, now);
  assertEquals(unlogged, []);
  const logged = adviceEvidence([{ user_day: today, day_fuel: { intake_state: "LOGGED", protein_in_g: 52, protein_g: 110 } }], [], [], today, now);
  assertEquals(logged[0].value, 52);
  assertEquals(logged[0].context?.target_g, 110);
  assertEquals(logged[0].context?.recording_is_partial, true);
});

Deno.test("current stress requires repeated recent worn readings, not an old peak or missing zero", () => {
  const ticks: EvidenceRow[] = Array.from({ length: 18 }, (_, i) => ({ ts: new Date(now.getTime() - (18 - i) * 300_000).toISOString(), heart: 64, stress: i < 6 ? 40 : 80 }));
  const stress = adviceEvidence([], [], ticks, today, now)[0];
  assertEquals(stress.metric, "stress");
  assertEquals(stress.value, 80);
  assertEquals(stress.comparison, undefined, "six earlier samples cannot establish a baseline");
  for (const bad of [ticks.slice(0, 6), ticks.slice(-1), ticks.map(r => ({ ...r, stress: 0 })), ticks.map(r => ({ ...r, heart: null }))]) {
    assertEquals(adviceEvidence([], [], bad, today, now), []);
  }
});

Deno.test("reserve freshness follows the observation, not recalculation; assumed anchors are excluded", () => {
  const row = { user_day: today, calculation_as_of: now.toISOString(), reserve_daily: { current_value: 24,
    drain_drivers: { observed_at: "2026-09-08T06:00:00Z", assumed_anchor: false, confidence: "medium" } } };
  const battery = adviceEvidence([row], [], [], today, now)[0];
  assertEquals(battery.observed_at, "2026-09-08T06:00:00Z");
  assertEquals(battery.calculated_at, now.toISOString());
  assertEquals(battery.context?.is_current, false);
  row.reserve_daily.drain_drivers.assumed_anchor = true;
  assertEquals(adviceEvidence([row], [], [], today, now), []);
});

Deno.test("night eligibility and baseline night count survive into advice evidence", () => {
  const night = { hrv: 12, hrv_base: 50, hrv_nights: 1, hrv_eligible: false, hrv_coverage: 0.2 };
  const row = { user_day: today, reserve_daily: { night_inputs: night } };
  assertEquals(adviceEvidence([row], [], [], today, now), []);
  night.hrv_eligible = true; night.hrv_coverage = 0.9;
  const sparse = adviceEvidence([row], [], [], today, now)[0];
  assertEquals(sparse.context?.personal_baseline, null);
  assertEquals(sparse.context?.delta, null);
  assertEquals(sparse.context?.coverage, 0.9);
  night.hrv_nights = 5;
  assertEquals(adviceEvidence([row], [], [], today, now)[0].context?.delta, -38);
});

Deno.test("stress deduplicates sources band-first and requires observations spanning time", () => {
  const instant = { ts: "2026-09-08T11:55:00Z", heart: 64, stress: 85 };
  const duplicates = ["health", "import", "band"].map(src => ({ ...instant, src }));
  assertEquals(adviceEvidence([], [], duplicates, today, now), []);
  const distinct = ["11:45", "11:50", "11:55"].flatMap(time => [
    { ts: `2026-09-08T${time}:00Z`, heart: 64, stress: 85, src: "health" },
    { ts: `2026-09-08T${time}:00Z`, heart: 64, stress: 40, src: "band" },
  ]);
  const stress = adviceEvidence([], [], distinct, today, now)[0];
  assertEquals(stress.value, 40);
  assertEquals(stress.context?.observations, 3);
});

Deno.test("advice accepts fewer than three complete specific suggestions and honest empty output", () => {
  assertEquals(validateAdvice(suggestion(), context()), null);
  const withScale = suggestion(); withScale.tasks[0].basis = "09-07 training load was 18/21.";
  assertEquals(validateAdvice(withScale, context()), null);
  assertEquals(validateAdvice(PlanArgs.parse({ title: "No adjustment", summary: "No current observations support a useful adjustment.", tasks: [] }), context()), null);
});

Deno.test("advice rejects filler, absent evidence, duplicate signals and fabricated numbers anywhere", () => {
  for (const sub of ["Sync data", "同步数据", "Eat three meals", "吃三顿饭", "Work 30 minutes", "Walk thirty minutes"]) {
    const args = suggestion(); args.tasks[0].sub = sub;
    assert(validateAdvice(args, context())?.startsWith("FILLER"), sub);
  }
  const absent = suggestion(); absent.tasks[0].evidence_ids = ["invented"];
  assert(validateAdvice(absent, context())?.startsWith("EVIDENCE"));
  const duplicate = suggestion(); duplicate.tasks.push({ ...duplicate.tasks[0], title: "Same signal again" });
  assert(validateAdvice(duplicate, context())?.startsWith("DUPLICATE_SIGNAL"));
  for (const field of ["title", "sub", "basis"] as const) {
    const args = suggestion(); args.tasks[0][field] = "Your reading is 97.3";
    assert(validateAdvice(args, context())?.startsWith("NUMBER"), field);
  }
  const tooLong = suggestion(); tooLong.tasks[0].sub = "a".repeat(361);
  assert(validateAdvice(tooLong, context())?.startsWith("LENGTH"));
});

Deno.test("previous suggestions are repetition context, never measurement evidence", () => {
  const args = suggestion(), ctx = context();
  ctx.recent_suggestions = [{ user_day: today, title: "Earlier", summary: "Earlier summary", tasks: args.tasks }];
  assert(validateAdvice(args, ctx)?.startsWith("REPEATED_SET"));
  const novel = suggestion(); novel.tasks[0].sub = "Replace intervals with relaxed technique practice; reassess after warming up.";
  assertEquals(validateAdvice(novel, ctx), null);
  ctx.recent_suggestions = [{ user_day: today, title: "Earlier", summary: "Earlier summary",
    tasks: [{ title: "Fake prior value", sub: "Your reading was 97.3" }] }];
  novel.tasks[0].sub = "Your reading was 97.3";
  assert(validateAdvice(novel, ctx)?.startsWith("NUMBER"));
});

Deno.test("advice prefetch scopes every table to owner, excludes stale derived days and handles snapshot races", async () => {
  for (const changed of [false, true]) {
    let reads = 0;
    const queries: { table: string; filters: unknown[][] }[] = [];
    const db = {
      rpc: () => Promise.resolve({ data: [{ user_day: today, pending: true, result_revision: changed ? ++reads : 1 }], error: null }),
      from(table: string) {
        const record = { table, filters: [] as unknown[][] }; queries.push(record);
        const q = {
          select() { return q; }, order() { return q; }, limit() { return q; },
          eq(...args: unknown[]) { record.filters.push(args); return q; }, gte() { return q; }, lte() { return q; },
          then(resolve: (v: unknown) => unknown) { return Promise.resolve({ data: table === "daily_results" ? days : table === "sleep_nights" ? sleeps : [], error: null }).then(resolve); },
        }; return q;
      },
    } as unknown as SupabaseClient;
    const result = await planContext(db, "owner", today, "UTC", now);
    assert(queries.every(q => q.filters.some(f => f[0] === "user_id" && f[1] === "owner")));
    assertEquals(result.evidence.some(e => e.id === "training_load:2026-09-08"), false);
    assertEquals(queries.some(q => q.table === "plan_task_checks"), false);
    if (changed) { assertEquals(result.evidence, []); assert(result.failed.includes("snapshot_changed_or_unavailable")); }
    else assert(result.evidence.some(e => e.id === "training_load:2026-09-07"));
  }
});
