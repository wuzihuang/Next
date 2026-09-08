import Foundation

/// One phone call owns its confirmation, eligibility and completion. Both the app and
/// controlled adapters execute through this interface; every suspended step rechecks the
/// same account/session, turn and band before it can issue a subsequent action.
@MainActor
final class PhoneToolExecution {
    struct Scope: Equatable {
        let session: RequestSession
        let turnID: UUID
        let binding: String?
    }

    struct Environment {
        let scope: Scope
        let consent: Bool
        let foreground: Bool
    }

    struct Prompt: Identifiable {
        let id: UUID
        let title: String
        let detail: String
    }

    enum Failure: String, Error {
        case cancelled = "CANCELLED"
        case background = "APP_BACKGROUND"
        case consentRequired = "CONSENT_REQUIRED"
        case sessionChanged = "SESSION_CHANGED"
        case bindingChanged = "BAND_DISCONNECTED"
    }

    @MainActor
    final class Execution {
        let id = UUID()
        let scope: Scope
        let callID: String
        fileprivate var failure: Failure?
        fileprivate var finished = false
        private let current: () -> Environment

        fileprivate init(scope: Scope, callID: String, current: @escaping () -> Environment) {
            self.scope = scope
            self.callID = callID
            self.current = current
        }

        /// Check immediately before each side effect. A read followed by a write must use
        /// separate steps so the read's suspension cannot carry old authority to the write.
        func check() throws {
            if let failure { throw failure }
            let now = current()
            let reason: Failure?
            if Task.isCancelled || finished { reason = .cancelled }
            else if !now.foreground { reason = .background }
            else if !now.consent { reason = .consentRequired }
            else if scope.session.owner == nil || now.scope.session != scope.session { reason = .sessionChanged }
            else if now.scope.turnID != scope.turnID { reason = .cancelled }
            else if now.scope.binding != scope.binding { reason = .bindingChanged }
            else { reason = nil }
            if let reason { failure = reason; throw reason }
        }

        var isAuthorized: Bool { (try? check()) != nil }

        func perform<Value>(_ action: @MainActor () async throws -> Value) async throws -> Value {
            try check()
            let result = try await action()
            try check()
            return result
        }
    }

    private struct Pending {
        let execution: Execution
        let continuation: CheckedContinuation<Bool, Never>
        let timer: Task<Void, Never>
    }

    private let current: () -> Environment
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private let changed: @MainActor (Prompt?, String?) -> Void
    private var executions: [UUID: Execution] = [:]
    private var pending: Pending?
    private var prompt: Prompt?
    private var displayed: (id: UUID, name: String)?

    init(current: @escaping () -> Environment,
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void = {
             try await Task.sleep(for: .seconds($0))
         },
         changed: @escaping @MainActor (Prompt?, String?) -> Void) {
        self.current = current
        self.sleep = sleep
        self.changed = changed
    }

    func run<Value>(scope: Scope, callID: String, name: String,
                    confirmation: (title: String, detail: String)?,
                    action: @MainActor (Execution) async throws -> Value) async throws -> Value {
        let execution = Execution(scope: scope, callID: callID, current: current)
        // A new call replaces the visible confirmation; the displaced waiter is completed
        // before installing its successor, and its timer can only resolve its own UUID.
        if let old = pending { invalidate(old.execution, reason: .cancelled) }
        executions[execution.id] = execution
        displayed = (execution.id, name)
        emit()
        defer {
            execution.finished = true
            executions.removeValue(forKey: execution.id)
            if displayed?.id == execution.id { displayed = nil }
            emit()
        }
        return try await withTaskCancellationHandler {
            try execution.check()
            if let confirmation {
                let approved = await waitForConfirmation(execution, title: confirmation.title, detail: confirmation.detail)
                try execution.check()
                guard approved else { throw Failure.cancelled }
            }
            return try await execution.perform { try await action(execution) }
        } onCancel: {
            Task { @MainActor in self.invalidate(execution, reason: .cancelled) }
        }
    }

    func resolve(id: UUID, approved: Bool) {
        guard let waiting = pending, waiting.execution.id == id else { return }
        pending = nil
        prompt = nil
        waiting.timer.cancel()
        let eligible = (try? waiting.execution.check()) != nil
        waiting.continuation.resume(returning: approved && eligible)
        emit()
    }

    /// Host events wake confirmation immediately; checks at every action remain the
    /// authority even if a notification has not yet reached the main actor.
    func refreshEligibility() {
        for execution in Array(executions.values) {
            if let reason = Result { try execution.check() }.failure as? Failure {
                invalidate(execution, reason: reason)
            }
        }
    }

    func invalidateAll(_ reason: Failure) {
        for execution in Array(executions.values) { invalidate(execution, reason: reason) }
    }

    private func invalidate(_ execution: Execution, reason: Failure) {
        execution.failure = execution.failure ?? reason
        resolve(id: execution.id, approved: false)
    }

    private func waitForConfirmation(_ execution: Execution, title: String, detail: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let timer = Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await sleep(60) } catch { return }
                resolve(id: execution.id, approved: false)
            }
            pending = Pending(execution: execution, continuation: continuation, timer: timer)
            prompt = Prompt(id: execution.id, title: title, detail: detail)
            emit()
        }
    }

    private func emit() { changed(prompt, displayed?.name) }
}
