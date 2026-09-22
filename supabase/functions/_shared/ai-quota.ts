import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { cors, serviceClient } from "./db.ts";
import { slowDownFrame } from "./contract.ts";
import type { TokenUsage } from "./cost.ts";

/// Endpoints that admit a user operation. One admission costs the person one of their
/// daily operations, so only work a person asked for appears here.
///
/// ⚠️ `memory` is deliberately absent, and `consume_ai_quota_trusted` rejects it in SQL
/// too (UNKNOWN_ENDPOINT). The nightly memory settle is a background job: it spends money,
/// which it records, but nobody asked for it, so it must not spend a person's daily count.
/// The two lists disagreed until 2026-09-20 — the type allowed an admission the database
/// would have thrown on.
export type AiQuotaEndpoint = "turn" | "meal" | "asr";

/// Endpoints whose provider calls are billed. Every admitted endpoint bills, and so does
/// the background settle.
export type AiUsageEndpoint = AiQuotaEndpoint | "memory";

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

/// One real provider attempt, priced or explicitly unpriceable.
///
/// ⚠️ Three states, never two. `reported` is usage the provider returned. `unknown` is an
/// attempt that may have been served and billed while the answer or the usage never
/// reached us — a network cut, a timeout mid-flight, an unusable body. It is recorded with
/// a conservative upper bound so the day's spend check counts it, and it is marked as an
/// estimate rather than a bill. Recording nothing would make a paid call look free.
export type ProviderAttempt = {
  attemptId: string;
  logicalCallId: string;
  model: string;
  requestId: string | null;
  latencyMs: number;
  usage: TokenUsage | null;
  costUnknown: boolean;
};

/// The upper bound charged for an attempt with no usage: the largest routing batch this
/// product sends, rounded up. Measured against the live API on 2026-09-20 — a four
/// question batch cost 1,304 input tokens, a five question one under 2,000.
export const UNKNOWN_ATTEMPT_PROMPT_TOKENS = 2500;

export async function recordProviderAttempt(
  db: SupabaseClient,
  attempt: ProviderAttempt,
  turnId?: string,
): Promise<void> {
  if (attempt.usage) {
    await recordAiUsage(db, {
      endpoint: "turn", modelId: attempt.model, usage: attempt.usage,
      turnId, latencyMs: attempt.latencyMs,
      attemptId: attempt.attemptId, logicalCallId: attempt.logicalCallId, costState: "reported",
    });
    return;
  }
  if (!attempt.costUnknown) return;
  await recordAiUsage(db, {
    endpoint: "turn", modelId: attempt.model,
    usage: { promptTokens: UNKNOWN_ATTEMPT_PROMPT_TOKENS, cachedTokens: 0, completionTokens: 0 },
    turnId, latencyMs: attempt.latencyMs,
    attemptId: attempt.attemptId, logicalCallId: attempt.logicalCallId, costState: "unknown",
  });
}

export async function recordAiUsage(
  db: SupabaseClient,
  args: {
    endpoint: AiUsageEndpoint;
    modelId: string;
    usage: TokenUsage;
    turnId?: string;
    latencyMs?: number;
    /// A stable id for the call this attempt belongs to, and the attempt's own id. The
    /// attempt id makes the row idempotent: a replayed record is the same row, while a
    /// real retry is a different attempt and is billed again.
    logicalCallId?: string;
    attemptId?: string;
    costState?: "reported" | "unknown";
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
    p_logical_call: args.logicalCallId ?? null,
    p_attempt: args.attemptId ?? null,
    p_cost_state: args.costState ?? "reported",
  });
  if (result.error) throw new Error(`AI_USAGE_UNAVAILABLE: ${result.error.message}`);
}
