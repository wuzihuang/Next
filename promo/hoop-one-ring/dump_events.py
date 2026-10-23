#!/usr/bin/env python3
"""dump_events.py — the comp's __events() → events.json, so the score is timed from the film, not retyped."""
import asyncio, json, os, sys
from playwright.async_api import async_playwright

async def main():
    comp = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "comp.html"))
    async with async_playwright() as p:
        b = await p.chromium.launch(); pg = await b.new_page(viewport={"width": 1920, "height": 1080})
        errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        await pg.goto("file://" + comp); await pg.evaluate("window.__ready")
        ev = await pg.evaluate("window.__events()")
        await b.close()
    out = os.path.join(os.path.dirname(comp), "events.json")
    json.dump(ev, open(out, "w"), indent=1)
    print(out, len(ev["events"]), "events | page errors:", errs[:3] or "none")

asyncio.run(main())
