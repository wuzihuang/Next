import Foundation

/// F2 §06 / F0 D05 · Daily Direction colour gates, kept free of SwiftUI so
/// NextBodySyncCore can pin the heat-map cases.
///
/// Calendar close is not a gate. The fuel page already shows live E_OUT_NOW, and
/// the heat map has to light the same day the equation exists — otherwise a user
/// who logged two slots and wore the band still sees 182 empty squares until 04:00.
public enum DailyDirectionPolicy: Sendable {
    public enum Fuel: Equatable, Sendable {
        case unlogged
        case partial(slots: Int)
        case fasted
        case confirmed
    }

    public enum Color: String, Equatable, Sendable {
        case deficit
        case level
        case surplus
        case greyNothing
        case greyNoBurn
    }

    public static func color(balance: Double?, fuel: Fuel, bandCoverage: Double) -> Color {
        switch fuel {
        case .unlogged:
            return .greyNothing
        case .partial(let slots) where slots < 2:
            return .greyNothing
        default:
            break
        }
        // 0 is "not loaded", not "wore the band 0% of the day". A computed balance
        // already required burn, so only a known-low coverage is NO BURN.
        if bandCoverage > 0 && bandCoverage < 0.5 { return .greyNoBurn }
        guard let balance else { return .greyNoBurn }
        if balance <= -150 { return .deficit }
        if balance >= 150 { return .surplus }
        return .level
    }
}
