// F4 §02 · POST /v1/asr — the audio buffer is transcribed and immediately zeroed.
// Nothing is written to Storage and nothing is written to a table.
// ⚠️ confidence < 0.4 returns NO_SPEECH and the client degrades in place to
// DIDN'T CATCH THAT — it never guesses at what was said.

import NodeWebSocket from "npm:ws@8.18.3";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import { audioAppend, finishEvents, parseProviderEvent, realtimeURL, sessionUpdate } from "../_shared/asr-realtime.ts";
import { currentUserId, cors, json, userClient } from "../_shared/db.ts";
import { asrFlashModel } from "../_shared/model.ts";
import { enforceRequestBudget } from "../_shared/rate-limit.ts";
import { consumeAiQuota, quotaDeniedResponse, recordAiUsage } from "../_shared/ai-quota.ts";
import { usageFromProvider, type TokenUsage } from "../_shared/cost.ts";

const MAX_BYTES = 2 * 1024 * 1024;   // ≤ 2 MB, ≤ 60 s

export type AsrTranscript =
  | { ok: true; text: string; usage?: TokenUsage }
  | { ok: false; error: string; status: number };

export type AsrDependencies = {
  authenticate: (request: Request) => Promise<string | null>;
  client: (request: Request) => SupabaseClient;
  budget: (db: SupabaseClient) => Promise<Response | null>;
  quota: (db: SupabaseClient) => Promise<
    { allowed: true } | { allowed: false; reason: "count" | "spend" | "unavailable" }
  >;
  transcribe: (bytes: Uint8Array, mime: string) => Promise<AsrTranscript>;
  recordUsage: (
    db: SupabaseClient,
    usage: TokenUsage,
    modelId: string,
  ) => Promise<void>;
};

async function providerTranscribe(
  bytes: Uint8Array,
  mime: string,
): Promise<AsrTranscript> {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  const dataUri = `data:${mime || "audio/wav"};base64,${btoa(binary)}`;
  const res = await fetch(
    "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${Deno.env.get("DASHSCOPE_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: asrFlashModel(),
        input: { messages: [{ role: "user", content: [{ audio: dataUri }] }] },
        parameters: { asr_options: { language: "zh" } },
      }),
      signal: AbortSignal.timeout(11_000),
    },
  );
  if (!res.ok) return { ok: false, error: "MODEL_UNAVAILABLE", status: 503 };
  const out = await res.json();
  // deno-lint-ignore no-explicit-any
  const parts = out?.output?.choices?.[0]?.message?.content as any[] | undefined;
  const text = (parts ?? []).map((p) => p?.text ?? "").join("").trim();
  return { ok: true, text, usage: usageFromProvider(out?.usage) };
}

const defaults: AsrDependencies = {
  authenticate: currentUserId,
  client: userClient,
  budget: (db) => enforceRequestBudget(db, "asr"),
  quota: (db) => consumeAiQuota(db, "asr"),
  transcribe: providerTranscribe,
  recordUsage: (db, usage, modelId) =>
    recordAiUsage(db, { endpoint: "asr", modelId, usage }),
};

export async function handleAsr(
  req: Request,
  deps = defaults,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if ((req.headers.get("upgrade") ?? "").toLowerCase() === "websocket") {
    const userId = await deps.authenticate(req);
    if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);
    const db = deps.client(req);
    const limited = await deps.budget(db);
    if (limited) return limited;
    const quota = await deps.quota(db);
    if (!quota.allowed) return quotaDeniedResponse("en-US", quota);
    return await streamTranscription(req);
  }
  const started = Date.now();
  const [userId, form] = await Promise.all([
    deps.authenticate(req),
    req.formData().catch(() => null),
  ]);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const file = form?.get("audio");
  if (!(file instanceof File)) return json({ error: "E_SCHEMA" }, 422);
  if (file.size > MAX_BYTES) return json({ error: "E_SCHEMA", reason: "TOO_LARGE" }, 413);

  const db = deps.client(req);
  const limited = await deps.budget(db);
  if (limited) return limited;
  const quota = await deps.quota(db);
  if (!quota.allowed) return quotaDeniedResponse("en-US", quota);

  let buffer: ArrayBuffer | null = await file.arrayBuffer();
  try {
    const bytes = new Uint8Array(buffer!);
    const result = await deps.transcribe(bytes, file.type || "audio/wav");
    if (!result.ok) return json({ error: result.error }, result.status);
    const text = result.text.trim();
    if (!text || isFiller(text)) return json({ error: "NO_SPEECH" }, 200);
    await deps.recordUsage(
      db,
      result.usage ?? { promptTokens: 0, cachedTokens: 0, completionTokens: 0 },
      asrFlashModel(),
    );
    return json({
      text,
      durationMs: null,
      confidence: null,
      latencyMs: Date.now() - started,
    });
  } finally {
    buffer = null;
  }
}

if (import.meta.main) Deno.serve((req) => handleAsr(req));


async function streamTranscription(req: Request): Promise<Response> {
  const [userId, key] = await Promise.all([
    currentUserId(req),
    Promise.resolve(Deno.env.get("DASHSCOPE_API_KEY")),
  ]);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);
  if (!key) return json({ error: "MODEL_UNAVAILABLE" }, 503);

  const { socket, response } = Deno.upgradeWebSocket(req);
  let upstream: NodeWebSocket | null = null;
  let upstreamReady = false;
  let finishRequested = false;
  let finishSent = false;
  let resultSent = false;
  let closed = false;
  let byteCount = 0;
  const pending: Uint8Array[] = [];

  let resolveLifetime: () => void = () => {};
  const lifetime = new Promise<void>((resolve) => {
    resolveLifetime = resolve;
  });
  const runtime = globalThis as typeof globalThis & {
    EdgeRuntime?: { waitUntil(promise: Promise<unknown>): void };
  };
  runtime.EdgeRuntime?.waitUntil(lifetime);

  const sendClient = (event: Record<string, unknown>) => {
    if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(event));
  };
  const close = () => {
    if (closed) return;
    closed = true;
    clearTimeout(timeout);
    pending.length = 0;
    if (upstream && upstream.readyState < NodeWebSocket.CLOSING) upstream.close();
    if (socket.readyState < WebSocket.CLOSING) socket.close();
    resolveLifetime();
  };
  const fail = (message: string) => {
    sendClient({ type: "error", error: "MODEL_UNAVAILABLE", reason: message });
    close();
  };
  const sendAudio = (bytes: Uint8Array) => {
    if (!upstream || upstream.readyState !== NodeWebSocket.OPEN) {
      fail("PROVIDER_NOT_OPEN");
      return;
    }
    upstream.send(audioAppend(bytes));
  };
  const finishProvider = () => {
    if (!finishRequested || !upstreamReady || finishSent || closed) return;
    finishSent = true;
    for (const event of finishEvents()) upstream?.send(event);
  };
  const timeout = setTimeout(() => fail("STREAM_TIMEOUT"), 70_000);

  socket.onopen = () => {
    upstream = new NodeWebSocket(realtimeURL(), {
      headers: {
        Authorization: `Bearer ${key}`,
        "OpenAI-Beta": "realtime=v1",
      },
    });
    upstream.on("open", () => upstream?.send(sessionUpdate("zh")));
    upstream.on("message", (raw) => {
      const event = parseProviderEvent(raw.toString());
      switch (event.kind) {
        case "ready":
          upstreamReady = true;
          pending.splice(0).forEach(sendAudio);
          sendClient({ type: "ready" });
          finishProvider();
          break;
        case "partial":
          if (event.text) sendClient({ type: "partial", text: event.text });
          break;
        case "completed":
          resultSent = true;
          sendClient(isFiller(event.text)
            ? { type: "done", error: "NO_SPEECH" }
            : { type: "done", text: event.text });
          break;
        case "finished":
          if (!resultSent) sendClient({ type: "done", error: "NO_SPEECH" });
          close();
          break;
        case "error":
          fail(event.message);
          break;
        case "other":
          break;
      }
    });
    upstream.on("error", (error) => fail(error.message));
    upstream.on("close", () => {
      if (!closed) fail("PROVIDER_CLOSED");
    });
  };

  socket.onmessage = (event) => {
    if (typeof event.data === "string") {
      let type = "";
      try {
        type = String((JSON.parse(event.data) as Record<string, unknown>).type ?? "");
      } catch {
        fail("INVALID_CLIENT_EVENT");
        return;
      }
      if (type === "finish") {
        finishRequested = true;
        finishProvider();
      } else if (type === "cancel") {
        close();
      }
      return;
    }

    const bytes = event.data instanceof ArrayBuffer
      ? new Uint8Array(event.data)
      : ArrayBuffer.isView(event.data)
      ? new Uint8Array(event.data.buffer, event.data.byteOffset, event.data.byteLength)
      : null;
    if (!bytes?.length) return;
    byteCount += bytes.length;
    if (byteCount > MAX_BYTES) {
      fail("TOO_LARGE");
      return;
    }
    const copy = bytes.slice();
    if (upstreamReady) sendAudio(copy);
    else pending.push(copy);
  };
  socket.onerror = () => close();
  socket.onclose = () => close();

  return response;
}

function isFiller(text: string): boolean {
  return /^[嗯啊呃哦唔呀哈\s。，、．.,!?！？~-]+$/u.test(text);
}
