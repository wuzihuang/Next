package com.nextbody.hoop.features.measure

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PointMode
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.atan
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 06 · THE FIELD. Dave Whyte's breathing dots, after Matt Rossman's react-three-fiber version.
 *
 * A hexagonally offset grid is pushed away from and pulled back toward the centre by a
 * ROUNDED SQUARE WAVE — `atan(sin(x)/delta)` — which sits at its extremes for most of the
 * cycle and snaps between them. Each dot's phase lags by its distance from the centre, and
 * that distance carries an octagonal offset (`cos(8θ)`), so the travelling ring reads as a
 * rotated square rather than a circle.
 *
 * ⚠️ THE PULSE IS THE MEASUREMENT. `bpm` is the rate the band is reporting right now, and it
 * drives the wave directly: one breath per heartbeat. When the band stops reporting, the field
 * holds a resting tempo and dims rather than inventing a rhythm.
 *
 * The field is drawn three times in one pass, each copy trailing by a delay in SECONDS and
 * masked to one colour channel, blended additively: where all three land the channels sum back
 * to the dot colour, where only the leading copy has arrived you get the pure fringe.
 */
@Composable
fun BreathingDots(
    bpm: Int?,
    modifier: Modifier = Modifier,
    /** 0…1 · how far into the measurement. Drives brightness and travel. */
    intensity: Double = 1.0,
    tint: Color = NB.lime1,
    /** Contact lost: the field freezes where it is and turns amber. */
    held: Boolean = false,
) {
    val reduceMotion = rememberReduceMotion()
    // ⚠️ The phase is ACCUMULATED, never computed from the clock: `now × rate` jumps every
    // time a reported beat changes the rate. Accumulating dt × rate bends the tempo instead.
    val clock = remember { BreathingPhase() }
    var frameNanos by remember { mutableLongStateOf(0L) }
    val paused = reduceMotion || held
    LaunchedEffect(paused) {
        if (paused) return@LaunchedEffect
        while (true) withFrameNanos { frameNanos = it }
    }

    Canvas(modifier.clearAndSetSemantics { }) {
        val now = if (paused) clock.lastNanos else frameNanos
        val unit = size.height / BreathingDotsSpec.rows.toFloat()
        if (unit <= 0.5f) return@Canvas
        val cols = ceil(size.width / unit).toInt() + 2
        val rows = ceil(BreathingDotsSpec.rows).toInt() + 2
        val cx = size.width / 2
        val cy = size.height / 2

        // One breath per heartbeat, and the rate the band last reported is what sets it.
        val rate = (bpm ?: BreathingDotsSpec.restingBPM.toInt()).toDouble() / 60
        var dt = if (clock.lastNanos == 0L || now == 0L) 0.0 else (now - clock.lastNanos) / 1e9
        if (now != 0L) clock.lastNanos = now
        // A backgrounded screen must not fast-forward the breath when it comes back.
        if (!dt.isFinite() || dt < 0) dt = 0.0
        if (dt > 0.05) dt = 0.05
        clock.cycles = (clock.cycles + dt * rate) % 1.0
        val t = clock.cycles
        val amp = BreathingDotsSpec.amplitude * (0.45 + 0.55 * min(1.0, max(0.0, intensity)))
        val radius = unit * 0.22f

        val base = if (held) NB.ember2 else tint
        val alpha = (0.35 + 0.65 * min(1.0, max(0.0, intensity))).toFloat()
        val masks = arrayOf(
            Color(base.red, 0f, 0f, alpha),
            Color(0f, base.green, 0f, alpha),
            Color(0f, 0f, base.blue, alpha),
        )

        for (lane in 0 until 3) {
            val points = ArrayList<Offset>(rows * cols)
            val laneShift = lane * BreathingDotsSpec.chromaDelay * rate
            for (row in 0 until rows) {
                for (col in 0 until cols) {
                    // Centred on the origin: the wave scales every dot about (0,0).
                    val x = col.toDouble() - (cols - 1).toDouble() / 2
                    // Every other column nudged half a row down — the hexagonal packing.
                    val y = row.toDouble() - (rows - 1).toDouble() / 2 + ((col % 2).toDouble() - 0.5) * 0.5
                    val len = sqrt(x * x + y * y)
                    // Unsigned angle from +X; the mirroring is what closes the octagon.
                    val dirX = if (len > 1e-5) x / len else 1.0
                    val dist = len + cos(acos(min(1.0, max(-1.0, dirX))) * 8) * 0.5
                    // How square the wave is: grows with distance so the outer ranks ease.
                    val delta = 0.15 + 0.2 * dist / 72
                    val phase = t - laneShift - dist * BreathingDotsSpec.lag * rate
                    val wave = (2 * amp / PI) * atan(sin(2 * PI * phase) / delta)
                    val scale = wave + 1.3
                    val px = (cx + x * scale * unit).toFloat()
                    val py = (cy + y * scale * unit).toFloat()
                    // Everything off the frame is skipped before it reaches the batch.
                    if (px <= -radius || px >= size.width + radius ||
                        py <= -radius || py >= size.height + radius) continue
                    points.add(Offset(px, py))
                }
            }
            // Additive, so the three copies sum back to the dot colour where they overlap.
            drawPoints(points, PointMode.Points, masks[lane], strokeWidth = radius * 2,
                cap = StrokeCap.Round, blendMode = BlendMode.Plus)
        }
    }
}

private class BreathingPhase {
    var cycles = 0.0
    var lastNanos = 0L
}

private object BreathingDotsSpec {
    /** Rows of dots across the frame's height. ⚠️ Sized for the WHOLE SCREEN. */
    const val rows = 52.0
    /** Fraction of its own offset each dot travels at full intensity. */
    const val amplitude = 0.44
    /** Seconds of phase lag per unit of distance from the centre — one ring in the air. */
    const val lag = 0.022
    /** Seconds between the three channel copies: the edge-only fringe on lime. */
    const val chromaDelay = 0.007
    const val restingBPM = 54.0
}
