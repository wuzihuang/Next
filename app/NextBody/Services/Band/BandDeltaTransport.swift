import Foundation

struct BandBundleReply {
    enum Entry {
        case ok(BandIngestionAcknowledgment)
        case deferred
        case error(code: String, message: String)
    }

    enum SleepEntry {
        case ok([[String: Any]])
        case deferred
        case error(code: String, message: String)
    }

    let results: [Entry]
    let sleep: SleepEntry?

    init(response: Any) throws {
        guard let object = response as? [String: Any],
              let rawResults = object["results"] as? [Any] else {
            throw SupabaseFailure.http(500, "Invalid ingest_band_bundle response")
        }
        results = rawResults.map(Self.entry)
        if let rawSleep = object["sleep"], !(rawSleep is NSNull) {
            sleep = Self.sleepEntry(rawSleep)
        } else {
            sleep = nil
        }
    }

    private static func entry(_ value: Any) -> Entry {
        guard let object = value as? [String: Any] else {
            return .error(code: "INVALID_BUNDLE_REPLY", message: "Invalid result entry")
        }
        if object["deferred"] as? Bool == true { return .deferred }
        if let error = object["error"] as? [String: Any] {
            return .error(code: error["code"] as? String ?? "UNKNOWN", message: error["message"] as? String ?? "")
        }
        if let ack = object["ok"],
           let data = try? JSONSerialization.data(withJSONObject: ack, options: [.fragmentsAllowed]),
           let decoded = try? JSONDecoder().decode(BandIngestionAcknowledgment.self, from: data) {
            return .ok(decoded)
        }
        return .error(code: "INVALID_BUNDLE_REPLY", message: "Missing domain acknowledgment")
    }

    private static func sleepEntry(_ value: Any) -> SleepEntry {
        guard let object = value as? [String: Any] else {
            return .error(code: "INVALID_BUNDLE_REPLY", message: "Invalid sleep entry")
        }
        if object["deferred"] as? Bool == true { return .deferred }
        if let error = object["error"] as? [String: Any] {
            return .error(code: error["code"] as? String ?? "UNKNOWN", message: error["message"] as? String ?? "")
        }
        if let rows = object["ok"] as? [[String: Any]] { return .ok(rows) }
        return .error(code: "INVALID_BUNDLE_REPLY", message: "Missing sleep acknowledgment")
    }
}

/// App and database releases are independent. A server without the additive delta RPC
/// keeps receiving the original full observations until its migration becomes available.
@MainActor
final class BandDeltaTransport {
    typealias RPC = @MainActor (String, [String: Any], String) async throws -> BandIngestionAcknowledgment
    typealias BundleRPC = @MainActor ([String: Any], String) async throws -> BandBundleReply
    private let rpc: RPC
    private let bundleRPC: BundleRPC?
    private let now: @MainActor () -> Date
    private var legacyUntil: Date?
    private var bundleUntil: Date?

    init(now: @escaping @MainActor () -> Date = { Date() }, rpc: @escaping RPC) {
        self.now = now; self.rpc = rpc; self.bundleRPC = nil
    }

    init(now: @escaping @MainActor () -> Date = { Date() }, rpc: @escaping RPC,
         bundleRPC: @escaping BundleRPC) {
        self.now = now; self.rpc = rpc; self.bundleRPC = bundleRPC
    }

    func bundle(domains: [[String: Any]], sleep: [String: Any]?, budgetMs: Int?,
                owner: String) async throws -> BandBundleReply? {
        guard let bundleRPC, bundleUntil.map({ $0 > now() }) != true else { return nil }
        var args: [String: Any] = ["p_domains": domains]
        if let sleep { args["p_sleep"] = sleep }
        if let budgetMs { args["p_budget_ms"] = budgetMs }
        do {
            let reply = try await bundleRPC(args, owner)
            bundleUntil = nil
            return reply
        } catch {
            guard Self.missingRPC(error) else { throw error }
            bundleUntil = now().addingTimeInterval(300)
            return nil
        }
    }

    func ingest(_ args: [String: Any], owner: String) async throws -> BandIngestionAcknowledgment {
        if legacyUntil.map({ $0 > now() }) != true {
            do {
                let result = try await rpc("ingest_band_delta", args, owner)
                legacyUntil = nil
                return result
            } catch {
                guard Self.missingRPC(error) else { throw error }
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

    private static func missingRPC(_ error: Error) -> Bool {
        guard case SupabaseFailure.http(404, let body) = error,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["code"] as? String == "PGRST202"
    }
}
