#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Training-only UI fixtures. They transform the view's local read without
/// mutating DataStore or the sample data used by other screens.
enum TrainingDebugFixture {
    static var name: String? {
        let value = ProcessInfo.processInfo.environment["NB_DEBUG_TRAINING_FIXTURE"]
        return ["no-target", "empty-curve", "baseline"].contains(value ?? "") ? value : nil
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
        return row
    }
}
#endif
