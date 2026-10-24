package com.nextbody.hoop.features.vitals

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import java.time.Instant
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * The week and month hero: one mark a user day, the window's own line under it. It stands
 * where the day page's big number and dial stand, because a rolling window has no single
 * reading — it has a shape. The number is still printed, once, in the summary row under the
 * field, so a week stays comparable with a day; it is no longer the headline.
 *
 * ⚠️ A day the band filed nothing for is a dotted slot (bars) or a floor mark (line) — never
 * a zero and never left out (F2 rule 05).
 */
object MetricTrendHero {
    enum class Style { line, bars }

    data class Point(val start: Instant, val value: Double?)

    /** A dashed rule across the field with its name: the window's own median, a baseline. */
    data class Rule(val value: Double, val label: String)

    /** A washed band across the field: this person's own night range. */
    data class Band(val range: ClosedFloatingPointRange<Double>, val label: String)

    data class Summary(
        /** The one number, already formatted: "MEDIAN 58". */
        val headline: String,
        val unit: String?,
        /** "+2 VS PRIOR 7D", or nil when either window is too thin to compare. */
        val delta: String?,
        /** "6 OF 7 DAYS". */
        val worn: String,
    )

    /** One slice of the month strip. */
    data class Roll(val id: Int, val label: String, val value: Double?)

    internal val height = 150.dp

    /** Uninterrupted stretches of days that recorded. An empty slot ends a run. */
    fun runs(values: List<Double?>): List<List<Pair<Int, Double>>> {
        val out = mutableListOf<List<Pair<Int, Double>>>()
        var run = mutableListOf<Pair<Int, Double>>()
        values.forEachIndexed { i, value ->
            if (value != null) {
                run.add(i to value)
            } else if (run.isNotEmpty()) {
                out.add(run)
                run = mutableListOf()
            }
        }
        if (run.isNotEmpty()) out.add(run)
        return out
    }
}

private fun DrawScope.dashedRule(y: Float, color: Color) {
    val u = density
    drawLine(color, Offset(0f, y), Offset(size.width, y), strokeWidth = u,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf(3 * u, 3 * u)))
}

/** A bar column with its dotted "no record" outline — shared by the day-bar charts. */
internal fun DrawScope.dottedSlot(x: Float, top: Float, w: Float, h: Float, radius: Float) {
    val u = density
    drawRoundRect(
        NB.hairline, Offset(x, top), Size(w, h), CornerRadius(radius, radius),
        style = Stroke(u, pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * u, 3 * u))),
    )
}

@Composable
fun MetricTrendHero(
    caption: String,
    points: List<MetricTrendHero.Point>,
    style: MetricTrendHero.Style,
    scale: ClosedFloatingPointRange<Double>,
    tint: Color,
    /** Given a ruler with cuts, a mark wears the colour of the zone its value sits in. */
    zones: VitalsDial.Model? = null,
    rule: MetricTrendHero.Rule? = null,
    band: MetricTrendHero.Band? = null,
    format: (Double) -> String,
    unit: String = "",
    /** What one mark is: "RESTING · PER NIGHT", "TOTAL · PER DAY". */
    seriesLabel: String,
    summary: MetricTrendHero.Summary,
    rolls: List<MetricTrendHero.Roll> = emptyList(),
    /** What the strip averaged: days on most pages, nights on SLEEP and TEMP. */
    rollCaption: String = L("AVERAGE OF RECORDED DAYS"),
    emptyLine: String,
    emptySub: String,
    accessibilityName: String = "vitals.probe.trend",
) {
    val recorded = points.count { it.value != null }
    val hasGap = recorded < points.size
    val isMonth = points.size > 10
    fun fraction(value: Double): Double = MetricTrendMath.fraction(value, scale)
    fun markTint(value: Double): Color = zones?.tint(value) ?: tint

    val access = buildList {
        add(summary.headline)
        summary.unit?.let { add(it) }
        summary.delta?.let { add(it) }
        add(summary.worn)
    }.joinToString(", ")

    Column(
        Modifier
            .width(com.nextbody.hoop.design.NB.Layout.contentWidth)
            .padding(bottom = 4.dp)
            .testTag("vitals.hero")
            .semantics { contentDescription = caption; stateDescription = access },
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        FitText(caption, NBFont.ui(400, 10f).tracking(0.12f), NB.white.copy(alpha = 0.45f), minScale = 0.8f)

        if (recorded == 0) {
            VitalsChartEmpty(emptyLine, emptySub, height = MetricTrendHero.height)
        } else {
            val ranges = VitalsProbeMath.equalSlots(points.size)
            val probeBins = points.zip(ranges).map { (point, range) ->
                val clock = MetricWindowMath.slotLabel(point.start, points.size)
                val value = point.value
                if (value == null) {
                    VitalsProbeMath.Bin(range.start, range.end, null, VitalsProbeCopy.gap(clock), vacant = true)
                } else {
                    val printed = if (unit.isEmpty()) format(value) else L("%@ %@", format(value), unit)
                    VitalsProbeMath.Bin(range.start, range.end, 1 - fraction(value), VitalsProbeCopy.line(clock, printed))
                }
            }
            VitalsChartProbe(
                series = VitalsProbeMath.Series.Bins(probeBins),
                tint = tint,
                height = MetricTrendHero.height,
                trailingInset = VitalsScaleRail.gutter,
                accessibilityTitle = L("BY DAY"),
                accessibilityName = accessibilityName,
            ) { _ ->
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(VitalsScaleRail.gap)) {
                    Canvas(Modifier.weight(1f).fillMaxHeight()) {
                        when (style) {
                            MetricTrendHero.Style.bars -> drawTrendBars(points, isMonth, band, rule, tint, ::fraction, ::markTint)
                            MetricTrendHero.Style.line -> drawTrendLine(points, isMonth, band, rule, tint, ::fraction, ::markTint)
                        }
                    }
                    val mid = (scale.start + scale.endInclusive) / 2
                    VitalsScaleRail(listOf(scale.endInclusive, mid, scale.start).map(format), tint)
                }
            }
            // Seven weekday names under a week; the first date and TODAY under a month.
            Box(Modifier.padding(end = VitalsScaleRail.gutter)) {
                if (isMonth) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        FitText(
                            points.firstOrNull()?.let { Fmt.displayDate(it.start, "d MMM").uppercase(Locale.ROOT) } ?: Fmt.dash,
                            NBFont.ui(400, 9f), NB.white.copy(alpha = 0.45f),
                        )
                        Spacer(Modifier.weight(1f))
                        FitText(L("TODAY"), NBFont.ui(500, 9f), tint)
                    }
                } else {
                    Row(Modifier.fillMaxWidth()) {
                        points.forEachIndexed { i, point ->
                            val last = i == points.size - 1
                            FitText(
                                Fmt.weekday(point.start), NBFont.ui(if (last) 500 else 400, 9f),
                                if (last) tint else NB.white.copy(alpha = 0.45f),
                                Modifier.weight(1f), minScale = 0.7f, align = TextAlign.Center,
                            )
                        }
                    }
                }
            }
            VitalsChartLegend(
                items = listOf(VitalsChartLegend.Item(seriesLabel, tint, stops = zones?.legendStops)) +
                    (rule?.let { listOf(VitalsChartLegend.Item(it.label, tint, isArea = true)) } ?: emptyList()) +
                    (band?.let { listOf(VitalsChartLegend.Item(it.label, tint, isArea = true)) } ?: emptyList()),
                trailing = if (hasGap) L("DOTTED · NO RECORD") else null,
                trailingTint = NB.white.copy(alpha = 0.45f),
            )
        }

        // The one number, the change, the count.
        Row(
            Modifier
                .fillMaxWidth()
                .drawBehind { drawRect(NB.white.copy(alpha = 0.06f), Offset.Zero, Size(size.width, 1.dp.toPx())) }
                .padding(top = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FitText(summary.headline, NBFont.dot(700, 14f).tracking(0.02f),
                if (recorded == 0) NB.text3Prod else tint, Modifier.alignBy(FirstBaseline), minScale = 0.8f)
            val u = summary.unit
            if (u != null && recorded > 0) {
                FitText(u, NBFont.ui(600, 10f), NB.text1, Modifier.alignBy(FirstBaseline))
            }
            val delta = summary.delta
            if (delta != null) {
                FitText(L("· %@", delta), NBFont.ui(500, 10f), NB.white.copy(alpha = 0.62f),
                    Modifier.alignBy(FirstBaseline), minScale = 0.8f)
            }
            Spacer(Modifier.weight(1f))
            FitText(summary.worn, NBFont.ui(400, 10f), NB.white.copy(alpha = 0.42f),
                Modifier.alignBy(FirstBaseline), minScale = 0.8f)
        }

        if (rolls.isNotEmpty()) RollStrip(rolls, rollCaption, tint, format, ::fraction)
    }
}

private fun DrawScope.drawTrendBars(
    points: List<MetricTrendHero.Point>, isMonth: Boolean,
    band: MetricTrendHero.Band?, rule: MetricTrendHero.Rule?, tint: Color,
    fraction: (Double) -> Double, markTint: (Double) -> Color,
) {
    val u = density
    val count = max(points.size, 1)
    val spacing = (if (isMonth) 2f else 6f) * u
    val width = max(2 * u, (size.width - spacing * (count - 1)) / count)
    val radius = min(width / 2, 6 * u)
    if (band != null) {
        val top = size.height * (1 - fraction(band.range.endInclusive)).toFloat()
        val bottom = size.height * (1 - fraction(band.range.start)).toFloat()
        drawRect(tint.copy(alpha = tint.alpha * 0.12f), Offset(0f, top), Size(size.width, max(u, bottom - top)))
    }
    points.forEachIndexed { i, point ->
        val x = i * (width + spacing)
        val value = point.value
        if (value == null) {
            dottedSlot(x, 0f, width, size.height, radius)
        } else {
            // A recorded zero is still a day, not a gap.
            val h = max(2 * u, size.height * fraction(value).toFloat())
            drawRoundRect(markTint(value), Offset(x, size.height - h), Size(width, h), CornerRadius(radius, radius))
        }
    }
    if (rule != null) {
        dashedRule(size.height * (1 - fraction(rule.value)).toFloat(), tint.copy(alpha = tint.alpha * 0.55f))
    }
}

private fun DrawScope.drawTrendLine(
    points: List<MetricTrendHero.Point>, isMonth: Boolean,
    band: MetricTrendHero.Band?, rule: MetricTrendHero.Rule?, tint: Color,
    fraction: (Double) -> Double, markTint: (Double) -> Color,
) {
    if (points.isEmpty()) return
    val u = density
    val pad = 6 * u
    val plot = max(0f, size.height - pad * 2)
    val slot = size.width / points.size
    fun y(value: Double): Float = size.height - pad - fraction(value).toFloat() * plot
    fun at(index: Int, value: Double): Offset = Offset((index + 0.5f) * slot, y(value))

    if (band != null) {
        val top = y(band.range.endInclusive)
        val bottom = y(band.range.start)
        drawRect(tint.copy(alpha = tint.alpha * 0.12f), Offset(0f, top), Size(size.width, max(u, bottom - top)))
    }
    drawRect(NB.white.copy(alpha = 0.10f), Offset(0f, size.height - u), Size(size.width, u))

    // A night with no reading gets a mark on the floor, never a point at the ruler's foot.
    points.forEachIndexed { i, point ->
        if (point.value != null) return@forEachIndexed
        val w = min(14 * u, slot * 0.5f)
        drawRect(NB.white.copy(alpha = 0.16f), Offset((i + 0.5f) * slot - w / 2, size.height - 3 * u), Size(w, 2 * u))
    }

    val runs = MetricTrendHero.runs(points.map { it.value }).map { run -> run.map { at(it.first, it.second) } }

    // The wash under the line is anchored to the run's own crest and stops at the run's ends.
    for (run in runs) {
        if (run.size <= 1) continue
        val area = Path().apply {
            moveTo(run[0].x, size.height)
            run.forEach { lineTo(it.x, it.y) }
            lineTo(run.last().x, size.height)
            close()
        }
        val crest = run.minOf { it.y }
        drawPath(area, Brush.verticalGradient(listOf(tint.copy(alpha = tint.alpha * 0.16f), tint.copy(alpha = 0f)),
            startY = crest, endY = size.height))
    }

    runs.forEachIndexed { i, run ->
        if (run.size > 1) {
            val path = Path().apply {
                moveTo(run[0].x, run[0].y)
                run.drop(1).forEach { lineTo(it.x, it.y) }
            }
            drawPath(path, tint, style = Stroke(2 * u, cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
        if (i + 1 < runs.size) {
            val tail = run.lastOrNull()
            val head = runs[i + 1].firstOrNull()
            if (tail != null && head != null) {
                drawLine(tint.copy(alpha = tint.alpha * 0.28f), tail, head, strokeWidth = 1.2f * u,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * u, 4 * u)))
            }
        }
    }

    if (rule != null) dashedRule(y(rule.value), tint.copy(alpha = tint.alpha * 0.55f))

    // A run of one has no line at all, so its dot is the reading.
    val r = (if (isMonth) 1.8f else 2.8f) * u
    points.forEachIndexed { i, point ->
        val value = point.value ?: return@forEachIndexed
        drawCircle(markTint(value), r, at(i, value))
    }

    // The last recorded day is ringed: it is the one the reader is standing on.
    val last = points.size - 1
    val lastValue = points[last].value
    if (lastValue != null) {
        val p = at(last, lastValue)
        drawCircle(tint.copy(alpha = tint.alpha * 0.45f), 6 * u, p, style = Stroke(u))
        drawCircle(markTint(lastValue), 3.4f * u, p)
    }
}

/** Two days, then four weeks, oldest first: the mean of each slice as a short column. */
@Composable
private fun RollStrip(
    rolls: List<MetricTrendHero.Roll>,
    rollCaption: String,
    tint: Color,
    format: (Double) -> String,
    fraction: (Double) -> Double,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .drawBehind { drawRect(NB.white.copy(alpha = 0.06f), Offset.Zero, Size(size.width, 1.dp.toPx())) }
            .padding(top = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(Modifier.fillMaxWidth()) {
            FitText(L("WEEK BY WEEK"), NBFont.ui(500, 10f).tracking(0.12f), NB.white.copy(alpha = 0.45f),
                Modifier.alignBy(FirstBaseline))
            Spacer(Modifier.width(16.dp))
            Spacer(Modifier.weight(1f))
            FitText(rollCaption, NBFont.ui(400, 9f), NB.white.copy(alpha = 0.35f), Modifier.alignBy(FirstBaseline))
        }
        Row(
            Modifier.fillMaxWidth().padding(end = VitalsScaleRail.gutter),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            rolls.forEach { roll ->
                val last = roll.id == rolls.size - 1
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val value = roll.value
                    FitText(value?.let(format) ?: Fmt.dash, NBFont.dot(600, 11f),
                        if (value == null) NB.text3Prod else if (last) tint else NB.text1, minScale = 0.7f)
                    Canvas(Modifier.fillMaxWidth().height(36.dp)) {
                        val u = density
                        val r = 3 * u
                        if (value == null) {
                            dottedSlot(0f, 0f, size.width, size.height, r)
                        } else {
                            val h = max(2 * u, 36 * u * fraction(value).toFloat())
                            drawRoundRect(tint.copy(alpha = tint.alpha * if (last) 1f else 0.55f),
                                Offset(0f, size.height - h), Size(size.width, h), CornerRadius(r, r))
                        }
                    }
                    FitText(roll.label, NBFont.ui(if (last) 500 else 400, 9f),
                        if (last) tint else NB.white.copy(alpha = 0.45f))
                }
            }
        }
    }
}
