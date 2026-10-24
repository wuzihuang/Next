package com.nextbody.hoop.features.vitals

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** Arithmetic for the heart page's three windows. No UI: the view only lays out
 *  what this file already reduced. */
object HeartWindowMath {
    fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2 else sorted[mid]
    }

    /** One median a day, then the median of those. A two-hour nap does not drag a week. */
    fun medianOfDailyMedians(daily: List<List<Double>>): Double? = median(daily.mapNotNull { median(it) })

    /** A day counts as worn when it filed at least one value. Empty is not zero. */
    fun wornDays(daily: List<List<Double>>): Int = daily.count { it.isNotEmpty() }

    fun extreme(daily: List<List<Double>>, pick: (Double, Double) -> Double): Double? {
        val flat = daily.flatten()
        val first = flat.firstOrNull() ?: return null
        return flat.drop(1).fold(first, pick)
    }

    /** How wide one equal slot is when `span` covers `days` user days. DST makes a day
     *  23 or 25 hours; dividing the real span keeps one bar a day. */
    fun slotSeconds(span: Double, days: Int): Double {
        if (days <= 0 || span <= 0) return 0.0
        return span / days
    }

    /** Which of `days` equal slots `fraction` lands in. Clamped, never extrapolated. */
    fun slotIndex(fraction: Double, days: Int): Int {
        if (days <= 0) return 0
        val clamped = min(1.0, max(0.0, fraction))
        return min(days - 1, max(0, floor(clamped * days).toInt()))
    }
}
