// Running a validated plan through the machinery a model turn uses, and nothing beside it.
//
// The fast route publishes through the same objects as every other turn: the turn's traced
// tool map (workflow gate, trace entry, SSE `tool` event), the same workflow phases
// (read → ready → render), the same source cache and snapshot, the same render tool, the
// same number ledger, the same envelope audit. Nothing here writes a frame, advances a
// phase by hand, or reaches the database on its own.
//
// What it adds is that no general model is called: the decision came from the router, the
// numbers come from the source, and the words come from fast-copy.ts.

import type { Tool } from "npm:ai@4.3.16";
import type { FastPlan } from "./decision-router.ts";
import { fastCopy } from "./fast-copy.ts";
import type { Kind, SourceResult } from "./sources.ts";
import { finishTurnStep, WORKFLOW_READY, type TurnWorkflow } from "./turn-phase.ts";
import { SKILL_BY_TYPE } from "./skills.ts";
import { FAMILY_KIND } from "./charts.ts";

/// Why a fast attempt did not publish. Each one is a different real situation, and the
/// caller hands the whole request back to the model with the turn still in a legal state.
export type FastFailure =
  | "FRESHNESS_PENDING"
  | "NO_DATA"
  | "SOURCE_FAILED"
  | "COPY_UNAVAILABLE"
  | "READY_REFUSED"
  | "RENDER_REFUSED"
  | "EXPLANATION_UNAVAILABLE"
  | "CANCELLED";

export type FastTurnResult =
  | { published: true; bindingId: string; route: "fast" | "assisted"; steps: number }
  | { published: false; reason: FastFailure; steps: number };

/// What the source read returned, or why it could not be read. The caller owns the
/// freshness gate so that this path cannot skip it.
export type ProbeResult =
  | { ok: true; result: SourceResult | null }
  | { ok: false; reason: "FRESHNESS_PENDING" | "SOURCE_FAILED" };

export type FastTurnDeps = {
  /// The turn's traced tools: gate, trace and SSE events already wrapped around them.
  traced: Record<string, Tool>;
  workflow: TurnWorkflow;
  /// Reads the source through the turn's freshness gate and its shared cache, so the
  /// render below reuses this exact snapshot instead of reading again.
  probe: (sourceId: string, kind: Kind, from: string, to: string) => Promise<ProbeResult>;
  locale: string;
  signal?: AbortSignal;
};

const RENDER_TOOL = "screen.render";

export async function runFastTurn(plan: FastPlan, deps: FastTurnDeps): Promise<FastTurnResult> {
  let steps = 0;
  const stop = (reason: FastFailure): FastTurnResult => ({ published: false, reason, steps });
  if (deps.signal?.aborted) return stop("CANCELLED");

  const skill = SKILL_BY_TYPE.get(plan.binding.type);
  if (!skill) return stop("RENDER_REFUSED");

  // 1 · enter the output phase through the real control tool, with the window the server
  // resolved. This is what sets the turn's range, so the read below and the render after
  // it cover the same days.
  const ready = deps.traced[WORKFLOW_READY];
  if (!ready?.execute) return stop("READY_REFUSED");
  const readyResult = await ready.execute(
    { range: { from: plan.window.from, to: plan.window.to } },
    { toolCallId: crypto.randomUUID(), messages: [] },
  ) as { ok?: boolean };
  steps += 1;
  finishTurnStep(deps.workflow, [{ toolName: WORKFLOW_READY, result: readyResult }]);
  if (readyResult?.ok !== true) return stop("READY_REFUSED");
  if (deps.signal?.aborted) return stop("CANCELLED");

  // 2 · read the evidence the words will be written from. Same cache key as the render's
  // own fetch, so this is one query and one snapshot, not two.
  const kind = FAMILY_KIND[skill.family];
  const probe = await deps.probe(plan.binding.source, kind, plan.window.from, plan.window.to);
  if (!probe.ok) return stop(probe.reason);
  if (!probe.result) return stop("NO_DATA");
  if (deps.signal?.aborted) return stop("CANCELLED");

  const deterministic = fastCopy(plan.binding, {
    agg: probe.result.agg,
    window: probe.result.window,
    hero: probe.result.hero,
    unit: probe.result.unit,
  }, deps.locale);
  // The source returned data whose shape this template cannot state as fact. The model
  // reads the same evidence and says it properly.
  if (!deterministic) return stop("COPY_UNAVAILABLE");

  // A request that also wanted an explanation never reaches here: the router sends it to
  // the guided route, where the model reads and writes the answer itself.
  if (plan.explanation) return stop("EXPLANATION_UNAVAILABLE");
  const words = deterministic;

  // 3 · publish through the same render tool the model would call. It registers the
  // source's evidence, harvests its numbers, and the turn's own audit runs after it.
  const render = deps.traced[RENDER_TOOL];
  if (!render?.execute) return stop("RENDER_REFUSED");
  const rendered = await render.execute({
    type: plan.binding.type,
    source: plan.binding.source,
    title: words.title,
    sentence: words.sentence,
    ...(words.footer ? { footer: words.footer } : {}),
  }, { toolCallId: crypto.randomUUID(), messages: [] }) as { rendered?: boolean };
  steps += 1;
  finishTurnStep(deps.workflow, [{ toolName: RENDER_TOOL, result: rendered }]);
  if (rendered?.rendered !== true) return stop("RENDER_REFUSED");

  return { published: true, bindingId: plan.binding.id, route: plan.explanation ? "assisted" : "fast", steps };
}
