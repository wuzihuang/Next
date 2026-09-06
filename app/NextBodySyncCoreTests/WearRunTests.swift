import XCTest
@testable import NextBodySyncCore

final class WearRunTests: XCTestCase {
    private let day = UserDay.containing(
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12))!)

    func testNoElapsedSlotIsNotWorn() {
        XCTAssertFalse(WearRun.isWornDay(samples: [], day: day, now: day.start))
    }

    func testHalfTheElapsedSlotsWithHeartIsWorn() {
        let now = day.start.addingTimeInterval(600)
        let samples = [
            tick(at: 0, hr: 64),
        ]
        XCTAssertTrue(WearRun.isWornDay(samples: samples, day: day, now: now))
    }

    func testOneOfThreeElapsedSlotsIsNotWorn() {
        let now = day.start.addingTimeInterval(900)
        XCTAssertFalse(WearRun.isWornDay(samples: [tick(at: 0, hr: 64)], day: day, now: now))
    }

    func testTemperatureAloneIsNotWristEvidence() {
        let now = day.start.addingTimeInterval(600)
        let sample = VitalSample(ts: day.start, hr: nil, stress: nil, temp: 33.1)
        XCTAssertFalse(WearRun.isWornDay(samples: [sample], day: day, now: now))
    }

    func testPositiveStepsCountAsWristEvidence() {
        let now = day.start.addingTimeInterval(300)
        let sample = VitalSample(ts: day.start, hr: nil, stress: nil, steps: 12)
        XCTAssertTrue(WearRun.isWornDay(samples: [sample], day: day, now: now))
    }

    func testTicksInTheOpenSlotDoNotCount() {
        let now = day.start.addingTimeInterval(420)
        let sample = VitalSample(ts: day.start.addingTimeInterval(360), hr: 70, stress: nil)
        XCTAssertFalse(WearRun.isWornDay(samples: [sample], day: day, now: now))
    }

    func testFirstMorningWithoutWearIsGray() {
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: nil), .gray)
    }

    func testFirstWornDayIsLiveOne() {
        XCTAssertEqual(WearRun.display(todayWorn: true, yesterday: nil), .live(1))
    }

    func testOpenTodayAddsToYesterdaysRun() {
        let yesterday = WearRun.Yesterday(worn: true, run: 3, miss: 0)
        XCTAssertEqual(WearRun.display(todayWorn: true, yesterday: yesterday), .live(4))
    }

    func testOpenTodayDoesNotAmberWhenNotYetWorn() {
        let yesterday = WearRun.Yesterday(worn: true, run: 3, miss: 0)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: yesterday), .live(3))
    }

    func testOneClosedMissIsAmberAndHasNoNumber() {
        let yesterday = WearRun.Yesterday(worn: false, run: 0, miss: 1)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: yesterday), .amber)
    }

    func testSecondClosedMissIsGray() {
        let yesterday = WearRun.Yesterday(worn: false, run: 0, miss: 2)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: yesterday), .gray)
    }

    func testWearingOnAmberRestartsAtOne() {
        let yesterday = WearRun.Yesterday(worn: false, run: 0, miss: 1)
        XCTAssertEqual(WearRun.display(todayWorn: true, yesterday: yesterday), .live(1))
    }

    private func tick(at slot: Int, hr: Int?) -> VitalSample {
        VitalSample(ts: day.start.addingTimeInterval(TimeInterval(slot) * 300), hr: hr, stress: nil)
    }
}
