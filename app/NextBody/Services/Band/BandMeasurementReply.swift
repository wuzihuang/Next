import Foundation

/// One native measurement owns its stop and continuation. Every terminal path stops on
/// main before releasing the caller, and late native replies cannot stop its successor.
@MainActor
final class BandMeasurementReply<Value: Sendable> {
    struct Timeout: Error {}
    private var continuation: CheckedContinuation<Value, Error>?
    private var stop: (() -> Void)?
    private var timeout: Task<Void, Never>?
    private var finished = false

    var isPending: Bool { continuation != nil && !finished }

    func wait(seconds: TimeInterval,
              start: (@escaping (Result<Value, Error>) -> Void) -> Void,
              stop: @escaping () -> Void) async throws -> Value {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.stop = stop
                timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(seconds)) }
                    catch { return }
                    self.finish(.failure(Timeout()))
                }
                start { result in self.finish(result) }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<Value, Error>) {
        guard !finished, let continuation else { return }
        finished = true
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        let stop = self.stop
        self.stop = nil
        stop?()
        continuation.resume(with: result)
    }
}
