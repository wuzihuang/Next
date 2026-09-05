import Foundation

/// One native sport callback serves the live screen and short state probes together.
/// A stale reader's cleanup cannot remove a later session's callback.
@MainActor
final class BandSportSubscription {
    nonisolated init() {}
    private var readers: Set<UUID> = []
    private(set) var generation = 0

    func add(_ id: UUID) -> Bool {
        let first = readers.isEmpty
        readers.insert(id)
        if first { generation += 1 }
        return first
    }

    func remove(_ id: UUID) -> Bool {
        guard readers.remove(id) != nil else { return false }
        return readers.isEmpty
    }

    func contains(_ id: UUID) -> Bool { readers.contains(id) }
}
