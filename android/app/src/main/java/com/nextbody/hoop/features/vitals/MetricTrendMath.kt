package com.nextbody.hoop.features.vitals

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * Arithmetic for the trend hero every rolling window now leads with. One value a user day
 * goes in and out come the window's headline, its change against the window before it, and
 * the month's week-by-week strip. No UI and no model types.
 *
 * ⚠️ A day with no value is absent from every figure here — never a zero (F2 rule 05).
 */
object MetricTrendMath {
    fun recorded(values: List<Double?>): List<Double> = values.filterNotNull()

    fun mean(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size

    fun median(values: List<Double>): Double? = HeartWindowMath.median(values)

    /** The window's one number: the median of its recorded days. */
    fun headline(values: List<Double?>): Double? = median(recorded(values))

    /** A rule for the field: the window's own middle day. Under three days it is not a
     *  habit, it is the only day there is, so nothing is drawn. */
    fun habit(values: List<Double?>, minimum: Int = 3): Double? {
        val present = recorded(values)
        return if (present.size >= minimum) median(present) else null
    }

    /** This window's headline against the previous window's. Both sides need `minimum`
     *  recorded days, or the comparison is two numbers that happen to be near each other. */
    fun delta(current: List<Double?>, prior: List<Double?>, minimum: Int = 3): Double? {
        val now = recorded(current)
        val before = recorded(prior)
        if (now.size < minimum || before.size < minimum) return null
        val a = median(now) ?: return null
        val b = median(before) ?: return null
        return a - b
    }

    /** One slice of the month strip. */
    data class Roll(val start: Int, val count: Int, val recorded: Int, val average: Double?)

    /** Oldest first. Thirty days become 2 + 7 + 7 + 7 + 7. */
    fun weekRolls(values: List<Double?>): List<Roll> {
        if (values.isEmpty()) return emptyList()
        val rolls = mutableListOf<Roll>()
        var cursor = values.size
        while (cursor > 0) {
            val start = max(0, cursor - 7)
            val slice = values.subList(start, cursor)
            val present = recorded(slice)
            rolls.add(Roll(start, slice.size, present.size, mean(present)))
            cursor = start
        }
        return rolls.reversed()
    }

    /**
     * A vertical ruler fitted around what was recorded: `pad` of air each side, both ends
     * snapped outward to a multiple of `step`, never narrower than `minimumSpan`, and
     * `fallback` when there is nothing to fit.
     */
    fun fittedScale(
        values: List<Double?>,
        step: Double,
        pad: Double,
        minimumSpan: Double,
        fallback: ClosedFloatingPointRange<Double>,
        including: ClosedFloatingPointRange<Double>? = null,
    ): ClosedFloatingPointRange<Double> {
        val present = recorded(values).toMutableList()
        if (including != null) present += listOf(including.start, including.endInclusive)
        val low = present.minOrNull()
        val high = present.maxOrNull()
        if (low == null || high == null || step <= 0) return fallback
        var lower = floor((low - pad) / step) * step
        var upper = ceil((high + pad) / step) * step
        if (upper - lower < minimumSpan) {
            val centre = (upper + lower) / 2
            lower = floor((centre - minimumSpan / 2) / step) * step
            upper = ceil((centre + minimumSpan / 2) / step) * step
        }
        return lower..upper
    }

    /** 0 at the ruler's floor, 1 at its top. Clamped, never extrapolated. */
    fun fraction(value: Double, scale: ClosedFloatingPointRange<Double>): Double {
        val span = scale.endInclusive - scale.start
        if (span <= 0) return 0.0
        return min(1.0, max(0.0, (value - scale.start) / span))
    }
}
