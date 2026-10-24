package com.nextbody.hoop.features.home

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.R
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.ui.SwiftEaseOut
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

/** Wall-clock seconds on the same wrapped scale as [rememberArtClock], so the two can be subtracted. */
internal fun nowSeconds(): Double = System.currentTimeMillis() / 1000.0 % 100_000.0

/**
 * The body-scan figure as a live point cloud. The points are sampled once from the `home_body`
 * artwork by brightness; on screen they gather, breathe, shimmer and get swept by a scan line.
 */
@Composable
fun HomeBodyParticles(
    /** One per `HomeV2Model.Zone`, in `entries` order: head, heart, gut, legs. */
    spots: List<BodyCloud.Spot>,
    /** Only the page on screen animates. */
    active: Boolean,
    modifier: Modifier = Modifier,
    lens: BodyLens = BodyLens.fit,
    /** false: the figure is already standing on first show, only the ripple and sweep play. */
    gathers: Boolean = true,
) {
    val context = LocalContext.current
    val reduceMotion = rememberReduceMotion()
    val artActive = LocalHomeArtActive.current
    val cloud = remember(lens.height == null) {
        if (lens.height == null) BodyCloud.shared(context) else BodyCloud.dense(context)
    }
    // Set the first time the page is shown. Until then nothing is drawn, so the first visit
    // watches the figure assemble; later visits get a ripple and a fresh sweep instead.
    var gatheredAt by remember { mutableStateOf<Double?>(null) }
    var pulsedAt by remember { mutableDoubleStateOf(Double.NEGATIVE_INFINITY) }
    LaunchedEffect(active) {
        if (active) {
            if (gatheredAt == null) gatheredAt = if (gathers) nowSeconds() else Double.NEGATIVE_INFINITY
            pulsedAt = nowSeconds()
        }
    }
    val shown = gatheredAt != null || reduceMotion
    val haloAlpha by animateFloatAsState(
        if (shown) 1f else 0f,
        tween(1400, delayMillis = if (gathers) 600 else 0, easing = SwiftEaseOut), label = "halo",
    )
    // ⚠️ Thousands of motes are rebuilt into paths every frame: 30 Hz, and only while seen.
    val clock = rememberArtClock(active && artActive && !reduceMotion)
    Box(modifier.clearAndSetSemantics { }) {
        // Soft aura under the points. Drawn once per size, blurred on the GPU.
        Canvas(
            Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = haloAlpha }
                .then(if (Build.VERSION.SDK_INT >= 31) Modifier.blur(7.dp) else Modifier),
        ) { cloud.drawHalo(this, lens) }
        Canvas(Modifier.fillMaxSize()) {
            val frame = BodyCloud.Frame(
                now = clock,
                gatheredAt = if (reduceMotion) Double.NEGATIVE_INFINITY else gatheredAt,
                pulsedAt = pulsedAt,
                spots = spots,
                lens = lens,
                still = reduceMotion,
            )
            cloud.draw(this, frame)
        }
    }
}

/** Where the artwork sits in its canvas: fitted whole, or enlarged around one point. */
data class BodyLens(
    /** Figure height in dp. null fits the whole figure in the canvas. */
    val height: Float? = null,
    /** The artwork point (0…1) that lands on `target`. */
    val focus: Offset = Offset(0.5f, 0.5f),
    /** Where `focus` lands, in canvas units. */
    val target: Offset = Offset(0.5f, 0.5f),
) {
    /** [size] in px, [density] to turn [height] (dp) into px. */
    fun box(size: Size, aspect: Float, density: Float = 1f): Rect {
        val h = height
        if (h == null) {
            var fitHeight = size.height
            var fitWidth = fitHeight * aspect
            if (fitWidth > size.width) {
                fitWidth = size.width
                fitHeight = fitWidth / aspect
            }
            return Rect(Offset((size.width - fitWidth) / 2, (size.height - fitHeight) / 2), Size(fitWidth, fitHeight))
        }
        val hp = h * density
        val width = hp * aspect
        return Rect(
            Offset(target.x * size.width - focus.x * width, target.y * size.height - focus.y * hp),
            Size(width, hp),
        )
    }

    companion object {
        val fit = BodyLens()
    }
}

/**
 * The middle of the body part, in `home_body` artwork units. Leader lines end here,
 * the tap zooms in around it, and the detail page frames it.
 */
val HomeV2Model.Zone.anchor: Offset
    get() = when (this) {
        HomeV2Model.Zone.head -> Offset(0.5f, 0.115f)
        HomeV2Model.Zone.heart -> Offset(0.56f, 0.265f)
        HomeV2Model.Zone.gut -> Offset(0.5f, 0.43f)
        HomeV2Model.Zone.legs -> Offset(0.45f, 0.72f)
    }

/** The close-up on the detail page: figure height, and where the anchor lands. */
val HomeV2Model.Zone.closeUp: BodyLens
    get() = when (this) {
        HomeV2Model.Zone.head -> BodyLens(980f, anchor, Offset(0.74f, 0.34f))
        HomeV2Model.Zone.heart -> BodyLens(760f, anchor, Offset(0.68f, 0.34f))
        HomeV2Model.Zone.gut -> BodyLens(800f, anchor, Offset(0.70f, 0.30f))
        HomeV2Model.Zone.legs -> BodyLens(900f, anchor, Offset(0.72f, 0.42f))
    }

class BodyCloud private constructor(
    val aspect: Float,
    /** Sampling rows; sets the point size so the cloud reads as solid at any zoom. */
    val rows: Int,
    internal val motes: List<Mote>,
    /** Bright points that shed rising dust. */
    internal val emitters: IntArray,
) {
    class Mote(
        /** 0…1 of the artwork. */
        val x: Float,
        val y: Float,
        /** 0…1 brightness of the source pixel. */
        val light: Float,
        val seed: Float,
        val phase: Float,
        /** Where the point waits before it gathers, in figure heights from home. */
        val scatterX: Float,
        val scatterY: Float,
    )

    /** One zone's light: how hot it burns and in which colour. Intensity 0 leaves the motes white. */
    data class Spot(val intensity: Double, val tint: Color)

    class Frame(
        val now: Double,
        /** null: the page has not been shown yet. */
        val gatheredAt: Double?,
        val pulsedAt: Double,
        /** In `HomeV2Model.Zone.entries` order. A spot with intensity 0 tints nothing. */
        val spots: List<Spot>,
        val lens: BodyLens,
        val still: Boolean,
    )

    companion object {
        private const val levels = 6
        /** Tone zero: the untinted mote colour, and the scan line. */
        private val base = hex(0xBDF5F0)
        /**
         * Zones in artwork units, in `HomeV2Model.Zone` order: head, heart, gut, legs.
         * Narrow enough that the arms and hands beside the torso stay untinted.
         */
        private val zones = listOf(
            Rect(Offset(0.36f, 0.00f), Size(0.28f, 0.19f)),
            Rect(Offset(0.48f, 0.20f), Size(0.20f, 0.14f)),
            Rect(Offset(0.33f, 0.37f), Size(0.34f, 0.15f)),
            Rect(Offset(0.34f, 0.52f), Size(0.32f, 0.46f)),
        )

        @Volatile private var sharedCloud: BodyCloud? = null
        @Volatile private var denseCloud: BodyCloud? = null

        fun shared(context: Context): BodyCloud =
            sharedCloud ?: sample(context, 150).also { sharedCloud = it }

        /** For close-ups. About three times the points; only those on screen are drawn. */
        fun dense(context: Context): BodyCloud =
            denseCloud ?: sample(context, 260).also { denseCloud = it }

        val sharedAspect: Float get() = sharedCloud?.aspect ?: 0.56f

        private fun sample(context: Context, cols: Int): BodyCloud {
            val image = runCatching {
                BitmapFactory.decodeResource(context.resources, R.drawable.home_body)
            }.getOrNull() ?: return BodyCloud(0.56f, 1, emptyList(), IntArray(0))
            val aspect = image.width.toFloat() / image.height.toFloat()
            val rows = (cols / aspect).roundToInt()
            val scaled = Bitmap.createScaledBitmap(image, cols, rows, true)
            val argb = IntArray(cols * rows)
            scaled.getPixels(argb, 0, cols, 0, 0, cols, rows)

            val rng = SplitMix(0x5EEDB0D1L)
            val motes = ArrayList<Mote>(cols * rows / 8)
            val emitters = ArrayList<Int>()
            for (row in 0 until rows) {
                for (col in 0 until cols) {
                    val p = argb[row * cols + col]
                    val r = (p shr 16) and 0xFF
                    val g = (p shr 8) and 0xFF
                    val b = p and 0xFF
                    val light = (0.299f * r + 0.587f * g + 0.114f * b) / 255f
                    if (!(light > 0.14f && rng.unit() < min(1f, (light - 0.1f) * 1.7f))) continue
                    val x = (col + rng.unit()) / cols
                    val y = (row + rng.unit()) / rows
                    val angle = atan2(y - 0.45f, (x - 0.5f) * aspect) + (rng.unit() - 0.5f) * 1.4f
                    val reach = 0.2f + rng.unit() * 0.5f
                    if (light > 0.55f && rng.unit() < 0.3f) emitters.add(motes.size)
                    motes.add(
                        Mote(
                            x, y, min(1f, light * 1.15f), rng.unit(), rng.unit() * 2 * PI.toFloat(),
                            cos(angle) * reach, sin(angle) * reach,
                        ),
                    )
                }
            }
            return BodyCloud(aspect, rows, motes, emitters.toIntArray())
        }

        private fun bump(value: Float, low: Float, high: Float): Float {
            val t = (value - low) / (high - low)
            if (t <= 0 || t >= 1) return 0f
            return sin(t * PI.toFloat())
        }
    }

    fun draw(scope: DrawScope, frame: Frame) = with(scope) {
        val gatheredAt = frame.gatheredAt ?: return@with
        if (motes.isEmpty()) return@with
        val box = frame.lens.box(size, aspect, density)
        if (box.height <= 4 * density) return@with
        // Point sizes are in dp in the Swift; the scale is dp-per-row, carried into px.
        val boxHeightDp = box.height / density
        val scale = min(1.6f, max(0.55f, boxHeightDp / rows / 1.8f)) * density
        val pad = 24 * density
        val bounds = Rect(-pad, -pad, size.width + pad, size.height + pad)
        // The sweep crosses the visible part of the figure, whole or close-up.
        val top = max(0f, -box.top / box.height)
        val span = max(0.05f, min(1f, (size.height - box.top) / box.height) - top)

        val clock = if (frame.still) 0.0 else frame.now % 3600.0
        val gatherAge = frame.now - gatheredAt
        val pulseAge = if (frame.still) Double.POSITIVE_INFINITY else frame.now - frame.pulsedAt
        val breath = sin(clock * 2 * PI / 4.8).toFloat()
        val ripple = if (pulseAge < 0.9) sin(pulseAge / 0.9 * PI).toFloat() else 0f
        val settle = min(1.0, max(0.0, (gatherAge - 1.6) / 0.8)).toFloat()
        val scanClock = if (pulseAge < 1e6) pulseAge else clock
        val scanY: Float? = if (frame.still) null
        else top + (((scanClock / 5.2) % 1.0).toFloat() * 1.3f - 0.15f) * span

        val paths = Array((1 + frame.spots.size) * levels) { Path() }
        val flares = Path()

        fun put(x: Float, y: Float, side: Float, alpha: Float, tone: Int) {
            if (alpha <= 0.04f) return
            val level = min(levels - 1, (alpha * levels).toInt())
            paths[tone * levels + level].addRect(Rect(x - side / 2, y - side / 2, x + side / 2, y + side / 2))
        }

        for (mote in motes) {
            val hx = box.left + mote.x * box.width
            val hy = box.top + mote.y * box.height
            if (!bounds.contains(Offset(hx, hy))) continue
            val delay = mote.y * 0.55 + mote.seed * 0.45
            val progress = min(1.0, max(0.0, (gatherAge - delay) / 1.2))
            val ease = (1 - (1 - progress).pow(3)).toFloat()
            if (ease <= 0.01f) continue
            val away = 1 - ease

            val torso = bump(mote.y, 0.16f, 0.56f)
            var x = 0.5f + (mote.x - 0.5f) * (1 + 0.014f * breath * torso)
            var y = mote.y - 0.003f * breath * torso
            var bright = mote.light
            var grow = 1f
            if (scanY != null) {
                val d = (y - scanY) / (0.022f * span)
                val band = exp(-d * d) * settle
                x += (x - 0.5f) * band * 0.035f
                bright += band * 0.8f
                grow += band * 0.7f
            }
            if (ripple > 0) {
                val push = ripple * (0.012f + 0.02f * mote.seed)
                x += (mote.x - 0.5f) * push * 2
                y += (mote.y - 0.45f) * push
                bright += ripple * 0.3f
            }

            val px = box.left + x * box.width + mote.scatterX * away * box.height +
                sin(clock * 0.8 + mote.phase).toFloat() * 0.7f * scale
            val py = box.top + y * box.height + mote.scatterY * away * box.height +
                cos(clock * 0.6 + mote.phase * 1.7).toFloat() * 0.7f * scale
            val twinkle = 0.6f + 0.4f * sin(clock * (1.2 + mote.seed * 3) + mote.phase).toFloat()
            val alpha = min(1f, bright * twinkle) * ease
            val side = (0.9f + mote.light * 1.1f) * scale * grow

            var tone = 0
            val zone = zones.indexOfFirst { it.contains(Offset(mote.x, mote.y)) }
            if (zone >= 0 && zone < frame.spots.size &&
                (mote.seed * 37.7f) % 1f < frame.spots[zone].intensity.toFloat() * 0.8f
            ) tone = zone + 1
            put(px, py, side, alpha, tone)

            if (mote.seed > 0.992f && sin(clock * 0.7 + mote.phase * 3) > 0.94) {
                val arm = 4 * scale
                val thin = 0.4f * density
                flares.addRect(Rect(px - arm, py - thin, px + arm, py + thin))
                flares.addRect(Rect(px - thin, py - arm, px + thin, py + arm))
            }
        }

        if (!frame.still && settle > 0 && emitters.isNotEmpty()) {
            for (index in 0 until min(70, emitters.size)) {
                val mote = motes[emitters[(index * 131) % emitters.size]]
                val rate = 0.08 + 0.1 * ((mote.seed * 13.3f) % 1f)
                val life = ((clock * rate + mote.phase / (2 * PI)) % 1.0).toFloat()
                val px = box.left + mote.x * box.width + sin(clock * 0.9 + mote.phase).toFloat() * 4 * scale
                val py = box.top + (mote.y - life * 0.12f) * box.height
                put(px, py, 1.2f * scale, sin(life * PI.toFloat()) * 0.55f * settle, 0)
            }
        }

        if (scanY != null && settle > 0 && scanY in 0f..1f) {
            val lineY = box.top + scanY * box.height
            val left = max(0f, box.left)
            val right = min(size.width, box.right)
            drawRect(
                Brush.horizontalGradient(
                    listOf(base.copy(alpha = 0f), base.copy(alpha = 0.5f * settle), base.copy(alpha = 0f)),
                    startX = left, endX = right,
                ),
                topLeft = Offset(left, lineY - 0.5f * density),
                size = Size(right - left, 1f * density),
                blendMode = BlendMode.Plus,
            )
        }
        for (tone in 0..frame.spots.size) {
            val tint = if (tone == 0) base else frame.spots[tone - 1].tint
            for (level in 0 until levels) {
                val path = paths[tone * levels + level]
                if (path.isEmpty) continue
                val opacity = (level + 0.5f) / levels
                drawPath(path, tint.copy(alpha = tint.alpha * opacity))
            }
        }
        drawPath(flares, NB.white.copy(alpha = 0.85f))
    }

    fun drawHalo(scope: DrawScope, lens: BodyLens) = with(scope) {
        val box = lens.box(size, aspect, density)
        if (box.height <= 4 * density) return@with
        val side = 2.6f * min(1.6f, max(0.55f, box.height / density / rows / 1.8f)) * density
        val pad = 16 * density
        val bounds = Rect(-pad, -pad, size.width + pad, size.height + pad)
        val halo = Path()
        for (mote in motes) {
            if (mote.light <= 0.35f) continue
            val p = Offset(box.left + mote.x * box.width, box.top + mote.y * box.height)
            if (!bounds.contains(p)) continue
            halo.addRect(Rect(p.x - side / 2, p.y - side / 2, p.x + side / 2, p.y + side / 2))
        }
        drawPath(halo, base.copy(alpha = 0.32f), blendMode = BlendMode.Plus)
    }
}

/** Deterministic, so the figure is the same constellation on every launch. */
private class SplitMix(private var state: Long) {
    fun unit(): Float {
        state += -0x61c8864680b583ebL // 0x9E3779B97F4A7C15
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L // 0xBF58476D1CE4E5B9
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L // 0x94D049BB133111EB
        z = z xor (z ushr 31)
        return ((z ushr 11).toDouble() / (1L shl 53).toDouble()).toFloat()
    }
}
