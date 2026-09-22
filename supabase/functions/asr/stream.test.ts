import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { stub } from "https://deno.land/std@0.224.0/testing/mock.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { EventEmitter } from "node:events";
import NodeWebSocket from "npm:ws@8.18.3";
import { ASR_QUIET_MS, ASR_STALL_MS, handleAsr } from "./index.ts";

type Event = Record<string, unknown>;

class Provider extends EventEmitter {
  readyState: number = NodeWebSocket.OPEN;
  sent: Event[] = [];
  send(raw: string) { this.sent.push(JSON.parse(raw)); }
  close() { this.readyState = NodeWebSocket.CLOSED; }
  event(type: string, fields: Event = {}) {
    this.emit("message", JSON.stringify({ type, ...fields }));
  }
}

// Exercise the actual request handler, stream callbacks, clocks and accounting;
// only socket I/O and authenticated database adapters are controlled here.
async function stream(audioBytes = 32_000, readyBeforeFinish = true) {
  const clock = new FakeTime();
  const provider = new Provider();
  const events: Event[] = [];
  const usage: unknown[] = [];
  const client = {
    readyState: WebSocket.OPEN as number,
    onmessage: null as ((event: { data: string | ArrayBuffer }) => void) | null,
    onclose: null as (() => void) | null,
    onerror: null as (() => void) | null,
    send(raw: string) { events.push(JSON.parse(raw)); },
    close() { this.readyState = WebSocket.CLOSED; this.onclose?.(); },
  };
  const upgrade = stub(Deno, "upgradeWebSocket", () => ({
    socket: client as unknown as WebSocket,
    response: new Response(),
  }));
  const priorKey = Deno.env.get("DASHSCOPE_API_KEY");
  Deno.env.set("DASHSCOPE_API_KEY", "test-only");
  const dispose = async () => {
    client.close();
    await clock.runMicrotasks();
    upgrade.restore();
    clock.restore();
    if (priorKey === undefined) Deno.env.delete("DASHSCOPE_API_KEY");
    else Deno.env.set("DASHSCOPE_API_KEY", priorKey);
  };
  try {
    await handleAsr(new Request("http://localhost/asr", {
      headers: { Upgrade: "websocket", "Idempotency-Key": "5d267dcf-249a-47fa-9274-a7cc7b638c23" },
    }), {
      authenticate: () => Promise.resolve("test-user"),
      client: () => ({} as never),
      entitlement: () => Promise.resolve({ allowed: true, introClaimed: false }),
      budget: () => Promise.resolve(null),
      quota: () => Promise.resolve({ allowed: true }),
      transcribe: () => Promise.reject(new Error("file provider must not run")),
      connectRealtime: () => provider as unknown as NodeWebSocket,
      recordUsage: (_db, value) => { usage.push(value); return Promise.resolve(); },
    });
    provider.emit("open");
    if (readyBeforeFinish) provider.event("session.updated");
    client.onmessage?.({ data: new Uint8Array(audioBytes).buffer });
    client.onmessage?.({ data: JSON.stringify({ type: "finish" }) });
    return { clock, provider, events, usage, client, dispose };
  } catch (error) {
    await dispose();
    throw error;
  }
}

const partial = "conversation.item.input_audio_transcription.text";
const completed = "conversation.item.input_audio_transcription.completed";

Deno.test("ASR keeps the stream alive when the first word arrives after the quiet window", async () => {
  const s = await stream();
  try {
    await s.clock.tickAsync(5_900);
    assertEquals(s.client.readyState, WebSocket.OPEN);
    s.provider.event(partial, { text: "今天" });
    await s.clock.tickAsync(300);
    s.provider.event(completed, { transcript: "今天走了五公里。" });
    s.provider.event("session.finished");
    await s.clock.runMicrotasks();
    assertEquals(s.events.at(-1), { type: "done", text: "今天走了五公里。" });
    assertEquals(s.usage.length, 1);
  } finally { await s.dispose(); }
});

Deno.test("ASR keeps an unfinished sentence through a long provider pause", async () => {
  const s = await stream();
  try {
    s.provider.event(partial, { text: "My heart rate was one hundred and" });
    await s.clock.tickAsync(5_000);
    assertEquals(s.client.readyState, WebSocket.OPEN);
    s.provider.event(completed, { transcript: "My heart rate was one hundred and twenty." });
    s.provider.event("session.finished");
    await s.clock.runMicrotasks();
    assertEquals(s.events.at(-1), { type: "done", text: "My heart rate was one hundred and twenty." });
  } finally { await s.dispose(); }
});

Deno.test("ASR cancels sentence fallback when the next sentence is still being decoded", async () => {
  const s = await stream();
  try {
    s.provider.event(completed, { transcript: "今天跑步。" });
    await s.clock.tickAsync(500);
    s.provider.event(partial, { text: "然后" });
    await s.clock.tickAsync(5_000);
    assertEquals(s.client.readyState, WebSocket.OPEN);
    s.provider.event(completed, { transcript: "然后吃了早餐。" });
    s.provider.event("session.finished");
    await s.clock.runMicrotasks();
    assertEquals(s.events.at(-1), { type: "done", text: "今天跑步。然后吃了早餐。" });
  } finally { await s.dispose(); }
});

Deno.test("ASR returns a provider-finished transcript immediately and ignores late events", async () => {
  const s = await stream();
  try {
    s.provider.event(completed, { transcript: "完整结果。" });
    s.provider.event("session.finished");
    await s.clock.runMicrotasks();
    assertEquals(s.events.at(-1), { type: "done", text: "完整结果。" });
    assertEquals(s.client.readyState, WebSocket.CLOSED);
    const count = s.events.length;
    s.provider.event(partial, { text: "late" });
    s.provider.event("error", { error: { message: "late error" } });
    await s.clock.tickAsync(ASR_STALL_MS + 1_000);
    assertEquals(s.events.length, count);
    assertEquals(s.usage.length, 1);
  } finally { await s.dispose(); }
});

Deno.test("ASR still settles completed sentences if the provider omits session.finished", async () => {
  const s = await stream();
  try {
    s.provider.event(completed, { transcript: "完整结果。" });
    await s.clock.tickAsync(ASR_QUIET_MS);
    assertEquals(s.events.at(-1), { type: "done", text: "完整结果。" });
    assertEquals(s.usage.length, 1);
  } finally { await s.dispose(); }
});

Deno.test("ASR bounds a truly stalled provider and never returns a partial transcript", async () => {
  const s = await stream();
  try {
    s.provider.event(partial, { text: "one hundred and" });
    await s.clock.tickAsync(ASR_STALL_MS - 1);
    assertEquals(s.client.readyState, WebSocket.OPEN);
    await s.clock.tickAsync(1);
    assertEquals(s.events.at(-1), { type: "error", error: "MODEL_UNAVAILABLE", reason: "STREAM_STALL" });
    assertEquals(s.usage.length, 1);
  } finally { await s.dispose(); }
});

Deno.test("ASR flushes queued audio before committing and ignores duplicate finish", async () => {
  const s = await stream(32_000, false);
  try {
    assertEquals(s.provider.sent.map(e => e.type), ["session.update"]);
    s.provider.event("session.updated");
    s.client.onmessage?.({ data: JSON.stringify({ type: "finish" }) });
    assertEquals(s.provider.sent.map(e => e.type), [
      "session.update", "input_audio_buffer.append",
      "input_audio_buffer.commit", "session.finish",
    ]);
    s.provider.event(completed, { transcript: "完整结果。" });
    s.provider.event("session.finished");
    await s.clock.runMicrotasks();
    assertEquals(s.usage, [{ promptTokens: 0, cachedTokens: 0, completionTokens: 0, audioSeconds: 1 }]);
  } finally { await s.dispose(); }
});

Deno.test("ASR does not submit or charge an empty recording", async () => {
  const s = await stream(0);
  try {
    assertEquals(s.provider.sent.map(e => e.type), [
      "session.update", "input_audio_buffer.commit", "session.finish",
    ]);
    s.provider.event("session.finished");
    await s.clock.runMicrotasks();
    assertEquals(s.events.at(-1), { type: "done", error: "NO_SPEECH" });
    assertEquals(s.usage, []);
  } finally { await s.dispose(); }
});
