import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { cors, userDayKey } from "./db.ts";
import { slowDownFrame } from "./contract.ts";
import { costFen, type TokenUsage } from "./cost.ts";

export type AiQuotaEndpoint = "turn" | "meal" | "asr";

export type QuotaDecision =
  | { allowed: true; remaining: number }
  | { allowed: false; reason: "count" | "spend" | "unavailable" };

export async function consumeAiQuota(
  db: SupabaseClient,
  endpoint: AiQuotaEndpoint,
): Promise<QuotaDecision> {
  try {
    const result = await db.rpc("consume_ai_quota", { p_endpoint: endpoint });
    if (result.error || typeof result.data?.allowed !== "boolean") {
      return { allowed: false, reason: "unavailable" };
    }
    if (result.data.allowed) {
      return { allowed: true, remaining: Number(result.data.remaining) || 0 };
    }
    return {
      allowed: false,
      reason: result.data.reason === "spend" ? "spend" : "count",
    };
  } catch {
    return { allowed: false, reason: "unavailable" };
  }
}

export function quotaDeniedResponse(
  locale: string,
  decision: Exclude<QuotaDecision, { allowed: true }>,
): Response {
  const status = decision.reason === "unavailable" ? 503 : 429;
  const error = decision.reason === "unavailable"
    ? "REQUEST_BUDGET_UNAVAILABLE"
    : "RATE_LIMITED";
  return new Response(
    JSON.stringify({
      error,
      fallback_frame: slowDownFrame(locale),
    }),
    {
      status,
      headers: {
        ...cors,
        "Content-Type": "application/json",
        ...(status === 429 ? { "Retry-After": "86400" } : {}),
      },
    },
  );
}

export async function recordAiUsage(
  db: SupabaseClient,
  args: {
    endpoint: AiQuotaEndpoint;
    modelId: string;
    usage: TokenUsage;
    timezone?: string;
    turnId?: string;
    latencyMs?: number;
  },
): Promise<void> {
  const fen = costFen(args.usage);
  const result = await db.rpc("record_ai_usage", {
    p_endpoint: args.endpoint,
    p_model: args.modelId,
    p_prompt: args.usage.promptTokens,
    p_cached: args.usage.cachedTokens,
    p_completion: args.usage.completionTokens,
    p_cost_fen: fen,
    p_user_day: userDayKey(args.timezone ?? "UTC"),
    p_turn: args.turnId ?? null,
    p_latency: args.latencyMs ?? null,
  });
  if (result.error) {
    console.error("record_ai_usage failed:", result.error.message);
  }
}

