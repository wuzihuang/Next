package com.nextbody.hoop.features.training

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.TrainingBand
import com.nextbody.hoop.band.TrainingCurvePoint
import com.nextbody.hoop.band.TrainingDayFacts
import com.nextbody.hoop.band.TrainingWindowMath
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.vitals.MetricWindowMath
import com.nextbody.hoop.features.vitals.VitalsChartLegend
import com.nextbody.hoop.features.vitals.VitalsChartProbe
import com.nextbody.hoop.features.vitals.VitalsProbeCopy
import com.nextbody.hoop.features.vitals.VitalsProbeMath
import com.nextbody.hoop.features.vitals.VitalsScaleRail
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.LoadPoint
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.SwiftEaseOut
import com.nextbody.hoop.ui.rememberReduceMotion
import java.time.Instant
import java.time.ZoneId
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** SwiftUI `.lineSpacing(n)` on a font of [size]: the line box grows by n. */
internal fun lineHeightFor(size: Float, spacing: Float) =
    androidx.compose.ui.unit.TextUnit(size * 1.2f + spacing, androidx.compose.ui.unit.TextUnitType.Sp)

/** Swift `RingArc`: a trim of the circle from `from` to `to` (0 = twelve o'clock, clockwise). */
private fun DrawScope.ringArc(from: Double, to: Double, diameter: Float, color: Color, width: Float) {
    if (to <= from) return
    val c = center
    drawArc(
        color,
        startAngle = (360 * from - 90).toFloat(),
        sweepAngle = (360 * (to - from)).toFloat(),
        useCenter = false,
        topLeft = Offset(c.x - diameter / 2, c.y - diameter / 2),
        size = Size(diameter, diameter),
        style = Stroke(width, cap = StrokeCap.Round),
    )
}

/**
 * The 200pt version of the ring. Same ruler, same three lanes. Lime is the
 * page colour; over the cap turns ember. The shape never changes.
 */
@Composable
fun BigTrainingRing(
    load: Double?,
    target: Double?,
    zone: ClosedFloatingPointRange<Double>?,
    modifier: Modifier = Modifier,
    tint: Color = NB.lime1,
    heroTint: Color? = null,
    over: Boolean = false,
    caption: String = "OF 21",
) {
    val reduceMotion = rememberReduceMotion()
    val shown = remember { Animatable(0f) }
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(load) {
        val v = (load ?: 0.0).toFloat()
        if (reduceMotion) shown.snapTo(v)
        else shown.animateTo(v, tween(if (appeared) 600 else 900, easing = SwiftEaseOut))
        appeared = true
    }
    val label = L("%@ %@ out of 21", MetricNames.trainingLoad, Fmt.load(load))
    Box(
        modifier.size(200.dp).clearAndSetSemantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val d = density
            // track: strokeBorder 14 inside a 186 frame → centre line at 172
            drawCircle(NB.ringTrack, radius = 86 * d, style = Stroke(14 * d))
            ringArc(0.0, shown.value / TrainingWindowMath.fullRing, 172 * d, tint, 14 * d)
            if (over) {
                drawCircle(
                    NB.ember1.copy(alpha = 0.6f), radius = 100 * d,
                    style = Stroke(1.5f * d, pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * d, 6 * d))),
                )
            }
            if (zone != null) {
                ringArc(zone.start / TrainingWindowMath.fullRing, zone.endInclusive / TrainingWindowMath.fullRing,
                    194 * d, NB.lime2, 5 * d)
            }
            if (target != null) {
                val a = Math.toRadians(360 * target / TrainingWindowMath.fullRing - 90)
                drawCircle(NB.limePale, radius = 4.5f * d,
                    center = Offset(center.x + 97 * d * cos(a).toFloat(), center.y + 97 * d * sin(a).toFloat()))
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                Fmt.load(load), style = NBFont.dot(700, 46f).tracking(-0.02f),
                color = if (load == null) NB.text3Prod else (heroTint ?: tint), maxLines = 1,
            )
            Text(L(caption), style = NBFont.ui(500, 11f).tracking(0.22f), color = NB.text3Prod, maxLines = 1)
        }
    }
}

/**
 * One day's load on the 0–21 ruler. WEEK and MONTH use this instead of the
 * ring: a missing day is a hole, not a zero and not a dashed callout.
 */
@Composable
fun TrainingDayLine(
    values: List<Double?>,
    average: Double?,
    modifier: Modifier = Modifier,
    todayIndex: Int? = null,
    heavyIndex: Int? = null,
) {
    Canvas(modifier.fillMaxWidth()) {
        if (values.isEmpty()) return@Canvas
        val d = density
        val ceiling = 21.0
        val pad = 8 * d
        val plot = max(0f, size.height - pad * 2)
        val slot = size.width / values.size
        fun y(value: Double): Float = size.height - pad - (min(ceiling, max(0.0, value)) / ceiling).toFloat() * plot
        fun point(index: Int, value: Double) = Offset((index + 0.5f) * slot, y(value))

        for (rule in listOf(7.0, 14.0)) {
            drawRect(NB.white.copy(alpha = 0.06f), Offset(0f, y(rule)), Size(size.width, 1 * d))
        }
        drawRect(NB.white.copy(alpha = 0.10f), Offset(0f, size.height - 1 * d), Size(size.width, 1 * d))

        val runs = TrainingWindowMath.lineRuns(values).map { run -> run.map { point(it.index, it.value) } }
        if (runs.isEmpty()) return@Canvas

        for (run in runs) {
            if (run.size <= 1) continue
            val area = Path().apply {
                moveTo(run[0].x, size.height)
                for (p in run) lineTo(p.x, p.y)
                lineTo(run.last().x, size.height)
                close()
            }
            val crest = run.minOf { it.y }
            drawPath(area, Brush.verticalGradient(
                listOf(NB.lime1.copy(alpha = 0.18f), NB.lime1.copy(alpha = 0f)), startY = crest, endY = size.height))
        }
        for (run in runs) {
            if (run.size <= 1) continue
            val line = Path().apply {
                moveTo(run[0].x, run[0].y)
                for (p in run.drop(1)) lineTo(p.x, p.y)
            }
            drawPath(line, NB.lime1, style = Stroke(2 * d, cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
        if (average != null) {
            drawLine(NB.limePale.copy(alpha = 0.4f), Offset(0f, y(average)), Offset(size.width, y(average)),
                strokeWidth = 1 * d, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3 * d, 4 * d)))
        }
        val r = (if (values.size > 14) 1.8f else 2.6f) * d
        for ((index, value) in values.withIndex()) {
            if (value == null) continue
            val p = point(index, value)
            val heavy = index == heavyIndex && index != todayIndex
            drawCircle(if (heavy) NB.ember1 else NB.lime1.copy(alpha = 0.9f), r, p)
        }
        if (todayIndex != null && todayIndex in values.indices) {
            val value = values[todayIndex]
            if (value != null) {
                val p = point(todayIndex, value)
                drawCircle(NB.lime1.copy(alpha = 0.45f), 6 * d, p, style = Stroke(1 * d))
                drawCircle(NB.lime1, 3.4f * d, p)
            }
        }
    }
}

/**
 * Recorded cumulative values on the actual user-day clock. Missing intervals
 * interrupt the line; a target is a horizontal reference, never a prediction.
 */
@Composable
fun CumulativeCurve(
    target: Double?,
    modifier: Modifier = Modifier,
    zone: ClosedFloatingPointRange<Double>? = null,
    points: List<LoadPoint> = emptyList(),
    day: UserDay = UserDay.containing(Instant.now()),
    through: Instant = Instant.now(),
) {
    val data = remember(points, day, through) {
        TrainingWindowMath.curveData(points.map { TrainingCurvePoint(it.ts, it.load) }, day, through)
    }
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val hDp = maxHeight
        fun yDp(load: Double): Dp = hDp - 12.dp - (hDp - 24.dp) * (load / 21).toFloat()

        Canvas(Modifier.fillMaxSize()) {
            val d = this.density
            val w = size.width
            val h = size.height
            fun y(load: Double): Float = h - 12 * d - (load / 21).toFloat() * (h - 24 * d)
            fun pt(p: TrainingCurvePoint) = Offset(w * TrainingWindowMath.dayFraction(p.ts, day).toFloat(), y(p.load))

            if (zone != null) {
                drawRect(NB.lime1.copy(alpha = 0.12f), Offset(0f, y(zone.endInclusive)),
                    Size(w, max(0f, y(zone.start) - y(zone.endInclusive))))
            }
            if (target != null) {
                drawLine(NB.limePale.copy(alpha = 0.45f), Offset(0f, y(target)), Offset(w, y(target)),
                    strokeWidth = 1 * d, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3 * d, 4 * d)))
            }
            drawLine(NB.white.copy(alpha = 0.10f), Offset(0f, h - 12 * d), Offset(w, h - 12 * d), strokeWidth = 1 * d)

            for (segment in data.segments) {
                val first = segment.firstOrNull() ?: continue
                val last = segment.last()
                val area = Path().apply {
                    val p0 = pt(first); moveTo(p0.x, p0.y)
                    for (p in segment.drop(1)) { val q = pt(p); lineTo(q.x, q.y) }
                    lineTo(pt(last).x, h - 12 * d)
                    lineTo(p0.x, h - 12 * d)
                    close()
                }
                drawPath(area, Brush.verticalGradient(listOf(NB.lime1.copy(alpha = 0.28f), NB.lime1.copy(alpha = 0f)), 0f, h))
                val line = Path().apply {
                    val p0 = pt(first); moveTo(p0.x, p0.y)
                    for (p in segment.drop(1)) { val q = pt(p); lineTo(q.x, q.y) }
                }
                drawPath(line, NB.lime1, style = Stroke(2 * d, cap = StrokeCap.Round, join = StrokeJoin.Round))
                if (segment.size == 1) drawCircle(NB.lime1, 2 * d, pt(first))
            }
            data.segments.lastOrNull()?.lastOrNull()?.let { last ->
                val p = pt(last)
                drawCircle(NB.carbon2, 4 * d, p)
                drawCircle(NB.lime1, 4 * d, p, style = Stroke(2.5f * d))
            }
        }
        if (target != null) {
            Text(
                L("TARGET %@", swiftFormat("%.1f", target)),
                style = NBFont.dot(700, 11f).tracking(0.02f), color = NB.limePale, maxLines = 1,
                modifier = Modifier.offset(x = 4.dp, y = max(0f, (yDp(target) - 18.dp).value).dp),
            )
        }
        if (data.segments.lastOrNull()?.lastOrNull() == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(L("NO LOAD SAMPLES"), style = NBFont.ui(500, 11f), color = NB.text3Prod)
            }
        }
    }
}

@Composable
fun ZoneBar(zone: String, fill: Double, tint: Color, value: String, modifier: Modifier = Modifier) {
    val reduceMotion = rememberReduceMotion()
    val grown = remember { Animatable(0f) }
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(fill) {
        if (reduceMotion) grown.snapTo(fill.toFloat())
        else grown.animateTo(fill.toFloat(), tween(if (appeared) 400 else 700, easing = SwiftEaseOut))
        appeared = true
    }
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(zone, style = NBFont.dot(700, 11f), color = NB.macroLabel, maxLines = 1, modifier = Modifier.width(24.dp))
        Box(Modifier.weight(1f).height(12.dp).background(hex(0x1A1A20), CircleShape)) {
            Box(Modifier.fillMaxHeight().fillMaxWidth(grown.value.coerceIn(0f, 1f)).background(tint, CircleShape))
        }
        Text(
            value, style = NBFont.dot(700, 11f).tracking(0.02f), color = tint, maxLines = 1,
            textAlign = TextAlign.End, modifier = Modifier.width(44.dp),
        )
    }
}

/** One stacked column a day: Z1–3 lime under Z4–5 ember. */
@Composable
fun TrainingZoneStack(days: List<TrainingDayFacts>, modifier: Modifier = Modifier) {
    val scale = TrainingWindowMath.zoneScaleMinutes(days)
    Row(
        modifier.fillMaxWidth().height(104.dp),
        horizontalArrangement = Arrangement.spacedBy(9.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        for (day in days) {
            val easy = (day.easyMinutes ?: 0).toDouble()
            val hard = (day.hardMinutes ?: 0).toDouble()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.Bottom) {
                if (hard > 0) {
                    val b = if (easy > 0) 0.dp else 5.dp
                    Box(Modifier.fillMaxWidth().height((104 * hard / scale).dp)
                        .background(NB.ember1, RoundedCornerShape(5.dp, 5.dp, b, b)))
                }
                if (easy > 0) {
                    val t = if (hard > 0) 0.dp else 5.dp
                    Box(Modifier.fillMaxWidth().height((104 * easy / scale).dp)
                        .background(NB.lime1.copy(alpha = 0.53f), RoundedCornerShape(t, t, 5.dp, 5.dp)))
                }
                if (easy == 0.0 && hard == 0.0) {
                    Box(Modifier.fillMaxWidth().height(8.dp).background(NB.white.copy(alpha = 0.06f), RoundedCornerShape(5.dp)))
                }
            }
        }
    }
}

/**
 * Hourly step columns on the user-day clock. The tallest hour that also has
 * a named session is marked amber.
 */
@Composable
fun TrainingStepBars(bins: List<Double>, modifier: Modifier = Modifier, sessionIndex: Int? = null) {
    Canvas(modifier.fillMaxWidth()) {
        val d = density
        val peak = max(1.0, bins.maxOrNull() ?: 1.0)
        val gap = 4 * d
        val n = max(1, bins.size)
        val w = max(4 * d, (size.width - gap * max(0, bins.size - 1)) / n)
        val total = w * bins.size + gap * max(0, bins.size - 1)
        var x = (size.width - total) / 2
        for ((i, value) in bins.withIndex()) {
            val color = when {
                i == sessionIndex -> NB.ember1
                value > 0 -> NB.lime1.copy(alpha = (0.35 + 0.65 * (value / peak)).toFloat())
                else -> NB.white.copy(alpha = 0.08f)
            }
            val h = max(2 * d, (size.height * value / peak).toFloat())
            drawRoundRect(color, Offset(x, size.height - h), Size(w, h), CornerRadius(3 * d, 3 * d))
            x += w + gap
        }
    }
}

/**
 * WEEK and MONTH lead with this instead of a number: one column a user day for the load
 * that day reached, against the target that day was set. The target is a tick across the
 * column and the optimal zone a faint band behind it. A finished day's column wears its
 * band's colour — light, steady, heavy — and today's is drawn hollow, still counting.
 *
 * ⚠️ A day with no load is a dotted slot, never a zero column (F2 rule 05).
 */
@Composable
fun TrainingTargetBars(days: List<TrainingDayFacts>, modifier: Modifier = Modifier, height: Dp = 150.dp) {
    val ceiling = 21.0
    fun fraction(value: Double): Float = (min(ceiling, max(0.0, value)) / ceiling).toFloat()
    fun tint(day: TrainingDayFacts, load: Double): Color = when (TrainingWindowMath.band(load, day.zone)) {
        TrainingBand.light -> NB.lime1.copy(alpha = 0.45f)
        TrainingBand.steady -> NB.lime1
        TrainingBand.heavy, TrainingBand.over -> NB.ember1
        TrainingBand.unknown -> NB.lime1.copy(alpha = 0.7f)
    }
    val probeBins = run {
        val ranges = VitalsProbeMath.equalSlots(days.size)
        days.zip(ranges).map { (day, range) ->
            val clock = MetricWindowMath.slotLabel(day.day.start, days.size)
            val load = day.load
            if (load == null) VitalsProbeMath.Bin(range.start, range.end, null, VitalsProbeCopy.gap(clock), vacant = true)
            else {
                val target = day.target?.let { L("TARGET %@", Fmt.load(it)) } ?: L("NO TARGET")
                VitalsProbeMath.Bin(range.start, range.end, (1 - fraction(load)).toDouble(),
                    VitalsProbeCopy.line(clock, L("%@ · %@", Fmt.load(load), target)))
            }
        }
    }
    Box(modifier) {
        VitalsChartProbe(
            series = VitalsProbeMath.Series.Bins(probeBins), tint = NB.lime1, height = height,
            trailingInset = VitalsScaleRail.gutter,
            accessibilityTitle = L("LOAD VS TARGET BY DAY"),
            accessibilityName = "training.probe.targetBars",
        ) { _ ->
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(VitalsScaleRail.gap)) {
                Canvas(Modifier.weight(1f).fillMaxHeight()) {
                    val d = density
                    val count = max(days.size, 1)
                    val spacing = (if (days.size > 10) 2f else 6f) * d
                    val width = max(2 * d, (size.width - spacing * (count - 1)) / count)
                    val radius = min(width / 2, 6 * d)
                    val h = size.height
                    for ((i, day) in days.withIndex()) {
                        val x = i * (width + spacing)
                        val zone = day.zone
                        if (zone != null) {
                            val zh = max(2 * d, h * (fraction(zone.endInclusive) - fraction(zone.start)))
                            drawRoundRect(NB.lime2.copy(alpha = 0.16f), Offset(x, h - h * fraction(zone.start) - zh),
                                Size(width, zh), CornerRadius(2 * d, 2 * d))
                        }
                        val load = day.load
                        if (load == null) {
                            drawRoundRect(NB.hairline, Offset(x, 0f), Size(width, h), CornerRadius(radius, radius),
                                style = Stroke(1 * d, pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * d, 3 * d))))
                        } else if (day.isOpen) {
                            // Today is still counting: hollow, so it is not read as a finished day.
                            val bh = max(radius * 2, h * fraction(load))
                            val rr = CornerRadius(radius, radius)
                            drawRoundRect(NB.lime1.copy(alpha = 0.18f), Offset(x, h - bh), Size(width, bh), rr)
                            drawRoundRect(NB.lime1, Offset(x, h - bh), Size(width, bh), rr, style = Stroke(1.5f * d))
                        } else {
                            val bh = max(2 * d, h * fraction(load))
                            drawRoundRect(tint(day, load), Offset(x, h - bh), Size(width, bh), CornerRadius(radius, radius))
                        }
                        val target = day.target
                        if (target != null) {
                            // The target as a tick across the whole slot.
                            drawRect(NB.limePale, Offset(x, h - h * fraction(target) - 2 * d), Size(width, 2 * d))
                        }
                    }
                }
                VitalsScaleRail(listOf("21", "14", "7", "0"), NB.lime1)
            }
        }
    }
}

@Composable
fun TrainingTargetBarsLegend() {
    VitalsChartLegend(
        items = listOf(
            VitalsChartLegend.Item(L("LOAD · PER DAY"), NB.lime1),
            VitalsChartLegend.Item(L("TARGET"), NB.limePale),
            VitalsChartLegend.Item(L("ZONE"), NB.lime2, isArea = true),
        ),
        trailing = L("DOTTED · NO RECORD"),
        trailingTint = NB.white.copy(alpha = 0.45f),
    )
}

