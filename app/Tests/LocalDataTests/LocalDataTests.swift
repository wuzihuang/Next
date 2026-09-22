import XCTest
import NextBodyLocalData

final class LocalDataTests: XCTestCase {
    func testPendingOperationAndDocumentSurviveReopenAndCacheEviction() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let operation = LocalOperation(id: "op-1", account: "alice", kind: "meal", payload: Data("meal".utf8))
        do {
            let store = try LocalDataStore(url: url)
            try store.enqueue(operation: operation, documentKey: "meal-1", document: operation.payload)
            try store.writeDocument(account: "alice", key: "home", data: Data("cache".utf8))
            try store.pruneCache(maxBytes: 0)
        }
        let reopened = try LocalDataStore(url: url)
        XCTAssertEqual(try reopened.operations(account: "alice", kind: "meal").map(\.id), ["op-1"])
        XCTAssertEqual(try reopened.readDocument(account: "alice", key: "meal-1"), operation.payload)
        XCTAssertNil(try reopened.readDocument(account: "alice", key: "home"))
        XCTAssertTrue(try reopened.operations(account: "bob", kind: "meal").isEmpty)
        try reopened.acknowledge(account: "bob", id: "op-1")
        XCTAssertEqual(try reopened.operations(account: "alice", kind: "meal").count, 1)
    }
}

extension LocalDataTests {
    func testConflictingRetryRollsBackLocalDocumentAndPreservesOriginalOperation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LocalDataStore(url: url)
        let original = LocalOperation(id: "same", account: "alice", kind: "meal", payload: Data("one".utf8))
        try store.enqueue(operation: original, documentKey: "meal", document: original.payload)
        let conflicting = LocalOperation(id: "same", account: "alice", kind: "meal", payload: Data("two".utf8))
        XCTAssertThrowsError(try store.enqueue(operation: conflicting, documentKey: "meal", document: conflicting.payload))
        XCTAssertEqual(try store.readDocument(account: "alice", key: "meal"), Data("one".utf8))
        XCTAssertEqual(try store.operations(account: "alice", kind: "meal").count, 1)
    }

    func testLegacyImportCanResumeWithoutDuplicatingOperationsOrChangingOrder() throws {
        struct Row: Codable, Equatable { let id: String; let owner: String; let value: Int }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LocalDataStore(url: url)
        let queue = DurableQueue<Row>(kind: "measurement", store: store)
        let rows = [Row(id: "first", owner: "alice", value: 70), Row(id: "second", owner: "alice", value: 71)]
        try queue.save(rows[0], id: "first", account: "alice")
        try queue.importLegacy(rows) { ($0.id,$0.owner) }
        try queue.importLegacy(rows) { ($0.id,$0.owner) }
        XCTAssertEqual(try queue.items(), rows)
        try queue.acknowledge(id: "first", account: "alice")
        XCTAssertEqual(try queue.items(), [rows[1]])
    }

    func testExpiredCacheAndAccountDeletionDoNotExposeOtherAccountData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LocalDataStore(url: url)
        try store.writeDocument(account: "alice", key: "home", data: Data("old".utf8), expiresAt: Date(timeIntervalSince1970: 1))
        XCTAssertNil(try store.readDocument(account: "alice", key: "home"))
        try store.enqueue(operation: LocalOperation(id: "one", account: "alice", kind: "meal", payload: Data("a".utf8)))
        try store.enqueue(operation: LocalOperation(id: "one", account: "bob", kind: "meal", payload: Data("b".utf8)))
        try store.purge(account: "alice")
        XCTAssertEqual(try store.operations(account: "bob", kind: "meal").count, 1)
        XCTAssertTrue(try store.operations(account: "alice", kind: "meal").isEmpty)
    }
}

extension LocalDataTests {
    func testEstimatePromotionKeepsFIFOPositionAndReplacesDurableDocumentAtomically() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LocalDataStore(url: url)
        let estimate = LocalOperation(id: "a", account: "alice", kind: "meal", payload: Data("estimate".utf8))
        try store.enqueue(operation: estimate, documentKey: "meal", document: estimate.payload)
        try store.enqueue(operation: LocalOperation(id: "b", account: "alice", kind: "meal", payload: Data("delete".utf8)))
        let confirmed = Data("confirmed".utf8)
        try store.replaceOperation(estimate, payload: confirmed, documentKey: "meal")
        XCTAssertEqual(try store.operations(account: "alice", kind: "meal").map(\.id), ["a", "b"])
        XCTAssertEqual(try store.readDocument(account: "alice", key: "meal"), confirmed)
        XCTAssertThrowsError(try store.replaceOperation(estimate, payload: Data("stale".utf8), documentKey: "meal"))
    }
}

extension LocalDataTests {
    func testEmptyDocumentsRoundTripAndIdenticalRetryIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LocalDataStore(url: url)
        try store.writeDocument(account: "alice", key: "empty", data: Data())
        XCTAssertEqual(try store.readDocument(account: "alice", key: "empty"), Data())
        let operation = LocalOperation(id: "once", account: "alice", kind: "meal", payload: Data("saved".utf8))
        try store.enqueue(operation: operation)
        try store.enqueue(operation: operation)
        XCTAssertEqual(try store.operations(account: "alice", kind: "meal").count, 1)
        XCTAssertThrowsError(try store.writeDocument(account: "", key: "home", data: Data()))
    }
}

extension LocalDataTests {
    func testRejectedMealSurvivesRestartWhileIndependentMealsContinueAndDependentsWait() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        func op(_ id: String, _ meal: String, replacement: String? = nil) throws -> LocalOperation {
            let body: [String: Any] = replacement.map { ["replacement": ["id": $0]] } ?? [:]
            return LocalOperation(id: id, account: "alice", kind: "meal", payload:
                try JSONSerialization.data(withJSONObject: ["meal_id": meal, "body": body], options: .sortedKeys))
        }
        let failed = try op("create-a", "meal-a")
        let dependent = try op("amend-a", "meal-a", replacement: "meal-a2")
        let independent = try op("create-b", "meal-b")
        do {
            let store = try LocalDataStore(url: url)
            for row in [failed, dependent, independent] { try store.enqueue(operation: row) }
            try store.replaceOperation(failed, payload: MealOutboxPolicy.replacingRejection(failed, message: "Rejected"), documentKey: "meal-a")
        }
        let store = try LocalDataStore(url: url)
        let rows = try store.operations(account: "alice", kind: "meal")
        XCTAssertEqual(try MealOutboxPolicy.runnable(rows).map(\.id), ["create-b"])
        XCTAssertEqual(try MealOutboxPolicy.rejectedChain("create-a", operations: rows).map(\.id), ["create-a", "amend-a"])
        try store.replaceOperation(rows[0], payload: MealOutboxPolicy.replacingRejection(rows[0], message: nil), documentKey: "meal-a")
        XCTAssertEqual(try MealOutboxPolicy.runnable(store.operations(account: "alice", kind: "meal")).map(\.id), ["create-a", "amend-a", "create-b"])
    }
}

extension LocalDataTests {
    func testMealEstimateRequiresAllMacrosBeforeDurablePromotion() throws {
        let operation = LocalOperation(id: UUID().uuidString, account: "alice", kind: "meal",
            payload: try JSONSerialization.data(withJSONObject: ["body": ["user_day": "2026-09-04", "slot": "LUNCH", "name": "Rice"]]))
        let output: [String: Any] = ["draft_id": UUID().uuidString, "name": "Rice and chicken", "kcal": 500,
                                     "protein_g": 30, "carb_g": 65, "fat_g": 12, "confidence": "HIGH"]
        let promoted = try MealOutboxPolicy.promotedEstimate(operation, output: output)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: promoted) as? [String: Any])
        let body = try XCTUnwrap(fields["body"] as? [String: Any])
        XCTAssertEqual(body["protein_g"] as? Int, 30)
        for key in ["protein_g", "carb_g", "fat_g"] {
            XCTAssertThrowsError(try MealOutboxPolicy.promotedEstimate(operation, output: output.filter { $0.key != key }))
            for bad in [NSNumber(value: -1), NSNumber(value: 100000.1), NSNumber(value: true)] {
                XCTAssertThrowsError(try MealOutboxPolicy.promotedEstimate(operation,
                    output: output.merging([key: bad]) { _, value in value }))
            }
        }
        let zeroFat = output.merging(["fat_g": 0]) { _, value in value }
        XCTAssertNoThrow(try MealOutboxPolicy.promotedEstimate(operation, output: zeroFat))
    }
}

extension LocalDataTests {
    func testCanonicalMealRebaseAtomicallyRemapsDependentChangesAndSurvivesReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        func op(_ id: String, _ kind: String, _ body: [String: Any]) throws -> LocalOperation {
            LocalOperation(id: id, account: "alice", kind: "meal", payload: try JSONSerialization.data(withJSONObject:
                ["meal_id": "old", "kind": kind, "body": body], options: .sortedKeys))
        }
        let create = try op("create", "create", ["id": "old", "draft_id": "draft"])
        let amend = try op("amend", "amend", ["meal_id": "old", "replacement": ["id": "replacement"]])
        let delete = try op("delete", "delete", ["meal_id": "old"])
        do {
            let store = try LocalDataStore(url: url)
            for operation in [create, amend, delete] { try store.enqueue(operation: operation) }
            let changes = try [create, amend, delete].map { operation in
                (expected: operation, payload: try MealOutboxPolicy.remappingMeal(operation, from: "old", to: "canonical"), documentKey: "meal.canonical")
            }
            try store.replaceOperations(changes)
            XCTAssertThrowsError(try store.replaceOperations(changes))
        }
        let rows = try LocalDataStore(url: url).operations(account: "alice", kind: "meal")
        XCTAssertEqual(rows.map(\.id), ["create", "amend", "delete"])
        for row in rows {
            let envelope = try MealOutboxPolicy.fields(row)
            XCTAssertEqual(envelope["meal_id"] as? String, "canonical")
            let body = try XCTUnwrap(envelope["body"] as? [String: Any])
            XCTAssertEqual(body[row.id == "create" ? "id" : "meal_id"] as? String, "canonical")
        }
        XCTAssertEqual(try MealOutboxPolicy.fields(rows[0])["canonical_previous_id"] as? String, "old")
        let body = try MealOutboxPolicy.fields(rows[1])["body"] as? [String: Any]
        XCTAssertEqual((body?["replacement"] as? [String: Any])?["id"] as? String, "replacement")
    }
}

extension LocalDataTests {
    func testEvidenceBatchIsDurableOrderedAndRetryIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let operations = (0..<288).map {
            LocalOperation(id: "tick-\($0)", account: "alice", kind: "band-domain", payload: Data("raw-\($0)".utf8))
        }
        do {
            let store = try LocalDataStore(url: url)
            try store.enqueue(operations: operations)
            try store.enqueue(operations: operations)
        }
        let reopened = try LocalDataStore(url: url)
        let saved = try reopened.operations(account: "alice", kind: "band-domain")
        XCTAssertEqual(saved.map(\.id), operations.map(\.id))
        XCTAssertEqual(saved.map(\.payload), operations.map(\.payload))
        try reopened.acknowledge(account: "bob", ids: operations.map(\.id))
        XCTAssertEqual(try reopened.operations(account: "alice", kind: "band-domain").count, 288)
        try reopened.acknowledge(account: "alice", ids: Array(operations.prefix(200)).map(\.id))
        XCTAssertEqual(try reopened.operations(account: "alice", kind: "band-domain").map(\.id), operations.suffix(88).map(\.id))
    }

    func testEvidenceBatchConflictRollsBackEarlierRows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LocalDataStore(url: url)
        let original = LocalOperation(id: "existing", account: "alice", kind: "band-domain", payload: Data("original".utf8))
        try store.enqueue(operation: original)
        let fresh = LocalOperation(id: "fresh", account: "alice", kind: "band-domain", payload: Data("fresh".utf8))
        let conflict = LocalOperation(id: "existing", account: "alice", kind: "band-domain", payload: Data("changed".utf8))
        XCTAssertThrowsError(try store.enqueue(operations: [fresh, conflict]))
        XCTAssertEqual(try store.operations(account: "alice", kind: "band-domain").map(\.id), ["existing"])
        XCTAssertEqual(try store.operations(account: "alice", kind: "band-domain").first?.payload, original.payload)
        let invalid = LocalOperation(id: "invalid", account: "", kind: "band-domain", payload: Data())
        XCTAssertThrowsError(try store.enqueue(operations: [fresh, invalid]))
        XCTAssertEqual(try store.operations(account: "alice", kind: "band-domain").map(\.id), ["existing"])
    }
}

extension LocalDataTests {
    func testObservationDocumentsSurviveReopenEvictionAndAcknowledgement() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let sleep = Data("sleep ending at 13:09".utf8)
        do {
            let store = try LocalDataStore(url: url)
            try store.writeObservationDocument(account: "alice", key: "sleep", data: sleep)
            try store.writeDocument(account: "alice", key: "home", data: Data("summary".utf8))
            try store.enqueue(operation: LocalOperation(id: "sleep", account: "alice", kind: "band-domain", payload: sleep))
            try store.acknowledge(account: "alice", ids: ["sleep"])
            try store.pruneCache(maxBytes: 0)
            try store.removeDocuments(account: "alice")
        }
        let reopened = try LocalDataStore(url: url)
        XCTAssertEqual(try reopened.readObservationDocument(account: "alice", key: "sleep"), sleep)
        XCTAssertEqual(try reopened.observationDocuments(account: "alice"), [sleep])
        XCTAssertTrue(try reopened.operations(account: "alice", kind: "band-domain").isEmpty)
        XCTAssertNil(try reopened.readDocument(account: "alice", key: "home"))
    }

    func testObservationReplacementIsCompleteAndEnumerationIsOrderedWithoutDuplicates() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let replacement = Data(repeating: 42, count: 65_536)
        do {
            let store = try LocalDataStore(url: url)
            try store.writeObservationDocument(account: "alice", key: "z-sleep", data: Data("old".utf8))
            try store.writeObservationDocument(account: "alice", key: "a-respiration", data: Data())
            try store.writeObservationDocument(account: "alice", key: "z-sleep", data: replacement)
            try store.writeObservationDocument(account: "alice", key: "z-sleep", data: replacement)
        }
        let reopened = try LocalDataStore(url: url)
        XCTAssertEqual(try reopened.readObservationDocument(account: "alice", key: "z-sleep"), replacement)
        XCTAssertEqual(try reopened.readObservationDocument(account: "alice", key: "a-respiration"), Data())
        XCTAssertEqual(try reopened.observationDocuments(account: "alice"), [Data(), replacement])
        XCTAssertNil(try reopened.readObservationDocument(account: "alice", key: "missing"))
    }

    func testObservationOwnersAreRequiredAndPurgeIsAccountScoped() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LocalDataStore(url: url)
        XCTAssertThrowsError(try store.writeObservationDocument(account: "", key: "sleep", data: Data()))
        XCTAssertThrowsError(try store.readObservationDocument(account: "", key: "sleep"))
        XCTAssertThrowsError(try store.observationDocuments(account: ""))
        try store.writeObservationDocument(account: "alice", key: "sleep", data: Data("a".utf8))
        try store.writeObservationDocument(account: "bob", key: "sleep", data: Data("b".utf8))
        XCTAssertEqual(try store.observationDocuments(account: "alice"), [Data("a".utf8)])
        XCTAssertEqual(try store.observationDocuments(account: "bob"), [Data("b".utf8)])
        try store.purge(account: "alice")
        XCTAssertNil(try store.readObservationDocument(account: "alice", key: "sleep"))
        XCTAssertTrue(try store.observationDocuments(account: "alice").isEmpty)
        XCTAssertEqual(try store.readObservationDocument(account: "bob", key: "sleep"), Data("b".utf8))
    }
}
