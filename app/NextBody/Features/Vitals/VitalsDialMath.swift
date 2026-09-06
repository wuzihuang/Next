import Foundation

/// The hero dial's ruler: a fixed scale, interior cuts that name the zones, and where a
/// reading sits. Views colour and label the zones; this file only places them.
///
/// The old fill-rail used today's own min and max as the two ends, so the same 79 BPM
/// landed in a different place every day. A dial's scale does not move with the day.
public enum VitalsDialMath {
    /// 0…1 on `scale`. A value outside the scale is clamped rather than extrapolated,
    /// so a 170 BPM reading still sits on the last millimetre of a 40–160 ruler.
    public static func fraction(value: Double, scale: ClosedRange<Double>) -> Double {
        let span = scale.upperBound - scale.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - scale.lowerBound) / span))
    }

    /// Zone index for `value` given interior cuts. The last zone includes the upper bound.
    public static func activeIndex(value: Double, cuts: [Double]) -> Int {
        var index = 0
        for cut in cuts {
            if value < cut { return index }
            index += 1
        }
        return index
    }

    /// One stretch of a mark that lies in a single zone. `from`/`to` run 0…1 with 0 at the
    /// mark's high end, which is the order a chart draws a column or a capsule in.
    public struct ZoneRun: Equatable {
        public let zone: Int
        public let from: Double
        public let to: Double

        public init(zone: Int, from: Double, to: Double) {
            self.zone = zone
            self.from = from
            self.to = to
        }
    }

    /// How a mark spanning `low…high` is split across the zones it covers.
    ///
    /// An envelope capsule *is* a range, so painting the whole of it in the colour of its
    /// own maximum overstates the low end: half an hour that touched 150 BPM once did not
    /// spend that half hour at 150. Each run is returned separately so the mark can carry a
    /// hard edge exactly where the reading crossed a cut.
    public static func zoneRuns(low: Double, high: Double, cuts: [Double]) -> [ZoneRun] {
        guard high > low else {
            return [ZoneRun(zone: activeIndex(value: high, cuts: cuts), from: 0, to: 1)]
        }
        let edges = [high] + cuts.filter { $0 > low && $0 < high }.sorted(by: >) + [low]
        let span = high - low
        return (0..<(edges.count - 1)).compactMap { i in
            let upper = edges[i]
            let lower = edges[i + 1]
            guard upper > lower else { return nil }
            // The midpoint, so the run is classified by the band it occupies rather than by
            // a boundary value that belongs to the zone above it.
            return ZoneRun(zone: activeIndex(value: (upper + lower) / 2, cuts: cuts),
                           from: (high - upper) / span,
                           to: (high - lower) / span)
        }
    }

    /// Tanaka zones on the same 40–160 ruler the heart chart uses.
    public static func heartCuts(maxHR: Int) -> (scale: ClosedRange<Double>, cuts: [Double]) {
        let ceiling = Double(max(120, maxHR))
        let raw = [0.60, 0.70, 0.80].map { $0 * ceiling }
        let cuts = raw.map { min(159, max(41, $0)) }
        return (40...160, cuts)
    }

    public static func stressCuts() -> (scale: ClosedRange<Double>, cuts: [Double]) {
        (0...100, [25, 50, 75])
    }

    /// Sleep-score colour bands from ADR 0008. The labels stay off the dial — the ADR
    /// forbids naming a night "poor".
    public static func sleepCuts() -> (scale: ClosedRange<Double>, cuts: [Double]) {
        (0...100, [40, 60, 80])
    }

    /// HRV / meal-response style: a personal centre with a ± band around it.
    public static func ratioCuts(base: Double, inner: Double = 0.08,
                                 outer: Double = 0.50) -> (scale: ClosedRange<Double>, cuts: [Double])? {
        guard base > 0 else { return nil }
        return ((base * (1 - outer))...(base * (1 + outer)),
                [base * (1 - inner), base * (1 + inner)])
    }

    /// A measured range with pad on both sides so the outer zones have width.
    public static func rangeCuts(lower: Double, upper: Double,
                                 pad: Double = 0.5) -> (scale: ClosedRange<Double>, cuts: [Double])? {
        guard upper > lower else { return nil }
        return ((lower - pad)...(upper + pad), [lower, upper])
    }

    /// Cumulative metrics against the last seven days. Usual is 80–115 % of the week mean.
    /// Fewer than three weekdays is not a range — it is noise.
    public static func weekCuts(today: Double, week: [Double]) -> (scale: ClosedRange<Double>, cuts: [Double])? {
        guard week.count >= 3 else { return nil }
        let mean = week.reduce(0, +) / Double(week.count)
        guard mean > 0 else { return nil }
        let usualLo = mean * 0.80
        let usualHi = mean * 1.15
        let top = max(today, week.max() ?? today, mean * 1.6)
        guard top > 0, usualHi > usualLo else { return nil }
        return (0...top, [usualLo, usualHi])
    }

    /// Meal-response percent versus own median. Near is ±8, matching `MealResponseIndex`.
    public static func responseCuts(percent: Double) -> (scale: ClosedRange<Double>, cuts: [Double]) {
        let extent = max(40, abs(percent) + 8)
        return ((-extent)...extent, [-8, 8])
    }
}
