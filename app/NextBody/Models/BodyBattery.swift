import Foundation

/// 13 · 昨夜与 Body Battery.
/// Sleep never reaches the screen (F0 rule 03). Duration, stages and depth ratios exist only
/// as inputs to this model; what the user sees is how much last night charged the battery,
/// plus one of four words.
enum BodyBattery {

    /// 13 · Sec 04 — nine bands, no interpolation inside a band.
    /// The target is fixed at wake and does not move as the battery drains through the day;
    /// a target that slid every five minutes would read as a live number and people would chase it.
    struct Band {
        let range: ClosedRange<Int>
        let target: Double
        let optimal: ClosedRange<Double>
        let ringPercent: Int
        let dayLooksLike: String
    }

    static let bands: [Band] = [
        .init(range: 0...19,   target: 4.0,  optimal: 0.0...6.0,   ringPercent: 19,
              dayLooksLike: "Training nothing today is a legal answer — inside the band, not a failure"),
        .init(range: 20...29,  target: 6.0,  optimal: 3.0...8.5,   ringPercent: 29,
              dayLooksLike: "Walking and ordinary movement reach the band"),
        .init(range: 30...39,  target: 8.0,  optimal: 5.0...10.5,  ringPercent: 38,
              dayLooksLike: "One easy aerobic session"),
        .init(range: 40...49,  target: 10.0, optimal: 7.0...12.5,  ringPercent: 48,
              dayLooksLike: "One moderate class"),
        .init(range: 50...59,  target: 11.5, optimal: 8.5...14.0,  ringPercent: 55,
              dayLooksLike: "An ordinary day"),
        .init(range: 60...69,  target: 13.0, optimal: 10.5...15.5, ringPercent: 62,
              dayLooksLike: "An ordinary day, with room for one lifting session"),
        .init(range: 70...79,  target: 14.5, optimal: 12.5...16.5, ringPercent: 69,
              dayLooksLike: "The body is ready — one lifting session fits"),
        .init(range: 80...89,  target: 16.0, optimal: 14.0...18.0, ringPercent: 76,
              dayLooksLike: "The body is ready for intensity"),
        // The full ring stays above the top band: the target is never allowed to reach 21.
        .init(range: 90...100, target: 18.0, optimal: 15.5...20.0, ringPercent: 86,
              dayLooksLike: "The full ring stays at 21; the target never goes there"),
    ]

    static func band(for wake: Int) -> Band {
        bands.first { $0.range.contains(max(0, min(100, wake))) } ?? bands[0]
    }

    /// Descriptive bands for points gained overnight, shared by every entry.
    /// These are absolute amounts, not personal baselines or claims of a full battery.
    static func chargeWord(_ delta: Int) -> String {
        switch delta {
        case ..<20:  return "LIGHT CHARGE"
        case ..<32:  return "MODERATE CHARGE"
        case ..<45:  return "STRONG CHARGE"
        default:     return "VERY STRONG CHARGE"
        }
    }

}

/// Display geometry uses actual elapsed seconds in the selected local user day.
/// A DST day can contain 23 or 25 hours. Colour describes each observed change;
/// an evening recovery must never recolour an earlier decline.
enum BodyBatteryCurveMath {
    struct Segment {
        let start: ReserveSample
        let end: ReserveSample
        var charging: Bool { end.value > start.value }
    }

    static func fraction(_ timestamp: Date, in day: UserDay) -> Double {
        let duration = day.end.timeIntervalSince(day.start)
        guard duration > 0 else { return 0 }
        return min(1, max(0, timestamp.timeIntervalSince(day.start) / duration))
    }

    static func segments(_ samples: [ReserveSample]) -> [Segment] {
        let ordered = samples.sorted { $0.ts < $1.ts }
        return zip(ordered, ordered.dropFirst()).compactMap { start, end in
            // Missing ticks remain a visible gap instead of an invented straight line.
            guard end.ts > start.ts, end.ts.timeIntervalSince(start.ts) <= 10 * 60 else { return nil }
            return Segment(start: start, end: end)
        }
    }
}

/// 13 · how old the last real tick is. The curve stops there; nothing is extrapolated to
/// cover the gap, so the screen has to say which of the three states it is in.
enum TickFreshness {
    case fresh          // under 90 minutes
    case stale          // 90 minutes to under 6 hours — numbers dim, SYNCED HH:MM appears
    case gone           // 6 hours or later, missing or future observation — the numbers themselves become ——

    static func of(_ at: Date?, now: Date = Date()) -> TickFreshness {
        guard let at else { return .gone }
        let age = now.timeIntervalSince(at)
        guard age >= 0 else { return .gone }
        if age >= 6 * 3600 { return .gone }
        if age >= 90 * 60 { return .stale }
        return .fresh
    }
}
