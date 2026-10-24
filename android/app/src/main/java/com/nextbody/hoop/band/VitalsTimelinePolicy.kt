package com.nextbody.hoop.band

import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.timeIntervalSince
import java.time.Instant
import java.time.ZoneId
import kotlin.math.max

/** A closed display range. `end` is the last instant the chart may claim to contain. */
data class VitalsTimelineRange(val start: Instant, val end: Instant) {
    val span: Double get() = max(0.0, end.timeIntervalSince(start))

    fun contains(timestamp: Instant): Boolean = timestamp >= start && timestamp <= end
}

/** Product time semantics shared by the sync tests and the eight Vitals detail pages. */
object VitalsTimelinePolicy {
    /** Issue #19 · every card's day. Local midnight on `now`'s user day to `now`.
     *  The only window a card labelled TODAY may draw. */
    fun today(endingAt: Instant, zone: ZoneId = currentZone()): VitalsTimelineRange {
        val day = UserDay.containing(endingAt, zone)
        return userDay(start = day.start, end = day.end, now = endingAt)
    }

    /** A tick's own freshness, not a card window: how far back a NOW reading may be
     *  joined from when the newest row carries no value of its own. */
    fun rolling24Hours(endingAt: Instant): VitalsTimelineRange =
        VitalsTimelineRange(start = endingAt.addingTimeInterval(-24.0 * 60 * 60), end = endingAt)

    fun userDay(start: Instant, end: Instant, now: Instant): VitalsTimelineRange {
        val visibleEnd = minOf(end, maxOf(start, now))
        return VitalsTimelineRange(start = start, end = visibleEnd)
    }

    /** Stress is often missing on the newest worn tick — sleep PPG still has heart.
     *  Join the last positive reading if it still sits inside the rolling 24h window.
     *  (`previous` is Swift's `(value: Int, at: Date)?`.) */
    fun currentStress(latest: Int?, previous: Pair<Int, Instant>?, at: Instant): Int? =
        currentJoinedReading(latest, previous, at)

    /** The newest row is often a step / MET / calorie tick with no PPG. Heart stays
     *  that tick's own reading when it has one; otherwise the last positive reading
     *  inside the same 24h window the instrument already uses. */
    fun currentHeart(latest: Int?, previous: Pair<Int, Instant>?, at: Instant): Int? =
        currentJoinedReading(latest, previous, at)

    private fun currentJoinedReading(latest: Int?, previous: Pair<Int, Instant>?, tickAt: Instant): Int? {
        if (latest != null) return latest
        if (previous == null) return null
        return if (rolling24Hours(tickAt).contains(previous.second)) previous.first else null
    }
}
