// A conservative pre-router for the model's tool catalogue.
//
// It does not answer the question and never chooses a final widget. It only removes unrelated
// source descriptions when one domain is explicit. Ambiguous text returns null, which means the
// model receives the full catalogue exactly as before. An explicit comparison among the three
// vitals carried by vitals.7d is also deterministic and stays on that single source.

interface DomainRoute {
  matches: RegExp;
  sources: (text: string) => string[];
}

const WEEK = /(这|本|上|近|最近|过去)?\s*(周|星期|7\s*天|seven\s*days?|week)/i;
const RANGE = /(范围|区间|最高|最低|高低|max|min|range|high|low)/i;
const VITALS_COMPARE = /(比较|对比|一起|几项|概览|compare|versus|\bvs\b|overview)/i;
const VITAL_SIGNALS = [
  /(心率|心跳|脉搏|heart\s*rate|\bhr\b|pulse)/i,
  /(压力|stress)/i,
  /(步数|走了|走路|steps?|walking)/i,
];

const ROUTES: DomainRoute[] = [
  {
    matches: /(睡眠|睡得|入睡|醒来|深睡|浅睡|清醒|血氧|sleep|asleep|awake|deep sleep|spo2|oxygen)/i,
    sources: (text) =>
      /(血氧|spo2|oxygen)/i.test(text)
        ? ["o2.night"]
        : ["sleep.stages", "sleep.mix"],
  },
  {
    matches: /(\bhrv\b|心率变异)/i,
    sources: () => ["hrv.7d"],
  },
  {
    matches: /(心率|心跳|脉搏|heart\s*rate|\bhr\b|pulse)/i,
    sources: (text) => {
      if (/(心率区间|心率分区|zone)/i.test(text)) return ["zones.today"];
      if (WEEK.test(text) || RANGE.test(text)) return ["heart.range.7d"];
      return ["heart.today"];
    },
  },
  {
    matches: /(压力|stress)/i,
    sources: (text) => (/(趋势|变化|曲线|trend|change|curve)/i.test(text) ? ["stress.today"] : ["stress.now"]),
  },
  {
    matches: /(步数|走了|走路|steps?|walking)/i,
    sources: (text) => (WEEK.test(text) ? ["steps.7d"] : ["steps.today"]),
  },
  {
    matches: /(训练负荷|运动负荷|training\s*load|strain)/i,
    sources: (text) => {
      if (/(构成|时段|segment|session)/i.test(text)) return ["segments.today"];
      if (WEEK.test(text)) return ["trainingLoad.7d"];
      return ["load.today"];
    },
  },
  {
    matches: /(body\s*battery|身体电量|恢复电量|电量)/i,
    sources: (text) => {
      if (WEEK.test(text)) return ["bodyBattery.7d"];
      if (/(趋势|变化|曲线|trend|change|curve)/i.test(text)) return ["bodyBattery.today"];
      return ["battery.now"];
    },
  },
  {
    matches: /(蛋白质|热量|卡路里|吃了|餐|营养|protein|calorie|kcal|meal|macro|food)/i,
    sources: (text) => {
      if (/(蛋白质|protein)/i.test(text)) return ["protein.today"];
      if (/(营养|macro)/i.test(text)) return ["macros.today"];
      if (WEEK.test(text)) return ["mealsLogged.7d"];
      return ["kcal.today", "meals.today", "mealsBySlot.today"];
    },
  },
  {
    matches: /(体脂|脂肪量|瘦体重|体成分|体重|body\s*fat|fat\s*mass|lean\s*mass|composition|weight)/i,
    sources: (text) => {
      if (/(体重|weight)/i.test(text) && !/(体脂|脂肪|body\s*fat|fat\s*mass)/i.test(text)) {
        return ["weight.30d", "weight.90d"];
      }
      return ["composition.dual", "composition.delta", "composition.recomp"];
    },
  },
  {
    matches: /(发生了什么|今天做了什么|时间线|events?|timeline)/i,
    sources: () => ["events.today"],
  },
  {
    matches: /(各项指标|生命体征|整体状态|vitals?|overview)/i,
    sources: () => ["vitals.7d"],
  },
];

export function sourceScopeFor(text: string): string[] | null {
  const vitalCount = VITAL_SIGNALS.filter((signal) => signal.test(text)).length;
  if (vitalCount >= 2 && VITALS_COMPARE.test(text)) return ["vitals.7d"];
  const routes = ROUTES.filter((route) => route.matches.test(text));
  if (routes.length !== 1) return null;
  return routes[0].sources(text);
}
