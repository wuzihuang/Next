import Foundation

/// Arithmetic for the trend hero every rolling window now leads with. One value a user day
/// goes in — a resting pulse, a day's mean stress, a night's median skin temperature, a
/// day's steps, a night's score — and out come the window's headline, its change against
/// the window before it, and the month's week-by-week strip. No SwiftUI and no model
/// types: the view hands in plain numbers so this is testable without a band.
///
/// ⚠️ A day with no value is absent from every figure here — never a zero (F2 rule 05). A
/// window that recorded three days and one that recorded thirty are different facts wearing
/// the same numeral, which is why the recorded count travels beside every headline.
public enum MetricTrendMath {
    public static func recorded(_ values: [Double?]) -> [Double] {
        values.compactMap { $0 }
    }

    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    public static func median(_ values: [Double]) -> Double? {
        HeartWindowMath.median(values)
    }

    /// The window's one number: the median of its recorded days. A median, not a mean —
    /// one night the band came off at 01:00 must not read as a bad week.
    public static func headline(_ values: [Double?]) -> Double? {
        median(recorded(values))
    }

    /// A rule for the field: the window's own middle day. Under three days it is not a
    /// habit, it is the only day there is, so nothing is drawn.
    public static func habit(_ values: [Double?], minimum: Int = 3) -> Double? {
        let present = recorded(values)
        return present.count >= minimum ? median(present) : nil
    }

    /// This window's headline against the previous window's. Both sides need `minimum`
    /// recorded days, or the comparison is two numbers that happen to be near each other.
    public static func delta(current: [Double?], prior: [Double?], minimum: Int = 3) -> Double? {
        let now = recorded(current), before = recorded(prior)
        guard now.count >= minimum, before.count >= minimum,
              let a = median(now), let b = median(before) else { return nil }
        return a - b
    }

    /// One slice of the month strip: where it starts in the window, how many days it
    /// spans, how many of those recorded, and their mean.
    public struct Roll: Equatable, Sendable {
        public let start: Int
        public let count: Int
        public let recorded: Int
        public let average: Double?

        public init(start: Int, count: Int, recorded: Int, average: Double?) {
            self.start = start
            self.count = count
            self.recorded = recorded
            self.average = average
        }
    }

    /// Oldest first. Thirty days become 2 + 7 + 7 + 7 + 7 — the same cut BODY BATTERY's
    /// month already makes, so the two pages agree on what "week by week" means.
    public static func weekRolls(_ values: [Double?]) -> [Roll] {
        guard !values.isEmpty else { return [] }
        var rolls: [Roll] = []
        var cursor = values.count
        while cursor > 0 {
            let start = max(0, cursor - 7)
            let slice = Array(values[start..<cursor])
            let present = recorded(slice)
            rolls.append(Roll(start: start, count: slice.count,
                              recorded: present.count, average: mean(present)))
            cursor = start
        }
        return rolls.reversed()
    }

    /// A vertical ruler fitted around what was recorded: `pad` of air each side, both ends
    /// snapped outward to a multiple of `step`, never narrower than `minimumSpan`, and
    /// `fallback` when there is nothing to fit. A ruler that hugs the data too tightly turns
    /// a two-beat wobble into a cliff; one that never moves flattens a real shift.
    public static func fittedScale(_ values: [Double?], step: Double, pad: Double,
                                   minimumSpan: Double,
                                   fallback: ClosedRange<Double>,
                                   including extra: ClosedRange<Double>? = nil) -> ClosedRange<Double> {
        var present = recorded(values)
        if let extra { present += [extra.lowerBound, extra.upperBound] }
        guard let low = present.min(), let high = present.max(), step > 0 else { return fallback }
        var lower = ((low - pad) / step).rounded(.down) * step
        var upper = ((high + pad) / step).rounded(.up) * step
        if upper - lower < minimumSpan {
            let centre = (upper + lower) / 2
            lower = ((centre - minimumSpan / 2) / step).rounded(.down) * step
            upper = ((centre + minimumSpan / 2) / step).rounded(.up) * step
        }
        return lower...upper
    }

    /// 0 at the ruler's floor, 1 at its top. Clamped, never extrapolated.
    public static func fraction(_ value: Double, in scale: ClosedRange<Double>) -> Double {
        let span = scale.upperBound - scale.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - scale.lowerBound) / span))
    }
}
