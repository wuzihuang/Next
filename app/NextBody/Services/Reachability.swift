import Foundation
import Network

/// 05 edge 5 · a message never leaves the dock when there is no connection — once it flies into
/// the panel there is no way to get it back. One path monitor, read on the main actor.
@MainActor
final class Reachability: ObservableObject {
    static let shared = Reachability()
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "nb.reachability"))
    }
}
