// The words a deterministic turn is allowed to say.
//
// A fast turn has no model writing for it, so its four text slots come from here. Each
// template states the metric, the window, and what the source returned — and nothing else.
// It never explains a cause, never says a reading is normal, good, low or high, and never
// advises. Those are the model's job, on the routes that involve one.
//
// Every number these templates print comes from the source's own `agg` block or its hero,
// which the render tool harvests into the number ledger before the audit runs. There is no
// exemption: a template number that the source did not return fails the audit like any
// other, which is the point.

import type { FastBinding } from "./chart-selection.ts";

export type CopySource = {
  /// The source's aggregate block, as returned this turn.
  agg: Record<string, number | null>;
  /// The window in the source's own words: "TODAY", "7 DAYS".
  window: string;
  hero?: string;
  unit?: string;
};

export type FastCopy = { title: string; sentence: string; footer?: string };

const ZH: Record<string, string> = {
  intakeKcal: "摄入",
  proteinG: "蛋白质",
  meals: "今天的餐",
  trainingLoad: "训练负荷",
  bodyBattery: "身体电量",
  heartRate: "心率",
  steps: "步数",
  weight: "体重",
  nightHRV: "夜间 HRV",
  sleepStructure: "昨夜睡眠",
  sleepScore: "睡眠分数",
};

const EN: Record<string, string> = {
  intakeKcal: "EATEN",
  proteinG: "PROTEIN",
  meals: "MEALS",
  trainingLoad: "LOAD",
  bodyBattery: "BATTERY",
  heartRate: "HEART",
  steps: "STEPS",
  weight: "WEIGHT",
  nightHRV: "NIGHT HRV",
  sleepStructure: "SLEEP",
  sleepScore: "SLEEP SCORE",
};

const WINDOW_ZH: Record<string, string> = {
  TODAY: "今天",
  "7 DAYS": "近 7 天",
  "30 DAYS": "近 30 天",
  LAST_NIGHT: "昨夜",
};

function num(value: number | null | undefined): string | null {
  return typeof value === "number" && Number.isFinite(value) ? String(Math.round(value * 10) / 10) : null;
}

/// Title is "METRIC · WINDOW" within the envelope's 18-character cap.
function titleFor(binding: FastBinding, data: CopySource, en: boolean): string {
  const name = en ? EN[binding.metric] : ZH[binding.metric];
  const window = binding.windows[0] === "LAST_NIGHT"
    ? (en ? "LAST NIGHT" : "昨夜")
    : en
    ? data.window
    : WINDOW_ZH[data.window] ?? data.window;
  // The night's own charts already say the night in their name.
  const title = binding.metric === "sleepStructure" || binding.metric === "sleepScore"
    ? (en ? `SLEEP · ${window}` : `睡眠 · ${window}`)
    : `${name} · ${window}`;
  return title.slice(0, 18);
}

/// One sentence of fact per copy kind. The caller has already proved the numbers exist.
export function fastCopy(binding: FastBinding, data: CopySource, locale: string): FastCopy | null {
  const en = locale.startsWith("en");
  const title = titleFor(binding, data, en);
  const unit = binding.unit;
  const agg = data.agg ?? {};
  switch (binding.copy) {
    case "target": {
      const eaten = num(agg.eaten ?? agg.value);
      const target = num(agg.target ?? agg.goal);
      const left = num(agg.left);
      if (eaten === null || target === null) return null;
      const sentence = en
        ? `${eaten}${unit} of ${target}${unit}`
        : `${eaten}${unit} / 目标 ${target}${unit}`;
      const footer = left === null ? undefined : en ? `${left}${unit} left` : `还差 ${left}${unit}`;
      return { title, sentence: sentence.slice(0, 48), footer: footer?.slice(0, 42) };
    }
    case "trend": {
      const latest = num(agg.latest ?? agg.today);
      const mean = num(agg.mean);
      const min = num(agg.min);
      const max = num(agg.max);
      if (latest === null && mean === null) return null;
      const head = latest !== null
        ? (en ? `latest ${latest}${unit}` : `最近 ${latest}${unit}`)
        : (en ? `mean ${mean}${unit}` : `均值 ${mean}${unit}`);
      const tail = mean !== null && latest !== null
        ? (en ? `, mean ${mean}${unit}` : `，均值 ${mean}${unit}`)
        : "";
      const footer = min !== null && max !== null
        ? (en ? `min ${min} · max ${max}` : `最低 ${min} · 最高 ${max}`)
        : undefined;
      return { title, sentence: `${head}${tail}`.slice(0, 48), footer: footer?.slice(0, 42) };
    }
    case "daily": {
      const mean = num(agg.mean ?? agg.mean0);
      const days = num(agg.days);
      if (mean === null) return null;
      const sentence = en ? `daily mean ${mean}${unit}` : `每天平均 ${mean}${unit}`;
      const footer = days === null ? undefined : en ? `${days} days with data` : `${days} 天有记录`;
      return { title, sentence: sentence.slice(0, 48), footer: footer?.slice(0, 42) };
    }
    case "mix": {
      const deep = num(agg.deep);
      const light = num(agg.light);
      const awake = num(agg.awake);
      const total = num(agg.total ?? agg.asleep);
      if (deep === null && total === null) return null;
      const sentence = total !== null
        ? (en ? `${total} min recorded` : `记录 ${total} 分钟`)
        : (en ? `deep ${deep} min` : `深睡 ${deep} 分钟`);
      const parts = [deep, light, awake];
      const footer = parts.every((p) => p !== null)
        ? (en ? `deep ${deep} · light ${light} · awake ${awake}` : `深 ${deep} · 浅 ${light} · 醒 ${awake}`)
        : undefined;
      return { title, sentence: sentence.slice(0, 48), footer: footer?.slice(0, 42) };
    }
    case "structure": {
      const total = num(agg.total ?? agg.asleep ?? agg.minutes);
      if (total === null) return null;
      return {
        title,
        sentence: (en ? `${total} min recorded` : `记录 ${total} 分钟`).slice(0, 48),
      };
    }
    case "score": {
      const score = num(agg.score ?? agg.value ?? agg.total);
      if (score === null) return null;
      return { title, sentence: (en ? `score ${score} of 100` : `得分 ${score} / 100`).slice(0, 48) };
    }
    case "list": {
      const total = num(agg.total ?? agg.kcal);
      const count = num(agg.count ?? agg.meals);
      if (total === null && count === null) return null;
      const sentence = total !== null
        ? (en ? `${total}${unit} recorded` : `已记录 ${total}${unit}`)
        : (en ? `${count} recorded` : `已记录 ${count} 餐`);
      // ⚠️ Not "you have eaten N": an unrecorded meal is not a meal that did not happen.
      const footer = total !== null && count !== null
        ? (en ? `${count} entries` : `${count} 笔记录`)
        : undefined;
      return { title, sentence: sentence.slice(0, 48), footer: footer?.slice(0, 42) };
    }
    case "total": {
      const total = num(agg.total);
      const peak = num(agg.peak);
      if (total === null) return null;
      const sentence = en ? `${total}${unit ? " " + unit : ""} today` : `今天 ${total}${unit}`;
      const footer = peak === null ? undefined : en ? `busiest block ${peak}` : `最高一段 ${peak}`;
      return { title, sentence: sentence.slice(0, 48), footer: footer?.slice(0, 42) };
    }
    case "scalar": {
      const value = num(agg.value ?? agg.latest);
      if (value === null) return null;
      return { title, sentence: (en ? `${value}${unit} now` : `现在 ${value}${unit}`).slice(0, 48) };
    }
  }
}
