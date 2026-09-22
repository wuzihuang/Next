import Foundation
import Combine

/// Finished workouts survive navigation, restart and (after upload) reinstallation.
/// Sensor evidence and calculated load keep their existing publication path.
@MainActor
final class SportRecapStore: ObservableObject {
    static let shared = SportRecapStore()
    @Published private(set) var recaps: [SportSessionRecap] = []
    @Published private(set) var errorLine: String?
    @Published private(set) var pendingCount = 0
    @Published var updatingTraining = false
    @Published var trainingError: String?
    private var account: String?
    private var flushing = false
    private var unsaved: [SportSessionRecap] = []

    func reset() {
        account = nil
        recaps = []
        unsaved = []
        errorLine = nil
        pendingCount = 0
        updatingTraining = false
        trainingError = nil
    }

    private func adopt(_ owner: String) throws -> SportRecapArchive {
        // Bind before opening disk: a failed first open must not make the next retry
        // reset this owner's unsaved record. Only an actual account change discards it.
        if account != owner {
            reset()
            account = owner
        }
        let archive = SportRecapArchive(local: try LocalDataStore.shared())
        if recaps.isEmpty { recaps = try archive.read(owner: owner) }
        return archive
    }

    func record(_ recap: SportSessionRecap) {
        guard !Band.allowsSeed, ConsentStore.shared.granted,
              let owner = SupabaseClient.currentUserIdSnapshot(), recap.ownerUserID == owner else { return }
        do {
            let archive = try adopt(owner)
            try archive.stage(recap, owner: owner)
            recaps = try archive.read(owner: owner)
            pendingCount = try archive.local.operations(account: owner, kind: SportRecapArchive.kind).count
            errorLine = nil
        } catch {
            unsaved.removeAll { $0.id == recap.id }
            unsaved.append(recap)
            recaps.removeAll { $0.id == recap.id }
            recaps.insert(recap, at: 0)
            errorLine = L("Session could not be saved. Retry before closing the app.")
            BandLog.shared.record("save session recap", error: error)
        }
    }

    func flush() async {
        guard !Band.allowsSeed, !flushing, ConsentStore.shared.granted,
              let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        guard Reachability.shared.isOnline else {
            errorLine = L("Session upload is waiting for a connection.")
            return
        }
        flushing = true
        let generation = Repository.shared.sessionGeneration
        defer { flushing = false }
        do {
            let archive = try adopt(owner)
            unsaved = archive.stagePending(unsaved.filter { $0.ownerUserID == owner }, owner: owner)
            recaps = try archive.read(owner: owner)
            let operations = try archive.local.operations(account: owner, kind: SportRecapArchive.kind)
            pendingCount = operations.count
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var uploadFailed = false
            for operation in operations {
                guard current(owner, generation) else { return }
                do {
                    let recap = try JSONDecoder().decode(SportSessionRecap.self, from: operation.payload)
                    guard let id = recap.sessionID, recap.ownerUserID == owner else { continue }
                    let payload = try JSONSerialization.jsonObject(with: operation.payload)
                    let result = try await SupabaseClient.shared.rpc("save_sport_recap", args: [
                        "p_id": id.uuidString.lowercased(), "p_started_at": formatter.string(from: recap.startedAt),
                        "p_ended_at": formatter.string(from: recap.endedAt), "p_payload": payload,
                    ], expectedOwner: owner)
                    guard current(owner, generation) else { return }
                    guard let receipt = result as? [String: Any],
                          (receipt["id"] as? String)?.lowercased() == id.uuidString.lowercased() else {
                        throw LocalDataStore.Failure.database("Missing session receipt")
                    }
                    try archive.local.acknowledge(account: owner, id: operation.id)
                    pendingCount -= 1
                } catch {
                    guard current(owner, generation) else { return }
                    uploadFailed = true
                    BandLog.shared.record("upload session recap", error: error)
                    // Keep this immutable operation for retry, but allow other sessions
                    // to publish if a single malformed record is refused permanently.
                }
            }
            pendingCount = try archive.local.operations(account: owner, kind: SportRecapArchive.kind).count
            if !unsaved.isEmpty {
                errorLine = unsaved.contains(where: { !$0.isValid })
                    ? L("This session exceeds the supported record limits. Other sessions can still sync.")
                    : L("Session could not be saved. Retry before closing the app.")
            } else {
                errorLine = uploadFailed ? L("Session upload failed. Your record is saved on this phone. Retry sync.") : nil
            }
        } catch {
            guard current(owner, generation) else { return }
            errorLine = unsaved.isEmpty
                ? L("Session upload failed. Your record is saved on this phone. Retry sync.")
                : L("Session could not be saved. Retry before closing the app.")
            BandLog.shared.record("upload session recap", error: error)
        }
    }

    func load() async {
        guard !Band.allowsSeed, let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        let generation = Repository.shared.sessionGeneration
        do {
            let archive = try adopt(owner)
            pendingCount = try archive.local.operations(account: owner, kind: SportRecapArchive.kind).count
            var offset = 0
            repeat {
                let rows = try await SupabaseClient.shared.select("sport_session_recaps", query: [
                    .init(name: "select", value: "id,payload"),
                    .init(name: "order", value: "started_at.desc,id.desc"),
                    .init(name: "limit", value: "200"), .init(name: "offset", value: String(offset)),
                ])
                guard current(owner, generation) else { return }
                let loaded = rows.compactMap { row -> SportSessionRecap? in
                    guard let payload = row["payload"], let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                          let bytes = try? JSONSerialization.data(withJSONObject: payload),
                          var recap = try? JSONDecoder().decode(SportSessionRecap.self, from: bytes) else { return nil }
                    recap.ownerUserID = owner
                    recap.sessionID = id
                    guard recap.isValid else { return nil }
                    return recap
                }
                try archive.cache(loaded, owner: owner)
                recaps = try archive.read(owner: owner)
                if rows.count < 200 { break }
                offset += rows.count
            } while !Task.isCancelled
        } catch {
            guard current(owner, generation) else { return }
            errorLine = L("Session history could not refresh. Saved records are still available.")
            BandLog.shared.record("read session recaps", error: error)
        }
    }

    func retry() async {
        await Repository.shared.settleAfterSport()
        await load()
    }

    private func current(_ owner: String, _ generation: UInt) -> Bool {
        !Task.isCancelled && ConsentStore.shared.granted
            && owner == SupabaseClient.currentUserIdSnapshot()
            && generation == Repository.shared.sessionGeneration
    }
}
