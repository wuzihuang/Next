export const MAX_TURN_STEPS = 6;
export const READ_STEP_BUDGET = 4;
export const WORKFLOW_READY = "workflow.ready";
export const WORKFLOW_REREAD = "workflow.reread";

export function isRenderTool(name: string): boolean {
  return name.startsWith("screen.render");
}

export type TurnWorkflow = {
  phase: "read" | "render" | "done";
  completedSteps: number;
  readSteps: number;
  rereadUsed: boolean;
  renderClaimed: boolean;
  controlClaimed: boolean;
  readTools: string[];
  renderTools: string[];
  // Tools permitted for the current model step.
  activeTools: string[];
};

function refreshActiveTools(state: TurnWorkflow): void {
  let names: string[] = [];
  if (state.completedSteps < MAX_TURN_STEPS) {
    if (state.phase === "read") {
      names = [...state.readTools, WORKFLOW_READY];
    } else if (state.phase === "render") {
      names = [...state.renderTools];
      // A reread needs three model steps: request, read, then render.
      if (
        !state.rereadUsed && state.readTools.length > 0 &&
        MAX_TURN_STEPS - state.completedSteps >= 3
      ) {
        names.push(WORKFLOW_REREAD);
      }
    }
  }
  state.activeTools.splice(0, state.activeTools.length, ...names);
}

export function createTurnWorkflow(
  readTools: string[],
  renderTools: string[],
): TurnWorkflow {
  const state: TurnWorkflow = {
    phase: readTools.length > 0 ? "read" : "render",
    completedSteps: 0,
    readSteps: 0,
    rereadUsed: false,
    renderClaimed: false,
    controlClaimed: false,
    readTools: [...readTools],
    renderTools: [...renderTools],
    activeTools: [],
  };
  refreshActiveTools(state);
  return state;
}

export type ToolGateDecision = {
  allow: boolean;
  error?: "TOOL_NOT_ACTIVE" | "STEP_ALREADY_COMMITTED";
};

// Claim synchronously before execute awaits. Parallel tool calls cannot draw
// twice, or mix a render with a reread transition in the same model step.
export function gateTurnTool(
  state: TurnWorkflow,
  toolName: string,
): ToolGateDecision {
  if (!state.activeTools.includes(toolName)) {
    return { allow: false, error: "TOOL_NOT_ACTIVE" };
  }
  const render = state.renderTools.includes(toolName);
  const control = toolName === WORKFLOW_READY || toolName === WORKFLOW_REREAD;
  if (render || control) {
    if (state.renderClaimed || state.controlClaimed) {
      return { allow: false, error: "STEP_ALREADY_COMMITTED" };
    }
    if (render) state.renderClaimed = true;
    else state.controlClaimed = true;
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
  state.completedSteps += 1;
  if (state.phase === "read") {
    state.readSteps += 1;
    if (
      succeeded(WORKFLOW_READY, "ok") || state.rereadUsed ||
      state.readSteps >= READ_STEP_BUDGET
    ) {
      state.phase = "render";
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
  refreshActiveTools(state);
}
