// 07 · the screen.render envelope, and the four tool names.
// F4 §01 · the vocabulary stays, the transport is cut: tools are defined here with the
// Vercel AI SDK's tool() + Zod, inside the Edge Function. No MCP server, no JSON-RPC hop,
// no extra cold start — and the tool bodies build a Supabase client from this turn's JWT,
// so RLS applies and the agent physically cannot read another user's rows.

import { z } from "npm:zod@3.23.8";

export const PANEL_TYPES = [
  "battery", "metric", "text", "line", "band", "bars", "days", "sparks", "ring", "gauge",
  "split", "cells", "hypnogram", "zones", "wave", "table", "workout", "events", "heat",
  "o2night", "food", "meal", "fuel", "balance", "recomp", "delta", "dual",
] as const;

export type PanelType = (typeof PANEL_TYPES)[number];

/// 07 · 04 · fourteen fields, four of them required. Anything outside this table is
/// dropped without an error; a missing required field is E_SCHEMA and the frame never ships.
/// The length caps are truncation, not validation — which makes them a rule for writing
/// copy, not a safety net.
export const Envelope = z.object({
  type: z.enum(PANEL_TYPES),
  title: z.string().max(18),
  tag: z.enum(["MOVE", "FUEL", "RECOVER", "ALERT"]).optional(),
  sentence: z.string().max(48),
  footer: z.string().max(42).optional(),
  action: z.string().max(32).optional(),
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
  target: z.enum(["training", "fuel", "bodyBattery", "composition", "profile"]),
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
