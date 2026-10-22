import Foundation

/// Linear sRGB channels in 0…1. SwiftUI wraps the result in a `Color`; this stays pure
/// so the body-map hues can be tested without the app.
struct BodyRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    func mixed(with other: BodyRGB, fraction: Double) -> BodyRGB {
        let t = min(1, max(0, fraction))
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return BodyRGB(red: lerp(red, other.red), green: lerp(green, other.green),
                       blue: lerp(blue, other.blue), alpha: lerp(alpha, other.alpha))
    }
}

/// The two data-driven hues on the Home body map. Legs grade by step volume, not by
/// shortfall: low is neutral, ~8k green, 10k yellow, 20k orange, 30k+ orange-red.
/// Gut mixes the macro colours by their share of recorded calories.
enum BodyTintMath {
    struct LegPalette {
        var neutral: BodyRGB
        var green: BodyRGB
        var yellow: BodyRGB
        var orange: BodyRGB
        var orangeRed: BodyRGB
    }

    static let legStops: [Double] = [0, 8_000, 10_000, 20_000, 30_000]

    static func legs(steps: Double?, palette: LegPalette) -> BodyRGB {
        guard let steps, steps.isFinite, steps > 0 else { return palette.neutral }
        let colors = [palette.neutral, palette.green, palette.yellow, palette.orange, palette.orangeRed]
        guard let upper = legStops.firstIndex(where: { steps <= $0 }) else { return palette.orangeRed }
        let low = legStops[upper - 1], high = legStops[upper]
        return colors[upper - 1].mixed(with: colors[upper], fraction: (steps - low) / (high - low))
    }

    /// 0.35 for any reading, rising to full at 30k so heavy days glow harder.
    static func legsIntensity(steps: Double?) -> Double {
        0.35 + 0.65 * min(1, max(0, (steps ?? 0) / legStops[legStops.count - 1]))
    }

    /// Protein and carbohydrate at 4 kcal/g, fat at 9. A missing macro adds nothing;
    /// with no macro calories at all there is no composition to show.
    static func gut(protein: Int?, carb: Int?, fat: Int?,
                    proteinColor: BodyRGB, carbColor: BodyRGB, fatColor: BodyRGB) -> BodyRGB? {
        let kcal: [Double] = [Double(protein ?? 0) * 4, Double(carb ?? 0) * 4, Double(fat ?? 0) * 9]
        let colors: [BodyRGB] = [proteinColor, carbColor, fatColor]
        let parts: [(Double, BodyRGB)] = zip(kcal, colors).filter { $0.0 > 0 }
        let total = parts.reduce(0) { $0 + $1.0 }
        guard total > 0 else { return nil }
        return parts.reduce(BodyRGB(red: 0, green: 0, blue: 0)) { sum, part in
            let share = part.0 / total
            return BodyRGB(red: sum.red + part.1.red * share, green: sum.green + part.1.green * share,
                           blue: sum.blue + part.1.blue * share)
        }
    }
}
