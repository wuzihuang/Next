package com.nextbody.hoop.band

import java.time.Instant
import java.util.UUID

/** One durable running-state receipt for an explicit strength mode. It contains no
 *  calculated calories: the server replays the same versioned MET mapping from facts. */
data class SportEnergyEvidence(
    val id: UUID,
    val sessionID: UUID,
    val continuityID: UUID,
    val observedAt: Instant,
    val sportMode: Int,
    val sampledTimeZone: String,
)

/** Running reports establish bounded intervals independently of optical contact.
 *  Pauses, invalid/ambiguous modes, clock reversal and gaps break continuity.
 *  (Swift value type with `mutating` methods → a small mutable class.) */
class SportEnergyEvidenceStream(val sessionID: UUID = UUID.randomUUID()) {
    private var continuityID: UUID = UUID.randomUUID()
    private var lastObservedAt: Instant? = null

    fun interrupted() {
        continuityID = UUID.randomUUID()
        lastObservedAt = null
    }

    fun accept(at: Instant, runState: Int?, sportMode: Int?, timeZone: String): SportEnergyEvidence? {
        if (runState != 1 || sportMode == null || SportMetricAccumulator.strengthMET(sportMode) == null ||
            timeZone.isEmpty()) {
            interrupted()
            return null
        }
        val previous = lastObservedAt
        if (previous != null) {
            val elapsed = BandTime.interval(at, previous)
            if (elapsed == 0.0) return null
            if (elapsed < 0 || elapsed > maximumGap) interrupted()
        }
        lastObservedAt = at
        return SportEnergyEvidence(id = UUID.randomUUID(), sessionID = sessionID,
            continuityID = continuityID, observedAt = at, sportMode = sportMode,
            sampledTimeZone = timeZone)
    }

    companion object {
        val maximumGap: Double = SportMetricAccumulator.liveWindow
    }
}
