package com.nextbody.hoop.model

import com.nextbody.hoop.band.BodyBatteryReadoutPolicy
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.l10n.L
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

/**
 * 13 · 昨夜与 Body Battery.
 * Sleep never reaches the screen (F0 rule 03). Duration, stages and depth ratios exist only
 * as inputs to this model; what the user sees is how much last night charged the battery,
 * plus one of four words.
 */
object BodyBattery {

    /** Legacy morning bands for older server payloads. Current training guidance is
     *  published by the server from sleep/recovery with a dynamic reserve limit. */
    data class Band(
        val range: IntRange,
        val target: Double,
        val optimal: ClosedFloatingPointRange<Double>,
        val ringPercent: Int,
        val dayLooksLike: String,
    )

    val bands: List<Band> = listOf(
        Band(range = 0..19, target = 4.0, optimal = 0.0..6.0, ringPercent = 19,
            dayLooksLike = "Training nothing today is a legal answer — inside the band, not a failure"),
        Band(range = 20..29, target = 6.0, optimal = 3.0..8.5, ringPercent = 29,
            dayLooksLike = "Walking and ordinary movement reach the band"),
        Band(range = 30..39, target = 8.0, optimal = 5.0..10.5, ringPercent = 38,
            dayLooksLike = "One easy aerobic session"),
        Band(range = 40..49, target = 10.0, optimal = 7.0..12.5, ringPercent = 48,
            dayLooksLike = "One moderate class"),
        Band(range = 50..59, target = 11.5, optimal = 8.5..14.0, ringPercent = 55,
            dayLooksLike = "An ordinary day"),
        Band(range = 60..69, target = 13.0, optimal = 10.5..15.5, ringPercent = 62,
            dayLooksLike = "An ordinary day, with room for one lifting session"),
        Band(range = 70..79, target = 14.5, optimal = 12.5..16.5, ringPercent = 69,
            dayLooksLike = "The body is ready — one lifting session fits"),
        Band(range = 80..89, target = 16.0, optimal = 14.0..18.0, ringPercent = 76,
            dayLooksLike = "The body is ready for intensity"),
        // The full ring stays above the top band: the target is never allowed to reach 21.
        Band(range = 90..100, target = 18.0, optimal = 15.5..20.0, ringPercent = 86,
            dayLooksLike = "The full ring stays at 21; the target never goes there"),
    )

    /** Swift `band(for:)`. */
    fun band(wake: Int): Band =
        bands.firstOrNull { max(0, min(100, wake)) in it.range } ?: bands[0]

    /** Morning and current readiness. Lime stays the colour for every tier. */
    fun tierWord(value: Int): String = when {
        value >= 80 -> "READY"
        value >= 65 -> "STEADY"
        value >= 50 -> "MODERATE"
        else -> "RECOVER"
    }

    fun standbyLine(current: Int, morning: Int): String =
        L("${tierWord(current)} · MORNING %d", morning)

    fun overnightLine(delta: Double, morning: Int): String =
        L("OVERNIGHT %@ · ${tierWord(morning)}", Fmt.signed(delta))
}

/**
 * Display geometry uses actual elapsed seconds in the selected local user day.
 * A DST day can contain 23 or 25 hours. Colour describes each observed change;
 * an evening recovery must never recolour an earlier decline.
 */
object BodyBatteryCurveMath {
    data class Segment(val start: ReserveSample, val end: ReserveSample) {
        val charging: Boolean get() = end.value > start.value
    }

    fun fraction(timestamp: Instant, day: UserDay): Double {
        val duration = day.end.timeIntervalSince(day.start)
        if (duration <= 0) return 0.0
        return min(1.0, max(0.0, timestamp.timeIntervalSince(day.start) / duration))
    }

    fun segments(samples: List<ReserveSample>): List<Segment> {
        val ordered = samples.sortedBy { it.ts }
        return ordered.zip(ordered.drop(1)).mapNotNull { (start, end) ->
            // Missing ticks remain a visible gap instead of an invented straight line.
            if (!(end.ts > start.ts && end.ts.timeIntervalSince(start.ts) <= 10 * 60)) null
            else Segment(start, end)
        }
    }
}

/**
 * 13 · how old the last real tick is. The curve stops there; nothing is extrapolated to
 * cover the gap, so the screen has to say which of the three states it is in.
 */
enum class TickFreshness {
    fresh,          // under 90 minutes
    stale,          // 90 minutes to under 6 hours — numbers dim, SYNCED HH:MM appears
    gone;           // 6 hours or later, missing or future observation — the numbers themselves become ——

    companion object {
        fun of(at: Instant?, now: Instant = Instant.now()): TickFreshness {
            if (at == null) return gone
            val age = now.timeIntervalSince(at)
            if (age < 0) return gone
            if (age >= BodyBatteryReadoutPolicy.goneAfter) return gone
            if (age >= BodyBatteryReadoutPolicy.staleAfter) return stale
            return fresh
        }
    }
}
