import XCTest
@testable import NextBodySyncCore

/// Issue #20 · using the app is wake evidence the band cannot collect.
final class SleepWakeClampTests: XCTestCase {
    private let bed = Date(timeIntervalSince1970: 1_788_400_000)

    private func night(hours: Double) -> (Date, Date) {
        (bed, bed.addingTimeInterval(hours * 3600))
    }

    func testForegroundMarkInsideTheNightEndsIt() {
        let (start, recorded) = night(hours: 8)
        let usedTheApp = start.addingTimeInterval(6.5 * 3600)

        XCTAssertEqual(SleepWakeClamp.wake(sleepStart: start, recordedWake: recorded,
                                           marks: [usedTheApp]),
                       usedTheApp)
    }

    func testTheFirstMarkWinsRatherThanTheLast() {
        let (start, recorded) = night(hours: 8)
        let first = start.addingTimeInterval(6 * 3600)
        let later = start.addingTimeInterval(7 * 3600)

        XCTAssertEqual(SleepWakeClamp.wake(sleepStart: start, recordedWake: recorded,
                                           marks: [later, first]),
                       first)
    }

    func testAGlanceWhileFallingAsleepIsNotAWake() {
        let (start, recorded) = night(hours: 8)
        let glance = start.addingTimeInterval(SleepWakeClamp.minimumNight - 60)

        XCTAssertNil(SleepWakeClamp.wake(sleepStart: start, recordedWake: recorded,
                                         marks: [glance]),
                     "a night is not erased by someone checking their phone in bed")
    }

    func testAMarkTheBandAlreadyAgreesWithChangesNothing() {
        let (start, recorded) = night(hours: 8)
        let almostWake = recorded.addingTimeInterval(-SleepWakeClamp.tolerance + 30)

        XCTAssertNil(SleepWakeClamp.wake(sleepStart: start, recordedWake: recorded,
                                         marks: [almostWake]))
    }

    func testMarksOutsideTheNightAreIgnored() {
        let (start, recorded) = night(hours: 8)
        let yesterdayEvening = start.addingTimeInterval(-2 * 3600)
        let afterBreakfast = recorded.addingTimeInterval(3600)

        XCTAssertNil(SleepWakeClamp.wake(sleepStart: start, recordedWake: recorded,
                                         marks: [yesterdayEvening, afterBreakfast]))
    }

    func testCuttingIsIdempotent() {
        let (start, recorded) = night(hours: 8)
        let mark = start.addingTimeInterval(6.5 * 3600)
        let cut = SleepWakeClamp.wake(sleepStart: start, recordedWake: recorded, marks: [mark])

        XCTAssertEqual(cut, mark)
        XCTAssertNil(SleepWakeClamp.wake(sleepStart: start, recordedWake: mark, marks: [mark]),
                     "re-reading a night already cut at this mark must not cut it again")
    }

    // MARK: the record

    private func defaults(_ name: String) throws -> UserDefaults {
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        store.removePersistentDomain(forName: name)
        return store
    }

    func testRepeatedForegroundsWithinAMinuteAreOneWaking() throws {
        let store = try defaults("nb.test.awake.coalesce")
        AwakeEvidence.record(at: bed, defaults: store)
        AwakeEvidence.record(at: bed.addingTimeInterval(20), defaults: store)
        AwakeEvidence.record(at: bed.addingTimeInterval(30), defaults: store)

        XCTAssertEqual(AwakeEvidence.marks(defaults: store), [bed])
    }

    func testMarksOlderThanTheRetentionAreDropped() throws {
        let store = try defaults("nb.test.awake.retention")
        AwakeEvidence.record(at: bed, defaults: store)
        let muchLater = bed.addingTimeInterval(AwakeEvidence.retention + 3600)
        AwakeEvidence.record(at: muchLater, defaults: store)

        XCTAssertEqual(AwakeEvidence.marks(defaults: store), [muchLater])
    }
}
