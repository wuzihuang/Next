// F4 §02 · POST /v1/turn · SSE.
// Event order is fixed: state(THINKING) → tool(0..n) → screen.render(1) → done.
// Every error carries a fallback_frame, and that frame is itself a legal envelope —
// the panel is never allowed to go empty.

import { generateText } from "npm:ai@4.3.16";
import { model, MODEL_VERSION } from "../_shared/model.ts";
import { systemPrompt } from "../_shared/prompt.ts";
import { buildTools } from "../_shared/tools.ts";
import { NumberLedger, auditFrame } from "../_shared/ledger.ts";
import { Envelope, MEDICAL_STOP, batteryFallback } from "../_shared/contract.ts";
import { userClient, currentUserId, cors, json } from "../_shared/db.ts";

const MEDICAL = /(诊断|症状|吃药|用药|疾病|怀孕|安全吗|癌|糖尿病|高血压|抑郁|medicine|diagnos|pregnan|symptom)/i;

// 60 turns an hour and 150 a day. Free forever does not mean unlimited: the cost is real,
// and the ceiling is a rate limit rather than a paywall.
const HOURLY = 60, DAILY = 150;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const userId = await currentUserId(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const db = userClient(req);
  const body = await req.json().catch(() => ({}));
  const text: string = body.text ?? "";
  const dayKey: string = body.dayKey ?? new Date().toISOString().slice(0, 10);
  const turnId: string = req.headers.get("Idempotency-Key") ?? crypto.randomUUID();

  // Replaying the same Idempotency-Key returns the same frames, so a dropped connection
  // never costs a second model call.
  const { data: existing } = await db.from("ai_turns")
    .select("id, frame_id").eq("id", turnId).maybeSingle();
  if (existing?.frame_id) {
    const { data: frame } = await db.from("screen_frames")
      .select("widget_tree").eq("id", existing.frame_id).maybeSingle();
    if (frame) return json({ envelope: frame.widget_tree, replay: true });
  }

  const { count: recent } = await db.from("ai_turns")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", new Date(Date.now() - 3600_000).toISOString());
  if ((recent ?? 0) >= HOURLY) {
    return sse((send) => {
      send("error", { code: "RATE_LIMITED", fallback_frame: batteryFallback(null) });
    });
  }

  const started = Date.now();
  const ledger = new NumberLedger();
  const tools = buildTools(db, userId, ledger);
  const trace: unknown[] = [];

  return sse(async (send) => {
    send("state", { value: "THINKING" });

    // S7 · the medical stop happens before any tool call, not after.
    if (MEDICAL.test(text)) {
      await persist(db, userId, turnId, text, MEDICAL_STOP, trace, Date.now() - started);
      send("screen.render", { envelope: MEDICAL_STOP });
      send("done", {});
      return;
    }

    let envelope: Envelope | null = null;
    try {
      const result = await generateText({
        model: model(),
        system: systemPrompt(),
        // S9 · everything between the tags is data, not instruction.
        prompt: `<user_text>\n${text}\n</user_text>\n\ndayKey=${dayKey}`,
        tools,
        maxSteps: 6,
        toolChoice: "auto",
        abortSignal: AbortSignal.timeout(50_000),
      });

      for (const step of result.steps ?? []) {
        for (const call of step.toolCalls ?? []) {
          trace.push({ tool: call.toolName, args: call.args });
          send("tool", { name: call.toolName });
        }
      }

      ledger.seal();
      envelope = extractEnvelope(result.text);
    } catch (_e) {
      send("error", { code: "MODEL_UNAVAILABLE", fallback_frame: batteryFallback(null) });
      send("done", {});
      return;
    }

    const parsed = Envelope.safeParse(envelope);
    if (!parsed.success) {
      const fb = batteryFallback(null);
      await persist(db, userId, turnId, text, fb, trace, Date.now() - started);
      send("error", { code: "E_SCHEMA", fallback_frame: fb });
      send("done", {});
      return;
    }

    // F4 §05 · the banned list is scanned after rendering. A hit throws away the whole
    // frame — no word-level surgery, because the sentence that contained it was wrong.
    const banned = await loadBanned(db);
    const blob = [parsed.data.title, parsed.data.sentence, parsed.data.footer, parsed.data.action]
      .filter(Boolean).join(" ");
    const hit = banned.find((re) => re.test(blob));
    if (hit) {
      const fb = batteryFallback(null);
      await persist(db, userId, turnId, text, fb, trace, Date.now() - started);
      send("error", { code: "E_SCHEMA", reason: "BANNED_PHRASE", fallback_frame: fb });
      send("done", {});
      return;
    }

    // F4 §06 · one untraceable number rejects the frame.
    const audit = auditFrame(parsed.data as unknown as Record<string, unknown>, ledger);
    if (!audit.ok) {
      const fb = batteryFallback(null);
      await persist(db, userId, turnId, text, fb, trace, Date.now() - started);
      send("error", {
        code: "E_SCHEMA", reason: "UNTRACEABLE_NUMBER", value: audit.value, fallback_frame: fb,
      });
      send("done", {});
      return;
    }

    await persist(db, userId, turnId, text, parsed.data, trace, Date.now() - started);
    send("screen.render", { envelope: parsed.data });
    send("done", {});
  });
});

function extractEnvelope(text: string): unknown {
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) return null;
  try { return JSON.parse(match[0]); } catch { return null; }
}

let bannedCache: { at: number; list: RegExp[] } | null = null;
async function loadBanned(db: ReturnType<typeof userClient>): Promise<RegExp[]> {
  // read once, cached for five minutes — adding a word must not require a release
  if (bannedCache && Date.now() - bannedCache.at < 300_000) return bannedCache.list;
  const { data } = await db.from("banned_phrases").select("pattern");
  const list = (data ?? []).map((r) => {
    try { return new RegExp(r.pattern); } catch { return /$^/; }
  });
  bannedCache = { at: Date.now(), list };
  return list;
}

async function persist(
  db: ReturnType<typeof userClient>, userId: string, turnId: string,
  text: string, envelope: Envelope, trace: unknown[], latency: number,
) {
  const { data: frame } = await db.from("screen_frames").insert({
    user_id: userId,
    trigger: "turn",
    widget_tree: envelope,
    expires_at: new Date(Date.now() + envelope.ttl_min * 60_000).toISOString(),
    model_version: MODEL_VERSION,
    latency_ms: latency,
    tool_calls: trace,
  }).select("id").single();

  await db.from("ai_turns").upsert({
    id: turnId, user_id: userId, user_text: text, tool_trace: trace,
    frame_id: frame?.id ?? null, model_version: MODEL_VERSION,
    latency_ms: latency, outcome: "ok",
  });
}

function sse(run: (send: (event: string, data: unknown) => void) => void | Promise<void>): Response {
  const stream = new ReadableStream({
    async start(controller) {
      const enc = new TextEncoder();
      const send = (event: string, data: unknown) => {
        controller.enqueue(enc.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
      };
      try { await run(send); } finally { controller.close(); }
    },
  });
  return new Response(stream, {
    headers: { ...cors, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
  });
}
