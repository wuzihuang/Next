import Foundation

/// The recommendation is published with its inputs. A present but unavailable target
/// is authoritative; only an older payload without the key may use a legacy range.
struct TrainingTargetEvidence: Codable, Hashable, Sendable {
    var version: String
    var target: Double?
    var lower: Double?
    var upper: Double?
    var sleepScore: Double?
    var sleepMinutes: Double?
    var recoveryScore: Double?
    var wakeReserve: Double?
    var recentLoad: Double?
    var historyDays: Int
    var readiness: Double?
    var limited: Bool
    var baseTarget: Double? = nil
    var currentReserve: Double? = nil
    var reserveAdjustment: Double? = nil
    var reserveLimit: Double? = nil
    var remaining: Double? = nil
    var observedAt: Date? = nil
    var reserveFresh: Bool? = nil

    var hasReserveLimit: Bool {
        version == "target-1.1" && reserveLimit != nil && currentReserve != nil
    }

    /// The server may deliberately retain a limit from an older observation.
    /// Only its explicit freshness flag permits describing the reading as current.
    var followsCurrentReserve: Bool { hasReserveLimit && reserveFresh == true }

    /// A cached publication keeps its limit, but time still passes while the page is open.
    func followsCurrentReserve(at now: Date) -> Bool {
        guard followsCurrentReserve, let observedAt else { return false }
        let age = now.timeIntervalSince(observedAt)
        return age >= 0 && age < 90 * 60
    }

    var optimalZone: ClosedRange<Double>? {
        guard let target, let lower, let upper,
              lower <= target, target <= upper else { return nil }
        return lower...upper
    }
}

/// One source's contribution to the day's cumulative curve. The whole-day load can
/// also grow from other activity between startedAt and endedAt, so their difference
/// is deliberately never used to reconstruct this session's loadDelta.
struct TrainingSessionContribution: Codable, Hashable, Identifiable, Sendable {
    var id: UUID { sessionID }
    var sessionID: UUID
    var sportMode: Int?
    var startedAt: Date
    var endedAt: Date
    var observedSeconds: Double
    var rawLoad: Double
    var loadDelta: Double
    var loadBefore: Double
    var loadAfter: Double
    var displayedDelta: Double?

    var deltaText: String {
        Self.deltaText(loadDelta, displayed: displayedDelta)
    }

    var reachesScaleLimit: Bool { rawLoad > 0 && loadAfter >= 20.9 }

    static func deltaText(_ delta: Double, displayed: Double? = nil) -> String {
        let shown = displayed ?? delta
        if delta > 0, shown < 0.1 { return "+<0.1" }
        return String(format: "+%.1f", max(0, shown))
    }

    static func overlaps(startedAt: Date, endedAt: Date, day: UserDay) -> Bool {
        startedAt < day.end && endedAt > day.start
    }
}

/// A saved declaration is visible even when no sensor evidence can price its load.
struct UnmeasuredTrainingSession: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var sportMode: Int?
    var startedAt: Date
    var endedAt: Date
}

struct TrainingSettlement: Codable, Hashable, Sendable {
    var target: TrainingTargetEvidence?
    var sessions: [TrainingSessionContribution]
    // Optional so snapshots written before backfill support continue to decode.
    var unmeasuredSessions: [UnmeasuredTrainingSession]? = nil

    init(evidence: [String: Any]?) {
        unmeasuredSessions = ((evidence?["sessions"] as? [[String: Any]]) ?? []).compactMap { row in
            guard row["source"] as? String == "manual", row["data_status"] as? String == "missing",
                  let id = (row["session_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let start = Self.timestamp(row["started_at"]), let end = Self.timestamp(row["ended_at"]),
                  end > start else { return nil }
            return UnmeasuredTrainingSession(id: id,
                sportMode: Self.number(row["sport_mode"], in: 0...65535).map(Int.init), startedAt: start, endedAt: end)
        }.sorted { $0.startedAt < $1.startedAt }
        if let evidence, evidence.keys.contains("target") {
            let row = evidence["target"] as? [String: Any] ?? [:]
            target = TrainingTargetEvidence(
                version: row["version"] as? String ?? "",
                target: Self.number(row["target"], in: 0...21),
                lower: Self.number(row["lower"], in: 0...21),
                upper: Self.number(row["upper"], in: 0...21),
                sleepScore: Self.number(row["sleep_score"], in: 0...100),
                sleepMinutes: Self.number(row["sleep_minutes"], in: 0...1440),
                recoveryScore: Self.number(row["recovery_score"], in: 0...100),
                wakeReserve: Self.number(row["wake_reserve"], in: 0...100),
                recentLoad: Self.number(row["recent_load"], in: 0...21),
                historyDays: Int(Self.number(row["history_days"], in: 0...365) ?? 0),
                readiness: Self.number(row["readiness"], in: 0...100),
                limited: row["limited"] as? Bool ?? true,
                baseTarget: Self.number(row["base_target"], in: 0...21),
                currentReserve: Self.number(row["current_reserve"], in: 0...100),
                reserveAdjustment: Self.number(row["reserve_adjustment"], in: -21...21))
            target?.reserveLimit = Self.number(row["reserve_limit"], in: 0...21)
            target?.remaining = Self.number(row["remaining"], in: 0...21)
            target?.observedAt = Self.timestamp(row["observed_at"])
            target?.reserveFresh = row["reserve_fresh"] as? Bool
        } else {
            target = nil
        }
        sessions = ((evidence?["sessions"] as? [[String: Any]]) ?? []).compactMap { row in
            guard let id = (row["session_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let start = Self.timestamp(row["started_at"]),
                  let end = Self.timestamp(row["ended_at"]), end >= start,
                  let observed = Self.number(row["observed_seconds"], in: 0...172800),
                  let raw = Self.number(row["raw_load"]), raw >= 0,
                  let delta = Self.number(row["load_delta"], in: 0...21),
                  let before = Self.number(row["load_before"], in: 0...21),
                  let after = Self.number(row["load_after"], in: 0...21), after >= before else { return nil }
            return TrainingSessionContribution(sessionID: id,
                sportMode: Self.number(row["sport_mode"], in: 0...65535).map(Int.init),
                startedAt: start, endedAt: end, observedSeconds: observed,
                rawLoad: raw, loadDelta: delta, loadBefore: before, loadAfter: after,
                displayedDelta: Self.number(row["displayed_delta"], in: 0...21))
        }.sorted { $0.startedAt < $1.startedAt }
    }

    func recommendation(legacyTarget: Double?, legacyZone: ClosedRange<Double>?)
        -> (target: Double?, zone: ClosedRange<Double>?) {
        guard let target else { return (legacyTarget, legacyZone) }
        return (target.target, target.optimalZone)
    }

    /// Reading the latest snapshot each time turns a pending recap into a settled one
    /// as soon as publication lands, without storing a second copy of calculated load.
    func session(_ sessionID: UUID?, on day: UserDay) -> TrainingSessionContribution? {
        guard let sessionID else { return nil }
        return sessions.first {
            $0.sessionID == sessionID
                && TrainingSessionContribution.overlaps(startedAt: $0.startedAt, endedAt: $0.endedAt, day: day)
        }
    }

    private static func number(_ value: Any?, in range: ClosedRange<Double>? = nil) -> Double? {
        let value = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        guard let value, value.isFinite, range?.contains(value) != false else { return nil }
        return value
    }

    private static func timestamp(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
