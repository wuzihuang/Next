package com.nextbody.hoop.band

import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The home-screen widgets' numbers, and the rules that decide what they may print.
 *
 * The glance is a copy of the facts each size is allowed to draw — body battery
 * (0–100), training load (0–21), last night's SLEEP, the band's own charge, the
 * last heart / stress tick, today's ACTIVE / steps / metres, and last night's
 * resting pulse / HRV / SpO2. After ninety minutes the live body numbers
 * withdraw. Last night's score, resting pulse, HRV, SpO2 and the band pip do
 * not withdraw with them.
 *
 * Body battery is the exception: it keeps `TickFreshness`'s three states so
 * the widget and the app agree about the same tick. Ninety minutes only dims
 * it (the app shows SYNCED HH:MM at that point); the number itself withdraws
 * at six hours. A widget that blanked at ninety while the app still printed
 * the score read as a bug, not as a freshness rule.
 */
object WidgetFaceMath {
    const val staleAfter: Double = 90.0 * 60
    /** `TickFreshness.gone` — the age at which the reserve score stops being printable. */
    const val goneAfter: Double = 6.0 * 3600
    const val loadCeiling = 21.0
    const val batteryCeiling = 100.0
    const val dash = "——"

    data class Glance(
        val numbersAt: Instant,
        val battery: Int?,
        val load: Double?,
        val signedIn: Boolean,
        val bandPercent: Int?,
        val bandCharge: String?,
        val heartRate: Int?,
        val stress: Int?,
        val sleepScore: Int?,
        val sleepMinutes: Int?,
        val activeKcal: Double?,
        val steps: Int?,
        val distanceM: Int?,
        val nightRhr: Int?,
        val nightHrv: Int?,
        val spo2: Int?,
        /** Independent clock: a meal/heart update cannot renew an old reserve score.
         *  Absent in legacy glances, which cannot prove reserve freshness. */
        val batteryObservedAt: Instant? = null,
    ) {
        companion object {
            val empty = Glance(
                numbersAt = BandTime.distantPast, battery = null, load = null, signedIn = false,
                bandPercent = null, bandCharge = null, heartRate = null, stress = null,
                sleepScore = null, sleepMinutes = null, activeKcal = null, steps = null,
                distanceM = null, nightRhr = null, nightHrv = null, spo2 = null)

            /** Gallery / placeholder — the same board numbers as `DataStore.seedToday`. */
            val placeholder = Glance(
                numbersAt = Instant.ofEpochSecond(1_778_086_800),
                battery = 72, load = 12.4, signedIn = true, bandPercent = 82, bandCharge = "unplugged",
                heartRate = 72, stress = 31, sleepScore = 78, sleepMinutes = 432, activeKcal = 320.0,
                steps = 8_432, distanceM = 6_200, nightRhr = 52, nightHrv = 54, spo2 = 96,
                batteryObservedAt = Instant.ofEpochSecond(1_778_086_800))
        }
    }

    data class TodayReadout(
        val batteryText: String,
        val batteryProgress: Double,
        /** The reserve tick is 90 minutes to under 6 hours old — printed, but unlit. */
        val batteryDim: Boolean = false,
        val loadText: String,
        val loadProgress: Double,
        val bandText: String,
        val bandProgress: Double,
        val bandLit: Boolean,
        val heartText: String,
        val stressText: String,
        val sleepText: String,
        val sleepProgress: Double,
        /** Last night's `h:mm` — the large face's SLEPT cell, the duration the
         *  score ring does not carry. */
        val sleepClockText: String,
        val activeText: String,
        val stepsText: String,
        val distanceText: String,
        val rhrText: String,
        val hrvText: String,
        val spo2Text: String,
        val stale: Boolean,
        /** `HH:mm` of `numbersAt` when the live numbers have been withdrawn. */
        val clock: String?,
    )

    fun isFresh(glance: Glance, now: Instant): Boolean = BandTime.interval(now, glance.numbersAt) < staleAfter

    fun progress(value: Double?, ceiling: Double): Double {
        if (value == null || ceiling <= 0) return 0.0
        return minOf(1.0, maxOf(0.0, value / ceiling))
    }

    fun batteryText(value: Int?): String = value?.toString() ?: dash

    fun loadText(value: Double?): String {
        if (value == null) return dash
        return String.format(Locale.ROOT, "%.1f", minOf(value, 20.9))
    }

    fun kcalText(value: Double?): String = value?.let { grouped().format(it) } ?: dash

    fun percentText(value: Int?): String = value?.let { "$it%" } ?: dash

    fun countText(value: Int?): String = value?.toString() ?: dash

    fun groupedText(value: Int?): String = value?.let { grouped().format(it.toLong()) } ?: dash

    /** Score first. Duration only when the night has not settled — same hero as page two. */
    fun sleepText(score: Int?, minutes: Int?): String {
        if (score != null) return score.toString()
        return nightClock(minutes)
    }

    /** The night's `h:mm`, regardless of whether a score landed. */
    fun nightClock(minutes: Int?): String {
        if (minutes == null || minutes <= 0) return dash
        return String.format(Locale.ROOT, "%d:%02d", minutes / 60, minutes % 60)
    }

    fun kmText(metres: Int?): String {
        if (metres == null) return dash
        return String.format(Locale.ROOT, "%.1f", metres / 1000.0)
    }

    fun clockText(date: Instant, zone: ZoneId = ZoneId.systemDefault()): String =
        DateTimeFormatter.ofPattern("HH:mm", Locale.US).format(date.atZone(zone))

    fun bandIsLit(charge: String?): Boolean = charge == "charging" || charge == "full"

    /** When the timeline should fire next: the 90-minute withdraw, else a 15-minute tick. */
    fun nextReload(glance: Glance, now: Instant): Instant {
        val staleAt = BandTime.adding(glance.numbersAt, staleAfter)
        val tick = BandTime.adding(now, 15.0 * 60)
        var next = if (staleAt > now) minOf(staleAt, tick) else tick
        glance.batteryObservedAt?.let { at ->
            // Both reserve edges: the dim at ninety minutes and the withdraw at six hours.
            for (edge in listOf(BandTime.adding(at, staleAfter), BandTime.adding(at, goneAfter))) {
                if (edge > now) next = minOf(next, edge)
            }
        }
        return next
    }

    fun today(glance: Glance, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): TodayReadout {
        val signedOut = !glance.signedIn
        val stale = !signedOut && !isFresh(glance, now)
        val hideLive = signedOut || stale
        // The reserve score answers to its own clock, so a meal or a heart tick cannot
        // renew it — but a glance too old to carry `batteryObservedAt` proves nothing
        // either way, and falls back to the live window rather than blanking outright.
        val batteryAge = glance.batteryObservedAt?.let { BandTime.interval(now, it) }
        val hideBattery = signedOut || (batteryAge?.let { it < 0 || it >= goneAfter } ?: hideLive)
        val dimBattery = !hideBattery && (batteryAge?.let { it >= staleAfter } ?: false)
        return TodayReadout(
            batteryText = if (hideBattery) dash else batteryText(glance.battery),
            batteryProgress = if (hideBattery) 0.0 else progress(glance.battery?.toDouble(), batteryCeiling),
            batteryDim = dimBattery,
            loadText = if (hideLive) dash else loadText(glance.load),
            loadProgress = if (hideLive) 0.0 else progress(glance.load, loadCeiling),
            bandText = if (signedOut) dash else percentText(glance.bandPercent),
            bandProgress = if (signedOut) 0.0 else progress(glance.bandPercent?.toDouble(), batteryCeiling),
            bandLit = !signedOut && bandIsLit(glance.bandCharge),
            heartText = if (hideLive) dash else countText(glance.heartRate),
            stressText = if (hideLive) dash else countText(glance.stress),
            sleepText = if (signedOut) dash else sleepText(glance.sleepScore, glance.sleepMinutes),
            sleepProgress = if (signedOut) 0.0 else progress(glance.sleepScore?.toDouble(), batteryCeiling),
            sleepClockText = if (signedOut) dash else nightClock(glance.sleepMinutes),
            activeText = if (hideLive) dash else kcalText(glance.activeKcal),
            stepsText = if (hideLive) dash else groupedText(glance.steps),
            distanceText = if (hideLive) dash else kmText(glance.distanceM),
            rhrText = if (signedOut) dash else countText(glance.nightRhr),
            hrvText = if (signedOut) dash else countText(glance.nightHrv),
            spo2Text = if (signedOut) dash else countText(glance.spo2),
            stale = stale,
            clock = if (stale) clockText(glance.numbersAt, zone) else null)
    }

    /** en_US decimal, "," grouping, no fraction digits (NumberFormatter rounds half-even). */
    private fun grouped(): DecimalFormat =
        DecimalFormat("#,##0", DecimalFormatSymbols(Locale.US)).apply { roundingMode = RoundingMode.HALF_EVEN }
}
