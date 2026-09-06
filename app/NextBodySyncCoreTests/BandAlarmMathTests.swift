import XCTest
@testable import NextBodySyncCore

final class BandAlarmMathTests: XCTestCase {
    func testWeekBitsMatchVendorString() {
        XCTAssertEqual(BandAlarmMath.Weekday.monday.bit, 1)
        XCTAssertEqual(BandAlarmMath.Weekday.tuesday.bit, 2)
        XCTAssertEqual(3 & BandAlarmMath.Weekday.monday.bit, 1)
        XCTAssertEqual(3 & BandAlarmMath.Weekday.tuesday.bit, 2)
        XCTAssertEqual(BandAlarmMath.Weekday.sunday.bit, 64)
        XCTAssertEqual(BandAlarmMath.weekdaysMask, 31)
        XCTAssertEqual(BandAlarmMath.everyDayMask, 127)
    }

    func testSwitchOnlyWhenTheAlarmRepeats() {
        var once = BandAlarm.emptyRead()
        once.repeatMask = 0
        XCTAssertFalse(once.showsSwitch)
        once.repeatMask = BandAlarmMath.weekdaysMask
        XCTAssertTrue(once.showsSwitch)
    }

    func testPhrases() {
        XCTAssertEqual(BandAlarmMath.phrase(0), "ONCE")
        XCTAssertEqual(BandAlarmMath.phrase(BandAlarmMath.everyDayMask), "EVERY DAY")
        XCTAssertEqual(BandAlarmMath.phrase(BandAlarmMath.weekdaysMask), "WEEKDAYS")
        XCTAssertEqual(BandAlarmMath.phrase(BandAlarmMath.weekendMask), "WEEKEND")
        XCTAssertEqual(BandAlarmMath.phrase(1 | 4), "MON · WED")
    }

    func testNextIDSkipsUsedSlots() {
        let alarms = [
            BandAlarm(id: 0, hour: 7, minute: 30, on: true, repeatMask: 31,
                      date: BandAlarm.onceDatePlaceholder, scene: 0),
            BandAlarm(id: 2, hour: 8, minute: 45, on: true, repeatMask: 31,
                      date: BandAlarm.onceDatePlaceholder, scene: 0),
        ]
        XCTAssertEqual(BandAlarmMath.nextID(in: alarms), 1)
        let full = (0..<20).map {
            BandAlarm(id: $0, hour: 7, minute: 0, on: true, repeatMask: 31,
                      date: BandAlarm.onceDatePlaceholder, scene: 0)
        }
        XCTAssertNil(BandAlarmMath.nextID(in: full))
        XCTAssertTrue(BandAlarmMath.isFull(full))
    }

    func testCountStaysUnknownUntilTheFirstRead() {
        XCTAssertEqual(BandAlarmMath.countLabel(count: nil, didRead: false, capacity: nil), "— / ?")
        XCTAssertEqual(BandAlarmMath.countLabel(count: 2, didRead: true, capacity: nil), "2 / ?")
        XCTAssertEqual(BandAlarmMath.countLabel(count: 20, didRead: true, capacity: 20), "20 / 20")
    }

    func testOnceDateMovesPastToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = date(year: 2026, month: 9, day: 6, hour: 8, minute: 0, calendar: calendar)
        XCTAssertEqual(
            BandAlarmMath.onceDate(hour: 7, minute: 30, now: morning, calendar: calendar),
            "2026-09-07")
        XCTAssertEqual(
            BandAlarmMath.onceDate(hour: 9, minute: 0, now: morning, calendar: calendar),
            "2026-09-06")
    }

    func testPreparedLocksSceneAndDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(year: 2026, month: 9, day: 6, hour: 8, minute: 0, calendar: calendar)
        var draft = BandAlarm(id: 1, hour: 7, minute: 30, on: true, repeatMask: 31,
                              date: "1999-01-01", scene: 7)
        let repeating = BandAlarmMath.prepared(draft, now: now, calendar: calendar)
        XCTAssertEqual(repeating.scene, 0)
        XCTAssertEqual(repeating.date, BandAlarm.onceDatePlaceholder)

        draft.repeatMask = 0
        let once = BandAlarmMath.prepared(draft, now: now, calendar: calendar)
        XCTAssertEqual(once.date, "2026-09-07")
        XCTAssertEqual(once.scene, 0)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int,
                      calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
