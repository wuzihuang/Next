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

    func testFourAMBoundaryIsALocalClockTimeAcrossDST() throws {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        for stamp in ["2026-03-08 12:00", "2026-11-01 12:00"] {
            let now = try XCTUnwrap(HealthSampleMapping.sleepInstant(stamp, calendar: eastern))
            let day = UserDay.containing(now, calendar: eastern)
            XCTAssertEqual(eastern.component(.hour, from: day.start), 4)
            XCTAssertEqual(eastern.component(.minute, from: day.start), 0)
            XCTAssertTrue(eastern.isDate(day.start, inSameDayAs: now))
            let beforeCut = day.start.addingTimeInterval(-1)
            let previous = UserDay.containing(beforeCut, calendar: eastern)
            XCTAssertEqual(eastern.component(.hour, from: previous.start), 4)
            XCTAssertEqual(eastern.dateComponents([.day], from: previous.start, to: day.start).day, 1)
        }
    }

    func testElapsedMinutesUsesActual23And25HourWindows() throws {
        let savedZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        defer { NSTimeZone.default = savedZone }
        let local = Calendar.current
        for (stamp, minutes) in [("2026-03-07 12:00", 1_380), ("2026-10-31 12:00", 1_500)] {
            let now = try XCTUnwrap(HealthSampleMapping.sleepInstant(stamp, calendar: local))
            let day = UserDay.containing(now)
            XCTAssertEqual(local.component(.hour, from: day.end), 4)
            XCTAssertEqual(day.end.timeIntervalSince(day.start), Double(minutes * 60), accuracy: 0.001)
            XCTAssertEqual(day.elapsedMinutes(at: day.end), minutes)
            XCTAssertEqual(day.elapsedMinutes(at: day.end.addingTimeInterval(3_600)), minutes)
            XCTAssertEqual(day.elapsedMinutes(at: day.start.addingTimeInterval(-60)), 0)
            XCTAssertEqual(day.adding(days: 1).start, day.end)
        }
    }
}
