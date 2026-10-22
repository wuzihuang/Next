import XCTest
@testable import NextBodyHomeCore

/// The Home body map's data-driven hues. Low steps must never read as a warning, and the
/// gut follows what was eaten, not only how much.
final class HomeBodyColorTests: XCTestCase {
    private let neutral = BodyRGB(red: 1, green: 1, blue: 1, alpha: 0.28)
    private let green = BodyRGB(red: 0.20, green: 0.83, blue: 0.60)
    private let yellow = BodyRGB(red: 0.99, green: 0.88, blue: 0.28)
    private let orange = BodyRGB(red: 0.96, green: 0.64, blue: 0.11)
    private let orangeRed = BodyRGB(red: 0.88, green: 0.37, blue: 0.06)
    private var palette: BodyTintMath.LegPalette {
        .init(neutral: neutral, green: green, yellow: yellow, orange: orange, orangeRed: orangeRed)
    }

    func testLowOrMissingStepsStayNeutralNotWarm() {
        XCTAssertEqual(BodyTintMath.legs(steps: nil, palette: palette), neutral)
        XCTAssertEqual(BodyTintMath.legs(steps: 0, palette: palette), neutral)
        let early = BodyTintMath.legs(steps: 500, palette: palette)
        XCTAssertLessThan(early.alpha, 0.35, "a few hundred steps is still mostly gray")
        XCTAssertGreaterThan(early.blue, early.red - 0.05, "low steps must not lean orange")
    }

    func testStepsPassThroughGreenYellowOrangeAndOrangeRed() {
        assertClose(BodyTintMath.legs(steps: 8_000, palette: palette), green)
        assertClose(BodyTintMath.legs(steps: 10_000, palette: palette), yellow)
        assertClose(BodyTintMath.legs(steps: 20_000, palette: palette), orange)
        assertClose(BodyTintMath.legs(steps: 30_000, palette: palette), orangeRed)
        assertClose(BodyTintMath.legs(steps: 45_000, palette: palette), orangeRed)

        let halfway = BodyTintMath.legs(steps: 25_000, palette: palette)
        XCTAssertLessThan(halfway.green, orange.green)
        XCTAssertGreaterThan(halfway.green, orangeRed.green)
        let greening = BodyTintMath.legs(steps: 4_000, palette: palette)
        XCTAssertEqual(greening.alpha, (neutral.alpha + 1) / 2, accuracy: 0.001)
    }

    func testLegIntensityRisesWithVolume() {
        XCTAssertEqual(BodyTintMath.legsIntensity(steps: 0), 0.35, accuracy: 0.001)
        XCTAssertEqual(BodyTintMath.legsIntensity(steps: 30_000), 1, accuracy: 0.001)
        XCTAssertEqual(BodyTintMath.legsIntensity(steps: 60_000), 1, accuracy: 0.001)
    }

    func testGutMixesMacroColoursByCalories() {
        let p = BodyRGB(red: 0, green: 1, blue: 0)
        let c = BodyRGB(red: 0, green: 0, blue: 1)
        let f = BodyRGB(red: 1, green: 0, blue: 0)
        // 20 g protein = 80 kcal, 20 g carbs = 80 kcal, 20 g fat = 180 kcal.
        let mix = BodyTintMath.gut(protein: 20, carb: 20, fat: 20, proteinColor: p, carbColor: c, fatColor: f)
        XCTAssertEqual(mix?.red ?? 0, 180.0 / 340, accuracy: 0.001)
        XCTAssertEqual(mix?.green ?? 0, 80.0 / 340, accuracy: 0.001)
        XCTAssertEqual(mix?.blue ?? 0, 80.0 / 340, accuracy: 0.001)

        assertClose(BodyTintMath.gut(protein: nil, carb: 50, fat: nil, proteinColor: p, carbColor: c, fatColor: f)!, c)
        XCTAssertNil(BodyTintMath.gut(protein: nil, carb: nil, fat: nil, proteinColor: p, carbColor: c, fatColor: f))
        XCTAssertNil(BodyTintMath.gut(protein: 0, carb: 0, fat: 0, proteinColor: p, carbColor: c, fatColor: f))
    }

    private func assertClose(_ actual: BodyRGB, _ expected: BodyRGB,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.red, expected.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.alpha, expected.alpha, accuracy: 0.001, file: file, line: line)
    }
}
