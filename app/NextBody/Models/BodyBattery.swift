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

    /// The four words the morning line is allowed to use. There is no fifth.
    static func chargeWord(_ delta: Int) -> String {
        switch delta {
        case ..<20:  return "LIGHT CHARGE"
        case ..<32:  return "BELOW USUAL"
        case ..<45:  return "NORMAL CHARGE"
        default:     return "FULL CHARGE"
        }
    }

}

// MARK: - 04 · the one prediction on the whole product

/// ⚠️ 1CVO · "CHARGING WHILE YOU WIND DOWN · FULL 06:40" is the only forecast NextBody
/// makes, and board 13 puts four conditions on keeping it: render it only on a charging
/// tick, only when there is less than four hours left, take the rate from the median of
/// the last six ticks, and drop the whole line if the time it names moves by more than
/// ±45 minutes. Fail any one of them and the line goes away — a prediction that jumps
/// around is worse than none.
enum ChargeForecast {
    /// Minutes per tick on the reserve grid.
    static let tickMinutes = 5.0

    static func line(curve: [ReserveSample], calendar: Calendar = .current) -> String? {
        guard let now = estimate(curve, endingAt: curve.count - 1) else { return nil }
        // Condition four: the same estimate one tick ago must land within 45 minutes.
        if let before = estimate(curve, endingAt: curve.count - 2),
           abs(now.timeIntervalSince(before)) > 45 * 60 { return nil }
        return L("CHARGING WHILE YOU WIND DOWN · FULL %@", Fmt.clock(now))
    }

    /// The instant the reserve reaches 100, or nil if any of the first three conditions fails.
    private static func estimate(_ curve: [ReserveSample], endingAt index: Int) -> Date? {
        guard index >= 6, index < curve.count else { return nil }
        let window = curve[(index - 6)...index]
        let deltas = zip(window.dropFirst(), window).map { Double($0.value - $1.value) }
        // Condition one: the last tick has to be charging.
        guard let last = deltas.last, last > 0 else { return nil }
        // Condition three: the rate is the median of the last six ticks, not the last one.
        let rate = median(deltas)
        guard rate > 0 else { return nil }
        let tick = curve[index]
        let remaining = Double(100 - tick.value)
        guard remaining > 0 else { return nil }
        let minutes = remaining / rate * tickMinutes
        // Condition two: less than four hours out.
        guard minutes < 240 else { return nil }
        return tick.ts.addingTimeInterval(minutes * 60)
    }

    private static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

/// 13 · how old the last real tick is. The curve stops there; nothing is extrapolated to
/// cover the gap, so the screen has to say which of the three states it is in.
enum TickFreshness {
    case fresh          // under 90 minutes
    case stale          // 90 minutes to 6 hours — numbers dim, SYNCED HH:MM appears
    case gone           // over 6 hours — the numbers themselves become ——

    static func of(_ at: Date?, now: Date = Date()) -> TickFreshness {
        guard let at else { return .gone }
        let minutes = now.timeIntervalSince(at) / 60
        if minutes > 360 { return .gone }
        if minutes > 90 { return .stale }
        return .fresh
    }
}
