package com.nextbody.hoop.band

import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.model.timeIntervalSince
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID
import kotlin.math.max

/**
 * The recommendation is published with its inputs. A present but unavailable target
 * is authoritative; only an older payload without the key may use a legacy range.
 */
data class TrainingTargetEvidence(
    var version: String,
    var target: Double?,
    var lower: Double?,
    var upper: Double?,
    var sleepScore: Double?,
    var sleepMinutes: Double?,
    var recoveryScore: Double?,
    var wakeReserve: Double?,
    var recentLoad: Double?,
    var historyDays: Int,
    var readiness: Double?,
    var limited: Boolean,
    var baseTarget: Double? = null,
    var currentReserve: Double? = null,
    var reserveAdjustment: Double? = null,
    var reserveLimit: Double? = null,
    var remaining: Double? = null,
    var observedAt: Instant? = null,
    var reserveFresh: Boolean? = null,
) {
    val hasReserveLimit: Boolean
        get() = reserveLimit != null && currentReserve != null && version.startsWith("target-") &&
            version.removePrefix("target-").split('.').map { it.toIntOrNull() ?: -1 }
                .let { it[0] > 1 || it[0] == 1 && it.getOrElse(1) { 0 } >= 1 }

    /** The server may deliberately retain a limit from an older observation.
     *  Only its explicit freshness flag permits describing the reading as current. */
    val followsCurrentReserve: Boolean get() = hasReserveLimit && reserveFresh == true

    /** A cached publication keeps its limit, but time still passes while the page is open. */
    fun followsCurrentReserve(now: Instant): Boolean {
        val observedAt = observedAt
        if (!followsCurrentReserve || observedAt == null) return false
        val age = now.timeIntervalSince(observedAt)
        return age >= 0 && age < 90 * 60
    }

    val optimalZone: ClosedFloatingPointRange<Double>?
        get() {
            val target = target ?: return null
            val lower = lower ?: return null
            val upper = upper ?: return null
            if (!(lower <= target && target <= upper)) return null
            return lower..upper
        }
}

/**
 * One source's contribution to the day's cumulative curve. The whole-day load can
 * also grow from other activity between startedAt and endedAt, so their difference
 * is deliberately never used to reconstruct this session's loadDelta.
 */
data class TrainingSessionContribution(
    var sessionID: UUID,
    var sportMode: Int?,
    var startedAt: Instant,
    var endedAt: Instant,
    var observedSeconds: Double,
    var rawLoad: Double,
    var loadDelta: Double,
    var loadBefore: Double,
    var loadAfter: Double,
    var displayedDelta: Double?,
) {
    val id: UUID get() = sessionID

    val deltaText: String get() = deltaText(loadDelta, displayedDelta)

    val reachesScaleLimit: Boolean get() = rawLoad > 0 && loadAfter >= 20.9

    companion object {
        fun deltaText(delta: Double, displayed: Double? = null): String {
            val shown = displayed ?: delta
            if (delta > 0 && shown < 0.1) return "+<0.1"
            return swiftFormat("+%.1f", max(0.0, shown))
        }

        fun overlaps(startedAt: Instant, endedAt: Instant, day: UserDay): Boolean =
            startedAt < day.end && endedAt > day.start
    }
}

/** A saved declaration is visible even when no sensor evidence can price its load. */
data class UnmeasuredTrainingSession(
    var id: UUID,
    var sportMode: Int?,
    var startedAt: Instant,
    var endedAt: Instant,
)

/** Swift returned the tuple `(target: Double?, zone: ClosedRange<Double>?)`. */
data class TrainingRecommendation(val target: Double?, val zone: ClosedFloatingPointRange<Double>?)

/**
 * Port note: Swift's `init(evidence: [String: Any]?)` is `TrainingSettlement(evidence)` here
 * (companion `invoke`); the evidence map is the JSON object as plain Kotlin values
 * (Map / List / Number / String / Boolean), e.g. converted from org.json.
 */
data class TrainingSettlement(
    var target: TrainingTargetEvidence?,
    var sessions: List<TrainingSessionContribution>,
    // Optional so snapshots written before backfill support continue to decode.
    var unmeasuredSessions: List<UnmeasuredTrainingSession>? = null,
) {
    fun recommendation(legacyTarget: Double?, legacyZone: ClosedFloatingPointRange<Double>?): TrainingRecommendation {
        val target = target ?: return TrainingRecommendation(legacyTarget, legacyZone)
        return TrainingRecommendation(target.target, target.optimalZone)
    }

    /** Reading the latest snapshot each time turns a pending recap into a settled one
     *  as soon as publication lands, without storing a second copy of calculated load. */
    fun session(sessionID: UUID?, day: UserDay): TrainingSessionContribution? {
        if (sessionID == null) return null
        return sessions.firstOrNull {
            it.sessionID == sessionID &&
                TrainingSessionContribution.overlaps(it.startedAt, it.endedAt, day)
        }
    }

    companion object {
        operator fun invoke(evidence: Map<String, Any?>?): TrainingSettlement {
            val rows = rows(evidence?.get("sessions"))
            val unmeasured = rows.mapNotNull { row ->
                if (row["source"] as? String != "manual" || row["data_status"] as? String != "missing") return@mapNotNull null
                val id = uuid(row["session_id"]) ?: return@mapNotNull null
                val start = timestamp(row["started_at"]) ?: return@mapNotNull null
                val end = timestamp(row["ended_at"]) ?: return@mapNotNull null
                if (end <= start) return@mapNotNull null
                UnmeasuredTrainingSession(id = id,
                    sportMode = number(row["sport_mode"], 0.0..65535.0)?.toInt(), startedAt = start, endedAt = end)
            }.sortedBy { it.startedAt }

            var target: TrainingTargetEvidence? = null
            if (evidence != null && evidence.containsKey("target")) {
                @Suppress("UNCHECKED_CAST")
                val row = (evidence["target"] as? Map<String, Any?>) ?: emptyMap()
                target = TrainingTargetEvidence(
                    version = row["version"] as? String ?: "",
                    target = number(row["target"], 0.0..21.0),
                    lower = number(row["lower"], 0.0..21.0),
                    upper = number(row["upper"], 0.0..21.0),
                    sleepScore = number(row["sleep_score"], 0.0..100.0),
                    sleepMinutes = number(row["sleep_minutes"], 0.0..1440.0),
                    recoveryScore = number(row["recovery_score"], 0.0..100.0),
                    wakeReserve = number(row["wake_reserve"], 0.0..100.0),
                    recentLoad = number(row["recent_load"], 0.0..21.0),
                    historyDays = (number(row["history_days"], 0.0..365.0) ?: 0.0).toInt(),
                    readiness = number(row["readiness"], 0.0..100.0),
                    limited = row["limited"] as? Boolean ?: true,
                    baseTarget = number(row["base_target"], 0.0..21.0),
                    currentReserve = number(row["current_reserve"], 0.0..100.0),
                    reserveAdjustment = number(row["reserve_adjustment"], -21.0..21.0),
                ).also {
                    it.reserveLimit = number(row["reserve_limit"], 0.0..21.0)
                    it.remaining = number(row["remaining"], 0.0..21.0)
                    it.observedAt = timestamp(row["observed_at"])
                    it.reserveFresh = row["reserve_fresh"] as? Boolean
                }
            }

            val sessions = rows.mapNotNull { row ->
                val id = uuid(row["session_id"]) ?: return@mapNotNull null
                val start = timestamp(row["started_at"]) ?: return@mapNotNull null
                val end = timestamp(row["ended_at"]) ?: return@mapNotNull null
                if (end < start) return@mapNotNull null
                val observed = number(row["observed_seconds"], 0.0..172800.0) ?: return@mapNotNull null
                val raw = number(row["raw_load"]) ?: return@mapNotNull null
                if (raw < 0) return@mapNotNull null
                val delta = number(row["load_delta"], 0.0..21.0) ?: return@mapNotNull null
                val before = number(row["load_before"], 0.0..21.0) ?: return@mapNotNull null
                val after = number(row["load_after"], 0.0..21.0) ?: return@mapNotNull null
                if (after < before) return@mapNotNull null
                TrainingSessionContribution(sessionID = id,
                    sportMode = number(row["sport_mode"], 0.0..65535.0)?.toInt(),
                    startedAt = start, endedAt = end, observedSeconds = observed,
                    rawLoad = raw, loadDelta = delta, loadBefore = before, loadAfter = after,
                    displayedDelta = number(row["displayed_delta"], 0.0..21.0))
            }.sortedBy { it.startedAt }

            return TrainingSettlement(target = target, sessions = sessions, unmeasuredSessions = unmeasured)
        }

        @Suppress("UNCHECKED_CAST")
        private fun rows(value: Any?): List<Map<String, Any?>> =
            (value as? List<*>)?.mapNotNull { it as? Map<String, Any?> } ?: emptyList()

        private fun uuid(value: Any?): UUID? =
            (value as? String)?.let { runCatching { UUID.fromString(it) }.getOrNull() }

        private fun number(value: Any?, range: ClosedFloatingPointRange<Double>? = null): Double? {
            val v: Double = when (value) {
                is Boolean -> if (value) 1.0 else 0.0   // NSNumber bridges Bool too
                is Number -> value.toDouble()
                is String -> value.toDoubleOrNull() ?: return null
                else -> return null
            }
            if (v.isNaN() || v.isInfinite()) return null
            if (range != null && v !in range) return null
            return v
        }

        private fun timestamp(value: Any?): Instant? {
            val text = value as? String ?: return null
            return runCatching { OffsetDateTime.parse(text).toInstant() }.getOrNull()
        }
    }
}
