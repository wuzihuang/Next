#!/usr/bin/env python3
"""ADR 0018 · run a whole matrix of turns against the deployed functions and report what
each one actually called.

usage: turn-matrix.py <matrix.json> [--out results.json] [--workers 3] [--only <id,id>]

Each case is {id, surface, text, want, image?, audio?, device?, result?}:
  surface  panel | chat | plan          want     the tool this case is aiming at
  audio    a wav path — POSTed to /asr first, and its transcript becomes the turn's text
  image    a jpg path — sent as a data URL
  device   the freshness.device block the phone would have uploaded
  result   what the phone answers a tool.request with (default ok:true OK)

Reads apikeys.json / session.json from NB_DEV_DIR, like turn-test.py.
"""
import base64, json, mimetypes, os, subprocess, sys, threading, time, uuid

SCR = os.environ.get("NB_DEV_DIR", os.path.dirname(os.path.abspath(__file__)))
URL = "https://gkgzwcxivnffsecshvfs.supabase.co"
BASE = f"{URL}/functions/v1"
keys = json.load(open(f"{SCR}/apikeys.json"))
ANON = [k["api_key"] for k in keys if k["name"] == "anon"][0]
sess = json.load(open(f"{SCR}/session.json"))
TOKEN = sess["access_token"]

# ⚠️ One AI session for the whole sweep, not one per case. Every session a turn opens is a
# candidate for the memory summarizer thirty minutes later, and a sweep's test queries have
# no business in the person's memory. One row is also one row to stamp afterwards:
#   update public.ai_sessions set summarized_at = now() where id = '<this>';
RUN_SESSION = os.environ.get("NB_RUN_SESSION", str(uuid.uuid4()))

# The server's request budget is 20 turn calls a minute; stay under it whatever the pool does.
_slots, _lock = [], threading.Lock()
def throttle(limit=16, window=60.0):
    while True:
        with _lock:
            now = time.time()
            _slots[:] = [t for t in _slots if now - t < window]
            if len(_slots) < limit:
                _slots.append(now)
                return
            wait = window - (now - _slots[0]) + 0.2
        time.sleep(max(0.5, wait))

def curl(args, timeout=180):
    p = subprocess.run(["curl", "-s", "--max-time", str(timeout)] + args, capture_output=True, text=True)
    return p.stdout

def transcribe(path):
    out = curl(["-X", "POST", f"{BASE}/asr", "-H", f"apikey: {ANON}", "-H", f"Authorization: Bearer {TOKEN}",
                "-H", f"Idempotency-Key: {uuid.uuid4()}", "-F", f"audio=@{path};type=audio/wav"])
    try:
        return json.loads(out)
    except Exception:
        return {"error": "BAD_RESPONSE", "raw": out[:200]}

def data_url(path):
    mime = mimetypes.guess_type(path)[0] or "image/jpeg"
    return f"data:{mime};base64," + base64.b64encode(open(path, "rb").read()).decode()

def stream(payload, key):
    p = subprocess.Popen(["curl", "-s", "-N", "--max-time", "180", "-X", "POST", f"{BASE}/turn",
                          "-H", f"apikey: {ANON}", "-H", f"Authorization: Bearer {TOKEN}",
                          "-H", "Content-Type: application/json", "-H", f"Idempotency-Key: {key}",
                          "-d", json.dumps(payload)], stdout=subprocess.PIPE, text=True, bufsize=1)
    ev = None
    out = {"tools": [], "thoughts": [], "frame": None, "request": None, "errors": [], "http": None}
    lines = []
    for line in p.stdout:
        lines.append(line)
        if line.startswith("event:"):
            ev = line[6:].strip()
        elif line.startswith("data:"):
            try:
                d = json.loads(line[5:].strip() or "{}")
            except Exception:
                continue
            if ev == "tool": out["tools"].append(d.get("name"))
            elif ev == "thought": out["thoughts"].append(d.get("text"))
            elif ev == "tool.request": out["request"] = d
            elif ev == "screen.render": out["frame"] = d.get("envelope")
            elif ev == "error": out["errors"].append(d)
    p.wait()
    if lines and not lines[0].startswith("event:"):
        out["http"] = "".join(lines)[:400]
    return out

def run_case(case):
    started = time.time()
    row = {"id": case["id"], "surface": case.get("surface", "panel"), "want": case.get("want"),
           "tools": [], "hops": 0, "frame": None, "title": None, "sentence": None,
           "errors": [], "transcript": None, "asr_error": None}
    text = case.get("text", "")
    if case.get("audio"):
        got = transcribe(case["audio"])
        row["transcript"] = got.get("text")
        if not got.get("text"):
            row["asr_error"] = got.get("error") or "NO_TEXT"
            row["seconds"] = round(time.time() - started, 1)
            return row
        text = got["text"]
    payload = {"text": text, "locale": case.get("locale", "zh-CN"), "surface": row["surface"],
               "session_id": case.get("session_id", RUN_SESSION)}
    if case.get("image"): payload["image"] = data_url(case["image"])
    if case.get("device"): payload["freshness"] = {"status": "ready", "device": case["device"]}
    # No conversation_id: a fresh uuid would name a conversation row that does not exist yet.
    key = str(uuid.uuid4())
    result = case.get("result") or {"ok": True, "code": "OK"}
    rate_waits = 0
    hop = 0
    while hop < 4:
        throttle()
        out = stream(payload, key)
        # The product's own hourly ceiling (60 turns) is not a test failure — wait it out.
        if not out["frame"] and any(e.get("code") == "RATE_LIMITED" for e in out["errors"]) and rate_waits < 25:
            rate_waits += 1
            time.sleep(70)
            continue
        hop += 1
        row["tools"] += [t for t in out["tools"] if t]
        row["errors"] += [e.get("code") + (":" + e["reason"] if e.get("reason") else "") for e in out["errors"]]
        if out["http"]: row["errors"].append("HTTP " + out["http"][:120])
        if out["request"]:
            row["hops"] = hop
            row.setdefault("requests", []).append({k: out["request"][k] for k in ("name", "args", "confirm")})
            payload["tool_result"] = {**result, "call_id": out["request"]["call_id"]}
            continue
        if out["frame"]:
            f = out["frame"]
            row["frame"] = f.get("type"); row["title"] = f.get("title"); row["sentence"] = f.get("sentence")
            if f.get("type") == "plan":
                row["tasks"] = [t.get("title") for t in (f.get("data") or {}).get("tasks", [])]
            if f.get("type") == "text":
                row["sub"] = ((f.get("data") or {}).get("sub") or "")[:400]
        break
    row["seconds"] = round(time.time() - started, 1)
    return row

def main():
    matrix = json.load(open(sys.argv[1]))
    out_path = "results.json"
    workers = 3
    only = None
    pace = 0.0
    args = sys.argv[2:]
    while args:
        k = args.pop(0)
        if k == "--pace": pace = float(args.pop(0))
        elif k == "--out": out_path = args.pop(0)
        elif k == "--workers": workers = int(args.pop(0))
        elif k == "--only": only = set(args.pop(0).split(","))
    cases = [c for c in matrix if not only or c["id"] in only]
    results, lock = [], threading.Lock()
    queue = list(cases)

    def worker():
        while True:
            with lock:
                if not queue: return
                case = queue.pop(0)
            if pace: time.sleep(pace)
            try:
                row = run_case(case)
            except Exception as e:
                row = {"id": case["id"], "want": case.get("want"), "errors": [f"HARNESS {e}"], "tools": []}
            with lock:
                results.append(row)
                hit = "ok " if case.get("want") in (row.get("tools") or []) or not case.get("want") else "MISS"
                print(f"[{len(results):>2}/{len(cases)}] {hit} {row['id']:<18} {row.get('seconds','?'):>5}s "
                      f"frame={row.get('frame')} tools={','.join(row.get('tools') or []) or '-'} "
                      f"{'err=' + ','.join(row['errors']) if row.get('errors') else ''}", flush=True)

    threads = [threading.Thread(target=worker) for _ in range(workers)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    order = {c["id"]: i for i, c in enumerate(cases)}
    results.sort(key=lambda r: order.get(r["id"], 0))
    json.dump(results, open(out_path, "w"), ensure_ascii=False, indent=1)
    print(f"\nwrote {out_path}")
    print(f"sweep session {RUN_SESSION} — stamp it summarized so it never reaches memory:")
    print(f"  update public.ai_sessions set summarized_at = now() where id = '{RUN_SESSION}';")

if __name__ == "__main__":
    main()
