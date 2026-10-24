package com.nextbody.hoop.band

import kotlin.math.min

/**
 * Paper 09C · the home calories card is two numbers and one fill.
 *
 * The pair is EATEN and the signed delta (`eaten − target`). Negative is still
 * short (TO GO). Positive is over (OVER). Zero is the end of 没到, not the
 * start of 超了. NEXT_MEAL stays in the data layer for the model; this card
 * never prints it. Unlogged is not 0: without a known intake the card cannot
 * say 还差 or 超了.
 */
object FuelCardMath {
    sealed class Pair {
        /** No known intake, or no target. */
        data object Silent : Pair()
        /** `eaten ≤ target`. Associated value is `eaten − target` (0 or negative). */
        data class ToGo(val delta: Double) : Pair()
        data class Over(val delta: Double) : Pair()
    }

    data class Readout(
        val eaten: Double?,
        val target: Double?,
        val pair: Pair,
        /** EATEN / TARGET, capped at 1. Empty when either number is missing. */
        val fill: Double,
    )

    /** EATEN is the sum of concluded plates. The `day_fuel` header can still be
     *  UNLOGGED / 0 after a meal write: insert only dirties the day, and the next
     *  `load` used to paint that stale header over rows the user can already read.
     *  An empty list keeps `server` so a failed meal fetch does not blank a settled
     *  number. Fasted with no plates is the explicit zero. */
    fun eaten(mealKcals: List<Double>, server: Double?, fasted: Boolean): Double? {
        if (mealKcals.isNotEmpty()) return mealKcals.sum()
        if (fasted) return 0.0
        return server
    }

    fun readout(eaten: Double?, target: Double?): Readout {
        if (eaten == null) return Readout(eaten = null, target = target, pair = Pair.Silent, fill = 0.0)
        if (target == null || target <= 0) return Readout(eaten = eaten, target = target, pair = Pair.Silent, fill = 0.0)
        val delta = eaten - target
        if (delta > 0) return Readout(eaten = eaten, target = target, pair = Pair.Over(delta), fill = 1.0)
        return Readout(eaten = eaten, target = target, pair = Pair.ToGo(delta), fill = min(1.0, eaten / target))
    }
}
