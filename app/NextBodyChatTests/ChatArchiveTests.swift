import Foundation
import XCTest
@testable import NextBodyChatCore

final class ChatArchiveTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func snapshot() -> ChatArchiveSnapshot {
        ChatArchiveSnapshot(activeSessionID: "session-1", sessions: [
            ChatArchiveSession(id: "session-1", title: "Sleep", subtitle: "A follow-up", updatedAt: Date(timeIntervalSince1970: 1_700_000_000), tags: ["sleep"], photosCount: 1, messages: [
                ChatArchiveMessage(id: UUID(), sender: "user", text: "What is this?", imageDataURL: "data:image/png;base64,aGVsbG8=", at: Date(timeIntervalSince1970: 1_700_000_000), envelope: nil),
                ChatArchiveMessage(id: UUID(), sender: "assistant", text: "A chart", imageDataURL: nil, at: Date(timeIntervalSince1970: 1_700_000_001), envelope: Data("{\"type\":\"chart\",\"values\":[1,2,3]}".utf8)),
            ])
        ])
    }

    func testRoundTripRetainsImagesAndWidgetEnvelopeAfterStoreRecreation() throws {
        let directory = try temporaryDirectory()
        let original = snapshot()
        try ChatArchiveStore(accountID: "user/one", directory: directory).save(original)
        let reloaded = try ChatArchiveStore(accountID: "user/one", directory: directory).load()
        XCTAssertEqual(reloaded, original)
    }

    func testAccountsAreIsolatedAndMissingArchiveReturnsNil() throws {
        let directory = try temporaryDirectory()
        let first = try ChatArchiveStore(accountID: "first", directory: directory)
        let second = try ChatArchiveStore(accountID: "second", directory: directory)
        XCTAssertNil(try first.load())
        try first.save(snapshot())
        XCTAssertNil(try second.load())
    }

    func testSavingEmptyArchiveDoesNotRestoreOldMessages() throws {
        let directory = try temporaryDirectory()
        let store = try ChatArchiveStore(accountID: "user", directory: directory)
        try store.save(snapshot())
        let empty = ChatArchiveSnapshot(activeSessionID: nil, sessions: [])
        try store.save(empty)
        XCTAssertEqual(try ChatArchiveStore(accountID: "user", directory: directory).load(), empty)
        try store.clear()
        XCTAssertNil(try store.load())
        try store.clear()
    }

    func testCorruptArchiveThrowsInsteadOfLookingLikeEmptyHistory() throws {
        let directory = try temporaryDirectory()
        let store = try ChatArchiveStore(accountID: "user", directory: directory)
        try store.save(snapshot())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("not-json".utf8).write(to: file)
        XCTAssertThrowsError(try store.load())
    }

    func testWrongAccountAndUnknownVersionAreRejected() throws {
        let directory = try temporaryDirectory()
        let store = try ChatArchiveStore(accountID: "user", directory: directory)
        try store.save(snapshot())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        try JSONSerialization.data(withJSONObject: original.merging(["accountID": "another-user"]) { _, new in new }).write(to: file)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? ChatArchiveError, .accountMismatch) }
        try JSONSerialization.data(withJSONObject: original.merging(["version": 999]) { _, new in new }).write(to: file)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? ChatArchiveError, .unsupportedVersion(999)) }
    }

    func testSaveErrorsAreReported() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("ordinary-file")
        try Data().write(to: file)
        let store = try ChatArchiveStore(accountID: "user", directory: file)
        XCTAssertThrowsError(try store.save(snapshot()))
    }

    func testMissingAccountIsRejectedWithReadableError() throws {
        XCTAssertThrowsError(try ChatArchiveStore(accountID: "", directory: temporaryDirectory())) {
            XCTAssertEqual($0 as? ChatArchiveError, .emptyAccountID)
            XCTAssertFalse($0.localizedDescription.isEmpty)
        }
        XCTAssertFalse(ChatArchiveError.accountMismatch.localizedDescription.isEmpty)
        XCTAssertFalse(ChatArchiveError.unsupportedVersion(2).localizedDescription.isEmpty)
    }
}

final class ChatTurnScopeTests: XCTestCase {
    func testProgressBelongsOnlyToItsAccountAndSelectedSession() {
        let scope = ChatTurnScope(accountID: "account-a", sessionID: "session-a", turnID: UUID())
        XCTAssertTrue(scope.isVisible(accountID: "account-a", sessionID: "session-a"))
        XCTAssertFalse(scope.isVisible(accountID: "account-a", sessionID: "session-b"))
        XCTAssertFalse(scope.isVisible(accountID: "account-b", sessionID: "session-a"))
    }

    func testOlderTurnCannotFinishOrPublishIntoReplacementTurn() {
        let first = ChatTurnScope(accountID: "a", sessionID: "s", turnID: UUID())
        let second = ChatTurnScope(accountID: "a", sessionID: "s", turnID: UUID())
        XCTAssertFalse(first.accepts(turnID: second.turnID))
        XCTAssertTrue(first.accepts(turnID: first.turnID))
    }
}
