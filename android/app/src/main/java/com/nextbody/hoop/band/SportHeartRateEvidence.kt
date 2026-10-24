package com.nextbody.hoop.band

import java.time.Instant
import java.util.UUID

/** Raw observations only. Training weights and load integration stay on the server. */
data class SportHeartRateEvidence(
    val id: UUID,
    val sessionID: UUID,
    val continuityID: UUID,
    val observedAt: Instant,
    val heartRate: Int,
    /** Joining an already-running workout does not verify its mode. */
    val sportMode: Int?,
    val sampledTimeZone: String,
)

/** A continuity ends on missing contact, pause, stream replacement, clock reversal or
 *  a gap exceeding 15 seconds. Neither a joined session nor an app restart invents
 *  observations for the earlier workout. SQL also enforces the same interval limit. */
class SportHeartRateEvidenceStream(val sessionID: UUID = UUID.randomUUID()) {
    private var continuityID: UUID = UUID.randomUUID()
    private var lastObservedAt: Instant? = null

    fun interrupted() {
        continuityID = UUID.randomUUID()
        lastObservedAt = null
    }

    fun accept(at: Instant, heartRate: Int?, runState: Int?, sportMode: Int?, timeZone: String): SportHeartRateEvidence? {
        if (heartRate == null || heartRate !in 1..250 || !(runState == null || runState == 1)) {
            interrupted()
            return null
        }
        val previous = lastObservedAt
        if (previous != null) {
            val elapsed = BandTime.interval(at, previous)
            // An exact duplicate callback is not another observation.
            if (elapsed == 0.0) return null
            if (elapsed < 0 || elapsed > maximumGap) interrupted()
        }
        lastObservedAt = at
        return SportHeartRateEvidence(id = UUID.randomUUID(), sessionID = sessionID,
            continuityID = continuityID, observedAt = at, heartRate = heartRate,
            sportMode = sportMode?.takeIf { it in 0..65535},
            sampledTimeZone = timeZone)
    }

    companion object {
        const val maximumGap: Double = 15.0
    }
}
