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
        /// The account that created this operation. A queued health row is never reassigned
        /// to whoever happens to sign in next.
        let ownerUserId: String?
    }

    @Published private(set) var pending: [Pending] = []
    private let key = "nb.weighins.pending"
    private var reach: AnyCancellable?
    private var flushing = false
    private var flushWaiters: [CheckedContinuation<Void, Never>] = []
    @Published private(set) var persistenceError: String?
    private func durable() throws -> DurableQueue<Pending> {
        DurableQueue(kind: "weigh-in", store: try LocalDataStore.shared())
    }

    private init() {
        do {
            let queue = try durable()
            if let d = UserDefaults.standard.data(forKey: key) {
                let rows = try JSONDecoder().decode([Pending].self, from: d)
                // Unknown ownership remains in the legacy store for explicit recovery.
                let owned = rows.filter { $0.ownerUserId != nil }
                try queue.importLegacy(owned) { ($0.id.uuidString, $0.ownerUserId!) }
                if owned.count == rows.count { UserDefaults.standard.removeObject(forKey: key) }
                else { UserDefaults.standard.set(try JSONEncoder().encode(rows.filter { $0.ownerUserId == nil }), forKey: key) }
            }
            pending = try queue.items()
        } catch { persistenceError = error.localizedDescription }
        reach = Reachability.shared.$isOnline.removeDuplicates().sink { [weak self] online in
            if online { Task { await self?.flush() } }
        }
    }

    /// 11 · DELETE EVERYTHING. ⚠️ The queue outlives a sign-out on purpose, and that is
    /// exactly what makes it dangerous here: rows left on the phone are flushed by whoever
    /// signs in next, so a deleted account's weights would land in a stranger's history
    /// under a fresh client_op_id the server has no reason to refuse. In memory first —
    /// clearing only the stored copy would let the next persist() write the array back.
    func purge() {
        do {
            for row in pending {
                if let owner = row.ownerUserId { try durable().acknowledge(id: row.id.uuidString, account: owner) }
            }
            pending = []
            UserDefaults.standard.removeObject(forKey: key)
        } catch { persistenceError = error.localizedDescription }
    }

    func isPending(_ id: UUID) -> Bool { pending.contains { $0.id == id } }

    func enqueue(_ w: WeighIn, ownerUserId: String) throws {
        let source: String = switch w.origin { case .health: "health"; case .band: "band"; case .manual: "manual" }
        let item = Pending(id: w.id, measuredAt: w.date, tz: TimeZone.current.identifier,
                               kg: w.weightKg, source: source, healthUUID: w.healthUUID,
                               ownerUserId: ownerUserId)
        try durable().save(item, id: item.id.uuidString, account: ownerUserId)
        pending = try durable().items()
        Task { await flush() }
    }

    /// One row at a time, oldest first. A refusal that means "already there" (the unique
    /// client_op index) clears the row too; anything else keeps it for the next try.
    @discardableResult
    func flush() async -> Bool {
        if flushing {
            await withCheckedContinuation { flushWaiters.append($0) }
            // Another edit may have been queued during the upload we just awaited.
            return await flush()
        }
        guard !pending.isEmpty else { return true }
        guard Reachability.shared.isOnline, !DebugEdge.on("offline") else { return false }
        flushing = true
        defer {
            flushing = false
            let waiters = flushWaiters
            flushWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        guard let userId = await SupabaseClient.shared.userId else { return false }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for row in pending where row.ownerUserId == userId {
            guard await SupabaseClient.shared.userId == userId else { return false }
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
                guard SupabaseClient.currentUserIdSnapshot() == userId, !Task.isCancelled else { return false }
                try durable().acknowledge(id: row.id.uuidString, account: userId)
                pending = pending.filter { $0.id != row.id }
                await Analytics.shared.track("WEIGHIN_SYNCED", ["SOURCE": row.source])
            } catch SupabaseClient.Failure.http(let code, _) where code == 409 {
                do {
                    let accepted = try await SupabaseClient.shared.select("weigh_ins", query: [
                        .init(name: "client_op_id", value: "eq.\(row.id.uuidString.lowercased())"),
                        .init(name: "user_id", value: "eq.\(userId)"),
                        .init(name: "select", value: "weight_kg,source,measured_at"),
                    ])
                    guard let fact = accepted.first,
                          (fact["weight_kg"] as? NSNumber)?.doubleValue == row.kg,
                          fact["source"] as? String == row.source,
                          let stamp = fact["measured_at"] as? String,
                          let date = iso.date(from: stamp), abs(date.timeIntervalSince(row.measuredAt)) < 0.001 else { break }
                    guard SupabaseClient.currentUserIdSnapshot() == userId, !Task.isCancelled else { return false }
                    try durable().acknowledge(id: row.id.uuidString, account: userId)
                    pending = pending.filter { $0.id != row.id }
                } catch { persistenceError = error.localizedDescription; break }
            } catch {
                #if DEBUG
                NSLog("WeighInQueue: kept %@ (%@)", row.id.uuidString, "\(error)")
                #endif
                break
            }
        }
        return !pending.contains { $0.ownerUserId == userId }
    }
}
