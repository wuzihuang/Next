import type { EventContext } from "@cloudflare/workers-types";
import type { McpEnv } from "../_lib/env.ts";
import { handleWellKnown } from "../_lib/metadata.ts";

export async function onRequest(context: EventContext<McpEnv, string, unknown>): Promise<Response> {
  return handleWellKnown(context.request, context.env);
}
