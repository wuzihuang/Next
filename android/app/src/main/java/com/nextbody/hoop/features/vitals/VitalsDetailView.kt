package com.nextbody.hoop.features.vitals

import com.nextbody.hoop.features.home.panel.VitalsMath
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.MealResponseIndex
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.band.VitalsClock
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.home.panel.VitalsPage
import com.nextbody.hoop.features.training.SegmentedPills
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.OvernightOxygenPoint
import com.nextbody.hoop.model.SleepScore
import com.nextbody.hoop.model.SleepScoreLoadState
import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.roundedInt
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.ui.CardBlock
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.DetailScroll
import com.nextbody.hoop.ui.SectionLabel
import com.nextbody.hoop.ui.hotZoneTap
import java.time.Instant
import kotlin.math.abs
import kotlin.math.max
import kotlinx.coroutines.launch

/**
 * 04 · vitals 二级页 · the second level behind each vitals card on home page two.
 * Body Battery is its own page (`BodyBatteryDetailView`), not this board.
 *
 * One view for eight pages, because the board is one anatomy drawn eight times: the hero,
 * the chart on its fixed ruler, the distribution, the two tiles. What changes between them is
 * the shape of the chart and the arithmetic behind the numbers — and the arithmetic all lives
 * in `VitalsReadout`, which is the only thing on this page that knows what a metric is.
 *
 * ⚠️ 04B rule 09 · not one read of the band happens here. Every number is a tick Body Battery
 * already pulled, a night `sleep_nights` already stored, or a total the server already
 * settled. Opening a detail page must never start a measurement.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VitalsDetailView(metric: VitalsMetric) {
    val data = DataStore
    // ADR 0008 · sleep carries a window switcher. ADR 0012 / 0013 reopen the same three pills.
    var rangeRaw by rememberSaveable(metric) { mutableStateOf(RollingPills.day.raw) }
    // #28 · the sleep page's own entry to correcting a night's start and end.
    var correctingNight by remember { mutableStateOf(false) }

    val m = data.today
    val now = VitalsClock.now
    val minute = now.epochSecond / 60
    val range = RollingPills.parse(rangeRaw)

    // The window's samples are derived from every stored day's curve, and the board reads them
    // twenty-odd times per body. The memo keeps them across recompositions and is rebuilt the
    // moment any input the derivation reads changes, so it can never show a stale window.
    val memo = remember(metric, rangeRaw, m, data.history, data.mealResponsePoints,
        data.mealResponseZerosToday, data.sleepScores, minute) {
        VitalsDetailMemo(metric, range, m, data.history, data.mealResponsePoints,
            data.mealResponseZerosToday, data.sleepScores, now)
    }
    val r = memo.readout(data.vitals, data.profile)
    val scope = rememberCoroutineScope()

    // AI tool surface · a detail page that is showing switches its pills and clears the request.
    LaunchedEffect(Router.windowRequest) {
        val request = Router.windowRequest ?: return@LaunchedEffect
        rangeRaw = request
        Router.windowRequest = null
    }
    LaunchedEffect(metric) {
        DetailWindow.debugRange(metric.detailSurface)?.let { rangeRaw = it.raw }
    }
    LaunchedEffect(metric, rangeRaw) {
        // ⚠️ 04B rule 09 still holds: this reads the server's `raw_samples`, not the band.
        // HEART and the five metric windows share one hydrate.
        if (Band.allowsSeed) return@LaunchedEffect
        Repository.hydrate(memo.detail, endingAt = m.day, store = data)
    }
    LaunchedEffect(metric, m.day) {
        if (metric != VitalsMetric.sleep || Band.allowsSeed) return@LaunchedEffect
        Repository.loadSleepScores(days = 30, endingAt = m.day, store = data)
    }
    LaunchedEffect(metric) {
        // The card and the page file the same key, so 「点了哪张卡、看到的是数还是 ——」 is one
        // join rather than two guesses.
        val states = VitalsPage.cardStates(
            m = m, vitals = data.vitals, history = data.history,
            mealResponsePoints = data.mealResponsePoints,
            mealResponseZerosToday = data.mealResponseZerosToday)
        Analytics.track("VITALS_DETAIL_OPEN", mapOf(
            "CARD" to metric.cardKey,
            "STATE" to (states[metric.cardKey] ?: "EMPTY"),
        ))
        if (metric == VitalsMetric.response) {
            Analytics.track("RESPONSE_DETAIL_OPEN", mapOf("STATE" to (states["RESPONSE"] ?: "EMPTY")))
        }
    }

    DetailScroll(
        glow = metric.tint,
        title = metric.title,
        onBack = { Router.backToRoot() },
        trailing = {
            FitText(memo.periodLabel, NBFont.dot(600, 11f).tracking(0.24f), NB.text3Prod, minScale = 0.72f)
        },
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = NB.Layout.gutter).padding(bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            // The switcher sits above the hero because the hero changes with it.
            if (metric.showsDetailPills) {
                SegmentedPills(RollingPills.words, rangeRaw, { rangeRaw = it }, lined = true)
            }
            if (metric == VitalsMetric.sleep) {
                val status = memo.sleepScoreStatus(data.sleepScoreLoadState, data.isOffline)
                if (status != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(status, Modifier.alignBy(FirstBaseline).weight(1f, fill = false),
                            style = NBFont.dot(500, 10f), color = NB.text3Prod)
                        if (data.sleepScoreLoadState == SleepScoreLoadState.failed) {
                            Text(L("RETRY"),
                                Modifier.alignBy(FirstBaseline).hotZoneTap {
                                    scope.launch { Repository.loadSleepScores(days = 30, endingAt = m.day, store = data) }
                                },
                                style = NBFont.dot(600, 10f), color = metric.tint)
                        }
                    }
                }
            }

            val todayScore = memo.todayScore
            if (memo.showsTrendHero) {
                // A rolling window has no single reading, so it leads with its shape: one mark a
                // user day, the median printed once underneath.
                memo.TrendHero(data.sleepScoreLoadState, data.isOffline)
            } else if (metric == VitalsMetric.sleep && todayScore != null) {
                // The card led with the score; the board must not lead with something else.
                VitalsHero(
                    sensor = memo.heroSensor,
                    value = todayScore.score.toString(),
                    unit = if (todayScore.usesContributors) L("OUT OF 100") else r.value ?: L("OUT OF 100"),
                    tint = metric.tint,
                    dial = VitalsReadout.sleepDial(todayScore.score, todayScore.usesContributors),
                    footLeft = if (todayScore.usesContributors) com.nextbody.hoop.model.SleepContributor.rating(todayScore.score.toDouble()) else r.footLeft,
                    footRight = if (todayScore.usesContributors) null else r.footRight,
                )
            } else if (metric == VitalsMetric.active && !memo.isMetricWindow) {
                ActiveEnergyHero(memo.activeModel, memo.heroSensor)
            } else {
                VitalsHero(memo.heroSensor, r.value, r.unit, metric.tint, r.dial, r.footLeft, r.footRight)
            }

            // The score explains itself on the screenful it appears on.
            if (metric == VitalsMetric.sleep && range == RollingPills.day && todayScore != null) {
                if (todayScore.usesContributors) {
                    SleepNightVerdict(todayScore)
                    Column(
                        Modifier.width(NB.Layout.contentWidth).padding(top = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(18.dp),
                    ) {
                        SectionLabel(L("SLEEP CONTRIBUTORS"))
                        SleepContributorBreakdown(todayScore)
                    }
                } else {
                    CardBlock(title = L("SCORE BREAKDOWN"), trailing = L("OUT OF 100")) {
                        SleepScoreBreakdown(todayScore)
                    }
                    CardBlock(title = L("NIGHT DATA COVERAGE")) {
                        SleepScoreCoverage(todayScore)
                    }
                }
            }

            // Oura order — score, then the key metrics, then the details. ACTIVE's day board has
            // no shared pair; sleep's multi-night board labels its own sections.
            if (metric == VitalsMetric.sleep && range == RollingPills.day) {
                SectionLabel(L("KEY METRICS"))
                memo.SleepKeyMetrics(r)
            } else if (metric != VitalsMetric.sleep && !(metric == VitalsMetric.active && !memo.isMetricWindow)) {
                SectionLabel(L("KEY METRICS"))
                VitalsStatPair(r.statLeft, r.statRight)
            }

            if (!(metric == VitalsMetric.sleep && range != RollingPills.day)) {
                SectionLabel(L("DETAILS"))
            }

            if (metric == VitalsMetric.sleep) {
                if (range == RollingPills.day) memo.SleepBoard(r) { correctingNight = true }
                else memo.MultiNightBoard()
            } else if (metric == VitalsMetric.heart) {
                // On a window the hero already drew the pulse's shape; the board keeps only the
                // companions that share its clock.
                HeartBoard(range, memo.window, memo.ticks, memo.heartOxygen, r,
                    memo.heartSlotMinutes, r.dial, showsLead = range == RollingPills.day)
            } else if (metric == VitalsMetric.active && !memo.isMetricWindow) {
                ActiveEnergyBoard(memo.activeModel)
            } else if (!memo.isMetricWindow) {
                CardBlock(title = memo.chartTitle, trailing = r.chartNote) {
                    memo.DayChart(r)
                    if (metric != VitalsMetric.response || range == RollingPills.day) {
                        // The clock is inset by exactly the rail's gutter, or NOW lands under the
                        // ruler instead of under the window's last minute.
                        VitalsAxis(memo.axisLabels, memo.window.endsNow, metric.tint,
                            Modifier.padding(end = if (memo.chartHasScaleRail) VitalsScaleRail.gutter else 0.dp))
                    } else if (range == RollingPills.week) {
                        VitalsAxis(memo.weekAxisLabels, false, metric.tint, Modifier.padding(end = VitalsScaleRail.gutter))
                    }
                    memo.DayChartLegend(r)
                }
            }

            // Sleep owns its own order: the split card is placed inside its board.
            if (metric != VitalsMetric.sleep &&
                (metric != VitalsMetric.heart || range == RollingPills.day) &&
                !(metric == VitalsMetric.active && !memo.isMetricWindow)
            ) {
                CardBlock(title = r.splitTitle, trailing = r.splitTrailing) {
                    VitalsSplit(r.bands)
                }
            }

            memo.Footer(data.sleepScoreLoadState, data.isOffline)
            memo.CorrectNightLine { correctingNight = true }
        }
    }

    if (correctingNight) {
        val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { correctingNight = false },
            sheetState = state,
            containerColor = NB.carbon2,
            contentColor = NB.text1,
            shape = RoundedCornerShape(topStart = 40.dp, topEnd = 40.dp),
        ) {
            SleepWindowSheet(m.day, m.sleep) { correctingNight = false }
        }
    }
}

/**
 * The per-key cache behind `VitalsDetailView`'s derived arrays. Every derivation is lazy, so a
 * value is computed at most once for one set of inputs; the view rebuilds the memo whenever an
 * input changes, so nothing survives a change.
 */
private class VitalsDetailMemo(
    val metric: VitalsMetric,
    val range: RollingPills,
    val m: DailyMetrics,
    val history: List<DailyMetrics>,
    val mealPoints: List<MealResponseIndex.Point>,
    val zerosToday: Boolean,
    val sleepScores: Map<String, SleepScore>,
    val now: Instant,
) {
    val detail: DetailWindow = DetailWindow(metric.detailSurface, range)

    /** True only on the rolling windows of the five instruments this board opened. The day
     *  window is deliberately not "a window of one" — it is the original page, untouched. */
    val isMetricWindow: Boolean = metric.hasMetricRange && range != RollingPills.day

    /** ⚠️ Read from `sleepScores`, never from `m.sleepScore`: a later `loadHome` replaces
     *  `today` wholesale, and the copy on that struct goes with it. */
    val todayScore: SleepScore? get() = sleepScores[m.day.key]

    /** The header word follows the window, because the window is now the user's to choose. */
    val periodLabel: String
        get() {
            if (metric.hasMetricRange) return range.metricPeriodLabel(metric)
            if (!metric.showsDetailPills) return metric.periodLabel
            val key = detail.periodKey
            return if (key.isEmpty()) metric.periodLabel else L(key)
        }

    val heroSensor: String
        get() = when {
            metric == VitalsMetric.response -> range.responseHeroSensor
            metric.hasMetricRange -> range.metricHeroSensor(metric)
            else -> metric.sensor
        }

    val chartTitle: String
        get() = when {
            metric == VitalsMetric.response -> range.responseChartTitle
            metric.hasMetricRange -> range.metricChartTitle(metric)
            else -> metric.chartTitle
        }

    val window: VitalsWindow by lazy { VitalsWindowAssembly.window(metric, range, m.day, now, m.sleep) }

    /** A multi-day window spans more than today's row. Merge history with the immediately
     *  synced local curve and then clip to the exact ruler. */
    val ticks: List<VitalSample> by lazy { VitalsWindowAssembly.ticks(metric, window, history, m) }

    val displayMetrics: DailyMetrics by lazy { VitalsWindowAssembly.displayMetrics(metric, range, m, ticks) }

    fun readout(vitals: com.nextbody.hoop.data.LiveVitals, profile: com.nextbody.hoop.data.Profile): VitalsReadout {
        if (metric == VitalsMetric.heart && range != RollingPills.day) {
            return VitalsReadout.heartWindow(heartDaily { it.hr?.toDouble() }, profile, detail.days)
        }
        if (isMetricWindow) return metricWindowReadout
        return VitalsReadout.make(metric, displayMetrics, history, vitals, profile, mealIndex, mealBoard)
    }

    /** One bucket a user day, in window order. Empty days stay empty arrays. */
    fun heartDaily(value: (VitalSample) -> Double?): List<List<Double>> {
        val first = m.day.adding(-(detail.days - 1))
        return (0 until detail.days).map { offset ->
            val day = first.adding(offset)
            ticks.mapNotNull { sample -> if (sample.ts >= day.start && sample.ts < day.end) value(sample) else null }
        }
    }

    val heartOxygen: List<OvernightOxygenPoint> by lazy {
        // `history` can already hold today (the simulator seed does). Same timestamp twice would
        // draw two marks on one reading.
        val byTs = LinkedHashMap<Instant, OvernightOxygenPoint>()
        (history + listOf(m))
            // Each night vouches for its own points: the companion under the pulse must print the
            // same night as the sleep board.
            .flatMap { day ->
                val night = day.sleep ?: return@flatMap emptyList()
                night.spo2.filter { night.containsSleepTimestamp(it.ts) }
            }
            .filter { window.contains(it.ts) }
            .forEach { byTs[it.ts] = it }
        byTs.values.sortedBy { it.ts }
    }

    val heartSlotMinutes: Double
        get() = if (range == RollingPills.day) detail.slotMinutes
        else HeartWindowMath.slotSeconds(window.span, detail.days) / 60

    // MARK: the five rolling windows · STRESS · TEMP · STEPS · DIST · CALS

    /** The window's user days, oldest first, today's row taken live rather than from history.
     *  A day with no row is an empty `DailyMetrics`, which yields nil totals rather than zeros. */
    val windowDays: List<DailyMetrics> by lazy { rows(m.day, detail.days) }

    fun metricDayTotal(day: DailyMetrics): Double? = when (metric) {
        VitalsMetric.steps -> VitalsReadout.daySteps(day)
        VitalsMetric.distance -> VitalsReadout.dayMetres(day)
        else -> VitalsReadout.dayActiveEnergy(day)
    }

    val metricSlots: List<MetricDayBars.Slot> by lazy { MetricWindowMath.slots(windowDays) { metricDayTotal(it) } }

    fun metricDaily(value: (VitalSample) -> Double?): List<List<Double>> =
        MetricWindowMath.dailyBuckets(ticks, m.day, detail.days, value)

    val metricWindowReadout: VitalsReadout
        get() = when (metric) {
            VitalsMetric.stress -> VitalsReadout.stressWindow(metricDaily { it.stress?.toDouble() }, ticks, detail.days)
            VitalsMetric.temp -> VitalsReadout.tempWindow(metricDaily { it.temp }, detail.days,
                SkinTempPresentation.nightRange(m, history, now).range)
            else -> VitalsReadout.totalWindow(metric, metricSlots, windowDays, ticks, detail.days)
        }

    // MARK: the trend hero · one mark a user day on every rolling window

    /** Every rolling window but RESPONSE leads with the trend hero. RESPONSE keeps its own week
     *  bars and month heat (ADR 0012), which already are its shape. */
    val showsTrendHero: Boolean
        get() = range != RollingPills.day && metric.showsDetailPills && metric != VitalsMetric.response

    /** The user days before the window, same length, oldest first — what "vs prior 7 days" is
     *  measured against. A day with no row is an empty `DailyMetrics`, never a zero day. */
    val priorDays: List<DailyMetrics> by lazy { rows(m.day.adding(-detail.days), detail.days) }

    fun rows(endingOn: UserDay, count: Int): List<DailyMetrics> {
        val first = endingOn.adding(-(count - 1))
        val byDay = history.associateBy { it.day }
        return (0 until count).map { offset ->
            val day = first.adding(offset)
            if (day == m.day) m else byDay[day] ?: DailyMetrics(day = day)
        }
    }

    /** Every tick the two windows can see, merged once and filed by the user day its clock falls
     *  in — the same way the worn-day tile under the page buckets them. */
    val trendTicksByDay: Map<UserDay, List<VitalSample>> by lazy {
        val eve = rows(m.day.adding(-(2 * detail.days)), 1)
        val curve = VitalSample.merging((eve + priorDays + windowDays).flatMap { it.vitalsCurve }, emptyList())
        curve.groupBy { UserDay.containing(it.ts) }
    }

    /** The value the hero marks for one user day. */
    fun trendValue(day: DailyMetrics, ticks: Map<UserDay, List<VitalSample>>): Double? = when (metric) {
        VitalsMetric.heart -> day.nightInputs?.rhr
        VitalsMetric.stress -> MetricTrendMath.mean((ticks[day.day] ?: emptyList()).mapNotNull { it.stress?.toDouble() })
        VitalsMetric.temp -> nightSkinMedian(day, (ticks[day.day.adding(-1)] ?: emptyList()) + (ticks[day.day] ?: emptyList()))
        VitalsMetric.steps -> VitalsReadout.daySteps(day)
        VitalsMetric.distance -> VitalsReadout.dayMetres(day)
        VitalsMetric.active -> VitalsReadout.dayActiveEnergy(day)
        VitalsMetric.sleep -> sleepScores[day.day.key]?.score?.toDouble()
        VitalsMetric.hrv, VitalsMetric.response -> null
    }

    /** ADR 0009 · skin temperature is a night reading. The median of the ticks the band took
     *  inside the recorded sleep — not an afternoon with the arm out of a sleeve. */
    fun nightSkinMedian(day: DailyMetrics, ticks: List<VitalSample>): Double? {
        val night = day.sleep ?: return null
        val start = night.sleepStart ?: return null
        val wake = night.wakeAt ?: return null
        if (wake <= start) return null
        val temps = ticks.mapNotNull { sample ->
            if (sample.ts >= start && sample.ts < wake && night.containsSleepTimestamp(sample.ts)) sample.temp else null
        }
        // Six ticks is half an hour: fewer is a wrist that came off, not a night.
        return if (temps.size >= 6) MetricTrendMath.median(temps) else null
    }

    val windowTrendValues: List<Double?> by lazy { windowDays.map { trendValue(it, trendTicksByDay) } }

    val priorTrendValues: List<Double?> by lazy { priorDays.map { trendValue(it, trendTicksByDay) } }

    /** How each instrument's window is drawn: the mark, the ruler, the rule or band across it,
     *  and the words. A window number is a different claim from a day number. */
    class TrendSpec(
        val style: MetricTrendHero.Style,
        val scale: ClosedFloatingPointRange<Double>,
        val zones: VitalsDial.Model? = null,
        val rule: MetricTrendHero.Rule? = null,
        val band: MetricTrendHero.Band? = null,
        val format: (Double) -> String,
        val unit: String,
        val seriesLabel: String,
        val nightly: Boolean,
        val empty: Pair<String, String>,
    )

    fun trendSpec(values: List<Double?>, loadState: SleepScoreLoadState, offline: Boolean): TrendSpec {
        val habit = MetricTrendMath.habit(values)
        val whole: (Double) -> String = { it.roundedInt().toString() }
        return when (metric) {
            VitalsMetric.heart -> {
                // The resting pulse, one a night, against the fourteen-night baseline the morning
                // reading is already judged by. Not the day's mean: a walk to the shops moves that.
                val base = m.nightInputs?.rhrBase
                TrendSpec(
                    style = MetricTrendHero.Style.line,
                    scale = MetricTrendMath.fittedScale(values, step = 5.0, pad = 4.0, minimumSpan = 20.0,
                        fallback = 40.0..80.0, including = base?.let { it..it }),
                    rule = base?.let { MetricTrendHero.Rule(it, L("BASELINE %@", whole(it))) }
                        ?: habit?.let { MetricTrendHero.Rule(it, L("MEDIAN %@", whole(it))) },
                    format = whole, unit = "BPM",
                    seriesLabel = L("RESTING · PER NIGHT"), nightly = true,
                    empty = L("NO RESTING PULSE IN THIS WINDOW") to L("A RECORDED NIGHT SETS THE NEXT POINT"),
                )
            }
            VitalsMetric.stress -> {
                val cuts = VitalsDialMath.stressCuts()
                TrendSpec(
                    style = MetricTrendHero.Style.bars, scale = cuts.scale,
                    zones = VitalsReadout.dial(cuts.scale, cuts.cuts, null,
                        listOf(L("REST"), L("STEADY"), L("ELEVATED"), L("HIGH")),
                        listOf(NB.optimal2, NB.lime1, NB.ember1, NB.alert2)),
                    rule = habit?.let { MetricTrendHero.Rule(it, L("MEDIAN %@", whole(it))) },
                    format = whole, unit = "/ 100",
                    seriesLabel = L("AVERAGE · PER DAY"), nightly = false,
                    empty = L("NO STRESS TICKS IN THIS WINDOW") to L("THE NEXT SYNC DRAWS THE LINE"),
                )
            }
            VitalsMetric.temp -> {
                val tenth: (Double) -> String = { swiftFormat("%.1f", it) }
                val nightRange = SkinTempPresentation.nightRange(m, history, now).range
                val own = nightRange?.let { it.lower..it.upper }
                TrendSpec(
                    style = MetricTrendHero.Style.line,
                    scale = MetricTrendMath.fittedScale(values, step = 0.5, pad = 0.5, minimumSpan = 2.0,
                        fallback = 30.0..38.0, including = own),
                    rule = if (own == null) habit?.let { MetricTrendHero.Rule(it, L("MEDIAN %@ °C", tenth(it))) } else null,
                    band = nightRange?.let {
                        MetricTrendHero.Band(it.lower..it.upper, L("YOUR RANGE %.1f–%.1f °C", it.lower, it.upper))
                    },
                    format = tenth, unit = "°C",
                    seriesLabel = L("NIGHT MEDIAN · PER NIGHT"), nightly = true,
                    empty = L("NO NIGHT SKIN TICKS IN THIS WINDOW") to L("A RECORDED NIGHT SETS THE NEXT POINT"),
                )
            }
            VitalsMetric.sleep -> TrendSpec(
                style = MetricTrendHero.Style.bars, scale = VitalsDialMath.sleepCuts().scale,
                zones = VitalsReadout.sleepDial(0, contributors = sleepWindow.contributorScores.isNotEmpty()),
                rule = habit?.let { MetricTrendHero.Rule(it, L("MEDIAN %@", whole(it))) },
                format = whole, unit = "/ 100",
                seriesLabel = L("SCORE · PER NIGHT"), nightly = true,
                empty = sleepScoreEmpty(loadState, offline),
            )
            VitalsMetric.steps, VitalsMetric.distance, VitalsMetric.active, VitalsMetric.hrv, VitalsMetric.response -> {
                val format = VitalsReadout.windowFormat(metric)
                val peak = MetricTrendMath.recorded(values).maxOrNull() ?: 0.0
                TrendSpec(
                    style = MetricTrendHero.Style.bars, scale = 0.0..max(peak, 1.0),
                    rule = habit?.let { MetricTrendHero.Rule(it, L("MEDIAN %@", format(it))) },
                    format = format,
                    // Distance prints its own unit — `6.4 KM` — so none is appended.
                    unit = if (metric == VitalsMetric.distance) "" else (VitalsReadout.windowUnit(metric) ?: ""),
                    seriesLabel = L("TOTAL · PER DAY"), nightly = false,
                    empty = L("NO DAYS ON RECORD IN THIS WINDOW") to L("THE NEXT SYNC FILLS THE DAYS"),
                )
            }
        }
    }

    @Composable
    fun TrendHero(loadState: SleepScoreLoadState, offline: Boolean) {
        val values = windowTrendValues
        val spec = trendSpec(values, loadState, offline)
        val days = windowDays
        val recorded = MetricTrendMath.recorded(values).size
        val headline = MetricTrendMath.headline(values)
        val delta = MetricTrendMath.delta(values, priorTrendValues)
        val rolls = if (range == RollingPills.month) {
            MetricTrendMath.weekRolls(values).mapIndexed { i, roll ->
                MetricTrendHero.Roll(i, L("%dD", roll.count), roll.average)
            }
        } else emptyList()
        MetricTrendHero(
            caption = L("%@ · %@", metric.sensor, L(detail.periodKey)),
            points = days.zip(values).map { (day, value) -> MetricTrendHero.Point(day.day.start, value) },
            style = spec.style, scale = spec.scale, tint = metric.tint,
            zones = spec.zones, rule = spec.rule, band = spec.band,
            format = spec.format, unit = spec.unit,
            seriesLabel = spec.seriesLabel,
            summary = MetricTrendHero.Summary(
                headline = L("MEDIAN %@", headline?.let(spec.format) ?: Fmt.dash),
                unit = spec.unit.ifEmpty { null },
                delta = trendDeltaText(delta, spec.nightly, spec.format),
                worn = if (spec.nightly) L("%d OF %d NIGHTS", recorded, days.size) else L("%d OF %d DAYS", recorded, days.size),
            ),
            rolls = rolls,
            rollCaption = if (spec.nightly) L("AVERAGE OF RECORDED NIGHTS") else L("AVERAGE OF RECORDED DAYS"),
            emptyLine = spec.empty.first, emptySub = spec.empty.second,
        )
    }

    /** "+2 VS PRIOR 7D": this window's median against the one before it. A change that rounds
     *  away to nothing says so rather than printing a signed zero. */
    fun trendDeltaText(delta: Double?, nightly: Boolean, format: (Double) -> String): String? {
        if (delta == null) return null
        val span = if (nightly) L("PRIOR %d NIGHTS", detail.days) else L("PRIOR %dD", detail.days)
        val magnitude = format(abs(delta))
        if (magnitude == format(0.0)) return L("LEVEL WITH %@", span)
        return L("%@%@ VS %@", if (delta > 0) "+" else "−", magnitude, span)
    }

    val mealBoard: MealResponsePresentation.Board by lazy {
        MealResponsePresentation.board(m, history, mealPoints, zerosToday, now, range)
    }

    val mealIndex: MealResponseIndex.Result get() = mealBoard.index

    val activeModel: ActiveEnergyModel by lazy { ActiveEnergyModel.make(m, now, history) }

    // MARK: sleep score status

    fun sleepScoreStatus(state: SleepScoreLoadState, offline: Boolean): String? {
        val hasSaved = if (range == RollingPills.day) todayScore != null else sleepWindow.recorded > 0
        return when (state) {
            SleepScoreLoadState.idle -> if (offline) {
                if (hasSaved) L("OFFLINE · SHOWING SAVED SCORES") else L("OFFLINE · SCORES NOT LOADED")
            } else if (hasSaved) L("SAVED SCORES · WAITING TO REFRESH") else L("SCORES NOT LOADED YET")
            SleepScoreLoadState.loading -> if (hasSaved) L("UPDATING SLEEP SCORES") else L("LOADING SLEEP SCORES")
            SleepScoreLoadState.failed -> if (hasSaved) L("REFRESH FAILED · SHOWING SAVED SCORES") else L("SLEEP SCORES COULD NOT BE LOADED")
            SleepScoreLoadState.ready ->
                if (range == RollingPills.day && todayScore == null && m.sleep != null) L("SCORE NOT SETTLED YET") else null
        }
    }

    fun sleepScoreEmpty(state: SleepScoreLoadState, offline: Boolean): Pair<String, String> {
        val status = sleepScoreStatus(state, offline)
        if (status != null) return status to L("SYNC AGAIN TO REFRESH SCORES")
        return L("NO SETTLED SCORES IN THIS WINDOW") to L("RECORDED NIGHTS APPEAR AFTER SCORING")
    }

    // MARK: the clock under the chart

    val axisLabels: List<String>
        get() = when (metric.timeline) {
            // ⚠️ The hypnogram is laid out along the line's own minutes, not along a clock.
            VitalsTimelineKind.lastNight -> sleepAxisLabels
            VitalsTimelineKind.userDayToNow -> window.labels
        }

    /** The night's own clock when the band recorded its ends, and the hours elapsed into it when
     *  it did not — either way a ruler the staircase above it is actually drawn on. */
    val sleepAxisLabels: List<String>
        get() {
            // No staircase means no ruler.
            val night = m.sleep ?: return emptyList()
            if (night.totalMinutes <= 0 || night.line.isEmpty()) return emptyList()
            val start = night.sleepStart
            val wake = night.wakeAt
            if (start != null && wake != null && wake > start &&
                ((night.intervals?.size ?: 1) <= 1 || night.line.all { it.offsetMinutes != null })
            ) {
                val span = wake.timeIntervalSince(start)
                return (0..4).map { Fmt.clock(start.addingTimeInterval(span * it / 4)) }
            }
            return (0..4).map { i -> if (i == 0) "0H" else Fmt.duration(night.totalMinutes * i / 4) }
        }

    // MARK: sleep board — key metrics, the night's stages, overnight vitals, the week

    /** Oura's four tiles under the factors: what the night measured, each against this
     *  person's own last 30 settled nights (WHOOP's "vs previous 30 days"). */
    @Composable
    fun SleepKeyMetrics(r: VitalsReadout) {
        val night = m.sleep
        val scored = todayScore?.inputs?.get("duration_min")?.takeIf { it.isFinite() && it > 0 && it <= 2880 }?.roundedInt()
        val asleep = scored ?: night?.totalMinutes?.takeIf { it > 0 }
        val start = night?.sleepStart
        val wake = night?.wakeAt
        val inBed = if (start != null && wake != null && wake > start) (wake.timeIntervalSince(start) / 60).toInt() else null
        val efficiency = todayScore?.inputs?.get("efficiency_pct")?.takeIf { it.isFinite() && it > 0 && it <= 100 }
        Column(Modifier.testTag("sleep.keyMetrics"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            VitalsStatPair(
                VitalsStatPair.Model(L("TOTAL SLEEP"), asleep?.let { Fmt.duration(it) }, null,
                    nightMedianFoot("duration_min") { Fmt.duration(it.roundedInt()) }, metric.tint),
                VitalsStatPair.Model(L("TIME IN BED"), inBed?.let { Fmt.duration(it) }, null, r.footLeft, null),
            )
            VitalsStatPair(
                VitalsStatPair.Model(L("SLEEP EFFICIENCY"), efficiency?.let { swiftFormat("%.0f", it) }, "%",
                    nightMedianFoot("efficiency_pct") { swiftFormat("%.0f%%", it) }, null),
                r.heartLow ?: VitalsStatPair.Model(L("SLEEP LOW HR"), null, "BPM", L("WEAR IT TONIGHT"), null),
            )
        }
    }

    /** The median of one settled input over the 30 nights before this one. Fewer than three
     *  nights is not a baseline and says so rather than printing one. */
    fun nightMedianFoot(key: String, format: (Double) -> String): String {
        val values = (1..30).mapNotNull { offset ->
            sleepScores[m.day.adding(-offset).key]?.inputs?.get(key)?.takeIf { it.isFinite() && it > 0 }
        }
        val median = if (values.size >= 3) SleepScoreMath.median(values) else null
        return median?.let { L("30-NIGHT MEDIAN %@", format(it)) } ?: L("30-NIGHT BASELINE BUILDING")
    }

    /** The details, Oura/WHOOP order: how the night was spent (the staircase and each stage on
     *  its own row), the window it was counted over, what the body did meanwhile, and the week
     *  of nights it sits in. Every number appears once on the page. */
    @Composable
    fun SleepBoard(r: VitalsReadout, correct: () -> Unit) {
        CardBlock(title = L("SLEEP STAGES"), trailing = r.value?.let { L("ASLEEP %@", it) }, trailingIsDot = true) {
            val line = m.sleep?.line
            if (!line.isNullOrEmpty()) {
                VitalsHypnogram(line, metric.tint, windowMinutes = window.span / 60, probeClock = window::clock)
            } else {
                VitalsChartEmpty(
                    line = when {
                        m.sleep == null -> L("NO NIGHT ON RECORD")
                        (m.sleep?.unstagedMinutes ?: 0) > 0 -> L("STAGES NOT MEASURED")
                        else -> L("TOTALS ONLY")
                    },
                    sub = if (m.sleep == null) L("WEAR IT TONIGHT") else L("THE BAND FILED NO STAGE LINE"),
                )
            }
            VitalsAxis(axisLabels, false, metric.tint, Modifier.padding(start = VitalsHypnogram.labelGutter))
            if (r.bands.isNotEmpty()) {
                Hairline()
                SleepStageRows(r.bands)
            }
            val wakes = r.extraRight
            val count = wakes?.value
            if (wakes != null && count != null) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(wakes.label, style = NBFont.ui(500, 13f), color = NB.text1, maxLines = 1, modifier = Modifier.weight(1f))
                    Text(count, style = NBFont.dot(700, 14f), color = NB.text1, maxLines = 1)
                }
            }
        }
        // Existing and missing nights use the same time wheels and evidence refresh.
        val night = m.sleep
        if (night != null && night.sleepStart != null && night.wakeAt != null) {
            SleepWindowCard(night, editable = SleepCorrection.canCorrect(m.day), edit = correct)
        } else if (night == null && SleepCorrection.canCorrect(m.day)) {
            CardBlock(title = L("SLEEP WINDOW")) {
                Text(L("ADD SLEEP"), Modifier.testTag("sleep.addNight").hotZoneTap { correct() },
                    style = NBFont.dot(600, 11f), color = NB.lime1)
            }
        }

        // ---- OVERNIGHT VITALS · what the body did while it was down there
        SectionLabel(L("OVERNIGHT VITALS"))
        if (todayScore?.usesContributors != false) {
            Text(L("SUPPORTING MEASUREMENTS · NOT SCORED"), style = NBFont.ui(400, 12f), color = NB.text3Prod,
                modifier = Modifier.offset(y = (-6).dp))
        }
        // ⚠️ Night HRV is a tile, not a trace: one night mean, read against this person's own
        // baseline, is the whole of what those scattered readings support.
        VitalsStatPair(
            r.statLeft,
            r.respirationLeft ?: VitalsStatPair.Model(L("MEAN RESPIRATION"), null, L("BREATHS / MIN"), L("WEAR IT TONIGHT"), null),
        )
        val spo2Mean = r.statRight.value
        CardBlock(
            title = L("NIGHT SPO2"),
            trailing = spo2Mean?.let { L("AVG %@", "$it%") } ?: L("FIXED 85–100 %"),
            trailingIsDot = spo2Mean != null,
        ) {
            val points = (m.sleep?.spo2 ?: emptyList()).filter { m.sleep?.containsSleepTimestamp(it.ts) == true }
            if (points.isNotEmpty()) {
                val series = points.map { TimedValue(it.ts, it.percent.toDouble()) }
                VitalsLineTrace(series, window, low = 85.0, high = 100.0, tint = NB.cyan1, marksMaximum = false, unit = "%")
                VitalsAxis(window.labels, false, NB.cyan1, Modifier.padding(end = VitalsScaleRail.gutter))
                VitalsChartLegend(
                    items = listOf(VitalsChartLegend.Item(L("MEASURED POINTS · LINE"), NB.cyan1)) +
                        (if (VitalsLineTrace.runs(series, window).size > 1)
                            listOf(VitalsChartLegend.Item(L("DASHED · NOT MEASURED"), NB.cyan1.copy(alpha = 0.45f)))
                        else emptyList()),
                    trailing = points.minOfOrNull { it.percent }?.let { L("MIN %d", it) },
                    trailingTint = NB.cyan1,
                )
            } else {
                VitalsChartEmpty(L("NO OVERNIGHT OXYGEN"), L("AUTO NIGHT MEASUREMENT WAS OFF OR EMPTY"))
                VitalsAxis(window.labels, false, NB.cyan1)
            }
        }
        CardBlock(title = L("SLEEP RESPIRATION"), trailing = L("FIXED 0–60 /MIN")) {
            val points = (m.sleep?.respiration ?: emptyList()).filter {
                m.sleep?.containsSleepTimestamp(it.ts) == true && it.breathsPerMinute.isFinite() && it.breathsPerMinute > 0
            }
            if (points.isNotEmpty()) {
                val series = points.map { TimedValue(it.ts, it.breathsPerMinute) }
                VitalsLineTrace(series, window, low = 0.0, high = 60.0, tint = NB.violet2, unit = "/MIN")
                VitalsAxis(window.labels, false, NB.violet2, Modifier.padding(end = VitalsScaleRail.gutter))
                VitalsChartLegend(
                    items = listOf(VitalsChartLegend.Item(L("MEASURED POINTS · LINE"), NB.violet2)) +
                        (if (VitalsLineTrace.runs(series, window).size > 1)
                            listOf(VitalsChartLegend.Item(L("DASHED · NOT MEASURED"), NB.violet2.copy(alpha = 0.45f)))
                        else emptyList()),
                    trailing = points.maxOfOrNull { it.breathsPerMinute }?.let { L("NIGHT HIGH %d", it.roundedInt()) },
                    trailingTint = NB.violet2,
                )
            } else {
                VitalsChartEmpty(L("NO SLEEP RESPIRATION"),
                    if (window.span > 0) L("THE BAND FILED NO RESPIRATION READINGS") else L("WINDOW NOT ON RECORD"))
                VitalsAxis(window.labels, false, NB.violet2)
            }
        }

        // ---- the week this night sits in
        SectionLabel(L("SLEEP SCHEDULE"))
        CardBlock(title = L("SLEEP BY NIGHT"), trailing = bedtimeTrailing) {
            ScheduleChart(
                scheduleNights(7), todayScore?.inputs?.get("bed_median"),
                if (todayScore?.inputs?.get("bed_offset") == null) L("NO BEDTIME RECORDED") else L("NO NIGHTS ON RECORD"),
            )
        }
    }

    /** The last N wake-days as columns from asleep to awake. */
    fun scheduleNights(count: Int): List<SleepScheduleNight> {
        val today = m.day
        val byDay = history.associateBy { it.day.key }
        return (0 until count).reversed().map { offset ->
            val day = today.adding(-offset)
            val summary = if (day == today) m.sleep else byDay[day.key]?.sleep
            SleepScheduleNight(day, sleepScores[day.key], summary)
        }
    }

    /** Ready-made: the schedule, its key, and the baseline count while the habit is still being
     *  learned — the one line that says why the band is not drawn yet. */
    @Composable
    fun ScheduleChart(nights: List<SleepScheduleNight>, baseline: Double?, empty: String) {
        val score = todayScore
        val baselineLine = L("BASELINE %d / %d NIGHTS · SCORED FROM THE THIRD NIGHT",
            (score?.inputs?.get("baseline_bed_nights") ?: 0.0).toInt(), SleepScoreMath.regularityBaselineNights)
        if (nights.any { it.isRecorded }) {
            SleepScheduleBars(nights, baseline)
            SleepScheduleBars.Legend(baseline)
            if (baseline == null && score?.usesContributors != true) {
                Text(baselineLine, style = NBFont.dot(500, 9f).tracking(0.05f), color = NB.text3Prod)
            }
        } else {
            VitalsChartEmpty(
                line = empty,
                sub = if (score?.usesContributors == true) L("TIMING USES SLEEP MIDPOINT, NOT BEDTIME REGULARITY") else baselineLine,
            )
        }
    }

    val bedtimeTrailing: String
        get() {
            val median = todayScore?.inputs?.get("bed_median") ?: return Fmt.dash
            return L("USUALLY %@", SleepScoreMath.bedClock(median))
        }

    // MARK: the sleep window

    /** The last N wake-days ending today, each with whatever score settled for it. Built from
     *  `sleepScores` rather than `history`, which carries sleep for only a handful of days. */
    val sleepSlots: List<SleepNightSlot>
        get() = (0 until detail.days).reversed().map { offset ->
            val day = m.day.adding(-offset)
            SleepNightSlot(day, sleepScores[day.key])
        }

    val sleepWindow: SleepWindowSummary by lazy { SleepWindowSummary(sleepSlots) }

    /** The score by night leads the page as the trend hero; the board underneath is what a
     *  median score cannot say by itself. */
    @Composable
    fun MultiNightBoard() {
        val summary = sleepWindow
        if (summary.recorded > 0) {
            val contributors = summary.contributorScores.isNotEmpty()
            SectionLabel(L("SLEEP CONTRIBUTORS"))
            CardBlock(
                title = L(if (contributors) "FACTOR MEDIANS" else "GROUP MEDIANS"),
                trailing = L("%d OF %d NIGHTS", summary.recorded, summary.slots.size),
            ) {
                SleepWindowBreakdown(summary)
            }
        }

        SectionLabel(L("KEY METRICS"))
        VitalsStatPair(
            VitalsStatPair.Model(L("TOTAL SLEEP"), summary.durationMinutes?.let { Fmt.duration(it) }, null,
                L("MEDIAN PER NIGHT"), metric.tint),
            VitalsStatPair.Model(L("MEDIAN BEDTIME"), summary.bedClock, null,
                L("ACROSS %d NIGHTS", summary.recorded), null),
        )
        VitalsStatPair(
            VitalsStatPair.Model(L("MEDIAN WAKES"), summary.wakes?.roundedInt()?.toString(), null,
                L("PER NIGHT"), null),
            VitalsStatPair.Model(L("NIGHTS SCORED"), "${summary.recorded}", L("OF %d NIGHTS", summary.slots.size),
                L("SETTLED SCORES ONLY"), null),
        )

        SectionLabel(L("DETAILS"))
        CardBlock(title = L("STAGE PROPORTIONS"),
            trailing = summary.durationMinutes?.let { L("MEDIAN %@", Fmt.duration(it)) } ?: Fmt.dash) {
            val bands = summary.bands
            if (bands.isEmpty()) VitalsChartEmpty(L("NO STAGES ON RECORD"), L("TOTALS ONLY"))
            else VitalsSplit(bands)
        }

        CardBlock(title = L("SLEEP BY NIGHT"), trailing = summary.bedClock?.let { L("USUALLY %@", it) } ?: Fmt.dash) {
            ScheduleChart(scheduleNights(summary.slots.size), summary.bedOffset, L("NO NIGHTS ON RECORD"))
        }
    }

    val chartHasScaleRail: Boolean
        get() {
            if (metric == VitalsMetric.response) return range != RollingPills.month
            // Every rolling window draws its own rail.
            if (isMetricWindow) return true
            return metric.chartHasScaleRail
        }

    val weekAxisLabels: List<String> get() = mealBoard.window.slots.map { Fmt.weekday(it.start) }

    @Composable
    fun ResponseChart(r: VitalsReadout) {
        when (range) {
            RollingPills.day -> {
                val axis = r.traceRange
                if (mealIndex.trendPoints.isNotEmpty() && axis != null) {
                    val zones = mealIndex.ownMedian?.let { median ->
                        VitalsDialMath.ratioCuts(median)?.let {
                            VitalsReadout.dial(it.scale, it.cuts, mealIndex.latestPoint,
                                listOf(L("BELOW"), L("NEAR"), L("ABOVE")),
                                listOf(NB.ember1, NB.compareAmber, NB.optimal2))
                        }
                    }
                    VitalsTrace(
                        samples = emptyList(),
                        value = { null },
                        window = window,
                        low = axis.start,
                        high = axis.endInclusive,
                        tint = metric.tint,
                        zones = zones,
                        referenceBand = r.referenceBand,
                        measuredPoints = mealIndex.trendPoints.map { TimedValue(it.ts, it.optical) },
                        valueFormat = { MealResponseIndex.pointValue(it) },
                    )
                } else {
                    VitalsChartEmpty(L("NO RESPONSE POINTS IN 24H"), L("THE NEXT SYNC FILLS THE POINTS"))
                }
            }
            RollingPills.week -> {
                if (mealBoard.window.recordedDays > 0) {
                    ResponseDayBars(mealBoard.window.slots, mealIndex.ownMedian, metric.tint)
                } else {
                    VitalsChartEmpty(L("NO RESPONSE POINTS IN THIS WINDOW"), L("THE NEXT SYNC FILLS THE POINTS"))
                }
            }
            RollingPills.month -> {
                if (mealBoard.window.recordedDays > 0) {
                    ResponseDayHeat(mealBoard.window.slots, mealIndex.ownMedian, metric.tint)
                } else {
                    VitalsChartEmpty(L("NO RESPONSE POINTS IN THIS WINDOW"), L("THE NEXT SYNC FILLS THE POINTS"))
                }
            }
        }
    }

    // MARK: the eight charts

    /** The day page's chart. The rolling windows no longer draw a chart card: their shape is
     *  the trend hero at the top of the page. */
    @Composable
    fun DayChart(r: VitalsReadout) {
        when (metric) {
            VitalsMetric.heart -> Trace({ it.hr?.toDouble() }, 40.0, 160.0, r,
                L("NO HEART TICKS IN 24H") to L("THE NEXT SYNC DRAWS THE LINE"),
                ticks.any { it.hr != null }, unit = "BPM")

            VitalsMetric.stress -> Trace({ it.stress?.toDouble() }, 0.0, 100.0, r,
                L("NO STRESS TICKS IN 24H") to L("THE NEXT SYNC DRAWS THE LINE"),
                ticks.any { it.stress != null })

            VitalsMetric.temp -> {
                // Drawn in °C against this wrist's own ruler, with the night range banded across
                // last night alone. A first week without a range still draws every measured tick.
                val axis = r.traceRange
                if (axis != null && ticks.any { it.temp != null }) {
                    VitalsTrace(
                        samples = ticks, value = { it.temp }, window = window,
                        low = axis.start, high = axis.endInclusive, tint = metric.tint,
                        zones = r.dial, referenceBand = r.referenceBand, referenceSpan = r.referenceSpan,
                        valueFormat = { swiftFormat("%.1f", it) }, unit = "°C",
                    )
                } else {
                    VitalsChartEmpty(L("NO SKIN TICKS IN 24H"), L("THE NEXT SYNC DRAWS THE LINE"))
                }
            }

            VitalsMetric.sleep -> Unit

            VitalsMetric.hrv -> {
                if (ticks.any { it.hrv != null }) {
                    val nightly = history.takeLast(15).dropLast(1).mapNotNull { it.nightInputs?.hrv }
                    VitalsScatter(ticks, window,
                        envelope = if (nightly.size >= 5) nightly.min()..nightly.max() else null,
                        baseline = m.nightInputs?.hrvBase, tint = metric.tint)
                } else {
                    VitalsChartEmpty(L("NO RMSSD TICKS IN 24H"), L("THE BAND MEASURES IT EVERY TEN MINUTES"))
                }
            }

            VitalsMetric.response -> ResponseChart(r)

            VitalsMetric.steps -> Histogram({ it.steps?.toDouble() }, L("NO STEPS TODAY") to L("THE NEXT SYNC FILLS THE HOURS"))

            VitalsMetric.active -> VitalsChartEmpty(L("HOURLY ENERGY NOT AVAILABLE"),
                L("DAILY ACTIVE ENERGY IS WEIGHT-AWARE AND SETTLED"))

            VitalsMetric.distance -> {
                val bins = VitalsMath.hourSum(ticks, window.range) { it.dis }
                if (VitalsMath.total(bins) != null) VitalsClimb(bins, window, metric.tint)
                else VitalsChartEmpty(L("NO DISTANCE TODAY"), L("THE NEXT SYNC DRAWS THE CLIMB"))
            }
        }
    }

    @Composable
    fun Trace(
        value: (VitalSample) -> Double?, low: Double, high: Double, r: VitalsReadout,
        empty: Pair<String, String>, has: Boolean,
        valueFormat: (Double) -> String = { swiftFormat("%.0f", it) },
        unit: String = "",
        slotMinutes: Double = VitalsTrace.defaultSlotMinutes,
    ) {
        if (has) {
            VitalsTrace(
                samples = ticks, value = value, window = window, low = low, high = high, tint = metric.tint,
                zones = r.dial, referenceBand = r.referenceBand, referenceSpan = r.referenceSpan,
                slotMinutes = slotMinutes, valueFormat = valueFormat, unit = unit,
            )
        } else {
            VitalsChartEmpty(empty.first, empty.second)
        }
    }

    /** What the marks mean, said under the clock. */
    @Composable
    fun DayChartLegend(r: VitalsReadout) {
        when (metric) {
            VitalsMetric.heart, VitalsMetric.stress, VitalsMetric.temp -> {
                val extreme = traceExtreme
                if (extreme != null) {
                    VitalsChartLegend(
                        items = listOf(VitalsChartLegend.Item(
                            L("EVERY %d MIN · MEASURED", VitalsTrace.defaultSlotMinutes.toInt()),
                            metric.tint, stops = r.dial?.legendStops)) +
                            (r.referenceLabel?.let { listOf(VitalsChartLegend.Item(it, metric.tint, isArea = true)) } ?: emptyList()),
                        trailing = traceExtremeLabel(extreme),
                        trailingTint = metric.tint,
                    )
                }
            }
            VitalsMetric.steps -> {
                val bins = VitalsMath.hourSum(ticks, window.range) { it.steps?.toDouble() }
                if (VitalsMath.total(bins) != null) {
                    VitalsChartLegend(
                        items = listOf(VitalsChartLegend.Item(L("PER HOUR"), metric.tint)),
                        trailing = bins.filterNotNull().maxOrNull()?.let { L("PEAK %@/H", Fmt.kcal(it)) },
                        trailingTint = metric.tint,
                    )
                }
            }
            VitalsMetric.distance -> {
                val bins = VitalsMath.hourSum(ticks, window.range) { it.dis }
                // ⚠️ The climb's own end, not `m.distanceM`: the rail names what is drawn; this
                // names the same thing.
                val climbed = VitalsMath.total(bins)
                if (climbed != null) {
                    VitalsChartLegend(
                        items = listOf(VitalsChartLegend.Item(L("CUMULATIVE"), metric.tint)),
                        trailing = L("%@ NOW", VitalsReadout.distanceLabel(climbed)),
                        trailingTint = metric.tint,
                    )
                }
            }
            VitalsMetric.response -> when (range) {
                RollingPills.day -> if (mealIndex.trendPoints.isNotEmpty()) {
                    VitalsChartLegend(
                        items = listOf(VitalsChartLegend.Item(
                            L("EVERY %d MIN · MEASURED", VitalsTrace.defaultSlotMinutes.toInt()), metric.tint)) +
                            (r.referenceLabel?.let { listOf(VitalsChartLegend.Item(it, metric.tint, isArea = true)) } ?: emptyList()),
                        trailing = mealIndex.trendPoints.maxOfOrNull { it.optical }?.let { L("HIGH %@", MealResponseIndex.pointValue(it)) },
                        trailingTint = metric.tint,
                    )
                }
                RollingPills.week -> if (mealBoard.window.recordedDays > 0) ResponseDayBars.Legend()
                RollingPills.month -> if (mealBoard.window.recordedDays > 0) ResponseDayHeat.Legend()
            }
            VitalsMetric.sleep, VitalsMetric.hrv, VitalsMetric.active -> Unit
        }
    }

    /** What makes a day count as worn on a trace window — the instrument's own reading, never
     *  "any tick at all". */
    fun windowTickValue(sample: VitalSample): Double? = when (metric) {
        VitalsMetric.stress -> sample.stress?.toDouble()
        VitalsMetric.temp -> sample.temp
        else -> null
    }

    val traceExtreme: Double?
        get() = when (metric) {
            VitalsMetric.heart -> ticks.mapNotNull { it.hr?.toDouble() }.maxOrNull()
            VitalsMetric.stress -> ticks.mapNotNull { it.stress?.toDouble() }.maxOrNull()
            VitalsMetric.temp -> ticks.mapNotNull { it.temp }.maxOrNull()
            else -> null
        }

    fun traceExtremeLabel(value: Double): String = when (metric) {
        VitalsMetric.heart -> L("MAX %d", value.roundedInt())
        VitalsMetric.stress -> L("PEAK %d", value.roundedInt())
        VitalsMetric.temp -> L("HIGH %.1f", value)
        else -> Fmt.dash
    }

    @Composable
    fun Histogram(value: (VitalSample) -> Double?, empty: Pair<String, String>) {
        val bins = VitalsMath.hourSum(ticks, window.range, value)
        if (VitalsMath.total(bins) != null) VitalsHistogram(bins, window, metric.tint)
        else VitalsChartEmpty(empty.first, empty.second)
    }

    // MARK: foot

    val latestTickAt: Instant?
        get() = when (metric) {
            VitalsMetric.heart -> ticks.lastOrNull { it.hr != null }?.ts
            VitalsMetric.sleep -> m.sleep?.wakeAt
            VitalsMetric.hrv -> ticks.lastOrNull { it.hrv != null }?.ts
            VitalsMetric.response -> mealIndex.trendPoints.lastOrNull()?.ts
            VitalsMetric.stress -> ticks.lastOrNull { it.stress != null }?.ts
            VitalsMetric.temp -> ticks.lastOrNull { it.temp != null }?.ts
            VitalsMetric.steps -> ticks.lastOrNull { it.steps != null }?.ts
            VitalsMetric.distance -> ticks.lastOrNull { it.dis != null }?.ts
            VitalsMetric.active -> ticks.lastOrNull { it.steps != null || it.dis != null }?.ts
        }

    /**
     * #28 · the last line of the sleep page is the way back to the night's own start and end.
     * The window card near the top offers the same correction, but the doubt about when the
     * night began usually arrives at the bottom of the page. Both open the same wheels.
     */
    @Composable
    fun CorrectNightLine(correct: () -> Unit) {
        val night = m.sleep
        if (metric == VitalsMetric.sleep && SleepCorrection.canCorrect(m.day) &&
            (night == null || (night.sleepStart != null && night.wakeAt != null))
        ) {
            // A multi-night window is not looking at one night, so the line says which one.
            val text = when {
                night == null -> L("ADD SLEEP")
                range == RollingPills.day -> L("CHANGE TIMES")
                else -> L("CHANGE TIMES · %@", m.day.key)
            }
            Box(
                Modifier.fillMaxWidth().testTag("sleep.changeTimes").hotZoneTap { correct() }.padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                // Centred: the page's last line is an offer, not another footnote.
                Text(text, style = NBFont.dot(600, 10f).tracking(0.12f), color = NB.lime1.copy(alpha = 0.85f),
                    textAlign = TextAlign.Center)
            }
        }
    }

    /** The one line that says where the page's numbers came from. 04B rule 05 · the age of the
     *  last tick belongs on the page that prints it, not only on the strip. */
    @Composable
    fun Footer(state: SleepScoreLoadState, offline: Boolean) {
        var line: String
        if (metric == VitalsMetric.sleep && range != RollingPills.day) {
            val summary = sleepWindow
            line = if (summary.recorded == 0) sleepScoreEmpty(state, offline).first
            else L("%d NIGHTS ENDING %@", summary.recorded, m.day.key)
        } else if (metric == VitalsMetric.heart && range != RollingPills.day) {
            val worn = HeartWindowMath.wornDays(heartDaily { it.hr?.toDouble() })
            line = if (worn == 0) L("NO HEART TICKS IN THIS WINDOW") else L("%d DAYS ENDING %@", worn, m.day.key)
        } else if (isMetricWindow) {
            val worn = if (metric.windowIsAccumulated) MetricWindowMath.recorded(metricSlots).size
            else HeartWindowMath.wornDays(metricDaily(::windowTickValue))
            line = if (worn == 0) L("NO RECORD IN THIS WINDOW") else L("%d DAYS ENDING %@", worn, m.day.key)
        } else if (metric == VitalsMetric.response && range != RollingPills.day) {
            val recorded = mealBoard.window.recordedDays
            line = if (recorded == 0) L("NO RESPONSE POINTS IN THIS WINDOW") else L("%d DAYS ENDING %@", recorded, m.day.key)
        } else if (metric.isNightly) {
            line = m.sleep?.wakeAt?.let { L("FROM THE NIGHT THAT ENDED %@", Fmt.clock(it)) }
                ?: L("FROM THE LAST NIGHT THE BAND FILED")
            todayScore?.computedAt?.let { line += L(" · SCORE UPDATED %@", Fmt.clock(it)) }
        } else {
            val at = latestTickAt
            if (at != null) {
                line = L("LAST TICK %@ · %@", Fmt.clock(at), VitalsMath.age(at, now))
                if (metric in setOf(VitalsMetric.heart, VitalsMetric.stress, VitalsMetric.temp, VitalsMetric.response)) {
                    val gap = VitalsMath.offWrist(ticks)
                    if (gap != null && gap.minutes >= 60) line += L(" · %@ OFF WRIST", Fmt.duration(gap.minutes))
                }
            } else {
                line = L("NO TICKS YET · FIRST SYNC DRAWS THE LINE")
            }
        }
        FitText(line, NBFont.dot(500, 9.5f).tracking(0.12f), NB.white.copy(alpha = 0.38f),
            Modifier.fillMaxWidth().padding(top = 2.dp), minScale = 0.8f)
    }
}
