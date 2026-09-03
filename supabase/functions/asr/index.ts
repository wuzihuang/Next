// F4 §02 · POST /v1/asr — the audio buffer is transcribed and immediately zeroed.
// Nothing is written to Storage and nothing is written to a table.
// ⚠️ confidence < 0.4 returns NO_SPEECH and the client degrades in place to
// DIDN'T CATCH THAT — it never guesses at what was said.

import NodeWebSocket from "npm:ws@8.18.3";
import { audioAppend, finishEvents, parseProviderEvent, realtimeURL, sessionUpdate } from "../_shared/asr-realtime.ts";
import { currentUserId, cors, json } from "../_shared/db.ts";

const MAX_BYTES = 2 * 1024 * 1024;   // ≤ 2 MB, ≤ 60 s

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if ((req.headers.get("upgrade") ?? "").toLowerCase() === "websocket") {
    return await streamTranscription(req);
  }
  const started = Date.now();
  const [userId, form] = await Promise.all([
    currentUserId(req),
    req.formData().catch(() => null),
  ]);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const file = form?.get("audio");
  if (!(file instanceof File)) return json({ error: "E_SCHEMA" }, 422);
  if (file.size > MAX_BYTES) return json({ error: "E_SCHEMA", reason: "TOO_LARGE" }, 413);

  let buffer: ArrayBuffer | null = await file.arrayBuffer();
  try {
    const bytes = new Uint8Array(buffer!);
    // ⚠️ This used to POST a multipart file to
    // `/compatible-mode/v1/audio/transcriptions` with `paraformer-realtime-v2`. That path does
    // not exist on DashScope — it answers 404 — so every request here returned
    // MODEL_UNAVAILABLE and the voice input could never have worked. A typechecker cannot see a
    // wrong URL, and the failure looked exactly like the model being down.
    //
    // What does work, tried with real speech: qwen3-asr-flash on the multimodal endpoint, with
    // the clip inline as a data URI. It returned 「今天吃了半碗面加一个鸡蛋。」 for a clip that
    // said exactly that.
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    }
    const dataUri = `data:${file.type || "audio/wav"};base64,${btoa(binary)}`;

    const res = await fetch(
      "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${Deno.env.get("DASHSCOPE_API_KEY")}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "qwen3-asr-flash",
          input: { messages: [{ role: "user", content: [{ audio: dataUri }] }] },
          parameters: { asr_options: { language: "zh" } },
        }),
        signal: AbortSignal.timeout(11_000),
      });
    if (!res.ok) return json({ error: "MODEL_UNAVAILABLE" }, 503);

    const out = await res.json();
    // deno-lint-ignore no-explicit-any
    const parts = out?.output?.choices?.[0]?.message?.content as any[] | undefined;
    const text = (parts ?? []).map((p) => p?.text ?? "").join("").trim();
    if (!text) return json({ error: "NO_SPEECH" }, 200);

    // ⚠️ Two seconds of digital silence came back as 「嗯。」. The model fills rather than
    // returns nothing, and with no confidence to gate on, a transcript of pure filler is the
    // only thing left that means "there was nothing there". The board's line is that she never
    // guesses at what was said — sending 「嗯。」 down the turn path is a guess, and it is the
    // kind that logs a meal or asks a question the user did not ask.
    if (isFiller(text)) {
      return json({ error: "NO_SPEECH" }, 200);
    }

    // ⚠️ This model returns no confidence and no duration, so neither is invented here. F4's
    // 「confidence < 0.4 → NO_SPEECH」 cannot be enforced against this provider: an empty
    // transcript is the only silence signal it gives. Writing 1.0 into the field would read as
    // "certain" on every clip, which is worse than saying nothing — S4's absence law applies to
    // our own metadata too. Both stay null until a provider that reports them is chosen.
    return json({ text, durationMs: null, confidence: null, latencyMs: Date.now() - started });
  } finally {
    // the buffer never outlives the request
    buffer = null;
  }
});

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
