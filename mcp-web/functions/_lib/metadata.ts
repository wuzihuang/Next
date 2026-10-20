import { configuredOrigin, resolvePublicOrigin, type FetchLike, type McpEnv } from "./env.ts";
import { applyCors, jsonResponse, optionsResponse, proxyResponse } from "./http.ts";

export const PROTECTED_RESOURCE_PATHS = [
  "/.well-known/oauth-protected-resource",
  "/.well-known/oauth-protected-resource/mcp",
] as const;

export const AUTHORIZATION_SERVER_PATHS = [
  "/.well-known/oauth-authorization-server",
  "/.well-known/oauth-authorization-server/mcp",
] as const;

export interface ProtectedResourceMetadata {
  resource: string;
  authorization_servers: string[];
  bearer_methods_supported: ["header"];
  scopes_supported: ["openid", "email", "profile"];
  resource_name: "NextBody";
  resource_documentation: string;
}

export function normalizePath(pathname: string): string {
  if (pathname.length > 1 && pathname.endsWith("/")) return pathname.slice(0, -1);
  return pathname;
}

export function isProtectedResourcePath(pathname: string): boolean {
  return (PROTECTED_RESOURCE_PATHS as readonly string[]).includes(normalizePath(pathname));
}

export function isAuthorizationServerPath(pathname: string): boolean {
  return (AUTHORIZATION_SERVER_PATHS as readonly string[]).includes(normalizePath(pathname));
}

export function protectedResourceMetadata(origin: string, supabaseUrl: string): ProtectedResourceMetadata | null {
  const authorizationOrigin = configuredOrigin(supabaseUrl);
  if (!authorizationOrigin) return null;
  const resourceOrigin = origin.replace(/\/$/, "");
  return {
    resource: `${resourceOrigin}/mcp`,
    authorization_servers: [`${authorizationOrigin}/auth/v1`],
    bearer_methods_supported: ["header"],
    scopes_supported: ["openid", "email", "profile"],
    resource_name: "NextBody",
    resource_documentation: `${resourceOrigin}/`,
  };
}

export function authorizationServerMetadataUrl(supabaseUrl: string): string | null {
  const origin = configuredOrigin(supabaseUrl);
  if (!origin) return null;
  return new URL("/auth/v1/.well-known/oauth-authorization-server", origin).toString();
}

export function handleProtectedResource(request: Request, env: McpEnv): Response {
  if (request.method === "OPTIONS") return optionsResponse();
  if (request.method !== "GET" && request.method !== "HEAD") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  const supabaseUrl = env.SUPABASE_URL?.trim();
  if (!supabaseUrl) return jsonResponse({ error: "SUPABASE_URL is not configured" }, 500);
  const document = protectedResourceMetadata(resolvePublicOrigin(request, env), supabaseUrl);
  if (!document) return jsonResponse({ error: "SUPABASE_URL is not a valid URL" }, 500);
  const headers = new Headers();
  headers.set("content-type", "application/json");
  headers.set("cache-control", "public, max-age=300");
  applyCors(headers);
  const body = request.method === "HEAD" ? null : JSON.stringify(document);
  return new Response(body, { status: 200, headers });
}

export async function handleAuthorizationServer(
  request: Request,
  env: McpEnv,
  fetchImpl: FetchLike = fetch,
): Promise<Response> {
  if (request.method === "OPTIONS") return optionsResponse();
  if (request.method !== "GET" && request.method !== "HEAD") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  const supabaseUrl = env.SUPABASE_URL?.trim();
  if (!supabaseUrl) return jsonResponse({ error: "SUPABASE_URL is not configured" }, 500);
  const upstreamUrl = authorizationServerMetadataUrl(supabaseUrl);
  if (!upstreamUrl) return jsonResponse({ error: "SUPABASE_URL is not a valid URL" }, 500);
  try {
    const upstream = await fetchImpl(upstreamUrl, { method: "GET", redirect: "manual" });
    const response = proxyResponse(upstream);
    if (request.method === "HEAD") {
      return new Response(null, { status: response.status, statusText: response.statusText, headers: response.headers });
    }
    return response;
  } catch {
    return jsonResponse({ error: "Upstream authorization server metadata request failed" }, 502);
  }
}

export async function handleWellKnown(
  request: Request,
  env: McpEnv,
  fetchImpl: FetchLike = fetch,
): Promise<Response> {
  const path = normalizePath(new URL(request.url).pathname);
  if (isProtectedResourcePath(path)) return handleProtectedResource(request, env);
  if (isAuthorizationServerPath(path)) return handleAuthorizationServer(request, env, fetchImpl);
  return jsonResponse({ error: "Not found" }, 404);
}
