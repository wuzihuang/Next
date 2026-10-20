import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { type Access, type ToolContext, type ToolOutcome, TOOLS } from "./tools.ts";

export const SUPPORTED_PROTOCOLS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"];
const LATEST_PROTOCOL = "2025-06-18";
const MAX_BODY = 64_000;

const INSTRUCTIONS =
  "NextBody holds this person's own data from their HOOP band and app: sleep, heart rate and HRV, body battery, training load, calories, meals, weight and body composition. Dates are the person's local days (YYYY-MM-DD). Missing values are unknown — never present them as zero. Derived scores are product estimates, not medical findings. Before logging or deleting meals, confirm the foods and amounts with the person.";

export interface McpDependencies {
  authenticate: (req: Request) => Promise<{ userId: string; clientId: string } | null>;
  client: (req: Request) => SupabaseClient;
  budget: (db: SupabaseClient) => Promise<Response | null>;
  publicOrigin: () => string;
  now: () => Date;
  newId: () => string;
}

type JsonRpcId = string | number | null;
type JsonRpcMessage = { jsonrpc?: unknown; id?: JsonRpcId; method?: unknown; params?: unknown };

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, content-type, accept, mcp-session-id, mcp-protocol-version, last-event-id, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, GET, DELETE, OPTIONS",
  "Access-Control-Expose-Headers": "www-authenticate, mcp-session-id",
};

function respond(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { ...CORS, ...(body === null ? {} : { "Content-Type": "application/json" }), ...headers },
  });
}

function unauthorized(deps: McpDependencies, reason?: string): Response {
  const metadata = `${deps.publicOrigin()}/.well-known/oauth-protected-resource`;
  const challenge = reason
    ? `Bearer resource_metadata="${metadata}", error="invalid_token", error_description="${reason}"`
    : `Bearer resource_metadata="${metadata}"`;
  return respond({ error: "UNAUTHENTICATED" }, 401, { "WWW-Authenticate": challenge });
}

function rpcError(id: JsonRpcId, code: number, message: string): Record<string, unknown> {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

function rpcResult(id: JsonRpcId, result: unknown): Record<string, unknown> {
  return { jsonrpc: "2.0", id, result };
}

function toolResult(outcome: ToolOutcome): Record<string, unknown> {
  if (outcome.ok) {
    return {
      content: [{ type: "text", text: JSON.stringify(outcome.data) }],
      structuredContent: outcome.data,
    };
  }
  return {
    content: [{ type: "text", text: `${outcome.error}: ${outcome.message}` }],
    isError: true,
  };
}

type AccessCheck =
  | { ok: true; access: Access }
  | { ok: false; response: Response };

async function checkAccess(
  deps: McpDependencies,
  db: SupabaseClient,
  caller: { userId: string; clientId: string },
): Promise<AccessCheck> {
  const { data, error } = await db.rpc("touch_mcp_grant");
  if (error) {
    if (error.code === "42501" || error.code === "28000" || String(error.message).includes("MCP_GRANT_MISSING")) {
      return { ok: false, response: unauthorized(deps, "Access to NextBody was revoked. Reconnect to continue.") };
    }
    return { ok: false, response: respond({ error: "ACCESS_CHECK_UNAVAILABLE" }, 503) };
  }
  const grant = (data ?? {}) as Record<string, unknown>;
  if (grant.deleting === true) {
    return { ok: false, response: respond({ error: "ACCOUNT_DELETING" }, 403) };
  }
  if (grant.consent !== "granted") {
    return {
      ok: false,
      response: respond({
        error: "consent_withdrawn",
        message: "Data collection is paused in the NextBody app. Turn it back on there to use this connection.",
      }, 403),
    };
  }
  return {
    ok: true,
    access: {
      userId: caller.userId,
      clientId: caller.clientId,
      clientName: typeof grant.client_name === "string" ? grant.client_name : "",
      canWrite: grant.can_write === true,
      timezone: typeof grant.timezone === "string" && grant.timezone ? grant.timezone : "UTC",
    },
  };
}

async function handleMessage(
  message: JsonRpcMessage,
  deps: McpDependencies,
  db: SupabaseClient,
  access: Access,
): Promise<Record<string, unknown> | null> {
  const isRequest = message.id !== undefined && message.id !== null;
  if (message.jsonrpc !== "2.0" || typeof message.method !== "string") {
    // Responses and malformed notifications need no reply.
    return isRequest ? rpcError(message.id ?? null, -32600, "Invalid Request") : null;
  }
  if (!isRequest) return null;
  const id = message.id as JsonRpcId;
  const params = (message.params ?? {}) as Record<string, unknown>;
  switch (message.method) {
    case "initialize": {
      const requested = typeof params.protocolVersion === "string" ? params.protocolVersion : "";
      return rpcResult(id, {
        protocolVersion: SUPPORTED_PROTOCOLS.includes(requested) ? requested : LATEST_PROTOCOL,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "nextbody", title: "NextBody", version: "1.0.0" },
        instructions: INSTRUCTIONS,
      });
    }
    case "ping":
      return rpcResult(id, {});
    case "tools/list":
      return rpcResult(id, {
        tools: TOOLS.map(({ name, title, description, inputSchema, annotations }) => ({
          name,
          title,
          description,
          inputSchema,
          annotations,
        })),
      });
    case "tools/call": {
      const tool = TOOLS.find((t) => t.name === params.name);
      if (!tool) return rpcError(id, -32602, `Unknown tool: ${String(params.name)}`);
      const limited = await deps.budget(db);
      if (limited) {
        const retry = limited.headers.get("Retry-After") ?? "60";
        return rpcResult(id, toolResult({
          ok: false,
          error: limited.status === 429 ? "RATE_LIMITED" : "UNAVAILABLE",
          message: limited.status === 429 ? `Too many requests. Retry in ${retry} seconds.` : "Try again shortly.",
        }));
      }
      const ctx: ToolContext = { db, access, now: deps.now(), newId: deps.newId };
      try {
        return rpcResult(id, toolResult(await tool.run(ctx, params.arguments ?? {})));
      } catch {
        return rpcResult(id, toolResult({ ok: false, error: "UNAVAILABLE", message: "Try again shortly." }));
      }
    }
    default:
      return rpcError(id, -32601, `Method not found: ${message.method}`);
  }
}

export async function handleMcp(req: Request, deps: McpDependencies): Promise<Response> {
  if (req.method === "OPTIONS") return respond(null, 204);
  if (req.method !== "POST") {
    return respond({ error: "METHOD_NOT_ALLOWED" }, 405, { Allow: "POST, OPTIONS" });
  }
  const caller = await deps.authenticate(req);
  if (!caller) return unauthorized(deps);

  const text = await req.text();
  if (text.length > MAX_BODY) return respond(rpcError(null, -32600, "Request too large"), 413);
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return respond(rpcError(null, -32700, "Parse error"), 400);
  }
  const messages = (Array.isArray(body) ? body : [body]) as JsonRpcMessage[];
  if (!messages.length || messages.some((m) => !m || typeof m !== "object")) {
    return respond(rpcError(null, -32600, "Invalid Request"), 400);
  }

  const db = deps.client(req);
  const checked = await checkAccess(deps, db, caller);
  if (!checked.ok) return checked.response;

  const replies: Record<string, unknown>[] = [];
  for (const message of messages) {
    const reply = await handleMessage(message, deps, db, checked.access);
    if (reply) replies.push(reply);
  }
  if (!replies.length) return respond(null, 202);
  return respond(Array.isArray(body) ? replies : replies[0]);
}
