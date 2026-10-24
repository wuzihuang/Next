package com.nextbody.hoop.band

import java.time.Instant
import kotlin.math.max
import kotlin.math.min

enum class TrainingBand(val raw: String) {
    light("LIGHT"), steady("STEADY"), heavy("HEAVY"), over("OVER"), unknown("NO TARGET")
}

sealed class TrainingRangeStatus {
    data object NoLoad : TrainingRangeStatus()
    data object NoTarget : TrainingRangeStatus()
    data class Below(val by: Double) : TrainingRangeStatus()
    data object InRange : TrainingRangeStatus()
    data class Above(val by: Double) : TrainingRangeStatus()
    data object Capped : TrainingRangeStatus()
}

/** Foundation `DateInterval`: a closed span of time. */
data class DateInterval(val start: Instant, val end: Instant) {
    val duration: Double get() = BandTime.interval(end, start)
}

data class TrainingCurvePoint(val ts: Instant, val load: Double)

data class TrainingCurveData(
    val segments: List<List<TrainingCurvePoint>>,
    val gaps: List<DateInterval>,
)

data class TrainingDayFacts(
    val day: UserDay,
    val load: Double?,
    val target: Double?,
    val zone: ClosedFloatingPointRange<Double>?,
    val zoneMinutes: List<Int>?,
    val steps: Int?,
    val activeKcal: Double?,
    val totalKcal: Double?,
    val worn: Boolean?,
    val isOpen: Boolean,
) {
    val hardMinutes: Int?
        get() {
            val z = zoneMinutes ?: return null
            if (z.size < 5) return null
            return z.drop(3).sum()
        }

    val easyMinutes: Int?
        get() {
            val z = zoneMinutes ?: return null
            if (z.size < 5) return null
            return z.take(3).sum()
        }

    /** A finished day that actually published a load. Today and a missing day stay out. */
    val isFinishedLoad: Boolean get() = !isOpen && load != null
}

data class TrainingWeekRoll(
    val start: UserDay,
    val end: UserDay,
    val days: Int,
    val wornDays: Int,
    val average: Double?,
)

/** Swift's five-way tuple from `bandCounts`. */
data class TrainingBandCounts(val light: Int, val steady: Int, val heavy: Int, val over: Int, val unknown: Int)

/** Arithmetic for the training page's three windows. No UI: the view only
 *  lays out what this file already reduced. */
object TrainingWindowMath {
    const val fullRing: Double = 21.0
    const val hardSessionMinutes = 20

    /** Contiguous days that published a load. An empty slot ends a run so WEEK / MONTH
     *  can break the line without drawing a zero or a missing-data mark. */
    fun lineRuns(values: List<Double?>): List<List<IndexedValue<Double>>> {
        val out = mutableListOf<List<IndexedValue<Double>>>()
        var run = mutableListOf<IndexedValue<Double>>()
        for ((i, value) in values.withIndex()) {
            if (value != null) {
                run.add(IndexedValue(i, value))
            } else if (run.isNotEmpty()) {
                out.add(run)
                run = mutableListOf()
            }
        }
        if (run.isNotEmpty()) out.add(run)
        return out
    }

    /** Mean of finished days that published a load. An open today and an empty
     *  slot stay out of the denominator — they are not zero. */
    fun averageLoad(days: List<TrainingDayFacts>): Double? {
        val values = days.filter { it.isFinishedLoad }.mapNotNull { it.load }
        if (values.isEmpty()) return null
        return values.sum() / values.size
    }

    /** Month hero: a typical finished day. Same grain as the week hero — never a 30-day sum. */
    fun typicalLoad(days: List<TrainingDayFacts>): Double? = averageLoad(days)

    fun typicalSteps(days: List<TrainingDayFacts>): Double? {
        val values = days.filter { it.isFinishedLoad }.mapNotNull { it.steps?.toDouble() }
        if (values.isEmpty()) return null
        return values.sum() / values.size
    }

    fun typicalActiveKcal(days: List<TrainingDayFacts>): Double? {
        val values = days.filter { it.isFinishedLoad }.mapNotNull { it.activeKcal }
        if (values.isEmpty()) return null
        return values.sum() / values.size
    }

    fun typicalTotalKcal(days: List<TrainingDayFacts>): Double? {
        val values = days.filter { it.isFinishedLoad }.mapNotNull { it.totalKcal }
        if (values.isEmpty()) return null
        return values.sum() / values.size
    }

    /** One typical day's five zones. Days without zones stay out. */
    fun typicalZones(days: List<TrainingDayFacts>): List<Double>? {
        val rows = days.filter { it.isFinishedLoad }.mapNotNull { day ->
            val z = day.zoneMinutes ?: return@mapNotNull null
            if (z.size < 5) null else z.take(5)
        }
        if (rows.isEmpty()) return null
        return (0 until 5).map { i -> rows.sumOf { it[i] }.toDouble() / rows.size }
    }

    fun wornCount(days: List<TrainingDayFacts>): Int = days.count { it.worn == true }

    /** A published zero is a recorded load; it is not proof of wearing the band. */
    fun recordedCount(days: List<TrainingDayFacts>): Int = days.count { it.load != null }

    fun emptyCount(days: List<TrainingDayFacts>): Int = days.size - recordedCount(days)

    /** A day counts as a session when it spent 20 minutes at Z4 or above. */
    fun sessionDays(days: List<TrainingDayFacts>): Int = days.count { (it.hardMinutes ?: 0) >= hardSessionMinutes }

    fun band(load: Double, zone: ClosedFloatingPointRange<Double>?): TrainingBand {
        if (zone == null) return TrainingBand.unknown
        if (load >= 20.9) return TrainingBand.over
        if (load < zone.start) return TrainingBand.light
        if (load > zone.endInclusive) return TrainingBand.heavy
        return TrainingBand.steady
    }

    fun bandCounts(days: List<TrainingDayFacts>): TrainingBandCounts {
        var light = 0; var steady = 0; var heavy = 0; var over = 0; var unknown = 0
        for (day in days) {
            val load = day.load ?: continue
            if (day.isOpen) continue
            when (band(load, day.zone)) {
                TrainingBand.light -> light += 1
                TrainingBand.steady -> steady += 1
                TrainingBand.heavy -> heavy += 1
                TrainingBand.over -> over += 1
                TrainingBand.unknown -> unknown += 1
            }
        }
        return TrainingBandCounts(light, steady, heavy, over, unknown)
    }

    fun rangeStatus(load: Double?, target: Double?, zone: ClosedFloatingPointRange<Double>?): TrainingRangeStatus {
        if (load == null || !load.isFinite()) return TrainingRangeStatus.NoLoad
        if (load >= 20.9) return TrainingRangeStatus.Capped
        val range = zone ?: target?.let { it..it } ?: return TrainingRangeStatus.NoTarget
        if (load < range.start) return TrainingRangeStatus.Below(range.start - load)
        if (load > range.endInclusive) return TrainingRangeStatus.Above(load - range.endInclusive)
        return TrainingRangeStatus.InRange
    }

    /** All columns share a minute scale, so 100 minutes is ten times 10 minutes. */
    fun zoneScaleMinutes(days: List<TrainingDayFacts>): Double =
        max(1.0, days.maxOfOrNull { ((it.easyMinutes ?: 0) + (it.hardMinutes ?: 0)).toDouble() } ?: 0.0)

    /** A five-minute sample contributes only its recorded value. Missing slots split
     *  the line; first/last missing intervals are visible too. Future time is not a gap. */
    fun curveData(input: List<TrainingCurvePoint>, day: UserDay, through: Instant): TrainingCurveData {
        val end = maxOf(day.start, minOf(through, day.end))
        val points = input.filter {
            it.ts >= day.start && it.ts <= end && it.load.isFinite() && it.load >= 0 && it.load <= 21
        }.sortedBy { it.ts }
        val first = points.firstOrNull()
            ?: return TrainingCurveData(emptyList(), if (end > day.start) listOf(DateInterval(day.start, end)) else emptyList())
        val segments = mutableListOf(mutableListOf(first))
        val gaps = mutableListOf<DateInterval>()
        if (first.ts > day.start) gaps.add(DateInterval(day.start, first.ts))
        for (point in points.drop(1)) {
            val previous = segments.lastOrNull()?.lastOrNull() ?: continue
            if (point.ts == previous.ts) continue
            if (BandTime.interval(point.ts, previous.ts) > 450) {
                gaps.add(DateInterval(previous.ts.plusSeconds(300), point.ts))
                segments.add(mutableListOf(point))
            } else {
                segments.last().add(point)
            }
        }
        segments.lastOrNull()?.lastOrNull()?.let { last ->
            val coveredThrough = last.ts.plusSeconds(300)
            if (BandTime.interval(end, coveredThrough) >= 300) gaps.add(DateInterval(coveredThrough, end))
        }
        return TrainingCurveData(segments, gaps)
    }

    fun dayFraction(instant: Instant, day: UserDay): Double =
        max(0.0, min(1.0, BandTime.interval(instant, day.start) / BandTime.interval(day.end, day.start)))

    /** Week rolls, oldest first. Groups of seven walking back from the end;
     *  a 30-day window is 2 + 7 + 7 + 7 + 7. */
    fun weekRolls(days: List<TrainingDayFacts>): List<TrainingWeekRoll> =
        UserDay.weekRolls(count = days.size).map { range ->
            val slice = days.subList(range.first, range.last + 1)
            TrainingWeekRoll(
                start = slice[0].day, end = slice[slice.size - 1].day, days = slice.size,
                wornDays = wornCount(slice), average = averageLoad(slice))
        }
}
