// ADR 0018 · three steps: read → act → render.
//
// read   · evidence, phone tools and direct text/food/metric output. Phone actions move to
//          act; health.prepare resumes in read. Ready opens measurement-chart rendering.
// act    · phone tools, direct text/food/metric output, ready and one reread. Health reads
//          are closed.
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
export const WORKFLOW_COACH = "workflow.coach";
export const HEALTH_PREPARE = "health.prepare";
// ⚠️ metric is direct because its number need not come from a health read: the band's
// battery arrives in availability.device and the ledger already vouches for every digit.
// Without it the prompt said "band battery → metric" while the phase offered only text,
// and the model spent two render steps finding that out before falling back to text.
const DIRECT_OUTPUTS = new Set(["screen.render.text", "screen.render.food", "screen.render.metric"]);

/// ⚠️ ADR 0031 · a guided turn has no range left to choose: the server resolved it before
/// the model ran, and the chart was chosen for it. `workflow.ready` exists to let the model
/// settle the chart's window, so making it walk through the gate anyway costs a whole model
/// step to confirm a decision nobody is waiting on — measured as four wasted steps before
/// the frame appeared. Such a workflow marks its render tools as direct output instead.
/// The evidence rules do not move: the ledger, the claims and the audit are unchanged.

export function isRenderTool(name: string): boolean {
  return name.startsWith("screen.render") || name === "plan.render";
}

export type TurnPhase = "read" | "act" | "render" | "done";

export type TurnWorkflow = {
  phase: TurnPhase;
  /// Render tools usable without passing through `workflow.ready` first.
  outputReady: boolean;
  completedSteps: number;
  readSteps: number;
  rereadUsed: boolean;
  renderClaimed: boolean;
  controlClaimed: boolean;
  phoneClaimed: boolean;
  readClaimed: boolean;
  coachClaimed: boolean;
  coachAllowed: boolean;
  coachHandoff: boolean;
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
    const direct = (name: string) => state.outputReady || DIRECT_OUTPUTS.has(name);
    // ⚠️ A guided turn is not offered `workflow.ready` at all: its only power is to set the
    // chart's window, and the server already resolved that one. Offering it would let the
    // model quietly widen or move the range a decision was made against.
    const ready = state.outputReady ? [] : [WORKFLOW_READY];
    if (state.phase === "read") {
      names = [...state.readTools, ...state.phoneTools, ...state.renderTools.filter(direct), ...ready];
      if (state.coachAllowed && !state.coachHandoff && MAX_TURN_STEPS - state.completedSteps >= 2) names.push(WORKFLOW_COACH);
    } else if (state.phase === "act") {
      names = [...state.phoneTools, ...state.renderTools.filter(direct), ...ready];
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
  coachAllowed = false,
  outputReady = false,
): TurnWorkflow {
  const state: TurnWorkflow = {
    phase: start,
    outputReady,
    completedSteps: 0,
    readSteps: 0,
    rereadUsed: false,
    renderClaimed: false,
    controlClaimed: false,
    phoneClaimed: false,
    readClaimed: false,
    coachClaimed: false,
    coachAllowed,
    coachHandoff: false,
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
  const state = createTurnWorkflow(r.readTools ?? [], r.renderTools ?? [], r.phoneTools ?? [], r.phase === "done" ? "render" : (r.phase ?? "read"), r.coachAllowed ?? false, r.outputReady ?? false);
  state.completedSteps = r.completedSteps ?? 0;
  state.readSteps = r.readSteps ?? 0;
  state.rereadUsed = r.rereadUsed ?? false;
  state.coachHandoff = r.coachHandoff ?? false;
  refreshActiveTools(state);
  return state;
}

export function serializeTurnWorkflow(state: TurnWorkflow): Record<string, unknown> {
  return {
    phase: state.phase, completedSteps: state.completedSteps, readSteps: state.readSteps,
    rereadUsed: state.rereadUsed, readTools: state.readTools, phoneTools: state.phoneTools,
    renderTools: state.renderTools,
    coachAllowed: state.coachAllowed, coachHandoff: state.coachHandoff,
    outputReady: state.outputReady,
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
  const read = state.readTools.includes(toolName);
  const coach = toolName === WORKFLOW_COACH;
  // A handoff changes the system prompt and output contract at the step boundary.
  // It must own the whole step, whichever concurrent tool claimed it first.
  if (state.coachClaimed || (coach && (state.readClaimed || state.phoneClaimed || state.renderClaimed || state.controlClaimed))) {
    return { allow: false, error: "STEP_ALREADY_COMMITTED" };
  }
  if (coach) state.coachClaimed = true;
  // Direct answers are legal in read/act, but never race pending evidence or effects.
  if ((render && (state.readClaimed || state.phoneClaimed)) ||
    (read && (state.renderClaimed || state.phoneClaimed)) ||
    (phone && (state.renderClaimed || state.readClaimed || state.controlClaimed)) ||
    (control && state.phoneClaimed)) {
    return { allow: false, error: "STEP_ALREADY_COMMITTED" };
  }
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
  if (read) state.readClaimed = true;
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
    state.activeTools.includes(name) && toolResults.some((item) => item.toolName === name && resultFlag(item.result, "suspended")));
  state.completedSteps += 1;
  if (state.renderTools.some((name) => succeeded(name, "rendered"))) {
    state.phase = "done";
  } else if (succeeded(WORKFLOW_COACH, "ok")) {
    state.coachHandoff = true;
  } else if (state.phase === "read") {
    state.readSteps += 1;
    if (succeeded(WORKFLOW_READY, "ok")) {
      state.phase = "render";
    } else if (phoneCalled) {
      if (!toolResults.some(item => item.toolName === HEALTH_PREPARE && resultFlag(item.result, "suspended"))) state.phase = "act";
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
  state.readClaimed = false;
  state.coachClaimed = false;
  refreshActiveTools(state);
}
