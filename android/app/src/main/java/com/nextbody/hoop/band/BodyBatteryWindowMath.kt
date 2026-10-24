package com.nextbody.hoop.band

import com.nextbody.hoop.model.roundedInt
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.timeIntervalSince
import java.time.Instant
import kotlin.math.abs
import kotlin.math.max

data class BodyBatteryDayFacts(
    var day: UserDay,
    var wake: Int?,
    var now: Int?,
    var nightCharge: Double?,
    var worn: Boolean?,
    var isOpen: Boolean,
) {
    /** A morning peak the page can put on the line. Today counts
     *  once `bbWake` is set — that number is frozen at wake, unlike training load. */
    val hasWake: Boolean get() = wake != null
}

data class BodyBatteryWeekRoll(
    var start: UserDay,
    var end: UserDay,
    var days: Int,
    var wornDays: Int,
    var average: Double?,
)

/**
 * Arithmetic for BODY BATTERY's three windows. No SwiftUI: the view only
 * lays out what this file already reduced. Week and month heroes are a
 * typical morning peak, never a 7-day or 30-day sum.
 */
object BodyBatteryWindowMath {
    /** Mean of days that published a wake peak. Empty slots stay out of the
     *  denominator — they are not zero. */
    fun averageWake(days: List<BodyBatteryDayFacts>): Double? {
        val values = days.filter { it.hasWake }.mapNotNull { it.wake?.toDouble() }
        if (values.isEmpty()) return null
        return values.sum() / values.size
    }

    /** Month hero: a typical morning. Same grain as the week hero. */
    fun typicalWake(days: List<BodyBatteryDayFacts>): Double? = averageWake(days)

    fun typicalNightCharge(days: List<BodyBatteryDayFacts>): Double? {
        val values = days.filter { it.hasWake }.mapNotNull { it.nightCharge }
        if (values.isEmpty()) return null
        return values.sum() / values.size
    }

    fun wornCount(days: List<BodyBatteryDayFacts>): Int = days.count { it.hasWake || it.worn == true }

    fun emptyCount(days: List<BodyBatteryDayFacts>): Int = days.count { !it.hasWake }

    fun peakDay(days: List<BodyBatteryDayFacts>): BodyBatteryDayFacts? =
        days.filter { it.hasWake }.maxByOrNull { it.wake ?: 0 }

    /** Oldest first. A 30-day window becomes 2 + 7 + 7 + 7 + 7. */
    fun weekRolls(days: List<BodyBatteryDayFacts>): List<BodyBatteryWeekRoll> {
        if (days.isEmpty()) return emptyList()
        val rolls = mutableListOf<BodyBatteryWeekRoll>()
        var cursor = days.size
        while (cursor > 0) {
            val start = max(0, cursor - 7)
            val slice = days.subList(start, cursor)
            cursor = start
            rolls.add(BodyBatteryWeekRoll(
                start = slice[0].day,
                end = slice[slice.size - 1].day,
                days = slice.size,
                wornDays = wornCount(slice),
                average = averageWake(slice)))
        }
        return rolls.reversed()
    }
}

/**
 * #25 · 未佩戴和真实的 0% 是两件事。An empty battery is a measurement someone earned;
 * a battery with no recent evidence is not, and every entry prints `——` for it rather
 * than a number the wrist never proved. The two states must never share a glyph.
 */
sealed class BodyBatteryReadout {
    /** A settled value whose evidence is young enough to print. `dim` marks the
     *  90-minute-to-six-hour window: the number is real, but it is no longer live. */
    data class Reading(val reading: Int, val dim: Boolean) : BodyBatteryReadout()

    /** Nothing recent enough to print. `since` is the last real tick, when there was one. */
    data class NotWorn(val since: Instant?) : BodyBatteryReadout()

    val value: Int? get() = (this as? Reading)?.reading

    /** True while the entry must show a placeholder instead of a number. */
    val isPlaceholder: Boolean get() = value == null

    val isDim: Boolean get() = (this as? Reading)?.dim ?: true
}

/**
 * One set of thresholds for every body battery entry, so a card and its page can never
 * disagree about whether the wrist is still answering. `TickFreshness` reads them too.
 */
object BodyBatteryReadoutPolicy {
    /** The number stays real but stops being live. */
    const val staleAfter: Double = 90.0 * 60
    /** The number stops being printable at all. */
    const val goneAfter: Double = 6.0 * 3600

    fun readout(value: Int?, observedAt: Instant?, now: Instant): BodyBatteryReadout {
        if (observedAt == null || value == null) return BodyBatteryReadout.NotWorn(observedAt)
        val age = now.timeIntervalSince(observedAt)
        // A future observation is a broken clock, not a fresh reading.
        if (!(age >= 0 && age < goneAfter)) return BodyBatteryReadout.NotWorn(observedAt)
        return BodyBatteryReadout.Reading(value, dim = age >= staleAfter)
    }
}

/**
 * 13 · WHY <n> as a ledger. One signed row per term and the balance after it; the last
 * balance is the hero number. Terms carry their own sign: recovery is the only one that
 * ever charges, the other three only ever drain.
 */
data class BodyBatteryLedgerRow(var term: Term, var delta: Int, var balance: Int) {
    enum class Term { recovery, awake, movement, stress }
}

object BodyBatteryLedgerMath {
    /** The server closes its four terms to `current − anchor` within ±0.5 before it publishes.
     *  The page prints integers, so the rounding residual (at most ±2) lands on the largest
     *  term instead of leaving the column one short of the number at the top. */
    fun rows(anchor: Int, recovery: Double, awake: Double, movement: Double,
             stress: Double, current: Int): List<BodyBatteryLedgerRow> {
        val terms = listOf(
            BodyBatteryLedgerRow.Term.recovery to recovery, BodyBatteryLedgerRow.Term.awake to awake,
            BodyBatteryLedgerRow.Term.movement to movement, BodyBatteryLedgerRow.Term.stress to stress,
        )
        val deltas = terms.map { it.second.roundedInt() }.toMutableList()
        val residual = (current - anchor) - deltas.sum()
        if (residual != 0) {
            // Swift `max(by:)` keeps the first of equal maxima.
            var widest = 0
            for (i in terms.indices) if (abs(terms[widest].second) < abs(terms[i].second)) widest = i
            deltas[widest] += residual
        }
        var balance = anchor
        return terms.zip(deltas).map { (term, delta) ->
            balance += delta
            BodyBatteryLedgerRow(term = term.first, delta = delta, balance = balance)
        }
    }

    /** Minutes awake inside this user day up to the last observation, on the five-minute
     *  grid the ticks live on. nil without a recorded wake: a day that started from an
     *  assumed anchor has no moment the wearer is known to have woken. */
    fun awakeMinutes(wakeAt: Instant?, dayStart: Instant, observedAt: Instant?): Int? {
        if (wakeAt == null || observedAt == null) return null
        val minutes = observedAt.timeIntervalSince(maxOf(wakeAt, dayStart)) / 60
        if (minutes < 5) return null
        return (minutes / 5).rounded().toInt() * 5
    }

    /** Five-minute ticks the drain model charged for stress: the index sat above 45.
     *  nil when no tick carried a stress index at all — missing is not calm. */
    fun stressedMinutes(samples: List<VitalSample>, above: Int = 45): Int? {
        val scored = samples.mapNotNull { it.stress }
        if (scored.isEmpty()) return null
        return scored.count { it > above } * 5
    }

    /** One of three words for the night's charge multiplier, around a ±3 % band of 1.00. */
    enum class Pace { slower, usual, faster }

    fun pace(multiplier: Double): Pace {
        if (multiplier < 0.97) return Pace.slower
        if (multiplier > 1.03) return Pace.faster
        return Pace.usual
    }
}
