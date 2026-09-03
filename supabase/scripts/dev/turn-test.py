#!/usr/bin/env python3
"""Drive /turn with the user's own session and print what came back, question by question.
usage: turn-test.py <base-url> <question>...   (base like http://localhost:8000/functions/v1)"""
import json, sys, subprocess, time, os
SCR = os.environ.get("NB_DEV_DIR", os.path.dirname(os.path.abspath(__file__)))
URL = "https://gkgzwcxivnffsecshvfs.supabase.co"
keys = json.load(open(f"{SCR}/apikeys.json"))
ANON = [k["api_key"] for k in keys if k["name"] == "anon"][0]
sess = json.load(open(f"{SCR}/session.json"))

def refresh():
    global sess
    r = subprocess.run(["curl", "-s", "-X", "POST", f"{URL}/auth/v1/token?grant_type=refresh_token",
                        "-H", f"apikey: {ANON}", "-H", "Content-Type: application/json",
                        "-d", json.dumps({"refresh_token": sess["refresh_token"]})], capture_output=True, text=True)
    d = json.loads(r.stdout)
    if "access_token" in d:
        sess = d; json.dump(d, open(f"{SCR}/session.json", "w"))
    else:
        print("refresh failed:", r.stdout[:200])

if time.time() > sess.get("expires_at", 0) - 300:
    refresh()

base = sys.argv[1]
for q in sys.argv[2:]:
    t0 = time.time()
    r = subprocess.run(["curl", "-s", "-N", "--max-time", "120", "-X", "POST", f"{base}/turn",
                        "-H", f"apikey: {ANON}", "-H", f"Authorization: Bearer {sess['access_token']}",
                        "-H", "Content-Type: application/json", "-H", f"Idempotency-Key: {os.urandom(8).hex()}",
                        "-d", json.dumps({"text": q} if not os.environ.get("NB_LOCALE") else {"text": q, "locale": os.environ["NB_LOCALE"]})], capture_output=True, text=True)
    dt = time.time() - t0
    print(f"\n=== {q}  ({dt:.1f}s, http-len {len(r.stdout)})")
    ev = None; tools = []; env = None; errs = []
    for line in r.stdout.splitlines():
        if line.startswith("event:"): ev = line[6:].strip()
        elif line.startswith("data:"):
            d = json.loads(line[5:].strip() or "{}")
            if ev == "tool": tools.append(d.get("name"))
            elif ev == "screen.render": env = d.get("envelope")
            elif ev == "error": errs.append(d); env = env or d.get("fallback_frame")
    if not r.stdout.startswith("event:"): print("  raw:", r.stdout[:400])
    print("  tools:", " → ".join(tools))
    for e in errs: print("  ERROR:", {k: v for k, v in e.items() if k != "fallback_frame"})
    if env:
        data = env.get("data", {})
        keys_ = {k: (v if not isinstance(v, list) else f"[{len(v)}]") for k, v in data.items()}
        print(f"  type={env.get('type')} target={env.get('target')} tag={env.get('tag')}")
        print(f"  title={env.get('title')!r} hero={data.get('hero')!r}")
        print(f"  sentence={env.get('sentence')!r}")
        print(f"  footer={env.get('footer')!r} action={env.get('action')!r}")
        print(f"  data={keys_}")
