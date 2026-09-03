import XCTest
@testable import NextBodySyncCore

final class HealthSampleMappingTests: XCTestCase {
    func testAutomaticMeasurementIntervalsOfferSubStepProbesBelowTheDeviceStep() {
        XCTAssertEqual(
            AutoMeasurementIntervalPolicy.options(minimumStepMinutes: 5),
            [1, 2, 3, 4] + Array(stride(from: 5, through: 180, by: 5))
        )
        XCTAssertEqual(
            AutoMeasurementIntervalPolicy.options(minimumStepMinutes: 1),
            Array(1...180)
        )
        XCTAssertEqual(
            AutoMeasurementIntervalPolicy.options(minimumStepMinutes: 7),
            [1, 2, 3, 4, 5, 6] + Array(stride(from: 7, through: 175, by: 7))
        )
    }

    func testZeroStepMeansEveryWholeMinuteValueIncludingZeroIsSupported() {
        let options = AutoMeasurementIntervalPolicy.options(minimumStepMinutes: 0)

        XCTAssertEqual(options.first, 0)
        XCTAssertEqual(options.last, 180)
        XCTAssertEqual(options.count, 181)
    }

    func testAutomaticMeasurementIntervalValidationRejectsOutOfRangeValues() {
        XCTAssertTrue(AutoMeasurementIntervalPolicy.isValid(1, minimumStepMinutes: 1))
        XCTAssertTrue(AutoMeasurementIntervalPolicy.isValid(15, minimumStepMinutes: 5))
        XCTAssertTrue(AutoMeasurementIntervalPolicy.isValid(3, minimumStepMinutes: 5))
        XCTAssertFalse(AutoMeasurementIntervalPolicy.isValid(185, minimumStepMinutes: 5))
        XCTAssertFalse(AutoMeasurementIntervalPolicy.isValid(-1, minimumStepMinutes: 0))
        XCTAssertTrue(AutoMeasurementIntervalPolicy.isValid(180, minimumStepMinutes: 0))
        XCTAssertFalse(AutoMeasurementIntervalPolicy.isValid(181, minimumStepMinutes: 0))
    }

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

    func testHRVBySlotFloorsAMeasuredMinuteOntoItsFiveMinuteSlot() {
        let slots = HealthSampleMapping.hrvBySlot([
            HrvMinuteSample(time: "00:00", rmssdMS: 44, vendorValue: 43, rrCount: 4),
            HrvMinuteSample(time: "00:12", rmssdMS: 51, vendorValue: 43, rrCount: 4),
            HrvMinuteSample(time: "23:57", rmssdMS: 35, vendorValue: 33, rrCount: 4),
        ])

        XCTAssertEqual(slots["00:00"], 44)
        XCTAssertEqual(slots["00:10"], 51)
        XCTAssertEqual(slots["23:55"], 35)
        XCTAssertEqual(slots.count, 3)
    }

    func testHRVBySlotKeepsTheMedianWhenOneSlotCaughtSeveralMinutes() {
        let slots = HealthSampleMapping.hrvBySlot([
            HrvMinuteSample(time: "06:00", rmssdMS: 30, vendorValue: nil, rrCount: 4),
            HrvMinuteSample(time: "06:01", rmssdMS: 90, vendorValue: nil, rrCount: 4),
            HrvMinuteSample(time: "06:02", rmssdMS: 40, vendorValue: nil, rrCount: 4),
        ])

        XCTAssertEqual(slots["06:00"], 40)
    }

    func testHRVBySlotDropsVendorOnlyAndImplausibleMinutes() {
        let slots = HealthSampleMapping.hrvBySlot([
            HrvMinuteSample(time: "07:00", rmssdMS: nil, vendorValue: 47, rrCount: 1),
            HrvMinuteSample(time: "07:05", rmssdMS: 900, vendorValue: 47, rrCount: 4),
            HrvMinuteSample(time: "07:10", rmssdMS: 0, vendorValue: 47, rrCount: 4),
            HrvMinuteSample(time: "07:15", rmssdMS: 48, vendorValue: 47, rrCount: 4),
        ])

        XCTAssertEqual(slots, ["07:15": 48])
    }

    func testOriginDistanceKilometresBecomeMetres() {
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: 0.036), 36)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: "0.036"), 36)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: NSNumber(value: 1.2)), 1_200)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: 0), 0)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: "0.000"), 0)
    }

    func testOriginDistanceAlreadyInMetresIsLeftAlone() {
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: 36), 36)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: "40"), 40)
    }

    func testOriginDistanceRejectsMissingAndNegativeValues() {
        XCTAssertNil(HealthSampleMapping.distanceMeters(from: nil))
        XCTAssertNil(HealthSampleMapping.distanceMeters(from: -0.1))
        XCTAssertNil(HealthSampleMapping.distanceMeters(from: "nope"))
    }
}
