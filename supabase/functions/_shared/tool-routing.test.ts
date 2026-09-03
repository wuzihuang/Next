import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chartSkillsForScope } from "./skills.ts";
import { SOURCE_IDS } from "./sources.ts";
import { sourceScopeFor } from "./tool-routing.ts";

Deno.test("routes a clear single-domain question to a small source set", () => {
  assertEquals(sourceScopeFor("你看看我昨天睡得怎么样"), ["sleep.stages", "sleep.mix"]);
  assertEquals(sourceScopeFor("How is my heart rate today?"), ["heart.today"]);
  assertEquals(sourceScopeFor("这周步数怎么样"), ["steps.7d"]);
  assertEquals(sourceScopeFor("现在压力多少"), ["stress.now"]);
});

Deno.test("uses the narrow source for explicit variants", () => {
  assertEquals(sourceScopeFor("今天各心率区间多久"), ["zones.today"]);
  assertEquals(sourceScopeFor("昨晚血氧怎么样"), ["o2.night"]);
  assertEquals(sourceScopeFor("这周 HRV 怎么样"), ["hrv.7d"]);
  assertEquals(sourceScopeFor("今天训练负荷由什么构成"), ["segments.today"]);
  assertEquals(sourceScopeFor("体重趋势"), ["weight.30d", "weight.90d"]);
  assertEquals(sourceScopeFor("比较心率和压力"), ["vitals.7d"]);
  assertEquals(sourceScopeFor("heart rate vs steps"), ["vitals.7d"]);
});

Deno.test("scoped chart tools retain only compatible renderers and safe fallbacks", () => {
  assertEquals(
    chartSkillsForScope(["sleep.stages", "sleep.mix"]).map((skill) => skill.type),
    ["metric", "text", "hypnogram", "split"],
  );
  assertEquals(
    chartSkillsForScope(["heart.today"]).map((skill) => skill.type),
    ["metric", "text", "line"],
  );
});

Deno.test("does not prune ambiguous questions", () => {
  assertEquals(sourceScopeFor("我最近怎么样"), null);
  assertEquals(sourceScopeFor("Should I train today?"), null);
});

Deno.test("every routed source exists in the source catalogue", () => {
  const questions = [
    "昨晚睡得怎么样",
    "现在心率",
    "今天压力",
    "这周步数",
    "训练负荷",
    "身体电量",
    "今天蛋白质",
    "体脂趋势",
    "今天发生了什么",
    "vitals overview",
  ];
  const known = new Set<string>(SOURCE_IDS);
  for (const question of questions) {
    for (const source of sourceScopeFor(question) ?? []) {
      if (!known.has(source)) throw new Error(`Unknown routed source: ${source}`);
    }
  }
});
