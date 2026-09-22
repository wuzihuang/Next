import Foundation

/// Regular refreshes share one publication. Finishing a sport needs a new drain after
/// that flight: its outbox snapshot may predate the last observed interval.
@MainActor
final class EvidencePublicationDrain {
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
    }
    private var flight: Flight?

    /// A band refresh must finish the foreground publisher's existing settlement
    /// before uploading new facts to the same account's calculation lock.
    func waitForCurrent() async {
        await flight?.task.value
    }

    func cancel() {
        flight?.task.cancel()
        flight = nil
    }

    func run(afterCurrent: Bool = false, authorized: @escaping @MainActor () -> Bool,
             publish: @escaping @MainActor () async -> Void) async {
        guard authorized(), !Task.isCancelled else { return }
        if let running = flight {
            await running.task.value
            guard afterCurrent, authorized(), !Task.isCancelled else { return }
            // The waiting caller may resume before the original caller clears its slot.
            if flight?.id == running.id { flight = nil }
            await run(authorized: authorized, publish: publish)
            return
        }
        let id = UUID()
        let task = Task { @MainActor in
            guard authorized(), !Task.isCancelled else { return }
            await publish()
        }
        flight = Flight(id: id, task: task)
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if flight?.id == id { flight = nil }
    }
}
