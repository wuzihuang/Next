package com.nextbody.hoop.band

import java.time.Instant

/** ADR 0026 · the body battery keeps being computed while the app is away, but only when
 *  someone is there to read it. The home-screen widget is that someone: it paints the
 *  glance and nothing else, and the glance is only ever written by this process.
 *  Without a widget there is no reader, and the phone's radio stays quiet in the background.
 *
 *  Every number here is a rule about *when to ask*, never about the reserve itself — the
 *  reserve is settled on the server from the ticks the pull brings up (F2 rule 02). */
object BackgroundRefreshPolicy {
    /** The background work identifier (iOS: BGTaskScheduler identifier). */
    const val taskIdentifier = "com.nextbody.hoop.refresh"

    /** Half an hour between background pulls. Eleven of them fit inside the six hours after
     *  which `BodyBatteryReadoutPolicy` withdraws the number, so a wrist in range keeps a
     *  printable score on the widget all day; the pull itself decides nothing about the value. */
    const val interval: Double = 30.0 * 60

    /** A pull is worth scheduling only when the phone can act on it: someone placed a
     *  widget, an account is signed in on this phone, and a band is bound to read from. */
    fun shouldSchedule(widgetCount: Int, signedIn: Boolean, bound: Boolean): Boolean =
        widgetCount > 0 && signedIn && bound

    /** The earliest moment the system may launch the next pull. Counted from the last pull
     *  that reached the server, so a background run does not follow a foreground sync by
     *  two minutes — and never earlier than now, so a stale `lastPullAt` cannot ask for the past. */
    fun nextBeginDate(now: Instant, lastPullAt: Instant?): Instant {
        if (lastPullAt == null || lastPullAt > now) return BandTime.adding(now, interval)
        return maxOf(now, BandTime.adding(lastPullAt, interval))
    }

    /** Whether a run's outcome counts as the task having done its job. `throttled` is a
     *  success: the coordinator declined because a fresher pull already exists. */
    fun completed(status: BandRefreshResult.Status): Boolean = when (status) {
        BandRefreshResult.Status.success, BandRefreshResult.Status.partial, BandRefreshResult.Status.throttled -> true
        else -> false
    }
}
