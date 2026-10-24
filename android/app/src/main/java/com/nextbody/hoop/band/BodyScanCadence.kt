package com.nextbody.hoop.band

import java.time.Instant
import java.time.ZoneId

/**
 * When the next body scan is worth taking, and what has changed since the first one.
 *
 * A wrist BIA reading moves with hydration, food and the hour of the day, so two scans a
 * day apart mostly measure the difference between two mornings rather than a change in the
 * body. A week is the shortest gap where the difference is likely to be the person.
 *
 * ⚠️ This is a cadence, not a streak. Missing it costs nothing, there is no run to keep,
 * and an overdue scan says DUE rather than counting days of failure — the product's whole
 * position on 打卡 is in the 词表, and this must not smuggle one in.
 */
object BodyScanCadence {
    const val days = 7

    /** Whole days until the next worthwhile scan. Zero means it is worth taking now. */
    fun daysLeft(since: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Int {
        val elapsed = BandTime.daysBetween(since, now, zone)
        return maxOf(0, days - maxOf(0, elapsed))
    }

    fun isDue(since: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean =
        daysLeft(since, now, zone) == 0

    /** What the first scan and the latest one say, as a difference.
     *
     *  Two scans taken on the same day are one data point, not a trend: a "since baseline"
     *  built from them would print a change that is entirely the hour of the measurement. */
    data class Change(val days: Int, val bodyFatPoints: Double?, val leanKg: Double?)

    fun change(firstAt: Instant, firstFat: Double?, firstLean: Double?,
               latestAt: Instant, latestFat: Double?, latestLean: Double?,
               zone: ZoneId = ZoneId.systemDefault()): Change? {
        val days = BandTime.daysBetween(firstAt, latestAt, zone)
        if (days < 1) return null
        val fat = if (firstFat != null && latestFat != null) latestFat - firstFat else null
        val lean = if (firstLean != null && latestLean != null) latestLean - firstLean else null
        if (fat == null && lean == null) return null
        return Change(days, fat, lean)
    }
}
