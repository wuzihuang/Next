import XCTest
import NextBodyLocalData
@testable import NextBodySyncCore

final class BandEvidencePublicationTests: XCTestCase {
    @MainActor private final class Fixture {
        enum Failure: Error { case lostReply }
        let directory: URL
        var local: LocalDataStore
        var owner = "alice"
        var consent = true
        var sent: [[String: Any]] = []
        var order: [String] = []
        var ingest: (@MainActor ([String: Any]) async throws -> BandIngestionAcknowledgment)?
        var sleep: (@MainActor ([String: Any]) async throws -> [[String: Any]])?

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            local = try LocalDataStore(url: directory.appendingPathComponent("evidence.sqlite"))
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
        func reopen() throws { local = try LocalDataStore(url: directory.appendingPathComponent("evidence.sqlite")) }
        func pending(_ account: String = "alice", kind: String = "band-domain") throws -> [LocalOperation] {
            try local.operations(account: account, kind: kind)
        }
        func publisher(_ account: String = "alice") -> BandEvidencePublication {
            BandEvidencePublication(account: account, local: local, authorized: { self.consent && self.owner == account },
                transport: .init(ingest: { args, capturedOwner in
                    XCTAssertEqual(capturedOwner, account)
                    self.sent.append(args)
                    self.order.append("domain")
                    if let ingest = self.ingest { return try await ingest(args) }
                    let count = (args["p_samples"] as? [[String: Any]])?.count ?? 0
                    return BandIngestionAcknowledgment(inserted: 0, completed: 0, unchanged: count, rejected: 0, affectedDays: [])
                }, sleep: { row, capturedOwner in
                    XCTAssertEqual(capturedOwner, account)
                    self.order.append("sleep")
                    return try await self.sleep?(row) ?? [row]
                }))
        }
        func domain(_ samples: [[String: Any]], name: String = "origin", status: BandDomainReadStatus = .complete,
                    observedAt: String = "2026-09-08T12:00:00Z") -> BandEvidencePublication.Domain {
            let iso = ISO8601DateFormatter()
            return .init(name: name, deviceKey: "band", day: "2026-09-08", timezone: "UTC",
                start: iso.date(from: "2026-09-08T00:00:00Z")!, end: iso.date(from: "2026-09-08T12:00:00Z")!,
                observedAt: iso.date(from: observedAt)!, mappingVersion: "veepoo-rmssd-v1", status: status, samples: samples)
        }
        func samples(_ count: Int) -> [[String: Any]] {
            let iso = ISO8601DateFormatter()
            let start = iso.date(from: "2026-09-08T00:00:00Z")!
            return (0..<count).map { ["ts": iso.string(from: start.addingTimeInterval(Double($0) * 60)), "hr": 61] }
        }
        var night: [String: Any] { ["user_id": "alice", "user_day": "2026-09-08", "total_minutes": 420] }
    }

    @MainActor func testEarlyStagingKeepsLegacyIdentityAndSurvivesSleepFailureAndReopen() async throws {
        let f = try Fixture(); defer { f.remove() }
        let domain = f.domain([["ts": "2026-09-08T10:00:00Z", "hr": 61]])
        do {
            let publication = f.publisher()
            try publication.stage(domain)
            try publication.stage(domain)
            let pending = try f.pending()
            XCTAssertEqual(pending.count, 1)
            XCTAssertEqual(pending[0].id, "band-1d497925ddaa113b368b2238409b9fa81a5614ec3fbb691b27612ff306cf7a0b")
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: pending[0].payload) as? [String: Any])
            XCTAssertEqual(fields["p_status"] as? String, "partial")
            XCTAssertEqual(fields["p_start"] as? String, "2026-09-08T10:00:00Z")
            XCTAssertEqual(fields["p_end"] as? String, "2026-09-08T10:01:00Z")
            XCTAssertTrue(f.sent.isEmpty, "staging must finish before any network work")
            f.sleep = { _ in throw Fixture.Failure.lostReply }
            do { try await publication.publishSleep(f.night); XCTFail("Expected lost reply") }
            catch Fixture.Failure.lostReply { }
        }
        try f.reopen()
        XCTAssertEqual(try f.pending().count, 1)
        XCTAssertEqual(try f.pending(kind: "band-sleep").count, 1)
        f.sleep = nil
        f.order = []
        let acknowledged = try await f.publisher().replay()
        XCTAssertEqual(acknowledged, 2)
        XCTAssertEqual(f.order, ["sleep", "domain"])
        XCTAssertEqual(f.sent[0]["p_observed_at"] as? String, "2026-09-08T12:00:00Z")
        XCTAssertTrue(try f.pending().isEmpty)
        XCTAssertTrue(try f.pending(kind: "band-sleep").isEmpty)
    }

    @MainActor func testLostReplyAfterCommitReplaysWithoutDuplicatingFacts() async throws {
        let f = try Fixture(); defer { f.remove() }
        var committed = Set<String>()
        var loseReply = true
        f.ingest = { args in
            let samples = try XCTUnwrap(args["p_samples"] as? [[String: Any]])
            var inserted = 0
            for sample in samples {
                let key = "\(sample["ts"]!)|\(args["p_observed_at"]!)"
                if committed.insert(key).inserted { inserted += 1 }
            }
            if loseReply { loseReply = false; throw Fixture.Failure.lostReply }
            return .init(inserted: inserted, completed: 0, unchanged: samples.count - inserted, rejected: 0, affectedDays: [])
        }
        do {
            _ = try await f.publisher().publish(f.domain(f.samples(2)))
            XCTFail("Expected a lost reply after commit")
        } catch Fixture.Failure.lostReply { }
        XCTAssertEqual(try f.pending().count, 2)
        try f.reopen()
        let acknowledged = try await f.publisher().replay()
        XCTAssertEqual(acknowledged, 2)
        XCTAssertEqual(committed.count, 2)
        XCTAssertEqual(f.sent.count, 2)
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testPartialAndRejectedAcknowledgmentsKeepTheEntireGroup() async throws {
        for ack in [
            BandIngestionAcknowledgment(inserted: 1, completed: 0, unchanged: 0, rejected: 0, affectedDays: []),
            BandIngestionAcknowledgment(inserted: 1, completed: 0, unchanged: 0, rejected: 1, affectedDays: []),
        ] {
            let f = try Fixture(); defer { f.remove() }
            f.ingest = { _ in ack }
            let domain = f.domain(f.samples(2))
            let result = try await f.publisher().publish(domain)
            XCTAssertFalse(result.confirmed)
            XCTAssertEqual(result.state.status, .partial)
            XCTAssertEqual(result.state.repairStart, domain.start)
            XCTAssertEqual(try f.pending().count, 2)
            let noProgress = try await f.publisher().replay()
            XCTAssertEqual(noProgress, 0)
            XCTAssertEqual(try f.pending().count, 2)
            f.ingest = nil
            let confirmed = try await f.publisher().replay()
            XCTAssertEqual(confirmed, 2)
            XCTAssertTrue(try f.pending().isEmpty)
        }
    }

    @MainActor func testAcceptedObservationsDoNotTurnAPartialReadIntoCompleteCoverage() async throws {
        let f = try Fixture(); defer { f.remove() }
        let domain = f.domain(f.samples(2), status: .partial)
        let result = try await f.publisher().publish(domain)
        XCTAssertEqual(result.changedCount, 0, "unchanged observations are accepted, not newly changed")
        XCTAssertFalse(result.confirmed)
        XCTAssertEqual(result.state.status, .partial)
        XCTAssertEqual(result.state.repairStart, domain.start)
        XCTAssertNil(result.state.acknowledgedStart)
        XCTAssertTrue(try f.pending().isEmpty, "accepted facts may retire despite incomplete read coverage")
    }

    @MainActor func testEmptyReadsPublishStatusWithoutInventingDurableSamples() async throws {
        let f = try Fixture(); defer { f.remove() }
        for (name, input, expected) in [
            ("origin", BandDomainReadStatus.complete, BandDomainReadStatus.notCollected),
            ("sleep", .complete, .complete),
            ("temperature", .unsupported, .unsupported),
            ("hrv", .failed, .failed),
            ("rr", .partial, .partial),
        ] {
            let domain = f.domain([], name: name, status: input)
            let result = try await f.publisher().publish(domain)
            XCTAssertEqual(result.state.status, expected)
            XCTAssertEqual(result.changedCount, 0)
            XCTAssertEqual(result.state.acknowledgedStart, result.confirmed ? domain.start : nil)
            XCTAssertEqual(result.state.repairStart, result.confirmed ? nil : domain.start)
            XCTAssertTrue(try f.pending().isEmpty)
        }
        XCTAssertEqual(f.sent.count, 5, "empty domain status still reaches the server")
    }

    @MainActor func testReplayUsesBoundedFiniteSnapshotAndLeavesNewObservationsForNextPass() async throws {
        let f = try Fixture(); defer { f.remove() }
        try f.publisher().stage(f.domain(f.samples(450)))
        var counts: [Int] = []
        f.ingest = { args in
            let count = try XCTUnwrap(args["p_samples"] as? [[String: Any]]).count
            counts.append(count)
            if counts.count == 1 {
                try f.publisher().stage(f.domain(f.samples(1), observedAt: "2026-09-08T12:01:00Z"))
            }
            return .init(inserted: 0, completed: 0, unchanged: count, rejected: 0, affectedDays: [])
        }
        let acknowledged = try await f.publisher().replay()
        XCTAssertEqual(acknowledged, 450)
        XCTAssertEqual(counts, [200, 200, 50])
        XCTAssertEqual(try f.pending().count, 1)
        let timestamps = f.sent.flatMap { ($0["p_samples"] as? [[String: Any]] ?? []).compactMap { $0["ts"] as? String } }
        XCTAssertEqual(Set(timestamps).count, 450)
        f.ingest = nil
        let next = try await f.publisher().replay()
        XCTAssertEqual(next, 1)
        XCTAssertEqual(f.sent.last?["p_observed_at"] as? String, "2026-09-08T12:01:00Z")
    }

    @MainActor func testNoProgressStopsBeforeTheNextReplayBatch() async throws {
        let f = try Fixture(); defer { f.remove() }
        try f.publisher().stage(f.domain(f.samples(201)))
        f.ingest = { _ in .init(inserted: 0, completed: 0, unchanged: 0, rejected: 1, affectedDays: []) }
        let acknowledged = try await f.publisher().replay()
        XCTAssertEqual(acknowledged, 0)
        XCTAssertEqual(f.sent.count, 1)
        XCTAssertEqual(try f.pending().count, 201)
    }

    @MainActor func testAccountOrConsentChangeDuringUploadCannotRetireEvidence() async throws {
        for changeAccount in [true, false] {
            let f = try Fixture(); defer { f.remove() }
            f.owner = "bob"
            try f.publisher("bob").stage(f.domain(f.samples(1)))
            f.owner = "alice"
            f.ingest = { _ in
                if changeAccount { f.owner = "bob" } else { f.consent = false }
                await Task.yield()
                return .init(inserted: 1, completed: 0, unchanged: 0, rejected: 0, affectedDays: [])
            }
            do { _ = try await f.publisher().publish(f.domain(f.samples(1))); XCTFail("Expected cancellation") }
            catch is CancellationError { }
            XCTAssertEqual(try f.pending("alice").count, 1)
            XCTAssertEqual(try f.pending("bob").count, 1)
            do { _ = try await f.publisher().replay(); XCTFail("Expected cancellation") }
            catch is CancellationError { }
            XCTAssertEqual(f.sent.count, 1, "an unauthorized replay must not send")
        }
    }

    @MainActor func testCancellationDuringUploadLeavesEvidenceQueued() async throws {
        let f = try Fixture(); defer { f.remove() }
        f.ingest = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return .init(inserted: 1, completed: 0, unchanged: 0, rejected: 0, affectedDays: [])
        }
        let task = Task { @MainActor in try await f.publisher().publish(f.domain(f.samples(1))) }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertEqual(try f.pending().count, 1)
    }

    @MainActor func testSleepConfirmationRequiresTheSameNightButAllowsMergedRawEvidence() async throws {
        let f = try Fixture(); defer { f.remove() }
        for (key, invalid) in [("user_id", "bob" as Any), ("user_day", "2026-09-07" as Any), ("total_minutes", 1 as Any)] {
            f.sleep = { row in [row.merging([key: invalid]) { _, new in new }] }
            do { try await f.publisher().publishSleep(f.night); XCTFail("Expected unconfirmed sleep") }
            catch BandEvidencePublication.Failure.sleepNotConfirmed { }
            XCTAssertEqual(try f.pending(kind: "band-sleep").count, 1)
        }
        f.sleep = { row in [row.merging(["raw": ["hrv": [61, 62]]]) { _, new in new }] }
        try await f.publisher().publishSleep(f.night)
        XCTAssertTrue(try f.pending(kind: "band-sleep").isEmpty)
    }

    @MainActor func testFailedSleepReplayStopsBeforeDomainReplay() async throws {
        let f = try Fixture(); defer { f.remove() }
        f.sleep = { _ in throw Fixture.Failure.lostReply }
        do { try await f.publisher().publishSleep(f.night); XCTFail("Expected upload failure") }
        catch Fixture.Failure.lostReply { }
        try f.publisher().stage(f.domain(f.samples(1)))
        f.order = []
        do { _ = try await f.publisher().replay(); XCTFail("Expected replay failure") }
        catch Fixture.Failure.lostReply { }
        XCTAssertEqual(f.order, ["sleep"])
        XCTAssertEqual(try f.pending(kind: "band-sleep").count, 1)
        XCTAssertEqual(try f.pending().count, 1)
    }
}
