import Foundation

/// One durable running-state receipt for an explicit strength mode. It contains no
/// calculated calories: the server replays the same versioned MET mapping from facts.
struct SportEnergyEvidence: Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let continuityID: UUID
    let observedAt: Date
    let sportMode: Int
    let sampledTimeZone: String
}

/// Running reports establish bounded intervals independently of optical contact.
/// Pauses, invalid/ambiguous modes, clock reversal and gaps break continuity.
struct SportEnergyEvidenceStream {
    static let maximumGap: TimeInterval = SportMetricAccumulator.liveWindow
    let sessionID: UUID
    private var continuityID = UUID()
    private var lastObservedAt: Date?

    init(sessionID: UUID = UUID()) { self.sessionID = sessionID }

    mutating func interrupted() {
        continuityID = UUID()
        lastObservedAt = nil
    }

    mutating func accept(at timestamp: Date, runState: Int?, sportMode: Int?,
                         timeZone: String) -> SportEnergyEvidence? {
        guard timestamp.timeIntervalSince1970.isFinite, runState == 1,
              let sportMode, SportMetricAccumulator.strengthMET(sportMode: sportMode) != nil,
              !timeZone.isEmpty else {
            interrupted()
            return nil
        }
        if let previous = lastObservedAt {
            let elapsed = timestamp.timeIntervalSince(previous)
            guard elapsed != 0 else { return nil }
            if elapsed < 0 || elapsed > Self.maximumGap { interrupted() }
        }
        lastObservedAt = timestamp
        return SportEnergyEvidence(id: UUID(), sessionID: sessionID,
            continuityID: continuityID, observedAt: timestamp, sportMode: sportMode,
            sampledTimeZone: timeZone)
    }
}
