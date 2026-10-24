package com.nextbody.hoop.band

import java.time.Instant
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min

data class FuelDayFacts(
    val day: UserDay,
    val intake: Double?,
    val burned: Double?,
    val foodCount: Int,
    val isFasted: Boolean,
    val isOpen: Boolean,
) {
    val gap: Double?
        get() {
            if (intake == null || burned == null) return null
            return intake - burned
        }
}

data class FuelWeekRoll(
    val start: UserDay,
    val end: UserDay,
    val days: Int,
    val fastedDays: Int,
    val avgIn: Double?,
    val avgOut: Double?,
    val avgGap: Double?,
    val intakeDays: Int,
    val burnedDays: Int,
    val pairedDays: Int,
)

data class FuelWindowTotal(
    val intake: Double?,
    val burned: Double?,
    val gap: Double?,
    val intakeDays: Int,
    val burnedDays: Int,
    val pairedDays: Int,
)

data class FuelClockPoint(val x: Double, val y: Double, val startsSegment: Boolean = false)

/** Swift's `(solid: [FuelClockPoint], dashed: [FuelClockPoint])`. */
data class FuelClockCurve(val solid: List<FuelClockPoint>, val dashed: List<FuelClockPoint>) {
    companion object { val empty = FuelClockCurve(emptyList(), emptyList()) }
}

/** Arithmetic for the calories page's three windows. No UI: the view only lays out
 *  what this file already reduced. */
object FuelWindowMath {
    /** Known values accumulate independently. A difference needs both values on
     *  the same day; an unlogged day is not a fasted zero. */
    fun sum(days: List<FuelDayFacts>): FuelWindowTotal? {
        val ins = days.mapNotNull { it.intake }
        val outs = days.mapNotNull { it.burned }
        val gaps = days.mapNotNull { it.gap }
        if (ins.isEmpty() && outs.isEmpty()) return null
        fun sumKnown(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum()
        return FuelWindowTotal(intake = sumKnown(ins), burned = sumKnown(outs), gap = sumKnown(gaps),
            intakeDays = ins.size, burnedDays = outs.size, pairedDays = gaps.size)
    }

    /** Only days with a recorded value enter that channel's denominator. */
    fun perDay(sum: FuelWindowTotal, slots: Int): FuelWindowTotal? {
        if (slots <= 0) return null
        return FuelWindowTotal(
            intake = sum.intake?.let { if (sum.intakeDays > 0) it / sum.intakeDays else null },
            burned = sum.burned?.let { if (sum.burnedDays > 0) it / sum.burnedDays else null },
            gap = sum.gap?.let { if (sum.pairedDays > 0) it / sum.pairedDays else null },
            intakeDays = sum.intakeDays, burnedDays = sum.burnedDays, pairedDays = sum.pairedDays)
    }

    /** Four week rolls, newest first. Today remains visible in the daily bars but
     *  an unfinished day cannot lower the estimate of a typical whole day. */
    fun weekRolls(days: List<FuelDayFacts>): List<FuelWeekRoll> =
        UserDay.weekRolls(count = days.size).reversed().map { range ->
            val slice = days.subList(range.first, range.last + 1)
            val closed = slice.filter { !it.isOpen }
            val total = sum(closed)
            val per = total?.let { perDay(it, slice.size) }
            FuelWeekRoll(
                start = slice[0].day, end = slice[slice.size - 1].day,
                days = slice.size, fastedDays = closed.count { it.isFasted },
                avgIn = per?.intake, avgOut = per?.burned, avgGap = per?.gap,
                intakeDays = per?.intakeDays ?: 0, burnedDays = per?.burnedDays ?: 0,
                pairedDays = per?.pairedDays ?: 0)
        }

    /** Weight week averages by their observed days; sparse weeks do not count as
     *  seven zeros or carry the same weight as a fully observed week. */
    fun typicalDay(rolls: List<FuelWeekRoll>): FuelWindowTotal? {
        val intakeDays = rolls.sumOf { it.intakeDays }
        val burnedDays = rolls.sumOf { it.burnedDays }
        val pairedDays = rolls.sumOf { it.pairedDays }
        if (intakeDays <= 0 && burnedDays <= 0) return null
        val intake = rolls.fold(0.0) { acc, r -> acc + (r.avgIn ?: 0.0) * r.intakeDays }
        val burned = rolls.fold(0.0) { acc, r -> acc + (r.avgOut ?: 0.0) * r.burnedDays }
        val gap = rolls.fold(0.0) { acc, r -> acc + (r.avgGap ?: 0.0) * r.pairedDays }
        return FuelWindowTotal(
            intake = if (intakeDays > 0) intake / intakeDays else null,
            burned = if (burnedDays > 0) burned / burnedDays else null,
            gap = if (pairedDays > 0) gap / pairedDays else null,
            intakeDays = intakeDays, burnedDays = burnedDays, pairedDays = pairedDays)
    }

    /** The full user day, to the following day's same clock. Calendar arithmetic
     *  preserves the extra/missing hour when daylight saving changes. */
    fun dayEnd(dayStart: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant =
        BandTime.addingDays(dayStart, 1, zone)

    fun clockFraction(at: Instant, dayStart: Instant, zone: ZoneId = ZoneId.systemDefault()): Double {
        val span = BandTime.interval(dayEnd(dayStart, zone), dayStart)
        return min(1.0, max(0.0, BandTime.interval(at, dayStart) / span))
    }

    fun clockLabels(dayStart: Instant, zone: ZoneId = ZoneId.systemDefault()): List<String> {
        val span = BandTime.interval(dayEnd(dayStart, zone), dayStart)
        return (0..4).map { i ->
            val at = BandTime.adding(dayStart, span * i / 4).atZone(zone)
            val hour = at.hour; val minute = at.minute
            if (minute == 0) fmt("%02d", hour) else fmt("%02d:%02d", hour, minute)
        }
    }

    /** Step polyline: hold, jump at each meal, hold to `now`, then a dashed run to `projectTo`. */
    fun intakeSteps(meals: List<Pair<Instant, Double>>, dayStart: Instant, now: Instant,
                    projectTo: Double?, zone: ZoneId = ZoneId.systemDefault()): FuelClockCurve {
        val nowX = clockFraction(now, dayStart, zone)
        val ordered = meals.sortedBy { it.first }
        var y = 0.0
        val solid = mutableListOf(FuelClockPoint(0.0, 0.0))
        for (meal in ordered) {
            val x = clockFraction(meal.first, dayStart, zone)
            if (x > nowX) break
            if (solid.last().x != x || solid.last().y != y) solid.add(FuelClockPoint(x, y))
            y += meal.second
            solid.add(FuelClockPoint(x, y))
        }
        if (solid.last().x != nowX) solid.add(FuelClockPoint(nowX, y))
        val dashed = when {
            projectTo != null && nowX < 1 -> listOf(FuelClockPoint(nowX, y), FuelClockPoint(1.0, projectTo))
            nowX < 1 -> listOf(FuelClockPoint(nowX, y), FuelClockPoint(1.0, y))
            else -> emptyList()
        }
        return FuelClockCurve(solid, dashed)
    }

    /** Same source priority and valid range as `nb.activity_met`: use native MET,
     *  otherwise 500 steps in five minutes approximates 3 MET, capped at 5. */
    fun activityMet(met: Double? = null, steps: Int?): Double? {
        if (met != null && met.isFinite() && met >= 0.5 && met <= 25) return met
        if (steps == null || steps < 0) return null
        return 1 + 2 * min(2.0, steps.toDouble() / 500)
    }

    /** Resting accumulates with time; activity uses the same net MET as settlement.
     *  Scaling these two components separately keeps exercise from changing the resting
     *  slope. A settled aggregate with no timed activity evidence has no invented curve. */
    fun burnCurve(dayStart: Instant, now: Instant, burnedNow: Double, burnedFull: Double?,
                  restingNow: Double?, ticks: List<VitalSample>,
                  zone: ZoneId = ZoneId.systemDefault()): FuelClockCurve {
        if (restingNow == null || restingNow < 0 || burnedNow < restingNow || now <= dayStart) return FuelClockCurve.empty
        val active = burnedNow - restingNow
        val samples = ticks.filter { it.ts >= dayStart && it.ts <= now }.sortedBy { it.ts }
        val weights = samples.map { max(0.0, (activityMet(it.met, it.steps) ?: 1.0) - 1) }
        val total = weights.sum()
        if (!(active == 0.0 || total > 0)) return FuelClockCurve.empty
        val elapsed = BandTime.interval(now, dayStart)
        fun point(at: Instant, movement: Double) = FuelClockPoint(
            x = clockFraction(at, dayStart, zone),
            y = restingNow * BandTime.interval(at, dayStart) / elapsed + movement)
        val solid = mutableListOf(point(dayStart, 0.0))
        var cumulative = 0.0
        for ((sample, weight) in samples.zip(weights)) {
            // Recorded ticks are discrete five-minute energy contributions, including
            // the opening tick; no duration or movement is invented across a missing run.
            val prior = if (total > 0) active * cumulative / total else 0.0
            solid.add(point(sample.ts, prior))
            cumulative += weight
            val movement = if (total > 0) active * cumulative / total else 0.0
            if (weight > 0) solid.add(point(sample.ts, movement))
        }
        solid.add(FuelClockPoint(clockFraction(now, dayStart, zone), burnedNow))
        val nowX = clockFraction(now, dayStart, zone)
        val dashed = if (nowX < 1 && burnedFull != null)
            listOf(FuelClockPoint(nowX, burnedNow), FuelClockPoint(1.0, max(burnedNow, burnedFull)))
        else emptyList()
        return FuelClockCurve(solid, dashed)
    }

    /** Explicitly basal-only: callers without movement cannot label total burn as basal. */
    fun burnLine(dayStart: Instant, now: Instant, burnedNow: Double, burnedFull: Double?,
                 zone: ZoneId = ZoneId.systemDefault()): FuelClockCurve =
        burnCurve(dayStart, now, burnedNow, burnedFull, restingNow = burnedNow, ticks = emptyList(), zone = zone)

    fun chartMax(budget: Double?, intake: Double, burnedNow: Double?, burnedFull: Double?): Double {
        val raw = listOfNotNull(budget, intake, burnedNow, burnedFull).maxOrNull() ?: 0.0
        return max(raw, 1.0)
    }
}
