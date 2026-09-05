import Foundation

/// An empty successful read means not collected, never an inferred healthy measurement.
enum BandDomainReadStatus: String, Codable, Sendable {
    case complete, notCollected = "not_collected", unsupported, failed, partial
}

struct BandIngestionAcknowledgment: Decodable, Sendable {
    let inserted: Int
    let completed: Int
    let unchanged: Int
    let rejected: Int
    let affectedDays: [String]
    enum CodingKeys: String, CodingKey {
        case inserted, completed, unchanged, rejected
        case affectedDays = "affected_days"
    }
    var hasChanges: Bool { inserted + completed > 0 }
    func confirms(offered: Int) -> Bool {
        inserted >= 0 && completed >= 0 && unchanged >= 0 && rejected == 0
            && inserted + completed + unchanged == offered
    }
}

/// Only acknowledged ranges are durable. Each failed read/upload retains its repair range.
struct BandDomainSyncState: Codable, Sendable {
    let domain: String
    let status: BandDomainReadStatus
    let attemptedAt: Date
    let acknowledgedStart: Date?
    let acknowledgedEnd: Date?
    let repairStart: Date?
    let repairEnd: Date?

    static func load(userId: String, deviceKey: String, day: String) -> [BandDomainSyncState] {
        guard let data = UserDefaults.standard.data(forKey: key(userId, deviceKey, day)) else { return [] }
        return (try? JSONDecoder().decode([BandDomainSyncState].self, from: data)) ?? []
    }
    static func save(_ states: [BandDomainSyncState], userId: String, deviceKey: String, day: String) throws {
        let previous = load(userId: userId, deviceKey: deviceKey, day: day)
        let merged = states.map { state in
            let old = previous.first { $0.domain == state.domain }
            return BandDomainSyncState(domain: state.domain, status: state.status, attemptedAt: state.attemptedAt,
                acknowledgedStart: state.acknowledgedStart ?? old?.acknowledgedStart,
                acknowledgedEnd: state.acknowledgedEnd ?? old?.acknowledgedEnd,
                repairStart: state.repairStart, repairEnd: state.repairEnd)
        }
        UserDefaults.standard.set(try JSONEncoder().encode(merged), forKey: key(userId, deviceKey, day))
    }
    static func purge(userId: String) {
        let prefix = "nb.sync.domains.v1.\(userId)."
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    private static func key(_ user: String, _ device: String, _ day: String) -> String {
        "nb.sync.domains.v1.\(user).\(device).\(day)"
    }
}

/// One drain owns a finite snapshot; newly queued observations belong to the next drain.
enum EvidenceDrainPolicy {
    static func batches<T>(_ pending: [T], limit: Int) -> [[T]] {
        guard limit > 0 else { return [] }
        return stride(from: 0, to: pending.count, by: limit).map {
            Array(pending[$0..<min($0 + limit, pending.count)])
        }
    }
    static func confirmedIDs(_ ids: [String], offeredSamples: Int,
                             acknowledgment: BandIngestionAcknowledgment) -> [String] {
        guard offeredSamples > 0, acknowledgment.confirms(offered: offeredSamples) else { return [] }
        return ids
    }
    static func shouldContinue(acknowledged: Int) -> Bool { acknowledged > 0 }
}
