package com.nextbody.hoop.band

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin
import kotlin.math.sqrt

/** Clock-parameterized pose of one idle plate. Separate from Compose so two
 *  timestamps can be compared without an emulator. `clock` is on-screen seconds;
 *  one loop is one full revolution of every moon / pip, seamless at the seam. */
data class IdlePlatePose(
    /** Loop phase 0..<1 when moving; the hold pose when not. */
    var phase: Double,
    var breathe: Double,
    var ringDeg: Double,
    var dash: Double,
    var bodyX: Double,
    var bodyY: Double,
    var lightX: Double,
    /** Orbit progress 0..<1. Zero is the Paper rest seat of that plate's moon / pip. */
    var satellite: Double,
    var moonYaw: Double,
    var moonPitch: Double,
    var comet: Double,
    var glow: Double,
    var twinkle: Double,
) {
    /** Flattened samples the tests compare. Order is part of the contract. */
    val samples: List<Double>
        get() = listOf(phase, breathe, ringDeg, dash, bodyX, bodyY, lightX,
            satellite, moonYaw, moonPitch, comet, glow, twinkle)
}

/** One body on an inclined ellipse. `front` is the near half of the ring plane. */
data class IdleOrbit(val x: Double, val y: Double, val front: Boolean)

object IdlePlateMotion {
    /** One closed revolution. Long enough to read as orbit, short enough to see. */
    const val loopSeconds: Double = 8.0

    // MARK: - Motion grammar
    //
    // Same three rules the source art obeys (output/fx/render_loops.py, written up in
    // output/fx/PLATES.md):
    //   1. Nothing turns at a constant rate. A constant rate is a clock, and there is no clock
    //      in the sky: anything going round obeys Kepler's second law and visibly crawls at
    //      apoapsis, whips through periapsis.
    //   2. A ring does not rotate. Its tilt is fixed by the planet's spin axis, and its
    //      particles are on independent orbits, so it cannot turn as one rigid hoop. Dashes on
    //      an orbit track are tick marks, not a conveyor belt: they hold still.
    //   3. What changes in eight seconds of sky is light, not position -- and light is never a
    //      single sine.
    // Every term below is zero (or 1, for a multiplier) at t == 0, so the hold pose under
    // Reduce Motion is still exactly the Paper rest seat.

    /** Eccentricity of the idle orbits. */
    const val orbitEccentricity: Double = 0.45

    /** Where a body sits along its orbit, 0..<1, Kepler-paced: apoapsis is the Paper rest seat.
     *  Newton on M = E - e sinE. progress(0) == 0, progress(0.5) == 0.5, progress(1) == 1. */
    fun orbitProgress(t: Double, ecc: Double = orbitEccentricity): Double {
        val tau = PI * 2
        val m = tau * t + PI
        var e = m + ecc * sin(m)
        repeat(8) { e -= (e - ecc * sin(e) - m) / (1 - ecc * cos(e)) }
        return (e - PI) / tau
    }

    /** Brightness wobble: three harmonics with unrelated phases. Zero at t == 0 and at the seam. */
    fun flicker(t: Double, seed: Double): Double {
        val tau = PI * 2
        var v = 0.0
        listOf(0.58 to 1.0, 0.29 to 2.0, 0.13 to 3.0).forEachIndexed { i, wk ->
            val ph = (seed * 1.7 + i * 2.39).rem(tau)
            v += wk.first * (sin(tau * wk.second * t + ph) - sin(ph))
        }
        return v
    }

    /** Pose of `plate` at `clock` on-screen seconds. `moving: false` (Reduce Motion) freezes
     *  the hold pose so two clocks compare equal. */
    fun pose(plate: Int, clock: Double, moving: Boolean): IdlePlatePose {
        val t = if (moving) phase(clock) else 0.0
        return look(plate, t)
    }

    fun samples(plate: Int, clock: Double, moving: Boolean): List<Double> = pose(plate, clock, moving).samples

    fun phase(clock: Double): Double {
        val p = clock / loopSeconds
        return p - floor(p)
    }

    /** Ellipse through the Paper rest seat `(restX, restY)` around `(cx, cy)`.
     *  `flatten` is the minor-axis ratio (saturn rings ~0.25). `u == 0` is the rest seat. */
    fun around(cx: Double, cy: Double, restX: Double, restY: Double, flatten: Double, u: Double): IdleOrbit {
        val tau = PI * 2
        val wrap = u - floor(u)
        val ox = restX - cx
        val oy = restY - cy
        val bx = -oy * flatten
        val by = ox * flatten
        val c = cos(tau * wrap)
        val s = sin(tau * wrap)
        return IdleOrbit(x = cx + ox * c + bx * s, y = cy + oy * c + by * s, front = s >= 0)
    }

    /** Point at parameter `u` (0...1) on a Paper SVG elliptical arc. */
    fun svgArcPoint(
        x1: Double, y1: Double, rx: Double, ry: Double,
        deg: Double, large: Boolean, sweep: Boolean,
        x2: Double, y2: Double, u: Double,
    ): Pair<Double, Double> {
        val phi = deg * PI / 180
        val cosP = cos(phi); val sinP = sin(phi)
        val dx = (x1 - x2) / 2; val dy = (y1 - y2) / 2
        val x1p = cosP * dx + sinP * dy
        val y1p = -sinP * dx + cosP * dy
        var rxv = abs(rx); var ryv = abs(ry)
        val lambda = (x1p * x1p) / (rxv * rxv) + (y1p * y1p) / (ryv * ryv)
        if (lambda > 1) {
            val r = sqrt(lambda)
            rxv *= r; ryv *= r
        }
        val num = maxOf(0.0, rxv * rxv * ryv * ryv - rxv * rxv * y1p * y1p - ryv * ryv * x1p * x1p)
        val den = rxv * rxv * y1p * y1p + ryv * ryv * x1p * x1p
        var coef = sqrt(num / maxOf(den, 1e-12))
        if (large == sweep) coef = -coef
        val cxp = coef * rxv * y1p / ryv
        val cyp = coef * -ryv * x1p / rxv
        val cx = cosP * cxp - sinP * cyp + (x1 + x2) / 2
        val cy = sinP * cxp + cosP * cyp + (y1 + y2) / 2
        fun ang(ux: Double, uy: Double, vx: Double, vy: Double): Double {
            val sign = if (ux * vy - uy * vx < 0) -1.0 else 1.0
            val n = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            val c = maxOf(-1.0, minOf(1.0, (ux * vx + uy * vy) / maxOf(n, 1e-12)))
            return sign * acos(c)
        }
        val th1 = ang(1.0, 0.0, (x1p - cxp) / rxv, (y1p - cyp) / ryv)
        var dth = ang((x1p - cxp) / rxv, (y1p - cyp) / ryv, (-x1p - cxp) / rxv, (-y1p - cyp) / ryv)
        if (!sweep && dth > 0) dth -= PI * 2
        if (sweep && dth < 0) dth += PI * 2
        val th = th1 + dth * u
        val x = rxv * cos(th); val y = ryv * sin(th)
        return Pair(cx + x * cosP - y * sinP, cy + x * sinP + y * cosP)
    }

    /** Ride a visible SVG arc. `u == 0` is the Paper rest seat at `restU`. */
    fun alongArc(
        x1: Double, y1: Double, rx: Double, ry: Double,
        deg: Double, large: Boolean, sweep: Boolean,
        x2: Double, y2: Double,
        restU: Double, swing: Double, u: Double,
    ): IdleOrbit {
        val wrap = u - floor(u)
        val q = restU + swing * sin(PI * 2 * wrap)
        val p = svgArcPoint(x1, y1, rx, ry, deg, large, sweep, x2, y2, q)
        return IdleOrbit(x = p.first, y = p.second, front = sin(PI * 2 * wrap) >= 0)
    }

    private fun look(plate: Int, t: Double): IdlePlatePose {
        // dash 0: the ticks on an orbit track never move. satellite/comet are Kepler-paced,
        // not linear ramps. glow/breathe carry the plate's light.
        val p = IdlePlatePose(
            phase = t, breathe = 1 + 0.12 * flicker(t, plate + 40.0), ringDeg = 0.0, dash = 0.0,
            bodyX = 179.0, bodyY = 188.0, lightX = 0.0, satellite = orbitProgress(t),
            moonYaw = 0.0, moonPitch = 0.0, comet = orbitProgress(t, ecc = 0.8),
            glow = 1 + 0.16 * flicker(t, plate.toDouble()), twinkle = 0.0)
        p.twinkle = minOf(maxOf(0.5 + 0.5 * flicker(t, plate + 80.0), 0.0), 1.0)
        when (plate) {
            1 -> { p.ringDeg = -14.0; p.bodyY = 188.0 }
            2 -> {
                p.bodyX = 179.0; p.bodyY = 196.0; p.ringDeg = -18.0
                // lightX used to swing the highlight across the disc once a loop. A light source an
                // astronomical unit away does not swing in eight seconds; the libration carries it.
                p.moonYaw = sin(PI * 2 * t); p.moonPitch = sin(PI * 4 * t)
            }
            3 -> { p.ringDeg = -3.0; p.bodyY = 128.0 }
            4 -> p.ringDeg = -18.0
            5 -> { p.ringDeg = -22.0; p.bodyY = 178.0 }
            6 -> p.ringDeg = -28.0
            7 -> { p.ringDeg = -24.0; p.bodyY = 178.0 }
            8 -> { p.bodyX = 140.0; p.bodyY = 190.0; p.ringDeg = -22.0 }
            9 -> { p.bodyY = 190.0; p.ringDeg = 18.0 }
            10 -> {}
            11 -> { p.bodyX = 560.0; p.bodyY = 150.0 }
            12 -> { p.ringDeg = -2.0; p.bodyY = 188.0 }
            13 -> p.ringDeg = -32.0
            14 -> { p.bodyX = 179.0; p.bodyY = 195.0 }
            15 -> p.ringDeg = -6.0
            16 -> p.ringDeg = -8.0
            17 -> p.ringDeg = -12.0
            18 -> {}
            19 -> p.ringDeg = -13.0
            20 -> { p.bodyX = 298.0; p.bodyY = 195.0; p.ringDeg = -12.0 }
            21 -> { p.bodyX = -60.0; p.bodyY = 240.0 }
            22 -> { p.ringDeg = -2.0; p.bodyY = 188.0 }
            23 -> {
                p.bodyX = 179.0; p.bodyY = 250.0; p.ringDeg = -16.0
                // libration: yaw once a loop, pitch twice, both zero at the rest seat. The pair
                // traces a figure eight, which is the path a real libration draws.
                p.moonYaw = sin(PI * 2 * t); p.moonPitch = sin(PI * 4 * t)
            }
            24 -> {}
            25 -> p.ringDeg = -4.0
            26 -> { p.bodyX = 250.0; p.bodyY = 230.0; p.ringDeg = -18.0 }
            27 -> {}
            28 -> p.ringDeg = 0.0
            else -> {}
        }
        return p
    }
}
