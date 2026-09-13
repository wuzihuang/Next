import Foundation

/// One short BLE transaction at a time. An account/binding change cannot share the old
/// result or start competing commands; callers still validate their scope after waiting.
@MainActor
final class BandReadinessFlight {
    private var current: (key: String, id: UUID, task: Task<Bool, Never>)?

    func run(key: String, operation: @escaping @MainActor () async -> Bool) async -> Bool {
        if let active = current {
            let result = await active.task.value
            if active.key == key { return result }
            if current?.id == active.id { current = nil }
            return await run(key: key, operation: operation)
        }
        let id = UUID()
        let task = Task { @MainActor in await operation() }
        current = (key, id, task)
        let result = await task.value
        if current?.id == id { current = nil }
        return result
    }
}

/// A timestamp alone is insufficient: only this owner and this verified link may reuse it.
enum BandReadinessReceiptPolicy {
    static func canReuse(requested: Bool, connected: Bool, exclusive: Bool,
                         ownerMatches: Bool, age: TimeInterval, maxAge: TimeInterval = 3) -> Bool {
        requested && connected && !exclusive && ownerMatches && age.isFinite && age >= 0 && age <= maxAge
    }
}

/// A takeover closes admission before waiting here. Only native BLE work holds a lease;
/// network uploads and historical orchestration never delay the sensor handoff.
@MainActor
final class BandNativeDrain {
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isIdle: Bool { active == 0 }

    func begin() { active += 1 }

    func end() {
        precondition(active > 0)
        active -= 1
        guard active == 0 else { return }
        let released = waiters
        waiters = []
        for waiter in released { waiter.resume() }
    }

    func waitUntilIdle() async {
        guard active > 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
