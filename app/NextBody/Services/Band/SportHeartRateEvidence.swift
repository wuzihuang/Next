import Foundation

/// Raw observations only. Training weights and load integration stay on the server.
struct SportHeartRateEvidence: Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let continuityID: UUID
    let observedAt: Date
    let heartRate: Int
    /// Joining an already-running workout does not verify its mode.
    let sportMode: Int?
    let sampledTimeZone: String
}

/// A continuity ends on missing contact, pause, stream replacement, clock reversal or
/// a gap exceeding 15 seconds. Neither a joined session nor an app restart invents
/// observations for the earlier workout. SQL also enforces the same interval limit.
struct SportHeartRateEvidenceStream {
    static let maximumGap: TimeInterval = 15
    let sessionID: UUID
    private var continuityID = UUID()
    private var lastObservedAt: Date?

    init(sessionID: UUID = UUID()) { self.sessionID = sessionID }

    mutating func interrupted() {
        continuityID = UUID()
        lastObservedAt = nil
    }

    mutating func accept(at timestamp: Date, heartRate: Int?, runState: Int?,
                         sportMode: Int?, timeZone: String) -> SportHeartRateEvidence? {
        guard timestamp.timeIntervalSince1970.isFinite,
              let heartRate, (1...250).contains(heartRate),
              runState == nil || runState == 1 else {
            interrupted()
            return nil
        }
        if let previous = lastObservedAt {
            let elapsed = timestamp.timeIntervalSince(previous)
            // An exact duplicate callback is not another observation.
            guard elapsed != 0 else { return nil }
            if elapsed < 0 || elapsed > Self.maximumGap { interrupted() }
        }
        lastObservedAt = timestamp
        return SportHeartRateEvidence(id: UUID(), sessionID: sessionID,
            continuityID: continuityID, observedAt: timestamp, heartRate: heartRate,
            sportMode: sportMode.flatMap { (0...65535).contains($0) ? $0 : nil },
            sampledTimeZone: timeZone)
    }
}
