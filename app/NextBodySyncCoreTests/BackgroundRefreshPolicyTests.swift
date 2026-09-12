import XCTest
@testable import NextBodySyncCore

final class BackgroundRefreshPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testIdentifierMatchesTheBundlePrefix() {
        XCTAssertEqual(BackgroundRefreshPolicy.taskIdentifier, "com.nextbody.hoop.refresh")
        XCTAssertEqual(BackgroundRefreshPolicy.interval, 30 * 60)
    }

    func testOnlyAPlacedWidgetOnASignedInBoundPhoneSchedules() {
        XCTAssertTrue(BackgroundRefreshPolicy.shouldSchedule(widgetCount: 1, signedIn: true, bound: true))
        XCTAssertTrue(BackgroundRefreshPolicy.shouldSchedule(widgetCount: 3, signedIn: true, bound: true))
        XCTAssertFalse(BackgroundRefreshPolicy.shouldSchedule(widgetCount: 0, signedIn: true, bound: true),
                       "no widget, no reader: the radio stays quiet")
        XCTAssertFalse(BackgroundRefreshPolicy.shouldSchedule(widgetCount: 1, signedIn: false, bound: true))
        XCTAssertFalse(BackgroundRefreshPolicy.shouldSchedule(widgetCount: 1, signedIn: true, bound: false))
    }

    func testNextRunIsHalfAnHourAfterTheLastPull() {
        let tenMinutesAgo = now.addingTimeInterval(-10 * 60)
        XCTAssertEqual(BackgroundRefreshPolicy.nextBeginDate(now: now, lastPullAt: tenMinutesAgo),
                       now.addingTimeInterval(20 * 60))
    }

    func testNextRunNeverAsksForThePast() {
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        XCTAssertEqual(BackgroundRefreshPolicy.nextBeginDate(now: now, lastPullAt: twoHoursAgo), now)
    }

    func testNoPullYetOrAFutureClockCountsFromNow() {
        XCTAssertEqual(BackgroundRefreshPolicy.nextBeginDate(now: now, lastPullAt: nil),
                       now.addingTimeInterval(30 * 60))
        XCTAssertEqual(BackgroundRefreshPolicy.nextBeginDate(now: now, lastPullAt: now.addingTimeInterval(60)),
                       now.addingTimeInterval(30 * 60))
    }

    func testAThrottledPullStillCountsAsDone() {
        XCTAssertTrue(BackgroundRefreshPolicy.completed(.success))
        XCTAssertTrue(BackgroundRefreshPolicy.completed(.partial))
        XCTAssertTrue(BackgroundRefreshPolicy.completed(.throttled))
        XCTAssertFalse(BackgroundRefreshPolicy.completed(.disconnected))
        XCTAssertFalse(BackgroundRefreshPolicy.completed(.failed))
        XCTAssertFalse(BackgroundRefreshPolicy.completed(.cancelled))
    }
}
