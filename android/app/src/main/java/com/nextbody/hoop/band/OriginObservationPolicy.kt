package com.nextbody.hoop.band

import java.time.Instant

/** Origin is a five-minute aggregate in the current band mapping. The SDK documents
 *  interval values but does not promise whether its clock labels the start or end.
 *  Treat it as a start, as the energy/load consumers do, and wait for the whole slot. */
object OriginObservationPolicy {
    const val slotDuration: Double = 5.0 * 60

    fun accepts(slot: Instant, dayStart: Instant, dayEnd: Instant, readStartedAt: Instant,
                snapshotStartedAt: Instant? = null): Boolean {
        val cutoff = coverageEnd(dayStart, dayEnd, readStartedAt, snapshotStartedAt ?: readStartedAt) ?: return false
        return slot >= dayStart && slot < dayEnd && BandTime.adding(slot, slotDuration) <= cutoff
    }

    /** A later database query cannot certify coverage after the native snapshot began. */
    fun coverageEnd(dayStart: Instant, dayEnd: Instant, readStartedAt: Instant, snapshotStartedAt: Instant): Instant? {
        val end = minOf(dayEnd, minOf(readStartedAt, snapshotStartedAt))
        return if (end > dayStart) end else null
    }
}
