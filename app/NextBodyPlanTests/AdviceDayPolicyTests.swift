import XCTest
@testable import NextBodyPlanCore

/// ADR 0022 · the day's set is generated once in the background; these pin the decisions.
final class AdviceDayPolicyTests: XCTestCase {
    private let owner = "user-a"
    private let today = "2026-09-09"
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private func run(_ attempt: Int, kind: AdviceDayRun.Kind = .automatic, outcome: AdviceDayRun.Outcome? = nil,
                     age: TimeInterval = 30, day: String? = nil) -> AdviceDayRun {
        AdviceDayRun(ownerUserId: owner, dayKey: day ?? today, kind: kind, attempt: attempt,
                     turnID: AdviceDayPolicy.automaticTurnID(owner: owner, dayKey: day ?? today, attempt: attempt),
                     startedAt: now.addingTimeInterval(-age), outcome: outcome)
    }

    private func situation(stored: String? = nil, runs: [AdviceDayRun] = [], bandSynced: Bool = true,
                           foregroundElapsed: TimeInterval = 0) -> AdviceDayPolicy.Situation {
        .init(dayKey: today, storedDayKey: stored, runs: runs, bandSynced: bandSynced,
              foregroundElapsed: foregroundElapsed, now: now)
    }

    func testTodaysStoredSetNeedsNoGeneration() {
        XCTAssertEqual(AdviceDayPolicy.next(situation(stored: today)), .showToday)
        XCTAssertEqual(AdviceDayPolicy.next(situation(stored: today, runs: [run(1)])), .showToday)
    }

    func testFirstOpeningStartsAttemptOneOnceTheBandHasSynced() {
        XCTAssertEqual(AdviceDayPolicy.next(situation(stored: "2026-09-08")), .start(attempt: 1))
        XCTAssertEqual(AdviceDayPolicy.next(situation(stored: nil)), .start(attempt: 1))
    }

    func testFirstAttemptWaitsForTheBandThenGivesUpWaiting() {
        XCTAssertEqual(AdviceDayPolicy.next(situation(bandSynced: false, foregroundElapsed: 5)), .waitForBand)
        XCTAssertEqual(AdviceDayPolicy.next(situation(bandSynced: false, foregroundElapsed: AdviceDayPolicy.bandWait)),
                       .start(attempt: 1))
        // Later attempts never wait: the band had its chance on the first one.
        XCTAssertEqual(AdviceDayPolicy.next(situation(runs: [run(1, outcome: .failed)], bandSynced: false, foregroundElapsed: 0)),
                       .start(attempt: 2))
    }

    func testAnOpenRunIsAttachedNotDuplicated() {
        let open = run(1)
        XCTAssertEqual(AdviceDayPolicy.next(situation(runs: [open])), .attach(open))
        let refresh = run(1, kind: .refresh)
        XCTAssertEqual(AdviceDayPolicy.next(situation(runs: [run(1, outcome: .delivered), refresh])), .attach(refresh))
    }

    func testADeliveredRunReplaysWhenTheStoredSetCannotBeRead() {
        let delivered = run(1, outcome: .delivered)
        XCTAssertEqual(AdviceDayPolicy.next(situation(stored: nil, runs: [delivered])), .attach(delivered))
        XCTAssertEqual(AdviceDayPolicy.next(situation(stored: "2026-09-08", runs: [delivered])), .attach(delivered))
        let refreshed = run(1, kind: .refresh, outcome: .delivered, age: 10)
        XCTAssertEqual(AdviceDayPolicy.next(situation(stored: nil, runs: [delivered, refreshed])), .attach(refreshed))
        XCTAssertEqual(AdviceDayPolicy.next(situation(stored: today, runs: [delivered])), .showToday)
    }

    func testARunNobodyHeardTheEndOfExpiresIntoTheNextAttempt() {
        let dead = run(1, age: AdviceDayPolicy.unknownRunLifetime)
        XCTAssertEqual(AdviceDayPolicy.next(situation(runs: [dead])), .start(attempt: 2))
        let settled = AdviceDayPolicy.settled([dead], now: now, keepDays: [today])
        XCTAssertEqual(settled.first?.outcome, .failed)
    }

    func testThreeFailedAttemptsLeaveOnlyRefresh() {
        let runs = [run(1, outcome: .failed), run(2, outcome: .failed), run(3, outcome: .failed)]
        XCTAssertEqual(AdviceDayPolicy.next(situation(runs: runs)), .exhausted)
        // A failed refresh does not spend an automatic attempt.
        XCTAssertEqual(AdviceDayPolicy.next(situation(runs: [run(1, outcome: .failed), run(1, kind: .refresh, outcome: .failed)])),
                       .start(attempt: 2))
    }

    func testYesterdaysRunsDoNotCountForToday() {
        let old = [run(1, outcome: .failed, day: "2026-09-08"), run(2, outcome: .failed, day: "2026-09-08"),
                   run(3, outcome: .failed, day: "2026-09-08")]
        XCTAssertEqual(AdviceDayPolicy.next(situation(stored: "2026-09-08", runs: old)), .start(attempt: 1))
        XCTAssertEqual(AdviceDayPolicy.settled(old, now: now, keepDays: [today]), [])
    }

    func testAutomaticTurnIDIsTheSameOnEveryPhoneAndDiffersPerAttemptAndDay() {
        let a = AdviceDayPolicy.automaticTurnID(owner: owner, dayKey: today, attempt: 1)
        XCTAssertEqual(a, AdviceDayPolicy.automaticTurnID(owner: owner, dayKey: today, attempt: 1))
        XCTAssertNotEqual(a, AdviceDayPolicy.automaticTurnID(owner: owner, dayKey: today, attempt: 2))
        XCTAssertNotEqual(a, AdviceDayPolicy.automaticTurnID(owner: owner, dayKey: "2026-09-10", attempt: 1))
        XCTAssertNotEqual(a, AdviceDayPolicy.automaticTurnID(owner: "user-b", dayKey: today, attempt: 1))
        // RFC 4122 version 5, variant 10xx.
        let bytes = a.uuid
        XCTAssertEqual(bytes.6 >> 4, 5)
        XCTAssertEqual(bytes.8 >> 6, 0b10)
    }

    func testProbeDelayFollowsTheServerWithinBounds() {
        XCTAssertEqual(AdviceDayPolicy.probeDelay(retryAfter: nil), AdviceDayPolicy.probeFloor)
        XCTAssertEqual(AdviceDayPolicy.probeDelay(retryAfter: 1), AdviceDayPolicy.probeFloor)
        XCTAssertEqual(AdviceDayPolicy.probeDelay(retryAfter: 6), 6)
        XCTAssertEqual(AdviceDayPolicy.probeDelay(retryAfter: 88), AdviceDayPolicy.probeCeiling)
    }
}
