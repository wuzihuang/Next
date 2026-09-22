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
             dash=None, arc=None, seg_colors=None, azim=None):
    """Elliptical ring band. half: 'front'|'back'|None. dash: (n, duty, offset).
    arc: (t0, t1) degrees. seg_colors: list of colors split by angle.
    azim: callable(angle) -> brightness multiplier along the ring, for glints (glints) and for
    the wake of a body running the track (crest). This is the only way a ring is allowed to
    look alive: the dash pattern itself never moves."""
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
    if azim is not None:
        sel = band > 0.004  # only the pixels actually on the band need the azimuthal term
        if sel.any():
            band = band.copy()
            band[sel] *= azim(t[sel])
    band = band * m * alpha
    if seg_colors:
        idx = np.clip((((t + math.pi) / TAU) * len(seg_colors)).astype(int),
                      0, len(seg_colors) - 1)
        for i, col in enumerate(seg_colors):
            img += (band * (idx == i))[..., None] * col
    else:
        img += band[..., None] * color


def add_ring_dots(img, cx, cy, rx, ry, deg, phases, dot_r, color, alpha, t,
                  ecc=0.0, k=1, primary=None):
    """Bodies sharing one orbit, at uneven mean-anomaly offsets (`phases`, in turns).
    Evenly spaced dots advancing at one rate is a clock face. Uneven spacing under Kepler's
    second law is a debris stream: it bunches where the orbit is slow and strings out where it
    is fast, and never shows a constant angular rate anywhere. Dots on the far half are dimmed
    and occulted by the primary; a dot that comes in close brightens and grows."""
    for ph in phases:
        th = kepler(t, k, ecc, TAU * ph)
        x, y, front = ellipse_pt(cx, cy, rx, ry, deg, th)
        near = kepler_near(th, ecc)
        add_satellite(img, x, y, front,
                      [(dot_r * near, color, alpha * near * (1.0 if front else 0.5))],
                      primary)


def ring_set(img, cx, cy, rx, ry, deg, color, half, gap=8,
             widths=(1.6, 1.2, 1.0), alphas=None, glint=None):
    """3 concentric thin ring lines with Cassini-gap spacing.
    Front half defaults to .85/.5/.3, back half to .3/.2/.12.
    glint=(amp, t): each line sparkles at its own rate, the inner line fastest, so the light
    shears across the gaps. That shear is the only rotation a ring is physically allowed --
    its particles are on independent Kepler orbits (omega ~ r^-1.5) and cannot turn as one
    rigid hoop. Front and back halves of a line share a seed, so the sparkle is continuous
    around the ansae."""
    if alphas is None:
        alphas = (0.85, 0.5, 0.3) if half == "front" else (0.3, 0.2, 0.12)
    for i in range(3):
        az = glints(glint[1], glint[0], shear=2 - i, seed=i * 1.9) if glint else None
        add_ring(img, cx, cy, rx + i * gap, ry + i * gap * (ry / rx), deg,
                 widths[i], color, alphas[i], half=half, azim=az)


def _line_field(p0, p1):
    x0, y0 = p0
    x1, y1 = p1
    vx, vy = x1 - x0, y1 - y0
    l2 = vx * vx + vy * vy
    s = ((X - x0) * vx + (Y - y0) * vy) / l2
    dist = np.hypot(X - (x0 + s * vx), Y - (y0 + s * vy))
    return dist, s


def add_line(img, p0, p1, width, color, alpha, dash=None, clip_seg=True, wave=None):
    dist, s = _line_field(p0, p1)
    band = np.exp(-((dist / width) ** 2)).astype(np.float32)
    m = np.ones((H, W), bool)
    if clip_seg:
        m = (s > -0.15) & (s < 1.15)
    if dash is not None:
        n, duty, off = dash
        m &= (s * n + off) % 1.0 < duty
    if wave is not None:
        sel = band > 0.004
        if sel.any():
            band = band.copy()
            band[sel] *= wave(s[sel])
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
        # two harmonics per star: scintillation is turbulent air, not a pulse generator
        a = a0 * (0.5 + 0.34 * math.sin(TAU * k * t + ph)
                  + 0.16 * math.sin(TAU * (k + 2) * t + ph * 1.7))
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
        a = 0.405 * scintillate(t, 0.48, ph, ks=(2, 3, 5))
        add_flare(img, x, y, r, WHITE, max(a, 0.0))


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


# ------------------------------------------------------- celestial mechanics
# Three rules, and every plate obeys them.
#   1. Nothing turns at a constant angular rate. A constant rate is a clock, and there is no
#      clock in the sky: everything that goes round obeys Kepler's second law and visibly
#      crawls at apoapsis, whips through periapsis.
#   2. A ring does not rotate. It is a swarm of particles on independent orbits, so it can only
#      shear (inner faster) and glint. A marching dash pattern is a conveyor belt, not a ring.
#   3. What actually changes in three seconds of sky is light, not position: glints off ring
#      particles, scintillation through air, the terminator, libration. Light is never a single
#      sine -- it is several, at rates that do not divide into each other.
# Every rate below is an integer number of cycles per loop, so frame 72 == frame 0 exactly.

def scintillate(t, amp, seed=0, ks=(1, 2, 3), w=(0.58, 0.29, 0.13)):
    """breathe() with three harmonics instead of one. A lone sine reads as a metronome; three
    unrelated phases read as a thing being looked at through an atmosphere."""
    return 1.0 + amp * sum(
        wi * math.sin(TAU * ki * t + (seed * 1.7 + i * 2.39) % TAU)
        for i, (ki, wi) in enumerate(zip(ks, w)))


def kepler(t, k=1, ecc=0.0, ph=0.0):
    """Eccentric anomaly E at loop time t, by Newton on M = E - e sinE, with M = 2*pi*k*t + ph.
    Feed E straight into a centred ellipse parametrisation (rx cosE, ry sinE) and the body
    traces that exact ellipse while sweeping equal areas in equal times -- fast when it is
    close, slow when it is far. k whole orbits per loop keeps the seam exact.

    The eccentricity here is a timing parameter: the drawn track stays where the composition
    put it, and only the body's pace along it is made honest."""
    M = TAU * k * t + ph
    E = M + ecc * math.sin(M)
    for _ in range(8):
        E -= (E - ecc * math.sin(E) - M) / (1 - ecc * math.cos(E))
    return E


def kepler_ease(t, ecc, ph=math.pi):
    """t (0..1) -> fraction along an open path, eased the same way. ph=pi puts periapsis at the
    middle of the path, so a body coasts in from far away, whips past, and coasts out."""
    return ((kepler(t, 1, ecc, ph) - ph) / TAU) % 1.0


def kepler_near(th, ecc, p=0.6):
    """How close a body is, as a multiplier around 1: bodies brighten and grow coming in and
    fade going out. Normalised on the geometric mean of periapsis and apoapsis so the swing is
    symmetric instead of a flare-out every lap."""
    return (math.sqrt(1 - ecc * ecc) / (1 - ecc * math.cos(th))) ** p


def ellipse_pt(cx, cy, rx, ry, deg, th):
    """Point on a drawn ellipse at parametric angle th, plus whether it is on the near half
    (the same yr > 0 convention add_ring uses to split front from back)."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    ox, oy = rx * math.cos(th), ry * math.sin(th)
    return cx + ox * ca - oy * sa, cy + ox * sa + oy * ca, oy > 0


def add_satellite(img, x, y, front, layers, primary=None):
    """A body on an orbit. layers: [(radius, colour, alpha)]. primary=(cx, cy, r): while the
    body is on the far half and inside that disc it is occulted, with a few pixels of fade at
    the limb. A moon that never goes behind its planet is a sticker on the glass."""
    if primary is not None and not front:
        cx, cy, r = primary
        d = math.hypot(x - cx, y - cy)
        if d < r - 4:
            return
        if d < r + 4:
            f = (d - (r - 4)) / 8.0
            layers = [(lr, col, al * f) for (lr, col, al) in layers]
    for (lr, col, al) in layers:
        add_glow(img, x, y, lr, lr, col, al)


GLINT_WAVES = ((7, 2), (11, -1), (17, 1), (23, -2), (31, 3))


def glints(t, amp=0.5, shear=0, seed=0.0):
    """Azimuthal brightness for a ring: five waves of different spatial harmonic m running at
    different signed integer rates k, i.e. drifting at k/m turns per loop each. No two share a
    speed and two of them run backwards, so the eye can find no rotation to lock onto -- it
    reads as sunlight catching ice. `shear` adds a turn to every rate; ring_set hands the inner
    line the biggest shear, which is Kepler's omega ~ r^-1.5 in the only form a flat ring can
    show it."""
    comps = [(m, k + (1 if k > 0 else -1) * shear, (seed + i * 2.39) % TAU)
             for i, (m, k) in enumerate(GLINT_WAVES)]
    def fn(th):
        g = np.zeros_like(th)
        for (m, k, ph) in comps:
            g += np.sin(m * th + TAU * k * t + ph)
        return np.clip(1.0 + amp * g / len(comps), 0.04, None)
    return fn


def crest(ang, span=0.5, tail=2.2, base=0.15):
    """Angular envelope peaking at `ang` with a long decay behind it. Lets a dashed orbit track
    light up around the body running it instead of marching: the dashes are tick marks on the
    path, and the only thing that moves is what is orbiting."""
    def fn(th):
        d = (th - ang + math.pi) % TAU - math.pi  # signed angle from the body, -pi..pi
        env = np.where(d >= 0, np.exp(-(d / span) ** 2), np.exp(d / tail))
        return base + (1 - base) * env
    return fn


def travel(t, amp, *waves, seed=0.0):
    """crest's cousin for straight lines: brightness running along the line as several waves of
    different wavelength and signed speed, so a sight line shimmers without ever reading as a
    crawling dash."""
    comps = [(m, k, (seed + i * 2.39) % TAU) for i, (m, k) in enumerate(waves)]
    def fn(s):
        g = np.zeros_like(s)
        for (m, k, ph) in comps:
            g += np.sin(TAU * m * s + TAU * k * t + ph)
        return np.clip(1.0 + amp * g / len(comps), 0.05, None)
    return fn


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


def add_comet(img, t, path, color, ecc=0.82):
    """The path is fixed; the pace along it is Kepler's. The comet coasts in from the far end,
    accelerates into the turn and coasts out again -- and because the tail samples are spaced
    in time, not in distance, the tail stretches out exactly when it is moving fastest."""
    env = math.sin(math.pi * t) ** 1.3
    if env < 0.01:
        return
    for j in range(26):
        q = t - j * 0.012
        if q < 0:
            continue
        px, py = path(kepler_ease(q, ecc))
        a = env * ((1 - j / 26) ** 2) * 0.32
        r = max(6.5 - j * 0.2, 1.2)
        add_glow(img, px, py, r, r, color, a)
    hx, hy = path(kepler_ease(t, ecc))
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
        img += (alpha * (0.6 + 0.28 * math.sin(TAU * k * t + ph)
                         + 0.12 * math.sin(TAU * (k + 2) * t + ph * 2.1))) * layer
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

def make_moon_surface(seed, craters=44, maria=3, gamma=1.0, span=(0.035, 0.075)):
    """Craters and maria as points on the unit sphere: (lon, lat, size as a fraction of r,
    depth, kind). Stored on the sphere, not on the screen, so the surface can librate.
    gamma > 1 biases the small craters toward the bottom of `span`, which is the power law a
    real cratered surface follows; gamma 1 keeps the flat spread plate 23 was tuned on."""
    rng = np.random.default_rng(seed)
    feats = []
    for _ in range(maria):
        feats.append((rng.uniform(-1.1, 1.1), rng.uniform(-0.6, 0.9),
                      rng.uniform(0.22, 0.34), rng.uniform(0.26, 0.36), "mare"))
    for i in range(craters):
        big = i < 6
        # draw exactly one size per crater, in the original order: with gamma 1 and the default
        # span this is the same stream of numbers plate 23 was tuned on, to the bit
        feats.append((rng.uniform(-1.35, 1.35), rng.uniform(-0.9, 1.2),
                      rng.uniform(0.08, 0.14) if big
                      else span[0] + (span[1] - span[0]) * rng.random() ** gamma,
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
    add_glow(img, 179, 200, 120, 100, C("#6B5B3A"), 0.32 * scintillate(t, 0.22, 1))
    st = [(0, C("#F7EFDD")), (.35, C("#DCCBA6")), (.65, C("#8A7A58")), (1, C("#1E1A12"))]
    haze = glints(t, 0.30, shear=0, seed=1.1)  # the dust sheet glints slower than the lines
    add_ring(img, 179, 198, 150, 38, -14, 12, C("#C9B68C"), 0.10, half="back", azim=haze)
    ring_set(img, 179, 198, 166, 43, -14, C("#D9C69A"), "back", glint=(0.6, t))
    paste(img, *sphere_layer(179, 198, 82, 150, 160, st))
    ring_set(img, 179, 198, 166, 43, -14, C("#E8D9B0"), "front", glint=(0.6, t))
    add_ring(img, 179, 198, 150, 38, -14, 12, C("#DCC99E"), 0.12, half="front", azim=haze)
    add_starfield(img, make_starfield(101, 5), t)


MOON02 = make_moon_surface(202, craters=46, maria=3, gamma=2.2, span=(0.035, 0.11))


def plate02(img, t):  # full-bleed B/W moon, librating
    # was: the whole ball slid 3px sideways and the light source slid 8px with it. Planets do
    # not shake and a light source 1 AU away does not swing in 3 seconds. What a moon really
    # does at this timescale is librate -- it nods, by a couple of degrees, and the craters go
    # with it because they are on the sphere, not painted on the glass.
    yaw = math.radians(3.0) * math.sin(TAU * t)
    pitch = math.radians(1.5) * math.sin(TAU * t + math.pi / 2)  # a quarter out of phase, so
    # the two axes together trace a small ellipse instead of rocking along one line
    st = [(0, C("#080808")), (.35, C("#3C3C3A")), (.7, C("#9A9A96")), (1, C("#EAEAE6"))]
    paste(img, *sphere_layer(179, 240, 205, 40, 90, st, terminator=0.52, specular=0.10,
                             relief=moon_relief(MOON02, 205, yaw, pitch)))
    add_glow(img, 179, 240, 210, 210, C("#555550"), 0.10 * scintillate(t, 0.26, 2))


def plate03(img, t):  # white ringed planet upper half, near-horizontal thin ring
    add_glow(img, 179, 130, 110, 90, C("#3E5462"), 0.28 * scintillate(t, 0.2, 3))
    st = [(0, C("#F4F8FA")), (.4, C("#C7D2D8")), (.7, C("#5E6B74")), (1, C("#101418"))]
    ring_set(img, 179, 128, 155, 19, -3, C("#C9D6DC"), "back", glint=(0.62, t))
    paste(img, *sphere_layer(179, 128, 78, 150, 95, st))
    ring_set(img, 179, 128, 155, 19, -3, C("#E8F0F4"), "front", glint=(0.62, t))
    add_starfield(img, make_starfield(103, 6), t)


def plate04(img, t):  # nested orbits seen edge-on, shearing against each other
    add_glow(img, 179, 215, 40, 30, C("#5E7A92"), 0.35 * scintillate(t, 0.28, 4))
    arcs = [(46, 2.2, C("#AFC6D8"), .50, 20, 200, None, 0.0),
            (66, 1.8, C("#7E93A8"), .42, 150, 340, (10, .5, 0.0), 1.1),
            (86, 2.4, C("#C3D4E2"), .46, 260, 460, None, 2.2),
            (106, 1.6, C("#6E8199"), .38, 40, 210, (14, .45, 0.3), 0.6),
            (126, 2.0, C("#9FB4C8"), .42, 190, 400, None, 1.7),
            (146, 1.6, C("#8AA0B4"), .34, 300, 520, (16, .4, 0.6), 2.8),
            (164, 1.4, C("#5E7185"), .30, 90, 260, (18, .4, 0.1), 2.0)]
    # was: every arc rocked its own tilt +-4..7 deg, which is a hoop wobbling on a spindle.
    # Now the tilts are fixed and the light runs round each arc at its own rate, fastest on the
    # innermost -- seven orbits shearing past each other, which is what a nested system does.
    for i, (r, w, col, al, t0, t1, dash, ph) in enumerate(arcs):
        add_ring(img, 179, 215, r, r * 0.42, -18, w, col, al, dash=dash,
                 arc=(t0 % 360, t1 % 360), azim=glints(t, 0.72, shear=3 - i // 2, seed=ph))
    add_starfield(img, make_starfield(104, 5), t)


def plate05(img, t):  # -30 deg dark saturn + thin crescent moon
    add_glow(img, 205, 215, 90, 80, C("#3A3423"), 0.26 * scintillate(t, 0.22, 5))
    st = [(0, C("#8A8578")), (.4, C("#4A463C")), (.7, C("#23211B")), (1, C("#0B0A08"))]
    ring_set(img, 205, 215, 130, 34, -30, C("#9A927E"), "back", glint=(0.58, t))
    paste(img, *sphere_layer(205, 215, 68, 175, 175, st))
    ring_set(img, 205, 215, 130, 34, -30, C("#B0A892"), "front", glint=(0.58, t))
    add_crescent(img, 88, 118, 24, (9, -5), C("#D8D2C0"), 0.8)
    add_starfield(img, make_starfield(105, 5), t)


def plate06(img, t):  # a body running a dashed orbit track + 2 fixed sight lines
    add_glow(img, 179, 205, 55, 55, C("#2E3E50"), 0.35 * scintillate(t, 0.3, 6))
    # was: the whole dash pattern crawled round once a loop and both sight lines crawled with
    # it, one each way -- three conveyor belts. The dashes are tick marks on a path now: they
    # never move. The body moves, Kepler-paced, and the track brightens around it.
    th = kepler(t, 1, 0.34, -math.pi / 2)
    px, py, front = ellipse_pt(179, 205, 72, 72, 0, th)
    add_ring(img, 179, 205, 72, 72, 0, 2.0, C("#B8C4D0"), 0.6, dash=(18, .45, 0.0),
             azim=crest(th, 0.5, 1.9, base=0.44))
    add_line(img, (10, 70), (348, 310), 1.1, C("#8AA0B8"), 0.30, dash=(20, .4, 0.0),
             wave=travel(t, 0.55, (3, 1), (7, -2), seed=0.4))
    add_line(img, (30, 330), (328, 60), 1.1, C("#8AA0B8"), 0.26, dash=(18, .4, 0.0),
             wave=travel(t, 0.55, (5, -1), (9, 2), seed=1.9))
    add_glow(img, px, py, 5.0, 5.0, C("#EAF4FF"), 0.9)
    add_glow(img, px, py, 13, 13, C("#8AB4D8"), 0.34)
    add_starfield(img, make_starfield(106, 4), t)


def plate07(img, t):  # blue-gray ball + one diagonal ring line
    add_glow(img, 168, 195, 95, 85, C("#2E465C"), 0.3 * scintillate(t, 0.2, 7))
    st = [(0, C("#C3D4E2")), (.4, C("#7E93A8")), (.7, C("#33465A")), (1, C("#0C1420"))]
    ring_set(img, 168, 195, 138, 30, -24, C("#A9C4DC"), "back", glint=(0.6, t))
    paste(img, *sphere_layer(168, 195, 72, 140, 160, st))
    ring_set(img, 168, 195, 138, 30, -24, C("#C3D9EC"), "front", glint=(0.6, t))
    add_starfield(img, make_starfield(107, 5), t)


def plate08(img, t):  # small ball + wide translucent diagonal band
    add_glow(img, 152, 182, 70, 60, C("#4C4630"), 0.26 * scintillate(t, 0.22, 8))
    st = [(0, C("#E5E0D2")), (.4, C("#B0A890")), (.7, C("#4C4838")), (1, C("#12110C"))]
    sheet = glints(t, 0.26, shear=0, seed=0.8)   # the wide dust sheet, slow
    edge = glints(t, 0.55, shear=2, seed=2.7)    # the sharp edge, faster: inner orbits win
    add_ring(img, 152, 182, 175, 50, -21, 16, C("#C8BE9E"), 0.13, half="back", azim=sheet)
    add_ring(img, 152, 182, 175, 50, -21, 1.6, C("#DCD2B2"), 0.3, half="back", azim=edge)
    paste(img, *sphere_layer(152, 182, 40, 132, 158, st))
    add_ring(img, 152, 182, 175, 50, -21, 16, C("#D4C9A8"), 0.22, half="front", azim=sheet)
    add_ring(img, 152, 182, 175, 50, -21, 1.6, C("#E8DFC0"), 0.4, half="front", azim=edge)
    add_starfield(img, make_starfield(108, 5), t)


def plate09(img, t):  # dotted-texture ball + thin diagonal line
    add_glow(img, 179, 205, 90, 85, C("#38352A"), 0.24 * scintillate(t, 0.22, 9))
    st = [(0, C("#D8D5CC")), (.4, C("#8F8C82")), (.7, C("#3A3830")), (1, C("#0D0C0A"))]
    paste(img, *sphere_layer(179, 205, 80, 150, 168, st, speckle=0.55, seed=109))
    # the ring is edge-on here: it glints along its length, it does not slide along it
    add_line(img, (48, 108), (318, 322), 1.0, C("#C9C4B4"), 0.32, dash=(22, .4, 0.0),
             wave=travel(t, 0.62, (4, 1), (9, -2), (15, 3), seed=1.2))
    add_starfield(img, make_starfield(109, 4), t)


def plate10(img, t):  # minimal: one diagonal + glowing end point
    add_line(img, (66, 320), (292, 140), 1.4, C("#D8DEE6"), 0.5,
             wave=travel(t, 0.3, (2, 1), (5, -2), seed=0.9))
    add_glow(img, 292, 140, 9, 9, C("#EAF4FF"), 0.85 * scintillate(t, 0.38, 10))
    add_glow(img, 292, 140, 24, 24, C("#7FB2D8"), 0.4 * scintillate(t, 0.34, 10.5))
    add_glow(img, 66, 320, 6, 6, C("#B8C8D8"), 0.3 * scintillate(t, 0.4, 21))
    add_starfield(img, make_starfield(110, 3), t)


def plate11(img, t):  # giant ball cropped by top-right edge + ring crossing through
    add_glow(img, 330, 60, 100, 90, C("#3E5462"), 0.3 * scintillate(t, 0.2, 11))
    st = [(0, C("#E9EDEF")), (.4, C("#A9B6BE")), (.7, C("#3E4A52")), (1, C("#0A0E12"))]
    ring_set(img, 338, 55, 262, 42, -8, C("#B9C6CE"), "back", gap=10,
             widths=(1.8, 1.3, 1.0), glint=(0.6, t))
    paste(img, *sphere_layer(338, 55, 150, 300, 20, st))
    ring_set(img, 338, 55, 262, 42, -8, C("#D5DEE4"), "front", gap=10,
             widths=(1.8, 1.3, 1.0), glint=(0.6, t))
    add_starfield(img, make_starfield(111, 5, ymax=360, xhi=200), t)


def plate12(img, t):  # dark silhouette saturn, near-horizontal ring, very dim
    add_glow(img, 179, 215, 100, 90, C("#1E1E24"), 0.45 * scintillate(t, 0.18, 12))
    st = [(0, C("#3A3A3E")), (.4, C("#232326")), (.7, C("#121214")), (1, C("#070708"))]
    ring_set(img, 179, 215, 165, 24, -2, C("#44444C"), "back",
             alphas=(0.3, 0.2, 0.12), glint=(0.34, t))
    paste(img, *sphere_layer(179, 215, 85, 150, 180, st))
    ring_set(img, 179, 215, 165, 24, -2, C("#55555E"), "front",
             alphas=(0.7, 0.42, 0.25), glint=(0.34, t))
    add_starfield(img, make_starfield(112, 4), t)


def plate13(img, t):  # big dashed orbit ellipse + diagonal light beam
    add_line(img, (-20, 360), (378, 70), 26, C("#7FA8C8"), 0.08 * scintillate(t, 0.45, 13),
             clip_seg=False)
    add_line(img, (-20, 360), (378, 70), 2.0, C("#A8CCE8"), 0.22 * scintillate(t, 0.45, 13),
             clip_seg=False, wave=travel(t, 0.35, (3, 2), (8, -1), seed=0.3))
    # was: 26 dashes crawling round the ellipse while the asteroid swung +-14 deg and swung
    # back. Nothing in orbit reverses. It goes all the way round now, Kepler-paced, so it
    # crawls along the far side and whips through the near one, and the track lights up in
    # front of it and fades out behind.
    th = kepler(t, 1, 0.55, math.radians(215))
    px, py, front = ellipse_pt(179, 215, 195, 95, -16, th)
    near = kepler_near(th, 0.55)
    add_ring(img, 179, 215, 195, 95, -16, 1.8, C("#A8BED0"), 0.5, dash=(26, .4, 0.0),
             azim=crest(th, 0.42, 1.7, base=0.4))
    st = [(0, C("#D8E4F0")), (.5, C("#7E93A8")), (1, C("#16202C"))]
    paste(img, *sphere_layer(px, py, 13 * near, px - 5, py - 6, st))
    add_starfield(img, make_starfield(113, 5), t)


def plate14(img, t):  # ultra-minimal: thin circle outline + diagonal line
    add_ring(img, 179, 195, 58, 58, 0, 1.5, C("#C5CDD6"), 0.55 * scintillate(t, 0.12, 14),
             azim=glints(t, 0.4, shear=1, seed=1.4))
    add_line(img, (80, 130), (272, 318), 1.0, C("#9AA8B8"), 0.28,
             wave=travel(t, 0.28, (2, -1), (6, 2), seed=2.2))
    add_starfield(img, make_starfield(114, 2), t)


def plate15(img, t):  # red/amber horizon glow + dark ball with red rim
    band = np.exp(-(((Y - 302) / 24) ** 2)) * np.exp(-(((X - 179) / 165) ** 2))
    img += (0.5 * scintillate(t, 0.28, 15) * band)[..., None] * C("#E05E10")
    band2 = np.exp(-(((Y - 296) / 9) ** 2)) * np.exp(-(((X - 179) / 130) ** 2))
    img += (0.4 * scintillate(t, 0.3, 15.7) * band2)[..., None] * C("#F6A41C")
    st = [(0, C("#2A1410")), (.4, C("#1A0D0A")), (.7, C("#0C0706")), (1, C("#050303"))]
    rim = (C("#E05E10"), 3.0, 1.0, (0.15, 1.0))
    paste(img, *sphere_layer(179, 218, 88, 179, 60, st, rim=rim))
    add_glow(img, 179, 300, 130, 40, C("#7C2D12"), 0.3 * scintillate(t, 0.28, 25.3))
    add_starfield(img, make_starfield(115, 3, ymax=150), t)


def plate16(img, t):  # deep blue + dashed crescent arc TL + bottom glow
    add_glow(img, 179, 470, 150, 60, C("#2563EB"), 0.28 * scintillate(t, 0.28, 16))
    add_glow(img, 179, 470, 250, 100, C("#155E75"), 0.18 * scintillate(t, 0.26, 16.4))
    # the dashes hold still; a body works its way round the whole orbit, Kepler-paced, and we
    # only see the glow it drags while it crosses the 100 deg of track that is drawn
    th = kepler(t, 1, 0.45, math.radians(60))
    add_ring(img, 62, 72, 68, 68, 0, 2.0, C("#7FB2E8"), 0.55, dash=(14, .42, 0.0),
             arc=(100, 200), azim=crest(th, 0.6, 2.4, base=0.42))
    add_glow(img, 62, 72, 40, 40, C("#1D4ED8"), 0.22 * scintillate(t, 0.24, 26))
    add_starfield(img, make_starfield(116, 6), t)


def plate17(img, t):  # violet nebula + orbit ring with asteroid dots
    blobs = [(90, 140, 90, 60, -20, C("#6D28D9"), .22, 8, 5, 1, 0.0),
             (260, 240, 100, 70, 15, C("#A78BFA"), .16, 7, 6, 1, 2.1),
             (150, 330, 90, 55, -10, C("#4F46E5"), .18, 6, 5, 2, 1.0),
             (300, 90, 70, 50, 0, C("#6D28D9"), .15, 6, 4, 2, 3.3)]
    add_nebula(img, blobs, t)
    # was: 5 evenly spaced dots advancing exactly 1/5 turn a loop -- a clock face, and the
    # loudest offender in the set. Same five bodies, but on one eccentric orbit at uneven
    # anomalies: they bunch on the slow far side and string out through the fast near side,
    # dim when they are behind the ring plane, and no two ever hold the same spacing.
    add_ring(img, 179, 210, 148, 58, -12, 2.0, C("#B9A8F5"), 0.3, half="back",
             azim=glints(t, 0.4, shear=1, seed=1.7))
    add_ring(img, 179, 210, 148, 58, -12, 2.0, C("#CFC2FF"), 0.5, half="front",
             azim=glints(t, 0.4, shear=1, seed=1.7))
    add_ring_dots(img, 179, 210, 148, 58, -12, (0.0, 0.17, 0.31, 0.58, 0.79),
                  2.4, C("#E4DCFF"), 0.85, t, ecc=0.4)
    add_starfield(img, make_starfield(117, 4), t)


def plate18(img, t):  # magenta nebula along diagonal + circle ring
    blobs = [(80, 100, 80, 55, -30, C("#E84393"), .22, 7, 5, 1, 0.0),
             (170, 200, 95, 65, -30, C("#D774B4"), .2, 8, 6, 1, 1.9),
             (270, 310, 85, 60, -30, C("#E84393"), .18, 6, 5, 2, 0.8),
             (300, 80, 60, 45, 0, C("#A78BFA"), .14, 5, 4, 2, 2.6)]
    add_nebula(img, blobs, t)
    st = [(0, C("#5A2440")), (.5, C("#2A1220")), (1, C("#0C060A"))]
    paste(img, *sphere_layer(179, 205, 30, 168, 192, st))
    add_ring(img, 179, 205, 95, 95, 0, 1.8, C("#E8A8D0"), 0.45 * scintillate(t, 0.18, 18),
             azim=glints(t, 0.45, shear=1, seed=0.6))
    add_starfield(img, make_starfield(118, 4), t)


def plate19(img, t):  # rainbow-segment saturn + star flares
    add_glow(img, 179, 205, 100, 85, C("#3A3444"), 0.28 * scintillate(t, 0.2, 19))
    st = [(0, C("#F2EEE4")), (.4, C("#C9C0AC")), (.7, C("#5E5748")), (1, C("#14120C"))]
    segs = [C("#EF4444"), C("#F6A41C"), C("#FDE047"), C("#34D399"), C("#38BDF8"), C("#A78BFA")]
    # was: the whole ring rocked +-3 deg once a loop. A ring's tilt is fixed by the planet's
    # spin axis and does not nod. The colour bands hold still and the light runs through them.
    band = glints(t, 0.5, shear=1, seed=2.4)
    add_ring(img, 179, 205, 150, 40, -14, 8, None, 0.4, half="back", seg_colors=segs,
             azim=band)
    paste(img, *sphere_layer(179, 205, 70, 150, 170, st))
    add_ring(img, 179, 205, 150, 40, -14, 8, None, 0.6, half="front", seg_colors=segs,
             azim=band)
    for (fx, fy, fr) in [(70, 90, 7), (300, 130, 6), (90, 330, 5)]:
        add_flare(img, fx, fy, fr, WHITE, 0.5 * scintillate(t, 0.42, fx, ks=(2, 3, 5)))
    add_starfield(img, make_starfield(119, 4, flares=0), t)


def plate20(img, t):  # blue planet glow exiting right edge
    add_glow(img, 305, 195, 85, 85, C("#2563EB"), 0.45 * scintillate(t, 0.22, 20))
    add_glow(img, 320, 195, 150, 130, C("#1D4ED8"), 0.2 * scintillate(t, 0.24, 20.6))
    st = [(0, C("#DCEAFB")), (.4, C("#7FB2E8")), (.7, C("#1D4ED8")), (1, C("#060D1F"))]
    paste(img, *sphere_layer(298, 195, 92, 262, 162, st))
    add_starfield(img, make_starfield(120, 5, xhi=180), t)


def plate21(img, t):  # huge deep-blue planet arc on the left + satellite dot
    add_glow(img, 0, 240, 120, 160, C("#1E3A66"), 0.3 * scintillate(t, 0.18, 21))
    st = [(0, C("#3E5A8A")), (.4, C("#1E3A66")), (.7, C("#0B1E3F")), (1, C("#040810"))]
    rim = (C("#38BDF8"), 4.0, 0.55, (1.0, -0.2))
    paste(img, *sphere_layer(-90, 240, 230, 60, 170, st, rim=rim))
    # was: the satellite swung +-15 deg and swung back, which no moon has ever done. It runs
    # the whole orbit now: it comes round the limb, crosses the planet's face as a transit,
    # goes behind on the far half and is occulted, and the eccentricity keeps it slow while it
    # is on screen. Apoapsis is aimed at the frame, periapsis off to the left.
    # deg 170 draws the same ellipse but turns the orbit end for end, so apoapsis lands on the
    # side of it we can see: the outer moon hangs slowly off the limb, then slips behind and is
    # occulted. Two moons, because one lone dot going round is still a hand on a dial -- and
    # they are put in a 2:1 resonance, inner one twice a lap, which is how real moons come
    # (Io:Europa is exactly this). Kepler's third law then fixes the inner radius: a * 2^-2/3.
    for (a, ry, k, ecc, ph, r0, r1, al) in [(268, 74, 1, 0.45, 2.5, 5.5, 13, 0.95),
                                            (169, 47, 2, 0.35, 1.8, 4.2, 10, 0.7)]:
        th = kepler(t, k, ecc, ph)
        px, py, front = ellipse_pt(-90, 240, a, ry, 170, th)
        near = kepler_near(th, ecc, 0.4)
        add_satellite(img, px, py, front,
                      [(r0 * near, C("#BAE6FD"), al * near),
                       (r1 * near, C("#38BDF8"), 0.35 * near)], primary=(-90, 240, 230))
    add_starfield(img, make_starfield(121, 5), t)


def plate22(img, t):  # planet sitting low + near-horizontal thin ring
    add_glow(img, 179, 268, 90, 70, C("#3E3823"), 0.26 * scintillate(t, 0.22, 22))
    st = [(0, C("#E2DCC8")), (.4, C("#A89F82")), (.7, C("#46402C")), (1, C("#100E08"))]
    ring_set(img, 179, 268, 145, 16, -2, C("#CFC5A2"), "back", glint=(0.6, t))
    paste(img, *sphere_layer(179, 268, 68, 155, 235, st))
    ring_set(img, 179, 268, 145, 16, -2, C("#E2D8B4"), "front", glint=(0.6, t))
    add_starfield(img, make_starfield(122, 5, ymax=170), t)


MOON23 = make_moon_surface(223)


def plate23(img, t):  # moon close-up, lit from the upper left, librating under the galaxy
    cx, cy, r = 214, 372, 224
    yaw = math.radians(2.4) * math.sin(TAU * t)  # libration: +-2.4 deg east-west
    pitch = math.radians(1.1) * math.sin(TAU * t + math.pi / 2)  # +-1.1 deg north-south, a
    # quarter cycle behind the yaw, so the pair traces an ellipse the way real libration does
    # NB: sphere_layer maps the lambert term through `stops` with 0 = facing away, 1 = facing
    # the light. Every other plate lists its stops bright-to-dark (a rim-lit look); the moon
    # is a lit body, so its ramp runs dark-to-bright and the craters' relief reads the right way.
    st = [(0, C("#0A0A0A")), (.35, C("#46443E")), (.65, C("#9C9A91")), (1, C("#D6D4CC"))]
    add_glow(img, cx - 40, cy - 60, 260, 240, C("#3A3C48"), 0.10 * scintillate(t, 0.24, 23))
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
             arc=(150, 330), azim=glints(t, 0.35, shear=0, seed=2.9))
    add_comet(img, t, path, C("#38BDF8"))
    add_starfield(img, make_starfield(124, 5), t)


def plate25(img, t):  # single red-orange glow point low + small arc
    add_glow(img, 179, 318, 34, 18, C("#E05E10"), 0.42 * scintillate(t, 0.32, 25))
    add_glow(img, 179, 316, 12, 8, C("#F6A41C"), 0.5 * scintillate(t, 0.34, 25.5))
    add_ring(img, 179, 252, 60, 30, 0, 2.0, C("#F6A41C"),
             0.5 * scintillate(t, 0.22, 35), arc=(200, 340),
             azim=glints(t, 0.4, shear=2, seed=1.3))
    add_glow(img, 179, 252, 30, 20, C("#7C2D12"), 0.2 * scintillate(t, 0.28, 45))
    add_starfield(img, make_starfield(125, 3, ymax=160), t)


def plate26(img, t):  # blue-violet planet lit on the right edge
    add_glow(img, 255, 195, 70, 80, C("#6D28D9"), 0.3 * scintillate(t, 0.22, 26))
    st = [(0, C("#8F9FE8")), (.4, C("#5A6ACF")), (.7, C("#1E2450")), (1, C("#07081A"))]
    rim = (C("#A78BFA"), 4.0, 0.6, (1.0, -0.1))
    paste(img, *sphere_layer(170, 205, 85, 255, 172, st, rim=rim))
    add_starfield(img, make_starfield(126, 4), t)


def plate27(img, t):  # ultra-minimal: dashed arc top-right + glow point
    # 10 dashes marching round a 95 deg arc was the most literal clock bezel in the set. The
    # ticks hold; a body runs the full orbit behind the frame and lights the arc as it passes.
    th = kepler(t, 1, 0.5, math.radians(170))
    add_ring(img, 330, 40, 82, 82, 0, 1.8, C("#B8C4D8"), 0.5, dash=(10, .42, 0.0),
             arc=(90, 185), azim=crest(th, 0.55, 2.2, base=0.4))
    add_glow(img, 250, 46, 7, 7, C("#EAF4FF"), 0.8 * scintillate(t, 0.38, 27))
    add_glow(img, 250, 46, 18, 18, C("#7FA8C8"), 0.35 * scintillate(t, 0.36, 37))
    add_starfield(img, make_starfield(127, 2), t)


def plate28(img, t):  # equatorial band + bright edge-on horizontal ring
    add_glow(img, 179, 212, 100, 60, C("#2E3E4C"), 0.28 * scintillate(t, 0.2, 28))
    st = [(0, C("#C9D4DC")), (.4, C("#7E8E9A")), (.7, C("#2E3A44")), (1, C("#0A0E12"))]
    rgb, al = sphere_layer(179, 212, 88, 150, 170, st)
    dxn = (X - 179) / 88
    bandm = np.exp(-(((Y - 220) / 8) ** 2)) * np.clip(1 - dxn * dxn, 0, 1) * al
    rgb += (0.3 * bandm)[..., None] * C("#E8F0F4")
    # seen edge-on, a ring is a line of ice catching the light: three lanes, the inner one
    # sparkling fastest, and nothing sliding along the line
    g0 = glints(t, 0.5, shear=2, seed=0.5)
    g1 = glints(t, 0.5, shear=1, seed=2.4)
    g2 = glints(t, 0.5, shear=0, seed=4.3)
    add_ring(img, 179, 212, 162, 4, 0, 1.6, C("#C9D8E4"), 0.3, half="back", azim=g0)
    add_ring(img, 179, 212, 162, 6.5, 0, 1.2, C("#C9D8E4"), 0.2, half="back", azim=g1)
    add_ring(img, 179, 212, 162, 9, 0, 1.0, C("#C9D8E4"), 0.12, half="back", azim=g2)
    paste(img, rgb, al)
    add_ring(img, 179, 212, 162, 4, 0, 1.6, C("#EAF2F8"),
             0.85 * scintillate(t, 0.18, 28.2), half="front", azim=g0)
    add_ring(img, 179, 212, 162, 6.5, 0, 1.2, C("#EAF2F8"),
             0.5 * scintillate(t, 0.18, 28.5), half="front", azim=g1)
    add_ring(img, 179, 212, 162, 9, 0, 1.0, C("#EAF2F8"),
             0.3 * scintillate(t, 0.18, 28.8), half="front", azim=g2)
    add_glow(img, 179, 212, 150, 6, C("#7FA8C8"), 0.25 * scintillate(t, 0.2, 38))
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
            status = "OK" if seam == 0 else ("OK (1 lsb)" if seam <= 1
                                             else f"SEAM DIFF {seam}")
            print(f"{name}: seam {status}  mp4 {sz_mp4/1e6:.2f}MB  gif {sz_gif/1e6:.2f}MB",
                  flush=True)
    shutil.rmtree(TMP, ignore_errors=True)
    print("done")


if __name__ == "__main__":
    main()
