import type { EventContext } from "@cloudflare/workers-types";
import type { McpEnv } from "./_lib/env.ts";
import { handleMcp } from "./_lib/mcp.ts";

export async function onRequest(context: EventContext<McpEnv, string, unknown>): Promise<Response> {
  return handleMcp(context.request, context.env);
}
