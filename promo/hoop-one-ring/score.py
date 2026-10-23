#!/usr/bin/env python3
"""score.py — the film's sound from its own events (events.json via dump_events.py), on the synthetic palette in one room.
No music: a heartbeat, one breath out, the day ticking past, a landing, keys. The end is silent."""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "onetake-src", "scripts"))
from sfx_palette import Score, air, glass, wood, sub, bubble, SR, lp

ev = json.load(open(os.path.join(HERE, "events.json")))
T, E = ev["T"], ev["events"]
rng = np.random.default_rng(3)
s = Score(dur=T["DUR"], T60=1.0)
place = s.place

def hum(dur, f=55.0, cut=0.04):
    """the band's own quiet: two low partials and a breath of noise, faded in, cut in `cut` s"""
    n = int(SR * dur); t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) * 0.6 + np.sin(2 * np.pi * f * 2 * t + 0.3) * 0.25 + lp(rng.standard_normal(n), 240) * 0.12
    env = np.minimum(1, t / 0.6) * np.where(t > dur - cut, (dur - t) / cut, 1)
    return x * env / (np.abs(x).max() + 1e-9)

# 0 · the pip: the band's hum, and a heartbeat (lub-dub) the pip blinks with
place(hum(T["PULL1"]), 0.0, 0.10, 0.0, 0.3)
for e in E:
    if e["kind"] == "lub": place(sub(92, 0.14), e["t"], 0.22, 0.0, 0.15)
    if e["kind"] == "dub": place(sub(74, 0.11), e["t"], 0.15, 0.0, 0.15)
# 1 · the pull-out: one long breath, and a felt landing with a knock when the band arrives
place(air(1.45, 160, 2600, 1.2, 0.72), T["PULL0"], 0.42, 0.0, 0.6)
place(sub(58, 0.7), T["PULL1"], 0.5, 0.0, 0.35); place(wood(150, 0.1), T["PULL1"] + 0.01, 0.28, 0.0, 0.2)
# 2 · the day: 96 slot ticks, never the same twice, loosened by a few ms, panned with the pip; the three captions as glass
for e in E:
    if e["kind"] == "slot":
        place(wood(900 + rng.uniform(-120, 160), 0.03), e["t"] + rng.uniform(-0.004, 0.004), (0.085 if e["v"] > 0.9 else 0.055) * rng.uniform(0.75, 1.25), e["pan"] * 0.8, 0.12)
caps = [glass(784, 0.8, 0.6), glass(659, 0.8, 0.6), glass(523, 0.9, 0.5)]
for e, gl in zip([e for e in E if e["kind"] == "caption"], caps): place(gl, e["t"], 0.14, e["pan"] * 0.6, 0.5)
place(air(0.9, 500, 2000, 1.4, 0.5), T["SWEEP0"] + 0.1, 0.16, -0.2, 0.5, pan_to=0.2)
# the stop
place(sub(70, 0.5), T["SWEEP1"], 0.36, 0.0, 0.3); place(wood(230, 0.08), T["SWEEP1"] + 0.005, 0.26, -0.2, 0.2)
# 3 · the fill: a short rise and a soft tone when 12.4 lands
place(air(0.55, 300, 2600, 1.3, 0.4), T["FILL0"], 0.28, 0.0, 0.45)
place(glass(1046, 1.3, 0.5), T["FILL1"], 0.13, 0.0, 0.6); place(glass(1318, 1.1, 0.4), T["FILL1"] + 0.02, 0.08, 0.1, 0.6)
# 4 · the page: one breath out as the camera pulls, a rounded pop as each row lands — then nothing (the hold is silent)
place(air(0.95, 220, 1700, 1.1, 0.5), T["PAGE0"], 0.3, 0.0, 0.6)
for i, e in enumerate([e for e in E if e["kind"] == "row"]): place(bubble(470 + i * 35, 0.2), e["t"], 0.12, (i % 2 - 0.5) * 0.3, 0.3)
# 5 · the hits: three felt hits, then the deep one as the ring returns
for i, e in enumerate([e for e in E if e["kind"] == "hit"]):
    place(sub(72 - i * 4, 0.5 if i < 3 else 1.0), e["t"], 0.42 if i < 3 else 0.5, 0.0, 0.25 if i < 3 else 0.45)
# 6 · the lockup: muted keys at 28 ms, the ring lands as the O, the pip pops, the line types softer
for e in E:
    if e["kind"] == "key": place(wood(175 + rng.uniform(-20, 20), 0.08), e["t"], 0.16 * rng.uniform(0.8, 1.2), e["pan"] * 0.4, 0.15)
    if e["kind"] == "key2": place(wood(190 + rng.uniform(-20, 20), 0.07), e["t"], 0.09 * rng.uniform(0.8, 1.2), 0.0, 0.15)
    if e["kind"] == "oland": place(sub(62, 0.6), e["t"], 0.4, 0.05, 0.35); place(bubble(400, 0.22), e["t"] + 0.005, 0.2, 0.05, 0.3)
    if e["kind"] == "pip": place(bubble(640, 0.18), e["t"], 0.24, 0.35, 0.3)

s.write(os.path.join(HERE, "sfx.wav"))
