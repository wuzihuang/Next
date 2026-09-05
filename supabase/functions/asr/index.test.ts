import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleAsr, type AsrDependencies } from "./index.ts";

function audioRequest(): Request {
  const form = new FormData();
  form.set("audio", new File([new Uint8Array([1, 2, 3, 4])], "clip.wav", {
    type: "audio/wav",
  }));
  return new Request("http://localhost/asr", { method: "POST", body: form });
}

function deps(overrides: Partial<AsrDependencies> = {}): AsrDependencies {
  return {
    authenticate: () => Promise.resolve("u"),
    client: () => ({} as never),
    budget: () => Promise.resolve(null),
    quota: () => Promise.resolve({ allowed: true as const }),
    transcribe: () => Promise.resolve({ ok: true, text: "hello" }),
    recordUsage: () => Promise.resolve(),
    ...overrides,
  };
}

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
  }]);
});
