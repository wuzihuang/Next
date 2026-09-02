// 07 · the screen.render envelope, and the four tool names.
// F4 §01 · the vocabulary stays, the transport is cut: tools are defined here with the
// Vercel AI SDK's tool() + Zod, inside the Edge Function. No MCP server, no JSON-RPC hop,
// no extra cold start — and the tool bodies build a Supabase client from this turn's JWT,
// so RLS applies and the agent physically cannot read another user's rows.

import { z } from "npm:zod@3.25.76";

export const PANEL_TYPES = [
  "battery", "metric", "text", "line", "band", "bars", "days", "sparks", "ring", "gauge",
  "split", "cells", "hypnogram", "zones", "wave", "table", "workout", "events", "heat",
  "o2night", "food", "meal", "fuel", "balance", "recomp", "delta", "dual",
] as const;

export type PanelType = (typeof PANEL_TYPES)[number];

/// ⚠️ What the model may actually choose — 24 of the 27.
///
/// 1EEU puts "睡眠分期与睡眠时长的任何渲染，含 07 板的 hypnogram / split / o2night 三个
/// widget" on the not-in-V1 list, and F0 rule 03 bans sleep from the screen outright: the
/// night only ever appears as the Body Battery it produced. The three stay in PANEL_TYPES
/// because the contract has 27 and a later version will want them, but offering them in the
/// render tool's enum is how a sleep-stage strip ends up on screen — the model picks what it
/// is given.
export const SLEEP_TYPES = ["hypnogram", "split", "o2night"] as const;
export const RENDERABLE_TYPES = PANEL_TYPES.filter(
  (t) => !(SLEEP_TYPES as readonly string[]).includes(t),
);

/// F0 rule 06 · every widget declares the page it lands on. There is no sixth destination.
export const TARGETS = ["training", "fuel", "bodyBattery", "composition", "profile"] as const;

/// 07 · 04 · fourteen fields, four of them required. Anything outside this table is
/// dropped without an error; a missing required field is E_SCHEMA and the frame never ships.
/// The length caps are truncation, not validation — which makes them a rule for writing
/// copy, not a safety net.
/// ⚠️ The length caps truncate, they do not reject. Writing too long costs half a sentence
/// on screen, which makes the cap a rule for writing copy rather than a safety net — and
/// throwing the frame away over one long word would be a worse outcome than trimming it.
const trimmed = (max: number) =>
  z.string().transform((s) => (s.length > max ? s.slice(0, max) : s));

export const Envelope = z.object({
  type: z.enum(PANEL_TYPES),
  title: trimmed(18),
  tag: z.enum(["MOVE", "FUEL", "RECOVER", "ALERT"]).optional(),
  sentence: trimmed(48),
  footer: trimmed(42).optional(),
  action: trimmed(32).optional(),
  accent: z.string().optional(),
  data: z.record(z.any()),
  theme: z.record(z.any()).optional(),
  layout: z.record(z.any()).optional(),
  format: z.record(z.any()).optional(),
  motion: z.record(z.any()).optional(),
  ttl_min: z.number().int().min(1).max(60).default(20),
  priority: z.enum(["normal", "alert"]).default("normal"),
  locale: z.enum(["zh-CN", "en-US"]).default("zh-CN"),
  // F0 rule 06 · every widget declares the page it lands on. No target, no screen.
  target: z.enum(TARGETS),
});

export type Envelope = z.infer<typeof Envelope>;

/// The panel is never allowed to be empty: when a frame expires it falls back to this.
export function batteryFallback(level: number | null): Envelope {
  return {
    type: "battery",
    title: "BODY BATTERY",
    sentence: level === null ? "还没有可用的夜间数据。" : `现在 ${level}。`,
    data: { level, unit: "%" },
    ttl_min: 20,
    priority: "normal",
    locale: "zh-CN",
    target: "bodyBattery",
  };
}

/// F4 · the fixed medical stop frame. S7 renders this and nothing else — no tools,
/// no explanation. "consult your doctor" is only ever allowed to appear here.
// F4 rule 11 · 「标签闭合串必须转义」.
//
// ⚠️ The user's words go into the prompt between <user_text> and </user_text>, and the system
// message says everything between those tags is data rather than instruction. Nothing stopped
// the user from writing the closing tag themselves — typing </user_text> ended the quoted
// region and everything after it read as instruction, which is the one sentence the wrapper
// exists to prevent. The tags are what separates her words from ours, so she does not get to
// write one. Replaced rather than stripped: the model still sees what was typed.
export function tagSafe(s: unknown): string {
  return String(s ?? "").replace(/<(\/?)(user_text|photo_extract)>/gi, "‹$1$2›");
}

// S7 · the one list. `turn` checks it before any tool call, and `meal` checks it too:
// the dock's food classifier looks for 吃, which 吃药 contains, so a medication question
// reaches /meal without ever passing through /turn.
export const MEDICAL = /(诊断|症状|吃药|用药|疾病|怀孕|安全吗|癌|糖尿病|高血压|抑郁|medicine|diagnos|pregnan|symptom)/i;

export const MEDICAL_STOP: Envelope = {
  type: "text",
  title: "NOT A DOCTOR",
  sentence: "这类问题请找医生。这块屏只报告测量到的数字。",
  footer: "NEXTBODY IS NOT A MEDICAL DEVICE",
  data: {},
  ttl_min: 5,
  priority: "normal",
  locale: "zh-CN",
  target: "profile",
};

export const ERROR_CODES = [
  "RATE_LIMITED", "MODEL_UNAVAILABLE", "E_SCHEMA", "TOOL_TIMEOUT",
  "NO_SPEECH", "IDEMPOTENT_REPLAY",
] as const;
