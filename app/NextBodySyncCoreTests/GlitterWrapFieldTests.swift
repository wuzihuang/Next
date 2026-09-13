import XCTest
@testable import NextBodySyncCore

final class GlitterWrapFieldTests: XCTestCase {
    func testThinkingPresetIsThePastedOriginkitWrap() {
        let c = GlitterWrapConfig.thinking
        XCTAssertEqual(c.particleCount, 773)
        XCTAssertEqual(c.color1.r, 255)
        XCTAssertEqual(c.color1.g, 255)
        XCTAssertEqual(c.color1.b, 255)
        XCTAssertEqual(c.color2.r, Double(0xB0))
        XCTAssertEqual(c.color2.g, Double(0xB0))
        XCTAssertEqual(c.color2.b, Double(0xBA))
        XCTAssertEqual(c.color3.r, Double(0xEF))
        XCTAssertEqual(c.color3.g, Double(0xF6))
        XCTAssertEqual(c.color3.b, Double(0x5A))
        XCTAssertEqual(c.speed, 4)
        XCTAssertEqual(c.density, 77)
        XCTAssertEqual(c.starSize, 18)
        XCTAssertEqual(c.focalDepth, 7)
        XCTAssertEqual(c.turbulence, 0)
        XCTAssertEqual(c.brightness, 100)
        XCTAssertEqual(c.glitterIntensity, 3)
        XCTAssertEqual(c.trailAmount, 67)
        XCTAssertTrue(c.reverse)
        let field = GlitterWrapField(config: c, seed: 7, width: 358, height: 470)
        XCTAssertEqual(field.stars.count, c.particleCount)
        XCTAssertEqual(field.config.palette.count, 3)
    }

    func testReverseProjectionShrinksAsZIncreases() {
        let d = GlitterWrapDerived(.thinking)
        XCTAssertTrue(d.reverse)
        let w = 358.0, h = 470.0
        let near = GlitterWrapField.project(
            x: 1, y: 0, z: d.focalDepth, width: w, height: h, focalDepth: d.focalDepth)
        let mid = GlitterWrapField.project(
            x: 1, y: 0, z: 0.5, width: w, height: h, focalDepth: d.focalDepth)
        let far = GlitterWrapField.project(
            x: 1, y: 0, z: 0.99, width: w, height: h, focalDepth: d.focalDepth)
        XCTAssertGreaterThan(near.radius, mid.radius)
        XCTAssertGreaterThan(mid.radius, far.radius)
    }

    func testStepMovesTheFieldAndPauseHoldsIt() {
        let field = GlitterWrapField(config: .thinking, seed: 11, width: 358, height: 470)
        let still = field.samples()
        field.step(deltaSec: 1.0 / 60.0, moving: true)
        let later = field.samples()
        XCTAssertNotEqual(still, later)
        XCTAssertEqual(still.count, later.count)
        XCTAssertGreaterThan(still.count, 4)

        let held = field.samples()
        field.step(deltaSec: 1.0 / 60.0, moving: false)
        field.step(deltaSec: 12, moving: false)
        XCTAssertEqual(field.samples(), held)
    }

    func testTrailKeepUsesOriginkitPowClamp() {
        let keep60 = GlitterWrapField.trailKeep(trailAmount: 67, deltaSec: 1.0 / 60.0)
        XCTAssertEqual(keep60, pow(0.67, 1.0), accuracy: 1e-12)
        let alpha60 = GlitterWrapField.trailAlpha(trailAmount: 67, deltaSec: 1.0 / 60.0)
        XCTAssertEqual(alpha60, max(0.02, 1 - keep60), accuracy: 1e-12)

        let capped = GlitterWrapField.trailKeep(trailAmount: 100, deltaSec: 1.0 / 60.0)
        XCTAssertEqual(capped, pow(0.98, 1.0), accuracy: 1e-12)

        let tiny = GlitterWrapField.trailKeep(trailAmount: 67, deltaSec: 0)
        XCTAssertEqual(tiny, pow(0.67, 0.06), accuracy: 1e-12)
        XCTAssertEqual(GlitterWrapField.frameDt(deltaSec: 0), 0.06, accuracy: 1e-12)
        XCTAssertEqual(GlitterWrapField.frameDt(deltaSec: 1), 6, accuracy: 1e-12)
    }

    func testGlitterRaisesFlashMultAboveOne() {
        let field = GlitterWrapField(config: .thinking, seed: 42, width: 358, height: 470)
        let glitter = GlitterWrapDerived(.thinking).glitter
        XCTAssertGreaterThan(glitter, 0)
        var peak = 1.0
        for _ in 0..<1200 {
            let frame = field.step(deltaSec: 1.0 / 60.0, moving: true)
            if let m = frame.stamps.map(\.flashMult).max() {
                peak = max(peak, m)
            }
            if peak > 1 { break }
        }
        XCTAssertGreaterThan(peak, 1)
        XCTAssertEqual(peak, 1 + 2.5 * glitter, accuracy: 1e-9)
    }

    func testEdgeGainIsBrightInTheMiddleAndGoneAtTheRim() {
        let w = 358.0, h = 470.0
        let core = GlitterWrapField.edgeGain(x: w / 2, y: h / 2, width: w, height: h)
        let mid = GlitterWrapField.edgeGain(x: w / 2 + w * 0.40, y: h / 2, width: w, height: h)
        let left = GlitterWrapField.edgeGain(x: 4, y: h / 2, width: w, height: h)
        let top = GlitterWrapField.edgeGain(x: w / 2, y: 6, width: w, height: h)
        XCTAssertGreaterThan(core, 0.9)
        XCTAssertGreaterThan(core, mid)
        XCTAssertGreaterThan(mid, left)
        XCTAssertGreaterThan(core, top)
        XCTAssertLessThan(left, 0.5)
        XCTAssertLessThan(top, 0.5)
    }

    func testStampsStayOnTheThinkingPalette() {
        let field = GlitterWrapField(config: .thinking, seed: 3, width: 358, height: 470)
        let frame = field.step(deltaSec: 1.0 / 60.0, moving: true)
        XCTAssertFalse(frame.stamps.isEmpty)
        for stamp in frame.stamps {
            XCTAssertTrue((0..<3).contains(stamp.colorIdx))
        }
        XCTAssertEqual(Set(field.stars.map(\.colorIdx)).isSubset(of: Set([0, 1, 2])), true)
    }
}
