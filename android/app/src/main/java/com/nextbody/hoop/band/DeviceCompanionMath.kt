package com.nextbody.hoop.band

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Inclusive user days this NEXTBODY has been with the health account. WITH YOU.
 *
 *  The start is the earliest wrist tick or bind on this account — not the latest
 *  `devices.bound_at` after a radio swap, and not firmware saveDays. */
object DeviceCompanionMath {
    /** Earliest real instant wins. Empty / all-null is missing. */
    fun start(candidates: List<Instant?>): Instant? = candidates.filterNotNull().minOrNull()

    /** Same user day is 1. A missing or future stamp is null — the page draws a dash
     *  instead of inventing a day count. */
    fun days(boundAt: Instant?, now: Instant, zone: ZoneId = ZoneId.systemDefault()): Int? {
        if (boundAt == null) return null
        val start = UserDay.containing(boundAt, zone)
        val end = UserDay.containing(now, zone)
        val delta = ChronoUnit.DAYS.between(start.start.atZone(zone), end.start.atZone(zone)).toInt()
        if (delta < 0) return null
        return delta + 1
    }
}
