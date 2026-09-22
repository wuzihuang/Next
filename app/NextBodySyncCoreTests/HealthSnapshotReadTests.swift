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
        var metricError: Error?

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
                    if capability == "meal_fields" { return HealthSnapshotRead.isMissingMealFields(error) }
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
    func testMissingPlateColumnsStillPublishesTodaysTrainingStepsAndCanonicalMeals() async throws {
        for response in [
            #"{"code":"42703","message":"column meals.meal_group_id does not exist"}"#,
            #"{"code":"PGRST204","message":"Could not find the 'sodium_mg' column of 'meals' in the schema cache"}"#,
        ] {
            let f = Fixture(); f.daily = [f.row()]; f.status = f.daily
            f.daily[0]["training_load"] = 8.4
            f.daily[0]["reserve_score"] = 20
            f.tables["reserve_daily"] = [["result_id": "result-1", "current_value": 20,
                "drain_drivers": ["observed_at": "2026-09-08T11:55:00Z"]]]
            f.tables["daily_training"] = [["result_id": "result-1", "recorded_steps": 4200,
                "evidence": ["target": ["version": "target-1.0", "target": 12.4, "lower": 10.9, "upper": 13.9]]]]
            f.tables["raw_samples"] = [["ts": ISO8601DateFormatter().string(from: f.day.start.addingTimeInterval(300)), "step": 120]]
            let mealID = "11111111-1111-4111-8111-111111111111"
            f.selectOverride = { table, query in
                guard table == "meals" else { return nil }
                if query.first(where: { $0.name == "select" })?.value?.contains("meal_group_id") == true {
                    throw SupabaseFailure.http(400, response)
                }
                return [["id": mealID, "user_day": f.day.key, "slot": "LUNCH", "kcal": 200, "text_input": "Rice"]]
            }
            let loaded = try await f.reader().detail(days: 0, endingAt: f.day)
            let result = try XCTUnwrap(loaded)
            XCTAssertTrue(result.publish { snapshot in
                XCTAssertEqual(snapshot.rows.first?["training_load"] as? Double, 8.4)
                XCTAssertEqual(snapshot.rows.first?["reserve_score"] as? Int, 20)
                XCTAssertEqual(snapshot.reserve.first?["current_value"] as? Int, 20)
                XCTAssertEqual(snapshot.training.first?["recorded_steps"] as? Int, 4200)
                XCTAssertEqual(snapshot.vitals(for: f.day, local: []).first?.steps, 120)
                XCTAssertEqual(snapshot.meals.first?["id"] as? String, mealID)
                XCTAssertNil(snapshot.meals.first?["meal_group_id"])
                XCTAssertNil(snapshot.meals.first?["fiber_g"])
            })
            let reads = f.calls.filter { $0.0 == "meals" }.map(\.1)
            XCTAssertEqual(reads.count, 2)
            XCTAssertEqual(reads[0].filter { $0.name != "select" }, reads[1].filter { $0.name != "select" })
            XCTAssertEqual(reads[1].first { $0.name == "select" }?.value,
                "id,user_day,slot,logged_at,text_input,kcal,protein_g,carb_g,fat_g")
        }
    }

    @MainActor
    func testMealReadOnlyFallsBackForExplicitMissingNewColumnsAndNeverHidesRetryFailure() async throws {
        let missing = #"{"code":"42703","message":"column meals.meal_group_id does not exist"}"#
        let errors: [Error] = [
            SupabaseFailure.http(401, missing), SupabaseFailure.http(403, missing),
            SupabaseFailure.http(503, missing), SupabaseFailure.http(400, "meal_group_id unavailable"),
            SupabaseFailure.http(400, #"{"code":"42501","message":"permission denied for column meal_group_id"}"#),
            SupabaseFailure.http(400, #"{"code":"42703","message":"column meals.kcal does not exist"}"#),
            SupabaseFailure.http(400, #"{"code":"PGRST204","message":"Could not find the 'photo_path' column of 'profiles' in the schema cache"}"#),
            URLError(.notConnectedToInternet), CancellationError(),
        ]
        for error in errors {
            let f = Fixture()
            f.selectOverride = { table, _ in
                guard table == "meals" else { return nil }
                throw error
            }
            do {
                _ = try await f.reader().detail(days: 0, endingAt: f.day)
                XCTFail("An arbitrary meal read failure must not publish a snapshot")
            } catch { }
            XCTAssertEqual(f.calls.filter { $0.0 == "meals" }.count, 1)
        }
        let f = Fixture()
        var attempts = 0
        f.selectOverride = { table, _ in
            guard table == "meals" else { return nil }
            attempts += 1
            throw SupabaseFailure.http(attempts == 1 ? 400 : 403, attempts == 1 ? missing : "denied")
        }
        do {
            _ = try await f.reader().detail(days: 0, endingAt: f.day)
            XCTFail("The legacy retry cannot swallow its own authorization failure")
        } catch {
            guard case let SupabaseFailure.http(status, _) = error else { return XCTFail("Lost HTTP failure") }
            XCTAssertEqual(status, 403)
        }
        XCTAssertEqual(attempts, 2)
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
    func testDetailAndHistoricalSummariesReadTheSamePublishedTrainingTarget() async throws {
        let f = Fixture()
        var yesterday = f.row()
        yesterday["id"] = "result-yesterday"
        yesterday["user_day"] = f.day.adding(days: -1).key
        f.daily = [yesterday, f.row()]
        f.status = f.daily
        f.tables["daily_training"] = [
            ["result_id": "result-1", "evidence": ["target": [
                "version": "target-1.0", "target": 12.4, "lower": 10.9, "upper": 13.9]]],
            ["result_id": "result-yesterday", "evidence": ["target": [
                "version": "target-1.0", "target": NSNull()]]],
        ]
        let detail = try await f.reader().detail(days: 1, endingAt: f.day)
        f.calls = []
        let summary = try await f.reader().summaries(days: 30, endingAt: f.day,
            known: [:], cachedDays: [], didPublish: { _ in })
        let detailRows = try XCTUnwrap(detail).training
        let summaryRows = try XCTUnwrap(summary).training
        for id in ["result-1", "result-yesterday"] {
            let detailed = TrainingSettlement(evidence: detailRows.first { $0["result_id"] as? String == id }?["evidence"] as? [String: Any])
            let summarized = TrainingSettlement(evidence: summaryRows.first { $0["result_id"] as? String == id }?["evidence"] as? [String: Any])
            XCTAssertEqual(detailed, summarized)
            XCTAssertNotNil(summarized.target)
            if id == "result-yesterday" {
                XCTAssertNil(summarized.recommendation(legacyTarget: 18, legacyZone: 16...20).target)
            }
        }
        let trainingColumns = f.calls.filter { $0.0 == "daily_training" }
            .compactMap { $0.1.first { $0.name == "select" }?.value }
        XCTAssertEqual(trainingColumns, ["result_id,recorded_steps,evidence"])
        XCTAssertFalse(trainingColumns.contains { $0.contains("curve") })
    }

    @MainActor
    func testTrainingEvidenceFailureIsNotMistakenForAnOlderTargetAlgorithm() async throws {
        let f = Fixture(); f.daily = [f.row()]; f.status = f.daily
        f.selectOverride = { table, query in
            if table == "daily_training", query.contains(where: { $0.value?.contains("evidence") == true }) {
                throw Fixture.Failure.unavailable
            }
            return nil
        }
        do {
            _ = try await f.reader().detail(days: 0, endingAt: f.day)
            XCTFail("A failed authoritative read must retain the previous snapshot")
        } catch { XCTAssertTrue(error is Fixture.Failure) }
        do {
            _ = try await f.reader().summaries(days: 30, endingAt: f.day,
                known: [:], cachedDays: [], didPublish: { _ in })
            XCTFail("Summaries cannot replace an unavailable target with the legacy target")
        } catch { XCTAssertTrue(error is Fixture.Failure) }
        f.selectOverride = { table, query in
            if table == "daily_training", query.contains(where: { $0.value?.contains("evidence") == true }) {
                throw Fixture.Failure.missing("training_evidence")
            }
            return nil
        }
        let legacy = try await f.reader().detail(days: 0, endingAt: f.day)
        XCTAssertNotNil(legacy)
    }

    @MainActor
    func testMissingLegacyColumnsCanBeRemovedInEitherOrderWithoutMaskingFailures() async throws {
        for revisionFirst in [true, false] {
            let f = Fixture(); f.daily = [f.row()]
            f.metricError = Fixture.Failure.missing("metric-read")
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
    func testSupabaseHTTPConflictRetainsThePriorSnapshotAcrossRequiredReadPaths() async throws {
        for source in ["metrics", "status", "daily_results"] {
            let f = Fixture(); f.daily = [f.row()]; f.status = f.daily
            let conflict = SupabaseFailure.http(409, #"{"ok":false,"code":"SNAPSHOT_CHANGED"}"#)
            if source == "metrics" { f.metricError = conflict }
            if source == "status" { f.statusOverride = { throw conflict } }
            if source == "daily_results" {
                f.selectOverride = { table, _ in
                    if table == "daily_results" { throw conflict }
                    return nil
                }
            }
            do {
                let result = try await f.reader().detail(days: 0, endingAt: f.day)
                result?.publish { _ in XCTFail("A conflicted read cannot replace the prior screen") }
                XCTFail("Expected a typed revision conflict from \(source)")
            } catch { XCTAssertEqual(error as? HealthSnapshotRead.Failure, .revisionChanged) }
        }
        // A real HTTP failure must not be relabelled as a harmless revision conflict.
        let unavailable = Fixture()
        unavailable.metricError = SupabaseFailure.http(503, "database unavailable")
        do { _ = try await unavailable.reader().detail(days: 0, endingAt: unavailable.day); XCTFail("Expected HTTP failure") }
        catch {
            guard case let SupabaseFailure.http(status, body) = error else { return XCTFail("HTTP error lost its type") }
            XCTAssertEqual(status, 503); XCTAssertEqual(body, "database unavailable")
        }
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
    /// The hand parser must agree with the formatters it replaced on every shape the server
    /// sends, and stay quiet on the ones it does not understand.
    func testTimestampFastPathMatchesFormatters() {
        let strict = ISO8601DateFormatter(); strict.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let micro = DateFormatter(); micro.locale = Locale(identifier: "en_US_POSIX")
        micro.timeZone = TimeZone(secondsFromGMT: 0); micro.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        let naive = DateFormatter(); naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = TimeZone(secondsFromGMT: 0); naive.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let cases: [(String, Date?)] = [
            ("2026-09-08T12:00:00Z", plain.date(from: "2026-09-08T12:00:00Z")),
            ("2026-09-08T12:00:01.123Z", strict.date(from: "2026-09-08T12:00:01.123Z")),
            ("2026-09-08T12:00:01+08:00", plain.date(from: "2026-09-08T12:00:01+08:00")),
            ("2026-09-08T01:23:45.123456+00:00", micro.date(from: "2026-09-08T01:23:45.123456+00:00")),
            ("2026-03-01T00:00:00", naive.date(from: "2026-03-01T00:00:00")),
            ("2024-02-29T23:59:59-05:30", plain.date(from: "2024-02-29T23:59:59-05:30")),
            ("1999-12-31T23:59:59Z", plain.date(from: "1999-12-31T23:59:59Z")),
        ]
        for (raw, expected) in cases {
            let got = HealthSnapshotRead.timestamp(raw)
            XCTAssertNotNil(expected, raw)
            XCTAssertNotNil(got, raw)
            XCTAssertEqual(got?.timeIntervalSince1970 ?? -1, expected?.timeIntervalSince1970 ?? -2, accuracy: 0.0005, raw)
            XCTAssertEqual(ISOTimestamp.parse(raw)?.timeIntervalSince1970 ?? -1,
                           expected?.timeIntervalSince1970 ?? -2, accuracy: 0.0005, "fast path · \(raw)")
        }
        for junk in ["", "2026-09-08", "2026-13-08T12:00:00Z", "2026-09-08T25:00:00Z", "not a date",
                     "2026-09-08T12:00:00Zjunk", "2026-09-08T12:00:00.Z"] {
            XCTAssertNil(ISOTimestamp.parse(junk), junk)
        }
    }

}
