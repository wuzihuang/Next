package com.nextbody.hoop.features.vitals

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.ui.Haptics
import kotlinx.coroutines.CancellationException

/** Copy for the 探点 readout. Time on the left, the sample (or `——`) on the right. */
object VitalsProbeCopy {
    fun line(time: String, value: String): String = L("%@ · %@", time, value)

    fun gap(time: String): String = line(time, Fmt.dash)

    /** One envelope's readout. A slot that reduced a single tick prints as the one value it
     *  is rather than as `62–62`. */
    fun range(time: String, low: String, high: String, unit: String): String =
        ranges(time, listOf(low to high), unit)

    /** Occupied runs in one slot. Two clusters print as `48–52 · 88–90 BPM`, never as the
     *  hollow `48–90` that would fill the hole between them. */
    fun ranges(time: String, spans: List<Pair<String, String>>, unit: String): String {
        val body = spans.joinToString(" · ") { if (it.first == it.second) it.first else L("%@–%@", it.first, it.second) }
        return line(time, if (unit.isEmpty()) body else L("%@ %@", body, unit))
    }
}

/**
 * The shared 探点 shell: readout above the field, 标线 on top of it, and a recognizer that
 * axis-locks against the page scroll. Charts draw the series; this owns the touch.
 *
 * A horizontal drag past the 10dp dead zone owns the touch (and the page stops scrolling,
 * because the probe consumes every move from then on); a vertical one gives up so the page
 * scrolls. Lift returns the readout to the last recorded sample.
 */
@Composable
fun VitalsChartProbe(
    series: VitalsProbeMath.Series,
    tint: Color,
    height: Dp = 160.dp,
    gapFraction: Double = 0.0,
    leadingInset: Dp = 0.dp,
    /** The scale rail's width plus its gap. The field stops where the rail begins. */
    trailingInset: Dp = 0.dp,
    clockAt: (Double) -> String = { Fmt.dash },
    accessibilityTitle: String = L("CHART"),
    accessibilityName: String = "vitals.probe",
    content: @Composable (probing: Boolean) -> Unit,
) {
    var pick by remember { mutableStateOf<VitalsProbeMath.Pick?>(null) }
    var lastIdentity by remember { mutableStateOf<String?>(null) }
    val probing = pick != null
    val currentSeries by rememberUpdatedState(series)
    val currentGap by rememberUpdatedState(gapFraction)

    val gapCopy = VitalsProbeCopy.gap(clockAt(pick?.marker ?: 1.0))
    val readout = VitalsProbeMath.readout(pick, series.idleText, gapCopy)

    fun apply(fraction: Double) {
        val next = currentSeries.pick(fraction, currentGap)
        if (next.snaps && next.identity != lastIdentity) Haptics.selection()
        lastIdentity = next.identity
        pick = next
    }

    fun clear() {
        pick = null
        lastIdentity = null
    }

    fun step(increment: Boolean): Boolean {
        val next = VitalsProbeMath.voStep(currentSeries.voItems, pick?.identity, increment) ?: return false
        pick = next
        lastIdentity = next.identity
        return true
    }

    val density = LocalDensity.current
    val leadingPx = with(density) { leadingInset.toPx() }
    val trailingPx = with(density) { trailingInset.toPx() }

    Column(
        Modifier
            .fillMaxWidth()
            .testTag(accessibilityName)
            .semantics {
                contentDescription = accessibilityTitle
                stateDescription = readout
                customActions = listOf(
                    CustomAccessibilityAction(L("NEXT")) { step(true) },
                    CustomAccessibilityAction(L("PREVIOUS")) { step(false) },
                )
            },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FitText(
            readout, NBFont.dot(600, 11f).tracking(0.06f),
            if (probing) tint else NB.white.copy(alpha = 0.72f), minScale = 0.75f,
        )

        Box(
            Modifier
                .fillMaxWidth()
                .height(height)
                .pointerInput(series.isEmpty, leadingPx, trailingPx) {
                    if (series.isEmpty) return@pointerInput
                    val slopPx = VitalsProbeMath.slop * density.density
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val origin = down.position
                        var began = false
                        fun fraction(x: Float): Double = VitalsProbeMath.fingerFraction(
                            x.toDouble(), size.width.toDouble(), leadingPx.toDouble(), trailingPx.toDouble())
                        try {
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                if (!began && event.changes.count { it.pressed } > 1) break
                                if (!change.pressed) break
                                val f = fraction(change.position.x)
                                if (!began) {
                                    if (change.isConsumed) break
                                    val dx = (change.position.x - origin.x).toDouble()
                                    val dy = (change.position.y - origin.y).toDouble()
                                    when (VitalsProbeMath.axisLock(dx, dy, slopPx)) {
                                        VitalsProbeMath.AxisLock.undecided -> continue
                                        VitalsProbeMath.AxisLock.vertical -> break
                                        VitalsProbeMath.AxisLock.horizontal -> {
                                            began = true
                                            change.consume()
                                            apply(f)
                                        }
                                    }
                                } else {
                                    change.consume()
                                    apply(f)
                                }
                            }
                        } catch (e: CancellationException) {
                            if (began) clear()
                            throw e
                        }
                        if (began) clear()
                    }
                },
        ) {
            content(probing)
            val current = pick
            if (current != null) {
                Canvas(Modifier.fillMaxSize()) {
                    val field = size.width - leadingPx - trailingPx
                    val x = leadingPx + field * current.marker.toFloat()
                    drawLine(
                        tint.copy(alpha = tint.alpha * 0.85f), Offset(x, 0f), Offset(x, size.height),
                        strokeWidth = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())),
                    )
                    val yFraction = current.yFraction
                    if (current.snaps && yFraction != null && current.text != null) {
                        drawCircle(tint, 4.dp.toPx(), Offset(x, size.height * yFraction.toFloat()))
                    }
                }
            }
        }
    }
}
