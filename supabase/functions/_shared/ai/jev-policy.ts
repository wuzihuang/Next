// Versioned decision policy for Jev routing: what may be asked, how sure an answer has to
// be, and which tasks are open in `on` mode.
//
// fast.single_read passed the frozen 108-case release holdout on 2026-09-20:
// 59/59 admitted requests correct, zero wrong admissions; 59/60 eligible reads routed.
// Evidence: supabase/scripts/eval/results-2026-09-20-release.json and
// docs/plans/2026-09-20-jev-tool-routing.md. Assisted requests remain closed.
// Thresholds are release engineering gates, not a population accuracy guarantee.
//
// A policy is keyed by task + model version + question version + candidate catalogue
// version. Change any one of them and the tuning no longer applies, so all four are
// carried on every decision and written to the log.

import { catalogVersion } from "./chart-selection.ts";

/// Bumped by hand whenever a question's wording or its criteria change.
export const QUESTION_VERSION = "2026-09-20.3";

export const FAST_READ_TASK = "fast.single_read" as const;
export const ASSISTED_READ_TASK = "assisted.read_with_explanation" as const;
export type JevTask = typeof FAST_READ_TASK | typeof ASSISTED_READ_TASK;

export type TaskPolicy = {
  /// Every consumed answer must clear all three. They are different measurements of the
  /// same answer and are never multiplied together or substituted for one another.
  minConfidence: number;
  /// Probability mass on the selected option.
  minProbability: number;
  /// Selected probability minus the runner-up.
  minMargin: number;
  /// True only once an independent test set has been reported for this task.
  evaluated: boolean;
};

export const TASK_POLICIES: Record<JevTask, TaskPolicy> = {
  [FAST_READ_TASK]: { minConfidence: 0.75, minProbability: 0.8, minMargin: 0.5, evaluated: true },
  [ASSISTED_READ_TASK]: { minConfidence: 0.75, minProbability: 0.8, minMargin: 0.5, evaluated: false },
};

export type PolicyVersion = {
  task: JevTask;
  modelVersion: string;
  questionVersion: string;
  catalogVersion: string;
};

export function policyVersion(task: JevTask, modelVersion: string): PolicyVersion {
  return {
    task,
    modelVersion,
    questionVersion: QUESTION_VERSION,
    catalogVersion: catalogVersion(),
  };
}

/// Does one answer clear its task's policy? Returns the failing field so the log can say
/// which gate refused, rather than a single opaque "low confidence".
export function clearsPolicy(
  policy: TaskPolicy,
  answer: { choice: string; confidence: number; probabilities: Record<string, number>; margin: number },
): { ok: true } | { ok: false; field: "confidence" | "probability" | "margin" } {
  if (answer.confidence < policy.minConfidence) return { ok: false, field: "confidence" };
  if ((answer.probabilities[answer.choice] ?? 0) < policy.minProbability) return { ok: false, field: "probability" };
  if (answer.margin < policy.minMargin) return { ok: false, field: "margin" };
  return { ok: true };
}

/// `on` opens only tasks that are named in the allowlist AND evaluated. An unevaluated task
/// stays closed however the environment is set: configuration is not evidence.
export function taskOpen(
  task: JevTask,
  env: (key: string) => string | undefined = Deno.env.get,
  policies: Record<JevTask, TaskPolicy> = TASK_POLICIES,
): boolean {
  const allowlist = (env("JEV_TASK_ALLOWLIST") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (!allowlist.includes(task)) return false;
  if (policies[task].evaluated) return true;
  // An explicit development override, so a developer can walk the path on their own
  // machine before the evaluation exists. Never set in production.
  return (env("JEV_ALLOW_UNEVALUATED")?.trim().toLowerCase() ?? "false") === "true";
}

/// Providers we hold a real, configured price for. A provider without one is not called:
/// an unpriced model would be billed at the price book's '*' rate, which is another
/// provider's price, and "free" is never the safe assumption.
export const JEV_PRICED_MODELS = new Set(["jev-1.13.0"]);

export function pricedModel(model: string): boolean {
  return JEV_PRICED_MODELS.has(model);
}
