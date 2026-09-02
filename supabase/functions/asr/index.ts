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
    // ⚠️ This used to POST a multipart file to
    // `/compatible-mode/v1/audio/transcriptions` with `paraformer-realtime-v2`. That path does
    // not exist on DashScope — it answers 404 — so every request here returned
    // MODEL_UNAVAILABLE and the voice input could never have worked. A typechecker cannot see a
    // wrong URL, and the failure looked exactly like the model being down.
    //
    // What does work, tried with real speech: qwen3-asr-flash on the multimodal endpoint, with
    // the clip inline as a data URI. It returned 「今天吃了半碗面加一个鸡蛋。」 for a clip that
    // said exactly that.
    const bytes = new Uint8Array(buffer!);
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
    if (/^[嗯啊呃哦唔呀哈\s。，、．.,!?！？~-]+$/u.test(text)) {
      return json({ error: "NO_SPEECH" }, 200);
    }

    // ⚠️ This model returns no confidence and no duration, so neither is invented here. F4's
    // 「confidence < 0.4 → NO_SPEECH」 cannot be enforced against this provider: an empty
    // transcript is the only silence signal it gives. Writing 1.0 into the field would read as
    // "certain" on every clip, which is worse than saying nothing — S4's absence law applies to
    // our own metadata too. Both stay null until a provider that reports them is chosen.
    return json({ text, durationMs: null, confidence: null });
  } finally {
    // the buffer never outlives the request
    buffer = null;
  }
});
