import Foundation

/// Owns the radio from BEFORE scanning until activation/scan cleanup completes.
/// A timeout abandons only the waiter, never an in-flight native command.
@MainActor
final class DeviceActivationGate {
    private(set) var owner: UUID?
    var isHeld: Bool { owner != nil }

    func prepare(owner token: UUID, timeout: Duration = .seconds(20),
                 acquired: () -> Void = {},
                 idle: () -> Bool) async throws {
        guard owner == nil || owner == token else { throw Failure.busy }
        owner = token
        acquired()
        do {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while !idle() {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw Failure.busy }
                try await Task.sleep(for: .milliseconds(50))
            }
            try Task.checkCancellation()
        } catch {
            release(owner: token)
            throw error
        }
    }

    func release(owner token: UUID) {
        if owner == token { owner = nil }
    }

    enum Failure: Error { case busy }
}
