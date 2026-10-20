import { configuredOrigin, type FetchLike, type McpEnv } from "./env.ts";
import { forwardedRequestHeaders, jsonResponse, optionsResponse, proxyResponse } from "./http.ts";

interface UpstreamInit extends RequestInit {
  duplex?: "half";
}

function methodSendsBody(method: string): boolean {
  return method !== "GET" && method !== "HEAD";
}

export function mcpUpstreamUrl(supabaseUrl: string, requestUrl: string): string | null {
  const origin = configuredOrigin(supabaseUrl);
  if (!origin) return null;
  const upstream = new URL("/functions/v1/mcp", origin);
  upstream.search = new URL(requestUrl).search;
  return upstream.toString();
}

export function buildUpstreamRequest(request: Request, env: McpEnv, supabaseUrl: string): Request | null {
  const upstreamUrl = mcpUpstreamUrl(supabaseUrl, request.url);
  if (!upstreamUrl) return null;
  const init: UpstreamInit = {
    method: request.method,
    headers: forwardedRequestHeaders(request, env.SUPABASE_PUBLISHABLE_KEY),
    redirect: "manual",
  };
  if (methodSendsBody(request.method) && request.body) {
    init.body = request.body;
    // Node's fetch rejects a streamed body unless duplex is set. Workers accept it too.
    init.duplex = "half";
  }
  return new Request(upstreamUrl, init);
}

export async function handleMcp(
  request: Request,
  env: McpEnv,
  fetchImpl: FetchLike = fetch,
): Promise<Response> {
  if (request.method === "OPTIONS") return optionsResponse();
  const supabaseUrl = env.SUPABASE_URL?.trim();
  if (!supabaseUrl) return jsonResponse({ error: "SUPABASE_URL is not configured" }, 500);
  const upstreamRequest = buildUpstreamRequest(request, env, supabaseUrl);
  if (!upstreamRequest) return jsonResponse({ error: "SUPABASE_URL is not a valid URL" }, 500);
  try {
    const upstream = await fetchImpl(upstreamRequest);
    return proxyResponse(upstream);
  } catch {
    return jsonResponse({ error: "Upstream MCP request failed" }, 502);
  }
}
