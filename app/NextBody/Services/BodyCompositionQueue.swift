import Foundation
import Combine

/// Durable, account-owned outbox for band BIA results. A scan is too expensive to repeat just
/// because the phone was offline, and it must never be uploaded under a later account.
@MainActor
final class BodyCompositionQueue {
    static let shared = BodyCompositionQueue()

    struct Pending: Codable, Identifiable {
        let id: UUID
        let ownerUserId: String
        let measuredAt: Date
        let userDay: String
        let inputWeightKg: Double
        let bodyFatPercent: Double
        let fatMassKg: Double
        let leanMassKg: Double
        let bmrKcal: Int?
    }

    private(set) var pending: [Pending] = []
    private let key = "nb.bodyComposition.pending"
    private var reachability: AnyCancellable?
    private var flushing = false
    private(set) var persistenceError: String?
    private func durable() throws -> DurableQueue<Pending> {
        DurableQueue(kind: "body-composition", store: try LocalDataStore.shared())
    }

    private init() {
        do {
            let queue = try durable()
            if let data = UserDefaults.standard.data(forKey: key) {
                let stored = try JSONDecoder().decode([Pending].self, from: data)
                try queue.importLegacy(stored) { ($0.id.uuidString, $0.ownerUserId) }
                UserDefaults.standard.removeObject(forKey: key)
            }
            pending = try queue.items()
        } catch { persistenceError = error.localizedDescription }
        reachability = Reachability.shared.$isOnline.removeDuplicates().sink { [weak self] online in
            if online { Task { await self?.flush() } }
        }
    }

    func enqueue(_ reading: BodyCompositionReading, at date: Date, ownerUserId: String) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let item = Pending(
            id: UUID(), ownerUserId: ownerUserId, measuredAt: date,
            userDay: formatter.string(from: UserDay.containing(date).date),
            inputWeightKg: reading.inputWeightKg, bodyFatPercent: reading.bodyFatPercent,
            fatMassKg: reading.fatMassKg, leanMassKg: reading.leanMassKg,
            bmrKcal: reading.bmrKcal)
        try durable().save(item, id: item.id.uuidString, account: ownerUserId)
        pending = try durable().items()
        Task { await flush() }
    }

    func flush() async {
        guard !flushing, Reachability.shared.isOnline, !DebugEdge.on("offline"),
              let currentUser = await SupabaseClient.shared.currentUserId else { return }
        flushing = true
        defer { flushing = false }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for item in pending where item.ownerUserId == currentUser {
            guard await SupabaseClient.shared.currentUserId == currentUser else { return }
            var row: [String: Any] = [
                "id": item.id.uuidString.lowercased(),
                "user_id": item.ownerUserId,
                "measured_at": iso.string(from: item.measuredAt),
                "user_day": item.userDay,
                "measurement_source": "device_bia",
                "input_weight_kg": item.inputWeightKg,
                "body_fat_pct": item.bodyFatPercent,
                "fat_mass_kg": item.fatMassKg,
                "lean_body_mass_kg": item.leanMassKg,
            ]
            if let bmr = item.bmrKcal { row["bmr_kcal"] = bmr }
            do {
                _ = try await SupabaseClient.shared.insert("body_composition", rows: [row],
                                                            returning: false)
                guard SupabaseClient.currentUserIdSnapshot() == currentUser, !Task.isCancelled else { return }
                try durable().acknowledge(id: item.id.uuidString, account: currentUser)
                pending = pending.filter { $0.id != item.id }
                await Analytics.shared.track("SCAN_SYNCED", ["SOURCE": "device_bia"])
            } catch SupabaseClient.Failure.http(let code, _) where code == 409 {
                do {
                    let accepted = try await SupabaseClient.shared.select("body_composition", query: [
                        .init(name: "id", value: "eq.\(item.id.uuidString.lowercased())"),
                        .init(name: "user_id", value: "eq.\(currentUser)"),
                    ])
                    guard let fact = accepted.first,
                          (fact["body_fat_pct"] as? NSNumber)?.doubleValue == item.bodyFatPercent,
                          (fact["input_weight_kg"] as? NSNumber)?.doubleValue == item.inputWeightKg,
                          (fact["fat_mass_kg"] as? NSNumber)?.doubleValue == item.fatMassKg,
                          (fact["lean_body_mass_kg"] as? NSNumber)?.doubleValue == item.leanMassKg,
                          fact["measurement_source"] as? String == "device_bia" else { break }
                    guard SupabaseClient.currentUserIdSnapshot() == currentUser, !Task.isCancelled else { return }
                try durable().acknowledge(id: item.id.uuidString, account: currentUser)
                    pending = pending.filter { $0.id != item.id }
                } catch { persistenceError = error.localizedDescription; break }
            } catch {
                BandLog.shared.record("body composition outbox", error: error)
                break
            }
        }
    }

    func purge() {
        do {
            for item in pending { try durable().acknowledge(id: item.id.uuidString, account: item.ownerUserId) }
            pending = []
            UserDefaults.standard.removeObject(forKey: key)
        } catch { persistenceError = error.localizedDescription }
    }
}
