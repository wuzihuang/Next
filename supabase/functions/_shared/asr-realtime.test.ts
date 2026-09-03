import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { audioAppend, finishEvents, parseProviderEvent, sessionUpdate } from "./asr-realtime.ts";

Deno.test("builds a manual 16 kHz PCM session", () => {
  const event = JSON.parse(sessionUpdate("zh"));
  assertEquals(event.type, "session.update");
  assertEquals(event.session.input_audio_format, "pcm");
  assertEquals(event.session.sample_rate, 16_000);
  assertEquals(event.session.turn_detection, null);
});

Deno.test("encodes PCM bytes and emits commit before finish", () => {
  const append = JSON.parse(audioAppend(new Uint8Array([0, 1, 2, 255])));
  assertEquals(append.type, "input_audio_buffer.append");
  assertEquals(append.audio, "AAEC/w==");

  const events = finishEvents().map((raw) => JSON.parse(raw).type);
  assertEquals(events, ["input_audio_buffer.commit", "session.finish"]);
});

Deno.test("parses partial, completed and provider errors", () => {
  assertEquals(
    parseProviderEvent(JSON.stringify({
      type: "conversation.item.input_audio_transcription.text",
      text: "今天",
      stash: "走路",
    })),
    { kind: "partial", text: "今天走路" },
  );
  assertEquals(
    parseProviderEvent(JSON.stringify({
      type: "conversation.item.input_audio_transcription.completed",
      transcript: "今天走路。",
    })),
    { kind: "completed", text: "今天走路。" },
  );
  const error = parseProviderEvent(JSON.stringify({
    type: "error",
    error: { message: "bad audio" },
  }));
  assertEquals(error.kind, "error");
  if (error.kind === "error") assertStringIncludes(error.message, "bad audio");
});
