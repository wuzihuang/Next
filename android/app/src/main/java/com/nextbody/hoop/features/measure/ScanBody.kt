package com.nextbody.hoop.features.measure

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.nextbody.hoop.features.home.BodyCloud
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.rememberReduceMotion
import java.time.Instant
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * The body the scan walks: the home figure's point cloud, gathered in from scatter, lit from
 * the feet up as the band's seconds pass. A lifted finger freezes it amber; computing and the
 * result hold the whole body lit.
 */
@Composable
fun ScanBody(
    beat: Int,
    total: Int = 30,
    beatAt: Instant,
    modifier: Modifier = Modifier,
    active: Boolean = true,
    held: Boolean = false,
    complete: Boolean = false,
) {
    val reduceMotion = rememberReduceMotion()
    val context = LocalContext.current
    val cloud = remember(context) { ScanCloud.shared(context) }
    val painter = remember { ScanPainter() }
    val appearedAt = remember { System.nanoTime() }
    var frameNanos by remember { mutableLongStateOf(System.nanoTime()) }
    // `TimelineView(paused: held || reduceMotion)`.
    LaunchedEffect(held, reduceMotion) {
        if (held || reduceMotion) return@LaunchedEffect
        while (true) withFrameNanos { frameNanos = System.nanoTime() }
    }
    val label = if (active) L("Body scan, %d of %d seconds", beat, total) else L("Waiting for contact")
    // `beatAt` is a wall-clock instant; the frame clock is monotonic. Translate once per beat.
    val beatAtNanos = remember(beatAt) {
        System.nanoTime() - (Instant.now().toEpochMilli() - beatAt.toEpochMilli()) * 1_000_000
    }

    Box(modifier.semantics { contentDescription = label }) {
        Canvas(Modifier.fillMaxSize()) {
            painter.draw(this, cloud, frameNanos, appearedAt, beatAtNanos, beat, total, active, held,
                complete, reduceMotion)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Canvas(Modifier.fillMaxSize().graphicsLayer {
                renderEffect = BlurEffect(6 * density, 6 * density, TileMode.Decal)
            }) {
                @Suppress("UNUSED_VARIABLE") val tick = frameNanos
                painter.drawGlow(this)
            }
        }
    }
}

private class ScanPainter {
    private val dot = additivePaint()
    private val ghost = arrayOf(DotBatch(), DotBatch())
    private val lit = Array(4) { DotBatch() }
    private val haloGhost = DotBatch()
    private val haloLit = DotBatch()
    private val flare = DotBatch()
    private val sparks = DotBatch()
    private var haloSide = 1f
    private var haloLitColor = Color.Transparent
    private var sparkSide = 1f
    private var sparkGlow = Color.Transparent

    fun drawGlow(scope: DrawScope) = with(scope) {
        drawDots(haloGhost, haloSide, BASE.copy(alpha = 0.16f), dot)
        drawDots(haloLit, haloSide, haloLitColor, dot)
        drawDots(sparks, sparkSide, sparkGlow, dot)
    }

    fun draw(scope: DrawScope, cloud: ScanCloud, nowNanos: Long, appearedAt: Long, beatAtNanos: Long,
             beat: Int, total: Int, active: Boolean, held: Boolean, complete: Boolean,
             reduceMotion: Boolean) { with(scope) {
        haloGhost.clear(); haloLit.clear(); sparks.clear()
        if (cloud.motes.isEmpty()) return
        val artwork = cloud.bounds
        val aspect = (cloud.aspect * artwork.width / artwork.height).toFloat()
        val boxHeight = min(size.height * 0.96f, size.width * 0.85f / aspect)
        val boxWidth = boxHeight * aspect
        val boxX = (size.width - boxWidth) / 2
        val boxY = (size.height - boxHeight) / 2
        if (boxHeight <= 4 * density) return

        val scale = min(1.6f, max(0.55f, boxHeight / density / cloud.rows / 1.8f)) * density
        val clock = if (reduceMotion) 0.0 else nowNanos / 1e9
        val gatherAge = if (reduceMotion) 2.0 else (nowNanos - appearedAt) / 1e9
        val beatAge = if (reduceMotion) 1.0 else (nowNanos - beatAtNanos) / 1e9
        val beatBlend = if (reduceMotion) 1.0 else smooth(beatAge / 0.9)
        val progress = if (complete) 1.0 else min(1.0, max(0.0,
            (max(0, beat - 1).toDouble() + beatBlend) / max(1, total).toDouble()))
        val scanY = 0.98 - progress * 0.96
        val lineY = boxY + scanY.toFloat() * boxHeight
        val tint = if (held) NB.ember1 else NB.lime1
        val flareColor = if (held) NB.ember2 else NB.limePale
        val pad = 24 * density
        for (b in ghost) b.clear()
        for (b in lit) b.clear()
        flare.clear()
        val breath = sin(clock * 2 * PI / 4.8)

        for (mote in cloud.motes) {
            val delay = mote.y * 0.15 + mote.seed * 0.08
            val gather = if (reduceMotion) 1.0 else easeOut((gatherAge - delay) / 0.9)
            if (gather <= 0.01) continue
            val away = 1 - gather
            val torso = bump(mote.y, 0.16, 0.56)
            val artworkX = 0.5 + (mote.x - 0.5) * (1 + 0.014 * breath * torso)
            val artworkY = mote.y - 0.003 * breath * torso
            val x = (artworkX - artwork.minX) / artwork.width
            val y = (artworkY - artwork.minY) / artwork.height
            val px = (boxX + x * boxWidth + mote.scatterX * away * boxHeight +
                sin(clock * 0.8 + mote.phase) * 0.7 * scale).toFloat()
            val py = (boxY + y * boxHeight + mote.scatterY * away * boxHeight +
                cos(clock * 0.6 + mote.phase * 1.7) * 0.7 * scale).toFloat()
            if (px < -pad || py < -pad || px > size.width + pad || py > size.height + pad) continue

            val flareAmt = if (active && !complete)
                max(0.0, 1 - abs(y - scanY) / max(0.006, 6.0 * density / boxHeight)) else 0.0
            val sheen = if (complete && !reduceMotion) {
                val sweep = (clock % 2.4) / 2.4
                exp(-((y - sweep) / 0.035).pow(2))
            } else 0.0
            val isLit = active && (complete || y >= scanY)
            val twinkle = 0.6 + 0.4 * sin(clock * (1.2 + mote.seed * 3) + mote.phase)

            if (isLit) {
                val intensity = min(1.0, (mote.light * twinkle * 1.2) + flareAmt * 0.45 + sheen * 0.35)
                val level = min(3, max(0, (intensity * 4).toInt()))
                lit[level].add(px, py)
                if (mote.light > 0.35) haloLit.add(px, py)
                if (flareAmt > 0.72 || sheen > 0.72) flare.add(px, py)
            } else {
                val intensity = 0.36 + mote.light * twinkle * 0.12
                ghost[min(1, (intensity * 4).toInt())].add(px, py)
                if (mote.light > 0.35) haloGhost.add(px, py)
            }
        }

        // ⚠️ One side per batch: the Swift figure sizes each mote by its light (0.9…2.0 × scale);
        // the batches here use the light band's middle, which the eye cannot tell apart at 1–3 px.
        val side = 1.45f * scale
        for ((index, b) in ghost.withIndex()) drawDots(b, side, BASE.copy(alpha = 0.34f + index * 0.1f), dot)
        for ((index, b) in lit.withIndex()) drawDots(b, side * (1 + 0.15f * index / 3f), tint.copy(alpha = 0.54f + index * 0.14f), dot)
        haloSide = 2.6f * scale
        haloLitColor = tint.copy(alpha = if (held) 0.26f else 0.32f)
        drawDots(flare, side + 0.9f * scale, flareColor.copy(alpha = if (held) 0.8f else 0.95f), dot)

        if (active && !complete) {
            drawSparks(cloud, boxX, boxY, boxWidth, boxHeight, scale, scanY, clock)
            sparkSide = 1.8f * scale
            sparkGlow = tint.copy(alpha = 0.52f)
            drawDots(sparks, 1.8f * scale, flareColor.copy(alpha = 0.82f), dot)
            drawScanLine(lineY, tint)
        }
        if (!active) drawSternum(cloud, boxX, boxY, boxWidth, boxHeight, scale, clock, reduceMotion)
        if (active && (progress > 0.02 || complete)) {
            val footX = boxX + boxWidth / 2
            val footY = boxY + boxHeight - 3 * scale
            drawOval(Brush.radialGradient(listOf(tint.copy(alpha = (0.2 * progress).toFloat()), tint.copy(alpha = 0f)),
                center = Offset(footX, footY), radius = boxWidth * 0.24f),
                topLeft = Offset(footX - boxWidth * 0.24f, footY - 12 * scale),
                size = Size(boxWidth * 0.48f, 22 * scale), blendMode = BlendMode.Plus)
        }
    } }

    private fun drawSparks(cloud: ScanCloud, boxX: Float, boxY: Float, boxW: Float, boxH: Float,
                           scale: Float, scanY: Double, clock: Double) {
        if (cloud.emitters.isEmpty()) return
        val b = cloud.bounds
        for (index in 0 until min(60, cloud.emitters.size)) {
            val mote = cloud.motes[cloud.emitters[(index * 131) % cloud.emitters.size]]
            val y = (mote.y - b.minY) / b.height
            if (y < scanY) continue
            val rate = 0.08 + 0.1 * ((mote.seed * 13.3) % 1.0)
            val phase = (clock * rate + mote.phase / (2 * PI)) % 1.0
            val x = boxX + (mote.x - b.minX) / b.width * boxW + sin(clock * 0.9 + mote.phase) * 4 * scale
            val py = boxY + (y - phase * 0.12) * boxH
            sparks.add(x.toFloat(), py.toFloat())
        }
    }

    private fun DrawScope.drawScanLine(y: Float, tint: Color) {
        val width = size.width * 0.85f
        val left = (size.width - width) / 2
        // The glow under the line: an ellipse 28 tall, brightest in the middle of its width.
        drawOval(Brush.horizontalGradient(listOf(tint.copy(alpha = 0f), tint.copy(alpha = 0.16f), tint.copy(alpha = 0f)),
            startX = left, endX = left + width), topLeft = Offset(left, y), size = Size(width, 28 * density),
            blendMode = BlendMode.Plus)
        drawLine(Brush.horizontalGradient(
            0f to tint.copy(alpha = 0f), 0.2f to tint.copy(alpha = 0.88f), 0.5f to NB.limePale.copy(alpha = 0.95f),
            0.8f to tint.copy(alpha = 0.88f), 1f to tint.copy(alpha = 0f), startX = left, endX = left + width),
            Offset(left, y), Offset(left + width, y), strokeWidth = 1 * density, blendMode = BlendMode.Plus)
    }

    private fun DrawScope.drawSternum(cloud: ScanCloud, boxX: Float, boxY: Float, boxW: Float, boxH: Float,
                                      scale: Float, clock: Double, reduceMotion: Boolean) {
        val alpha = (if (reduceMotion) 0.58 else 0.42 + 0.3 * (0.5 + 0.5 * sin(clock / 0.6))).toFloat()
        val b = cloud.bounds
        val p = Offset((boxX + (0.5 - b.minX) / b.width * boxW).toFloat(), (boxY + (0.28 - b.minY) / b.height * boxH).toFloat())
        drawCircle(Brush.radialGradient(listOf(NB.lime1.copy(alpha = alpha * 0.55f), NB.lime1.copy(alpha = 0f)),
            center = p, radius = 14 * scale), radius = 14 * scale, center = p, blendMode = BlendMode.Plus)
        drawCircle(NB.lime1.copy(alpha = alpha), radius = 1.6f * scale, center = p, blendMode = BlendMode.Plus)
    }

    private fun smooth(value: Double): Double {
        val t = min(1.0, max(0.0, value))
        return t * t * (3 - 2 * t)
    }

    private fun easeOut(value: Double): Double {
        val t = min(1.0, max(0.0, value))
        return 1 - (1 - t).pow(3)
    }

    private fun bump(value: Double, low: Double, high: Double): Double {
        val t = (value - low) / (high - low)
        if (t <= 0 || t >= 1) return 0.0
        return sin(t * PI)
    }
}

private val BASE = Color(0xFFBDF5F0)

/**
 * Home's figure (`BodyCloud.shared`, features.home) in the scan's own double-precision form,
 * with the lit content's bounds the scan frames the figure by.
 */
internal class ScanCloud(
    val aspect: Float,
    val rows: Int,
    val motes: List<Mote>,
    val emitters: List<Int>,
) {
    class Mote(val x: Double, val y: Double, val light: Double, val seed: Double, val phase: Double,
               val scatterX: Double, val scatterY: Double)

    class Bounds(val minX: Double, val minY: Double, val width: Double, val height: Double)

    /** The lit content's box (light > 0.14), so the figure fills the stage, not the artwork. */
    val bounds: Bounds by lazy {
        var minX = Double.MAX_VALUE; var minY = Double.MAX_VALUE
        var maxX = -Double.MAX_VALUE; var maxY = -Double.MAX_VALUE
        for (m in motes) if (m.light > 0.14) {
            minX = min(minX, m.x); minY = min(minY, m.y); maxX = max(maxX, m.x); maxY = max(maxY, m.y)
        }
        if (maxX > minX && maxY > minY) Bounds(minX, minY, maxX - minX, maxY - minY) else Bounds(0.0, 0.0, 1.0, 1.0)
    }

    companion object {
        @Volatile private var cached: ScanCloud? = null

        fun shared(context: Context): ScanCloud =
            cached ?: synchronized(this) { cached ?: from(BodyCloud.shared(context)).also { cached = it } }

        private fun from(c: BodyCloud): ScanCloud = ScanCloud(
            aspect = c.aspect, rows = c.rows,
            motes = c.motes.map { m ->
                Mote(m.x.toDouble(), m.y.toDouble(), m.light.toDouble(), m.seed.toDouble(), m.phase.toDouble(),
                    m.scatterX.toDouble(), m.scatterY.toDouble())
            },
            emitters = c.emitters.toList())
    }
}
