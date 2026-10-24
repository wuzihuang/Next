package com.nextbody.hoop.band

import com.nextbody.hoop.model.SleepInterval
import com.nextbody.hoop.model.SleepSummary
import java.time.Instant
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Issue #20 · the half of `SleepWakeClamp` that rewrites a `SleepSummary`. It lives beside
 * the decision rather than inside it because `SleepSummary` is an app-target model and the
 * decision — which mark ends a night, and when a mark is too early to be a wake — is the
 * part worth testing on its own.
 */

/** The same night, ended at `wake`. Everything that carries a time position is cut at
 *  that instant; the stage totals follow the minutes the line actually kept, so a night
 *  whose line and vendor totals already agree is cut exactly and one whose totals came
 *  from the vendor's own scalars is reduced in the same proportion. Per-minute series
 *  are left to the caller's existing in-window filter, which reads `intervals`. */
fun SleepWakeClamp.clamp(night: SleepSummary, wake: Instant): SleepSummary {
    val start = night.sleepStart ?: return night
    val recorded = night.wakeAt ?: return night
    if (!(wake > start && wake < recorded)) return night
    val cut = night.copy()
    cut.wakeAt = wake
    night.intervals?.let { intervals ->
        cut.intervals = intervals
            .mapNotNull { if (it.start >= wake) null else SleepInterval(start = it.start, end = minOf(it.end, wake)) }
            .filter { it.end > it.start }
    }

    val keptMinutes = (BandTime.interval(wake, start) / 60).toInt()
    if (night.line.isEmpty()) {
        // No positions to cut against. The only honest reduction is the proportion of
        // the recorded window that survived, applied to every total alike.
        val elapsed = BandTime.interval(recorded, start)
        val ratio = if (elapsed > 0) BandTime.interval(wake, start) / elapsed else 1.0
        cut.totalMinutes = (night.totalMinutes * ratio).roundToInt()
        cut.deepMinutes = (night.deepMinutes * ratio).roundToInt()
        cut.lightMinutes = (night.lightMinutes * ratio).roundToInt()
        return cut
    }

    val kept = mutableListOf<SleepStageRun>()
    var offset = 0
    for (run in night.line) {
        val runStart = run.offsetMinutes ?: offset
        offset = runStart + run.minutes
        if (runStart >= keptMinutes) continue
        val minutes = min(run.minutes, keptMinutes - runStart)
        if (minutes <= 0) continue
        kept.add(SleepStageRun(stage = run.stage, minutes = minutes, offsetMinutes = run.offsetMinutes))
    }
    cut.line = kept

    // Stages 0 deep, 1 light, 2 REM are asleep; 3 insomnia and 4 awake are not.
    fun asleep(runs: List<SleepStageRun>) = runs.filter { it.stage <= 2 }.sumOf { it.minutes }
    val whole = asleep(night.line)
    val ratio = if (whole > 0) asleep(kept).toDouble() / whole else 1.0
    cut.totalMinutes = (night.totalMinutes * ratio).roundToInt()
    cut.deepMinutes = (night.deepMinutes * ratio).roundToInt()
    cut.lightMinutes = (night.lightMinutes * ratio).roundToInt()
    // Truncation can only remove awakenings, never add one.
    cut.wakeCount = min(night.wakeCount, kept.count { it.stage >= 3 })
    return cut
}

/** The night as it should be filed, given what the phone knows about being awake. */
fun SleepWakeClamp.applying(marks: List<Instant>, night: SleepSummary): SleepSummary {
    val start = night.sleepStart ?: return night
    val recorded = night.wakeAt ?: return night
    val cutAt = wake(sleepStart = start, recordedWake = recorded, marks = marks) ?: return night
    return clamp(night, cutAt)
}
