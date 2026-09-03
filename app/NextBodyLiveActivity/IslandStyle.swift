import SwiftUI

/// The house palette and type, as much of it as the island needs.
///
/// ⚠️ Deliberately a small copy rather than a shared module. The app's `NB` and `NBFont`
/// live in the app target; pulling them in would drag the whole design system, the band
/// stack and the SDK into a widget that draws six numbers. Four constants and two font
/// helpers is the honest cost — if a colour changes here it changes in `Tokens.swift` too.
enum Island {
    static let carbon    = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0D / 255)
    static let panelInk  = Color(red: 0x07 / 255, green: 0x07 / 255, blue: 0x09 / 255)
    static let lime      = Color(red: 0xEF / 255, green: 0xF6 / 255, blue: 0x5A / 255)
    static let ember     = Color(red: 0xF6 / 255, green: 0xA4 / 255, blue: 0x1C / 255)
    static let white     = Color.white

    /// Doto — the dot-matrix numerals. Same names the app registers.
    static func dot(_ weight: Int, _ size: CGFloat) -> Font {
        let style = weight >= 700 ? "Bold" : weight >= 600 ? "SemiBold" : "Medium"
        return .custom("Doto-\(style)", size: size)
    }
    /// Inter Tight — the brand face, for the readout numbers.
    static func brand(_ size: CGFloat) -> Font { .custom("InterTight-Bold", size: size) }

    /// The one colour decision: the lime warms toward amber as the heart climbs. Interpolated
    /// by hand because `Color.mix` is iOS 18 and this ships to 17.
    static func tone(effort: Double) -> Color {
        let t = min(1, max(0, (effort - 0.35) / 0.60))
        return Color(
            red:   (0xEF + (0xF6 - 0xEF) * t) / 255,
            green: (0xF6 + (0xA4 - 0xF6) * t) / 255,
            blue:  (0x5A + (0x1C - 0x5A) * t) / 255)
    }

    /// The elapsed clock, counting up on the island's own time. A day's ceiling, because
    /// `Text(timerInterval:)` wants a range and no session outlives one.
    static func elapsedRange(from start: Date) -> ClosedRange<Date> {
        start...start.addingTimeInterval(60 * 60 * 24)
    }
}
