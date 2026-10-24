package com.nextbody.hoop.band

import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.max

/**
 * This wrist's own night range for skin temperature, and last night measured against it.
 *
 * ⚠️ Skin temperature is not core body temperature. A wrist sits around 33 °C, and the
 * daytime hours run 1–2 °C below the night because the arm is out from under the covers —
 * so a daytime tick is never judged here. Only a closed night is given a verdict, and only
 * against this person's own recent nights (ADR 0009). Nothing in this file feeds training
 * load, stress or any score.
 */
object SkinTempNightRange {
    data class Point(val ts: Instant, val celsius: Double)

    /** One recorded sleep window. `end` is the wake instant; a window whose end is still in
     *  the future is a night in progress and carries no conclusion. */
    data class Night(val start: Instant, val end: Instant) {
        val duration: Double get() = max(0.0, BandTime.interval(end, start))
        fun contains(ts: Instant): Boolean = ts >= start && ts < end
    }

    /** Why there is no verdict tonight. Never a reason to blank the page: the measured skin
     *  temperature is still printed beside it. */
    enum class Empty(val raw: String) {
        noNight("NO_NIGHT"), nightTooShort("SHORT"), tooFewTicks("FEW_TICKS"), needsFiveNights("NEEDS5")
    }

    /** Outside by up to one range width is mild; further out is well outside. The old page
     *  had one fixed ±0.3 °C step from stable straight to red, which is what called an
     *  ordinary night a deviation. */
    enum class Tier(val raw: String) {
        within("within"), mildAbove("mildAbove"), mildBelow("mildBelow"), wellAbove("wellAbove"), wellBelow("wellBelow");

        val isAbove: Boolean get() = this == mildAbove || this == wellAbove
        val isBelow: Boolean get() = this == mildBelow || this == wellBelow
        val isMild: Boolean get() = this == mildAbove || this == mildBelow
    }

    data class Range(
        val lower: Double,
        val upper: Double,
        val median: Double,
        /** How many valid nights the range was built from. */
        val nights: Int,
    ) {
        val width: Double get() = upper - lower
        fun contains(celsius: Double): Boolean = celsius >= lower && celsius <= upper
    }

    data class Result(
        val range: Range? = null,
        /** Valid nights behind last night, inside the look-back. Drives the learning count. */
        val sampleNights: Int = 0,
        val lastNightMean: Double? = null,
        /** The window last night's verdict belongs to — the chart bands only that stretch. */
        val lastNight: Night? = null,
        /** Signed °C against the range's median. null when there is no range or no verdict. */
        val delta: Double? = null,
        val tier: Tier? = null,
        val minutesBelow: Int = 0,
        val minutesWithin: Int = 0,
        val minutesAbove: Int = 0,
        val empty: Empty? = null,
        /** The most recent skin tick, verdict or not — the page always has this to print. */
        val latestSkin: Double? = null,
        val dayMean: Double? = null,
        val dayLow: Double? = null,
        val dayHigh: Double? = null,
        /** Daytime mean minus last night's mean. Described, never scored. */
        val dayNightGap: Double? = null,
    ) {
        val learningNights: Int get() = minOf(sampleNights, requiredNights)

        val analyticsState: String
            get() {
                if (tier != null) return "VERDICT"
                return empty?.raw ?: "EMPTY"
            }
    }

    /** A night the band recorded for less than three hours describes a nap, not a night. */
    const val minimumNightHours: Double = 3.0
    /** Below this share of five-minute slots the band was off the wrist for most of it. */
    const val minimumCoverage: Double = 0.6
    const val requiredNights = 5
    const val maximumSampleNights = 14
    const val lookbackDays = 28
    /** A perfectly steady sleeper would otherwise collapse the range to ±0.05 °C and be
     *  called out for every ordinary night. */
    const val halfWidthFloor = 0.2
    const val tickMinutes = 5

    fun make(
        points: List<Point>,
        nights: List<Night>,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
        dayBoundaryHour: Int = UserDay.boundaryHour,
    ): Result {
        val valid = points
            .filter { it.celsius.isFinite() && it.celsius >= 10 && it.celsius <= 50 && it.ts <= now }
            .sortedBy { it.ts }
        var result = Result(latestSkin = valid.lastOrNull()?.celsius)

        val closed = nights.filter { it.end > it.start && it.end <= now }.sortedBy { it.end }
        val lastNight = closed.lastOrNull()
        if (lastNight == null) {
            result = result.copy(empty = Empty.noNight)
            return addDaytime(result, valid, nights, now, zone, dayBoundaryHour)
        }

        // The sample: valid nights behind last night, inside the look-back, most recent first.
        val earliest = BandTime.addingDays(lastNight.end, -lookbackDays.toLong(), zone)
        val sample = closed.dropLast(1)
            .filter { it.end >= earliest }
            .mapNotNull { measure(it, valid)?.mean }
            .takeLast(maximumSampleNights)
        result = result.copy(sampleNights = sample.size, range = range(sample))

        val tonight = measure(lastNight, valid)
        result = result.copy(lastNight = lastNight, lastNightMean = tonight?.mean)

        val empty = when {
            lastNight.duration < minimumNightHours * 3600 -> Empty.nightTooShort
            tonight == null -> Empty.tooFewTicks
            result.range == null -> Empty.needsFiveNights
            else -> null
        }
        result = result.copy(empty = empty)

        val range = result.range
        if (range != null && tonight != null && empty == null) {
            var below = 0; var within = 0; var above = 0
            for (celsius in tonight.slotValues) {
                if (celsius < range.lower) below += tickMinutes
                else if (celsius > range.upper) above += tickMinutes
                else within += tickMinutes
            }
            result = result.copy(delta = tonight.mean - range.median, tier = tier(tonight.mean, range),
                minutesBelow = below, minutesWithin = within, minutesAbove = above)
        }

        return addDaytime(result, valid, nights, now, zone, dayBoundaryHour)
    }

    fun tier(celsius: Double, range: Range): Tier {
        if (range.contains(celsius)) return Tier.within
        val width = max(range.width, halfWidthFloor * 2)
        if (celsius > range.upper) return if (celsius <= range.upper + width) Tier.mildAbove else Tier.wellAbove
        return if (celsius >= range.lower - width) Tier.mildBelow else Tier.wellBelow
    }

    // MARK: one night

    private class NightMeasurement(
        val mean: Double,
        /** One value per occupied five-minute slot, for the minutes split. */
        val slotValues: List<Double>,
    )

    /** null when the band was off the wrist for too much of the window, or the night is a nap. */
    private fun measure(night: Night, points: List<Point>): NightMeasurement? {
        if (night.duration < minimumNightHours * 3600) return null
        val slots = max(1, (night.duration / (tickMinutes * 60).toDouble()).toInt())
        val bySlot = HashMap<Int, Double>()
        for (point in points) {
            if (!night.contains(point.ts)) continue
            val slot = BandTime.interval(point.ts, night.start).toInt() / (tickMinutes * 60)
            bySlot[slot] = point.celsius
        }
        if (bySlot.isEmpty() || bySlot.size.toDouble() / slots < minimumCoverage) return null
        val mean = mean(bySlot.values.toList()) ?: return null
        return NightMeasurement(mean, bySlot.entries.sortedBy { it.key }.map { it.value })
    }

    // MARK: the range

    fun range(nightlyMeans: List<Double>): Range? {
        if (nightlyMeans.size < requiredNights) return null
        val centre = medianOf(nightlyMeans) ?: return null
        val deviations = nightlyMeans.map { abs(it - centre) }
        val halfWidth = max(halfWidthFloor, 2 * (medianOf(deviations) ?: 0.0))
        return Range(lower = centre - halfWidth, upper = centre + halfWidth, median = centre, nights = nightlyMeans.size)
    }

    // MARK: the daytime, described only

    private fun addDaytime(result: Result, valid: List<Point>, nights: List<Night>,
                           now: Instant, zone: ZoneId, dayBoundaryHour: Int): Result {
        val dayStart = UserDay.containing(now, zone, dayBoundaryHour).start
        val daytime = valid.filter { point -> point.ts >= dayStart && nights.none { it.contains(point.ts) } }
            .map { it.celsius }
        if (daytime.isEmpty()) return result
        val dayMean = mean(daytime)
        val gap = if (dayMean != null && result.lastNightMean != null) dayMean - result.lastNightMean else null
        return result.copy(dayMean = dayMean, dayLow = daytime.minOrNull(), dayHigh = daytime.maxOrNull(),
            dayNightGap = gap ?: result.dayNightGap)
    }

    private fun mean(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size
}
