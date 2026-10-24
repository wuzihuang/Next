package com.nextbody.hoop.features.device

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BatteryDrainMath
import com.nextbody.hoop.band.BatteryEta
import com.nextbody.hoop.band.BatteryLeft
import com.nextbody.hoop.band.BatteryLog
import com.nextbody.hoop.band.BatteryPlot
import com.nextbody.hoop.band.BatteryPoint
import com.nextbody.hoop.band.BatterySpan
import com.nextbody.hoop.band.DetailSurface
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.training.SegmentedPills
import com.nextbody.hoop.features.vitals.VitalsChartProbe
import com.nextbody.hoop.features.vitals.VitalsProbeCopy
import com.nextbody.hoop.features.vitals.VitalsProbeMath
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.ui.DetailScroll
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Second-level behind the device lime slab. Paper 12F is only the instrument:
 * DAY / WEEK / MONTH pills, overnight columns on the sleep clock, and the line this phone
 * kept. Landing is DAY — last 24 hours — the same default HEART uses.
 */
@Composable
fun BatteryTrendView() {
    val data = DataStore
    var rangeRaw by remember { mutableStateOf(RollingPills.day.raw) }
    val range = RollingPills.parse(rangeRaw)
    val detail = DetailWindow(DetailSurface.battery, range)
    val now = Instant.now()
    val window = BatteryLog.window(endingAt = now, range = range)
    val plot = BatteryLog.plot(data.batteryLog, window.start, window.end)

    /** The night the sleep page uses — sleepStart → wakeAt — not a 04:00 cut and not a charge
     *  span the phone invented. */
    val overnightNights: List<BatterySpan> = run {
        val seen = HashSet<Instant>()
        val spans = mutableListOf<BatterySpan>()
        for (row in data.history + listOf(data.today)) {
            if (!seen.add(row.day.date)) continue
            val start = row.sleep?.sleepStart ?: continue
            val wake = row.sleep?.wakeAt ?: continue
            if (wake <= start) continue
            spans.add(BatterySpan(start, wake))
        }
        spans
    }
    val overnight = BatteryDrainMath.clip(overnightNights, plot.start, plot.end)

    LaunchedEffect(Unit) {
        DetailWindow.debugRange(DetailSurface.battery)?.let { rangeRaw = it.raw }
        if (Band.allowsSeed) return@LaunchedEffect
        com.nextbody.hoop.services.Repository.hydrate(detail, endingAt = UserDay.containing(now), store = data)
    }

    DetailScroll(
        glow = NB.lime1,
        title = L("BATTERY"),
        onBack = { Router.back() },
        trailing = {
            FitText(L(detail.periodKey), NBFont.dot(600, 11f).tracking(0.24f), NB.text3Prod, minScale = 0.72f)
        },
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            SegmentedPills(RollingPills.words, rangeRaw, { rangeRaw = it }, lined = true)
            Instrument(plot, overnight, overnightNights, range, detail, now)
        }
    }
}

@Composable
private fun Instrument(
    plot: BatteryPlot,
    overnight: List<BatterySpan>,
    overnightNights: List<BatterySpan>,
    range: RollingPills,
    detail: DetailWindow,
    now: Instant,
) {
    val data = DataStore
    val periodLabel = L(detail.periodKey)
    Column(
        Modifier
            .fillMaxWidth()
            .bleed(NB.Layout.gutter)
            .topRule()
            .semantics { contentDescription = L("Battery trend"); stateDescription = periodLabel },
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 16.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(periodLabel, style = NBFont.dot(600, 10f).tracking(0.2f), color = NB.white.copy(alpha = 0.60f),
                    modifier = Modifier.weight(1f))
                Spacer(Modifier.width(16.dp)) // 8 + 0 + 8, as SwiftUI spaces around the Spacer
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(10.dp).background(NB.lime1.copy(alpha = 0.28f), RoundedCornerShape(1.5.dp)))
                    Text(L("OVERNIGHT"), style = NBFont.dot(600, 10f).tracking(0.16f), color = NB.white.copy(alpha = 0.60f))
                }
            }

            if (plot.points.isEmpty()) {
                Text(
                    L("Nothing recorded yet. Charge, unplug, or sync this NEXTBODY to start the line."),
                    style = NBFont.ui(400, 13f).tracking(0.02f),
                    color = NB.text3Prod,
                    modifier = Modifier.fillMaxWidth().height(148.dp),
                )
            } else {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        VitalsChartProbe(
                            series = VitalsProbeMath.Series.Points(probePoints(plot)),
                            tint = NB.lime1,
                            height = 148.dp,
                            gapFraction = VitalsProbeMath.gapFraction(seconds(plot.start, plot.end)),
                            leadingInset = 3.dp,
                            trailingInset = 3.dp,
                            clockAt = { f -> probeClock(plot, f) },
                            accessibilityTitle = L("Battery trend"),
                            accessibilityName = "battery.probe",
                        ) { probing ->
                            BatteryTrendChart(
                                plot = plot,
                                overnight = overnight,
                                dayTicks = gridTicks(plot, range, overnightNights),
                                lineWidth = if (range == RollingPills.month) 1.5f else 1.8f,
                                showPip = !probing,
                            )
                        }
                        val labels = axisLabels(plot, range)
                        Row(Modifier.fillMaxWidth()) {
                            labels.forEachIndexed { i, label ->
                                val last = i == labels.size - 1
                                Text(
                                    label,
                                    style = NBFont.dot(if (last) 700 else 500, 9f).tracking(0.08f),
                                    color = if (last) NB.lime1 else NB.white.copy(alpha = 0.34f),
                                    maxLines = 1,
                                )
                                if (!last) Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                    BatteryScaleRail(if (plot.isPercent) listOf("100", "50", "0") else listOf("4", "2", "0"))
                }
            }
        }

        Rule()

        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            val high = factParts(plot, plot.high)
            val low = factParts(plot, plot.low)
            BatteryFact(L("HIGH"), high.first, high.second, Modifier.weight(1f))
            VRule()
            BatteryFact(L("LOW"), low.first, low.second, Modifier.weight(1f))
            VRule()
            val lastPlug = BatteryLog.lastPlug(data.batteryLog, plot.start, plot.end)
            BatteryFact(L("LAST PLUG"), lastPlug?.let { Fmt.clock(it) } ?: L("NEVER"), null, Modifier.weight(1f))
        }

        // Learned unplugged slope only. Silent with `eta` — never the five-day pack.
        val left = if (plot.isPercent && plot.points.isNotEmpty()) BatteryDrainMath.left(data.batteryLog, now) else null
        if (left != null) {
            Rule()
            val parts = when (left) {
                is BatteryLeft.Hours -> "${left.hours}" to L("HRS")
                is BatteryLeft.Days -> "${left.days}" to L("DAYS")
            }
            BatteryFact(L("LEFT"), parts.first, parts.second, Modifier.fillMaxWidth().testTag("battery.left"))
        }

        // Small because it is a slope, not a reading. Silent when the log has not learned a
        // rate — the five-day pack must not become a clock.
        val eta = if (plot.isPercent && plot.points.isNotEmpty()) BatteryDrainMath.eta(data.batteryLog, now) else null
        if (eta != null) {
            Rule()
            val line = when (eta) {
                is BatteryEta.Full -> L("EST · FULL %@", stamp(eta.at, now))
                is BatteryEta.Empty -> L("EST · EMPTY %@", stamp(eta.at, now))
            }
            // A sentence with a weekday and clock: one UI face.
            Text(
                line,
                style = NBFont.ui(500, 12f).tracking(0.02f),
                color = NB.white.copy(alpha = 0.38f),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).testTag("battery.eta"),
            )
        }
    }
}

@Composable
private fun Rule() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(NB.hairline))
}

@Composable
private fun VRule() {
    Box(Modifier.width(1.dp).fillMaxHeight().background(NB.hairline))
}

private fun seconds(from: Instant, to: Instant): Double = Duration.between(from, to).toMillis() / 1000.0

private fun factParts(plot: BatteryPlot, value: Double?): Pair<String, String?> {
    if (value == null) return Fmt.dash to null
    return "${value.roundToInt()}" to if (plot.isPercent) "%" else "/4"
}

private fun stamp(date: Instant, now: Instant): String {
    val zone = ZoneId.systemDefault()
    val clock = Fmt.clock(date)
    val day = date.atZone(zone).toLocalDate()
    val today = now.atZone(zone).toLocalDate()
    if (day == today) return L("TODAY %@", clock)
    if (day == today.plusDays(1)) return L("TOMORROW %@", clock)
    val days = ChronoUnit.DAYS.between(today, day)
    if (days in 1..6) return "${Fmt.weekday(date)} $clock"
    return "${Fmt.displayDate(date, "MM-dd")} $clock"
}

/** Week marks each recorded night's start — the same clock the sleep page uses — not the
 *  04:00 user-day cut. Day and month keep the four-way split the axis labels use. */
private fun gridTicks(plot: BatteryPlot, range: RollingPills, nights: List<BatterySpan>): List<Instant> {
    return when (range) {
        RollingPills.week -> {
            val starts = nights.map { it.start }.filter { it > plot.start && it < plot.end }.sorted()
            if (starts.isNotEmpty()) return starts
            var day = UserDay.containing(plot.start)
            if (day.start <= plot.start) day = day.adding(1)
            val ticks = mutableListOf<Instant>()
            while (day.start < plot.end) {
                ticks.add(day.start)
                day = day.adding(1)
            }
            ticks
        }
        RollingPills.day, RollingPills.month -> {
            val span = seconds(plot.start, plot.end)
            (1..3).map { i -> plot.start.plusMillis((span * i / 4 * 1000).toLong()) }
        }
    }
}

private fun axisLabels(plot: BatteryPlot, range: RollingPills): List<String> {
    val span = max(0.001, seconds(plot.start, plot.end))
    val marks = (0 until 5).map { i -> plot.start.plusMillis((span * i / 4 * 1000).toLong()) }
    return marks.mapIndexed { i, date ->
        if (i == marks.size - 1) return@mapIndexed L("NOW")
        when (range) {
            RollingPills.day -> Fmt.clock(date)
            RollingPills.week -> Fmt.weekday(date)
            RollingPills.month -> String.format(java.util.Locale.ROOT, "%02d", date.atZone(ZoneId.systemDefault()).dayOfMonth)
        }
    }
}

private fun probePoints(plot: BatteryPlot): List<VitalsProbeMath.Point> {
    val span = max(0.001, seconds(plot.start, plot.end))
    return plot.points.filter { !it.estimated }.map { point ->
        val fraction = VitalsProbeMath.clamp(seconds(plot.start, point.at) / span)
        val value = if (plot.isPercent) "${point.value.roundToInt()}%" else "${point.value.roundToInt()}/4"
        VitalsProbeMath.Point(
            fraction = fraction,
            yFraction = VitalsProbeMath.yFraction(point.value, 0.0, plot.yMax),
            text = VitalsProbeCopy.line(Fmt.clock(point.at), value),
        )
    }
}

private fun probeClock(plot: BatteryPlot, fraction: Double): String {
    if (fraction >= 0.999) return L("NOW")
    val span = max(0.0, seconds(plot.start, plot.end))
    return Fmt.clock(plot.start.plusMillis((span * fraction * 1000).toLong()))
}

/** Paper 12F · overnight lime columns, a lime polyline, a NOW pip. The ruler lives beside the
 *  field. A stretch the phone did not hear is a dashed drain curve, not a ruler. */
@Composable
private fun BatteryTrendChart(
    plot: BatteryPlot,
    overnight: List<BatterySpan>,
    dayTicks: List<Instant>,
    lineWidth: Float = 1.8f,
    showPip: Boolean = true,
) {
    Canvas(Modifier.fillMaxWidth().height(148.dp)) {
        val k = 1.dp.toPx()
        val spanY = max(0.001, plot.yMax)
        val spanX = max(0.001, seconds(plot.start, plot.end))
        val inset = 3 * k
        fun y(v: Double): Float {
            val clamped = min(plot.yMax, max(0.0, v))
            return (size.height - 1 * k - clamped / spanY * (size.height - 2 * k)).toFloat()
        }
        fun x(at: Instant): Float = (inset + seconds(plot.start, at) / spanX * (size.width - inset * 2)).toFloat()
        fun point(p: BatteryPoint) = Offset(x(p.at), y(p.value))

        for (tick in dayTicks) {
            val at = x(tick)
            drawLine(NB.white.copy(alpha = 0.06f), Offset(at, 0f), Offset(at, size.height), 1 * k)
        }
        for (span in overnight) {
            val left = x(span.start)
            val width = max(2 * k, x(span.end) - left)
            drawRect(NB.lime1.copy(alpha = 0.10f), Offset(left, 0f), Size(width, size.height))
        }
        drawRuns(plot, ::point, heardWidth = lineWidth * k, guessAlpha = 0.55f, round = true)
        if (showPip) {
            plot.runs.lastOrNull()?.lastOrNull()?.let { drawCircle(NB.lime1, 3 * k, point(it)) }
        }
    }
}

/** The heard line solid, the guessed stretches dashed, and a dashed join across a gap that
 *  touches a guess. Shared by the trend and the lime slab's lead. */
internal fun DrawScope.drawRuns(
    plot: BatteryPlot,
    point: (BatteryPoint) -> Offset,
    heardWidth: Float,
    guessAlpha: Float,
    round: Boolean,
    guessWidth: Float = 1.2f * density,
) {
    val k = density
    val dash = PathEffect.dashPathEffect(floatArrayOf(2 * k, 3 * k))
    val cap = if (round) StrokeCap.Round else StrokeCap.Square
    val join = if (round) StrokeJoin.Round else StrokeJoin.Miter
    plot.runs.forEachIndexed { i, run ->
        val first = run.firstOrNull() ?: return@forEachIndexed
        val heard = Path()
        val guess = Path()
        if (run.size == 1) {
            val p = point(first)
            heard.moveTo(p.x, p.y); heard.lineTo(p.x + 0.5f * k, p.y)
        }
        var prev = first
        for (p in run.drop(1)) {
            val a = point(prev); val b = point(p)
            val target = if (prev.estimated || p.estimated) guess else heard
            target.moveTo(a.x, a.y); target.lineTo(b.x, b.y)
            prev = p
        }
        drawPath(heard, NB.lime1, style = Stroke(heardWidth, cap = cap, join = join))
        drawPath(guess, NB.lime1.copy(alpha = guessAlpha), style = Stroke(guessWidth, cap = cap, join = join, pathEffect = dash))
        val next = plot.runs.getOrNull(i + 1)?.firstOrNull()
        val last = run.lastOrNull()
        if (next != null && last != null && (last.estimated || next.estimated)) {
            val a = point(last); val b = point(next)
            drawLine(NB.lime1.copy(alpha = guessAlpha), a, b, guessWidth, pathEffect = dash)
        }
    }
}

/** Doto rail on the right, top mark first — 100 / 50 / 0, or 4 / 2 / 0 for bars. */
@Composable
private fun BatteryScaleRail(labels: List<String>) {
    Box(Modifier.width(28.dp).height(148.dp)) {
        labels.forEachIndexed { i, label ->
            val fraction = if (labels.size > 1) i.toFloat() / (labels.size - 1) else 0f
            val y = 148.dp * fraction
            Box(Modifier.offset(x = 0.dp, y = y).size(6.dp, 1.dp).background(NB.white.copy(alpha = 0.22f)))
            FitText(
                label,
                NBFont.dot(600, 9f).tracking(0.06f),
                NB.white.copy(alpha = 0.45f),
                Modifier.offset(x = 8.dp, y = y - 6.dp),
                minScale = 0.7f,
            )
        }
    }
}

/** One cell on the carbon instrument. Same split as the lime slab: Doto number, Doto unit. */
@Composable
private fun BatteryFact(label: String, value: String, unit: String?, modifier: Modifier = Modifier) {
    Column(
        modifier.padding(vertical = 14.dp, horizontal = 16.dp).heightIn(min = 0.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text(label, style = NBFont.ui(500, 10f).tracking(0.16f), color = NB.text3Prod)
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            FitText(value, NBFont.dot(700, 20f), NB.text1, Modifier.alignByBaseline(), minScale = 0.55f)
            if (unit != null) {
                Text(unit, style = NBFont.dot(500, 10f), color = NB.white.copy(alpha = 0.45f), modifier = Modifier.alignByBaseline())
            }
        }
    }
}
