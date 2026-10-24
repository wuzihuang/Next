package com.nextbody.hoop.features.vitals

import com.nextbody.hoop.features.home.panel.VitalsMath
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.ActiveEnergyHour
import com.nextbody.hoop.band.ActiveEnergyMath
import com.nextbody.hoop.band.ActiveEnergySplit
import com.nextbody.hoop.band.ActiveEnergyWeekBar
import com.nextbody.hoop.band.FuelClockPoint
import com.nextbody.hoop.band.FuelWindowMath
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.ui.CardBlock
import java.time.Instant
import java.util.Locale
import kotlin.math.max

/** Paper HY1-0 · ACTIVE ENERGY day board. Five cards, one question each. The OUT polyline is
 *  `FuelWindowMath.burnCurve` — the same points the calories page draws. */
data class ActiveEnergyModel(
    val split: ActiveEnergySplit,
    val hours: List<ActiveEnergyHour>,
    val outSolid: List<FuelClockPoint>,
    val outDashed: List<FuelClockPoint>,
    val restSolid: List<FuelClockPoint>,
    val restDashed: List<FuelClockPoint>,
    val metSolid: List<FuelClockPoint>,
    val metDashed: List<FuelClockPoint>,
    /** `(index, kcal)` of the busiest lived hour. */
    val peak: IndexedValue<Double>?,
    val weekBars: List<ActiveEnergyWeekBar>,
    val weekAverage: Double?,
    val todayDelta: Double?,
    val hoursLeft: Int,
    val now: Instant,
    val dayStart: Instant,
) {
    val nowFraction: Double get() = FuelWindowMath.clockFraction(now, dayStart)

    companion object {
        fun make(m: DailyMetrics, now: Instant, history: List<DailyMetrics>): ActiveEnergyModel {
            val clipped = minOf(now, minOf(m.asOf ?: now, m.day.end))
            val ticks = m.vitalsCurve
            val energyTicks = m.energyDistribution?.map { it.tick } ?: ticks
            val windows = sportWindows(m)
            val split = ActiveEnergyMath.split(
                dayStart = m.day.start, now = clipped, bmr = m.bmr, bmrFull = m.bmrFull,
                eActive = m.eActive, eTrain = m.eTrain, eOutNow = m.eOutNow,
                ticks = ticks, sportWindows = windows, energyDistribution = m.energyDistribution)
            val hours = ActiveEnergyMath.hourly(m.day.start, clipped, split, energyTicks, windows)
            val out = split.out?.let {
                ActiveEnergyMath.outCurve(m.day.start, clipped, burnedNow = it, burnedFull = m.eOutFull,
                    restingNow = split.resting, ticks = energyTicks)
            }
            val rest = split.resting?.let { ActiveEnergyMath.restCurve(m.day.start, clipped, it) }
            val met = ActiveEnergyMath.intensity(m.day.start, clipped, ticks)
            val weekDays = (0 until 7).map { offset ->
                val day = m.day.adding(-(6 - offset))
                val row = if (day == m.day) m else history.firstOrNull { it.day == day }
                day.start to row?.let { ActiveEnergyMath.totals(it.bmr, it.eActive, it.eTrain, it.eOutNow).active }
            }
            val week = ActiveEnergyMath.week(weekDays, m.day.start)
            return ActiveEnergyModel(
                split = split, hours = hours,
                outSolid = out?.solid ?: emptyList(), outDashed = out?.dashed ?: emptyList(),
                restSolid = rest?.solid ?: emptyList(), restDashed = rest?.dashed ?: emptyList(),
                metSolid = met.solid, metDashed = met.dashed,
                peak = ActiveEnergyMath.peakHour(hours),
                weekBars = week.bars, weekAverage = week.average, todayDelta = week.todayDelta,
                hoursLeft = ActiveEnergyMath.hoursLeft(m.day.start, clipped),
                now = clipped, dayStart = m.day.start,
            )
        }

        fun sportWindows(m: DailyMetrics): List<Pair<Instant, Instant>> =
            m.segments.filter { !it.allDay }.mapNotNull { segment ->
                val minutes = segment.minutes
                if (minutes == null || minutes <= 0) null
                else segment.at to segment.at.addingTimeInterval(minutes * 60.0)
            }
    }
}

/** Ledger hero. Keeps `vitals.hero` and the sensor label so the second-level UI test still
 *  lands on the right page. */
@Composable
fun ActiveEnergyHero(model: ActiveEnergyModel, sensor: String) {
    val active = model.split.active
    Column(
        Modifier
            .width(NB.Layout.contentWidth)
            .padding(bottom = 4.dp)
            .testTag("vitals.hero")
            .clearAndSetSemantics {
                contentDescription = sensor
                stateDescription = active?.let { "$it KCAL ACTIVE" } ?: "no reading"
            },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FitText(L("TODAY · 04→%@", Fmt.clock(model.now)), NBFont.ui(500, 11f).tracking(0.12f), NB.text3Prod)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FitText(Fmt.kcal(active), NBFont.dot(700, 56f).tracking(-0.04f),
                if (active == null) NB.text3Prod else NB.lime1, Modifier.alignBy(FirstBaseline), minScale = 0.6f)
            FitText(L("KCAL ACTIVE"), NBFont.ui(500, 13f).tracking(0.1f), NB.text3Prod, Modifier.alignBy(FirstBaseline))
            Spacer(Modifier.weight(1f))
        }
        FitText(L("RESTING %@ + ACTIVE %@", Fmt.kcal(model.split.resting), Fmt.kcal(active)),
            NBFont.ui(400, 14f), NB.text2, minScale = 0.8f)
    }
}

private fun metLabel(value: Double?): String = value?.let { swiftFormat("%.1f", it) } ?: Fmt.dash

/** Emits its five cards and the footer as siblings into the caller's column. */
@Composable
fun ActiveEnergyBoard(model: ActiveEnergyModel) {
    val dayStart = model.dayStart
    val s = model.split

    // ACCUMULATED
    CardBlock(title = L("ACCUMULATED"), trailing = "KCAL") {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (model.outSolid.isEmpty()) {
                VitalsChartEmpty(L("HOURLY ENERGY NOT AVAILABLE"), L("DAILY ACTIVE ENERGY IS WEIGHT-AWARE AND SETTLED"),
                    height = 176.dp)
            } else {
                val ys = (model.outSolid + model.outDashed + model.restSolid + model.restDashed).map { it.y }
                val chartMax = max(ys.maxOrNull() ?: 1.0, 1.0)
                ActiveEnergyLineChart(
                    series = listOf(
                        ActiveEnergyLineChart.Series(model.restSolid, NB.macroValue, false, 1.5.dp),
                        ActiveEnergyLineChart.Series(model.restDashed, NB.macroValue, true, 1.5.dp),
                        ActiveEnergyLineChart.Series(model.outSolid, NB.lime1, false, 2.dp),
                        ActiveEnergyLineChart.Series(model.outDashed, NB.lime1, true, 2.dp),
                    ),
                    nowX = model.nowFraction,
                    nowBright = true,
                    maxY = chartMax,
                    height = 176.dp,
                    mark = model.outSolid.lastOrNull()?.let { it to NB.lime1 },
                    restMark = model.restSolid.lastOrNull()?.let { it to NB.macroValue },
                )
                VitalsAxis(FuelWindowMath.clockLabels(dayStart), highlightsLast = false, tint = NB.lime1)
                val last = model.outDashed.lastOrNull()?.y
                val out = s.out
                val leftover = if (last == null || out == null) L("EST +%@", Fmt.dash)
                else L("EST +%@", Fmt.kcal(max(0.0, last - out)))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    LegendTick(NB.lime1, L("OUT %@", Fmt.kcal(s.out)))
                    LegendTick(NB.macroValue, L("RESTING %@", Fmt.kcal(s.resting)))
                    LegendTick(NB.lime1.copy(alpha = 0.5f), leftover)
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }

    // PER HOUR
    CardBlock(
        title = L("PER HOUR"),
        trailing = model.peak?.let {
            L("PEAK %@ · %@", VitalsMath.clock(day = UserDay.containing(dayStart), minute = it.index * 60), Fmt.kcal(it.value))
        },
    ) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (model.hours.isEmpty()) {
                VitalsChartEmpty(L("HOURLY ENERGY NOT AVAILABLE"), L("WAITING FOR VERIFIED ENERGY"), height = 84.dp)
            } else {
                LivedHourBars(model.hours, NB.lime1, 84.dp)
            }
            VitalsAxis(FuelWindowMath.clockLabels(dayStart), highlightsLast = false, tint = NB.lime1)
            FitText(L("Activity only · resting energy is excluded"), NBFont.ui(400, 11f), NB.text3Prod, minScale = 0.8f)
        }
    }

    // SPLIT
    CardBlock(title = L("SPLIT"), trailing = L("4 PARTS · %@", Fmt.kcal(s.out))) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ActiveEnergySplitBar(s)
            val dayMinutes = (FuelWindowMath.dayEnd(dayStart).timeIntervalSince(dayStart) / 60).toInt()
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SplitCell(L("RESTING"), s.resting, NB.white.copy(alpha = 0.55f),
                    s.bmrFull?.let { full -> s.elapsedMinutes?.let { L("%@ × %d / %d", Fmt.kcal(full), it, dayMinutes) } }
                        ?: L("NEEDS YOUR WEIGHT"), Modifier.weight(1f))
                SplitCell(L("SPORT"), s.sport, NB.lime1,
                    s.sportMinutes?.let { L("%d min · MET %@", it, metLabel(s.sportMet)) } ?: L("——"), Modifier.weight(1f))
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SplitCell(L("STEPS"), s.steps, NB.lime1.copy(alpha = 0.75f),
                    s.stepCount?.let { L("%@ steps · MET %@", Fmt.int(it), metLabel(s.stepsMet)) } ?: L("——"),
                    Modifier.weight(1f))
                SplitCell(L("INCIDENTAL"), s.incidental, NB.lime1.copy(alpha = 0.55f),
                    s.incidentalMinutes?.let { L("%d min · MET %@", it, metLabel(s.incidentalMet)) } ?: L("——"),
                    Modifier.weight(1f))
            }
        }
    }

    // INTENSITY
    val metPeak = model.metSolid.maxOfOrNull { it.y } ?: ActiveEnergyMath.stillMet
    CardBlock(title = L("INTENSITY"), trailing = L("MET · MAX %@", metLabel(metPeak))) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            ActiveEnergyLineChart(
                series = listOf(
                    ActiveEnergyLineChart.Series(model.metSolid, NB.lime1, false, 2.dp),
                    ActiveEnergyLineChart.Series(model.metDashed, NB.white.copy(alpha = 0.35f), true, 2.dp),
                ),
                nowX = model.nowFraction,
                maxY = max(metPeak, ActiveEnergyMath.sportMet),
                height = 84.dp,
            )
            VitalsAxis(FuelWindowMath.clockLabels(dayStart), highlightsLast = false, tint = NB.lime1)
            FitText(L("1.0 still · 3.0 walk · 5.1 the session"), NBFont.ui(400, 11f), NB.text3Prod, minScale = 0.8f)
        }
    }

    // LAST 7 DAYS
    val avg = L("AVG %@", Fmt.kcal(model.weekAverage))
    val weekTrailing = model.todayDelta?.let { L("%@ · TODAY %@", avg, Fmt.signedKcal(it)) } ?: avg
    CardBlock(title = L("LAST 7 DAYS"), trailing = weekTrailing) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            ActiveEnergyWeekBars(model.weekBars, model.weekAverage, 84.dp)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                model.weekBars.forEach { bar ->
                    FitText(
                        Fmt.weekday(bar.start).take(3).uppercase(Locale.ROOT),
                        NBFont.ui(if (bar.isToday) 600 else 500, 10f).tracking(0.08f),
                        if (bar.isToday) NB.lime1 else NB.text3Prod,
                        Modifier.weight(1f),
                    )
                }
            }
            FitText(L("Dashed = 7-day average · today has %dH left", model.hoursLeft), NBFont.ui(400, 11f),
                NB.text3Prod, minScale = 0.8f)
        }
    }

    // Footer
    Column(Modifier.width(NB.Layout.contentWidth).padding(top = 2.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        FitText(
            L("%@ + %@ + %@ + %@ = %@", Fmt.kcal(s.resting), Fmt.kcal(s.sport), Fmt.kcal(s.steps),
                Fmt.kcal(s.incidental), Fmt.kcal(s.out)),
            NBFont.ui(500, 13f), NB.text2, minScale = 0.7f,
        )
        FitText(L("Resting energy is estimated from your body profile; active energy from recorded activity."),
            NBFont.ui(400, 11f), NB.text3Prod, maxLines = Int.MAX_VALUE)
        FitText(L("Missing activity time is not included."), NBFont.ui(400, 11f), NB.text3Prod, maxLines = Int.MAX_VALUE)
        FitText(L("A missing part reads —— not 0."), NBFont.ui(400, 11f), NB.text3Prod, maxLines = Int.MAX_VALUE)
    }
}

@Composable
private fun SplitCell(name: String, value: Double?, tint: Color, foot: String, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.align(Alignment.CenterVertically).size(8.dp).background(tint, RoundedCornerShape(2.dp)))
            FitText(name, NBFont.ui(600, 11f).tracking(0.08f), NB.text2, Modifier.alignBy(FirstBaseline))
            Spacer(Modifier.weight(1f))
            FitText(Fmt.kcal(value), NBFont.dot(600, 19f), if (value == null) NB.text3Prod else tint,
                Modifier.alignBy(FirstBaseline), minScale = 0.7f)
        }
        FitText(foot, NBFont.ui(400, 10f), NB.text3Prod, minScale = 0.8f)
    }
}

@Composable
private fun LegendTick(tint: Color, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(14.dp, 2.dp).background(tint))
        FitText(text, NBFont.ui(500, 11f).tracking(0.06f), NB.text2, minScale = 0.75f)
    }
}

@Composable
fun ActiveEnergySplitBar(split: ActiveEnergySplit) {
    val parts = listOf(
        split.resting to NB.white.copy(alpha = 0.22f),
        split.sport to NB.lime1,
        split.steps to NB.lime1.copy(alpha = 0.75f),
        split.incidental to NB.lime1.copy(alpha = 0.55f),
    ).mapNotNull { (value, tint) -> if (value == null || value <= 0) null else value to tint }
    val total = parts.sumOf { it.first }
    BoxWithConstraints(Modifier.fillMaxWidth().height(16.dp).clip(RoundedCornerShape(8.dp))) {
        val w = maxWidth.value
        Row(Modifier.fillMaxSize()) {
            if (total <= 0) {
                Box(Modifier.fillMaxSize().background(NB.barTrack))
            } else {
                parts.forEach { (value, tint) ->
                    Box(Modifier.width(max(2.0, w * value / total).toFloat().dp).height(16.dp).background(tint))
                }
            }
        }
    }
}

object ActiveEnergyLineChart {
    data class Series(val points: List<FuelClockPoint>, val tint: Color, val dashed: Boolean, val width: Dp)
}

@Composable
fun ActiveEnergyLineChart(
    series: List<ActiveEnergyLineChart.Series>,
    nowX: Double = 0.0,
    nowBright: Boolean = false,
    maxY: Double,
    height: Dp = 176.dp,
    mark: Pair<FuelClockPoint, Color>? = null,
    restMark: Pair<FuelClockPoint, Color>? = null,
) {
    Canvas(Modifier.fillMaxWidth().height(height)) {
        val u = density
        fun px(p: FuelClockPoint): Offset =
            Offset((size.width * p.x).toFloat(), (size.height * (1 - p.y / max(maxY, 0.001))).toFloat())
        val nx = (size.width * nowX).toFloat()
        drawLine(NB.white.copy(alpha = if (nowBright) 0.85f else 0.12f), Offset(nx, 0f), Offset(nx, size.height),
            strokeWidth = u, pathEffect = if (nowBright) null else PathEffect.dashPathEffect(floatArrayOf(2 * u, 3 * u)))
        for (item in series) {
            if (item.points.size < 2) continue
            val path = Path()
            val first = px(item.points[0])
            path.moveTo(first.x, first.y)
            for (point in item.points.drop(1)) {
                val p = px(point)
                if (point.startsSegment) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
            }
            drawPath(path, item.tint, style = Stroke(item.width.toPx(),
                pathEffect = if (item.dashed) PathEffect.dashPathEffect(floatArrayOf(5 * u, 4 * u)) else null))
        }
        restMark?.let { drawCircle(it.second, 3 * u, px(it.first)) }
        mark?.let { drawCircle(it.second, 4.5f * u, px(it.first)) }
    }
}

@Composable
fun LivedHourBars(hours: List<ActiveEnergyHour>, tint: Color, height: Dp = 28.dp) {
    Canvas(Modifier.fillMaxWidth().height(height)) {
        val u = density
        val n = max(1, hours.size)
        val gap = (if (n > 20) 2f else 3f) * u
        val w = (size.width - gap * (n - 1)) / n
        val top = hours.maxOfOrNull { it.kcal } ?: 0.0
        if (top <= 0) return@Canvas
        hours.forEachIndexed { i, hour ->
            if (hour.kcal <= 0) return@forEachIndexed
            val h = max(0.8f * u, (size.height * hour.kcal / top).toFloat())
            drawRect(tint.copy(alpha = tint.alpha * if (hour.lived) 1f else 0.18f), Offset(i * (w + gap), size.height - h), Size(w, h))
        }
    }
}

@Composable
fun ActiveEnergyWeekBars(bars: List<ActiveEnergyWeekBar>, average: Double?, height: Dp = 84.dp) {
    Canvas(Modifier.fillMaxWidth().height(height)) {
        val u = density
        val n = max(1, bars.size)
        val gap = 11 * u
        val w = (size.width - gap * (n - 1)) / n
        val top = maxOf(bars.mapNotNull { it.active }.maxOrNull() ?: 0.0, average ?: 0.0, 1.0)
        if (average != null) {
            val y = (size.height * (1 - average / top)).toFloat()
            drawLine(NB.white.copy(alpha = 0.28f), Offset(0f, y), Offset(size.width, y), strokeWidth = u,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4 * u, 4 * u)))
        }
        bars.forEachIndexed { i, bar ->
            val active = bar.active
            if (active == null || active <= 0) return@forEachIndexed
            val h = (size.height * active / top).toFloat()
            drawRoundRect(if (bar.isToday) NB.lime1 else NB.white.copy(alpha = 0.2f),
                Offset(i * (w + gap), size.height - h), Size(w, h), CornerRadius(3 * u, 3 * u))
        }
    }
}
