package com.nextbody.hoop.band

/**
 * Fibre, sugar and sodium for a day.
 *
 * The estimate reports these only for foods whose composition it actually knows, so most
 * days have some rows that can say and some that cannot.
 *
 * ⚠️ A day's total is therefore all-or-nothing. Summing what is known and skipping the rest
 * prints a number that is true of *part* of the day while looking like the whole of it —
 * the same failure as writing 0 kcal for a plate the parser could not read. When a row is
 * silent the day is silent, and the page says how many rows were silent.
 */
object MealMicroTotals {
    fun total(values: List<Double?>): Double? {
        if (values.isEmpty() || !values.all { it != null }) return null
        return values.fold(0.0) { acc, v -> acc + (v ?: 0.0) }
    }

    fun unknownCount(values: List<Double?>): Int = values.count { it == null }

    /** True when at least one row reported this nutrient — the difference between "nothing
     *  on this day ever knows" (say nothing at all) and "three of five rows know". */
    fun anyKnown(values: List<Double?>): Boolean = values.any { it != null }
}
