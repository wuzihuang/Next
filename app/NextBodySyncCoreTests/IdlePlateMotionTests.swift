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
        // yaw once a loop, pitch twice: a figure eight through the rest seat, not a rock along
        // one line and not the old pitch that only ever nodded one way (0...2).
        let eighth = IdlePlateMotion.pose(
            plate: 23, clock: IdlePlateMotion.loopSeconds / 8, moving: true)
        XCTAssertEqual(eighth.moonYaw, sin(.pi / 4), accuracy: 1e-9)
        XCTAssertEqual(eighth.moonPitch, 1, accuracy: 1e-9)
        let mid = IdlePlateMotion.pose(plate: 23, clock: IdlePlateMotion.loopSeconds / 2, moving: true)
        XCTAssertEqual(mid.moonYaw, 0, accuracy: 1e-9)
        XCTAssertEqual(mid.moonPitch, 0, accuracy: 1e-9)
        XCTAssertEqual(
            IdlePlateMotion.pose(plate: 23, clock: 0, moving: true),
            IdlePlateMotion.pose(plate: 23, clock: IdlePlateMotion.loopSeconds, moving: true))
    }

    func testPlate02SitsInTheField() {
        let p = IdlePlateMotion.pose(plate: 2, clock: 0, moving: false)
        XCTAssertEqual(p.bodyX, 179, accuracy: 1e-9)
        XCTAssertEqual(p.bodyY, 196, accuracy: 1e-9)
        let moon = IdlePlateMotion.around(
            cx: 179, cy: 196, restX: 292, restY: 168, flatten: 0.30, u: 0)
        XCTAssertEqual(moon.x, 292, accuracy: 1e-9)
        XCTAssertEqual(moon.y, 168, accuracy: 1e-9)
        let far = IdlePlateMotion.around(
            cx: 179, cy: 196, restX: 292, restY: 168, flatten: 0.30, u: 0.5)
        XCTAssertGreaterThan(abs(far.x - moon.x), 80)
    }

    func testPlate10TravelerSeatsOnTheTrail() {
        let rest = IdlePlateMotion.around(
            cx: 179, cy: 200, restX: 14, restY: 94, flatten: 0.20, u: 0)
        let far = IdlePlateMotion.around(
            cx: 179, cy: 200, restX: 14, restY: 94, flatten: 0.20, u: 0.5)
        XCTAssertEqual(rest.x, 14, accuracy: 1e-9)
        XCTAssertEqual(rest.y, 94, accuracy: 1e-9)
        XCTAssertEqual(far.x, 179 - (14 - 179), accuracy: 1e-9)
        XCTAssertGreaterThan(abs(far.x - rest.x), 200)
        XCTAssertEqual(
            IdlePlateMotion.pose(plate: 10, clock: 0, moving: true).satellite, 0, accuracy: 1e-9)
        XCTAssertEqual(
            IdlePlateMotion.pose(plate: 10, clock: 4, moving: true).satellite, 0.5, accuracy: 1e-9)
    }

    func testPlate23SkyPipStaysOnTheBoard() {
        for k in 0...16 {
            let o = IdlePlateMotion.around(
                cx: 179, cy: 38, restX: 300, restY: 42, flatten: 0.22, u: Double(k) / 16)
            XCTAssertGreaterThan(o.x, 8, "plate 23 pip left the board at u=\(k)/16")
            XCTAssertLessThan(o.x, 350, "plate 23 pip left the board at u=\(k)/16")
            XCTAssertGreaterThan(o.y, 4, "plate 23 pip left the sky at u=\(k)/16")
            XCTAssertLessThan(o.y, 90, "plate 23 pip dropped into the disc at u=\(k)/16")
        }
    }

    func testPlate16MoonRidesAClosedOrbit() {
        let rest = IdlePlateMotion.around(
            cx: 210, cy: 140, restX: 302, restY: 88, flatten: 0.30, u: 0)
        let far = IdlePlateMotion.around(
            cx: 210, cy: 140, restX: 302, restY: 88, flatten: 0.30, u: 0.5)
        XCTAssertEqual(rest.x, 302, accuracy: 1e-9)
        XCTAssertEqual(rest.y, 88, accuracy: 1e-9)
        XCTAssertGreaterThan(abs(far.x - rest.x), 80)
    }

    /// A ring's tilt is set by the planet's spin axis. It held a full 360 deg revolution per
    /// loop until 2026-09-15, which is what made the whole set read as clockwork.
    func testRingsHoldTheirTiltAllLoop() {
        for plate in IdlePlateLock.dayPool + [11, 20, 25] {
            let rest = IdlePlateMotion.pose(plate: plate, clock: 0, moving: true).ringDeg
            for k in 1...16 {
                let deg = IdlePlateMotion.pose(
                    plate: plate,
                    clock: IdlePlateMotion.loopSeconds * Double(k) / 16,
                    moving: true).ringDeg
                XCTAssertEqual(deg, rest, accuracy: 1e-9, "plate \(plate) ring spun")
            }
        }
        let hold = IdlePlateMotion.pose(plate: 7, clock: 3, moving: false)
        XCTAssertEqual(hold.ringDeg, -24, accuracy: 1e-9)
    }

    /// Dashes on an orbit track are tick marks on a path, not a conveyor belt.
    func testOrbitTicksNeverCrawl() {
        for plate in IdlePlateLock.dayPool + [11, 20, 25] {
            for k in 0...8 {
                let p = IdlePlateMotion.pose(
                    plate: plate,
                    clock: IdlePlateMotion.loopSeconds * Double(k) / 8,
                    moving: true)
                XCTAssertEqual(p.dash, 0, accuracy: 1e-9, "plate \(plate) dash crawled")
            }
        }
    }

    /// Kepler's second law: the body sweeps equal areas in equal times, so its progress along
    /// the orbit is not the clock. It still passes the rest seat at 0 and the far side at 1/2.
    func testOrbitProgressIsKeplerNotLinear() {
        XCTAssertEqual(IdlePlateMotion.orbitProgress(0), 0, accuracy: 1e-9)
        XCTAssertEqual(IdlePlateMotion.orbitProgress(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(IdlePlateMotion.orbitProgress(1), 1, accuracy: 1e-9)
        let quarter = IdlePlateMotion.orbitProgress(0.25)
        XCTAssertLessThan(quarter, 0.22, "quarter of the clock is a quarter of the orbit")
        XCTAssertGreaterThan(quarter, 0.10)
        var last = 0.0
        for k in 1...64 {
            let u = IdlePlateMotion.orbitProgress(Double(k) / 64)
            XCTAssertGreaterThan(u, last, "orbit reversed at \(k)/64")
            last = u
        }
    }

    /// Light is never a single sine, and it is exactly 1 at the Paper rest seat.
    func testFlickerSeatsAtRestAndSeams() {
        XCTAssertEqual(IdlePlateMotion.flicker(0, 3), 0, accuracy: 1e-9)
        XCTAssertEqual(IdlePlateMotion.flicker(1, 3), 0, accuracy: 1e-12)
        let a = IdlePlateMotion.pose(plate: 1, clock: 2, moving: true)
        let b = IdlePlateMotion.pose(plate: 1, clock: 6, moving: true)
        XCTAssertNotEqual(a.glow, b.glow, "glow is a plain sine")
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
