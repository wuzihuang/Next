package com.nextbody.hoop.band

import java.time.Instant

/**
 * Issue #20 · 「我都已经醒了、在用 App 的时候，它居然还算我在睡觉。」
 *
 * The band decides on its own when a night ended, and on this firmware it is generous:
 * a wrist lying still on a duvet at 07:10 while its owner reads the app in bed is filed
 * as sleep, and the night's recorded wake lands well after the person got up. The phone
 * being in front of a face is the one piece of wake evidence the band cannot see, so it
 * is the one the phone owes it.
 *
 * `AwakeEvidence` records the instants this app was in the foreground; `SleepWakeClamp`
 * cuts a recorded night at the first of them that lands inside it. Nothing here invents
 * sleep — it only ever removes minutes the band claimed after the person was demonstrably
 * awake, and it never touches a night the app was not open during.
 */
object AwakeEvidence {
    private const val key = "nb.awake.foregroundMarks"

    /** Two days is longer than any night plus the sync that reads it, and short enough
     *  that this stays a handful of timestamps rather than a log. */
    const val retention: Double = 48.0 * 3600

    /** Foreground marks closer together than this are the same waking: coming back from
     *  the app switcher four times in a minute is not four pieces of evidence. */
    const val coalesce: Double = 60.0

    fun record(at: Instant = Instant.now()) {
        val kept = marks().filter { BandTime.interval(at, it) < retention }.toMutableList()
        val last = kept.lastOrNull()
        if (last != null && BandTime.interval(at, last) < coalesce) return
        kept.add(at)
        BandPrefs.setString(key, kept.joinToString(",") { BandTime.seconds(it).toString() })
    }

    fun marks(): List<Instant> =
        (BandPrefs.string(key) ?: "").split(",").mapNotNull { it.toDoubleOrNull() }
            .map { BandTime.fromSeconds(it) }.sorted()

    /** DEBUG. */
    fun reset() = BandPrefs.remove(key)
}

object SleepWakeClamp {
    /** A night is not cut below this. Opening the app at 00:20 does not mean the night that
     *  began at 00:05 never happened — a glance that early is someone falling asleep with a
     *  phone in their hand, and calling it a wake would erase the whole night. */
    const val minimumNight: Double = 45.0 * 60

    /** Nor is a mark within this of the band's own wake worth acting on: the band and the
     *  phone agree, and rewriting the night to save four minutes only creates churn. */
    const val tolerance: Double = 5.0 * 60

    /** The instant this night actually ended, or null to keep the band's own answer.
     *  The first foreground mark strictly inside the recorded night, at least
     *  `minimumNight` after it began and at least `tolerance` before the band's wake. */
    fun wake(sleepStart: Instant, recordedWake: Instant, marks: List<Instant>): Instant? {
        if (recordedWake <= sleepStart) return null
        return marks.sorted().firstOrNull {
            it > BandTime.adding(sleepStart, minimumNight) && it < BandTime.adding(recordedWake, -tolerance)
        }
    }
}
