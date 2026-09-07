import Foundation

/// Issue #20 · the half of `SleepWakeClamp` that rewrites a `SleepSummary`. It lives beside
/// the decision rather than inside it because `SleepSummary` is an app-target model and the
/// decision — which mark ends a night, and when a mark is too early to be a wake — is the
/// part worth testing on its own.
extension SleepWakeClamp {
    /// The same night, ended at `wake`. Everything that carries a time position is cut at
    /// that instant; the stage totals follow the minutes the line actually kept, so a night
    /// whose line and vendor totals already agree is cut exactly and one whose totals came
    /// from the vendor's own scalars is reduced in the same proportion. Per-minute series
    /// are left to the caller's existing in-window filter, which reads `intervals`.
    static func clamp(_ night: SleepSummary, to wake: Date) -> SleepSummary {
        guard let start = night.sleepStart, let recorded = night.wakeAt,
              wake > start, wake < recorded else { return night }
        var cut = night
        cut.wakeAt = wake
        if let intervals = night.intervals {
            cut.intervals = intervals
                .compactMap { $0.start >= wake ? nil : SleepInterval(start: $0.start, end: min($0.end, wake)) }
                .filter { $0.end > $0.start }
        }

        let keptMinutes = Int(wake.timeIntervalSince(start) / 60)
        if night.line.isEmpty {
            // No positions to cut against. The only honest reduction is the proportion of
            // the recorded window that survived, applied to every total alike.
            let elapsed = recorded.timeIntervalSince(start)
            let ratio = elapsed > 0 ? wake.timeIntervalSince(start) / elapsed : 1
            cut.totalMinutes = Int((Double(night.totalMinutes) * ratio).rounded())
            cut.deepMinutes = Int((Double(night.deepMinutes) * ratio).rounded())
            cut.lightMinutes = Int((Double(night.lightMinutes) * ratio).rounded())
            return cut
        }

        var kept: [SleepStageRun] = []
        var offset = 0
        for run in night.line {
            let runStart = run.offsetMinutes ?? offset
            offset = runStart + run.minutes
            guard runStart < keptMinutes else { continue }
            let minutes = min(run.minutes, keptMinutes - runStart)
            guard minutes > 0 else { continue }
            kept.append(SleepStageRun(stage: run.stage, minutes: minutes, offsetMinutes: run.offsetMinutes))
        }
        cut.line = kept

        // Stages 0 deep, 1 light, 2 REM are asleep; 3 insomnia and 4 awake are not.
        func asleep(_ runs: [SleepStageRun]) -> Int {
            runs.filter { $0.stage <= 2 }.reduce(0) { $0 + $1.minutes }
        }
        let whole = asleep(night.line)
        let ratio = whole > 0 ? Double(asleep(kept)) / Double(whole) : 1
        cut.totalMinutes = Int((Double(night.totalMinutes) * ratio).rounded())
        cut.deepMinutes = Int((Double(night.deepMinutes) * ratio).rounded())
        cut.lightMinutes = Int((Double(night.lightMinutes) * ratio).rounded())
        // Truncation can only remove awakenings, never add one.
        cut.wakeCount = min(night.wakeCount, kept.filter { $0.stage >= 3 }.count)
        return cut
    }

    /// The night as it should be filed, given what the phone knows about being awake.
    static func applying(_ marks: [Date], to night: SleepSummary) -> SleepSummary {
        guard let start = night.sleepStart, let recorded = night.wakeAt,
              let cutAt = wake(sleepStart: start, recordedWake: recorded, marks: marks)
        else { return night }
        return clamp(night, to: cutAt)
    }
}
