package com.nextbody.hoop.features.vitals

import com.nextbody.hoop.features.home.panel.VitalsMath
import androidx.compose.ui.graphics.Color
import com.nextbody.hoop.band.ActiveEnergyMath
import com.nextbody.hoop.band.ActivityEnergyPolicy
import com.nextbody.hoop.band.DetailSurface
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.HealthSampleMapping
import com.nextbody.hoop.band.MealResponseIndex
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.band.VitalsClock
import com.nextbody.hoop.data.LiveVitals
import com.nextbody.hoop.data.Profile
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.SleepSummary
import com.nextbody.hoop.model.TickFreshness
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.roundedInt
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import java.time.Instant
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * 04 · 8 大指标二级页 · everything the page prints, derived from the day the app already
 * holds. No view in this feature computes a number; they only lay one out.
 *
 * ⚠️ Nothing here reads the band and nothing here invents. Every field is either a value that
 * arrived — a tick, a night, a server-settled total — or nil, which renders as —— (F2 rule
 * 05). A zero is only ever printed when the band actually reported one.
 */
data class VitalsReadout(
    var value: String?,
    var unit: String?,
    var dial: VitalsDial.Model?,
    var footLeft: String,
    var footRight: String?,
    /** The note at the right of the chart card — the ruler the curve is drawn against. */
    var chartNote: String,
    var splitTitle: String,
    var splitTrailing: String?,
    var bands: List<VitalsSplit.Band>,
    var statLeft: VitalsStatPair.Model,
    var statRight: VitalsStatPair.Model,
    /** Sleep's wake-events tile, paired with its deep episodes. Other pages leave it empty. */
    var extraRight: VitalsStatPair.Model? = null,
    var respirationLeft: VitalsStatPair.Model? = null,
    var respirationRight: VitalsStatPair.Model? = null,
    /** The lowest heart rate the band recorded inside the night window. */
    var heartLow: VitalsStatPair.Model? = null,
    /** The physiological band drawn behind the trace, in the chart's own units. It is a
     *  reference, never a target. */
    var referenceBand: ClosedFloatingPointRange<Double>? = null,
    var referenceLabel: String? = null,
    /** 05 · the vertical ruler the skin-temperature trace is drawn against, in °C. */
    var traceRange: ClosedFloatingPointRange<Double>? = null,
    /** The stretch of the chart the reference band belongs to — last night's sleep window. */
    var referenceSpan: ClosedRange<Instant>? = null,
) {
    companion object {
        /** One tick is five minutes wide, which is the finest any duration on these pages can
         *  be. 08 rule 02 · zone minutes are multiples of five, floored. */
        const val tickMinutes = 5

        // MARK: the day's three totals

        /**
         * Steps and metres may be summed from measured tick increments. Active kcal may not:
         * the archived vendor calorie field is a differently-defined counter, so energy waits
         * for the server's weight-aware settled value.
         *
         * ⚠️ Shared rather than re-derived per page: two pages disagreeing about one number is
         * worse than either number being absent.
         */
        fun daySteps(m: DailyMetrics): Double? = m.steps?.toDouble() ?: VitalsMath.total(
            VitalsMath.hourSum(m.vitalsCurve, m.day) { it.steps?.toDouble() })

        fun dayMetres(m: DailyMetrics): Double? = m.distanceM?.toDouble() ?: VitalsMath.total(
            VitalsMath.hourSum(m.vitalsCurve, m.day) { it.dis })

        fun dayActiveKcal(m: DailyMetrics): Double? = ActivityEnergyPolicy.displayTotal(
            settledActiveKcal = m.eActive,
            archivedVendorCalories = m.vitalsCurve.mapNotNull { it.vendorCalories })

        /** Metres under a kilometre read as metres. "0.0 KM" for a real 40-metre walk looks
         *  like a bug on the legend even though the number is honest. */
        fun distanceLabel(metres: Double): String =
            if (metres < 1000) L("%d M", metres.roundedInt()) else L("%.1f KM", metres / 1000)

        /** Recorded activity only, shared by the day and rolling-window heroes. */
        fun dayActiveEnergy(m: DailyMetrics): Double? =
            ActiveEnergyMath.totals(m.bmr, m.eActive, m.eTrain, m.eOutNow).active

        // MARK: building it

        fun make(
            metric: VitalsMetric,
            m: DailyMetrics,
            history: List<DailyMetrics>,
            vitals: LiveVitals,
            profile: Profile,
            mealResponse: MealResponseIndex.Result? = null,
            mealBoard: MealResponsePresentation.Board? = null,
        ): VitalsReadout = when (metric) {
            VitalsMetric.heart -> heart(m, history, vitals, profile)
            VitalsMetric.sleep -> sleep(m)
            VitalsMetric.hrv -> hrv(m)
            VitalsMetric.response -> response(mealBoard, mealResponse)
            VitalsMetric.stress -> stress(m, vitals)
            VitalsMetric.temp -> temp(m, history)
            VitalsMetric.steps -> steps(m, history)
            VitalsMetric.distance -> distance(m, history)
            VitalsMetric.active -> active(m, history)
        }

        // MARK: 01 · heart

        private fun heart(m: DailyMetrics, history: List<DailyMetrics>, vitals: LiveVitals, profile: Profile): VitalsReadout {
            val ticks = m.vitalsCurve
            val hrs = ticks.mapNotNull { it.hr }
            val gone = vitals.freshness == TickFreshness.gone
            val now = if (gone) null else (vitals.hr ?: ticks.lastOrNull { it.hr != null }?.hr)
            val resting = m.nightInputs?.rhr?.roundedInt()

            val restingBand = resting?.let { it.toDouble()..(it + 20).toDouble() }
            val sevenDayResting = mean(history.takeLast(8).dropLast(1).mapNotNull { it.nightInputs?.rhr })
            val placed = VitalsDialMath.heartCuts(profile.hrMax)
            val cuts = placed.cuts.map { it.roundedInt() }
            val restingDelta = delta(resting?.toDouble(), sevenDayResting, "BPM", "vs 7d", lowerIsBetter = true)

            val out = VitalsReadout(
                value = now?.toString(),
                unit = "BPM",
                dial = dial(placed.scale, placed.cuts, now?.toDouble(),
                    listOf(L("RESTING"), L("EASY"), L("AEROBIC"), L("PEAK")),
                    listOf(NB.blue1, NB.lime2, NB.ember1, NB.alert2)),
                footLeft = vitals.at?.let { L("LAST TICK %@", Fmt.clock(it)) } ?: L("NO TICK YET"),
                footRight = L("BOUNDS %d · %d · %d BPM", cuts[0], cuts[1], cuts[2]),
                chartNote = L("FIXED 40–160 BPM"),
                splitTitle = L("TIME IN ZONES"),
                splitTrailing = zoneTotal(m, ticks, profile),
                bands = heartZoneBands(m, ticks, profile),
                statLeft = VitalsStatPair.Model(L("RESTING HR"), resting?.toString(), "BPM",
                    restingDelta.first, restingDelta.second),
                statRight = VitalsStatPair.Model(L("24H MEAN"),
                    mean(hrs.map { it.toDouble() })?.roundedInt()?.toString(), "BPM",
                    if (hrs.isEmpty()) L("NO TICKS YET") else L("LOW %d · HIGH %d", hrs.min(), hrs.max()),
                    NB.lime1),
            )
            out.referenceBand = restingBand
            out.referenceLabel = restingBand?.let { L("RESTING BAND %d–%d", it.start.toInt(), it.endInclusive.toInt()) }
            return out
        }

        /** Week and month hero: a median on the same dial the live reading uses. The number is
         *  the median of daily medians so one loud hour cannot drag the window. */
        fun heartWindow(daily: List<List<Double>>, profile: Profile, days: Int): VitalsReadout {
            val placed = VitalsDialMath.heartCuts(profile.hrMax)
            val cuts = placed.cuts.map { it.roundedInt() }
            val median = HeartWindowMath.medianOfDailyMedians(daily)
            val worn = HeartWindowMath.wornDays(daily)
            val high = HeartWindowMath.extreme(daily) { a, b -> max(a, b) }
            val low = HeartWindowMath.extreme(daily) { a, b -> min(a, b) }
            val out = VitalsReadout(
                value = median?.roundedInt()?.toString(),
                unit = "BPM",
                dial = dial(placed.scale, placed.cuts, median,
                    listOf(L("RESTING"), L("EASY"), L("AEROBIC"), L("PEAK")),
                    listOf(NB.blue1, NB.lime2, NB.ember1, NB.alert2)),
                footLeft = L("%d DAYS WORN", worn),
                footRight = L("BOUNDS %d · %d · %d BPM", cuts[0], cuts[1], cuts[2]),
                chartNote = L("FIXED 40–160 BPM"),
                splitTitle = L("TIME IN ZONES"),
                splitTrailing = null,
                bands = emptyList(),
                statLeft = VitalsStatPair.Model(L("%d DAYS WORN", worn), worn.toString(), L("OF %d", days),
                    L("ROLLING"), null),
                statRight = VitalsStatPair.Model(L("WINDOW MAX"), high?.roundedInt()?.toString(), "BPM",
                    low?.let { L("LOW %d", it.roundedInt()) } ?: L("NO TICKS YET"), NB.lime1),
            )
            out.referenceBand = null
            return out
        }

        /** 08 rule 04 · the five server zones collapsed onto the board's four bands, or derived
         *  from the ticks when the day has not settled. Never a guessed name for a band nobody
         *  was in. */
        private fun heartZoneBands(m: DailyMetrics, ticks: List<VitalSample>, profile: Profile): List<VitalsSplit.Band> {
            val names = listOf(L("Rest"), L("Fat"), L("Aero"), L("Peak"))
            val tints = listOf(NB.lime1, NB.optimal2, NB.caution2, NB.alert2)
            var minutes = MutableList(4) { 0 }
            val zones = m.zoneMinutes
            if (zones != null && zones.size >= 5) {
                // Z1 · Z2 · Z3 · Z4+Z5 — the top two are one band on the board.
                minutes = mutableListOf(zones[0], zones[1], zones[2], zones[3] + zones[4])
            } else {
                // Tanaka off the profile's own birthday — the same ceiling 11 prints.
                val maxHR = max(120, profile.hrMax)
                for (tick in ticks) {
                    val hr = tick.hr ?: continue
                    if (hr <= 0) continue
                    val share = hr.toDouble() / maxHR
                    val i = if (share < 0.60) 0 else if (share < 0.70) 1 else if (share < 0.80) 2 else 3
                    minutes[i] += tickMinutes
                }
            }
            val total = minutes.sum()
            if (total <= 0) return emptyList()
            return (0 until 4).map { i ->
                VitalsSplit.Band(names[i], tints[i], minutes[i].toDouble(),
                    "${(minutes[i].toDouble() / total * 100).roundedInt()}%")
            }
        }

        private fun zoneTotal(m: DailyMetrics, ticks: List<VitalSample>, profile: Profile): String? {
            val total = heartZoneBands(m, ticks, profile).sumOf { it.share }.toInt()
            return if (total > 0) L("TOTAL %@", Fmt.duration(total)) else null
        }

        // MARK: 02 · sleep

        fun sleepHRVSamples(night: SleepSummary?, fallback: List<VitalSample>): List<VitalSample> {
            if (night == null) return emptyList()
            val samples = night.hrv?.map { VitalSample(ts = it.ts, hr = null, stress = null, hrv = it.rmssdMS) } ?: fallback
            return samples.filter {
                val value = it.hrv
                night.containsSleepTimestamp(it.ts) && value != null && value.isFinite() && value > 0
            }.sortedBy { it.ts }
        }

        private fun sleep(m: DailyMetrics): VitalsReadout {
            val night = m.sleep
            if (night == null || night.totalMinutes <= 0) {
                val out = empty(
                    unit = L("ASLEEP"),
                    foot = L("NO NIGHT ON RECORD"),
                    chartNote = L("4 STAGES"),
                    splitTitle = L("STAGE PROPORTIONS"),
                    statLeft = VitalsStatPair.Model(L("NIGHT HRV"), null, "MS", L("WEAR IT TONIGHT"), null),
                    statRight = VitalsStatPair.Model(L("NIGHT SPO2"), null, "%", L("WEAR IT TONIGHT"), null),
                )
                out.extraRight = VitalsStatPair.Model(L("WAKE EVENTS"), null, null, L("WEAR IT TONIGHT"), null)
                out.respirationLeft = VitalsStatPair.Model(L("MEAN RESPIRATION"), null, L("BREATHS / MIN"),
                    L("WEAR IT TONIGHT"), null)
                out.heartLow = VitalsStatPair.Model(L("SLEEP LOW HR"), null, "BPM", L("WEAR IT TONIGHT"), null)
                return out
            }

            val total = night.totalMinutes
            val spo2Percents = night.spo2.filter { night.containsSleepTimestamp(it.ts) }.map { it.percent }
            val spo2 = HealthSampleMapping.overnightOxygenSummary(spo2Percents)
            val hrv = mean(sleepHRVSamples(night, m.vitalsCurve).mapNotNull { it.hrv })
            val hrvBase = m.nightInputs?.hrvBase

            // A deep episode is one run of stage 0. The band files them; counting them is not
            // the same as claiming a 90-minute cycle model the device never used.
            val deepEpisodes = night.line.count { it.stage == 0 }

            val bands = mutableListOf<VitalsSplit.Band>()
            if (night.unstagedMinutes > 0 && night.line.isEmpty()) {
                // nothing staged to split
            } else if (night.line.isEmpty()) {
                // A row stored before the line was kept: the two totals it does have.
                bands += VitalsSplit.Band(L("Deep"), NB.violet1, night.deepMinutes.toDouble(), Fmt.duration(night.deepMinutes))
                bands += VitalsSplit.Band(L("Light"), NB.violet2, night.lightMinutes.toDouble(), Fmt.duration(night.lightMinutes))
            } else {
                // ⚠️ A stage line is not a promise of every stage. An absent stage is left out
                // rather than drawn as a zero-width band.
                bands += VitalsSplit.Band(L("Deep"), NB.violet1, night.deepMinutes.toDouble(), Fmt.duration(night.deepMinutes))
                bands += VitalsSplit.Band(L("Light"), NB.violet2, night.lightMinutes.toDouble(), Fmt.duration(night.lightMinutes))
                if (night.remMinutes > 0) {
                    bands += VitalsSplit.Band(L("REM"), NB.blue1, night.remMinutes.toDouble(), Fmt.duration(night.remMinutes))
                }
                if (night.awakeMinutes > 0) {
                    bands += VitalsSplit.Band(L("Awake"), NB.white.copy(alpha = 0.35f), night.awakeMinutes.toDouble(),
                        Fmt.duration(night.awakeMinutes))
                }
            }
            if (night.unstagedMinutes > 0) {
                bands.removeAll { it.share <= 0 }
                bands += VitalsSplit.Band(L("Unstaged"), NB.white.copy(alpha = 0.18f), night.unstagedMinutes.toDouble(),
                    Fmt.duration(night.unstagedMinutes))
            }

            val start = night.sleepStart
            val wake = night.wakeAt
            val window = if (start != null && wake != null && wake > start) {
                L("BED %@ · WAKE %@", Fmt.clock(start), Fmt.clock(wake))
            } else L("WINDOW NOT ON RECORD")

            val out = VitalsReadout(
                value = Fmt.duration(total),
                unit = L("ASLEEP"),
                dial = null,
                footLeft = window,
                footRight = if (deepEpisodes > 0) L("%d DEEP EPISODES", deepEpisodes) else null,
                chartNote = when {
                    night.unstagedMinutes > 0 -> L("PARTIAL STAGE COVERAGE")
                    night.line.isEmpty() -> L("TOTALS ONLY")
                    else -> L("AWAKE · REM · LIGHT · DEEP")
                },
                splitTitle = L("STAGE PROPORTIONS"),
                splitTrailing = L("TOTAL %@", Fmt.duration(total)),
                bands = bands,
                statLeft = VitalsStatPair.Model(L("NIGHT HRV"), hrv?.roundedInt()?.toString(), "MS",
                    hrvBase?.let { L("BASE %d MS", it.roundedInt()) } ?: L("NO BASELINE YET"),
                    VitalsMetric.hrv.tint),
                statRight = VitalsStatPair.Model(L("NIGHT SPO2"), spo2?.first?.toString(), "%",
                    spo2?.let { L("MIN %d%% · %d READINGS", it.second, spo2Percents.size) } ?: L("NO OVERNIGHT OXYGEN"),
                    NB.cyan1),
            )
            out.extraRight = VitalsStatPair.Model(
                L("WAKE EVENTS"),
                if (night.unstagedMinutes > 0) null else night.wakeCount.toString(),
                if (night.wakeCount == 1) L("WAKE") else L("WAKES"),
                when {
                    night.unstagedMinutes > 0 -> L("STAGES NOT MEASURED")
                    night.awakeMinutes > 0 -> L("%@ AWAKE", Fmt.duration(night.awakeMinutes))
                    else -> L("NONE STAGED AWAKE")
                },
                null,
            )
            val respiration = (night.respiration ?: emptyList()).filter {
                night.containsSleepTimestamp(it.ts) && it.breathsPerMinute.isFinite() && it.breathsPerMinute > 0
            }.map { it.breathsPerMinute }
            val respirationMean = if (respiration.isEmpty()) null else respiration.sum() / respiration.size
            out.respirationLeft = VitalsStatPair.Model(
                L("MEAN RESPIRATION"), respirationMean?.let { swiftFormat("%.1f", it) }, L("BREATHS / MIN"),
                if (respiration.isEmpty()) L("NO SLEEP RESPIRATION") else L("%d READINGS", respiration.size),
                NB.violet2)
            val rLow = respiration.minOrNull()
            val rHigh = respiration.maxOrNull()
            out.respirationRight = VitalsStatPair.Model(
                L("RESPIRATION RANGE"),
                if (rLow != null && rHigh != null) swiftFormat("%.1f–%.1f", rLow, rHigh) else null,
                L("BREATHS / MIN"), L("IN THE NIGHT WINDOW"), NB.violet2)

            // The night's floor, not a resting estimate: the lowest tick the band actually filed
            // inside the recorded window.
            val sleepHeart = (night.heartRate ?: m.vitalsCurve).filter { night.containsSleepTimestamp(it.ts) }
                .mapNotNull { it.hr }.filter { it > 0 }
            out.heartLow = VitalsStatPair.Model(
                L("SLEEP LOW HR"), sleepHeart.minOrNull()?.toString(), "BPM",
                if (sleepHeart.isEmpty()) L("NO NIGHT HEART RATE") else L("%d READINGS", sleepHeart.size),
                VitalsMetric.heart.tint)
            return out
        }

        // MARK: 03b · meal response

        private fun response(board: MealResponsePresentation.Board?, fallback: MealResponseIndex.Result?): VitalsReadout {
            val result = board?.index ?: fallback ?: MealResponseIndex.make(emptyList(), emptyList(), Instant.now())
            val range = board?.range ?: RollingPills.day
            val heroPoint = board?.heroPoint ?: result.latestPoint
            val heroPercent = board?.heroPercent ?: result.hero
            val split = board?.split ?: MealResponsePresentation.Split(result.below, result.near, result.above)
            val pointCount = board?.pointCount ?: result.trendPoints.size
            val hero = heroPoint?.let { MealResponseIndex.pointValue(it) }
            val bands = if (split.below + split.near + split.above == 0) emptyList() else listOf(
                VitalsSplit.Band(L("Below"), NB.ember1, split.below.toDouble(), "${split.below}"),
                VitalsSplit.Band(L("Near"), NB.compareAmber, split.near.toDouble(), "${split.near}"),
                VitalsSplit.Band(L("Above"), NB.optimal2, split.above.toDouble(), "${split.above}"),
            )
            val versus = heroPercent?.let { MealResponseIndex.signedPercent(it) }
            val foot: String = if (heroPoint != null) {
                if (result.ownMedianReady && versus != null) {
                    if (range == RollingPills.day) L("%@ VS OWN MEDIAN", versus) else L("%@ VS OWN", versus)
                } else L("%d / 5 BASELINE DAYS", result.baselineDays)
            } else if (range != RollingPills.day) {
                L("NO RESPONSE POINTS IN THIS WINDOW")
            } else when (result.empty) {
                MealResponseIndex.Empty.needs5Days -> L("NEEDS 5 DAYS")
                MealResponseIndex.Empty.switchOff -> L("SWITCH OFF")
                MealResponseIndex.Empty.allZeros -> L("ALL ZEROS")
                MealResponseIndex.Empty.empty, null -> L("NO TICKS TODAY")
            }
            val footRight: String? = when (range) {
                RollingPills.day -> if (pointCount == 0) null else L("%d POINTS", pointCount)
                RollingPills.week, RollingPills.month -> {
                    val days = board?.window?.recordedDays ?: 0
                    if (days == 0) null else L("%d DAYS", days)
                }
            }
            val out = VitalsReadout(
                value = hero,
                unit = null,
                dial = heroPercent?.let {
                    val placed = VitalsDialMath.responseCuts(it.toDouble())
                    dial(placed.scale, placed.cuts, it.toDouble(),
                        listOf(L("BELOW"), L("NEAR"), L("ABOVE")),
                        listOf(NB.ember1, NB.compareAmber, NB.optimal2))
                },
                footLeft = foot,
                footRight = footRight,
                chartNote = if (range == RollingPills.day)
                    L("EVERY %d MIN · MEASURED", VitalsTrace.defaultSlotMinutes.toInt()) else L("DAILY VS OWN"),
                splitTitle = L("VS OWN MEDIAN"),
                splitTrailing = if (pointCount == 0) null else L("%d POINTS", pointCount),
                bands = bands,
                statLeft = VitalsStatPair.Model(
                    range.responseAverageLabel,
                    (if (range == RollingPills.day) result.median24hPoint else heroPoint)?.let { MealResponseIndex.pointValue(it) },
                    null,
                    if (range == RollingPills.day) {
                        if (result.median24hPoint == null) L("NO TICKS TODAY") else L("MEASURED POINTS")
                    } else L("%d OF %d DAYS", board?.window?.recordedDays ?: 0, DetailWindow(DetailSurface.response, range).days),
                    NB.compareAmber),
                statRight = VitalsStatPair.Model(
                    if (range == RollingPills.day) L("VS OWN MEDIAN") else L("VS OWN"),
                    versus,
                    null,
                    if (result.ownMedianReady) {
                        if (range == RollingPills.day) L("LATEST POINT") else L("WINDOW AVERAGE")
                    } else L("%d / 5 BASELINE DAYS", result.baselineDays),
                    if (result.ownMedianReady) NB.compareAmber else null),
            )
            val median = result.ownMedian
            if (median != null && median > 0) {
                out.referenceBand = (median * 0.92)..(median * 1.08)
                out.referenceLabel = L("OWN MEDIAN %@", MealResponseIndex.pointValue(median))
                out.traceRange = MealResponseIndex.axis(result.trendPoints.map { it.optical }, median)
            } else {
                out.traceRange = MealResponseIndex.axis(result.trendPoints.map { it.optical }, null)
            }
            return out
        }

        // MARK: 03 · HRV

        private fun hrv(m: DailyMetrics): VitalsReadout {
            val night = m.nightInputs
            val value = night?.hrv
            val base = night?.hrvBase
            val ticks = m.vitalsCurve.mapNotNull { it.hrv }

            // Where the night's own ticks fell relative to the baseline — a distribution of
            // measurements rather than a verdict.
            var bands = emptyList<VitalsSplit.Band>()
            if (base != null && base > 0 && ticks.isNotEmpty()) {
                val below = ticks.count { it < base * 0.92 }
                val inBand = ticks.count { it >= base * 0.92 && it <= base * 1.08 }
                val above = ticks.count { it > base * 1.08 }
                bands = listOf(
                    VitalsSplit.Band(L("Below"), NB.ember1, below.toDouble(), "$below"),
                    VitalsSplit.Band(L("In band"), NB.blue1, inBand.toDouble(), "$inBand"),
                    VitalsSplit.Band(L("Above"), NB.optimal2, above.toDouble(), "$above"),
                )
            }
            val nights = night?.hrvNights ?: 0
            return VitalsReadout(
                value = value?.roundedInt()?.toString(),
                unit = "MS",
                dial = VitalsDialMath.ratioCuts(base ?: 0.0)?.let {
                    dial(it.scale, it.cuts, value, listOf(L("BELOW"), L("IN RANGE"), L("ABOVE")),
                        listOf(NB.ember1, NB.blue1, NB.optimal2))
                },
                footLeft = L("%d/14 NIGHTS ON FILE", nights),
                footRight = base?.let { L("BASE %d MS", it.roundedInt()) },
                chartNote = if (ticks.isEmpty()) L("NO RMSSD TICKS") else L("%d TICKS · 14-NIGHT ENVELOPE", ticks.size),
                splitTitle = L("TICKS VS BASELINE"),
                splitTrailing = if (ticks.isEmpty()) null else L("%d TICKS", ticks.size),
                bands = bands,
                statLeft = VitalsStatPair.Model(L("24H MEDIAN"), median(ticks)?.roundedInt()?.toString(), "MS",
                    if (ticks.isEmpty()) L("NO TICKS YET")
                    else L("LOW %d · HIGH %d", ticks.min().roundedInt(), ticks.max().roundedInt()),
                    VitalsMetric.hrv.tint),
                statRight = VitalsStatPair.Model(L("VS BASELINE"),
                    if (value != null && (base ?: 0.0) > 0) swiftFormat("%.2f", value / base!!) else null,
                    L("RATIO"),
                    if (nights >= 5) L("%d NIGHTS WEIGHED", nights) else L("NEEDS 5 NIGHTS"),
                    null),
            )
        }

        // MARK: 04 · stress

        private fun stress(m: DailyMetrics, vitals: LiveVitals): VitalsReadout {
            val ticks = m.vitalsCurve
            val values = ticks.mapNotNull { it.stress }
            val gone = vitals.freshness == TickFreshness.gone
            val now = if (gone) null else (vitals.stress ?: ticks.lastOrNull { it.stress != null }?.stress)
            val peak = ticks.filter { it.stress != null }.maxByOrNull { it.stress ?: 0 }
            val dayMean = mean(values.map { it.toDouble() })

            // Four bands of the same index, each tick five minutes wide.
            val minutes = MutableList(4) { 0 }
            for (value in values) {
                val i = if (value < 25) 0 else if (value < 50) 1 else if (value < 75) 2 else 3
                minutes[i] += tickMinutes
            }
            val names = listOf(L("Rest"), L("Low"), L("Mid"), L("High"))
            val tints = listOf(NB.optimal2, NB.lime1, NB.ember1, NB.alert2)
            val totalMinutes = minutes.sum()
            val bands = if (totalMinutes == 0) emptyList() else (0 until 4).map { i ->
                VitalsSplit.Band(names[i], tints[i], minutes[i].toDouble(), Fmt.duration(minutes[i]))
            }

            // A sympathetic event is a run of ticks over 75 — counted as runs, not as ticks.
            var events = 0
            var inEvent = false
            for (tick in ticks) {
                val s = tick.stress ?: continue
                if (s > 75) {
                    if (!inEvent) { events += 1; inEvent = true }
                } else inEvent = false
            }

            val cuts = VitalsDialMath.stressCuts()
            return VitalsReadout(
                value = now?.toString(),
                unit = "/ 100",
                dial = dial(cuts.scale, cuts.cuts, now?.toDouble(),
                    listOf(L("REST"), L("STEADY"), L("ELEVATED"), L("HIGH")),
                    listOf(NB.optimal2, NB.lime1, NB.ember1, NB.alert2)),
                footLeft = dayMean?.let { L("24H MEAN %d", it.roundedInt()) } ?: L("NO TICKS YET"),
                footRight = peak?.let { tick -> tick.stress?.let { L("PEAK %d AT %@", it, Fmt.clock(tick.ts)) } },
                chartNote = L("FIXED 0–100 INDEX"),
                splitTitle = L("TIME IN STRESS ZONES"),
                splitTrailing = if (totalMinutes > 0) L("TOTAL %@", Fmt.duration(totalMinutes)) else null,
                bands = bands,
                statLeft = VitalsStatPair.Model(L("RECOVERY TIME"),
                    if (minutes[0] > 0) Fmt.duration(minutes[0]) else null, null,
                    if (totalMinutes > 0) L("%d%% OF 24H", (minutes[0].toDouble() / totalMinutes * 100).roundedInt())
                    else L("NO TICKS YET"),
                    NB.optimal2),
                statRight = VitalsStatPair.Model(L("HIGH-LOAD EVENTS"),
                    if (values.isEmpty()) null else events.toString(),
                    if (events == 1) L("EVENT") else L("EVENTS"),
                    if (minutes[3] > 0) L("%@ OVER 75", Fmt.duration(minutes[3])) else L("NONE OVER 75"),
                    if (events > 0) NB.ember1 else null),
            )
        }

        // MARK: 05 · temperature

        /** ADR 0009 · last night against this wrist's own night range. Nothing daytime is
         *  judged; the daytime ticks stay on the page as description. */
        private fun temp(m: DailyMetrics, history: List<DailyMetrics>): VitalsReadout {
            val ticks = m.vitalsCurve
            val today = ticks.mapNotNull { it.temp }
            val night = SkinTempPresentation.nightRange(m, history)
            val range = night.range

            val names = listOf(L("Below"), L("In range"), L("Above"))
            val tints = listOf(NB.blue1, NB.optimal2, NB.ember1)
            val minutes = listOf(night.minutesBelow, night.minutesWithin, night.minutesAbove)
            val totalMinutes = minutes.sum()
            val bands = if (totalMinutes == 0) emptyList() else (0 until 3).map { i ->
                VitalsSplit.Band(names[i], tints[i], minutes[i].toDouble(), Fmt.duration(minutes[i]))
            }

            // Before the range exists the hero prints the measured skin temperature rather than
            // a deviation from nothing — a first week of real ticks is not an empty page.
            val hasVerdict = night.delta != null
            val value = if (hasVerdict) night.delta?.let { swiftFormat("%+.1f", it) }
            else night.latestSkin?.let { swiftFormat("%.1f", it) }

            val out = VitalsReadout(
                value = value,
                unit = if (hasVerdict) L("°C · LAST NIGHT") else L("°C SKIN"),
                dial = (if (hasVerdict) range?.let { VitalsDialMath.rangeCuts(it.lower, it.upper) } else null)?.let {
                    dial(it.scale, it.cuts, night.lastNightMean,
                        listOf(L("BELOW"), L("IN RANGE"), L("ABOVE")),
                        listOf(NB.blue1, NB.optimal2, NB.ember1))
                },
                footLeft = range?.let { L("YOUR RANGE %.1f–%.1f °C · %d NIGHTS", it.lower, it.upper, it.nights) }
                    ?: L("LEARNING · %d / 5 NIGHTS", night.learningNights),
                // The learning count is already the left foot; the right one stays the measurement.
                footRight = night.empty?.let { empty ->
                    if (empty == com.nextbody.hoop.band.SkinTempNightRange.Empty.needsFiveNights) null
                    else SkinTempPresentation.reason(empty, night.learningNights)
                } ?: night.latestSkin?.let { L("SKIN %.1f °C", it) },
                chartNote = if (range == null) L("FIXED 30–38 °C") else L("SCALED TO YOUR RANGE"),
                splitTitle = L("TIME OFF YOUR RANGE"),
                splitTrailing = if (totalMinutes > 0) L("LAST NIGHT %@", Fmt.duration(totalMinutes)) else null,
                bands = bands,
                statLeft = VitalsStatPair.Model(L("24H LOW"), today.minOrNull()?.let { swiftFormat("%.1f", it) }, "°C",
                    if (today.isEmpty()) L("NO TICKS YET") else L("%d TICKS · 24H", today.size), NB.blue1),
                statRight = VitalsStatPair.Model(L("24H HIGH"), today.maxOrNull()?.let { swiftFormat("%.1f", it) }, "°C",
                    // The daytime number is described, never scored (ADR 0009).
                    night.dayMean?.let { L("DAY MEAN %.1f °C", it) } ?: L("NO TICKS YET"), NB.ember1),
            )
            out.traceRange = SkinTempPresentation.axis(range, 1.5)
            out.referenceBand = range?.let { it.lower..it.upper }
            out.referenceLabel = range?.let { L("YOUR RANGE %.1f–%.1f °C", it.lower, it.upper) }
            out.referenceSpan = night.lastNight?.let { it.start..it.end }
            return out
        }

        // MARK: 06 · steps

        private fun steps(m: DailyMetrics, history: List<DailyMetrics>): VitalsReadout {
            val ticks = m.vitalsCurve
            val bins = VitalsMath.hourSum(ticks, m.day) { it.steps?.toDouble() }
            val total = daySteps(m)
            val metres = dayMetres(m)
            val activeKcal = dayActiveKcal(m)
            val peak = VitalsMath.peak(bins)
            val week = history.takeLast(8).dropLast(1).mapNotNull { daySteps(it) }

            // Cadence, per tick: steps in five minutes, which is what the band actually filed.
            var casual = 0.0
            var active = 0.0
            var run = 0.0
            for (tick in ticks) {
                val s = tick.steps ?: continue
                if (s <= 0) continue
                if (s < 150) casual += s else if (s < 400) active += s else run += s
            }
            val bands = if (casual + active + run == 0.0) emptyList() else listOf(
                VitalsSplit.Band(L("Casual"), NB.optimal2.copy(alpha = 0.45f), casual, Fmt.kcal(casual)),
                VitalsSplit.Band(L("Active"), NB.optimal2, active, Fmt.kcal(active)),
                VitalsSplit.Band(L("Run"), NB.lime1, run, Fmt.kcal(run)),
            )

            return VitalsReadout(
                value = total?.let { Fmt.kcal(it) },
                unit = L("STEPS"),
                dial = total?.let { today ->
                    VitalsDialMath.weekCuts(today, week)?.let {
                        dial(it.scale, it.cuts, today,
                            listOf(L("WELL BELOW"), L("YOUR USUAL RANGE"), L("ABOVE")),
                            listOf(NB.white.copy(alpha = 0.45f), NB.optimal2, NB.lime2))
                    }
                },
                footLeft = m.activeMinutes?.let { L("ACTIVE TIME %@", Fmt.duration(it)) } ?: L("NO ACTIVE TIME YET"),
                footRight = peak?.let { L("PEAK %@/H AT %@", Fmt.kcal(it.value), VitalsMath.clock(m.day, it.index * 60)) },
                chartNote = L("TODAY · PER HOUR"),
                splitTitle = L("CADENCE INTENSITY"),
                splitTrailing = total?.let { L("%@ STEPS", Fmt.kcal(it)) },
                bands = bands,
                statLeft = VitalsStatPair.Model(L("DISTANCE"), metres?.let { swiftFormat("%.2f", it / 1000) }, "KM",
                    metres?.let { L("%@ M WALKED", Fmt.kcal(it)) } ?: L("NO DISTANCE YET"), NB.violetPink),
                statRight = VitalsStatPair.Model(L("ACTIVITY BURN"), activeKcal?.let { Fmt.kcal(it) }, "KCAL",
                    if (activeKcal == null) L("NEEDS YOUR WEIGHT") else L("MOVEMENT ONLY"), NB.run1),
            )
        }

        // MARK: 07 · distance

        private fun distance(m: DailyMetrics, history: List<DailyMetrics>): VitalsReadout {
            val ticks = m.vitalsCurve
            val metres = dayMetres(m)
            val steps = daySteps(m)
            val activeKcal = dayActiveKcal(m)
            val week = history.takeLast(8).dropLast(1).mapNotNull { dayMetres(it) }

            // When the ground was covered, on the user day's own thirds.
            var morning = 0.0
            var afternoon = 0.0
            var night = 0.0
            for (tick in ticks) {
                val d = tick.dis ?: continue
                if (d <= 0) continue
                val hour = tick.ts.timeIntervalSince(m.day.start) / 3600
                if (hour < 8) morning += d else if (hour < 16) afternoon += d else night += d
            }
            val bands = if (morning + afternoon + night == 0.0) emptyList() else listOf(
                VitalsSplit.Band("04–12", NB.violetPink.copy(alpha = 0.45f), morning, distanceLabel(morning)),
                VitalsSplit.Band("12–20", NB.violetPink, afternoon, distanceLabel(afternoon)),
                VitalsSplit.Band("20–04", NB.violet1, night, distanceLabel(night)),
            )

            // Stride is the day's own two numbers divided: metres over steps, in centimetres.
            val stride = if (metres != null && steps != null && steps > 0) metres / steps * 100 else null

            return VitalsReadout(
                value = metres?.let { swiftFormat("%.2f", it / 1000) },
                unit = "KM",
                dial = metres?.let { today ->
                    VitalsDialMath.weekCuts(today, week)?.let {
                        dial(it.scale, it.cuts, today,
                            listOf(L("WELL BELOW"), L("YOUR USUAL RANGE"), L("ABOVE")),
                            listOf(NB.white.copy(alpha = 0.45f), NB.violetPink, NB.lime2))
                    }
                },
                footLeft = metres?.let { L("%@ METRES TODAY", Fmt.kcal(it)) } ?: L("NO DISTANCE YET"),
                footRight = m.activeMinutes?.let { L("ACTIVE %@", Fmt.duration(it)) },
                chartNote = L("CUMULATIVE · TODAY"),
                splitTitle = L("WHEN IT HAPPENED"),
                splitTrailing = metres?.let { L("%.2f KM", it / 1000) },
                bands = bands,
                statLeft = VitalsStatPair.Model(L("STRIDE LENGTH"), stride?.let { swiftFormat("%.0f", it) }, "CM",
                    steps?.let { L("%@ STEPS", Fmt.kcal(it)) } ?: L("NEEDS STEPS"), NB.violetPink),
                statRight = VitalsStatPair.Model(L("ACTIVITY BURN"), activeKcal?.let { Fmt.kcal(it) }, "KCAL",
                    if (activeKcal == null) L("NEEDS YOUR WEIGHT") else L("MOVEMENT ONLY"), NB.run1),
            )
        }

        // MARK: 08 · metabolic burn

        private fun active(m: DailyMetrics, history: List<DailyMetrics>): VitalsReadout {
            val clockNow = VitalsClock.now
            val now = minOf(clockNow, minOf(m.asOf ?: clockNow, m.day.end))
            val ticks = m.vitalsCurve
            val windows = ActiveEnergyModel.sportWindows(m)
            val split = ActiveEnergyMath.split(
                dayStart = m.day.start, now = now, bmr = m.bmr, bmrFull = m.bmrFull,
                eActive = m.eActive, eTrain = m.eTrain, eOutNow = m.eOutNow,
                ticks = ticks, sportWindows = windows)
            val hours = ActiveEnergyMath.hourly(dayStart = m.day.start, now = now, split = split,
                ticks = ticks, sportWindows = windows)
            val peak = ActiveEnergyMath.peakHour(hours)
            val bands = listOf(
                Triple(L("SPORT"), NB.lime1, split.sport),
                Triple(L("STEPS"), NB.lime1.copy(alpha = 0.75f), split.steps),
                Triple(L("INCIDENTAL"), NB.lime1.copy(alpha = 0.55f), split.incidental),
            ).mapNotNull { (name, tint, value) ->
                if (value == null || value <= 0) null else VitalsSplit.Band(name, tint, value, Fmt.kcal(value))
            }

            val week = history.takeLast(8).dropLast(1).mapNotNull { dayActiveEnergy(it) }
            return VitalsReadout(
                value = split.active?.let { Fmt.kcal(it) },
                unit = "KCAL",
                dial = split.active?.let { today ->
                    VitalsDialMath.weekCuts(today, week)?.let {
                        dial(it.scale, it.cuts, today,
                            listOf(L("WELL BELOW"), L("YOUR USUAL RANGE"), L("ABOVE")),
                            listOf(NB.white.copy(alpha = 0.45f), NB.lime1, NB.lime2))
                    }
                },
                footLeft = if (split.resting != null || split.active != null)
                    L("RESTING %@ + ACTIVE %@", Fmt.kcal(split.resting), Fmt.kcal(split.active))
                else L("NEEDS YOUR WEIGHT"),
                footRight = split.bmrFull?.let { L("FULL DAY BASELINE %@", Fmt.kcal(it)) },
                chartNote = L("TODAY · PER HOUR"),
                splitTitle = L("WHERE THE BURN CAME FROM"),
                splitTrailing = split.active?.let { L("%@ KCAL", Fmt.kcal(it)) },
                bands = bands,
                statLeft = VitalsStatPair.Model(L("PEAK BURN HOUR"), peak?.let { Fmt.kcal(it.value) }, "KCAL",
                    peak?.let { L("PEAK %@", VitalsMath.clock(m.day, it.index * 60)) } ?: L("HOURLY ENERGY NOT AVAILABLE"),
                    NB.lime1),
                statRight = VitalsStatPair.Model(L("RESTING BASELINE"), (split.bmrFull ?: split.resting)?.let { Fmt.kcal(it) },
                    "KCAL",
                    when {
                        split.bmrFull != null -> L("WHOLE DAY, UNMOVED")
                        split.resting != null -> L("ELAPSED SO FAR")
                        else -> L("NEEDS YOUR WEIGHT")
                    },
                    null),
            )
        }

        // MARK: arithmetic

        fun dial(scale: ClosedFloatingPointRange<Double>, cuts: List<Double>, value: Double?,
                 names: List<String>, tints: List<Color>): VitalsDial.Model {
            val edges = listOf(scale.start) + cuts + listOf(scale.endInclusive)
            val count = minOf(names.size, tints.size, max(0, edges.size - 1))
            val zones = (0 until count).map { i ->
                VitalsDial.Zone(names[i], tints[i], max(0.001, edges[i + 1] - edges[i]))
            }
            return VitalsDial.Model(
                zones = zones,
                fraction = value?.let { VitalsDialMath.fraction(it, scale) },
                activeIndex = value?.let { min(count - 1, VitalsDialMath.activeIndex(it, cuts)) },
                cuts = cuts,
            )
        }

        /** ADR 0008 · the score's own colour bands, without naming the night. */
        fun sleepDial(score: Int, contributors: Boolean = false): VitalsDial.Model {
            val placed = VitalsDialMath.sleepCuts()
            return dial(placed.scale, if (contributors) listOf(60.0, 70.0, 85.0) else placed.cuts, score.toDouble(),
                listOf("", "", "", ""), listOf(NB.ember1, NB.compareAmber, NB.violet1, NB.optimal2))
        }

        fun mean(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size

        fun median(values: List<Double>): Double? {
            if (values.isEmpty()) return null
            val sorted = values.sorted()
            val mid = sorted.size / 2
            return if (sorted.size % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2 else sorted[mid]
        }

        /** nil when every part is nil — a total of nothing is not zero. */
        fun sum(parts: List<Double?>): Double? {
            val present = parts.filterNotNull()
            return if (present.isEmpty()) null else present.sum()
        }

        /** "↓ 2 BPM vs 7d", and the colour that goes with the direction. Without both numbers
         *  it says so instead of printing a delta against a baseline that does not exist. */
        fun delta(value: Double?, vs: Double?, unit: String, suffix: String, lowerIsBetter: Boolean): Pair<String, Color?> {
            if (value == null || vs == null) return L("NO BASELINE YET") to null
            val diff = value - vs
            val rounded = abs(diff).rounded().toInt()
            if (rounded <= 0) return L("LEVEL %@", L(suffix)) to null
            val better = if (lowerIsBetter) diff < 0 else diff > 0
            return L("%@ %d %@ %@", if (diff < 0) "↓" else "↑", rounded, unit, L(suffix)) to
                (if (better) NB.optimal2 else NB.ember1)
        }

        /** A page whose metric has nothing on record at all. It keeps every frame the board
         *  drew and fills none of them in — 04B F5 · an empty page, not a zeroed one. */
        fun empty(unit: String?, foot: String, chartNote: String, splitTitle: String,
                  statLeft: VitalsStatPair.Model, statRight: VitalsStatPair.Model): VitalsReadout =
            VitalsReadout(value = null, unit = unit, dial = null, footLeft = foot, footRight = null,
                chartNote = chartNote, splitTitle = splitTitle, splitTrailing = null,
                bands = emptyList(), statLeft = statLeft, statRight = statRight)
    }
}
