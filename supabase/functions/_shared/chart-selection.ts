// Which (chart, source) pairs a deterministic turn may publish, and the closed candidate
// sets the decision router is allowed to offer Jev.
//
// This is an admission list over the registries that already exist — CHART_SKILLS in
// skills.ts and SOURCES in sources.ts — not a second catalogue. Every entry names an
// existing chart type, an existing source id that the chart itself declares, and the
// window semantics that source actually reads. `assertBindings()` proves all of that
// against the live registries, and its test fails the build if a registry moves.
//
// ⚠️ A window is never widened to fit a source. weight has .30d and .90d and no .7d, so
// "last seven days of weight" has no binding and the request goes to the model. Reading
// the 30-day source over a 7-day range would answer a question nobody asked.

import { CHART_SKILLS, SKILL_BY_TYPE } from "./skills.ts";
import { SOURCE_BY_ID } from "./sources.ts";
import { addDays } from "./calendar.ts";
import type { PanelType } from "./contract.ts";

/// Time categories the router may ask about. Only the resolvable ones reach a window.
export const TIME_LABELS = [
  "TODAY",
  "YESTERDAY",
  "LAST_NIGHT",
  "LAST_7_USER_DAYS",
  "LAST_30_USER_DAYS",
  "EXPLICIT_DATE_CANDIDATE",
  "UNSPECIFIED",
  "OTHER_OR_AMBIGUOUS",
] as const;
export type TimeLabel = (typeof TIME_LABELS)[number];

/// What the answer has to show. Internal labels for picking an existing chart — not new
/// chart types, and never shown to the user.
export const PRESENTATIONS = [
  "SCALAR",
  "TREND",
  "DAILY_COMPARISON",
  "STRUCTURE",
  "TARGET_PROGRESS",
  "NO_PREFERENCE",
  "UNKNOWN",
] as const;
export type Presentation = (typeof PRESENTATIONS)[number];

/// How fast-copy.ts words this binding. Each kind has a template that states only what the
/// source returned; none of them explains, judges or advises.
export type CopyKind = "target" | "trend" | "daily" | "structure" | "score" | "mix" | "list" | "scalar" | "total";

export type FastBinding = {
  /// `${type}:${source}` — the only thing a model is ever asked to choose between.
  id: string;
  type: PanelType;
  source: string;
  metric: FastMetricId;
  /// The windows this source genuinely reads. `rolling` entries name their exact span.
  windows: TimeLabel[];
  presentations: Presentation[];
  /// Inclusive user-day span the source reads, for windows that are ranges.
  spanDays?: number;
  unit: string;
  copy: CopyKind;
  /// A one-line English label for the second-batch binding question.
  says: string;
};

/// The metrics fast routing may claim to understand. Everything else is NO_MATCH, which
/// sends the request to the model — the correct outcome, not a failure.
export const FAST_METRICS = {
  intakeKcal: "Calories the user recorded eating (food intake, 摄入 / 吃了多少卡).",
  proteinG: "Protein grams the user recorded eating (蛋白质).",
  meals: "Which meals were recorded today and their calories (记了哪几餐).",
  trainingLoad: "The product's daily training load score out of 21 (训练负荷).",
  bodyBattery: "Body Battery, the 0–100 energy reserve (身体电量).",
  heartRate: "Wrist heart rate over a day (心率曲线).",
  steps: "Step count (步数).",
  weight: "Body weight in kilograms (体重).",
  nightHRV: "Night heart-rate variability in milliseconds (夜间 HRV).",
  sleepStructure: "How last night was made up: stages, deep/light/awake split, duration (睡眠分期 / 时长).",
  sleepScore: "The nightly sleep score out of 100 (睡眠分数).",
} as const;
export type FastMetricId = keyof typeof FAST_METRICS;

/// Neighbours of the supported metrics that this product measures but cannot draw on the
/// fast route. They are offered as their own options so a request about one has somewhere
/// true to go: without them, "how far did I walk today" landed on the step count, because
/// steps was the closest thing on offer. Selecting any of these is a refusal.
///
/// ⚠️ These are not bindable and never reach a plan. Adding one here only sharpens the
/// boundary; giving one a binding means adding it to FAST_METRICS and FAST_BINDINGS.
export const UNSUPPORTED_METRICS = {
  NOT_SUPPORTED_distance: "Distance walked, run or moved — kilometres or miles (距离 / 公里 / how far).",
  NOT_SUPPORTED_burnKcal: "Calories burned or expended, as opposed to eaten (消耗 / burn / expenditure).",
  NOT_SUPPORTED_bloodOxygen: "Blood oxygen or SpO2, including overnight oxygen (血氧).",
  NOT_SUPPORTED_stress: "The stress reading (压力).",
  NOT_SUPPORTED_restingHeartRate: "Resting heart rate as its own number (静息心率).",
  NOT_SUPPORTED_bodyComposition: "Body fat percentage, fat mass, lean mass or a body scan (体脂 / 体成分).",
  NOT_SUPPORTED_bloodPressure: "Blood pressure or an ECG reading (血压 / 心电).",
  NOT_SUPPORTED_deviceState: "The band itself: its battery, its connection, how long it has been worn (手环电量 / 佩戴).",
  NOT_SUPPORTED_activeMinutes: "Active minutes, workout sessions or exercise duration (运动时长 / 训练时段).",
} as const;

const ROLLING_7: TimeLabel[] = ["LAST_7_USER_DAYS"];
const ROLLING_30: TimeLabel[] = ["LAST_30_USER_DAYS"];
const TODAY: TimeLabel[] = ["TODAY"];
const NIGHT: TimeLabel[] = ["LAST_NIGHT"];

/// ⚠️ Ordered. When several bindings survive filtering and the router does not ask Jev a
/// second question, the first one wins — so the most literal reading of the request comes
/// first within each metric.
export const FAST_BINDINGS: FastBinding[] = [
  // ---------------------------------------------------------------- fuel, today
  {
    id: "ring:kcal.today", type: "ring", source: "kcal.today", metric: "intakeKcal",
    windows: TODAY, presentations: ["TARGET_PROGRESS", "SCALAR", "NO_PREFERENCE"],
    unit: "kcal", copy: "target", says: "Today's recorded calories against the day's target.",
  },
  {
    id: "ring:protein.today", type: "ring", source: "protein.today", metric: "proteinG",
    windows: TODAY, presentations: ["TARGET_PROGRESS", "SCALAR", "NO_PREFERENCE"],
    unit: "g", copy: "target", says: "Today's recorded protein against the day's target.",
  },
  {
    id: "meal:meals.today", type: "meal", source: "meals.today", metric: "meals",
    windows: TODAY, presentations: ["STRUCTURE", "DAILY_COMPARISON", "NO_PREFERENCE", "SCALAR"],
    unit: "kcal", copy: "list", says: "The meals recorded today, one row each with its calories.",
  },
  // ---------------------------------------------------------------- training, today
  {
    id: "ring:load.today", type: "ring", source: "load.today", metric: "trainingLoad",
    windows: TODAY, presentations: ["TARGET_PROGRESS", "SCALAR", "NO_PREFERENCE"],
    unit: "", copy: "target", says: "Today's training load against the full scale of 21.",
  },
  {
    id: "bars:steps.today", type: "bars", source: "steps.today", metric: "steps",
    windows: TODAY, presentations: ["TREND", "STRUCTURE", "NO_PREFERENCE", "SCALAR"],
    // ⚠️ `total`, not `trend`: steps.today returns {total, peak, bins} and has no latest or
    // mean, so the trend template had nothing to say and the route abstained every time.
    unit: "", copy: "total", says: "Today's steps in two-hour columns.",
  },
  // ---------------------------------------------------------------- vitals, today
  {
    id: "line:heart.today", type: "line", source: "heart.today", metric: "heartRate",
    windows: TODAY, presentations: ["TREND", "NO_PREFERENCE", "STRUCTURE"],
    unit: "bpm", copy: "trend", says: "Today's heart-rate curve.",
  },
  {
    id: "line:bodyBattery.today", type: "line", source: "bodyBattery.today", metric: "bodyBattery",
    windows: TODAY, presentations: ["TREND", "STRUCTURE"],
    unit: "", copy: "trend", says: "Today's Body Battery curve.",
  },
  {
    id: "battery:battery.now", type: "battery", source: "battery.now", metric: "bodyBattery",
    windows: TODAY, presentations: ["SCALAR", "TARGET_PROGRESS", "NO_PREFERENCE"],
    unit: "", copy: "scalar", says: "Body Battery right now.",
  },
  // ---------------------------------------------------------------- last night
  {
    id: "split:sleep.mix", type: "split", source: "sleep.mix", metric: "sleepStructure",
    windows: NIGHT, presentations: ["STRUCTURE", "SCALAR", "NO_PREFERENCE"],
    unit: "min", copy: "mix", says: "Last night's deep, light and awake minutes as one stacked track.",
  },
  {
    id: "hypnogram:sleep.stages", type: "hypnogram", source: "sleep.stages", metric: "sleepStructure",
    // Shares STRUCTURE with the stacked split: "how did I sleep" is genuinely either the
    // three-way mix or the stage strip, and that is the one ambiguity worth a second
    // question rather than a coin toss.
    windows: NIGHT, presentations: ["STRUCTURE", "TREND", "DAILY_COMPARISON"],
    unit: "min", copy: "structure", says: "Last night's stages minute by minute, as three lanes.",
  },
  {
    id: "score:sleep.score.night", type: "score", source: "sleep.score.night", metric: "sleepScore",
    windows: NIGHT, presentations: ["SCALAR", "STRUCTURE", "TARGET_PROGRESS", "NO_PREFERENCE"],
    unit: "", copy: "score", says: "Last night's sleep score with its four sub-scores.",
  },
  // ---------------------------------------------------------------- rolling windows
  {
    id: "line:intakeKcal.7d", type: "line", source: "intakeKcal.7d", metric: "intakeKcal",
    windows: ROLLING_7, presentations: ["TREND", "NO_PREFERENCE"], spanDays: 7,
    unit: "kcal", copy: "trend", says: "Recorded calories over the last seven user days, as a line.",
  },
  {
    id: "days:intakeKcal.7d", type: "days", source: "intakeKcal.7d", metric: "intakeKcal",
    windows: ROLLING_7, presentations: ["DAILY_COMPARISON"], spanDays: 7,
    unit: "kcal", copy: "daily", says: "Recorded calories for each of the last seven user days, day by day.",
  },
  {
    id: "line:intakeKcal.30d", type: "line", source: "intakeKcal.30d", metric: "intakeKcal",
    windows: ROLLING_30, presentations: ["TREND", "NO_PREFERENCE", "DAILY_COMPARISON"], spanDays: 30,
    unit: "kcal", copy: "trend", says: "Recorded calories over the last thirty user days.",
  },
  {
    id: "line:trainingLoad.7d", type: "line", source: "trainingLoad.7d", metric: "trainingLoad",
    windows: ROLLING_7, presentations: ["TREND", "NO_PREFERENCE"], spanDays: 7,
    unit: "", copy: "trend", says: "Training load over the last seven user days, as a line.",
  },
  {
    id: "days:trainingLoad.7d", type: "days", source: "trainingLoad.7d", metric: "trainingLoad",
    windows: ROLLING_7, presentations: ["DAILY_COMPARISON"], spanDays: 7,
    unit: "", copy: "daily", says: "Training load for each of the last seven user days.",
  },
  {
    id: "line:trainingLoad.30d", type: "line", source: "trainingLoad.30d", metric: "trainingLoad",
    windows: ROLLING_30, presentations: ["TREND", "NO_PREFERENCE", "DAILY_COMPARISON"], spanDays: 30,
    unit: "", copy: "trend", says: "Training load over the last thirty user days.",
  },
  {
    id: "line:bodyBattery.7d", type: "line", source: "bodyBattery.7d", metric: "bodyBattery",
    windows: ROLLING_7, presentations: ["TREND", "NO_PREFERENCE"], spanDays: 7,
    unit: "", copy: "trend", says: "Body Battery over the last seven user days, as a line.",
  },
  {
    id: "days:bodyBattery.7d", type: "days", source: "bodyBattery.7d", metric: "bodyBattery",
    windows: ROLLING_7, presentations: ["DAILY_COMPARISON"], spanDays: 7,
    unit: "", copy: "daily", says: "Body Battery for each of the last seven user days.",
  },
  {
    id: "line:bodyBattery.30d", type: "line", source: "bodyBattery.30d", metric: "bodyBattery",
    windows: ROLLING_30, presentations: ["TREND", "NO_PREFERENCE", "DAILY_COMPARISON"], spanDays: 30,
    unit: "", copy: "trend", says: "Body Battery over the last thirty user days.",
  },
  {
    id: "days:steps.7d", type: "days", source: "steps.7d", metric: "steps",
    windows: ROLLING_7, presentations: ["DAILY_COMPARISON", "TREND", "NO_PREFERENCE"], spanDays: 7,
    unit: "", copy: "daily", says: "Steps for each of the last seven user days.",
  },
  {
    id: "line:weight.30d", type: "line", source: "weight.30d", metric: "weight",
    windows: ROLLING_30, presentations: ["TREND", "NO_PREFERENCE", "DAILY_COMPARISON"], spanDays: 30,
    unit: "kg", copy: "trend", says: "Body weight over the last thirty user days.",
  },
  {
    id: "line:hrv.7d", type: "line", source: "hrv.7d", metric: "nightHRV",
    windows: ROLLING_7, presentations: ["TREND", "NO_PREFERENCE", "DAILY_COMPARISON"], spanDays: 7,
    unit: "ms", copy: "trend", says: "Night HRV over the last seven user days.",
  },
];

/// Proves the admission list against the registries it points at. Called at module load:
/// a chart that stops declaring a source, or a source that is renamed, must not leave a
/// binding that renders something else.
export function assertBindings(bindings: FastBinding[] = FAST_BINDINGS): void {
  const seen = new Set<string>();
  for (const binding of bindings) {
    if (binding.id !== `${binding.type}:${binding.source}`) {
      throw new Error(`JEV_BINDING_ID_MISMATCH: ${binding.id}`);
    }
    if (seen.has(binding.id)) throw new Error(`JEV_BINDING_DUPLICATE: ${binding.id}`);
    seen.add(binding.id);
    const skill = SKILL_BY_TYPE.get(binding.type);
    if (!skill) throw new Error(`JEV_BINDING_UNKNOWN_CHART: ${binding.type}`);
    if (!skill.sources.includes(binding.source)) {
      throw new Error(`JEV_BINDING_CHART_REJECTS_SOURCE: ${binding.id}`);
    }
    if (!SOURCE_BY_ID.has(binding.source)) throw new Error(`JEV_BINDING_UNKNOWN_SOURCE: ${binding.source}`);
    if (!(binding.metric in FAST_METRICS)) throw new Error(`JEV_BINDING_UNKNOWN_METRIC: ${binding.metric}`);
    if (!binding.windows.length || !binding.presentations.length) {
      throw new Error(`JEV_BINDING_EMPTY_CANDIDATES: ${binding.id}`);
    }
    // A rolling source's span is the window it reads; the id carries it.
    const declared = Number(binding.source.match(/\.(\d+)d$/)?.[1] ?? 0);
    if (declared && declared !== binding.spanDays) {
      throw new Error(`JEV_BINDING_SPAN_MISMATCH: ${binding.id} reads ${declared}d`);
    }
    if (binding.spanDays && !declared) throw new Error(`JEV_BINDING_SPAN_UNBACKED: ${binding.id}`);
  }
  // Every chart named here must still exist in the skills catalogue.
  const types = new Set(CHART_SKILLS.map((s) => s.type));
  for (const binding of bindings) {
    if (!types.has(binding.type)) throw new Error(`JEV_BINDING_STALE_TYPE: ${binding.type}`);
  }
}

assertBindings();

/// A content fingerprint of the candidate catalogue. A threshold tuned against one set of
/// candidates does not carry over to a different set, so the version travels with the
/// decision and is logged with it.
export function catalogVersion(bindings: FastBinding[] = FAST_BINDINGS): string {
  const blob = JSON.stringify([
    Object.keys(FAST_METRICS),
    Object.keys(UNSUPPORTED_METRICS),
    bindings.map((b) => [b.id, b.metric, b.windows, b.presentations, b.spanDays ?? 0]),
  ]);
  // FNV-1a, 32 bit: a stable short fingerprint, not a security hash.
  let hash = 0x811c9dc5;
  for (let i = 0; i < blob.length; i++) {
    hash ^= blob.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `cat-${hash.toString(16).padStart(8, "0")}`;
}

export type ResolvedWindow = { from: string; to: string; label: TimeLabel; spanDays: number };

/// Dates are the server's job. Jev names a category; this turns it into a real user-day
/// range using the turn's own current day. Categories that need interpretation of the
/// user's words (an explicit date, an ambiguous phrase, nothing at all) resolve to null
/// and the request goes to the model.
///
/// ⚠️ "Last week" and "this month" are calendar periods, not rolling windows. They are not
/// in the resolvable set precisely so that they cannot be served as 7 or 30 rolling days.
export function resolveWindow(label: TimeLabel, currentDay: string): ResolvedWindow | null {
  switch (label) {
    case "TODAY":
      return { from: currentDay, to: currentDay, label, spanDays: 1 };
    case "YESTERDAY": {
      const day = addDays(currentDay, -1);
      return { from: day, to: day, label, spanDays: 1 };
    }
    // The night that ended this morning is read by the sleep sources from the current
    // user day: sleep attribution is theirs, and this range never becomes a day range.
    case "LAST_NIGHT":
      return { from: currentDay, to: currentDay, label, spanDays: 1 };
    case "LAST_7_USER_DAYS":
      return { from: addDays(currentDay, -6), to: currentDay, label, spanDays: 7 };
    case "LAST_30_USER_DAYS":
      return { from: addDays(currentDay, -29), to: currentDay, label, spanDays: 30 };
    default:
      return null;
  }
}

/// The legal bindings for one (metric, window, presentation) triple. An empty result is a
/// real answer: this product cannot draw that request today.
export function candidateBindings(
  metric: FastMetricId,
  label: TimeLabel,
  presentation: Presentation,
  bindings: FastBinding[] = FAST_BINDINGS,
): FastBinding[] {
  return bindings.filter((binding) =>
    binding.metric === metric &&
    binding.windows.includes(label) &&
    // UNKNOWN presentation never widens the candidate set; the router refuses it earlier.
    (presentation === "NO_PREFERENCE"
      ? binding.presentations.includes("NO_PREFERENCE")
      : binding.presentations.includes(presentation))
  );
}

/// The metrics that have at least one binding anywhere — used to keep the router's metric
/// question honest about what the product can actually draw.
export function bindableMetrics(bindings: FastBinding[] = FAST_BINDINGS): Set<FastMetricId> {
  return new Set(bindings.map((b) => b.metric));
}

export function bindingById(id: string, bindings: FastBinding[] = FAST_BINDINGS): FastBinding | undefined {
  return bindings.find((b) => b.id === id);
}
