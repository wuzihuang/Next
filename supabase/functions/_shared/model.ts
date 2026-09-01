import { createOpenAICompatible } from "npm:@ai-sdk/openai-compatible@0.2.14";

/// The model is qwen3.8-flash, reached through the Vercel AI Gateway.
/// If the gateway is unavailable we fall back to DashScope's OpenAI-compatible endpoint;
/// the model id and the prompt are identical either way, so a fallback never changes
/// what she says — only where the request went.
export function model() {
  const gatewayKey = Deno.env.get("AI_GATEWAY_API_KEY");
  if (gatewayKey) {
    const gw = createOpenAICompatible({
      name: "vercel-gateway",
      baseURL: "https://ai-gateway.vercel.sh/v1",
      apiKey: gatewayKey,
    });
    return gw("alibaba/qwen3.8-flash");
  }
  const dashscope = createOpenAICompatible({
    name: "dashscope",
    baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
    apiKey: Deno.env.get("DASHSCOPE_API_KEY")!,
  });
  return dashscope("qwen3.8-flash");
}

export const MODEL_VERSION = "qwen3.8-flash/2026-09";
