import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type AsrDependencies,
  audioDurationSeconds,
  handleAsr,
} from "./index.ts";

const OPERATION = "5d267dcf-249a-47fa-9274-a7cc7b638c23";

function wav(seconds = 1, sampleRate = 16000, channels = 1): Uint8Array {
  const size = seconds * sampleRate * channels * 2;
  const bytes = new Uint8Array(44 + size);
  const view = new DataView(bytes.buffer);
  const tag = (at: number, value: string) =>
    bytes.set(new TextEncoder().encode(value), at);
  tag(0, "RIFF");
  view.setUint32(4, bytes.length - 8, true);
  tag(8, "WAVE");
  tag(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * channels * 2, true);
  view.setUint16(32, channels * 2, true);
  view.setUint16(34, 16, true);
  tag(36, "data");
  view.setUint32(40, size, true);
  return bytes;
}

function audioRequest(
  bytes = wav(),
  operation: string | null = OPERATION,
): Request {
  const form = new FormData();
  form.set(
    "audio",
    new File([bytes.slice().buffer], "clip.wav", { type: "audio/wav" }),
  );
  return new Request("http://localhost/asr", {
    method: "POST",
    body: form,
    headers: operation ? { "Idempotency-Key": operation } : {},
  });
}

function deps(overrides: Partial<AsrDependencies> = {}): AsrDependencies {
  return {
    authenticate: () => Promise.resolve("u"),
    client: () => ({} as never),
    budget: () => Promise.resolve(null),
    quota: () => Promise.resolve({ allowed: true as const }),
    entitlement: () => Promise.resolve({ allowed: true as const, introClaimed: false }),
    transcribe: () => Promise.resolve({ ok: true, text: "hello" }),
    recordUsage: () => Promise.resolve(),
    ...overrides,
  };
}

Deno.test("a missing Pro entitlement never sends audio to the model", async () => {
  let transcribed = false;
  const response = await handleAsr(
    audioRequest(),
    deps({
      entitlement: () => Promise.resolve({
        allowed: false as const,
        introClaimed: true,
        reason: "expired",
      }),
      transcribe: () => {
        transcribed = true;
        return Promise.resolve({ ok: true, text: "hello" });
      },
    }),
  );
  assertEquals(response.status, 402);
  const body = await response.json();
  assertEquals(body.error, "SUBSCRIPTION_REQUIRED");
  assertEquals(body.intro_claimed, true);
  assertEquals(transcribed, false);
});

Deno.test("an exhausted daily allowance never sends audio to the model", async () => {
  let transcribed = false;
  const response = await handleAsr(
    audioRequest(),
    deps({
      quota: () => Promise.resolve({ allowed: false, reason: "count" }),
      transcribe: () => {
        transcribed = true;
        return Promise.resolve({ ok: true, text: "hello" });
      },
    }),
  );
  assertEquals(response.status, 429);
  assertEquals(transcribed, false);
});

Deno.test("a allowed clip records usage and returns the transcript without inventing confidence", async () => {
  const recorded: unknown[] = [];
  const response = await handleAsr(
    audioRequest(),
    deps({
      transcribe: () =>
        Promise.resolve({
          ok: true,
          text: "hello",
          usage: { promptTokens: 40, cachedTokens: 0, completionTokens: 8 },
        }),
      recordUsage: (_db, usage) => {
        recorded.push(usage);
        return Promise.resolve();
      },
    }),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.text, "hello");
  assertEquals(body.confidence, null);
  assertEquals(recorded, [{
    promptTokens: 40,
    cachedTokens: 0,
    completionTokens: 8,
    audioSeconds: 1,
  }]);
});

Deno.test("ASR admission receives the same operation used by downstream turns", async () => {
  const operations: (string | undefined)[] = [];
  for (let attempt = 0; attempt < 2; attempt++) {
    const response = await handleAsr(
      audioRequest(),
      deps({
        quota: (_db, operation) => {
          operations.push(operation);
          return Promise.resolve({ allowed: true });
        },
      }),
    );
    assertEquals(response.status, 200);
  }
  assertEquals(operations, [OPERATION, OPERATION]);
});

Deno.test("invalid operation and malformed audio never consume quota or call a provider", async () => {
  let called = 0;
  const hooks = deps({
    quota: () => {
      called++;
      return Promise.resolve({ allowed: true });
    },
    transcribe: () => {
      called++;
      return Promise.resolve({ ok: true, text: "unexpected" });
    },
  });
  for (
    const request of [
      audioRequest(wav(), null),
      audioRequest(wav(), "not-a-uuid"),
      audioRequest(new Uint8Array([1, 2])),
    ]
  ) {
    assertEquals((await handleAsr(request, hooks)).status, 422);
  }
  assertEquals(called, 0);
});

Deno.test("WAV accounting uses actual format and PCM accounting uses 16k mono", () => {
  assertEquals(audioDurationSeconds(wav(2, 8000, 2), "audio/wav"), 2);
  assertEquals(audioDurationSeconds(wav(1, 44100, 1), "audio/wav"), 1);
  assertEquals(audioDurationSeconds(new Uint8Array(48000), "audio/pcm"), 1.5);
  assertEquals(audioDurationSeconds(wav().slice(0, 50), "audio/wav"), null);
  assertEquals(audioDurationSeconds(new Uint8Array(3), "audio/pcm"), null);
});

Deno.test("silence and failed provider attempts still record the submitted audio cost", async () => {
  for (
    const result of [{ ok: true as const, text: "嗯" }, {
      ok: false as const,
      error: "MODEL_UNAVAILABLE",
      status: 503,
    }]
  ) {
    const usage: unknown[] = [];
    const response = await handleAsr(
      audioRequest(),
      deps({
        transcribe: () => Promise.resolve(result),
        recordUsage: (_db, value) => {
          usage.push(value);
          return Promise.resolve();
        },
      }),
    );
    assertEquals(response.status, result.ok ? 200 : 503);
    assertEquals(usage, [{
      promptTokens: 0,
      cachedTokens: 0,
      completionTokens: 0,
      audioSeconds: 1,
    }]);
  }
});

Deno.test("failed accounting is explicit and never returns a successful transcript", async () => {
  const response = await handleAsr(
    audioRequest(),
    deps({ recordUsage: () => Promise.reject(Error("offline")) }),
  );
  assertEquals(response.status, 503);
  assertEquals((await response.json()).error, "AI_USAGE_UNAVAILABLE");
});

Deno.test("audio duration and spend limits block the provider before submission", async () => {
  let submitted = false;
  const hooks = deps({
    quota: () => Promise.resolve({ allowed: false, reason: "spend" }),
    transcribe: () => {
      submitted = true;
      return Promise.resolve({ ok: true, text: "no" });
    },
  });
  assertEquals(
    (await handleAsr(audioRequest(wav(61, 8000)), hooks)).status,
    413,
  );
  assertEquals((await handleAsr(audioRequest(), hooks)).status, 429);
  assertEquals(submitted, false);
});
