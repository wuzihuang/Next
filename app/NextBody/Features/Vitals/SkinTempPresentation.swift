import SwiftUI

/// The one place the day and its history are turned into a skin-temperature night range, so
/// the Home card and the detail page cannot disagree about last night (ADR 0009).
enum SkinTempPresentation {
    static func nightRange(today: DailyMetrics, history: [DailyMetrics],
                           now: Date = Date()) -> SkinTempNightRange.Result {
        var days = history
        if days.last?.day != today.day { days.append(today) }

        let curve = VitalSample.merging(days.flatMap(\.vitalsCurve), with: today.vitalsCurve)
        let points = curve.compactMap { sample in
            sample.temp.map { SkinTempNightRange.Point(ts: sample.ts, celsius: $0) }
        }
        // One night per window: a day carried twice in `history` would otherwise weigh twice
        // in the median that judges tonight.
        var seen: Set<SkinTempNightRange.Night> = []
        let nights = days.compactMap { day -> SkinTempNightRange.Night? in
            guard let start = day.sleep?.sleepStart, let wake = day.sleep?.wakeAt, wake > start
            else { return nil }
            return seen.insert(SkinTempNightRange.Night(start: start, end: wake)).inserted
                ? SkinTempNightRange.Night(start: start, end: wake) : nil
        }
        return SkinTempNightRange.make(points: points, nights: nights, now: now)
    }

    /// The badge, in the metric's own colours. Mild sits between "nothing happened" and the
    /// colour the page used to jump straight to.
    static func badge(_ tier: SkinTempNightRange.Tier) -> (text: String, tint: Color) {
        switch tier {
        case .within:    (L("WITHIN YOUR RANGE"), NB.optimal2)
        case .mildAbove: (L("SLIGHTLY ABOVE RANGE"), NB.cyan1)
        case .mildBelow: (L("SLIGHTLY BELOW RANGE"), NB.cyan1)
        case .wellAbove: (L("WELL ABOVE YOUR RANGE"), NB.ember1)
        case .wellBelow: (L("WELL BELOW YOUR RANGE"), NB.blue1)
        }
    }

    /// The short form the Home card prints after last night's signed number.
    static func shortTier(_ tier: SkinTempNightRange.Tier) -> String {
        switch tier {
        case .within:                 L("IN RANGE")
        case .mildAbove, .wellAbove:  L("ABOVE RANGE")
        case .mildBelow, .wellBelow:  L("BELOW RANGE")
        }
    }

    /// Why last night carries no verdict, in the words the card prints.
    static func reason(_ empty: SkinTempNightRange.Empty, learningNights: Int) -> String {
        switch empty {
        case .noNight:        L("NO NIGHT YET")
        case .nightTooShort:  L("NIGHT TOO SHORT")
        case .tooFewTicks:    L("TOO FEW NIGHT TICKS")
        case .needsFiveNights: L("LEARNING · %d / 5 NIGHTS", learningNights)
        }
    }

    /// The chart's vertical ruler: the person's own range with room around it, or the plain
    /// wrist window before there is a range. Never the 35.5–37.0 core-temperature ruler.
    static func axis(_ range: SkinTempNightRange.Range?, pad: Double) -> ClosedRange<Double> {
        guard let range else { return 30...38 }
        return (range.lower - pad)...(range.upper + pad)
    }
}
