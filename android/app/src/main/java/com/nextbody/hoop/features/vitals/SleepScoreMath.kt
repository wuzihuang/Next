package com.nextbody.hoop.features.vitals

import com.nextbody.hoop.model.rounded
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max

/**
 * ADR 0008 · the arithmetic behind the sleep board's week and month windows, with no view
 * and no app types in it.
 *
 * Everything here is a median rather than a mean. One two-hour night — a wrist taken off at
 * 01:00 — drags a mean far enough to be read as a bad week.
 */
object SleepScoreMath {
    /** Prior canonical nights the server needs before it publishes a bedtime median and
     *  scores the regularity group. The UI counts up to this so the group never just says
     *  "not yet". */
    const val regularityBaselineNights = 3

    /** Keep the familiar minimum range, extending the ruler to include actual peaks. */
    fun hrvUpperBound(values: List<Double>): Double {
        val peak = values.filter { it.isFinite() && it > 0 }.maxOrNull() ?: 0.0
        return max(90.0, ceil(peak / 30) * 30)
    }

    fun effectiveWeights(values: List<Double?>, weights: List<Double>): List<Double?> {
        if (values.size != weights.size) return values.map { null }
        val present = values.zip(weights).map { (value, weight) ->
            if (value == null || !value.isFinite() || !weight.isFinite() || weight <= 0) null else weight
        }
        val total = present.filterNotNull().sum()
        if (total <= 0) return values.map { null }
        return present.map { it?.let { w -> w / total * 100 } }
    }

    fun bedtimeDeviation(bedtime: Double, baseline: Double): Double {
        val raw = (bedtime - baseline) % 1440.0
        return if (raw > 720) raw - 1440 else if (raw < -720) raw + 1440 else raw
    }

    fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2 else sorted[middle]
    }

    /** Tukey hinges for a bedtime box. */
    data class Box(val min: Double, val q1: Double, val median: Double, val q3: Double, val max: Double)

    /** Lower and upper halves exclude the median on an odd count. */
    fun box(values: List<Double>): Box? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val n = sorted.size
        val low = sorted[0]
        val high = sorted[n - 1]
        val mid = median(sorted) ?: return null
        if (n == 1) return Box(low, low, mid, high, high)
        val split = n / 2
        val lower = sorted.subList(0, split)
        val upper = if (n % 2 == 0) sorted.subList(split, n) else sorted.subList(split + 1, n)
        return Box(low, median(lower) ?: low, mid, median(upper) ?: high, high)
    }

    /** The lowest-scoring member. Ties go to the first in the given order. */
    fun <Key> weakest(scores: List<Pair<Key, List<Double>>>): Key? {
        var best: Pair<Key, Double>? = null
        for ((key, values) in scores) {
            val median = median(values) ?: continue
            if (best == null || median < best.second) best = key to median
        }
        return best?.first
    }

    /** `bed_offset` counts minutes past 18:00 local, unwound the same way to be printed. */
    fun bedClock(offset: Double): String {
        val minutes = ((offset.rounded().toInt() + 1080) % 1440 + 1440) % 1440
        return String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)
    }

    /** Stage percentages renormalised over the stages that were actually measured. */
    fun renormalised(shares: List<Double>): List<Double> {
        val total = shares.sum()
        if (total <= 0) return shares.map { 0.0 }
        return shares.map { it / total * 100 }
    }
}
