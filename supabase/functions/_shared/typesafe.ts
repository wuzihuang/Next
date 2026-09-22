// Jev (typesafe.ai) HTTP adapter. One POST to /v1/systemone asks a batch of independent
// Choice questions about one immutable `state` and gets back, per question, the selected
// criterion with a probability distribution over the candidates.
//
// Jev is a decision component, not a chat model: it never joins the OpenAI-compatible
// model chain in model.ts, it is never handed images or audio, and its answer is only ever
// an index into candidates the server already decided are legal.
//
// ⚠️ Three fields that are not each other (F7 · verified against the live API 2026-09-20,
// request "最近七天我的体重趋势怎么样"): `confidence` 0.52, the selected option's
// probability 0.61, and the margin to the runner-up 0.72 − 0.24 = 0.48 on another question
// of the same batch. Thresholds name which one they mean; nothing multiplies them together.

import type { TokenUsage } from "./cost.ts";

export const JEV_ENDPOINT = "https://api.typesafe.ai/v1/systemone";

/// The evaluated model is pinned. `jev-latest` would let a provider-side change alter
/// tuned behaviour with no regression run.
export const JEV_DEFAULT_MODEL = "jev-1.13.0";

/// `off` never calls the provider. `on` routes the tasks in JEV_TASK_ALLOWLIST.
/// `shadow` is accepted so configuration can name it, but /turn treats it as `off`: an
/// online shadow costs real money against the user's own spend cap, which this project's
/// accounting cannot yet separate from their usage. Shadow evaluation runs offline
/// (supabase/scripts/eval/jev-eval.ts).
export type JevMode = "off" | "shadow" | "on";

export type JevConfig = {
  mode: JevMode;
  model: string;
  apiKey: string | null;
  timeoutMs: number;
  totalWaitMs: number;
  maxCallsPerTurn: number;
  shadowSampleRate: number;
  assistedEnabled: boolean;
  /// Answer an accepted read with a server-written template and no model at all. Off by
  /// default: the model keeps the tools, so it can check the web, read a second metric or
  /// say something the templates cannot. See ADR 0031.
  templateFast: boolean;
};

/// Production default is off, and a missing key downgrades any mode to off rather than
/// failing a turn. Bad numbers fall back to the documented engineering start values.
export function jevConfig(env: (key: string) => string | undefined = Deno.env.get): JevConfig {
  const apiKey = env("TYPESAFE_API_KEY")?.trim() || null;
  const requested = (env("JEV_MODE")?.trim().toLowerCase() ?? "off") as JevMode;
  const mode: JevMode = requested === "shadow" || requested === "on" ? requested : "off";
  return {
    mode: apiKey ? mode : "off",
    model: env("TYPESAFE_MODEL")?.trim() || JEV_DEFAULT_MODEL,
    apiKey,
    timeoutMs: positive(env("JEV_TIMEOUT_MS"), 1500),
    totalWaitMs: positive(env("JEV_TOTAL_WAIT_MS"), 2500),
    maxCallsPerTurn: Math.max(0, Math.trunc(positive(env("JEV_MAX_CALLS_PER_TURN"), 2))),
    shadowSampleRate: clamp01(Number(env("JEV_SHADOW_SAMPLE_RATE") ?? 0)),
    assistedEnabled: (env("JEV_ASSISTED_ENABLED")?.trim().toLowerCase() ?? "false") === "true",
    templateFast: (env("JEV_TEMPLATE_FAST")?.trim().toLowerCase() ?? "false") === "true",
  };
}

function positive(raw: string | undefined, fallback: number): number {
  const value = Number(raw);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function clamp01(value: number): number {
  return Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
}

/// A question is one decision over a closed candidate set. Every criteria map carries its
/// own refusal exit (UNKNOWN / NO_MATCH / NOT_SUPPORTED) — see decision-router.ts.
export type JevChoiceQuestion = {
  type: "choice";
  instructions: string;
  criteria: Record<string, string>;
};

export type JevAnswer = {
  choice: string;
  confidence: number;
  probabilities: Record<string, number>;
  /// Selected probability minus the runner-up, computed here so no caller re-derives it.
  margin: number;
};

/// Why a call produced no usable answers. CANCELLED means the turn itself is going away
/// (parent abort): the caller must stop, not fall back into a paid model step.
export type JevFailure =
  | "NOT_CONFIGURED"
  | "TIMEOUT"
  | "CANCELLED"
  | "AUTH"
  | "REQUEST_REJECTED"
  | "RATE_LIMITED"
  | "PROVIDER_UNAVAILABLE"
  | "INVALID_RESPONSE"
  | "TRANSPORT";

export type JevCallResult =
  | {
    ok: true;
    model: string;
    requestId: string | null;
    answers: Record<string, JevAnswer>;
    usage: TokenUsage;
    latencyMs: number;
  }
  | {
    ok: false;
    failure: JevFailure;
    status?: number;
    requestId: string | null;
    /// Present when the provider billed us anyway: an unusable answer is not free.
    usage: TokenUsage | null;
    /// True when the provider may have done work we cannot price (no usage reached us).
    costUnknown: boolean;
    latencyMs: number;
  };

export type JevCallOptions = {
  state: Record<string, unknown>;
  questions: Record<string, JevChoiceQuestion>;
  config: JevConfig;
  /// The turn's signal. Its abort is CANCELLED; our own budget expiring is TIMEOUT.
  signal?: AbortSignal;
  timeoutMs?: number;
  fetch?: typeof fetch;
  now?: () => number;
};

export async function askJev(options: JevCallOptions): Promise<JevCallResult> {
  const { config, state, questions } = options;
  const now = options.now ?? Date.now;
  const started = now();
  const send = options.fetch ?? globalThis.fetch;
  const ids = Object.keys(questions);
  if (!config.apiKey) return failed("NOT_CONFIGURED", { latencyMs: 0 });
  if (ids.length === 0) return failed("REQUEST_REJECTED", { latencyMs: 0 });
  if (options.signal?.aborted) return failed("CANCELLED", { latencyMs: 0 });

  const budget = AbortSignal.timeout(options.timeoutMs ?? config.timeoutMs);
  const signal = options.signal ? AbortSignal.any([options.signal, budget]) : budget;
  let response: Response;
  try {
    response = await send(JEV_ENDPOINT, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${config.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: config.model, state, questions }),
      signal,
    });
  } catch (error) {
    // Parent cancellation and our own budget both surface as AbortError; only the
    // provider's own deadline may be retried or fallen back from.
    const cancelled = options.signal?.aborted === true;
    const failure: JevFailure = cancelled ? "CANCELLED" : isAbort(error) ? "TIMEOUT" : "TRANSPORT";
    // A request aborted in flight may still have been served and billed upstream.
    return failed(failure, { latencyMs: now() - started, costUnknown: failure !== "CANCELLED" });
  }

  const requestId = response.headers.get("x-typesafe-request-id");
  const latencyMs = now() - started;
  const text = await response.text().catch(() => "");
  if (!response.ok) {
    // ⚠️ The provider's error body can quote the request state; never log or return it.
    return failed(httpFailure(response.status), {
      latencyMs,
      status: response.status,
      requestId,
      usage: usageOf(safeParse(text)),
    });
  }

  const body = safeParse(text);
  const usage = usageOf(body);
  const answers = validateAnswers(body, config.model, questions);
  if (!answers) {
    // Billed, unusable. Usage still goes to the ledger of what this turn cost.
    return failed("INVALID_RESPONSE", { latencyMs, status: response.status, requestId, usage });
  }
  return {
    ok: true,
    // The version the provider actually served, not the alias we asked for.
    model: String((body as Record<string, unknown>).model),
    requestId,
    answers,
    usage: usage ?? { promptTokens: 0, cachedTokens: 0, completionTokens: 0 },
    latencyMs,
  };
}

function failed(
  failure: JevFailure,
  extra: { latencyMs: number; status?: number; requestId?: string | null; usage?: TokenUsage | null; costUnknown?: boolean },
): JevCallResult {
  return {
    ok: false,
    failure,
    ...(extra.status === undefined ? {} : { status: extra.status }),
    requestId: extra.requestId ?? null,
    usage: extra.usage ?? null,
    costUnknown: extra.costUnknown ?? false,
    latencyMs: extra.latencyMs,
  };
}

function httpFailure(status: number): JevFailure {
  if (status === 401 || status === 403) return "AUTH";
  if (status === 429) return "RATE_LIMITED";
  if (status >= 500) return "PROVIDER_UNAVAILABLE";
  return "REQUEST_REJECTED";
}

function isAbort(error: unknown): boolean {
  return error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError");
}

function safeParse(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/// Jev reports `usage.input_tokens` / `usage.output_tokens`. Mapped explicitly: the
/// OpenAI-compatible parser in cost.ts does not know these names, and a missed field
/// would silently record a paid call as free.
export function usageOf(body: unknown): TokenUsage | null {
  const usage = (body as { usage?: unknown } | null)?.usage;
  if (!usage || typeof usage !== "object") return null;
  const row = usage as Record<string, unknown>;
  const input = row.input_tokens;
  const output = row.output_tokens;
  if (typeof input !== "number" || !Number.isFinite(input)) return null;
  const completion = typeof output === "number" && Number.isFinite(output) ? output : 0;
  return {
    promptTokens: Math.max(0, Math.trunc(input)),
    cachedTokens: 0,
    completionTokens: Math.max(0, Math.trunc(completion)),
  };
}

const PROBABILITY_SUM_TOLERANCE = 0.02;

/// Every consumed field is validated; unknown extra fields are ignored. An obviously
/// illegal distribution is rejected rather than repaired — a quietly normalised answer
/// would be a decision nobody made.
function validateAnswers(
  body: unknown,
  requestedModel: string,
  questions: Record<string, JevChoiceQuestion>,
): Record<string, JevAnswer> | null {
  if (!body || typeof body !== "object") return null;
  const row = body as Record<string, unknown>;
  if (typeof row.model !== "string" || !row.model.trim()) return null;
  // The provider reports the version that actually answered; an alias resolves to one. A
  // pinned request must be answered by exactly that version — anything else is not the
  // model these thresholds were tuned against.
  if (/\d/.test(requestedModel) && row.model !== requestedModel) return null;
  if (!row.answers || typeof row.answers !== "object") return null;
  const answers = row.answers as Record<string, unknown>;
  const out: Record<string, JevAnswer> = {};
  for (const [id, question] of Object.entries(questions)) {
    const answer = answers[id];
    if (!answer || typeof answer !== "object") return null;
    const item = answer as Record<string, unknown>;
    if (item.type !== "choice") return null;
    const choice = item.choice;
    if (typeof choice !== "string" || !(choice in question.criteria)) return null;
    const confidence = item.confidence;
    if (typeof confidence !== "number" || !Number.isFinite(confidence) || confidence < 0 || confidence > 1) return null;
    if (!item.probabilities || typeof item.probabilities !== "object") return null;
    const probabilities = item.probabilities as Record<string, unknown>;
    const names = Object.keys(probabilities);
    const expected = Object.keys(question.criteria);
    if (names.length !== expected.length || !expected.every((name) => name in probabilities)) return null;
    const values: Record<string, number> = {};
    let sum = 0;
    for (const name of expected) {
      const value = probabilities[name];
      if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) return null;
      values[name] = value;
      sum += value;
    }
    if (Math.abs(sum - 1) > PROBABILITY_SUM_TOLERANCE) return null;
    const ordered = Object.values(values).sort((a, b) => b - a);
    out[id] = {
      choice,
      confidence,
      probabilities: values,
      margin: Math.max(0, (values[choice] ?? 0) - (ordered[1] ?? 0)),
    };
  }
  return out;
}
