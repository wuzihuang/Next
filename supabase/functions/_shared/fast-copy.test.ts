import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fastCopy } from "./fast-copy.ts";
import { bindingById, FAST_BINDINGS } from "./chart-selection.ts";

const binding = (id: string) => bindingById(id)!;

Deno.test("a target template states eaten, target and what is left, in the app's language", () => {
  const data = { agg: { eaten: 1450, target: 2100, left: 650, pct: 69 }, window: "TODAY" };
  assertEquals(fastCopy(binding("ring:kcal.today"), data, "zh-CN"), {
    title: "摄入 · 今天", sentence: "1450kcal / 目标 2100kcal", footer: "还差 650kcal",
  });
  assertEquals(fastCopy(binding("ring:kcal.today"), data, "en-US"), {
    title: "EATEN · TODAY", sentence: "1450kcal of 2100kcal", footer: "650kcal left",
  });
});

Deno.test("a trend template states the reading and the window's own statistics", () => {
  const copy = fastCopy(binding("line:weight.30d"), {
    agg: { latest: 72.4, mean: 72.9, min: 71.8, max: 74.1, days: 21 }, window: "30 DAYS",
  }, "zh-CN")!;
  assertEquals(copy.title, "体重 · 近 30 天");
  assertEquals(copy.sentence, "最近 72.4kg，均值 72.9kg");
  assertEquals(copy.footer, "最低 71.8 · 最高 74.1");
});

Deno.test("a template never invents a number it was not given", () => {
  // No target read means no target sentence: the ring's words come from the ring's data.
  assertEquals(fastCopy(binding("ring:kcal.today"), { agg: { eaten: 1450, target: null }, window: "TODAY" }, "zh-CN"), null);
  assertEquals(fastCopy(binding("line:weight.30d"), { agg: { latest: null, mean: null }, window: "30 DAYS" }, "zh-CN"), null);
  assertEquals(fastCopy(binding("score:sleep.score.night"), { agg: { score: null }, window: "TODAY" }, "zh-CN"), null);
  // A missing "left" drops the footer rather than computing one.
  const partial = fastCopy(binding("ring:kcal.today"), { agg: { eaten: 1450, target: 2100, left: null }, window: "TODAY" }, "zh-CN")!;
  assertEquals(partial.footer, undefined);
});

Deno.test("every template stays inside the envelope's caps and says nothing evaluative", () => {
  const generous = {
    agg: {
      eaten: 12345, target: 22222, left: 9877, latest: 123.4, mean: 456.7, min: 12.3, max: 789.1,
      days: 30, deep: 123, light: 456, awake: 78, total: 657, score: 88, count: 6, value: 99,
    },
    window: "30 DAYS",
  };
  const banned = /好|不错|正常|偏低|偏高|应该|建议|good|normal|low|high|should/;
  for (const b of FAST_BINDINGS) {
    for (const locale of ["zh-CN", "en-US"]) {
      const copy = fastCopy(b, generous, locale);
      if (!copy) continue;
      assert(copy.title.length <= 18, `${b.id} title: ${copy.title}`);
      assert(copy.sentence.length <= 48, `${b.id} sentence: ${copy.sentence}`);
      assert((copy.footer?.length ?? 0) <= 42, `${b.id} footer: ${copy.footer}`);
      const blob = `${copy.title} ${copy.sentence} ${copy.footer ?? ""}`;
      assertEquals(banned.test(blob), false, `${b.id} (${locale}) judges the reading: ${blob}`);
    }
  }
});

Deno.test("the meals template counts records, never claims what was eaten", () => {
  const copy = fastCopy(binding("meal:meals.today"), { agg: { total: 1450, count: 3 }, window: "TODAY" }, "zh-CN")!;
  assertEquals(copy.sentence, "已记录 1450kcal");
  assertEquals(copy.footer, "3 笔记录");
  // "recorded", not "eaten": an unlogged meal is not a meal that did not happen.
  assertEquals(copy.sentence.includes("吃"), false);
});
