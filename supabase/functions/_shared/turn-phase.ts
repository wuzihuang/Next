export const MAX_TURN_STEPS = 6;
export const READ_STEP_BUDGET = 4;

// AI SDK 4.3 streamText has no prepareStep. gateTurnTool is the runtime
// constraint; nextTurnPhase is the intended activeTools policy.

export function isRenderTool(name: string): boolean {
  return name.startsWith("screen.render");
}

export type PhaseInput = {
  stepNumber: number;
  lastToolNames: string[];
  rereadUsed: boolean;
  readTools: string[];
  renderTools: string[];
};

export type PhaseResult = {
  activeTools: string[];
  rereadUsed: boolean;
  phase: 1 | 2;
};

export type ToolGateState = {
  phase: 1 | 2;
  readCalls: number;
  rereadUsed: boolean;
};

export type ToolGateDecision = {
  allow: boolean;
  error?: "READ_FIRST" | "REREAD_USED";
  next: ToolGateState;
};

export function initialToolGate(hasReadTools: boolean): ToolGateState {
  return {
    phase: hasReadTools ? 1 : 2,
    readCalls: 0,
    rereadUsed: false,
  };
}

export function gateTurnTool(
  state: ToolGateState,
  toolName: string,
  hasReadTools: boolean,
): ToolGateDecision {
  if (!hasReadTools) {
    return { allow: true, next: { ...state, phase: 2 } };
  }
  if (isRenderTool(toolName)) {
    if (state.phase === 1 && state.readCalls === 0) {
      return { allow: false, error: "READ_FIRST", next: state };
    }
    return { allow: true, next: { ...state, phase: 2 } };
  }
  if (state.phase === 2) {
    if (state.rereadUsed) {
      return { allow: false, error: "REREAD_USED", next: state };
    }
    return {
      allow: true,
      next: {
        phase: 2,
        readCalls: state.readCalls + 1,
        rereadUsed: true,
      },
    };
  }
  const readCalls = state.readCalls + 1;
  return {
    allow: true,
    next: {
      phase: readCalls >= READ_STEP_BUDGET ? 2 : 1,
      readCalls,
      rereadUsed: false,
    },
  };
}

export function nextTurnPhase(input: PhaseInput): PhaseResult {
  if (input.readTools.length === 0) {
    return {
      activeTools: input.renderTools,
      rereadUsed: input.rereadUsed,
      phase: 2,
    };
  }
  if (input.stepNumber < READ_STEP_BUDGET) {
    return { activeTools: input.readTools, rereadUsed: false, phase: 1 };
  }
  if (input.rereadUsed) {
    return { activeTools: input.renderTools, rereadUsed: true, phase: 2 };
  }
  const lastRead = input.lastToolNames.some((name) => !isRenderTool(name));
  if (input.stepNumber > READ_STEP_BUDGET && lastRead) {
    return { activeTools: input.renderTools, rereadUsed: true, phase: 2 };
  }
  return {
    activeTools: [...input.readTools, ...input.renderTools],
    rereadUsed: false,
    phase: 2,
  };
}
