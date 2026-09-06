import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { cors, serviceClient } from "./db.ts";
import { slowDownFrame } from "./contract.ts";
import type { TokenUsage } from "./cost.ts";

export type AiQuotaEndpoint = "turn" | "meal" | "asr";

export type QuotaDecision =
  | { allowed: true; remaining: number }
  | { allowed: false; reason: "count" | "spend" | "unavailable" };

export async function consumeAiQuota(
  db: SupabaseClient,
  endpoint: AiQuotaEndpoint,
  operationId: string = crypto.randomUUID(),
): Promise<QuotaDecision> {
  try {
    const { data, error } = await db.auth.getUser();
    if (error || !data.user) return { allowed: false, reason: "unavailable" };
    const result = await serviceClient().rpc("consume_ai_quota_trusted", {
      p_owner: data.user.id, p_endpoint: endpoint, p_operation: operationId,
    });
    if (result.error || typeof result.data?.allowed !== "boolean") {
      return { allowed: false, reason: "unavailable" };
    }
    if (result.data.allowed) {
      return { allowed: true, remaining: Number(result.data.remaining) || 0 };
    }
    return {
      allowed: false,
      reason: result.data.reason === "spend" ? "spend" : result.data.reason === "count" ? "count" : "unavailable",
    };
  } catch {
    return { allowed: false, reason: "unavailable" };
  }
}

/** Recheck between model steps without charging another user operation. */
export async function checkAiSpend(db: SupabaseClient): Promise<QuotaDecision> {
  try {
    const { data, error } = await db.auth.getUser();
    if (error || !data.user) return { allowed: false, reason: "unavailable" };
    const result = await serviceClient().rpc("check_ai_spend_trusted", { p_owner: data.user.id });
    if (result.error || typeof result.data?.allowed !== "boolean") {
      return { allowed: false, reason: "unavailable" };
    }
    if (result.data.allowed) return { allowed: true, remaining: Number(result.data.remaining) || 0 };
    return { allowed: false, reason: result.data.reason === "spend" ? "spend" : "unavailable" };
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
    turnId?: string;
    latencyMs?: number;
  },
): Promise<void> {
  const { data, error } = await db.auth.getUser();
  if (error || !data.user) throw new Error("AI_USAGE_UNAUTHENTICATED");
  const result = await serviceClient().rpc("record_ai_usage_trusted", {
    p_owner: data.user.id,
    p_endpoint: args.endpoint,
    p_model: args.modelId,
    p_prompt: args.usage.promptTokens,
    p_cached: args.usage.cachedTokens,
    p_completion: args.usage.completionTokens,
    p_audio_seconds: args.usage.audioSeconds ?? 0,
    p_turn: args.turnId ?? null,
    p_latency: args.latencyMs ?? null,
  });
  if (result.error) throw new Error(`AI_USAGE_UNAVAILABLE: ${result.error.message}`);
}
