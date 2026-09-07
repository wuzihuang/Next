#!/usr/bin/env python3
"""ADR 0018 · drive /turn through the resumable protocol from a terminal.

usage: turn-resume.py [--surface panel|chat|plan] [--locale zh-CN] [--device '{...json...}']
                      [--result '{"ok":true,"code":"OK","data":{...}}'] <question>

Sends the question; if the server answers with tool.request, prints it and replays the same
Idempotency-Key with --result (default: ok:true OK) until a frame arrives. Reads apikeys.json
and session.json from NB_DEV_DIR (see turn-test.py)."""
import json, os, subprocess, sys, time, uuid

SCR = os.environ.get("NB_DEV_DIR", os.path.dirname(os.path.abspath(__file__)))
URL = "https://gkgzwcxivnffsecshvfs.supabase.co"
keys = json.load(open(f"{SCR}/apikeys.json"))
ANON = [k["api_key"] for k in keys if k["name"] == "anon"][0]
sess = json.load(open(f"{SCR}/session.json"))

args = sys.argv[1:]
opts = {"surface": "panel", "locale": "en-US", "device": None, "result": None, "base": f"{URL}/functions/v1"}
while args and args[0].startswith("--"):
    k = args.pop(0)[2:]
    opts[k] = args.pop(0)
question = " ".join(args)

body = {"text": question, "locale": opts["locale"], "surface": opts["surface"]}
if opts["device"]:
    body["freshness"] = {"status": "ready", "device": json.loads(opts["device"])}
body["session_id"] = os.environ.get("NB_SESSION_ID", str(uuid.uuid4()))
key = str(uuid.uuid4())
default_result = json.loads(opts["result"]) if opts["result"] else {"ok": True, "code": "OK"}

def post(payload):
    t0 = time.time()
    p = subprocess.Popen(["curl", "-s", "-N", "--max-time", "120", "-X", "POST", f"{opts['base']}/turn",
                          "-H", f"apikey: {ANON}", "-H", f"Authorization: Bearer {sess['access_token']}",
                          "-H", "Content-Type: application/json", "-H", f"Idempotency-Key: {key}",
                          "-d", json.dumps(payload)], stdout=subprocess.PIPE, text=True, bufsize=1)
    ev = None; out = {"tools": [], "thoughts": [], "frame": None, "request": None, "errors": [], "raw": []}
    for line in p.stdout:
        out["raw"].append(line)
        if line.startswith("event:"): ev = line[6:].strip()
        elif line.startswith("data:"):
            d = json.loads(line[5:].strip() or "{}")
            if ev == "tool": out["tools"].append(d.get("name"))
            elif ev == "thought": out["thoughts"].append(d.get("text"))
            elif ev == "tool.request": out["request"] = d
            elif ev == "screen.render": out["frame"] = d.get("envelope")
            elif ev == "error": out["errors"].append(d)
    p.wait()
    out["seconds"] = round(time.time() - t0, 1)
    if not out["raw"]:
        out["errors"].append({"code": "EMPTY_RESPONSE"})
    elif not out["raw"][0].startswith("event:"):
        out["errors"].append({"code": "HTTP", "body": "".join(out["raw"])[:400]})
    return out

hop = 0
while True:
    out = post(body)
    print(f"--- hop {hop} · {out['seconds']}s · tools={out['tools']}")
    for t in out["thoughts"][:6]: print("   ·", t)
    for e in out["errors"]: print("   ERROR", json.dumps(e, ensure_ascii=False)[:600])
    if out["request"]:
        r = out["request"]
        print("   tool.request", json.dumps({k: r[k] for k in ("name", "args", "confirm")}, ensure_ascii=False))
        hop += 1
        if hop > 3: print("   gave up"); break
        body["tool_result"] = {**default_result, "call_id": r["call_id"]}
        continue
    if out["frame"]:
        f = out["frame"]
        print("   FRAME", f.get("type"), "|", f.get("title"), "|", f.get("sentence"), "|", (f.get("data") or {}).get("sub", "")[:300])
        if f.get("type") == "plan":
            for t in f["data"].get("tasks", []): print("     -", t.get("title"), "·", t.get("sub"), "·", t.get("basis"))
    break
