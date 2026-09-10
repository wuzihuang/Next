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
                    observedAt: String = "2026-09-08T12:00:00Z", deviceKey: String = "band",
                    mappingVersion: String = "veepoo-rmssd-v1") -> BandEvidencePublication.Domain {
            let iso = ISO8601DateFormatter()
            return .init(name: name, deviceKey: deviceKey, day: "2026-09-08", timezone: "UTC",
                start: iso.date(from: "2026-09-08T00:00:00Z")!, end: iso.date(from: "2026-09-08T12:00:00Z")!,
                observedAt: iso.date(from: observedAt)!, mappingVersion: mappingVersion, status: status, samples: samples)
        }
        func completeSample(_ ts: String, heart: Int = 61, readAt: String? = nil) -> [String: Any] {
            var sample: [String: Any] = ["ts": ts, "heart": heart, "step": 5, "cal": 1,
                "dis": 4, "met": 1.2, "stress": 20, "sleep_states": 0,
                "user_id": owner, "src": "band", "sampled_tz": "UTC"]
            if let readAt { sample["origin_read_at"] = readAt }
            return sample
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

    @MainActor func testConfirmedContentUsesReceiptsAfterReopenAndPreservesNewObservationClock() async throws {
        let f = try Fixture(); defer { f.remove() }
        let ts = "2026-09-08T10:00:00Z"
        f.ingest = { args in
            let samples = args["p_samples"] as? [[String: Any]] ?? []
            let references = args["p_receipts"] as? [[String: Any]] ?? []
            return .init(inserted: 0, completed: 0, unchanged: samples.count + references.count,
                         rejected: 0, affectedDays: [], receipts: [ts: "server-confirmed-content"])
        }
        _ = try await f.publisher().publish(f.domain([f.completeSample(ts, readAt: "2026-09-08T12:00:01.123Z")]))
        try f.reopen()
        let next = f.domain([f.completeSample(ts, readAt: "2026-09-08T12:05:01.456Z")],
                            observedAt: "2026-09-08T12:05:00Z")
        let result = try await f.publisher().publish(next)
        let sent = try XCTUnwrap(f.sent.last)
        XCTAssertTrue(try XCTUnwrap(sent["p_samples"] as? [[String: Any]]).isEmpty)
        let reference = try XCTUnwrap((sent["p_receipts"] as? [[String: Any]])?.first)
        XCTAssertEqual(reference["receipt"] as? String, "server-confirmed-content")
        XCTAssertEqual(reference["origin_read_at"] as? String, "2026-09-08T12:05:01.456Z")
        XCTAssertEqual(sent["p_observed_at"] as? String, "2026-09-08T12:05:00Z")
        XCTAssertTrue(result.confirmed, "a verified unchanged read is complete, not not_collected")
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testNewAndRevisedValuesUploadWhileUnchangedValuesUseReceipts() async throws {
        let f = try Fixture(); defer { f.remove() }
        let a = "2026-09-08T10:00:00Z", b = "2026-09-08T10:05:00Z", c = "2026-09-08T10:10:00Z"
        f.ingest = { args in
            let samples = args["p_samples"] as? [[String: Any]] ?? []
            let refs = args["p_receipts"] as? [[String: Any]] ?? []
            return .init(inserted: 0, completed: 0, unchanged: samples.count + refs.count,
                         rejected: 0, affectedDays: [], receipts: [a: "a", b: "b", c: "c"])
        }
        _ = try await f.publisher().publish(f.domain([f.completeSample(a), f.completeSample(b, heart: 62)]))
        _ = try await f.publisher().publish(f.domain([f.completeSample(a), f.completeSample(b, heart: 65),
            f.completeSample(c, heart: 63)], observedAt: "2026-09-08T12:05:00Z"))
        XCTAssertEqual((f.sent.last?["p_samples"] as? [[String: Any]])?.compactMap { $0["ts"] as? String }, [b, c])
        XCTAssertEqual((f.sent.last?["p_receipts"] as? [[String: Any]])?.compactMap { $0["ts"] as? String }, [a])
    }

    @MainActor func testServerInvalidatedReceiptResendsOriginalValuesWithoutLosingRevisionTime() async throws {
        let f = try Fixture(); defer { f.remove() }
        let ts = "2026-09-08T10:00:00Z"
        f.ingest = { _ in .init(inserted: 1, completed: 0, unchanged: 0, rejected: 0,
                                affectedDays: [], receipts: [ts: "old-token"]) }
        _ = try await f.publisher().publish(f.domain([f.completeSample(ts)]))
        f.ingest = { args in
            if !(args["p_receipts"] as? [[String: Any]] ?? []).isEmpty {
                return .init(inserted: 0, completed: 0, unchanged: 0, rejected: 0,
                             affectedDays: [], needsSamples: [ts])
            }
            return .init(inserted: 0, completed: 1, unchanged: 0, rejected: 0,
                         affectedDays: ["2026-09-08"], receipts: [ts: "fresh-token"])
        }
        let result = try await f.publisher().publish(f.domain([f.completeSample(ts)],
            observedAt: "2026-09-08T12:05:00Z"))
        XCTAssertEqual(f.sent.count, 3)
        XCTAssertEqual((f.sent.last?["p_samples"] as? [[String: Any]])?.first?["heart"] as? Int, 61)
        XCTAssertEqual(f.sent.last?["p_observed_at"] as? String, "2026-09-08T12:05:00Z")
        XCTAssertTrue(result.confirmed)
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testFailedReceiptUploadRemainsDurableAndReplayUsesOriginalObservation() async throws {
        let f = try Fixture(); defer { f.remove() }
        let ts = "2026-09-08T10:00:00Z"
        f.ingest = { _ in .init(inserted: 1, completed: 0, unchanged: 0, rejected: 0,
                                affectedDays: [], receipts: [ts: "token"]) }
        _ = try await f.publisher().publish(f.domain([f.completeSample(ts)]))
        f.ingest = { _ in throw Fixture.Failure.lostReply }
        do {
            _ = try await f.publisher().publish(f.domain([f.completeSample(ts)], observedAt: "2026-09-08T12:05:00Z"))
            XCTFail("Expected failed confirmation")
        } catch Fixture.Failure.lostReply { }
        try f.reopen()
        XCTAssertEqual(try f.pending().count, 1)
        f.ingest = { args in
            XCTAssertEqual(args["p_observed_at"] as? String, "2026-09-08T12:05:00Z")
            return .init(inserted: 0, completed: 0, unchanged: 1, rejected: 0,
                         affectedDays: [], receipts: [ts: "token"])
        }
        let replayed = try await f.publisher().replay()
        XCTAssertEqual(replayed, 1)
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testAggregateAcknowledgmentWithoutExplicitReceiptsNeverEnablesDeduplication() async throws {
        let f = try Fixture(); defer { f.remove() }
        let domain = f.domain(f.samples(1))
        _ = try await f.publisher().publish(domain)
        _ = try await f.publisher().publish(domain)
        XCTAssertEqual((f.sent.last?["p_samples"] as? [[String: Any]])?.count, 1,
                       "unchanged can mean a stale revision was ignored; it is not proof of equal stored content")
    }

    @MainActor func testSmallMeasurementsAreNotReplacedWithLargerReceipts() async throws {
        let f = try Fixture(); defer { f.remove() }
        let ts = "2026-09-08T10:00:00Z"
        f.ingest = { _ in .init(inserted: 0, completed: 0, unchanged: 1, rejected: 0,
                                affectedDays: [], receipts: [ts: String(repeating: "a", count: 64)]) }
        let domain = f.domain([["ts": ts, "temp": 36.5]], name: "temperature")
        _ = try await f.publisher().publish(domain)
        _ = try await f.publisher().publish(domain)
        XCTAssertEqual((f.sent.last?["p_samples"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(f.sent.last?["p_receipts"], "a scalar is cheaper to send than a content receipt")
    }

    @MainActor func testReceiptScopeSeparatesAccountsDevicesAndMappingVersions() async throws {
        let f = try Fixture(); defer { f.remove() }
        let ts = "2026-09-08T10:00:00Z"
        f.ingest = { _ in .init(inserted: 0, completed: 0, unchanged: 1, rejected: 0,
                                affectedDays: [], receipts: [ts: "token"]) }
        _ = try await f.publisher().publish(f.domain([f.completeSample(ts)]))
        _ = try await f.publisher().publish(f.domain([f.completeSample(ts)], deviceKey: "other"))
        XCTAssertNil(f.sent.last?["p_receipts"])
        _ = try await f.publisher().publish(f.domain([f.completeSample(ts)], mappingVersion: "veepoo-rmssd-v2"))
        XCTAssertNil(f.sent.last?["p_receipts"])
        f.owner = "bob"
        _ = try await f.publisher("bob").publish(f.domain([f.completeSample(ts)]))
        XCTAssertNil(f.sent.last?["p_receipts"])
        f.owner = "alice"
        try f.local.purge(account: "alice")
        _ = try await f.publisher().publish(f.domain([f.completeSample(ts)]))
        XCTAssertNil(f.sent.last?["p_receipts"], "account purge also removes its confirmation cache")
    }

    @MainActor func testVerifiedReferencesStayReusableWithoutReturningTokensAndReduceRequestBytes() async throws {
        let f = try Fixture(); defer { f.remove() }
        let ts = "2026-09-08T10:00:00Z"
        f.ingest = { args in
            let references = args["p_receipts"] as? [[String: Any]] ?? []
            return .init(inserted: 0, completed: 0, unchanged: 1, rejected: 0, affectedDays: [],
                         receipts: references.isEmpty ? [ts: String(repeating: "a", count: 64)] : [:])
        }
        for minute in ["00", "05", "10"] {
            _ = try await f.publisher().publish(f.domain([f.completeSample(ts, readAt: "2026-09-08T12:\(minute):01.123Z")],
                observedAt: "2026-09-08T12:\(minute):00Z"))
        }
        let firstBytes = try JSONSerialization.data(withJSONObject: f.sent[0]).count
        for request in f.sent.dropFirst() {
            XCTAssertTrue(try XCTUnwrap(request["p_samples"] as? [[String: Any]]).isEmpty)
            XCTAssertEqual((request["p_receipts"] as? [[String: Any]])?.count, 1)
            XCTAssertLessThan(try JSONSerialization.data(withJSONObject: request).count, firstBytes)
        }
    }

    @MainActor func testSameSecondRevisionsReplayInSeparateTimestampUniqueBatches() async throws {
        let f = try Fixture(); defer { f.remove() }
        let ts = "2026-09-08T10:00:00Z"
        try f.publisher().stage(f.domain([f.completeSample(ts, heart: 61, readAt: "2026-09-08T12:00:00.100Z")]))
        try f.publisher().stage(f.domain([f.completeSample(ts, heart: 65, readAt: "2026-09-08T12:00:00.900Z")]))
        f.ingest = { args in
            let samples = try XCTUnwrap(args["p_samples"] as? [[String: Any]])
            XCTAssertEqual(samples.count, 1, "delta RPC rejects two versions of one instant in the same batch")
            return .init(inserted: 0, completed: samples.count, unchanged: 0, rejected: 0, affectedDays: [])
        }
        let count = try await f.publisher().replay()
        XCTAssertEqual(count, 2)
        XCTAssertEqual(f.sent.compactMap { ($0["p_samples"] as? [[String: Any]])?.first?["heart"] as? Int }, [61, 65])
        XCTAssertTrue(try f.pending().isEmpty)
    }
}
