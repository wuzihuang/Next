import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { systemPrompt } from "./prompt.ts";

Deno.test("chat selects presentation by question without changing the home panel", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const home = systemPrompt(locale);
    const chat = systemPrompt(locale, "chat");
    assert(chat.includes(locale.toLowerCase().startsWith("zh") ? "AI 教练" : "AI Coach"));
    assert(chat.includes("screen.render.text"));
    assert(!home.includes("You are AI Coach"));
    assert(home.includes("workflow.coach"));
    assert(home.includes("S0 IDENTITY"));
    assert(!chat.includes("workflow.coach"));
    assert(!systemPrompt(locale, "plan").includes("workflow.coach"));
    assertEquals(systemPrompt(locale, "panel"), home);
  }
});

Deno.test("panel and coach prompts route small talk without data or refusal in either language", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const home = systemPrompt(locale, "panel");
    const chat = systemPrompt(locale, "chat");
    assert(home.includes(locale === "en-US" ? "call workflow.coach alone before any read or answer" : "先单独调用 workflow.coach，不读取数据、不先回答"));
    assert(home.includes(locale === "en-US" ? "original message and attached image unchanged" : "用户原话和附图原样带过去"));
    assert(home.includes(locale === "en-US" ? "Keep personal health measurements" : "个人健康测量、健康知识解释、估餐或记录饮食、设备操作继续使用当前面板流程"));
    assert(chat.includes(locale === "en-US" ? "small talk, greetings and feelings without personal data reads or web search" : "闲聊、打招呼和分享感受时自然接话，不需要读取个人数据或联网搜索"));
  }
});

Deno.test("different questions keep the system prompt byte-for-byte identical", () => {
  const a = systemPrompt("en-US");
  const b = systemPrompt("en-US", "panel");
  const c = systemPrompt("zh-CN");
  assertEquals(a, b);
  assert(a.includes("S11 CHART CHOICE"));
  assert(a.includes("call read for that metric"));
  assert(a.includes("ENTITIES (find / write)"));
  assert(a.includes("Wear run is a consecutive worn-day count"));
  assert(c.includes("连续佩戴是佩戴日个数"));
  assert(!a.includes("this turn:"));
  assert(!a.includes("the same source"));
  assert(!a.includes("完全相同的 source"));
  assert(c.includes("先用 read 读取"));
  assert(c.includes("ENTITIES (find / write)"));
});

Deno.test("a food photo is estimated directly instead of paying for two vision reads", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const prompt = systemPrompt(locale, "chat");
    assert(prompt.includes(locale === "zh-CN"
      ? "报餐直接用 meal.estimate，包括看不出菜名的食物照片"
      : "use meal.estimate directly, including for an unknown food photo"));
    assert(prompt.includes(locale === "zh-CN" ? "不要先调用 image.inspect" : "do not call image.inspect first"));
    assert(!prompt.includes("Identify an unknown food photo with image.inspect first"));
    assert(!prompt.includes("未知食物照片先 image.inspect"));
  }
});

Deno.test("advice has its own evidence and variation rules without the panel's no-advice/slot constraints", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const prompt = systemPrompt(locale, "plan");
    assert(prompt.includes("evidence_ids"));
    assert(prompt.includes("recent_suggestions"));
    assert(prompt.includes("reference_ids"));
    assert(prompt.includes("tasks=[]"));
    assert(prompt.includes("REVIEWED GUIDANCE"));
    assert(!prompt.includes("S5 SLOT LIMITS"));
    assert(!prompt.includes("No encouragement, no praise, no comfort, no advice"));
    assert(!prompt.includes("用户打的勾"));
  }
});

// #26 · one intake target, and it belongs to the profile goal. Coach answers in prose,
// which is where a second target — a BMR multiplier spoken as "about 2900" — came from,
// so the rule has to reach that surface as well as the panel.
Deno.test("both speaking surfaces are told the day's intake target has one owner", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const zh = locale.startsWith("zh");
    for (const surface of ["panel", "chat"] as const) {
      const prompt = systemPrompt(locale, surface);
      assert(prompt.includes("FUEL TARGET"));
      assert(prompt.includes("day_fuel.target_in"));
      assert(prompt.includes(zh ? "不许另算一套摄入数" : "Never derive a second intake figure"));
      assert(prompt.includes(zh ? "就直说看不到当日目标" : "say the day's target cannot be seen"));
    }
  }
});

// #27 · a switch on the band is changed because the user asked, never because a sync
// finished or a night came back without overnight SpO2.
Deno.test("no surface may turn an automatic measurement on by itself", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const zh = locale.startsWith("zh");
    for (const surface of ["panel", "chat"] as const) {
      const prompt = systemPrompt(locale, surface);
      assert(prompt.includes(zh ? "自动测量开关" : "An automatic-measurement switch"));
      assert(prompt.includes(zh ? "同步完成不是要求" : "A finished sync is not that request"));
    }
  }
});

// #28 · the one night field the user owns, and the rule that it is theirs to ask for.
Deno.test("both speaking surfaces know how to correct a night, and not to do it unasked", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const zh = locale.startsWith("zh");
    for (const surface of ["panel", "chat"] as const) {
      const prompt = systemPrompt(locale, surface);
      assert(prompt.includes("sleep_night"));
      assert(prompt.includes(zh ? "一夜按醒来那天命名" : "named by the day it was woken on"));
      assert(prompt.includes(zh ? "用户没提改睡眠时间，就不要去改" : "never done unless the user asked for it"));
    }
  }
});
