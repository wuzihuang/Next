import Foundation

/// #28 · what a corrected night does to the band's stage line.
///
/// A correction moves the window, never the minutes. The band recorded each run at a real
/// clock time, anchored at the window it filed; when the person says the night began later
/// or ended earlier, those runs keep their clock and the ends are cut off. Nothing is
/// stretched, nothing is invented, and a window pushed out past the band's own record gains
/// room with no measured stages in it. Reported duration and missing stages stay distinct.
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
                     bandStart: Date, start: Date, end: Date,
                     recordedIntervals: [(start: Date, end: Date)] = []) -> [Run] {
        guard end > start else { return [] }
        let runs = position(runs, bandStart: bandStart, recordedIntervals: recordedIntervals)
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

    /// Older device lines omit offsets and concatenate actual sleep sessions. Restore
    /// their wall clock before clipping, so a session gap cannot move later REM/deep runs.
    static func position(_ runs: [(stage: Int, minutes: Int, offsetMinutes: Int?)],
                         bandStart: Date, recordedIntervals: [(start: Date, end: Date)])
        -> [(stage: Int, minutes: Int, offsetMinutes: Int?)] {
        guard !recordedIntervals.isEmpty, runs.allSatisfy({ $0.offsetMinutes == nil }) else { return runs }
        var windows: [(start: Int, end: Int)] = []
        for interval in recordedIntervals.sorted(by: { $0.start < $1.start }) where interval.end > interval.start {
            let lo = Int((interval.start.timeIntervalSince(bandStart) / 60).rounded())
            let hi = Int((interval.end.timeIntervalSince(bandStart) / 60).rounded())
            guard hi > lo else { continue }
            if let last = windows.last, lo <= last.end {
                windows[windows.count - 1].end = max(last.end, hi)
            } else { windows.append((lo, hi)) }
        }
        guard !windows.isEmpty else { return runs }
        var index = 0
        var offset = windows[0].start
        var result: [(stage: Int, minutes: Int, offsetMinutes: Int?)] = []
        for run in runs where run.minutes > 0 {
            var remaining = run.minutes
            while remaining > 0, index < windows.count {
                let count = min(remaining, windows[index].end - offset)
                if count > 0 {
                    result.append((run.stage, count, offset))
                    offset += count
                    remaining -= count
                }
                if offset >= windows[index].end {
                    index += 1
                    if index < windows.count { offset = windows[index].start }
                }
            }
        }
        return result
    }

    struct RestoredWindow: Equatable {
        var totalMinutes: Int
        var line: [Run]
    }

    /// A device archive supplies measurements, not a replacement for the saved reported
    /// duration. Reopening offline must not turn every unmeasured minute back into zero.
    static func restoreReportedWindow(totalMinutes: Int,
                                      deviceRuns: [(stage: Int, minutes: Int, offsetMinutes: Int?)],
                                      bandStart: Date, start: Date, end: Date,
                                      recordedIntervals: [(start: Date, end: Date)]) -> RestoredWindow {
        RestoredWindow(totalMinutes: totalMinutes,
                       line: clip(deviceRuns, bandStart: bandStart, start: start, end: end,
                                  recordedIntervals: recordedIntervals))
    }

    /// Missing stage coverage is explicit; overlapping device runs cannot count twice.
    static func unstagedMinutes(_ runs: [(stage: Int, minutes: Int, offsetMinutes: Int?)],
                                start: Date, end: Date) -> Int {
        let span = max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
        var covered = Set<Int>()
        var cursor = 0
        for run in runs where run.minutes > 0 {
            let from = run.offsetMinutes ?? cursor
            cursor = from + run.minutes
            guard (0...4).contains(run.stage) else { continue }
            let lo = max(0, from), hi = min(span, cursor)
            if hi > lo { covered.formUnion(lo..<hi) }
        }
        return max(0, span - covered.count)
    }

    /// A partially intersecting device interval still supplies evidence in the new window.
    static func clipInterval(start: Date, end: Date, windowStart: Date, windowEnd: Date)
        -> (start: Date, end: Date)? {
        let lo = max(start, windowStart), hi = min(end, windowEnd)
        return hi > lo ? (lo, hi) : nil
    }


    /// Raw sample HRV fills only minutes without native RR or an explicit invalidation.
    /// The timestamp stays that of the real observation; no interpolation is performed.
    static func hrvBackfill(samples: [VitalSample], nativeMinutes: [Date],
                            invalidatedMinutes: [Date]) -> [VitalSample] {
        func minute(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 60)) }
        var occupied = Set((nativeMinutes + invalidatedMinutes).map(minute))
        return samples.sorted { $0.ts < $1.ts }.filter { sample in
            let key = minute(sample.ts)
            guard !occupied.contains(key), sample.hrvValid != false,
                  let value = sample.hrv, value.isFinite, (1...300).contains(value) else { return false }
            occupied.insert(key)
            return true
        }
    }

}
