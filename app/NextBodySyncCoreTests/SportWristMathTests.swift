import XCTest
@testable import NextBodySyncCore

final class SportWristMathTests: XCTestCase {
    func testEmptyRunningReportIsReadingNotALooseStrap() {
        XCTAssertEqual(face(hr: nil, seeking: 0), .reaching)
        XCTAssertEqual(face(hr: 0, seeking: 0), .reaching)
        XCTAssertEqual(face(hr: nil, seeking: 20), .reaching)
        XCTAssertEqual(face(hr: nil, seeking: 29.9), .reaching)
    }

    func testTightenWaitsUntilTheLockWindowHasPassed() {
        XCTAssertEqual(face(hr: nil, seeking: 30), .noContact)
        XCTAssertEqual(face(hr: nil, seeking: 45), .noContact)
    }

    func testAValidBeatIsLiveImmediately() {
        XCTAssertEqual(face(hr: 128, seeking: 2), .live)
        XCTAssertEqual(face(hr: 50, seeking: 40, hadHeart: true, silent: 0), .live)
    }

    func testPauseWinsOverAMissingBeat() {
        XCTAssertEqual(SportWristMath.face(runState: 2, heartRate: nil,
                                          hadHeart: false, seekingFor: 40, silentFor: 40),
                       .paused)
    }

    func testADropoutAfterLockIsReadingUntilTheLiveWindowEnds() {
        XCTAssertEqual(face(hr: nil, seeking: 40, hadHeart: true, silent: 0), .reaching)
        XCTAssertEqual(face(hr: nil, seeking: 40, hadHeart: true, silent: 14.9), .reaching)
        XCTAssertEqual(face(hr: nil, seeking: 40, hadHeart: true, silent: 15), .noContact)
    }

    private func face(hr: Int?, seeking: TimeInterval, hadHeart: Bool = false,
                      silent: TimeInterval = .greatestFiniteMagnitude) -> SportWristMath.Face {
        SportWristMath.face(runState: 1, heartRate: hr, hadHeart: hadHeart,
                            seekingFor: seeking, silentFor: silent)
    }
}
