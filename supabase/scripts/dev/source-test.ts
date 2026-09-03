// Every source, straight against the hosted DB with the user's own JWT.
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { SOURCES, fetchAs } from "../../functions/_shared/sources.ts";
import { userDayKey } from "../../functions/_shared/db.ts";

const SCR = (Deno.env.get("NB_DEV_DIR") ?? new URL(".", import.meta.url).pathname).replace(/\/?$/, "/");
const keys = JSON.parse(await Deno.readTextFile(`${SCR}apikeys.json`));
const anon = keys.find((k: { name: string }) => k.name === "anon").api_key;
let sess = JSON.parse(await Deno.readTextFile(`${SCR}session.json`));
const URL_ = "https://gkgzwcxivnffsecshvfs.supabase.co";
if (Date.now() / 1000 > sess.expires_at - 300) {
  const r = await fetch(`${URL_}/auth/v1/token?grant_type=refresh_token`, { method: "POST", headers: { apikey: anon, "Content-Type": "application/json" }, body: JSON.stringify({ refresh_token: sess.refresh_token }) });
  const d = await r.json();
  if (d.access_token) { sess = d; await Deno.writeTextFile(`${SCR}session.json`, JSON.stringify(d)); } else console.log("refresh failed", d);
}
const db = createClient(URL_, anon, { global: { headers: { Authorization: `Bearer ${sess.access_token}` } }, auth: { persistSession: false } });
const { data: u } = await db.auth.getUser();
const tz = "Asia/Shanghai";
const dayKey = Deno.args[0] ?? userDayKey(tz);
console.log("user", u.user?.id, "dayKey", dayKey);
const ctx = { db, userId: u.user!.id, dayKey, tz };
for (const s of SOURCES) {
  const t0 = Date.now();
  try {
    const r = await fetchAs(s.id, s.kind, ctx);
    const ms = Date.now() - t0;
    if (!r) { console.log(`${s.id.padEnd(22)} ${ms}ms  NULL`); continue; }
    const d = r.data as Record<string, unknown>;
    const size = Object.entries(d).filter(([k]) => k !== "kind").map(([k, v]) => Array.isArray(v) ? `${k}[${v.length}]` : `${k}=${JSON.stringify(v)}`).join(" ");
    console.log(`${s.id.padEnd(22)} ${ms}ms  hero=${JSON.stringify(r.hero)} ${size}\n${"".padEnd(23)}agg=${JSON.stringify(r.agg)}`);
  } catch (e) { console.log(`${s.id.padEnd(22)} THREW`, e instanceof Error ? e.message : e); }
}
