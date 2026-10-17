import { cors, json } from "./db.ts";

/** AI endpoints answer 410 AI_DISABLED unless the project sets AI_ENABLED=1. */
export function aiDisabled(req: Request): Response | null {
  if (Deno.env.get("AI_ENABLED") === "1") return null;
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  return json({ error: "AI_DISABLED" }, 410);
}
