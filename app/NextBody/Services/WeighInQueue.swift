import Foundation
import Combine

/// 10S rule 09 · save is optimistic: the sheet closes, the number changes, and the row goes
/// up when it can. Edge 4 · OFFLINE: `SAVED · NOT SYNCED`, "IT'LL GO UP LATER" — the queue
/// retries on its own, no dialog, no rollback. Pending rows survive a relaunch.
@MainActor
final class WeighInQueue: ObservableObject {
    static let shared = WeighInQueue()

    struct Pending: Codable, Identifiable {
        let id: UUID            // client_op_id — the server dedupes on it
        let measuredAt: Date
        let tz: String
        let kg: Double
        let source: String      // 'manual' | 'health' | 'band'
        let healthUUID: String?
    }

    @Published private(set) var pending: [Pending] = []
    private let key = "nb.weighins.pending"
    private var reach: AnyCancellable?
    private var flushing = false

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let rows = try? JSONDecoder().decode([Pending].self, from: d) { pending = rows }
        reach = Reachability.shared.$isOnline.removeDuplicates().sink { [weak self] online in
            if online { Task { await self?.flush() } }
        }
    }

    func isPending(_ id: UUID) -> Bool { pending.contains { $0.id == id } }

    func enqueue(_ w: WeighIn) {
        let source: String = switch w.origin { case .health: "health"; case .band: "band"; case .manual: "manual" }
        pending.append(Pending(id: w.id, measuredAt: w.date, tz: TimeZone.current.identifier,
                               kg: w.weightKg, source: source, healthUUID: w.healthUUID))
        persist()
        Task { await flush() }
    }

    /// One row at a time, oldest first. A refusal that means "already there" (the unique
    /// client_op index) clears the row too; anything else keeps it for the next try.
    func flush() async {
        guard !flushing, !pending.isEmpty else { return }
        guard Reachability.shared.isOnline, !DebugEdge.on("offline") else { return }
        guard let userId = await SupabaseClient.shared.userId else { return }
        flushing = true; defer { flushing = false }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for row in pending {
            do {
                _ = try await SupabaseClient.shared.insert("weigh_ins", rows: [[
                    "user_id": userId,
                    "measured_at": iso.string(from: row.measuredAt),
                    "sampled_tz": row.tz,
                    "weight_kg": row.kg,
                    "source": row.source,
                    "health_uuid": row.healthUUID as Any,
                    "client_op_id": row.id.uuidString.lowercased(),
                ]], returning: false)
                pending.removeAll { $0.id == row.id }
                await Analytics.shared.track("WEIGHIN_SYNCED", ["SOURCE": row.source])
            } catch SupabaseClient.Failure.http(let code, _) where code == 409 {
                pending.removeAll { $0.id == row.id }
            } catch {
                #if DEBUG
                NSLog("WeighInQueue: kept %@ (%@)", row.id.uuidString, "\(error)")
                #endif
                break
            }
        }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: key)
    }
}
