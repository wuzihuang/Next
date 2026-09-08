import Foundation

/// Requests describe different work, not the screen that happened to ask for it.
enum BandRefreshRequest: Sendable {
    case automatic, foreground, fullHistory, latest, phoneTool

    fileprivate func minimumInterval(cadence: TimeInterval) -> TimeInterval {
        switch self {
        case .automatic: min(120, cadence / 2)
        case .foreground: cadence
        case .fullHistory, .latest, .phoneTool: 0
        }
    }
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

    /// Production uses the band and existing publication module; tests control their waits.
    struct Work {
        let prepare: @MainActor (_ reuseRecentLiveReceipt: Bool) async -> Bool
        let day: @MainActor (_ daysAgo: Int) async -> BandRefreshResult
        let history: @MainActor () async -> BandRefreshResult
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

    init(state: @escaping @MainActor () -> State, now: @escaping @MainActor () -> Date = { Date() }) {
        self.state = state
        self.now = now
    }

    func isDue(cadence: TimeInterval) -> Bool {
        guard let lastAttempt, lastAttempt.scope == state().scope else { return true }
        return now().timeIntervalSince(lastAttempt.at) >= cadence
    }

    func refresh(_ request: BandRefreshRequest, cadence: TimeInterval, work: Work) async -> BandRefreshResult {
        guard !Task.isCancelled else { return .init(status: .cancelled) }
        let initial = state()
        if let rejected = initial.rejection() { return .init(status: rejected) }
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
        let interval = request.minimumInterval(cadence: cadence)
        if interval > 0, let lastAttempt, lastAttempt.scope == scope,
           now().timeIntervalSince(lastAttempt.at) < interval {
            return .init(status: .throttled)
        }

        let flight = Flight(scope: scope, history: request == .fullHistory)
        current = flight
        flight.task = Task { @MainActor in
            let result = await perform(flight, reuseReceipt: request == .foreground, work: work)
            if result.status == .success || result.status == .partial || result.status == .failed {
                lastAttempt = (scope, now())
            }
            if current === flight { current = nil }
            return result
        }
        let result = await flight.task.value
        return resultForWaiter(result, scope: scope)
    }

    func waitForCurrentPull() async { _ = await current?.task.value }

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
        var results: [BandRefreshResult] = []
        for offset in [1, 0] {
            if let rejected = state().rejection(expected: scope) {
                return .init(status: rejected, points: results.reduce(0) { $0 + $1.points })
            }
            results.append(await work.day(offset))
        }
        if let rejected = state().rejection(expected: scope) {
            return .init(status: rejected, points: results.reduce(0) { $0 + $1.points })
        }
        if flight.wantsHistory { results.append(await work.history()) }
        if let rejected = state().rejection(expected: scope) {
            return .init(status: rejected, points: results.reduce(0) { $0 + $1.points })
        }
        return .combining(results, at: now())
    }
}
