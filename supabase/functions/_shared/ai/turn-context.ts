import { z } from "npm:zod@3.25.76";

export interface TurnContext {
  dayKey: string;
  from: string;
  to: string;
  queryText: string;
  explicitRange: boolean;
}

export interface PreviousResolvedContext {
  from: string;
  to: string;
  dayKey?: string;
  queryText?: string;
}

function isDay(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) &&
    date.toISOString().slice(0, 10) === value;
}

export function requireDay(value: string): string {
  if (!isDay(value)) throw new Error("INVALID_DAY");
  return value;
}

const daySchema = z.string().refine(
  isDay,
  "Expected a real ISO calendar date (YYYY-MM-DD)",
);

// Dates come from model tool arguments. Validation checks their shape and
// bounds; it never interprets question wording or conversation history.
export const workflowRangeSchema = z.object({
  from: daySchema,
  to: daySchema,
}).refine(({ from, to }) => {
  const days = (Date.parse(to) - Date.parse(from)) / 864e5 + 1;
  return Number.isFinite(days) && days >= 1 && days <= 366;
}, "Range must be ordered and contain at most 366 inclusive days");

export function createTurnContext(
  currentDay: string,
  text: string,
): TurnContext {
  requireDay(currentDay);
  return {
    dayKey: currentDay,
    from: currentDay,
    to: currentDay,
    queryText: text.slice(-8000),
    explicitRange: false,
  };
}

export function withTurnRange(
  context: TurnContext,
  range: z.infer<typeof workflowRangeSchema>,
): TurnContext {
  const validated = workflowRangeSchema.parse(range);
  return {
    ...context,
    ...validated,
    dayKey: validated.to,
    explicitRange: true,
  };
}
