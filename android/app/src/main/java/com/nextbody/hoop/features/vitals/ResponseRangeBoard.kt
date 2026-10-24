package com.nextbody.hoop.features.vitals

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.MealResponseIndex
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.currentZone
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

// RESPONSE's three rolling windows. Day is this user day; week and month are the last 7 and
// 30 user days. Not a calendar week or month (ADR 0012).
//
// ⚠️ Sleep still medians a night. This board means a week: the hero is the arithmetic mean of
// the daily means. The own daytime median stays the comparison, not the hero.

val RollingPills.responseHeroSensor: String
    get() = when (this) {
        RollingPills.day -> L("RESPONSE · TODAY")
        RollingPills.week -> L("RESPONSE · LAST 7D")
        RollingPills.month -> L("RESPONSE · LAST 30D")
    }

val RollingPills.responseChartTitle: String
    get() = when (this) {
        RollingPills.day -> L("FOOD RESPONSE")
        RollingPills.week, RollingPills.month -> L("DAILY VS OWN")
    }

val RollingPills.responseAverageLabel: String
    get() = when (this) {
        RollingPills.day -> L("24H MEDIAN POINT")
        RollingPills.week -> L("7-DAY AVERAGE")
        RollingPills.month -> L("30-DAY AVERAGE")
    }

private fun dayOfMonth(start: Instant): String = start.atZone(currentZone()).dayOfMonth.toString()

// MARK: - week / month bars

/**
 * One bar a user day, height by that day's mean optical point, colour by Below / Near / Above
 * versus the own daytime median. A day with no point is a dotted slot at full height.
 */
object ResponseDayBars {
    @Composable
    fun Legend() {
        VitalsChartLegend(
            items = listOf(
                VitalsChartLegend.Item(L("BELOW"), NB.ember1),
                VitalsChartLegend.Item(L("NEAR"), NB.compareAmber),
                VitalsChartLegend.Item(L("ABOVE"), NB.optimal2),
            ),
            trailing = L("DOTTED · NO RECORD"),
            trailingTint = NB.white.copy(alpha = 0.45f),
        )
    }

    fun tint(mean: Double, ownMedian: Double?, fallback: Color): Color =
        when (MealResponseIndex.Band.of(mean, ownMedian ?: 0.0)) {
            MealResponseIndex.Band.below -> NB.ember1
            MealResponseIndex.Band.near -> NB.compareAmber
            MealResponseIndex.Band.above -> NB.optimal2
            null -> fallback
        }

    internal fun fraction(value: Double, axis: ClosedFloatingPointRange<Double>): Double {
        val span = axis.endInclusive - axis.start
        if (span <= 0) return 0.0
        return min(1.0, max(0.08, (value - axis.start) / span))
    }
}

@Composable
fun ResponseDayBars(
    slots: List<MealResponseIndex.DaySlot>,
    ownMedian: Double?,
    tint: Color = NB.compareAmber,
    height: Dp = 160.dp,
) {
    val axis = MealResponseIndex.axis(slots.mapNotNull { it.mean }, ownMedian) ?: (80.0..120.0)
    val high = axis.endInclusive
    val mid = ownMedian ?: ((high + axis.start) / 2)
    val railLabels = listOf(high, mid, axis.start).map { MealResponseIndex.pointValue(it) }
    val ranges = VitalsProbeMath.equalSlots(slots.size)
    val probeBins = slots.zip(ranges).map { (slot, range) ->
        val clock = if (slots.size > 10) dayOfMonth(slot.start) else Fmt.weekday(slot.start)
        val mean = slot.mean
        if (mean != null) {
            VitalsProbeMath.Bin(range.start, range.end, 1 - ResponseDayBars.fraction(mean, axis),
                VitalsProbeCopy.line(clock, MealResponseIndex.pointValue(mean)))
        } else {
            VitalsProbeMath.Bin(range.start, range.end, null, VitalsProbeCopy.gap(clock), vacant = true)
        }
    }

    VitalsChartProbe(
        series = VitalsProbeMath.Series.Bins(probeBins),
        tint = tint,
        height = height,
        trailingInset = VitalsScaleRail.gutter,
        accessibilityTitle = L("DAILY VS OWN"),
        accessibilityName = "vitals.probe.response.days",
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
                    val mean = slot.mean
                    if (mean == null) {
                        dottedSlot(x, 0f, width, size.height, radius)
                    } else {
                        val h = max(radius * 2, size.height * ResponseDayBars.fraction(mean, axis).toFloat())
                        drawRoundRect(ResponseDayBars.tint(mean, ownMedian, tint), Offset(x, size.height - h),
                            Size(width, h), CornerRadius(radius, radius))
                    }
                }
            }
            VitalsScaleRail(railLabels, tint)
        }
    }
}

// MARK: - month heat

/**
 * Thirty user days as a 5 × 6 grid, oldest at the top-left, filling down a column then
 * across. Colour is the day's band versus the own median; an empty day is a dotted cell.
 *
 * 探点 stays a horizontal drag (CONTEXT · 探点), so the finger names a column — the five days
 * that share that x — rather than inventing a second axis on this card.
 */
object ResponseDayHeat {
    internal const val columns = 6
    internal const val rows = 5

    @Composable
    fun Legend() = ResponseDayBars.Legend()
}

@Composable
fun ResponseDayHeat(
    slots: List<MealResponseIndex.DaySlot>,
    ownMedian: Double?,
    tint: Color = NB.compareAmber,
    height: Dp = 160.dp,
) {
    val columns = ResponseDayHeat.columns
    val rows = ResponseDayHeat.rows
    val ranges = VitalsProbeMath.equalSlots(columns)
    val probeBins = (0 until columns).map { col ->
        val days = (0 until rows).mapNotNull { row -> slots.getOrNull(col * rows + row) }
        val filled = days.mapNotNull { it.mean }
        val clock = days.firstOrNull()?.let { dayOfMonth(it.start) } ?: Fmt.dash
        val mean = MealResponseIndex.mean(filled)
        if (mean != null) {
            VitalsProbeMath.Bin(ranges[col].start, ranges[col].end, 0.5,
                VitalsProbeCopy.line(clock, MealResponseIndex.pointValue(mean)))
        } else {
            VitalsProbeMath.Bin(ranges[col].start, ranges[col].end, null, VitalsProbeCopy.gap(clock), vacant = true)
        }
    }
    val columnLabels = (0 until columns).map { col -> slots.getOrNull(col * rows)?.let { dayOfMonth(it.start) } ?: "" }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        VitalsChartProbe(
            series = VitalsProbeMath.Series.Bins(probeBins),
            tint = tint,
            height = height,
            accessibilityTitle = L("DAILY VS OWN"),
            accessibilityName = "vitals.probe.response.heat",
        ) { probing ->
            Canvas(Modifier.fillMaxSize()) {
                val u = density
                val gap = 4 * u
                val cellW = max(8 * u, (size.width - gap * (columns - 1)) / columns)
                val cellH = max(8 * u, (size.height - gap * (rows - 1)) / rows)
                val r = 3 * u
                val alpha = if (probing) 0.85f else 1f
                for (col in 0 until columns) for (row in 0 until rows) {
                    val x = col * (cellW + gap)
                    val y = row * (cellH + gap)
                    val mean = slots.getOrNull(col * rows + row)?.mean
                    if (mean == null) {
                        drawRoundRect(NB.hairline, Offset(x, y), Size(cellW, cellH), CornerRadius(r, r), alpha = alpha,
                            style = androidx.compose.ui.graphics.drawscope.Stroke(u,
                                pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(2 * u, 3 * u))))
                    } else {
                        drawRoundRect(ResponseDayBars.tint(mean, ownMedian, tint), Offset(x, y), Size(cellW, cellH),
                            CornerRadius(r, r), alpha = alpha)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            columnLabels.forEach { label ->
                FitText(label, NBFont.ui(400, 9f), NB.white.copy(alpha = 0.45f), Modifier.weight(1f))
            }
        }
    }
}
