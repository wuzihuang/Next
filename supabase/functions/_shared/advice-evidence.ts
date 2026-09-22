// Evidence selection, not a second health score. Comparisons describe this person's
// observations; the model decides whether a difference merits a practical suggestion.
import { addDays } from "./calendar.ts";

export type EvidenceRow = Record<string, unknown>;
export type AdviceEvidence = {
  id: string; metric: string; day: string; value: number; unit: string;
  observed_at?: string; calculated_at?: string; comparison?: Record<string, number | string>;
  scale_max?: number;
  context?: Record<string, unknown>;
};
export const one = (v: unknown): EvidenceRow => (Array.isArray(v) ? v[0] : v) as EvidenceRow ?? {};
const number = (v: unknown): number | null => typeof v === "number" && Number.isFinite(v) ? v : null;
const round = (v: number) => Math.round(v * 10) / 10;
const median = (xs: number[]) => {
  const sorted = [...xs].sort((a, b) => a - b), mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

export function adviceEvidence(days: EvidenceRow[], sleeps: EvidenceRow[], ticks: EvidenceRow[], today: string, now: Date): AdviceEvidence[] {
  const out: AdviceEvidence[] = [], yesterday = addDays(today, -1);
  const add = (metric: string, row: EvidenceRow, value: unknown, unit: string, history: number[] = [], context?: Record<string, unknown>) => {
    const v = number(value);
    if (v === null) return;
    const day = String(row.user_day);
    const baseline = history.length >= 5 ? median(history) : null;
    out.push({ id: `${metric}:${day}`, metric, day, value: round(v), unit,
      ...(metric === "training_load" ? { scale_max: 21 } : metric === "body_battery" ? { scale_max: 100 } : {}),
      ...(typeof row.observed_at === "string" ? { observed_at: row.observed_at } : {}),
      ...(typeof row.calculation_as_of === "string" ? { calculated_at: row.calculation_as_of } : {}),
      ...(baseline !== null ? { comparison: { median: round(baseline), delta: round(v - baseline), observations: history.length, kind: "prior_completed_days" } } : {}),
      ...(context ? { context } : {}),
    });
  };
  // A partial today never enters the baseline for a completed yesterday.
  for (const row of days.filter(r => r.user_day === today || r.user_day === yesterday)) {
    const history = days.filter(r => String(r.user_day) < String(row.user_day));
    const prior = (key: string) => history.flatMap(r => number(r[key]) === null ? [] : [r[key] as number]);
    const completedDay = String(row.user_day) < today;
    const training = one(one(row.daily_training).evidence), target = one(training.target);
    const load = number(row.training_load), suggested = number(target.target);
    add("training_load", row, load, "0–21", completedDay ? prior("training_load") : [], {
      completed_day: completedDay, suggested_target: suggested,
      remaining_to_target: suggested !== null && load !== null ? round(Math.max(0, suggested - load)) : null,
      target_basis: Object.keys(target).length ? target : null,
      recorded_sessions: Array.isArray(training.sessions) ? training.sessions : [],
    });
    const reserve = one(row.reserve_daily), night = one(reserve.night_inputs), fuel = one(row.day_fuel);
    const drivers = one(reserve.drain_drivers);
    const observed = typeof drivers.observed_at === "string" ? Date.parse(drivers.observed_at) : NaN;
    // A re-settlement does not make an old observation current. Unknown/assumed or
    // low-confidence reserve anchors cannot justify a personalized adjustment.
    if (Number.isFinite(observed) && observed <= now.getTime() && drivers.assumed_anchor === false && ["medium", "high"].includes(String(drivers.confidence))) {
      add("body_battery", { ...row, observed_at: drivers.observed_at }, reserve.current_value ?? row.reserve_score, "0–100", [], {
        wake_value: reserve.wake_value ?? null, confidence: drivers.confidence,
        assumed_anchor: drivers.assumed_anchor, coverage: drivers.coverage ?? null,
        is_current: String(row.user_day) === today && now.getTime() - observed <= 1800_000,
      });
    }
    for (const [metric, key, unit] of [["night_hrv", "hrv", "ms"], ["night_rhr", "rhr", "bpm"]]) {
      if (night[`${key}_eligible`] !== true) continue;
      const baselineNights = number(night[`${key}_nights`]);
      const baseline = (baselineNights ?? 0) >= 5 ? number(night[`${key}_base`]) : null;
      const wake = sleeps.find(s => s.user_day === row.user_day)?.wake_at;
      add(metric, { ...row, observed_at: wake }, night[key], unit, [], { personal_baseline: baseline,
        eligible: true, coverage: night[`${key}_coverage`] ?? null, baseline_nights: baselineNights,
        delta: baseline !== null && number(night[key]) !== null ? round((night[key] as number) - baseline) : null });
    }
    if (fuel.intake_state !== "UNLOGGED") {
      add("recorded_protein", row, fuel.protein_in_g, "g", [], {
        target_g: fuel.protein_g ?? null, intake_state: fuel.intake_state,
        recording_is_partial: true, // Missing meals never establish dietary deficiency.
      });
    }
  }
  const completedSleeps = sleeps.filter(r => typeof r.wake_at === "string" && Date.parse(r.wake_at) <= now.getTime() && number(r.total_minutes) !== null && (r.total_minutes as number) > 0);
  const sleep = completedSleeps.filter(r => r.user_day === today || r.user_day === yesterday).at(-1);
  if (sleep) {
    const history = completedSleeps.filter(r => String(r.user_day) < String(sleep.user_day)).map(r => r.total_minutes as number);
    add("sleep_minutes", { ...sleep, observed_at: sleep.wake_at }, sleep.total_minutes, "min", history, { sleep_start: sleep.sleep_start, wake_at: sleep.wake_at });
  }
  // Stress is a device index, not a diagnosis. Reject unworn/zero/future ticks and
  // require repeated recent observations; an isolated spike is not a current trend.
  const canonical = new Map<string, EvidenceRow>();
  for (const tick of ticks) {
    const ts = typeof tick.ts === "string" ? Date.parse(tick.ts) : NaN;
    if (!Number.isFinite(ts)) continue;
    const key = new Date(ts).toISOString(), prior = canonical.get(key);
    if (!prior || (tick.src === "band" && prior.src !== "band")) canonical.set(key, tick);
  }
  const valid = [...canonical.values()].filter(r => typeof r.ts === "string" && Date.parse(r.ts) <= now.getTime()
    && Date.parse(r.ts) >= now.getTime() - 86400_000 && (number(r.heart) ?? 0) > 0
    && (number(r.stress) ?? 0) > 0 && (r.stress as number) <= 100)
    .sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
  const recent = valid.filter(r => Date.parse(String(r.ts)) >= now.getTime() - 3600_000);
  const prior = valid.filter(r => Date.parse(String(r.ts)) < now.getTime() - 3600_000);
  const latest = recent.at(-1);
  if (recent.length >= 3 && latest && now.getTime() - Date.parse(String(latest.ts)) <= 1800_000
    && Date.parse(String(latest.ts)) - Date.parse(String(recent[0].ts)) >= 600_000) {
    const value = round(recent.reduce((sum, r) => sum + (r.stress as number), 0) / recent.length);
    const baseline = prior.length >= 12 ? median(prior.map(r => r.stress as number)) : null;
    out.push({ id: `stress:${today}`, metric: "stress", day: today, value, unit: "device index 0–100", scale_max: 100, observed_at: String(latest.ts),
      context: { window_minutes: 60, observations: recent.length, sustained: true, clinical_threshold: null },
      ...(baseline !== null ? { comparison: { median: round(baseline), delta: round(value - baseline), observations: prior.length, kind: "earlier_in_rolling_day_not_long_term_baseline" } } : {}),
    });
  }
  return out;
}

// Reviewed public guidance. It is never personal measurement evidence, and no private
// health history is sent to a search provider to retrieve these fixed references.
export const ADVICE_REFERENCES = [
  { id: "recovery", title: "ACSM / ECSS · Training and Recovery Consensus", url: "https://onlinelibrary.wiley.com/doi/10.1080/17461391.2012.730061",
    guidance: "Training needs sufficient recovery. When recent heavier load coincides with weaker recovery observations, consider an easier session and perceived effort. No single wearable marker diagnoses overtraining; never derive a precise training dose or disease from it." },
  { id: "protein", title: "NIH ODS · Exercise and Athletic Performance", url: "https://ods.od.nih.gov/factsheets/ExerciseAndAthleticPerformance-HealthProfessional/",
    guidance: "Adequate dietary protein supports muscle repair after exercise. Spread protein-containing foods across eating occasions; respect dietary preferences. Do not infer deficiency from fatigue or incomplete logs, prescribe supplements, or exceed a personal target just because load increased." },
  { id: "sleep", title: "NIH NHLBI · Healthy Sleep Habits", url: "https://www.nhlbi.nih.gov/health/sleep-deprivation/healthy-sleep-habits",
    guidance: "Protect sufficient sleep opportunity and a consistent schedule. A quiet wind-down, less bright light before bed, and avoiding late caffeine can help. Choose the adjustment relevant to the observed sleep pattern; do not infer insomnia from wearable staging." },
  { id: "relaxation", title: "NIH NCCIH · Relaxation Techniques", url: "https://www.nccih.nih.gov/health/relaxation-techniques-what-you-need-to-know",
    guidance: "Comfortable slow breathing and progressive muscle relaxation may help perceived stress; evidence varies. Suggest a quiet pause and gentle breathing without breath holds or force. Do not promise a lower wearable score or diagnose anxiety from the device index." },
] as const;
