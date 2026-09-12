import Foundation

/// One phone call owns its confirmation, eligibility and completion. Both the app and
/// controlled adapters execute through this interface; every suspended step rechecks the
/// same account/session, turn and band before it can issue a subsequent action.
@MainActor
final class PhoneToolExecution {
    fileprivate final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }
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
        /// A confirm whose own fields the tap may correct before it approves. The model
        /// proposes by ear — #28's night is the clearest case — and the person who lived
        /// the thing being written is already looking at the screen.
        var edit: Edit?

        enum Edit: Equatable {
            /// The night's two clock times, `HH:MM`, as proposed. Approved values come back
            /// as the `start` and `end` the tool writes.
            case sleepWindow(start: String, end: String)
        }
    }

    enum Failure: String, Error {
        case cancelled = "CANCELLED"
        case background = "APP_BACKGROUND"
        case consentRequired = "CONSENT_REQUIRED"
        case sessionChanged = "SESSION_CHANGED"
        case bindingChanged = "BAND_DISCONNECTED"
        case alarmSlotsFull = "ALARM_SLOTS_FULL"
        case alarmNotFound = "ALARM_NOT_FOUND"
        case alreadyExecuted = "CALL_ALREADY_EXECUTED"
    }

    @MainActor
    final class Execution {
        let id = UUID()
        let scope: Scope
        let callID: String
        fileprivate var failure: Failure?
        fileprivate var finished = false
        /// What the confirm's own fields were set to before the tap approved it. A tool
        /// reads these over its arguments: an edited confirm writes what the screen said,
        /// not what the model guessed.
        fileprivate(set) var edited: [String: String] = [:]
        private let current: () -> Environment
        private let cancellation: Cancellation

        fileprivate init(scope: Scope, callID: String, cancellation: Cancellation,
                         current: @escaping () -> Environment) {
            self.scope = scope
            self.callID = callID
            self.current = current
            self.cancellation = cancellation
        }

        /// Check immediately before each side effect. A read followed by a write must use
        /// separate steps so the read's suspension cannot carry old authority to the write.
        func check() throws {
            if let failure { throw failure }
            let now = current()
            let reason: Failure?
            if Task.isCancelled || cancellation.isCancelled || finished { reason = .cancelled }
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

        func setAlarm(_ draft: BandAlarm,
                      read: @MainActor () async throws -> [BandAlarm],
                      write: @MainActor (BandAlarm) async throws -> [BandAlarm]) async throws -> (id: Int, alarms: [BandAlarm]) {
            let alarms = try await perform(read)
            guard let id = BandAlarmMath.nextID(in: alarms) else { throw Failure.alarmSlotsFull }
            var next = draft
            next.id = id
            let after = try await perform { try await write(BandAlarmMath.prepared(next)) }
            return (id, after)
        }

        func deleteAlarm(_ id: Int,
                         read: @MainActor () async throws -> [BandAlarm],
                         delete: @MainActor (BandAlarm) async throws -> [BandAlarm]) async throws -> [BandAlarm] {
            let alarms = try await perform(read)
            guard let alarm = alarms.first(where: { $0.id == id }) else { throw Failure.alarmNotFound }
            return try await perform { try await delete(alarm) }
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
    private var admittedScope: Scope?
    private var admittedCalls: Set<String> = []

    init(current: @escaping () -> Environment,
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void,
         changed: @escaping @MainActor (Prompt?, String?) -> Void) {
        self.current = current
        self.sleep = sleep
        self.changed = changed
    }

    func run<Value>(scope: Scope, callID: String, name: String,
                    confirmation: (title: String, detail: String, edit: Prompt.Edit?)?,
                    action: @MainActor (Execution) async throws -> Value) async throws -> Value {
        let cancellation = Cancellation()
        let execution = Execution(scope: scope, callID: callID, cancellation: cancellation, current: current)
        try execution.check()
        if admittedScope != scope { admittedScope = scope; admittedCalls = [] }
        guard admittedCalls.insert(callID).inserted else { throw Failure.alreadyExecuted }
        // A new call replaces the visible confirmation; the displaced waiter is completed
        // before installing its successor, and its timer can only resolve its own UUID.
        invalidateAll(.cancelled)
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
                let approved = await waitForConfirmation(execution, title: confirmation.title,
                                                        detail: confirmation.detail, edit: confirmation.edit)
                try execution.check()
                guard approved else { throw Failure.cancelled }
            }
            return try await execution.perform { try await action(execution) }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor in self.invalidate(execution, reason: .cancelled) }
        }
    }

    /// `edited` is what the confirm's own fields read at the moment of the tap. It is kept
    /// only on an approval that is still eligible: a cancelled or expired confirm writes
    /// nothing, so there is nothing for it to carry.
    func resolve(id: UUID, approved: Bool, edited: [String: String] = [:]) {
        guard let waiting = pending, waiting.execution.id == id else { return }
        pending = nil
        prompt = nil
        waiting.timer.cancel()
        let eligible = (try? waiting.execution.check()) != nil
        if approved, eligible { waiting.execution.edited = edited }
        waiting.continuation.resume(returning: approved && eligible)
        emit()
    }

    /// Host events wake confirmation immediately; checks at every action remain the
    /// authority even if a notification has not yet reached the main actor.
    func refreshEligibility() {
        for execution in Array(executions.values) {
            do { try execution.check() }
            catch let reason as Failure { invalidate(execution, reason: reason) }
            catch { invalidate(execution, reason: .cancelled) }
        }
    }

    func invalidateAll(_ reason: Failure) {
        for execution in Array(executions.values) { invalidate(execution, reason: reason) }
    }

    private func invalidate(_ execution: Execution, reason: Failure) {
        execution.failure = execution.failure ?? reason
        resolve(id: execution.id, approved: false)
    }

    private func waitForConfirmation(_ execution: Execution, title: String, detail: String,
                                     edit: Prompt.Edit?) async -> Bool {
        await withCheckedContinuation { continuation in
            let timer = Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await sleep(60) } catch { return }
                resolve(id: execution.id, approved: false)
            }
            pending = Pending(execution: execution, continuation: continuation, timer: timer)
            prompt = Prompt(id: execution.id, title: title, detail: detail, edit: edit)
            emit()
        }
    }

    private func emit() { changed(prompt, displayed?.name) }
}
