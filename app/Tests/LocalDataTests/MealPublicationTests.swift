import XCTest
import NextBodyLocalData

final class MealPublicationTests: XCTestCase {
    @MainActor private final class Fixture {
        enum Failure: Error { case offline, disk }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var local: LocalDataStore
        var current = true
        var consent = true
        var sent: [[String: Any]] = []
        var projected: [[LocalOperation]] = []
        var transport: (@MainActor (String, [String: Any]) async throws -> [String: Any])?
        var save: (@MainActor () throws -> Void)?
        let at = ISO8601DateFormatter().date(from: "2026-09-08T12:30:00Z")!
        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            local = try LocalDataStore(url: directory.appendingPathComponent("meals.sqlite"))
        }
        func close() { try? FileManager.default.removeItem(at: directory) }
        func reopen() throws { local = try LocalDataStore(url: directory.appendingPathComponent("meals.sqlite")) }
        func pending() throws -> [LocalOperation] { try local.operations(account: "alice", kind: "meal") }
        func publisher() -> MealPublication {
            MealPublication(account: "alice", local: local, isCurrent: { self.current }, consent: { self.consent },
                send: { endpoint, body, owner in
                    XCTAssertEqual(owner, "alice")
                    self.sent.append(body)
                    if let transport = self.transport { return try await transport(endpoint, body) }
                    return self.receipt(body)
                }, persistProjection: {
                    try self.save?()
                    self.projected.append(try self.pending())
                })
        }
        func receipt(_ body: [String: Any]) -> [String: Any] {
            let id = body["id"] ?? body["meal_id"] ?? ""
            return ["id": id, "meal_id": id,
                "client_op_id": body["draft_id"] ?? body["operation_id"] ?? "",
                "operation_id": body["operation_id"] ?? body["draft_id"] ?? ""]
        }
        @discardableResult func manual(_ publisher: MealPublication? = nil, id: UUID = UUID()) throws -> MealPublication.Submitted {
            try (publisher ?? self.publisher()).createManual(id: id, day: "2026-09-08", slot: "LUNCH", name: "Rice", kcal: 500, at: at)
        }
    }

    @MainActor func testFractionalNutrientsSurviveDiskProjectionAndReplay() async throws {
        let f = try Fixture(); defer { f.close() }
        let id = UUID()
        _ = try f.publisher().create(id: id, fields: [
            "draft_id": id.uuidString.lowercased(),
            "user_day": "2026-09-08", "slot": "LUNCH", "name": "Yoghurt",
            "kcal": 123.4, "protein_g": 23.6, "carb_g": 8.2, "fat_g": 2.5,
            "fiber_g": 1.3, "sodium_mg": 45.7,
        ], source: "TYPED")
        try f.reopen()
        let meal = try XCTUnwrap(f.publisher().projection().meals.first)
        XCTAssertEqual(meal.kcal, 123.4)
        XCTAssertEqual(meal.protein, 23.6)
        XCTAssertEqual(meal.fiber, 1.3)
        XCTAssertNil(meal.sugar)
        let result = try await f.publisher().replay()
        XCTAssertEqual(result.acknowledged, 1)
        XCTAssertEqual((f.sent.last?["protein_g"] as? NSNumber)?.doubleValue, 23.6)
        XCTAssertEqual((f.sent.last?["sodium_mg"] as? NSNumber)?.doubleValue, 45.7)
    }

    @MainActor func testFractionalDraftPromotesWithoutDroppingMicronutrients() throws {
        let f = try Fixture(); defer { f.close() }
        let submitted = try f.publisher().confirmDraft(day: "2026-09-08", slot: "LUNCH", output: [
            "draft_id": UUID().uuidString.lowercased(), "name": "Soup", "kcal": 123.4,
            "macros": ["p": 23.6, "c": 8.2, "f": 2.5], "micros": ["fiber": 1.3, "sodium": 45.7],
        ], at: f.at)
        XCTAssertEqual((submitted.fields["protein_g"] as? NSNumber)?.doubleValue, 23.6)
        XCTAssertEqual((submitted.fields["fiber_g"] as? NSNumber)?.doubleValue, 1.3)
        XCTAssertNil(submitted.fields["sugar_g"])
    }

    @MainActor func testNutrientsRejectBooleanAndNonfiniteValuesBeforeQueueing() throws {
        let f = try Fixture(); defer { f.close() }
        for bad in [true as Any, Double.nan, Double.infinity, -0.1, 100000.1] {
            XCTAssertThrowsError(try f.publisher().create(id: UUID(), fields: [
                "draft_id": UUID().uuidString.lowercased(), "user_day": "2026-09-08",
                "slot": "LUNCH", "name": "Soup", "kcal": 123.4,
                "protein_g": bad, "carb_g": 8.2, "fat_g": 2.5,
            ]))
        }
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testExplicitZeroCalorieFoodSurvivesProjectionAndReplay() async throws {
        let f = try Fixture(); defer { f.close() }
        let publisher = f.publisher()
        _ = try publisher.createManual(day: "2026-09-08", slot: "LUNCH", name: "Water", kcal: 0, at: f.at)
        XCTAssertEqual(try publisher.projection().meals.first?.kcal, 0)
        try f.reopen()
        let result = try await f.publisher().replay()
        XCTAssertEqual(result.acknowledged, 1)
        XCTAssertEqual(f.sent.last?["kcal"] as? Int, 0)
    }

    @MainActor func testManualMealIsDurableBeforeNetworkAndReplaysAfterReopen() async throws {
        let f = try Fixture(); defer { f.close() }
        let meal = try f.manual()
        XCTAssertTrue(f.sent.isEmpty)
        XCTAssertEqual(try f.pending().count, 1)
        f.transport = { _, _ in throw Fixture.Failure.offline }
        do { _ = try await f.publisher().replay(); XCTFail("Expected offline") } catch Fixture.Failure.offline { }
        try f.reopen()
        f.transport = nil
        let result = try await f.publisher().replay()
        XCTAssertEqual(result.acknowledged, 1)
        XCTAssertEqual(f.sent[0]["draft_id"] as? String, meal.id.uuidString.lowercased())
        XCTAssertEqual(f.sent[0]["logged_at"] as? String, "2026-09-08T12:30:00Z")
        XCTAssertEqual(f.sent[0]["draft_id"] as? String, f.sent[1]["draft_id"] as? String)
        XCTAssertEqual(f.projected[0].count, 1, "Save the accepted projection before removing the pending record")
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testDraftMustBeCompleteAndUsesTheSameDurablePathAsManual() async throws {
        let f = try Fixture(); defer { f.close() }
        let draft = UUID().uuidString.lowercased()
        let fields: [String: Any] = ["draft_id": draft, "name": "Soup", "kcal": 250]
        do {
            _ = try f.publisher().confirmDraft(day: "2026-09-08", slot: "LUNCH", output: fields, at: f.at)
            XCTFail("Incomplete draft must not become a meal")
        } catch { }
        XCTAssertTrue(try f.pending().isEmpty)
        let output = fields.merging(["macros": ["p": 10, "c": 30, "f": 8]]) { _, new in new }
        let submitted = try f.publisher().confirmDraft(day: "2026-09-08", slot: "LUNCH", output: output, at: f.at)
        XCTAssertEqual(submitted.fields["protein_g"] as? Int, 10)
        try f.manual()
        let result = try await f.publisher().replay()
        XCTAssertEqual(result.acknowledged, 2)
        XCTAssertEqual(f.sent[0]["draft_id"] as? String, draft)
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testLostReplyAfterCommitDoesNotCreateAnotherMeal() async throws {
        let f = try Fixture(); defer { f.close() }
        try f.manual()
        var committed = Set<String>()
        var lost = true
        f.transport = { _, body in
            committed.insert(body["draft_id"] as! String)
            if lost { lost = false; throw Fixture.Failure.offline }
            return f.receipt(body)
        }
        do { _ = try await f.publisher().replay(); XCTFail("Expected lost response") } catch Fixture.Failure.offline { }
        try f.reopen()
        _ = try await f.publisher().replay()
        XCTAssertEqual(committed.count, 1)
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testProjectionFailureKeepsAcknowledgedMealUntilItCanBeSaved() async throws {
        let f = try Fixture(); defer { f.close() }
        try f.manual()
        f.save = { throw Fixture.Failure.disk }
        do { _ = try await f.publisher().replay(); XCTFail("Expected disk failure") } catch Fixture.Failure.disk { }
        XCTAssertEqual(try f.pending().count, 1)
        f.save = nil
        _ = try await f.publisher().replay()
        XCTAssertEqual(f.sent.count, 2)
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testRejectionBlocksDependentAmendmentButNotAnotherMeal() async throws {
        let f = try Fixture(); defer { f.close() }
        let first = try f.manual()
        var replacement = first.fields
        replacement["id"] = UUID().uuidString.lowercased(); replacement.removeValue(forKey: "draft_id")
        _ = try f.publisher().amend(id: first.id, replacement: replacement)
        try f.manual()
        f.transport = { _, body in
            if body["id"] as? String == first.id.uuidString.lowercased() {
                throw MealPublication.Failure.http(422, "{}")
            }
            return f.receipt(body)
        }
        let result = try await f.publisher().replay()
        XCTAssertEqual(result.acknowledged, 1)
        XCTAssertEqual(f.sent.count, 2)
        XCTAssertEqual(try f.pending().count, 2)
        XCTAssertNotNil(try MealOutboxPolicy.rejection(f.pending()[0]))
    }

    @MainActor func testCanonicalReceiptRebasesDependentChangesBeforeSavingAndRetiring() async throws {
        let f = try Fixture(); defer { f.close() }
        let created = try f.manual()
        try f.publisher().delete(id: created.id)
        let canonical = UUID().uuidString.lowercased()
        f.transport = { _, body in
            if let draft = body["draft_id"] {
                return ["id": canonical, "meal_id": canonical, "requested_meal_id": body["id"]!, "client_op_id": draft]
            }
            XCTAssertEqual(body["meal_id"] as? String, canonical)
            return f.receipt(body)
        }
        let result = try await f.publisher().replay()
        XCTAssertEqual(result.acknowledged, 2)
        let projected = try MealOutboxPolicy.fields(f.projected[0][0])
        XCTAssertEqual(projected["canonical_previous_id"] as? String, created.id.uuidString.lowercased())
        XCTAssertTrue(try f.pending().isEmpty)
    }

    @MainActor func testSessionChangeWhileRequestIsAwayCannotRetireOrRejectOldWork() async throws {
        for status in [200, 422] {
            let f = try Fixture(); defer { f.close() }
            try f.manual()
            f.transport = { _, body in
                f.current = false
                if status == 422 { throw MealPublication.Failure.http(422, "{}") }
                return f.receipt(body)
            }
            do { _ = try await f.publisher().replay(); XCTFail("Expected invalid session") } catch is CancellationError { }
            XCTAssertEqual(try f.pending().count, 1)
            XCTAssertNil(try MealOutboxPolicy.rejection(f.pending()[0]))
            XCTAssertTrue(f.projected.isEmpty)
        }
    }

    @MainActor func testWithdrawalPausesCollectionButPermitsExplicitDeletion() async throws {
        let f = try Fixture(); defer { f.close() }
        try f.manual()
        f.consent = false
        try f.publisher().delete(id: UUID())
        do { try f.manual(); XCTFail("Expected collection pause") } catch MealPublication.Failure.collectionPaused { }
        let result = try await f.publisher().replay()
        XCTAssertEqual(result.acknowledged, 1)
        XCTAssertEqual(f.sent.count, 1)
        XCTAssertEqual(f.sent[0]["kind"] as? String, "delete")
        XCTAssertEqual(try f.pending().count, 1)
    }

    @MainActor func testWithdrawalAfterServerResponseKeepsTheOriginalOperation() async throws {
        let f = try Fixture(); defer { f.close() }
        try f.manual()
        f.transport = { _, body in f.consent = false; return f.receipt(body) }
        do { _ = try await f.publisher().replay(); XCTFail("Expected collection pause") } catch MealPublication.Failure.collectionPaused { }
        XCTAssertEqual(try f.pending().count, 1)
        XCTAssertTrue(f.projected.isEmpty)
    }

    @MainActor func testNewArrivalsWaitForTheNextReplayAndWrongReceiptRetainsWork() async throws {
        let f = try Fixture(); defer { f.close() }
        try f.manual()
        f.transport = { _, body in try f.manual(); return f.receipt(body) }
        let result = try await f.publisher().replay()
        XCTAssertEqual(result.acknowledged, 1)
        XCTAssertEqual(try f.pending().count, 1)
        f.transport = { _, _ in ["client_op_id": UUID().uuidString] }
        do { _ = try await f.publisher().replay(); XCTFail("Expected invalid acknowledgment") } catch MealPublication.Failure.invalidAcknowledgment { }
        XCTAssertEqual(try f.pending().count, 1)
    }

    @MainActor func testActualProjectionPreservesSourcesAndRevisionsAcrossAmendmentAndReopen() async throws {
        let f = try Fixture(); defer { f.close() }
        let manual = try f.manual()
        let draft = try f.publisher().confirmDraft(day: "2026-09-08", slot: "DINNER", output: [
            "draft_id": UUID().uuidString, "source": "photo", "name": "Soup", "kcal": 250,
            "protein_g": 10, "carb_g": 30, "fat_g": 8,
        ], at: f.at)
        var replacement = draft.fields
        replacement.removeValue(forKey: "draft_id")
        let replacementID = UUID()
        replacement["id"] = replacementID.uuidString.lowercased()
        _ = try f.publisher().amend(id: draft.id, replacement: replacement, source: "PHOTO", revisions: 2)
        try f.reopen()
        let projected = try f.publisher().projection()
        XCTAssertEqual(projected.removedIDs, [draft.id])
        let restoredManual = try XCTUnwrap(projected.meals.first { $0.id == manual.id })
        XCTAssertEqual(restoredManual.source, "TYPED")
        XCTAssertEqual(restoredManual.revisions, 0)
        let restoredAmendment = try XCTUnwrap(projected.meals.first { $0.id == replacementID })
        XCTAssertEqual(restoredAmendment.source, "PHOTO")
        XCTAssertEqual(restoredAmendment.revisions, 2)
        XCTAssertEqual(restoredAmendment.at, f.at)
        f.transport = { _, body in
            XCTAssertNil(body["source"])
            XCTAssertNil(body["revisions"])
            if let replacement = body["replacement"] as? [String: Any] {
                XCTAssertNil(replacement["source"])
                XCTAssertNil(replacement["revisions"])
            }
            return f.receipt(body)
        }
        let result = try await f.publisher().replay()
        XCTAssertEqual(result.acknowledged, 3)
    }
}
