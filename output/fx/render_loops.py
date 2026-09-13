#!/usr/bin/env python3
"""render_loops.py — 28 seamless 3s LED dot-matrix loops for NEXTBODY-HOOP planet plates.

Outputs plate-01.mp4 .. plate-28.mp4 (libx264/yuv420p via ffmpeg) and plate-01.gif .. plate-28.gif
(PIL), 358x470 @ 24fps, 72 frames. All motion phases are integer cycles per loop (or symmetric
n-dot rotation stepping 1/n turn per loop), so frame N == frame 0 exactly.

Every plate is drawn on the same deep-sky layer (see GALAXY / add_galaxy): a tilted band of
~150 faint stars, three dust clouds and one distant galaxy, so the 28 plates read as views of
one galaxy rather than 28 planets on black. Per-plate animation logic is written up in PLATES.md.

Usage: .venv/bin/python render_loops.py [plate numbers...] [--jobs N]
"""
import math
import multiprocessing as mp
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

W, H = 358, 470
FPS, SECONDS = 24, 3
N = FPS * SECONDS
OUT = os.path.dirname(os.path.abspath(__file__))
TMP = os.path.join(OUT, "_frames")

Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
TAU = 2 * math.pi


def C(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


WHITE = C("#FFFFFF")


# ---------------------------------------------------------------- primitives

def _gauss(cx, cy, sx, sy, deg=0.0):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    dx, dy = X - cx, Y - cy
    xr = dx * ca + dy * sa
    yr = -dx * sa + dy * ca
    return np.exp(-0.5 * ((xr / sx) ** 2 + (yr / sy) ** 2)).astype(np.float32)


def add_glow(img, cx, cy, sx, sy, color, alpha, deg=0.0):
    if alpha <= 0:
        return
    img += (alpha * _gauss(cx, cy, sx, sy, deg))[..., None] * color


def ellipse_field(cx, cy, rx, ry, deg):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    dx, dy = X - cx, Y - cy
    xr = dx * ca + dy * sa
    yr = -dx * sa + dy * ca
    u, v = xr / rx, yr / ry
    d = np.hypot(u, v)
    t = np.arctan2(v, u)
    return d, t, yr  # yr > 0 is the front (below-center) half


def _arc_mask(t, t0, t1):
    tt = np.degrees(t) % 360.0
    if t0 <= t1:
        return (tt >= t0) & (tt <= t1)
    return (tt >= t0) | (tt <= t1)


def add_ring(img, cx, cy, rx, ry, deg, width, color, alpha, half=None,
             dash=None, arc=None, seg_colors=None):
    """Elliptical ring band. half: 'front'|'back'|None. dash: (n, duty, offset).
    arc: (t0, t1) degrees. seg_colors: list of colors split by angle."""
    d, t, yr = ellipse_field(cx, cy, rx, ry, deg)
    rt = rx * ry / np.sqrt((ry * np.cos(t)) ** 2 + (rx * np.sin(t)) ** 2 + 1e-6)
    dist = np.abs(d - 1.0) * rt  # approx pixel distance to the ellipse curve
    band = np.exp(-((dist / width) ** 2)).astype(np.float32)
    m = np.ones((H, W), bool)
    if half == "front":
        m = yr > 0
    elif half == "back":
        m = yr <= 0
    if arc is not None:
        m &= _arc_mask(t, arc[0], arc[1])
    if dash is not None:
        n, duty, off = dash
        m &= (((t / TAU) % 1.0) * n + off) % 1.0 < duty
    band = band * m * alpha
    if seg_colors:
        idx = np.clip((((t + math.pi) / TAU) * len(seg_colors)).astype(int),
                      0, len(seg_colors) - 1)
        for i, col in enumerate(seg_colors):
            img += (band * (idx == i))[..., None] * col
    else:
        img += band[..., None] * color


def add_ring_dots(img, cx, cy, rx, ry, deg, n, dot_r, color, alpha, phase):
    """n evenly spaced dots on the ellipse; phase 0..1 rotates by 1/n turn (seamless)."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    for i in range(n):
        t = TAU * (i + phase) / n
        ct, st = math.cos(t), math.sin(t)
        px = cx + rx * ct * ca - ry * st * sa
        py = cy + rx * ct * sa + ry * st * ca
        add_glow(img, px, py, dot_r, dot_r, color, alpha)


def ring_set(img, cx, cy, rx, ry, deg, color, half, gap=8,
             widths=(1.6, 1.2, 1.0), alphas=None):
    """3 concentric thin ring lines with Cassini-gap spacing.
    Front half defaults to .85/.5/.3, back half to .3/.2/.12."""
    if alphas is None:
        alphas = (0.85, 0.5, 0.3) if half == "front" else (0.3, 0.2, 0.12)
    for i in range(3):
        add_ring(img, cx, cy, rx + i * gap, ry + i * gap * (ry / rx), deg,
                 widths[i], color, alphas[i], half=half)


def _line_field(p0, p1):
    x0, y0 = p0
    x1, y1 = p1
    vx, vy = x1 - x0, y1 - y0
    l2 = vx * vx + vy * vy
    s = ((X - x0) * vx + (Y - y0) * vy) / l2
    dist = np.hypot(X - (x0 + s * vx), Y - (y0 + s * vy))
    return dist, s


def add_line(img, p0, p1, width, color, alpha, dash=None, clip_seg=True):
    dist, s = _line_field(p0, p1)
    band = np.exp(-((dist / width) ** 2)).astype(np.float32)
    m = np.ones((H, W), bool)
    if clip_seg:
        m = (s > -0.15) & (s < 1.15)
    if dash is not None:
        n, duty, off = dash
        m &= (s * n + off) % 1.0 < duty
    img += (band * m * alpha)[..., None] * color


def sphere_layer(cx, cy, r, hx, hy, stops, rim=None, craters=0, seed=0, speckle=0.0,
                 terminator=0.65, specular=0.3, relief=None):
    """Lambert-shaded sphere. stops: [(pos0..1, rgb)]. rim: (color, pow, alpha, (dx,dy)|None).
    terminator: fraction the night side is crushed toward black (day/night line).
    specular: alpha of a small highlight spot aligned with the light source (hx, hy).
    relief: optional callable(dx, dy, z, light) -> multiplier on the lambert field, for surface
    detail that must be mapped onto the sphere (see moon_relief)."""
    dx = (X - cx) / r
    dy = (Y - cy) / r
    rr = dx * dx + dy * dy
    z = np.sqrt(np.clip(1 - rr, 0, 1))
    lx, ly, lz = (hx - cx) / r, (hy - cy) / r, 1.0
    nrm = math.sqrt(lx * lx + ly * ly + lz * lz)
    lam_raw = np.clip(dx * lx / nrm + dy * ly / nrm + z * lz / nrm, 0, 1)
    lam = 0.10 + 0.90 * lam_raw
    if craters:
        rng = np.random.default_rng(seed)
        for _ in range(craters):
            ax = cx + rng.uniform(-0.65, 0.65) * r
            ay = cy + rng.uniform(-0.65, 0.65) * r
            sr = rng.uniform(0.035, 0.15) * r
            depth = rng.uniform(0.15, 0.45)
            g = np.exp(-(((X - ax) ** 2 + (Y - ay) ** 2) / (2 * sr * sr)))
            lam = lam * (1 - depth * g) + 0.05 * g
    if relief is not None:
        lam = lam * relief(dx, dy, z, (lx / nrm, ly / nrm))
    if speckle:
        rng = np.random.default_rng(seed + 999)
        sp = rng.random((H, W)).astype(np.float32)
        lam = lam * (1 - speckle * (sp > 0.93))
    pos = np.array([s[0] for s in stops], np.float32)
    cols = np.stack([s[1] for s in stops])
    flat = lam.ravel()
    rgb = np.empty((H * W, 3), np.float32)
    for ch in range(3):
        rgb[:, ch] = np.interp(flat, pos, cols[:, ch])
    rgb = rgb.reshape(H, W, 3)
    if terminator:
        lit = np.clip(lam_raw / 0.45, 0, 1) ** 0.85
        rgb *= ((1 - terminator) + terminator * lit)[..., None]
    if rim is not None:
        rimc, rpow, ralpha, rdir = rim
        rt = (1 - z) ** rpow
        if rdir is not None:
            rt = rt * np.clip(dx * rdir[0] + dy * rdir[1], 0, 1)
        rgb += (rt * ralpha)[..., None] * rimc
    alpha = np.clip((1.0 - rr) * r / 1.8, 0, 1).astype(np.float32)
    if specular:
        dl = math.hypot(hx - cx, hy - cy) or 1.0
        spx = cx + (hx - cx) / dl * 0.42 * r
        spy = cy + (hy - cy) / dl * 0.42 * r
        g = np.exp(-(((X - spx) ** 2 + (Y - spy) ** 2) / (2 * (0.15 * r) ** 2)))
        rgb += (specular * g * alpha)[..., None] * WHITE
    return rgb, alpha


def paste(img, rgb, alpha, scale=1.0):
    a = np.clip(alpha * scale, 0, 1)[..., None]
    img[:] = img * (1 - a) + rgb * a


def add_crescent(img, cx, cy, r, off, color, alpha):
    m1 = (X - cx) ** 2 + (Y - cy) ** 2 <= r * r
    m2 = (X - cx - off[0]) ** 2 + (Y - cy - off[1]) ** 2 <= (r * 0.92) ** 2
    m = (m1 & ~m2).astype(np.float32)
    img += (m * alpha)[..., None] * color
    add_glow(img, cx, cy, r * 1.5, r * 1.5, color, alpha * 0.12)


def make_stars(seed, n=6, ymax=295, xlo=16, xhi=342):
    rng = np.random.default_rng(seed)
    palette = [C("#FFFFFF"), C("#FFE9C9"), C("#CFE4FF")]
    out = []
    for _ in range(n):
        if rng.random() < 0.35:  # bright tier
            r, a0 = rng.uniform(1.1, 1.6), rng.uniform(0.5, 0.75)
        else:  # dim tier
            r, a0 = rng.uniform(0.6, 1.0), rng.uniform(0.14, 0.3)
        out.append((float(rng.uniform(xlo, xhi)), float(rng.uniform(18, ymax)),
                    float(r), float(a0),
                    int(rng.integers(1, 3)), float(rng.uniform(0, TAU)),
                    palette[int(rng.integers(0, 3))]))
    return out


def add_stars(img, stars, t):
    for (x, y, r, a0, k, ph, col) in stars:
        a = a0 * (0.5 + 0.5 * math.sin(TAU * k * t + ph))
        img += (a * np.exp(-(((X - x) ** 2 + (Y - y) ** 2) / (2 * r * r))))[..., None] * col


def make_starfield(seed, n=6, flares=1, ymax=295, xlo=16, xhi=342):
    """Layered starfield: small two-tier points + 1-2 cross-flare stars."""
    stars = make_stars(seed, n, ymax, xlo, xhi)
    rng = np.random.default_rng(seed + 5000)
    fl = [(float(rng.uniform(xlo + 24, xhi - 24)),
           float(rng.uniform(30, ymax * 0.8)),
           float(rng.uniform(4.5, 7)), float(rng.uniform(0, TAU)))
          for _ in range(flares)]
    return stars, fl


def add_starfield(img, field, t):
    stars, flares = field
    add_stars(img, stars, t)
    for (x, y, r, ph) in flares:
        a = 0.6 * (0.35 + 0.65 * (0.5 + 0.5 * math.sin(TAU * 2 * t + ph)))
        add_flare(img, x, y, r, WHITE, a)


def add_flare(img, x, y, r, color, alpha):
    dx, dy = np.abs(X - x), np.abs(Y - y)
    core = np.exp(-(dx * dx + dy * dy) / (2 * (r * 0.35) ** 2))
    h = np.exp(-((dy / (r * 0.18)) ** 2) - (dx / (r * 1.7)))
    v = np.exp(-((dx / (r * 0.18)) ** 2) - (dy / (r * 1.7)))
    img += (alpha * (core + 0.7 * h + 0.7 * v))[..., None] * color


def add_nebula(img, blobs, t):
    for (cx, cy, sx, sy, deg, col, al, dx, dy, k, ph) in blobs:
        ox = dx * math.sin(TAU * k * t + ph)
        oy = dy * math.sin(TAU * k * t + ph + 1.3)
        add_glow(img, cx + ox, cy + oy, sx, sy, col, al, deg)


def breathe(t, amp, k=1, ph=0.0):
    return 1.0 + amp * math.sin(TAU * k * t + ph)


def background(tint=None, tint_pos=(179, 200, 170, 170), tint_alpha=0.12):
    dcx = (X - W / 2) / (W / 2)
    dcy = (Y - H / 2) / (H / 2)
    d = np.clip(np.hypot(dcx, dcy), 0, 1)
    top, edge = C("#0B0B0D"), C("#070709")
    img = top[None, None, :] * (1 - d[..., None]) + edge[None, None, :] * d[..., None]
    img = img.astype(np.float32).copy()
    if tint is not None:
        img += (tint_alpha * _gauss(*tint_pos))[..., None] * tint
    return img


def add_comet(img, t, path, color):
    env = math.sin(math.pi * t) ** 1.3
    if env < 0.01:
        return
    for j in range(26):
        q = t - j * 0.012
        if q < 0:
            continue
        px, py = path(q)
        a = env * ((1 - j / 26) ** 2) * 0.32
        r = max(6.5 - j * 0.2, 1.2)
        add_glow(img, px, py, r, r, color, a)
    hx, hy = path(t)
    add_glow(img, hx, hy, 7, 7, C("#EAF6FF"), env * 0.9)
    add_glow(img, hx, hy, 17, 17, color, env * 0.5)


# ------------------------------------------------------------------- galaxy

def make_galaxy(seed, deg, cy=235, n=240, spread=64):
    """Deep-sky layer drawn under every plate. A band of n faint stars tilted `deg`, centred on
    (W/2, cy), with a gaussian spread across the band. Stars are binned into 6 twinkle groups
    (k in {1,2} cycles/loop x 3 phases) and pre-summed to static RGB images, so a frame costs
    6 full-frame multiplies instead of n. Also returns 3 dust clouds and one distant galaxy
    that sit on the same band."""
    rng = np.random.default_rng(seed)
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    palette = [WHITE, C("#FFE9C9"), C("#CFE4FF"), C("#E8DDFF")]
    groups = [np.zeros((H, W, 3), np.float32) for _ in range(6)]
    for _ in range(n):
        u = rng.uniform(-300, 300)
        v = rng.normal(0, spread)
        x = W / 2 + u * ca - v * sa
        y = cy + u * sa + v * ca
        if not (4 <= x <= W - 4 and 4 <= y <= H - 4):
            continue
        near = math.exp(-0.5 * (v / spread) ** 2)  # denser core reads brighter
        # a star must cover about one 4px dot of the LED screen or the dot mask eats it
        if rng.random() < 0.12:
            r, a0 = rng.uniform(1.2, 1.7), rng.uniform(0.22, 0.38) * (0.6 + 0.4 * near)
        else:
            r, a0 = rng.uniform(0.8, 1.2), rng.uniform(0.08, 0.20) * (0.5 + 0.5 * near)
        col = palette[int(rng.integers(0, len(palette)))]
        g = int(rng.integers(0, 6))
        groups[g] += (a0 * np.exp(-(((X - x) ** 2 + (Y - y) ** 2) / (2 * r * r))))[..., None] * col
    dust = []
    for (u, sx, sy, al) in [(-130, 150, 30, 0.08), (10, 170, 40, 0.10), (140, 140, 28, 0.075)]:
        dust.append((W / 2 + u * ca, cy + u * sa, sx, sy, al, rng.uniform(0, TAU)))
    gu, gv = rng.uniform(-170, 170), rng.uniform(-90, 90) * (1 if rng.random() < .5 else -1)
    far = (W / 2 + gu * ca - gv * sa, cy + gu * sa + gv * ca, deg + rng.uniform(15, 40))
    return dict(deg=deg, groups=groups, dust=dust, far=far, ca=ca, sa=sa)


def add_galaxy(img, gal, t, alpha=1.0, tint=None):
    """Draws a make_galaxy() layer at time t (0..1). Twinkle: group g breathes at k=1+g%2
    cycles per loop with phase (g//2)*120 deg. The dust clouds breathe (k=1, amp .18) and slide
    3px along the band (k=1). The distant galaxy pulses (k=1, amp .15). All integer cycles,
    so frame N == frame 0."""
    if alpha <= 0:
        return
    for g, layer in enumerate(gal["groups"]):
        k, ph = 1 + g % 2, (g // 2) * TAU / 3
        img += (alpha * (0.6 + 0.4 * math.sin(TAU * k * t + ph))) * layer
    col = tint if tint is not None else C("#8A8AA8")
    slide = 3 * math.sin(TAU * t)
    for (x, y, sx, sy, al, ph) in gal["dust"]:
        add_glow(img, x + slide * gal["ca"], y + slide * gal["sa"], sx, sy, col,
                 alpha * al * breathe(t, 0.18, 1, ph), gal["deg"])
    fx, fy, fdeg = gal["far"]
    pulse = breathe(t, 0.15)
    add_glow(img, fx, fy, 18, 6, C("#B8C4E8"), alpha * 0.18 * pulse, fdeg)
    add_glow(img, fx, fy, 5.5, 2.8, C("#F4F0FF"), alpha * 0.5 * pulse, fdeg)


# (band angle deg, band centre y, alpha) per plate. None = the plate's own default.
# The band is aimed along each composition's diagonal so it never fights a ring or a beam,
# and dimmed under the nebula plates (17, 18) and the ultra-minimal ones (12, 14, 27).
GALAXY = {
    1: (-22, 120, 1.0), 2: (-22, 235, 1.0), 3: (-16, 300, 1.0), 4: (-24, 235, 0.8),
    5: (-30, 235, 1.0), 6: (35, 190, 0.9), 7: (-24, 235, 1.0), 8: (-21, 235, 1.0),
    9: (38, 215, 0.9), 10: (-38, 230, 1.0), 11: (-8, 300, 1.0), 12: (-2, 235, 0.55),
    13: (-36, 215, 0.8), 14: (44, 224, 0.6), 15: (-6, 150, 0.7), 16: (-28, 235, 0.9),
    17: (-12, 235, 0.55), 18: (-30, 205, 0.55), 19: (-14, 235, 0.9), 20: (-20, 235, 1.0),
    21: (-10, 235, 1.0), 22: (-4, 110, 1.0), 23: (-20, 105, 1.1), 24: (8, 235, 0.9),
    25: (-12, 150, 0.9), 26: (-18, 235, 1.0), 27: (-32, 235, 0.6), 28: (0, 235, 0.9),
}
_GALAXY_CACHE = {}


def galaxy_for(num):
    if num not in _GALAXY_CACHE:
        deg, cy, _ = GALAXY[num]
        _GALAXY_CACHE[num] = make_galaxy(300 + num, deg, cy)
    return _GALAXY_CACHE[num]


# --------------------------------------------------------------------- moon

def make_moon_surface(seed, craters=44, maria=3):
    """Craters and maria as points on the unit sphere: (lon, lat, size as a fraction of r,
    depth, kind). Stored on the sphere, not on the screen, so the surface can librate."""
    rng = np.random.default_rng(seed)
    feats = []
    for _ in range(maria):
        feats.append((rng.uniform(-1.1, 1.1), rng.uniform(-0.6, 0.9),
                      rng.uniform(0.22, 0.34), rng.uniform(0.26, 0.36), "mare"))
    for i in range(craters):
        big = i < 6
        feats.append((rng.uniform(-1.35, 1.35), rng.uniform(-0.9, 1.2),
                      rng.uniform(0.08, 0.14) if big else rng.uniform(0.035, 0.075),
                      rng.uniform(0.45, 0.6) if big else rng.uniform(0.35, 0.55), "crater"))
    return feats


def moon_relief(feats, r, yaw, pitch):
    """relief() for sphere_layer: every feature is rotated by (yaw, pitch), projected to the
    disc and drawn foreshortened. A crater is a floor (darker, deepest on the side nearest
    the light, where the rim's shadow falls) plus a rim that is bright on the wall facing the
    light and dark on the wall turned away from it. A mare is only a soft dark floor."""
    cyaw, syaw = math.cos(yaw), math.sin(yaw)
    cpi, spi = math.cos(pitch), math.sin(pitch)

    def fn(dx, dy, z, light):
        lx, ly = light
        m = np.ones_like(dx)
        for (lon, lat, size, depth, kind) in feats:
            # unit vector on the sphere, then yaw about the vertical and pitch about the horizontal
            px, py, pz = math.cos(lat) * math.sin(lon), math.sin(lat), math.cos(lat) * math.cos(lon)
            px, pz = px * cyaw + pz * syaw, -px * syaw + pz * cyaw
            py, pz = py * cpi - pz * spi, py * spi + pz * cpi
            if pz < 0.06:
                continue
            sx, sy = px, -py  # screen (y down), in units of r
            rad = math.atan2(sy, sx)  # radial direction on the disc
            a = rad - math.pi / 2  # ellipse frame: rotated y axis lies along the radial
            ca, sa = math.cos(a), math.sin(a)
            ex, ey = dx - sx, dy - sy
            xr = ex * ca + ey * sa
            yr = -ex * sa + ey * ca
            u, v = xr / size, yr / (size * pz)
            d = np.hypot(u, v)
            fade = min(1.0, pz / 0.35)  # features soften toward the limb
            floor = np.clip((1.05 - d) / 0.25, 0, 1)
            if kind == "mare":
                m -= depth * fade * floor * np.exp(-0.5 * (d / 0.9) ** 2)
                continue
            along = (ex * lx + ey * ly) / size  # + toward the light
            # floor: a flat dark disc, deepest under the near rim where its shadow falls
            m -= depth * fade * floor * (0.75 + 0.25 * np.clip(along, -1, 1))
            tt = np.arctan2(v, u)
            nx = np.cos(tt) * ca - np.sin(tt) * sa
            ny = np.cos(tt) * sa + np.sin(tt) * ca
            ndl = nx * lx + ny * ly  # rim normal . light: + on the side nearest the light
            # inner wall: thin bright arc on the far wall (it faces the light), dark near wall
            inner = np.exp(-((d - 0.92) / 0.10) ** 2)
            m += fade * inner * (0.7 * np.clip(-ndl, 0, 1) - 0.7 * np.clip(ndl, 0, 1))
            # outer slope of the raised rim: lit on the near side, shadowed on the far side
            outer = np.exp(-((d - 1.18) / 0.12) ** 2)
            m += fade * outer * (0.25 * np.clip(ndl, 0, 1) - 0.22 * np.clip(-ndl, 0, 1))
        return np.clip(m, 0.04, 1.8)
    return fn


# ------------------------------------------------------------------- plates

def plate01(img, t):  # warm ivory saturn, wide ring -14 deg
    add_glow(img, 179, 200, 120, 100, C("#6B5B3A"), 0.32 * breathe(t, 0.25))
    st = [(0, C("#F7EFDD")), (.35, C("#DCCBA6")), (.65, C("#8A7A58")), (1, C("#1E1A12"))]
    add_ring(img, 179, 198, 150, 38, -14, 12, C("#C9B68C"), 0.10, half="back")
    ring_set(img, 179, 198, 166, 43, -14, C("#D9C69A"), "back")
    paste(img, *sphere_layer(179, 198, 82, 150, 160, st))
    ring_set(img, 179, 198, 166, 43, -14, C("#E8D9B0"), "front")
    add_ring(img, 179, 198, 150, 38, -14, 12, C("#DCC99E"), 0.12, half="front")
    add_starfield(img, make_starfield(101, 5), t)


def plate02(img, t):  # full-bleed B/W moon
    cx = 179 + 3 * math.sin(TAU * t)
    hx = 120 + 8 * math.sin(TAU * t + 0.7)
    st = [(0, C("#EAEAE6")), (.4, C("#9A9A96")), (.7, C("#3C3C3A")), (1, C("#0A0A0A"))]
    paste(img, *sphere_layer(cx, 240, 205, hx, 150, st, craters=30, seed=202))
    add_glow(img, cx, 240, 210, 210, C("#555550"), 0.10 * breathe(t, 0.3))


def plate03(img, t):  # white ringed planet upper half, near-horizontal thin ring
    add_glow(img, 179, 130, 110, 90, C("#3E5462"), 0.28 * breathe(t, 0.22))
    st = [(0, C("#F4F8FA")), (.4, C("#C7D2D8")), (.7, C("#5E6B74")), (1, C("#101418"))]
    ring_set(img, 179, 128, 155, 19, -3, C("#C9D6DC"), "back")
    paste(img, *sphere_layer(179, 128, 78, 150, 95, st))
    ring_set(img, 179, 128, 155, 19, -3, C("#E8F0F4"), "front")
    add_starfield(img, make_starfield(103, 6), t)


def plate04(img, t):  # abstract swirl arc cluster
    add_glow(img, 179, 215, 40, 30, C("#5E7A92"), 0.35 * breathe(t, 0.3))
    arcs = [(46, 2.2, C("#AFC6D8"), .50, 20, 200, None, 4, 0.0),
            (66, 1.8, C("#7E93A8"), .42, 150, 340, (10, .5, 0.0), 5, 1.1),
            (86, 2.4, C("#C3D4E2"), .46, 260, 460, None, 4, 2.2),
            (106, 1.6, C("#6E8199"), .38, 40, 210, (14, .45, 0.3), 6, 0.6),
            (126, 2.0, C("#9FB4C8"), .42, 190, 400, None, 5, 1.7),
            (146, 1.6, C("#8AA0B4"), .34, 300, 520, (16, .4, 0.6), 6, 2.8),
            (164, 1.4, C("#5E7185"), .30, 90, 260, (18, .4, 0.1), 7, 2.0)]
    for (r, w, col, al, t0, t1, dash, sw, ph) in arcs:
        deg = -18 + sw * math.sin(TAU * t + ph)
        add_ring(img, 179, 215, r, r * 0.42, deg, w, col, al, dash=dash,
                 arc=(t0 % 360, t1 % 360))
    add_starfield(img, make_starfield(104, 5), t)


def plate05(img, t):  # -30 deg dark saturn + thin crescent moon
    add_glow(img, 205, 215, 90, 80, C("#3A3423"), 0.26 * breathe(t, 0.25))
    st = [(0, C("#8A8578")), (.4, C("#4A463C")), (.7, C("#23211B")), (1, C("#0B0A08"))]
    ring_set(img, 205, 215, 130, 34, -30, C("#9A927E"), "back")
    paste(img, *sphere_layer(205, 215, 68, 175, 175, st))
    ring_set(img, 205, 215, 130, 34, -30, C("#B0A892"), "front")
    add_crescent(img, 88, 118, 24, (9, -5), C("#D8D2C0"), 0.8)
    add_starfield(img, make_starfield(105, 5), t)


def plate06(img, t):  # dashed-circle planet + 2 diagonal orbit lines
    add_glow(img, 179, 205, 55, 55, C("#2E3E50"), 0.35 * breathe(t, 0.3))
    add_ring(img, 179, 205, 72, 72, 0, 2.0, C("#B8C4D0"), 0.6, dash=(18, .45, t))
    add_line(img, (10, 70), (348, 310), 1.1, C("#8AA0B8"), 0.30, dash=(20, .4, t))
    add_line(img, (30, 330), (328, 60), 1.1, C("#8AA0B8"), 0.26, dash=(18, .4, -t))
    add_glow(img, 179, 133, 5, 5, C("#D8E4F0"), 0.5 * breathe(t, 0.4, 2))
    add_starfield(img, make_starfield(106, 4), t)


def plate07(img, t):  # blue-gray ball + one diagonal ring line
    add_glow(img, 168, 195, 95, 85, C("#2E465C"), 0.3 * breathe(t, 0.22))
    st = [(0, C("#C3D4E2")), (.4, C("#7E93A8")), (.7, C("#33465A")), (1, C("#0C1420"))]
    ring_set(img, 168, 195, 138, 30, -24, C("#A9C4DC"), "back")
    paste(img, *sphere_layer(168, 195, 72, 140, 160, st))
    ring_set(img, 168, 195, 138, 30, -24, C("#C3D9EC"), "front")
    add_starfield(img, make_starfield(107, 5), t)


def plate08(img, t):  # small ball + wide translucent diagonal band
    add_glow(img, 152, 182, 70, 60, C("#4C4630"), 0.26 * breathe(t, 0.25))
    st = [(0, C("#E5E0D2")), (.4, C("#B0A890")), (.7, C("#4C4838")), (1, C("#12110C"))]
    add_ring(img, 152, 182, 175, 50, -21, 16, C("#C8BE9E"), 0.13, half="back")
    add_ring(img, 152, 182, 175, 50, -21, 1.6, C("#DCD2B2"), 0.3, half="back")
    paste(img, *sphere_layer(152, 182, 40, 132, 158, st))
    add_ring(img, 152, 182, 175, 50, -21, 16, C("#D4C9A8"), 0.22, half="front")
    add_ring(img, 152, 182, 175, 50, -21, 1.6, C("#E8DFC0"), 0.4, half="front")
    add_starfield(img, make_starfield(108, 5), t)


def plate09(img, t):  # dotted-texture ball + thin diagonal line
    add_glow(img, 179, 205, 90, 85, C("#38352A"), 0.24 * breathe(t, 0.22))
    st = [(0, C("#D8D5CC")), (.4, C("#8F8C82")), (.7, C("#3A3830")), (1, C("#0D0C0A"))]
    paste(img, *sphere_layer(179, 205, 80, 150, 168, st, speckle=0.55, seed=109))
    add_line(img, (48, 108), (318, 322), 1.0, C("#C9C4B4"), 0.32, dash=(22, .4, t))
    add_starfield(img, make_starfield(109, 4), t)


def plate10(img, t):  # minimal: one diagonal + glowing end point
    add_line(img, (66, 320), (292, 140), 1.4, C("#D8DEE6"), 0.5)
    add_glow(img, 292, 140, 9, 9, C("#EAF4FF"), 0.85 * breathe(t, 0.4))
    add_glow(img, 292, 140, 24, 24, C("#7FB2D8"), 0.4 * breathe(t, 0.4))
    add_glow(img, 66, 320, 6, 6, C("#B8C8D8"), 0.3 * breathe(t, 0.4, 1, 2.1))
    add_starfield(img, make_starfield(110, 3), t)


def plate11(img, t):  # giant ball cropped by top-right edge + ring crossing through
    add_glow(img, 330, 60, 100, 90, C("#3E5462"), 0.3 * breathe(t, 0.22))
    st = [(0, C("#E9EDEF")), (.4, C("#A9B6BE")), (.7, C("#3E4A52")), (1, C("#0A0E12"))]
    ring_set(img, 338, 55, 262, 42, -8, C("#B9C6CE"), "back", gap=10,
             widths=(1.8, 1.3, 1.0))
    paste(img, *sphere_layer(338, 55, 150, 300, 20, st))
    ring_set(img, 338, 55, 262, 42, -8, C("#D5DEE4"), "front", gap=10,
             widths=(1.8, 1.3, 1.0))
    add_starfield(img, make_starfield(111, 5, ymax=360, xhi=200), t)


def plate12(img, t):  # dark silhouette saturn, near-horizontal ring, very dim
    add_glow(img, 179, 215, 100, 90, C("#1E1E24"), 0.45 * breathe(t, 0.2))
    st = [(0, C("#3A3A3E")), (.4, C("#232326")), (.7, C("#121214")), (1, C("#070708"))]
    ring_set(img, 179, 215, 165, 24, -2, C("#44444C"), "back",
             alphas=(0.3, 0.2, 0.12))
    paste(img, *sphere_layer(179, 215, 85, 150, 180, st))
    ring_set(img, 179, 215, 165, 24, -2, C("#55555E"), "front",
             alphas=(0.7, 0.42, 0.25))
    add_starfield(img, make_starfield(112, 4), t)


def plate13(img, t):  # big dashed orbit ellipse + diagonal light beam
    add_line(img, (-20, 360), (378, 70), 26, C("#7FA8C8"), 0.08 * breathe(t, 0.5),
             clip_seg=False)
    add_line(img, (-20, 360), (378, 70), 2.0, C("#A8CCE8"), 0.22 * breathe(t, 0.5),
             clip_seg=False)
    add_ring(img, 179, 215, 195, 95, -16, 1.8, C("#A8BED0"), 0.5, dash=(26, .4, t))
    th = math.radians(215 + 14 * math.sin(TAU * t))
    a = math.radians(-16)
    px = 179 + 195 * math.cos(th) * math.cos(a) - 95 * math.sin(th) * math.sin(a)
    py = 215 + 195 * math.cos(th) * math.sin(a) + 95 * math.sin(th) * math.cos(a)
    st = [(0, C("#D8E4F0")), (.5, C("#7E93A8")), (1, C("#16202C"))]
    paste(img, *sphere_layer(px, py, 13, px - 5, py - 6, st))
    add_starfield(img, make_starfield(113, 5), t)


def plate14(img, t):  # ultra-minimal: thin circle outline + diagonal line
    add_ring(img, 179, 195, 58, 58, 0, 1.5, C("#C5CDD6"), 0.55 * breathe(t, 0.15))
    add_line(img, (80, 130), (272, 318), 1.0, C("#9AA8B8"), 0.28)
    add_starfield(img, make_starfield(114, 2), t)


def plate15(img, t):  # red/amber horizon glow + dark ball with red rim
    band = np.exp(-(((Y - 302) / 24) ** 2)) * np.exp(-(((X - 179) / 165) ** 2))
    img += (0.5 * breathe(t, 0.3) * band)[..., None] * C("#E05E10")
    band2 = np.exp(-(((Y - 296) / 9) ** 2)) * np.exp(-(((X - 179) / 130) ** 2))
    img += (0.4 * breathe(t, 0.3) * band2)[..., None] * C("#F6A41C")
    st = [(0, C("#2A1410")), (.4, C("#1A0D0A")), (.7, C("#0C0706")), (1, C("#050303"))]
    rim = (C("#E05E10"), 3.0, 1.0, (0.15, 1.0))
    paste(img, *sphere_layer(179, 218, 88, 179, 60, st, rim=rim))
    add_glow(img, 179, 300, 130, 40, C("#7C2D12"), 0.3 * breathe(t, 0.3))
    add_starfield(img, make_starfield(115, 3, ymax=150), t)


def plate16(img, t):  # deep blue + dashed crescent arc TL + bottom glow
    add_glow(img, 179, 470, 150, 60, C("#2563EB"), 0.28 * breathe(t, 0.3))
    add_glow(img, 179, 470, 250, 100, C("#155E75"), 0.18 * breathe(t, 0.3))
    add_ring(img, 62, 72, 68, 68, 0, 2.0, C("#7FB2E8"), 0.55, dash=(14, .42, t),
             arc=(100, 200))
    add_glow(img, 62, 72, 40, 40, C("#1D4ED8"), 0.22 * breathe(t, 0.25))
    add_starfield(img, make_starfield(116, 6), t)


def plate17(img, t):  # violet nebula + orbit ring with asteroid dots
    blobs = [(90, 140, 90, 60, -20, C("#6D28D9"), .22, 8, 5, 1, 0.0),
             (260, 240, 100, 70, 15, C("#A78BFA"), .16, 7, 6, 1, 2.1),
             (150, 330, 90, 55, -10, C("#4F46E5"), .18, 6, 5, 2, 1.0),
             (300, 90, 70, 50, 0, C("#6D28D9"), .15, 6, 4, 2, 3.3)]
    add_nebula(img, blobs, t)
    add_ring(img, 179, 210, 148, 58, -12, 2.0, C("#B9A8F5"), 0.3, half="back")
    add_ring(img, 179, 210, 148, 58, -12, 2.0, C("#CFC2FF"), 0.5, half="front")
    add_ring_dots(img, 179, 210, 148, 58, -12, 5, 2.4, C("#E4DCFF"), 0.85, t)
    add_starfield(img, make_starfield(117, 4), t)


def plate18(img, t):  # magenta nebula along diagonal + circle ring
    blobs = [(80, 100, 80, 55, -30, C("#E84393"), .22, 7, 5, 1, 0.0),
             (170, 200, 95, 65, -30, C("#D774B4"), .2, 8, 6, 1, 1.9),
             (270, 310, 85, 60, -30, C("#E84393"), .18, 6, 5, 2, 0.8),
             (300, 80, 60, 45, 0, C("#A78BFA"), .14, 5, 4, 2, 2.6)]
    add_nebula(img, blobs, t)
    st = [(0, C("#5A2440")), (.5, C("#2A1220")), (1, C("#0C060A"))]
    paste(img, *sphere_layer(179, 205, 30, 168, 192, st))
    add_ring(img, 179, 205, 95, 95, 0, 1.8, C("#E8A8D0"), 0.45 * breathe(t, 0.2))
    add_starfield(img, make_starfield(118, 4), t)


def plate19(img, t):  # rainbow-segment saturn + star flares
    add_glow(img, 179, 205, 100, 85, C("#3A3444"), 0.28 * breathe(t, 0.22))
    st = [(0, C("#F2EEE4")), (.4, C("#C9C0AC")), (.7, C("#5E5748")), (1, C("#14120C"))]
    segs = [C("#EF4444"), C("#F6A41C"), C("#FDE047"), C("#34D399"), C("#38BDF8"), C("#A78BFA")]
    sway = 3 * math.sin(TAU * t)
    add_ring(img, 179, 205, 150, 40, -14 + sway, 8, None, 0.4, half="back", seg_colors=segs)
    paste(img, *sphere_layer(179, 205, 70, 150, 170, st))
    add_ring(img, 179, 205, 150, 40, -14 + sway, 8, None, 0.6, half="front", seg_colors=segs)
    for (fx, fy, fr) in [(70, 90, 7), (300, 130, 6), (90, 330, 5)]:
        add_flare(img, fx, fy, fr, WHITE, 0.5 * breathe(t, 0.45, 2, fx))
    add_starfield(img, make_starfield(119, 4, flares=0), t)


def plate20(img, t):  # blue planet glow exiting right edge
    add_glow(img, 305, 195, 85, 85, C("#2563EB"), 0.45 * breathe(t, 0.25))
    add_glow(img, 320, 195, 150, 130, C("#1D4ED8"), 0.2 * breathe(t, 0.25))
    st = [(0, C("#DCEAFB")), (.4, C("#7FB2E8")), (.7, C("#1D4ED8")), (1, C("#060D1F"))]
    paste(img, *sphere_layer(298, 195, 92, 262, 162, st))
    add_starfield(img, make_starfield(120, 5, xhi=180), t)


def plate21(img, t):  # huge deep-blue planet arc on the left + satellite dot
    add_glow(img, 0, 240, 120, 160, C("#1E3A66"), 0.3 * breathe(t, 0.2))
    st = [(0, C("#3E5A8A")), (.4, C("#1E3A66")), (.7, C("#0B1E3F")), (1, C("#040810"))]
    rim = (C("#38BDF8"), 4.0, 0.55, (1.0, -0.2))
    paste(img, *sphere_layer(-90, 240, 230, 60, 170, st, rim=rim))
    th = math.radians(-32 + 15 * math.sin(TAU * t))
    a = math.radians(-10)
    px = -90 + 268 * math.cos(th) * math.cos(a) - 74 * math.sin(th) * math.sin(a)
    py = 240 + 268 * math.cos(th) * math.sin(a) + 74 * math.sin(th) * math.cos(a)
    add_glow(img, px, py, 4.5, 4.5, C("#BAE6FD"), 0.85)
    add_glow(img, px, py, 10, 10, C("#38BDF8"), 0.35)
    add_starfield(img, make_starfield(121, 5), t)


def plate22(img, t):  # planet sitting low + near-horizontal thin ring
    add_glow(img, 179, 268, 90, 70, C("#3E3823"), 0.26 * breathe(t, 0.22))
    st = [(0, C("#E2DCC8")), (.4, C("#A89F82")), (.7, C("#46402C")), (1, C("#100E08"))]
    ring_set(img, 179, 268, 145, 16, -2, C("#CFC5A2"), "back")
    paste(img, *sphere_layer(179, 268, 68, 155, 235, st))
    ring_set(img, 179, 268, 145, 16, -2, C("#E2D8B4"), "front")
    add_starfield(img, make_starfield(122, 5, ymax=170), t)


MOON23 = make_moon_surface(223)


def plate23(img, t):  # moon close-up, lit from the upper left, librating under the galaxy
    cx, cy, r = 214, 372, 224
    yaw = math.radians(2.4) * math.sin(TAU * t)  # libration: +-2.4 deg east-west
    pitch = math.radians(1.1) * math.sin(TAU * t + 1.0)  # +-1.1 deg north-south
    # NB: sphere_layer maps the lambert term through `stops` with 0 = facing away, 1 = facing
    # the light. Every other plate lists its stops bright-to-dark (a rim-lit look); the moon
    # is a lit body, so its ramp runs dark-to-bright and the craters' relief reads the right way.
    st = [(0, C("#0A0A0A")), (.35, C("#46443E")), (.65, C("#9C9A91")), (1, C("#D6D4CC"))]
    add_glow(img, cx - 40, cy - 60, 260, 240, C("#3A3C48"), 0.10 * breathe(t, 0.25))
    paste(img, *sphere_layer(cx, cy, r, -40, 60, st, terminator=0.82, specular=0.12,
                             relief=moon_relief(MOON23, r, yaw, pitch)))
    add_starfield(img, make_starfield(123, 6, ymax=150), t)


def plate24(img, t):  # blue comet arc sweeping in from the right edge
    def path(q):
        ax, ay = 372, 150
        bx, by = 330, 310
        cx2, cy2 = 96, 300
        x = (1 - q) ** 2 * ax + 2 * (1 - q) * q * bx + q * q * cx2
        y = (1 - q) ** 2 * ay + 2 * (1 - q) * q * by + q * q * cy2
        return x, y
    add_ring(img, 200, 260, 235, 135, 8, 1.0, C("#2E4A66"), 0.3,
             arc=(150, 330))
    add_comet(img, t, path, C("#38BDF8"))
    add_starfield(img, make_starfield(124, 5), t)


def plate25(img, t):  # single red-orange glow point low + small arc
    add_glow(img, 179, 318, 34, 18, C("#E05E10"), 0.42 * breathe(t, 0.35))
    add_glow(img, 179, 316, 12, 8, C("#F6A41C"), 0.5 * breathe(t, 0.35))
    add_ring(img, 179, 252, 60, 30, 0, 2.0, C("#F6A41C"),
             0.5 * breathe(t, 0.25), arc=(200, 340))
    add_glow(img, 179, 252, 30, 20, C("#7C2D12"), 0.2 * breathe(t, 0.3))
    add_starfield(img, make_starfield(125, 3, ymax=160), t)


def plate26(img, t):  # blue-violet planet lit on the right edge
    add_glow(img, 255, 195, 70, 80, C("#6D28D9"), 0.3 * breathe(t, 0.25))
    st = [(0, C("#8F9FE8")), (.4, C("#5A6ACF")), (.7, C("#1E2450")), (1, C("#07081A"))]
    rim = (C("#A78BFA"), 4.0, 0.6, (1.0, -0.1))
    paste(img, *sphere_layer(170, 205, 85, 255, 172, st, rim=rim))
    add_starfield(img, make_starfield(126, 4), t)


def plate27(img, t):  # ultra-minimal: dashed arc top-right + glow point
    add_ring(img, 330, 40, 82, 82, 0, 1.8, C("#B8C4D8"), 0.5, dash=(10, .42, t),
             arc=(90, 185))
    add_glow(img, 250, 46, 7, 7, C("#EAF4FF"), 0.8 * breathe(t, 0.4))
    add_glow(img, 250, 46, 18, 18, C("#7FA8C8"), 0.35 * breathe(t, 0.4))
    add_starfield(img, make_starfield(127, 2), t)


def plate28(img, t):  # equatorial band + bright edge-on horizontal ring
    add_glow(img, 179, 212, 100, 60, C("#2E3E4C"), 0.28 * breathe(t, 0.22))
    st = [(0, C("#C9D4DC")), (.4, C("#7E8E9A")), (.7, C("#2E3A44")), (1, C("#0A0E12"))]
    rgb, al = sphere_layer(179, 212, 88, 150, 170, st)
    dxn = (X - 179) / 88
    bandm = np.exp(-(((Y - 220) / 8) ** 2)) * np.clip(1 - dxn * dxn, 0, 1) * al
    rgb += (0.3 * bandm)[..., None] * C("#E8F0F4")
    add_ring(img, 179, 212, 162, 4, 0, 1.6, C("#C9D8E4"), 0.3, half="back")
    add_ring(img, 179, 212, 162, 6.5, 0, 1.2, C("#C9D8E4"), 0.2, half="back")
    add_ring(img, 179, 212, 162, 9, 0, 1.0, C("#C9D8E4"), 0.12, half="back")
    paste(img, rgb, al)
    add_ring(img, 179, 212, 162, 4, 0, 1.6, C("#EAF2F8"),
             0.85 * breathe(t, 0.2), half="front")
    add_ring(img, 179, 212, 162, 6.5, 0, 1.2, C("#EAF2F8"),
             0.5 * breathe(t, 0.2), half="front")
    add_ring(img, 179, 212, 162, 9, 0, 1.0, C("#EAF2F8"),
             0.3 * breathe(t, 0.2), half="front")
    add_glow(img, 179, 212, 150, 6, C("#7FA8C8"), 0.25 * breathe(t, 0.2))
    add_starfield(img, make_starfield(128, 5), t)


PLATES = {
    1: (plate01, C("#3A2E1A")), 2: (plate02, None), 3: (plate03, C("#1E2E38")),
    4: (plate04, C("#16202A")), 5: (plate05, C("#241F14")), 6: (plate06, C("#141C26")),
    7: (plate07, C("#14202E")), 8: (plate08, C("#262216")), 9: (plate09, C("#1E1C16")),
    10: (plate10, C("#101820")), 11: (plate11, C("#18222A")), 12: (plate12, C("#101014")),
    13: (plate13, C("#12202E")), 14: (plate14, C("#14181E")), 15: (plate15, C("#2A0E06")),
    16: (plate16, C("#0B1E3F")), 17: (plate17, C("#1A1030")), 18: (plate18, C("#260A1E")),
    19: (plate19, C("#181422")), 20: (plate20, C("#0A1626")), 21: (plate21, C("#0A1830")),
    22: (plate22, C("#201C10")), 23: (plate23, None), 24: (plate24, C("#0A1626")),
    25: (plate25, C("#200A04")), 26: (plate26, C("#141233")), 27: (plate27, C("#12161E")),
    28: (plate28, C("#101820")),
}


# -------------------------------------------------------------------- post

def _post_masks():
    dx4 = (X % 4) - 1.5
    dy4 = (Y % 4) - 1.5
    dot = 0.38 + 0.82 * np.exp(-(dx4 ** 2 + dy4 ** 2) / (2 * 0.85 ** 2))
    d = np.hypot((X - W / 2) / (W / 2), (Y - H / 2) / (H / 2))
    vig = 1 - 0.55 * np.clip(d - 0.55, 0, 1) ** 1.4
    sz = np.clip((Y - 280) / 190, 0, 1) ** 1.5
    cxw = 1 - np.clip((np.abs(X - W / 2) / (W / 2)) ** 2, 0, 1)
    safe = 1 - 0.42 * sz * (0.35 + 0.65 * cxw)
    return dot.astype(np.float32), vig.astype(np.float32), safe.astype(np.float32)


DOT, VIG, SAFE = _post_masks()

# one shared film-grain plate (~5.5% luminance noise), reused for every frame
GRAIN = np.random.default_rng(20260913).normal(0, 0.055, (H, W, 1)).astype(np.float32)


def render_frame(num, fn, tint, t, grain):
    img = background(tint)
    _, _, galpha = GALAXY[num]
    add_galaxy(img, galaxy_for(num), t, galpha, tint)
    fn(img, t)
    img += grain
    img *= (DOT * VIG * SAFE)[..., None]
    return np.clip(img * 255, 0, 255).astype(np.uint8)


# -------------------------------------------------------------------- build

def build_plate(num):
    fn, tint = PLATES[num]
    name = f"plate-{num:02d}"
    fdir = os.path.join(TMP, name)
    os.makedirs(fdir, exist_ok=True)
    grain = GRAIN
    paths = []
    # seamless self-check: frame(t=0) must equal frame(t=1)
    f0 = render_frame(num, fn, tint, 0.0, grain)
    f1 = render_frame(num, fn, tint, 1.0, grain)
    seam = int(np.abs(f0.astype(int) - f1.astype(int)).max())
    for i in range(N):
        arr = render_frame(num, fn, tint, i / N, grain)
        p = os.path.join(fdir, f"f{i:04d}.png")
        Image.fromarray(arr).save(p)
        paths.append(p)
    mp4 = os.path.join(OUT, f"{name}.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS),
                    "-i", os.path.join(fdir, "f%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "19",
                    "-movflags", "+faststart", mp4], check=True)
    gif = os.path.join(OUT, f"{name}.gif")
    ims = [Image.open(p).convert("RGB") for p in paths]
    pal = ims[0].quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    q = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in ims]
    q[0].save(gif, save_all=True, append_images=q[1:], duration=1000 // FPS,
              loop=0, optimize=True)
    shutil.rmtree(fdir, ignore_errors=True)
    return name, seam, os.path.getsize(mp4), os.path.getsize(gif)


def main():
    argv = sys.argv[1:]
    jobs = 8
    if "--jobs" in argv:
        i = argv.index("--jobs")
        jobs = int(argv[i + 1])
        del argv[i:i + 2]
    nums = [int(a) for a in argv] or list(range(1, 29))
    os.makedirs(TMP, exist_ok=True)
    with mp.Pool(min(jobs, len(nums))) as pool:
        for name, seam, sz_mp4, sz_gif in pool.imap_unordered(build_plate, nums):
            status = "OK" if seam == 0 else f"SEAM DIFF {seam}"
            print(f"{name}: seam {status}  mp4 {sz_mp4/1e6:.2f}MB  gif {sz_gif/1e6:.2f}MB",
                  flush=True)
    shutil.rmtree(TMP, ignore_errors=True)
    print("done")


if __name__ == "__main__":
    main()
