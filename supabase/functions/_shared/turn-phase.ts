// ADR 0018 · three steps: read → act → render.
//
// read   · read tools, phone tools and workflow.ready. Calling a phone tool moves the
//          turn to act; calling ready moves it to render.
// act    · phone tools, workflow.ready and one workflow.reread. Reads are closed: what the
//          model wanted to know it should have asked before it touched the band.
// render · one screen.render / plan.render, or one workflow.reread back to read.
//
// Every step re-sends the whole context, so the budget is eight model steps and four of
// them may be reads. A phone tool suspends the turn (the phone runs it and resumes the
// turn); the step counter keeps counting across the resume.

export const MAX_TURN_STEPS = 8;
export const READ_STEP_BUDGET = 4;
export const MAX_RESUMES = 3;
export const WORKFLOW_READY = "workflow.ready";
export const WORKFLOW_REREAD = "workflow.reread";

export function isRenderTool(name: string): boolean {
  return name.startsWith("screen.render") || name === "plan.render";
}

export type TurnPhase = "read" | "act" | "render" | "done";

export type TurnWorkflow = {
  phase: TurnPhase;
  completedSteps: number;
  readSteps: number;
  rereadUsed: boolean;
  renderClaimed: boolean;
  controlClaimed: boolean;
  phoneClaimed: boolean;
  readTools: string[];
  phoneTools: string[];
  renderTools: string[];
  // Tools permitted for the current model step.
  activeTools: string[];
};

function refreshActiveTools(state: TurnWorkflow): void {
  let names: string[] = [];
  if (state.completedSteps < MAX_TURN_STEPS) {
    const rereadFits = !state.rereadUsed && state.readTools.length > 0 &&
      MAX_TURN_STEPS - state.completedSteps >= 3;
    if (state.phase === "read") {
      names = [...state.readTools, ...state.phoneTools, WORKFLOW_READY];
    } else if (state.phase === "act") {
      names = [...state.phoneTools, WORKFLOW_READY];
      if (rereadFits) names.push(WORKFLOW_REREAD);
    } else if (state.phase === "render") {
      names = [...state.renderTools];
      if (rereadFits) names.push(WORKFLOW_REREAD);
    }
  }
  state.activeTools.splice(0, state.activeTools.length, ...names);
}

export function createTurnWorkflow(
  readTools: string[],
  renderTools: string[],
  phoneTools: string[] = [],
  start: TurnPhase = readTools.length > 0 ? "read" : "render",
): TurnWorkflow {
  const state: TurnWorkflow = {
    phase: start,
    completedSteps: 0,
    readSteps: 0,
    rereadUsed: false,
    renderClaimed: false,
    controlClaimed: false,
    phoneClaimed: false,
    readTools: [...readTools],
    phoneTools: [...phoneTools],
    renderTools: [...renderTools],
    activeTools: [],
  };
  refreshActiveTools(state);
  return state;
}

/// A suspended turn stores the workflow as plain JSON and rebuilds it here.
export function restoreTurnWorkflow(raw: unknown): TurnWorkflow {
  const r = raw as Partial<TurnWorkflow>;
  const state = createTurnWorkflow(r.readTools ?? [], r.renderTools ?? [], r.phoneTools ?? [], r.phase === "done" ? "render" : (r.phase ?? "read"));
  state.completedSteps = r.completedSteps ?? 0;
  state.readSteps = r.readSteps ?? 0;
  state.rereadUsed = r.rereadUsed ?? false;
  refreshActiveTools(state);
  return state;
}

export function serializeTurnWorkflow(state: TurnWorkflow): Record<string, unknown> {
  return {
    phase: state.phase, completedSteps: state.completedSteps, readSteps: state.readSteps,
    rereadUsed: state.rereadUsed, readTools: state.readTools, phoneTools: state.phoneTools,
    renderTools: state.renderTools,
  };
}

export type ToolGateDecision = {
  allow: boolean;
  error?: "TOOL_NOT_ACTIVE" | "STEP_ALREADY_COMMITTED" | "ONE_PHONE_TOOL_PER_STEP";
};

// Claim synchronously before execute awaits. Parallel tool calls cannot draw
// twice, mix a render with a reread transition, or send two phone tools at once —
// the phone runs one and the turn resumes with one result.
export function gateTurnTool(
  state: TurnWorkflow,
  toolName: string,
): ToolGateDecision {
  if (!state.activeTools.includes(toolName)) {
    return { allow: false, error: "TOOL_NOT_ACTIVE" };
  }
  const render = state.renderTools.includes(toolName);
  const control = toolName === WORKFLOW_READY || toolName === WORKFLOW_REREAD;
  const phone = state.phoneTools.includes(toolName);
  if (render || control) {
    if (state.renderClaimed || state.controlClaimed) {
      return { allow: false, error: "STEP_ALREADY_COMMITTED" };
    }
    if (render) state.renderClaimed = true;
    else state.controlClaimed = true;
  }
  if (phone) {
    if (state.phoneClaimed) return { allow: false, error: "ONE_PHONE_TOOL_PER_STEP" };
    state.phoneClaimed = true;
  }
  return { allow: true };
}

export type TurnToolResult = { toolName: string; result?: unknown };

function resultFlag(result: unknown, key: string): boolean {
  return typeof result === "object" && result !== null &&
    (result as Record<string, unknown>)[key] === true;
}

// Transitions happen after every tool in this model step has settled. Reading
// alone does not switch phases: the model declares readiness or hits its budget.
export function finishTurnStep(
  state: TurnWorkflow,
  toolResults: readonly TurnToolResult[],
): void {
  const succeeded = (name: string, flag: string) =>
    state.activeTools.includes(name) &&
    toolResults.some((item) =>
      item.toolName === name && resultFlag(item.result, flag)
    );
  const phoneCalled = state.phoneTools.some((name) =>
    state.activeTools.includes(name) && toolResults.some((item) => item.toolName === name));
  state.completedSteps += 1;
  if (state.phase === "read") {
    state.readSteps += 1;
    if (succeeded(WORKFLOW_READY, "ok")) {
      state.phase = "render";
    } else if (phoneCalled) {
      state.phase = "act";
    } else if (state.rereadUsed || state.readSteps >= READ_STEP_BUDGET) {
      state.phase = "render";
    }
  } else if (state.phase === "act") {
    if (succeeded(WORKFLOW_READY, "ok")) {
      state.phase = "render";
    } else if (succeeded(WORKFLOW_REREAD, "ok")) {
      state.rereadUsed = true;
      state.phase = "read";
    }
  } else if (state.phase === "render") {
    if (state.renderTools.some((name) => succeeded(name, "rendered"))) {
      state.phase = "done";
    } else if (succeeded(WORKFLOW_REREAD, "ok")) {
      state.rereadUsed = true;
      state.phase = "read";
    }
  }
  if (state.completedSteps >= MAX_TURN_STEPS) state.phase = "done";
  state.renderClaimed = false;
  state.controlClaimed = false;
  state.phoneClaimed = false;
  refreshActiveTools(state);
}
