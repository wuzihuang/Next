import Foundation

/// Foreground demand controls the panel; background collection belongs to the app.
enum BandLivePolicy {
    enum Phase { case active, inactive, background }
    struct Owner: Equatable, Sendable {
        let account: String
        let binding: String
    }
    static func shouldRun(phase: Phase, foregroundWanted: Bool, hasOwner: Bool,
                          consent: Bool, connected: Bool, exclusive: Bool) -> Bool {
        hasOwner && consent && connected && !exclusive
            && (phase != .active || foregroundWanted)
    }
}

/// Keep the old task until its cancellation cleanup completes. New eligibility may change
/// repeatedly during that await; only the latest request is started afterwards.
@MainActor
final class BandLiveTaskOwner {
    private var task: Task<Void, Never>?
    private var taskOwner: BandLivePolicy.Owner?
    private var desired: BandLivePolicy.Owner?
    private var operation: (@MainActor () async -> Void)?
    private var stopping = false
    private var generation: UInt = 0

    func update(owner: BandLivePolicy.Owner?, operation: @escaping @MainActor () async -> Void) {
        desired = owner
        self.operation = operation
        if task != nil {
            if owner != taskOwner || stopping {
                stopping = true
                task?.cancel()
            }
            return
        }
        launchIfWanted()
    }

    private func launchIfWanted() {
        guard let desired, let operation else { return }
        generation += 1
        let token = generation
        taskOwner = desired
        stopping = false
        task = Task { @MainActor in
            await operation()
            guard self.generation == token else { return }
            let restart = self.stopping
            self.task = nil
            self.taskOwner = nil
            self.stopping = false
            if restart { self.launchIfWanted() }
        }
    }
}
