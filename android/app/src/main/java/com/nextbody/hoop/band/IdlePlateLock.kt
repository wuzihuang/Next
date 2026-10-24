package com.nextbody.hoop.band

import java.time.Instant

/**
 * 04 · idle 星球的日子。一天一张，开二十次也是这一张。
 *
 * Pure: wearer + user-day + stored lock + optional one-shot event.
 * Hour-of-day and LIVE BPM are accepted so callers cannot smuggle them in
 * as a second picker — they do not change the plate.
 */
object IdlePlateLock {
    /** Playbook day-pool. Forbidden 13/17/18/19/24 never enter. Event plates
     *  11/20/25 stay out of the daily draw so a normal morning is not an alarm. */
    val dayPool: List<Int> = listOf(
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
        12, 14, 15, 16, 21, 22, 23, 26, 27, 28,
    )
    val forbidden: Set<Int> = setOf(13, 17, 18, 19, 24)
    const val lowReservePlate = 25
    const val lowBandChargePlate = 11
    const val bandAwayPlate = 20
    const val bandAwaySeconds: Double = 4.0 * 3600

    enum class LockedBy(val raw: String) {
        daily("daily"), event("event"), visit("visit");
        companion object { fun fromRaw(raw: String): LockedBy? = entries.firstOrNull { it.raw == raw } }
    }

    /** Every painted look, including event and forbidden plates. Product idle
     *  never draws from this list — `appear` still uses `dayPool`. */
    val reviewRoster: List<Int> = (1..28).toList()

    enum class Event { lowReserve, lowBandCharge, bandAway }

    data class Snapshot(val day: String, val plate: Int, val lockedBy: LockedBy)

    /** Deterministic daily draw. Adjacent days skip yesterday when the pool allows.
     *  02 and 23 are both moons: if yesterday was one, today will not be the other. */
    fun dailyPlate(wearer: String, day: String, yesterday: Int?): Int {
        val pool = dayPool
        if (pool.isEmpty()) return 1
        var idx = (fnv(wearer + "\u0001" + day) % pool.size.toULong()).toInt()
        var plate = pool[idx]
        if (yesterday != null && plate == yesterday && pool.size > 1) {
            idx = (idx + 1) % pool.size
            plate = pool[idx]
        }
        if (yesterday != null && isMoon(plate) && isMoon(yesterday) && plate != yesterday && pool.size > 2) {
            idx = (idx + 1) % pool.size
            plate = pool[idx]
            if (plate == yesterday) {
                idx = (idx + 1) % pool.size
                plate = pool[idx]
            }
        }
        return plate
    }

    /** Next look on the review roster. Unknown / missing previous starts at 01.
     *  Product idle does not call this — a DEBUG visit walk does. */
    fun advanceVisit(previous: Int?): Int {
        val roster = reviewRoster
        if (roster.isEmpty()) return 1
        val i = previous?.let { roster.indexOf(it) } ?: -1
        if (i < 0) return roster[0]
        return roster[(i + 1) % roster.size]
    }

    /** First idle appear of a user-day writes the lock. Same day keeps it.
     *  A new user-day only takes if idle is not already on screen (`idleVisible`).
     *  `hour` and `bpm` are ignored on purpose. */
    @Suppress("UNUSED_PARAMETER")
    fun appear(
        wearer: String,
        day: String,
        stored: Snapshot?,
        idleVisible: Boolean,
        hour: Int = 12,
        bpm: Int? = null,
    ): Snapshot {
        if (stored != null) {
            if (stored.day == day) return stored
            if (idleVisible) return stored
        }
        val plate = dailyPlate(wearer, day, stored?.plate)
        return Snapshot(day = day, plate = plate, lockedBy = LockedBy.daily)
    }

    /** One-shot override for the stored day. A second edge the same day is ignored.
     *  Clearing the edge is not this function — the snapshot stays. */
    fun applyEvent(event: Event, stored: Snapshot, day: String): Snapshot {
        if (stored.day != day) return stored
        if (stored.lockedBy != LockedBy.daily) return stored
        return Snapshot(day = stored.day, plate = plate(event), lockedBy = LockedBy.event)
    }

    fun plate(event: Event): Int = when (event) {
        Event.lowReserve -> lowReservePlate
        Event.lowBandCharge -> lowBandChargePlate
        Event.bandAway -> bandAwayPlate
    }

    /** Seconds since the BLE-down stamp. Unbound, still connected, or a missing
     *  stamp is 0 — `lastSync` / `.distantPast` is not a disconnect clock. */
    fun disconnectedFor(bound: Boolean, connected: Boolean, disconnectStamp: Instant?, now: Instant): Double {
        if (!bound || connected || disconnectStamp == null) return 0.0
        return maxOf(0.0, BandTime.interval(now, disconnectStamp))
    }

    /** Named edges only. REACHING, brief NO CONTACT, recovered reserve, and BPM
     *  are accepted so a caller cannot invent a fourth picker. */
    @Suppress("UNUSED_PARAMETER")
    fun edge(
        reserve: Int?,
        wakeReserve: Int?,
        bandPercent: Int?,
        charging: Boolean,
        disconnectedFor: Double,
        reaching: Boolean = false,
        noContact: Boolean = false,
        bpm: Int? = null,
    ): Event? {
        if (reserve != null && reserve <= 35 && wakeReserve != null && wakeReserve - reserve >= 15) return Event.lowReserve
        if (bandPercent != null && bandPercent <= 15 && !charging) return Event.lowBandCharge
        if (disconnectedFor >= bandAwaySeconds) return Event.bandAway
        return null
    }

    private fun isMoon(plate: Int) = plate == 2 || plate == 23

    private fun fnv(s: String): ULong {
        var h: ULong = 14_695_981_039_346_656_037uL
        for (b in s.toByteArray(Charsets.UTF_8)) {
            h = h xor (b.toInt() and 0xFF).toULong()
            h *= 1_099_511_628_211uL
        }
        return h
    }
}
