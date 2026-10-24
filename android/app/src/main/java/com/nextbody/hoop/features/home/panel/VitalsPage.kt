package com.nextbody.hoop.features.home.panel

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.band.ActiveEnergyMath
import com.nextbody.hoop.band.MealResponseIndex
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.band.VitalsClock
import com.nextbody.hoop.band.VitalsTimelinePolicy
import com.nextbody.hoop.band.VitalsTimelineRange
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.LiveVitals
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.bodybattery.BatteryCurve
import com.nextbody.hoop.features.vitals.ActiveEnergyModel
import com.nextbody.hoop.features.vitals.LivedHourBars
import com.nextbody.hoop.features.vitals.MealResponsePresentation
import com.nextbody.hoop.features.vitals.SkinTempPresentation
import com.nextbody.hoop.features.vitals.VitalsMetric
import com.nextbody.hoop.features.vitals.tint
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.SleepScore
import com.nextbody.hoop.model.SleepSummary
import com.nextbody.hoop.model.TickFreshness
import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.delay
import java.time.Instant
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * One of the eight page-two hot zones. Seven open a vitals board;
 * Body Battery opens the same reserve page Profile and the morning widget use.
 */
sealed class PageTwoCard {
    data class Vitals(val metric: VitalsMetric) : PageTwoCard()
    data object BodyBattery : PageTwoCard()

    val cardKey: String
        get() = when (this) {
            is Vitals -> metric.cardKey
            BodyBattery -> "BODY_BATTERY"
        }

    val destination: Destination
        get() = when (this) {
            is Vitals -> Destination.Vitals(metric)
            BodyBattery -> Destination.BodyBattery
        }
}

/**
 * 04C · PAGE TWO · 往右一滑是仪表，不是判断. Eight of the strip's own 174-wide cards:
 * SLEEP · HEART / BODY BATTERY · STRESS / TEMP · STEPS / DISTANCE · ACTIVE. Night HRV
 * lives on the sleep page. RESPONSE is no longer a page-two card; `vitals.response` still
 * deep-links to that board. No dock, no buttons, no adjectives — and not one read of the band.
 *
 * [height] is the height the root frames the page to (panel top → over the dots' lane). The
 * cards grow into it: row gaps stay a constant 10 and the card height takes the rest.
 * Every card is a hot zone ([hotZoneTap]) opening its own second level through [onOpen].
 */
@Composable
fun VitalsPage(
    m: DailyMetrics,
    history: List<DailyMetrics>,
    vitals: LiveVitals,
    sleepScore: SleepScore? = null,
    width: Dp = NB.Layout.contentWidth,
    height: Dp = 585.dp,
    onOpen: (PageTwoCard) -> Unit,
) {
    // 04B rule 01 · the card is a fixed 174 wide; its height is whatever the phone leaves
    // after the foot (12 + 12) and three row gaps of 10.
    val cardHeight = (height - 12.dp - 12.dp - NB.Layout.cardGap * 3) / 4
    val freshness = vitals.freshness
    // 04B rule 05 · one source for "now": the last tick. 90 minutes on it dims to 45 %,
    // six hours turns the number itself into ——.
    val dim = if (freshness == TickFreshness.stale) 0.45f else 1f
    val gone = freshness == TickFreshness.gone
    val p = PageTwo(m, history, vitals, sleepScore, cardHeight, dim, gone)

    Column(
        modifier = Modifier
            .width(width)
            .height(height)
            .semantics { contentDescription = L("Vitals, page two") },
    ) {
        Column(
            modifier = Modifier.weight(1f).padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(NB.Layout.cardGap),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(NB.Layout.cardGap)) {
                Zone(PageTwoCard.Vitals(VitalsMetric.sleep), onOpen) { p.SleepCard() }
                Zone(PageTwoCard.Vitals(VitalsMetric.heart), onOpen) { p.HeartCard() }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(NB.Layout.cardGap)) {
                Zone(PageTwoCard.BodyBattery, onOpen) { p.BodyBatteryCard() }
                Zone(PageTwoCard.Vitals(VitalsMetric.stress), onOpen) { p.StressCard() }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(NB.Layout.cardGap)) {
                Zone(PageTwoCard.Vitals(VitalsMetric.temp), onOpen) { p.TempCard() }
                Zone(PageTwoCard.Vitals(VitalsMetric.steps), onOpen) { p.StepsCard() }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(NB.Layout.cardGap)) {
                Zone(PageTwoCard.Vitals(VitalsMetric.distance), onOpen) { p.DistanceCard() }
                Zone(PageTwoCard.Vitals(VitalsMetric.active), onOpen) { ActiveEnergyCard(m = m, height = cardHeight) }
            }
        }
        // 04B · LAST TICK 22:29 · 12 MIN AGO · 1H 05M OFF WRIST, pinned to the foot. The page
        // dots are the root's furniture, crossfading in the lane below this line (rule 02).
        Box(Modifier.width(width), contentAlignment = Alignment.Center) {
            ShrinkText(
                p.footLine(),
                NBFont.dot(500, 9.5f).tracking(0.12f).copy(color = NB.white.copy(alpha = 0.38f)),
                minScale = 0.85f,
            )
        }
    }
}

/** ADR-0001 · a card presses like the strip's do: the tap retires past the slop, so the page
 *  drag underneath always wins a swipe. */
@Composable
private fun Zone(slot: PageTwoCard, onOpen: (PageTwoCard) -> Unit, card: @Composable () -> Unit) {
    Box(Modifier.testTag(slot.cardKey).hotZoneTap { onOpen(slot) }) { card() }
}

/** The page's per-render inputs, so each card reads like the Swift computed properties. */
private class PageTwo(
    val m: DailyMetrics,
    val history: List<DailyMetrics>,
    val vitals: LiveVitals,
    val sleepScore: SleepScore?,
    val cardHeight: Dp,
    val dim: Float,
    val gone: Boolean,
) {
    val day: UserDay get() = m.day
    val ticks: List<VitalSample> get() = m.vitalsCurve

    /** ADR 0008 · the score takes the main position and the duration rides beside it as the
     *  unit. The stage strip is drawn only when the band filed a real stage line. */
    @Composable
    fun SleepCard() {
        val night = m.sleep
        val score = sleepScore
        val duration = night?.let { Fmt.duration(it.totalMinutes) }
        val hasLine = night?.line?.isNotEmpty() == true
        InstrumentCard(
            label = L("SLEEP"), tag = L("LAST NIGHT"), tint = NB.violet1,
            height = cardHeight,
            value = score?.let { it.score.toString() } ?: duration,
            unit = if (score == null) (if (night == null) null else L("ASLEEP")) else duration,
            foot = sleepFoot(night, score),
            valueTint = score?.tint,
        ) {
            if (hasLine && night != null) SleepStrip(sleep = night, tint = NB.violet1)
        }
    }

    private fun sleepFoot(night: SleepSummary?, score: SleepScore?): String {
        if (night == null) return L("NO NIGHT YET")
        if (score == null) return L("SCORE NOT SETTLED YET")
        // The calibration note lives here until the baselines are this person's own.
        if (score.isCalibrating) return L("TYPICAL-ADULT BASELINE")
        val start = night.sleepStart
        val wake = night.wakeAt
        if (start != null && wake != null && wake > start) {
            return L("BED %@ · WAKE %@", Fmt.clock(start), Fmt.clock(wake))
        }
        return L("WINDOW NOT ON RECORD")
    }

    @Composable
    fun HeartCard() {
        val peak = m.peakHR ?: ticks.mapNotNull { it.hr }.maxOrNull()
        val resting = m.nightInputs?.rhr?.let { it.rounded().toInt() }
        // The newest tick often has steps or MET and no PPG. The number is the last heart
        // reading in the same 24h window the spark is drawn from.
        val samples = VitalSample.today(
            VitalSample.merging(history.flatMap { it.vitalsCurve }, ticks), Instant.now())
        val latest = if (gone) null else (vitals.hr ?: samples.lastOrNull { it.hr != null }?.hr)
        // 04B F5 · DAY ONE. No tick has ever landed: the number is ——, the curve is not drawn.
        val dayOne = vitals.at == null && ticks.isEmpty()
        InstrumentCard(
            label = L("HEART"), tag = L("NOW"), tint = NB.lime1,
            height = cardHeight,
            value = latest?.toString(), unit = "BPM",
            foot = L("RESTING %@ · PEAK %@", Fmt.int(resting), Fmt.int(peak)),
            dim = dim,
            // 04B F3 · GONE keeps the unit, greyed with the dash.
            unitWhenEmpty = gone && !dayOne,
            status = if (dayOne) ("NO TICKS YET" to "FIRST SYNC DRAWS IT") else null,
        ) {
            DaySpark(samples = ticks, day = day, value = { it.hr?.toDouble() }, low = 40.0, high = 160.0, tint = NB.lime1)
        }
    }

    @Composable
    fun BodyBatteryCard() {
        // TimelineView(.periodic(by: 60))
        val now by produceState(Instant.now()) {
            while (true) { delay(60_000); value = Instant.now() }
        }
        val forceEmpty = DebugEdgeFlag.on("empty")
        val freshness = m.bodyBatteryFreshness(now)
        val value = if (forceEmpty) null else m.bodyBatteryForDisplay(now)
        val stale = freshness != TickFreshness.fresh
        val observedAt = m.bodyBatteryObservedAt
        val empty = forceEmpty || (value == null && observedAt == null)
        val status = if (empty) (L("NO TICKS YET") to L("FIRST SYNC DRAWS IT")) else null
        val morning = m.bbWake
        val foot = when {
            empty -> L("NO RECENT READINESS READING")
            value == null && observedAt != null -> L("NOT WORN SINCE %@ · NO CURRENT READING", Fmt.clock(observedAt))
            stale && observedAt != null -> L("SYNCED %@", Fmt.clock(observedAt))
            morning != null -> L("MORNING %d", morning)
            else -> L("FROM WRIST DATA")
        }
        InstrumentCard(
            label = MetricNames.bodyBattery, tag = L("NOW"), tint = NB.lime1,
            height = cardHeight,
            value = value?.toString(), unit = null,
            foot = foot,
            dim = if (stale) 0.45f else 1f,
            status = status,
        ) {
            BatteryCurve(samples = m.reserveCurve, day = m.day, dim = stale, compact = true, modifier = Modifier.fillMaxSize())
        }
    }

    @Composable
    fun StressCard() {
        val now = Instant.now()
        val window = VitalsTimelinePolicy.today(now)
        val samples = VitalSample.today(
            VitalSample.merging(history.flatMap { it.vitalsCurve }, ticks), now)
        val bins = VitalsMath.halfHourMean(samples, window) { it.stress?.toDouble() }
        val peak = VitalsMath.peak(bins)
        // The newest tick often has heart from PPG and no stress: the number is the last
        // stress reading in the same today window the bars are drawn from.
        val latest = if (gone) null else (vitals.stress ?: samples.lastOrNull { it.stress != null }?.stress)
        InstrumentCard(
            label = L("STRESS"), tag = L("TODAY"), tint = NB.ember1,
            height = cardHeight,
            value = latest?.toString(), unit = L("/100 NOW"),
            foot = peak?.let {
                L("PEAK %d AT %@", it.value.rounded().toInt(),
                    Fmt.clock(window.start.addingTimeInterval((it.index * 30 * 60).toDouble())))
            } ?: L("NO TICKS YET"),
            dim = dim, unitWhenEmpty = gone,
        ) {
            FineBars(values = bins, tint = NB.ember1, highlight = { it > 60 })
        }
    }

    @Composable
    fun TempCard() {
        val window = VitalsTimelinePolicy.today(Instant.now())
        val samples = VitalSample.merging(history.flatMap { it.vitalsCurve }, ticks)
            .filter { window.contains(it.ts) }
        val last = if (gone) null else samples.lastOrNull { it.temp != null }?.temp
        // ADR 0009 · the glance carries last night's verdict. The spark is ruled by this
        // wrist's own range, never by 35.5–37.0 °C — that is a core-temperature ruler.
        val night = SkinTempPresentation.nightRange(today = m, history = history)
        val axis = SkinTempPresentation.axis(night.range, pad = 1.0)
        val delta = night.delta
        val tier = night.tier
        val emptyReason = night.empty
        val foot = when {
            delta != null && tier != null -> L("LAST NIGHT %+.1f · %@", delta, SkinTempPresentation.shortTier(tier))
            emptyReason != null -> SkinTempPresentation.reason(emptyReason, learningNights = night.learningNights)
            else -> L("NO TICKS YET")
        }
        InstrumentCard(
            label = L("TEMP"), tag = L("NOW"), tint = NB.cyan1,
            height = cardHeight,
            value = last?.let { swiftFormat("%.1f", it) }, unit = L("°C SKIN"),
            foot = foot,
            dim = dim, unitWhenEmpty = gone,
        ) {
            DaySpark(samples = samples, day = day, value = { it.temp },
                low = axis.start, high = axis.endInclusive, tint = NB.cyan1, range = window)
        }
    }

    @Composable
    fun StepsCard() {
        val bins = VitalsMath.hourSum(ticks, day) { it.steps?.toDouble() }
        val total = m.steps?.toDouble() ?: VitalsMath.total(bins)
        val peak = VitalsMath.peak(bins)
        InstrumentCard(
            label = L("STEPS"), tag = L("TODAY"), tint = NB.optimal2,
            height = cardHeight,
            value = total?.let { Fmt.kcal(it) }, unit = null,
            foot = peak?.let { L("PEAK %@ AT %@", Fmt.kcal(it.value), VitalsMath.clock(day, it.index * 60)) }
                ?: L("NO TICKS YET"),
        ) {
            HourBars(values = bins, tint = NB.optimal2)
        }
    }

    @Composable
    fun DistanceCard() {
        val bins = VitalsMath.hourSum(ticks, day) { it.dis }
        val metres = m.distanceM?.toDouble() ?: VitalsMath.total(bins)
        val peak = VitalsMath.peak(bins)
        InstrumentCard(
            label = L("DISTANCE"), tag = L("TODAY"), tint = NB.violetPink,
            height = cardHeight,
            value = metres?.let { swiftFormat("%.1f", it / 1000) }, unit = "KM",
            foot = peak?.let { L("%.1f KM AT %@", it.value / 1000, VitalsMath.clock(day, it.index * 60)) }
                ?: L("NO TICKS YET"),
        ) {
            HourBars(values = bins, tint = NB.violetPink)
        }
    }

    fun footLine(): String {
        val at = vitals.at ?: return L("NO TICKS YET · FIRST SYNC DRAWS THE LINE")
        val age = VitalsMath.age(at)
        var line = if (vitals.freshness == TickFreshness.stale) L("SYNCED %@ · %@", Fmt.clock(at), age)
        else L("LAST TICK %@ · %@", Fmt.clock(at), age)
        // 04B rule 04 · gaps of an hour or more are named once, here, never on a card.
        val gap = VitalsMath.offWrist(ticks)
        if (gap != null && gap.minutes >= 60) line += L(" · %@ OFF WRIST", Fmt.duration(gap.minutes))
        return line
    }
}

/**
 * `VitalsPage.cardStates` — 04C · PAGE2_CARD_STATE{CARD,STATE}. RESPONSE stays in the map so
 * a `vitals.response` deep link can still join against the same key.
 */
object VitalsPage {
    fun cardStates(
        m: DailyMetrics,
        vitals: LiveVitals,
        history: List<DailyMetrics> = emptyList(),
        mealResponsePoints: List<MealResponseIndex.Point> = emptyList(),
        mealResponseZerosToday: Boolean = false,
    ): Map<String, String> {
        fun nowCard(value: Boolean): String {
            if (vitals.at == null) return "EMPTY"
            return when (vitals.freshness) {
                TickFreshness.gone -> "GONE"
                TickFreshness.stale -> if (value) "STALE" else "EMPTY"
                TickFreshness.fresh -> if (value) "FRESH" else "EMPTY"
            }
        }
        val day = m.day
        val ticks = m.vitalsCurve
        val rolling = VitalSample.today(
            VitalSample.merging(history.flatMap { it.vitalsCurve }, ticks), Instant.now())
        val steps = m.steps?.toDouble() ?: VitalsMath.total(VitalsMath.hourSum(ticks, day) { it.steps?.toDouble() })
        val metres = m.distanceM?.toDouble() ?: VitalsMath.total(VitalsMath.hourSum(ticks, day) { it.dis })
        val kcal = ActiveEnergyMath.totals(bmr = m.bmr, eActive = m.eActive, eTrain = m.eTrain, eOutNow = m.eOutNow).active
        val battery = when (m.bodyBatteryFreshness()) {
            TickFreshness.gone -> if (m.bodyBatteryObservedAt == null) "EMPTY" else "GONE"
            TickFreshness.stale -> "STALE"
            TickFreshness.fresh -> if (m.bodyBattery != null) "FRESH" else "EMPTY"
        }
        return mapOf(
            "SLEEP" to (if (m.sleep == null) "EMPTY" else "FRESH"),
            "HEART" to nowCard(vitals.hr != null || rolling.any { it.hr != null }),
            "BODY_BATTERY" to battery,
            "RESPONSE" to MealResponsePresentation.index(today = m, history = history, points = mealResponsePoints,
                zerosToday = mealResponseZerosToday).analyticsState,
            "STRESS" to nowCard(vitals.stress != null || rolling.any { it.stress != null }),
            // Which night-range state the card is actually in, not just whether a tick arrived.
            "TEMP" to SkinTempPresentation.nightRange(today = m, history = history).analyticsState,
            "STEPS" to (if (steps == null) "EMPTY" else "FRESH"),
            "DISTANCE" to (if (metres == null) "EMPTY" else "FRESH"),
            "ACTIVE" to (if (kcal == null) "EMPTY" else "FRESH"),
        )
    }
}

/** 174-wide ACTIVE ENERGY card. */
@Composable
fun ActiveEnergyCard(m: DailyMetrics, height: Dp) {
    val now = minOf(VitalsClock.now, minOf(m.asOf ?: VitalsClock.now, m.day.end))
    val model = ActiveEnergyModel.make(m = m, now = now, history = emptyList())
    val split = model.split
    val kcal = split.active
    val foot = if (kcal == null) L("WAITING FOR VERIFIED ENERGY")
    else L("%@ + %@ = %@", Fmt.kcal(split.resting), Fmt.kcal(split.active), Fmt.kcal(split.out))
    val hint = model.peak?.let {
        L("PEAK %@ · %@ + %@ = %@",
            VitalsMath.clock(m.day, it.index * 60),
            Fmt.kcal(split.resting), Fmt.kcal(split.active), Fmt.kcal(split.out))
    }
    InstrumentCard(
        label = L("ACTIVE ENERGY"), tag = L("TODAY"), tint = NB.lime1,
        height = height,
        value = kcal?.let { Fmt.kcal(it) }, unit = "KCAL",
        foot = foot,
        spokenHint = hint,
    ) {
        LivedHourBars(hours = model.hours, tint = NB.lime1, height = 28.dp)
    }
}

/**
 * 04B rule 03 · a card is a label, a tag, a number, a chart and a foot. Only the tag, the
 * number and the chart take the card's colour; the rest stays the strip's own white-grey.
 *
 * [height]: the strip's cards are the fixed 136; page two's grow into what the phone leaves.
 * [unitWhenEmpty]: 04B F3 · GONE — the number is —— but the unit stays, greyed with it.
 * [valueTint]: ADR 0008 · the numeral alone may take a colour of its own.
 * [status]: 04B F1 / F5 · the two-line state foot; replaces the chart and the foot.
 */
@Composable
fun InstrumentCard(
    label: String,
    tag: String,
    tint: Color,
    height: Dp = NB.Layout.stripHeight,
    value: String?,
    unit: String?,
    foot: String,
    dim: Float = 1f,
    unitWhenEmpty: Boolean = false,
    valueTint: Color? = null,
    status: Pair<String, String>? = null,
    spokenHint: String? = null,
    chart: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(NB.R.card)
    Column(
        modifier = Modifier
            .size(NB.Layout.cardWidth, height)
            .background(NB.carbon4, shape)
            .border(1.dp, NB.hairline, shape)
            .padding(12.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = spokenHint?.let { "$label, $tag, $it" } ?: "$label, $tag"
                stateDescription = status?.let { "${it.first}, ${it.second}" }
                    ?: value?.let { "$it ${unit ?: ""}, $foot" } ?: "no data, $foot"
            },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(Modifier.fillMaxWidth()) {
                ShrinkText(label, NBFont.ui(500, 11f).tracking(0.2f).copy(color = NB.text3Prod),
                    Modifier.alignByBaseline())
                Spacer(Modifier.weight(1f))
                ShrinkText(tag, NBFont.dot(700, 12f).tracking(0.04f).copy(color = if (value == null) NB.text3Prod else tint),
                    Modifier.alignByBaseline().alpha(dim))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                // F2 rule 05 · a number that is not there is ——, never 0.
                ShrinkText(
                    value ?: Fmt.dash,
                    NBFont.dot(700, 26f).tracking(-0.02f)
                        .copy(color = if (value == null) NB.text3Prod else (valueTint ?: tint)),
                    Modifier.alignByBaseline().weight(1f, fill = false).alpha(dim),
                    minScale = 0.8f,
                )
                if (unit != null && (value != null || unitWhenEmpty)) {
                    ShrinkText(unit, NBFont.dot(500, 11f).copy(color = if (value == null) NB.text3Prod else NB.macroValue),
                        Modifier.alignByBaseline().alpha(dim))
                }
            }
        }
        Spacer(Modifier.weight(1f))
        if (status != null) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                ShrinkText(status.first, NBFont.dot(600, 10f).tracking(0.14f).copy(color = NB.white.copy(alpha = 0.55f)))
                ShrinkText(status.second, NBFont.dot(500, 10f).tracking(0.05f).copy(color = NB.macroValue), minScale = 0.8f)
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.fillMaxWidth().height(28.dp).alpha(dim)) { chart() }
                ShrinkText(foot, NBFont.dot(500, 10f).tracking(0.05f).copy(color = NB.macroValue), minScale = 0.8f)
            }
        }
    }
}

/** 04 · 04B · the two 4 pt page dots. The current page is the bright one. */
@Composable
fun PageDots(current: Int, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(2) { i ->
            Box(Modifier.size(4.dp).background(NB.white.copy(alpha = if (i == current) 0.72f else 0.24f), CircleShape))
        }
    }
}

// MARK: charts · 148 × 28 in the board. Each one fills the size its caller gives it.

/**
 * A day of one tick series, midnight → midnight across the width, y on a fixed scale — the
 * ruler never changes with the day (04B rule 04). A gap in the ticks is a dashed gap in the
 * line, never a straight segment across it; the last tick carries a dot.
 */
@Composable
fun DaySpark(
    samples: List<VitalSample>,
    day: UserDay,
    value: (VitalSample) -> Double?,
    low: Double,
    high: Double,
    tint: Color,
    range: VitalsTimelineRange? = null,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height
        val d = density
        val span = max(0.001, high - low)
        val origin = range?.start ?: day.start
        val total = max(1.0, range?.span ?: 86_400.0)
        fun point(s: VitalSample, v: Double): Offset {
            val t = min(1.0, max(0.0, s.ts.timeIntervalSince(origin) / total))
            val clamped = min(high, max(low, v))
            val y = h - 2 * d - ((clamped - low) / span * (h - 4 * d)).toFloat()
            return Offset((w * t).toFloat(), y)
        }
        val runs = ArrayList<List<Offset>>()
        var run = ArrayList<Offset>()
        var lastTs: Instant? = null
        for (s in samples) {
            val v = value(s) ?: continue
            // Two ticks more than ten minutes apart were not neighbours on the wrist.
            val prev = lastTs
            if (prev != null && s.ts.timeIntervalSince(prev) > 10 * 60 && run.isNotEmpty()) {
                runs.add(run); run = ArrayList()
            }
            run.add(point(s, v))
            lastTs = s.ts
        }
        if (run.isNotEmpty()) runs.add(run)
        if (runs.isEmpty()) return@Canvas
        runs.forEachIndexed { i, r ->
            val p = Path()
            p.moveTo(r[0].x, r[0].y)
            for (pt in r.drop(1)) p.lineTo(pt.x, pt.y)
            if (r.size == 1) p.lineTo(r[0].x, r[0].y)
            drawPath(p, tint.copy(alpha = 0.85f * tint.alpha),
                style = Stroke(width = 1.5f * d, cap = StrokeCap.Round, join = StrokeJoin.Round))
            if (i + 1 < runs.size) {
                drawLine(tint.copy(alpha = 0.35f), r.last(), runs[i + 1][0], strokeWidth = 1.2f * d,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * d, 2.5f * d)))
            }
        }
        runs.last().lastOrNull()?.let { end -> drawCircle(tint, radius = 2.5f * d, center = end) }
    }
}

/** 24 bars of an hour each across the day. The tallest hour is the bright one; a bin with no
 *  ticks is left empty, never drawn as 0. */
@Composable
fun HourBars(values: List<Double?>, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val n = max(1, values.size)
        val gap = 2 * density
        val w = (size.width - gap * (n - 1)) / n
        val top = values.filterNotNull().maxOrNull() ?: 0.0
        if (top <= 0) return@Canvas
        values.forEachIndexed { i, v ->
            if (v == null || v <= 0) return@forEachIndexed
            val h = max(0.8f * density, (size.height * v / top).toFloat())
            drawRect(tint.copy(alpha = if (v >= top) 1f else 0.4f),
                topLeft = Offset(i * (w + gap), size.height - h), size = Size(w, h))
        }
    }
}

/** 48 half-hour bars. 04B · the bars over 60 are the same colour, only brighter —
 *  intensity is not a semantic colour. */
@Composable
fun FineBars(values: List<Double?>, tint: Color, highlight: (Double) -> Boolean, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val n = max(1, values.size)
        val gap = 1 * density
        val w = (size.width - gap * (n - 1)) / n
        values.forEachIndexed { i, v ->
            if (v == null) return@forEachIndexed
            val h = max(0.8f * density, (size.height * min(1.0, v / 100)).toFloat())
            drawRect(tint.copy(alpha = if (highlight(v)) 1f else 0.4f),
                topLeft = Offset(i * (w + gap), size.height - h), size = Size(w, h))
        }
    }
}

/** Seven nights, tonight brightest, a dashed line at the 14-night base. A night we do not have
 *  is a missing bar; under five nights there is no base and no line (04B rule 06). */
@Composable
fun NightBars(values: List<Double?>, base: Double?, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val present = values.filterNotNull()
        if (present.isEmpty()) return@Canvas
        val d = density
        val lo = min(present.min(), base ?: Double.POSITIVE_INFINITY) - 8
        val hi = max(present.max(), base ?: Double.NEGATIVE_INFINITY) + 4
        val span = max(1.0, hi - lo)
        val w = 8 * d
        val gap = 6 * d
        val n = values.size
        fun y(v: Double): Float = size.height - ((v - lo) / span).toFloat() * size.height
        if (base != null) {
            drawLine(NB.white.copy(alpha = 0.28f), Offset(0f, y(base)), Offset(n * (w + gap) - gap, y(base)),
                strokeWidth = 1 * d, pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * d, 3 * d)))
        }
        values.forEachIndexed { i, v ->
            if (v == null) return@forEachIndexed
            val top = y(v)
            drawRoundRect(tint.copy(alpha = if (i == n - 1) 1f else 0.35f),
                topLeft = Offset(i * (w + gap), top), size = Size(w, size.height - top),
                cornerRadius = CornerRadius(1 * d))
        }
    }
}

/**
 * 04B rule 04 · the night as the band's own sleepLine: deep full height, light half, awake a
 * short mark, in the order the night ran — the app never re-segments it. Only a night stored
 * without a line falls back to the totals laid out in the order nights usually run.
 */
@Composable
fun SleepStrip(sleep: SleepSummary, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val W = size.width
        val H = size.height
        if (sleep.line.isNotEmpty()) {
            val hasOffsets = sleep.line.all { it.offsetMinutes != null }
            val start = sleep.sleepStart
            val wake = sleep.wakeAt
            val recordedSpan = if (start != null && wake != null) wake.timeIntervalSince(start) / 60 else 0.0
            val total = max(1.0,
                if (hasOffsets) max(recordedSpan, (sleep.line.maxOfOrNull { (it.offsetMinutes ?: 0) + it.minutes } ?: 0).toDouble())
                else sleep.line.sumOf { it.minutes }.toDouble())
            var x = 0f
            for (run in sleep.line) {
                if (hasOffsets) x = (W * (run.offsetMinutes ?: 0) / total).toFloat()
                val w = (W * run.minutes / total).toFloat()
                // SDK stages: 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake.
                val (h, a) = when (run.stage) {
                    0 -> H to 0.95f
                    1, 2 -> H * 16 / 28 to 0.45f
                    else -> H * 7 / 28 to 0.3f
                }
                drawRect(tint.copy(alpha = a), topLeft = Offset(x, H - h), size = Size(max(w, 0.8f * density), h))
                x += w
            }
            return@Canvas
        }
        // Fallback for nights stored before the line was kept: deep early, light late.
        val total = max(1, sleep.totalMinutes).toDouble()
        val deep = sleep.deepMinutes / total
        val light = sleep.lightMinutes / total
        val wakes = max(0, min(sleep.wakeCount, 4))
        val segs = mutableListOf(
            Triple(light * 0.2, 16f, 0.45f), Triple(deep * 0.55, 28f, 0.95f), Triple(light * 0.3, 16f, 0.45f),
            Triple(deep * 0.45, 28f, 0.95f), Triple(light * 0.5, 16f, 0.45f),
        )
        val wakeShare = 0.018
        for (k in 0 until wakes) segs.add(min(segs.size, 2 + k * 2), Triple(wakeShare, 7f, 0.3f))
        val sum = segs.sumOf { it.first }
        var x = 0f
        for ((share, hPt, alpha) in segs) {
            val w = (W * share / sum).toFloat()
            val h = hPt * density
            drawRect(tint.copy(alpha = alpha), topLeft = Offset(x, H - h), size = Size(w, h))
            x += w
        }
    }
}

/** The arithmetic behind the eight cards. Nothing here asks the band or the server. */
object VitalsMath {
    /** `(minutes:, from:)` of [offWrist]. */
    data class OffWrist(val minutes: Int, val from: Instant)

    /** Sum of a per-tick value in each hour of the user day; hours with no ticks are null. */
    fun hourSum(samples: List<VitalSample>, day: UserDay, value: (VitalSample) -> Double?): List<Double?> {
        val bins = arrayOfNulls<Double>(24)
        for (s in samples) {
            val v = value(s) ?: continue
            val i = (s.ts.timeIntervalSince(day.start) / 3600).toInt()
            if (i !in 0 until 24) continue
            bins[i] = (bins[i] ?: 0.0) + v
        }
        return bins.toList()
    }

    /** Sum into only the hours actually visible on a detail ruler. A current user day may be
     *  nine hours old, not 24; keeping 24 columns would put its newest bar under a future time. */
    fun hourSum(samples: List<VitalSample>, range: VitalsTimelineRange, value: (VitalSample) -> Double?): List<Double?> {
        val count = max(1, ceil(range.span / 3600).toInt())
        val bins = arrayOfNulls<Double>(count)
        for (sample in samples) {
            if (!range.contains(sample.ts)) continue
            val measured = value(sample) ?: continue
            val elapsed = max(0.0, sample.ts.timeIntervalSince(range.start))
            val index = min(count - 1, (elapsed / 3600).toInt())
            bins[index] = (bins[index] ?: 0.0) + measured
        }
        return bins.toList()
    }

    /** Mean of a per-tick value in each half hour; half hours with no ticks are null. */
    fun halfHourMean(samples: List<VitalSample>, day: UserDay, value: (VitalSample) -> Double?): List<Double?> {
        val sum = DoubleArray(48)
        val n = IntArray(48)
        for (s in samples) {
            val v = value(s) ?: continue
            val dt = s.ts.timeIntervalSince(day.start)
            val i = (dt / 1800).toInt()
            if (i !in 0 until 48) continue
            sum[i] += v; n[i] += 1
        }
        return (0 until 48).map { if (n[it] == 0) null else sum[it] / n[it] }
    }

    fun halfHourMean(samples: List<VitalSample>, range: VitalsTimelineRange, value: (VitalSample) -> Double?): List<Double?> {
        val count = max(1, ceil(range.span / 1800).toInt())
        val sum = DoubleArray(count)
        val n = IntArray(count)
        for (sample in samples) {
            if (!range.contains(sample.ts)) continue
            val measured = value(sample) ?: continue
            val elapsed = max(0.0, sample.ts.timeIntervalSince(range.start))
            val index = min(count - 1, (elapsed / 1800).toInt())
            sum[index] += measured
            n[index] += 1
        }
        return (0 until count).map { if (n[it] == 0) null else sum[it] / n[it] }
    }

    /** `(index:, value:)` of the tallest positive bin. */
    fun peak(bins: List<Double?>): IndexedValue<Double>? {
        var best: IndexedValue<Double>? = null
        bins.forEachIndexed { i, v ->
            if (v != null && v > 0 && (best == null || v > best!!.value)) best = IndexedValue(i, v)
        }
        return best
    }

    fun total(bins: List<Double?>): Double? {
        val present = bins.filterNotNull()
        return if (present.isEmpty()) null else present.sum()
    }

    /** "18:00" for a bin that starts `minute` minutes into the user day. */
    fun clock(day: UserDay, minute: Int): String =
        Fmt.clock(day.start.addingTimeInterval((minute * 60).toDouble()))

    /** "12 MIN AGO" under an hour, "2H 29M AGO" over it. Multiples of one minute, no seconds. */
    fun age(of: Instant, now: Instant = Instant.now()): String {
        val minutes = max(0, (now.timeIntervalSince(of) / 60).toInt())
        return if (minutes < 60) L("%d MIN AGO", minutes) else L("%@ AGO", Fmt.duration(minutes - minutes % 5))
    }

    /** 04B rule 04 · the minutes the band recorded nothing between two ticks that both exist.
     *  Two ticks ten minutes apart are neighbours; anything wider is a gap. */
    fun offWrist(samples: List<VitalSample>): OffWrist? {
        var minutes = 0
        var first: Instant? = null
        var last: Instant? = null
        for (s in samples) {
            if (s.hr == null && s.stress == null) continue
            val l = last
            if (l != null && s.ts.timeIntervalSince(l) > 10 * 60) {
                minutes += (s.ts.timeIntervalSince(l) / 60).toInt() - 5
                if (first == null) first = l
            }
            last = s.ts
        }
        val f = first
        if (minutes <= 0 || f == null) return null
        return OffWrist(minutes, f)
    }
}

/**
 * One-line text with SwiftUI's `.lineLimit(1).minimumScaleFactor(minScale)`: drawn at full size
 * when it fits, scaled down to fit the offered width (never under [minScale]), then clipped.
 * Exposes First/LastBaseline so it can sit in a baseline-aligned row.
 */
@Composable
fun ShrinkText(
    text: String,
    style: TextStyle,
    modifier: Modifier = Modifier,
    minScale: Float = 1f,
) {
    val measurer = rememberTextMeasurer()
    val holder = remember { arrayOfNulls<TextLayoutResult>(1) }
    Layout(
        content = {},
        modifier = modifier
            .semantics { contentDescription = text }
            .drawBehind { holder[0]?.let { drawText(it) } },
    ) { _, c ->
        var r = measurer.measure(text, style, softWrap = false, maxLines = 1)
        if (c.hasBoundedWidth && r.size.width > c.maxWidth) {
            val s = max(minScale, c.maxWidth.toFloat() / r.size.width)
            r = measurer.measure(text, style.copy(fontSize = style.fontSize * s), softWrap = false, maxLines = 1,
                constraints = Constraints(maxWidth = c.maxWidth))
        }
        holder[0] = r
        val w = r.size.width.coerceIn(c.minWidth, c.maxWidth)
        val h = r.size.height.coerceIn(c.minHeight, c.maxHeight)
        layout(w, h, mapOf(FirstBaseline to r.firstBaseline.roundToInt(), LastBaseline to r.lastBaseline.roundToInt())) {}
    }
}
