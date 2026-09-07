import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleMemorySettle, type MemorySettleDependencies } from "./index.ts";

function request(body: Record<string, unknown> = {}): Request {
  return new Request("http://localhost/memory-settle", {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
  });
}

function harness(opts: { due?: string[]; transcript?: unknown[]; consent?: string; generated?: number } = {}) {
  const writes: Record<string, unknown>[] = [];
  const closed: string[] = [];
  const usages: unknown[] = [];
  let generated = 0;
  const db = {
    from(table: string) {
      const q = {
        select() { return q; }, eq() { return q; }, order() { return q; }, limit() { return q; },
        maybeSingle() {
          if (table === "profiles") return Promise.resolve({ data: { locale: "en-US", timezone: "UTC", deletion_requested_at: null }, error: null });
          if (table === "consents") return Promise.resolve({ data: { choice: opts.consent ?? "granted" }, error: null });
          if (table === "user_memory") return Promise.resolve({ data: { summary: "Runner.", facts: [{ text: "Left knee sore since spring", at: "2026-08-01", source: "chat" }] }, error: null });
          return Promise.resolve({ data: null, error: null });
        },
      };
      return q;
    },
    rpc(name: string, args?: Record<string, unknown>) {
      if (name === "close_ai_session") { closed.push(String(args!.p_session)); return Promise.resolve({ data: null, error: null }); }
      if (name === "ai_sessions_due") return Promise.resolve({ data: opts.due ?? [], error: null });
      if (name === "ai_session_transcript") return Promise.resolve({ data: opts.transcript ?? [], error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  const trusted = {
    rpc(name: string, args?: Record<string, unknown>) {
      if (name === "write_user_memory_trusted") { writes.push(args!); return Promise.resolve({ data: null, error: null }); }
      return Promise.resolve({ data: null, error: null });
    },
  };
  const deps: MemorySettleDependencies = {
    authenticate: () => Promise.resolve("u"),
    client: () => db as never,
    trusted: () => trusted as never,
    generateObject: (() => {
      generated++;
      return Promise.resolve({
        object: { summary: "Runner with a sore left knee; avoids dairy.", facts: [
          { text: "Left knee sore since spring", at: "2026-08-01", source: "chat" },
          { text: "Avoids dairy", at: "2026-09-06", source: "chat" },
        ] },
        usage: { promptTokens: 40, completionTokens: 30 },
      });
    }) as unknown as MemorySettleDependencies["generateObject"],
    spend: () => Promise.resolve(true),
    recordUsage: (_db, usage) => { usages.push(usage); return Promise.resolve(); },
  };
  return { deps, writes, closed, usages, generated: () => generated };
}

const session = "33333333-3333-4333-8333-333333333333";
const transcript = [
  { at: "2026-09-06", source: "chat", user: "I stopped eating dairy last week", assistant: "Noted; it can help with the bloating you mentioned." },
];

Deno.test("a due session is summarized once, written through the trusted writer, and accounted", async () => {
  const h = harness({ due: [session], transcript });
  const out = await (await handleMemorySettle(request(), h.deps)).json();
  assertEquals(out.settled, [session]);
  assertEquals(h.generated(), 1);
  assertEquals(h.writes.length, 1);
  assertEquals(h.writes[0].p_session, session);
  assert(String(h.writes[0].p_summary).includes("dairy"));
  assertEquals(h.usages.length, 1);
});

Deno.test("closing a session from the phone marks it closed before the sweep", async () => {
  const h = harness({ due: [] });
  const out = await (await handleMemorySettle(request({ close_session: session }), h.deps)).json();
  assertEquals(h.closed, [session]);
  assertEquals(out.settled, []);
  assertEquals(h.generated(), 0);
});

Deno.test("an empty transcript is skipped without a model call", async () => {
  const h = harness({ due: [session], transcript: [] });
  const out = await (await handleMemorySettle(request(), h.deps)).json();
  assertEquals(out.skipped, [{ session, reason: "EMPTY" }]);
  assertEquals(h.generated(), 0);
});

Deno.test("withdrawn consent refuses the summary outright", async () => {
  const h = harness({ due: [session], transcript, consent: "withdrawn" });
  const response = await handleMemorySettle(request(), h.deps);
  assertEquals(response.status, 403);
  assertEquals(h.generated(), 0);
});
