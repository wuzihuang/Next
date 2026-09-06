import Foundation
import Combine

/// Uses the existing account-scoped durable outbox. A valid live report is committed
/// before returning to the stream, then uploads in bounded batches. No measurement is
/// kept in a second in-memory queue that could restore data after account deletion.
@MainActor
final class SportEvidenceQueue {
    static let shared = SportEvidenceQueue()
    private static let kind = "sport-heart-rate"
    private var reachability: AnyCancellable?
    private var scheduled: Task<Void, Never>?
    private var flushing = false

    private init() {
        reachability = Reachability.shared.$isOnline.removeDuplicates().sink { online in
            if online { Task { await Repository.shared.flushPendingEvidence() } }
        }
    }

    func enqueue(_ observation: SportHeartRateEvidence, ownerUserId: String) throws {
        guard ownerUserId == SupabaseClient.currentUserIdSnapshot(), ConsentStore.shared.granted else {
            throw CancellationError()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try LocalDataStore.shared().enqueue(operation: LocalOperation(
            id: observation.id.uuidString.lowercased(), account: ownerUserId,
            kind: Self.kind, payload: try encoder.encode(observation)))
        guard scheduled == nil else { return }
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            self?.scheduled = nil
            guard !Task.isCancelled else { return }
            await Repository.shared.flushPendingEvidence()
        }
    }

    /// Repository owns publication/settlement after every evidence queue is drained.
    /// Snapshot the account's work so a continuing workout cannot extend this drain forever.
    func flush() async {
        guard !flushing, !Task.isCancelled, ConsentStore.shared.granted,
              Reachability.shared.isOnline, !DebugEdge.on("offline"),
              let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        flushing = true
        defer { flushing = false }
        do {
            let local = try LocalDataStore.shared()
            let snapshot = try local.operations(account: owner, kind: Self.kind)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for offset in stride(from: 0, to: snapshot.count, by: 300) {
                guard !Task.isCancelled, owner == SupabaseClient.currentUserIdSnapshot(),
                      ConsentStore.shared.granted else { return }
                let batch = Array(snapshot[offset..<min(offset + 300, snapshot.count)])
                let samples: [[String: Any]] = try batch.map { operation in
                    let sample = try JSONDecoder().decode(SportHeartRateEvidence.self, from: operation.payload)
                    var row: [String: Any] = [
                        "id": sample.id.uuidString.lowercased(),
                        "session_id": sample.sessionID.uuidString.lowercased(),
                        "continuity_id": sample.continuityID.uuidString.lowercased(),
                        "observed_at": formatter.string(from: sample.observedAt),
                        "heart_rate": sample.heartRate,
                        "sampled_tz": sample.sampledTimeZone,
                    ]
                    if let mode = sample.sportMode { row["sport_mode"] = mode }
                    return row
                }
                let result = try await SupabaseClient.shared.rpc("ingest_sport_heart_rate",
                    args: ["p_samples": samples], expectedOwner: owner)
                guard !Task.isCancelled, owner == SupabaseClient.currentUserIdSnapshot(),
                      ConsentStore.shared.granted else { return }
                guard let response = result as? [String: Any],
                      let acknowledged = response["acknowledged_ids"] as? [String],
                      Set(acknowledged.map { $0.lowercased() }) == Set(batch.map(\.id)) else {
                    throw LocalDataStore.Failure.database("Sport evidence receipt did not confirm the batch")
                }
                try local.acknowledge(account: owner, ids: batch.map(\.id))
            }
        } catch {
            BandLog.shared.record("sport evidence outbox", error: error)
        }
    }
}
