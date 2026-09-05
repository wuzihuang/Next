import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  gateTurnTool,
  initialToolGate,
  MAX_TURN_STEPS,
  nextTurnPhase,
} from "./turn-phase.ts";

const reads = ["data.read", "data.catalog", "day.get"];
const renders = ["screen.render.line", "screen.render.metric"];

function step(
  stepNumber: number,
  lastToolNames: string[],
  rereadUsed = false,
) {
  return nextTurnPhase({
    stepNumber,
    lastToolNames,
    rereadUsed,
    readTools: reads,
    renderTools: renders,
  });
}

Deno.test("the first step can only read", () => {
  const first = step(0, []);
  assertEquals(first.phase, 1);
  assertEquals(first.activeTools, reads);
  assertEquals(first.rereadUsed, false);
});

Deno.test("further reads stay in the evidence phase until the four-step budget", () => {
  const second = step(1, ["data.read"]);
  assertEquals(second.phase, 1);
  assertEquals(second.activeTools, reads);
  const fourth = step(3, ["data.read"]);
  assertEquals(fourth.phase, 1);
});

Deno.test("drawing offers one reread and then locks to charts", () => {
  const drawing = step(4, ["data.read"]);
  assertEquals(drawing.phase, 2);
  assertEquals(drawing.activeTools.includes("data.read"), true);
  assertEquals(drawing.activeTools.includes("screen.render.line"), true);
  const afterReread = step(5, ["data.read"], false);
  assertEquals(afterReread.rereadUsed, true);
  assertEquals(afterReread.activeTools, renders);
  const noSecondReread = step(5, ["data.read"], true);
  assertEquals(noSecondReread.activeTools, renders);
  assertEquals(MAX_TURN_STEPS, 6);
});

Deno.test("a photo-only turn with no read tools goes straight to drawing", () => {
  const result = nextTurnPhase({
    stepNumber: 0,
    lastToolNames: [],
    rereadUsed: false,
    readTools: [],
    renderTools: renders,
  });
  assertEquals(result.phase, 2);
  assertEquals(result.activeTools, renders);
});

Deno.test("the execute gate blocks drawing until one read, then allows one reread", () => {
  let state = initialToolGate(true);
  const firstDraw = gateTurnTool(state, "screen.render.line", true);
  assertEquals(firstDraw.allow, false);
  assertEquals(firstDraw.error, "READ_FIRST");
  const firstRead = gateTurnTool(state, "data.read", true);
  assertEquals(firstRead.allow, true);
  state = firstRead.next;
  const draw = gateTurnTool(state, "screen.render.metric", true);
  assertEquals(draw.allow, true);
  state = draw.next;
  assertEquals(state.phase, 2);
  const reread = gateTurnTool(state, "data.read", true);
  assertEquals(reread.allow, true);
  state = reread.next;
  const secondRead = gateTurnTool(state, "data.catalog", true);
  assertEquals(secondRead.allow, false);
  assertEquals(secondRead.error, "REREAD_USED");
});

Deno.test("four reads open drawing without a fifth being required first", () => {
  let state = initialToolGate(true);
  for (let i = 0; i < 4; i++) {
    const next = gateTurnTool(state, "data.read", true);
    assertEquals(next.allow, true);
    state = next.next;
  }
  assertEquals(state.phase, 2);
  const draw = gateTurnTool(state, "screen.render.line", true);
  assertEquals(draw.allow, true);
});

Deno.test("a photo path with no read tools never blocks drawing", () => {
  const state = initialToolGate(false);
  const draw = gateTurnTool(state, "screen.render.line", false);
  assertEquals(draw.allow, true);
  assertEquals(draw.next.phase, 2);
});
