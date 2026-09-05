// 07 · 11–15 · the chart skills: one per type the model may render, and the rules for
// picking between them. Board 07 draws each widget once with the data it is for; this is
// that catalogue as rules the agent can follow, and it is the single source for three
// things — the tool descriptions, the S11 section of the system prompt, and
// docs/prd/07-chart-skills.md (deno run supabase/scripts/chart-skills-doc.ts).
//
// The shape of a question decides the chart. A number now is a metric; a number against a
// full value is a ring; how a day moved is a line; how a week went is days; what a plate
// was is food. The skill says when, when not, and how the words should read.

import type { PanelType } from "./contract.ts";

export type Family = "number" | "curve" | "pair" | "column" | "arc" | "gauge" | "stack" | "grid" | "strip" | "rows";

export interface ChartSkill {
  type: PanelType;
  family: Family;
  /// Board 07's own subtitle for the widget.
  shape: string;
  /// When to pick it. One line, the whole rule.
  use: string;
  /// When not to — the next-best chart is named.
  avoid: string;
  /// Data sources the tool may name. Empty means the model supplies the words itself.
  sources: string[];
  /// How the four text slots should read on this chart.
  copy: string;
  /// F0 rule 06 · the page a tap lands on when the model gives none.
  target: "training" | "fuel" | "bodyBattery" | "composition" | "profile";
}

export const CHART_SKILLS: ChartSkill[] = [
  {
    type: "metric", family: "number", shape: "ANY SCALAR",
    use: "用户问的是此刻的一个数（心率现在多少、体重多少、今天吃了多少）。",
    avoid: "这个数有满值或目标时用 ring；问的是「怎么变」时用 line。",
    sources: [],
    copy: "value 只写数字与单位，来自本轮读到的值；label 写指标名；ref 写参照（+4 VS RHR 52）。",
    target: "profile",
  },
  {
    type: "text", family: "number", shape: "BIG WORD · NO DATA",
    use: "没有任何一张图配得上这个问题：一句判断、一个方向、或者数据是空的（写 ——）。",
    avoid: "手里有一串数据就别用 text，把它画出来。",
    sources: [],
    copy: "headline 是屏内唯一高光（≤ 12 字，柠檬绿大字）；eyebrow 写依据，sub 写补充；sentence 写在 facts 行。",
    target: "profile",
  },
  {
    type: "line", family: "curve", shape: "TIME SERIES",
    use: "问的是一天之内或一段日子里某个指标怎么变：心率、压力、BODY BATTERY 曲线、体重走势、负荷/电量/摄入的 7–30 天趋势。",
    avoid: "只有一个数时用 metric；一周里逐天比较用 days；两条线对照用 dual。",
    sources: ["heart.today", "stress.today", "bodyBattery.today", "trainingLoad.7d", "trainingLoad.30d", "bodyBattery.7d", "bodyBattery.30d", "intakeKcal.7d", "intakeKcal.30d", "weight.30d", "weight.90d", "hrv.7d"],
    copy: "title 写「指标 · 窗口」；sentence 说形状（一个高峰、平了、往下走），footer 放 min/max/mean。",
    target: "training",
  },
  {
    type: "band", family: "pair", shape: "HI / LO PAIR",
    use: "问的是每天的高低两条边——一周心率最高与最低的走势。",
    avoid: "只关心一条线用 line；不是高低成对的数据不要用。",
    sources: ["heart.range.7d"],
    copy: "hero 写今天的低–高；sentence 说两条边有没有拉开或收窄。",
    target: "training",
  },
  {
    type: "bars", family: "column", shape: "INTRADAY BINS",
    use: "一天里分时段的量：今天的步数按两小时、今天每一餐的 kcal。",
    avoid: "逐天比较用 days；连续变化用 line。",
    sources: ["steps.today", "mealsBySlot.today", "trainingLoad.7d", "intakeKcal.7d"],
    copy: "hero 写总量与单位；sentence 指出最高的那一段；footer 写峰值时段。",
    target: "training",
  },
  {
    type: "days", family: "column", shape: "WEEK VS TARGET",
    use: "一周里每天多少：步数、训练负荷、电量、摄入逐天比较。",
    avoid: "一天之内用 bars；有正有负用 delta。",
    sources: ["steps.7d", "trainingLoad.7d", "bodyBattery.7d", "intakeKcal.7d"],
    copy: "hero 写 7 天均值；sentence 点名最高和最低的那天；footer 写今天对均值。",
    target: "training",
  },
  {
    type: "hypnogram", family: "strip", shape: "SLEEP STAGES",
    use: "问的是昨晚睡得怎么样、几点睡几点醒、深睡够不够：按分钟画成清醒 / 浅睡 / 深睡三条泳道。",
    avoid: "只想知道各段总时长用 split；只想要一个数用 metric。",
    sources: ["sleep.stages"],
    copy: "title 写 SLEEP · 起止时刻；hero 是总时长；sentence 说深睡块的形状；footer 写醒了几次。",
    target: "bodyBattery",
  },
  {
    type: "split", family: "stack", shape: "SLEEP MIX",
    use: "昨晚深睡 / 浅睡 / 清醒各占多少：一条堆叠轨加三行图例。",
    avoid: "想看逐分钟的形状用 hypnogram。",
    sources: ["sleep.mix"],
    copy: "hero 是总时长（7H38 这种）；sentence 说深睡占比；footer 写三段分钟数。",
    target: "bodyBattery",
  },
  {
    type: "o2night", family: "curve", shape: "NIGHT SPO2",
    use: "问的是夜间血氧：一整夜的曲线、均值、最低点。不是呼吸暂停分级，不数掉到 90 以下几次。",
    avoid: "手环没写夜间自动血氧时这张图没有数据，改用 split 或 text。白天点测不上这张图。",
    sources: ["o2.night"],
    copy: "hero 写均值百分比；sentence 说曲线的形状；footer 写最低值。不要写 guide 90，不要数 dips。",
    target: "bodyBattery",
  },
  {
    type: "sparks", family: "rows", shape: "MULTI-METRIC ROWS",
    use: "用户想一眼看几项指标（心率、压力、步数）各自的近况。",
    avoid: "只问一项时用 line 或 metric。",
    sources: ["vitals.7d"],
    copy: "没有 hero；sentence 说三项里哪一项在动；footer 写窗口。",
    target: "training",
  },
  {
    type: "ring", family: "arc", shape: "GOAL PROGRESS",
    use: "一个数对它的满值或目标：TRAINING LOAD 对 21、蛋白质对目标、热量对目标。",
    avoid: "没有目标的数用 metric；BODY BATTERY 用 battery。",
    sources: ["load.today", "protein.today", "kcal.today"],
    copy: "sentence 写「X 的 Y」或还差多少；footer 写目标从哪来。",
    target: "training",
  },
  {
    type: "gauge", family: "gauge", shape: "ZONED 0–100",
    use: "一个 0–100 且有分区含义的读数：此刻的压力（REST / MID / HIGH）。",
    avoid: "没有分区的数用 metric 或 ring。",
    sources: ["stress.now"],
    copy: "hero 写数值与分区名；sentence 说它在往哪边走；footer 写读数时刻。",
    target: "bodyBattery",
  },
  {
    type: "battery", family: "arc", shape: "BODY BATTERY",
    use: "问的是 BODY BATTERY 此刻多少、或者没有更好的判断时的回落帧。",
    avoid: "问一天怎么充放用 line + bodyBattery.today。",
    sources: ["battery.now"],
    copy: "title 固定 BODY BATTERY；sentence 写「现在 N」；footer 写醒来时的值。",
    target: "bodyBattery",
  },
  {
    type: "cells", family: "grid", shape: "COUNT OF N",
    use: "做到了几天：一周里称了几天体重、记了几天餐。",
    avoid: "关心数值本身时用 line 或 days。",
    sources: ["weighins.7d", "mealsLogged.7d"],
    copy: "hero 写「N OF 7」；sentence 说缺的是哪几天。",
    target: "composition",
  },
  {
    type: "zones", family: "strip", shape: "LIVE WORKOUT",
    use: "今天在五个心率区间各待了多少分钟。",
    avoid: "问负荷总量用 ring + load.today；问构成用 workout。",
    sources: ["zones.today"],
    copy: "hero 写占比最大的区间与分钟；footer 写五个分钟数与峰值心率。",
    target: "training",
  },
  {
    type: "table", family: "rows", shape: "KV ROWS",
    use: "几对「名称 → 值」并排看：今天负荷的构成、一次体成分的几个字段。",
    avoid: "有时间顺序用 events；带趋势用 sparks。",
    sources: ["segments.today"],
    copy: "rows ≤ 5，value 里的数字必须来自本轮读到的值；hero 写总数。",
    target: "training",
  },
  {
    type: "workout", family: "rows", shape: "SESSION CARD",
    use: "今天的一次或几次训练：抬高心率的时段、各自的贡献。",
    avoid: "没有抬高心率的时段就没有 workout，改用 ring + load.today 或 text。",
    sources: ["segments.today"],
    copy: "hero 写今天的 TRAINING LOAD；sentence 点名最重的一段；footer 写分钟与平均心率。",
    target: "training",
  },
  {
    type: "events", family: "rows", shape: "DAY LOG",
    use: "用户问今天发生了什么、记录了什么：餐、训练时段、称重、体成分按时间排列。",
    avoid: "只问一类事情时用那一类的图。",
    sources: ["events.today"],
    copy: "hero 写事件数；sentence 说最重要的一件；footer 写最早和最晚的时刻。",
    target: "profile",
  },
  {
    type: "heat", family: "grid", shape: "WEEK × HOUR",
    use: "一周里的规律：哪一天的哪个时段心率或步数最高。",
    avoid: "只问今天用 bars 或 line。",
    sources: ["heart.heat.7d", "steps.heat.7d"],
    copy: "hero 写最亮的格子（星期 + 时段）；sentence 说这个规律；footer 写 UNLIT → DIM → MID → BRIGHT。",
    target: "training",
  },
  {
    type: "food", family: "rows", shape: "ONE ITEM",
    use: "用户报了一顿吃的（S10）：渲染草稿帧，action 固定「确认记录」，由屏幕那一侧提交。",
    avoid: "用户问的是今天吃了多少（不是在报餐）时用 meal 或 balance。",
    sources: [],
    copy: "name 写菜名，portion 写份量；kcal 与三个宏量只在工具给过时才写，绝不估；sentence 说这一餐大致是什么。",
    target: "fuel",
  },
  {
    type: "meal", family: "rows", shape: "ITEM LIST",
    use: "今天记了哪几餐、各多少 kcal。",
    avoid: "问剩多少额度用 ring + kcal.today；问三大营养素用 fuel。",
    sources: ["meals.today"],
    copy: "hero 写总 kcal；sentence 说还有哪一餐没记（没记 ≠ 0）；footer 写蛋白质合计。",
    target: "fuel",
  },
  {
    type: "fuel", family: "stack", shape: "MACRO BUDGET",
    use: "三大营养素今天吃进对目标：蛋白质、碳水、脂肪各差多少。",
    avoid: "只问热量用 balance 或 ring + kcal.today。",
    sources: ["macros.today"],
    copy: "hero 是缺口最大的那个（服务端算好）；sentence 说怎么补；footer 写三对 eaten/target。",
    target: "fuel",
  },
  {
    type: "balance", family: "stack", shape: "IN VS OUT",
    use: "今天吃进对消耗：净差是多少、还能吃多少。",
    avoid: "没记餐的一天没有 balance（没记 ≠ 0），改用 meal 或 text。",
    sources: ["balance.today"],
    copy: "hero 写 in − out（带符号）；sentence 说方向；footer 写 in / out / 目标。",
    target: "fuel",
  },
  {
    type: "recomp", family: "grid", shape: "DAY GRID · 12 W",
    use: "12 周里体成分的方向：多少次测量脂肪往下走。",
    avoid: "问具体数值用 dual；问最近几次变化用 delta。",
    sources: ["composition.recomp"],
    copy: "hero 写 N DOWN · M UP；sentence 说趋势；footer 写 12 周脂肪量变化。",
    target: "composition",
  },
  {
    type: "delta", family: "column", shape: "DAILY Δ · SIGNED",
    use: "有正有负的逐次变化：两次体成分之间脂肪量的增减、一周每天吃进减消耗。",
    avoid: "全是正数的量用 days 或 bars。",
    sources: ["composition.delta", "deltaKcal.7d"],
    copy: "hero 写净变化（带符号）；sentence 写几次向上几次向下；footer 写窗口。",
    target: "composition",
  },
  {
    type: "dual", family: "pair", shape: "FAT vs LEAN",
    use: "两条趋势对照：12 周脂肪量 vs 瘦体重。",
    avoid: "只有一条线用 line；问方向用 recomp。",
    sources: ["composition.dual"],
    copy: "hero 写最新体脂率；sentence 说两条线有没有交叉或拉开；footer 写各自的变化量。",
    target: "composition",
  },
];

export const SKILL_BY_TYPE = new Map(CHART_SKILLS.map((s) => [s.type, s]));

export function chartSkillsForScope(sourceScope?: string[]): ChartSkill[] {
  if (!sourceScope) return CHART_SKILLS;
  const allowed = new Set(sourceScope);
  const foodQuestion = sourceScope.some((source) =>
    /^(protein|kcal|meals|mealsBySlot|mealsLogged|macros|balance|deltaKcal)\./.test(source)
  );
  return CHART_SKILLS.filter((skill) =>
    skill.sources.some((source) => allowed.has(source)) ||
    skill.type === "text" ||
    skill.type === "metric" ||
    (skill.type === "food" && foodQuestion)
  );
}

/// The tool description: what it shows, when, when not. The source list is on the
/// parameter, so it is not repeated here.
export function toolDescription(s: ChartSkill): string {
  return `${s.shape} · ${s.use} 不用于：${s.avoid}`;
}

/// S11 · the router. Compact on purpose: one line per group of charts, so the whole
/// section reads in a glance and a wrong line can be rolled back on its own.
export function chartChoicePrompt(sourceScope?: string[], en = true): string {
  if (sourceScope) {
    const choices = chartSkillsForScope(sourceScope)
      .map((skill) => `· ${skill.type} → ${skill.use}`);
    return [
      "S11 CHART CHOICE",
      en
        ? "Each chart on screen is a screen.render.<type> tool. Read the numbers first, then pick from the charts offered this turn:"
        : "屏上的每一种图都是一个 screen.render.<type> 工具。先用读工具拿到数字，再从本轮提供的图里选：",
      ...choices,
      en
        ? "Series charts only pick a source; the server fills the points. If a tool returns NO_DATA, switch chart or write —— as text. One render per turn."
        : "序列类的图只选数据源，点由服务端填；工具返回 NO_DATA 就换图或用 text 写 ——。一轮只渲染一次。",
    ].join("\n");
  }
  return en
    ? [
      "S11 CHART CHOICE",
      "Each chart on screen is a screen.render.<type> tool. Read the numbers first, then pick a chart that matches the question's shape:",
      "· one number now → metric; a number against a target → ring; 0–100 with zones → gauge; BODY BATTERY now → battery",
      "· change inside a day or across tens of days → line; day-by-day for a week → days; amounts by hour → bars",
      "· daily high and low → band; week × hour pattern → heat; signed changes → delta; two trends → dual",
      "· training: zone minutes → zones; today's load makeup → workout / table; what happened today → events",
      "· last night: minute stages → hypnogram; three-way split → split; overnight SpO2 → o2night",
      "· fuel: macros vs target → fuel; in vs out → balance; which meals today → meal; user reports a plate → food",
      "· several metrics together → sparks; days completed → cells; 12-week composition direction → recomp",
      "Series charts only pick a source; the server fills the points. If a tool returns NO_DATA, switch chart or write —— as text. Do not invent points.",
      "Use text only when no chart fits. One render per turn.",
    ].join("\n")
    : [
      "S11 CHART CHOICE",
      "屏上的每一种图都是一个 screen.render.<type> 工具。先用读工具拿到数字，再按问题的形状选图：",
      "· 此刻一个数 → metric；一个数对满值/目标 → ring；0–100 带分区 → gauge；BODY BATTERY 此刻 → battery",
      "· 一天之内或几十天里怎么变 → line；一周逐天比较 → days；一天里分时段的量 → bars",
      "· 每天高低两条边 → band；一周×时段的规律 → heat；有正有负的逐次变化 → delta；两条趋势对照 → dual",
      "· 训练：区间分钟 → zones；今天负荷的构成 → workout / table；今天发生了什么 → events",
      "· 昨夜：逐分钟分期 → hypnogram；三段占比 → split；夜间血氧 → o2night",
      "· 燃料：三大营养素对目标 → fuel；吃进对消耗 → balance；今天记了哪几餐 → meal；用户报一顿吃的 → food",
      "· 几项指标一起看 → sparks；做到了几天 → cells；12 周体成分的方向 → recomp",
      "序列类的图只选数据源，点由服务端填；工具返回 NO_DATA 就换一种图或用 text 写 ——，不许自己造点。",
      "没有任何图配得上时才用 text。一轮只渲染一次。",
    ].join("\n");
}
