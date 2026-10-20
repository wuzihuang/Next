export const FORWARDED_REQUEST_HEADERS = [
  "authorization",
  "content-type",
  "accept",
  "mcp-session-id",
  "mcp-protocol-version",
  "last-event-id",
] as const;

export const CORS_ALLOW_HEADERS =
  "authorization, content-type, accept, mcp-session-id, mcp-protocol-version, last-event-id";

export const CORS_EXPOSE_HEADERS = "www-authenticate, mcp-session-id";

// Browser preflight of a JSON POST fails without this, even though the MCP client list is the allow-headers set.
export const CORS_ALLOW_METHODS = "GET, POST, DELETE, OPTIONS";

const HOP_BY_HOP = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
]);

export function applyCors(headers: Headers): void {
  headers.set("access-control-allow-origin", "*");
  headers.set("access-control-allow-headers", CORS_ALLOW_HEADERS);
  headers.set("access-control-expose-headers", CORS_EXPOSE_HEADERS);
}

export function optionsResponse(): Response {
  const headers = new Headers();
  applyCors(headers);
  headers.set("access-control-allow-methods", CORS_ALLOW_METHODS);
  return new Response(null, { status: 204, headers });
}

export function jsonResponse(body: unknown, status: number): Response {
  const headers = new Headers();
  headers.set("content-type", "application/json");
  applyCors(headers);
  return new Response(JSON.stringify(body), { status, headers });
}

export function cloneUpstreamHeaders(source: Headers): Headers {
  const headers = new Headers();
  source.forEach(function copyHeader(value: string, key: string): void {
    if (HOP_BY_HOP.has(key)) return;
    headers.append(key, value);
  });
  return headers;
}

export function proxyResponse(upstream: Response): Response {
  const headers = cloneUpstreamHeaders(upstream.headers);
  applyCors(headers);
  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers,
  });
}

export function incomingHost(request: Request): string {
  return request.headers.get("host") ?? new URL(request.url).host;
}

export function forwardedRequestHeaders(request: Request, publishableKey: string | undefined): Headers {
  const headers = new Headers();
  for (const name of FORWARDED_REQUEST_HEADERS) {
    const value = request.headers.get(name);
    if (value !== null) headers.set(name, value);
  }
  const key = publishableKey?.trim();
  if (key) headers.set("apikey", key);
  headers.set("x-forwarded-host", incomingHost(request));
  return headers;
}
