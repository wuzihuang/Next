import Foundation

/// 常吃 — a plate worth keeping.
///
/// The cost of logging a meal should fall the more often you eat it. A favourite is the
/// items of a plate that was already written once: logging it again writes those same rows
/// with no model call, so the second time costs one tap and nothing is re-estimated.
///
/// ⚠️ A favourite is a copy, not a reference. Changing a favourite must not rewrite the
/// history that produced it, and deleting the meal it came from must not empty the list.
/// The server table has no foreign key to `meals` for exactly that reason.
@MainActor
final class MealFavorites: ObservableObject {
    static let shared = MealFavorites()

    struct Item: Codable, Hashable {
        var name: String
        var portion: String?
        var kcal: Double
        var protein: Double
        var carb: Double
        var fat: Double
        var fiber: Double?
        var sugar: Double?
        var sodium: Double?
    }

    struct Favorite: Identifiable, Hashable {
        let id: UUID
        var label: String
        var items: [Item]
        var photoPath: String?
        var uses: Int
        var kcal: Double { items.reduce(0) { $0 + $1.kcal } }
    }

    @Published private(set) var list: [Favorite] = []
    @Published var lastError: String?
    private var loadedFor: String?

    func load(force: Bool = false) async {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { list = []; loadedFor = nil; return }
        guard force || loadedFor != owner else { return }
        do {
            let rows = try await SupabaseClient.shared.select("meal_favorites", query: [
                .init(name: "select", value: "id,label,items,photo_path,uses,last_used_at"),
                .init(name: "order", value: "last_used_at.desc.nullslast"),
                .init(name: "limit", value: "12"),
            ])
            guard SupabaseClient.currentUserIdSnapshot() == owner else { return }
            list = rows.compactMap(Self.decode)
            loadedFor = owner
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Keep the rows of one plate. A row that belongs to a group takes the whole group with
    /// it — the plate is what a person means by "this meal", even though the table is a flat
    /// ledger of foods.
    func save(_ entry: MealEntry, from meals: [MealEntry]) async {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        let rows = entry.groupID.map { group in
            meals.filter { $0.groupID == group }.sorted { $0.at < $1.at }
        } ?? [entry]
        let items = (rows.isEmpty ? [entry] : rows).prefix(12).map {
            Item(name: $0.text, portion: $0.portion, kcal: $0.kcal, protein: $0.protein,
                 carb: $0.carb, fat: $0.fat, fiber: $0.fiber, sugar: $0.sugar, sodium: $0.sodium)
        }
        guard !items.isEmpty,
              let payload = try? JSONSerialization.jsonObject(
                with: JSONEncoder().encode(Array(items))) else { return }
        let label = items.count == 1 ? items[0].name
            : items.prefix(3).map(\.name).joined(separator: " · ")
        do {
            _ = try await SupabaseClient.shared.insert("meal_favorites", row: [
                "user_id": owner,
                "label": String(label.prefix(120)),
                "items": payload,
                "photo_path": entry.photoPath as Any,
            ])
            await load(force: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Write it again. No model call, no estimate, no confirmation — every number here was
    /// already accepted once by the person who saved it.
    func log(_ favorite: Favorite, day: UserDay, into data: DataStore) {
        var written: [UUID] = []
        for item in favorite.items {
            guard item.kcal >= 1 else { continue }
            if Band.allowsSeed {
                data.addManualMeal(text: item.name, kcal: Double(item.kcal), day: day)
                continue
            }
            do {
                written.append(try MealQueue.shared.createKnown(
                    item, day: day, into: data))
            } catch {
                lastError = error.localizedDescription
            }
        }
        if !written.isEmpty {
            data.postMealReceipt(favorite.label, added: written)
        }
        Task { await touch(favorite) }
    }

    func remove(_ favorite: Favorite) async {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        list.removeAll { $0.id == favorite.id }
        try? await SupabaseClient.shared.deleteWhere("meal_favorites", column: "id",
                                                     equals: favorite.id.uuidString.lowercased(),
                                                     expectedOwner: owner)
    }

    private func touch(_ favorite: Favorite) async {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]
        _ = try? await SupabaseClient.shared.patch("meal_favorites",
            id: favorite.id.uuidString.lowercased(),
            row: ["uses": favorite.uses + 1, "last_used_at": stamp.string(from: Date())],
            expectedOwner: owner)
    }

    private static func decode(_ row: [String: Any]) -> Favorite? {
        guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
              let label = row["label"] as? String,
              let raw = row["items"],
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let items = try? JSONDecoder().decode([Item].self, from: data),
              !items.isEmpty else { return nil }
        return Favorite(id: id, label: label, items: items,
                        photoPath: row["photo_path"] as? String,
                        uses: (row["uses"] as? NSNumber)?.intValue ?? 0)
    }
}
