package com.nextbody.hoop.features.vitals

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.MealResponseIndex
import com.nextbody.hoop.band.SleepStageRun
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.band.VitalsTimelinePolicy
import com.nextbody.hoop.band.VitalsTimelineRange
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.roundedInt
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import java.time.Instant
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// 04 · 8 大指标二级页 · the five chart shapes the eight pages are drawn from. Every one of
// them takes the band's own ticks and nothing else: there is no smoothing pass, no
// interpolation across a gap, and no rescaling of the ruler to flatter a quiet day.
//
// The ruler is fixed and named on the card (「FIXED 40–160 BPM」) for the same reason 08's
// curve names its own: a chart that rescales itself makes every day look identical.

/** A timestamped value — Swift's `(ts: Date, value: Double)`. */
data class TimedValue(val ts: Instant, val value: Double)

/** The exact window a chart is drawn across, plus the clock printed under it. */
data class VitalsWindow(
    val start: Instant,
    val span: Double,
    val labels: List<String>,
    /** True when the last label is NOW rather than a clock reading. */
    val endsNow: Boolean,
    /** How many user days this window was built from. nil on a clock window. */
    val dayCount: Int? = null,
    /** The last user day of a multi-day window, so TODAY is that day and not the wall clock. */
    val endingDay: UserDay? = null,
) {
    val range: VitalsTimelineRange get() = VitalsTimelineRange(start, start.addingTimeInterval(span))

    fun fraction(ts: Instant): Double {
        if (span <= 0) return 0.0
        return min(1.0, max(0.0, ts.timeIntervalSince(start) / span))
    }

    fun contains(ts: Instant): Boolean = span > 0 && ts >= start && ts.timeIntervalSince(start) <= span

    fun clock(atFraction: Double): String {
        if (span <= 0) return Fmt.dash
        val dayCount = dayCount
        if (dayCount != null) {
            val slot = HeartWindowMath.slotIndex(atFraction, dayCount)
            val mark = start.addingTimeInterval(slot * HeartWindowMath.slotSeconds(span, dayCount))
            if (endingDay != null && UserDay.containing(mark) == endingDay) return L("TODAY")
            return if (dayCount <= 7) Fmt.weekday(mark)
            else Fmt.displayDate(mark, "d MMM").uppercase(Locale.ROOT)
        }
        if (endsNow && atFraction >= 0.999) return L("NOW")
        return Fmt.clock(start.addingTimeInterval(span * atFraction))
    }

    companion object {
        fun userDay(day: UserDay, now: Instant): VitalsWindow {
            val range = VitalsTimelinePolicy.userDay(day.start, day.end, now)
            return make(range, endsNow = now >= day.start && now < day.end)
        }

        /** Last `count` user days ending on `day`, one equal slot a day. The span is the real
         *  calendar width (DST included) so a 23-hour day does not invent an eighth bar. */
        fun rollingUserDays(count: Int, endingOn: UserDay, @Suppress("UNUSED_PARAMETER") now: Instant): VitalsWindow {
            val slots = UserDay.last(max(1, count), endingOn)
            val days = slots.size
            val first = slots[0]
            val start = first.start
            val end = endingOn.end
            val span = max(0.0, end.timeIntervalSince(start))
            val labels = (0..4).map { index ->
                val slot = HeartWindowMath.slotIndex(index / 4.0, days)
                val mark = first.adding(slot)
                when {
                    mark == endingOn -> L("TODAY")
                    days <= 7 -> Fmt.weekday(mark.start)
                    index == 0 -> Fmt.displayDate(mark.start, "d MMM").uppercase(Locale.ROOT)
                    else -> Fmt.displayDate(mark.start, "d")
                }
            }
            return VitalsWindow(start, span, labels, endsNow = true, dayCount = days, endingDay = endingOn)
        }

        /** Only a recorded sleep interval can supply a night clock or admit overnight points. */
        fun night(start: Instant?, end: Instant?, fallback: UserDay): VitalsWindow {
            if (start == null || end == null || end <= start) {
                return VitalsWindow(fallback.start, 0.0, emptyList(), endsNow = false)
            }
            return make(VitalsTimelineRange(start, end), endsNow = false)
        }

        private fun make(range: VitalsTimelineRange, endsNow: Boolean): VitalsWindow {
            val marks = (0..4).map { range.start.addingTimeInterval(range.span * it / 4) }
            val labels = marks.map { Fmt.clock(it) }.toMutableList()
            if (endsNow && labels.isNotEmpty()) labels[labels.size - 1] = L("NOW")
            return VitalsWindow(range.start, range.span, labels, endsNow)
        }
    }
}

private fun f0(v: Double): String = swiftFormat("%.0f", v)

private fun DrawScope.hLine(y: Float, color: Color, width: Float = density) {
    drawLine(color, Offset(0f, y), Offset(size.width, y), strokeWidth = width)
}

private fun DrawScope.fillStops(stops: GradientStops, rect: Rect, radius: Float, alpha: Float) {
    drawRoundRect(
        Brush.verticalGradient(*stops.toTypedArray(), startY = rect.top, endY = rect.bottom),
        topLeft = rect.topLeft, size = rect.size, cornerRadius = CornerRadius(radius, radius), alpha = alpha,
    )
}

/**
 * The 24-hour trace: heart, autonomic load, skin temperature. A fixed vertical ruler that
 * stands beside the field, an optional reference band behind the marks, and occupancy runs
 * inside each quarter hour — only the value bands that have ticks.
 *
 * ⚠️ An envelope is not a min–max fill, not a smoothing pass, and not an average. A hole
 * such as 70–75 with no sample stays empty; a quarter hour the band did not report draws
 * nothing at all. 08 rule 07 · a gap is never interpolated still holds on both axes.
 *
 * ⚠️ Nothing is printed inside the field. The ruler lives in `VitalsScaleRail`, the band's
 * name and the extreme in `VitalsChartLegend` under the clock.
 */
object VitalsTrace {
    /** How wide one envelope is. A quarter hour over a full day is 96 columns. */
    const val defaultSlotMinutes: Double = 15.0
}

@Composable
fun VitalsTrace(
    samples: List<VitalSample>,
    value: (VitalSample) -> Double?,
    window: VitalsWindow,
    low: Double,
    high: Double,
    tint: Color,
    /** The hero dial's own ruler. Given one, every capsule is coloured by the zone it sits in. */
    zones: VitalsDial.Model? = null,
    /** The physiological band drawn behind the marks — 60–80 resting, ±0.3 °C, and so on. */
    referenceBand: ClosedFloatingPointRange<Double>? = null,
    /** The stretch of the window the band belongs to. nil spans the whole chart. */
    referenceSpan: ClosedRange<Instant>? = null,
    /** True to pick out the highest envelope, false the lowest. */
    marksMaximum: Boolean = true,
    height: Dp = 160.dp,
    /** Additional measured series share the same chart without impersonating another vital. */
    measuredPoints: List<TimedValue>? = null,
    slotMinutes: Double = VitalsTrace.defaultSlotMinutes,
    /** A value without its unit: `72`, `36.4`. Drives the rail and both ends of the readout. */
    valueFormat: (Double) -> String = ::f0,
    /** What the readout calls the numbers. Empty for a bare score. */
    unit: String = "",
) {
    val railLabels = listOf(high, (high + low) / 2, low).map(valueFormat)
    val slotSeconds = slotMinutes * 60
    val raw = measuredPoints ?: samples.mapNotNull { s -> value(s)?.let { TimedValue(s.ts, it) } }
    val windowPoints = raw.mapNotNull { s ->
        if (!window.contains(s.ts) || !s.value.isFinite()) null else window.fraction(s.ts) to s.value
    }
    val envelopes = VitalsProbeMath.envelopes(windowPoints, slotSeconds, window.span,
        VitalsProbeMath.occupancyGap(low, high))
    // Which occupied run holds the window's extreme, so the field can pick it out without
    // printing a number over it. Identity is the mark itself.
    val extremeMark = if (envelopes.size > 2) {
        if (marksMaximum) envelopes.maxByOrNull { it.high } else envelopes.minByOrNull { it.low }
    } else null

    // Every slot the window has room for, filled or not. A quarter hour the band skipped is
    // still a slot the finger can land on — it just reads `——`.
    val grouped = envelopes.groupBy { it.index }
    val probeBins = VitalsProbeMath.timeSlots(slotSeconds, window.span).map { slot ->
        val clock = window.clock((slot.start + slot.end) / 2)
        val marks = grouped[slot.index]
        if (marks.isNullOrEmpty()) {
            VitalsProbeMath.Bin(slot.start, slot.end, null, VitalsProbeCopy.gap(clock), vacant = true)
        } else {
            val ordered = marks.sortedBy { it.low }
            val top = ordered.maxOf { it.high }
            VitalsProbeMath.Bin(
                slot.start, slot.end,
                // The dot lands on the top of the highest occupied run.
                VitalsProbeMath.yFraction(top, low, high),
                VitalsProbeCopy.ranges(clock, ordered.map { valueFormat(it.low) to valueFormat(it.high) }, unit),
                vacant = false,
            )
        }
    }

    VitalsChartProbe(
        series = VitalsProbeMath.Series.Bins(probeBins),
        tint = tint,
        height = height,
        trailingInset = VitalsScaleRail.gutter,
        clockAt = window::clock,
    ) { probing ->
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(VitalsScaleRail.gap)) {
            Canvas(Modifier.weight(1f).fillMaxHeight()) {
                val u = density
                val span = max(0.001, high - low)
                fun y(v: Double): Float {
                    val clamped = min(high, max(low, v))
                    return (size.height - u - (clamped - low) / span * (size.height - 2 * u)).toFloat()
                }
                // One gridline, at the value the rail's middle mark names.
                hLine(y((high + low) / 2), NB.white.copy(alpha = 0.05f))
                hLine(size.height - 0.5f * u, NB.white.copy(alpha = 0.10f))

                if (referenceBand != null) {
                    val top = y(referenceBand.endInclusive)
                    val bottom = y(referenceBand.start)
                    val edges = referenceSpan?.let {
                        (size.width * window.fraction(it.start)).toFloat() to (size.width * window.fraction(it.endInclusive)).toFloat()
                    } ?: (0f to size.width)
                    val left = max(0f, min(edges.first, edges.second))
                    val right = min(size.width, max(edges.first, edges.second))
                    // A night that has scrolled out of the window bands nothing at all.
                    if (right > left) {
                        // ⚠️ Kept deliberately faint: the band is background; the marks are the reading.
                        drawRect(tint.copy(alpha = tint.alpha * 0.055f), Offset(left, top),
                            Size(right - left, max(u, bottom - top)))
                    }
                }

                if (envelopes.isEmpty()) return@Canvas
                for (mark in envelopes) {
                    val top = y(mark.high)
                    val bottom = y(mark.low)
                    val bar = VitalsProbeMath.slotBar(mark.start, mark.end, size.width.toDouble() / u)
                    val barWidth = (bar.width * u).toFloat()
                    val radius = (VitalsProbeMath.slotBarRadius(bar.width) * u).toFloat()
                    // A slot that reduced one tick draws as a round mark of the capsule's head.
                    val barHeight = max(radius * 2, bottom - top)
                    val centre = (top + bottom) / 2
                    val originY = min(max(0f, centre - barHeight / 2), size.height - barHeight)
                    val rect = Rect(Offset((bar.x * u).toFloat(), originY), Size(barWidth, barHeight))
                    val isPeak = !probing && extremeMark == mark
                    // ⚠️ The clamped ends, not the raw ones: a capsule pinned to the top of the
                    // ruler is coloured by the stretch it actually shows.
                    val stops = zones?.stops(max(low, mark.low), min(high, mark.high))
                    if (stops != null) {
                        fillStops(stops, rect, radius, if (isPeak) 1f else 0.78f)
                    } else {
                        drawRoundRect(tint.copy(alpha = tint.alpha * if (isPeak) 1f else 0.72f),
                            rect.topLeft, rect.size, CornerRadius(radius, radius))
                    }
                }
            }
            VitalsScaleRail(railLabels, tint)
        }
    }
}

/**
 * A slow vital drawn as the line it is: overnight SpO2, sleep respiration. One reading every
 * few minutes has nothing to envelope.
 *
 * ⚠️ 08 rule 07 · a gap is never interpolated. Readings further apart than `maxGapMinutes`
 * are two runs, not one line; the hole is spanned by a faint dash, never a measurement.
 */
object VitalsLineTrace {
    /** Past this many visible readings the per-sample dots come off. */
    internal const val dotLimit = 56

    /** The readings this window holds, in the order the night filed them. */
    fun visible(points: List<TimedValue>, window: VitalsWindow): List<TimedValue> =
        points.filter { window.contains(it.ts) && it.value.isFinite() }.sortedBy { it.ts }

    /** Uninterrupted stretches of readings — a longer hole starts a new one. */
    fun runs(points: List<TimedValue>, window: VitalsWindow, maxGapMinutes: Double = 20.0): List<List<TimedValue>> {
        val out = mutableListOf<List<TimedValue>>()
        var run = mutableListOf<TimedValue>()
        for (sample in visible(points, window)) {
            val last = run.lastOrNull()
            if (last != null && sample.ts.timeIntervalSince(last.ts) > maxGapMinutes * 60) {
                out.add(run)
                run = mutableListOf()
            }
            run.add(sample)
        }
        if (run.isNotEmpty()) out.add(run)
        return out
    }
}

@Composable
fun VitalsLineTrace(
    points: List<TimedValue>,
    window: VitalsWindow,
    low: Double,
    high: Double,
    tint: Color,
    /** True picks out the night's high, false its low. Oxygen's news is its floor. */
    marksMaximum: Boolean = true,
    referenceBand: ClosedFloatingPointRange<Double>? = null,
    height: Dp = 160.dp,
    maxGapMinutes: Double = 20.0,
    valueFormat: (Double) -> String = ::f0,
    unit: String = "",
) {
    val railLabels = listOf(high, (high + low) / 2, low).map(valueFormat)
    val visible = VitalsLineTrace.visible(points, window)
    val runs = VitalsLineTrace.runs(points, window, maxGapMinutes)
    val extreme = if (marksMaximum) visible.maxByOrNull { it.value } else visible.minByOrNull { it.value }
    val probePoints = visible.map { sample ->
        VitalsProbeMath.Point(
            window.fraction(sample.ts),
            VitalsProbeMath.yFraction(sample.value, low, high),
            VitalsProbeCopy.range(Fmt.clock(sample.ts), valueFormat(sample.value), valueFormat(sample.value), unit),
        )
    }

    VitalsChartProbe(
        series = VitalsProbeMath.Series.Points(probePoints),
        tint = tint,
        height = height,
        gapFraction = VitalsProbeMath.gapFraction(window.span),
        trailingInset = VitalsScaleRail.gutter,
        clockAt = window::clock,
    ) { probing ->
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(VitalsScaleRail.gap)) {
            Canvas(Modifier.weight(1f).fillMaxHeight()) {
                val u = density
                val span = max(0.001, high - low)
                fun y(v: Double): Float {
                    val clamped = min(high, max(low, v))
                    return (size.height - u - (clamped - low) / span * (size.height - 2 * u)).toFloat()
                }
                fun at(s: TimedValue): Offset = Offset((size.width * window.fraction(s.ts)).toFloat(), y(s.value))

                hLine(y((high + low) / 2), NB.white.copy(alpha = 0.05f))
                hLine(size.height - 0.5f * u, NB.white.copy(alpha = 0.10f))

                if (referenceBand != null) {
                    val top = y(referenceBand.endInclusive)
                    val bottom = y(referenceBand.start)
                    drawRect(tint.copy(alpha = tint.alpha * 0.055f), Offset(0f, top), Size(size.width, max(u, bottom - top)))
                }

                val plotted = runs.map { run -> run.map(::at) }
                if (plotted.isEmpty()) return@Canvas

                // The wash under the line, anchored to the run's own crest and stopping at the
                // run's own ends, so a hole in the night stays a hole in the fill.
                for (run in plotted) {
                    if (run.size <= 1) continue
                    val area = Path().apply {
                        moveTo(run[0].x, size.height)
                        run.forEach { lineTo(it.x, it.y) }
                        lineTo(run.last().x, size.height)
                        close()
                    }
                    val crest = run.minOf { it.y }
                    drawPath(area, Brush.verticalGradient(
                        listOf(tint.copy(alpha = tint.alpha * 0.16f), tint.copy(alpha = 0f)),
                        startY = crest, endY = size.height))
                }

                plotted.forEachIndexed { i, run ->
                    if (run.size > 1) {
                        val line = Path().apply {
                            moveTo(run[0].x, run[0].y)
                            run.drop(1).forEach { lineTo(it.x, it.y) }
                        }
                        drawPath(line, tint, style = Stroke(1.8f * u, cap = StrokeCap.Round, join = StrokeJoin.Round))
                    }
                    if (i + 1 < plotted.size) {
                        val tail = run.lastOrNull()
                        val head = plotted[i + 1].firstOrNull()
                        if (tail != null && head != null) {
                            drawLine(tint.copy(alpha = tint.alpha * 0.28f), tail, head, strokeWidth = 1.2f * u,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * u, 4 * u)))
                        }
                    }
                }

                val marks = plotted.flatten()
                // A run of one has no line at all, so its dot is the reading; a dense night
                // keeps only the line.
                if (marks.size <= VitalsLineTrace.dotLimit || plotted.any { it.size == 1 }) {
                    for (p in marks) drawCircle(tint.copy(alpha = tint.alpha * 0.90f), 1.8f * u, p)
                }

                if (!probing && marks.size > 2 && extreme != null) {
                    val p = at(extreme)
                    drawCircle(tint.copy(alpha = tint.alpha * 0.45f), 5f * u, p, style = Stroke(u))
                    drawCircle(tint, 2.5f * u, p)
                }
            }
            VitalsScaleRail(railLabels, tint)
        }
    }
}

/**
 * 02 · the night as four lanes — AWAKE · REM · LIGHT · DEEP — stepped in the order the band
 * filed it. The app never re-segments the line (04B rule 04).
 */
object VitalsHypnogram {
    /** SDK stages: 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake. Deepest at the bottom. */
    internal fun lane(stage: Int): Int = when (stage) {
        0 -> 3
        1 -> 2
        2 -> 1
        else -> 0
    }

    internal val laneNames = listOf("AWAKE", "REM", "LIGHT", "DEEP")

    /** The lane-label gutter plus its gap. The clock under the chart is inset by exactly this. */
    val labelGutter: Dp = 40.dp
}

@Composable
fun VitalsHypnogram(
    runs: List<SleepStageRun>,
    tint: Color,
    windowMinutes: Double? = null,
    height: Dp = 160.dp,
    probeClock: (Double) -> String = { Fmt.dash },
) {
    val hasOffsets = runs.all { it.offsetMinutes != null }
    val layoutTotal = if (hasOffsets) {
        max(windowMinutes ?: 0.0, (runs.maxOfOrNull { (it.offsetMinutes ?: 0) + it.minutes } ?: 0).toDouble())
    } else runs.sumOf { it.minutes }.toDouble()

    val probeRuns: List<VitalsProbeMath.Run> = run {
        val offsets = if (hasOffsets) runs.map { it.offsetMinutes ?: 0 } else null
        val spans = VitalsProbeMath.stageSpans(runs.map { it.minutes }, offsets, windowMinutes)
        if (spans.size != runs.size) emptyList()
        else runs.zip(spans).map { (run, span) ->
            val lane = VitalsHypnogram.lane(run.stage)
            val stage = L(VitalsHypnogram.laneNames[lane])
            val mid = (span.start + span.end) / 2
            VitalsProbeMath.Run(span.start, span.end, (lane + 0.5) / 4, VitalsProbeCopy.line(probeClock(mid), stage))
        }
    }

    VitalsChartProbe(
        series = VitalsProbeMath.Series.Runs(probeRuns),
        tint = tint,
        height = height,
        leadingInset = VitalsHypnogram.labelGutter,
        clockAt = probeClock,
    ) { _ ->
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Column(Modifier.width(34.dp).fillMaxHeight()) {
                VitalsHypnogram.laneNames.forEach { name ->
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.CenterStart) {
                        BasicText(L(name), style = NBFont.ui(400, 8f).tracking(0.08f).copy(color = NB.white.copy(alpha = 0.40f)),
                            maxLines = 1)
                    }
                }
            }
            Canvas(Modifier.weight(1f).fillMaxHeight()) {
                val u = density
                val total = layoutTotal
                if (total <= 0) return@Canvas
                val laneHeight = size.height / 4
                for (i in 0 until 4) hLine(laneHeight * (i + 0.5f), NB.white.copy(alpha = 0.05f))

                var x = 0f
                val path = Path()
                var previousY: Float? = null
                for (run in runs) {
                    val runX = if (hasOffsets) (size.width * (run.offsetMinutes ?: 0) / total).toFloat() else x
                    val w = (size.width * run.minutes / total).toFloat()
                    val followsPrevious = abs(runX - x) < 0.1f
                    x = runX
                    val y = laneHeight * (VitalsHypnogram.lane(run.stage) + 0.5f)
                    if (previousY != null && followsPrevious) path.lineTo(x, y) else path.moveTo(x, y)
                    path.lineTo(x + w, y)
                    previousY = y
                    x += w
                    // Deep sleep is the night's payload, so its runs carry a block behind the line.
                    if (run.stage == 0) {
                        drawRect(tint.copy(alpha = tint.alpha * 0.22f), Offset(x - w, y), Size(max(u, w), laneHeight * 0.5f))
                    }
                }
                drawPath(path, tint, style = Stroke(1.6f * u, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
        }
    }
}

/**
 * 03 · the night's RMSSD ticks as a scatter, inside the envelope the last fortnight of nights
 * drew. The envelope is the baseline's own spread — not a target band.
 */
@Composable
fun VitalsScatter(
    samples: List<VitalSample>,
    window: VitalsWindow,
    /** The 14-night envelope, when there are enough nights to have one (04B rule 06). */
    envelope: ClosedFloatingPointRange<Double>? = null,
    baseline: Double? = null,
    tint: Color,
    height: Dp = 160.dp,
) {
    val values = samples.mapNotNull { it.hrv }
    val scatterRange: Pair<Double, Double> = if (values.isEmpty()) 0.0 to 1.0 else {
        val lo = minOf(values.min(), envelope?.start ?: Double.POSITIVE_INFINITY, baseline ?: Double.POSITIVE_INFINITY) - 6
        val hi = maxOf(values.max(), envelope?.endInclusive ?: Double.NEGATIVE_INFINITY, baseline ?: Double.NEGATIVE_INFINITY) + 6
        lo to hi
    }
    val probePoints = samples.mapNotNull { sample ->
        val v = sample.hrv
        if (!window.contains(sample.ts) || v == null) null
        else VitalsProbeMath.Point(
            window.fraction(sample.ts),
            VitalsProbeMath.yFraction(v, scatterRange.first, scatterRange.second),
            VitalsProbeCopy.line(Fmt.clock(sample.ts), "${v.roundedInt()} MS"),
        )
    }
    VitalsChartProbe(
        series = VitalsProbeMath.Series.Points(probePoints),
        tint = tint,
        height = height,
        gapFraction = VitalsProbeMath.gapFraction(window.span),
        clockAt = window::clock,
    ) { _ ->
        Canvas(Modifier.fillMaxSize()) {
            val u = density
            if (values.isEmpty()) return@Canvas
            val (lo, hi) = scatterRange
            val span = max(1.0, hi - lo)
            fun y(v: Double): Float = (size.height - 2 * u - (min(hi, max(lo, v)) - lo) / span * (size.height - 4 * u)).toFloat()

            if (envelope != null) {
                val top = y(envelope.endInclusive)
                val bottom = y(envelope.start)
                drawRect(tint.copy(alpha = tint.alpha * 0.08f), Offset(0f, top), Size(size.width, max(u, bottom - top)))
            }
            if (baseline != null) {
                drawLine(NB.white.copy(alpha = 0.28f), Offset(0f, y(baseline)), Offset(size.width, y(baseline)),
                    strokeWidth = u, pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * u, 3 * u)))
            }
            val trend = Path()
            var started = false
            var previous: Instant? = null
            for (s in samples) {
                val v = s.hrv
                if (!window.contains(s.ts) || v == null) continue
                val p = Offset((size.width * window.fraction(s.ts)).toFloat(), y(v))
                val prev = previous
                if (prev != null && s.ts.timeIntervalSince(prev) <= 10 * 60) trend.lineTo(p.x, p.y) else trend.moveTo(p.x, p.y)
                previous = s.ts
                started = true
            }
            if (started) {
                drawPath(trend, tint.copy(alpha = tint.alpha * 0.45f),
                    style = Stroke(1.2f * u, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
            for (s in samples) {
                val v = s.hrv
                if (!window.contains(s.ts) || v == null) continue
                drawCircle(tint, 2 * u, Offset((size.width * window.fraction(s.ts)).toFloat(), y(v)))
            }
        }
    }
}

/** Rolling-24h meal-response index. Points only, compare-amber, a dashed own-median at 0.
 *  No polyline, no meal marks, no envelope, no MAX callout. */
@Composable
fun VitalsIndexScatter(
    points: List<MealResponseIndex.ScatterPoint>,
    window: VitalsWindow,
    tint: Color,
    height: Dp = 160.dp,
) {
    Canvas(Modifier.fillMaxWidth().height(height)) {
        val u = density
        val visible = points.filter { window.contains(it.ts) }
        if (visible.isEmpty()) return@Canvas
        val values = visible.map { it.percent }
        val lo = min(values.min().toDouble(), -8.0) - 6
        val hi = max(values.max().toDouble(), 8.0) + 6
        val span = max(1.0, hi - lo)
        fun y(v: Int): Float = (size.height - 2 * u - (min(hi, max(lo, v.toDouble())) - lo) / span * (size.height - 4 * u)).toFloat()
        drawLine(NB.white.copy(alpha = 0.28f), Offset(0f, y(0)), Offset(size.width, y(0)), strokeWidth = u,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * u, 3 * u)))
        for (point in visible) {
            drawCircle(tint, 2 * u, Offset((size.width * window.fraction(point.ts)).toFloat(), y(point.percent)))
        }
    }
}

/**
 * Rolling-24h wrist meal-response points. The vendor scale is opaque, so the chart names these
 * as points and scales only to the observed range. Gaps stay dashed.
 */
@Composable
fun VitalsResponseTrace(
    points: List<MealResponseIndex.Point>,
    window: VitalsWindow,
    tint: Color,
    height: Dp = 160.dp,
) {
    val visible = points.filter { window.contains(it.ts) && it.optical.isFinite() && it.optical > 0 }
    val minimum = visible.minOfOrNull { it.optical }
    val maximum = visible.maxOfOrNull { it.optical }
    val probePoints = if (minimum == null || maximum == null) emptyList() else {
        val padding = max(1.0, (maximum - minimum) * 0.12)
        visible.map { p ->
            VitalsProbeMath.Point(
                window.fraction(p.ts),
                VitalsProbeMath.yFraction(p.optical, minimum - padding, maximum + padding),
                VitalsProbeCopy.line(Fmt.clock(p.ts), MealResponseIndex.pointValue(p.optical)),
            )
        }
    }
    VitalsChartProbe(
        series = VitalsProbeMath.Series.Points(probePoints),
        tint = tint,
        height = height,
        gapFraction = VitalsProbeMath.gapFraction(window.span),
        clockAt = window::clock,
    ) { probing ->
        Canvas(Modifier.fillMaxSize()) {
            val u = density
            if (minimum == null || maximum == null) return@Canvas
            val padding = max(1.0, (maximum - minimum) * 0.12)
            val low = minimum - padding
            val high = maximum + padding
            val span = max(1.0, high - low)
            fun position(p: MealResponseIndex.Point): Offset = Offset(
                (size.width * window.fraction(p.ts)).toFloat(),
                (size.height - 2 * u - (p.optical - low) / span * (size.height - 4 * u)).toFloat(),
            )
            for (fraction in listOf(0.15f, 0.45f, 0.75f)) hLine(size.height * fraction, NB.white.copy(alpha = 0.05f))

            val runs = mutableListOf<List<MealResponseIndex.Point>>()
            var run = mutableListOf<MealResponseIndex.Point>()
            for (point in visible) {
                val previous = run.lastOrNull()
                if (previous != null && point.ts.timeIntervalSince(previous.ts) > 10 * 60) {
                    runs.add(run)
                    run = mutableListOf()
                }
                run.add(point)
            }
            if (run.isNotEmpty()) runs.add(run)

            runs.forEachIndexed { index, samples ->
                val line = Path()
                val first = position(samples[0])
                line.moveTo(first.x, first.y)
                samples.drop(1).forEach { val p = position(it); line.lineTo(p.x, p.y) }
                if (samples.size == 1) line.lineTo(first.x + 0.5f * u, first.y)
                drawPath(line, tint, style = Stroke(1.8f * u, cap = StrokeCap.Round, join = StrokeJoin.Round))
                if (index + 1 < runs.size) {
                    drawLine(tint.copy(alpha = tint.alpha * 0.28f), position(samples.last()), position(runs[index + 1][0]),
                        strokeWidth = 1.1f * u, pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * u, 3 * u)))
                }
            }
            for (sample in visible) drawCircle(tint, 2 * u, position(sample))
            val latest = visible.lastOrNull()
            if (!probing && latest != null) drawCircle(tint, 4 * u, position(latest))
        }
    }
}

/**
 * 06 · 08 · the day as 24 hourly columns, graded against the busiest hour. An hour with no
 * ticks is left empty rather than drawn as a zero — 04B rule 04.
 */
@Composable
fun VitalsHistogram(
    /** Hourly bins, nil where the band reported nothing. */
    bins: List<Double?>,
    window: VitalsWindow,
    tint: Color,
    /** The hero dial's ruler, as on `VitalsTrace`. nil for the hourly metrics with no zones. */
    zones: VitalsDial.Model? = null,
    /** How a column's total prints on the rail — `1,420`, `620`. */
    valueFormat: (Double) -> String = { Fmt.kcal(it) },
    height: Dp = 160.dp,
) {
    val peak = bins.filterNotNull().filter { it > 0 }.maxOrNull()
    val railLabels = (peak ?: 0.0).let { top -> listOf(top, top / 2, 0.0).map(valueFormat) }
    val top0 = peak ?: 0.0
    val probeBins = VitalsProbeMath.hourSlots(bins.size, window.span).map { slot ->
        val value = bins[slot.index]
        val clock = Fmt.clock(window.start.addingTimeInterval(slot.index * 3600.0))
        if (value != null && !VitalsProbeMath.isVacantHour(value) && top0 > 0) {
            VitalsProbeMath.Bin(slot.start, slot.end, 1 - value / top0, VitalsProbeCopy.line(clock, valueFormat(value)), false)
        } else {
            VitalsProbeMath.Bin(slot.start, slot.end, null, VitalsProbeCopy.gap(clock), true)
        }
    }
    VitalsChartProbe(
        series = VitalsProbeMath.Series.Bins(probeBins),
        tint = tint,
        height = height,
        trailingInset = VitalsScaleRail.gutter,
        clockAt = window::clock,
    ) { probing ->
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(VitalsScaleRail.gap)) {
            Canvas(Modifier.weight(1f).fillMaxHeight()) {
                val u = density
                val top = peak
                if (top == null || top <= 0 || window.span <= 0) return@Canvas
                val gap = 3 * u
                val field = size.height - 2 * u
                hLine(size.height - field / 2, NB.white.copy(alpha = 0.05f))
                hLine(size.height - 0.5f * u, NB.white.copy(alpha = 0.10f))
                bins.forEachIndexed { i, value ->
                    if (value == null || value <= 0) return@forEachIndexed
                    val ratio = value / top
                    val start = min(window.span, i * 3600.0)
                    val end = min(window.span, (i + 1) * 3600.0)
                    val x = (size.width * start / window.span).toFloat()
                    val endX = (size.width * end / window.span).toFloat()
                    // ⚠️ The hour that just started has no room of its own; it stays out of the
                    // field until it owns enough width to be a column. The probe reports it.
                    val hour = (size.width * 3600 / window.span).toFloat()
                    if (endX - x < hour * 0.4f) return@forEachIndexed
                    val width = max(2.5f * u, endX - x - gap)
                    // ⚠️ Capped at 6 so a few-hours-old day's wide columns stay columns.
                    val radius = min(width / 2, 6 * u)
                    val h = max(radius * 2, (field * ratio).toFloat())
                    val rect = Rect(Offset(x, size.height - h), Size(width, h))
                    val isPeak = !probing && value == top
                    // A column stands on the floor, so the run it covers is 0…its total.
                    val stops = zones?.stops(0.0, value)
                    if (stops != null) fillStops(stops, rect, radius, if (isPeak) 1f else 0.78f)
                    else drawRoundRect(tint.copy(alpha = tint.alpha * if (isPeak) 1f else 0.72f), rect.topLeft, rect.size,
                        CornerRadius(radius, radius))
                }
            }
            VitalsScaleRail(railLabels, tint)
        }
    }
}

/**
 * 07 · the day's displacement as a climb: each hour's metres added to the last, so the curve
 * only ever rises and its steepness is the hour that moved.
 */
@Composable
fun VitalsClimb(
    /** Hourly increments, nil where the band reported nothing. */
    bins: List<Double?>,
    window: VitalsWindow,
    tint: Color,
    /** How a running total prints on the rail — `6.42 KM`. */
    valueFormat: (Double) -> String = { VitalsReadout.distanceLabel(it) },
    height: Dp = 160.dp,
) {
    val totals = VitalsProbeMath.cumulativeTotals(bins)
    val total = totals.maxOrNull() ?: 0.0
    val railLabels = listOf(total, total / 2, 0.0).map(valueFormat)
    val probeBins = VitalsProbeMath.hourSlots(bins.size, window.span).map { slot ->
        val running = totals[slot.index]
        val elapsed = min(window.span, (slot.index + 1) * 3600.0)
        val clock = Fmt.clock(window.start.addingTimeInterval(elapsed))
        VitalsProbeMath.Bin(slot.start, slot.end, if (total > 0) 1 - running / total else null,
            VitalsProbeCopy.line(clock, valueFormat(running)))
    }
    VitalsChartProbe(
        series = VitalsProbeMath.Series.Bins(probeBins),
        tint = tint,
        height = height,
        trailingInset = VitalsScaleRail.gutter,
        clockAt = window::clock,
    ) { probing ->
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(VitalsScaleRail.gap)) {
            Canvas(Modifier.weight(1f).fillMaxHeight()) {
                val u = density
                if (window.span <= 0) return@Canvas
                var running = 0.0
                var any = false
                val cumulative = bins.mapIndexed { index, bin ->
                    if (bin != null && bin > 0) { running += bin; any = true }
                    val elapsed = min(window.span, (index + 1) * 3600.0)
                    (elapsed / window.span) to running
                }
                if (!any || running <= 0) return@Canvas
                val field = size.height - 2 * u
                fun point(i: Int): Offset = Offset(
                    (size.width * cumulative[i].first).toFloat(),
                    (size.height - u - cumulative[i].second / running * field).toFloat(),
                )
                hLine(size.height - u - field / 2, NB.white.copy(alpha = 0.05f))

                val area = Path().apply {
                    moveTo(0f, size.height - u)
                    cumulative.indices.forEach { val p = point(it); lineTo(p.x, p.y) }
                    lineTo(size.width, size.height - u)
                    close()
                }
                drawPath(area, Brush.verticalGradient(
                    listOf(tint.copy(alpha = tint.alpha * 0.22f), tint.copy(alpha = tint.alpha * 0.01f)),
                    startY = 0f, endY = size.height))
                val line = Path().apply {
                    moveTo(0f, size.height - u)
                    cumulative.indices.forEach { val p = point(it); lineTo(p.x, p.y) }
                }
                drawPath(line, tint, style = Stroke(1.8f * u, cap = StrokeCap.Round, join = StrokeJoin.Round))
                if (!probing) drawCircle(tint, 4 * u, point(cumulative.size - 1))
            }
            VitalsScaleRail(railLabels, tint)
        }
    }
}
