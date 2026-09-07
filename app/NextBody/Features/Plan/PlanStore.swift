import Combine
import Foundation
import os

/// ADR 0018 · the plan the server wrote for a user day: a title, a summary, three to five
/// tasks the model chose. The phone renders it and records ticks; it never assembles one.
struct DailyPlan: Equatable {
    struct Task: Equatable, Identifiable {
        let id: String
        let title: String
        let sub: String
        let basis: String?
    }
    let dayKey: String
    let title: String
    let summary: String
    let tasks: [Task]
    let readFrom: String
    let readTo: String

    /// From a `daily_plans` row or a `plan` envelope's `data`.
    init?(row: [String: Any], dayKey: String? = nil) {
        guard let title = row["title"] as? String, let summary = row["summary"] as? String,
              let rawTasks = row["tasks"] as? [[String: Any]] else { return nil }
        let tasks = rawTasks.compactMap { t -> Task? in
            guard let id = t["id"] as? String, let title = t["title"] as? String, let sub = t["sub"] as? String else { return nil }
            return Task(id: id, title: title, sub: sub, basis: (t["basis"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }
        guard !tasks.isEmpty else { return nil }
        self.dayKey = dayKey ?? (row["user_day"] as? String) ?? ""
        self.title = title
        self.summary = summary
        self.tasks = tasks
        self.readFrom = (row["read_from"] as? String) ?? ""
        self.readTo = (row["read_to"] as? String) ?? ""
    }
}

/// Today's plan and its ticks. Loading reads the row; generating is one `surface=plan`
/// turn; a tick is a local mark that the outbox carries to `plan_task_checks`.
@MainActor
final class PlanStore: ObservableObject {
    static let shared = PlanStore()

    @Published private(set) var plan: DailyPlan?
    @Published private(set) var checked: Set<String> = []
    @Published private(set) var loading = false
    @Published private(set) var generating = false
    @Published private(set) var generatedAt: Date?
    @Published var errorLine: String?

    private var loadedDay: String?
    private var loadedOwner: String?

    /// Read today's row, if the day changed or nothing is loaded yet. Cheap on repeat.
    func load(dayKey: String, force: Bool = false) async {
        let owner = SupabaseClient.currentUserIdSnapshot()
        if !force, loadedDay == dayKey, loadedOwner == owner, plan != nil { return }
        if loadedDay != dayKey || loadedOwner != owner { plan = nil; checked = [] }
        loadedDay = dayKey
        loadedOwner = owner
        checked = PlanChecks.load(dayKey: dayKey)
        guard owner != nil, Reachability.shared.isOnline, !DebugEdge.on("offline") else { return }
        loading = true
        defer { loading = false }
        do {
            let rows = try await SupabaseClient.shared.select("daily_plans", query: [
                URLQueryItem(name: "select", value: "user_day,title,summary,tasks,read_from,read_to"),
                URLQueryItem(name: "user_day", value: "eq.\(dayKey)"),
                URLQueryItem(name: "limit", value: "1"),
            ])
            guard loadedDay == dayKey else { return }
            if let row = rows.first, let loaded = DailyPlan(row: row) { plan = loaded }
            let ticks = try await SupabaseClient.shared.select("plan_task_checks", query: [
                URLQueryItem(name: "select", value: "task_id"),
                URLQueryItem(name: "user_day", value: "eq.\(dayKey)"),
            ])
            guard loadedDay == dayKey else { return }
            let remote = Set(ticks.compactMap { $0["task_id"] as? String })
            checked = checked.union(remote)
            PlanChecks.save(dayKey: dayKey, done: checked)
        } catch {
            Logger(subsystem: "com.nextbody.hoop", category: "plan").error("plan load failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// One turn on the plan surface. The thinking stream shows while it runs; the row lands
    /// in `daily_plans` on the server and the frame carries the same content back.
    func generate(day: UserDay, store: DataStore, ai: AIService) async {
        guard !generating else { return }
        generating = true
        errorLine = nil
        defer { generating = false }
        let dayKey = AIService.dayFormatter.string(from: day.start)
        let frame = await ai.turn("", day: day, store: store, surface: "plan")
        guard loadedDay == nil || loadedDay == dayKey else { return }
        loadedDay = dayKey
        if let frame, frame.type == .plan, let data = frame.envelopeData,
           let env = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let payload = env["data"] as? [String: Any], let generated = DailyPlan(row: payload, dayKey: dayKey) {
            plan = generated
            generatedAt = Date()
            // A regenerated plan may rename tasks; ticks that no longer match stay harmless.
            checked = PlanChecks.load(dayKey: dayKey)
        } else {
            errorLine = ai.lastError ?? L("Today's plan could not be generated. Try again.")
        }
    }

    /// A tick is the user's own claim. Local at once, then the outbox carries it up.
    func tick(_ taskID: String, dayKey: String) {
        guard !checked.contains(taskID) else { return }
        checked.insert(taskID)
        PlanChecks.save(dayKey: dayKey, done: checked)
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        do { try PlanCheckQueue.shared.enqueue(dayKey: dayKey, taskID: taskID, ownerUserId: owner) }
        catch { Logger(subsystem: "com.nextbody.hoop", category: "plan").error("tick enqueue failed: \(String(describing: error), privacy: .public)") }
    }

    func reset() {
        plan = nil
        checked = []
        loadedDay = nil
        loadedOwner = nil
        generatedAt = nil
        errorLine = nil
    }
}

/// The outbox for ticks: one row per (day, task), duplicates are fine, order is kept.
@MainActor
final class PlanCheckQueue {
    static let shared = PlanCheckQueue()

    struct Pending: Codable, Identifiable {
        let id: String
        let ownerUserId: String
        let dayKey: String
        let taskID: String
        let checkedAt: Date
    }

    private(set) var pending: [Pending] = []
    private var flushing = false
    private var reachability: AnyCancellable?

    private func durable() throws -> DurableQueue<Pending> {
        DurableQueue(kind: "plan-check", store: try LocalDataStore.shared())
    }

    private init() {
        pending = (try? durable().items()) ?? []
        reachability = Reachability.shared.$isOnline.removeDuplicates().sink { [weak self] online in
            if online { Task { await self?.flush() } }
        }
    }

    func enqueue(dayKey: String, taskID: String, ownerUserId: String) throws {
        let item = Pending(id: "\(dayKey).\(taskID)", ownerUserId: ownerUserId, dayKey: dayKey, taskID: taskID, checkedAt: Date())
        try durable().save(item, id: item.id, account: ownerUserId)
        pending = try durable().items()
        Task { await flush() }
    }

    func flush() async {
        guard !flushing, Reachability.shared.isOnline, !DebugEdge.on("offline"),
              let currentUser = await SupabaseClient.shared.currentUserId else { return }
        flushing = true
        defer { flushing = false }
        let iso = ISO8601DateFormatter()
        for item in pending where item.ownerUserId == currentUser {
            let row: [String: Any] = ["user_id": currentUser, "user_day": item.dayKey, "task_id": item.taskID,
                                      "checked_at": iso.string(from: item.checkedAt)]
            do {
                _ = try await SupabaseClient.shared.insert("plan_task_checks", rows: [row], ignoringDuplicatesOn: "user_id,user_day,task_id", expectedOwner: currentUser)
                guard SupabaseClient.currentUserIdSnapshot() == currentUser, !Task.isCancelled else { return }
                try durable().acknowledge(id: item.id, account: currentUser)
                pending.removeAll { $0.id == item.id }
            } catch SupabaseClient.Failure.http(let code, _) where code == 409 {
                try? durable().acknowledge(id: item.id, account: currentUser)
                pending.removeAll { $0.id == item.id }
            } catch {
                // Stop, keep order: one failure must not let a later tick overtake it.
                break
            }
        }
    }

    func purge() {
        for item in pending { try? durable().acknowledge(id: item.id, account: item.ownerUserId) }
        pending = []
    }
}
