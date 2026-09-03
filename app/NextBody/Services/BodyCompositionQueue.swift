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

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let stored = try? JSONDecoder().decode([Pending].self, from: data) {
            pending = stored
        }
        reachability = Reachability.shared.$isOnline.removeDuplicates().sink { [weak self] online in
            if online { Task { await self?.flush() } }
        }
    }

    func enqueue(_ reading: BodyCompositionReading, at date: Date, ownerUserId: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let item = Pending(
            id: UUID(), ownerUserId: ownerUserId, measuredAt: date,
            userDay: formatter.string(from: UserDay.containing(date).date),
            inputWeightKg: reading.inputWeightKg, bodyFatPercent: reading.bodyFatPercent,
            fatMassKg: reading.fatMassKg, leanMassKg: reading.leanMassKg,
            bmrKcal: reading.bmrKcal)
        pending = (pending + [item]).sorted { $0.measuredAt < $1.measuredAt }
        persist()
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
                pending = pending.filter { $0.id != item.id }
                await Analytics.shared.track("SCAN_SYNCED", ["SOURCE": "device_bia"])
            } catch SupabaseClient.Failure.http(let code, _) where code == 409 {
                pending = pending.filter { $0.id != item.id }
            } catch {
                BandLog.shared.record("body composition outbox", error: error)
                break
            }
        }
        persist()
    }

    func purge() {
        pending = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: key)
    }
}
