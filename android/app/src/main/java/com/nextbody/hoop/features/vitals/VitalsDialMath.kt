package com.nextbody.hoop.features.vitals

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * The hero dial's ruler: a fixed scale, interior cuts that name the zones, and where a
 * reading sits. Views colour and label the zones; this file only places them.
 *
 * The old fill-rail used today's own min and max as the two ends, so the same 79 BPM
 * landed in a different place every day. A dial's scale does not move with the day.
 */
object VitalsDialMath {
    /** Swift's `(scale: ClosedRange<Double>, cuts: [Double])`. */
    data class Placed(val scale: ClosedFloatingPointRange<Double>, val cuts: List<Double>)

    /** 0…1 on `scale`. A value outside the scale is clamped rather than extrapolated. */
    fun fraction(value: Double, scale: ClosedFloatingPointRange<Double>): Double {
        val span = scale.endInclusive - scale.start
        if (span <= 0) return 0.0
        return min(1.0, max(0.0, (value - scale.start) / span))
    }

    /** Zone index for `value` given interior cuts. The last zone includes the upper bound. */
    fun activeIndex(value: Double, cuts: List<Double>): Int {
        var index = 0
        for (cut in cuts) {
            if (value < cut) return index
            index += 1
        }
        return index
    }

    /** One stretch of a mark that lies in a single zone. `from`/`to` run 0…1 with 0 at the
     *  mark's high end, which is the order a chart draws a column or a capsule in. */
    data class ZoneRun(val zone: Int, val from: Double, val to: Double)

    /**
     * How a mark spanning `low…high` is split across the zones it covers. Each run is returned
     * separately so the mark can carry a hard edge exactly where the reading crossed a cut.
     */
    fun zoneRuns(low: Double, high: Double, cuts: List<Double>): List<ZoneRun> {
        if (high <= low) return listOf(ZoneRun(activeIndex(high, cuts), 0.0, 1.0))
        val edges = listOf(high) + cuts.filter { it > low && it < high }.sortedDescending() + listOf(low)
        val span = high - low
        return (0 until edges.size - 1).mapNotNull { i ->
            val upper = edges[i]
            val lower = edges[i + 1]
            if (upper <= lower) return@mapNotNull null
            // The midpoint, so the run is classified by the band it occupies rather than by
            // a boundary value that belongs to the zone above it.
            ZoneRun(activeIndex((upper + lower) / 2, cuts), (high - upper) / span, (high - lower) / span)
        }
    }

    /** Tanaka zones on the same 40–160 ruler the heart chart uses. */
    fun heartCuts(maxHR: Int): Placed {
        val ceiling = max(120, maxHR).toDouble()
        val cuts = listOf(0.60, 0.70, 0.80).map { min(159.0, max(41.0, it * ceiling)) }
        return Placed(40.0..160.0, cuts)
    }

    fun stressCuts(): Placed = Placed(0.0..100.0, listOf(25.0, 50.0, 75.0))

    /** Sleep-score colour bands from ADR 0008. The labels stay off the dial. */
    fun sleepCuts(): Placed = Placed(0.0..100.0, listOf(40.0, 60.0, 80.0))

    /** HRV / meal-response style: a personal centre with a ± band around it. */
    fun ratioCuts(base: Double, inner: Double = 0.08, outer: Double = 0.50): Placed? {
        if (base <= 0) return null
        return Placed((base * (1 - outer))..(base * (1 + outer)),
            listOf(base * (1 - inner), base * (1 + inner)))
    }

    /** A measured range with pad on both sides so the outer zones have width. */
    fun rangeCuts(lower: Double, upper: Double, pad: Double = 0.5): Placed? {
        if (upper <= lower) return null
        return Placed((lower - pad)..(upper + pad), listOf(lower, upper))
    }

    /** Cumulative metrics against the last seven days. Usual is 80–115 % of the week mean.
     *  Fewer than three weekdays is not a range — it is noise. */
    fun weekCuts(today: Double, week: List<Double>): Placed? {
        if (week.size < 3) return null
        val mean = week.sum() / week.size
        if (mean <= 0) return null
        val usualLo = mean * 0.80
        val usualHi = mean * 1.15
        val top = maxOf(today, week.maxOrNull() ?: today, mean * 1.6)
        if (!(top > 0 && usualHi > usualLo)) return null
        return Placed(0.0..top, listOf(usualLo, usualHi))
    }

    /** Meal-response percent versus own median. Near is ±8, matching `MealResponseIndex`. */
    fun responseCuts(percent: Double): Placed {
        val extent = max(40.0, abs(percent) + 8)
        return Placed((-extent)..extent, listOf(-8.0, 8.0))
    }
}
