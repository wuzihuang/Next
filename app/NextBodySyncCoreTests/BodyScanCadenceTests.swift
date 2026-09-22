import XCTest
@testable import NextBodySyncCore

final class BodyScanCadenceTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    func testAWeekIsTheGapWorthMeasuring() {
        let last = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(BodyScanCadence.daysLeft(since: last, now: last, calendar: calendar), 7)
        XCTAssertEqual(BodyScanCadence.daysLeft(since: last, now: last + 2 * day, calendar: calendar), 5)
        XCTAssertEqual(BodyScanCadence.daysLeft(since: last, now: last + 7 * day, calendar: calendar), 0)
        XCTAssertTrue(BodyScanCadence.isDue(since: last, now: last + 7 * day, calendar: calendar))
    }

    /// Overdue is due, not a growing count of missed days.
    func testOverdueNeverGoesNegative() {
        let last = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(BodyScanCadence.daysLeft(since: last, now: last + 40 * day, calendar: calendar), 0)
    }

    func testChangeNeedsTwoDifferentDays() {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(BodyScanCadence.change(firstAt: first, firstFat: 24, firstLean: 55,
                                            latestAt: first + 3600, latestFat: 23, latestLean: 56,
                                            calendar: calendar))
        let change = BodyScanCadence.change(firstAt: first, firstFat: 24, firstLean: 55,
                                            latestAt: first + 30 * day, latestFat: 21.5, latestLean: 56.2,
                                            calendar: calendar)
        XCTAssertEqual(change?.days, 30)
        XCTAssertEqual(change?.bodyFatPoints ?? 0, -2.5, accuracy: 0.0001)
        XCTAssertEqual(change?.leanKg ?? 0, 1.2, accuracy: 0.0001)
    }

    func testNothingMeasuredIsNotAChangeOfZero() {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(BodyScanCadence.change(firstAt: first, firstFat: nil, firstLean: nil,
                                            latestAt: first + 10 * day, latestFat: nil, latestLean: nil,
                                            calendar: calendar))
        let half = BodyScanCadence.change(firstAt: first, firstFat: nil, firstLean: 55,
                                          latestAt: first + 10 * day, latestFat: 22, latestLean: 56,
                                          calendar: calendar)
        XCTAssertNil(half?.bodyFatPoints)
        XCTAssertEqual(half?.leanKg ?? 0, 1, accuracy: 0.0001)
    }
}
