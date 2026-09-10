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
}
