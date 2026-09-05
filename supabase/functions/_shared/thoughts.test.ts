// deno test --allow-none _shared/thoughts.test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ThoughtStream, width } from "./thoughts.ts";

function collect(chunks: string[], banned: RegExp[] = [], max?: number): string[] {
  const out: string[] = [];
  const s = new ThoughtStream((t) => out.push(t), banned, max);
  for (const c of chunks) s.push(c);
  s.flush();
  return out;
}

Deno.test("a sentence per line, whatever the chunk boundaries", () => {
  // The same reasoning delivered one character at a time must cut identically.
  const text = "用户问为什么today这么累。先看昨夜睡眠。5小时12分，比周均少1小时40分。";
  const whole = collect([text]);
  const perChar = collect([...text]);
  assertEquals(whole, perChar);
  assertEquals(whole, [
    "用户问为什么today这么累",
    "先看昨夜睡眠",
    "5小时12分，比周均少1小时40分",
  ]);
});

Deno.test("a long clause breaks at the last comma, not mid-word", () => {
  const out = collect([
    "HRV dropped from 38 to 31 over two nights, which is a real decline, so the fatigue is recovery and not training load",
  ]);
  for (const line of out) {
    if (width(line) > 34.1) throw new Error(`line too wide: ${width(line)} ${line}`);
  }
  assertEquals(out[0], "HRV dropped from 38 to 31 over two");
  assertEquals(out.at(-1), "training load");
});

Deno.test("markdown, bullets and fragments never reach the LED", () => {
  assertEquals(collect(["**Step 1:** read the week.\n- 嗯\n`series.get` is the tool to call.\n"]), [
    "Step 1: read the week",
    "series.get is the tool to call",
  ]);
});

Deno.test("a repeated line prints once", () => {
  assertEquals(collect(["Reading the week.\nReading the week.\nReading today.\n"]), [
    "Reading the week",
    "Reading today",
  ]);
});

Deno.test("F5 C7 · a banned phrase is dropped, not printed", () => {
  assertEquals(collect(["Your sleep is short.\nYou have sleep apnea for sure.\nSo rest now.\n"], [/apnea/i]), [
    "Your sleep is short",
    "So rest now",
  ]);
});

Deno.test("the tail flushes even without a full stop", () => {
  assertEquals(collect(["So it is the sleep, not the strain"]), ["So it is the sleep, not the strain"]);
});

Deno.test("a runaway reasoning block is capped", () => {
  const flood = Array.from({ length: 200 }, (_, i) => `Thought number ${i} about the week.`).join("");
  assertEquals(collect([flood], [], 5).length, 5);
});

Deno.test("model reasoning reaches both surfaces before the final answer", () => {
  const out: string[] = [];
  const stream = new ThoughtStream((text) => out.push(text));
  stream.accept({ type: "reasoning", textDelta: "先看昨夜睡眠。" });
  assertEquals(out, ["先看昨夜睡眠"]);
  stream.accept({ type: "reasoning", textDelta: "再看训练量" });
  stream.accept({ type: "text-delta", textDelta: "最终回答" });
  assertEquals(out, ["先看昨夜睡眠", "再看训练量"]);
});

Deno.test("reasoning tail appears before tool execution and is not duplicated at step end", () => {
  const out: string[] = [];
  const stream = new ThoughtStream((text) => out.push(text));
  stream.accept({ type: "reasoning", textDelta: "Checking recovery" });
  stream.accept({ type: "tool-call" });
  assertEquals(out, ["Checking recovery"]);
  stream.accept({ type: "step-finish" });
  stream.accept({ type: "text-delta", textDelta: "Final answer" });
  assertEquals(out, ["Checking recovery"]);
});
