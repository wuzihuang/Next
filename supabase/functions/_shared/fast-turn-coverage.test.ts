// Completeness: every binding in the admission list, rendered end to end.
//
// One test per FAST_BINDINGS entry, driven through runFastTurn with the real render tools,
// the real sources, the real number ledger and the real envelope schema. A binding that
// cannot draw its own chart from plausible rows is a binding that would abstain or fail in
// front of a user, so the sweep is a build failure, not a warning.
//
// The fixtures are shaped like the real tables, not like the sources' return values: the
// source code does the reading, so a column that moves breaks this test.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { runFastTurn, type FastTurnDeps } from "./fast-turn.ts";
import { FAST_BINDINGS, resolveWindow, type FastBinding } from "./chart-selection.ts";
import { buildRenderTools } from "./charts.ts";
import { auditFrame, NumberLedger } from "./ledger.ts";
import { createTurnWorkflow, gateTurnTool, WORKFLOW_READY } from "./turn-phase.ts";
import { Envelope } from "./contract.ts";
import { addDays } from "./calendar.ts";
import { fetchAs, type Ctx } from "./sources.ts";
import { FAST_READ_TASK } from "./jev-policy.ts";
import type { FastPlan } from "./decision-router.ts";
import type { Tool } from "npm:ai@4.3.16";

const DAY = "2026-09-20";

/// Rows shaped like the tables the sources actually read.
function fixtures(): Record<string, unknown[]> {
  const days = Array.from({ length: 30 }, (_, i) => addDays(DAY, -(29 - i)));
  const daily_results = days.map((user_day, i) => ({
    user_day,
    training_load: 6 + (i % 5),
    reserve_score: 55 + (i % 20),
    result_revision: `rev-${user_day}`,
    day_fuel: [{
      kcal_in: 1400 + i * 10, kcal_out: 2200, target_in: 2100,
      protein_g: 120, carb_g: 220, fat_g: 70,
      protein_in_g: 80 + (i % 12), carb_in_g: 180, fat_in_g: 60,
    }],
    reserve_daily: [{ current_value: 62, wake_value: 88, min_value: 31, hrv: 45 + (i % 9), night_inputs: [{ hrv: 45 + (i % 9), hrv_nights: 20 }] }],
    daily_training: [{ zone_minutes: [10, 20, 8, 3, 0], peak_hr: 162, segments: [], session_count: 1 }],
  }));
  // Intraday samples: every half hour of the day, which is what the buckets expect.
  const raw_samples = Array.from({ length: 40 }, (_, i) => ({
    ts: new Date(Date.parse(`${DAY}T06:00:00Z`) + i * 1800_000).toISOString(),
    heart: 62 + (i % 25), stress: 30 + (i % 40), step: 120 + (i % 300), src: "band",
  }));
  // Seven days of samples for the weekly step columns.
  const weekSamples = days.slice(-7).flatMap((day) =>
    Array.from({ length: 6 }, (_, i) => ({
      ts: new Date(Date.parse(`${day}T08:00:00Z`) + i * 3600_000).toISOString(),
      heart: 70 + i, stress: 35, step: 800 + i * 50, src: "band",
    }))
  );
  return {
    daily_results,
    raw_samples: [...raw_samples, ...weekSamples],
    reserve_samples: Array.from({ length: 24 }, (_, i) => ({
      ts: new Date(Date.parse(`${DAY}T00:00:00Z`) + i * 3600_000).toISOString(),
      value: i < 8 ? 40 + i * 6 : 90 - (i - 8) * 2,
    })),
    weigh_ins: days.filter((_, i) => i % 2 === 0).map((day, i) => ({
      measured_at: `${day}T07:10:00Z`, weight_kg: 73.5 - i * 0.05, user_day: day, id: `w-${day}`,
    })),
    meals: [
      { slot: "BREAKFAST", logged_at: `${DAY}T01:20:00Z`, text_input: "燕麦", kcal: 320, protein_g: 12, user_day: DAY, model_version: "m1", deleted_at: null },
      { slot: "LUNCH", logged_at: `${DAY}T05:10:00Z`, text_input: "牛肉面", kcal: 620, protein_g: 30, user_day: DAY, model_version: "m1", deleted_at: null },
      { slot: "DINNER", logged_at: `${DAY}T11:40:00Z`, text_input: "三文鱼", kcal: 510, protein_g: 38, user_day: DAY, model_version: "m1", deleted_at: null },
    ],
    sleep_nights: [{
      user_day: DAY, total_minutes: 438, deep_minutes: 96, light_minutes: 300, wake_count: 2,
      sleep_line: "1:40,0:55,1:60,2:35,1:80,0:41,4:12,1:115",
      sleep_start: `${addDays(DAY, -1)}T15:12:00Z`, wake_at: `${DAY}T22:30:00Z`,
    }],
    night_score: [{
      user_day: DAY, score: 79, duration_score: 84, architecture_score: 71,
      recovery_score: 80, regularity_score: 74,
    }],
    sample_archives: [],
  };
}

function stubDb(rows: Record<string, unknown[]>) {
  const reads: string[] = [];
  return {
    from(table: string) {
      reads.push(table);
      const q: Record<string, unknown> = {};
      for (const m of ["select", "eq", "gte", "lte", "lt", "gt", "neq", "order", "limit", "range", "is", "in"]) {
        q[m] = () => q;
      }
      const data = rows[table] ?? [];
      q.maybeSingle = () => Promise.resolve({ data: data[0] ?? null, error: null });
      q.single = q.maybeSingle;
      q.then = (resolve: (v: unknown) => unknown) => Promise.resolve({ data, error: null }).then(resolve);
      return q;
    },
    rpc: () => Promise.resolve({ data: [], error: null }),
    reads,
  };
}

function planFor(binding: FastBinding): FastPlan {
  const label = binding.windows[0];
  const window = resolveWindow(label, DAY)!;
  // A rolling binding reads exactly its own span, the way the router resolves it.
  const resolved = binding.spanDays
    ? { ...window, from: addDays(DAY, 1 - binding.spanDays), to: DAY, spanDays: binding.spanDays }
    : window;
  return {
    task: FAST_READ_TASK,
    metric: binding.metric,
    presentation: binding.presentations[0],
    window: resolved,
    binding,
    explanation: false,
  };
}

function buildTurn(rows: Record<string, unknown[]>) {
  const db = stubDb(rows);
  const ctx: Ctx = { db: db as never, userId: "u", dayKey: DAY, tz: "UTC", cache: new Map() };
  const ledger = new NumberLedger();
  ledger.seedConstants();
  let envelope: Envelope | null = null;
  const renderTools = buildRenderTools(ctx, ledger, (env) => { envelope = env; }, "zh-CN");
  const workflow = createTurnWorkflow(["read"], Object.keys(renderTools), [], "read");
  const traced: Record<string, Tool> = {
    ...Object.fromEntries(Object.entries(renderTools).map(([name, tool]) => [name, {
      ...tool,
      execute: (args: Record<string, unknown>, opts: never) => {
        const decision = gateTurnTool(workflow, name);
        if (!decision.allow) return Promise.resolve({ rendered: false, error: decision.error });
        return tool.execute!(args, opts);
      },
    }])),
    [WORKFLOW_READY]: {
      description: "control",
      parameters: renderTools["screen.render"].parameters,
      execute: (args: { range?: { from: string; to: string } }) => {
        if (args.range) { ctx.from = args.range.from; ctx.to = args.range.to; ctx.dayKey = args.range.to; }
        return Promise.resolve({ ok: true });
      },
    } as unknown as Tool,
  };
  const deps: FastTurnDeps = {
    traced, workflow, locale: "zh-CN",
    probe: async (sourceId, kind) => ({ ok: true, result: await fetchAs(sourceId, kind, ctx) }),
  };
  return { deps, ledger, workflow, get envelope() { return envelope; }, reads: db.reads };
}

for (const binding of FAST_BINDINGS) {
  Deno.test(`binding ${binding.id} draws its own chart end to end`, async () => {
    const turn = buildTurn(fixtures());
    const result = await runFastTurn(planFor(binding), turn.deps);
    assert(result.published, `${binding.id} did not publish: ${JSON.stringify(result)}`);
    assertEquals(turn.workflow.phase, "done");

    const frame = Envelope.safeParse(turn.envelope);
    assert(frame.success, `${binding.id} produced an illegal envelope: ${JSON.stringify(turn.envelope)}`);
    // The chart the binding promised, not whatever the source felt like.
    assertEquals(frame.data.type, binding.type, binding.id);
    assert(frame.data.title.length > 0 && frame.data.sentence.length > 0, binding.id);

    // Every number the words say traces to this turn's own evidence.
    turn.ledger.seal();
    const audit = auditFrame(frame.data as unknown as Record<string, unknown>, turn.ledger);
    assertEquals(audit, { ok: true }, `${binding.id} said a number no tool returned: ${JSON.stringify(audit)}`);
  });
}

Deno.test("the sweep covers every admitted binding", () => {
  // A binding added without a fixture would otherwise pass silently by never running.
  assertEquals(FAST_BINDINGS.length, 23);
});
