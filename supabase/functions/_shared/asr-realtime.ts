export const ASR_REALTIME_MODEL = "qwen3-asr-flash-realtime";

export function realtimeURL(): string {
  return `wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=${ASR_REALTIME_MODEL}`;
}

export function sessionUpdate(language: string): string {
  return JSON.stringify({
    event_id: crypto.randomUUID(),
    type: "session.update",
    session: {
      input_audio_format: "pcm",
      sample_rate: 16_000,
      input_audio_transcription: { language },
      turn_detection: null,
    },
  });
}

export function audioAppend(bytes: Uint8Array): string {
  return JSON.stringify({
    event_id: crypto.randomUUID(),
    type: "input_audio_buffer.append",
    audio: bytesToBase64(bytes),
  });
}

export function finishEvents(): [string, string] {
  return [
    JSON.stringify({ event_id: crypto.randomUUID(), type: "input_audio_buffer.commit" }),
    JSON.stringify({ event_id: crypto.randomUUID(), type: "session.finish" }),
  ];
}

export type ProviderEvent =
  | { kind: "ready" }
  | { kind: "partial"; text: string }
  | { kind: "completed"; text: string }
  | { kind: "finished" }
  | { kind: "error"; message: string }
  | { kind: "other" };

export function parseProviderEvent(raw: string): ProviderEvent {
  let event: Record<string, unknown>;
  try {
    event = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return { kind: "error", message: "INVALID_PROVIDER_EVENT" };
  }

  switch (event.type) {
    case "session.updated":
      return { kind: "ready" };
    case "conversation.item.input_audio_transcription.text":
      return { kind: "partial", text: `${event.text ?? ""}${event.stash ?? ""}`.trim() };
    case "conversation.item.input_audio_transcription.completed":
      return { kind: "completed", text: String(event.transcript ?? "").trim() };
    case "session.finished":
      return { kind: "finished" };
    case "error":
    case "conversation.item.input_audio_transcription.failed": {
      const error = event.error as Record<string, unknown> | undefined;
      return { kind: "error", message: String(error?.message ?? error?.code ?? "MODEL_UNAVAILABLE") };
    }
    default:
      return { kind: "other" };
  }
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}
