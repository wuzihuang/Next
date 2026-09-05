import Foundation

/// A start attempt has its own identity even when the next workout uses the same mode.
struct SportSessionLifetime: Equatable, Sendable {
    private let id = UUID()
    let account: String?
    let binding: String?

    func accepts(current: Self?, account: String?, binding: String?, consent: Bool) -> Bool {
        self == current && consent && self.account == account && self.binding == binding
    }
}

/// Cancellation does not retract an SDK command already on the wire. Finish its callback
/// before issuing final stop, then let a subsequent session acquire the band.
@MainActor
enum SportSessionTaskFence {
    static func cancelAndWait(_ opening: Task<Void, Never>?, _ reading: Task<Void, Never>?) async {
        opening?.cancel()
        reading?.cancel()
        await opening?.value
        await reading?.value
    }
}

/// Retry the bound device without turning a missing wrist into a tight scan loop.
enum SportReconnectPolicy {
    static func delay(failures: Int) -> TimeInterval {
        min(30, 3 * pow(2, Double(min(4, max(0, failures - 1)))))
    }
}

/// Only an issued command with an uncertain/successful result can need final close.
/// A definitive busy reply means this start did not acquire the sport mode.
enum SportStartDisposition {
    case notIssued, issued, busy, opened

    var needsCleanup: Bool { self == .issued || self == .opened }
    static func shouldRetryBusy(previousRetries: Int) -> Bool { previousRetries == 0 }
    static func canJoin(observedRunState: Int?) -> Bool { observedRunState == 1 }
}

@MainActor
enum SportStartRetry {
    static func perform(settle: () async throws -> Void, start: () async throws -> Void,
                        isBusy: (Error) -> Bool,
                        disposition: (SportStartDisposition) -> Void) async throws {
        var retries = 0
        while true {
            try await settle()
            try Task.checkCancellation()
            disposition(.issued)
            do {
                try await start()
                disposition(.opened)
                return
            } catch {
                guard isBusy(error) else { throw error }
                disposition(.busy)
                guard SportStartDisposition.shouldRetryBusy(previousRetries: retries),
                      !Task.isCancelled else { throw error }
                retries += 1
            }
        }
    }
}
