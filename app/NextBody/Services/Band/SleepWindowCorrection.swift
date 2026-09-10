import Foundation

/// #28 · what a corrected night does to the band's stage line.
///
/// A correction moves the window, never the minutes. The band recorded each run at a real
/// clock time, anchored at the window it filed; when the person says the night began later
/// or ended earlier, those runs keep their clock and the ends are cut off. Nothing is
/// stretched, nothing is invented, and a window pushed out past the band's own record gains
/// room with no sleep in it — which is the whole reason a correction cannot inflate a night.
///
/// The server clips the same way (`nb.sleep_evidence_minutes` anchors the offset line on
/// `raw.recorded_start` and filters by the published window), so the hypnogram on the page
/// and the score behind it are counting the same minutes.
enum SleepWindowCorrection {
    struct Run: Equatable {
        var stage: Int
        var minutes: Int
        /// Minutes from the published window's start. Always set on a clipped run: once the
        /// front of the line is cut off, position can no longer be read from order alone.
        var offsetMinutes: Int
    }

    /// `runs` are the band's own, positioned against `bandStart`; a run without an offset
    /// follows the one before it, which is how the older rows store a line.
    static func clip(_ runs: [(stage: Int, minutes: Int, offsetMinutes: Int?)],
                     bandStart: Date, start: Date, end: Date) -> [Run] {
        guard end > start else { return [] }
        let windowStart = Int((start.timeIntervalSince(bandStart) / 60).rounded())
        let windowEnd = Int((end.timeIntervalSince(bandStart) / 60).rounded())
        var cursor = 0
        var out: [Run] = []
        for run in runs where run.minutes > 0 {
            let from = run.offsetMinutes ?? cursor
            let to = from + run.minutes
            cursor = to
            let lo = max(from, windowStart), hi = min(to, windowEnd)
            guard hi > lo else { continue }
            out.append(Run(stage: run.stage, minutes: hi - lo, offsetMinutes: lo - windowStart))
        }
        return out
    }
}
