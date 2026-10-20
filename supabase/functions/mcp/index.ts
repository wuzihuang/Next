// ADR 0032 · MCP over Streamable HTTP (stateless JSON, no sessions) for assistants a person
// connected through Supabase OAuth. Every read and write runs on the caller's token, so RLS,
// `mcp_request_gate` and the meal RPCs' own checks all apply.
import { assistantCaller, userClient } from "../_shared/db.ts";
import { enforceRequestBudget } from "../_shared/rate-limit.ts";
import { handleMcp, type McpDependencies } from "./server.ts";

const dependencies: McpDependencies = {
  authenticate: assistantCaller,
  client: userClient,
  budget: (db) => enforceRequestBudget(db, "mcp"),
  publicOrigin: () => (Deno.env.get("MCP_PUBLIC_ORIGIN") ?? "https://mcp.nextbody.ai").replace(/\/$/, ""),
  now: () => new Date(),
  newId: () => crypto.randomUUID(),
};

if (import.meta.main) Deno.serve((req) => handleMcp(req, dependencies));
