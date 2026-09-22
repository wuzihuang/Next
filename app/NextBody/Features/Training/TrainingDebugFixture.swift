#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Training-only UI fixtures. They transform the view's local read without
/// mutating DataStore or the sample data used by other screens.
enum TrainingDebugFixture {
    static var name: String? {
        let value = ProcessInfo.processInfo.environment["NB_DEBUG_TRAINING_FIXTURE"]
        return ["no-target", "empty-curve", "baseline", "sessions", "reserve-adjusted", "reserve-stale"].contains(value ?? "") ? value : nil
    }

    static func metrics(_ source: DailyMetrics) -> DailyMetrics {
        guard let name else { return source }
        var row = source
        let elapsed = row.day.elapsedMinutes()
        let lastMinute = max(0, elapsed - 10)
        row.trainingLoad = 6.4
        row.targetLoad = name == "no-target" ? nil : 16
        row.optimalZone = name == "no-target" ? nil : 14...18
        row.recordedSteps = 1_652
        row.segments = [TrainingSegment(at: row.day.start, name: "ALL DAY", minutes: nil,
            avgHR: nil, steps: 1_652, delta: name == "sessions" ? 4.7 : 6.4, allDay: true)]
        row.zoneMinutes = [35, 20, 10, 5, 0]
        row.loadCurve = name == "empty-curve" ? [] : [
            LoadPoint(ts: row.day.start.addingTimeInterval(Double(max(0, lastMinute - 5)) * 60), load: 6.2),
            LoadPoint(ts: row.day.start.addingTimeInterval(Double(lastMinute) * 60), load: 6.4),
        ]
        row.nightInputs = NightInputs(hrv: 56, hrvBase: nil, rhr: 57, rhrBase: nil,
                                    rhrNights: 4, hrvNights: 3, multiplier: 1)
        row.trainingEvidence = TrainingEvidence(
            elapsedMinutes: elapsed, recordedMinutes: elapsed * 9 / 10,
            heartRateMinutes: elapsed * 8 / 10, movementMinutes: elapsed * 7 / 10,
            restingHeartRate: 57, restingBaselineNights: 3, baselineEstimated: true)
        var evidence: [String: Any] = ["target": [
            "version": "target-1.0", "target": name == "no-target" ? NSNull() : 16,
            "lower": 14, "upper": 18, "sleep_score": 84, "sleep_minutes": 455,
            "recovery_score": 88, "wake_reserve": 81, "recent_load": 11.2,
            "history_days": 4, "readiness": 85, "limited": true,
        ]]
        if ["reserve-adjusted", "reserve-stale"].contains(name), var target = evidence["target"] as? [String: Any] {
            target["version"] = "target-1.1"
            target["target"] = 8
            target["lower"] = 6
            target["upper"] = 10
            target["base_target"] = 16
            target["current_reserve"] = 25
            target["reserve_adjustment"] = -8
            target["reserve_limit"] = 8
            target["reserve_fresh"] = name != "reserve-stale"
            target["observed_at"] = ISO8601DateFormatter().string(from: row.day.start.addingTimeInterval(3600))
            target["remaining"] = 1.6
            evidence["target"] = target
        }
        if name == "sessions" {
            let iso = ISO8601DateFormatter()
            let start = row.day.start.addingTimeInterval(Double(max(0, elapsed - 45)) * 60)
            evidence["sessions"] = [[
                "session_id": "A8C8CB12-4BF2-4000-A830-605A5F1EE236", "sport_mode": 25,
                "started_at": iso.string(from: start),
                "ended_at": iso.string(from: start.addingTimeInterval(1200)),
                "observed_seconds": 1200, "raw_load": 25, "load_delta": 1.73,
                "displayed_delta": 1.7, "load_before": 4.2, "load_after": 6.4,
            ]]
            row.segments.insert(TrainingSegment(at: start, name: "RECORDED SESSION", minutes: 20,
                avgHR: nil, steps: nil, delta: 1.7, allDay: false), at: 0)
        }
        row.applyTrainingSettlement(TrainingSettlement(evidence: evidence))
        return row
    }
}
#endif
