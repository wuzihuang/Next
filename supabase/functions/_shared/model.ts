import { OpenAICompatibleChatLanguageModel } from "npm:@ai-sdk/openai-compatible@0.2.14";

export function primaryModelId(): string {
  return Deno.env.get("DASHSCOPE_MODEL") ?? "qwen3.8-flash";
}

export function fallbackModelIds(): string[] {
  const raw = Deno.env.get("DASHSCOPE_FALLBACK_MODELS") ?? "kimi-k3,deepseek-v4-flash";
  return raw.split(",").map((id) => id.trim()).filter((id) =>
    id.length > 0 && !id.includes("/")
  );
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
    url: ({ path }) => `${baseURL}${path}`,
    defaultObjectGenerationMode: "json",
  });
}

export function model(id = primaryModelId()) {
  const useGateway = id === primaryModelId()
    && Boolean(Deno.env.get("AI_GATEWAY_API_KEY"))
    && !Deno.env.get("AI_GATEWAY_API_KEY")!.startsWith("vck_");
  if (useGateway) {
    return compatibleModel(id.includes("/") ? id : `alibaba/${id}`, "vercel-gateway",
      "https://ai-gateway.vercel.sh/v1", Deno.env.get("AI_GATEWAY_API_KEY")!);
  }
  return compatibleModel(id, "dashscope", "https://dashscope.aliyuncs.com/compatible-mode/v1",
    Deno.env.get("DASHSCOPE_API_KEY")!);
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
