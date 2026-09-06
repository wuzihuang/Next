import XCTest
@testable import NextBodySyncCore

final class BandAlarmMathTests: XCTestCase {
    func testMalformedFirmwareRowCannotBecomeAnEditableAlarm() {
        let malformed = BandAlarm(id: 74, hour: 56, minute: 180, on: true,
                                  repeatMask: 196, date: "2084-06-57", scene: 0)
        XCTAssertFalse(malformed.isValidDeviceValue)
        for mask in [0, 31, 96, 127] {
            let alarm = BandAlarm(id: 1, hour: 7, minute: 30, on: true,
                                  repeatMask: mask, date: "0000-00-00", scene: 0)
            XCTAssertTrue(alarm.isValidDeviceValue)
        }
    }
    func testRealHoopCapabilityUsesTextAlarmCommands() {
        let bytes: [UInt8] = [0xa7, 1, 0, 2, 2, 2, 1, 0, 6, 20, 1, 2, 0, 0, 0, 1, 0, 6, 3, 1]
        let kind = BandAlarmProtocol(functionData: Data(bytes))
        XCTAssertEqual(kind, .text)
        XCTAssertEqual(kind?.sdkMode(for: 0), 1)
        XCTAssertEqual(kind?.sdkMode(for: 1), 2)
        XCTAssertEqual(kind?.sdkMode(for: 2), 3)
        XCTAssertEqual(kind?.capacity, 10)
        XCTAssertNil(BandAlarmProtocol(functionData: Data(bytes.prefix(17))))
        XCTAssertNil(BandAlarmProtocol(functionData: nil))
        for flag: UInt8 in 1...7 {
            var data = bytes
            data[17] = flag
            let protocolKind = BandAlarmProtocol(functionData: Data(data))
            XCTAssertEqual(protocolKind, flag < 5 ? .scene : .text)
        }
    }

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
        XCTAssertEqual(BandAlarmMath.nextID(in: []), 1)
        XCTAssertNil(BandAlarmMath.nextID(in: [], ceiling: 0))
        let alarms = [
            BandAlarm(id: 0, hour: 7, minute: 30, on: true, repeatMask: 31,
                      date: BandAlarm.onceDatePlaceholder, scene: 0),
            BandAlarm(id: 2, hour: 8, minute: 45, on: true, repeatMask: 31,
                      date: BandAlarm.onceDatePlaceholder, scene: 0),
        ]
        XCTAssertEqual(BandAlarmMath.nextID(in: alarms), 1)
        let full = (1...20).map {
            BandAlarm(id: $0, hour: 7, minute: 0, on: true, repeatMask: 31,
                      date: BandAlarm.onceDatePlaceholder, scene: 0)
        }
        XCTAssertNil(BandAlarmMath.nextID(in: full))
        XCTAssertTrue(BandAlarmMath.isFull(full))
        XCTAssertEqual(BandAlarmMath.nextID(in: Array(full.dropLast())), 20)
        XCTAssertEqual(BandAlarmMath.nextID(in: full.filter { $0.id != 7 }), 7)
    }

    /// The SWITCH face never prints a running count. `2 / ?` was engineering talk on a
    /// wearer's screen — capacity only becomes a sentence when the band actually refuses.
    func testCapacityOnlyMattersWhenTheHoopIsFull() {
        let one = [BandAlarm(id: 0, hour: 7, minute: 30, on: true, repeatMask: 31,
                             date: BandAlarm.onceDatePlaceholder, scene: 0)]
        XCTAssertFalse(BandAlarmMath.isFull(one, ceiling: 20))
        XCTAssertTrue(BandAlarmMath.isFull(one, ceiling: 1))
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
