import { cors, json } from "../_shared/db.ts";

/** Retired entry point: all AI requests must pass through the turn workflow. */
export function handleMeal(req: Request): Response {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  return json({ error: "WORKFLOW_REQUIRED", endpoint: "turn" }, 410);
}

if (import.meta.main) Deno.serve(handleMeal);
