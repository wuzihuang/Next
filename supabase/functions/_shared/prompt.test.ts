import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { systemPrompt } from "./prompt.ts";

Deno.test("chat selects presentation by question without changing the home panel", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const home = systemPrompt(locale);
    const chat = systemPrompt(locale, "chat");
    assert(chat.includes(locale.toLowerCase().startsWith("zh") ? "AI 教练" : "AI Coach"));
    assert(chat.includes("screen.render.text"));
    assert(!home.includes("AI Coach"));
    assertEquals(systemPrompt(locale, "panel"), home);
  }
});

Deno.test("different questions keep the system prompt byte-for-byte identical", () => {
  const a = systemPrompt("en-US");
  const b = systemPrompt("en-US", "panel");
  const c = systemPrompt("zh-CN");
  assertEquals(a, b);
  assert(a.includes("S11 CHART CHOICE"));
  assert(a.includes("data.read"));
  assert(a.includes("Wear run is a consecutive worn-day count"));
  assert(c.includes("连续佩戴是佩戴日个数"));
  assert(!a.includes("this turn:"));
  assert(!a.includes("the same source"));
  assert(!a.includes("完全相同的 source"));
  assert(c.includes("data.read"));
});

