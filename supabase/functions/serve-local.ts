// Serves the Edge Functions the way Supabase does — /functions/v1/<name> — so the simulator
// can exercise the real handlers before `supabase functions deploy` has run.
//
// Each function calls Deno.serve at module load, so Deno.serve is swapped for a collector
// before the imports and put back afterwards.

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
] as const) {
  try { await load(name, path); console.log("loaded", name); }
  catch (e) { console.error("FAILED", name, e instanceof Error ? e.message : e); }
}

// deno-lint-ignore no-explicit-any
(Deno as any).serve = realServe;

realServe({ port: 8000 }, (req) => {
  const name = new URL(req.url).pathname.replace(/^\/functions\/v1\//, "").split("/")[0];
  const h = handlers.get(name);
  console.log(req.method, name, h ? "→ ok" : "→ 404");
  if (!h) return new Response(JSON.stringify({ error: "NOT_FOUND", name }), { status: 404 });
  return h(req);
});
