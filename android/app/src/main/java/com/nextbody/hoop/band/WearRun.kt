package com.nextbody.hoop.band

import com.nextbody.hoop.model.timeIntervalSince
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

/**
 * ADR 0010 · consecutive worn days as a silent header fact.
 *
 * A worn day is wrist evidence in at least half of the user-day's elapsed five-minute
 * slots. Bluetooth, an empty raw row, and a valid night are all different things.
 */
object WearRun {
    sealed class Flame {
        data class Live(val days: Int) : Flame()
        data object Amber : Flame()
        data object Gray : Flame()
    }

    data class Yesterday(var worn: Boolean, var run: Int, var miss: Int)

    const val slotsPerDay = 288
    const val slotSeconds: Double = 300.0

    /** Heart, stress, HRV, or a positive step count. Skin temperature and vendor calories
     *  alone do not count — a band on the nightstand can still report those. */
    fun hasWristEvidence(sample: VitalSample): Boolean =
        sample.hr != null || sample.stress != null || sample.hrv != null || (sample.steps ?: 0) > 0

    fun elapsedSlots(day: UserDay, now: Instant): Int {
        val hi = minOf(now, day.end)
        if (hi <= day.start) return 0
        return min(slotsPerDay, (hi.timeIntervalSince(day.start) / slotSeconds).toInt())
    }

    fun isWornDay(samples: List<VitalSample>, day: UserDay, now: Instant): Boolean {
        val elapsed = elapsedSlots(day, now)
        if (elapsed <= 0) return false
        val bins = HashSet<Int>()
        val upper = minOf(now, day.end)
        for (sample in samples) {
            if (!(sample.ts >= day.start && sample.ts < upper)) continue
            if (!hasWristEvidence(sample)) continue
            val slot = (sample.ts.timeIntervalSince(day.start) / slotSeconds).toInt()
            if (!(slot >= 0 && slot < elapsed)) continue
            bins.add(slot)
        }
        return bins.size * 2 >= elapsed
    }

    /** Server wear columns may still be missing on an older backend. `worn == nil`
     *  then falls back to local ticks; an explicit `false` does not. */
    fun yesterday(worn: Boolean?, run: Int?, miss: Int?, localWorn: Boolean): Yesterday {
        val isWorn = worn ?: localWorn
        return Yesterday(
            worn = isWorn,
            run = run ?: (if (isWorn) 1 else 0),
            miss = miss ?: (if (isWorn) 0 else 2))
    }

    /** Today never cools the flame: an open user-day that is not yet a worn day still
     *  shows yesterday's live run. A closed miss is already sitting on yesterday. */
    fun display(todayWorn: Boolean, yesterday: Yesterday?): Flame {
        if (todayWorn) {
            val prior = if (yesterday?.worn == true) max(0, yesterday.run) else 0
            return Flame.Live(prior + 1)
        }
        if (yesterday == null) return Flame.Gray
        if (yesterday.worn) return Flame.Live(max(1, yesterday.run))
        if (yesterday.miss == 1) return Flame.Amber
        return Flame.Gray
    }
}
