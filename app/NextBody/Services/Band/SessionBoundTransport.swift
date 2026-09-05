import Foundation

struct RequestSession: Equatable, Sendable {
    let owner: String?
    let generation: UUID
}

/// A refresh may change credentials, never the account/session that owns the request body.
enum SessionBoundTransport {
    static func identifying(_ request: URLRequest, requestID: UUID) -> URLRequest {
        var identified = request
        identified.setValue(requestID.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        return identified
    }
    static func perform<Body: Sendable>(_ request: URLRequest, session: RequestSession,
        current: @Sendable () async -> RequestSession,
        send: @Sendable (URLRequest) async throws -> (Body, URLResponse),
        refresh: @Sendable () async -> String?) async throws -> (Body, URLResponse) {
        guard !Task.isCancelled, await current() == session else { throw CancellationError() }
        let first = try await send(request)
        guard !Task.isCancelled, await current() == session else { throw CancellationError() }
        guard (first.1 as? HTTPURLResponse)?.statusCode == 401 else { return first }
        guard let token = await refresh() else { return first }
        guard !Task.isCancelled, await current() == session else { throw CancellationError() }
        var retry = request
        retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let result = try await send(retry)
        guard !Task.isCancelled, await current() == session else { throw CancellationError() }
        return result
    }
}
