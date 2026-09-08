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
    private var flushRequested = false
    private var reachability: AnyCancellable?
    private var retry: Task<Void, Never>?
    private var retryDelay: UInt64 = 2
    private init() {
        reachability = Reachability.shared.$isOnline.removeDuplicates().sink { [weak self] online in
            if online { Task { await self?.flush() } }
        }
    }
    private func publication(owner: String) throws -> MealPublication {
        let session = SupabaseClient.currentRequestSessionSnapshot()
        return MealPublication(account: owner, local: try LocalDataStore.shared(), isCurrent: {
            session.owner == owner && SupabaseClient.currentRequestSessionSnapshot() == session
        }, consent: { ConsentStore.shared.granted }, send: { endpoint, body, owner in
            do { return try await SupabaseClient.shared.callFunction(endpoint, payload: body, expectedOwner: owner) }
            catch SupabaseClient.Failure.http(let status, let body) { throw MealPublication.Failure.http(status, body) }
        }, persistProjection: {
            try self.applyPending(into: DataStore.shared, ownerUserId: owner)
            guard HomeSnapshot.save(from: DataStore.shared) else {
                throw LocalDataStore.Failure.database(L("Could not save synchronized meals locally"))
            }
        })
    }

    func createManual(text: String, kcal: Double, day: UserDay, into data: DataStore) throws {
        guard kcal.isFinite, kcal >= 1, kcal <= 100000,
              let owner = SupabaseClient.currentUserIdSnapshot() else { throw MealPublication.Failure.invalidMeal }
        try ensureCanAdd(day: day, into: data)
        let at = day.pinningClock(Date())
        _ = try publication(owner: owner).createManual(day: day.key,
            slot: MealEntry.Slot.guess(at: at, day: day).rawValue, name: text, kcal: Int(kcal), at: at)
        try didSubmit(owner: owner, into: data)
    }

    func confirmDraft(_ output: [String: Any], mealID: UUID, day: UserDay,
                      slot: MealEntry.Slot, owner: String, into data: DataStore) throws -> MealPublication.Submitted {
        try ensureCanAdd(day: day, into: data)
        let result = try publication(owner: owner).confirmDraft(id: mealID, day: day.key,
            slot: slot.rawValue, output: output, at: day.pinningClock(Date()))
        try didSubmit(owner: owner, into: data)
        return result
    }

    private func ensureCanAdd(day: UserDay, into data: DataStore) throws {
        guard ConsentStore.shared.granted else { throw MealPublication.Failure.collectionPaused }
        if day == data.today.day, case .fasted = data.today.fuelState {
            throw LocalDataStore.Failure.database(L("This day is marked as fasted."))
        }
    }

    private func didSubmit(owner: String, into data: DataStore) throws {
        try applyPending(into: data, ownerUserId: owner)
        refreshStatus(owner: owner)
        NotificationReach.evaluate(store: data)
        Task { await flush() }
    }

    func enqueueDelete(mealID: UUID, ownerUserId: String) throws {
        try publication(owner: ownerUserId).delete(id: mealID)
        try didSubmit(owner: ownerUserId, into: DataStore.shared)
    }

    func enqueueAmend(mealID: UUID, replacement: [String: Any], source: MealEntry.Source, revisions: Int, ownerUserId: String) throws {
        _ = try publication(owner: ownerUserId).amend(id: mealID, replacement: replacement, source: source.rawValue, revisions: revisions)
        try didSubmit(owner: ownerUserId, into: DataStore.shared)
    }
    func overlayPending(into data: DataStore, ownerUserId: String) {
        do { try applyPending(into: data, ownerUserId: ownerUserId) }
        catch { lastError = error.localizedDescription }
    }

    private func applyPending(into data: DataStore, ownerUserId: String) throws {
        guard SupabaseClient.currentUserIdSnapshot() == ownerUserId else { throw CancellationError() }
        refreshStatus(owner: ownerUserId)
        let projection = try publication(owner: ownerUserId).projection()
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let entries = projection.meals.compactMap { row -> MealEntry? in
            guard let date = formatter.date(from: row.day),
                  let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date),
                  let slot = MealEntry.Slot(rawValue: row.slot) else { return nil }
            let previous = data.meals.first { $0.id == row.id } ?? data.recentMeals.first { $0.id == row.id }
            return MealEntry(id: row.id, day: UserDay.containing(noon), at: row.at,
                slot: slot, status: row.confirmed ? .confirmed : .open, text: row.name,
                kcal: row.kcal, protein: row.protein, carb: row.carb, fat: row.fat,
                revisions: row.revisions ?? previous?.revisions ?? 0,
                source: row.source.flatMap { MealEntry.Source(rawValue: $0.uppercased()) } ?? previous?.source ?? .voice)
        }
        guard !entries.isEmpty || !projection.removedIDs.isEmpty else { return }
        data.overlayPendingMeals(entries, removedIDs: projection.removedIDs)
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
        if flushing { flushRequested = true; return }
        guard Reachability.shared.isOnline, !DebugEdge.on("offline"),
              let owner = await SupabaseClient.shared.currentUserId else { return }
        flushing = true
        defer {
            flushing = false; refreshStatus(owner: owner)
            if flushRequested {
                flushRequested = false
                Task { await flush() }
            }
        }
        do {
            lastError = nil
            let result = try await publication(owner: owner).replay()
            lastError = result.message.map { L($0) }
            retryDelay = 2
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
            if case MealPublication.Failure.collectionPaused = error { return }
            if case MealPublication.Failure.http(let code, _) = error, code == 401 || code == 403 { return }
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
