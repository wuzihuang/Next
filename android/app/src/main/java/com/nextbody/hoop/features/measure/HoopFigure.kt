package com.nextbody.hoop.features.measure

import android.graphics.BitmapFactory
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Region
import android.graphics.Shader
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.nextbody.hoop.R
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The band at the board's size, drawn as a point cloud: the knit opening, the shell, the side
 * key and its ripples, and the index finger that comes to rest on it. Mode `lit` is the dimmed
 * band the battery check writes its trace over.
 */
@Composable
fun HoopFigure(mode: HoopFigureMode, modifier: Modifier = Modifier) {
    val reduceMotion = rememberReduceMotion()
    val context = LocalContext.current
    val finger = remember(context) {
        runCatching {
            BitmapFactory.decodeResource(context.resources, R.drawable.hoop_finger,
                BitmapFactory.Options().apply { inScaled = false })
        }.getOrNull()
    }
    val painter = remember { HoopPainter() }
    // `onChange(of: mode) { changedAt = .now }`
    val changedAt = remember(mode) { System.nanoTime() }
    var frameNanos by remember { mutableLongStateOf(System.nanoTime()) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) return@LaunchedEffect
        while (true) withFrameNanos { frameNanos = System.nanoTime() }
    }

    Box(modifier.fillMaxSize().clearAndSetSemantics { }) {
        Canvas(Modifier.fillMaxSize()) {
            val now = if (reduceMotion) changedAt else frameNanos
            val elapsed = if (reduceMotion) (if (mode == HoopFigureMode.contact) 1.2 else 0.0)
            else (now - changedAt) / 1e9
            painter.drawMain(this, mode, max(0.0, elapsed), now / 1e9, reduceMotion, finger)
        }
        // The blurred blooms: one layer, blurred once, added over the sharp dots.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Canvas(Modifier.fillMaxSize().graphicsLayer {
                renderEffect = BlurEffect(6.dp2px(density), 6.dp2px(density), TileMode.Decal)
            }) {
                @Suppress("UNUSED_VARIABLE") val tick = frameNanos
                painter.drawGlow(this)
            }
        }
    }
}

private fun Int.dp2px(density: Float): Float = this * density

enum class HoopFigureMode { waiting, nudge, contact, lit }

/** A growable flat array of point centres, drawn as squares in one native call. */
internal class DotBatch(capacity: Int = 512) {
    var data = FloatArray(capacity * 2)
    var count = 0
    fun clear() { count = 0 }
    val isEmpty: Boolean get() = count == 0
    fun add(x: Float, y: Float) {
        if (count * 2 + 2 > data.size) data = data.copyOf(data.size * 2)
        data[count * 2] = x
        data[count * 2 + 1] = y
        count++
    }
}

internal fun additivePaint(round: Boolean = false): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    strokeCap = if (round) Paint.Cap.ROUND else Paint.Cap.SQUARE
    xfermode = PorterDuffXfermode(PorterDuff.Mode.ADD)
}

internal fun DrawScope.drawDots(batch: DotBatch, side: Float, color: Color, paint: Paint) {
    if (batch.isEmpty) return
    paint.color = color.toArgb()
    paint.strokeWidth = side
    drawIntoCanvas { it.nativeCanvas.drawPoints(batch.data, 0, batch.count * 2, paint) }
}

/** SplitMix64 — the same deterministic sequence the Swift figure seeds its particles from. */
internal class SplitMix64(seed: Long) {
    private var state: ULong = seed.toULong()
    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var value = state
        value = (value xor (value shr 30)) * 0xBF58476D1CE4E5B9uL
        value = (value xor (value shr 27)) * 0x94D049BB133111EBuL
        return value xor (value shr 31)
    }
    fun nextDouble(): Double = (next() shr 11).toDouble() / (1uL shl 53).toDouble()
}

private class HoopPainter {
    private val dot = additivePaint()
    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val layerPaint = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.ADD) }
    private val maskPaint = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) }

    // What the glow canvas draws this frame, filled by drawMain.
    private var transform = floatArrayOf(0f, 0f, 1f) // tx, ty, scale (px)
    private val rim = DotBatch(); private var rimColor = Color.Transparent; private var rimSide = 1f
    private val bloom = DotBatch(); private var bloomColor = Color.Transparent; private var bloomSide = 1f
    private val ripples = DotBatch(); private var rippleColor = Color.Transparent; private var rippleSide = 1f

    private val dust = arrayOf(DotBatch(), DotBatch())
    private val knit = Array(4) { DotBatch() }
    private val shell = Array(3) { DotBatch() }
    private val key = DotBatch()
    private val motes = arrayOf(DotBatch(), DotBatch())

    fun drawGlow(scope: DrawScope) = with(scope) {
        withTransform({
            translate(transform[0], transform[1])
            scale(transform[2], transform[2], Offset.Zero)
        }) {
            drawDots(rim, rimSide, rimColor, dot)
            drawDots(bloom, bloomSide, bloomColor, dot)
            drawDots(ripples, rippleSide, rippleColor, dot)
        }
    }

    fun drawMain(scope: DrawScope, mode: HoopFigureMode, elapsed: Double, time: Double,
                 reduceMotion: Boolean, finger: android.graphics.Bitmap?) = with(scope) {
        val d = density
        val w = size.width / d
        val h = size.height / d
        // Scale in points; the canvas works in px, so the transform carries density too.
        val scale = min(w * 0.38f / FRAME_W, h * 0.9f / FRAME_H)
        val tx = (w * 0.46f - CX * scale) * d
        val ty = (h * 0.5f - CY * scale) * d
        transform = floatArrayOf(tx, ty, scale * d)
        rim.clear(); bloom.clear(); ripples.clear()
        withTransform({
            translate(tx, ty)
            scale(scale * d, scale * d, Offset.Zero)
        }) {
            val contact = mode == HoopFigureMode.contact
            val waiting = mode == HoopFigureMode.waiting || mode == HoopFigureMode.nudge
            drawBackdrop(mode, time, contact, scale)
            drawInterior(mode, elapsed, time, contact, scale)
            drawShell(mode, elapsed, contact, scale)
            drawKey(time, elapsed, waiting, mode == HoopFigureMode.nudge, contact, scale)
            if (mode != HoopFigureMode.lit && finger != null) {
                drawFinger(finger, elapsed, time, contact, mode == HoopFigureMode.nudge, scale, reduceMotion)
            }
            if (contact) drawContactBloom(elapsed, scale)
        }
    }

    private fun DrawScope.drawBackdrop(mode: HoopFigureMode, time: Double, contact: Boolean, scale: Float) {
        val haloAlpha = if (contact) 0.2f else if (mode == HoopFigureMode.lit) 0.025f else 0.055f
        drawOval(
            Brush.radialGradient(listOf(NB.lime1.copy(alpha = haloAlpha), NB.lime1.copy(alpha = 0f)),
                center = Offset(CX, CY), radius = 214f),
            topLeft = Offset(35f, 42f), size = Size(320f, 386f), blendMode = BlendMode.Plus)

        dust[0].clear(); dust[1].clear()
        val speed = if (contact) 17.0 else if (mode == HoopFigureMode.nudge) 7.5 else 3.2
        val boost = if (contact) 1.7 else if (mode == HoopFigureMode.nudge) 1.15 else 1.0
        for (mote in Particles.dust) {
            val rise = (time * speed + mote.phase) % 400.0
            val y = 35 + ((mote.y - 35 - rise + 400) % 400.0)
            val x = mote.x + 1.8 * sin(time * 0.15 + mote.phase)
            val dx = (x - CX) / 150
            val dy = (y - CY) / 200
            val radius = dx * dx + dy * dy
            if (radius >= 1.22) continue
            val twinkle = 0.58 + 0.42 * sin(time * 1.6 + mote.phase)
            val alpha = min(0.34, mote.alpha * (1 - min(0.85, radius * 0.55)) * twinkle * boost)
            val a = min(1.0, alpha * 3)
            if (a <= 0.02) continue
            val level = min(1, max(0, (a * 2).toInt()))
            dust[level].add(x.toFloat(), y.toFloat())
        }
        drawDots(dust[0], 1.0f / scale, NB.lime1.copy(alpha = 0.08f), dot)
        drawDots(dust[1], 1.0f / scale, NB.lime1.copy(alpha = 0.28f), dot)
    }

    private fun DrawScope.drawInterior(mode: HoopFigureMode, elapsed: Double, time: Double,
                                       contact: Boolean, scale: Float) {
        val settled = if (contact) min(1.0, max(0.0, (elapsed - 0.2) / 1.0)) else 0.0
        val sweep = INNER_MAX_X - settled * INNER_W
        val flow = time * (if (contact) 0.75 else 0.18)
        for (b in knit) b.clear()

        drawRoundRect(
            Brush.radialGradient(
                listOf(NB.lime1.copy(alpha = if (contact) 0.95f else if (mode == HoopFigureMode.lit) 0.015f else 0.62f),
                    NB.lime1.copy(alpha = if (contact) 0.07f else 0.025f)),
                center = Offset(CX, CY), radius = 112f),
            topLeft = Offset(132f, 120f), size = Size(118f, 228f),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(8f, 8f), blendMode = BlendMode.Plus)

        val breathBase = if (contact) 1.0 else 0.92 + 0.08 * sin(time * 2 * PI / 4.8)
        for (point in Particles.knit) {
            val dx = (point.x - CX) / (INNER_W * 0.52)
            val dy = (point.y - CY) / (INNER_H * 0.52)
            val radial = exp(-(dx * dx + dy * dy))
            val twill = (0.55 + 0.45 * sin((point.x + point.y) * 0.075)).pow(1.2) *
                (0.55 + 0.45 * sin((point.x - point.y) * 0.071)).pow(1.2)
            val x = point.x
            val streak = max(exp(-((x - 151) / 5.5).pow(2)),
                max(exp(-((x - 191) / 5).pow(2)), exp(-((x - 231) / 5.5).pow(2))))
            val wave = 0.84 + 0.16 * sin(point.y * 0.05 - flow)
            val twinkle = 0.8 + 0.2 * sin(time * 0.8 + point.phase)
            var alpha = (if (contact) 0.94 + settled * 0.05 else if (mode == HoopFigureMode.lit) 0.14 else 0.56) *
                (0.68 + 0.32 * twill) * wave * twinkle * breathBase *
                (0.34 + 0.66 * radial + 0.16 * streak)
            if (contact) {
                val behind = max(0.0, point.x - sweep)
                alpha *= 0.34 + 0.66 * min(1.0, behind / 20)
                if (kotlin.math.abs(point.x - sweep) < 1.4) knit[3].add(point.x.toFloat(), point.y.toFloat())
            }
            val level = min(3, max(0, (min(1.0, alpha) * 4).toInt()))
            knit[level].add(point.x.toFloat(), point.y.toFloat())
            if (point.edge < 5 && alpha > 0.18) rim.add(point.x.toFloat(), point.y.toFloat())
        }
        for ((index, batch) in knit.withIndex()) {
            val color = if (contact && index == 3) NB.limePale else NB.lime1
            val opacity = if (contact) 0.2 + index * 0.2
            else if (mode == HoopFigureMode.lit) 0.08 + index * 0.035 else 0.12 + index * 0.17
            drawDots(batch, 1.05f / scale, color.copy(alpha = opacity.toFloat()), dot)
        }
        rimSide = 1.4f / scale
        rimColor = NB.lime1.copy(alpha = if (contact) 0.36f else 0.18f)
    }

    private fun DrawScope.drawShell(mode: HoopFigureMode, elapsed: Double, contact: Boolean, scale: Float) {
        for (b in shell) b.clear()
        val lit = mode == HoopFigureMode.lit
        val progress = if (contact && elapsed >= 0.1 && elapsed < 1.05) min(1.0, max(0.0, (elapsed - 0.1) / 0.9)) else null
        val top = progress?.let { packetPoint(it, true) }
        val bottom = progress?.let { packetPoint(it, false) }
        for (point in Particles.shell) {
            val x = point.x; val y = point.y
            val light = max(0.0, min(1.0, 1 - 0.0038 * (x - 116) - 0.0018 * (y - 100)))
            val outerEdge = min(min(x - 116, 266 - x), min(y - 100, 368 - y))
            val innerEdge = min(min(x - 132, 250 - x), min(y - 120, 348 - y))
            val edge = min(outerEdge, innerEdge)
            val edgeGlow = exp(-max(0.0, edge) / 4)
            val shimmer = 0.94 + 0.06 * sin(elapsed * 1.2 + point.phase)
            var alpha = if (lit) 0.08 * light else (if (contact) 0.68 + 0.24 * light else 0.39 + 0.23 * light) * shimmer
            alpha = min(1.0, alpha + edgeGlow * (if (lit) 0.08 else 0.27))
            if (top != null && bottom != null) {
                val da = hypot(x - top.first, y - top.second)
                val db = hypot(x - bottom.first, y - bottom.second)
                alpha = min(1.0, alpha + exp(-(min(da, db) / 4.8).pow(2)) * 0.8)
            }
            val level = min(2, max(0, (alpha * 3).toInt()))
            shell[level].add(x.toFloat(), y.toFloat())
            if (edge < 4 || alpha > 0.85) bloom.add(x.toFloat(), y.toFloat())
        }
        for (point in Particles.bevel) shell[2].add(point.x.toFloat(), point.y.toFloat())
        for ((index, batch) in shell.withIndex()) {
            val color = if (index == 2) NB.limePale else NB.lime1
            val opacity = if (lit) 0.08 + index * 0.04 else if (contact) 0.3 + index * 0.23 else 0.15 + index * 0.19
            drawDots(batch, 1.05f / scale, color.copy(alpha = opacity.toFloat()), dot)
        }
        bloomSide = 1.05f / scale + 0.9f / scale
        bloomColor = NB.lime1.copy(alpha = if (lit) 0.06f else if (contact) 0.5f else 0.3f)
    }

    private fun DrawScope.drawKey(time: Double, elapsed: Double, waiting: Boolean, nudge: Boolean,
                                  contact: Boolean, scale: Float) {
        val pulse = 0.6 + 0.4 * sin(time * 2 * PI / 1.6)
        val flash = if (contact && elapsed < 0.25) 1 - elapsed / 0.25 else 0.0
        key.clear()
        val threshold = if (contact) max(0.7, flash) else if (waiting) 0.55 + pulse * 0.4 else 0.14
        for (point in Particles.key) {
            if (point.phase >= threshold) continue
            key.add(point.x.toFloat(), point.y.toFloat())
        }
        if (!key.isEmpty) {
            val color = if (nudge) NB.ember1 else if (contact && flash > 0.35) NB.white else NB.lime1
            val opacity = if (contact) 0.95 else if (waiting) (if (nudge) 0.6 else 0.5 + pulse * 0.25) else 0.18
            drawDots(key, 1.05f / scale, color.copy(alpha = opacity.toFloat()), dot)
        }
        if (!waiting) { rippleColor = Color.Transparent; return }
        for (index in 0 until 3) {
            val phase = (time / 1.6 + index / 3.0) % 1.0
            val radius = 12 + phase * 48
            for (i in 0 until 70) {
                val angle = i / 69.0 * PI * 1.35 - PI * 0.68
                ripples.add((KEY_X + cos(angle) * radius).toFloat(), (KEY_Y + sin(angle) * radius).toFloat())
            }
        }
        val color = if (nudge) NB.ember1 else NB.lime1
        rippleSide = 0.9f / scale
        rippleColor = color.copy(alpha = 0.48f)
        drawDots(ripples, 0.9f / scale, color.copy(alpha = if (nudge) 0.34f else 0.24f), dot)
    }

    private fun DrawScope.drawFinger(image: android.graphics.Bitmap, elapsed: Double, time: Double,
                                     contact: Boolean, nudge: Boolean, scale: Float, reduceMotion: Boolean) {
        val gap: Double
        val strength: Double
        if (contact) {
            gap = if (reduceMotion) 0.0 else 12 * (1 - smooth(elapsed / 0.25))
            strength = if (reduceMotion) 1.0 else min(1.0, 0.78 + elapsed * 0.65)
        } else {
            val cycle = if (reduceMotion) 1.2 else elapsed % 2.4
            val travel = if (nudge) 17.0 else 9.0
            val approach = when {
                cycle < 0.8 -> smooth(cycle / 0.8)
                cycle < 1.2 -> 1.0
                cycle < 2 -> 1 - smooth((cycle - 1.2) / 0.8)
                else -> 0.0
            }
            gap = (if (nudge) 20.0 else 12.0) - travel * approach
            strength = 0.42 + 0.2 * (0.5 + 0.5 * sin(elapsed * 2 * PI / 2.4))
        }
        val tipX = KEY_EDGE - 1 + AXIS_X * gap
        val tipY = KEY_Y + AXIS_Y * gap
        val side = FINGER_SIDE
        val rect = RectF((tipX - ANCHOR_X * side).toFloat(), (tipY - ANCHOR_Y * side).toFloat(),
            (tipX - ANCHOR_X * side + side).toFloat(), (tipY - ANCHOR_Y * side + side).toFloat())
        drawIntoCanvas { c ->
            val canvas = c.nativeCanvas
            val save = canvas.saveLayer(rect, layerPaint)
            imagePaint.alpha = (strength * 255).toInt().coerceIn(0, 255)
            canvas.drawBitmap(image, null, rect, imagePaint)
            maskPaint.shader = LinearGradient(tipX.toFloat(), tipY.toFloat(),
                (tipX + AXIS_X * side).toFloat(), (tipY + AXIS_Y * side).toFloat(),
                intArrayOf(android.graphics.Color.WHITE, android.graphics.Color.WHITE,
                    android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
                floatArrayOf(0f, 0.49f, 0.8f, 1f), Shader.TileMode.CLAMP)
            canvas.drawRect(rect, maskPaint)
            canvas.restoreToCount(save)
        }

        val padX = (tipX + AXIS_X * 8).toFloat()
        val padY = (tipY + AXIS_Y * 8).toFloat()
        val glowAlpha = ((if (contact) 0.4 else 0.14) * strength).toFloat()
        drawCircle(Brush.radialGradient(
            listOf(NB.limePale.copy(alpha = glowAlpha), NB.lime1.copy(alpha = glowAlpha * 0.45f), NB.lime1.copy(alpha = 0f)),
            center = Offset(padX, padY), radius = 24f), radius = 24f, center = Offset(padX, padY),
            blendMode = BlendMode.Plus)
        motes[0].clear(); motes[1].clear()
        for (mote in Particles.tipMotes) {
            val twinkle = 0.5 + 0.5 * sin(time * 2.1 + mote.phase)
            val alpha = mote.alpha * twinkle
            if (alpha <= 0.15) continue
            motes[if (alpha > 0.42) 1 else 0].add((tipX + mote.x).toFloat(), (tipY + mote.y).toFloat())
        }
        for ((index, batch) in motes.withIndex()) {
            val a = min(1.0, (if (contact) 0.5 else 0.2) * strength * (if (index == 0) 0.55 else 1.0))
            drawDots(batch, 0.95f / scale, NB.limePale.copy(alpha = a.toFloat()), dot)
        }
    }

    private fun DrawScope.drawContactBloom(elapsed: Double, scale: Float) {
        val alpha = if (elapsed < 0.25) 0.86f else 0.3f
        val radius = 28f / scale
        val c = Offset(KEY_EDGE.toFloat(), KEY_Y.toFloat())
        drawCircle(Brush.radialGradient(
            listOf(NB.white.copy(alpha = alpha), NB.lime1.copy(alpha = alpha * 0.7f), NB.lime1.copy(alpha = 0f)),
            center = c, radius = radius), radius = radius, center = c, blendMode = BlendMode.Plus)
    }

    private fun smooth(value: Double): Double {
        val t = min(1.0, max(0.0, value))
        return t * t * (3 - 2 * t)
    }

    private fun packetPoint(progress: Double, @Suppress("UNUSED_PARAMETER") top: Boolean): Pair<Double, Double> {
        val distance = min(1.0, max(0.0, progress)) * 418
        if (distance < 134) {
            val a = distance / 134
            return Pair(KEY_EDGE + (266 - KEY_EDGE) * a, KEY_Y + (100 - KEY_Y) * a)
        }
        if (distance < 284) {
            val a = (distance - 134) / 150
            return Pair(266 + (116 - 266) * a, 100.0)
        }
        val a = (distance - 284) / 134
        return Pair(116.0, 100 + (KEY_Y - 100) * a)
    }
}

private const val CX = 191f
private const val CY = 234f
private const val FRAME_W = 150f
private const val FRAME_H = 268f
private const val KEY_X = 269.0
private const val KEY_Y = 234.0
private const val KEY_EDGE = 272.0
private const val FINGER_SIDE = 285.0
private const val ANCHOR_X = 0.204
private const val ANCHOR_Y = 0.363
private const val AXIS_X = 0.908
private const val AXIS_Y = 0.417
private const val INNER_W = 118.0
private const val INNER_H = 228.0
private const val INNER_MAX_X = 250.0

private class Dust(val x: Double, val y: Double, val alpha: Double, val phase: Double, val size: Double)
private class KnitPoint(val x: Double, val y: Double, val edge: Double, val size: Double, val phase: Double)
private class ShellPoint(val x: Double, val y: Double, val phase: Double, val size: Double)

/** The figure's particles, seeded once — the same SplitMix64 seed and order as the Swift set. */
private object Particles {
    val dust: List<Dust>
    val knit: List<KnitPoint>
    val shell: List<ShellPoint>
    val bevel: List<ShellPoint>
    val key: List<ShellPoint>
    val tipMotes: List<Dust>

    private fun insideInner(x: Double, y: Double): Boolean {
        if (x < 132 || x > 250 || y < 120 || y > 348) return false
        val r = 8.0
        val cx = when { x < 140 -> 140.0; x > 242 -> 242.0; else -> return true }
        val cy = when { y < 128 -> 128.0; y > 340 -> 340.0; else -> return true }
        return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r
    }

    /** The outer silhouette, rasterised at ×10 so `contains` resolves a tenth of a unit. */
    private val outerRegion: Region by lazy {
        val p = android.graphics.Path().apply {
            moveTo(124f, 100f); lineTo(258f, 100f)
            quadTo(266f, 100f, 266f, 108f); lineTo(266f, 120f)
            cubicTo(269f, 190f, 269f, 278f, 266f, 348f); lineTo(266f, 360f)
            quadTo(266f, 368f, 258f, 368f); lineTo(124f, 368f)
            quadTo(116f, 368f, 116f, 360f); lineTo(116f, 348f)
            cubicTo(113f, 278f, 113f, 190f, 116f, 120f); lineTo(116f, 108f)
            quadTo(116f, 100f, 124f, 100f); close()
            transform(android.graphics.Matrix().apply { setScale(10f, 10f) })
        }
        Region().apply { setPath(p, Region(1000, 900, 2800, 3800)) }
    }

    init {
        val random = SplitMix64(0x484F4F5050415254L)
        dust = (0 until 900).map {
            val angle = random.nextDouble() * PI * 2
            val radius = sqrt(random.nextDouble())
            Dust(x = CX + cos(angle) * radius * 150, y = CY + sin(angle) * radius * 200,
                alpha = 0.05 + 0.3 * (1 - radius), phase = random.nextDouble() * PI * 2,
                size = 0.85 + random.nextDouble() * 0.35)
        }

        val knitPoints = ArrayList<KnitPoint>()
        var y = 120.0
        while (y < 348) {
            var x = 132 + random.nextDouble() * 1.6
            while (x < 250) {
                val px = x + (random.nextDouble() - 0.5) * 1.4
                val py = y + (random.nextDouble() - 0.5) * 1.4
                if (insideInner(px, py)) {
                    val edge = min(min(px - 132, 250 - px), min(py - 120, 348 - py))
                    knitPoints.add(KnitPoint(px, py, edge, size = 0.8 + random.nextDouble() * 0.5,
                        phase = random.nextDouble() * PI * 2))
                }
                x += 1.6
            }
            y += 1.6
        }
        knit = knitPoints

        val shellPoints = ArrayList<ShellPoint>()
        var shellY = 99.0
        while (shellY <= 369) {
            var shellX = 115 + random.nextDouble() * 1.8
            while (shellX <= 267) {
                val px = shellX + (random.nextDouble() - 0.5) * 1.6
                val py = shellY + (random.nextDouble() - 0.5) * 1.6
                if (outerRegion.contains((px * 10).toInt(), (py * 10).toInt()) && !insideInner(px, py)) {
                    shellPoints.add(ShellPoint(px, py, phase = random.nextDouble() * PI * 2,
                        size = 0.8 + random.nextDouble() * 0.5))
                }
                shellX += 1.8
            }
            shellY += 1.8
        }
        shell = shellPoints

        val bevelPoints = ArrayList<ShellPoint>()
        var bx = 132.0
        while (bx <= 250) {
            for (by in listOf(120.0, 348.0)) {
                bevelPoints.add(ShellPoint(bx, by + (random.nextDouble() - 0.5), phase = random.nextDouble(),
                    size = 0.9 + random.nextDouble() * 0.3))
            }
            bx += 1.5
        }
        for ((from, to) in listOf(112.0 to 128.0, 340.0 to 356.0)) {
            var vy = from
            while (vy <= to) {
                for (vx in listOf(132.0, 250.0)) {
                    bevelPoints.add(ShellPoint(vx + (random.nextDouble() - 0.5), vy, phase = random.nextDouble(),
                        size = 0.9 + random.nextDouble() * 0.3))
                }
                vy += 1.5
            }
        }
        bevel = bevelPoints

        val keyPoints = ArrayList<ShellPoint>()
        var keyY = 210.0
        while (keyY <= 258) {
            var keyX = 266.0
            while (keyX <= 272) {
                keyPoints.add(ShellPoint(keyX, keyY, phase = random.nextDouble(), size = 0.8 + random.nextDouble() * 0.5))
                keyX += 0.85
            }
            keyY += 0.85
        }
        key = keyPoints

        tipMotes = (0 until 16).map {
            val angle = random.nextDouble() * PI * 2
            val radius = sqrt(random.nextDouble())
            Dust(x = AXIS_X * 12 + cos(angle) * radius * 24, y = AXIS_Y * 12 + sin(angle) * radius * 17,
                alpha = 0.3 + 0.5 * (1 - radius), phase = random.nextDouble() * PI * 2,
                size = 0.7 + random.nextDouble() * 0.5)
        }
    }
}
