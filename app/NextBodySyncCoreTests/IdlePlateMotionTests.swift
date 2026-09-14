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
            IdlePlateMotion.pose(plate: 1, clock: 8, moving: false))
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

    func testLoopSeams() {
        for plate in IdlePlateLock.dayPool + [11, 20, 25] {
            XCTAssertEqual(
                IdlePlateMotion.pose(plate: plate, clock: 0, moving: true),
                IdlePlateMotion.pose(plate: plate, clock: IdlePlateMotion.loopSeconds, moving: true),
                "plate \(plate) does not seam")
        }
    }

    func testPlate01MoonRidesAClosedOrbit() {
        let rest = IdlePlateMotion.pose(plate: 1, clock: 0, moving: true)
        let mid = IdlePlateMotion.pose(plate: 1, clock: IdlePlateMotion.loopSeconds / 2, moving: true)
        XCTAssertEqual(rest.satellite, 0, accuracy: 1e-9)
        XCTAssertEqual(mid.satellite, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rest.ringDeg, -14, accuracy: 1e-9)
        XCTAssertEqual(mid.ringDeg, -14, accuracy: 1e-9)
        XCTAssertEqual(rest.glow, 1, accuracy: 1e-9)
        let seat = IdlePlateMotion.around(
            cx: 179, cy: 188, restX: 289.5, restY: 217.5, flatten: 0.28, u: 0)
        let far = IdlePlateMotion.around(
            cx: 179, cy: 188, restX: 289.5, restY: 217.5, flatten: 0.28, u: 0.5)
        XCTAssertEqual(seat.x, 289.5, accuracy: 1e-9)
        XCTAssertEqual(seat.y, 217.5, accuracy: 1e-9)
        XCTAssertEqual(far.x, 179 - (289.5 - 179), accuracy: 1e-9)
        XCTAssertEqual(far.y, 188 - (217.5 - 188), accuracy: 1e-9)
        XCTAssertGreaterThan(abs(far.x - seat.x), 80)
    }

    func testOrbitSeamsAndHidesTheFarHalf() {
        let a = IdlePlateMotion.around(
            cx: 0, cy: 0, restX: 100, restY: 0, flatten: 0.3, u: 0)
        let b = IdlePlateMotion.around(
            cx: 0, cy: 0, restX: 100, restY: 0, flatten: 0.3, u: 1)
        let near = IdlePlateMotion.around(
            cx: 0, cy: 0, restX: 100, restY: 0, flatten: 0.3, u: 0.25)
        let rear = IdlePlateMotion.around(
            cx: 0, cy: 0, restX: 100, restY: 0, flatten: 0.3, u: 0.75)
        XCTAssertEqual(a, b)
        XCTAssertTrue(near.front)
        XCTAssertFalse(rear.front)
    }

    func testPaperHoldGeometry() {
        let p5 = IdlePlateMotion.pose(plate: 5, clock: 0, moving: false)
        XCTAssertEqual(p5.ringDeg, -22, accuracy: 1e-9)
        XCTAssertEqual(p5.bodyY, 178, accuracy: 1e-9)
        let p11 = IdlePlateMotion.pose(plate: 11, clock: 0, moving: false)
        XCTAssertEqual(p11.bodyX, 560, accuracy: 1e-9)
        XCTAssertEqual(p11.bodyY, 150, accuracy: 1e-9)
        let p12 = IdlePlateMotion.pose(plate: 12, clock: 0, moving: false)
        XCTAssertEqual(p12.bodyY, 188, accuracy: 1e-9)
        let p21 = IdlePlateMotion.pose(plate: 21, clock: 0, moving: false)
        XCTAssertEqual(p21.bodyX, -60, accuracy: 1e-9)
        XCTAssertEqual(p21.bodyY, 240, accuracy: 1e-9)
        XCTAssertEqual(p21.satellite, 0, accuracy: 1e-9)
        let p26 = IdlePlateMotion.pose(plate: 26, clock: 0, moving: false)
        XCTAssertEqual(p26.bodyX, 250, accuracy: 1e-9)
        XCTAssertEqual(p26.bodyY, 230, accuracy: 1e-9)
        let p8 = IdlePlateMotion.pose(plate: 8, clock: 0, moving: false)
        XCTAssertEqual(p8.bodyX, 140, accuracy: 1e-9)
        XCTAssertEqual(p8.bodyY, 190, accuracy: 1e-9)
        let p14 = IdlePlateMotion.pose(plate: 14, clock: 0, moving: false)
        XCTAssertEqual(p14.bodyX, 179, accuracy: 1e-9)
        XCTAssertEqual(p14.bodyY, 195, accuracy: 1e-9)
        let p19 = IdlePlateMotion.pose(plate: 19, clock: 0, moving: false)
        XCTAssertEqual(p19.ringDeg, -13, accuracy: 1e-9)
        let p23 = IdlePlateMotion.pose(plate: 23, clock: 0, moving: true)
        XCTAssertEqual(p23.moonYaw, 0, accuracy: 1e-9)
        XCTAssertEqual(p23.moonPitch, 0, accuracy: 1e-9)
    }

    func testPlate23LibratesThenSeams() {
        let mid = IdlePlateMotion.pose(plate: 23, clock: IdlePlateMotion.loopSeconds / 2, moving: true)
        XCTAssertEqual(mid.moonYaw, 0, accuracy: 1e-9)
        XCTAssertEqual(mid.moonPitch, 2, accuracy: 1e-9)
        XCTAssertEqual(
            IdlePlateMotion.pose(plate: 23, clock: 0, moving: true),
            IdlePlateMotion.pose(plate: 23, clock: IdlePlateMotion.loopSeconds, moving: true))
    }

    func testPlate21PipStaysOnTheDashedArc() {
        let rest = IdlePlateMotion.alongArc(
            x1: 169, y1: 128, rx: 300, ry: 110, deg: -12,
            large: false, sweep: true, x2: 140, y2: 286,
            restU: 0.63, swing: 0.36, u: 0)
        XCTAssertEqual(rest.x, 223.9, accuracy: 1.5)
        XCTAssertEqual(rest.y, 218.1, accuracy: 1.5)
        for k in 0...16 {
            let o = IdlePlateMotion.alongArc(
                x1: 169, y1: 128, rx: 300, ry: 110, deg: -12,
                large: false, sweep: true, x2: 140, y2: 286,
                restU: 0.63, swing: 0.36, u: Double(k) / 16)
            XCTAssertGreaterThan(o.x, 142, "plate 21 left the visible arc at u=\(k)/16")
        }
    }
}
