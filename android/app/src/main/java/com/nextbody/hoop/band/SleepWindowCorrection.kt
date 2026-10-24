package com.nextbody.hoop.band

import com.nextbody.hoop.model.SleepInterval
import com.nextbody.hoop.model.roundedInt
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.model.timeIntervalSince1970
import java.time.Instant
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * #28 · what a corrected night does to the band's stage line.
 *
 * A correction moves the window, never the minutes. The band recorded each run at a real
 * clock time, anchored at the window it filed; when the person says the night began later
 * or ended earlier, those runs keep their clock and the ends are cut off. Nothing is
 * stretched, nothing is invented, and a window pushed out past the band's own record gains
 * room with no measured stages in it. Reported duration and missing stages stay distinct.
 *
 * The server clips the same way (`nb.sleep_evidence_minutes` anchors the offset line on
 * `raw.recorded_start` and filters by the published window), so the hypnogram on the page
 * and the score behind it are counting the same minutes.
 *
 * Port note: Swift's `(stage:, minutes:, offsetMinutes:)` tuples are [LineRun]; the
 * `(start:, end:)` interval tuples are [SleepInterval].
 */
object SleepWindowCorrection {
    data class Run(
        var stage: Int,
        var minutes: Int,
        /** Minutes from the published window's start. Always set on a clipped run: once the
         *  front of the line is cut off, position can no longer be read from order alone. */
        var offsetMinutes: Int,
    )

    /** Swift's input tuple `(stage: Int, minutes: Int, offsetMinutes: Int?)`. */
    data class LineRun(val stage: Int, val minutes: Int, val offsetMinutes: Int?)

    /** `runs` are the band's own, positioned against `bandStart`; a run without an offset
     *  follows the one before it, which is how the older rows store a line. */
    fun clip(
        runs: List<LineRun>, bandStart: Instant, start: Instant, end: Instant,
        recordedIntervals: List<SleepInterval> = emptyList(),
    ): List<Run> {
        if (end <= start) return emptyList()
        val positioned = position(runs, bandStart, recordedIntervals)
        val windowStart = (start.timeIntervalSince(bandStart) / 60).roundedInt()
        val windowEnd = (end.timeIntervalSince(bandStart) / 60).roundedInt()
        var cursor = 0
        val out = mutableListOf<Run>()
        for (run in positioned) {
            if (run.minutes <= 0) continue
            val from = run.offsetMinutes ?: cursor
            val to = from + run.minutes
            cursor = to
            val lo = max(from, windowStart)
            val hi = min(to, windowEnd)
            if (hi <= lo) continue
            out.add(Run(stage = run.stage, minutes = hi - lo, offsetMinutes = lo - windowStart))
        }
        return out
    }

    /** Older device lines omit offsets and concatenate actual sleep sessions. Restore
     *  their wall clock before clipping, so a session gap cannot move later REM/deep runs. */
    fun position(runs: List<LineRun>, bandStart: Instant, recordedIntervals: List<SleepInterval>): List<LineRun> {
        if (recordedIntervals.isEmpty() || !runs.all { it.offsetMinutes == null }) return runs
        val windows = mutableListOf<IntArray>() // [start, end]
        for (interval in recordedIntervals.sortedBy { it.start }) {
            if (interval.end <= interval.start) continue
            val lo = (interval.start.timeIntervalSince(bandStart) / 60).roundedInt()
            val hi = (interval.end.timeIntervalSince(bandStart) / 60).roundedInt()
            if (hi <= lo) continue
            val last = windows.lastOrNull()
            if (last != null && lo <= last[1]) {
                last[1] = max(last[1], hi)
            } else windows.add(intArrayOf(lo, hi))
        }
        if (windows.isEmpty()) return runs
        var index = 0
        var offset = windows[0][0]
        val result = mutableListOf<LineRun>()
        for (run in runs) {
            if (run.minutes <= 0) continue
            var remaining = run.minutes
            while (remaining > 0 && index < windows.size) {
                val count = min(remaining, windows[index][1] - offset)
                if (count > 0) {
                    result.add(LineRun(run.stage, count, offset))
                    offset += count
                    remaining -= count
                }
                if (offset >= windows[index][1]) {
                    index += 1
                    if (index < windows.size) offset = windows[index][0]
                }
            }
        }
        return result
    }

    data class RestoredWindow(var totalMinutes: Int, var line: List<Run>)

    /** A device archive supplies measurements, not a replacement for the saved reported
     *  duration. Reopening offline must not turn every unmeasured minute back into zero. */
    fun restoreReportedWindow(
        totalMinutes: Int, deviceRuns: List<LineRun>, bandStart: Instant, start: Instant, end: Instant,
        recordedIntervals: List<SleepInterval>,
    ): RestoredWindow = RestoredWindow(
        totalMinutes = totalMinutes,
        line = clip(deviceRuns, bandStart, start, end, recordedIntervals))

    /** Missing stage coverage is explicit; overlapping device runs cannot count twice. */
    fun unstagedMinutes(runs: List<LineRun>, start: Instant, end: Instant): Int {
        val span = max(0, (end.timeIntervalSince(start) / 60).roundedInt())
        val covered = HashSet<Int>()
        var cursor = 0
        for (run in runs) {
            if (run.minutes <= 0) continue
            val from = run.offsetMinutes ?: cursor
            cursor = from + run.minutes
            if (run.stage !in 0..4) continue
            val lo = max(0, from)
            val hi = min(span, cursor)
            if (hi > lo) for (m in lo until hi) covered.add(m)
        }
        return max(0, span - covered.size)
    }

    /** A partially intersecting device interval still supplies evidence in the new window. */
    fun clipInterval(start: Instant, end: Instant, windowStart: Instant, windowEnd: Instant): SleepInterval? {
        val lo = maxOf(start, windowStart)
        val hi = minOf(end, windowEnd)
        return if (hi > lo) SleepInterval(lo, hi) else null
    }

    /** Raw sample HRV fills only minutes without native RR or an explicit invalidation.
     *  The timestamp stays that of the real observation; no interpolation is performed. */
    fun hrvBackfill(samples: List<VitalSample>, nativeMinutes: List<Instant>,
                    invalidatedMinutes: List<Instant>): List<VitalSample> {
        fun minute(date: Instant): Long = floor(date.timeIntervalSince1970 / 60).toLong()
        val occupied = (nativeMinutes + invalidatedMinutes).map { minute(it) }.toHashSet()
        return samples.sortedBy { it.ts }.filter { sample ->
            val key = minute(sample.ts)
            val value = sample.hrv
            if (occupied.contains(key) || sample.hrvValid == false || value == null ||
                value.isNaN() || value.isInfinite() || value !in 1.0..300.0) return@filter false
            occupied.add(key)
            true
        }
    }
}
