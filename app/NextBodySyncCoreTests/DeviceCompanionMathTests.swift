import XCTest
@testable import NextBodySyncCore

final class DeviceCompanionMathTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testMissingBindIsNil() {
        XCTAssertNil(DeviceCompanionMath.days(boundAt: nil, now: Date(), calendar: calendar))
    }

    func testSameUserDayIsOne() {
        let bound = date(year: 2026, month: 9, day: 6, hour: 8)
        let now = date(year: 2026, month: 9, day: 6, hour: 22)
        XCTAssertEqual(DeviceCompanionMath.days(boundAt: bound, now: now, calendar: calendar), 1)
    }

    func testBeforeFourIsThePreviousUserDay() {
        let bound = date(year: 2026, month: 9, day: 6, hour: 3)
        let now = date(year: 2026, month: 9, day: 6, hour: 5)
        XCTAssertEqual(DeviceCompanionMath.days(boundAt: bound, now: now, calendar: calendar), 2)
    }

    func testNextUserDayIsTwo() {
        let bound = date(year: 2026, month: 9, day: 5, hour: 12)
        let now = date(year: 2026, month: 9, day: 6, hour: 12)
        XCTAssertEqual(DeviceCompanionMath.days(boundAt: bound, now: now, calendar: calendar), 2)
    }

    func testEightyFourClosedDaysPlusTodayIsEightyFive() {
        let now = date(year: 2026, month: 9, day: 6, hour: 12)
        let bound = date(year: 2026, month: 6, day: 14, hour: 12)
        XCTAssertEqual(DeviceCompanionMath.days(boundAt: bound, now: now, calendar: calendar), 85)
    }

    func testFutureStampIsNil() {
        let bound = date(year: 2026, month: 9, day: 7, hour: 12)
        let now = date(year: 2026, month: 9, day: 6, hour: 12)
        XCTAssertNil(DeviceCompanionMath.days(boundAt: bound, now: now, calendar: calendar))
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
