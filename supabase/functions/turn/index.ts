// F4 §02 · POST /v1/turn · SSE.
// Event order is fixed: state(THINKING) → tool(0..n) → screen.render(1) → done.
// Every error carries a fallback_frame, and that frame is itself a legal envelope —
// the panel is never allowed to go empty.

import { generateText } from "npm:ai@4.3.16";
import { model, MODEL_VERSION } from "../_shared/model.ts";
import { systemPrompt } from "../_shared/prompt.ts";
import { buildTools } from "../_shared/tools.ts";
import { NumberLedger, auditFrame } from "../_shared/ledger.ts";
import { Envelope, MEDICAL, medicalStop, normalizeLocale, batteryFallback, tagSafe } from "../_shared/contract.ts";
import { buildChartTools } from "../_shared/charts.ts";
import { userClient, currentUserId, cors, json, userDayKey, userTimezone } from "../_shared/db.ts";

// 60 turns an hour and 150 a day. Free forever does not mean unlimited: the cost is real,
// and the ceiling is a rate limit rather than a paywall.
const HOURLY = 60, DAILY = 150;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const userId = await currentUserId(req);
  if (!userId) return json({ error: "UNAUTHENTICATED" }, 401);

  const db = userClient(req);

  // 补屏 rule 06 · 「撤回后 /v1/turn 返 403 consent_withdrawn」. The newest answer decides. An
  // account with no answer has not consented either. ⚠️ 42P01 is "the table does not exist":
  // until migration 20260902030000 is applied, consent is recorded on the phone and not
  // enforced here — enforcing against a missing table would refuse every turn.
  const { data: consent, error: consentErr } = await db.from("consents")
    .select("choice").eq("user_id", userId)
    .order("decided_at", { ascending: false }).limit(1).maybeSingle();
  if (!consentErr && consent?.choice !== "granted") {
    return json({ error: "consent_withdrawn" }, 403);
  }

  const body = await req.json().catch(() => ({}));
  const text: string = body.text ?? "";
  // ⚠️ The user's calendar, not the server's. See userDayKey.
  const tz = await userTimezone(db, userId);
  const dayKey: string = body.dayKey ?? userDayKey(tz);
  // 11 · 07 · language is an app-side preference: the app sends it with the turn, and the
  // profile row stands in for a client that does not. Every word on screen follows it.
  const { data: prof } = await db.from("profiles").select("locale").eq("user_id", userId).maybeSingle();
  const locale = normalizeLocale(body.locale ?? prof?.locale);
  const turnId: string = req.headers.get("Idempotency-Key") ?? crypto.randomUUID();

  // Replaying the same Idempotency-Key returns the same frames, so a dropped connection
  // never costs a second model call.
  const { data: existing } = await db.from("ai_turns")
    .select("id, frame_id").eq("id", turnId).maybeSingle();
  if (existing?.frame_id) {
    const { data: frame } = await db.from("screen_frames")
      .select("widget_tree").eq("id", existing.frame_id).maybeSingle();
    if (frame) return json({ envelope: frame.widget_tree, replay: true });
  }

  /// ⚠️ Every failure path sent batteryFallback(null), so a degraded frame told a user with
  /// a live battery "还没有可用的夜间数据". That sentence is for an account that has never
  /// recorded a night, and printing it after a model timeout is a lie about their data
  /// rather than an apology for ours. The fallback carries the real level.
  let cachedLevel: number | null | undefined;
  const fallback = async () => {
    if (cachedLevel === undefined) {
      const { data } = await db.from("daily_results")
        .select("id, reserve_daily(current_value)")
        .eq("user_id", userId).eq("user_day", dayKey).maybeSingle();
      // deno-lint-ignore no-explicit-any
      const r = (data as any)?.reserve_daily;
      cachedLevel = (Array.isArray(r) ? r[0]?.current_value : r?.current_value) ?? null;
    }
    return batteryFallback(cachedLevel ?? null, locale);
  };
  const { count: recent } = await db.from("ai_turns")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", new Date(Date.now() - 3600_000).toISOString());
  if ((recent ?? 0) >= HOURLY) {
    const fb = await fallback();
    return sse((send) => {
      send("error", { code: "RATE_LIMITED", fallback_frame: fb });
    });
  }

  const started = Date.now();
  const ledger = new NumberLedger();
  ledger.seedConstants();

  const tools = buildTools(db, userId, ledger, { dayKey, tz });
  const trace: unknown[] = [];

  return sse(async (send) => {
    send("state", { value: "THINKING" });

    // S7 · the medical stop happens before any tool call, not after.
    if (MEDICAL.test(text)) {
      const stop = medicalStop(locale);
      await persist(db, userId, turnId, text, stop, trace, Date.now() - started);
      send("screen.render", { envelope: stop });
      send("done", {});
      return;
    }

    // 07 · 02 · the surface is a tool, not a reply. S1 says the only way she speaks is by
    // calling screen.render, so every widget on board 07 is one: screen.render.<type>,
    // one flat schema each, the series filled by the server from the source she names.
    // The model cannot answer in prose, and there is no free text to parse out of.
    // S1 · one render per turn. ⚠️ Told so in the prompt, the model still rendered eight
    // times in a row on one question (37 s, the last frame winning). A successful render
    // now ends the turn: the callback pulls the cord, generateText stops, and the frame it
    // produced is the answer. A NO_DATA result is not a render and the model goes on.
    let envelope: Envelope | null = null;
    const stop = new AbortController();
    const renderTools = buildChartTools({ db, userId, dayKey, tz }, ledger, (env) => {
      envelope = env;
      stop.abort();
    }, locale);

    // Every tool call is traced and announced as it runs, not read back from the steps
    // afterwards — the steps are not there when the turn ends by abort. A number the model
    // passed to a read tool, and got data back for, is not invented; the render tools'
    // arguments are the frame itself and are audited there.
    // S2 · READ FIRST, mechanically. ⚠️ With the render ending the turn, a model that opened
    // with screen.render.recomp never read anything, wrote 「——」 for a sentence, and the turn
    // was over in 4 s. A chart that names a data source is about data the sentence must
    // quote, so it needs one read behind it; text, metric and food carry their own words.
    let reads = 0;
    const traced = Object.fromEntries(Object.entries({ ...tools, ...renderTools }).map(([name, t]) => [name, {
      ...t,
      // deno-lint-ignore no-explicit-any
      execute: async (args: any, opts: any) => {
        trace.push({ tool: name, args });
        send("tool", { name });
        if (!name.startsWith("screen.render")) {
          reads += 1;
          ledger.harvest(args, `${name}.args`);
        } else if (args?.source && reads === 0) {
          return {
            rendered: false, error: "READ_FIRST",
            say: locale.startsWith("en")
              ? `Read first: call series.get with source "${args.source}" (or another read tool), then render with the numbers it returned.`
              : `先读再画：先用 series.get 读 "${args.source}"（或别的读工具），再拿返回的数字渲染。`,
          };
        }
        return t.execute!(args, opts);
      },
    }]));

    const attempt = () => generateText({
        model: model(),
        system: systemPrompt(locale),
        // S9 · everything between the tags is data, not instruction.
        prompt: `<user_text>\n${tagSafe(text)}\n</user_text>\n\ndayKey=${dayKey}`,
        tools: traced,
        maxSteps: 8,
        toolChoice: "auto",
        // qwen3 on DashScope thinks before every tool call unless told not to; the turn
        // took 27–38 s that way. TURN_THINKING=on restores it.
        providerOptions: { dashscope: { enable_thinking: Deno.env.get("TURN_THINKING") === "on" } },
        abortSignal: AbortSignal.any([
          AbortSignal.timeout(Math.max(5_000, 50_000 - (Date.now() - started))),
          stop.signal,
        ]),
      });
    // A throw with a frame in hand is the render that ended the turn, not a failure.
    const run = async () => { try { await attempt(); } catch (e) { if (envelope) return; throw e; } };

    try {
      try {
        await run();
      } catch (e) {
        // ⚠️ Seen on production: the same question answered in 8 s once and failed in 6 s
        // the next time, no tool called, MODEL_UNAVAILABLE. A fast failure on the model hop
        // gets one more attempt while the 55 s budget allows; the 50 s timeout does not.
        const fast = Date.now() - started < 20_000 && !(e instanceof Error && e.name === "AbortError");
        if (!fast) throw e;
        console.error("turn attempt 1 failed, retrying:", e instanceof Error ? `${e.name}: ${e.message}` : e);
        envelope = null;
        await run();
      }
      // The ledger closes after every read has returned — the render tool does not close
      // it, which is what let a later tool's numbers arrive unaccounted for.
      ledger.seal();
    } catch (e) {
      console.error("turn failed:", e instanceof Error ? (e.stack ?? e.message) : e);
      send("error", { code: "MODEL_UNAVAILABLE", fallback_frame: await fallback() });
      send("done", {});
      return;
    }

    const parsed = Envelope.safeParse(envelope);
    if (!parsed.success) {
      console.error("E_SCHEMA", JSON.stringify(parsed.error.issues), JSON.stringify(envelope));
      const fb = await fallback();
      await persist(db, userId, turnId, text, fb, trace, Date.now() - started);
      send("error", { code: "E_SCHEMA", fallback_frame: fb });
      send("done", {});
      return;
    }

    // F4 §05 · the banned list is scanned after rendering. A hit throws away the whole
    // frame — no word-level surgery, because the sentence that contained it was wrong.
    const banned = await loadBanned(db);
    const blob = [parsed.data.title, parsed.data.sentence, parsed.data.footer, parsed.data.action]
      .filter(Boolean).join(" ");
    const hit = banned.find((re) => re.test(blob));
    if (hit) {
      const fb = await fallback();
      await persist(db, userId, turnId, text, fb, trace, Date.now() - started);
      // F5 C7 · a banned phrase is E_CLAIM, not a schema error: the frame was well-formed and
      // said something the product is not allowed to say.
      send("error", { code: "E_CLAIM", reason: "BANNED_PHRASE", fallback_frame: fb });
      send("done", {});
      return;
    }

    // F4 §06 · one untraceable number rejects the frame.
    const audit = auditFrame(parsed.data as unknown as Record<string, unknown>, ledger);
    if (!audit.ok) {
      const fb = await fallback();
      await persist(db, userId, turnId, text, fb, trace, Date.now() - started);
      // The number alone is not diagnosable — 7 could be a window, a weekday or a real
      // measurement the tools failed to return. The frame goes in the log with it.
      console.error("UNTRACEABLE_NUMBER", audit.value, JSON.stringify(parsed.data));
      send("error", {
        code: "E_SCHEMA", reason: "UNTRACEABLE_NUMBER", value: audit.value, fallback_frame: fb,
      });
      send("done", {});
      return;
    }

    await persist(db, userId, turnId, text, parsed.data, trace, Date.now() - started);
    send("screen.render", { envelope: parsed.data });
    send("done", {});
  });
});

let bannedCache: { at: number; list: RegExp[] } | null = null;
async function loadBanned(db: ReturnType<typeof userClient>): Promise<RegExp[]> {
  // read once, cached for five minutes — adding a word must not require a release
  if (bannedCache && Date.now() - bannedCache.at < 300_000) return bannedCache.list;
  const { data } = await db.from("banned_phrases").select("pattern");
  const list = (data ?? []).map((r) => {
    try { return new RegExp(r.pattern); } catch { return /$^/; }
  });
  bannedCache = { at: Date.now(), list };
  return list;
}

async function persist(
  db: ReturnType<typeof userClient>, userId: string, turnId: string,
  text: string, envelope: Envelope, trace: unknown[], latency: number,
) {
  const { data: frame } = await db.from("screen_frames").insert({
    user_id: userId,
    trigger: "turn",
    widget_tree: envelope,
    expires_at: new Date(Date.now() + envelope.ttl_min * 60_000).toISOString(),
    model_version: MODEL_VERSION,
    latency_ms: latency,
    tool_calls: trace,
  }).select("id").single();

  await db.from("ai_turns").upsert({
    id: turnId, user_id: userId, user_text: text, tool_trace: trace,
    frame_id: frame?.id ?? null, model_version: MODEL_VERSION,
    latency_ms: latency, outcome: "ok",
  });
}

function sse(run: (send: (event: string, data: unknown) => void) => void | Promise<void>): Response {
  const stream = new ReadableStream({
    async start(controller) {
      const enc = new TextEncoder();
      const send = (event: string, data: unknown) => {
        controller.enqueue(enc.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
      };
      try { await run(send); } finally { controller.close(); }
    },
  });
  return new Response(stream, {
    headers: { ...cors, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
  });
}
