package com.nextbody.hoop.band

import java.util.Locale
import kotlin.math.floor

/** Swift `Double.rounded()` — schoolbook rounding, half away from zero (Kotlin's `round` is half-even). */
internal fun Double.roundedAway(): Double = if (this >= 0) floor(this + 0.5) else -floor(-this + 0.5)

/** Swift `String(format:)` with a fixed POSIX locale. */
internal fun fmt(format: String, vararg args: Any?): String = String.format(Locale.US, format, *args)

/** Swift `ClosedRange.contains` for an optional bound check. */
internal fun Double.within(lo: Double, hi: Double): Boolean = this >= lo && this <= hi

/** Median of a list; null when empty. Shared by the window maths. */
internal fun medianOf(values: List<Double>): Double? {
    if (values.isEmpty()) return null
    val sorted = values.sorted()
    val middle = sorted.size / 2
    return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2 else sorted[middle]
}

