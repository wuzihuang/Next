import type { ToolCallRepairFunction, ToolSet } from "npm:ai@4.3.16";
import type { ZodIssue } from "npm:zod@3.25.76";

// Repair only missing presentation fields, using existing text. Measurement tools
// and invalid values still fail validation; this never manufactures health data.
export const repairTextToolCall: ToolCallRepairFunction<ToolSet> = ({ toolCall, tools }) => {
  if (toolCall.toolName !== "screen.render.text") return Promise.resolve(null);
  const parameters = tools[toolCall.toolName]?.parameters;
  if (!parameters || !("safeParse" in parameters)) return Promise.resolve(null);

  let args: unknown;
  try { args = JSON.parse(toolCall.args); } catch { return Promise.resolve(null); }
  if (!args || typeof args !== "object" || Array.isArray(args)) return Promise.resolve(null);
  const original = parameters.safeParse(args);
  if (original.success) return Promise.resolve(null);
  const fields = args as Record<string, unknown>;
  const missing = (field: string) => original.error.issues.some((issue: ZodIssue) =>
    issue.path.length === 1 && issue.path[0] === field &&
    issue.code === "invalid_type" && issue.received === "undefined"
  );
  const candidate = {
    ...fields,
    ...(missing("headline") ? {
      headline: typeof fields.title === "string" && fields.title.trim() ? fields.title : "AI COACH",
    } : {}),
    ...(missing("sub") && typeof fields.sentence === "string" && fields.sentence.trim()
      ? { sub: fields.sentence } : {}),
  };
  const repaired = parameters.safeParse(candidate);
  return Promise.resolve(repaired.success ? { ...toolCall, args: JSON.stringify(repaired.data) } : null);
};
