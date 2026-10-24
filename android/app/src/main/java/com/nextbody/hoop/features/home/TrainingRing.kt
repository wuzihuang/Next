package com.nextbody.hoop.features.home

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.ui.SwiftEaseOut
import kotlin.math.cos
import kotlin.math.sin

/**
 * 04 · 03 训练环 The Ring.
 * An absolute 0–21 gauge, never a percentage: the ruler does not change shape from day to day.
 * Inner ring 80×80 · inner stroke 7.5 at r27 · outer zone stroke 4 at r35.5 · target dot r3.25,
 * all three concentric. The zone arc and the target dot only appear once the day has a
 * Body Battery result; the rest of the time the outer lane stays empty.
 */
object TrainingRingSpec {
    const val fullRing: Double = 21.0
}

@Composable
fun TrainingRing(
    load: Double?,                                 // TRAINING_LOAD 0–21
    target: Double?,                               // TARGET_LOAD
    zone: ClosedFloatingPointRange<Double>?,       // OPTIMAL_ZONE
    modifier: Modifier = Modifier,
    size: Dp = 80.dp,
    animate: Boolean = true,
) {
    val s = size.value / 80f
    val shown = remember { Animatable(0f) }
    val first = remember { booleanArrayOf(true) }
    LaunchedEffect(load) {
        if (first[0]) {
            first[0] = false
            val l = load ?: return@LaunchedEffect
            if (animate) shown.animateTo(l.toFloat(), tween(900, easing = SwiftEaseOut)) else shown.snapTo(l.toFloat())
        } else {
            shown.animateTo((load ?: 0.0).toFloat(), tween(600, easing = SwiftEaseOut))
        }
    }
    val label = L("%@ %@ out of 21", MetricNames.trainingLoad, Fmt.load(load))   // F5 §09
    Box(
        modifier.size(size).clearAndSetSemantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val u = s * density
            // Full ring · the ruler itself (r27 centre-line)
            drawCircle(NB.ringTrack, radius = 27f * u, style = Stroke(7.5f * u))
            // Training now
            drawRingArc(0.0, shown.value / TrainingRingSpec.fullRing, 54f * u, NB.lime1, 7.5f * u)
            // Optimal zone, on the outer lane
            if (zone != null) {
                drawRingArc(zone.start / TrainingRingSpec.fullRing, zone.endInclusive / TrainingRingSpec.fullRing,
                    71f * u, NB.lime2, 4f * u)
            }
            // Target — a point, not an arc
            if (target != null) {
                val a = Math.toRadians(360 * target / TrainingRingSpec.fullRing - 90)
                drawCircle(NB.limePale, radius = 3.25f * u,
                    center = center + Offset((35.5f * u * cos(a)).toFloat(), (35.5f * u * sin(a)).toFloat()))
            }
        }
        Text(
            Fmt.load(load),
            style = NBFont.dot(700, 16f * s).tracking(-0.02f),
            color = NB.lime1,
            maxLines = 1,
            softWrap = false,
        )
    }
}

/** A clockwise arc measured from 12 o'clock, in ring fractions. */
object RingArc {
    fun path(from: Double, to: Double, rect: Rect): Path {
        val p = Path()
        if (to <= from) return p
        val r = minOf(rect.width, rect.height) / 2
        val box = Rect(rect.center.x - r, rect.center.y - r, rect.center.x + r, rect.center.y + r)
        p.arcTo(box, (360 * from - 90).toFloat(), (360 * (to - from)).toFloat(), forceMoveTo = true)
        return p
    }
}

/** Strokes a [RingArc] of [diameter] px, centred on [center]. */
fun DrawScope.drawRingArc(
    from: Double,
    to: Double,
    diameter: Float,
    color: Color,
    strokeWidth: Float,
    center: Offset = this.center,
    cap: StrokeCap = StrokeCap.Round,
) {
    if (to <= from) return
    drawArc(
        color = color,
        startAngle = (360 * from - 90).toFloat(),
        sweepAngle = (360 * (to - from)).toFloat(),
        useCenter = false,
        topLeft = Offset(center.x - diameter / 2, center.y - diameter / 2),
        size = Size(diameter, diameter),
        style = Stroke(strokeWidth, cap = cap),
    )
}
