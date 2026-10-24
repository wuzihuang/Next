package com.nextbody.hoop.band

import java.time.Instant

/** One report from the band during a sport mode. Zero energy/duration are valid;
 *  an unknown energy unit must never be presented as kcal. */
data class SportLiveInfo(
    /** SDK callback receipt, not an inferred device sampling timestamp. */
    val receivedAt: Instant = Instant.now(),
    val heartRate: Int? = null,
    /** Only populated by a source with a verified kcal contract, including a valid zero. */
    val caloriesKcal: Double? = null,
    /** VPDeviceSportControlModel does not document this counter's unit or availability. (UInt32) */
    val rawCalories: Long? = null,
    val distanceM: Int? = null,
    val durationSec: Int? = null,
    /** 0 not started · 1 running · 2 paused */
    val runState: Int? = null,
) {
    companion object {
        fun deviceReport(heartRate: Int, rawCalories: Long, durationSec: Int,
                         runState: Int, distanceM: Int? = null, receivedAt: Instant = Instant.now()): SportLiveInfo =
            SportLiveInfo(receivedAt = receivedAt, heartRate = if (heartRate in 1..255) heartRate else null,
                caloriesKcal = null, rawCalories = rawCalories, distanceM = distanceM,
                durationSec = if (durationSec >= 0) durationSec else null, runState = runState)
    }
}

/** Presentation freshness is deliberately independent of calorie/training integration.
 *  A 1 Hz poll is not proof the firmware sampled at 1 Hz; the SDK exposes no sample clock. */
object SportHeartFreshness {
    enum class State { live, stale, missing }

    fun state(receivedAt: Instant?, now: Instant): State {
        if (receivedAt == null) return State.missing
        val age = BandTime.interval(now, receivedAt)
        if (!age.isFinite() || age < 0 || age >= 10) return State.missing
        return if (age < 3) State.live else State.stale
    }
}
