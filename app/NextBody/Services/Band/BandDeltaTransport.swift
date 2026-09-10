import Foundation

/// App and database releases are independent. A server without the additive delta RPC
/// keeps receiving the original full observations until its migration becomes available.
@MainActor
final class BandDeltaTransport {
    typealias RPC = @MainActor (String, [String: Any], String) async throws -> BandIngestionAcknowledgment
    private let rpc: RPC
    private let now: @MainActor () -> Date
    private var legacyUntil: Date?

    init(now: @escaping @MainActor () -> Date = { Date() }, rpc: @escaping RPC) {
        self.now = now; self.rpc = rpc
    }

    func ingest(_ args: [String: Any], owner: String) async throws -> BandIngestionAcknowledgment {
        if legacyUntil.map({ $0 > now() }) != true {
            do {
                let result = try await rpc("ingest_band_delta", args, owner)
                legacyUntil = nil
                return result
            } catch {
                guard Self.missingDeltaRPC(error) else { throw error }
                legacyUntil = now().addingTimeInterval(300)
            }
        }
        // The publisher still owns full durable samples. Ask it to resend them before
        // calling the legacy RPC; never silently drop referenced measurements.
        let references = args["p_receipts"] as? [[String: Any]] ?? []
        if !references.isEmpty {
            return .init(inserted: 0, completed: 0, unchanged: 0, rejected: 0,
                         affectedDays: [], needsSamples: references.compactMap { $0["ts"] as? String })
        }
        var full = args
        full.removeValue(forKey: "p_receipts")
        return try await rpc("ingest_band_domain", full, owner)
    }

    private static func missingDeltaRPC(_ error: Error) -> Bool {
        guard case SupabaseFailure.http(404, let body) = error,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["code"] as? String == "PGRST202"
    }
}
