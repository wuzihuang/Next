import XCTest
@testable import NextBodySyncCore

final class BodyBatteryIngestionTests: XCTestCase {
    func testInvalidRRSlotDoesNotBecomeAConsecutiveHeartbeatPair() throws {
        let sample = try XCTUnwrap(HealthSampleMapping.hrv(from: [
            "time": "01:03", "hearts": [80, 255, 100],
        ]))
        XCTAssertNil(sample.rmssdMS)
        XCTAssertEqual(sample.rrMilliseconds, [800, 1_000])
        XCTAssertEqual(sample.rrValidIndices, [0, 2])
        XCTAssertEqual(sample.rrCount, 2)
    }

    func testRRUsesOnlyAdjacentValidPairsAcrossMultipleRuns() throws {
        let sample = try XCTUnwrap(HealthSampleMapping.hrv(from: [
            "time": "01:03", "hearts": [80, 82, 255, 100, 101],
        ]))
        XCTAssertEqual(try XCTUnwrap(sample.rmssdMS), sqrt(250), accuracy: 0.001)
        XCTAssertEqual(sample.rrValidIndices, [0, 1, 3, 4])
    }

    func testNonNumericRRSlotAlsoBreaksAdjacency() throws {
        let sample = try XCTUnwrap(HealthSampleMapping.hrv(from: [
            "time": "01:03", "hearts": ["80", "missing", "100"],
        ]))
        XCTAssertNil(sample.rmssdMS)
    }

    func testEveryInvalidRRValueBreaksAdjacencyWithoutPoisoningValidRuns() throws {
        for invalid: Any in [0, 255, "NaN", Double.infinity, NSNull(), "unavailable"] {
            let sample = try XCTUnwrap(HealthSampleMapping.hrv(from: [
                "time": "01:03", "hrvValue": Double.nan,
                "hearts": [80, 82, invalid, 100, 101],
            ]))
            XCTAssertEqual(try XCTUnwrap(sample.rmssdMS), sqrt(250), accuracy: 0.001)
            XCTAssertEqual(sample.rrValidIndices, [0, 1, 3, 4])
            XCTAssertNil(sample.vendorValue)
            XCTAssertEqual(HealthSampleMapping.hrvByMinute([sample])["01:03"], sample.rmssdMS)
            XCTAssertEqual(HealthSampleMapping.hrvBySlot([sample])["01:00"], sample.rmssdMS)
        }
    }

    func testRRMissingAdjacencyProducesNoHRVMinuteOrSlot() throws {
        let sample = try XCTUnwrap(HealthSampleMapping.hrv(from: [
            "time": "01:03", "hrvValue": 60, "hearts": [80, 255, 100],
        ]))
        XCTAssertTrue(HealthSampleMapping.hrvByMinute([sample]).isEmpty)
        XCTAssertTrue(HealthSampleMapping.hrvBySlot([sample]).isEmpty)
        XCTAssertEqual(HealthSampleMapping.invalidHRVSlots([sample]), ["01:00"])
    }

    func testInvalidMinuteCannotRevokeAnotherValidMinuteInTheSameSlot() throws {
        let invalid = try XCTUnwrap(HealthSampleMapping.hrv(from: [
            "time": "01:03", "hearts": [80, 255, 100],
        ]))
        let valid = try XCTUnwrap(HealthSampleMapping.hrv(from: [
            "time": "01:04", "hearts": [80, 82, 79],
        ]))
        let missing = try XCTUnwrap(HealthSampleMapping.hrv(from: ["time": "01:09", "hearts": []]))
        XCTAssertTrue(HealthSampleMapping.invalidHRVSlots([invalid, valid, missing]).isEmpty)
        XCTAssertTrue(HealthSampleMapping.invalidHRVSlots([missing]).isEmpty)
    }

    func testNumericPayloadBoundariesRejectNonFiniteOverflowAndFractionalIntegerFields() {
        for invalid in [Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude, 6.5] {
            XCTAssertNil(HealthSampleMapping.temperature(from: [
                "hour": invalid, "minute": 0, "originalValue": 342,
            ]))
            XCTAssertNil(HealthSampleMapping.oxygen(from: ["Time": "01:03", "OxygenValue": invalid]))
        }
        XCTAssertNil(HealthSampleMapping.distanceMeters(from: Double.greatestFiniteMagnitude))
    }

    func testBeforeFourAMRefreshReadsYesterdayUserDayUsingNaturalDayOffsets() throws {
        let calendar = easternCalendar
        let now = try date("2026-09-06 02:00", calendar: calendar)
        // refreshNow first closes the previous user day, then refreshes the current one.
        let today = UserDay.containing(now, calendar: calendar)
        let previous = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today.start))
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(start: previous, now: now, calendar: calendar), [2, 1])
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(start: today.start, now: now, calendar: calendar), [1, 0])
        // readSleep receives the maximum page offset, which must name the requested wake date.
        for (start, expectedWakeDay) in [(previous, 4), (today.start, 5)] {
            let offset = try XCTUnwrap(HealthSampleMapping.deviceDayOffsets(start: start, now: now, calendar: calendar).max())
            let wakeDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: now))
            XCTAssertEqual(calendar.component(.day, from: wakeDay), expectedWakeDay)
        }
    }

    func testPagesAfterFourAMAndAtMidnightKeepTheCorrectNaturalDates() throws {
        let calendar = easternCalendar
        let noon = try date("2026-09-06 12:00", calendar: calendar)
        let today = UserDay.containing(noon, calendar: calendar)
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(start: today.start, now: noon, calendar: calendar), [0])
        let midnight = try date("2026-09-07 00:00", calendar: calendar)
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(start: today.start, now: midnight, calendar: calendar), [1, 0])
        let future = try date("2026-09-07 04:00", calendar: calendar)
        XCTAssertTrue(HealthSampleMapping.deviceDayOffsets(start: future, now: noon, calendar: calendar).isEmpty)
    }

    func testHistoricalPagesAcrossBothDSTTransitionsStayOnNaturalDates() throws {
        let calendar = easternCalendar
        for nowString in ["2026-03-09 02:00", "2026-11-02 02:00"] {
            let now = try date(nowString, calendar: calendar)
            let today = UserDay.containing(now, calendar: calendar)
            let previous = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today.start))
            XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(start: previous, now: now, calendar: calendar), [2, 1])
        }
    }

    private var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ value: String, calendar: Calendar) throws -> Date {
        try XCTUnwrap(HealthSampleMapping.sleepInstant(value, calendar: calendar))
    }
}
