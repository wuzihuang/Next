import XCTest
@testable import NextBodySyncCore

final class UserDayTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testLastWalksOldestFirstAndEndsOnTheFocusDay() {
        let focus = UserDay.containing(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!,
            calendar: calendar)
        let days = UserDay.last(3, endingAt: focus)
        XCTAssertEqual(days.map(\.key), [
            focus.adding(days: -2).key,
            focus.adding(days: -1).key,
            focus.key,
        ])
    }

    func testLastOfZeroIsEmpty() {
        let focus = UserDay.containing(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!,
            calendar: calendar)
        XCTAssertEqual(UserDay.last(0, endingAt: focus), [])
        XCTAssertEqual(UserDay.last(-4, endingAt: focus), [])
    }

    func testHoursSitOnTheFourOClockCut() {
        let day = UserDay.containing(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12))!,
            calendar: calendar)
        XCTAssertEqual(UserDay.hours(day.start, in: day), 0, accuracy: 0.001)
        XCTAssertEqual(UserDay.hours(day.end, in: day), 24, accuracy: 0.001)
        let noon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12))!
        XCTAssertEqual(UserDay.hours(noon, in: day), 8, accuracy: 0.001)
    }

    func testWeekRollsPutTheRemainderOnTheOldestGroup() {
        XCTAssertEqual(UserDay.weekRolls(count: 30).map(\.count), [2, 7, 7, 7, 7])
        XCTAssertEqual(UserDay.weekRolls(count: 28).map(\.count), [7, 7, 7, 7])
        XCTAssertEqual(UserDay.weekRolls(count: 16).map(\.count), [2, 7, 7])
        XCTAssertEqual(UserDay.weekRolls(count: 5).map(\.count), [5])
        XCTAssertEqual(UserDay.weekRolls(count: 0), [])
        let thirty = UserDay.weekRolls(count: 30)
        XCTAssertEqual(thirty.first, 0..<2)
        XCTAssertEqual(thirty.last, 23..<30)
    }
}
