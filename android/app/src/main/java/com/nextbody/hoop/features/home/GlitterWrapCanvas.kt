package com.nextbody.hoop.features.home

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.nextbody.hoop.band.GlitterWrapField
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/**
 * Persistent bitmap for Originkit Glitter Wrap: destination-out trail fade
 * plus additive square stamps. A feathered elliptical mask softens all four
 * edges so the field blooms instead of clipping to the panel rect.
 */
@Composable
fun GlitterWrapStage(paused: Boolean, modifier: Modifier = Modifier) {
    val view = remember { GlitterWrapView() }
    var frame by remember { mutableIntStateOf(0) }
    LaunchedEffect(paused) {
        if (paused) return@LaunchedEffect
        var last = -1L
        while (true) withFrameNanos { now ->
            val delta = if (last < 0) 1.0 / 60 else (now - last) / 1e9
            last = now
            view.render(delta)
            frame++
        }
    }
    Canvas(
        modifier
            .fillMaxSize()
            .clearAndSetSemantics { }
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                glitterWrapHaloMask()
            },
    ) {
        @Suppress("UNUSED_EXPRESSION") frame
        val dpr = min(density, 2f)
        view.ensure(size.width / density, size.height / density, dpr)
        if (paused) view.bakeIfNeeded()
        val bmp = view.bitmap ?: return@Canvas
        drawIntoCanvas { c ->
            c.nativeCanvas.drawBitmap(bmp, null, android.graphics.RectF(0f, 0f, size.width, size.height), view.blit)
        }
    }
}

/** The radial halo mask: white to 42 %, 70 % at 68 %, 18 % at 88 %, clear at the rim. */
private fun androidx.compose.ui.graphics.drawscope.DrawScope.glitterWrapHaloMask() {
    val w = size.width; val h = size.height
    val m = max(1f, min(w, h))
    scale((w / m) * 0.98f, (h / m) * 0.84f, pivot = center) {
        drawRect(
            Brush.radialGradient(
                0f to Color.White, 0.42f to Color.White, 0.68f to Color.White.copy(alpha = 0.7f),
                0.88f to Color.White.copy(alpha = 0.18f), 1f to Color.Transparent,
                center = center, radius = m * 0.5f,
            ),
            topLeft = Offset(-w, -h), size = androidx.compose.ui.geometry.Size(w * 3, h * 3),
            blendMode = BlendMode.DstIn,
        )
    }
}

private class GlitterWrapView {
    private val field = GlitterWrapField(seed = Random.nextLong(1, Long.MAX_VALUE).toULong())
    var bitmap: Bitmap? = null
        private set
    private var canvas: android.graphics.Canvas? = null
    private var w = 0
    private var h = 0
    private var dpr = 1f
    private var baked = false
    val blit = Paint(Paint.FILTER_BITMAP_FLAG)
    private val fade = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT) }
    private val add = Paint(Paint.ANTI_ALIAS_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.ADD) }

    fun ensure(widthPt: Float, heightPt: Float, scale: Float) {
        val nw = max(1, widthPt.toInt()); val nh = max(1, heightPt.toInt())
        field.width = nw.toDouble(); field.height = nh.toDouble()
        if (nw == w && nh == h && scale == dpr && bitmap != null) return
        w = nw; h = nh; dpr = scale
        val pw = max(1, (nw * scale).toInt()); val ph = max(1, (nh * scale).toInt())
        bitmap?.recycle()
        val b = Bitmap.createBitmap(pw, ph, Bitmap.Config.ARGB_8888)
        bitmap = b
        canvas = android.graphics.Canvas(b).apply { scale(scale, scale) }
        baked = false
    }

    /** Paused: one still frame, 80 steps in so the field is already full. */
    fun bakeIfNeeded() {
        if (baked) return
        repeat(80) { render(1.0 / 60.0) }
        baked = true
    }

    fun render(deltaSec: Double) {
        val c = canvas ?: return
        baked = false
        val frame = field.step(deltaSec, moving = true)
        fade.color = android.graphics.Color.argb((frame.trailAlpha * 255).toInt().coerceIn(0, 255), 0, 0, 0)
        c.drawRect(0f, 0f, w.toFloat(), h.toFloat(), fade)
        val palette = field.config.palette
        for (stamp in frame.stamps) {
            val col = palette[stamp.colorIdx.coerceIn(0, palette.size - 1)]
            val rgb = android.graphics.Color.rgb(col.r.toInt(), col.g.toInt(), col.b.toInt())
            val px = stamp.px; val py = stamp.py
            if (px != null && py != null) {
                add.style = Paint.Style.STROKE
                add.strokeWidth = max(0.4, stamp.r * 0.4).toFloat()
                add.color = rgb; add.alpha = (stamp.alpha * 0.5 * 255).toInt().coerceIn(0, 255)
                c.drawLine(px.toFloat(), py.toFloat(), stamp.sx.toFloat(), stamp.sy.toFloat(), add)
            }
            add.style = Paint.Style.FILL
            add.color = rgb; add.alpha = (stamp.alpha * 255).toInt().coerceIn(0, 255)
            val r = stamp.r.toFloat(); val sx = stamp.sx.toFloat(); val sy = stamp.sy.toFloat()
            c.drawRect(sx - r, sy - r, sx + r, sy + r, add)
            stamp.haloR?.let { rf ->
                val f = rf.toFloat()
                add.alpha = (stamp.alpha * 0.5 * 255).toInt().coerceIn(0, 255)
                c.drawRect(sx - f, sy - f, sx + f, sy + f, add)
            }
        }
    }
}
