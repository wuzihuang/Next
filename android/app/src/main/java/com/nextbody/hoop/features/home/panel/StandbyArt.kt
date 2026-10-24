package com.nextbody.hoop.features.home.panel

import com.nextbody.hoop.features.home.DeepSpacePlate

import android.os.PowerManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.nextbody.hoop.band.IdlePlateMotion
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 04 · 01 默认 / 01M ◇4 — the star ring. The one thing on this panel that never stops.
 *
 * A planet at the centre with its own turn on it; a lime band on a steep orbit that
 * **passes behind the sphere and comes out the other side**, and flares as its head clears
 * the limb; and a small body running the blue orbit — hidden by the planet across the far
 * half, in front of it across the near one. Every period here is co-prime with the others,
 * and the band's plane itself precesses, so the field never repeats a pose.
 *
 * The whole thing is one Canvas on the board's own 358 × 470 space, so the halftone mask
 * above it has a single layer to eat rather than a stack of shapes.
 *
 * Use: `Canvas(m) { OrbitField(clock = clock, arrival = …, coreLit = …, moving = …).draw(this) }`.
 */
class OrbitField(
    /** On-screen seconds. It advances only while the field is visible and turning, so a
     *  trip to the background pauses it instead of skipping it forward. */
    var clock: Double,
    /** 0…1 — how much of the ring the lime band covers. It is the charge level, not decoration. */
    var charge: Double = 0.72,
    /** Unknown is not an empty battery: without a score the lime band is absent. */
    var chargeKnown: Boolean = true,
    /** 0…1 — ◇3's sweep. The idle panel passes 1 and never looks at it again. */
    var arrival: Double = 1.0,
    /** ◇2 — before the core is lit the whole plate sits at 20%: this screen comes up backlit. */
    var coreLit: Boolean = true,
    /** ◇4 — from here the body is on the ring. */
    var moving: Boolean = true,
    /** Day-pool / event look. 1 is the shipping field; other ids only change composition. */
    var plate: Int = 1,
) {
    companion object {
        // The board's geometry, in the board's own 358 × 470 units.
        const val planetR = 74.0
        const val orbitRX = 126.0
        const val orbitRY = 34.0
        const val haloR = 90.0
        /** The blue orbit's plane, tilted the same 16° the board draws it at. */
        const val tilt: Double = -16 * PI / 180
        const val haloTilt: Double = 26 * PI / 180
        /** 90 seconds a revolution for the body, and nothing else divides into it. */
        const val revolution = 90.0
        const val haloRevolution = 26.0
        /** The lime plane's node walks all the way round in 97 seconds; the inclination
         *  breathes on 37 — the band comes up from a different angle every time. */
        const val nodePeriod = 97.0
        const val precession = 37.0

        /** x, y on the board, base brightness, twinkle phase. */
        private val specks: List<DoubleArray> = listOf(
            t(52, 84, 0.50, 0.0), t(300, 112, 0.35, 1.7), t(84, 300, 0.30, 3.1),
            t(286, 286, 0.50, 0.8), t(212, 70, 0.25, 2.4), t(40, 208, 0.35, 4.2),
            t(150, 372, 0.22, 5.3), t(332, 214, 0.28, 2.0), t(118, 152, 0.20, 3.9),
            t(248, 396, 0.26, 1.1),
        )

        private fun look(plate: Int): Look = when (plate) {
            2, 23 -> Look(cy = 196.0, planetR = 78.0, halo = false, orbit = false, body = false,
                          visitor = false, gray = true)
            3 -> Look(cy = 168.0, planetR = 70.0)
            4 -> Look(planet = false, halo = false, orbit = false, body = false, visitor = false, arcs = true)
            5 -> Look(cy = 186.0, planetR = 68.0, gray = true)
            6 -> Look(planet = false, halo = false, body = false, visitor = false, arcs = true)
            7 -> Look(cy = 186.0, planetR = 72.0)
            8 -> Look(cy = 176.0, planetR = 48.0)
            9 -> Look(halo = false, body = false)
            10 -> Look(planet = false, halo = false, orbit = false, body = false, visitor = false, meteors = true)
            11 -> Look(cy = 96.0, offsetX = 110.0, planetR = 120.0, body = false, visitor = false)
            12 -> Look(planetR = 80.0, visitor = false, gray = true)
            14 -> Look(planet = false, halo = false, body = false, visitor = false)
            15, 16, 25 -> Look(cy = 168.0, planetR = 64.0, halo = false, body = false,
                               visitor = false, meteors = false, horizon = true)
            20 -> Look(cy = 188.0, offsetX = 96.0, planetR = 86.0, body = false, visitor = false)
            21 -> Look(cy = 200.0, offsetX = -130.0, planetR = 140.0, halo = false, body = false, visitor = false)
            22 -> Look(cy = 210.0, planetR = 66.0)
            26 -> Look(cy = 186.0, offsetX = 36.0, planetR = 76.0, halo = false)
            27 -> Look(planet = false, halo = false, orbit = false, body = false, visitor = false, arcs = true)
            28 -> Look(cy = 188.0, planetR = 76.0)
            else -> Look()
        }
    }

    private data class Look(
        val cy: Double = 196.0,
        val offsetX: Double = 0.0,
        val planetR: Double = 74.0,
        val planet: Boolean = true,
        val halo: Boolean = true,
        val orbit: Boolean = true,
        val body: Boolean = true,
        val visitor: Boolean = true,
        val meteors: Boolean = true,
        val gray: Boolean = false,
        val arcs: Boolean = false,
        val horizon: Boolean = false,
    )

    fun draw(ds: DrawScope, size: Size = ds.size) {
        val g = PlateGc(ds)
        val w = size.width.toDouble(); val h = size.height.toDouble()
        val sx = w / 358; val sy = h / 470
        val s = min(sx, sy)
        val look = look(plate)
        val c = P(w / 2 + look.offsetX * s, look.cy * sy)

        g.fill(rectPath(0, 0, w, h), NB.panelWash.op(if (coreLit) 1.0 else 0.2))

        // ◇1 · one lime pixel, dead centre — and then the core it bursts into.
        if (!coreLit) { dot(g, c, 1.5 * s, NB.lime1); return }
        if (!(arrival > 0.001)) { dot(g, c, 6 * s, NB.lime1); return }

        val a = min(1.0, arrival)
        val bodyA = clock * 2 * PI / revolution
        val haloA = -clock * 2 * PI / haloRevolution
        // The lime plane's inclination breathes: 0.20 nearly edge-on, 0.58 wide open.
        val incl = 0.26 + 0.36 * (0.5 + 0.5 * sin(clock * 2 * PI / precession))
        // The sphere is lit from wherever the band is nearest the eye, by that much.
        val light = haloLight(haloA, incl, c, s)
        // The sweep starts at the right and closes anticlockwise, as the board draws it.
        val swept = 2 * PI * a

        nebula(g, size, s, a)
        dust(g, sx, sy, s, a)
        if (look.meteors) for (lane in 0 until 3) meteor(g, lane, sx, sy, s, a)
        if (look.visitor) visitor(g, c, s, a)
        if (look.arcs) arcs(g, c, s, a)

        // Everything upstage of the planet, in order of depth: the body crosses the far half
        // of the orbit *behind* the sphere — that occlusion is the whole trick.
        if (look.orbit) ring(g, c, s, from = PI, to = 2 * PI, swept = swept, alpha = 0.11, width = 2.2 * s)
        if (look.body && moving && sin(bodyA) < 0) body(g, c, s, bodyA)
        if (look.halo) halo(g, c, s, haloA, incl, growth = a, back = true)

        if (look.planet) planet(g, c, s, a, light, look.gray)

        // …and everything downstage of it.
        if (look.halo) halo(g, c, s, haloA, incl, growth = a, back = false)
        if (look.orbit) ring(g, c, s, from = 0.0, to = PI, swept = swept, alpha = 0.27, width = 2.8 * s)
        // The orbit lights up just ahead of the body, so you can see where it is going.
        if (look.body && moving) {
            ring(g, c, s, from = bodyA + 0.26, to = bodyA + 1.30, swept = Double.POSITIVE_INFINITY,
                 alpha = 0.26, width = 3 * s, color = NB.violet2)
        }
        if (look.body && moving && sin(bodyA) >= 0) body(g, c, s, bodyA)

        if (look.horizon) horizon(g, size, s, ember = plate == 15 || plate == 25)
        if (plate == 10) {
            val beam = Path().apply { move(P(48 * sx, 72 * sy)); line(P(310 * sx, 340 * sy)) }
            g.stroke(beam, NB.white.op(0.22 * a), width = 1.4 * s, cap = StrokeCap.Round)
        }
    }

    // MARK: geometry

    /** A point on a tilted ellipse. Angle 0 is the right-hand extreme; the lower half is
     *  the near side, which is what every `sin(angle) >= 0` test in here is asking. */
    private fun point(angle: Double, c: P, rx: Double, ry: Double, tilt: Double): P {
        val x = rx * cos(angle); val y = ry * sin(angle)
        val ct = cos(tilt); val st = sin(tilt)
        return P(c.x + (x * ct - y * st), c.y + (x * st + y * ct))
    }

    private fun orbitPoint(angle: Double, c: P, s: Double): P =
        point(angle, c, orbitRX * s, orbitRY * s, tilt)

    // MARK: the pieces

    private fun ring(g: PlateGc, c: P, s: Double, from: Double, to: Double, swept: Double,
                     alpha: Double, width: Double, color: Color = NB.violet2) {
        val path = Path()
        var drew = false
        val steps = 48
        for (i in 0..steps) {
            val t = from + (to - from) * i / steps
            // While ◇3 is still drawing, the ring exists only as far as the sweep has got.
            if (!(swept.isInfinite() || t % (2 * PI) <= swept)) continue
            val p = orbitPoint(t, c, s)
            if (drew) path.line(p) else { path.move(p); drew = true }
        }
        if (!drew) return
        g.stroke(path, color.op(alpha), width = width, cap = StrokeCap.Round)
    }

    /** The band's length. It is the charge level, not decoration. */
    private val haloSpan: Double
        get() = if (!chargeKnown) 0.0 else 2 * PI * (0.34 + 0.26 * min(1.0, max(0.0, charge)))

    /** A point on the lime band's ring. The ring is *polar*: it stands up through the
     *  planet's poles, so depth here reads off `cos`, not `sin`. */
    private fun haloPoint(t: Double, c: P, s: Double, incl: Double): P {
        val haloR = look(plate).planetR * (90.0 / 74)
        return point(t, c, haloR * s * incl, haloR * s, haloPlane)
    }

    /** The lean of the band's plane. The node walks, so the ring stands up through a
     *  different pair of poles every minute and a half. */
    private val haloPlane: Double get() = haloTilt + clock * 2 * PI / nodePeriod

    /** 0…1 — how recently the head of the band came out from behind the planet. */
    private val emergence: Double
        get() {
            val head = -clock * 2 * PI / haloRevolution
            var since = (PI / 2 - head) % (2 * PI)
            if (since < 0) since += 2 * PI
            val seconds = since * haloRevolution / (2 * PI)
            // A bump centred 0.4s after the crossing, ±0.5s wide.
            val d = (seconds - 0.4) / 0.5
            return exp(-d * d)
        }

    /** Where the band's light falls on the planet, and how much of it — a weighted sum of
     *  the near-side samples, so the direction slides continuously (an argmax would stutter). */
    private fun haloLight(angle: Double, incl: Double, c: P, s: Double): Pair<Double, Double> {
        if (!chargeKnown) return 0.0 to 0.0
        val span = haloSpan
        val n = 24
        var vx = 0.0; var vy = 0.0
        for (i in 0..n) {
            val t = angle + span * i / n
            val w = max(0.0, cos(t))
            if (!(w > 0)) continue
            val p = haloPoint(t, c, s, incl)
            val dx = p.x - c.x; val dy = p.y - c.y
            val len = max(1e-6, sqrt(dx * dx + dy * dy))
            vx += w * w * dx / len
            vy += w * w * dy / len
        }
        val mag = sqrt(vx * vx + vy * vy) / (n + 1)
        return atan2(vy, vx) to min(1.0, mag * 3)
    }

    /** The lime band, in two passes with the planet between them: the far segments go down
     *  first, thinner and dimmer, so the band narrows round the back and swells forward. */
    private fun halo(g: PlateGc, c: P, s: Double, angle: Double, incl: Double, growth: Double, back: Boolean) {
        val span = haloSpan * growth
        if (!(span > 0.03)) return
        val n = 26
        val flash = emergence
        for (i in 0 until n) {
            val u0 = i.toDouble() / n; val u1 = (i + 1).toDouble() / n
            val t0 = angle + span * u0; val t1 = angle + span * u1
            val mid = (t0 + t1) / 2
            if ((cos(mid) >= 0) == back) continue
            val depth = (cos(mid) + 1) / 2
            // Tapered at both ends, so it is a band passing through, not a pie slice.
            val taper = sin(PI * (u0 + u1) / 2).pow(0.45)
            val seg = Path().apply { move(haloPoint(t0, c, s, incl)); line(haloPoint(t1, c, s, incl)) }
            val width = (3.2 + 4.2 * depth) * s * (0.55 + 0.45 * taper)
            g.stroke(seg, NB.lime1.op(0.05 * taper * depth * growth), width = width * 2.6, cap = StrokeCap.Round)
            g.stroke(seg, NB.lime1.op(min(1.0, (0.20 + 0.70 * taper) * (0.30 + 0.70 * depth)
                                                 * (1 + 0.8 * flash * depth) * growth)),
                     width = width, cap = StrokeCap.Round)
        }
        // The head of the band, bright and glowing — the band reads as being drawn by it.
        val head = angle
        if ((cos(head) >= 0) != back) {
            val depth = (cos(head) + 1) / 2
            val p = haloPoint(head, c, s, incl)
            dot(g, p, 7 * s * (0.5 + 0.5 * depth), NB.lime1.op(0.07 * depth * growth))
            dot(g, p, 2.2 * s * (0.6 + 0.4 * depth),
                NB.limePale.op(min(1.0, (0.35 + 0.55 * depth) * (1 + flash) * growth)))
            if (flash > 0.02) {
                dot(g, p, 30 * s * (0.4 + 0.6 * flash), NB.lime1.op(0.12 * flash * growth))
                dot(g, p, 11 * s * (0.4 + 0.6 * flash), NB.lime1.op(0.30 * flash * growth))
            }
        }
    }

    /** The planet: a body, not a hole. A fixed key light from the upper left gives it form;
     *  the lime and ember on its limb come from the band and follow it. */
    private fun planet(g: PlateGc, c: P, s: Double, alpha: Double, light: Pair<Double, Double>,
                       gray: Boolean = false) {
        val r = look(plate).planetR * s * (0.35 + 0.65 * alpha)
        val disc = oval(c.x - r, c.y - r, r * 2, r * 2)
        val key = P(c.x - r * 0.42, c.y - r * 0.48)

        g.fill(disc, NB.discInk)
        g.fill(disc, radial(evenly(NB.white.op((if (gray) 0.40 else 0.15) * alpha), NB.white.op(0)),
                            key, 0.0, r * (if (gray) 0.95 else 1.15)))
        g.fill(disc, radial(evenly(NB.panelInk.op(0), NB.panelInk.op(0.80 * alpha)),
                            P(c.x * 2 - key.x, c.y * 2 - key.y), r * 0.15, r * 1.5))
        g.stroke(disc, NB.white.op(0.10 * alpha), width = 1.0)

        // The band's light on the near limb, and a cold ember answer on the far one.
        val k = light.second * alpha
        if (!(k > 0.01) || gray) return
        val la = light.first
        arc(g, c, r, la - 0.8, 1.6, 2.4 * s, NB.lime1.op(0.28 * k))
        arc(g, c, r + 3 * s, la - 0.55, 1.1, 8 * s, NB.lime1.op(0.06 * k))
        arc(g, c, r - 0.5 * s, la + PI - 0.9, 1.8, 2.6 * s, NB.ember2.op(0.30 * k))
        arc(g, c, r + 2 * s, la + PI - 0.6, 1.2, 9 * s, NB.run2.op(0.06 * k))
    }

    /** Plate 4 / 6 / 27 — LED ellipses, no second renderer. They turn with the field clock. */
    private fun arcs(g: PlateGc, c: P, s: Double, alpha: Double) {
        val spin = clock * 2 * PI / precession
        val rings = listOf(
            t(126, 34, tilt + spin * 0.15, 0.28),
            t(148, 48, tilt - spin * 0.22, 0.16),
            t(98, 22, -tilt + spin * 0.11, 0.22),
        )
        for (r in rings) {
            val path = Path()
            val steps = 48
            for (i in 0..steps) {
                val tt = PI * 2 * i / steps
                val p = point(tt, c, r[0] * s, r[1] * s, r[2])
                if (i == 0) path.move(p) else path.line(p)
            }
            g.stroke(path, NB.white.op(r[3] * alpha), width = 1.6 * s, cap = StrokeCap.Round)
        }
    }

    private fun horizon(g: PlateGc, size: Size, s: Double, ember: Boolean) {
        val tint = if (ember) NB.ember1 else NB.blue1
        val w = size.width.toDouble()
        val y = size.height * 0.62
        val r = 140 * s
        g.fill(oval(w / 2 - r, y - r * 0.28, r * 2, r * 0.7),
               radial(evenly(tint.op(0.22), tint.op(0)), P(w / 2, y), 0.0, r))
    }

    /** The small body, with the tail it drags. It swells on the near side of the orbit and
     *  shrinks away on the far side — the depth cue that makes the ellipse read as a circle. */
    private fun body(g: PlateGc, c: P, s: Double, angle: Double) {
        val near = (sin(angle) + 1) / 2
        for (k in 14 downTo 1) {
            val t = angle - k * 0.045
            val fade = 1 - k / 15.0
            dot(g, orbitPoint(t, c, s), 5 * s * (fade * (0.55 + 0.45 * near)),
                NB.lime1.op(0.18 * fade * fade * (0.4 + 0.6 * near)))
        }
        val p = orbitPoint(angle, c, s)
        val r = 6 * s * (0.70 + 0.45 * near)
        dot(g, p, r * 3.2, NB.lime1.op(0.07 * (0.3 + 0.7 * near)))
        dot(g, p, r * 1.8, NB.lime1.op(0.12 * (0.3 + 0.7 * near)))
        dot(g, p, r, NB.lime1.op(0.55 + 0.45 * near))
        dot(g, p, r * 0.42, NB.limePale.op(0.5 + 0.5 * near))
    }

    /** Every so often something else comes round the back — a moon, a dust giant, a cold one.
     *  Which, which way, how steep and when are all drawn from the cycle index. */
    private fun visitor(g: PlateGc, c: P, s: Double, alpha: Double) {
        val period = 44.0; val pass = 16.0
        val cycle = floor(clock / period)
        val h1 = hash(cycle + 3, 12.9898); val h2 = hash(cycle + 3, 78.233)
        val h3 = hash(cycle + 3, 39.425); val h4 = hash(cycle + 3, 57.117)
        val u = (clock - cycle * period - h1 * (period - pass)) / pass
        if (!(u > 0 && u < 1)) return

        val e = 0.45 * u + 0.55 * u * u * (3 - 2 * u)
        val t = PI + PI * (if (h3 < 0.5) e else 1 - e)      // the far half only
        val tlt = (-28 + 56 * h4) * PI / 180
        val ry = (34 + 60 * h2) * s                           // how deep behind it dips
        val p = point(t, c, 246 * s, ry, tlt)
        val depth = 1 + sin(t)                                // 1 at the sides, 0 deepest
        val fade = min(1.0, min(u, 1 - u) / 0.10) * alpha

        val kind = (h2 * 97).toInt() % 3
        val base = listOf(30.0, 50.0, 38.0)[kind]
        val tint = listOf(NB.white, NB.ember2, NB.violet2)[kind]
        val tintA = listOf(0.34, 0.32, 0.34)[kind]
        val r = base * s * (0.62 + 0.38 * depth)
        val disc = oval(p.x - r, p.y - r, r * 2, r * 2)
        val key = P(p.x - r * 0.42, p.y - r * 0.48)

        // The giants carry a little atmosphere; the moon does not.
        if (kind > 0) {
            val gr = r * 1.7
            g.fill(oval(p.x - gr, p.y - gr, gr * 2, gr * 2),
                   radial(evenly(tint.op(0.10 * fade), tint.op(0)), p, r * 0.8, gr))
        }
        g.fill(disc, NB.discInk.op(fade))
        g.fill(disc, tint.op(tintA * fade))
        // Lit the same way the planet is — one sky, one sun.
        g.fill(disc, radial(evenly(NB.white.op(0.22 * fade), NB.white.op(0)), key, 0.0, r * 1.15))
        g.fill(disc, radial(evenly(NB.panelInk.op(0), NB.panelInk.op(0.85 * fade)),
                            P(p.x * 2 - key.x, p.y * 2 - key.y), r * 0.15, r * 1.5))
        g.stroke(disc, NB.white.op(0.11 * fade), width = 1.0)
    }

    /** Deterministic 0…1 from an index, so the sky is the same sky on every launch. */
    private fun hash(n: Double, salt: Double): Double {
        val v = sin(n * salt) * 43758.5453
        return v - floor(v)
    }

    /** The starfield. Thirty specks, each with its own size, brightness and rate. */
    private fun dust(g: PlateGc, sx: Double, sy: Double, s: Double, alpha: Double) {
        for (i in 0 until 30) {
            val n = i + 1.0
            val hx = hash(n, 12.9898); val hy = hash(n, 78.233); val hz = hash(n, 39.425)
            val side = if (hz < 0.62) 2.0 else (if (hz < 0.92) 3.0 else 4.0)
            val rate = 0.4 + 1.7 * hz
            val twinkle = max(0.0, 0.30 + 0.70 * sin(clock * rate + hy * 6.283))
            // The brightest few take a colour — a dot screen can hold that much.
            val tint = if (hz > 0.94) NB.ember1 else (if (hz > 0.88) NB.cyan1 else NB.white)
            g.fill(rectPath(hx * 358 * sx, hy * 470 * sy, side * s, side * s),
                   tint.op((0.13 + 0.36 * hz) * twinkle * alpha))
        }
    }

    /** Three slow washes of colour drifting behind everything, on periods that do not divide. */
    private fun nebula(g: PlateGc, size: Size, s: Double, alpha: Double) {
        val blobs = listOf(
            Triple(NB.run2, t(0.0, 61, 0.070), 0),
            Triple(NB.ember1, t(2.1, 83, 0.052), 0),
            Triple(NB.violet3, t(4.2, 71, 0.066), 0),
        )
        for ((tint, b, _) in blobs) {
            val tt = clock * 2 * PI / b[1] + b[0]
            val cx = (0.5 + 0.44 * sin(tt)) * size.width
            val cy = (0.44 + 0.38 * cos(tt * 0.7 + 1.3)) * size.height
            val r = 172 * s
            g.fill(oval(cx - r, cy - r, r * 2, r * 2),
                   radial(evenly(tint.op(b[2] * alpha), tint.op(0)), P(cx, cy), 0.0, r))
        }
    }

    /** Three lanes of shooting stars, on 7.3 / 11.9 / 17.1 seconds. */
    private fun meteor(g: PlateGc, lane: Int, sx: Double, sy: Double, s: Double, alpha: Double) {
        val specPeriod = listOf(7.3, 11.9, 17.1)
        val specFlight = listOf(0.9, 1.4, 1.1)
        val specTint = listOf(NB.limePale, NB.white, NB.ember1)
        val specWeight = listOf(1.4, 1.8, 1.5)
        val period = specPeriod[lane]; val flight = specFlight[lane]
        val tint = specTint[lane]; val weight = specWeight[lane]
        val cycle = floor(clock / period)
        val u = (clock - cycle * period) / flight
        if (!(u > 0 && u < 1)) return
        // A cheap hash of the cycle index, so no two passes share a path.
        val seed = hash(cycle + lane * 7 + 1, 12.9898)
        val drop = hash(cycle + lane * 7 + 1, 78.233)
        val y0 = -20 + 420 * seed
        val from = P(-40 * sx, y0 * sy)
        val to = P(420 * sx, (y0 + 60 + 220 * drop) * sy)
        fun at(p: Double) = P(from.x + (to.x - from.x) * p, from.y + (to.y - from.y) * p)
        val fade = sin(PI * u) * alpha
        // The tail is drawn in falling steps, so it thins out and dims behind the head.
        val steps = listOf(0.38 to 0.05, 0.22 to 0.11, 0.10 to 0.24, 0.0 to 0.55)
        val ends = listOf(0.11, 0.05, 0.0)
        for ((i, step) in steps.withIndex()) {
            val seg = Path().apply {
                move(at(max(0.0, u - step.first)))
                line(at(max(0.0, u - (if (i == 0) 0.22 else ends[i - 1]))))
            }
            g.stroke(seg, tint.op(step.second * fade), width = weight * s * (0.5 + 0.2 * (3 - i)),
                     cap = StrokeCap.Round)
        }
        dot(g, at(u), 2 * s, tint.op(0.85 * fade))
    }

    private fun arc(g: PlateGc, c: P, r: Double, from: Double, span: Double, width: Double, color: Color) {
        val path = Path().apply {
            arcTo(Rect((c.x - r).toFloat(), (c.y - r).toFloat(), (c.x + r).toFloat(), (c.y + r).toFloat()),
                  Math.toDegrees(from).toFloat(), Math.toDegrees(span).toFloat(), true)
        }
        g.stroke(path, color, width = width, cap = StrokeCap.Round)
    }

    private fun dot(g: PlateGc, at: P, r: Double, color: Color) {
        g.fill(oval(at.x - r, at.y - r, r * 2, r * 2), color)
    }
}

/**
 * The day's deep-space scene. Its clock advances only while the panel is visible;
 * Reduce Motion and navigation hold the current pose instead of resetting the scene.
 *
 * Paints `DeepSpacePlate` (the Home shell's AGSL port of the Metal shader) at this clock.
 */
@Composable
fun StandbyArt(
    /** Day-pool / event plate from `IdlePlateLock`. Ceremony does not pass this. */
    plate: Int = 1,
    /** 0…1 — kept so the charge cluster and any future lime band share one number. */
    charge: Double = 0.72,
    chargeKnown: Boolean = true,
    animate: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = rememberReduceMotion()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val state by lifecycle.currentStateAsState()
    val active = state.isAtLeast(Lifecycle.State.RESUMED)
    val context = LocalContext.current
    // Re-read on every resume, as iOS re-reads on the power-state notification.
    val lowPower = remember(active) {
        runCatching { context.getSystemService(PowerManager::class.java)?.isPowerSaveMode == true }
            .getOrDefault(false)
    }
    // Start just inside the scene's drift; pausing preserves this accumulated time.
    var clock by remember { mutableDoubleStateOf(0.45) }
    // Composition stands in for onAppear / onDisappear (visible).
    val moving = animate && !reduceMotion && active

    LaunchedEffect(moving, lowPower) {
        if (!moving) return@LaunchedEffect
        val interval = if (lowPower) 1.0 / 15 else 1.0 / 30
        var lastTick: Long? = null
        while (true) {
            withFrameNanos { now ->
                val previous = lastTick
                if (previous == null) {
                    lastTick = now
                } else {
                    val dt = (now - previous) / 1_000_000_000.0
                    if (dt >= interval - 0.002) {
                        lastTick = now
                        // A stalled frame cannot turn into a camera jump on the next draw.
                        clock += min(max(0.0, dt), 0.1)
                    }
                }
            }
        }
    }

    DeepSpacePlate(plate = plate, clock = clock, modifier = modifier)
}
