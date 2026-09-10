import XCTest
@testable import NextBodyPlanCore

final class DailyAdviceTests: XCTestCase {
    private func row(_ tasks: [[String: Any]]) -> [String: Any] {
        ["title": "Your latest suggestions", "summary": "Based on available readings.", "tasks": tasks]
    }

    func testInsufficientEvidenceCanProduceZeroSuggestions() throws {
        let result = try XCTUnwrap(DailyPlan(row: row([]), dayKey: "2026-09-08"))
        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertEqual(result.dayKey, "2026-09-08")
        XCTAssertEqual(result.summary, "Based on available readings.")
    }

    func testLongSuggestionsAreNotTruncated() throws {
        let title = String(repeating: "恢复", count: 24)
        let advice = String(repeating: "具体建议及适用条件。", count: 36)
        let basis = String(repeating: "最近的数据证据。", count: 30)
        let result = try XCTUnwrap(DailyPlan(row: row([
            ["id": "recovery", "title": title, "sub": advice, "basis": basis],
        ])))
        XCTAssertEqual(result.tasks.first?.title, title)
        XCTAssertEqual(result.tasks.first?.sub, advice)
        XCTAssertEqual(result.tasks.first?.basis, basis)
    }

    func testMalformedItemsCannotMasqueradeAsEmptyEvidence() {
        XCTAssertNil(DailyPlan(row: row([["id": "missing-copy"]])))
        XCTAssertNil(DailyPlan(row: row([["id": "", "title": "Advice", "sub": "Try this."]])))
    }

    func testDuplicateIdentifiersAndMoreThanFiveAreRejected() {
        let item: [String: Any] = ["id": "same", "title": "Advice", "sub": "Try this."]
        XCTAssertNil(DailyPlan(row: row([item, item])))
        XCTAssertNil(DailyPlan(row: row((0..<6).map {
            ["id": "\($0)", "title": "Advice", "sub": "Try this."]
        })))
        XCTAssertEqual(DailyPlan(row: row((0..<5).map {
            ["id": "\($0)", "title": "Advice", "sub": "Try this."]
        }))?.tasks.count, 5)
    }

    func testSourcesSurviveStoredRowsAndAggregateWithoutUnsafeLinksOrDuplicates() throws {
        let source = ["title": "NIH", "url": "https://ods.od.nih.gov/"]
        var payload = row([
            ["id": "nutrition", "title": "Advice", "sub": "Context", "sources": [source]],
            ["id": "recovery", "title": "Advice", "sub": "Context", "sources": [source]],
        ])
        payload["web_sources"] = [source,
            ["title": "Unsafe", "url": "javascript:alert(1)"],
            ["title": "Credentials", "url": "https://user:password@example.com/"],
            ["title": "Local", "url": "file:///tmp/private"],
        ]
        let result = try XCTUnwrap(DailyPlan(row: payload))
        XCTAssertEqual(result.tasks.first?.sources.first?.title, "NIH")
        XCTAssertEqual(result.sources.count, 1)
        XCTAssertEqual(result.sources.first?.url.absoluteString, "https://ods.od.nih.gov/")
    }

    func testRepeatedOpeningSharesFlightThenStartsFreshOnSameDay() throws {
        var state = AdviceRequestLifetime()
        state.prepare(owner: "alice", dayKey: "2026-09-08")
        let first = try XCTUnwrap(state.begin())
        XCTAssertNil(state.begin(), "Reopening during generation must share the active request")
        XCTAssertTrue(state.accepts(first, owner: "alice", dayKey: "2026-09-08"))
        XCTAssertTrue(state.finish(first))
        let second = try XCTUnwrap(state.begin())
        XCTAssertNotEqual(first, second, "An unchanged day must not suppress a new generation")
        XCTAssertFalse(state.finish(first), "Late completion must not clear a newer request")
        XCTAssertTrue(state.accepts(second, owner: "alice", dayKey: "2026-09-08"))
    }

    func testOwnerAndDayChangesRejectLateReplies() throws {
        var state = AdviceRequestLifetime()
        state.prepare(owner: "alice", dayKey: "2026-09-08")
        let alice = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.accepts(alice, owner: "bob", dayKey: "2026-09-08"))
        XCTAssertFalse(state.accepts(alice, owner: "alice", dayKey: "2026-09-09"))
        state.prepare(owner: "bob", dayKey: "2026-09-09")
        let bob = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.finish(alice))
        XCTAssertFalse(state.accepts(alice, owner: "bob", dayKey: "2026-09-09"))
        XCTAssertTrue(state.accepts(bob, owner: "bob", dayKey: "2026-09-09"))
    }

    func testResetRejectsReplyEvenWhenSameAccountAndDayReturns() throws {
        var state = AdviceRequestLifetime()
        state.prepare(owner: "alice", dayKey: "2026-09-08")
        let old = try XCTUnwrap(state.begin())
        state.reset()
        state.prepare(owner: "alice", dayKey: "2026-09-08")
        let current = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.accepts(old, owner: "alice", dayKey: "2026-09-08"))
        XCTAssertFalse(state.finish(old))
        XCTAssertTrue(state.accepts(current, owner: "alice", dayKey: "2026-09-08"))
    }
}
