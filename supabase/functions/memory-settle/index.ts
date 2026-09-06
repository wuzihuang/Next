// ADR 0018 · POST /v1/memory/settle — fold finished sessions into the person's memory.
//
// The phone calls this when the user leaves Chat and whenever it next touches the AI; the
// server picks the sessions that are closed or idle for thirty minutes and not yet
// summarized, and rewrites the memory once per session. It is a system action: it is
// accounted as a model call under `memory`, and it never consumes the user's turn allowance.
//
// The caller's JWT selects the sessions and reads the transcript (RLS). Only the write goes
// through the service role, owner-scoped, and it refuses to resurrect a memory that consent
// withdrawal has erased in the meantime.

import { generateObject } from "npm:ai@4.3.16";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { userClient, serviceClient, currentUserId, cors, json, userDayKey } from "../_shared/db.ts";
import { model, primaryModelId } from "../_shared/model.ts";
import { usageFromProvider } from "../_shared/cost.ts";
import { recordAiUsage, checkAiSpend } from "../_shared/ai-quota.ts";
import { normalizeLocale } from "../_shared/contract.ts";
import {
  MemoryDoc, emptyMemory, estimateTokens, fitMemory, loadMemory, memoryMessages, memoryPrompt,
  type SessionLine,
} from "../_shared/memory.ts";

export const IDLE_MINUTES = 30;

export type MemorySettleDependencies = {
  authenticate: (req: Request) => Promise<string | null>;
  client: (req: Request) => SupabaseClient;
  trusted: () => SupabaseClient;
  generateObject: typeof generateObject;
  spend: (db: SupabaseClient) => Promise<boolean>;
  recordUsage: (db: SupabaseClient, usage: ReturnType<typeof usageFromProvider>, modelId: string) => Promise<void>;
};

const defaults: MemorySettleDependencies = {
  authenticate: currentUserId,
  client: userClient,
  trusted: serviceClient,
  generateObject,
  spend: async (db) => (await checkAiSpend(db)).allowed,
  recordUsage: (db, usage, modelId) => recordAiUsage(db, { endpoint: "memory", modelId, usage }),
};

type TranscriptRow = { at: string; source: "chat" | "panel" | "plan"; user: string | null; assistant: string | null };

export async function handleMemorySettle(req: Request, deps = defaults): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  const userId = await deps.authenticate(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);
  const body = await req.json().catch(() => ({}));
  const db = deps.client(req);

  const [profile, consent] = await Promise.all([
    db.from("profiles").select("locale, timezone, deletion_requested_at").eq("user_id", userId).maybeSingle(),
    db.from("consents").select("choice").eq("user_id", userId).order("decided_at", { ascending: false }).limit(1).maybeSingle(),
  ]);
  if (profile.error || consent.error) return json({ error: "PREFLIGHT_UNAVAILABLE" }, 503);
  if (profile.data?.deletion_requested_at) return json({ error: "ACCOUNT_DELETING" }, 403);
  if (consent.data?.choice !== "granted") return json({ error: "consent_withdrawn" }, 403);
  const locale = normalizeLocale(body?.locale ?? profile.data?.locale);
  const tz = profile.data?.timezone ?? "UTC";

  // An explicit close from the phone, then whatever is due.
  if (typeof body?.close_session === "string") {
    const closed = await db.rpc("close_ai_session", { p_session: body.close_session });
    if (closed.error) return json({ error: "SESSION_UNAVAILABLE" }, 503);
  }
  const due = await db.rpc("ai_sessions_due", { p_idle_minutes: IDLE_MINUTES });
  if (due.error) return json({ error: "SESSIONS_UNAVAILABLE" }, 503);
  const sessions: string[] = Array.isArray(due.data) ? due.data.map((r: unknown) => typeof r === "string" ? r : (r as { ai_sessions_due?: string }).ai_sessions_due ?? "").filter(Boolean) : [];
  if (sessions.length === 0) return json({ settled: [], skipped: [] });

  const settled: string[] = [];
  const skipped: { session: string; reason: string }[] = [];
  const today = userDayKey(tz);
  for (const session of sessions) {
    if (!await deps.spend(db)) { skipped.push({ session, reason: "AI_SPEND_LIMIT" }); break; }
    const transcript = await db.rpc("ai_session_transcript", { p_session: session });
    if (transcript.error) { skipped.push({ session, reason: "TRANSCRIPT_UNAVAILABLE" }); continue; }
    const rows = (transcript.data ?? []) as TranscriptRow[];
    const lines: SessionLine[] = [];
    for (const r of rows) {
      if (r.user?.trim()) lines.push({ role: "user", text: r.user.trim(), at: r.at, source: r.source });
      if (r.assistant?.trim()) lines.push({ role: "assistant", text: r.assistant.trim(), at: r.at, source: r.source });
    }
    if (lines.length === 0) { skipped.push({ session, reason: "EMPTY" }); continue; }
    const old = (await loadMemory(db, userId)) ?? emptyMemory;
    try {
      const result = await deps.generateObject({
        model: model(),
        schema: MemoryDoc,
        system: memoryPrompt(locale),
        messages: memoryMessages(old, lines, today),
        mode: "json",
        maxRetries: 0,
        abortSignal: AbortSignal.timeout(40_000),
      });
      await deps.recordUsage(db, usageFromProvider(result.usage, result.providerMetadata), primaryModelId());
      const doc = fitMemory(result.object);
      const write = await deps.trusted().rpc("write_user_memory_trusted", {
        p_owner: userId, p_session: session, p_summary: doc.summary, p_facts: doc.facts, p_tokens: estimateTokens(doc),
      });
      if (write.error) { skipped.push({ session, reason: "WRITE_FAILED" }); continue; }
      settled.push(session);
    } catch (e) {
      console.error("memory settle failed:", e instanceof Error ? e.message : e);
      skipped.push({ session, reason: "MODEL_UNAVAILABLE" });
    }
  }
  return json({ settled, skipped });
}

if (import.meta.main) Deno.serve((req) => handleMemorySettle(req));
