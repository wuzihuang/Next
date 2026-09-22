import XCTest
@testable import NextBodySyncCore

/// #28 · a correction clips the band's line; it never shifts it and never fills it in.
final class SleepWindowCorrectionTests: XCTestCase {
    private let bandStart = Date(timeIntervalSince1970: 1_789_000_000)
    private func at(_ minutes: Int) -> Date { bandStart.addingTimeInterval(Double(minutes) * 60) }

    /// 22:00 light 90 · deep 120 · light 60 · awake 20 · REM 70 · light 180, ending at 07:00.
    private let night: [(stage: Int, minutes: Int, offsetMinutes: Int?)] = [
        (1, 90, 0), (0, 120, 90), (1, 60, 210), (4, 20, 270), (2, 70, 290), (1, 180, 360),
    ]

    func testTheUntouchedWindowKeepsEveryRun() {
        let runs = SleepWindowCorrection.clip(night, bandStart: bandStart, start: at(0), end: at(540))
        XCTAssertEqual(runs.map(\.minutes), [90, 120, 60, 20, 70, 180])
        XCTAssertEqual(runs.map(\.offsetMinutes), [0, 90, 210, 270, 290, 360])
    }

    func testAStartMovedLaterCutsTheFrontOffAndRebasesTheRest() {
        // "I was reading until half eleven": the first 90 minutes go, and deep sleep is now
        // the first thing in the window — at minute 0 of it, not shifted 90 minutes along.
        let runs = SleepWindowCorrection.clip(night, bandStart: bandStart, start: at(90), end: at(540))
        XCTAssertEqual(runs.map(\.stage), [0, 1, 4, 2, 1])
        XCTAssertEqual(runs.map(\.minutes), [120, 60, 20, 70, 180])
        XCTAssertEqual(runs.first?.offsetMinutes, 0)
        XCTAssertEqual(runs.map(\.minutes).reduce(0, +), 450)
    }

    func testARunStraddlingTheNewStartIsCutNotDropped() {
        let runs = SleepWindowCorrection.clip(night, bandStart: bandStart, start: at(150), end: at(540))
        XCTAssertEqual(runs.first?.stage, 0)
        XCTAssertEqual(runs.first?.minutes, 60)
        XCTAssertEqual(runs.first?.offsetMinutes, 0)
    }

    func testAnEndMovedEarlierDropsWhatCameAfterIt() {
        let runs = SleepWindowCorrection.clip(night, bandStart: bandStart, start: at(0), end: at(300))
        XCTAssertEqual(runs.map(\.stage), [1, 0, 1, 4, 2])
        XCTAssertEqual(runs.last?.minutes, 10)
    }

    /// A window stretched past the band's own record gains room and no sleep. That is what
    /// keeps a correction from being a way to invent a night.
    func testAWiderWindowAddsNoMinutes() {
        let runs = SleepWindowCorrection.clip(night, bandStart: bandStart, start: at(-120), end: at(660))
        XCTAssertEqual(runs.map(\.minutes).reduce(0, +), 540)
        XCTAssertEqual(runs.first?.offsetMinutes, 120)
    }

    func testALineWithoutOffsetsFollowsItsOwnOrder() {
        let plain: [(stage: Int, minutes: Int, offsetMinutes: Int?)] = [(1, 60, nil), (0, 60, nil), (1, 60, nil)]
        let runs = SleepWindowCorrection.clip(plain, bandStart: bandStart, start: at(30), end: at(150))
        XCTAssertEqual(runs.map(\.stage), [1, 0, 1])
        XCTAssertEqual(runs.map(\.minutes), [30, 60, 30])
        XCTAssertEqual(runs.map(\.offsetMinutes), [0, 30, 90])
    }

    func testAnEmptyWindowKeepsNothing() {
        XCTAssertTrue(SleepWindowCorrection.clip(night, bandStart: bandStart, start: at(300), end: at(300)).isEmpty)
    }

    func testReportedNightWithoutStageDataStaysEntirelyUnstaged() {
        XCTAssertEqual(SleepWindowCorrection.unstagedMinutes([], start: at(0), end: at(480)), 480)
    }

    func testExpandedWindowCountsOnlyUncoveredMinutesAsUnstaged() {
        let runs = SleepWindowCorrection.clip(night, bandStart: bandStart, start: at(-60), end: at(600))
        XCTAssertEqual(SleepWindowCorrection.unstagedMinutes(
            runs.map { ($0.stage, $0.minutes, $0.offsetMinutes) }, start: at(-60), end: at(600)), 120)
    }

    func testStageOverlapDoesNotEraseAnUnmeasuredGap() {
        XCTAssertEqual(SleepWindowCorrection.unstagedMinutes(
            [(0, 60, 0), (1, 60, 30), (2, 30, 120)], start: at(0), end: at(180)), 60)
    }

    func testADeviceIntervalIntersectingCorrectedStartIsClippedNotDropped() {
        let interval = SleepWindowCorrection.clipInterval(start: at(0), end: at(180),
                                                          windowStart: at(60), windowEnd: at(240))
        XCTAssertEqual(interval?.start, at(60))
        XCTAssertEqual(interval?.end, at(180))
    }

    func testAnOutsideDeviceIntervalDoesNotBecomeNewStageEvidence() {
        XCTAssertNil(SleepWindowCorrection.clipInterval(start: at(0), end: at(60),
                                                        windowStart: at(60), windowEnd: at(240)))
    }


    func testHRVBackfillUsesOnlyRealUnoccupiedMinutesAndHonorsInvalidations() {
        let native = at(1)
        let invalid = at(2)
        let samples = [
            VitalSample(ts: native.addingTimeInterval(10), hr: nil, stress: nil, hrv: 50),
            VitalSample(ts: invalid.addingTimeInterval(10), hr: nil, stress: nil, hrv: 60),
            VitalSample(ts: at(3), hr: nil, stress: nil, hrv: 42),
            VitalSample(ts: at(3).addingTimeInterval(10), hr: nil, stress: nil, hrv: 43),
            VitalSample(ts: at(4), hr: nil, stress: nil, hrv: nil),
            VitalSample(ts: at(5), hr: nil, stress: nil, hrv: 30, hrvValid: false),
        ]
        let filled = SleepWindowCorrection.hrvBackfill(samples: samples,
                                                       nativeMinutes: [native], invalidatedMinutes: [invalid])
        XCTAssertEqual(filled.map(\.ts), [at(3)])
        XCTAssertEqual(filled.map(\.hrv), [42])
    }


    func testLegacyStageLineUsesOriginalIntervalsBeforeClipping() {
        let runs = SleepWindowCorrection.clip([(1, 90, nil), (2, 30, nil)],
            bandStart: bandStart, start: at(80), end: at(180),
            recordedIntervals: [(at(0), at(60)), (at(120), at(180))])
        XCTAssertEqual(runs, [
            .init(stage: 1, minutes: 30, offsetMinutes: 40),
            .init(stage: 2, minutes: 30, offsetMinutes: 70),
        ])
    }

    func testExplicitStageOffsetsAreNotPositionedAgain() {
        let runs = SleepWindowCorrection.clip([(2, 30, 150)],
            bandStart: bandStart, start: at(80), end: at(180),
            recordedIntervals: [(at(0), at(60)), (at(120), at(180))])
        XCTAssertEqual(runs, [.init(stage: 2, minutes: 30, offsetMinutes: 70)])
    }


    func testRestoringExpandedReportedNightDoesNotReplaceDurationWithStageCoverage() {
        let restored = SleepWindowCorrection.restoreReportedWindow(totalMinutes: 480,
            deviceRuns: [(1, 180, nil), (0, 180, nil)],
            bandStart: at(60), start: at(0), end: at(480), recordedIntervals: [])
        XCTAssertEqual(restored.totalMinutes, 480)
        XCTAssertEqual(restored.line.map(\.minutes).reduce(0, +), 360)
        XCTAssertEqual(restored.line.first?.offsetMinutes, 60)
    }

    func testRestoringManualNightWithoutMeasurementsKeepsReportedDuration() {
        let restored = SleepWindowCorrection.restoreReportedWindow(totalMinutes: 480,
            deviceRuns: [], bandStart: at(0), start: at(0), end: at(480), recordedIntervals: [])
        XCTAssertEqual(restored.totalMinutes, 480)
        XCTAssertTrue(restored.line.isEmpty)
    }

    func testRestoringReportedNightKeepsOriginalSessionGapAndDuration() {
        let restored = SleepWindowCorrection.restoreReportedWindow(totalMinutes: 100,
            deviceRuns: [(1, 90, nil), (2, 30, nil)],
            bandStart: bandStart, start: at(80), end: at(180),
            recordedIntervals: [(at(0), at(60)), (at(120), at(180))])
        XCTAssertEqual(restored.totalMinutes, 100)
        XCTAssertEqual(restored.line, [
            .init(stage: 1, minutes: 30, offsetMinutes: 40),
            .init(stage: 2, minutes: 30, offsetMinutes: 70),
        ])
    }

}
