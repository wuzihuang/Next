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

    @MainActor func testBundleMissingRPCIsRememberedForFiveMinutes() async throws {
        var now = Date(timeIntervalSince1970: 1_000)
        var calls = 0
        let transport = BandDeltaTransport(now: { now }, rpc: { _, _, _ in
            XCTFail("The bundle probe must not use the legacy RPC")
            return .init(inserted: 0, completed: 0, unchanged: 0, rejected: 0, affectedDays: [])
        }, bundleRPC: { args, owner in
            calls += 1
            XCTAssertEqual(owner, "alice")
            if calls == 1 {
                XCTAssertEqual((args["p_domains"] as? [[String: Any]])?.count, 1)
                XCTAssertEqual((args["p_sleep"] as? [String: Any])?["user_id"] as? String, "alice")
                XCTAssertEqual(args["p_budget_ms"] as? Int, 1250)
            }
            if calls == 1 { throw SupabaseFailure.http(404, #"{"code":"PGRST202"}"#) }
            return try BandBundleReply(response: ["results": [], "sleep": NSNull()])
        })

        let unsupported = try await transport.bundle(domains: [["p_domain": "origin"]],
            sleep: ["user_id": "alice"], budgetMs: 1250, owner: "alice")
        XCTAssertNil(unsupported)
        let remembered = try await transport.bundle(domains: [], sleep: nil, budgetMs: nil, owner: "alice")
        XCTAssertNil(remembered)
        XCTAssertEqual(calls, 1)
        now.addTimeInterval(301)
        let available = try await transport.bundle(domains: [], sleep: nil, budgetMs: nil, owner: "alice")
        XCTAssertNotNil(available)
        XCTAssertEqual(calls, 2)
    }
}
