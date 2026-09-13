import { OpenAICompatibleChatLanguageModel } from "npm:@ai-sdk/openai-compatible@0.2.14";

export function primaryModelId(): string {
  return Deno.env.get("GROK_MODEL")?.trim() || "grok-4.6";
}

export function fallbackModelIds(): string[] {
  return [Deno.env.get("DASHSCOPE_MODEL")?.trim() || "qwen3.8-flash"];
}

export function asrFlashModel(): string {
  return Deno.env.get("DASHSCOPE_ASR_MODEL") ?? "qwen3-asr-flash";
}

export function asrRealtimeModel(): string {
  return Deno.env.get("DASHSCOPE_ASR_REALTIME_MODEL") ??
    "qwen3-asr-flash-realtime";
}

export function modelVersion(id = primaryModelId()): string {
  return `${id}/2026-09`;
}

export const MODEL_VERSION = modelVersion();

function compatibleModel(id: string, provider: string, baseURL: string, apiKey: string) {
  // 0.2.x's provider factory drops includeUsage; the exported model config
  // supports it and requests the terminal usage chunk for streamed calls.
  return new OpenAICompatibleChatLanguageModel(id, {}, {
    provider: `${provider}.chat`,
    includeUsage: true,
    headers: () => ({ Authorization: `Bearer ${apiKey}` }),
    url: ({ path }) => {
      if (provider === "grok" && (!baseURL || !apiKey)) throw new ModelConfigurationError();
      return `${baseURL}${path}`;
    },
    defaultObjectGenerationMode: "json",
    // Bound each provider request so the fallback still has time inside the turn.
    // This owns only the HTTP request, not execution of the model's tools.
    fetch: (url, init) => fetch(url, {
      ...init,
      signal: AbortSignal.any([
        ...(init?.signal ? [init.signal] : []),
        AbortSignal.timeout(30_000),
      ]),
    }),
  });
}

export function model(id = primaryModelId()) {
  if (id === primaryModelId()) {
    const base = Deno.env.get("GROK_BASE_URL")?.trim().replace(/\/+$/, "");
    const key = Deno.env.get("GROK_API_KEY")?.trim();
    return compatibleModel(id, "grok", base ? (base.endsWith("/v1") ? base : `${base}/v1`) : "", key ?? "");
  }
  return compatibleModel(id, "dashscope", "https://dashscope.aliyuncs.com/compatible-mode/v1",
    Deno.env.get("DASHSCOPE_API_KEY")!);
}

class ModelConfigurationError extends Error {
  constructor() {
    super("GROK_BASE_URL or GROK_API_KEY is missing");
    this.name = "ModelConfigurationError";
  }
}

/** Only provider/generation failures may change models; never permissions or writes. */
export function isModelFailure(error: unknown): boolean {
  return error instanceof Error && [
    "ModelConfigurationError", "AI_APICallError", "AI_RetryError",
    "AI_NoObjectGeneratedError", "AI_NoContentGeneratedError",
    "AI_InvalidResponseDataError", "AI_JSONParseError", "AI_TypeValidationError",
    "TimeoutError",
  ].includes(error.name);
}

export async function withModelFallback<T>(
  run: (modelId: string) => Promise<T>,
  signal?: AbortSignal,
  ids = modelChain(),
): Promise<{ result: T; modelId: string }> {
  for (const [index, modelId] of ids.entries()) {
    signal?.throwIfAborted();
    try {
      return { result: await run(modelId), modelId };
    } catch (error) {
      if (signal?.aborted || !isModelFailure(error) || index === ids.length - 1) throw error;
      // Error messages/bodies can contain the image or private transcript.
      console.warn("model fallback", modelId, (error as Error).name);
    }
  }
  throw new Error("MODEL_CHAIN_EMPTY");
}

export function modelChain(): string[] {
  const seen = new Set<string>();
  const ids: string[] = [];
  for (const id of [primaryModelId(), ...fallbackModelIds()]) {
    if (seen.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }
  return ids;
}
