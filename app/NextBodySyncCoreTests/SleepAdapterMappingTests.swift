import XCTest
@testable import NextBodySyncCore

final class SleepAdapterMappingTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var now: Date { Date(timeIntervalSince1970: 1_788_652_800) } // 2026-09-06 UTC

    func testAfternoonWakeBelongsToItsFullCalendarDay() {
        let rows = [("2026/09/05 03:00", "2026/09/05 13:09")]
        XCTAssertEqual(HealthSampleMapping.sleepRecordIndices(stamps: rows, wakeDay: "2026-09-05", now: now, calendar: calendar), [0])
    }

    func testAdjacentSDKPagesDeduplicateSlashAndHyphenStampsAndSortChronologically() {
        let rows = [("2026-09-05 14:00", "2026-09-05 15:00"),
                    ("2026/09/05 03:00", "2026/09/05 13:09"),
                    ("2026-09-05 03:00", "2026-09-05 13:09")]
        XCTAssertEqual(HealthSampleMapping.sleepRecordIndices(stamps: rows, wakeDay: "2026-09-05", now: now, calendar: calendar), [1, 0])
    }

    func testInvalidFutureReversedAndOtherDaySleepAreExcluded() {
        let rows: [(String?, String?)] = [(nil, "2026-09-05 13:09"),
            ("2026-09-05 14:00", "2026-09-05 13:09"),
            ("2026-09-05 13:09", "2026-09-05 13:09"),
            ("2026-09-05 10:00", "2026-09-06 13:09"),
            ("2026-09-05 10:00", "2026-09-05 25:09"),
            ("2026-02-30 10:00", "2026-09-05 13:09")]
        XCTAssertEqual(HealthSampleMapping.sleepRecordIndices(stamps: rows, wakeDay: "2026-09-05", now: now, calendar: calendar), [])
    }

    func testFutureWakeOnRequestedDayIsExcludedUntilItHasOccurred() throws {
        let noon = try XCTUnwrap(HealthSampleMapping.sleepInstant("2026-09-05 12:00", calendar: calendar))
        let rows = [("2026-09-05 03:00", "2026-09-05 13:09")]
        XCTAssertEqual(HealthSampleMapping.sleepRecordIndices(stamps: rows, wakeDay: "2026-09-05", now: noon, calendar: calendar), [])
    }

    func testEveningWakeAndMidnightBelongToExactlyOneDay() {
        let rows = [("2026-09-05 14:00", "2026-09-05 23:59"),
                    ("2026-09-04 22:00", "2026-09-05 00:00")]
        XCTAssertEqual(HealthSampleMapping.sleepRecordIndices(stamps: rows, wakeDay: "2026-09-05", now: now, calendar: calendar), [1, 0])
        XCTAssertEqual(HealthSampleMapping.sleepRecordIndices(stamps: rows, wakeDay: "2026-09-04", now: now, calendar: calendar), [])
    }

    func testSleepTimestampSupportsBothVendorSeparators() {
        XCTAssertEqual(HealthSampleMapping.sleepInstant("2026/09/05 13:09", calendar: calendar), HealthSampleMapping.sleepInstant("2026-09-05 13:09", calendar: calendar))
        XCTAssertNotNil(HealthSampleMapping.sleepInstant("2026-09-05 13:09", calendar: calendar))
        XCTAssertNil(HealthSampleMapping.sleepInstant("2026-02-30 13:09", calendar: calendar))
    }

    func testMinuteHRVPreservesSleepStartAndWakeBoundaryReadings() {
        let samples = [
            HrvMinuteSample(time: "03:59", rmssdMS: 42, vendorValue: nil, rrCount: 3),
            HrvMinuteSample(time: "09:02", rmssdMS: 53, vendorValue: nil, rrCount: 3),
        ]
        let minutes = HealthSampleMapping.hrvByMinute(samples)
        XCTAssertEqual(minutes.filter { $0.key >= "03:59" && $0.key < "09:03" },
                       ["03:59": 42, "09:02": 53])
        XCTAssertNil(minutes["03:55"])
        XCTAssertNil(minutes["09:00"])
    }

    func testMinuteHRVDoesNotSubstituteVendorScalarOrDuplicateAReading() {
        let sample = HrvMinuteSample(time: "03:59", rmssdMS: 42, vendorValue: 70, rrCount: 3)
        let minutes = HealthSampleMapping.hrvByMinute([
            sample, sample,
            HrvMinuteSample(time: "04:00", rmssdMS: nil, vendorValue: 70, rrCount: 0),
            HrvMinuteSample(time: "04:01", rmssdMS: .nan, vendorValue: nil, rrCount: 3),
        ])
        XCTAssertEqual(minutes, ["03:59": 42])
    }

    func testRespirationSurvivesMissingOxygenValue() {
        XCTAssertEqual(HealthSampleMapping.respiration(from: ["Time": "03:45", "RespirationRate": "17", "OxygenValue": 0]), RespirationSample(time: "03:45", breathsPerMinute: 17))
    }

    func testRespirationRejectsEmptyReservedAndNonFiniteSlots() {
        for value in [0.0, -1, 255, 256, Double.nan, Double.infinity] {
            XCTAssertNil(HealthSampleMapping.respiration(from: ["Time": "03:45", "RespirationRate": value]))
        }
        XCTAssertNil(HealthSampleMapping.respiration(from: ["Time": "25:45", "RespirationRate": 17]))
    }
}
