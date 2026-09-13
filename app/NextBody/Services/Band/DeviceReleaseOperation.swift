import Foundation

/// The account acknowledgment completes removal. Radio cleanup may still be draining
/// an SDK command, so it must never hold that acknowledgment on screen.
@MainActor
enum DeviceReleaseOperation {
    static func run<Response>(request: () async throws -> Response,
                              publish: (Response) -> Void,
                              cleanup: @escaping @MainActor () async -> Void) async throws -> Task<Void, Never> {
        let response = try await request()
        publish(response)
        return Task { await cleanup() }
    }
}

enum DeviceReleaseError: Error {
    case busy, pendingChanges, bindingUnavailable

    static func message(for error: Error) -> String {
        if let failure = error as? Self {
            switch failure {
            case .busy: return "The HOOP is switching or finishing a command. Try again shortly."
            case .pendingChanges: return "Your last wear change is still being saved. Try again shortly."
            case .bindingUnavailable: return "The pairing details are not loaded yet. Reopen Device and try again."
            }
        }
        if case SupabaseFailure.http(let status, let body) = error {
            if status == 404 || body.contains("PGRST202") {
                return "HOOP removal is temporarily unavailable. Please try again later."
            }
            if status == 401 { return "Your session has expired. Sign in again to remove this HOOP." }
            if status == 403 { return "The pairing has changed. Reopen Device to refresh it." }
        }
        let underlying: Error
        if case SupabaseFailure.transport(let cause) = error { underlying = cause } else { underlying = error }
        if let urlError = underlying as? URLError {
            if urlError.code == .timedOut {
                return "Removal could not be confirmed in time. Retry to check; your history is safe."
            }
            return "Unable to reach the server. Check your internet connection and try again."
        }
        return "Removal could not be confirmed. Retry to check; your history is safe."
    }
}
