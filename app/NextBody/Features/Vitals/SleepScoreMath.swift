import Foundation

/// ADR 0008 · the arithmetic behind the sleep board's week and month windows, with no view
/// and no app types in it, so it can be exercised without a simulator.
///
/// Everything here is a median rather than a mean. One two-hour night — a wrist taken off at
/// 01:00 — drags a mean far enough to be read as a bad week, and the rest of this codebase
/// already medians for the same reason (night HRV is a median of fifteen-minute medians).
public enum SleepScoreMath {
    /// Prior canonical nights the server needs before it publishes a bedtime median and
    /// scores the regularity group (sleep-v1.3, `20260909100000_regularity_from_third_night`).
    /// The UI counts up to this so the group never just says "not yet".
    public static let regularityBaselineNights = 3

    /// Keep the familiar minimum range, extending the ruler to include actual peaks.
    public static func hrvUpperBound(_ values: [Double]) -> Double {
        let peak = values.filter { $0.isFinite && $0 > 0 }.max() ?? 0
        return max(90, ceil(peak / 30) * 30)
    }

    public static func effectiveWeights(values: [Double?], weights: [Double]) -> [Double?] {
        guard values.count == weights.count else { return values.map { _ in nil } }
        let present = zip(values, weights).map { value, weight -> Double? in
            guard let value, value.isFinite, weight.isFinite, weight > 0 else { return nil }
            return weight
        }
        let total = present.compactMap { $0 }.reduce(0, +)
        guard total > 0 else { return values.map { _ in nil } }
        return present.map { $0.map { $0 / total * 100 } }
    }

    public static func bedtimeDeviation(bedtime: Double, baseline: Double) -> Double {
        let raw = (bedtime - baseline).truncatingRemainder(dividingBy: 1440)
        return raw > 720 ? raw - 1440 : raw < -720 ? raw + 1440 : raw
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2
                                              : sorted[middle]
    }

    /// Tukey hinges for a bedtime box. The box is this person's habit (Q1–Q3), the
    /// whiskers are the nights that actually happened, and the median is the line the
    /// regularity score already names as "usually".
    public struct Box: Equatable, Sendable {
        public var min: Double
        public var q1: Double
        public var median: Double
        public var q3: Double
        public var max: Double

        public init(min: Double, q1: Double, median: Double, q3: Double, max: Double) {
            self.min = min
            self.q1 = q1
            self.median = median
            self.q3 = q3
            self.max = max
        }
    }

    /// Lower and upper halves exclude the median on an odd count, so a three-night run
    /// does not put the same night in both walls of the box.
    public static func box(_ values: [Double]) -> Box? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let n = sorted.count
        let low = sorted[0]
        let high = sorted[n - 1]
        guard let mid = median(sorted) else { return nil }
        if n == 1 {
            return Box(min: low, q1: low, median: mid, q3: high, max: high)
        }
        let split = n / 2
        let lower = Array(sorted[0..<split])
        let upper = n.isMultiple(of: 2)
            ? Array(sorted[split..<n])
            : Array(sorted[(split + 1)..<n])
        return Box(
            min: low,
            q1: median(lower) ?? low,
            median: mid,
            q3: median(upper) ?? high,
            max: high)
    }

    /// The lowest-scoring member, which is what the week and month hero names as the thing
    /// dragging. Ties go to the first in the given order, so the caller's order is the
    /// tie-break and the answer never flickers between two equal groups.
    public static func weakest<Key>(_ scores: [(key: Key, values: [Double])]) -> Key? {
        var best: (key: Key, value: Double)?
        for entry in scores {
            guard let median = median(entry.values) else { continue }
            if best == nil || median < best!.value { best = (entry.key, median) }
        }
        return best?.key
    }

    /// `bed_offset` counts minutes past 18:00 local. That is what keeps a 23:40 bedtime and
    /// a 01:20 one 100 minutes apart instead of twenty-two hours, and it has to be unwound
    /// the same way to be printed.
    public static func bedClock(offset: Double) -> String {
        let minutes = ((Int(offset.rounded()) + 1080) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// Stage percentages renormalised over the stages that were actually measured, so a run
    /// of nights with no stage line yields deep and light summing to 100 rather than a bar
    /// with a third of it silently missing.
    public static func renormalised(_ shares: [Double]) -> [Double] {
        let total = shares.reduce(0, +)
        guard total > 0 else { return shares.map { _ in 0 } }
        return shares.map { $0 / total * 100 }
    }
}
