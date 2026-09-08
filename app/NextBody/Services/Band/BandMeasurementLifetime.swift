import Foundation

/// Owns the native measurement until its cancellation and SDK stop have drained. A
/// dismissed view can no longer hold the device, and a successor cannot race its stop.
@MainActor
final class BandMeasurementLifetime {
    private var current: (id: UUID, generation: UUID, task: Task<Void, Never>)?
    private let acquire: @MainActor () async -> Void
    private let release: @MainActor () async -> Void
    private let changed: @MainActor () -> Void
    var isBusy: Bool { current != nil }

    init(acquire: @escaping @MainActor () async -> Void,
         release: @escaping @MainActor () async -> Void,
         changed: @escaping @MainActor () -> Void) {
        self.acquire = acquire
        self.release = release
        self.changed = changed
    }

    @discardableResult
    func start(id: UUID, operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = current?.task
        previous?.cancel()
        let generation = UUID()
        let task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { finish(generation); return }
            await acquire()
            if !Task.isCancelled { await operation() }
            // Cancellation still owes release; SDK streams may enqueue their stop on the
            // main queue after the consumer leaves its iterator.
            await release()
            finish(generation)
        }
        current = (id, generation, task)
        changed()
        return task
    }

    func cancel(id: UUID) {
        guard current?.id == id else { return }
        current?.task.cancel()
    }

    private func finish(_ generation: UUID) {
        guard current?.generation == generation else { return }
        current = nil
        changed()
    }
}
