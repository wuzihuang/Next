import Foundation

/// Paper 09C · the home calories card is two numbers and one fill.
///
/// The pair is EATEN and the signed delta (`eaten − target`). Negative is still
/// short (TO GO). Positive is over (OVER). Zero is the end of 没到, not the
/// start of 超了. NEXT_MEAL stays in the data layer for the model; this card
/// never prints it. Unlogged is not 0: without a known intake the card cannot
/// say 还差 or 超了.
enum FuelCardMath {
    enum Pair: Equatable, Sendable {
        /// No known intake, or no target.
        case silent
        /// `eaten ≤ target`. Associated value is `eaten − target` (0 or negative).
        case toGo(Double)
        case over(Double)
    }

    struct Readout: Equatable, Sendable {
        var eaten: Double?
        var target: Double?
        var pair: Pair
        /// EATEN / TARGET, capped at 1. Empty when either number is missing.
        var fill: Double
    }

    static func readout(eaten: Double?, target: Double?) -> Readout {
        guard let eaten else {
            return Readout(eaten: nil, target: target, pair: .silent, fill: 0)
        }
        guard let target, target > 0 else {
            return Readout(eaten: eaten, target: target, pair: .silent, fill: 0)
        }
        let delta = eaten - target
        if delta > 0 {
            return Readout(eaten: eaten, target: target, pair: .over(delta), fill: 1)
        }
        return Readout(eaten: eaten, target: target, pair: .toGo(delta),
                       fill: min(1, eaten / target))
    }
}
