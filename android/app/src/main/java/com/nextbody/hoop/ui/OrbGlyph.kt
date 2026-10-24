package com.nextbody.hoop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * A ball of dots for the dock's right key. Two Fibonacci shells: the outer one turns one way
 * and draws in, the inner one turns the other way and swells out to meet it, and both land in
 * a single depth sort so an inner dot can paint over an outer one. That single sort is the
 * whole reason it reads as a volume rather than as a spray of dots.
 *
 * Ported from the Originkit "Particle Interlock" reference; its accent is `NB.lime1`.
 *
 * @param density 1 = the reference's 90 + 60 dots; 2.43 makes the shells read as shells at 32.
 * @param dotSize the reference's 1.5 only welds the discs shut at glyph size.
 * @param speed signed; half speed — a ten-second loop — so the key does not pull the eye down.
 * @param spinTurns extra whole turns per loop; whole numbers keep the loop seamless.
 */
@Composable
fun OrbGlyph(
    modifier: Modifier = Modifier,
    side: Dp = 32.dp,
    dot: Color = NB.iconInk,
    accent: Color = NB.lime1,
    density: Double = 2.43,
    dotSize: Double = 1.0,
    speed: Double = 0.5,
    spinTurns: Double = 1.0,
    spread: Double = 1.0,
    turn: Double = 0.0,
    tilt: Double = 0.0,
) {
    val clock = rememberFrameClock(true)
    Canvas(modifier.size(side)) {
        // Work in dp so the ball matches the iOS point geometry; draw in px.
        val px = 1.dp.toPx()
        val s = min(size.width, size.height) / px.toDouble()
        val bx = (size.width / px - s) / 2
        val by = (size.height / px - s) / 2
        val half = s / 2
        // Wrapped rather than left to accumulate: an unbounded clock costs float precision.
        var phase = (clock * speed / ORB_PERIOD) % 1.0
        if (phase < 0) phase += 1.0

        val p = OrbParams(density, spread, orbDotScale(s) * dotSize, turn, tilt, spinTurns, phase)
        val fit = OrbFitCache.value(s, p)
        val pts = ArrayList<OrbSpeck>((160 * density).toInt() + 8)
        orbFrame(phase, density, pts)

        for (d in orbProject(pts, s, p)) {
            // The fit scales positions about the centre and radii by a gentler factor.
            val rr = d.r * (0.55 + 0.45 * fit)
            if (rr <= 0.05 || d.a <= 0.004) continue
            var dr = rr
            var da = min(1.0, d.a)
            // A floor on the disc, alpha scaled by the area it would otherwise have lost:
            // the back of the ball is where the depth cue lives, and those dots are sub-pixel.
            if (dr < ORB_MIN_RADIUS) {
                da *= (dr / ORB_MIN_RADIUS) * (dr / ORB_MIN_RADIUS)
                dr = ORB_MIN_RADIUS
            }
            val cx = bx + half + (d.x - half) * fit
            val cy = by + half + (d.y - half) * fit
            drawCircle(
                (if (d.accent) accent else dot).copy(alpha = (if (d.accent) accent else dot).alpha * da.toFloat()),
                radius = (dr * px).toFloat(),
                center = Offset((cx * px).toFloat(), (cy * px).toFloat()),
            )
        }
    }
}

// MARK: - The ball

private const val ORB_PERIOD = 5.0 // seconds for one loop at speed 1
private const val ORB_BASE_SPREAD = 0.3 // sphere radius as a fraction of the ball box
private const val ORB_PERSPECTIVE = 3.5 // camera distance in ball radii
private const val ORB_MIN_RADIUS = 0.6
private const val TAU = PI * 2

data class OrbParams(
    val density: Double,
    val spread: Double,
    val dotScale: Double,
    val yaw: Double,
    val pitch: Double,
    val spinTurns: Double,
    val phase: Double,
)

class OrbSpeck(val x: Double, val y: Double, val z: Double, val rScale: Double, val aScale: Double, val accent: Boolean)

private class OrbDisc(val x: Double, val y: Double, val r: Double, val a: Double, val z: Double, val accent: Boolean)

private class V3(val x: Double, val y: Double, val z: Double)

/** Fibonacci sphere: even coverage with no poles and no seam. */
private fun orbFib(i: Int, n: Int): V3 {
    val y = 1 - (i.toDouble() / max(1, n - 1).toDouble()) * 2
    val r = sqrt(max(0.0, 1 - y * y))
    val th = 2.399963 * i
    return V3(cos(th) * r, y, sin(th) * r)
}

/** Yaw about the vertical axis, then pitch. */
private fun orbSpin(p: V3, yaw: Double, pitch: Double): V3 {
    val ca = cos(yaw)
    val sa = sin(yaw)
    val rx = p.x * ca - p.z * sa
    var rz = p.x * sa + p.z * ca
    val co = cos(pitch)
    val so = sin(pitch)
    val ry = p.y * co - rz * so
    rz = p.y * so + rz * co
    return V3(rx, ry, rz)
}

/** The loop itself — the only part of this file that is "interlock". */
private fun orbFrame(t: Double, n: Double, out: MutableList<OrbSpeck>) {
    val k = 0.5 - 0.5 * cos(TAU * t)
    // Outer shell: turning one way, drawing in.
    val outer = max(1, (90 * n).roundToInt())
    for (i in 0 until outer) {
        val q = orbSpin(orbFib(i, outer), TAU * t, 0.36)
        val s = 1 - 0.22 * k
        out.add(OrbSpeck(q.x * s, q.y * s, q.z * s, 0.85, 0.85, false))
    }
    // Inner shell: the other way, swelling out to meet it.
    val inner = max(1, (60 * n).roundToInt())
    for (i in 0 until inner) {
        val q = orbSpin(orbFib(i, inner), -TAU * t, 0.36)
        val s = 0.45 + 0.3 * k
        out.add(OrbSpeck(q.x * s, q.y * s, q.z * s, 0.9, 1.0, true))
    }
}

/** Rotate, project, sort back to front. */
private fun orbProject(pts: List<OrbSpeck>, size: Double, p: OrbParams): List<OrbDisc> {
    val c = size / 2
    val radius = size * ORB_BASE_SPREAD * p.spread
    val pv = ORB_PERSPECTIVE
    val yaw = p.yaw + TAU * p.spinTurns * p.phase
    val out = ArrayList<OrbDisc>(pts.size)
    for (pt in pts) {
        val q = orbSpin(V3(pt.x, pt.y, pt.z), yaw, p.pitch)
        val z = q.z
        val s = pv / (pv - z)
        val f = min(1.0, max(0.0, (z + 1.1) / 2.2))
        out.add(
            OrbDisc(
                x = c + q.x * radius * s,
                y = c + q.y * radius * s,
                r = p.dotScale * (0.4 + 1.6 * f) * s * pt.rScale,
                a = (0.07 + 0.93 * f.pow(1.55)) * pt.aScale,
                z = z,
                accent = pt.accent,
            ),
        )
    }
    out.sortBy { it.z }
    return out
}

/**
 * Ball size to dot scale, in three segments. Deliberately not linear: a ball twice the size
 * gets dots well under twice the radius, so it reads as denser rather than as a zoom.
 */
private fun orbDotScale(size: Double): Double = when {
    size <= 46 -> 0.4
    size <= 190 -> 0.4 + ((size - 46) / 144) * 0.6
    size <= 340 -> 1 + ((size - 190) / 150) * 0.55
    else -> 1.55
}

/** The fit is twenty frames of work and only changes when the ball does: measured once per shape. */
object OrbFitCache {
    private val store = HashMap<String, Double>()

    fun value(size: Double, p: OrbParams): Double {
        // Phase is not part of the key: the fit is the maximum over the whole loop.
        val key = "$size/${p.density}/${p.spread}/${p.yaw}/${p.pitch}/${p.spinTurns}"
        return store.getOrPut(key) { orbFit(size, p) }
    }
}

/** Sample the loop at twenty phases, measure how far out it throws a dot, normalise to the box. */
fun orbFit(size: Double, base: OrbParams): Double {
    val half = size / 2
    var ext = 0.0
    for (k in 0 until 20) {
        val probe = base.copy(dotScale = 1.0, phase = k / 20.0)
        val pts = ArrayList<OrbSpeck>()
        orbFrame(probe.phase, probe.density, pts)
        for (d in orbProject(pts, size, probe)) {
            if (d.a > 0.05 && d.r > 0.15) {
                ext = max(ext, max(abs(d.x - half) + 0.5 * d.r, abs(d.y - half) + 0.5 * d.r))
            }
        }
    }
    return if (ext > 1) min(1.7, max(0.55, 0.415 * size / ext)) else 1.0
}
