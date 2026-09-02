// Serves the Edge Functions the way Supabase does — /functions/v1/<name> — so the simulator
// can exercise the real handlers before `supabase functions deploy` has run. Criterion 5
// allows the AI to be proven 本地 / 模拟器 / 真机, and the thing worth proving is the
// deployed artefact: the real prompt, the real eight tools, the real SSE stream.
//
// Each function calls Deno.serve at module load, so Deno.serve is swapped for a collector
// before the imports and put back afterwards. The function sources are untouched.
//
//   cd supabase/functions
//   SUPABASE_URL=… SUPABASE_ANON_KEY=… DASHSCOPE_API_KEY=… PORT=8000 \
//     deno run --allow-net --allow-env --allow-read --config deno.json serve-local.ts
//
// ⚠️ The keys come from the environment of *this* process. A host started from a shell
// without them serves every turn as MODEL_UNAVAILABLE with a perfectly healthy-looking
// stream, so the startup line below says which keys it can see.

type Handler = (req: Request) => Response | Promise<Response>;
const handlers = new Map<string, Handler>();
const realServe = Deno.serve.bind(Deno);

async function load(name: string, path: string) {
  // deno-lint-ignore no-explicit-any
  (Deno as any).serve = (a: unknown, b?: unknown) => {
    const h = (typeof a === "function" ? a : b) as Handler;
    handlers.set(name, h);
    return { finished: Promise.resolve(), shutdown: () => Promise.resolve(), ref() {}, unref() {} };
  };
  await import(path);
}

for (const [name, path] of [
  ["turn", "./turn/index.ts"],
  ["meal", "./meal/index.ts"],
  ["meal-commit", "./meal-commit/index.ts"],
  ["asr", "./asr/index.ts"],
  ["screen-current", "./screen-current/index.ts"],
  ["export", "./export/index.ts"],
] as const) {
  try { await load(name, path); console.log("loaded", name); }
  catch (e) { console.error("FAILED", name, e instanceof Error ? e.message : e); }
}

// deno-lint-ignore no-explicit-any
(Deno as any).serve = realServe;

const keys = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "DASHSCOPE_API_KEY", "AI_GATEWAY_API_KEY"]
  .map((k) => `${k}=${Deno.env.get(k) ? "set" : "MISSING"}`).join("  ");
console.log("env:", keys);

const port = Number(Deno.env.get("PORT") ?? "8000");
realServe({ port, hostname: "0.0.0.0" }, async (req) => {
  const name = new URL(req.url).pathname.replace(/^\/functions\/v1\//, "").split("/")[0];
  const h = handlers.get(name);
  console.log(req.method, name, h ? "→ ok" : "→ 404");
  if (!h) return new Response(JSON.stringify({ error: "NOT_FOUND", name }), { status: 404 });
  try { return await h(req); }
  catch (e) {
    console.error(name, "threw:", e instanceof Error ? (e.stack ?? e.message) : e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
