package com.nextbody.hoop.features.vitals

import androidx.compose.ui.graphics.Color
import com.nextbody.hoop.band.ActiveEnergyMath
import com.nextbody.hoop.band.SkinTempNightRange
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.band.VitalsClock
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.roundedInt
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

// What the five rolling boards print. The day readouts stay in `VitalsReadout`; these are
// their week and month counterparts, kept apart because a window number is a different claim
// from a day number and the two must not quietly share a formula.
//
// ⚠️ Nothing here invents a day. A day the band filed nothing for is absent from every median,
// every total and every count — it is never a zero (F2 rule 05). That is why the worn-day
// count sits in the hero's foot on every one of these.

/** How a window's numbers print for each instrument — one day cannot be `6.4 KM` in one place
 *  and `6420 M` in another. */
fun VitalsReadout.Companion.windowFormat(metric: VitalsMetric): (Double) -> String = when (metric) {
    VitalsMetric.steps -> { v -> Fmt.kcal(v) }
    VitalsMetric.distance -> { v -> VitalsReadout.distanceLabel(v) }
    VitalsMetric.active -> { v -> Fmt.kcal(v) }
    else -> { v -> v.roundedInt().toString() }
}

fun VitalsReadout.Companion.windowUnit(metric: VitalsMetric): String? = when (metric) {
    VitalsMetric.steps -> L("STEPS")
    VitalsMetric.distance -> "KM"
    VitalsMetric.active -> "KCAL"
    else -> null
}

// MARK: 04 · stress over a window

/** The median of daily medians on the same 0–100 dial the live reading uses, so a week and a
 *  moment are read against one ruler. One loud afternoon cannot drag a month. */
fun VitalsReadout.Companion.stressWindow(daily: List<List<Double>>, ticks: List<VitalSample>, days: Int): VitalsReadout {
    val median = HeartWindowMath.medianOfDailyMedians(daily)
    val worn = HeartWindowMath.wornDays(daily)
    val peak = HeartWindowMath.extreme(daily) { a, b -> max(a, b) }
    val low = HeartWindowMath.extreme(daily) { a, b -> min(a, b) }
    val cuts = VitalsDialMath.stressCuts()

    // The same four bands the day page splits, over every tick in the window.
    val minutes = MutableList(4) { 0 }
    for (value in ticks.mapNotNull { it.stress }) {
        val i = if (value < 25) 0 else if (value < 50) 1 else if (value < 75) 2 else 3
        minutes[i] += VitalsReadout.tickMinutes
    }
    val names = listOf(L("Rest"), L("Low"), L("Mid"), L("High"))
    val tints = listOf(NB.optimal2, NB.lime1, NB.ember1, NB.alert2)
    val totalMinutes = minutes.sum()
    val bands = if (totalMinutes == 0) emptyList() else (0 until 4).map { i ->
        VitalsSplit.Band(names[i], tints[i], minutes[i].toDouble(), Fmt.duration(minutes[i]))
    }

    // Per worn day, not per window.
    val restPerDay = if (worn > 0) minutes[0] / worn else 0
    val highPerDay = if (worn > 0) minutes[3] / worn else 0

    return VitalsReadout(
        value = median?.roundedInt()?.toString(),
        unit = "/ 100",
        dial = VitalsReadout.dial(cuts.scale, cuts.cuts, median,
            listOf(L("REST"), L("STEADY"), L("ELEVATED"), L("HIGH")),
            listOf(NB.optimal2, NB.lime1, NB.ember1, NB.alert2)),
        footLeft = L("%d DAYS WORN", worn),
        footRight = peak?.let { L("WINDOW PEAK %d", it.roundedInt()) },
        chartNote = L("FIXED 0–100 INDEX"),
        splitTitle = L("TIME IN STRESS ZONES"),
        splitTrailing = if (totalMinutes > 0) L("TOTAL %@", Fmt.duration(totalMinutes)) else null,
        bands = bands,
        statLeft = VitalsStatPair.Model(L("RECOVERY TIME"),
            if (restPerDay > 0) Fmt.duration(restPerDay) else null, null,
            if (worn > 0) L("PER WORN DAY") else L("NO TICKS YET"), NB.optimal2),
        statRight = VitalsStatPair.Model(L("DAYS WORN"), worn.toString(), L("OF %d", days),
            when {
                highPerDay > 0 -> L("%@ OVER 75 A DAY", Fmt.duration(highPerDay))
                low != null -> L("NONE OVER 75")
                else -> L("NO TICKS YET")
            },
            if (highPerDay > 0) NB.ember1 else null),
    )
}

// MARK: 05 · temperature over a window

/** ADR 0009 holds across the window too: the range is learned from nights and the daytime ticks
 *  are described, never scored. The reference band is deliberately not drawn here. */
fun VitalsReadout.Companion.tempWindow(daily: List<List<Double>>, days: Int, range: SkinTempNightRange.Range?): VitalsReadout {
    val median = HeartWindowMath.medianOfDailyMedians(daily)
    val worn = HeartWindowMath.wornDays(daily)
    val high = HeartWindowMath.extreme(daily) { a, b -> max(a, b) }
    val low = HeartWindowMath.extreme(daily) { a, b -> min(a, b) }

    // Days, not minutes: this window's grain is a day.
    val counts = MutableList(3) { 0 }
    if (range != null) {
        for (day in daily) {
            val dayMedian = HeartWindowMath.median(day) ?: continue
            val i = if (dayMedian < range.lower) 0 else if (dayMedian > range.upper) 2 else 1
            counts[i] += 1
        }
    }
    val names = listOf(L("Below"), L("In range"), L("Above"))
    val tints = listOf(NB.blue1, NB.optimal2, NB.ember1)
    val totalDays = counts.sum()
    val bands = if (totalDays == 0) emptyList() else (0 until 3).map { i ->
        VitalsSplit.Band(names[i], tints[i], counts[i].toDouble(), L("%d D", counts[i]))
    }

    val out = VitalsReadout(
        value = median?.let { swiftFormat("%.1f", it) },
        unit = L("°C SKIN"),
        dial = range?.let { VitalsDialMath.rangeCuts(it.lower, it.upper) }?.let {
            VitalsReadout.dial(it.scale, it.cuts, median,
                listOf(L("BELOW"), L("IN RANGE"), L("ABOVE")),
                listOf(NB.blue1, NB.optimal2, NB.ember1))
        },
        footLeft = range?.let { L("YOUR RANGE %.1f–%.1f °C · %d NIGHTS", it.lower, it.upper, it.nights) }
            ?: L("%d DAYS WORN", worn),
        footRight = L("%d DAYS WORN", worn),
        chartNote = if (range == null) L("FIXED 30–38 °C") else L("SCALED TO YOUR RANGE"),
        splitTitle = L("DAYS OFF YOUR RANGE"),
        splitTrailing = if (totalDays > 0) L("%d DAYS MEDIANED", totalDays) else null,
        bands = bands,
        statLeft = VitalsStatPair.Model(L("WINDOW LOW"), low?.let { swiftFormat("%.1f", it) }, "°C",
            if (worn > 0) L("ACROSS %d DAYS", worn) else L("NO TICKS YET"), NB.blue1),
        statRight = VitalsStatPair.Model(L("WINDOW HIGH"), high?.let { swiftFormat("%.1f", it) }, "°C",
            median?.let { L("MEDIAN %.1f °C", it) } ?: L("NO TICKS YET"), NB.ember1),
    )
    out.traceRange = SkinTempPresentation.axis(range, 1.5)
    // ⚠️ Deliberately nil. See the note above the function.
    out.referenceBand = null
    out.referenceLabel = range?.let { L("YOUR NIGHT RANGE %.1f–%.1f °C", it.lower, it.upper) }
    return out
}

// MARK: 06 · 07 · 08 — the accumulated instruments over a window

/** Steps, metres and kilocalories share one window shape: a bar a day, a median day for the
 *  hero, and the window's own total in the foot. */
fun VitalsReadout.Companion.totalWindow(
    metric: VitalsMetric,
    slots: List<MetricDayBars.Slot>,
    days: List<DailyMetrics>,
    ticks: List<VitalSample>,
    count: Int,
): VitalsReadout {
    val recorded = MetricWindowMath.recorded(slots)
    val median = HeartWindowMath.median(recorded)
    val total = MetricWindowMath.sum(slots)
    val best = MetricWindowMath.best(slots)
    val format = windowFormat(metric)
    val worn = recorded.size

    // The hero is the middle day, not the sum: a window's headline number has to be comparable
    // with the day page's, and a month's total is not.
    val heroValue: String? = if (metric == VitalsMetric.distance) median?.let { swiftFormat("%.2f", it / 1000) }
    else median?.let(format)

    return VitalsReadout(
        value = heroValue,
        unit = windowUnit(metric),
        dial = null,
        footLeft = L("%d OF %d DAYS", worn, count),
        footRight = total?.let { L("TOTAL %@", if (metric == VitalsMetric.distance) VitalsReadout.distanceLabel(it) else format(it)) },
        chartNote = L("PER DAY · ROLLING"),
        splitTitle = windowSplitTitle(metric),
        splitTrailing = total?.let { if (metric == VitalsMetric.distance) VitalsReadout.distanceLabel(it) else format(it) },
        bands = windowBands(metric, days, ticks),
        statLeft = VitalsStatPair.Model(L("BEST DAY"),
            best?.total?.let { if (metric == VitalsMetric.distance) swiftFormat("%.2f", it / 1000) else format(it) },
            windowUnit(metric),
            best?.let { L("ON %@", Fmt.displayDate(it.start, "d MMM").uppercase(Locale.ROOT)) } ?: L("NO DAYS ON RECORD"),
            metric.tint),
        statRight = VitalsStatPair.Model(L("MEDIAN DAY"), heroValue, windowUnit(metric),
            if (worn > 0) L("ACROSS %d DAYS", worn) else L("NO DAYS ON RECORD"), null),
    )
}

private fun windowSplitTitle(metric: VitalsMetric): String = when (metric) {
    VitalsMetric.steps -> L("CADENCE INTENSITY")
    VitalsMetric.distance -> L("WHEN IT HAPPENED")
    VitalsMetric.active -> L("WHERE THE BURN CAME FROM")
    else -> L("DISTRIBUTION")
}

/** Each instrument's own split, summed across the window rather than re-asked per day. */
private fun windowBands(metric: VitalsMetric, days: List<DailyMetrics>, ticks: List<VitalSample>): List<VitalsSplit.Band> {
    when (metric) {
        VitalsMetric.steps -> {
            var casual = 0.0
            var active = 0.0
            var run = 0.0
            for (tick in ticks) {
                val s = tick.steps ?: continue
                if (s <= 0) continue
                if (s < 150) casual += s else if (s < 400) active += s else run += s
            }
            if (casual + active + run <= 0) return emptyList()
            return listOf(
                VitalsSplit.Band(L("Casual"), NB.optimal2.copy(alpha = 0.45f), casual, Fmt.kcal(casual)),
                VitalsSplit.Band(L("Active"), NB.optimal2, active, Fmt.kcal(active)),
                VitalsSplit.Band(L("Run"), NB.lime1, run, Fmt.kcal(run)),
            )
        }
        VitalsMetric.distance -> {
            // The user day's own thirds, taken against the day each tick belongs to.
            var morning = 0.0
            var afternoon = 0.0
            var night = 0.0
            for (tick in ticks) {
                val d = tick.dis ?: continue
                if (d <= 0) continue
                val hour = tick.ts.timeIntervalSince(UserDay.containing(tick.ts).start) / 3600
                if (hour < 8) morning += d else if (hour < 16) afternoon += d else night += d
            }
            if (morning + afternoon + night <= 0) return emptyList()
            return listOf(
                VitalsSplit.Band("04–12", NB.violetPink.copy(alpha = 0.45f), morning, VitalsReadout.distanceLabel(morning)),
                VitalsSplit.Band("12–20", NB.violetPink, afternoon, VitalsReadout.distanceLabel(afternoon)),
                VitalsSplit.Band("20–04", NB.violet1, night, VitalsReadout.distanceLabel(night)),
            )
        }
        VitalsMetric.active -> {
            var sport = 0.0
            var walk = 0.0
            var incidental = 0.0
            val now = VitalsClock.now
            for (day in days) {
                val end = minOf(day.day.end, day.asOf ?: now)
                val split = ActiveEnergyMath.split(
                    dayStart = day.day.start, now = minOf(end, now),
                    bmr = day.bmr, bmrFull = day.bmrFull,
                    eActive = day.eActive, eTrain = day.eTrain, eOutNow = day.eOutNow,
                    ticks = day.vitalsCurve,
                    sportWindows = ActiveEnergyModel.sportWindows(day))
                sport += split.sport ?: 0.0
                walk += split.steps ?: 0.0
                incidental += split.incidental ?: 0.0
            }
            val parts: List<Triple<String, Color, Double>> = listOf(
                Triple(L("SPORT"), NB.lime1, sport),
                Triple(L("STEPS"), NB.lime1.copy(alpha = 0.75f), walk),
                Triple(L("INCIDENTAL"), NB.lime1.copy(alpha = 0.55f), incidental),
            )
            return parts.mapNotNull { (name, tint, value) ->
                if (value > 0) VitalsSplit.Band(name, tint, value, Fmt.kcal(value)) else null
            }
        }
        else -> return emptyList()
    }
}
