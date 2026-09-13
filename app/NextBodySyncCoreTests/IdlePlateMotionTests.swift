import XCTest
@testable import NextBodySyncCore

final class IdlePlateMotionTests: XCTestCase {
    func testSaturnLookMovesBetweenTwoClocks() {
        let still = IdlePlateMotion.samples(plate: 1, clock: 0, moving: true)
        let later = IdlePlateMotion.samples(plate: 1, clock: 1, moving: true)
        XCTAssertNotEqual(still, later)
        XCTAssertEqual(still.count, later.count)
        XCTAssertGreaterThan(still.count, 4)
    }

    func testNonSphereLoopMovesBetweenTwoClocks() {
        let still = IdlePlateMotion.samples(plate: 10, clock: 0, moving: true)
        let later = IdlePlateMotion.samples(plate: 10, clock: 1, moving: true)
        XCTAssertNotEqual(still, later)
        let arcs = IdlePlateMotion.samples(plate: 4, clock: 0, moving: true)
        let arcsLater = IdlePlateMotion.samples(plate: 4, clock: 1, moving: true)
        XCTAssertNotEqual(arcs, arcsLater)
    }

    func testReduceMotionHoldsThePose() {
        let a = IdlePlateMotion.samples(plate: 1, clock: 0, moving: false)
        let b = IdlePlateMotion.samples(plate: 1, clock: 12, moving: false)
        XCTAssertEqual(a, b)
        let c = IdlePlateMotion.samples(plate: 10, clock: 0, moving: false)
        let d = IdlePlateMotion.samples(plate: 10, clock: 9, moving: false)
        XCTAssertEqual(c, d)
        XCTAssertEqual(
            IdlePlateMotion.pose(plate: 1, clock: 0, moving: false),
            IdlePlateMotion.pose(plate: 1, clock: 3, moving: false))
    }

    func testDayPoolLooksAllMoveWhenAsked() {
        for plate in IdlePlateLock.dayPool {
            let a = IdlePlateMotion.samples(plate: plate, clock: 0, moving: true)
            let b = IdlePlateMotion.samples(plate: plate, clock: 1, moving: true)
            XCTAssertNotEqual(a, b, "plate \(plate) is a still")
            let hold = IdlePlateMotion.samples(plate: plate, clock: 0, moving: false)
            let held = IdlePlateMotion.samples(plate: plate, clock: 2, moving: false)
            XCTAssertEqual(hold, held, "plate \(plate) drifted under Reduce Motion")
        }
    }

    func testEventLooksMoveWhenAsked() {
        for plate in [11, 20, 25] {
            let a = IdlePlateMotion.samples(plate: plate, clock: 0, moving: true)
            let b = IdlePlateMotion.samples(plate: plate, clock: 1, moving: true)
            XCTAssertNotEqual(a, b, "event plate \(plate) is a still")
        }
    }
}
