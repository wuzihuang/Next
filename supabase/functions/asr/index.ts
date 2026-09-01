// F4 §02 · POST /v1/asr — the audio buffer is transcribed and immediately zeroed.
// Nothing is written to Storage and nothing is written to a table.
// ⚠️ confidence < 0.4 returns NO_SPEECH and the client degrades in place to
// DIDN'T CATCH THAT — it never guesses at what was said.

import { currentUserId, cors, json } from "../_shared/db.ts";

const MAX_BYTES = 2 * 1024 * 1024;   // ≤ 2 MB, ≤ 60 s

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const userId = await currentUserId(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const form = await req.formData();
  const file = form.get("audio");
  if (!(file instanceof File)) return json({ error: "E_SCHEMA" }, 422);
  if (file.size > MAX_BYTES) return json({ error: "E_SCHEMA", reason: "TOO_LARGE" }, 413);

  let buffer: ArrayBuffer | null = await file.arrayBuffer();
  try {
    const upstream = new FormData();
    upstream.append("file", new Blob([buffer!], { type: file.type }), "clip.m4a");
    upstream.append("model", "paraformer-realtime-v2");

    const res = await fetch("https://dashscope.aliyuncs.com/compatible-mode/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${Deno.env.get("DASHSCOPE_API_KEY")}` },
      body: upstream,
      signal: AbortSignal.timeout(11_000),
    });
    if (!res.ok) return json({ error: "MODEL_UNAVAILABLE" }, 503);

    const out = await res.json();
    const confidence = out.confidence ?? 1;
    if (!out.text || confidence < 0.4) return json({ error: "NO_SPEECH" }, 200);

    return json({
      text: out.text,
      durationMs: Math.round((out.duration ?? 0) * 1000),
      confidence,
    });
  } finally {
    // the buffer never outlives the request
    buffer = null;
  }
});
