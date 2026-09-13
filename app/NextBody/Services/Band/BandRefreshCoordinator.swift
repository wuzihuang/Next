import Foundation

/// Requests describe different work, not the screen that happened to ask for it.
enum BandRefreshRequest: Equatable, Sendable {
    case automatic, foreground, resume, background, fullHistory, latest, phoneTool

    fileprivate func minimumInterval(cadence: TimeInterval) -> TimeInterval {
        switch self {
        case .automatic, .foreground: cadence
        // ADR 0026 · coming back to the app asks the wrist again whatever the cadence is set
        // to. The one-minute floor only folds an app switched away and straight back into
        // the pull that just ran; it never lets the device page's EVERY HOUR hold it.
        case .resume: min(60, cadence)
        // A background launch is already spaced by the system. The floor is the server's
        // own five-minute tick: a day settled inside it cannot come back different.
        case .background: min(300, cadence)
        case .fullHistory, .latest, .phoneTool: 0
        }
    }

    /// A live receipt seconds old is proof enough that the link is up for a pull the user
    /// did not press for; explicit pulls still walk readiness in full.
    var reusesRecentLiveReceipt: Bool { self == .foreground || self == .resume }
}

struct BandRefreshResult: Equatable, Sendable {
    enum Status: String, Sendable {
        case success, partial, failed, signedOut, consentRequired, unbound
        case busy, disconnected, throttled, cancelled
    }
    let status: Status
    var points: Int = 0
    var syncedAt: Date? = nil

    /// A day may fail after another day succeeded. Never let the last day hide that.
    static func combining(_ results: [Self], at date: Date) -> Self {
        let status: Status = results.allSatisfy { $0.status == .success } ? .success
            : results.contains { $0.status == .success || $0.status == .partial } ? .partial : .failed
        return Self(status: status, points: results.reduce(0) { $0 + $1.points },
                    syncedAt: status == .success ? date : nil)
    }
}

/// One process-owned refresh includes readiness, yesterday, today and any requested history.
/// Cancelling a view's waiter does not cancel work shared by another caller or durable replay.
@MainActor
final class BandRefreshCoordinator {
    struct Scope: Equatable, Hashable, Sendable {
        let account: String
        let binding: String
    }

    struct State {
        let account: String?
        let binding: String?
        let consent: Bool
        let exclusive: Bool
        let connected: Bool

        var scope: Scope? {
            guard let account, let binding else { return nil }
            return Scope(account: account, binding: binding)
        }
        func rejection(expected: Scope? = nil) -> BandRefreshResult.Status? {
            if let expected, scope != expected { return .cancelled }
            if account == nil { return .signedOut }
            if binding == nil { return .unbound }
            if !consent { return .consentRequired }
            if exclusive { return .busy }
            return nil
        }
    }

    struct HistoryResult {
        /// Nil means no historical work was needed; it is not an extra successful day.
        let result: BandRefreshResult?
        /// A retry repaired a recent day whose original result would otherwise remain partial.
        var recoveredDays: Set<Int> = []
    }

    /// Production uses the band and existing publication module; tests control their waits.
    struct Work {
        let prepare: @MainActor (_ reuseRecentLiveReceipt: Bool) async -> Bool
        let day: @MainActor (_ daysAgo: Int) async -> BandRefreshResult
        let history: @MainActor (_ recentDays: [Int: BandRefreshResult]) async -> HistoryResult
        var checkHistory: @MainActor () -> Bool = { false }
        var finish: @MainActor () async -> Void = {}
        var completed: @MainActor (BandRefreshResult) -> Void = { _ in }
    }

    private final class Flight {
        let scope: Scope
        var wantsHistory: Bool
        var task: Task<BandRefreshResult, Never>!
        init(scope: Scope, history: Bool) { self.scope = scope; wantsHistory = history }
    }

    private let state: @MainActor () -> State
    private let now: @MainActor () -> Date
    private var current: Flight?
    private var lastAttempt: (scope: Scope, at: Date)?
    private var consentRequest: (scope: Scope, request: BandRefreshRequest)?

    init(state: @escaping @MainActor () -> State, now: @escaping @MainActor () -> Date = { Date() }) {
        self.state = state
        self.now = now
    }

    /// Consuming also discards a declined or stale request. It cannot follow a new account.
    func refreshAfterConsent(cadence: TimeInterval, work: Work) async -> BandRefreshResult? {
        guard let pending = consentRequest else { return nil }
        consentRequest = nil
        if let rejected = state().rejection(expected: pending.scope) { return .init(status: rejected) }
        return await refresh(pending.request, cadence: cadence, work: work)
    }

    func refresh(_ request: BandRefreshRequest, cadence: TimeInterval, work: Work) async -> BandRefreshResult {
        guard !Task.isCancelled else { return .init(status: .cancelled) }
        let initial = state()
        if let rejected = initial.rejection() {
            if rejected == .consentRequired, request == .fullHistory, let scope = initial.scope {
                consentRequest = (scope, request)
            }
            return .init(status: rejected)
        }
        guard let scope = initial.scope else { return .init(status: .signedOut) }
        // ADR 0018: a phone tool cannot wait for a disconnected band to come back.
        if request == .phoneTool && !initial.connected { return .init(status: .disconnected) }

        while let flight = current {
            if flight.scope == scope {
                if request == .fullHistory { flight.wantsHistory = true }
                let result = await flight.task.value
                return resultForWaiter(result, scope: scope)
            }
            // A different account/binding never receives the old result or overlaps its work.
            _ = await flight.task.value
            if current === flight { current = nil }
            if let rejected = state().rejection(expected: scope) { return .init(status: rejected) }
            guard !Task.isCancelled else { return .init(status: .cancelled) }
        }
        if request == .phoneTool && !state().connected { return .init(status: .disconnected) }
        let interval = request.minimumInterval(cadence: cadence)
        if interval > 0, let lastAttempt, lastAttempt.scope == scope,
           now().timeIntervalSince(lastAttempt.at) < interval {
            return .init(status: .throttled)
        }

        let flight = Flight(scope: scope, history: request == .fullHistory)
        current = flight
        flight.task = Task { @MainActor in
            let result = await perform(flight, reuseReceipt: request.reusesRecentLiveReceipt, work: work)
            // Await the BLE-cache lifetime cleanup before releasing this shared flight.
            // A different account or new refresh cannot have its cache ended by old work.
            await work.finish()
            work.completed(resultForWaiter(result, scope: scope))
            // A failed connection is still an attempt. Automatic callers must not
            // restart preparation on every timer tick; explicit retries bypass cadence.
            if result.status == .success || result.status == .partial || result.status == .failed
                || result.status == .disconnected {
                lastAttempt = (scope, now())
            }
            if current === flight { current = nil }
            return result
        }
        let result = await flight.task.value
        return resultForWaiter(result, scope: scope)
    }

    func waitForCurrentPull() async { _ = await current?.task.value }
    var isIdle: Bool { current == nil }

    private func resultForWaiter(_ result: BandRefreshResult, scope: Scope) -> BandRefreshResult {
        if Task.isCancelled { return .init(status: .cancelled, points: result.points) }
        if let rejected = state().rejection(expected: scope) { return .init(status: rejected, points: result.points) }
        return result
    }

    private func perform(_ flight: Flight, reuseReceipt: Bool, work: Work) async -> BandRefreshResult {
        let scope = flight.scope
        if let rejected = state().rejection(expected: scope) { return .init(status: rejected) }
        let ready = await work.prepare(reuseReceipt)
        if let rejected = state().rejection(expected: scope) { return .init(status: rejected) }
        guard ready else { return .init(status: state().connected ? .failed : .disconnected) }
        var recentDays: [Int: BandRefreshResult] = [:]
        for offset in [1, 0] {
            if let rejected = state().rejection(expected: scope) {
                return .init(status: rejected, points: recentDays.values.reduce(0) { $0 + $1.points })
            }
            recentDays[offset] = await work.day(offset)
        }
        if let rejected = state().rejection(expected: scope) {
            return .init(status: rejected, points: recentDays.values.reduce(0) { $0 + $1.points })
        }
        var history: BandRefreshResult?
        if flight.wantsHistory || work.checkHistory() {
            let checked = await work.history(recentDays)
            history = checked.result
            for offset in checked.recoveredDays where recentDays[offset] != nil {
                recentDays[offset] = .init(status: .success, points: recentDays[offset]?.points ?? 0)
            }
        }
        let results = Array(recentDays.values) + (history.map { [$0] } ?? [])
        if let rejected = state().rejection(expected: scope) {
            return .init(status: rejected, points: results.reduce(0) { $0 + $1.points })
        }
        return .combining(results, at: now())
    }
}
