package com.nextbody.hoop.band

import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.swiftFormat
import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.max

/**
 * Unitless meal-response index versus this wrist's own daytime median.
 *
 * Vendor optical scalars stay opaque. Screens print only the signed percent, the empty
 * reason, and the Below / Near / Above counts. Near is ±8 % (ratio 0.92–1.08).
 */
object MealResponseIndex {
    data class Point(var ts: Instant, var optical: Double)

    data class SleepWindow(var start: Instant, var end: Instant) {
        fun contains(ts: Instant): Boolean = ts >= start && ts < end
    }

    enum class Empty(val raw: String) {
        needs5Days("NEEDS5"),
        switchOff("OFF"),
        allZeros("ZERO"),
        empty("EMPTY"),
    }

    data class ScatterPoint(var ts: Instant, var percent: Int)

    data class Result(
        /** Latest valid vendor point in today's 04:00 user day. This can be shown before
         *  the five-day personal baseline is ready. */
        var latestPoint: Double?,
        /** Raw valid points in the rolling 24-hour chart window. */
        var trendPoints: List<Point>,
        var median24hPoint: Double?,
        /** Daytime median after five valid days. Nil until then — never a guessed centre. */
        var ownMedian: Double?,
        var baselineDays: Int,
        var hero: Int?,
        var median24h: Int?,
        var ownMedianReady: Boolean,
        var below: Int,
        var near: Int,
        var above: Int,
        var empty: Empty?,
        var percents: List<ScatterPoint>,
    ) {
        val analyticsState: String
            get() {
                if (latestPoint != null) return "FRESH"
                return empty?.raw ?: "EMPTY"
            }
    }

    fun signedPercent(value: Int): String {
        if (value > 0) return "+$value"
        if (value < 0) return "−${abs(value)}"
        return "0"
    }

    fun pointValue(value: Double): String {
        val rounded = value.rounded()
        return if (abs(value - rounded) < 0.05) rounded.toInt().toString() else swiftFormat("%.1f", value)
    }

    private fun valid(optical: Double): Boolean = !optical.isNaN() && !optical.isInfinite() && optical > 0

    fun make(
        points: List<Point>,
        sleepWindows: List<SleepWindow>,
        now: Instant,
        switchOff: Boolean = false,
        allZeros: Boolean = false,
        zone: ZoneId = currentZone(),
        dayBoundaryHour: Int = UserDay.boundaryHour,
    ): Result {
        val valid = points.filter { valid(it.optical) }
        val todayStart = UserDay.containing(now, zone, dayBoundaryHour).start
        val todayEnd = todayStart.atZone(zone).plusDays(1).toInstant()
        val windowStart = now.addingTimeInterval(-24.0 * 60 * 60)

        val daysWithPoints = valid.map { UserDay.containing(it.ts, zone, dayBoundaryHour).start }.toSet()
        val daytime = valid.filter { point ->
            val dayStart = UserDay.containing(point.ts, zone, dayBoundaryHour).start
            val dayEnd = dayStart.atZone(zone).plusDays(1).toInstant()
            val hasNight = sleepWindows.any { window -> window.start < dayEnd && window.end > dayStart }
            if (!hasNight) return@filter true
            !sleepWindows.any { it.contains(point.ts) }
        }
        val ownMedian = if (daysWithPoints.size >= 5) median(daytime.map { it.optical }) else null
        val ownMedianReady = ownMedian != null && ownMedian > 0

        fun percent(optical: Double): Int? {
            if (ownMedian == null || ownMedian <= 0) return null
            return (100 * (optical / ownMedian - 1)).rounded().toInt()
        }

        val todayPoints = valid.filter { it.ts >= todayStart && it.ts < todayEnd && it.ts <= now }
            .sortedBy { it.ts }
        val heroOptical = todayPoints.lastOrNull()?.optical
        val hero = heroOptical?.let { percent(it) }

        val trendPoints = valid.filter { it.ts >= windowStart && it.ts <= now }.sortedBy { it.ts }
        val median24hPoint = median(trendPoints.map { it.optical })

        val todayPercents = todayPoints.mapNotNull { percent(it.optical) }
        val median24h = median(todayPercents.map { it.toDouble() })?.let { it.rounded().toInt() }

        val percents: List<ScatterPoint> = if (ownMedianReady) {
            valid.mapNotNull { point ->
                if (!(point.ts >= windowStart && point.ts <= now)) return@mapNotNull null
                val value = percent(point.optical) ?: return@mapNotNull null
                ScatterPoint(point.ts, value)
            }.sortedBy { it.ts }
        } else emptyList()

        var below = 0
        var near = 0
        var above = 0
        if (ownMedian != null && ownMedian > 0) {
            for (point in valid) {
                if (!(point.ts >= windowStart && point.ts <= now)) continue
                val ratio = point.optical / ownMedian
                if (ratio < 0.92) below += 1
                else if (ratio > 1.08) above += 1
                else near += 1
            }
        }

        val empty: Empty? = when {
            heroOptical == null && switchOff -> Empty.switchOff
            heroOptical == null && allZeros -> Empty.allZeros
            heroOptical != null -> null
            !ownMedianReady -> Empty.needs5Days
            else -> Empty.empty
        }

        return Result(
            latestPoint = heroOptical,
            trendPoints = trendPoints,
            median24hPoint = median24hPoint,
            ownMedian = ownMedian,
            baselineDays = minOf(daysWithPoints.size, 5),
            hero = hero,
            median24h = median24h,
            ownMedianReady = ownMedianReady,
            below = below,
            near = near,
            above = above,
            empty = empty,
            percents = percents)
    }

    /** Rolling windows the RESPONSE board can open: user days counted backwards from
     *  today, never a calendar week or month. Day is one user day (issue #19), not a
     *  rolling clock — the card says TODAY and now means it. */
    sealed class Horizon {
        data class UserDays(val days: Int) : Horizon()
    }

    /** One user day on the week / month board. `mean` is the day's own arithmetic mean.
     *  A day with no valid point stays empty — it is never a zero. */
    data class DaySlot(var start: Instant, var mean: Double?, var count: Int)

    /** Below / Near / Above versus this wrist's own daytime median. Near is ±8 %. */
    enum class Band {
        below, near, above;

        companion object {
            fun of(optical: Double, ownMedian: Double): Band? {
                if (!(ownMedian > 0 && valid(optical))) return null
                val ratio = optical / ownMedian
                if (ratio < 0.92) return below
                if (ratio > 1.08) return above
                return near
            }
        }
    }

    /** What a week or month window reduces to, once. The hero is the mean of the daily
     *  means — two high days pull it up, a busy day of twenty ticks does not outweigh a
     *  quiet one. Empty days stay out of the average so a gap cannot read as a low week. */
    data class HorizonWindow(
        var horizon: Horizon,
        var points: List<Point>,
        var slots: List<DaySlot>,
        var dailyMean: Double?,
        var below: Int,
        var near: Int,
        var above: Int,
        var recordedDays: Int,
    )

    fun percent(optical: Double, ownMedian: Double): Int? {
        if (!(ownMedian > 0 && valid(optical))) return null
        return (100 * (optical / ownMedian - 1)).rounded().toInt()
    }

    fun mean(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size

    /** Observed optical range with room around the own median, so a quiet day is not
     *  flattened against a 1-point ruler. */
    fun axis(values: List<Double>, ownMedian: Double?): ClosedFloatingPointRange<Double>? {
        val lo = values.minOrNull() ?: return null
        val hi = values.maxOrNull() ?: return null
        val pad = max(4.0, (hi - lo) * 0.12)
        var lower = lo - pad
        var upper = hi + pad
        if (ownMedian != null && ownMedian > 0) {
            lower = minOf(lower, ownMedian * 0.85)
            upper = maxOf(upper, ownMedian * 1.15)
        }
        if (upper - lower < 8) upper = lower + 8
        return lower..upper
    }

    fun daySlots(
        points: List<Point>,
        todayStart: Instant,
        days: Int,
        now: Instant,
        zone: ZoneId = currentZone(),
    ): List<DaySlot> {
        val valid = points.filter { valid(it.optical) && it.ts <= now }
        return (0 until max(1, days)).reversed().map { offset ->
            val start = todayStart.atZone(zone).plusDays(-offset.toLong()).toInstant()
            val end = start.atZone(zone).plusDays(1).toInstant()
            val inDay = valid.filter { it.ts >= start && it.ts < end }
            DaySlot(start = start, mean = mean(inDay.map { it.optical }), count = inDay.size)
        }
    }

    fun horizonWindow(
        points: List<Point>,
        ownMedian: Double?,
        now: Instant,
        horizon: Horizon,
        zone: ZoneId = currentZone(),
        dayBoundaryHour: Int = UserDay.boundaryHour,
    ): HorizonWindow {
        val valid = points.filter { valid(it.optical) && it.ts <= now }
        val todayStart = UserDay.containing(now, zone, dayBoundaryHour).start

        val windowPoints: List<Point>
        val slots: List<DaySlot>
        when (horizon) {
            is Horizon.UserDays -> {
                slots = daySlots(valid, todayStart, horizon.days, now, zone)
                val start = slots.firstOrNull()?.start ?: todayStart
                windowPoints = valid.filter { it.ts >= start }.sortedBy { it.ts }
            }
        }

        var below = 0
        var near = 0
        var above = 0
        if (ownMedian != null && ownMedian > 0) {
            for (point in windowPoints) {
                when (Band.of(point.optical, ownMedian)) {
                    Band.below -> below += 1
                    Band.near -> near += 1
                    Band.above -> above += 1
                    null -> {}
                }
            }
        }

        val recorded = slots.filter { it.mean != null }
        return HorizonWindow(
            horizon = horizon,
            points = windowPoints,
            slots = slots,
            dailyMean = mean(recorded.map { it.mean!! }),
            below = below,
            near = near,
            above = above,
            recordedDays = recorded.size)
    }

    private fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2 else sorted[middle]
    }
}
