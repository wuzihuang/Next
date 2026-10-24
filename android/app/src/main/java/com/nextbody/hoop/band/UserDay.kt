package com.nextbody.hoop.band

import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.timeIntervalSince
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.max

// Moved out of Models/Metrics.swift so the sync package can use it: `WearRun` counts a worn
// day in the user-day's own five-minute slots, and the type it counts them in cannot live
// in a file the package does not compile. Pure Foundation, unchanged otherwise.

/** F2 rule 03 · one calendar. A user day runs local 00:00 → 00:00 next day. */
class UserDay(
    /** The instant the window opens: local midnight on the day it starts. */
    val date: Instant,
) : Comparable<UserDay> {
    val id: Instant get() = date

    /**
     * Two user days are the same day if they start on the same calendar date.
     * ⚠️ Comparing the instants directly breaks across a DST change and across the two
     * places a UserDay is built — from `now`, and from a `yyyy-MM-dd` string off the wire.
     */
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is UserDay) return false
        val zone = currentZone()
        return date.atZone(zone).toLocalDate() == other.date.atZone(zone).toLocalDate()
    }

    override fun hashCode(): Int = date.atZone(currentZone()).toLocalDate().hashCode()

    override fun toString(): String = "UserDay($key)"

    val start: Instant get() = date

    /** The server's `user_day` string for this day. */
    val key: String get() = keyFormatter.format(date.atZone(currentZone()))

    val end: Instant get() = date.atZone(currentZone()).plusDays(1).toInstant()

    fun adding(days: Int): UserDay = UserDay(date.atZone(currentZone()).plusDays(days.toLong()).toInstant())

    /** Oldest → newest, `count` user days ending on this one. */
    fun rollingBack(count: Int): List<UserDay> = last(count, endingAt = this)

    /** Minutes elapsed inside the window at `now`, capped to the full window. */
    fun elapsedMinutes(now: Instant = Instant.now()): Int =
        max(0, (minOf(now, end).timeIntervalSince(start) / 60).toInt())

    val isClosed: Boolean get() = Instant.now() >= end

    /**
     * Applies a clock to this user day. With a midnight seam every hour lands on the
     * day itself; the branch survives so a non-zero `boundaryHour` still reads correctly.
     */
    fun pinningClock(instant: Instant, zone: ZoneId = currentZone()): Instant {
        val z = instant.atZone(zone)
        val hour = z.hour
        val minute = z.minute
        val baseDate = if (hour < boundaryHour) start.atZone(zone).plusDays(1).toLocalDate()
        else start.atZone(zone).toLocalDate()
        return ZonedDateTime.of(baseDate, java.time.LocalTime.of(hour, minute, 0), zone).toInstant()
    }

    override fun compareTo(other: UserDay): Int = date.compareTo(other.date)

    companion object {
        /**
         * Issue #19 · the cards say TODAY and the person reads midnight. They now agree.
         * A night that ends at 02:40 still belongs to the night it started, because a night is
         * keyed to the day the person woke on and stored, never cut out of this window.
         */
        const val boundaryHour = 0

        private val keyFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

        fun containing(instant: Instant, zone: ZoneId = currentZone(),
                       boundaryHour: Int = UserDay.boundaryHour): UserDay {
            val z = instant.atZone(zone)
            var startDate = z.toLocalDate()
            if (z.hour < boundaryHour) startDate = startDate.minusDays(1)
            val start = if (boundaryHour == 0) startDate.atStartOfDay(zone)
            else ZonedDateTime.of(startDate, java.time.LocalTime.of(boundaryHour, 0), zone)
            return UserDay(start.toInstant())
        }

        /** Parses the server's `yyyy-MM-dd` `user_day` string. */
        fun fromKey(key: String, zone: ZoneId = currentZone()): UserDay? =
            runCatching { UserDay(java.time.LocalDate.parse(key).atStartOfDay(zone).toInstant()) }.getOrNull()

        /** Oldest → newest, `count` user days ending at `end`. */
        fun last(count: Int, endingAt: UserDay): List<UserDay> {
            if (count <= 0) return emptyList()
            return (0 until count).map { endingAt.adding(-(count - 1 - it)) }
        }

        /** Elapsed hours since this day's local midnight (23 or 25 across DST, otherwise 24). */
        fun hours(instant: Instant, day: UserDay): Double = instant.timeIntervalSince(day.start) / 3600

        /**
         * Partition `0..<count` from the end in sevens. Oldest group first.
         * A 30-day window is 2 + 7 + 7 + 7 + 7; a 28-day window is four sevens.
         * (Swift `Range<Int>` → Kotlin `IntRange` built with `until`.)
         */
        fun weekRolls(count: Int): List<IntRange> {
            if (count <= 0) return emptyList()
            val newestFirst = mutableListOf<IntRange>()
            var cursor = count
            while (cursor > 0) {
                val start = max(0, cursor - 7)
                newestFirst.add(start until cursor)
                cursor = start
            }
            return newestFirst.reversed()
        }
    }
}
