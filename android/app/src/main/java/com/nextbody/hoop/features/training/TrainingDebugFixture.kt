package com.nextbody.hoop.features.training

import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.TrainingSettlement
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.LoadPoint
import com.nextbody.hoop.model.NightInputs
import com.nextbody.hoop.model.TrainingEvidence
import com.nextbody.hoop.model.TrainingSegment
import com.nextbody.hoop.model.addingTimeInterval
import kotlin.math.max

/**
 * Training-only UI fixtures (DEBUG on the seeded emulator — Swift's `DEBUG && simulator`).
 * They transform the view's local read without mutating DataStore or the sample data used
 * by other screens. `NB_DEBUG_TRAINING_FIXTURE=no-target | empty-curve | baseline |
 * sessions | reserve-adjusted | reserve-stale`.
 */
object TrainingDebugFixture {
    private val names = setOf("no-target", "empty-curve", "baseline", "sessions", "reserve-adjusted", "reserve-stale")

    val name: String?
        get() {
            if (!BuildConfig.DEBUG || !Band.allowsSeed) return null
            val value = DebugEnv["NB_DEBUG_TRAINING_FIXTURE"] ?: return null
            return if (value in names) value else null
        }

    fun metrics(source: DailyMetrics): DailyMetrics {
        val name = name ?: return source
        val row = source.copy()
        val elapsed = row.day.elapsedMinutes()
        val lastMinute = max(0, elapsed - 10)
        row.trainingLoad = 6.4
        row.targetLoad = if (name == "no-target") null else 16.0
        row.optimalZone = if (name == "no-target") null else 14.0..18.0
        row.recordedSteps = 1_652
        row.segments = listOf(TrainingSegment(at = row.day.start, name = "ALL DAY", minutes = null,
            avgHR = null, steps = 1_652, delta = if (name == "sessions") 4.7 else 6.4, allDay = true))
        row.zoneMinutes = listOf(35, 20, 10, 5, 0)
        row.loadCurve = if (name == "empty-curve") emptyList() else listOf(
            LoadPoint(row.day.start.addingTimeInterval(max(0, lastMinute - 5).toDouble() * 60), 6.2),
            LoadPoint(row.day.start.addingTimeInterval(lastMinute.toDouble() * 60), 6.4),
        )
        row.nightInputs = NightInputs(hrv = 56.0, hrvBase = null, rhr = 57.0, rhrBase = null,
            rhrNights = 4, hrvNights = 3, multiplier = 1.0)
        row.trainingEvidence = TrainingEvidence(
            elapsedMinutes = elapsed, recordedMinutes = elapsed * 9 / 10,
            heartRateMinutes = elapsed * 8 / 10, movementMinutes = elapsed * 7 / 10,
            restingHeartRate = 57.0, restingBaselineNights = 3, baselineEstimated = true)
        val target = mutableMapOf<String, Any?>(
            "version" to "target-1.0", "target" to (if (name == "no-target") null else 16),
            "lower" to 14, "upper" to 18, "sleep_score" to 84, "sleep_minutes" to 455,
            "recovery_score" to 88, "wake_reserve" to 81, "recent_load" to 11.2,
            "history_days" to 4, "readiness" to 85, "limited" to true,
        )
        val evidence = mutableMapOf<String, Any?>("target" to target)
        if (name == "reserve-adjusted" || name == "reserve-stale") {
            target["version"] = "target-1.1"
            target["target"] = 8
            target["lower"] = 6
            target["upper"] = 10
            target["base_target"] = 16
            target["current_reserve"] = 25
            target["reserve_adjustment"] = -8
            target["reserve_limit"] = 8
            target["reserve_fresh"] = name != "reserve-stale"
            target["observed_at"] = row.day.start.addingTimeInterval(3600.0).toString()
            target["remaining"] = 1.6
        }
        if (name == "sessions") {
            val start = row.day.start.addingTimeInterval(max(0, elapsed - 45).toDouble() * 60)
            evidence["sessions"] = listOf(mapOf<String, Any?>(
                "session_id" to "A8C8CB12-4BF2-4000-A830-605A5F1EE236", "sport_mode" to 25,
                "started_at" to start.toString(),
                "ended_at" to start.addingTimeInterval(1200.0).toString(),
                "observed_seconds" to 1200, "raw_load" to 25, "load_delta" to 1.73,
                "displayed_delta" to 1.7, "load_before" to 4.2, "load_after" to 6.4,
            ))
            row.segments = listOf(TrainingSegment(at = start, name = "RECORDED SESSION", minutes = 20,
                avgHR = null, steps = null, delta = 1.7, allDay = false)) + row.segments
        }
        row.applyTrainingSettlement(TrainingSettlement(evidence))
        return row
    }
}
