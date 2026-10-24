package com.nextbody.hoop.features.connect

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.R
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.features.auth.GText
import com.nextbody.hoop.ui.HapticMotor
import com.nextbody.hoop.ui.HapticsSetting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 02 · 05 CONNECTED · the choreography, as a function of seconds since the screen appeared.
 * One clock drives everything on the success screen, so nothing is a chain of timers that can
 * drift apart; every function is pure in `t`, which is also what lets Reduce Motion show the
 * finished picture by asking for a late `t`.
 *
 *     0.00  the print comes in, cell by cell, hands apart
 *     0.35  the hands start to close
 *     1.45  almost there — a held breath, a tremor in the fingertips
 *     1.85  touch · haptic · the ring leaves the contact point
 *     2.05  YOU'RE CONNECTED types in
 *     2.85  「已经连上那个未来的你」 types in
 *     3.40  the after-pulse begins, and keeps going
 *     3.70  LINK LOCKED and the button
 */
object LinkChoreo {
    /** Where the fingertips meet, as a fraction of the picture. Measured off the asset. */
    const val touchU = 0.498f
    const val touchV = 0.497f
    /** Each hand starts this far from rest, in points, along the diagonal. */
    const val gapMax = 150f
    const val touchAt = 1.85
    const val titleAt = 2.05
    const val subtitleAt = 2.85
    const val pulseFrom = 3.40
    const val pulsePeriod = 2.6
    const val footerAt = 3.70

    fun printIn(t: Double) = easeOut(clamp01(t / 0.7))

    fun approach(t: Double): Double = when {
        t < 0.35 -> 0.0
        t < 1.45 -> 0.92 * easeInOut((t - 0.35) / 1.1)
        // The hesitation: held at a hair's breadth, with a tremor.
        t < 1.75 -> 0.92 + 0.006 * sin((t - 1.45) * 28)
        else -> 0.92 + 0.08 * easeIn(clamp01((t - 1.75) / 0.10))
    }

    /** Ring radius in points. `maxR` is what the shader treats as "off the frame". */
    fun reveal(t: Double, maxR: Double) = if (t < touchAt) 0.0 else 1.02 * maxR * easeOut(clamp01((t - touchAt) / 1.4))
    fun spark(t: Double) = if (t < touchAt) 0.0 else exp(-(t - touchAt) * 2.6)
    /** Phase 0…1 of the after-pulse, or −1 before it starts. */
    fun pulse(t: Double) = if (t < pulseFrom) -1.0 else ((t - pulseFrom) % pulsePeriod) / pulsePeriod
    fun burst(t: Double) = if (t < touchAt) 0.0 else easeOut(clamp01((t - touchAt) / 0.9))
    fun burstAlpha(t: Double) = if (t < touchAt) 0.0 else 1 - smooth(clamp01((t - touchAt - 1.1) / 1.3))
    fun title(t: Double) = clamp01((t - titleAt) / 0.75)
    fun subtitle(t: Double) = clamp01((t - subtitleAt) / 1.0)
    fun footer(t: Double) = easeOut(clamp01((t - footerAt) / 0.5))
    /** 0 before the touch, 1 from the touch, 2 from the title. Each step is one haptic. */
    fun hapticStage(t: Double) = if (t < touchAt) 0 else if (t < titleAt) 1 else 2

    /** A `t` past everything, for Reduce Motion and previews. */
    const val finished = 10.0

    private fun clamp01(x: Double) = min(1.0, max(0.0, x))
    private fun easeOut(x: Double) = 1 - (1 - x).pow(3)
    private fun easeIn(x: Double) = x * x * x
    private fun easeInOut(x: Double) = if (x < 0.5) 4 * x * x * x else 1 - (-2 * x + 2).pow(3) / 2
    private fun smooth(x: Double) = x * x * (3 - 2 * x)
}

/**
 * The two hands. One photograph, printed through the same cell maths the iOS fragment shader
 * (`HandsReveal.metal`) runs — here on the CPU, one pixel per cell, scaled up with no filtering
 * so the picture stays made of cells. `width`/`height` must be the frame the picture fills.
 */
@Composable
fun HandsLink(clock: Double, width: Dp, height: Dp, modifier: Modifier = Modifier, cell: Float = 4f) {
    val context = LocalContext.current
    val source = remember { HandsSource.load(context) }
    val printer = remember(width, height, cell) { HandsPrinter(width.value, height.value, cell) }
    Canvas(modifier.size(width, height).semantics { contentDescription = "" }) {
        val src = source ?: return@Canvas
        val image = printer.render(src, clock)
        val px = cell * density
        drawImage(image, srcOffset = IntOffset.Zero, srcSize = IntSize(printer.cols, printer.rows),
            dstOffset = IntOffset.Zero,
            dstSize = IntSize((printer.cols * px).roundToInt(), (printer.rows * px).roundToInt()),
            filterQuality = FilterQuality.None)
    }
}

/** The photograph, decoded once at a working size. */
private class HandsSource(val w: Int, val h: Int, val gray: FloatArray) {
    companion object {
        @Volatile private var cached: HandsSource? = null

        fun load(context: android.content.Context): HandsSource? {
            cached?.let { return it }
            val bmp = runCatching {
                val opts = BitmapFactory.Options().apply { inSampleSize = 1 }
                BitmapFactory.decodeResource(context.resources, R.drawable.hands_reach, opts)
            }.getOrNull() ?: return null
            // Work at ~2 samples per point of the 390-wide frame: plenty for a 4pt print.
            val targetW = min(bmp.width, 780)
            val targetH = (bmp.height.toFloat() * targetW / bmp.width).roundToInt()
            val scaled = if (targetW != bmp.width) Bitmap.createScaledBitmap(bmp, targetW, targetH, true) else bmp
            val px = IntArray(targetW * targetH)
            scaled.getPixels(px, 0, targetW, 0, 0, targetW, targetH)
            val g = FloatArray(px.size)
            for (i in px.indices) {
                val c = px[i]
                val r = ((c shr 16) and 0xFF) / 255f
                val gg = ((c shr 8) and 0xFF) / 255f
                val b = (c and 0xFF) / 255f
                g[i] = grayOf(r * 0.299f + gg * 0.587f + b * 0.114f)
            }
            return HandsSource(targetW, targetH, g).also { cached = it }
        }

        /** JPEG black is not black; floor it so the ground prints as nothing. */
        private fun grayOf(lum: Float): Float = smoothstep(0.035f, 1f, lum)
    }
}

private fun smoothstep(a: Float, b: Float, x: Float): Float {
    val k = ((x - a) / (b - a)).coerceIn(0f, 1f)
    return k * k * (3 - 2 * k)
}

private fun fract(x: Float) = x - floor(x)
private fun hrHash(x: Float, y: Float): Float = fract(sin(x * 127.1f + y * 311.7f) * 43758.5453f)

private val BAYER8 = intArrayOf(
    0, 32, 8, 40, 2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44, 4, 36, 14, 46, 6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
    3, 35, 11, 43, 1, 33, 9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47, 7, 39, 13, 45, 5, 37,
    63, 31, 55, 23, 61, 29, 53, 21,
)

/** The cell maths of `nbHandsReveal`, one output pixel per cell. */
private class HandsPrinter(val w: Float, val h: Float, val cell: Float) {
    val cols = kotlin.math.ceil(w / cell).toInt().coerceAtLeast(1)
    val rows = kotlin.math.ceil(h / cell).toInt().coerceAtLeast(1)
    private val out = IntArray(cols * rows)
    private val bitmap: Bitmap = Bitmap.createBitmap(cols, rows, Bitmap.Config.ARGB_8888)
    private val image: ImageBitmap = bitmap.asImageBitmap()

    private val ink = NB.panelInk
    private val lime = NB.lime1
    private val pale = NB.limePale
    private val white = NB.white

    // aspectRatio(.fill) of a 3:4 photograph into w × h, cropped equally.
    private var scale = 1f
    private var offX = 0f
    private var offY = 0f

    /** `layer.sample(p)` — the filled, clipped picture at a point of the frame. */
    private fun sample(src: HandsSource, x: Float, y: Float): Float {
        if (x < 0 || y < 0 || x >= w || y >= h) return 0f
        val ix = ((x - offX) / scale).toInt()
        val iy = ((y - offY) / scale).toInt()
        if (ix < 0 || iy < 0 || ix >= src.w || iy >= src.h) return 0f
        return src.gray[iy * src.w + ix]
    }

    fun render(src: HandsSource, time: Double): ImageBitmap {
        scale = max(w / src.w, h / src.h)
        offX = (w - src.w * scale) / 2
        offY = (h - src.h * scale) / 2

        val pictureHeight = w * 4 / 3
        val touchX = w * LinkChoreo.touchU
        val touchY = pictureHeight * LinkChoreo.touchV - (pictureHeight - h) / 2
        val maxR = hypot(w, h) * 0.62f
        val print = LinkChoreo.printIn(time).toFloat()
        val approach = LinkChoreo.approach(time).toFloat()
        val reveal = LinkChoreo.reveal(time, maxR.toDouble()).toFloat()
        val spark = LinkChoreo.spark(time).toFloat()
        val pulse = LinkChoreo.pulse(time).toFloat()
        val t = time.toFloat()

        // The top hand travels down-left to the meeting point; the bottom hand the reverse.
        val ax = -0.70710678f
        val ay = 0.70710678f
        val gap = LinkChoreo.gapMax * (1f - approach)
        val ringAlive = if (reveal > 0f) smoothstep(0f, 40f, reveal) * (1f - smoothstep(0.75f * maxR, maxR, reveal)) else 0f
        val litness = if (reveal > 0f) smoothstep(0f, maxR, reveal) else 0f
        val shift = floor(t * 3f).toInt()

        for (cy in 0 until rows) {
            for (cx in 0 until cols) {
                val pcx = (cx + 0.5f) * cell
                val pcy = (cy + 0.5f) * cell
                val dx = pcx - touchX
                val dy = pcy - touchY
                val dist = sqrt(dx * dx + dy * dy)
                val dirX = if (dist > 0.5f) dx / dist else 0f
                val dirY = if (dist > 0.5f) dy / dist else 0f
                // Light leaves the picture's bottom edge softly rather than crossing the lines under it.
                val below = 1f - smoothstep(0f, 44f, pcy - h)
                val ringK = exp(-((dist - reveal) / 70f).pow(2)) * ringAlive
                // Heat shimmer on the sparse print, gone once the picture is lit.
                val waveX = sin(pcy * 0.021f + t * 1.3f) * 1.6f * (1f - litness)
                val waveY = sin(pcx * 0.017f + t * 0.9f) * 1.6f * (1f - litness)
                val side = if (dx - dy > 0f) 1f else -1f
                val sx = pcx + side * ax * gap + waveX + dirX * ringK * 12f
                val sy = pcy + side * ay * gap + waveY + dirY * ringK * 12f
                // While the hands are apart a cell must only ever show its own hand.
                val own = if (gap > 0.5f) (if (((sx - touchX) - (sy - touchY) > 0f) == (side > 0f)) 1f else 0f) else 1f
                val g = sample(src, sx, sy) * own
                // Contour and specular rim print; the even mid-tone is pushed under the first level.
                val gx = abs(sample(src, sx + cell, sy) - sample(src, sx - cell, sy))
                val gy = abs(sample(src, sx, sy + cell) - sample(src, sx, sy - cell))
                val edge = ((gx + gy) * 1.9f).coerceIn(0f, 1f) * own

                // Ordered dither, the matrix drifting so the grain crawls.
                val mx = (cx + shift) and 7
                val my = (cy + shift) and 7
                val m = BAYER8[my * 8 + mx] / 64f - 0.5f

                // Each cell is born at its own moment while the print comes in.
                val born = hrHash(cx * 0.37f + 3.1f, cy * 0.37f + 3.1f)
                val on = if (print >= born) 1f else 0f
                // Near the frame edges a cell survives only by chance — grain, not a stump.
                val fade = min(min(smoothstep(0f, 96f, pcy), smoothstep(0f, 150f, h - pcy)),
                    min(smoothstep(0f, 44f, pcx), smoothstep(0f, 44f, w - pcx)))
                val alive = if (fade >= hrHash(cx * 1.71f + 9.37f, cy * 1.71f + 9.37f)) 1f else 0f

                // Sparse print · five levels in lime.
                val vPrint = max(edge * 0.55f, g.pow(2.8f) * 0.85f)
                val i0 = (vPrint * 4f + m).roundToInt().coerceIn(0, 4)
                val f0 = i0 / 4f * on
                var r = lime.red * f0
                var gr = lime.green * f0
                var b = lime.blue * f0
                val a0 = f0

                // Lit print · eight levels up the ramp.
                val vLit = max(edge * 0.46f, g.pow(1.60f))
                val i1 = (vLit * 7f + m).roundToInt().coerceIn(0, 7)
                val f1 = i1 / 7f
                val a1 = if (f1 > 0f) 1f else 0f
                var lr = 0f; var lg = 0f; var lb = 0f
                if (a1 > 0f) {
                    val c = ramp(f1)
                    lr = c[0]; lg = c[1]; lb = c[2]
                }

                // Inside the ring the sparse print gives way to the lit one.
                val inside = if (reveal > 0f) 1f - smoothstep(reveal - 60f, reveal + 60f, dist) else 0f
                r = (r + (lr - r) * inside) * alive
                gr = (gr + (lg - gr) * inside) * alive
                b = (b + (lb - b) * inside) * alive
                var alpha = (a0 + (a1 - a0) * inside) * alive

                // The hand has a body, and the body is ink — it puts the rays behind the hands.
                val body = smoothstep(0.09f, 0.24f, g) * own * alive * (if (on > 0f) 1f else print)
                val bodyA = body * 0.94f
                r += ink.red * bodyA * (1 - alpha)
                gr += ink.green * bodyA * (1 - alpha)
                b += ink.blue * bodyA * (1 - alpha)
                alpha += bodyA * (1 - alpha)

                // The ring itself: a bright line, its glow reaching a little ahead.
                val line = exp(-((dist - reveal) / 9f).pow(2)) * ringAlive
                val halo = exp(-((dist - reveal) / 34f).pow(2)) * ringAlive
                val ringLight = (halo * 0.28f + line * 0.85f) * below
                r += (pale.red * halo * 0.28f + white.red * line * 0.85f) * below
                gr += (pale.green * halo * 0.28f + white.green * line * 0.85f) * below
                b += (pale.blue * halo * 0.28f + white.blue * line * 0.85f) * below

                // The flash at the contact point.
                val flash = exp(-(dist * dist) / (2f * 42f * 42f)) * spark * 0.9f
                r += (lime.red + (white.red - lime.red) * spark) * flash
                gr += (lime.green + (white.green - lime.green) * spark) * flash
                b += (lime.blue + (white.blue - lime.blue) * spark) * flash

                // The after-pulse: a faint ring leaving the same point, again and again.
                var pk = 0f
                if (pulse > 0f) {
                    val pr = pulse * maxR
                    pk = exp(-((dist - pr) / 30f).pow(2)) * (1f - pulse) * (1f - pulse) * 0.22f * below
                    r += lime.red * pk; gr += lime.green * pk; b += lime.blue * pk
                }

                alpha = (alpha + ringLight + flash + pk).coerceIn(0f, 1f)
                r = min(r, 1f); gr = min(gr, 1f); b = min(b, 1f)
                out[cy * cols + cx] = if (alpha <= 0.002f) 0 else {
                    // Premultiplied in, straight ARGB out.
                    val ia = (alpha * 255f).roundToInt().coerceIn(0, 255)
                    val ur = (r / alpha).coerceIn(0f, 1f)
                    val ug = (gr / alpha).coerceIn(0f, 1f)
                    val ub = (b / alpha).coerceIn(0f, 1f)
                    (ia shl 24) or ((ur * 255f).roundToInt() shl 16) or ((ug * 255f).roundToInt() shl 8) or (ub * 255f).roundToInt()
                }
            }
        }
        bitmap.setPixels(out, 0, cols, 0, 0, cols, rows)
        image.prepareToDraw()
        return image
    }

    private val rampOut = FloatArray(3)

    /** The lit print's ramp: shadow → deep lime → lime → pale → white. */
    private fun ramp(t: Float): FloatArray {
        val shadow = floatArrayOf(lime.red * 0.30f, lime.green * 0.30f, lime.blue * 0.30f)
        val deep = floatArrayOf(lime.red * 0.62f, lime.green * 0.62f, lime.blue * 0.62f)
        val l = floatArrayOf(lime.red, lime.green, lime.blue)
        val p = floatArrayOf(pale.red, pale.green, pale.blue)
        val wh = floatArrayOf(white.red, white.green, white.blue)
        val (a, bb, k) = when {
            t < 0.30f -> Triple(shadow, deep, t / 0.30f)
            t < 0.62f -> Triple(deep, l, (t - 0.30f) / 0.32f)
            t < 0.86f -> Triple(l, p, (t - 0.62f) / 0.24f)
            else -> Triple(p, wh, (t - 0.86f) / 0.14f)
        }
        for (i in 0..2) rampOut[i] = a[i] + (bb[i] - a[i]) * k
        return rampOut
    }
}

/**
 * 02 · 05 CONNECTED · the link, felt. One score, scheduled against the same clock the picture
 * runs on: a rumble that grows while the hands close, three small tremors at the hesitation,
 * one hard strike at the fingertips, a decay, then the two lines and the button landing.
 * Android has no continuous haptic event, so the rumble and the decay are dense trains of
 * small blunt transients whose intensity follows the iOS curves.
 */
object LinkHaptics {
    val isSupported: Boolean get() = HapticMotor.supported

    private const val rumbleFrom = 0.45
    private val rumbleTo get() = LinkChoreo.touchAt - 0.06

    fun play(scope: CoroutineScope, still: Boolean): Job = scope.launch {
        if (!HapticsSetting.enabled) return@launch
        val events = if (still) contactOnly() else score()
        var clock = 0.0
        for ((at, intensity, sharpness) in events.sortedBy { it.first }) {
            val wait = at - clock
            if (wait > 0) delay((wait * 1000).toLong())
            clock = at
            HapticMotor.transient(intensity, sharpness)
        }
    }

    private fun score(): List<Triple<Double, Float, Float>> {
        val out = mutableListOf<Triple<Double, Float, Float>>()
        // The closing: barely there for the first half, then steep.
        val span = rumbleTo - rumbleFrom
        var t = rumbleFrom
        while (t < rumbleTo) {
            val k = (t - rumbleFrom) / span
            val curve = when {
                k < 0.55 -> 0.05 + (0.28 - 0.05) * (k / 0.55)
                k < 0.85 -> 0.28 + (0.62 - 0.28) * ((k - 0.55) / 0.30)
                else -> 0.62 + (1.0 - 0.62) * ((k - 0.85) / 0.15)
            }
            if (t !in 1.45..1.75) out += Triple(t, (0.62 * curve).toFloat(), 0.10f)
            t += 0.07
        }
        // The hesitation: three small dry taps.
        listOf(1.47, 1.585, 1.70).forEachIndexed { i, at -> out += Triple(at, (0.16 + 0.04 * i).toFloat(), 0.80f) }
        // Contact. The hardest thing on the screen.
        out += Triple(LinkChoreo.touchAt, 1.0f, 0.92f)
        // What the strike leaves behind: a body that empties out.
        var d = 0.07
        while (d < 0.90) {
            val c = if (d < 0.30) 1.0 + (0.34 - 1.0) * (d / 0.30) else 0.34 * (1 - (d - 0.30) / 0.60)
            out += Triple(LinkChoreo.touchAt + 0.02 + d, (0.80 * c).toFloat(), 0.28f)
            d += 0.08
        }
        // The two lines landing, and the button arriving under them.
        out += Triple(LinkChoreo.titleAt, 0.42f, 0.62f)
        out += Triple(LinkChoreo.subtitleAt, 0.22f, 0.45f)
        out += Triple(LinkChoreo.footerAt, 0.30f, 0.50f)
        return out
    }

    /** Reduce Motion · the contact alone, on the first beat. */
    private fun contactOnly(): List<Triple<Double, Float, Float>> =
        listOf(Triple(0.0, 1.0f, 0.92f), Triple(0.12, 0.30f, 0.28f), Triple(0.26, 0.18f, 0.28f))
}

/**
 * A line typing itself in: the finished line lays out invisibly so nothing shifts while the
 * letters arrive, and a block cursor sits at the end until the last one lands.
 */
@Composable
fun TypeIn(text: String, progress: Double, style: TextStyle, size: Float, color: Color, modifier: Modifier = Modifier) {
    val n = floor(text.length * progress).toInt().coerceIn(0, text.length)
    val shown = text.take(n)
    val tracking = style.letterSpacing.value * size
    Box(modifier.alpha(if (progress > 0) 1f else 0f).semantics { contentDescription = text }, contentAlignment = Alignment.CenterStart) {
        GText(text, style, Color.Transparent, maxLines = 1)
        Row(verticalAlignment = Alignment.CenterVertically) {
            GText(shown, style, color, maxLines = 1)
            if (progress > 0 && progress < 1) {
                Box(Modifier.offset(x = if (n == 0) 0.dp else (-tracking * 0.5f).dp)
                    .size((size * 0.55f).dp, size.dp).background(color))
            }
        }
    }
}

@Suppress("unused")
private fun Color.argb(): Int = toArgb()
