package com.nextbody.hoop.band

/** The automatic-measurement interval is a device capability, not an app-wide constant.
 *  Veepoo reports either a positive step (step, 2 × step … 180 minutes) or zero when every
 *  whole-minute value from 0 through 180 is accepted. A firmware that reports a positive
 *  step may still accept finer whole-minute values, so the minutes below the step are
 *  offered too — the write is only believed when the band echoes the value back. */
object AutoMeasurementIntervalPolicy {
    const val maximumMinutes = 180

    fun options(minimumStepMinutes: Int): List<Int> {
        if (minimumStepMinutes < 0) return emptyList()
        if (minimumStepMinutes == 0) return (0..maximumMinutes).toList()
        if (minimumStepMinutes > maximumMinutes) return emptyList()
        val probed = (1 until minimumStepMinutes).toList()
        return probed + (minimumStepMinutes..maximumMinutes step minimumStepMinutes).toList()
    }

    fun isValid(minutes: Int, minimumStepMinutes: Int): Boolean =
        options(minimumStepMinutes).contains(minutes)
}
