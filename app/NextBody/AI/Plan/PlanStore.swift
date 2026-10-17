import Combine
import Foundation
import os

/// ADR 0022 · the day's set. Generated once per user day in the background, by whichever
/// phone opens the day first; the face reads it and never regenerates on its own. The wire
/// surface remains `plan` for compatibility, and `daily_plans` holds the day's latest set.
///
/// A run that this device started keeps going on the server after the app leaves; coming
/// back replays the same Idempotency-Key until the server answers with the result.
@MainActor
final class PlanStore: ObservableObject {
    static let shared = PlanStore()

    @Published private(set) var plan: DailyPlan?
    @Published private(set) var generating = false
    @Published private(set) var generatedAt: Date?
    @Published private(set) var errorLine: String?
    /// Every automatic attempt for today failed; only REFRESH remains.
    @Published private(set) var exhausted = false
    /// When the run being waited on started, for the thinking stage's clock.
    @Published private(set) var startedAt = Date()

    private var lifetime = AdviceRequestLifetime()
    private var scopeOwner: String?
    private var scopeDayKey: String?
    private var runs: [AdviceDayRun] = []
    private var foregroundAt: Date?
    private var driver: Task<Void, Never>?
    #if DEBUG && targetEnvironment(simulator)
    private var fixtureSequence = 0
    private var fixtureCleared = false
    #endif
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "advice")

    /// The health account this device is acting for. The simulator fixtures answer without
    /// a session, so they act for a stand-in owner.
    private static func owner() -> String? {
        if let owner = SupabaseClient.currentUserIdSnapshot() { return owner }
        #if DEBUG && targetEnvironment(simulator)
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_ADVICE_FIXTURE"] != nil { return "fixture" }
        #endif
        return nil
    }

    /// The set on screen belongs to an earlier user day: today's has not arrived yet.
    var planIsStale: Bool {
        guard let plan, let scopeDayKey else { return false }
        return plan.dayKey != scopeDayKey
    }

    // MARK: scope

    /// Another account drops everything. A new day keeps the previous set on screen as the
    /// stale one and forgets the old day's runs and failures.
    func prepare(dayKey: String) {
        let owner = Self.owner()
        let ownerChanged = scopeOwner != owner
        let previousDay = scopeDayKey
        guard lifetime.prepare(owner: owner, dayKey: dayKey) else { return }
        driver?.cancel()
        driver = nil
        generating = false
        errorLine = nil
        exhausted = false
        scopeOwner = owner
        scopeDayKey = dayKey
        if ownerChanged {
            plan = nil
            generatedAt = nil
        }
        if previousDay != dayKey { foregroundAt = nil }
        #if DEBUG && targetEnvironment(simulator)
        // `NB_DEBUG_ADVICE_FRESH=1` forgets the fixture owner's runs once per process, so a
        // UI test starts its scenario clean; a relaunch without it keeps the runs.
        if Band.allowsSeed, !fixtureCleared, ProcessInfo.processInfo.environment["NB_DEBUG_ADVICE_FRESH"] == "1" {
            fixtureCleared = true
            Self.purge(owner: "fixture")
        }
        #endif
        runs = owner.map { Self.loadRuns(owner: $0, dayKey: dayKey) } ?? []
    }

    /// The app came to the foreground: the band gets its moment, then today's set is made.
    func noteForeground() {
        if foregroundAt == nil { foregroundAt = Date() }
    }

    // MARK: the day's set

    /// Called on foreground, on opening the face and on the day rolling over. It reads the
    /// stored set first; only the first phone of the day actually starts a generation.
    func ensureToday(day: UserDay, store: DataStore, ai: AIService, reload: Bool = false) {
        let dayKey = day.key
        guard dayKey == store.today.day.key else { return }
        prepare(dayKey: dayKey)
        noteForeground()
        guard driver == nil else { return }
        guard ConsentStore.shared.granted, let owner = Self.owner() else { return }
        if !Reachability.shared.isOnline || DebugEdge.on("offline") {
            showOffline(dayKey: dayKey)
            return
        }
        driver = Task { [weak self] in
            guard let self else { return }
            await self.drive(day: day, owner: owner, store: store, ai: ai, reload: reload)
            self.driver = nil
        }
    }

    /// REFRESH: the only way to regenerate within a day. Its result replaces today's set.
    func refresh(day: UserDay, store: DataStore, ai: AIService) {
        let dayKey = day.key
        guard dayKey == store.today.day.key else { return }
        prepare(dayKey: dayKey)
        guard driver == nil, ConsentStore.shared.granted, let owner = Self.owner() else { return }
        if !Reachability.shared.isOnline || DebugEdge.on("offline") {
            showOffline(dayKey: dayKey)
            return
        }
        let run = AdviceDayRun(ownerUserId: owner, dayKey: dayKey, kind: .refresh, attempt: 1,
                               turnID: UUID(), startedAt: Date(), outcome: nil)
        remember(run)
        driver = Task { [weak self] in
            guard let self else { return }
            await self.perform(run, day: day, owner: owner, store: store, ai: ai, prepareFreshness: true)
            self.driver = nil
        }
    }

    func showOffline(dayKey: String) {
        prepare(dayKey: dayKey)
        guard !generating else { return }
        errorLine = plan == nil
            ? L("Connect to get suggestions from your latest data.")
            : L("Offline. These are earlier suggestions; they could not be refreshed.")
    }

    func reset() {
        driver?.cancel()
        driver = nil
        lifetime.reset()
        scopeOwner = nil
        scopeDayKey = nil
        runs = []
        foregroundAt = nil
        plan = nil
        generating = false
        generatedAt = nil
        errorLine = nil
        exhausted = false
    }

    /// Account purge: this device forgets which runs it started for that owner.
    static func purge(owner: String?) {
        guard let owner else { return }
        UserDefaults.standard.removeObject(forKey: runsKey(owner))
    }

    // MARK: driving

    private func drive(day: UserDay, owner: String, store: DataStore, ai: AIService, reload: Bool) async {
        let dayKey = day.key
        if reload || plan?.dayKey != dayKey { await loadStored(owner: owner, day: day) }
        guard !Task.isCancelled, accepts(owner: owner, dayKey: dayKey, store: store) else { return }
        while !Task.isCancelled {
            let situation = AdviceDayPolicy.Situation(
                dayKey: dayKey, storedDayKey: plan?.dayKey, runs: runs,
                bandSynced: store.lastSync.map { UserDay.containing($0).key == dayKey } ?? false,
                foregroundElapsed: foregroundAt.map { Date().timeIntervalSince($0) } ?? AdviceDayPolicy.bandWait,
                now: Date())
            switch AdviceDayPolicy.next(situation) {
            case .showToday:
                generating = false
                return
            case .exhausted:
                generating = false
                exhausted = true
                errorLine = L("Today's suggestions could not be generated. Refresh to try again.")
                return
            case .waitForBand:
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, accepts(owner: owner, dayKey: dayKey, store: store) else { return }
                continue
            case .attach(let run):
                await perform(run, day: day, owner: owner, store: store, ai: ai, prepareFreshness: false)
                return
            case .start(let attempt):
                let run = AdviceDayRun(ownerUserId: owner, dayKey: dayKey, kind: .automatic, attempt: attempt,
                                       turnID: AdviceDayPolicy.automaticTurnID(owner: owner, dayKey: dayKey, attempt: attempt),
                                       startedAt: Date(), outcome: nil)
                remember(run)
                await perform(run, day: day, owner: owner, store: store, ai: ai, prepareFreshness: true)
                return
            }
        }
    }

    private enum Answer { case delivered(DailyPlan), inProgress(Int?), failed(String?), interrupted(String?) }

    /// One run, followed to its end: the live stream when the phone is present, otherwise
    /// replays of the same key until the server hands back the stored result.
    private func perform(_ run: AdviceDayRun, day: UserDay, owner: String, store: DataStore, ai: AIService,
                         prepareFreshness: Bool) async {
        guard let request = lifetime.begin() else { return }
        generating = true
        errorLine = nil
        startedAt = run.startedAt
        defer {
            if lifetime.finish(request) { generating = false }
        }
        var prepare = prepareFreshness
        let probeDeadline = run.startedAt.addingTimeInterval(AdviceDayPolicy.unknownRunLifetime)
        while !Task.isCancelled {
            let answer = await ask(run, day: day, store: store, ai: ai, prepareFreshness: prepare)
            prepare = false
            guard lifetime.accepts(request, owner: Self.owner(), dayKey: store.today.day.key),
                  !Task.isCancelled else { return }
            switch answer {
            case .delivered(let set):
                plan = set
                generatedAt = Date()
                errorLine = nil
                exhausted = false
                record(run, outcome: .delivered)
                await Analytics.shared.track("PLAN_GENERATE", ["HAS_PLAN": true, "KIND": run.kind.rawValue, "ATTEMPT": run.attempt])
                return
            case .inProgress(let retryAfter):
                guard Date() < probeDeadline else {
                    record(run, outcome: .failed)
                    errorLine = failureLine(run)
                    return
                }
                try? await Task.sleep(for: .seconds(AdviceDayPolicy.probeDelay(retryAfter: retryAfter)))
            case .failed(let reason):
                record(run, outcome: .failed)
                errorLine = run.kind == .refresh ? (reason ?? failureLine(run)) : failureLine(run)
                await Analytics.shared.track("PLAN_GENERATE", ["HAS_PLAN": false, "KIND": run.kind.rawValue, "ATTEMPT": run.attempt])
                return
            case .interrupted(let reason):
                // Nothing definitive was heard: the run keeps its unknown outcome and the next
                // foreground or opening attaches to it again.
                errorLine = reason ?? failureLine(run)
                return
            }
        }
    }

    private func ask(_ run: AdviceDayRun, day: UserDay, store: DataStore, ai: AIService, prepareFreshness: Bool) async -> Answer {
        #if DEBUG && targetEnvironment(simulator)
        if let fixture = fixtureAnswer(run, dayKey: day.key) { return fixture }
        #endif
        let frame = await ai.turn("", day: day, store: store, surface: "plan", turnID: run.turnID,
                                  prepareData: prepareFreshness)
        if let frame, frame.type == .plan, let data = frame.envelopeData,
           let env = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let payload = env["data"] as? [String: Any], let generated = DailyPlan(row: payload, dayKey: day.key) {
            return .delivered(generated)
        }
        if let frame {
            // The server answered with a frame that is not a set: the stored failure of this
            // run (its fallback frame replays too), in its own words.
            return .failed(frame.sentence.isEmpty ? nil : frame.sentence)
        }
        switch ai.lastErrorCode {
        case "TURN_IN_PROGRESS": return .inProgress(ai.lastRetryAfter)
        case nil: return .interrupted(nil)
        default: return .interrupted(ai.lastError)
        }
    }

    private func failureLine(_ run: AdviceDayRun) -> String {
        if run.kind == .refresh { return L("Could not refresh. These are earlier suggestions.") }
        return plan == nil
            ? L("Today's suggestions could not be generated yet. They will be tried again.")
            : L("Today's suggestions could not be generated yet. These are yesterday's.")
    }

    // MARK: the stored set

    /// The day's latest set, or the previous day's to show as stale while today's is made.
    private func loadStored(owner: String, day: UserDay) async {
        let yesterday = day.adding(days: -1).key
        #if DEBUG && targetEnvironment(simulator)
        // `NB_DEBUG_ADVICE_YESTERDAY=1` stands in for a stored set from the previous day.
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_ADVICE_YESTERDAY"] == "1", plan == nil {
            plan = Self.fixtureSet(dayKey: yesterday, sequence: 0, empty: false)
            generatedAt = day.start.addingTimeInterval(-3 * 3600)
            return
        }
        #endif
        let rows = try? await SupabaseClient.shared.select("daily_plans", query: [
            .init(name: "select", value: "user_day,title,summary,tasks,read_from,read_to,created_at"),
            .init(name: "user_day", value: "gte.\(yesterday)"),
            .init(name: "user_day", value: "lte.\(day.key)"),
            .init(name: "order", value: "user_day.desc,created_at.desc"),
            .init(name: "limit", value: "1"),
        ])
        guard Self.owner() == owner, !Task.isCancelled,
              let row = rows?.first, let stored = DailyPlan(row: row) else { return }
        if let current = plan, current.dayKey > stored.dayKey { return }
        plan = stored
        generatedAt = (row["created_at"] as? String).flatMap(Self.timestamp)
    }

    private static func timestamp(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private func accepts(owner: String, dayKey: String, store: DataStore) -> Bool {
        Self.owner() == owner && store.today.day.key == dayKey && scopeDayKey == dayKey
    }

    // MARK: runs this device knows about

    private func remember(_ run: AdviceDayRun) {
        runs.removeAll { $0.turnID == run.turnID }
        runs.append(run)
        saveRuns()
    }

    private func record(_ run: AdviceDayRun, outcome: AdviceDayRun.Outcome) {
        guard let index = runs.firstIndex(where: { $0.turnID == run.turnID }) else { return }
        runs[index].outcome = outcome
        saveRuns()
    }

    private func saveRuns() {
        guard let owner = runs.first?.ownerUserId, let data = try? JSONEncoder().encode(runs) else { return }
        UserDefaults.standard.set(data, forKey: Self.runsKey(owner))
    }

    private static func loadRuns(owner: String, dayKey: String) -> [AdviceDayRun] {
        guard let data = UserDefaults.standard.data(forKey: runsKey(owner)),
              let stored = try? JSONDecoder().decode([AdviceDayRun].self, from: data) else { return [] }
        return AdviceDayPolicy.settled(stored, now: Date(), keepDays: [dayKey])
    }

    private static func runsKey(_ owner: String) -> String { "nb.advice.runs.v1.\(owner)" }

    // MARK: simulator fixtures

    #if DEBUG && targetEnvironment(simulator)
    /// `NB_DEBUG_ADVICE_FIXTURE=numbered|empty|failure|slow` answers without a server.
    private func fixtureAnswer(_ run: AdviceDayRun, dayKey: String) -> Answer? {
        guard Band.allowsSeed, let fixture = ProcessInfo.processInfo.environment["NB_DEBUG_ADVICE_FIXTURE"],
              ["numbered", "empty", "failure", "slow"].contains(fixture) else { return nil }
        // A probe that finds the run still going is not an answer: the sequence counts answers.
        if fixture == "slow", Date().timeIntervalSince(run.startedAt) < 12 { return .inProgress(3) }
        fixtureSequence += 1
        let sequence = fixtureSequence
        if fixture == "failure", sequence > 1 { return .failed(L("Could not refresh. These are earlier suggestions.")) }
        return Self.fixtureSet(dayKey: dayKey, sequence: sequence, empty: fixture == "empty").map { .delivered($0) } ?? .failed(nil)
    }

    private static func fixtureSet(dayKey: String, sequence: Int, empty: Bool) -> DailyPlan? {
        let tasks: [[String: Any]] = empty ? [] : (1...5).map { number in
            ["id": "suggestion-\(number)",
             "title": "A specific recovery suggestion for your day \(number)",
             "sub": "This suggestion explains how the latest reading differs from your usual pattern. It offers one practical adjustment and explains when that adjustment is relevant, so the complete advice stays readable even across several lines.",
             "basis": "Based on the recent recorded pattern and its personal baseline; gaps remain uncertain.",
             "sources": [["title": "NIH Office of Dietary Supplements", "url": "https://ods.od.nih.gov/"]]]
        }
        return DailyPlan(row: ["title": "Suggestions \(sequence)",
                               "summary": empty
                                ? "There is not enough recent evidence to offer a useful suggestion."
                                : "Generated from the latest available readings.",
                               "tasks": tasks], dayKey: dayKey)
    }
    #endif
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
