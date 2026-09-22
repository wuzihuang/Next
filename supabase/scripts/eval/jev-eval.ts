// Offline evaluation of the Jev routing decision. ADR 0031.
//
// It drives the REAL router (decision-router.ts, the real candidate catalogue, the real
// thresholds) over a labelled set, so what it measures is the code that runs in a turn —
// not a reimplementation of it. Nothing here touches the database, a user's health data
// or production: the only outbound call is the provider's own decision endpoint.
//
//   deno run --allow-net --allow-env --allow-read \
//     supabase/scripts/eval/jev-eval.ts --set supabase/scripts/eval/jev-eval-set.json \
//     [--split test|dev|all] [--out results.json] [--concurrency 4]
//
// Needs TYPESAFE_API_KEY. Every call is billed to that key: 156 samples cost roughly
// 200k input tokens, about USD 0.01 at the published price.
//
// ⚠️ The numbers it prints are a measurement of one labelled set at one moment, with the
// pinned model version. They are not a guarantee about any population of real requests,
// and they are certainly not a clinical claim.

import { routeTurn, type RouteDecision } from "../../functions/_shared/decision-router.ts";
import { jevConfig } from "../../functions/_shared/typesafe.ts";
import { catalogVersion } from "../../functions/_shared/chart-selection.ts";
import { QUESTION_VERSION } from "../../functions/_shared/jev-policy.ts";

type Sample = {
  id: string;
  split: "dev" | "test";
  lang: string;
  text: string;
  expect: { route: "fast" | "assisted" | "legacy"; binding: string | null; reason: string | null };
};

type Outcome = {
  id: string;
  split: string;
  lang: string;
  text: string;
  expected: Sample["expect"];
  got: { route: string; binding: string | null; reason: string | null };
  correct: boolean;
  /// The dangerous class: something that should have gone to the model was routed.
  wrongAdmission: boolean;
  latencyMs: number;
  inputTokens: number;
};

function parseArgs(): Record<string, string> {
  const args: Record<string, string> = {};
  for (let i = 0; i < Deno.args.length; i += 2) args[Deno.args[i].replace(/^--/, "")] = Deno.args[i + 1];
  return args;
}

function decisionOf(decision: RouteDecision): { route: string; binding: string | null; reason: string | null } {
  if (decision.outcome === "accept") {
    return { route: decision.route, binding: decision.plan.binding.id, reason: null };
  }
  if (decision.outcome === "abstain") {
    return { route: "legacy", binding: null, reason: decision.detail ? `${decision.reason} (${decision.detail})` : decision.reason };
  }
  if (decision.outcome === "unavailable") return { route: "legacy", binding: null, reason: decision.reason };
  return { route: "legacy", binding: null, reason: "CANCELLED" };
}

async function main() {
  const args = parseArgs();
  const setPath = args.set ?? "supabase/scripts/eval/jev-eval-set.json";
  const split = args.split ?? "all";
  const concurrency = Math.max(1, Number(args.concurrency ?? 4));
  const file = JSON.parse(await Deno.readTextFile(setPath)) as { version: string; samples: Sample[] };
  const samples = file.samples.filter((s) => split === "all" || s.split === split);
  const config = jevConfig();
  const tasks = args.tasks ?? tasks;
  if (!config.apiKey) {
    console.error("TYPESAFE_API_KEY is not set: nothing was evaluated.");
    Deno.exit(2);
  }
  // The evaluation measures the decision, so every task is open regardless of the
  // production allowlist — that is exactly what has to be measured before one is opened.
  const env = (key: string): string | undefined =>
    key === "JEV_TASK_ALLOWLIST"
      ? tasks
      : key === "JEV_ALLOW_UNEVALUATED"
      ? "true"
      : Deno.env.get(key);

  const currentDay = args.day ?? new Date().toISOString().slice(0, 10);
  const outcomes: Outcome[] = [];
  let index = 0;
  const workers = Array.from({ length: concurrency }, async () => {
    while (index < samples.length) {
      const sample = samples[index++];
      const started = Date.now();
      const decision = await routeTurn({
        text: sample.text,
        locale: sample.lang === "en" ? "en-US" : "zh-CN",
        currentDay,
        surface: "panel",
        hasImage: false,
        isResume: false,
        // Assisted must be reachable for the labels that expect it.
        config: { ...config, assistedEnabled: tasks.split(",").includes("assisted.read_with_explanation") },
        env,
      });
      const got = decisionOf(decision);
      const correct = got.route === sample.expect.route &&
        (sample.expect.route !== "fast" || got.binding === sample.expect.binding);
      outcomes.push({
        id: sample.id, split: sample.split, lang: sample.lang, text: sample.text,
        expected: sample.expect, got, correct,
        wrongAdmission: sample.expect.route === "legacy" && got.route !== "legacy",
        latencyMs: Date.now() - started,
        inputTokens: decision.attempts.reduce((sum, a) => sum + (a.usage?.promptTokens ?? 0), 0),
      });
      if (outcomes.length % 20 === 0) console.error(`  … ${outcomes.length}/${samples.length}`);
    }
  });
  await Promise.all(workers);
  outcomes.sort((a, b) => a.id.localeCompare(b.id));

  const report = summarise(outcomes, { set: setPath, setVersion: file.version, split, currentDay, model: config.model });
  console.log(JSON.stringify(report, null, 1));
  if (args.out) {
    await Deno.writeTextFile(args.out, JSON.stringify({ report, outcomes }, null, 1));
    console.error(`wrote ${args.out}`);
  }
}

function summarise(outcomes: Outcome[], context: Record<string, string>) {
  const bySplit = (name: string) => outcomes.filter((o) => o.split === name || name === "all");
  const stats = (rows: Outcome[]) => {
    const admitted = rows.filter((o) => o.got.route !== "legacy");
    const shouldRoute = rows.filter((o) => o.expected.route !== "legacy");
    const admittedCorrect = admitted.filter((o) => o.correct);
    const latencies = rows.map((o) => o.latencyMs).sort((a, b) => a - b);
    return {
      samples: rows.length,
      // Of the requests this actually routed, how many were routed correctly. This is the
      // number that matters before opening a task: a wrong admission reaches a user.
      accepted_accuracy: admitted.length ? round(admittedCorrect.length / admitted.length) : null,
      accepted: admitted.length,
      // How much of the work it takes off the model at all.
      coverage: shouldRoute.length ? round(admitted.filter((o) => o.expected.route !== "legacy").length / shouldRoute.length) : null,
      // The dangerous one, reported separately and never averaged away.
      wrong_admission_rate: rows.length ? round(rows.filter((o) => o.wrongAdmission).length / rows.length) : null,
      wrong_admissions: rows.filter((o) => o.wrongAdmission).map((o) => ({ id: o.id, text: o.text, got: o.got })),
      missed: rows.filter((o) => o.expected.route !== "legacy" && o.got.route === "legacy")
        .map((o) => ({ id: o.id, text: o.text, reason: o.got.reason })),
      wrong_binding: rows.filter((o) => o.expected.route === "fast" && o.got.route !== "legacy" && o.got.binding !== o.expected.binding)
        .map((o) => ({ id: o.id, text: o.text, expected: o.expected.binding, got: o.got.binding })),
      latency_ms: { p50: latencies[Math.floor(latencies.length * 0.5)] ?? null, p95: latencies[Math.floor(latencies.length * 0.95)] ?? null },
      input_tokens: rows.reduce((sum, o) => sum + o.inputTokens, 0),
      fallback_reasons: count(rows.filter((o) => o.got.route === "legacy").map((o) => o.got.reason ?? "none")),
    };
  };
  return {
    context: { ...context, questionVersion: QUESTION_VERSION, catalogVersion: catalogVersion(), ranAt: new Date().toISOString() },
    all: stats(outcomes),
    dev: stats(bySplit("dev")),
    test: stats(bySplit("test")),
    by_language: Object.fromEntries(["zh", "en"].map((lang) => [lang, stats(outcomes.filter((o) => o.lang === lang))])),
  };
}

function count(values: string[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const value of values) out[value] = (out[value] ?? 0) + 1;
  return Object.fromEntries(Object.entries(out).sort((a, b) => b[1] - a[1]));
}

const round = (value: number) => Math.round(value * 1000) / 1000;

if (import.meta.main) await main();
