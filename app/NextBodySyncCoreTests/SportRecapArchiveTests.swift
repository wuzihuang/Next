import XCTest
import NextBodyLocalData
@testable import NextBodySyncCore

final class SportRecapArchiveTests: XCTestCase {
    private func recap(owner: String) -> SportSessionRecap {
        .init(title: "Run", startedAt: Date(timeIntervalSince1970: 10), endedAt: Date(timeIntervalSince1970: 20),
              seconds: 10, avgHR: nil, peakHR: nil, kcal: 0, caloriesEstimated: true,
              curve: [], zoneMinutes: [0, 0, 0, 0, 0], aerobicMinutes: 0, anaerobicMinutes: 0,
              conclusion: "No heart-rate record.", sessionID: UUID(), ownerUserID: owner,
              loadBefore: nil, loadAfter: nil, curvePoints: [], observedSeconds: 0, hasCalories: false)
    }

    func testRestartRetainsRecordAndAcknowledgingUploadDoesNotDeleteHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let record = recap(owner: "a")
        do { try SportRecapArchive(local: LocalDataStore(url: url)).stage(record, owner: "a") }
        let local = try LocalDataStore(url: url)
        let archive = SportRecapArchive(local: local)
        XCTAssertEqual(try archive.read(owner: "a"), [record])
        let operation = try XCTUnwrap(local.operations(account: "a", kind: SportRecapArchive.kind).first)
        try local.acknowledge(account: "a", id: operation.id)
        XCTAssertEqual(try archive.read(owner: "a"), [record])
        XCTAssertTrue(try local.operations(account: "a", kind: SportRecapArchive.kind).isEmpty)
        XCTAssertFalse(record.hasZones)
        XCTAssertFalse(record.hasEnergy)
    }

    func testAccountIsolationReplayAndPurge() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let local = try LocalDataStore(url: url)
        let archive = SportRecapArchive(local: local)
        let record = recap(owner: "a")
        try archive.stage(record, owner: "a")
        try archive.stage(record, owner: "a")
        XCTAssertEqual(try local.operations(account: "a", kind: SportRecapArchive.kind).count, 1)
        XCTAssertTrue(try archive.read(owner: "b").isEmpty)
        XCTAssertThrowsError(try archive.stage(record, owner: "b"))
        try archive.cache([record], owner: "b")
        XCTAssertTrue(try archive.read(owner: "b").isEmpty)
        try local.purge(account: "a")
        XCTAssertTrue(try archive.read(owner: "a").isEmpty)
    }
    func testMalformedCloudNumbersCannotReachIntegerFormattingOrOutbox() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let local = try LocalDataStore(url: url)
        let archive = SportRecapArchive(local: local)
        var malformed = recap(owner: "a")
        malformed.kcal = 1e100
        XCTAssertFalse(malformed.isValid)
        XCTAssertThrowsError(try archive.stage(malformed, owner: "a"))
        XCTAssertTrue(try local.operations(account: "a", kind: SportRecapArchive.kind).isEmpty)
        let valid = recap(owner: "a")
        XCTAssertEqual(archive.stagePending([malformed, valid], owner: "a"), [malformed])
        XCTAssertEqual(try archive.read(owner: "a"), [valid])
        XCTAssertEqual(try local.operations(account: "a", kind: SportRecapArchive.kind).count, 1)
    }

}
