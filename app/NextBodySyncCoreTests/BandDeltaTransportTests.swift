import XCTest
@testable import NextBodySyncCore

final class BandDeltaTransportTests: XCTestCase {
    @MainActor func testOldServerRequestsFullValuesThenUsesLegacyRPC() async throws {
        var calls: [String] = []
        let transport = BandDeltaTransport { name, args, owner in
            calls.append(name)
            XCTAssertEqual(owner, "alice")
            if name == "ingest_band_delta" { throw SupabaseFailure.http(404, #"{"code":"PGRST202"}"#) }
            XCTAssertNil(args["p_receipts"])
            XCTAssertEqual((args["p_samples"] as? [[String: Any]])?.count, 1)
            return .init(inserted: 1, completed: 0, unchanged: 0, rejected: 0, affectedDays: [])
        }
        let miss = try await transport.ingest(["p_samples": [], "p_receipts": [["ts": "t", "receipt": "token"]]], owner: "alice")
        XCTAssertEqual(miss.needsSamples, ["t"])
        XCTAssertFalse(miss.confirms(offered: 0))
        let full = try await transport.ingest(["p_samples": [["ts": "t", "heart": 61]]], owner: "alice")
        XCTAssertTrue(full.confirms(offered: 1))
        XCTAssertEqual(calls, ["ingest_band_delta", "ingest_band_domain"])
    }

    @MainActor func testPermissionNetworkAndUnknown404FailuresNeverDowngrade() async throws {
        for error in [SupabaseFailure.http(403, #"{"code":"42501"}"#), .http(500, "unavailable"), .http(404, "other")] {
            var calls: [String] = []
            let transport = BandDeltaTransport { name, _, _ in calls.append(name); throw error }
            do { _ = try await transport.ingest(["p_samples": []], owner: "alice"); XCTFail("Expected error") }
            catch is SupabaseFailure { }
            XCTAssertEqual(calls, ["ingest_band_delta"])
        }
    }

    @MainActor func testServerUpgradeIsDiscoveredAfterBoundedFallback() async throws {
        var now = Date(timeIntervalSince1970: 1_000)
        var available = false
        var calls: [String] = []
        let transport = BandDeltaTransport(now: { now }) { name, _, _ in
            calls.append(name)
            if name == "ingest_band_delta" && !available { throw SupabaseFailure.http(404, #"{"code":"PGRST202"}"#) }
            return .init(inserted: 0, completed: 0, unchanged: 0, rejected: 0, affectedDays: [])
        }
        _ = try await transport.ingest(["p_samples": []], owner: "alice")
        available = true
        _ = try await transport.ingest(["p_samples": []], owner: "alice")
        now.addTimeInterval(301)
        _ = try await transport.ingest(["p_samples": []], owner: "alice")
        XCTAssertEqual(calls, ["ingest_band_delta", "ingest_band_domain", "ingest_band_domain", "ingest_band_delta"])
    }
}
