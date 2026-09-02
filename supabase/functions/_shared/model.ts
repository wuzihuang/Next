import { createOpenAICompatible } from "npm:@ai-sdk/openai-compatible@0.2.14";

/// The model is qwen3.8-flash, reached through the Vercel AI Gateway.
/// If the gateway is unavailable we fall back to DashScope's OpenAI-compatible endpoint;
/// the model id and the prompt are identical either way, so a fallback never changes
/// what she says — only where the request went.
export function model() {
  const gatewayKey = Deno.env.get("AI_GATEWAY_API_KEY");
  // ⚠️ A Vercel access token (vck_…) is not an AI Gateway API key. It authenticates against
  // api.vercel.com and is refused by the gateway with "Authentication failed", which reads
  // like an outage rather than the wrong kind of credential. Gateway keys are minted at
  // vercel.com → team → AI Gateway → API Keys.
  if (gatewayKey && !gatewayKey.startsWith("vck_")) {
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

/// 05 · C · a plate arrives as a photo. qwen3.8-flash reads text only, so the photo track goes
/// to the same family's vision model on the same endpoint (qwen-vl-plus looped on JSON;
/// qwen3-vl-flash answers cleanly in ~3 s). ⚠️ Not the mandated model — the nearest one that
/// can see; recorded in STATUS as a decision to confirm.
export function visionModel() {
  const dashscope = createOpenAICompatible({
    name: "dashscope",
    baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
    apiKey: Deno.env.get("DASHSCOPE_API_KEY")!,
  });
  return dashscope("qwen3-vl-flash");
}
export const VISION_MODEL_VERSION = "qwen3-vl-flash/2026-09";
