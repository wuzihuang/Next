import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { runFastTurn, type FastTurnDeps, type ProbeResult } from "./fast-turn.ts";
import { bindingById, FAST_BINDINGS } from "./chart-selection.ts";
import { buildRenderTools, FAMILY_KIND } from "./charts.ts";
import { NumberLedger, auditFrame } from "./ledger.ts";
import { createTurnWorkflow, gateTurnTool, WORKFLOW_READY } from "./turn-phase.ts";
import { SKILL_BY_TYPE } from "./skills.ts";
import { Envelope } from "./contract.ts";
import { fetchAs, SOURCE_BY_ID, type Ctx } from "./sources.ts";
import { FAST_READ_TASK, ASSISTED_READ_TASK } from "./jev-policy.ts";
import type { FastPlan } from "./decision-router.ts";
import type { Tool } from "npm:ai@4.3.16";

const DAY = "2026-09-20";

/// A Supabase stub that answers the queries the in-scope sources make.
function stubDb(rows: Record<string, unknown[]>) {
  const queried: string[] = [];
  const db = {
    from(table: string) {
      queried.push(table);
      const q: Record<string, unknown> = {};
      for (const method of ["select", "eq", "gte", "lte", "lt", "gt", "order", "limit", "range", "is", "in"]) {
        q[method] = () => q;
      }
      q.maybeSingle = () => Promise.resolve({ data: (rows[table] ?? [])[0] ?? null, error: null });
      q.single = q.maybeSingle;
      q.then = (resolve: (v: unknown) => unknown) => Promise.resolve({ data: rows[table] ?? [], error: null }).then(resolve);
      return q;
    },
    rpc: () => Promise.resolve({ data: [], error: null }),
  };
  return { db, queried };
}

function plan(bindingId: string, explanation = false): FastPlan {
  const binding = bindingById(bindingId)!;
  return {
    task: explanation ? ASSISTED_READ_TASK : FAST_READ_TASK,
    metric: binding.metric,
    presentation: binding.presentations[0],
    window: { from: DAY, to: DAY, label: "TODAY", spanDays: 1 },
    binding,
    explanation,
  };
}

/// The real render tools, the real ledger, the real workflow — only the database and the
/// control tool are stubs, and the control tool sets the range exactly as the turn's does.
function turnUnderTest(rows: Record<string, unknown[]>, probeOverride?: FastTurnDeps["probe"]) {
  const { db, queried } = stubDb(rows);
  const ctx: Ctx = { db: db as never, userId: "u", dayKey: DAY, tz: "UTC", cache: new Map() };
  const ledger = new NumberLedger();
  ledger.seedConstants();
  let envelope: Envelope | null = null;
  const renderTools = buildRenderTools(ctx, ledger, (env) => { envelope = env; }, "zh-CN");
  const workflow = createTurnWorkflow(["read"], Object.keys(renderTools), [], "read");
  const gated: string[] = [];
  const traced: Record<string, Tool> = {
    ...Object.fromEntries(Object.entries(renderTools).map(([name, tool]) => [name, {
      ...tool,
      execute: (args: Record<string, unknown>, opts: never) => {
        const decision = gateTurnTool(workflow, name);
        gated.push(`${name}:${decision.allow}`);
        if (!decision.allow) return Promise.resolve({ rendered: false, error: decision.error });
        return tool.execute!(args, opts);
      },
    }])),
    [WORKFLOW_READY]: {
      description: "test control",
      parameters: renderTools["screen.render"].parameters,
      execute: (args: { range?: { from: string; to: string } }) => {
        if (args.range) { ctx.from = args.range.from; ctx.to = args.range.to; ctx.dayKey = args.range.to; }
        return Promise.resolve({ ok: true });
      },
    } as unknown as Tool,
  };
  const probe: FastTurnDeps["probe"] = probeOverride ??
    (async (sourceId, kind) => ({ ok: true, result: await fetchAs(sourceId, kind, ctx) } as ProbeResult));
  return { deps: { traced, workflow, probe, locale: "zh-CN" } as FastTurnDeps, get envelope() { return envelope; }, ledger, workflow, queried, gated };
}

const FUEL_ROWS = {
  daily_results: [{ user_day: DAY, training_load: 6, day_fuel: [{ kcal_in: 1450, target_in: 2100, protein_g: 120, protein_in_g: 80 }] }],
};

Deno.test("a fast turn publishes through the real render tool, with the real phases", async () => {
  const t = turnUnderTest(FUEL_ROWS);
  const result = await runFastTurn(plan("ring:kcal.today"), t.deps);
  assert(result.published, JSON.stringify(result));
  assertEquals(result.route, "fast");
  // ready then render, both allowed by the gate in the phase they belong to.
  assertEquals(t.gated, ["screen.render:true"]);
  assertEquals(t.workflow.phase, "done");
  assertEquals(t.workflow.completedSteps, 2);
  const frame = Envelope.safeParse(t.envelope);
  assert(frame.success, JSON.stringify(t.envelope));
  assertEquals(frame.data.type, "ring");
  // The numbers on screen are the source's own, and the frame survives the real audit.
  assertEquals(frame.data.sentence, "1450kcal / 目标 2100kcal");
  assertEquals(frame.data.footer, "还差 650kcal");
  t.ledger.seal();
  assertEquals(auditFrame(frame.data as unknown as Record<string, unknown>, t.ledger), { ok: true });
});

Deno.test("the read and the render share one snapshot, not two queries", async () => {
  const t = turnUnderTest(FUEL_ROWS);
  const result = await runFastTurn(plan("ring:kcal.today"), t.deps);
  assert(result.published);
  // daily_results is read once: the render's own fetch hits the turn's source cache.
  assertEquals(t.queried.filter((table) => table === "daily_results").length, 1);
});

Deno.test("no data is a fallback, never an invented zero", async () => {
  const t = turnUnderTest({ daily_results: [] });
  const result = await runFastTurn(plan("ring:kcal.today"), t.deps);
  assertEquals(result, { published: false, reason: "NO_DATA", steps: 1 });
  assertEquals(t.envelope, null);
});

Deno.test("a pending upload or a failed query each stop the fast route with their own reason", async () => {
  for (const reason of ["FRESHNESS_PENDING", "SOURCE_FAILED"] as const) {
    const t = turnUnderTest(FUEL_ROWS, () => Promise.resolve({ ok: false, reason }));
    const result = await runFastTurn(plan("ring:kcal.today"), t.deps);
    assertEquals(result.published, false);
    assert(!result.published);
    assertEquals(result.reason, reason);
    assertEquals(t.envelope, null);
  }
});

Deno.test("a cancelled turn publishes nothing", async () => {
  const controller = new AbortController();
  controller.abort();
  const t = turnUnderTest(FUEL_ROWS);
  const result = await runFastTurn(plan("ring:kcal.today"), { ...t.deps, signal: controller.signal });
  assertEquals(result, { published: false, reason: "CANCELLED", steps: 0 });
});

Deno.test("a request that wanted an explanation is not answered from a template", async () => {
  // The router sends those to the guided route, where the model reads and writes itself.
  const t = turnUnderTest(FUEL_ROWS);
  const result = await runFastTurn(plan("ring:kcal.today", true), t.deps);
  assert(!result.published);
  assertEquals(result.reason, "EXPLANATION_UNAVAILABLE");
  assertEquals(t.envelope, null);
});

Deno.test("every admitted binding's chart can actually eat its source's shape", () => {
  // fetchAs converts only between curve and column. Any other mismatch returns null at
  // render time, which would make a binding that can never draw.
  for (const binding of FAST_BINDINGS) {
    const skill = SKILL_BY_TYPE.get(binding.type)!;
    const wanted = FAMILY_KIND[skill.family];
    const produced = SOURCE_BY_ID.get(binding.source)!.kind;
    const convertible = (wanted === "column" && produced === "curve") || (wanted === "curve" && produced === "column");
    assert(wanted === produced || convertible, `${binding.id}: chart wants ${wanted}, source gives ${produced}`);
  }
});
