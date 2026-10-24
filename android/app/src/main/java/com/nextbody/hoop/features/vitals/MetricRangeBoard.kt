package com.nextbody.hoop.features.vitals

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.DetailSurface
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.currentZone
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

// The three rolling windows, reopened for the five instruments that still only had a day:
// STRESS · TEMP · STEPS · DIST · CALS. Same three words sleep (ADR 0008), response (ADR 0012)
// and heart (ADR 0013) already carry, and the same grain heart counts in — user days.
//
// ⚠️ Rolling last-N, never a calendar week or month. A natural week collapses to one bar
// every Monday, which reads as data loss on a page whose whole job is to show wear.

fun RollingPills.metricPeriodLabel(metric: VitalsMetric): String =
    if (this == RollingPills.day) metric.periodLabel else L(DetailWindow(DetailSurface.metric, this).periodKey)

fun RollingPills.metricHeroSensor(metric: VitalsMetric): String =
    if (this == RollingPills.day) metric.sensor
    else L("%@ · %@", metric.sensor, L(DetailWindow(DetailSurface.metric, this).periodKey))

/** What the chart card is headed on this window. The day heads stay exactly as they were;
 *  the rolling ones name the grain. */
fun RollingPills.metricChartTitle(metric: VitalsMetric): String {
    if (this == RollingPills.day) return metric.chartTitle
    return when (metric) {
        VitalsMetric.stress -> L("DAILY AUTONOMIC LOAD")
        VitalsMetric.temp -> L("DAILY SKIN TEMPERATURE")
        VitalsMetric.steps -> L("STEPS BY DAY")
        VitalsMetric.distance -> L("DISTANCE BY DAY")
        VitalsMetric.active -> L("BURN BY DAY")
        else -> metric.chartTitle
    }
}

// MARK: - which metrics carry the switcher, and how their window is drawn

/** The five instruments this board opened. HEART, SLEEP and RESPONSE own their own range
 *  types and their own boards. */
val VitalsMetric.hasMetricRange: Boolean
    get() = when (this) {
        VitalsMetric.stress, VitalsMetric.temp, VitalsMetric.steps, VitalsMetric.distance, VitalsMetric.active -> true
        VitalsMetric.heart, VitalsMetric.sleep, VitalsMetric.hrv, VitalsMetric.response -> false
    }

val VitalsMetric.detailSurface: DetailSurface
    get() = when (this) {
        VitalsMetric.sleep, VitalsMetric.hrv -> DetailSurface.sleep
        VitalsMetric.heart -> DetailSurface.heart
        VitalsMetric.response -> DetailSurface.response
        VitalsMetric.active -> DetailSurface.active
        VitalsMetric.stress, VitalsMetric.temp, VitalsMetric.steps, VitalsMetric.distance -> DetailSurface.metric
    }

val VitalsMetric.showsDetailPills: Boolean
    get() = this == VitalsMetric.sleep || this == VitalsMetric.response || this == VitalsMetric.heart || hasMetricRange

/** A trace metric's window is an envelope a day; an accumulated metric's is one bar a day. */
val VitalsMetric.windowIsAccumulated: Boolean
    get() = when (this) {
        VitalsMetric.steps, VitalsMetric.distance, VitalsMetric.active -> true
        else -> false
    }

// MARK: - one bar a user day

/**
 * The rolling window for the three accumulated instruments. One bar a user day, scaled to the
 * busiest day in the window, with the window's own median drawn across it. A day the band
 * filed nothing for is a dotted slot at full height (F2 rule 05).
 *
 * ⚠️ A day that was worn and did not move is a real zero: it keeps its slot, not a gap.
 */
object MetricDayBars {
    data class Slot(val start: Instant, val total: Double?)

    @Composable
    fun Legend(tint: Color, median: Double?, format: (Double) -> String) {
        VitalsChartLegend(
            items = listOf(VitalsChartLegend.Item(L("PER DAY"), tint)) +
                (median?.let { listOf(VitalsChartLegend.Item(L("MEDIAN %@", format(it)), tint, isArea = true)) } ?: emptyList()),
            trailing = L("DOTTED · NO RECORD"),
            trailingTint = NB.white.copy(alpha = 0.45f),
        )
    }
}

@Composable
fun MetricDayBars(
    slots: List<MetricDayBars.Slot>,
    tint: Color,
    /** The window's median recorded day, drawn as a dashed line. nil until three days. */
    median: Double? = null,
    format: (Double) -> String,
    height: Dp = 160.dp,
) {
    // The rail is scaled to the busiest day, so its top mark is that day and its floor a real zero.
    val peak = slots.mapNotNull { it.total }.maxOrNull() ?: 0.0
    fun fraction(value: Double): Double = if (peak <= 0) 0.0 else min(1.0, max(0.0, value / peak))
    val railLabels = listOf(peak, peak / 2, 0.0).map(format)
    val ranges = VitalsProbeMath.equalSlots(slots.size)
    val probeBins = slots.zip(ranges).map { (slot, range) ->
        val clock = MetricWindowMath.slotLabel(slot.start, slots.size)
        val total = slot.total
        if (total == null) VitalsProbeMath.Bin(range.start, range.end, null, VitalsProbeCopy.gap(clock), vacant = true)
        else VitalsProbeMath.Bin(range.start, range.end, 1 - fraction(total), VitalsProbeCopy.line(clock, format(total)))
    }

    VitalsChartProbe(
        series = VitalsProbeMath.Series.Bins(probeBins),
        tint = tint,
        height = height,
        trailingInset = VitalsScaleRail.gutter,
        accessibilityTitle = L("BY DAY"),
        accessibilityName = "vitals.probe.metric.days",
    ) { _ ->
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(VitalsScaleRail.gap)) {
            Canvas(Modifier.weight(1f).fillMaxHeight()) {
                val u = density
                val count = max(slots.size, 1)
                val spacing = (if (slots.size > 10) 2f else 6f) * u
                val width = max(2 * u, (size.width - spacing * (count - 1)) / count)
                val radius = min(width / 2, 6 * u)
                slots.forEachIndexed { i, slot ->
                    val x = i * (width + spacing)
                    val total = slot.total
                    if (total == null) {
                        dottedSlot(x, 0f, width, size.height, radius)
                    } else if (total > 0) {
                        val h = max(2 * u, size.height * fraction(total).toFloat())
                        drawRoundRect(tint, Offset(x, size.height - h), Size(width, h), CornerRadius(radius, radius))
                    }
                }
                if (median != null && peak > 0) {
                    // The habit line, not a target: it is this window's own middle day.
                    val y = size.height * (1 - fraction(median)).toFloat()
                    drawLine(tint.copy(alpha = tint.alpha * 0.55f), Offset(0f, y), Offset(size.width, y), strokeWidth = u,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(3 * u, 3 * u)))
                }
            }
            VitalsScaleRail(railLabels, tint)
        }
    }
}

// MARK: - the window's arithmetic

/**
 * What the five rolling boards reduce before anything is laid out. The medians and the
 * worn-day count come from `HeartWindowMath`, which already settled that vocabulary.
 */
object MetricWindowMath {
    /** A weekday inside a week, a day-of-month across a month. */
    fun slotLabel(start: Instant, count: Int): String =
        if (count > 10) start.atZone(currentZone()).dayOfMonth.toString() else Fmt.weekday(start)

    /** One bucket a user day, in window order. A day the band filed nothing for stays an empty
     *  list — never a zero, which is a reading the band never took. */
    fun dailyBuckets(ticks: List<VitalSample>, endingOn: UserDay, days: Int,
                     value: (VitalSample) -> Double?): List<List<Double>> {
        val first = endingOn.adding(-(days - 1))
        return (0 until days).map { offset ->
            val bucket = first.adding(offset)
            ticks.mapNotNull { sample ->
                if (sample.ts >= bucket.start && sample.ts < bucket.end) value(sample) else null
            }
        }
    }

    fun slots(days: List<DailyMetrics>, total: (DailyMetrics) -> Double?): List<MetricDayBars.Slot> =
        days.map { MetricDayBars.Slot(it.day.start, total(it)) }

    fun recorded(slots: List<MetricDayBars.Slot>): List<Double> = slots.mapNotNull { it.total }

    /** The window's own total, which is only a number when at least one day recorded one. */
    fun sum(slots: List<MetricDayBars.Slot>): Double? {
        val values = recorded(slots)
        return if (values.isEmpty()) null else values.sum()
    }

    /** The best day in the window and when it was, for the tile that names it. */
    fun best(slots: List<MetricDayBars.Slot>): MetricDayBars.Slot? =
        slots.filter { it.total != null }.maxByOrNull { it.total ?: 0.0 }
}
