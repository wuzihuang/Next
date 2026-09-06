import Foundation

/// ADR 0008 · the arithmetic behind the sleep board's week and month windows, with no view
/// and no app types in it, so it can be exercised without a simulator.
///
/// Everything here is a median rather than a mean. One two-hour night — a wrist taken off at
/// 01:00 — drags a mean far enough to be read as a bad week, and the rest of this codebase
/// already medians for the same reason (night HRV is a median of fifteen-minute medians).
public enum SleepScoreMath {
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2
                                              : sorted[middle]
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
