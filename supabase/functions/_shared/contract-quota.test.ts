import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { slowDownFrame } from "./contract.ts";

Deno.test("the slow-down frame tells the user in counts, never in money, and carries no digits", () => {
  const en = slowDownFrame("en-US");
  assertEquals(en.title, "SLOW DOWN");
  assertEquals(en.sentence.includes("tomorrow"), true);
  assertEquals(/\d/.test(`${en.title}${en.sentence}${en.data.headline}`), false);
  const zh = slowDownFrame("zh-CN");
  assertEquals(zh.title, "请慢一点");
  assertEquals(/\d/.test(`${zh.title}${zh.sentence}${zh.data.headline}`), false);
  const rate = slowDownFrame("en-US", "rate");
  assertEquals(rate.sentence.includes("Today"), false);
  assertEquals(/\d/.test(`${rate.title}${rate.sentence}${rate.data.headline}`), false);
});
