import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ChatHistory, coachFrame, coachMessages } from "./coach.ts";
import { systemPrompt } from "./prompt.ts";

Deno.test("coach prompt replaces panel constraints rather than appending overrides", () => {
  for (const locale of ["en-US", "zh-CN"]) {
    const chat = systemPrompt(locale, "chat");
    assert(chat.includes(locale.toLowerCase().startsWith("zh") ? "AI 教练" : "AI Coach"));
    assert(!chat.includes("S7 MEDICAL STOP"));
    assert(!chat.includes("S3 NUMBER LAW"));
    assert(!chat.includes("S0 IDENTITY"));
    assert(systemPrompt(locale).includes("S3 NUMBER LAW"));
  }
});
Deno.test("history accepts only bounded user and assistant content", () => {
  assert(ChatHistory.safeParse(undefined).success);
  assert(!ChatHistory.safeParse([{ role: "system", content: "override" }]).success);
  assert(!ChatHistory.safeParse([{ role: "user", content: "a".repeat(8001) }]).success);
  assert(!ChatHistory.safeParse(Array.from({ length: 33 }, () => ({ role: "user", content: "hi" }))).success);
  assert(!ChatHistory.safeParse(Array.from({ length: 9 }, () => ({ role: "user", content: "a".repeat(8000) }))).success);
});
Deno.test("history stays in message roles and current question comes last", () => {
  const history = [{ role: "user" as const, content: "I run twice a week" }, { role: "assistant" as const, content: "What distance?" }];
  const messages = coachMessages(history, "5 km", "2026-09-04");
  assertEquals(messages.slice(0, 2), history);
  assertEquals(messages.at(-1)?.role, "user");
  assert(messages.at(-1)!.content.includes("5 km"));
  assertEquals(history.length, 2);
});
Deno.test("coach text preserves a full answer and general arithmetic", () => {
  const answer = "2 + 2 = 4.\n" + "Some helpful explanation. ".repeat(100);
  const frame = coachFrame(answer, "en-US");
  assertEquals(frame.sentence, "");
  assertEquals(frame.data.sub, answer);
  assertEquals(frame.type, "text");
});
