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
import { TARGETS } from "./contract.ts";

export const PHONE_PAGES = [...TARGETS, "device", "plan", "sleep", "heart"] as const;

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

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "HH:MM");

export const PHONE_TOOLS: PhoneToolDef[] = [
  {
    name: "device.find",
    description: "Make the band vibrate so the user can find it. Only when the user asks where the band is.",
    parameters: z.object({}),
    confirm: false,
    codes: BAND_CODES,
  },
  {
    name: "device.sync",
    description: "Pull the band's latest data to the phone and the cloud now. Use when the user asks to sync or when they say today's numbers look stale. Returns the last synced time; reread the data afterwards if the answer depends on it.",
    parameters: z.object({}),
    confirm: false,
    codes: BAND_CODES,
  },
  {
    name: "device.alarm.set",
    description: "Set an alarm on the band. days is 0–6 (Sunday=0); empty means once. The user confirms on the phone before it is written. Returns the band's alarm list after the write.",
    parameters: z.object({
      time,
      days: z.array(z.number().int().min(0).max(6)).max(7).default([]),
      label: z.string().max(20).optional(),
    }),
    confirm: true,
    codes: ["ALARM_SLOTS_FULL", "UNSUPPORTED", ...BAND_CODES],
  },
  {
    name: "device.alarm.delete",
    description: "Delete one band alarm by its id from the device state or a previous device.alarm.set result. The user confirms on the phone.",
    parameters: z.object({ alarm_id: z.string().max(40) }),
    confirm: true,
    codes: ["ALARM_NOT_FOUND", ...BAND_CODES],
  },
  {
    name: "sport.start",
    description: "Start a live sport session on the band and phone. The user confirms on the phone. Fails with SESSION_ACTIVE if one is already running.",
    parameters: z.object({ sport: z.enum(["run", "walk", "ride", "strength", "other"]).default("other") }),
    confirm: true,
    codes: ["SESSION_ACTIVE", ...BAND_CODES],
  },
  {
    name: "sport.stop",
    description: "Stop the live sport session that is running. The user confirms on the phone.",
    parameters: z.object({}),
    confirm: true,
    codes: ["NO_SESSION", ...BAND_CODES],
  },
  {
    name: "meal.log",
    description: "Save the meal draft from meal.estimate as a logged meal for the slot. Call meal.estimate first; the user confirms on the phone. Returns the saved meal id.",
    parameters: z.object({ slot: z.enum(["BREAKFAST", "LUNCH", "DINNER", "SNACK"]).optional() }),
    confirm: true,
    codes: ["ESTIMATE_REQUIRED", "FASTED_DAY", ...COMMON_CODES],
  },
  {
    name: "balance_check.start",
    description: "Open the balance check flow on the phone. The phone reports whether the user completed it.",
    parameters: z.object({}),
    confirm: false,
    codes: ["ABANDONED", ...BAND_CODES],
  },
  {
    name: "body_scan.start",
    description: "Open the body composition scan flow on the phone. The phone reports whether the user completed it.",
    parameters: z.object({}),
    confirm: false,
    codes: ["ABANDONED", ...BAND_CODES],
  },
  {
    name: "app.open",
    description: `Open a page of the app: one of ${PHONE_PAGES.join(" / ")}. Only when the user asks to see or open something.`,
    parameters: z.object({ page: z.enum(PHONE_PAGES) }),
    confirm: false,
    codes: COMMON_CODES,
  },
];

export const PHONE_TOOL_BY_NAME = new Map(PHONE_TOOLS.map((t) => [t.name, t]));

export function phoneToolDescription(t: PhoneToolDef): string {
  return `${t.description} Runs on the phone${t.confirm ? " after the user confirms" : ""}. Result codes: OK / ${t.codes.join(" / ")}.`;
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
