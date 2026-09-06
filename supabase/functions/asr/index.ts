// F4 §02 · POST /v1/asr — the audio buffer is transcribed and immediately zeroed.
// Audio is never persisted; only operation usage and cost are recorded.
// ⚠️ confidence < 0.4 returns NO_SPEECH and the client degrades in place to
// DIDN'T CATCH THAT — it never guesses at what was said.

import NodeWebSocket from "npm:ws@8.18.3";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  audioAppend,
  finishEvents,
  parseProviderEvent,
  realtimeURL,
  sessionUpdate,
} from "../_shared/asr-realtime.ts";
import { cors, currentUserId, json, userClient } from "../_shared/db.ts";
import { asrFlashModel, asrRealtimeModel } from "../_shared/model.ts";
import { enforceRequestBudget } from "../_shared/rate-limit.ts";
import {
  consumeAiQuota,
  quotaDeniedResponse,
  recordAiUsage,
} from "../_shared/ai-quota.ts";
import { type TokenUsage, usageFromProvider } from "../_shared/cost.ts";

const MAX_BYTES = 2 * 1024 * 1024;
const MAX_SECONDS = 60;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type AsrTranscript =
  | { ok: true; text: string; usage?: TokenUsage }
  | { ok: false; error: string; status: number };

export type AsrDependencies = {
  authenticate: (request: Request) => Promise<string | null>;
  client: (request: Request) => SupabaseClient;
  budget: (db: SupabaseClient) => Promise<Response | null>;
  quota: (db: SupabaseClient, operationId?: string) => Promise<
    { allowed: true } | {
      allowed: false;
      reason: "count" | "spend" | "unavailable";
    }
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
  const parts = out?.output?.choices?.[0]?.message?.content as
    | { text?: string }[]
    | undefined;
  const text = (parts ?? []).map((p) => p?.text ?? "").join("").trim();
  return { ok: true, text, usage: usageFromProvider(out?.usage) };
}

const defaults: AsrDependencies = {
  authenticate: currentUserId,
  client: userClient,
  budget: (db) => enforceRequestBudget(db, "asr"),
  quota: (db, operationId) => consumeAiQuota(db, "asr", operationId),
  transcribe: providerTranscribe,
  recordUsage: (db, usage, modelId) =>
    recordAiUsage(db, { endpoint: "asr", modelId, usage }),
};

export async function handleAsr(
  req: Request,
  deps = defaults,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const operationId = req.headers.get("Idempotency-Key");
  if (!operationId || !UUID.test(operationId)) {
    return json({ error: "E_SCHEMA", reason: "INVALID_OPERATION_ID" }, 422);
  }
  if ((req.headers.get("upgrade") ?? "").toLowerCase() === "websocket") {
    const userId = await deps.authenticate(req);
    if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);
    const db = deps.client(req);
    const limited = await deps.budget(db);
    if (limited) return limited;
    const quota = await deps.quota(db, operationId);
    if (!quota.allowed) return quotaDeniedResponse("en-US", quota);
    return streamTranscription(req, deps, db);
  }
  const started = Date.now();
  const [userId, form] = await Promise.all([
    deps.authenticate(req),
    req.formData().catch(() => null),
  ]);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const file = form?.get("audio");
  if (!(file instanceof File)) return json({ error: "E_SCHEMA" }, 422);
  if (file.size > MAX_BYTES) {
    return json({ error: "E_SCHEMA", reason: "TOO_LARGE" }, 413);
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  const audioSeconds = audioDurationSeconds(bytes, file.type || "audio/wav");
  if (audioSeconds === null || audioSeconds <= 0) {
    bytes.fill(0);
    return json({ error: "E_SCHEMA", reason: "INVALID_AUDIO" }, 422);
  }
  if (audioSeconds > MAX_SECONDS) {
    bytes.fill(0);
    return json({ error: "E_SCHEMA", reason: "TOO_LONG" }, 413);
  }

  const db = deps.client(req);
  let usage: TokenUsage = {
    promptTokens: 0,
    cachedTokens: 0,
    completionTokens: 0,
  };
  try {
    const limited = await deps.budget(db);
    if (limited) return limited;
    const quota = await deps.quota(db, operationId);
    if (!quota.allowed) return quotaDeniedResponse("en-US", quota);
    let result: AsrTranscript;
    try {
      result = await deps.transcribe(bytes, file.type || "audio/wav");
      if (result.ok && result.usage) usage = result.usage;
    } catch {
      result = { ok: false, error: "MODEL_UNAVAILABLE", status: 503 };
    }
    // Account even for silence and failed attempts: audio already reached the provider.
    try {
      await deps.recordUsage(db, { ...usage, audioSeconds }, asrFlashModel());
    } catch (error) {
      console.error(
        "ASR_USAGE_UNAVAILABLE",
        error instanceof Error ? error.message : "write failed",
      );
      return json({ error: "AI_USAGE_UNAVAILABLE" }, 503);
    }
    if (!result.ok) return json({ error: result.error }, result.status);
    const text = result.text.trim();
    if (!text || isFiller(text)) return json({ error: "NO_SPEECH" }, 200);
    return json({
      text,
      durationMs: audioSeconds * 1000,
      confidence: null,
      latencyMs: Date.now() - started,
    });
  } finally {
    bytes.fill(0);
  }
}

if (import.meta.main) Deno.serve((req) => handleAsr(req));

function streamTranscription(
  req: Request,
  deps: AsrDependencies,
  db: SupabaseClient,
): Response {
  const key = Deno.env.get("DASHSCOPE_API_KEY");
  if (!key) return json({ error: "MODEL_UNAVAILABLE" }, 503);

  const { socket, response } = Deno.upgradeWebSocket(req);
  let upstream: NodeWebSocket | null = null;
  let upstreamReady = false;
  let finishRequested = false;
  let finishSent = false;
  let finalEvent: Record<string, unknown> | null = null;
  let closed = false;
  let byteCount = 0;
  let submittedBytes = 0;
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
    if (socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(event));
    }
  };
  const close = () => {
    if (closed) return;
    closed = true;
    clearTimeout(timeout);
    pending.forEach((bytes) => bytes.fill(0));
    pending.length = 0;
    if (upstream && upstream.readyState < NodeWebSocket.CLOSING) {
      upstream.close();
    }
    // Keep the edge lifetime alive until accounting settles, including cancel/failure.
    void (async () => {
      try {
        if (submittedBytes > 0) {
          await deps.recordUsage(db, {
            promptTokens: 0,
            cachedTokens: 0,
            completionTokens: 0,
            audioSeconds: submittedBytes / 32_000,
          }, asrRealtimeModel());
        }
        if (finalEvent) sendClient(finalEvent);
      } catch (error) {
        console.error(
          "ASR_USAGE_UNAVAILABLE",
          error instanceof Error ? error.message : "write failed",
        );
        sendClient({ type: "error", error: "AI_USAGE_UNAVAILABLE" });
      } finally {
        if (socket.readyState < WebSocket.CLOSING) socket.close();
        resolveLifetime();
      }
    })();
  };
  const fail = (message: string) => {
    finalEvent = null;
    sendClient({ type: "error", error: "MODEL_UNAVAILABLE", reason: message });
    close();
  };
  const sendAudio = (bytes: Uint8Array) => {
    if (!upstream || upstream.readyState !== NodeWebSocket.OPEN) {
      bytes.fill(0);
      fail("PROVIDER_NOT_OPEN");
      return;
    }
    try {
      upstream.send(audioAppend(bytes));
      submittedBytes += bytes.length;
    } catch {
      fail("PROVIDER_SEND_FAILED");
    } finally {
      bytes.fill(0);
    }
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
          finalEvent = !event.text.trim() || isFiller(event.text)
            ? { type: "done", error: "NO_SPEECH" }
            : { type: "done", text: event.text };
          break;
        case "finished":
          finalEvent ??= { type: "done", error: "NO_SPEECH" };
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
    if (closed) return;
    if (typeof event.data === "string") {
      let type = "";
      try {
        type = String(
          (JSON.parse(event.data) as Record<string, unknown>).type ?? "",
        );
      } catch {
        fail("INVALID_CLIENT_EVENT");
        return;
      }
      if (type === "finish") {
        finishRequested = true;
        finishProvider();
      } else if (type === "cancel") {
        finalEvent = null;
        close();
      }
      return;
    }

    if (finishRequested) return;
    const bytes = event.data instanceof ArrayBuffer
      ? new Uint8Array(event.data)
      : ArrayBuffer.isView(event.data)
      ? new Uint8Array(
        event.data.buffer,
        event.data.byteOffset,
        event.data.byteLength,
      )
      : null;
    if (!bytes?.length) return;
    byteCount += bytes.length;
    if (byteCount > MAX_BYTES || byteCount / 32_000 > MAX_SECONDS) {
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

/** Duration from the bytes we submit, never a client-supplied duration. */
export function audioDurationSeconds(
  bytes: Uint8Array,
  mime: string,
): number | null {
  const format = mime.split(";")[0].trim().toLowerCase();
  if (
    ["audio/pcm", "audio/x-pcm", "application/octet-stream"].includes(format)
  ) {
    return bytes.length % 2 === 0 ? bytes.length / 32_000 : null;
  }
  if (
    !["audio/wav", "audio/wave", "audio/x-wav"].includes(format) ||
    bytes.length < 12
  ) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (offset: number) =>
    String.fromCharCode(...bytes.subarray(offset, offset + 4));
  if (tag(0) !== "RIFF" || tag(8) !== "WAVE") return null;
  const end = view.getUint32(4, true) + 8;
  if (end > bytes.length || end < 12) return null;
  let bytesPerSecond = 0, blockAlign = 0, dataBytes = 0;
  for (let offset = 12; offset + 8 <= end;) {
    const size = view.getUint32(offset + 4, true);
    const body = offset + 8;
    if (body + size > end) return null;
    if (tag(offset) === "fmt ") {
      if (size < 16 || view.getUint16(body, true) !== 1) return null;
      const channels = view.getUint16(body + 2, true);
      const sampleRate = view.getUint32(body + 4, true);
      const bits = view.getUint16(body + 14, true);
      blockAlign = channels * bits / 8;
      if (
        !channels || !sampleRate || ![8, 16, 24, 32].includes(bits) ||
        view.getUint16(body + 12, true) !== blockAlign
      ) return null;
      bytesPerSecond = sampleRate * blockAlign;
      if (view.getUint32(body + 8, true) !== bytesPerSecond) return null;
    } else if (tag(offset) === "data") dataBytes += size;
    offset = body + size + (size % 2);
  }
  return bytesPerSecond && dataBytes % blockAlign === 0
    ? dataBytes / bytesPerSecond
    : null;
}

function isFiller(text: string): boolean {
  return /^[嗯啊呃哦唔呀哈\s。，、．.,!?！？~-]+$/u.test(text);
}
