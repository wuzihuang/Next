// ADR 0018 · phone tools. The model calls them like any tool; the phone runs them.
//
// The edge function cannot reach the band, so a phone tool call suspends the turn: the
// server sends `tool.request`, stores the conversation, closes the stream, and the phone
// resumes the turn with the result under the same Idempotency-Key. Every result is
// `{ ok, code, data }` so the model can say whether the alarm was actually set.
//
// `confirm` is fixed here, not chosen by the model: starting a session, setting an alarm
// and logging a meal wait for a tap on the phone; the rest run at once.

import { z } from "npm:zod@3.25.76";
import { ACTION_NAMES, ACTIONS, confirmFor, doDescription, normalizeDo, normalizeWrite, WRITE_ENTITIES, writeDescription } from "./entities.ts";

export const WRITE_TOOL = "write";
export const DO_TOOL = "do";
export const HEALTH_PREPARE_TOOL = "health.prepare";

export interface PhoneToolDef {
  name: string;
  description: string;
  parameters: z.ZodTypeAny;
  confirm: boolean;
  /// Codes the phone may return besides OK. Listed in the description so the model can
  /// read a failure without guessing.
  codes: string[];
}

const COMMON_CODES = ["APP_BACKGROUND", "CANCELLED", "TIMEOUT"];
const BAND_CODES = ["BAND_DISCONNECTED", "BAND_ERROR", ...COMMON_CODES];

// ⚠️ Nothing in a tool's parameters may reject. Seen on production twice in one sweep:
// `screen.render.food` with {"kcal":"350"} and `workflow.ready` with a JSON *string* for
// `range` both raised AI_InvalidToolArgumentsError, and the SDK turns that into a dead turn
// — the panel falls to the battery frame because the model quoted a number or typed a
// bracket. So every parameter here is permissive, and `normalizePhoneArgs` below decides:
// it either hands the phone clean arguments or returns a sentence the model can act on.
const loose = z.coerce.string();

export { normalizeDays, normalizeSlot, normalizeSport, normalizeTime } from "./normalize.ts";

export const PHONE_TOOLS: PhoneToolDef[] = [
  {
    name: HEALTH_PREPARE_TOOL,
    description: "Upload pending local health records and check calculation readiness before reading current personal data. Only when a read reports LOCAL_UPLOADS_PENDING. Does not sync the band. Returns freshness metadata, not measurements; then retry the needed read.",
    parameters: z.object({}), confirm: false, codes: COMMON_CODES,
  },
  {
    name: WRITE_TOOL,
    description: writeDescription(),
    parameters: z.object({
      entity: loose.describe(`one of ${WRITE_ENTITIES.join(" / ")}`),
      op: loose.describe("create / update / delete / restore"),
      id: z.any().optional().describe("the record id from find or device state"),
      match: z.any().optional().describe("{ day, slot, query } for meal · { day } for weigh_in · { time, label } for alarm"),
      fields: z.any().optional().describe("the entity's fields for this op"),
    }),
    confirm: false, // decided per (entity, op) in confirmFor()
    codes: ["NOT_FOUND", "AMBIGUOUS", "BAD_ARGS", "UNSUPPORTED", "EDIT_WINDOW_CLOSED", "FASTED_DAY", "ALARM_SLOTS_FULL", ...BAND_CODES],
  },
  {
    name: DO_TOOL,
    description: doDescription(),
    parameters: z.object({
      action: loose.describe(`one of ${ACTION_NAMES.join(" / ")}`),
      mode: z.any().optional().describe("sport.start: the sport"),
      kind: z.any().optional().describe("measure.start: what to measure"),
      page: z.any().optional().describe("app.open: the page"),
      sheet: z.any().optional().describe("app.open: a sheet to lift"),
      window: z.any().optional().describe("app.open: DAY / WEEK / MONTH"),
      day: z.any().optional().describe("app.open: YYYY-MM-DD"),
      session: z.any().optional(),
      stop: z.any().optional(),
    }),
    confirm: false, // decided per action in ACTIONS
    codes: ["BAD_ARGS", "UNKNOWN_PAGE", "SESSION_ACTIVE", "NO_SESSION", "NO_DRAFT", "NOTHING_TO_UNDO", "UNSUPPORTED", "ABANDONED", ...BAND_CODES],
  },
];

export const PHONE_TOOL_BY_NAME = new Map(PHONE_TOOLS.map((t) => [t.name, t]));

/// Clean arguments for the phone, or one sentence telling the model what to fix. Called in
/// the tool body, where a complaint is a result the model can act on rather than a throw.
/// `today` is the turn's user day, for "today" / "yesterday" in fields and matches.
export function normalizePhoneArgs(
  name: string,
  args: Record<string, unknown>,
  today = new Date().toISOString().slice(0, 10),
): { ok: true; args: Record<string, unknown>; confirm: boolean } | { ok: false; say: string } {
  switch (name) {
    case WRITE_TOOL: {
      const n = normalizeWrite(args, today);
      if (!n.ok) return n;
      return { ok: true, args: n.args, confirm: confirmFor(n.entity!, n.op!, (n.args.fields as Record<string, unknown>) ?? {}) };
    }
    case DO_TOOL: {
      const n = normalizeDo(args, today);
      if (!n.ok) return n;
      return { ok: true, args: n.args, confirm: ACTIONS[n.action!].confirm };
    }
    default:
      return { ok: true, args: {}, confirm: false };
  }
}

export function phoneToolDescription(t: PhoneToolDef): string {
  return `${t.description} Result codes: OK / ${t.codes.join(" / ")}.`;
}

/// What the phone sends back with the resumed turn.
export const phoneToolResult = z.object({
  call_id: z.string().min(1).max(80),
  ok: z.boolean(),
  code: z.string().min(1).max(40),
  data: z.record(z.any()).optional(),
  message: z.string().max(200).optional(),
}).strict();

export type PhoneToolResult = z.infer<typeof phoneToolResult>;

/// What the server sends as `tool.request`.
export interface PhoneToolRequest {
  call_id: string;
  name: string;
  args: Record<string, unknown>;
  confirm: boolean;
  /// The turn state expires at this instant; a later resume is TURN_STATE_LOST.
  resume_by: string;
}
