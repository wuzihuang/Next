import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { systemPrompt } from "./prompt.ts";

Deno.test("chat selects presentation by question without changing the home panel", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const home = systemPrompt(locale);
    const chat = systemPrompt(locale, undefined, "chat");
    assert(chat.includes("AI Coach"));
    assert(chat.includes("screen.render.text"));
    assert(!home.includes("AI Coach"));
    assertEquals(systemPrompt(locale, undefined, "panel"), home);
  }
});

Deno.test("different questions keep the system prompt byte-for-byte identical", () => {
  const a = systemPrompt("en-US", ["heart.today"]);
  const b = systemPrompt("en-US", ["sleep.stages", "sleep.mix"]);
  const c = systemPrompt("en-US");
  assertEquals(a, b);
  assertEquals(b, c);
  assert(a.includes("S11 CHART CHOICE"));
  assert(!a.includes("this turn:"));
});

