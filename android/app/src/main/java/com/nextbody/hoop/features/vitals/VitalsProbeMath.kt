package com.nextbody.hoop.features.vitals

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * 探点 arithmetic, with no UI in it. A finger fraction in 0…1 either lands on a recorded
 * sample or it does not; the math never invents a value between ticks.
 */
object VitalsProbeMath {
    /** Half the ten-minute break the traces already use: closer than this and the nearest
     *  tick is a neighbour; farther and the finger is in a gap. */
    const val neighbourSeconds: Double = 5.0 * 60

    /** Same dead zone as `HotZoneTap.slop` — 10 screen points. Travel at or inside this
     *  stays undecided so the page can still take a vertical scroll. */
    const val slop: Double = 10.0

    /** Copy separator. The app wraps this in `L("%@ · %@")`; tests assert the same string. */
    const val dash = "——"

    data class Point(val fraction: Double, val yFraction: Double? = null, val text: String)

    data class Bin(
        val start: Double,
        val end: Double,
        val yFraction: Double? = null,
        val text: String,
        /** An hour (or night) the band did not report. The readout is still named — it is
         *  `——` — so a missing slot is a slot, not a skip to the next filled one. */
        val vacant: Boolean = false,
    )

    data class Run(val start: Double, val end: Double, val yFraction: Double? = null, val text: String)

    data class Pick(
        /** Where the 标线 is drawn, 0…1 in the field. */
        val marker: Double,
        val yFraction: Double?,
        /** Nil only on a point-series gap. Bins and runs always carry copy. */
        val text: String?,
        /** Stable for the life of one sample / bin / run; changes fire the selection haptic. */
        val identity: String,
        val snaps: Boolean,
    )

    data class StageSpan(val start: Double, val end: Double)

    /** One slot of a time window: `(index, start, end)`. */
    data class Slot(val index: Int, val start: Double, val end: Double)

    /** `(start, end)` fraction range. */
    data class SlotRange(val start: Double, val end: Double)

    sealed class Series {
        data class Points(val points: List<Point>) : Series()
        data class Bins(val bins: List<Bin>) : Series()
        data class Runs(val runs: List<Run>) : Series()

        val isEmpty: Boolean
            get() = when (this) {
                is Points -> points.isEmpty()
                is Bins -> bins.isEmpty()
                is Runs -> runs.isEmpty()
            }

        /** Lift-off copy: last recorded sample in the window. Vacant bins at the end are
         *  skipped so a trailing missing hour does not become the idle readout. */
        val idleText: String?
            get() = when (this) {
                is Points -> points.lastOrNull()?.text
                is Bins -> bins.lastOrNull { !it.vacant }?.text ?: bins.lastOrNull()?.text
                is Runs -> runs.lastOrNull()?.text
            }

        val voItems: List<Pick>
            get() = when (this) {
                is Points -> points.mapIndexed { index, point ->
                    Pick(point.fraction, point.yFraction, point.text, pointIdentity(index), true)
                }
                is Bins -> bins.map {
                    Pick((it.start + it.end) / 2, if (it.vacant) null else it.yFraction,
                        it.text, binIdentity(it.start), true)
                }
                is Runs -> runs.map {
                    Pick((it.start + it.end) / 2, it.yFraction, it.text, runIdentity(it.start), true)
                }
            }

        fun pick(finger: Double, gapFraction: Double): Pick = when (this) {
            is Points -> pickPoint(finger, points, gapFraction)
            is Bins -> pickBin(finger, bins)
            is Runs -> pickRun(finger, runs)
        }
    }

    enum class AxisLock { undecided, horizontal, vertical }

    fun line(time: String, value: String): String = "$time · $value"

    fun gap(time: String): String = line(time, dash)

    fun readout(pick: Pick?, idle: String?, gap: String): String {
        if (pick != null) return pick.text ?: gap
        return idle ?: gap
    }

    fun voStep(items: List<Pick>, currentIdentity: String?, increment: Boolean): Pick? {
        if (items.isEmpty()) return null
        val current = currentIdentity?.let { id -> items.indexOfFirst { it.identity == id }.takeIf { it >= 0 } }
            ?: (items.size - 1)
        val next = if (increment) min(items.size - 1, current + 1) else max(0, current - 1)
        return items[next]
    }

    fun gapFraction(span: Double): Double {
        if (span <= 0) return 0.5
        return min(0.5, neighbourSeconds / span)
    }

    fun yFraction(value: Double, low: Double, high: Double): Double {
        val span = max(0.001, high - low)
        val clamped = min(high, max(low, value))
        return 1 - (clamped - low) / span
    }

    fun clamp(value: Double): Double = min(1.0, max(0.0, value))

    /** Map a touch x onto the field, discounting the gutters either side of it: a left one
     *  for the hypnogram's lane labels, a right one for the scale rail. */
    fun fingerFraction(x: Double, width: Double, leadingInset: Double, trailingInset: Double = 0.0): Double =
        clamp((x - leadingInset) / max(1.0, width - leadingInset - trailingInset))

    /** Axis lock against page scroll. Travel at or inside `slop` is still the dead zone. */
    fun axisLock(dx: Double, dy: Double, slop: Double = VitalsProbeMath.slop): AxisLock {
        if (sqrt(dx * dx + dy * dy) <= slop) return AxisLock.undecided
        return if (abs(dx) >= abs(dy)) AxisLock.horizontal else AxisLock.vertical
    }

    /** One slot's fraction range on a window. Slots that start at or past the right edge are
     *  dropped so a nine-hour user day does not grow twenty-four zero-width bins. */
    fun timeSlot(index: Int, seconds: Double, span: Double): SlotRange? {
        if (!(span > 0 && seconds > 0 && index >= 0)) return null
        val start = min(1.0, index * seconds / span)
        val end = min(1.0, (index + 1) * seconds / span)
        if (end <= start) return null
        return SlotRange(start, end)
    }

    /** Every slot of `seconds` the window has room for. A window that does not divide evenly
     *  keeps its short last slot rather than rounding the window up. */
    fun timeSlots(seconds: Double, span: Double): List<Slot> {
        if (!(span > 0 && seconds > 0)) return emptyList()
        val count = ceil(span / seconds).toInt()
        val slots = ArrayList<Slot>(count)
        for (index in 0 until count) {
            val range = timeSlot(index, seconds, span) ?: continue
            slots.add(Slot(index, range.start, range.end))
        }
        return slots
    }

    fun hourSlot(index: Int, span: Double): SlotRange? = timeSlot(index, 3600.0, span)

    fun hourSlots(count: Int, span: Double): List<Slot> {
        val slots = ArrayList<Slot>(max(count, 0))
        for (index in 0 until count) {
            val range = hourSlot(index, span) ?: continue
            slots.add(Slot(index, range.start, range.end))
        }
        return slots
    }

    /**
     * One occupied value run inside a time slot.
     *
     * ⚠️ This is not a min–max fill. `low` and `high` are the ends of ticks that actually
     * sat next to each other; a hole such as 70–75 with no sample stays out of the mark.
     */
    data class Envelope(
        val index: Int,
        val start: Double,
        val end: Double,
        val low: Double,
        val high: Double,
        /** How many ticks this run reduced. One tick is a legitimate envelope of no height. */
        val count: Int,
    ) {
        val mid: Double get() = (start + end) / 2
    }

    data class SlotBar(val x: Double, val width: Double)

    /** The mark that occupies one envelope's own slot. Width follows the slot, not a 7pt cap. */
    fun slotBar(start: Double, end: Double, field: Double, gap: Double = 2.0, minWidth: Double = 2.5): SlotBar {
        val left = field * min(1.0, max(0.0, start))
        val right = field * min(1.0, max(start, end))
        val span = max(0.0, right - left)
        val inset = min(gap, span * 0.25)
        val width = max(minWidth, span - inset)
        // A slot shorter than the minimum mark still sits flush on its right edge, so
        // the last ten minutes of a night do not leave a hole against the rail.
        val x = if (width >= span) max(0.0, right - width) else left + (span - width) / 2
        return SlotBar(x, width)
    }

    /** Capsule heads stay a column, not a pill, once a slot is wider than 12pt. */
    fun slotBarRadius(width: Double, cap: Double = 6.0): Double = min(max(width / 2, 0.0), cap)

    /** A hole larger than this fraction of the ruler is left empty. 4% of 40–160 is 4.8 BPM. */
    const val occupancyGapFraction = 0.04

    /** The merge distance for occupancy runs on a given ruler. */
    fun occupancyGap(low: Double, high: Double): Double = max(0.0, (high - low) * occupancyGapFraction)

    /** Cluster ticks that sit next to each other. A gap larger than `gap` starts a new
     *  run, so a slot that recorded 45, 50 and 90 paints 45–50 and 90, never 45–90. */
    fun occupancyRuns(values: List<Double>, gap: Double): List<Pair<Double, Double>> {
        val sorted = values.filter { it.isFinite() }.sorted()
        val first = sorted.firstOrNull() ?: return emptyList()
        val last = sorted.last()
        if (!gap.isFinite() || gap < 0) return listOf(first to last)
        val runs = mutableListOf<Pair<Double, Double>>()
        var lo = first
        var hi = first
        for (value in sorted.drop(1)) {
            if (value - hi > gap) {
                runs.add(lo to hi)
                lo = value
                hi = value
            } else {
                hi = value
            }
        }
        runs.add(lo to hi)
        return runs
    }

    /** Reduce a window's ticks to occupied runs per slot. 288 ticks over 24 hours become
     *  96 fifteen-minute columns; each column only paints the value bands that have ticks.
     *  `points` are `(fraction, value)` pairs. */
    fun envelopes(points: List<Pair<Double, Double>>, seconds: Double, span: Double,
                  valueGap: Double = Double.POSITIVE_INFINITY): List<Envelope> {
        val slots = timeSlots(seconds, span)
        if (slots.isEmpty()) return emptyList()
        val buckets = List(slots.size) { mutableListOf<Double>() }
        for ((fraction, value) in points) {
            if (!value.isFinite()) continue
            val slot = clamp(fraction) * span / seconds
            val index = min(slots.size - 1, max(0, floor(slot).toInt()))
            buckets[index].add(value)
        }
        return slots.flatMap { slot ->
            val values = buckets[slot.index]
            if (values.isEmpty()) return@flatMap emptyList()
            occupancyRuns(values, valueGap).map { (low, high) ->
                Envelope(slot.index, slot.start, slot.end, low, high,
                    values.count { it >= low && it <= high })
            }
        }
    }

    fun equalSlots(count: Int): List<SlotRange> {
        val n = max(count, 1)
        return (0 until n).map { SlotRange(it.toDouble() / n, (it + 1).toDouble() / n) }
    }

    /** Climb totals: a missing or zero hour is a flat stretch, not a skip. */
    fun cumulativeTotals(increments: List<Double?>): List<Double> {
        var running = 0.0
        return increments.map { increment ->
            if (increment != null && increment > 0) running += increment
            running
        }
    }

    fun isVacantHour(value: Double?): Boolean = value == null || value <= 0

    /** Sequential runs, or offset-placed runs on a night window. Offsets win when every
     *  run carries one, matching the hypnogram's own layout. */
    fun stageSpans(minutes: List<Int>, offsets: List<Int>?, windowMinutes: Double?): List<StageSpan> {
        if (offsets != null && offsets.size == minutes.size) {
            val farthest = offsets.zip(minutes).maxOfOrNull { it.first + it.second } ?: 0
            val total = max(windowMinutes ?: 0.0, farthest.toDouble())
            if (total <= 0) return emptyList()
            return offsets.zip(minutes).map { (offset, length) ->
                StageSpan(offset / total, (offset + length) / total)
            }
        }
        val total = minutes.sum().toDouble()
        if (total <= 0) return emptyList()
        var cursor = 0.0
        return minutes.map { length ->
            val start = cursor
            val width = length / total
            cursor += width
            StageSpan(start, start + width)
        }
    }

    /** Nearest recorded point, or a gap at the finger when that point is not a neighbour.
     *  Equal distance prefers the later sample so a midpoint on a time series reads forward. */
    fun pickPoint(finger: Double, points: List<Point>, maxFraction: Double): Pick {
        val f = clamp(finger)
        if (points.isEmpty()) return gapPick(f)
        var bestIndex = 0
        var bestDist = abs(points[0].fraction - f)
        for (index in 1 until points.size) {
            val dist = abs(points[index].fraction - f)
            if (dist < bestDist - 1e-12 || (abs(dist - bestDist) <= 1e-12 && index > bestIndex)) {
                bestIndex = index
                bestDist = dist
            }
        }
        val best = points[bestIndex]
        if (bestDist <= maxFraction) {
            return Pick(best.fraction, best.yFraction, best.text, pointIdentity(bestIndex), true)
        }
        return gapPick(f)
    }

    /** The bin that contains the finger. Marker sits on the bin's centre. A hole between
     *  bins is a gap — never the last bin just because nothing else matched. */
    fun pickBin(finger: Double, bins: List<Bin>): Pick {
        val f = clamp(finger)
        val bin = bins.withIndex().firstOrNull { (i, b) -> contains(f, b.start, b.end, i == bins.size - 1) }?.value
            ?: return gapPick(f)
        return Pick((bin.start + bin.end) / 2, if (bin.vacant) null else bin.yFraction,
            bin.text, binIdentity(bin.start), true)
    }

    /** The run under the finger. The marker stays at the finger — the whole run is the same
     *  sample — so pointing at twenty minutes of DEEP does not jump to the run's edge. */
    fun pickRun(finger: Double, runs: List<Run>): Pick {
        val f = clamp(finger)
        val run = runs.withIndex().firstOrNull { (i, r) -> contains(f, r.start, r.end, i == runs.size - 1) }?.value
            ?: return gapPick(f)
        return Pick(f, run.yFraction, run.text, runIdentity(run.start), true)
    }

    fun pointIdentity(index: Int): String = "p:$index"
    fun binIdentity(start: Double): String = "b:$start"
    fun runIdentity(start: Double): String = "r:$start"

    private fun gapPick(f: Double): Pick = Pick(f, null, null, "gap", false)

    /** Occupancy is `[start, end)` except the last interval includes 1. */
    private fun contains(f: Double, start: Double, end: Double, last: Boolean): Boolean =
        f >= start && (f < end || (last && f <= end))
}
