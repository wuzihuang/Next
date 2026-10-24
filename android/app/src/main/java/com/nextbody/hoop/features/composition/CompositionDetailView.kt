package com.nextbody.hoop.features.composition

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.band.BodyScanCadence
import com.nextbody.hoop.band.CompositionDayReading
import com.nextbody.hoop.band.CompositionFieldDelta
import com.nextbody.hoop.band.CompositionPlot
import com.nextbody.hoop.band.CompositionPoint
import com.nextbody.hoop.band.CompositionScan
import com.nextbody.hoop.band.CompositionSpan
import com.nextbody.hoop.band.CompositionWindowMath
import com.nextbody.hoop.band.DetailSurface
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.BodyCompositionQueue
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.ui.DetailScroll
import com.nextbody.hoop.features.training.SegmentedPills
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.lineSkin
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * 10E · 成分详情。主语是体脂率。DAY 是这一次对上一次；WEEK / MONTH 是滚动窗口。
 * 数只来自已经落进 `body_composition` 的扫描行——SDK 里没落库的字段不画。
 *
 * [focus] is the user day the page ends on (Swift takes a `Date?`; a local date names the
 * same user day, since a user day runs local midnight → midnight).
 */
@Composable
fun CompositionDetailView(focus: LocalDate?) {
    val data = DataStore
    var rangeRaw by rememberSaveable { mutableStateOf(RollingPills.day.raw) }

    val range = RollingPills.parse(rangeRaw)
    val detail = DetailWindow(DetailSurface.composition, range)
    val day = if (focus != null) UserDay(focus.atStartOfDay(currentZone()).toInstant())
    else UserDay.containing(Instant.now())
    val now = Instant.now()

    val scans: List<CompositionScan> = when {
        DebugEdgeFlag.on("empty") -> emptyList()
        DebugEdgeFlag.on("firstscan") -> data.compositionScans.take(1)
        else -> data.compositionScans
    }

    val window = CompositionWindowMath.bounds(range, endingOn = day, now = now)
    val windowScans = CompositionWindowMath.inWindow(scans, from = window.start, to = window.end)
    val reading = CompositionWindowMath.dayReading(scans, asOf = minOf(now, day.end))
    val plot = CompositionWindowMath.plot(scans, range, endingOn = day, now = now)
    val buckets = CompositionWindowMath.weekBuckets(scans, endingOn = day)
    val weekDays = day.rollingBack(7)

    // router.$windowRequest
    val request = Router.windowRequest
    LaunchedEffect(request) {
        if (request != null) {
            rangeRaw = request
            Router.windowRequest = null
        }
    }

    LaunchedEffect(Unit) {
        DetailWindow.debugRange(DetailSurface.composition)?.let { rangeRaw = it.raw }
        BodyCompositionQueue.flush()
        // The seeded board (emulator) keeps its own rows; the server would replace them.
        if (!Band.allowsSeed) Repository.hydrate(detail, endingAt = day, store = data)
        Analytics.track("COMP_DETAIL_OPEN", mapOf(
            "RANGE" to range.raw,
            "SCANS" to windowScans.size,
            "HAS_CURRENT" to (reading != null),
        ))
    }

    val headerPeriod: String = when (range) {
        RollingPills.day -> {
            val scan = reading?.current
            if (scan == null) L(detail.periodKey)
            else {
                val clock = Fmt.clock(scan.at)
                if (UserDay.containing(scan.at) == UserDay.containing(now)) L("TODAY %@", clock)
                else "${Fmt.weekday(scan.at)} $clock"
            }
        }
        else -> L(detail.periodKey)
    }

    val axisLabels: List<CompositionAxisLabel> = when (range) {
        RollingPills.day -> emptyList()
        RollingPills.week -> {
            val measured = plot.points.map { it.day }.toSet()
            weekDays.mapIndexed { index, slot ->
                val last = index == weekDays.size - 1
                val text = if (last && slot == UserDay.containing(now)) L("NOW") else Fmt.weekday(slot.start)
                CompositionAxisLabel(text, dim = !measured.contains(slot) && !last)
            }
        }
        RollingPills.month -> listOf(
            CompositionAxisLabel(L("−30D"), false),
            CompositionAxisLabel(L("−20D"), false),
            CompositionAxisLabel(L("−10D"), false),
            CompositionAxisLabel(L("NOW"), false),
        )
    }

    DetailScroll(
        glow = NB.lime1,
        title = L("COMPOSITION"),
        onBack = { Router.back() },
        trailing = {
            T(headerPeriod, NBFont.dot(600, 11f).tracking(0.24f), NB.text3Prod)
        },
    ) {
        Column(
            Modifier
                .padding(horizontal = 16.dp)
                .padding(bottom = 30.dp)
                .semantics { contentDescription = "composition.page" },
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            SegmentedPills(RollingPills.words, rangeRaw, onSelect = { rangeRaw = it }, lined = true)
            WindowCard(range, detail, reading, plot, axisLabels)
            SinceBaselineCard(scans)
            when (range) {
                RollingPills.day -> if (reading != null) DayDeltaCard(reading)
                RollingPills.week -> ScanRows(windowScans, scans, window.start, window.end)
                RollingPills.month -> WeekRows(buckets, windowScans)
            }
        }
    }
}

// MARK: since baseline

/**
 * Am I changing, and when is the next scan worth taking. Everything else on this page is a
 * window; this card answers the whole distance from where they started. The cadence line is
 * a measurement suggestion, never a streak.
 */
@Composable
private fun SinceBaselineCard(scans: List<CompositionScan>) {
    val ordered = scans.sortedBy { it.at }
    val first = ordered.firstOrNull() ?: return
    val latest = ordered.last()
    val change = BodyScanCadence.change(
        firstAt = first.at, firstFat = first.bodyFatPercent, firstLean = first.leanMassKg,
        latestAt = latest.at, latestFat = latest.bodyFatPercent, latestLean = latest.leanMassKg,
    ) ?: return
    val due = BodyScanCadence.isDue(since = latest.at)
    Column(
        Modifier.width(NB.Layout.contentWidth).lineSkin(top = 16.dp)
            .semantics { contentDescription = "composition.sinceBaseline" },
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth()) {
            T(L("SINCE YOUR FIRST SCAN"), NBFont.ui(500, 11f).tracking(0.2f), NB.text3Prod, Modifier.weight(1f))
            // 8 + 0 + 8, as SwiftUI spaces around the Spacer
            Spacer(Modifier.width(16.dp))
            T(L("%d DAYS", change.days), NBFont.dot(600, 11f).tracking(0.08f), NB.lime1)
        }
        FactStrip {
            CompositionFact(
                L("BODY FAT"),
                change.bodyFatPoints?.let { Fmt.signedKg(it, decimals = 1) } ?: Fmt.dash,
                unit = if (change.bodyFatPoints == null) null else "PT",
                valueTint = if (change.bodyFatPoints == null) NB.text1 else NB.lime1,
            )
            VRule()
            CompositionFact(
                L("LEAN"),
                change.leanKg?.let { Fmt.signedKg(it, decimals = 1) } ?: Fmt.dash,
                unit = if (change.leanKg == null) null else "KG",
                valueTint = if (change.leanKg == null) NB.text1 else NB.lime1,
            )
            VRule()
            CompositionFact(
                L("NEXT SCAN"),
                if (due) L("DUE") else "${BodyScanCadence.daysLeft(since = latest.at)}",
                unit = if (due) null else L("D"),
                valueTint = if (due) NB.ember1 else NB.text1,
            )
        }
    }
}

// MARK: window card

@Composable
private fun WindowCard(
    range: RollingPills,
    detail: DetailWindow,
    reading: CompositionDayReading?,
    plot: CompositionPlot,
    axisLabels: List<CompositionAxisLabel>,
) {
    val windowTitle = run {
        val n = if (range == RollingPills.day) (if (reading == null) 0 else 1) else plot.scanCount
        val count = if (n == 1) L("%d SCAN", n) else L("%d SCANS", n)
        "${L("BODY FAT")} % · $count"
    }
    val title = L("COMPOSITION")
    val period = L(detail.periodKey)
    Column(
        Modifier.width(NB.Layout.contentWidth)
            .semantics { contentDescription = title; stateDescription = period },
    ) {
        Column(Modifier.padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth()) {
                T(windowTitle, NBFont.dot(600, 10f).tracking(0.2f), NB.white.copy(alpha = 0.60f), Modifier.alignByBaseline().weight(1f))
                Spacer(Modifier.width(16.dp))
                if (range == RollingPills.day) {
                    T(L("NO CHART"), NBFont.dot(600, 10f).tracking(0.16f), NB.white.copy(alpha = 0.60f), Modifier.alignByBaseline())
                } else {
                    Row(
                        Modifier.alignByBaseline(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.size(10.dp).background(NB.lime1.copy(alpha = 0.28f), RoundedCornerShape(1.5.dp)))
                        T(L(if (range == RollingPills.week) "WEEK BAND" else "YOUR BAND"),
                            NBFont.dot(600, 10f).tracking(0.16f), NB.white.copy(alpha = 0.60f))
                    }
                }
            }

            when {
                range == RollingPills.day -> T(
                    dayCaption(reading), NBFont.ui(300, 13f).tracking(0.02f), NB.text2, maxLines = Int.MAX_VALUE,
                )
                plot.points.isEmpty() -> Box(Modifier.height(148.dp)) {
                    T(L("No body scan in this window yet. A finished 30-second scan writes the first row."),
                        NBFont.ui(400, 13f).tracking(0.02f), NB.text3Prod, maxLines = Int.MAX_VALUE)
                }
                else -> Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        CompositionTrendChart(plot, axisLabels)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            axisLabels.forEachIndexed { i, label ->
                                val last = i == axisLabels.size - 1
                                T(label.text, NBFont.dot(if (last) 700 else 500, 9f).tracking(0.08f),
                                    if (last) NB.lime1 else NB.white.copy(alpha = if (label.dim) 0.20f else 0.34f))
                            }
                        }
                    }
                    CompositionScaleRail(
                        listOf(plot.yMax, (plot.yMax + plot.yMin) / 2, plot.yMin).map { swiftFormat("%.1f", it) },
                        Modifier.height(148.dp),
                    )
                }
            }
        }

        Hairline()
        FactStrip {
            when (range) {
                RollingPills.day -> {
                    val age = lastScanAge(reading)
                    CompositionFact(L("NOW"), fat(reading?.current?.bodyFatPercent), unit = "%")
                    VRule()
                    val d = reading?.bodyFat?.delta
                    CompositionFact(L("VS LAST"), signedNumber(d), unit = if (d == null) null else "PT",
                        valueTint = if (d == null) NB.text1 else NB.lime1)
                    VRule()
                    CompositionFact(L("LAST SCAN"), age.first, unit = age.second)
                }
                RollingPills.week -> {
                    CompositionFact(L("NOW"), fat(plot.now), unit = "%")
                    VRule()
                    CompositionFact(L("7D LOW"), fat(plot.windowLow), unit = "%")
                    VRule()
                    CompositionFact(L("7D HIGH"), fat(plot.windowHigh), unit = "%")
                }
                RollingPills.month -> {
                    CompositionFact(L("NOW"), fat(plot.now), unit = "%")
                    VRule()
                    CompositionFact(L("30D LOW"), fat(plot.windowLow), unit = "%")
                    VRule()
                    CompositionFact(L("30D HIGH"), fat(plot.windowHigh), unit = "%")
                }
            }
        }
    }
}

private fun dayCaption(reading: CompositionDayReading?): String = when {
    reading == null -> L("No body scan yet. A finished 30-second scan writes the first row.")
    reading.previous == null -> L("This is the first scan on this account. There is no previous row to compare.")
    else -> L("A single scan cannot make a line. The last scan is the reference.")
}

private fun lastScanAge(reading: CompositionDayReading?): Pair<String, String?> {
    val previous = reading?.previous ?: return Fmt.dash to null
    val current = reading.current
    val zone = currentZone()
    val days = ChronoUnit.DAYS.between(
        previous.at.atZone(zone).toLocalDate(), current.at.atZone(zone).toLocalDate(),
    ).toInt()
    if (days <= 0) return Fmt.clock(previous.at) to null
    return "$days" to L("D AGO")
}

// MARK: lists

@Composable
private fun DayDeltaCard(reading: CompositionDayReading) {
    data class Item(val name: String, val field: CompositionFieldDelta, val unit: String, val highlight: Boolean)
    val rows = listOf(
        Item(L("BODY FAT"), reading.bodyFat, "%", true),
        Item(L("FAT MASS"), reading.fatMass, "KG", false),
        Item(L("LEAN MASS"), reading.leanMass, "KG", false),
        Item(L("BMR ESTIMATE"), reading.bmr, "KCAL/DAY", false),
        Item(L("INPUT WEIGHT"), reading.inputWeight, "KG", false),
    )
    ListColumn {
        ListHead(
            left = reading.previous?.let { L("VS %@", "${Fmt.weekday(it.at)} ${Fmt.clock(it.at)}") } ?: L("THIS SCAN"),
            right = L("5 FIELDS"),
        )
        for (row in rows) {
            Hairline()
            CompositionDeltaRow(
                name = row.name,
                before = number(row.field.before, row.unit),
                now = number(row.field.now, row.unit),
                delta = signed(row.field.delta, if (row.unit == "%") "PT" else row.unit),
                highlight = row.highlight,
            )
        }
    }
}

@Composable
private fun ScanRows(windowScans: List<CompositionScan>, scans: List<CompositionScan>, from: Instant, to: Instant) {
    val ordered = windowScans.sortedByDescending { it.at }
    ListColumn {
        ListHead(L("EVERY SCAN"), L("NEWEST FIRST"))
        if (ordered.isEmpty()) {
            Hairline()
            T(L("No body scan in this window yet."), NBFont.ui(300, 13f), NB.text3Prod,
                Modifier.padding(vertical = 14.dp), maxLines = Int.MAX_VALUE)
        } else {
            ordered.forEachIndexed { index, scan ->
                Hairline()
                val older = if (index + 1 < ordered.size) ordered[index + 1] else null
                val nowFat = scan.bodyFatPercent
                val thenFat = older?.bodyFatPercent
                val delta = if (nowFat != null && thenFat != null) nowFat - thenFat else null
                CompositionScanRow(
                    label = "${Fmt.weekday(scan.at)} ${Fmt.clock(scan.at)}",
                    value = fat(scan.bodyFatPercent),
                    unit = "%",
                    delta = if (older == null) "—" else signed(delta, "PT"),
                    newest = index == 0,
                )
            }
            Hairline()
            Footnote(CompositionWindowMath.inWindow(scans, from = from, to = to))
        }
    }
}

@Composable
private fun WeekRows(buckets: List<com.nextbody.hoop.band.CompositionWeekBucket>, windowScans: List<CompositionScan>) {
    ListColumn {
        ListHead(L("WEEK AVERAGES"), L("NEWEST FIRST"))
        buckets.forEachIndexed { index, bucket ->
            Hairline()
            CompositionScanRow(
                label = weekLabel(bucket.offset),
                value = fat(bucket.averageFat),
                unit = "%",
                delta = if (bucket.offset + 1 >= buckets.size) "—" else signed(bucket.delta, "PT"),
                newest = index == 0,
            )
        }
        Hairline()
        Footnote(windowScans)
    }
}

/** A list section: content width, a hairline over its top edge. */
@Composable
private fun ListColumn(content: @Composable () -> Unit) {
    Box(Modifier.width(NB.Layout.contentWidth)) {
        Column(Modifier.fillMaxWidth()) { content() }
        Hairline(modifier = Modifier.align(Alignment.TopCenter))
    }
}

@Composable
private fun ListHead(left: String, right: String) {
    Row(Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 12.dp)) {
        T(left, NBFont.dot(600, 10f).tracking(0.2f), NB.white.copy(alpha = 0.60f), Modifier.alignByBaseline().weight(1f))
        Spacer(Modifier.width(16.dp))
        T(right, NBFont.dot(600, 10f).tracking(0.16f), NB.white.copy(alpha = 0.60f), Modifier.alignByBaseline())
    }
}

@Composable
private fun Footnote(scans: List<CompositionScan>) {
    val fat = CompositionWindowMath.span({ it.fatMassKg }, scans)
    val lean = CompositionWindowMath.span({ it.leanMassKg }, scans)
    val bmr = CompositionWindowMath.span({ it.bmrKcal }, scans)
    val parts = listOfNotNull(
        arrow(L("FAT MASS"), fat, "kg"),
        arrow(L("LEAN MASS"), lean, "kg"),
        arrow(L("BMR ESTIMATE"), bmr, "kcal/day"),
    )
    Column(
        Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        T(L("SAME WINDOW"), NBFont.dot(600, 9f).tracking(0.2f), NB.white.copy(alpha = 0.34f))
        T(if (parts.isEmpty()) L("No other fields in this window.") else parts.joinToString(" · "),
            NBFont.ui(300, 11f), NB.text3Prod, maxLines = Int.MAX_VALUE)
    }
}

private fun arrow(name: String, span: CompositionSpan, unit: String): String? {
    val last = span.last ?: return null
    val first = span.first
    if (first != null && first != last) return "$name ${fmt(first, unit)} → ${fmt(last, unit)} $unit"
    return "$name ${fmt(last, unit)} $unit"
}

private fun weekLabel(offset: Int): String = when (offset) {
    0 -> L("THIS WEEK")
    1 -> L("LAST WEEK")
    else -> L("%d WKS AGO", offset)
}

// MARK: number formatting

private fun fat(value: Double?): String = value?.let { swiftFormat("%.1f", it) } ?: Fmt.dash

private fun signOf(value: Double): String = if (value < 0) "−" else if (value > 0) "+" else ""

private fun signedNumber(value: Double?): String {
    if (value == null) return Fmt.dash
    return "${signOf(value)}${swiftFormat("%.1f", abs(value))}"
}

private fun signed(value: Double?, unit: String): String {
    if (value == null) return "—"
    if (unit == "KCAL") return "${signOf(value)}${value.rounded().toInt()} $unit"
    return "${signOf(value)}${swiftFormat("%.1f", abs(value))} $unit"
}

private fun number(value: Double?, unit: String): String {
    if (value == null) return Fmt.dash
    if (unit == "KCAL") return "${value.rounded().toInt()}"
    return swiftFormat("%.1f", value)
}

private fun fmt(value: Double, unit: String): String =
    if (unit == "kcal") "${value.rounded().toInt()}" else swiftFormat("%.1f", value)

// MARK: pieces

private data class CompositionAxisLabel(val text: String, val dim: Boolean)

/** One line of styled text, SwiftUI `Text` defaults (one line unless told otherwise). */
@Composable
private fun T(text: String, style: TextStyle, color: Color, modifier: Modifier = Modifier, maxLines: Int = 1) {
    Text(
        text = text, modifier = modifier, style = style, color = color, maxLines = maxLines,
        overflow = TextOverflow.Ellipsis, softWrap = maxLines > 1,
    )
}

/** An HStack of facts split by full-height hairlines. */
@Composable
private fun FactStrip(content: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), content = content)
}

@Composable
private fun VRule() {
    Box(Modifier.width(1.dp).fillMaxHeight().background(NB.hairline))
}

@Composable
private fun RowScope.CompositionFact(label: String, value: String, unit: String? = null, valueTint: Color = NB.text1) {
    Column(
        Modifier.weight(1f).padding(vertical = 14.dp, horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        T(label, NBFont.ui(500, 10f).tracking(0.16f), NB.text3Prod)
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            T(value, NBFont.dot(700, 20f), valueTint, Modifier.alignByBaseline())
            if (unit != null) T(unit, NBFont.dot(500, 10f), NB.white.copy(alpha = 0.45f), Modifier.alignByBaseline())
        }
    }
}

@Composable
private fun CompositionTrendChart(plot: CompositionPlot, labels: List<CompositionAxisLabel>, height: Dp = 148.dp) {
    Canvas(Modifier.fillMaxWidth().height(height).clearAndSetSemantics {}) {
        val w = size.width
        val h = size.height
        val px = 1.dp.toPx()
        val spanY = max(0.001, plot.yMax - plot.yMin)
        fun y(value: Double): Float {
            val clamped = min(plot.yMax, max(plot.yMin, value))
            return ((plot.yMax - clamped) / spanY).toFloat() * (h - 2 * px) + px
        }
        fun x(fraction: Double): Float = min(1.0, max(0.0, fraction)).toFloat() * (w - 6 * px) + 3 * px
        fun point(p: CompositionPoint): Offset = Offset(x(p.x), y(p.value))

        val ticks = max(2, labels.size)
        for (i in 0 until ticks) {
            val at = x(i.toDouble() / (ticks - 1).toDouble())
            drawLine(NB.white.copy(alpha = 0.06f), Offset(at, 0f), Offset(at, h), strokeWidth = px)
        }

        val low = plot.bandLow
        val high = plot.bandHigh
        if (low != null && high != null) {
            val top = y(high)
            val bottom = y(low)
            drawRect(NB.lime1.copy(alpha = 0.10f), Offset(0f, top),
                androidx.compose.ui.geometry.Size(w, max(2 * px, bottom - top)))
        }
        plot.median?.let { median ->
            drawLine(NB.white.copy(alpha = 0.16f), Offset(0f, y(median)), Offset(w, y(median)),
                strokeWidth = px, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3 * px, 3 * px)))
        }

        val lastAt = plot.points.lastOrNull()?.at
        for (run in plot.runs) {
            val first = run.firstOrNull() ?: continue
            val path = Path()
            val p0 = point(first)
            path.moveTo(p0.x, p0.y)
            for (item in run.drop(1)) { val p = point(item); path.lineTo(p.x, p.y) }
            if (run.size == 1) path.lineTo(p0.x + 0.5f * px, p0.y)
            drawPath(path, NB.lime1, style = Stroke(width = 1.8f * px, cap = StrokeCap.Round, join = StrokeJoin.Round))
            for (item in run) {
                val r = (if (item.at == lastAt) 3.5f else 2.5f) * px
                drawCircle(NB.lime1, radius = r, center = point(item))
            }
        }
    }
}

@Composable
private fun CompositionScaleRail(labels: List<String>, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.width(28.dp).clearAndSetSemantics {}) {
        val h = maxHeight
        labels.forEachIndexed { i, label ->
            val fraction = if (labels.size > 1) i.toFloat() / (labels.size - 1) else 0f
            T(label, NBFont.dot(600, 9f).tracking(0.06f), NB.white.copy(alpha = 0.45f),
                Modifier.offset(y = h * fraction - 6.dp))
        }
    }
}

@Composable
private fun CompositionDeltaRow(name: String, before: String, now: String, delta: String, highlight: Boolean = false) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        T(name, NBFont.ui(500, 12f).tracking(0.02f), if (highlight) NB.text1 else NB.text2,
            Modifier.width(80.dp).alignByBaseline(), maxLines = Int.MAX_VALUE)
        T(before, NBFont.dot(500, 12f), NB.white.copy(alpha = 0.34f), Modifier.alignByBaseline())
        T("→", NBFont.dot(500, 12f), NB.white.copy(alpha = 0.20f), Modifier.alignByBaseline())
        T(now, NBFont.dot(700, 15f), NB.text1, Modifier.alignByBaseline())
        Spacer(Modifier.weight(1f))
        T(delta, NBFont.dot(600, 11f).tracking(0.1f), if (highlight) NB.lime1 else NB.text2, Modifier.alignByBaseline())
    }
}

@Composable
private fun CompositionScanRow(label: String, value: String, unit: String, delta: String, newest: Boolean = false) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        T(label, NBFont.ui(500, 12f).tracking(0.02f), if (newest) NB.text1 else NB.text2,
            Modifier.width(92.dp).alignByBaseline())
        Row(Modifier.alignByBaseline(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            T(value, NBFont.dot(700, 15f), NB.text1, Modifier.alignByBaseline())
            T(unit, NBFont.dot(500, 10f), NB.white.copy(alpha = 0.45f), Modifier.alignByBaseline())
        }
        Spacer(Modifier.weight(1f))
        T(delta, NBFont.dot(600, 11f).tracking(0.1f), if (newest) NB.lime1 else NB.text2, Modifier.alignByBaseline())
    }
}

/**
 * The 30×26 chevron disc a date pager uses (`PagerButton` lives in CompositionDetailView.swift
 * and FuelDetailView borrows it). Public so the Fuel page can share it.
 */
@Composable
fun PagerButton(forward: Boolean, enabled: Boolean, action: () -> Unit) {
    Box(
        Modifier.size(width = 30.dp, height = 26.dp)
            .hotZoneTap(enabled = enabled, pressedOpacity = 0.72f, pressedScale = 1f) { action() },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(26.dp).background(hex(0x141418), CircleShape))
        Canvas(Modifier.size(width = 6.dp, height = 10.dp)) {
            val u = 1.dp.toPx()
            val path = Path()
            if (forward) {
                path.moveTo(1 * u, 1 * u); path.lineTo(5 * u, 5 * u); path.lineTo(1 * u, 9 * u)
            } else {
                path.moveTo(5 * u, 1 * u); path.lineTo(1 * u, 5 * u); path.lineTo(5 * u, 9 * u)
            }
            drawPath(path, if (enabled) hex(0x8A8A96) else hex(0x5A5A66),
                style = Stroke(width = 1.5f * u, cap = StrokeCap.Square))
        }
    }
}
