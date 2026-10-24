package com.nextbody.hoop.features.home.panel

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import com.nextbody.hoop.band.IdleOrbit
import com.nextbody.hoop.band.IdlePlateMotion
import com.nextbody.hoop.band.IdlePlatePose
import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * A SwiftUI `GraphicsContext` over a Compose [DrawScope], so the idle-plate recipes read
 * 1:1 with the Swift. `layer {}` is `drawLayer` (save / restore of transform and clip —
 * the Swift layers never set opacity, blend or filters, so a canvas save is exact).
 * Geometry is Double throughout (CGFloat), converted to Float at the draw call.
 */
internal class PlateGc(val ds: DrawScope) {
    private val canvas get() = ds.drawContext.canvas

    fun fill(path: Path, color: Color) = ds.drawPath(path, color)
    fun fill(path: Path, brush: Brush) = ds.drawPath(path, brush)

    fun stroke(path: Path, color: Color, width: Double, cap: StrokeCap = StrokeCap.Butt,
               dash: List<Double>? = null, phase: Double = 0.0) =
        ds.drawPath(path, color, style = style(width, cap, dash, phase))

    fun stroke(path: Path, brush: Brush, width: Double, cap: StrokeCap = StrokeCap.Butt,
               dash: List<Double>? = null, phase: Double = 0.0) =
        ds.drawPath(path, brush, style = style(width, cap, dash, phase))

    private fun style(width: Double, cap: StrokeCap, dash: List<Double>?, phase: Double): Stroke {
        val effect = dash?.takeIf { it.isNotEmpty() }?.let { d ->
            val even = if (d.size % 2 == 1) d + d else d
            PathEffect.dashPathEffect(even.map { it.toFloat() }.toFloatArray(), phase.toFloat())
        }
        return Stroke(width = width.toFloat(), cap = cap, pathEffect = effect)
    }

    inline fun layer(block: () -> Unit) {
        ds.drawContext.canvas.save()
        try { block() } finally { ds.drawContext.canvas.restore() }
    }

    fun translate(x: Double, y: Double) = canvas.translate(x.toFloat(), y.toFloat())
    /** Degrees, clockwise on screen — SwiftUI's `rotate(by: .degrees(_))`. */
    fun rotate(deg: Double) = canvas.rotate(deg.toFloat())
    fun clip(path: Path) = canvas.clipPath(path)
}

/** CGPoint. */
internal class P(val x: Double, val y: Double) {
    val offset: Offset get() = Offset(x.toFloat(), y.toFloat())
}
internal fun P(x: Number, y: Number): P = P(x.toDouble(), y.toDouble())

internal val Number.d: Double get() = toDouble()

/** `Color(hex:opacity:)` with full float alpha precision (the plates use 0.025-level alphas). */
internal fun col(rgb: Int, a: Number = 1.0): Color = Color(
    red = ((rgb shr 16) and 0xFF) / 255f,
    green = ((rgb shr 8) and 0xFF) / 255f,
    blue = (rgb and 0xFF) / 255f,
    alpha = a.toFloat().coerceIn(0f, 1f),
)
internal fun white(a: Number): Color = Color(1f, 1f, 1f, a.toFloat().coerceIn(0f, 1f))
internal fun black(a: Number): Color = Color(0f, 0f, 0f, a.toFloat().coerceIn(0f, 1f))
internal fun Color.op(a: Number): Color = copy(alpha = (alpha * a.toFloat()).coerceIn(0f, 1f))

/** A Swift tuple of numbers. */
internal fun t(vararg v: Number): DoubleArray = DoubleArray(v.size) { v[it].toDouble() }
/** One gradient stop. */
internal fun ws(loc: Number, c: Color): Pair<Double, Color> = loc.toDouble() to c
/** `Gradient(colors:)` — evenly spaced. */
internal fun evenly(a: Color, b: Color): List<Pair<Double, Color>> = listOf(0.0 to a, 1.0 to b)
internal fun evenly(a: Color, b: Color, c: Color): List<Pair<Double, Color>> =
    listOf(0.0 to a, 0.5 to b, 1.0 to c)

/** `Path(ellipseIn:)`. */
internal fun oval(x: Number, y: Number, w: Number, h: Number): Path = Path().apply {
    addOval(Rect(x.toFloat(), y.toFloat(), x.toFloat() + w.toFloat(), y.toFloat() + h.toFloat()))
}
/** `Path(CGRect)`. */
internal fun rectPath(x: Number, y: Number, w: Number, h: Number): Path = Path().apply {
    addRect(Rect(x.toFloat(), y.toFloat(), x.toFloat() + w.toFloat(), y.toFloat() + h.toFloat()))
}
internal fun Path.move(p: P) = moveTo(p.x.toFloat(), p.y.toFloat())
internal fun Path.line(p: P) = lineTo(p.x.toFloat(), p.y.toFloat())

/**
 * `.radialGradient(_, center:, startRadius:, endRadius:)`. Compose has no start radius, so
 * the stops are remapped into [start/end, 1] — inside the start radius is the first colour,
 * which is what SwiftUI paints there too.
 */
internal fun radial(stops: List<Pair<Double, Color>>, center: P, start: Double, end: Double): Brush {
    val e = max(end, 0.001)
    val st = (start / e).coerceIn(0.0, 1.0)
    val mapped = stops.map { (st + it.first.coerceIn(0.0, 1.0) * (1 - st)).toFloat() to it.second }
    val safe = if (mapped.size == 1) listOf(0f to mapped[0].second, 1f to mapped[0].second) else mapped
    return Brush.radialGradient(*safe.toTypedArray(), center = center.offset, radius = e.toFloat())
}

/** `.linearGradient(_, startPoint:, endPoint:)`. */
internal fun linear(stops: List<Pair<Double, Color>>, from: P, to: P): Brush =
    Brush.linearGradient(*stops.map { it.first.toFloat() to it.second }.toTypedArray(),
        start = from.offset, end = to.offset)

/**
 * Clock-driven draw of one idle plate. Geometry and ramps come from Paper
 * `V-1`. Pose comes from `IdlePlateMotion` so the field the tests sample
 * is the field the panel paints. Moons and pips ride closed ellipses
 * (`pose.satellite`); they do not pulse in place.
 *
 * On top of the 1:1 recipe: a second atmosphere bloom, a tight specular,
 * hashed surface grain, and a limb rim — still the same body, just more
 * light on it. The planet does not breathe in size.
 *
 * Port note: the iOS idle panel paints `DeepSpacePlate` (a Metal shader); this Canvas
 * recipe is kept 1:1 and is what `StandbyArt` falls back to on Android.
 */
@Suppress("UNUSED_PARAMETER", "unused", "SameParameterValue")
object IdlePlateArt {
    val board = Size(358f, 470f)

    fun draw(plate: Int, pose: IdlePlatePose, charge: Double, chargeKnown: Boolean,
             ds: DrawScope, size: Size = ds.size) {
        val g = PlateGc(ds)
        val sx = size.width.toDouble() / board.width
        val sy = size.height.toDouble() / board.height
        val s = min(sx, sy)
        wash(g, size, plate)
        galaxy(g, plate, pose, size, s, sx, sy)
        look(plate, pose, g, size, s, sx, sy)
        filmGrain(g, size, plate)
        vignette(g, size)
    }

    private fun look(plate: Int, pose: IdlePlatePose, g: PlateGc, size: Size,
                     s: Double, sx: Double, sy: Double) {
        when (plate) {
            1 -> plate01(g, pose, s, sx, sy)
            2 -> plate02(g, pose, s, sx, sy)
            3 -> plate03(g, pose, s, sx, sy)
            4 -> plate04(g, pose, s, sx, sy)
            5 -> plate05(g, pose, s, sx, sy)
            6 -> plate06(g, pose, s, sx, sy)
            7 -> plate07(g, pose, s, sx, sy)
            8 -> plate08(g, pose, s, sx, sy)
            9 -> plate09(g, pose, s, sx, sy)
            10 -> plate10(g, pose, s, sx, sy)
            11 -> plate11(g, pose, s, sx, sy)
            12 -> plate12(g, pose, s, sx, sy)
            13 -> plate13(g, pose, s, sx, sy)
            14 -> plate14(g, pose, s, sx, sy)
            15 -> plate15(g, pose, s, sx, sy)
            16 -> plate16(g, pose, s, sx, sy)
            17 -> plate17(g, pose, s, sx, sy)
            18 -> plate18(g, pose, s, sx, sy)
            19 -> plate19(g, pose, s, sx, sy)
            20 -> plate20(g, pose, s, sx, sy)
            21 -> plate21(g, pose, s, sx, sy)
            22 -> plate22(g, pose, s, sx, sy)
            23 -> plate23(g, pose, s, sx, sy)
            24 -> plate24(g, pose, s, sx, sy)
            25 -> plate25(g, pose, s, sx, sy)
            26 -> plate26(g, pose, s, sx, sy)
            27 -> plate27(g, pose, s, sx, sy)
            28 -> plate28(g, pose, s, sx, sy)
            else -> {
                saturn(g, pose = pose, s = s, sx = sx, sy = sy,
                       cx = 179, cy = 188, r = 74, hx = 150, hy = 160,
                       stops = listOf(t(0, 0xF7EFDD), t(0.4, 0xDCCBA6), t(0.7, 0x8A7A58), t(1, 0x1E1A12)),
                       air = 0x6B5B3A, airA = 0.30,
                       ringRX = 126, ringRY = 34, ringDeg = -14,
                       ring = 0xE8D9B0, dust = 0xC9B68C, gap = 8, wide = 0)
                stars(g, pose = pose, s = s, sx = sx, sy = sy, seed = 100, n = 5)
            }
        }
    }

    // MARK: sky

    private val tints: Map<Int, Int> = mapOf(
        1 to 0x3A2E1A, 3 to 0x1E2E38, 4 to 0x16202A, 5 to 0x241F14,
        6 to 0x141C26, 7 to 0x14202E, 8 to 0x262216, 9 to 0x1E1C16,
        10 to 0x101820, 11 to 0x18222A, 12 to 0x101014, 13 to 0x12202E,
        14 to 0x14181E, 15 to 0x2A0E06, 16 to 0x0B1E3F, 17 to 0x1A1030,
        18 to 0x260A1E, 19 to 0x181422, 20 to 0x0A1626, 21 to 0x0A1830,
        22 to 0x201C10, 24 to 0x0A1626, 25 to 0x200A04, 26 to 0x141233,
        27 to 0x12161E, 28 to 0x101820,
    )

    private val galaxyBand: Map<Int, DoubleArray> = mapOf(
        1 to t(-22, 120, 1.0), 2 to t(-22, 235, 1.0), 3 to t(-16, 300, 1.0),
        4 to t(-24, 235, 0.8), 5 to t(-30, 235, 1.0), 6 to t(35, 190, 0.9),
        7 to t(-24, 235, 1.0), 8 to t(-21, 235, 0.22), 9 to t(38, 215, 0.9),
        10 to t(-38, 230, 0.40), 11 to t(-8, 300, 1.0), 12 to t(-2, 235, 0.55),
        13 to t(-36, 215, 0.22), 14 to t(44, 224, 0.6), 15 to t(-6, 150, 0.7),
        16 to t(-28, 235, 0.40), 17 to t(-12, 235, 0.55), 18 to t(-30, 205, 0.55),
        19 to t(-14, 235, 0.9), 20 to t(-20, 235, 1.0), 21 to t(-10, 235, 0.45),
        22 to t(-4, 110, 1.0), 23 to t(-20, 105, 1.1), 24 to t(8, 235, 0.35),
        25 to t(-12, 150, 0.35), 26 to t(-18, 235, 1.0), 27 to t(-32, 235, 0.6),
        28 to t(0, 235, 0.9),
    )

    private fun wash(g: PlateGc, size: Size, plate: Int) {
        val w = size.width.toDouble(); val h = size.height.toDouble()
        g.fill(rectPath(0, 0, w, h), col(0x070709))
        val mid = P(w * 0.5, h * 0.42)
        g.fill(oval(mid.x - w, mid.y - h, w * 2, h * 2),
               radial(evenly(col(0x0B0B0D), col(0x070709)), mid, 0.0, w * 0.85))
        tints[plate]?.let { tint ->
            val r = w * 0.55
            g.fill(oval(mid.x - r, mid.y - r, r * 2, r * 2),
                   radial(evenly(col(tint, 0.16), col(tint, 0)), mid, 0.0, r))
        }
    }

    private fun galaxy(g: PlateGc, plate: Int, pose: IdlePlatePose, size: Size,
                       s: Double, sx: Double, sy: Double) {
        val band = galaxyBand[plate] ?: t(-18, 235, 0.85)
        val deg = band[0] * PI / 180
        val ca = cos(deg); val sa = sin(deg)
        val cy = band[1]
        val alpha = band[2]
        for (i in 0 until 52) {
            val n = (i + plate * 17 + 1).toDouble()
            val u = (hash(n, 12.9898) - 0.5) * 560
            val v = (hash(n, 78.233) - 0.5) * 110
            val x = 179 + u * ca - v * sa
            val y = cy + u * sa + v * ca
            if (!(x > 6 && x < 352 && y > 8 && y < 300)) continue
            val near = exp(-0.5 * (v / 64) * (v / 64))
            val k = 1.0 + (i % 2)
            val ph = (i / 2 % 3) * (PI * 2 / 3)
            val tw = 0.55 + 0.45 * sin(pose.phase * PI * 2 * k + ph)
            val r = (0.85 + 0.7 * hash(n, 39.425)) * s
            val c = if (hash(n, 57.117) > 0.66) 0xCFE4FF
                else (if (hash(n, 57.117) > 0.33) 0xFFE9C9 else 0xE8DDFF)
            val a = (0.06 + 0.14 * near) * tw * alpha
            fillDot(g, at = P(x * sx, y * sy), r = r, rgb = c, a = a)
        }
        val dust = listOf(t(-130, 150, 30, 0.05), t(10, 170, 40, 0.06), t(140, 140, 28, 0.04))
        for (d in dust) {
            val x = 179 + d[0] * ca
            val y = cy + d[0] * sa
            glow(g, at = P(x * sx, y * sy), rx = d[1] * s, ry = d[2] * s, rgb = 0x8A8AA8,
                 a = d[3] * alpha, deg = band[0])
        }
    }

    private fun vignette(g: PlateGc, size: Size) {
        val w = size.width.toDouble(); val h = size.height.toDouble()
        g.fill(rectPath(0, 0, w, h),
               radial(listOf(ws(0.52, black(0)), ws(0.82, black(0.28)), ws(1, black(0.58))),
                      P(w / 2, h * 0.40), 0.0, w * 0.82))
    }

    /** Paper plate overlays `1YSM69…` / `1ZRG6HM…` — hashed film, not a texture asset. */
    private fun filmGrain(g: PlateGc, size: Size, plate: Int) {
        val rng = PlateRNG(1700 + plate * 37)
        val sx = size.width.toDouble() / board.width
        val sy = size.height.toDouble() / board.height
        val s = min(sx, sy)
        repeat(900) {
            val p = P(rng.uniform(0.0, board.width.toDouble()) * sx,
                      rng.uniform(0.0, board.height.toDouble()) * sy)
            val light = rng.next() > 0.50
            fillDot(g, at = p, r = rng.uniform(0.22, 0.55) * s,
                    rgb = if (light) 0xF2EEE4 else 0x000000,
                    a = rng.uniform(0.025, 0.07))
        }
    }

    // MARK: planet

    private fun plate01(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 188 * sy)
        val moon = ride(pose, cx = 179, cy = 188, restX = 289.5, restY = 217.5, flatten = 0.28)
        glow(g, at = c, rx = 130 * s, ry = 130 * s, rgb = 0xC9B68C, a = 0.22 * pose.glow)
        glow(g, at = c, rx = 92 * s, ry = 80 * s, rgb = 0x6B5B3A, a = 0.28 * pose.glow)
        riderMoon(g, o = moon, front = false, cx = 179, cy = 188, occlude = 82,
                  s = s, sx = sx, sy = sy, r = 3.5)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = true, bands = listOf(
            t(136, 34, 14, 0.16, 0xD9C69A),
            t(150, 38, 1.6, 0.34, 0xE8D9B0),
            t(158, 40, 1.2, 0.22, 0xD9C69A),
            t(167, 42.3, 1.0, 0.12, 0xD9C69A),
        ))
        sphere(g, c = c, r = 82 * s, hx = 146 * sx, hy = 149 * sy,
               stops = listOf(t(0, 0xFFF8EC), t(0.14, 0xF7EFDD), t(0.32, 0xE8D9B0),
                       t(0.50, 0xDCCBA6), t(0.66, 0x8A7A58), t(0.82, 0x3A3224),
                       t(1, 0x1E1A12)),
               air = 0xC9B68C, airA = 0.18, speckle = 0.14, specA = 0.10, nightA = 0.28,
               limbA = 0)
        ringShadow(g, c = c, r = 82 * s, rx = 150 * s, ry = 38 * s,
                   deg = pose.ringDeg, rgb = 0x050403, a = 0.18)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = false, bands = listOf(
            t(136, 34, 12, 0.24, 0xE8D9B0),
            t(150, 38, 1.7, 0.90, 0xF5EBCD),
            t(158, 40, 1.25, 0.55, 0xF5EBCD),
            t(167, 42.3, 1.0, 0.32, 0xF5EBCD),
        ))
        ansaGlow(g, c = c, rx = 150 * s, ry = 38 * s, deg = pose.ringDeg,
                 pose = pose, s = s, rgb = 0xFFF6D6)
        riderMoon(g, o = moon, front = true, cx = 179, cy = 188, occlude = 82,
                  s = s, sx = sx, sy = sy, r = 3.5)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(46, 58, 1.25, 0xFFFAEB, 0.78),
            t(298, 44, 0.95, 0xFFE9C9, 0.58),
            t(328, 238, 1.05, 0xCFE4FF, 0.42),
            t(28, 268, 0.85, 0xFFFAEB, 0.36),
            t(244, 28, 0.85, 0xFFFAEB, 0.52),
            t(118, 36, 1.05, 0xFFE9C9, 0.34),
            t(64, 168, 0.70, 0xFFFAEB, 0.30),
            t(292, 318, 0.70, 0xCFE4FF, 0.26),
            t(196, 52, 0.60, 0xFFFAEB, 0.28),
            t(14, 142, 0.65, 0xFFE9C9, 0.32),
        ), flares = listOf(t(78, 88, 5.2, 0xFFFCF0, 0.92), t(312, 118, 4.0, 0xCFE4FF, 0.70)))
    }

    // Moon in the field, not a 320px balloon on the glass. Soft night
    // ramp, walking terminator, dust ring, and a shepherd.
    private fun plate02(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val cx = pose.bodyX; val cy = pose.bodyY
        val c = P(cx * sx, cy * sy)
        val pr = 92 * s
        val moon = ride(pose, cx = cx, cy = cy, restX = 292, restY = 168, flatten = 0.30)
        val hx = (cx - 34 + pose.lightX * 26) * sx
        val hy = (cy - 30 - pose.moonPitch * 3) * sy
        haloRing(g, at = c, r = 148 * s, rgb = 0xD6E4FF,
                 stops = listOf(t(0.70, 0), t(0.78, 0.10),
                         t(0.88, 0.04), t(1, 0)))
        orbitGuide(g, cx = cx, cy = cy, restX = 292, restY = 168,
                   flatten = 0.30, s = s, sx = sx, sy = sy, rgb = 0xD8E0EC, a = 0.16)
        riderMoon(g, o = moon, front = false, cx = cx, cy = cy, occlude = 92,
                  s = s, sx = sx, sy = sy, r = 4.2, rgb = 0xE8E4D8)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = true, bands = listOf(
            t(128, 34, 16, 0.08, 0xC8D0DC),
            t(142, 38, 1.4, 0.20, 0xD8E0EC),
            t(150, 40, 1.0, 0.12, 0xC8D0DC),
        ))
        softBall(g, c = c, r = pr, hx = c.x, hy = c.y - 12 * sy, stops = listOf(
            t(0, 0xC8C8C0, 0.28),
            t(0.38, 0x8A8A84, 0.18),
            t(0.68, 0x4A4A48, 0.08),
            t(1, 0x070709, 0),
        ))
        softBall(g, c = c, r = pr * 0.86, hx = hx, hy = hy, stops = listOf(
            t(0, 0xF0F0E8, 0.30),
            t(0.34, 0xB8B8B0, 0.14),
            t(0.70, 0x6A6A68, 0.05),
            t(1, 0x070709, 0),
        ))
        paperCraters(g, origin = P((cx - 92) * sx, (cy - 92) * sy),
                     disc = c, r = pr, s = s, sx = sx, sy = sy,
                     shiftX = pose.moonYaw * 1.2 * sx, shiftY = -pose.moonPitch * 0.8 * sy,
                     mares = listOf(t(28, 48, 78, 56, 0.12), t(70, 96, 64, 46, 0.10)),
                     pits = listOf(t(48, 42, 22, 0.11), t(102, 58, 16, 0.09),
                            t(36, 98, 26, 0.10), t(86, 118, 18, 0.08),
                            t(124, 36, 14, 0.09), t(18, 68, 14, 0.08),
                            t(60, 80, 10, 0.07), t(110, 92, 9, 0.06)))
        featherRim(g, c = c, r = pr, rgb = 0x070709, inner = 0.78, pad = 1.0)
        ringShadow(g, c = c, r = pr, rx = 142 * s, ry = 38 * s,
                   deg = pose.ringDeg, rgb = 0x050508, a = 0.16)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = false, bands = listOf(
            t(128, 34, 14, 0.14, 0xE4EAF2),
            t(142, 38, 1.55, 0.62, 0xF2F6FC),
            t(150, 40, 1.1, 0.32, 0xE4EAF2),
        ))
        ansaGlow(g, c = c, rx = 142 * s, ry = 38 * s, deg = pose.ringDeg,
                 pose = pose, s = s, rgb = 0xF6F8FF)
        riderMoon(g, o = moon, front = true, cx = cx, cy = cy, occlude = 92,
                  s = s, sx = sx, sy = sy, r = 4.2, rgb = 0xE8E4D8)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(40, 30, 1.3, 0xFFFCF0, 0.75), t(320, 24, 1.0, 0xFFFCF0, 0.55),
            t(344, 150, 1.2, 0xCFE4FF, 0.60), t(14, 180, 1.0, 0xFFFCF0, 0.40),
            t(70, 380, 1.0, 0xFFFCF0, 0.35), t(330, 420, 1.1, 0xCFE4FF, 0.40),
            t(296, 392, 0.8, 0xFFFCF0, 0.30), t(24, 90, 0.9, 0xFFFCF0, 0.38),
            t(150, 18, 0.8, 0xFFFCF0, 0.45), t(250, 430, 0.8, 0xCFE4FF, 0.28),
            t(88, 48, 0.7, 0xFFE9C9, 0.36), t(268, 56, 0.75, 0xFFFCF0, 0.34),
            t(312, 280, 0.7, 0xCFE4FF, 0.26), t(48, 310, 0.65, 0xFFFCF0, 0.24),
        ), flares = listOf(t(58, 96, 5.0, 0xFFFCF0, 0.90), t(328, 84, 4.0, 0xCFE4FF, 0.60)))
    }

    // Paper `223M-1` · 156px ice ball at 101/50, rings −3°.
    private fun plate03(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 128 * sy)
        val moon = ride(pose, cx = 179, cy = 128, restX = 334, restY = 128, flatten = 0.12)
        glow(g, at = P(179 * sx, 128 * sy),
             rx = 110 * s, ry = 110 * s, rgb = 0xC9D6DC, a = 0.22 * pose.glow)
        glow(g, at = P(179 * sx, 50 * sy),
             rx = 110 * s, ry = 90 * s, rgb = 0xF4F8FA, a = 0.10 * pose.glow)
        riderMoon(g, o = moon, front = false, cx = 179, cy = 128, occlude = 78,
                  s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xE8F0F4)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = true, bands = listOf(
            t(140, 17, 10, 0.14, 0xC9D6DC),
            t(155, 19, 1.5, 0.32, 0xC9D6DC),
            t(163, 20, 1.15, 0.20, 0xC9D6DC),
            t(171, 21, 1.0, 0.12, 0xC9D6DC),
        ))
        sphere(g, c = c, r = 78 * s, hx = 151 * sx, hy = 91 * sy,
               stops = listOf(t(0, 0xF8FBFC), t(0.16, 0xF0F4F6), t(0.38, 0xCFD8DC),
                       t(0.60, 0x85939C), t(0.80, 0x3D4A52), t(1, 0x101418)),
               air = 0x3E5462, airA = 0.22, speckle = 0.12, specA = 0.28, nightA = 0.58)
        paperHighlight(g, at = P(150 * sx, 82 * sy),
                       rx = 18 * s, ry = 10 * s, deg = -22, a = 0.22)
        ringShadow(g, c = c, r = 78 * s, rx = 155 * s, ry = 19 * s,
                   deg = pose.ringDeg, rgb = 0x05080A, a = 0.16)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = false, bands = listOf(
            t(140, 17, 9, 0.20, 0xE8F0F4),
            t(155, 19, 1.6, 0.88, 0xE8F0F4),
            t(163, 20, 1.2, 0.50, 0xE8F0F4),
            t(171, 21, 1.0, 0.28, 0xE8F0F4),
        ))
        ansaGlow(g, c = c, rx = 155 * s, ry = 19 * s, deg = pose.ringDeg,
                 pose = pose, s = s, rgb = 0xF4FBFF)
        riderMoon(g, o = moon, front = true, cx = 179, cy = 128, occlude = 78,
                  s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xE8F0F4)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(52, 48, 1.2, 0xFFFAEE, 0.50), t(312, 36, 1.0, 0xFFFAEE, 0.40),
            t(336, 230, 1.1, 0xFFFAEE, 0.35), t(26, 270, 1.0, 0xFFFAEE, 0.40),
            t(150, 26, 1.2, 0xFFFAEE, 0.45), t(270, 290, 1.0, 0xFFFAEE, 0.30),
        ), flares = listOf())
    }

    // Paper `224E-1` · seven independent elliptical arcs, no planet.
    private fun plate04(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        glow(g, at = P(180 * sx, 205 * sy),
             rx = 120 * s, ry = 120 * s, rgb = 0xF0F0F5, a = 0.10 * pose.glow)
        glow(g, at = P(179 * sx, 248 * sy),
             rx = 22 * s, ry = 16 * s, rgb = 0x5E7A92, a = 0.08 * pose.glow)
        orbitGuide(g, cx = 179, cy = 248, restX = 268.9, restY = 171.4,
                   flatten = 0.42, s = s, sx = sx, sy = sy, rgb = 0xEBEBF0, a = 0.14)
        val pip = ride(pose, cx = 179, cy = 248, restX = 268.9, restY = 171.4, flatten = 0.42)
        riderPip(g, o = pip, front = false, cx = 179, cy = 248, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 1.7, rgb = 0xF5F5FA)
        g.layer {
            val pivot = P(179 * sx, 248 * sy)
            g.translate(pivot.x, pivot.y)
            g.rotate(pose.ringDeg + 18)
            g.translate(-pivot.x, -pivot.y)
            svgArc(g, s = s, sx = sx, sy = sy,
                   x1 = -83.5, y1 = 289.0, rx = 280, ry = 120, deg = -22,
                   large = true, sweep = true, x2 = 348.7, y2 = 248.9,
                   width = 1.0, rgb = 0xEBEBF0, a = 0.12)
            svgArc(g, s = s, sx = sx, sy = sy,
                   x1 = -61.1, y1 = 258.2, rx = 250, ry = 110, deg = -8,
                   large = true, sweep = true, x2 = 279.1, y2 = 295.5,
                   width = 1.2, rgb = 0xEBEBF0, a = 0.16)
            svgArc(g, s = s, sx = sx, sy = sy,
                   x1 = -46.5, y1 = 165.1, rx = 230, ry = 55, deg = 10,
                   large = true, sweep = true, x2 = 285.0, y2 = 271.9,
                   width = 1.0, rgb = 0xEBEBF0, a = 0.14)
            svgArc(g, s = s, sx = sx, sy = sy,
                   x1 = 9.6, y1 = 297.2, rx = 220, ry = 70, deg = -18,
                   large = true, sweep = true, x2 = 363.8, y2 = 187.5,
                   width = 1.15, rgb = 0xF0F0F5, a = 0.28)
            svgArc(g, s = s, sx = sx, sy = sy,
                   x1 = 9.1, y1 = 266.1, rx = 190, ry = 95, deg = -30,
                   large = true, sweep = true, x2 = 138.9, y2 = 323.7,
                   width = 1.0, rgb = 0xF0F0F5, a = 0.22)
            svgArc(g, s = s, sx = sx, sy = sy,
                   x1 = 152.5, y1 = 287.7, rx = 140, ry = 60, deg = -35,
                   large = true, sweep = true, x2 = 299.5, y2 = 146.4,
                   width = 1.35, rgb = 0xF5F5FA, a = 0.48)
            svgArc(g, s = s, sx = sx, sy = sy,
                   x1 = 171.6, y1 = 249.1, rx = 100, ry = 42, deg = -12,
                   large = true, sweep = true, x2 = 268.9, y2 = 171.4,
                   width = 1.1, rgb = 0xF5F5FA, a = 0.38)
        }
        riderPip(g, o = pip, front = true, cx = 179, cy = 248, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 1.7, rgb = 0xF5F5FA)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(46, 40, 1.2, 0xFFFFFA, 0.50), t(320, 60, 1.0, 0xFFFFFA, 0.40),
            t(340, 300, 1.1, 0xFFFFFA, 0.35), t(24, 330, 1.0, 0xFFFFFA, 0.40),
            t(200, 30, 1.1, 0xFFFFFA, 0.45), t(90, 120, 1.0, 0xFFFFFA, 0.35),
            t(300, 160, 1.2, 0xFFFFFA, 0.40),
        ), flares = listOf())
    }

    // Paper `2256-1` · 136px umber ball at 111/110, rings −22°, moon at 88/108.
    private fun plate05(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 178 * sy)
        val moon = ride(pose, cx = 179, cy = 178, restX = 88, restY = 108, flatten = 0.28)
        glow(g, at = c, rx = 110 * s, ry = 110 * s, rgb = 0x9A927E, a = 0.18 * pose.glow)
        if (!moon.front && !occulted(moon, cx = 179, cy = 178, r = 68)) {
            glow(g, at = P(moon.x * sx, moon.y * sy),
                 rx = 13 * s, ry = 13 * s, rgb = 0xE8E2D0, a = 0.12)
            crescent(g, at = P(moon.x * sx, moon.y * sy), r = 13 * s,
                     off = P(4.5 * s, -2.2 * s), rgb = 0xE8E2D0, a = 0.45)
        }
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = true, bands = listOf(
            t(118, 31, 12, 0.12, 0xB0A892),
            t(130, 34, 1.5, 0.30, 0xB0A892),
            t(138, 36.1, 1.15, 0.18, 0xB0A892),
            t(146, 38.2, 1.0, 0.10, 0xB0A892),
        ))
        sphere(g, c = c, r = 68 * s, hx = 152 * sx, hy = 148 * sy,
               stops = listOf(t(0, 0xD0C8B0), t(0.22, 0x9D9686), t(0.48, 0x645E50),
                       t(0.72, 0x3F3A30), t(1, 0x0B0A08)),
               air = 0x3A3423, airA = 0.20, speckle = 0.12, specA = 0.26, nightA = 0.62)
        paperHighlight(g, at = P(152 * sx, 136 * sy),
                       rx = 14 * s, ry = 8 * s, deg = -22, a = 0.20)
        ringShadow(g, c = c, r = 68 * s, rx = 130 * s, ry = 34 * s,
                   deg = pose.ringDeg, rgb = 0x080604, a = 0.20)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = false, bands = listOf(
            t(118, 31, 10, 0.18, 0xD0C8B0),
            t(130, 34, 1.6, 0.78, 0xD0C8B0),
            t(138, 36.1, 1.2, 0.46, 0xD0C8B0),
            t(146, 38.2, 1.0, 0.26, 0xD0C8B0),
        ))
        ansaGlow(g, c = c, rx = 130 * s, ry = 34 * s, deg = pose.ringDeg,
                 pose = pose, s = s, rgb = 0xE8E2D0)
        if (moon.front) {
            glow(g, at = P(moon.x * sx, moon.y * sy),
                 rx = 13 * s, ry = 13 * s, rgb = 0xE8E2D0, a = 0.22)
            crescent(g, at = P(moon.x * sx, moon.y * sy), r = 13 * s,
                     off = P(4.5 * s, -2.2 * s), rgb = 0xE8E2D0, a = 0.82)
            glow(g, at = P((moon.x - 6) * sx, (moon.y - 4) * sy),
                 rx = 3 * s, ry = 3 * s, rgb = 0xFFFAEB, a = 0.35)
        }
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(44, 52, 1.2, 0xFFFCFA, 0.50), t(316, 40, 1.0, 0xFFFCFA, 0.40),
            t(338, 210, 1.1, 0xFFFCFA, 0.35), t(22, 150, 1.0, 0xFFFCFA, 0.40),
            t(120, 30, 1.1, 0xFFFCFA, 0.45), t(290, 400, 1.0, 0xFFFCFA, 0.30),
            t(60, 390, 1.2, 0xFFFCFA, 0.35),
        ), flares = listOf())
    }

    // Paper `225Y-1` · dark 150px ball at 105/120, two dashed circles + two dashed ellipses.
    private fun plate06(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(180 * sx, 195 * sy)
        sphere(g, c = c, r = 75 * s, hx = 168 * sx, hy = 171 * sy,
               stops = listOf(t(0, 0x3A4048), t(0.45, 0x242830), t(0.75, 0x181C22),
                       t(1, 0x101418)),
               air = 0xE1E1E8, airA = 0.03, speckle = 0.02, specA = 0.02, nightA = 0.28,
               limbA = 0)
        hazeOrb(g, c = P(179 * sx, 205 * sy), r = 36 * s,
                hx = 166 * sx, hy = 189 * sy,
                core = 0xE4ECF4, mid = 0x6A7A88, a = 0.08)
        val crawl = pose.dash * 8 * s
        paperDashCircle(g, c = c, r = 75 * s, width = 1.6 * s,
                        rgb = 0xE1E1E8, a = 0.55, dash = listOf(2 * s, 6 * s), phase = crawl)
        paperDashCircle(g, c = c, r = 62 * s, width = 1.0 * s,
                        rgb = 0xE1E1E8, a = 0.18, dash = listOf(1.5 * s, 7 * s), phase = crawl)
        paperDashEllipse(g, c = c, rx = 190 * s, ry = 52 * s, deg = pose.ringDeg,
                         width = 1.2 * s, rgb = 0xDCDCE4, a = 0.35,
                         dash = listOf(2 * s, 6 * s), phase = crawl)
        paperDashEllipse(g, c = c, rx = 170 * s, ry = 60 * s, deg = pose.ringDeg + 52,
                         width = 1.1 * s, rgb = 0xDCDCE4, a = 0.25,
                         dash = listOf(2 * s, 6 * s), phase = -crawl)
        val pip = ride(pose, cx = 180, cy = 195, restX = 320, restY = 170, flatten = 0.27)
        riderPip(g, o = pip, front = false, cx = 180, cy = 195, occlude = 75,
                 s = s, sx = sx, sy = sy, r = 2.6, rgb = 0xE1E1E8)
        riderPip(g, o = pip, front = true, cx = 180, cy = 195, occlude = 75,
                 s = s, sx = sx, sy = sy, r = 2.6, rgb = 0xE1E1E8)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(50, 44, 1.1, 0xFFFCF2, 0.45), t(310, 34, 1.0, 0xFFFCF2, 0.40),
            t(336, 260, 1.1, 0xFFFCF2, 0.35), t(26, 300, 1.0, 0xFFFCF2, 0.35),
            t(240, 26, 1.0, 0xFFFCF2, 0.40),
        ), flares = listOf())
    }

    // Paper `226Q-1` · 144px blue-gray ball at 107/106, rings −24°.
    private fun plate07(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 178 * sy)
        val moon = ride(pose, cx = 179, cy = 178, restX = 317, restY = 178, flatten = 0.22)
        glow(g, at = c, rx = 100 * s, ry = 100 * s, rgb = 0xA9C4DC, a = 0.20 * pose.glow)
        riderMoon(g, o = moon, front = false, cx = 179, cy = 178, occlude = 72,
                  s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xC3D9EC)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = true, bands = listOf(
            t(126, 27, 12, 0.12, 0xA9C4DC),
            t(138, 30, 1.5, 0.32, 0xA9C4DC),
            t(146, 31.7, 1.15, 0.18, 0xA9C4DC),
            t(154, 33.5, 1.0, 0.10, 0xA9C4DC),
        ))
        sphere(g, c = c, r = 72 * s, hx = 150 * sx, hy = 146 * sy,
               stops = listOf(t(0, 0xF2F8FC), t(0.16, 0xDBE8F2), t(0.40, 0xA7BFD0),
                       t(0.64, 0x62809A), t(0.88, 0x30485C), t(1, 0x0C1420)),
               air = 0x2E465C, airA = 0.22, speckle = 0.12, specA = 0.28, nightA = 0.58)
        paperHighlight(g, at = P(152 * sx, 133 * sy),
                       rx = 16 * s, ry = 9 * s, deg = -24, a = 0.22)
        ringShadow(g, c = c, r = 72 * s, rx = 138 * s, ry = 30 * s,
                   deg = pose.ringDeg, rgb = 0x060C14, a = 0.18)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = false, bands = listOf(
            t(126, 27, 10, 0.20, 0xC3D9EC),
            t(138, 30, 1.6, 0.86, 0xC3D9EC),
            t(146, 31.7, 1.2, 0.50, 0xC3D9EC),
            t(154, 33.5, 1.0, 0.28, 0xC3D9EC),
        ))
        ansaGlow(g, c = c, rx = 138 * s, ry = 30 * s, deg = pose.ringDeg,
                 pose = pose, s = s, rgb = 0xD6ECF8)
        riderMoon(g, o = moon, front = true, cx = 179, cy = 178, occlude = 72,
                  s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xC3D9EC)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(46, 50, 1.2, 0xE6F8FF, 0.50), t(316, 34, 1.0, 0xE6F8FF, 0.40),
            t(338, 250, 1.1, 0xE6F8FF, 0.35), t(24, 300, 1.0, 0xE6F8FF, 0.40),
            t(140, 28, 1.1, 0xE6F8FF, 0.45), t(70, 380, 1.0, 0xE6F8FF, 0.30),
        ), flares = listOf())
    }

    // Paper `227I-1` · 90px warm ball at 95/145 + wide diagonal band. No rings.
    private fun plate08(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(pose.bodyX * sx, pose.bodyY * sy)
        bloom(g, at = c, rx = 85 * s, ry = 85 * s, rgb = 0xE4E8F0, a = 0.08)
        paperBlurLine(g, s = s, sx = sx, sy = sy,
                      from = t(-30, 351), to = t(388, 99), width = 94, rgb = 0xC8CED8, a = 0.04)
        paperBlurLine(g, s = s, sx = sx, sy = sy,
                      from = t(-30, 351), to = t(388, 99), width = 58, rgb = 0xCED4DE, a = 0.06)
        paperBlurLine(g, s = s, sx = sx, sy = sy,
                      from = t(-30, 351), to = t(388, 99), width = 30, rgb = 0xD6DCE6, a = 0.08)
        sphere(g, c = c, r = 45 * s,
               hx = 123.8 * sx, hy = 170.2 * sy,
               stops = listOf(t(0, 0xA8A498), t(0.30, 0x7A7668), t(0.60, 0x4A4638),
                       t(0.86, 0x242220), t(1, 0x141210)),
               air = 0xC8BE9E, airA = 0.02, speckle = 0.02, specA = 0, nightA = 0,
               limbA = 0)
        discWash(g, c = c, r = 45 * s, deg = 148, stops = listOf(
            ws(0, white(0.03)),
            ws(0.34, white(0)),
            ws(0.64, col(0x18160E, 0.44)),
            ws(1, col(0x14120C, 0.84)),
        ))
        paperHighlight(g, at = P(163 * sx, 165.5 * sy),
                       rx = 13 * s, ry = 7.5 * s, deg = -22, a = 0.03)
        paperLine(g, s = s, sx = sx, sy = sy,
                  from = t(-30, 333), to = t(388, 81), width = 2.2, rgb = 0xE4E8F0, a = 0.14)
        orbitGuide(g, cx = pose.bodyX, cy = pose.bodyY, restX = 232, restY = 152,
                   flatten = 0.34, s = s, sx = sx, sy = sy, rgb = 0xE4E0D0, a = 0.18)
        val moon = ride(pose, cx = pose.bodyX, cy = pose.bodyY, restX = 232, restY = 152, flatten = 0.34)
        riderMoon(g, o = moon, front = false, cx = pose.bodyX, cy = pose.bodyY, occlude = 45,
                  s = s, sx = sx, sy = sy, r = 3.0, rgb = 0xE4E0D0)
        riderMoon(g, o = moon, front = true, cx = pose.bodyX, cy = pose.bodyY, occlude = 45,
                  s = s, sx = sx, sy = sy, r = 3.0, rgb = 0xE4E0D0)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(42, 64, 1.3, 0xF0F2F6, 0.60), t(312, 46, 1.0, 0xF0F2F6, 0.45),
            t(336, 230, 1.1, 0xF0F2F6, 0.40), t(28, 150, 1.0, 0xF0F2F6, 0.38),
            t(246, 30, 1.2, 0xF0F2F6, 0.50), t(120, 40, 1.0, 0xF0F2F6, 0.35),
            t(330, 130, 1.0, 0xF0F2F6, 0.30),
        ), flares = listOf())
    }

    // Paper `228A-1` · 150px cool ball at 104/115 + fading diagonal.
    private fun plate09(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 190 * sy)
        bloom(g, at = c, rx = 125 * s, ry = 125 * s, rgb = 0xD6DCE8, a = 0.07)
        sphere(g, c = c, r = 75 * s, hx = 194 * sx, hy = 160 * sy,
               stops = listOf(t(0, 0xA0A6B0), t(0.32, 0x7A828C), t(0.62, 0x4A525C),
                       t(0.86, 0x2A3038), t(1, 0x14181C)),
               air = 0xD6DCE8, airA = 0.03, speckle = 0.02, specA = 0, nightA = 0.12,
               limbA = 0)
        featherRim(g, c = c, r = 75 * s, rgb = 0x070709, inner = 0.78, pad = 1.0)
        paperCraters(g, origin = P(104 * sx, 115 * sy),
                     disc = c, r = 75 * s, s = s, sx = sx, sy = sy,
                     shiftX = 0, shiftY = 0,
                     mares = listOf(t(20, 44, 70, 50, 0.06), t(64, 78, 56, 40, 0.05),
                             t(46, 22, 44, 32, 0.04)),
                     pits = listOf())
        val soft = listOf(
            t(-20, 295, 51.6, 266.2, 0.04),
            t(123.3, 237.4, 194.9, 208.6, 0.07),
            t(266.6, 179.8, 378, 135, 0.12),
        )
        for (seg in soft) {
            paperLine(g, s = s, sx = sx, sy = sy,
                      from = t(seg[0], seg[1]), to = t(seg[2], seg[3]), width = 6, rgb = 0xB0B8C4, a = seg[4])
        }
        val core = listOf(
            t(-20, 295, 51.6, 266.2, 0.08),
            t(51.6, 266.2, 123.3, 237.4, 0.16),
            t(123.3, 237.4, 194.9, 208.6, 0.26),
            t(194.9, 208.6, 266.6, 179.8, 0.38),
            t(266.6, 179.8, 322.3, 157.4, 0.48),
            t(322.3, 157.4, 378, 135, 0.58),
        )
        for (seg in core) {
            paperLine(g, s = s, sx = sx, sy = sy,
                      from = t(seg[0], seg[1]), to = t(seg[2], seg[3]), width = 1.5, rgb = 0xC0C8D4, a = seg[4])
        }
        orbitGuide(g, cx = 179, cy = 190, restX = 286, restY = 148,
                   flatten = 0.36, s = s, sx = sx, sy = sy, rgb = 0xC0C8D4, a = 0.16)
        val pip = ride(pose, cx = 179, cy = 190, restX = 286, restY = 148, flatten = 0.36)
        riderPip(g, o = pip, front = false, cx = 179, cy = 190, occlude = 75,
                 s = s, sx = sx, sy = sy, r = 2.4, rgb = 0xE8ECF2)
        riderPip(g, o = pip, front = true, cx = 179, cy = 190, occlude = 75,
                 s = s, sx = sx, sy = sy, r = 2.4, rgb = 0xE8ECF2)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(40, 58, 1.2, 0xF0F2F6, 0.50), t(318, 44, 1.0, 0xF0F2F6, 0.40),
            t(338, 260, 1.0, 0xF0F2F6, 0.35), t(24, 330, 1.0, 0xF0F2F6, 0.30),
            t(262, 26, 1.1, 0xF0F2F6, 0.45), t(90, 28, 1.0, 0xF0F2F6, 0.32),
        ), flares = listOf())
    }

    // Paper `2292-1` · dashed blue diagonal from top-left + star at (14, 94).
    private fun plate10(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val soft = listOf(
            t(-10, 82, 46.7, 117.4, 0.05),
            t(46.7, 117.4, 122.3, 164.6, 0.10),
            t(122.3, 164.6, 235.7, 235.4, 0.14),
            t(235.7, 235.4, 311.3, 282.6, 0.09),
            t(311.3, 282.6, 368, 318, 0.04),
        )
        for (seg in soft) {
            paperLine(g, s = s, sx = sx, sy = sy,
                      from = t(seg[0], seg[1]), to = t(seg[2], seg[3]), width = 7, rgb = 0x6090FF, a = seg[4])
        }
        val core = listOf(
            t(-10, 82, 46.7, 117.4, 0.16),
            t(46.7, 117.4, 122.3, 164.6, 0.38),
            t(122.3, 164.6, 235.7, 235.4, 0.55),
            t(235.7, 235.4, 311.3, 282.6, 0.32),
            t(311.3, 282.6, 368, 318, 0.12),
        )
        for (seg in core) {
            paperDashLine(g, s = s, sx = sx, sy = sy,
                          from = t(seg[0], seg[1]), to = t(seg[2], seg[3]), width = 1.6, rgb = 0x96BAFF, a = seg[4],
                          dash = listOf(2, 5), phase = pose.dash * 7)
        }
        orbitGuide(g, cx = 179, cy = 200, restX = 14, restY = 94,
                   flatten = 0.20, s = s, sx = sx, sy = sy, rgb = 0x96BAFF, a = 0.20)
        val body = ride(pose, cx = 179, cy = 200, restX = 14, restY = 94, flatten = 0.20)
        val star = P(body.x * sx, body.y * sy)
        bloom(g, at = star, rx = 16 * s, ry = 16 * s, rgb = 0x96BAFF, a = 0.28 * pose.glow)
        glow(g, at = star, rx = 6 * s, ry = 6 * s, rgb = 0xF4F8FF, a = 0.70 * pose.glow)
        flare(g, at = star, r = 7 * s, rgb = 0xEBF2FF, a = 0.92 * pose.glow)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(300, 40, 1.0, 0xE6EEFF, 0.40), t(110, 30, 1.0, 0xE6EEFF, 0.32),
            t(340, 180, 1.0, 0xE6EEFF, 0.30), t(230, 22, 1.1, 0xE6EEFF, 0.36),
            t(48, 360, 0.8, 0xE6EEFF, 0.28), t(168, 18, 0.75, 0xFFFCF0, 0.34),
            t(318, 88, 0.7, 0xCFE4FF, 0.26), t(86, 48, 0.7, 0xE6EEFF, 0.30),
            t(250, 420, 0.8, 0xE6EEFF, 0.22), t(20, 220, 0.65, 0xFFFCF0, 0.24),
        ), flares = listOf(t(328, 52, 3.4, 0xEBF2FF, 0.42)))
    }

    // Paper `22BE-1` · bright diagonal + dashed ellipse 210×110 at −32°. No moon.
    private fun plate13(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        paperBlurLine(g, s = s, sx = sx, sy = sy,
                      from = t(-20, 460), to = t(378, 50), width = 42, rgb = 0xEBEEF4,
                      a = 0.16 * pose.glow)
        paperBlurLine(g, s = s, sx = sx, sy = sy,
                      from = t(-20, 460), to = t(378, 50), width = 14, rgb = 0xF0F3F8,
                      a = 0.28 * pose.glow)
        paperDashEllipse(g, c = P(180 * sx, 235 * sy),
                         rx = 210 * s, ry = 110 * s, deg = pose.ringDeg,
                         width = 1.5 * s, rgb = 0xE4E8EE, a = 0.50,
                         dash = listOf(2 * s, 6 * s), phase = pose.dash * 8 * s)
        val pip = ride(pose, cx = 180, cy = 235, restX = 320, restY = 180, flatten = 0.52)
        riderPip(g, o = pip, front = false, cx = 180, cy = 235, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 2.8, rgb = 0xFAFBFD)
        paperLine(g, s = s, sx = sx, sy = sy,
                  from = t(-20, 460), to = t(378, 50), width = 2.4, rgb = 0xFAFBFD, a = 0.90)
        riderPip(g, o = pip, front = true, cx = 180, cy = 235, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 2.8, rgb = 0xFAFBFD)
        glow(g, at = P(35 * sx, 425 * sy),
             rx = 45 * s, ry = 45 * s, rgb = 0xF8F8FA, a = 0.40 * pose.glow)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(44, 62, 1.2, 0xF0F2F6, 0.50), t(316, 40, 1.0, 0xF0F2F6, 0.40),
            t(340, 200, 1.0, 0xF0F2F6, 0.35), t(26, 170, 1.0, 0xF0F2F6, 0.38),
            t(250, 24, 1.1, 0xF0F2F6, 0.45), t(120, 36, 1.0, 0xF0F2F6, 0.32),
            t(70, 280, 1.0, 0xF0F2F6, 0.30),
        ), flares = listOf())
    }

    // Paper `22C6-1` · 56px dim ball at 151/167, dashed r=62 circle, fade line.
    private fun plate14(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        glow(g, at = P(200 * sx, 320 * sy),
             rx = 120 * s, ry = 100 * s, rgb = 0x5EEAD4, a = 0.055 * pose.glow)
        paperDashCircle(g, c = P(173 * sx, 205 * sy), r = 62 * s,
                        width = 1.0 * s, rgb = 0xFFFFFF, a = 0.11 * pose.glow,
                        dash = listOf(1.6 * s, 5 * s), phase = 0)
        paperGradientLine(g, s = s, sx = sx, sy = sy,
                          from = t(-20, 400), to = t(378, 218), width = 1.0,
                          stops = listOf(t(0, 0), t(0.22, 0.12), t(0.78, 0.12), t(1, 0)))
        val c = P(pose.bodyX * sx, pose.bodyY * sy)
        val pip = ride(pose, cx = 173, cy = 205, restX = 235, restY = 205, flatten = 1)
        riderPip(g, o = pip, front = false, cx = 173, cy = 205, occlude = 28,
                 s = s, sx = sx, sy = sy, r = 2.4, rgb = 0xE8F4F6)
        glow(g, at = c, rx = 36 * s, ry = 36 * s, rgb = 0xA8BED0, a = 0.10 * pose.glow)
        g.fill(oval(c.x - 28 * s, c.y - 28 * s, 56 * s, 56 * s),
               radial(evenly(col(0x3A4450, 0.22), col(0x12161C, 0.12), col(0x12161C, 0)),
                      center = P(168 * sx, 182 * sy), start = 0.0, end = 28 * s))
        riderPip(g, o = pip, front = true, cx = 173, cy = 205, occlude = 28,
                 s = s, sx = sx, sy = sy, r = 2.4, rgb = 0xE8F4F6)
    }

    // Paper `22DQ-1` · bottom cyan bloom + far circles + left dashed crescent.
    private fun plate16(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        mist(g, at = P(180 * sx, 450 * sy),
             rx = 260 * s, ry = 150 * s, rgb = 0x67E8F9, a = 0.32)
        mist(g, at = P(205 * sx, 445 * sy),
             rx = 95 * s, ry = 60 * s, rgb = 0xCFFAFE, a = 0.22)
        g.fill(rectPath(0, 300 * sy, 358 * sx, 170 * sy),
               linear(listOf(ws(0, col(0x67E8F9, 0)), ws(0.55, col(0x67E8F9, 0.06)),
                             ws(1, col(0xCFFAFE, 0.14))),
                      P(179 * sx, 300 * sy), P(179 * sx, 470 * sy)))
        strokeCircle(g, c = P(900 * sx, -100 * sy), r = 796 * s,
                     width = 1.5 * s, rgb = 0xBAE6FD, a = 0.28)
        strokeCircle(g, c = P(1050 * sx, 300 * sy), r = 720 * s,
                     width = 1.0 * s, rgb = 0xBAE6FD, a = 0.10)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = 110, y1 = 232.3, rx = 20, ry = 20, deg = 0,
               large = true, sweep = true, x2 = 110, y2 = 197.7,
               width = 2, rgb = 0xBAE6FD, a = 0.55,
               marks = listOf(2, 5), markPhase = pose.dash * 7)
        orbitGuide(g, cx = 210, cy = 140, restX = 302, restY = 88,
                   flatten = 0.30, s = s, sx = sx, sy = sy, rgb = 0xBAE6FD, a = 0.22)
        val moon = ride(pose, cx = 210, cy = 140, restX = 302, restY = 88, flatten = 0.30)
        riderMoon(g, o = moon, front = false, cx = 210, cy = 140, occlude = 0,
                  s = s, sx = sx, sy = sy, r = 3.6, rgb = 0xE2F4FF)
        riderMoon(g, o = moon, front = true, cx = 210, cy = 140, occlude = 0,
                  s = s, sx = sx, sy = sy, r = 3.6, rgb = 0xE2F4FF)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(60, 90, 1.2, 0xE2F4FF, 0.60), t(290, 60, 1.0, 0xE2F4FF, 0.45),
            t(330, 170, 1.1, 0xE2F4FF, 0.40), t(200, 120, 1.0, 0xE2F4FF, 0.50),
            t(140, 42, 1.2, 0xE2F4FF, 0.40), t(36, 270, 1.0, 0xE2F4FF, 0.35),
            t(88, 18, 0.75, 0xFFFCF0, 0.36), t(248, 28, 0.7, 0xE2F4FF, 0.30),
            t(318, 88, 0.7, 0xCFE4FF, 0.26), t(22, 140, 0.65, 0xE2F4FF, 0.28),
        ), flares = listOf(t(48, 52, 3.2, 0xE2F4FF, 0.40)))
    }

    // Paper `22EI-1` · violet bloom + 128×96 ellipse at 18° + pip (294, 210).
    private fun plate17(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        bloom(g, at = P(180 * sx, 260 * sy),
              rx = 125 * s, ry = 115 * s, rgb = 0x6D28D9, a = 0.28)
        bloom(g, at = P(250 * sx, 320 * sy),
              rx = 75 * s, ry = 65 * s, rgb = 0xD774B4, a = 0.18)
        bloom(g, at = P(185 * sx, 270 * sy),
              rx = 75 * s, ry = 65 * s, rgb = 0xA78BFA, a = 0.22)
        bloom(g, at = P(185 * sx, 280 * sy),
              rx = 45 * s, ry = 35 * s, rgb = 0xFFF4E0, a = 0.16)
        paperDashEllipse(g, c = P(182 * sx, 238 * sy),
                         rx = 128 * s, ry = 96 * s, deg = pose.ringDeg + 30,
                         width = 1.2 * s, rgb = 0xC4B5FD, a = 0.38,
                         dash = listOf(), phase = 0)
        paperLine(g, s = s, sx = sx, sy = sy,
                  from = t(200, -20), to = t(330, 180), width = 1.0, rgb = 0xFFFFFF, a = 0.07)
        paperLine(g, s = s, sx = sx, sy = sy,
                  from = t(245, -20), to = t(358, 140), width = 1.0, rgb = 0xFFFFFF, a = 0.05)
        val pip = ride(pose, cx = 182, cy = 238, restX = 294, restY = 210, flatten = 0.75)
        riderPip(g, o = pip, front = false, cx = 182, cy = 238, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xA78BFA)
        riderPip(g, o = pip, front = true, cx = 182, cy = 238, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xA78BFA)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(48, 72, 1.2, 0xF0EBFF, 0.60), t(310, 50, 1.0, 0xF0EBFF, 0.45),
            t(334, 300, 1.1, 0xF0EBFF, 0.40), t(90, 150, 1.0, 0xF0EBFF, 0.50),
            t(160, 60, 1.3, 0xF0EBFF, 0.40), t(250, 120, 1.0, 0xF0EBFF, 0.45),
            t(36, 330, 1.0, 0xF0EBFF, 0.35), t(290, 360, 1.2, 0xF0EBFF, 0.30),
        ), flares = listOf())
    }

    // Paper `22FA-1` · two magenta blooms + rings at (200, 210) + pip (106, 264).
    private fun plate18(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        glow(g, at = P(75 * sx, 75 * sy),
              rx = 145 * s, ry = 125 * s, rgb = 0xE84393, a = 0.22)
        glow(g, at = P(310 * sx, 420 * sy),
             rx = 145 * s, ry = 125 * s, rgb = 0xD774B4, a = 0.24)
        val ring = P(200 * sx, 210 * sy)
        strokeCircle(g, c = ring, r = 112 * s, width = 1.0 * s, rgb = 0xFFEBF4, a = 0.14)
        strokeCircle(g, c = ring, r = 107 * s, width = 1.2 * s,
                     rgb = 0xFFEBF4, a = 0.34 * pose.glow)
        val pip = ride(pose, cx = 200, cy = 210, restX = 106, restY = 264, flatten = 1)
        riderPip(g, o = pip, front = false, cx = 200, cy = 210, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xE84393)
        riderPip(g, o = pip, front = true, cx = 200, cy = 210, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xE84393)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(58, 180, 1.2, 0xFFEBF4, 0.55), t(300, 90, 1.0, 0xFFEBF4, 0.45),
            t(335, 220, 1.1, 0xFFEBF4, 0.40), t(150, 70, 1.0, 0xFFEBF4, 0.40),
            t(240, 340, 1.0, 0xFFEBF4, 0.35), t(70, 330, 1.3, 0x9AE6F0, 0.50),
            t(320, 380, 1.1, 0x9AE6F0, 0.40), t(180, 150, 1.0, 0x9AE6F0, 0.35),
        ), flares = listOf())
    }

    // Paper `22G2-1` · 150px ivory ball at 105/125, thin ring −13°, three color ticks.
    private fun plate19(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(180 * sx, 200 * sy)
        glow(g, at = c, rx = 125 * s, ry = 125 * s, rgb = 0xFFF8E0, a = 0.10 * pose.glow)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = 343.7, y1 = 197.2, rx = 168, ry = 48, deg = pose.ringDeg,
               large = false, sweep = false, x2 = 16.3, y2 = 272.8,
               width = 2.5, rgb = 0xF0DEAA, a = 0.30)
        sphere(g, c = c, r = 75 * s, hx = 162 * sx, hy = 164 * sy,
               stops = listOf(t(0, 0xE8DCC4), t(0.18, 0xC4B89A), t(0.40, 0x8A8068),
                       t(0.66, 0x4A4438), t(1, 0x1A1810)),
               air = 0xC9C0AC, airA = 0.10, speckle = 0.06, specA = 0.05, nightA = 0.40,
               limbA = 0)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = 343.7, y1 = 197.2, rx = 168, ry = 48, deg = pose.ringDeg,
               large = false, sweep = true, x2 = 16.3, y2 = 272.8,
               width = 2.0, rgb = 0xF5E6BE, a = 0.55)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = 344.0, y1 = 200.1, rx = 168, ry = 48, deg = pose.ringDeg,
               large = false, sweep = true, x2 = 278.8, y2 = 253.4,
               width = 3.0, rgb = 0xF472B6, a = 0.90)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = 262.5, y1 = 260.1, rx = 168, ry = 48, deg = pose.ringDeg,
               large = false, sweep = true, x2 = 115.6, y2 = 293.8,
               width = 3.0, rgb = 0x22D3EE, a = 0.90)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = 98.0, y1 = 294.9, rx = 168, ry = 48, deg = pose.ringDeg,
               large = false, sweep = true, x2 = 17.2, y2 = 275.5,
               width = 3.0, rgb = 0xFDE047, a = 0.90)
        for (f in listOf(
            t(72.0, 265.0, 9.0, 0xFFF6DC),
            t(127.0, 88.0, 7.0, 0xF472B6),
            t(263.0, 128.0, 8.0, 0xBAF0FA),
            t(318.0, 300.0, 5.5, 0xFFF6DC),
        )) {
            flare(g, at = P(f[0] * sx, f[1] * sy), r = f[2] * s,
                  rgb = f[3].toInt(), a = 0.72 * pose.breathe)
        }
        val pip = ride(pose, cx = 180, cy = 200, restX = 343.7, restY = 197.2, flatten = 0.29)
        riderPip(g, o = pip, front = false, cx = 180, cy = 200, occlude = 75,
                 s = s, sx = sx, sy = sy, r = 2.8, rgb = 0xFFF6DC)
        riderPip(g, o = pip, front = true, cx = 180, cy = 200, occlude = 75,
                 s = s, sx = sx, sy = sy, r = 2.8, rgb = 0xFFF6DC)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(46, 120, 1.2, 0xFFF6DC, 0.55), t(310, 60, 1.0, 0xFFF6DC, 0.50),
            t(336, 200, 1.1, 0xFFF6DC, 0.40), t(200, 46, 1.0, 0xFFF6DC, 0.45),
            t(30, 350, 1.0, 0xFFF6DC, 0.35),
        ), flares = listOf())
    }

    // Paper `22JY-1` · cyan trail `M 372 96 C …` + static head (366, 92).
    private fun plate24(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        glow(g, at = P(330 * sx, 180 * sy),
             rx = 120 * s, ry = 120 * s, rgb = 0x22D3EE, a = 0.16 * pose.glow)
        val trail = listOf(
            t(6, 0x22D3EE, 0.06), t(3, 0x22D3EE, 0.12),
            t(1.6, 0x38BDF8, 0.42), t(1.0, 0xCFFAFE, 0.82),
        )
        for (tr in trail) {
            paperCubics(g, s = s, sx = sx, sy = sy,
                        p0 = t(372, 96), c1 = t(268, 116), c2 = t(196, 178), p1 = t(158, 246),
                        c3 = t(128, 300), c4 = t(138, 344), p2 = t(196, 366),
                        width = tr[0], rgb = tr[1].toInt(), a = tr[2])
        }
        paperCubics(g, s = s, sx = sx, sy = sy,
                    p0 = t(378, 170), c1 = t(300, 190), c2 = t(240, 240), p1 = t(214, 300),
                    width = 1.2, rgb = 0x93C5FD, a = 0.22,
                    dash = listOf(2, 6), phase = pose.dash * 8)
        val q = pose.comet
        val p = plate24Point(q)
        glow(g, at = P(p.first * sx, p.second * sy),
             rx = 10 * s, ry = 10 * s, rgb = 0x38BDF8, a = 0.40)
        glow(g, at = P(p.first * sx, p.second * sy),
             rx = 3.4 * s, ry = 3.4 * s, rgb = 0xEAF6FF, a = 0.88)
        fillDot(g, at = P(p.first * sx, p.second * sy), r = 2.6 * s, rgb = 0xE0F7FE, a = 0.95)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(60, 70, 1.2, 0xFFFFFF, 0.50), t(130, 40, 1.0, 0xFFFFFF, 0.38),
            t(40, 210, 1.1, 0xFFFFFF, 0.40), t(90, 330, 1.0, 0xFFFFFF, 0.30),
            t(260, 420, 1.1, 0xFFFFFF, 0.32), t(320, 380, 1.0, 0xFFFFFF, 0.30),
            t(22, 48, 0.75, 0xCFFAFE, 0.34), t(168, 22, 0.7, 0xFFFFFF, 0.28),
            t(300, 60, 0.7, 0x38BDF8, 0.26), t(48, 160, 0.65, 0xFFFFFF, 0.24),
        ), flares = listOf(t(88, 52, 3.4, 0xCFFAFE, 0.40)))
    }

    // Paper `229U-1` · 860px limb from the right, diagonal lines, no rings.
    private fun plate11(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        paperLine(g, s = s, sx = sx, sy = sy,
                  from = t(-30, 327), to = t(368, 48), width = 1.5, rgb = 0xBEC3CD, a = 0.18)
        paperLine(g, s = s, sx = sx, sy = sy,
                  from = t(-30, 335), to = t(368, 56), width = 1.0, rgb = 0xBEC3CD, a = 0.08)
        val c = P(pose.bodyX * sx, pose.bodyY * sy)
        sphere(g, c = c, r = 430 * s, hx = 170 * sx, hy = 133 * sy,
               stops = listOf(t(0, 0x6A7078), t(0.12, 0x3A4048), t(0.28, 0x1C2228),
                       t(0.50, 0x101418), t(0.74, 0x0A0C10), t(1, 0x07080A)),
               air = 0xC8CDD6, airA = 0.03, speckle = 0.02, specA = 0.03, nightA = 0.62,
               limbA = 0)
        paperLine(g, s = s, sx = sx, sy = sy,
                  from = t(-30, 345), to = t(140, 226), width = 1.2, rgb = 0xC8CDD7, a = 0.02)
        paperLine(g, s = s, sx = sx, sy = sy,
                  from = t(-30, 327), to = t(135, 211), width = 2.0, rgb = 0xDCE1E9, a = 0.18)
        orbitGuide(g, cx = 90, cy = 180, restX = 210, restY = 70,
                   flatten = 0.40, s = s, sx = sx, sy = sy, rgb = 0xC8CDD7, a = 0.16)
        val pip = ride(pose, cx = 90, cy = 180, restX = 210, restY = 70, flatten = 0.40)
        riderPip(g, o = pip, front = true, cx = 90, cy = 180, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 2.6, rgb = 0xE8ECF2)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(40, 60, 1.3, 0xF0F2F6, 0.55), t(120, 34, 1.0, 0xF0F2F6, 0.40),
            t(30, 200, 1.0, 0xF0F2F6, 0.35), t(90, 120, 1.1, 0xF0F2F6, 0.42),
            t(220, 26, 1.0, 0xF0F2F6, 0.38), t(52, 300, 1.0, 0xF0F2F6, 0.30),
        ), flares = listOf())
    }

    // Paper `22AM-1` · 170px silhouette at 94/103, rings −2°.
    private fun plate12(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 188 * sy)
        val moon = ride(pose, cx = 179, cy = 188, restX = 344, restY = 188, flatten = 0.145)
        glow(g, at = P(230 * sx, 190 * sy),
             rx = 110 * s, ry = 110 * s, rgb = 0x50505A, a = 0.10 * pose.glow)
        riderMoon(g, o = moon, front = false, cx = 179, cy = 188, occlude = 85,
                  s = s, sx = sx, sy = sy, r = 3.0, rgb = 0x9696A0)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = true, bands = listOf(
            t(152, 22, 10, 0.10, 0x55555E),
            t(165, 24, 1.5, 0.28, 0x55555E),
            t(173, 25.2, 1.15, 0.16, 0x55555E),
            t(181, 26.3, 1.0, 0.10, 0x55555E),
        ))
        sphere(g, c = c, r = 85 * s, hx = 142 * sx, hy = 154 * sy,
               stops = listOf(t(0, 0x7A7A86), t(0.24, 0x4A4A54), t(0.50, 0x2C2C32),
                       t(0.74, 0x18181C), t(1, 0x0A0A0C)),
               air = 0x1E1E24, airA = 0.28, speckle = 0.10)
        ringShadow(g, c = c, r = 85 * s, rx = 165 * s, ry = 24 * s,
                   deg = pose.ringDeg, rgb = 0x000000, a = 0.22)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = false, bands = listOf(
            t(152, 22, 8, 0.16, 0x787882),
            t(165, 24, 1.6, 0.72, 0x9696A0),
            t(173, 25.2, 1.2, 0.42, 0x9696A0),
            t(181, 26.3, 1.0, 0.24, 0x9696A0),
        ))
        ansaGlow(g, c = c, rx = 165 * s, ry = 24 * s, deg = pose.ringDeg,
                 pose = pose, s = s, rgb = 0xC8C8D0)
        riderMoon(g, o = moon, front = true, cx = 179, cy = 188, occlude = 85,
                  s = s, sx = sx, sy = sy, r = 3.0, rgb = 0x9696A0)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(46, 66, 1.1, 0xEBEEF2, 0.40), t(312, 48, 1.0, 0xEBEEF2, 0.32),
            t(334, 150, 1.0, 0xEBEEF2, 0.28), t(28, 290, 1.0, 0xEBEEF2, 0.26),
            t(240, 28, 1.0, 0xEBEEF2, 0.35),
        ), flares = listOf())
    }

    // Paper `22GU-1` · 184px blue ball at 206/103, two far circular arcs.
    private fun plate20(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        bloom(g, at = P(290 * sx, 190 * sy),
              rx = 150 * s, ry = 150 * s, rgb = 0x38BDF8, a = 0.12)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = -40, y1 = 400, rx = 420, ry = 420, deg = 0,
               large = false, sweep = true, x2 = 262, y2 = 62,
               width = 1.0, rgb = 0xBAE6FD, a = 0.26)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = -54, y1 = 412, rx = 438, ry = 438, deg = 0,
               large = false, sweep = true, x2 = 270, y2 = 52,
               width = 0.8, rgb = 0xBAE6FD, a = 0.11)
        val c20 = P(pose.bodyX * sx, pose.bodyY * sy)
        softBall(g, c = c20, r = 92 * s, hx = c20.x, hy = c20.y, stops = listOf(
            t(0, 0x4A6A98, 0.28),
            t(0.42, 0x2A4A78, 0.18),
            t(0.74, 0x122040, 0.07),
            t(1, 0x080E1C, 0),
        ))
        softBall(g, c = c20, r = 78 * s, hx = 246 * sx, hy = 166 * sy, stops = listOf(
            t(0, 0xA8C4E0, 0.22),
            t(0.40, 0x5A7EA8, 0.10),
            t(1, 0x1A2A58, 0),
        ))
        flare(g, at = P(104 * sx, 132 * sy),
              r = 5.2 * s, rgb = 0xF0F8FF, a = 0.70 * pose.twinkle)
        orbitGuide(g, cx = pose.bodyX, cy = pose.bodyY, restX = 168, restY = 118,
                   flatten = 0.42, s = s, sx = sx, sy = sy, rgb = 0xBAE6FD, a = 0.18)
        val pip = ride(pose, cx = pose.bodyX, cy = pose.bodyY, restX = 168, restY = 118, flatten = 0.42)
        riderPip(g, o = pip, front = false, cx = pose.bodyX, cy = pose.bodyY, occlude = 92,
                 s = s, sx = sx, sy = sy, r = 2.8, rgb = 0xE0F2FF)
        riderPip(g, o = pip, front = true, cx = pose.bodyX, cy = pose.bodyY, occlude = 92,
                 s = s, sx = sx, sy = sy, r = 2.8, rgb = 0xE0F2FF)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(52, 66, 1.3, 0xFFFFFF, 0.62), t(120, 40, 1.0, 0xFFFFFF, 0.40),
            t(30, 180, 1.1, 0xFFFFFF, 0.45), t(90, 330, 1.2, 0xFFFFFF, 0.35),
            t(206, 34, 1.0, 0xFFFFFF, 0.50), t(26, 260, 1.0, 0xFFFFFF, 0.30),
        ), flares = listOf())
    }

    // Paper `22HM-1` · 404px left giant at −262/38, dashed arc, pip at 223/218.
    private fun plate21(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        bloom(g, at = P(30 * sx, 270 * sy),
              rx = 210 * s, ry = 210 * s, rgb = 0x2563EB, a = 0.22 * pose.glow)
        sphere(g, c = P(pose.bodyX * sx, pose.bodyY * sy), r = 202 * s,
               hx = 80 * sx, hy = 200 * sy,
               stops = listOf(t(0, 0xE8F4FF), t(0.16, 0xA8D4F8), t(0.36, 0x5B9EF0),
                       t(0.58, 0x2F74E0), t(0.80, 0x1A4AA8), t(1, 0x0A2050)),
               air = 0x3B82F6, airA = 0.18, speckle = 0.03, specA = 0.10, nightA = 0.32,
               limbA = 0)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = 169, y1 = 128, rx = 300, ry = 110, deg = -12,
               large = false, sweep = true, x2 = 140, y2 = 286,
               width = 1.3, rgb = 0x93C5FD, a = 0.40,
               marks = listOf(2, 6), markPhase = pose.dash * 8)
        val sat = IdlePlateMotion.alongArc(
            x1 = 169.0, y1 = 128.0, rx = 300.0, ry = 110.0, deg = -12.0,
            large = false, sweep = true, x2 = 140.0, y2 = 286.0,
            restU = 0.63, swing = 0.36, u = pose.satellite)
        riderPip(g, o = sat, front = false, cx = 195, cy = 208, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 4, rgb = 0xBAE6FD)
        riderPip(g, o = sat, front = true, cx = 195, cy = 208, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 4, rgb = 0xBAE6FD)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(300, 60, 1.3, 0xFFFFFF, 0.55), t(330, 150, 1.0, 0xFFFFFF, 0.40),
            t(250, 30, 1.1, 0xFFFFFF, 0.45), t(320, 330, 1.2, 0xFFFFFF, 0.35),
            t(210, 380, 1.0, 0xFFFFFF, 0.30),
        ), flares = listOf())
    }

    // Paper `22IE-1` · 136px ivory ball at 111/118, rings −2°.
    private fun plate22(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 186 * sy)
        val moon = ride(pose, cx = 179, cy = 186, restX = 324, restY = 186, flatten = 0.11)
        glow(g, at = c, rx = 120 * s, ry = 120 * s, rgb = 0xCFC5A2, a = 0.16 * pose.glow)
        riderMoon(g, o = moon, front = false, cx = 179, cy = 186, occlude = 68,
                  s = s, sx = sx, sy = sy, r = 3.0, rgb = 0xE2D8B4)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = true, bands = listOf(
            t(132, 14.5, 8, 0.12, 0xCFC5A2),
            t(145, 16, 1.5, 0.32, 0xCFC5A2),
            t(152, 16.8, 1.15, 0.18, 0xCFC5A2),
            t(159, 17.5, 1.0, 0.10, 0xCFC5A2),
        ))
        sphere(g, c = c, r = 68 * s, hx = 152 * sx, hy = 156 * sy,
               stops = listOf(t(0, 0xF3EFD6), t(0.16, 0xE4DCC0), t(0.42, 0xB3A882),
                       t(0.66, 0x5F5640), t(0.90, 0x2A2418), t(1, 0x100E08)),
               air = 0x3E3823, airA = 0.18, speckle = 0.12)
        ringShadow(g, c = c, r = 68 * s, rx = 145 * s, ry = 16 * s,
                   deg = pose.ringDeg, rgb = 0x0A0804, a = 0.16)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = false, bands = listOf(
            t(132, 14.5, 7, 0.18, 0xE2D8B4),
            t(145, 16, 1.6, 0.86, 0xE2D8B4),
            t(152, 16.8, 1.2, 0.50, 0xE2D8B4),
            t(159, 17.5, 1.0, 0.28, 0xE2D8B4),
        ))
        ansaGlow(g, c = c, rx = 145 * s, ry = 16 * s, deg = pose.ringDeg,
                 pose = pose, s = s, rgb = 0xFFF6D6)
        riderMoon(g, o = moon, front = true, cx = 179, cy = 186, occlude = 68,
                  s = s, sx = sx, sy = sy, r = 3.0, rgb = 0xE2D8B4)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(60, 52, 1.3, 0xFFFCF0, 0.70), t(150, 32, 1.0, 0xFFE9C9, 0.48),
            t(300, 70, 1.2, 0xCFE4FF, 0.52), t(330, 168, 1.0, 0xFFFFFF, 0.36),
            t(240, 48, 1.1, 0xFFFCF0, 0.42), t(36, 148, 0.9, 0xFFFFFF, 0.30),
        ), flares = listOf(t(88, 86, 5.0, 0xFFFCF0, 0.88)))
    }

    // Paper `22KQ-1` · low amber bloom + tiny ring at y≈414, no sphere.
    private fun plate25(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        mist(g, at = P(179 * sx, 313 * sy),
             rx = 120 * s, ry = 65 * s, rgb = 0xE05E10, a = 0.05)
        mist(g, at = P(179 * sx, 298 * sy),
             rx = 50 * s, ry = 20 * s, rgb = 0xF6A41C, a = 0.06)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = 244, y1 = 410, rx = 64, ry = 15, deg = -4,
               large = false, sweep = false, x2 = 116, y2 = 419,
               width = 1.8, rgb = 0xFFE9B8, a = 0.90)
        val pip = IdlePlateMotion.alongArc(
            x1 = 244.0, y1 = 410.0, rx = 64.0, ry = 15.0, deg = -4.0,
            large = false, sweep = false, x2 = 116.0, y2 = 419.0,
            restU = 0.48, swing = 0.44, u = pose.satellite)
        riderPip(g, o = pip, front = true, cx = 180, cy = 414.5, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 2.6, rgb = 0xFFE9B8)
        riderPip(g, o = pip, front = false, cx = 180, cy = 414.5, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 2.6, rgb = 0xFFE9B8)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(70, 90, 1.1, 0xFFFAF0, 0.45), t(290, 60, 1.2, 0xFFFAF0, 0.50),
            t(180, 140, 1.0, 0xFFFAF0, 0.35), t(320, 200, 1.0, 0xFFFAF0, 0.30),
            t(40, 240, 1.0, 0xFFFAF0, 0.30),
        ), flares = listOf())
    }

    // Paper `22LI-1` · 160px violet ball at 170/150, lit from the left limb.
    private fun plate26(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        glow(g, at = P(250 * sx, 230 * sy),
             rx = 160 * s, ry = 160 * s, rgb = 0x6D28D9, a = 0.22 * pose.glow)
        sphere(g, c = P(pose.bodyX * sx, pose.bodyY * sy), r = 80 * s,
               hx = 196 * sx, hy = 198 * sy,
               stops = listOf(t(0, 0x8A72C8), t(0.28, 0x4A3288), t(0.58, 0x2A1A58),
                       t(0.84, 0x120C28), t(1, 0x080610)),
               air = 0x6D28D9, airA = 0.10, speckle = 0.04,
               specA = 0.05, nightA = 0.46, limbA = 0)
        glow(g, at = P(250 * sx, 230 * sy),
             rx = 94 * s, ry = 94 * s, rgb = 0xA78BFA, a = 0.08)
        paperHighlight(g, at = P(199 * sx, 188 * sy),
                       rx = 14 * s, ry = 8 * s, deg = 24, a = 0.10)
        orbitGuide(g, cx = pose.bodyX, cy = pose.bodyY, restX = 318, restY = 168,
                   flatten = 0.28, s = s, sx = sx, sy = sy, rgb = 0xC4B5FD, a = 0.16)
        val moon = ride(pose, cx = pose.bodyX, cy = pose.bodyY, restX = 318, restY = 168, flatten = 0.28)
        riderMoon(g, o = moon, front = false, cx = pose.bodyX, cy = pose.bodyY, occlude = 80,
                  s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xE6DEFF)
        riderMoon(g, o = moon, front = true, cx = pose.bodyX, cy = pose.bodyY, occlude = 80,
                  s = s, sx = sx, sy = sy, r = 3.2, rgb = 0xE6DEFF)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(42, 66, 1.3, 0xEBE6FF, 0.65), t(96, 34, 1.0, 0xEBE6FF, 0.45),
            t(160, 80, 1.2, 0xEBE6FF, 0.50), t(236, 40, 1.0, 0xEBE6FF, 0.55),
            t(310, 64, 1.4, 0xEBE6FF, 0.70), t(330, 130, 1.0, 0xEBE6FF, 0.40),
            t(60, 150, 1.1, 0xEBE6FF, 0.40), t(200, 120, 1.0, 0xEBE6FF, 0.35),
            t(120, 200, 0.9, 0xEBE6FF, 0.30),
        ), flares = listOf(t(78, 108, 5.4, 0xF0ECFF, 0.85), t(322, 190, 4.0, 0xF0ECFF, 0.55)))
    }

    // Paper `22MA-1` · two dashed far arcs + pip at 150/138.
    private fun plate27(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = -46.9, y1 = 368.5, rx = 289, ry = 289, deg = 0,
               large = false, sweep = true, x2 = 399.3, y2 = 151.8,
               width = 0.8, rgb = 0xBAE6FD, a = 0.16,
               marks = listOf(1.2, 8), markPhase = pose.dash * 8)
        svgArc(g, s = s, sx = sx, sy = sy,
               x1 = -30, y1 = 370, rx = 272, ry = 272, deg = 0,
               large = false, sweep = true, x2 = 390, y2 = 166,
               width = 0.9, rgb = 0xBAE6FD, a = 0.40,
               marks = listOf(1.6, 7), markPhase = pose.dash * 8)
        val pip = ride(pose, cx = 241, cy = 394, restX = 150, restY = 138, flatten = 1)
        riderPip(g, o = pip, front = false, cx = 241, cy = 394, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 2.6, rgb = 0xF0FDFF)
        riderPip(g, o = pip, front = true, cx = 241, cy = 394, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 2.6, rgb = 0xF0FDFF)
        glow(g, at = P(pip.x * sx, pip.y * sy),
             rx = 16 * s, ry = 16 * s, rgb = 0x38BDF8, a = 0.40 * pose.glow)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(52, 88, 1.2, 0xDCEBFF, 0.50), t(120, 46, 1.0, 0xDCEBFF, 0.40),
            t(216, 60, 1.3, 0xDCEBFF, 0.60), t(312, 44, 1.0, 0xDCEBFF, 0.45),
            t(332, 112, 1.1, 0xDCEBFF, 0.35), t(36, 180, 1.0, 0xDCEBFF, 0.35),
        ), flares = listOf())
    }

    // Paper `22CY-1` · 270px dark ball at 82/188, amber left glow, huge far arc.
    private fun plate15(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        bloom(g, at = P(320 * sx, 270 * sy),
              rx = 130 * s, ry = 130 * s, rgb = 0x1D4ED8, a = 0.05)
        mist(g, at = P(100 * sx, 280 * sy),
             rx = 170 * s, ry = 115 * s, rgb = 0xE05E10, a = 0.08)
        mist(g, at = P(135 * sx, 253 * sy),
             rx = 55 * s, ry = 43 * s, rgb = 0xF6A41C, a = 0.07)
        val c15 = P(217 * sx, 323 * sy)
        sphere(g, c = c15, r = 135 * s,
               hx = 152 * sx, hy = 231 * sy,
               stops = listOf(t(0, 0xA84A14), t(0.04, 0x6A2E0C), t(0.10, 0x2A1810),
                       t(0.22, 0x100C0A), t(0.55, 0x0A0806), t(1, 0x070709)),
               air = 0xE05E10, airA = 0.02, speckle = 0.02, specA = 0, nightA = 0,
               limbA = 0)
        featherRim(g, c = c15, r = 135 * s, rgb = 0x070709, inner = 0.64, pad = 1.0)
        strokeCircle(g, c = P(650 * sx, 458 * sy), r = 685 * s,
                     width = 1.5 * s, rgb = 0xFFEED6, a = 0.30)
        orbitGuide(g, cx = 160, cy = 90, restX = 286, restY = 72,
                   flatten = 0.38, s = s, sx = sx, sy = sy, rgb = 0xFFE9C9, a = 0.18)
        val moon = ride(pose, cx = 160, cy = 90, restX = 286, restY = 72, flatten = 0.38)
        riderMoon(g, o = moon, front = true, cx = 160, cy = 90, occlude = 0,
                  s = s, sx = sx, sy = sy, r = 3.4, rgb = 0xFFE9C9)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(52, 66, 1.3, 0xFFF4E0, 0.65), t(300, 48, 1.1, 0xFFF4E0, 0.50),
            t(332, 180, 1.0, 0xFFF4E0, 0.40), t(238, 96, 1.2, 0xFFF4E0, 0.45),
            t(150, 40, 1.0, 0xFFF4E0, 0.50), t(30, 330, 1.1, 0xFFF4E0, 0.35),
        ), flares = listOf())
    }

    // Paper `22J6-1` · 600px disc at −121/−50, painted craters, libration.
    // Lips are typed `PaperLip` SVG elliptical-arc strokes — not circular bowl rims.
    private fun plate23(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val cx = pose.bodyX; val cy = pose.bodyY
        val c = P(cx * sx, cy * sy)
        val pr = 300 * s
        val ox = pose.moonYaw * 1.4 * sx
        val oy = -pose.moonPitch * 1.8 * sy
        glow(g, at = P((cx - 40) * sx, (cy - 80) * sy),
             rx = 200 * s, ry = 180 * s, rgb = 0x3A3C48, a = 0.10 * pose.glow)
        orbitGuide(g, cx = 179, cy = 38, restX = 300, restY = 42,
                   flatten = 0.22, s = s, sx = sx, sy = sy, rgb = 0xFFF8E8, a = 0.16)
        val pip = ride(pose, cx = 179, cy = 38, restX = 300, restY = 42, flatten = 0.22)
        riderPip(g, o = pip, front = false, cx = 179, cy = 38, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 2.4, rgb = 0xFFF8E8)
        sphere(g, c = c, r = pr,
               hx = (47 + pose.moonYaw * 10) * sx, hy = (82 - pose.moonPitch * 4) * sy,
               stops = listOf(t(0, 0xF2F0E6), t(0.14, 0xC8C6BE), t(0.36, 0x8A8880),
                       t(0.62, 0x54524C), t(0.88, 0x1A1814), t(1, 0x080809)),
               air = 0xC0C4D0, airA = 0.03 * pose.glow, speckle = 0.05, seed = 223,
               specA = 0, nightA = 0, limbA = 0)
        discWash(g, c = c, r = pr, deg = 142, stops = listOf(
            ws(0, white(0.08)),
            ws(0.28, white(0)),
            ws(0.60, black(0.32)),
            ws(1, black(0.72)),
        ))
        paperCraters(g, origin = P(0.0, 0.0), disc = c, r = pr, s = s, sx = sx, sy = sy,
                     shiftX = ox, shiftY = oy,
                     mares = listOf(t(120, 150, 190, 150, 0.28), t(-30, 230, 170, 140, 0.22)),
                     pits = listOf())
        paperOvals(g, disc = c, r = pr, sx = sx, sy = sy, shiftX = ox, shiftY = oy,
                   ovals = listOf(
                    t(168, 168, 22, 19, 0.28),
                    t(248, 128, 14, 12, 0.24),
                    t(286, 248, 26, 22, 0.26),
                    t(118, 268, 16, 14, 0.24),
                    t(198, 220, 10, 9, 0.22),
                    t(64, 210, 11, 10, 0.20),
                    t(310, 88, 8, 7, 0.20),
                   ))
        g.fill(rectPath(0, 0, 358 * sx, 470 * sy),
               linear(listOf(ws(0.30, black(0)), ws(0.55, black(0.35)), ws(0.85, black(0.72))),
                      P(179 * sx, 0), P(179 * sx, 470 * sy)))
        riderPip(g, o = pip, front = true, cx = 179, cy = 38, occlude = 0,
                 s = s, sx = sx, sy = sy, r = 2.4, rgb = 0xFFF8E8)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(40, 36, 1.1, 0xFFFCF0, 0.40), t(300, 28, 0.9, 0xCFE4FF, 0.36),
            t(330, 70, 1.0, 0xFFFCF0, 0.32), t(18, 90, 0.8, 0xFFE9C9, 0.28),
            t(250, 48, 0.85, 0xFFFCF0, 0.30), t(88, 22, 0.75, 0xCFE4FF, 0.26),
            t(168, 16, 0.7, 0xFFFCF0, 0.28), t(318, 110, 0.7, 0xCFE4FF, 0.24),
        ), flares = listOf(t(58, 54, 3.6, 0xFFFCF0, 0.55)))
    }

    // Paper `22N2-1` · 160px ball at 99/108, edge-on rings on y=188.
    private fun plate28(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 188 * sy)
        bloom(g, at = P(180 * sx, 203 * sy),
              rx = 160 * s, ry = 95 * s, rgb = 0x67E8F9, a = 0.14)
        val moon = ride(pose, cx = 179, cy = 188, restX = 338, restY = 188, flatten = 0.04)
        riderMoon(g, o = moon, front = false, cx = 179, cy = 188, occlude = 80,
                  s = s, sx = sx, sy = sy, r = 3.0, rgb = 0xEAF2F8)
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = true, bands = listOf(
            t(162, 5, 1.6, 0.22, 0xC9D8E4),
            t(166, 6.5, 1.2, 0.14, 0xC9D8E4),
            t(170, 9, 1.0, 0.08, 0xC9D8E4),
        ))
        sphere(g, c = c, r = 80 * s, hx = 150 * sx, hy = 150 * sy,
               stops = listOf(t(0, 0xC8D2D8), t(0.16, 0xA8B4BC), t(0.42, 0x7A8A94),
                       t(0.66, 0x3A4A54), t(0.90, 0x1A2430), t(1, 0x0C1218)),
               air = 0x7FA8C8, airA = 0.08, speckle = 0.03, specA = 0, nightA = 0,
               limbA = 0)
        discWash(g, c = c, r = 80 * s, deg = 148, stops = listOf(
            ws(0, white(0.16)),
            ws(0.36, white(0)),
            ws(0.66, col(0x0A1016, 0.18)),
            ws(1, col(0x080C10, 0.62)),
        ))
        g.layer {
            g.clip(oval(c.x - 80 * s, c.y - 80 * s, 160 * s, 160 * s))
            glow(g, at = P(c.x, c.y + 1 * s),
                 rx = 72 * s, ry = 7 * s, rgb = 0xEAF2F8, a = 0.32)
        }
        fineRings(g, c = c, deg = pose.ringDeg, s = s, back = false, bands = listOf(
            t(162, 5, 1.7, 0.90, 0xEAF2F8),
            t(166, 6.5, 1.25, 0.50, 0xEAF2F8),
            t(170, 9, 1.0, 0.28, 0xEAF2F8),
        ))
        ansaGlow(g, c = c, rx = 166 * s, ry = 6.5 * s, deg = pose.ringDeg,
                 pose = pose, s = s, rgb = 0xF4FBFF)
        riderMoon(g, o = moon, front = true, cx = 179, cy = 188, occlude = 80,
                  s = s, sx = sx, sy = sy, r = 3.0, rgb = 0xEAF2F8)
        paperStars(g, pose = pose, s = s, sx = sx, sy = sy, dots = listOf(
            t(44, 62, 1.3, 0xE2F0FF, 0.60), t(110, 36, 1.0, 0xE2F0FF, 0.42),
            t(180, 74, 1.2, 0xE2F0FF, 0.50), t(268, 42, 1.0, 0xE2F0FF, 0.55),
            t(326, 86, 1.4, 0xE2F0FF, 0.65), t(64, 132, 1.0, 0xE2F0FF, 0.35),
            t(332, 160, 1.1, 0xE2F0FF, 0.40),
        ), flares = listOf())
    }

    private fun ride(pose: IdlePlatePose, cx: Number, cy: Number, restX: Number, restY: Number,
                     flatten: Number): IdleOrbit =
        IdlePlateMotion.around(cx = cx.d, cy = cy.d, restX = restX.d, restY = restY.d,
                               flatten = flatten.d, u = pose.satellite)

    /** The closed ellipse `ride` traces, so a shepherd reads as orbit not a blink. */
    private fun orbitGuide(g: PlateGc, cx: Number, cy: Number, restX: Number, restY: Number,
                           flatten: Number, s: Double, sx: Double, sy: Double,
                           rgb: Int = 0xD8DCE8, a: Number = 0.16) {
        val path = Path()
        for (i in 0..48) {
            val o = IdlePlateMotion.around(cx = cx.d, cy = cy.d, restX = restX.d, restY = restY.d,
                                           flatten = flatten.d, u = i / 48.0)
            val p = P(o.x * sx, o.y * sy)
            if (i == 0) path.move(p) else path.line(p)
        }
        g.stroke(path, col(rgb, a), width = max(0.65, 0.8 * s), dash = listOf(1.5 * s, 5.2 * s))
    }

    private fun occulted(o: IdleOrbit, cx: Number, cy: Number, r: Number): Boolean {
        if (o.front) return false
        val dx = o.x - cx.d; val dy = o.y - cy.d
        return dx * dx + dy * dy < r.d * r.d
    }

    private fun paintMoon(g: PlateGc, o: IdleOrbit, s: Double, sx: Double, sy: Double,
                          r: Number = 3.5, rgb: Int = 0xE8D9B0) {
        val p = P(o.x * sx, o.y * sy)
        val k = if (o.front) 1.0 else 0.55
        glow(g, at = p, rx = r.d * 2.6 * s, ry = r.d * 2.6 * s, rgb = rgb, a = 0.30 * k)
        sphere(g, c = p, r = r.d * s, hx = p.x - 0.32 * r.d * s, hy = p.y - 0.36 * r.d * s,
               stops = listOf(t(0, 0xFFFCF0), t(0.55, rgb), t(1, 0x8A7A58)),
               air = rgb, airA = 0.12 * k, speckle = 0)
    }

    private fun paintPip(g: PlateGc, o: IdleOrbit, s: Double, sx: Double, sy: Double,
                         r: Number, rgb: Int, a: Double = 0.92) {
        val p = P(o.x * sx, o.y * sy)
        val k = if (o.front) 1.0 else 0.50
        paperPip(g, at = p, r = r.d * s, rgb = rgb, a = a * k)
    }

    private fun riderMoon(g: PlateGc, o: IdleOrbit, front: Boolean, cx: Number, cy: Number,
                          occlude: Number, s: Double, sx: Double, sy: Double,
                          r: Number = 3.5, rgb: Int = 0xE8D9B0) {
        if (o.front != front) return
        if (!front && occulted(o, cx, cy, occlude)) return
        paintMoon(g, o = o, s = s, sx = sx, sy = sy, r = r, rgb = rgb)
    }

    private fun riderPip(g: PlateGc, o: IdleOrbit, front: Boolean, cx: Number, cy: Number,
                         occlude: Number, s: Double, sx: Double, sy: Double,
                         r: Number, rgb: Int, a: Double = 0.92) {
        if (o.front != front) return
        if (!front && occulted(o, cx, cy, occlude)) return
        paintPip(g, o = o, s = s, sx = sx, sy = sy, r = r, rgb = rgb, a = a)
    }

    private fun saturn(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double,
                       cx: Number, cy: Number, r: Number, hx: Number, hy: Number,
                       stops: List<DoubleArray>, air: Int, airA: Number,
                       ringRX: Number, ringRY: Number, ringDeg: Number,
                       ring: Int, dust: Int, gap: Number, wide: Number,
                       moon: P? = null, dimRing: Boolean = false) {
        val c = P(cx.d * sx, cy.d * sy)
        val pr = r.d * s
        glow(g, at = c, rx = pr * 2.15, ry = pr * 1.85, rgb = air, a = airA.d * pose.glow * 1.15)
        glow(g, at = c, rx = pr * 1.45, ry = pr * 1.25, rgb = air, a = airA.d * 0.55 * pose.glow)
        if (ringRX.d > 4) {
            rings(g, c = c, rx = ringRX.d * s, ry = ringRY.d * s, deg = ringDeg.d,
                  pose = pose, rgb = ring, dust = dust, gap = gap.d * s, wide = wide.d * s,
                  dim = dimRing, back = true)
        }
        sphere(g, c = c, r = pr, hx = hx.d * sx, hy = hy.d * sy, stops = stops,
               air = air, airA = airA.d * 0.35)
        if (ringRX.d > 4) {
            ringShadow(g, c = c, r = pr, rx = ringRX.d * s, ry = ringRY.d * s,
                       deg = ringDeg.d, rgb = 0x050403, a = if (dimRing) 0.16 else 0.22)
            rings(g, c = c, rx = ringRX.d * s, ry = ringRY.d * s, deg = ringDeg.d,
                  pose = pose, rgb = ring, dust = dust, gap = gap.d * s, wide = wide.d * s,
                  dim = dimRing, back = false)
        }
        if (moon != null) {
            glow(g, at = moon, rx = 8 * s, ry = 8 * s, rgb = 0xE8D9B0, a = 0.28 * pose.glow)
            sphere(g, c = moon, r = 3.6 * s, hx = moon.x - 1.2 * s, hy = moon.y - 1.4 * s,
                   stops = listOf(t(0, 0xFFF8EC), t(0.55, 0xE8D9B0), t(1, 0x8A7A58)),
                   air = 0xE8D9B0, airA = 0.10)
        }
    }

    private fun sphere(g: PlateGc, c: P, r: Number, hx: Number, hy: Number,
                       stops: List<DoubleArray>, air: Int, airA: Number,
                       speckle: Number = 0.12, seed: Int = 0,
                       specA: Number = 0.36, nightA: Number = 0.68,
                       rim: Pair<Int, Double>? = null, limbA: Number = 0.10) {
        val r = r.d
        val disc = oval(c.x - r, c.y - r, r * 2, r * 2)
        g.fill(disc, col(stops.lastOrNull()?.get(1)?.toInt() ?: 0x0A0A0C))
        val key = P(hx.d, hy.d)
        g.fill(disc, radial(stops.map { it[0] to col(it[1].toInt()) }, key, 0.0, r * 1.38))
        val night = P(c.x * 2 - key.x, c.y * 2 - key.y)
        val nA = nightA.d
        g.fill(disc, radial(evenly(col(0x050508, 0), col(0x050508, nA * 0.28), col(0x050508, nA)),
                            night, r * 0.12, r * 1.45))
        g.fill(disc, radial(evenly(white(0), black(nA * 0.28)), c, r * 0.62, r * 1.02))
        val spec = P(c.x + (key.x - c.x) * 0.42, c.y + (key.y - c.y) * 0.42)
        if (specA.d > 0.02) {
            g.fill(oval(spec.x - r * 0.22, spec.y - r * 0.13, r * 0.44, r * 0.26),
                   radial(evenly(white(specA), white(0)), spec, 0.0, r * 0.24))
        }
        if (speckle.d > 0.02) {
            grain(g, c = c, r = r, amount = speckle.d, seed = seed)
        }
        if (rim != null) {
            g.stroke(disc, col(rim.first, rim.second * 0.55), width = max(1.2, r * 0.035))
            glow(g, at = P(c.x + r * 0.55, c.y - r * 0.15),
                 rx = r * 0.55, ry = r * 0.7, rgb = rim.first, a = rim.second * 0.18)
        } else if (limbA.d > 0.01) {
            g.stroke(disc, white(limbA), width = 1.0)
        }
        glow(g, at = c, rx = r * 1.12, ry = r * 1.12, rgb = air, a = airA.d * 0.45)
    }

    private fun grain(g: PlateGc, c: P, r: Double, amount: Double, seed: Int) {
        g.layer {
            g.clip(oval(c.x - r, c.y - r, r * 2, r * 2))
            val n = if (amount > 0.4) 56 else 36
            for (i in 0 until n) {
                val k = (seed * 13 + i + 1).toDouble()
                val ang = hash(k, 12.9898) * PI * 2
                val rad = (0.18 + 0.72 * hash(k, 78.233)) * r
                val p = P(c.x + cos(ang) * rad, c.y + sin(ang) * rad)
                val rr = (0.9 + 2.4 * hash(k, 39.425)) * (r / 82)
                val dark = hash(k, 57.117) > 0.45
                g.fill(oval(p.x - rr, p.y - rr, rr * 2, rr * 2), white(if (dark) 0.0 else 0.07 * amount))
                if (dark) {
                    g.fill(oval(p.x - rr, p.y - rr, rr * 2, rr * 2), black(0.16 * amount))
                }
            }
        }
    }

    private fun ansaGlow(g: PlateGc, c: P, rx: Number, ry: Number, deg: Number,
                         pose: IdlePlatePose, s: Double, rgb: Int) {
        val tau = pose.satellite * PI * 2
        val a = deg.d * PI / 180
        val ca = cos(a); val sa = sin(a)
        val x = c.x + rx.d * cos(tau) * ca - ry.d * sin(tau) * sa
        val y = c.y + rx.d * cos(tau) * sa + ry.d * sin(tau) * ca
        val front = sin(tau) >= 0
        val k = if (front) 1.0 else 0.42
        glow(g, at = P(x, y), rx = 7 * s, ry = 4.2 * s, rgb = rgb, a = 0.34 * k)
        fillDot(g, at = P(x, y), r = 1.6 * s, rgb = rgb, a = 0.72 * k)
    }

    private fun rings(g: PlateGc, c: P, rx: Double, ry: Double, deg: Double,
                      pose: IdlePlatePose, rgb: Int, dust: Int,
                      gap: Double, wide: Double, dim: Boolean, back: Boolean? = null) {
        val a = deg * PI / 180
        val halves: List<Boolean> = back?.let { listOf(it) } ?: listOf(true, false)
        for (isBack in halves) {
            if (wide > 1) {
                strokeEllipse(g, c = c, rx = rx, ry = ry, rot = a, back = isBack,
                              width = wide, rgb = dust,
                              a = (if (isBack) 0.16 else 0.28) * (if (dim) 0.45 else 1.0))
            }
            val lines: List<DoubleArray> = if (gap > 1) listOf(
                t(0, if (dim) 1.4 else 1.7,
                  if (dim) (if (isBack) 0.30 else 0.70) else (if (isBack) 0.34 else 0.90)),
                t(gap, if (dim) 1.1 else 1.25,
                  if (dim) (if (isBack) 0.20 else 0.42) else (if (isBack) 0.22 else 0.55)),
                t(gap * 2, 1.0,
                  if (dim) (if (isBack) 0.12 else 0.25) else (if (isBack) 0.12 else 0.32)),
            ) else listOf(t(0, 1.6, if (isBack) 0.30 else 0.42))
            for (l in lines) {
                val gg = l[0]; val w = l[1]; val al = l[2]
                val scale = 1 + gg / max(rx, 1.0)
                strokeEllipse(g, c = c, rx = rx + gg, ry = ry * scale, rot = a,
                              back = isBack, width = w, rgb = rgb, a = al)
            }
            if (!isBack && !dim) {
                strokeEllipse(g, c = c, rx = rx + 4, ry = ry + 1, rot = a, back = false,
                              width = 7.0, rgb = rgb, a = 0.08)
                ansaGlow(g, c = c, rx = rx, ry = ry, deg = deg,
                         pose = pose, s = max(rx / 150, 0.7), rgb = rgb)
            }
        }
    }

    private fun fineRings(g: PlateGc, c: P, deg: Double, s: Double, back: Boolean,
                          bands: List<DoubleArray>) {
        val rot = deg * PI / 180
        for (b in bands) {
            strokeEllipse(g, c = c, rx = b[0] * s, ry = b[1] * s, rot = rot,
                          back = back, width = max(0.7, b[2] * s), rgb = b[4].toInt(), a = b[3])
        }
    }

    private fun paperStars(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double,
                           dots: List<DoubleArray>, flares: List<DoubleArray>) {
        for (d in dots) {
            val tw = 0.72 + 0.28 * sin(pose.phase * PI * 2 + d[0] * 0.03)
            fillDot(g, at = P(d[0] * sx, d[1] * sy), r = d[2] * s, rgb = d[3].toInt(), a = d[4] * tw)
        }
        for (f in flares) {
            val tw = 0.70 + 0.30 * sin(pose.phase * PI * 4 + f[1] * 0.02)
            flare(g, at = P(f[0] * sx, f[1] * sy), r = f[2] * s, rgb = f[3].toInt(), a = f[4] * tw)
        }
    }

    /** Paper crater highlight: an SVG elliptical-arc stroke, not a circular rim. */
    private class PaperLip(val x1: Double, val y1: Double, val rx: Double, val ry: Double,
                           val x2: Double, val y2: Double, val width: Double, val a: Double)

    /** Dissolve a hard disc edge into ink so a Paper soft moon does not read as a cut-out. */
    private fun featherRim(g: PlateGc, c: P, r: Number, rgb: Int = 0x070709,
                           inner: Number = 0.86, pad: Number = 1.12) {
        val outer = r.d * pad.d
        if (!(outer > 0 && inner.d < 1)) return
        val start = min(0.98, (r.d * inner.d) / outer)
        g.fill(oval(c.x - outer, c.y - outer, outer * 2, outer * 2),
               radial(listOf(
                   ws(start, col(rgb, 0)),
                   ws(start + (1 - start) * 0.42, col(rgb, 0.42)),
                   ws(start + (1 - start) * 0.80, col(rgb, 0.88)),
                   ws(1, col(rgb, 1)),
               ), c, 0.0, outer))
    }

    private fun discWash(g: PlateGc, c: P, r: Number, deg: Number, stops: List<Pair<Double, Color>>) {
        val r = r.d
        g.layer {
            val disc = oval(c.x - r, c.y - r, r * 2, r * 2)
            g.clip(disc)
            val rad = deg.d * PI / 180
            val vx = sin(rad); val vy = -cos(rad)
            g.fill(disc, linear(stops, P(c.x - vx * r, c.y - vy * r), P(c.x + vx * r, c.y + vy * r)))
        }
    }

    private fun paperOvals(g: PlateGc, disc: P, r: Double, sx: Double, sy: Double,
                           shiftX: Double, shiftY: Double, ovals: List<DoubleArray>) {
        g.layer {
            g.clip(oval(disc.x - r, disc.y - r, r * 2, r * 2))
            for (o in ovals) {
                g.fill(oval((o[0] - o[2]) * sx + shiftX, (o[1] - o[3]) * sy + shiftY,
                            o[2] * 2 * sx, o[3] * 2 * sy), black(o[4]))
            }
        }
    }

    private fun paperLips(g: PlateGc, s: Double, sx: Double, sy: Double,
                          shiftX: Double, shiftY: Double, lips: List<PaperLip>) {
        for (lip in lips) {
            svgArc(g, s = s, sx = sx, sy = sy,
                   x1 = lip.x1 + shiftX / sx, y1 = lip.y1 + shiftY / sy,
                   rx = lip.rx, ry = lip.ry, deg = 0,
                   large = false, sweep = true,
                   x2 = lip.x2 + shiftX / sx, y2 = lip.y2 + shiftY / sy,
                   width = lip.width, rgb = 0xFFFAF0, a = lip.a)
        }
    }

    private fun paperCraters(g: PlateGc, origin: P, disc: P, r: Double,
                             s: Double, sx: Double, sy: Double,
                             shiftX: Number, shiftY: Number,
                             mares: List<DoubleArray>, pits: List<DoubleArray>) {
        g.layer {
            g.clip(oval(disc.x - r, disc.y - r, r * 2, r * 2))
            for (m in mares) {
                val x = origin.x + m[0] * sx + shiftX.d
                val y = origin.y + m[1] * sy + shiftY.d
                val w = m[2] * sx; val h = m[3] * sy
                val center = P(x + w / 2, y + h / 2)
                g.fill(oval(x, y, w, h),
                       radial(evenly(black(m[4]), black(m[4] * 0.35), black(0)),
                              center, 0.0, max(w, h) * 0.55))
            }
            for (p in pits) {
                val rr = p[2] * sx * 0.5
                val c = P(origin.x + p[0] * sx + shiftX.d, origin.y + p[1] * sy + shiftY.d)
                g.fill(oval(c.x - rr, c.y - rr * 0.86, rr * 2, rr * 1.72),
                       radial(evenly(black(p[3]), black(p[3] * 0.45), black(0)), c, 0.0, rr * 1.15))
            }
        }
    }

    private fun ringShadow(g: PlateGc, c: P, r: Double, rx: Double, ry: Double,
                           deg: Double, rgb: Int, a: Double) {
        g.layer {
            g.clip(oval(c.x - r, c.y - r, r * 2, r * 2))
            strokeEllipse(g, c = c, rx = min(rx, r * 0.98), ry = max(3.0, ry * 0.55),
                          rot = deg * PI / 180, back = false, width = 5.0, rgb = rgb, a = a)
        }
    }

    // MARK: moon

    private class MoonFeat(val lon: Double, val lat: Double, val size: Double,
                           val depth: Double, val mare: Boolean)

    private val moonClose: List<MoonFeat> by lazy {
        val rng = PlateRNG(223)
        val feats = mutableListOf<MoonFeat>()
        repeat(3) {
            val lon = rng.uniform(-1.1, 1.1); val lat = rng.uniform(-0.55, 0.85)
            val size = rng.uniform(0.22, 0.33); val depth = rng.uniform(0.26, 0.36)
            feats.add(MoonFeat(lon, lat, size, depth, mare = true))
        }
        for (i in 0 until 22) {
            val big = i < 6
            val lon = rng.uniform(-1.3, 1.3); val lat = rng.uniform(-0.85, 1.1)
            val size = if (big) rng.uniform(0.08, 0.13) else rng.uniform(0.04, 0.075)
            val depth = if (big) rng.uniform(0.45, 0.6) else rng.uniform(0.34, 0.52)
            feats.add(MoonFeat(lon, lat, size, depth, mare = false))
        }
        feats
    }

    private fun moon(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double,
                     cx: Double, cy: Double, r: Double, hx: Double, hy: Double,
                     close: Boolean, seed: Int) {
        val c = P(cx * sx, cy * sy)
        val pr = r * s
        glow(g, at = P((cx - 40) * sx, (cy - 60) * sy),
             rx = pr * 1.15, ry = pr * 1.05, rgb = 0x3A3C48, a = 0.12 * pose.glow)
        glow(g, at = c, rx = pr * 1.08, ry = pr * 1.08, rgb = 0x8A8AA8, a = 0.08 * pose.glow)
        val stops = if (close)
            listOf(t(0, 0x0A0A0A), t(0.28, 0x2C2A26), t(0.52, 0x6A6860), t(0.74, 0x9C9A91), t(1, 0xD6D4CC))
        else listOf(t(0, 0xEAEAE6), t(0.32, 0x9A9A96), t(0.62, 0x3C3C3A), t(1, 0x0A0A0A))
        // Close-up is a lit body (dark→bright). Full-bleed plate 02 keeps the
        // rim-lit catalogue ramp so it stays a pale disc, not a second 23.
        val key = P(hx * sx, hy * sy)
        sphere(g, c = c, r = pr, hx = key.x, hy = key.y, stops = stops,
               air = 0x555550, airA = 0.10 * pose.glow, speckle = if (close) 0.12 else 0.22,
               seed = seed, rim = if (close) null else (0xEAEAE6 to 0.08))
        if (close) {
            relief(g, c = c, r = pr, yaw = pose.moonYaw * PI / 180,
                   pitch = pose.moonPitch * PI / 180, s = s)
            glow(g, at = P(c.x - pr * 0.55, c.y - pr * 0.35),
                 rx = pr * 0.55, ry = pr * 0.40, rgb = 0xB8C4E8, a = 0.06)
        } else {
            val rng = PlateRNG(seed)
            g.layer {
                g.clip(oval(c.x - pr, c.y - pr, pr * 2, pr * 2))
                repeat(18) {
                    val ax = c.x + rng.uniform(-0.62, 0.62) * pr
                    val ay = c.y + rng.uniform(-0.62, 0.62) * pr
                    val sr = rng.uniform(0.04, 0.13) * pr
                    g.fill(oval(ax - sr, ay - sr, sr * 2, sr * 2), black(0.16))
                }
            }
        }
    }

    private fun relief(g: PlateGc, c: P, r: Double, yaw: Double, pitch: Double, s: Double) {
        val cyaw = cos(yaw); val syaw = sin(yaw)
        val cpi = cos(pitch); val spi = sin(pitch)
        g.layer {
            g.clip(oval(c.x - r, c.y - r, r * 2, r * 2))
            for (feat in moonClose) {
                var px = cos(feat.lat) * sin(feat.lon)
                var py = sin(feat.lat)
                var pz = cos(feat.lat) * cos(feat.lon)
                val px2 = px * cyaw + pz * syaw
                pz = -px * syaw + pz * cyaw
                px = px2
                val py2 = py * cpi - pz * spi
                pz = py * spi + pz * cpi
                py = py2
                if (pz <= 0.08) continue
                val fx = c.x + px * r
                val fy = c.y - py * r
                val fade = min(1.0, pz / 0.35)
                val rx = feat.size * r
                val ry = rx * pz
                val rect = oval(fx - rx, fy - ry, rx * 2, ry * 2)
                if (feat.mare) {
                    g.fill(rect, black(0.22 * fade * feat.depth))
                    continue
                }
                g.fill(rect, black(0.28 * fade * feat.depth))
                val rim = oval(fx - rx * 1.08, fy - ry * 1.08, rx * 2.16, ry * 2.16)
                g.stroke(rim, white(0.16 * fade), width = max(0.8, rx * 0.08))
                val lit = P(fx - rx * 0.28, fy - ry * 0.22)
                g.fill(oval(lit.x - rx * 0.18, lit.y - ry * 0.10, rx * 0.36, ry * 0.20),
                       white(0.14 * fade))
            }
        }
    }

    // MARK: lines / arcs

    private fun swirls(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 215 * sy)
        glow(g, at = c, rx = 40 * s, ry = 30 * s, rgb = 0x5E7A92, a = 0.40 * pose.glow)
        class Arc(val rr: Double, val w: Double, val col: Int, val al: Double, val t0: Double,
                  val t1: Double, val dash: Pair<Int, Double>?, val sw: Double, val ph: Double)
        val arcs = listOf(
            Arc(46.0, 2.2, 0xAFC6D8, 0.50, 20.0, 200.0, null, 4.0, 0.0),
            Arc(66.0, 1.8, 0x7E93A8, 0.42, 150.0, 340.0, 10 to 0.5, 5.0, 1.1),
            Arc(86.0, 2.4, 0xC3D4E2, 0.46, 260.0, 460.0, null, 4.0, 2.2),
            Arc(106.0, 1.6, 0x6E8199, 0.38, 40.0, 210.0, 14 to 0.45, 6.0, 0.6),
            Arc(126.0, 2.0, 0x9FB4C8, 0.42, 190.0, 400.0, null, 5.0, 1.7),
            Arc(146.0, 1.6, 0x8AA0B4, 0.34, 300.0, 520.0, 16 to 0.4, 6.0, 2.8),
            Arc(164.0, 1.4, 0x5E7185, 0.30, 90.0, 260.0, 18 to 0.4, 7.0, 2.0),
        )
        for (a in arcs) {
            val deg = -18 + a.sw * sin(pose.phase * PI * 2 + a.ph)
            strokeEllipse(g, c = c, rx = a.rr * s, ry = a.rr * 0.42 * s, rot = deg * PI / 180,
                          back = false, width = a.w * s, rgb = a.col, a = a.al,
                          arc = a.t0 to a.t1, dash = a.dash, dashOff = 0.0)
            strokeEllipse(g, c = c, rx = a.rr * s, ry = a.rr * 0.42 * s, rot = deg * PI / 180,
                          back = true, width = a.w * 0.8 * s, rgb = a.col, a = a.al * 0.45,
                          arc = a.t0 to a.t1, dash = a.dash, dashOff = 0.0)
        }
    }

    private fun dashedOrbits(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 205 * sy)
        glow(g, at = c, rx = 55 * s, ry = 55 * s, rgb = 0x2E3E50, a = 0.38 * pose.glow)
        dashEllipse(g, c = c, rx = 72 * s, ry = 72 * s, rot = 0.0, n = 18, pose = pose,
                    rgb = 0xB8C4D0, a = 0.60)
        dashedLine(g, pose = pose, s = s, from = P(10 * sx, 70 * sy), to = P(348 * sx, 310 * sy),
                   n = 20, rgb = 0x8AA0B8, a = 0.30)
        dashedLine(g, pose = pose, s = s, from = P(30 * sx, 330 * sy), to = P(328 * sx, 60 * sy),
                   n = 18, rgb = 0x8AA0B8, a = 0.26, reverse = true)
        glow(g, at = P(179 * sx, 133 * sy), rx = 6 * s, ry = 6 * s, rgb = 0xD8E4F0,
             a = 0.55 * pose.breathe)
    }

    private fun beam(g: PlateGc, pose: IdlePlatePose, s: Double, from: P, to: P) {
        val path = Path().apply { move(from); line(to) }
        g.stroke(path, col(0xD8DEE6, 0.50), width = 1.4 * s, cap = StrokeCap.Round)
        glow(g, at = to, rx = 24 * s, ry = 24 * s, rgb = 0x7FB2D8, a = 0.44 * pose.glow)
        glow(g, at = to, rx = 9 * s, ry = 9 * s, rgb = 0xEAF4FF, a = 0.88 * pose.glow)
        glow(g, at = from, rx = 6 * s, ry = 6 * s, rgb = 0xB8C8D8, a = 0.34 * pose.breathe)
    }

    private fun beamCore(g: PlateGc, pose: IdlePlatePose, s: Double, from: P, to: P) {
        val fat = Path().apply { move(from); line(to) }
        g.stroke(fat, col(0x7FA8C8, 0.10 * pose.glow), width = 26 * s, cap = StrokeCap.Round)
        val core = Path().apply { move(from); line(to) }
        g.stroke(core, col(0xA8CCE8, 0.24 * pose.glow), width = 2 * s, cap = StrokeCap.Round)
    }

    private fun horizon(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        glow(g, at = P(179 * sx, 302 * sy), rx = 165 * s, ry = 24 * s, rgb = 0xE05E10, a = 0.55 * pose.glow)
        glow(g, at = P(179 * sx, 296 * sy), rx = 130 * s, ry = 9 * s, rgb = 0xF6A41C, a = 0.46 * pose.glow)
        sphere(g, c = P(179 * sx, 218 * sy), r = 88 * s, hx = 179 * sx, hy = 60 * sy,
               stops = listOf(t(0, 0x2A1410), t(0.4, 0x1A0D0A), t(0.7, 0x0C0706), t(1, 0x050303)),
               air = 0xE05E10, airA = 0.16, rim = 0xE05E10 to 1.0)
        glow(g, at = P(179 * sx, 300 * sy), rx = 130 * s, ry = 40 * s, rgb = 0x7C2D12, a = 0.34 * pose.glow)
    }

    private fun emberPoint(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        glow(g, at = P(179 * sx, 318 * sy), rx = 34 * s, ry = 18 * s, rgb = 0xE05E10, a = 0.48 * pose.glow)
        glow(g, at = P(179 * sx, 316 * sy), rx = 12 * s, ry = 8 * s, rgb = 0xF6A41C, a = 0.56 * pose.glow)
        strokeEllipse(g, c = P(179 * sx, 252 * sy), rx = 60 * s, ry = 30 * s, rot = 0.0, back = false,
                      width = 2 * s, rgb = 0xF6A41C, a = 0.50 * pose.breathe, arc = 200.0 to 340.0)
        glow(g, at = P(179 * sx, 252 * sy), rx = 30 * s, ry = 20 * s, rgb = 0x7C2D12, a = 0.22 * pose.glow)
    }

    private fun equator(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 212 * sy)
        glow(g, at = c, rx = 100 * s, ry = 60 * s, rgb = 0x2E3E4C, a = 0.32 * pose.glow)
        rings(g, c = c, rx = 162 * s, ry = 4 * s, deg = 0.0, pose = pose,
              rgb = 0xC9D8E4, dust = 0xC9D8E4, gap = 2.5 * s, wide = 0.0, dim = true, back = true)
        sphere(g, c = c, r = 88 * s, hx = 150 * sx, hy = 170 * sy,
               stops = listOf(t(0, 0xE8F0F4), t(0.22, 0xC9D4DC), t(0.50, 0x7E8E9A),
                              t(0.76, 0x2E3A44), t(1, 0x0A0E12)),
               air = 0x2E3E4C, airA = 0.22)
        g.layer {
            g.clip(oval(c.x - 88 * s, c.y - 88 * s, 176 * s, 176 * s))
            glow(g, at = P(c.x, c.y + 8 * s), rx = 70 * s, ry = 8 * s, rgb = 0xE8F0F4, a = 0.28)
        }
        strokeEllipse(g, c = c, rx = 162 * s, ry = 4 * s, rot = 0.0, back = false,
                      width = 1.6 * s, rgb = 0xEAF2F8, a = 0.88 * pose.breathe)
        strokeEllipse(g, c = c, rx = 162 * s, ry = 6.5 * s, rot = 0.0, back = false,
                      width = 1.2 * s, rgb = 0xEAF2F8, a = 0.52 * pose.breathe)
        strokeEllipse(g, c = c, rx = 162 * s, ry = 9 * s, rot = 0.0, back = false,
                      width = 1.0 * s, rgb = 0xEAF2F8, a = 0.32 * pose.breathe)
        glow(g, at = c, rx = 150 * s, ry = 6 * s, rgb = 0x7FA8C8, a = 0.28 * pose.breathe)
    }

    private fun rainbowSaturn(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        val c = P(179 * sx, 205 * sy)
        glow(g, at = c, rx = 100 * s, ry = 85 * s, rgb = 0x3A3444, a = 0.32 * pose.glow)
        val segs = listOf(0xEF4444, 0xF6A41C, 0xFDE047, 0x34D399, 0x38BDF8, 0xA78BFA)
        segmentRing(g, c = c, rx = 150 * s, ry = 40 * s, deg = pose.ringDeg,
                    width = 8 * s, colors = segs, a = 0.40, back = true)
        sphere(g, c = c, r = 70 * s, hx = 150 * sx, hy = 170 * sy,
               stops = listOf(t(0, 0xF2EEE4), t(0.4, 0xC9C0AC), t(0.7, 0x5E5748), t(1, 0x14120C)),
               air = 0x3A3444, airA = 0.20)
        segmentRing(g, c = c, rx = 150 * s, ry = 40 * s, deg = pose.ringDeg,
                    width = 8 * s, colors = segs, a = 0.60, back = false)
        for (f in listOf(t(70.0, 90.0, 7.0), t(300.0, 130.0, 6.0), t(90.0, 330.0, 5.0))) {
            flare(g, at = P(f[0] * sx, f[1] * sy), r = f[2] * s, rgb = 0xFFFFFF, a = 0.50 * pose.breathe)
        }
    }

    private enum class NebulaKind { violet, magenta }

    private fun nebula(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double, kind: NebulaKind) {
        val blobs: List<DoubleArray> = when (kind) {
            NebulaKind.violet -> listOf(
                t(90, 140, 90, 60, -20, 0x6D28D9, 0.24, 8, 5, 1, 0.0),
                t(260, 240, 100, 70, 15, 0xA78BFA, 0.18, 7, 6, 1, 2.1),
                t(150, 330, 90, 55, -10, 0x4F46E5, 0.20, 6, 5, 2, 1.0),
                t(300, 90, 70, 50, 0, 0x6D28D9, 0.16, 6, 4, 2, 3.3),
            )
            NebulaKind.magenta -> listOf(
                t(80, 100, 80, 55, -30, 0xE84393, 0.24, 7, 5, 1, 0.0),
                t(170, 200, 95, 65, -30, 0xD774B4, 0.22, 8, 6, 1, 1.9),
                t(270, 310, 85, 60, -30, 0xE84393, 0.20, 6, 5, 2, 0.8),
                t(300, 80, 60, 45, 0, 0xA78BFA, 0.16, 5, 4, 2, 2.6),
            )
        }
        for (b in blobs) {
            val ox = b[7] * sin(pose.phase * PI * 2 * b[9] + b[10])
            val oy = b[8] * sin(pose.phase * PI * 2 * b[9] + b[10] + 1.3)
            glow(g, at = P((b[0] + ox) * sx, (b[1] + oy) * sy),
                 rx = b[2] * s, ry = b[3] * s, rgb = b[5].toInt(), a = b[6], deg = b[4])
        }
    }

    private fun comet(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double) {
        strokeEllipse(g, c = P(200 * sx, 260 * sy), rx = 235 * s, ry = 135 * s, rot = 8 * PI / 180,
                      back = false, width = 1 * s, rgb = 0x2E4A66, a = 0.30, arc = 150.0 to 330.0)
        val tt = pose.comet
        val env = sin(PI * tt).pow(1.3)
        if (!(env > 0.01)) return
        fun path(q: Double): P {
            val ax = 372.0; val ay = 150.0; val bx = 330.0; val by = 310.0; val cx = 96.0; val cy = 300.0
            val u = 1 - q
            return P((u * u * ax + 2 * u * q * bx + q * q * cx) * sx,
                     (u * u * ay + 2 * u * q * by + q * q * cy) * sy)
        }
        for (j in 0 until 26) {
            val q = tt - j * 0.012
            if (q <= 0) continue
            val a = env * (1 - j / 26.0).pow(2) * 0.32
            val rr = max(6.5 - j * 0.2, 1.2) * s
            glow(g, at = path(q), rx = rr, ry = rr, rgb = 0x38BDF8, a = a)
        }
        val head = path(tt)
        glow(g, at = head, rx = 17 * s, ry = 17 * s, rgb = 0x38BDF8, a = env * 0.50)
        glow(g, at = head, rx = 7 * s, ry = 7 * s, rgb = 0xEAF6FF, a = env * 0.90)
    }

    // MARK: stars

    private fun stars(g: PlateGc, pose: IdlePlatePose, s: Double, sx: Double, sy: Double,
                      seed: Int, n: Int, ymax: Double = 295.0,
                      xlo: Double = 16.0, xhi: Double = 342.0, flares: Int = 1) {
        val rng = PlateRNG(seed)
        val palette = listOf(0xFFFFFF, 0xFFE9C9, 0xCFE4FF)
        for (i in 0 until n) {
            val bright = rng.next() < 0.35
            val r = (if (bright) rng.uniform(1.1, 1.6) else rng.uniform(0.7, 1.05)) * s
            val a0 = if (bright) rng.uniform(0.50, 0.78) else rng.uniform(0.16, 0.32)
            val x = rng.uniform(xlo, xhi)
            val y = rng.uniform(18.0, ymax)
            val k = 1.0 + (rng.next() * 2).toInt()
            val ph = rng.uniform(0.0, PI * 2)
            val c = palette[(rng.next() * 3).toInt() % 3]
            val tw = 0.5 + 0.5 * sin(pose.phase * PI * 2 * k + ph)
            fillDot(g, at = P(x * sx, y * sy), r = r, rgb = c, a = a0 * tw)
            if (i == 0 || bright) {
                flare(g, at = P(x * sx, y * sy), r = r * 3.2, rgb = c, a = a0 * tw * 0.35)
            }
        }
        repeat(flares) {
            val x = rng.uniform(xlo + 24, xhi - 24)
            val y = rng.uniform(30.0, ymax * 0.8)
            val r = rng.uniform(4.5, 7.0) * s
            val ph = rng.uniform(0.0, PI * 2)
            val a = 0.62 * (0.35 + 0.65 * (0.5 + 0.5 * sin(pose.phase * PI * 4 + ph)))
            flare(g, at = P(x * sx, y * sy), r = r, rgb = 0xFFFFFF, a = a)
        }
    }

    // MARK: primitives

    private fun glow(g: PlateGc, at: P, rx: Number, ry: Number, rgb: Int, a: Number, deg: Number = 0) {
        val rx = rx.d; val ry = ry.d; val a = a.d
        if (!(a > 0.004 && rx > 0 && ry > 0)) return
        g.layer {
            if (deg.d != 0.0) {
                g.translate(at.x, at.y); g.rotate(deg.d); g.translate(-at.x, -at.y)
            }
            g.fill(oval(at.x - rx, at.y - ry, rx * 2, ry * 2),
                   radial(evenly(col(rgb, a), col(rgb, 0)), at, 0.0, max(rx, ry)))
        }
    }

    /** Horizon mist: gone by ~48% radius so a large ellipse never reads as a disc. */
    private fun mist(g: PlateGc, at: P, rx: Number, ry: Number, rgb: Int, a: Number) {
        val rx = rx.d; val ry = ry.d; val a = a.d
        if (!(a > 0.004 && rx > 0 && ry > 0)) return
        g.fill(oval(at.x - rx, at.y - ry, rx * 2, ry * 2),
               radial(listOf(ws(0, col(rgb, a)), ws(0.22, col(rgb, a * 0.40)),
                             ws(0.48, col(rgb, a * 0.10)), ws(0.78, col(rgb, 0))),
                      at, 0.0, max(rx, ry)))
    }

    /** Paper bloom: fades by 70% radius so a large ellipse stays a haze, not a disc. */
    private fun bloom(g: PlateGc, at: P, rx: Number, ry: Number, rgb: Int, a: Number, deg: Number = 0) {
        val rx = rx.d; val ry = ry.d; val a = a.d
        if (!(a > 0.004 && rx > 0 && ry > 0)) return
        g.layer {
            if (deg.d != 0.0) {
                g.translate(at.x, at.y); g.rotate(deg.d); g.translate(-at.x, -at.y)
            }
            g.fill(oval(at.x - rx, at.y - ry, rx * 2, ry * 2),
                   radial(listOf(ws(0, col(rgb, a)), ws(0.38, col(rgb, a * 0.45)),
                                 ws(0.70, col(rgb, a * 0.10)), ws(1, col(rgb, 0))),
                          at, 0.0, max(rx, ry)))
        }
    }

    /** Paper fog-edge disc: radial holds colour then dissolves. Unlike `sphere()`,
     *  there is no opaque last-stop fill and no night / spec. */
    private fun softBall(g: PlateGc, c: P, r: Number, hx: Number, hy: Number, stops: List<DoubleArray>) {
        val r = r.d
        if (!(r > 0) || stops.isEmpty()) return
        g.fill(oval(c.x - r, c.y - r, r * 2, r * 2),
               radial(stops.map { it[0] to col(it[1].toInt(), it[2]) }, P(hx.d, hy.d), 0.0, r))
    }

    /** Soft orb whose rim fades to clear — used as a highlight wash, not a body. */
    private fun hazeOrb(g: PlateGc, c: P, r: Number, hx: Number, hy: Number,
                        core: Int, mid: Int, a: Number) {
        val r = r.d; val a = a.d
        if (!(a > 0.004 && r > 0)) return
        g.fill(oval(c.x - r, c.y - r, r * 2, r * 2),
               radial(listOf(ws(0, col(core, a)), ws(0.40, col(mid, a * 0.50)),
                             ws(0.72, col(mid, a * 0.14)), ws(1, col(mid, 0))),
                      P(hx.d, hy.d), 0.0, r * 1.05))
    }

    /** Paper 02 halo: a ring glow that starts after 70% of the radius. */
    private fun haloRing(g: PlateGc, at: P, r: Number, rgb: Int, stops: List<DoubleArray>) {
        val r = r.d
        if (!(r > 0)) return
        g.fill(oval(at.x - r, at.y - r, r * 2, r * 2),
               radial(stops.map { it[0] to col(rgb, it[1]) }, at, 0.0, r))
    }

    private fun fillDot(g: PlateGc, at: P, r: Number, rgb: Int, a: Number) {
        if (!(a.d > 0.01)) return
        val r = r.d
        g.fill(oval(at.x - r, at.y - r, r * 2, r * 2), col(rgb, a))
    }

    private fun flare(g: PlateGc, at: P, r: Number, rgb: Int, a: Number) {
        val r = r.d; val a = a.d
        if (!(a > 0.02)) return
        fillDot(g, at = at, r = r * 0.35, rgb = rgb, a = a)
        g.fill(oval(at.x - r * 1.7, at.y - r * 0.16, r * 3.4, r * 0.32), col(rgb, a * 0.55))
        g.fill(oval(at.x - r * 0.16, at.y - r * 1.7, r * 0.32, r * 3.4), col(rgb, a * 0.55))
    }

    private fun crescent(g: PlateGc, at: P, r: Number, off: P, rgb: Int, a: Number) {
        val r = r.d
        g.layer {
            val disc = oval(at.x - r, at.y - r, r * 2, r * 2)
            disc.addPath(oval(at.x + off.x - r * 0.92, at.y + off.y - r * 0.92, r * 1.84, r * 1.84))
            disc.fillType = PathFillType.EvenOdd
            g.fill(disc, col(rgb, a))
        }
        glow(g, at = at, rx = r * 1.5, ry = r * 1.5, rgb = rgb, a = a.d * 0.14)
    }

    private fun paperHighlight(g: PlateGc, at: P, rx: Number, ry: Number, deg: Number, a: Number) {
        val rx = rx.d; val ry = ry.d
        g.layer {
            g.translate(at.x, at.y); g.rotate(deg.d); g.translate(-at.x, -at.y)
            g.fill(oval(at.x - rx, at.y - ry, rx * 2, ry * 2),
                   radial(evenly(white(a), white(0)), at, 0.0, max(rx, ry)))
        }
    }

    private fun paperLine(g: PlateGc, s: Double, sx: Double, sy: Double,
                          from: DoubleArray, to: DoubleArray, width: Number, rgb: Int, a: Number) {
        val path = Path().apply { move(P(from[0] * sx, from[1] * sy)); line(P(to[0] * sx, to[1] * sy)) }
        g.stroke(path, col(rgb, a), width = width.d * s, cap = StrokeCap.Round)
    }

    private fun paperDashStroke(g: PlateGc, path: Path, width: Double, rgb: Int, a: Number,
                                dash: List<Number>, phase: Double = 0.0) {
        if (dash.isEmpty()) g.stroke(path, col(rgb, a), width = width, cap = StrokeCap.Round)
        else g.stroke(path, col(rgb, a), width = width, cap = StrokeCap.Round,
                      dash = dash.map { it.d }, phase = phase)
    }

    private fun paperDashCircle(g: PlateGc, c: P, r: Number, width: Number, rgb: Int, a: Number,
                                dash: List<Number>, phase: Number = 0) {
        val r = r.d
        paperDashStroke(g, path = oval(c.x - r, c.y - r, r * 2, r * 2),
                        width = width.d, rgb = rgb, a = a, dash = dash, phase = phase.d)
    }

    private fun paperDashEllipse(g: PlateGc, c: P, rx: Number, ry: Number, deg: Number,
                                 width: Number, rgb: Int, a: Number,
                                 dash: List<Number>, phase: Number = 0) {
        g.layer {
            g.translate(c.x, c.y)
            g.rotate(deg.d)
            paperDashStroke(g, path = oval(-rx.d, -ry.d, rx.d * 2, ry.d * 2),
                            width = width.d, rgb = rgb, a = a, dash = dash, phase = phase.d)
        }
    }

    private fun paperDashLine(g: PlateGc, s: Double, sx: Double, sy: Double,
                              from: DoubleArray, to: DoubleArray, width: Number, rgb: Int, a: Number,
                              dash: List<Number>, phase: Number) {
        val path = Path().apply { move(P(from[0] * sx, from[1] * sy)); line(P(to[0] * sx, to[1] * sy)) }
        paperDashStroke(g, path = path, width = width.d * s, rgb = rgb, a = a,
                        dash = dash.map { it.d * s }, phase = phase.d * s)
    }

    private fun paperGradientLine(g: PlateGc, s: Double, sx: Double, sy: Double,
                                  from: DoubleArray, to: DoubleArray, width: Number,
                                  stops: List<DoubleArray>) {
        val a = P(from[0] * sx, from[1] * sy)
        val b = P(to[0] * sx, to[1] * sy)
        val path = Path().apply { move(a); line(b) }
        g.stroke(path, linear(stops.map { it[0] to white(it[1]) }, a, b),
                 width = width.d * s, cap = StrokeCap.Round)
    }

    private fun paperSoftBand(g: PlateGc, s: Double, sx: Double, sy: Double,
                              from: DoubleArray, to: DoubleArray, rx: Number, rgb: Int, a: Number) {
        paperBlurLine(g, s = s, sx = sx, sy = sy, from = from, to = to, width = rx.d * 2, rgb = rgb, a = a)
    }

    /** Paper blurred stroke: a capsule whose alpha falls off across the width. */
    private fun paperBlurLine(g: PlateGc, s: Double, sx: Double, sy: Double,
                              from: DoubleArray, to: DoubleArray, width: Number, rgb: Int, a: Number) {
        val a = a.d
        val a0 = P(from[0] * sx, from[1] * sy)
        val b0 = P(to[0] * sx, to[1] * sy)
        val dx = b0.x - a0.x; val dy = b0.y - a0.y
        val len = hypot(dx, dy)
        if (!(len > 0.5 && a > 0.002 && width.d > 0)) return
        val nx = -dy / len; val ny = dx / len
        val hw = width.d * s * 0.5
        val quad = Path().apply {
            move(P(a0.x + nx * hw, a0.y + ny * hw))
            line(P(b0.x + nx * hw, b0.y + ny * hw))
            line(P(b0.x - nx * hw, b0.y - ny * hw))
            line(P(a0.x - nx * hw, a0.y - ny * hw))
            close()
        }
        val mid = P((a0.x + b0.x) / 2, (a0.y + b0.y) / 2)
        g.fill(quad, linear(listOf(
            ws(0, col(rgb, 0)), ws(0.28, col(rgb, a * 0.35)), ws(0.5, col(rgb, a)),
            ws(0.72, col(rgb, a * 0.35)), ws(1, col(rgb, 0)),
        ), P(mid.x + nx * hw, mid.y + ny * hw), P(mid.x - nx * hw, mid.y - ny * hw)))
        bloom(g, at = a0, rx = hw, ry = hw, rgb = rgb, a = a * 0.55)
        bloom(g, at = b0, rx = hw, ry = hw, rgb = rgb, a = a * 0.55)
    }

    private fun paperPip(g: PlateGc, at: P, r: Number, rgb: Int, a: Number) {
        glow(g, at = at, rx = r.d * 2.2, ry = r.d * 2.2, rgb = rgb, a = a.d * 0.28)
        fillDot(g, at = at, r = r, rgb = rgb, a = a)
    }

    private fun paperCubics(g: PlateGc, s: Double, sx: Double, sy: Double,
                            p0: DoubleArray, c1: DoubleArray, c2: DoubleArray, p1: DoubleArray,
                            c3: DoubleArray? = null, c4: DoubleArray? = null, p2: DoubleArray? = null,
                            width: Number, rgb: Int, a: Number,
                            dash: List<Number> = emptyList(), phase: Number = 0) {
        val path = Path()
        path.moveTo((p0[0] * sx).toFloat(), (p0[1] * sy).toFloat())
        path.cubicTo((c1[0] * sx).toFloat(), (c1[1] * sy).toFloat(),
                     (c2[0] * sx).toFloat(), (c2[1] * sy).toFloat(),
                     (p1[0] * sx).toFloat(), (p1[1] * sy).toFloat())
        if (c3 != null && c4 != null && p2 != null) {
            path.cubicTo((c3[0] * sx).toFloat(), (c3[1] * sy).toFloat(),
                         (c4[0] * sx).toFloat(), (c4[1] * sy).toFloat(),
                         (p2[0] * sx).toFloat(), (p2[1] * sy).toFloat())
        }
        paperDashStroke(g, path = path, width = width.d * s, rgb = rgb, a = a,
                        dash = dash.map { it.d * s }, phase = phase.d * s)
    }

    private fun plate24Point(q: Double): Pair<Double, Double> {
        fun cubic(t: Double, a: DoubleArray, b: DoubleArray, c: DoubleArray, d: DoubleArray): Pair<Double, Double> {
            val u = 1 - t; val uu = u * u; val uuu = uu * u; val tt = t * t; val ttt = tt * t
            return Pair(uuu * a[0] + 3 * uu * t * b[0] + 3 * u * tt * c[0] + ttt * d[0],
                        uuu * a[1] + 3 * uu * t * b[1] + 3 * u * tt * c[1] + ttt * d[1])
        }
        if (q <= 0.5) return cubic(q * 2, t(372, 96), t(268, 116), t(196, 178), t(158, 246))
        return cubic((q - 0.5) * 2, t(158, 246), t(128, 300), t(138, 344), t(196, 366))
    }

    /** SVG elliptical-arc center parameterization (Paper path `M … A rx ry deg …`). */
    private fun svgArc(g: PlateGc, s: Double, sx: Double, sy: Double,
                       x1: Number, y1: Number, rx: Number, ry: Number,
                       deg: Number, large: Boolean, sweep: Boolean,
                       x2: Number, y2: Number,
                       width: Number, rgb: Int, a: Number,
                       dash: Pair<Int, Double>? = null, dashOff: Double = 0.0,
                       marks: List<Number>? = null, markPhase: Number = 0) {
        val x1 = x1.d; val y1 = y1.d; val x2 = x2.d; val y2 = y2.d
        val phi = deg.d * PI / 180
        val cosP = cos(phi); val sinP = sin(phi)
        val dx = (x1 - x2) / 2; val dy = (y1 - y2) / 2
        val x1p = cosP * dx + sinP * dy
        val y1p = -sinP * dx + cosP * dy
        var rxv = abs(rx.d); var ryv = abs(ry.d)
        val lambda = (x1p * x1p) / (rxv * rxv) + (y1p * y1p) / (ryv * ryv)
        if (lambda > 1) {
            val r = sqrt(lambda)
            rxv *= r; ryv *= r
        }
        val num = max(0.0, rxv * rxv * ryv * ryv - rxv * rxv * y1p * y1p - ryv * ryv * x1p * x1p)
        val den = rxv * rxv * y1p * y1p + ryv * ryv * x1p * x1p
        var coef = sqrt(num / max(den, 1e-12))
        if (large == sweep) coef = -coef
        val cxp = coef * rxv * y1p / ryv
        val cyp = coef * -ryv * x1p / rxv
        val cx = cosP * cxp - sinP * cyp + (x1 + x2) / 2
        val cy = sinP * cxp + cosP * cyp + (y1 + y2) / 2
        fun ang(ux: Double, uy: Double, vx: Double, vy: Double): Double {
            val sign = if (ux * vy - uy * vx < 0) -1.0 else 1.0
            val n = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            val c = max(-1.0, min(1.0, (ux * vx + uy * vy) / max(n, 1e-12)))
            return sign * acos(c)
        }
        val th1 = ang(1.0, 0.0, (x1p - cxp) / rxv, (y1p - cyp) / ryv)
        var dth = ang((x1p - cxp) / rxv, (y1p - cyp) / ryv, (-x1p - cxp) / rxv, (-y1p - cyp) / ryv)
        if (!sweep && dth > 0) dth -= PI * 2
        if (sweep && dth < 0) dth += PI * 2
        val path = Path()
        val steps = 56
        var drew = false
        for (i in 0..steps) {
            val u = i.toDouble() / steps
            if (marks == null && dash != null) {
                val duty = ((u + dashOff) * dash.first) % 1.0
                if (!(duty < dash.second)) { drew = false; continue }
            }
            val th = th1 + dth * u
            val x = rxv * cos(th); val y = ryv * sin(th)
            val p = P((cx + x * cosP - y * sinP) * sx, (cy + x * sinP + y * cosP) * sy)
            if (drew) path.line(p) else { path.move(p); drew = true }
        }
        if (marks != null) {
            paperDashStroke(g, path = path, width = width.d * s, rgb = rgb, a = a,
                            dash = marks.map { it.d * s }, phase = markPhase.d * s)
        } else {
            g.stroke(path, col(rgb, a), width = width.d * s, cap = StrokeCap.Round)
        }
    }

    private fun strokeCircle(g: PlateGc, c: P, r: Number, width: Number, rgb: Int, a: Number) {
        val r = r.d
        g.stroke(oval(c.x - r, c.y - r, r * 2, r * 2), col(rgb, a), width = width.d, cap = StrokeCap.Round)
    }

    private fun strokeEllipse(g: PlateGc, c: P, rx: Double, ry: Double, rot: Double,
                              back: Boolean, width: Double, rgb: Int, a: Double,
                              arc: Pair<Double, Double>? = null,
                              dash: Pair<Int, Double>? = null, dashOff: Double = 0.0) {
        val path = Path()
        val steps = 64
        var drew = false
        for (i in 0..steps) {
            val u = i.toDouble() / steps
            val tt = u * PI * 2
            if (arc != null) {
                val deg = (u * 360) % 360.0
                val t0 = arc.first % 360.0
                val t1 = arc.second % 360.0
                val inside = if (t0 <= t1) (deg >= t0 && deg <= t1) else (deg >= t0 || deg <= t1)
                if (!inside) { drew = false; continue }
            }
            if (dash != null) {
                val duty = ((u + dashOff) * dash.first) % 1.0
                if (!(duty < dash.second)) { drew = false; continue }
            }
            val x = rx * cos(tt); val y = ry * sin(tt)
            val yr = x * sin(rot) + y * cos(rot)
            val isFront = yr > 0
            if (isFront == back) { drew = false; continue }
            val p = P(c.x + (x * cos(rot) - y * sin(rot)), c.y + (x * sin(rot) + y * cos(rot)))
            if (drew) path.line(p) else { path.move(p); drew = true }
        }
        g.stroke(path, col(rgb, a), width = width, cap = StrokeCap.Round)
    }

    private fun dashEllipse(g: PlateGc, c: P, rx: Double, ry: Double, rot: Double,
                            n: Int, pose: IdlePlatePose, rgb: Int, a: Double) {
        val steps = n * 4
        for (i in 0 until steps) {
            val u = (i.toDouble() / steps + pose.dash) % 1.0
            val duty = (u * n) % 1.0
            if (!(duty < 0.45)) continue
            val tt = u * PI * 2
            val x = rx * cos(tt); val y = ry * sin(tt)
            val p = P(c.x + (x * cos(rot) - y * sin(rot)), c.y + (x * sin(rot) + y * cos(rot)))
            fillDot(g, at = p, r = 1.55, rgb = rgb, a = a)
        }
    }

    private fun dashArc(g: PlateGc, c: P, r: Double, from: Double, to: Double, n: Int,
                        pose: IdlePlatePose, rgb: Int, a: Double) {
        strokeEllipse(g, c = c, rx = r, ry = r, rot = 0.0, back = false,
                      width = 2 * (r / 68), rgb = rgb, a = a,
                      arc = from to to, dash = n to 0.42, dashOff = pose.dash)
    }

    private fun dashedLine(g: PlateGc, pose: IdlePlatePose, s: Double, from: P, to: P,
                           n: Int, rgb: Int, a: Double, reverse: Boolean = false, crawl: Boolean = true) {
        if (n <= 1 || !crawl) {
            val path = Path().apply { move(from); line(to) }
            g.stroke(path, col(rgb, a), width = 1.1 * s, cap = StrokeCap.Round)
            return
        }
        val off = if (reverse) -pose.dash else pose.dash
        for (i in 0 until n) {
            val u = (i.toDouble() / n + off) % 1.0
            if (!((u * n) % 1.0 < 0.42)) continue
            val p = P(from.x + (to.x - from.x) * u, from.y + (to.y - from.y) * u)
            fillDot(g, at = p, r = 1.35 * s, rgb = rgb, a = a)
        }
    }

    private fun ringDots(g: PlateGc, c: P, rx: Double, ry: Double, deg: Double,
                         n: Int, phase: Double, r: Double, rgb: Int) {
        val rot = deg * PI / 180
        for (i in 0 until n) {
            val tt = PI * 2 * (i + phase) / n
            val x = rx * cos(tt); val y = ry * sin(tt)
            val p = P(c.x + (x * cos(rot) - y * sin(rot)), c.y + (x * sin(rot) + y * cos(rot)))
            glow(g, at = p, rx = r * 1.8, ry = r * 1.8, rgb = rgb, a = 0.35)
            fillDot(g, at = p, r = r, rgb = rgb, a = 0.88)
        }
    }

    private fun segmentRing(g: PlateGc, c: P, rx: Double, ry: Double, deg: Double,
                            width: Double, colors: List<Int>, a: Double, back: Boolean) {
        val n = colors.size
        val span = 360.0 / n
        for ((i, colr) in colors.withIndex()) {
            val t0 = i * span
            strokeEllipse(g, c = c, rx = rx, ry = ry, rot = deg * PI / 180,
                          back = back, width = width, rgb = colr, a = a, arc = t0 to t0 + span)
        }
    }

    private fun hash(n: Double, salt: Double): Double {
        val v = sin(n * salt) * 43758.5453
        return v - floor(v)
    }
}

/** Deterministic plate RNG — the same LCG as iOS so the grain and the moons land 1:1. */
private class PlateRNG(seed: ULong) {
    private var state: ULong = seed * 0x9E3779B97F4A7C15uL

    constructor(seed: Int) : this(seed.toLong().toULong())

    fun next(): Double {
        state = state * 6364136223846793005uL + 1442695040888963407uL
        return ((state shr 33) and 0xFFFFFFFFuL).toDouble() / 4_294_967_296.0
    }

    fun uniform(a: Double, b: Double): Double = a + (b - a) * next()
}
