import Foundation
import Combine

/// Meals use the same durable, account-owned ordered outbox as measurements.
@MainActor
final class MealQueue: ObservableObject {
    static let shared = MealQueue()
    @Published private(set) var lastError: String?
    @Published private(set) var pendingCount = 0
    struct Rejected: Identifiable { let id: String; let name: String; let reason: String }
    @Published private(set) var rejected: [Rejected] = []
    private var flushing = false
    private var activeEstimates: Set<String> = []
    private var reachability: AnyCancellable?
    private var retry: Task<Void, Never>?
    private var retryDelay: UInt64 = 2
    private init() {
        reachability = Reachability.shared.$isOnline.removeDuplicates().sink { [weak self] online in
            if online { Task { await self?.flush() } }
        }
    }
    func beginEstimate(entry: MealEntry, request: [String: Any], owner: String) throws {
        if entry.day == DataStore.shared.today.day, case .fasted = DataStore.shared.today.fuelState {
            throw LocalDataStore.Failure.database(L("This day is marked as fasted."))
        }
        guard ConsentStore.shared.granted else { throw LocalDataStore.Failure.database(L("Data collection is paused.")) }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let id = entry.id.uuidString.lowercased()
        let body: [String: Any] = ["id": id, "user_day": formatter.string(from: entry.day.start),
                                   "slot": entry.slot.rawValue, "name": entry.text, "request": request]
        let envelope: [String: Any] = ["kind": "estimate", "meal_id": id, "body": body]
        let payload = try JSONSerialization.data(withJSONObject: envelope, options: .sortedKeys)
        // The photo/request has one durable copy; the local display document is lightweight.
        let display: [String: Any] = ["kind": "estimate", "meal_id": id,
                                      "body": body.filter { $0.key != "request" }]
        try LocalDataStore.shared().enqueue(operation: LocalOperation(id: id, account: owner, kind: "meal", payload: payload),
                                            documentKey: "meal.\(id)",
                                            document: JSONSerialization.data(withJSONObject: display, options: .sortedKeys))
        activeEstimates.insert(id)
        pendingCount = try LocalDataStore.shared().operations(account: owner, kind: "meal").count
    }
    func releaseEstimate(_ id: UUID) {
        activeEstimates.remove(id.uuidString.lowercased())
        Task { await flush() }
    }
    func promoteEstimate(mealID: UUID, output: [String: Any], owner: String) throws {
        let id = mealID.uuidString.lowercased()
        guard let pending = try LocalDataStore.shared().operations(account: owner, kind: "meal").first(where: { $0.id == id }) else {
            throw LocalDataStore.Failure.conflictingOperation
        }
        guard ConsentStore.shared.granted else { throw LocalDataStore.Failure.database(L("Data collection is paused.")) }
        try promote(pending, output: output)
    }
    private func promote(_ operation: LocalOperation, output: [String: Any]) throws {
        let payload = try MealOutboxPolicy.promotedEstimate(operation, output: output)
        try LocalDataStore.shared().replaceOperation(operation, payload: payload, documentKey: "meal.\(operation.id)")
    }

    func enqueueCreate(mealID: UUID, payload: [String: Any], ownerUserId: String) throws {
        guard let draft = payload["draft_id"] as? String, UUID(uuidString: draft) != nil else {
            throw LocalDataStore.Failure.conflictingOperation
        }
        let body = payload.merging(["id": mealID.uuidString.lowercased()]) { _, new in new }
        try enqueue(id: draft, owner: ownerUserId, kind: "create", mealID: mealID, body: body)
    }
    func enqueueDelete(mealID: UUID, ownerUserId: String) throws {
        let id = UUID().uuidString.lowercased()
        try enqueue(id: id, owner: ownerUserId, kind: "delete", mealID: mealID,
                    body: ["operation_id": id, "kind": "delete", "meal_id": mealID.uuidString.lowercased()])
    }
    func enqueueAmend(mealID: UUID, replacement: [String: Any], ownerUserId: String) throws {
        guard ConsentStore.shared.granted else { throw LocalDataStore.Failure.database(L("Data collection is paused.")) }
        let id = UUID().uuidString.lowercased()
        let replacement = replacement.merging(["id": UUID().uuidString.lowercased()]) { old, _ in old }
        try enqueue(id: id, owner: ownerUserId, kind: "amend", mealID: mealID,
                    body: ["operation_id": id, "kind": "amend", "meal_id": mealID.uuidString.lowercased(), "replacement": replacement])
    }
    private func enqueue(id: String, owner: String, kind: String, mealID: UUID, body: [String: Any]) throws {
        let envelope: [String: Any] = ["kind": kind, "meal_id": mealID.uuidString.lowercased(), "body": body]
        let bytes = try JSONSerialization.data(withJSONObject: envelope, options: .sortedKeys)
        try LocalDataStore.shared().enqueue(operation: LocalOperation(id: id, account: owner, kind: "meal", payload: bytes),
                                            documentKey: "meal.\(mealID.uuidString.lowercased())", document: bytes)
        pendingCount = try LocalDataStore.shared().operations(account: owner, kind: "meal").count
        Task { await flush() }
    }
    func pendingMealDocuments(ownerUserId: String) throws -> [[String: Any]] {
        try LocalDataStore.shared().operations(account: ownerUserId, kind: "meal").map {
            guard let object = try JSONSerialization.jsonObject(with: $0.payload) as? [String: Any] else {
                throw LocalDataStore.Failure.database("Invalid queued meal")
            }
            return object
        }
    }
    func overlayPending(into data: DataStore, ownerUserId: String) {
        guard SupabaseClient.currentUserIdSnapshot() == ownerUserId else { return }
        do {
            refreshStatus(owner: ownerUserId)
            let pending = try pendingMealDocuments(ownerUserId: ownerUserId)
            pendingCount = pending.count
            guard !pending.isEmpty else { return }
            var entries: [MealEntry] = []
            var removed = Set<UUID>()
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            for envelope in pending {
                guard let kind = envelope["kind"] as? String, let body = envelope["body"] as? [String: Any],
                      let original = envelope["meal_id"] as? String, let originalID = UUID(uuidString: original) else { continue }
                if let previous = envelope["canonical_previous_id"] as? String, let oldID = UUID(uuidString: previous) {
                    removed.insert(oldID)
                    entries = entries.filter { $0.id != oldID }
                }
                if kind == "amend" || kind == "delete" {
                    removed.insert(originalID)
                    entries = entries.filter { $0.id != originalID }
                }
                if kind == "delete" { continue }
                let fields = kind == "amend" ? body["replacement"] as? [String: Any] : body
                guard let fields, let id = fields["id"] as? String, let uuid = UUID(uuidString: id),
                      let date = fields["user_day"] as? String, let midnight = formatter.date(from: date),
                      let noon = Calendar.current.date(byAdding: .hour, value: 12, to: midnight),
                      let slot = (fields["slot"] as? String).flatMap(MealEntry.Slot.init(rawValue:)) else { continue }
                let day = UserDay.containing(noon)
                entries = entries.filter { $0.id != uuid } + [MealEntry(id: uuid, day: day, at: noon,
                    slot: slot, status: kind == "estimate" || envelope["rejection"] != nil ? .open : .confirmed, text: fields["name"] as? String ?? "",
                    kcal: (fields["kcal"] as? NSNumber)?.doubleValue ?? 0,
                    protein: (fields["protein_g"] as? NSNumber)?.intValue ?? 0,
                    carb: (fields["carb_g"] as? NSNumber)?.intValue ?? 0,
                    fat: (fields["fat_g"] as? NSNumber)?.intValue ?? 0)]
            }
            data.overlayPendingMeals(entries, removedIDs: removed)
            pendingCount = pending.count
        } catch { lastError = error.localizedDescription }
    }

    func refreshStatus(owner: String) {
        guard SupabaseClient.currentUserIdSnapshot() == owner else { rejected = []; pendingCount = 0; return }
        do {
            let operations = try LocalDataStore.shared().operations(account: owner, kind: "meal")
            pendingCount = operations.count
            rejected = try operations.compactMap { operation in
                guard let message = try MealOutboxPolicy.rejection(operation) else { return nil }
                let fields = try MealOutboxPolicy.fields(operation)
                let body = fields["body"] as? [String: Any] ?? [:]
                return Rejected(id: operation.id, name: body["name"] as? String ?? L("Meal change"), reason: message)
            }
        } catch { lastError = error.localizedDescription }
    }
    func retryRejected(_ id: String) {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        do {
            let store = try LocalDataStore.shared()
            guard let operation = try store.operations(account: owner, kind: "meal").first(where: { $0.id == id }) else { return }
            let payload = try MealOutboxPolicy.replacingRejection(operation, message: nil)
            try store.replaceOperation(operation, payload: payload, documentKey: "meal.\(id)")
            refreshStatus(owner: owner)
            Task { await flush() }
        } catch { lastError = error.localizedDescription }
    }
    /// Explicitly removes only a rejected local change and its dependent changes.
    func discardRejected(_ id: String, into data: DataStore) {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        do {
            let store = try LocalDataStore.shared()
            let chain = try MealOutboxPolicy.rejectedChain(id, operations: store.operations(account: owner, kind: "meal"))
            var removed = Set<UUID>()
            for operation in chain {
                removed.formUnion(try MealOutboxPolicy.affectedMeals(operation).compactMap(UUID.init(uuidString:)))
            }
            data.overlayPendingMeals([], removedIDs: removed)
            // A previous successful operation may have cached these pending changes too.
            // Remove that display copy before discarding the only durable rejection record.
            guard HomeSnapshot.save(from: data) else {
                throw LocalDataStore.Failure.database("Could not save discarded meals locally")
            }
            for operation in chain { try store.acknowledge(account: owner, id: operation.id) }
            refreshStatus(owner: owner)
            Task { await Repository.shared.loadToday(into: data) }
        } catch { lastError = error.localizedDescription }
    }
    func flush() async {
        guard !flushing, Reachability.shared.isOnline, !DebugEdge.on("offline"),
              let owner = await SupabaseClient.shared.currentUserId else { return }
        flushing = true
        defer { flushing = false; refreshStatus(owner: owner) }
        do {
            let store = try LocalDataStore.shared()
            var collectionPaused = !ConsentStore.shared.granted
            lastError = nil
            for queued in try store.operations(account: owner, kind: "meal") {
                guard SupabaseClient.currentUserIdSnapshot() == owner, !Task.isCancelled else { return }
                let rows = try store.operations(account: owner, kind: "meal")
                guard let operation = rows.first(where: { $0.id == queued.id }) else { continue }
                let fields = try MealOutboxPolicy.fields(operation)
                let probe = fields["rejection"] != nil && fields["kind"] as? String == "create"
                    && fields["canonical_probe_attempted"] as? Bool != true
                let runnable = try MealOutboxPolicy.runnable(rows)
                guard probe || runnable.contains(where: { $0.id == operation.id }) else { continue }
                if activeEstimates.contains(operation.id) { return }
                var current = operation
                do {
                    var envelope = try MealOutboxPolicy.fields(current)
                    let kind = envelope["kind"] as? String
                    // Withdrawal pauses collection, but an explicit deletion remains allowed.
                    guard kind == "delete" || (!collectionPaused && ConsentStore.shared.granted) else {
                        lastError = L("Data collection is paused. Pending meals stay on this device."); continue
                    }
                    if kind == "estimate", let body = envelope["body"] as? [String: Any],
                       let request = body["request"] as? [String: Any] {
                        let output = try await SupabaseClient.shared.callFunction("meal", payload: request, expectedOwner: owner)
                        guard SupabaseClient.currentUserIdSnapshot() == owner, ConsentStore.shared.granted, !Task.isCancelled else { return }
                        try promote(current, output: output)
                        guard let promoted = try store.operations(account: owner, kind: "meal").first(where: { $0.id == current.id }) else { return }
                        current = promoted; envelope = try MealOutboxPolicy.fields(current)
                    }
                    guard let body = envelope["body"] as? [String: Any], let kind = envelope["kind"] as? String else {
                        throw LocalDataStore.Failure.database("Invalid queued meal")
                    }
                    let request = probe ? body.merging(["reconcile_only": true]) { _, new in new } : body
                    let response = try await SupabaseClient.shared.callFunction(kind == "create" ? "meal-commit" : "meal-operation", payload: request, expectedOwner: owner)
                    guard SupabaseClient.currentUserIdSnapshot() == owner, !Task.isCancelled else { return }
                    let acknowledgement = response[kind == "create" ? "client_op_id" : "operation_id"] as? String
                    let acceptedID = (response["id"] as? String)?.lowercased()
                    let requestedID = (body["id"] as? String)?.lowercased()
                    let canonicalMatch = kind == "create" && acceptedID.flatMap(UUID.init(uuidString:)) != nil
                        && (response["requested_meal_id"] as? String)?.lowercased() == requestedID
                        && (response["meal_id"] as? String)?.lowercased() == acceptedID
                    guard acknowledgement?.lowercased() == (kind == "create" ? (body["draft_id"] as? String)?.lowercased() : operation.id.lowercased()),
                          kind != "create" || acceptedID == requestedID || canonicalMatch else {
                        throw LocalDataStore.Failure.database("Meal acknowledgment did not match the pending operation")
                    }
                    if kind == "create", let requestedID, let acceptedID, canonicalMatch || probe {
                        let changes = try store.operations(account: owner, kind: "meal").map { row in
                            let mapped = try MealOutboxPolicy.remappingMeal(row, from: requestedID, to: acceptedID)
                            let remapped = LocalOperation(id: row.id, account: row.account, kind: row.kind, payload: mapped)
                            let payload = row.id == current.id ? try MealOutboxPolicy.replacingRejection(remapped, message: nil) : mapped
                            let fields = try MealOutboxPolicy.fields(remapped)
                            return (expected: row, payload: payload, documentKey: "meal.\(fields["meal_id"] as? String ?? row.id)")
                        }
                        try store.replaceOperations(changes)
                        if requestedID != acceptedID, let old = UUID(uuidString: requestedID) {
                            DataStore.shared.overlayPendingMeals([], removedIDs: [old])
                        }
                    }
                    // Persist the visible accepted values before dropping their durable outbox.
                    // This also updates estimates recovered in the background after a restart.
                    overlayPending(into: DataStore.shared, ownerUserId: owner)
                    guard HomeSnapshot.save(from: DataStore.shared) else {
                        throw LocalDataStore.Failure.database("Could not save synchronized meals locally")
                    }
                    try store.acknowledge(account: owner, id: operation.id)
                } catch SupabaseClient.Failure.http(let code, _) where code == 403 {
                    collectionPaused = true
                    lastError = L("Data collection is paused. Pending meals stay on this device.")
                    continue
                } catch SupabaseClient.Failure.http(let code, let responseBody) where (400..<500).contains(code) && code != 401 && code != 403 && code != 408 && code != 429 {
                    let rejected = try MealOutboxPolicy.replacingRejection(current,
                        message: L("This change could not sync. Retry it or remove the pending change."))
                    let rejectedOperation = LocalOperation(id: current.id, account: current.account, kind: current.kind, payload: rejected)
                    let fields = try MealOutboxPolicy.fields(rejectedOperation)
                    // A transport/service failure never consumes the one canonical-match probe.
                    let errorData = responseBody.data(using: .utf8)
                    let serverError = errorData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["error"] as? String
                    let definitiveMismatch = code == 409 && ["NO_CANONICAL_MATCH", "OPERATION_CONFLICT"].contains(serverError ?? "")
                    let result = probe && definitiveMismatch ? fields.merging(["canonical_probe_attempted": true]) { _, new in new } : fields
                    let payload = try JSONSerialization.data(withJSONObject: result, options: .sortedKeys)
                    try store.replaceOperation(current, payload: payload, documentKey: "meal.\(current.id)")
                    // The next independent meal still gets its opportunity to synchronize.
                    continue
                }
            }
            retryDelay = 2
        } catch {
            lastError = error.localizedDescription
            if case SupabaseClient.Failure.http(let code, _) = error, code == 401 || code == 403 { return }
            let delay = retryDelay; retryDelay = min(60, retryDelay * 2)
            retry?.cancel()
            retry = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.flush()
            }
        }
    }
    func purge(ownerUserId: String) throws {
        retry?.cancel()
        try LocalDataStore.shared().purge(account: ownerUserId)
        pendingCount = 0; rejected = []
    }
}
