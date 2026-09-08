import XCTest
@testable import NextBodySyncCore
import NextBodyLocalData

final class HealthSnapshotReadTests: XCTestCase {
    @MainActor private final class Fixture {
        enum Failure: Error { case missing(String), unavailable }
        var account = "alice"
        var generation: UInt = 1
        let day = UserDay(date: ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z")!)
        var daily: [[String: Any]] = []
        var tables: [String: [[String: Any]]] = [:]
        var metrics: [String: Any] = ["ok": true, "data": []]
        var status: [[String: Any]] = []
        var calls: [(String, [URLQueryItem])] = []
        var selectOverride: (@MainActor (String, [URLQueryItem]) async throws -> [[String: Any]]?)?
        var statusOverride: (@MainActor () async throws -> [[String: Any]])?
        var metricError: Failure?

        func row(revision: String = "r1") -> [String: Any] {
            ["id": "result-1", "user_day": day.key, "result_revision": revision,
             "fuel_balance_kcal": 550, "computed_at": "2026-09-08T12:00:00Z"]
        }
        func reader() -> HealthSnapshotRead {
            let owner = account, token = generation
            return HealthSnapshotRead(transport: .init(
                select: { [self] table, query in
                    calls.append((table, query))
                    if let result = try await selectOverride?(table, query) { return .init(result) }
                    if table == "daily_results" { return .init(daily) }
                    if table == "raw_samples", let offset = query.first(where: { $0.name == "offset" })?.value,
                       offset != "0" { return .init([]) }
                    return .init(tables[table] ?? [])
                },
                status: { [self] _, _ in
                    if let statusOverride { return .init(try await statusOverride()) }
                    return .init(status)
                },
                metrics: { [self] _, _ in
                    if let metricError { throw metricError }
                    return .init(metrics)
                },
                missingCapability: { error, capability in
                    if case let Failure.missing(name) = error { return name == capability }
                    return false
                }
            ), accepts: { [self] in account == owner && generation == token })
        }
        func formal(_ name: String, value: Any, revision: String = "r1") -> [String: Any] {
            ["metric": name, "points": [["dayKey": day.key, "value": value, "resultRevision": revision]]]
        }
    }

    @MainActor
    func testRawFactsLoadBeforeAnySettlementAndAllPagesAreMerged() async throws {
        let f = Fixture()
        let early = f.day.start.addingTimeInterval(3600), late = f.day.start.addingTimeInterval(7200)
        let previous = f.day.adding(days: -1).start.addingTimeInterval(3600)
        let iso = ISO8601DateFormatter()
        f.selectOverride = { table, query in
            guard table == "raw_samples", let offset = query.first(where: { $0.name == "offset" })?.value else { return nil }
            switch offset {
            case "0": return [["ts": iso.string(from: previous), "heart": 51], ["ts": iso.string(from: early), "heart": 61]]
            case "2": return [["ts": iso.string(from: late), "heart": 71]]
            default: return []
            }
        }
        let snapshot = try await f.reader().detail(days: 0, endingAt: f.day)
        let result = try XCTUnwrap(snapshot)
        var published: [VitalSample] = []
        XCTAssertTrue(result.publish { published = $0.vitals(for: f.day, local: []) })
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(published.compactMap(\.hr), [61, 71])
        XCTAssertEqual(result.vitals(for: f.day.adding(days: -1), local: []).compactMap(\.hr), [51])
        XCTAssertFalse(f.calls.contains { ["day_fuel", "reserve_daily", "daily_training"].contains($0.0) })
        let offsets = f.calls.filter { $0.0 == "raw_samples" }.compactMap { $0.1.first { $0.name == "offset" }?.value }
        XCTAssertEqual(offsets, ["0", "2", "3"])
    }

    @MainActor
    func testAuthoritativeNullCannotRebuildBurnAndReopenedLocalFactsSurvive() async throws {
        let f = Fixture()
        f.daily = [f.row()]; f.status = f.daily
        f.metrics = ["ok": true, "data": [f.formal("burnKcal", value: NSNull()), f.formal("intakeKcal", value: NSNull())]]
        f.tables["day_fuel"] = [["result_id": "result-1", "kcal_in": 1200, "kcal_out": 1800,
                                  "bmr_kcal": 1000, "active_kcal": 800]]
        let tick = f.day.start.addingTimeInterval(3600), later = tick.addingTimeInterval(300)
        let iso = ISO8601DateFormatter()
        f.tables["raw_samples"] = [["ts": iso.string(from: tick), "heart": 60, "hrv": 80,
                                    "domain_sources": ["hrv": ["hrv_valid": true, "observed_at": iso.string(from: tick)]]]]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("health-read-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let samples = [VitalSample(ts: tick, hr: 62, stress: 10, hrv: nil, hrvValid: false, hrvObservedAt: later),
                       VitalSample(ts: later, hr: 64, stress: 15)]
        do {
            let database = try LocalDataStore(url: url)
            try database.writeObservationDocument(account: "alice", key: "band-day:" + f.day.key, data: JSONEncoder().encode(samples))
        }
        let snapshot = try await f.reader().detail(days: 0, endingAt: f.day)
        let result = try XCTUnwrap(snapshot)
        let reopened = try LocalDataStore(url: url)
        let data = try XCTUnwrap(reopened.readObservationDocument(account: "alice", key: "band-day:" + f.day.key))
        let local = try JSONDecoder().decode([VitalSample].self, from: data)
        var displayed: [VitalSample] = []
        result.publish { displayed = $0.vitals(for: f.day, local: local) }
        XCTAssertEqual(displayed.compactMap(\.hr), [62, 64])
        XCTAssertNil(displayed.first?.hrv)
        XCTAssertEqual(displayed.first?.hrvValid, false)
        let energy = result.energy(day: f.day.key, legacy: try XCTUnwrap(result.fuel.first))
        XCTAssertNil(energy.intake); XCTAssertNil(energy.burn); XCTAssertNil(energy.balance)
        XCTAssertNil(energy.resting); XCTAssertNil(energy.active)
        XCTAssertNil(try reopened.readObservationDocument(account: "bob", key: "band-day:" + f.day.key))
    }

    @MainActor
    func testSlowerPreviousReadCannotPublishOverNewRequest() async throws {
        let f = Fixture()
        f.daily = [f.row()]; f.status = f.daily
        var release: CheckedContinuation<Void, Never>?
        var first = true
        f.selectOverride = { table, _ in
            guard table == "daily_results", first else { return nil }
            first = false
            await withCheckedContinuation { release = $0 }
            return [f.row(revision: "stale")]
        }
        let oldReader = f.reader()
        let task = Task { @MainActor in try await oldReader.detail(days: 0, endingAt: f.day) }
        while release == nil { await Task.yield() }
        f.generation += 1
        let current = try await f.reader().detail(days: 0, endingAt: f.day)
        var publications = 0
        try XCTUnwrap(current).publish { _ in publications += 1 }
        release?.resume()
        do { _ = try await task.value; XCTFail("The old response must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(publications, 1)
    }

    @MainActor
    func testAccountChangeBetweenReadAndPublicationCannotPaintOrPersist() async throws {
        let f = Fixture()
        let snapshot = try await f.reader().detail(days: 0, endingAt: f.day)
        f.account = "bob"
        var persisted = false
        XCTAssertFalse(try XCTUnwrap(snapshot).publish { _ in persisted = true })
        XCTAssertFalse(persisted)
    }

    @MainActor
    func testFormalRevisionMismatchRejectsWholeReadButIndependentSleepRevisionIsAllowed() async throws {
        let f = Fixture(); f.daily = [f.row()]; f.status = f.daily
        f.metrics = ["ok": true, "data": [f.formal("burnKcal", value: 123, revision: "r2")]]
        do { _ = try await f.reader().detail(days: 0, endingAt: f.day); XCTFail("Mismatched revision") }
        catch { XCTAssertEqual(error as? HealthSnapshotRead.Failure, .revisionChanged) }
        f.metrics = ["ok": true, "data": [f.formal("sleepMinutes", value: 480, revision: "night-2")]]
        let valid = try await f.reader().detail(days: 0, endingAt: f.day)
        XCTAssertNotNil(valid)
    }

    @MainActor
    func testChangedCalculationAfterChildReadsRejectsWholeSnapshot() async throws {
        let f = Fixture(); f.daily = [f.row()]; f.status = [f.row(revision: "r2")]
        do { _ = try await f.reader().detail(days: 0, endingAt: f.day); XCTFail("A re-settled child set cannot publish") }
        catch { XCTAssertEqual(error as? HealthSnapshotRead.Failure, .revisionChanged) }
    }

    @MainActor
    func testSummaryRevisionsAreRememberedOnlyWhenPublicationSucceeds() async throws {
        let f = Fixture(); f.daily = [f.row()]; f.status = f.daily
        var known: [String: String] = [:]
        let pending = try await f.reader().summaries(days: 182, endingAt: f.day, known: known,
            cachedDays: [f.day.key], didPublish: { known = $0 })
        XCTAssertTrue(known.isEmpty)
        f.generation += 1
        XCTAssertFalse(try XCTUnwrap(pending).publish { _ in XCTFail("Stale summary") })
        XCTAssertTrue(known.isEmpty)
        let current = try await f.reader().summaries(days: 182, endingAt: f.day, known: known,
            cachedDays: [f.day.key], didPublish: { known = $0 })
        XCTAssertTrue(try XCTUnwrap(current).publish { _ in })
        XCTAssertEqual(known[f.day.key], "r1")
        let callsBefore = f.calls.count
        let unchanged = try await f.reader().summaries(days: 182, endingAt: f.day, known: known,
            cachedDays: [f.day.key], didPublish: { known = $0 })
        XCTAssertNil(unchanged)
        XCTAssertEqual(callsBefore, f.calls.count)
    }

    @MainActor
    func testMissingLegacyColumnsCanBeRemovedInEitherOrderWithoutMaskingFailures() async throws {
        for revisionFirst in [true, false] {
            let f = Fixture(); f.daily = [f.row()]
            f.metricError = .missing("metric-read")
            f.tables["day_fuel"] = [["result_id": "result-1", "kcal_in": "500", "kcal_out": 1800,
                                      "bmr_kcal": 1000, "active_kcal": 200]]
            f.selectOverride = { table, query in
                guard table == "daily_results" else { return nil }
                let columns = query.first { $0.name == "select" }?.value ?? ""
                if revisionFirst, columns.contains("result_revision") { throw Fixture.Failure.missing("result_revision") }
                if columns.contains("worn") { throw Fixture.Failure.missing("worn") }
                if columns.contains("result_revision") { throw Fixture.Failure.missing("result_revision") }
                return nil
            }
            let loaded = try await f.reader().detail(days: 0, endingAt: f.day)
            let snapshot = try XCTUnwrap(loaded)
            XCTAssertFalse(snapshot.hasFormalMetrics)
            XCTAssertEqual(snapshot.value("deltaKcal", day: f.day.key, legacy: "550"), 550)
            let energy = snapshot.energy(day: f.day.key, legacy: try XCTUnwrap(snapshot.fuel.first))
            XCTAssertEqual(energy.burn, 1200)
            XCTAssertEqual(energy.balance, -700)
            XCTAssertEqual(f.calls.filter { $0.0 == "daily_results" }.count, 3)
        }
        let failed = Fixture()
        failed.selectOverride = { table, _ in
            if table == "daily_results" { throw Fixture.Failure.unavailable }
            return nil
        }
        do { _ = try await failed.reader().detail(days: 0, endingAt: failed.day); XCTFail("Failure is not a legacy capability") }
        catch { XCTAssertTrue(error is Fixture.Failure) }
        XCTAssertEqual(failed.calls.count, 1)
    }

    @MainActor
    func testOptionalTablesCanLagWhileMalformedFormalReadFailsClosed() async throws {
        let f = Fixture()
        f.selectOverride = { table, _ in
            if ["sleep_nights", "oxygen_samples", "response_samples"].contains(table) { throw Fixture.Failure.unavailable }
            return nil
        }
        let loaded = try await f.reader().detail(days: 0, endingAt: f.day)
        let snapshot = try XCTUnwrap(loaded)
        XCTAssertNil(snapshot.nights); XCTAssertNil(snapshot.oxygen); XCTAssertNil(snapshot.response)
        f.metrics = ["ok": false, "data": []]
        do { _ = try await f.reader().detail(days: 0, endingAt: f.day); XCTFail("Malformed formal result") }
        catch { XCTAssertEqual(error as? HealthSnapshotRead.Failure, .unavailable) }
    }
}
