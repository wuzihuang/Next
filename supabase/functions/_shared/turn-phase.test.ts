import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createTurnWorkflow,
  finishTurnStep,
  restoreTurnWorkflow,
  serializeTurnWorkflow,
  gateTurnTool,
  MAX_TURN_STEPS,
  WORKFLOW_READY,
  WORKFLOW_REREAD,
} from "./turn-phase.ts";

const reads = ["data.read", "data.catalog"];
const renders = ["screen.render.line", "screen.render.metric"];
const ready = { toolName: WORKFLOW_READY, result: { ok: true } };
const reread = { toolName: WORKFLOW_REREAD, result: { ok: true } };
const read = { toolName: "data.read", result: { rows: [1] } };

Deno.test("model chooses data tools and declares readiness after one step", () => {
  const state = createTurnWorkflow(reads, renders);
  const activeReference = state.activeTools;
  assertEquals(state.activeTools, [...reads, WORKFLOW_READY]);
  assertEquals(gateTurnTool(state, "data.catalog").allow, true);
  assertEquals(gateTurnTool(state, "data.read").allow, true);
  assertEquals(gateTurnTool(state, WORKFLOW_READY).allow, true);
  // A ready call cannot unlock rendering while parallel reads are executing.
  assertEquals(gateTurnTool(state, renders[0]).allow, false);
  finishTurnStep(state, [read, ready]);
  assertEquals(state.phase, "render");
  assertEquals(state.activeTools === activeReference, true);
  assertEquals(state.activeTools, [...renders, WORKFLOW_REREAD]);
  assertEquals(gateTurnTool(state, reads[0]).allow, false);
});

Deno.test("read budget counts model steps, not parallel tool invocations", () => {
  const state = createTurnWorkflow(reads, renders);
  for (let step = 0; step < 4; step++) {
    assertEquals(state.phase, "read");
    for (let call = 0; call < 7; call++) {
      assertEquals(gateTurnTool(state, "data.read").allow, true);
    }
    finishTurnStep(state, Array.from({ length: 7 }, () => read));
  }
  assertEquals(state.phase, "render");
  // Four read steps of eight leave room for one reread; it disappears after two more.
  assertEquals(state.activeTools, [...renders, WORKFLOW_REREAD]);
  finishTurnStep(state, []);
  finishTurnStep(state, []);
  assertEquals(state.activeTools, renders);
  assertEquals(gateTurnTool(state, WORKFLOW_REREAD).allow, false);
});

Deno.test("failed control result does not advance the workflow", () => {
  const state = createTurnWorkflow(reads, renders);
  finishTurnStep(state, [{ toolName: WORKFLOW_READY, result: { ok: false } }]);
  assertEquals(state.phase, "read");
  finishTurnStep(state, [ready]);
  assertEquals(state.phase, "render");
  finishTurnStep(state, [{
    toolName: WORKFLOW_REREAD,
    result: { error: "failed" },
  }]);
  assertEquals(state.phase, "render");
  assertEquals(state.rereadUsed, false);
});

Deno.test("one explicit reread allows parallel reads then returns to rendering", () => {
  const state = createTurnWorkflow(reads, renders);
  finishTurnStep(state, [ready]);
  assertEquals(gateTurnTool(state, WORKFLOW_REREAD).allow, true);
  assertEquals(gateTurnTool(state, renders[0]).allow, false);
  assertEquals(gateTurnTool(state, reads[0]).allow, false);
  finishTurnStep(state, [reread]);
  assertEquals(state.phase, "read");
  assertEquals(state.rereadUsed, true);
  assertEquals(gateTurnTool(state, reads[0]).allow, true);
  assertEquals(gateTurnTool(state, reads[1]).allow, true);
  finishTurnStep(state, [read]);
  assertEquals(state.phase, "render");
  assertEquals(state.activeTools, renders);
  assertEquals(gateTurnTool(state, WORKFLOW_REREAD).allow, false);
});

Deno.test("reread is hidden when too few steps remain to read and render", () => {
  const state = createTurnWorkflow(reads, renders);
  finishTurnStep(state, [ready]);
  for (let step = 1; step < MAX_TURN_STEPS - 2; step++) finishTurnStep(state, []);
  assertEquals(state.activeTools, renders);
});

Deno.test("parallel renders are claimed once and a failed render can retry next step", () => {
  const state = createTurnWorkflow(reads, renders);
  finishTurnStep(state, [ready]);
  assertEquals(gateTurnTool(state, renders[0]).allow, true);
  assertEquals(gateTurnTool(state, renders[1]), {
    allow: false,
    error: "STEP_ALREADY_COMMITTED",
  });
  assertEquals(gateTurnTool(state, WORKFLOW_REREAD).allow, false);
  finishTurnStep(state, [{
    toolName: renders[0],
    result: { rendered: false },
  }]);
  assertEquals(state.phase, "render");
  assertEquals(gateTurnTool(state, renders[1]).allow, true);
  finishTurnStep(state, [{ toolName: renders[1], result: { rendered: true } }]);
  assertEquals(state.phase, "done");
  assertEquals(state.activeTools, []);
  assertEquals(gateTurnTool(state, renders[0]).allow, false);
});

Deno.test("unknown tools and inactive result names cannot change phases", () => {
  const state = createTurnWorkflow(reads, renders);
  assertEquals(gateTurnTool(state, "legacy.estimate").allow, false);
  finishTurnStep(state, [{ toolName: renders[0], result: { rendered: true } }]);
  assertEquals(state.phase, "read");
});

Deno.test("turn without data tools can render immediately and cannot reread", () => {
  const state = createTurnWorkflow([], renders);
  assertEquals(state.phase, "render");
  assertEquals(state.activeTools, renders);
  assertEquals(gateTurnTool(state, renders[0]).allow, true);
});

Deno.test("eight steps exhaust workflow even when render keeps failing", () => {
  const state = createTurnWorkflow(reads, renders);
  for (let step = 0; step < MAX_TURN_STEPS; step++) finishTurnStep(state, []);
  assertEquals(state.completedSteps, 8);
  assertEquals(state.phase, "done");
  assertEquals(state.activeTools, []);
});

// ADR 0018 · the act step.
const phones = ["device.alarm.set", "device.find"];

Deno.test("a phone tool moves read to act, closes reads, and one reread reopens them", () => {
  const state = createTurnWorkflow(reads, renders, phones);
  assertEquals(state.activeTools, [...reads, ...phones, WORKFLOW_READY]);
  assertEquals(gateTurnTool(state, "device.alarm.set").allow, true);
  assertEquals(gateTurnTool(state, "device.find"), { allow: false, error: "ONE_PHONE_TOOL_PER_STEP" });
  finishTurnStep(state, [{ toolName: "device.alarm.set", result: { suspended: true } }]);
  assertEquals(state.phase, "act");
  assertEquals(gateTurnTool(state, "data.read").allow, false);
  assertEquals(gateTurnTool(state, WORKFLOW_REREAD).allow, true);
  finishTurnStep(state, [{ toolName: WORKFLOW_REREAD, result: { ok: true } }]);
  assertEquals(state.phase, "read");
  finishTurnStep(state, [ready]);
  assertEquals(state.phase, "render");
  assertEquals(state.activeTools, renders);
});

Deno.test("act then ready renders; the workflow survives a serialize and restore", () => {
  const state = createTurnWorkflow(reads, renders, phones);
  finishTurnStep(state, [{ toolName: "device.find", result: { suspended: true } }]);
  const restored = restoreTurnWorkflow(JSON.parse(JSON.stringify(serializeTurnWorkflow(state))));
  assertEquals(restored.phase, "act");
  assertEquals(restored.completedSteps, 1);
  assertEquals(restored.activeTools, state.activeTools);
  finishTurnStep(restored, [ready]);
  assertEquals(restored.phase, "render");
});

Deno.test("the plan surface starts in render with plan.render and may reread once", () => {
  const state = createTurnWorkflow(reads, ["plan.render"], phones, "render");
  assertEquals(state.activeTools, ["plan.render", WORKFLOW_REREAD]);
  finishTurnStep(state, [{ toolName: WORKFLOW_REREAD, result: { ok: true } }]);
  assertEquals(state.phase, "read");
  assertEquals(gateTurnTool(state, "data.read").allow, true);
});
