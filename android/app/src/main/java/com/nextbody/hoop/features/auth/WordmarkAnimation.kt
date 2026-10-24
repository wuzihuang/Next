package com.nextbody.hoop.features.auth

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.HapticMotor
import com.nextbody.hoop.ui.HapticsSetting
import com.nextbody.hoop.ui.ImpactStyle
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * MOTION SPEC · 01 · 像素坠落 → 字标成形.
 * 2.6s, plays through once, never loops. Two places: a new registration, and the moment the
 * band pairs. Cold start is [LaunchMark], not this film.
 *
 *  0.00 → 0.35  the whole screen goes lime for 120ms then drops to pure black — a power-on.
 *  0.35 → 1.10  pixels fall from above at three speeds, each dragging a short blur; a 1px lime floor.
 *  1.10 → 1.80  every pixel drops into its own letter cell, overshooting 4pt before springing back.
 *  1.80 → 2.15  the last pixel lands and the whole word lights lime at once; strays are flung aside.
 *  2.15 → 2.60  the matrix cross-dissolves into the solid wordmark; the sub-line 200ms later.
 *               The dot lands on two taps — the 「噔噔」. See [WordmarkHaptics].
 */
@Composable
fun WordmarkAnimation(onFinish: () -> Unit) {
    val reduceMotion = rememberReduceMotion()
    val finish by rememberUpdatedState(onFinish)
    val pin = DebugEnv["NB_DEBUG_WORDMARK_T"]?.toDoubleOrNull()
    var t by remember { mutableDoubleStateOf(pin ?: if (reduceMotion) TOTAL else 0.0) }

    LaunchedEffect(Unit) {
        // Haptic score is scheduled against the same clock the picture is stamped on.
        val score = WordmarkHaptics.play(this, still = reduceMotion)
        if (pin != null) return@LaunchedEffect
        if (reduceMotion) {
            // Reduce Motion holds the last frame: the word still has to be read.
            delay((STILL * 1000).toLong())
            finish()
            return@LaunchedEffect
        }
        val start = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            t = (now - start) / 1e9
            if (t >= TOTAL) break
        }
        score.cancel()
        finish()
    }

    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        // ◇1 · power-on flash
        Box(Modifier.fillMaxSize().alpha(flashOpacity(t).toFloat()).background(NB.lime1))
        PixelFall(t, Modifier.fillMaxSize())
        // ◇5 · the solid wordmark takes over
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Row(Modifier.alpha(solidOpacity(t).toFloat()), horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalAlignment = Alignment.CenterVertically) {
                val g = glow(t).toFloat()
                GText(L("NEXTBODY"), NBFont.brand(800, 46f).tracking(-0.01f).copy(
                    shadow = Shadow(NB.lime1.copy(alpha = 0.5f * g), Offset.Zero, 48f)), NB.text1, maxLines = 1)
                Box(Modifier.size(6.dp).background(NB.lime1, RoundedCornerShape(1.5.dp)))
            }
            GText(L("Find your next body."), NBFont.ui(300, 21f).tracking(0.02f), NB.white.copy(alpha = 0.82f),
                Modifier.alpha(subOpacity(t).toFloat()))
        }
    }
}

private const val TOTAL = 2.60
/** Reduce Motion holds the last frame instead of playing the fall. */
private const val STILL = 1.40

private fun flashOpacity(t: Double): Double = when {
    t < 0.12 -> 1.0
    t < 0.35 -> 1 - (t - 0.12) / 0.23
    else -> 0.0
}
private fun glow(t: Double): Double = when {
    t < 1.80 -> 0.0
    t < 2.15 -> (t - 1.80) / 0.35
    else -> max(0.0, 1 - (t - 2.15) / 0.45)
}
private fun solidOpacity(t: Double): Double = if (t < 2.15) 0.0 else min(1.0, (t - 2.15) / 0.45)
private fun subOpacity(t: Double): Double = if (t < 2.35) 0.0 else min(1.0, (t - 2.35) / 0.25)

/**
 * Opening still. Take 1's lime pip on take 2's Doto.
 * The only move is a typewriter: first line, then the pip, then the second line.
 */
@Composable
fun LaunchMark() {
    val reduceMotion = rememberReduceMotion()
    val word = L("NEXTBODY")
    val line = launchLine()
    var wordCount by remember { mutableIntStateOf(0) }
    var lineCount by remember { mutableIntStateOf(0) }
    var showPip by remember { mutableStateOf(false) }

    LaunchedEffect(word, line) {
        val step = DebugEnv["NB_DEBUG_LAUNCH_STEP"]
        if (step != null) {
            when (step) {
                "blank" -> {}
                "word" -> wordCount = max(1, word.length / 2)
                "wordfull" -> wordCount = word.length
                "pip" -> { wordCount = word.length; showPip = true }
                "line" -> { wordCount = word.length; showPip = true; lineCount = max(1, line.length / 2) }
                else -> { wordCount = word.length; showPip = true; lineCount = line.length }
            }
            return@LaunchedEffect
        }
        if (reduceMotion) {
            wordCount = word.length; showPip = true; lineCount = line.length
            return@LaunchedEffect
        }
        for (n in 1..word.length) { wordCount = n; delay(28) }
        showPip = true
        delay(180)
        for (n in 1..line.length) { lineCount = n; delay(28) }
    }

    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                TypedSlot(word, wordCount, 28f, 700, 0.14f, NB.white)
                Box(Modifier.size(6.dp).alpha(if (showPip) 1f else 0f).background(NB.lime1, RoundedCornerShape(1.5.dp)))
            }
            TypedSlot(line, lineCount, 11f, 400, 0.22f, NB.white.copy(alpha = 0.72f))
        }
    }
}

/** The finished line lays out invisibly so nothing shifts while the letters arrive. */
@Composable
private fun TypedSlot(full: String, count: Int, size: Float, weight: Int, tracking: Float, color: Color) {
    val style = NBFont.dot(weight, size).tracking(tracking)
    Box(contentAlignment = Alignment.CenterStart) {
        GText(full, style, Color.Transparent, maxLines = 1)
        GText(full.take(count), style, color, maxLines = 1)
    }
}

fun launchLine(): String {
    val line = L("Build Your NextBody")
    return if (AppLanguage.isEnglish) line.uppercase() else line
}

// MARK: the falling matrix

/** A 5 × 7 face for the eight letters of the wordmark. */
private val FONT: Map<Char, List<String>> = mapOf(
    'N' to listOf("X...X", "XX..X", "XX..X", "X.X.X", "X..XX", "X..XX", "X...X"),
    'E' to listOf("XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"),
    'X' to listOf("X...X", "X...X", ".X.X.", "..X..", ".X.X.", "X...X", "X...X"),
    'T' to listOf("XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.."),
    'B' to listOf("XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX."),
    'O' to listOf(".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."),
    'D' to listOf("XXXX.", "X...X", "X...X", "X...X", "X...X", "X...X", "XXXX."),
    'Y' to listOf("X...X", "X...X", ".X.X.", "..X..", "..X..", "..X..", "..X.."),
)

private class Pixel(val tx: Float, val ty: Float, val speed: Int, val startX: Float, val stray: Boolean, val strayDrift: Float)

private val PIXELS: List<Pixel> by lazy {
    val word = "NEXTBODY"
    val cell = 4.4f
    val letterW = cell * 6
    val totalW = letterW * word.length - cell
    val originX = (390f - totalW) / 2
    // ◇5 dissolves the matrix into the solid wordmark: the same centre line, 15pt up.
    val originY = 384f
    val out = mutableListOf<Pixel>()
    var seed: ULong = 0x2545F4914F6CDD1DUL
    fun rnd(): Float {
        seed = seed * 6364136223846793005UL + 1442695040888963407UL
        return ((seed shr 33) % 1000UL).toFloat() / 1000f
    }
    word.forEachIndexed { li, ch ->
        val rows = FONT[ch] ?: return@forEachIndexed
        rows.forEachIndexed { r, row ->
            row.forEachIndexed { c, ck ->
                if (ck == 'X') {
                    val speed = (rnd() * 3).toInt()
                    val sx = originX + li * letterW + c * cell + (rnd() - 0.5f) * 44
                    out += Pixel(originX + li * letterW + c * cell, originY + r * cell, speed, sx, false, 0f)
                }
            }
        }
    }
    // strays — they never had a cell, and nobody tidies them away
    repeat(26) {
        val tx = rnd() * 390
        val speed = (rnd() * 3).toInt()
        val sx = rnd() * 390
        val drift = (rnd() - 0.5f) * 320
        out += Pixel(tx, 414f, speed, sx, true, drift)
    }
    out
}

@Composable
private fun PixelFall(t: Double, modifier: Modifier) {
    Canvas(modifier) {
        if (t < 0.30) return@Canvas
        // Laid out on the 390 × 844 board; on a wider phone scaled and centred.
        val k = size.width / 390f
        scale(k, k, pivot = Offset.Zero) {
            translate(0f, (size.height / k - 844f) / 2) {
                PIXELS.forEachIndexed { i, px ->
                    val lead = px.speed * 0.14 + (i % 7) * 0.012
                    val fallStart = 0.35 + lead
                    val fallEnd = 1.10 + lead
                    if (t < fallStart) return@forEachIndexed
                    var y: Float
                    var x = px.startX
                    var alpha: Double
                    var trail = 0f
                    if (t < fallEnd) {
                        val p = (t - fallStart) / (fallEnd - fallStart)
                        y = -10f + (px.ty + 10f) * p.toFloat()
                        trail = (10 - px.speed * 3) * (1 - p * 0.4).toFloat()
                        alpha = 0.28 + 0.32 * (2 - px.speed) / 2.0
                    } else if (t < 1.80) {
                        // ◇3 · land with a 4pt overshoot, then spring back
                        val p = min(1.0, (t - fallEnd) / (1.80 - fallEnd))
                        val over = sin(p * PI) * 4
                        y = px.ty + (over * (1 - p)).toFloat()
                        x = px.startX + (px.tx - px.startX) * p.toFloat()
                        alpha = 0.45
                    } else {
                        y = px.ty
                        x = px.tx
                        alpha = if (t < 2.15) 0.45 + 0.55 * (t - 1.80) / 0.35 else max(0.0, 1 - (t - 2.15) / 0.45)
                    }
                    if (px.stray && t >= 1.80) {
                        val p = min(1.0, (t - 1.80) / 0.6)
                        x = px.startX + px.strayDrift * p.toFloat()
                        alpha *= 1 - p
                    }
                    val base = if (t >= 1.80) NB.lime1 else NB.white.copy(alpha = 0.9f)
                    if (trail > 0) {
                        drawRect(base.copy(alpha = base.alpha * (alpha * 0.35).toFloat().coerceIn(0f, 1f)),
                            Offset(x, y - trail), Size(3f, trail + 3f))
                    }
                    drawRect(base.copy(alpha = base.alpha * alpha.toFloat().coerceIn(0f, 1f)), Offset(x, y), Size(3f, 3f))
                }
                // the floor
                if (t >= 0.35 && t < 1.95) {
                    val a = if (t < 1.80) 0.55 else 0.55 * (1 - (t - 1.80) / 0.15)
                    drawRect(NB.lime1.copy(alpha = a.toFloat().coerceIn(0f, 1f)), Offset(0f, 454f), Size(390f, 1f))
                }
            }
        }
    }
}

/**
 * 02M · the film's haptic score. Two gestures and a silence between them: the rain of the
 * fall, then the 「噔噔」 as the dot lands. The power-on flash is deliberately untouched.
 * Android has no Core Haptics: the score is the same events, scheduled on the film's clock.
 */
object WordmarkHaptics {
    fun play(scope: CoroutineScope, still: Boolean): Job = scope.launch {
        if (!HapticsSetting.enabled) return@launch
        // Reduce Motion: no rain to track — only the landing, moved onto that shorter beat.
        val dun1 = if (still) 0.50 else 2.30
        val dun2 = if (still) 0.62 else 2.42
        val events = mutableListOf<Triple<Double, Float, Float>>()
        if (!still) events += rain()
        // ◇5 · two transients 120 ms apart, the second harder and sharper.
        events += Triple(dun1, 0.70f, 0.55f)
        events += Triple(dun2, 1.0f, 0.95f)
        var clock = 0.0
        for ((at, intensity, sharpness) in events.sortedBy { it.first }) {
            val wait = at - clock
            if (wait > 0) delay((wait * 1000).toLong())
            clock = at
            HapticMotor.transient(intensity, sharpness)
        }
    }

    /** ◇2 · the rain: two dozen small dry drops on an irregular grid, thick in the middle. */
    private fun rain(): List<Triple<Double, Float, Float>> {
        var seed: ULong = 0x9E3779B97F4A7C15UL
        fun rnd(): Double {
            seed = seed * 6364136223846793005UL + 1442695040888963407UL
            return ((seed shr 33) % 1000UL).toDouble() / 1000
        }
        val out = mutableListOf<Triple<Double, Float, Float>>()
        var t = 0.42
        while (t < 1.62) {
            val peak = max(0.0, 1 - abs(t - 1.02) / 0.62)
            val intensity = (0.12 + 0.24 * peak + rnd() * 0.10).toFloat()
            val sharpness = (0.72 + rnd() * 0.25).toFloat()
            out += Triple(t, intensity, sharpness)
            // 44 ms at the height of it, 86 ms at the edges, and never twice the same.
            t += 0.058 - 0.028 * peak + rnd() * 0.028
        }
        return out
    }

    @Suppress("unused")
    private fun fallback() { Haptics.impact(ImpactStyle.Soft, 0.7f); Haptics.impact(ImpactStyle.Rigid) }
}
