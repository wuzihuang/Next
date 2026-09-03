import XCTest
@testable import NextBodySyncCore

final class HealthSampleMappingTests: XCTestCase {
    func testHistoricalUserDayReadsItsCalendarDayAndTheFollowingCalendarDay() {
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(daysBack: 1, straddles: true), [1, 0])
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(daysBack: 2, straddles: true), [2, 1])
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(daysBack: 0, straddles: true), [0, 1])
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(daysBack: 0, straddles: false), [0])
    }

    func testSameClockOnAdjacentDevicePagesKeepsDistinctCalendarDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let secondDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))

        let first = try XCTUnwrap(HealthSampleMapping.instant(time: "01:30", calendarDay: firstDay,
                                                               calendar: calendar))
        let second = try XCTUnwrap(HealthSampleMapping.instant(time: "01:30", calendarDay: secondDay,
                                                                calendar: calendar))
        XCTAssertEqual(second.timeIntervalSince(first), 24 * 60 * 60, accuracy: 0.1)
    }

    func testTemperatureUsesSkinValueAndNormalizesTenths() {
        let sample = HealthSampleMapping.temperature(from: [
            "hour": 6,
            "minute": 5,
            "value": 368,
            "originalValue": 342,
        ])

        let value = try? XCTUnwrap(sample)
        XCTAssertEqual(value?.time, "06:05")
        XCTAssertEqual(value?.celsius ?? 0, 34.2, accuracy: 0.001)
    }

    func testTemperatureRejectsMissingAndOutOfRangeSkinValues() {
        XCTAssertNil(HealthSampleMapping.temperature(from: ["hour": 6, "minute": 5, "value": 36.8]))
        XCTAssertNil(HealthSampleMapping.temperature(from: [
            "hour": 24, "minute": 5, "originalValue": 34.2,
        ]))
        XCTAssertNil(HealthSampleMapping.temperature(from: [
            "hour": 6, "minute": 5, "originalValue": 99.0,
        ]))
    }

    func testHRVComputesRMSSDFromTenMillisecondRRUnits() {
        let sample = HealthSampleMapping.hrv(from: [
            "time": "01:03",
            "hrvValue": 47,
            "hearts": ["80", "82", "79"],
        ])

        let value = try? XCTUnwrap(sample)
        XCTAssertEqual(value?.time, "01:03")
        XCTAssertEqual(value?.vendorValue, 47)
        XCTAssertEqual(value?.rmssdMS ?? 0, sqrt(650), accuracy: 0.001)
        XCTAssertEqual(value?.rrCount, 3)
    }

    func testHRVNeverLabelsVendorOnlyValueAsRMSSD() {
        let sample = HealthSampleMapping.hrv(from: [
            "time": "01:03",
            "hrvValue": 47,
            "hearts": [],
        ])

        XCTAssertEqual(sample?.vendorValue, 47)
        XCTAssertNil(sample?.rmssdMS)
    }

    func testNightHRVIsMedianOfFifteenMinuteBucketMedians() {
        let samples = [
            HrvMinuteSample(time: "00:01", rmssdMS: 30, vendorValue: nil, rrCount: 8),
            HrvMinuteSample(time: "00:06", rmssdMS: 50, vendorValue: nil, rrCount: 9),
            HrvMinuteSample(time: "00:16", rmssdMS: 80, vendorValue: nil, rrCount: 10),
            HrvMinuteSample(time: "12:00", rmssdMS: 100, vendorValue: nil, rrCount: 11),
        ]

        let night = HealthSampleMapping.nightHRV(from: samples)

        let value = try? XCTUnwrap(night)
        XCTAssertEqual(value?.rmssdMS ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(value?.bucketCount, 2)
        XCTAssertEqual(value?.rrCount, 27)
    }
}
