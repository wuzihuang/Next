package com.nextbody.hoop.band

import com.nextbody.hoop.model.DistantPast
import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.timeIntervalSince
import java.time.Instant
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * How the battery trend fills a stretch the phone did not hear.
 *
 * A lithium pack does not sit still, and it does not travel in a ruler line.
 * Discharge eases in (holds, then falls). Charge eases out (climbs, then
 * tapers). The phone never heard these points — the chart dashes them.
 */
sealed class BatteryEta {
    data class Full(val at: Instant) : BatteryEta()
    data class Empty(val at: Instant) : BatteryEta()
}

/** How long the unplugged pack still has, from the same learned slope as `eta`.
 *  Hours when empty is today-ish; whole days after that. Never the spec pack. */
sealed class BatteryLeft {
    data class Hours(val hours: Int) : BatteryLeft()
    data class Days(val days: Int) : BatteryLeft()
}

object BatteryDrainMath {
    /** Quiet measuring wear. Used only when this log has no unplugged drop to learn from. */
    const val packHours: Double = 5.0 * 24
    /** Percent-scale. Bars scale by `yMax / 100`. */
    const val chargePerHourAt100: Double = 40.0
    const val step: Double = 15.0 * 60
    const val maxSteps = 48
    const val minCurveSpan: Double = 15.0 * 60
    /** First-connect stale + fresh land in the same minute. Closer than this, the later packet wins. */
    const val clash: Double = 2.0 * 60
    /** A printed clock stays inside these bounds. Wider than this, the slope is not a time. */
    const val maxChargeHours: Double = 8.0
    const val maxEmptyHours: Double = 14.0 * 24
    /** Under this, LEFT prints hours. Eighteen hours still reads as 1 DAY. */
    const val leftHourCutoff: Double = 18.0
    /** Learn from recent wear, not a month of equally weighted packet-to-packet blips. */
    const val learningAge: Double = 7.0 * 24 * 3600
    const val dischargeWindow: Double = 48.0 * 3600
    const val minDischargeHours: Double = 6.0
    const val minDischargePercent: Double = 3.0
    /** A day without a real reading can hide an entire charge cycle. */
    const val maxReadingAge: Double = 24.0 * 3600

    fun cliff(isPercent: Boolean): Double = if (isPercent) 8.0 else 1.0

    /** Many firmwares keep sending `.charging` at 100% / 4 bars and never
     *  flip to `.full`. The pack is already topped — that is Charged. */
    fun isToppedUp(isPercent: Boolean, percent: Int?, level: Int?): Boolean {
        if (isPercent) return (percent ?: 0) >= 100
        return (level ?: 0) >= 4
    }

    fun settle(charge: BatteryObservation.Charge, isPercent: Boolean, percent: Int?, level: Int?): BatteryObservation.Charge =
        if (charge == BatteryObservation.Charge.charging && isToppedUp(isPercent, percent, level))
            BatteryObservation.Charge.full else charge

    /** SDK `default: .unknown` packets that still carry a percent or bar count.
     *  Those values are stale. A connect row with no reading is not a ghost. */
    fun isGhost(sample: BatteryObservation): Boolean =
        sample.plotValue != null && sample.charge == BatteryObservation.Charge.unknown

    /** Drop every valued `unknown` packet, then collapse a first-connect cliff,
     *  then any leftover V-dip inside the clash window. */
    fun collapse(samples: List<BatteryObservation>): List<BatteryObservation> {
        val ordered = samples.sortedBy { it.at }
        fun valued(sample: BatteryObservation): Boolean = sample.connected && sample.plotValue != null
        val withoutGhosts = ordered.filter { !isGhost(it) }

        val out = mutableListOf<BatteryObservation>()
        for (sample in withoutGhosts) {
            val last = out.lastOrNull()
            if (last != null && valued(last) && valued(sample) &&
                last.isPercent == sample.isPercent && last.charge == sample.charge) {
                val va = last.plotValue
                val vb = sample.plotValue
                if (va != null && vb != null &&
                    sample.at.timeIntervalSince(last.at) < clash &&
                    abs(va - vb) >= cliff(sample.isPercent)) {
                    out.removeAt(out.size - 1)
                }
            }
            out.add(sample)
        }

        var index = 1
        while (index + 1 < out.size) {
            val previous = out[index - 1]
            val mid = out[index]
            val next = out[index + 1]
            val low = mid.plotValue
            val left = previous.plotValue
            val right = next.plotValue
            if (valued(previous) && valued(mid) && valued(next) &&
                previous.isPercent == mid.isPercent && mid.isPercent == next.isPercent &&
                previous.charge == mid.charge && mid.charge == next.charge &&
                low != null && left != null && right != null &&
                low < left - 0.5 && low < right - 0.5 &&
                mid.at.timeIntervalSince(previous.at) < clash &&
                next.at.timeIntervalSince(mid.at) < clash) {
                out.removeAt(index)
                continue
            }
            index += 1
        }
        return out
    }

    /** Estimated points that sit on top of a heard packet are the dest we drew to NOW
     *  before the first read landed. They are the noon cliff. */
    fun scrub(points: List<BatteryPoint>): List<BatteryPoint> {
        val heard = points.filter { !it.estimated }.map { it.at }
        return points.filter { point ->
            if (!point.estimated) return@filter true
            !heard.any { abs(it.timeIntervalSince(point.at)) < clash }
        }
    }

    fun clip(spans: List<BatterySpan>, from: Instant, to: Instant): List<BatterySpan> =
        spans.mapNotNull { span ->
            val lo = maxOf(span.start, from)
            val hi = minOf(span.end, to)
            if (hi <= lo) null else BatterySpan(lo, hi)
        }

    fun progress(u: Double, rising: Boolean): Double {
        val t = min(1.0, max(0.0, u))
        if (rising) return 1 - (1 - t).pow(2.1)
        return t.pow(1.65)
    }

    /** The chart alone may fall back to the pack. LEFT and ETA require a learned rate. */
    fun drainRate(samples: List<BatteryObservation>, yMax: Double, now: Instant? = null): Double {
        val end = now ?: samples.maxOfOrNull { it.at } ?: DistantPast
        return learnedDrainRate(samples, yMax, end) ?: (yMax / packHours)
    }

    /** Net loss / full elapsed time includes integer-percent plateaus and is invariant
     *  to packet frequency. Never join across a charge, a rise, a unit change, or a
     *  day-long gap. Prefer the latest usable cycle; its last 48h reflect current wear. */
    private fun learnedDrainRate(samples: List<BatteryObservation>, yMax: Double, now: Instant): Double? {
        val rows = collapse(samples.filter { it.at <= now && now.timeIntervalSince(it.at) <= learningAge })
        val runs = mutableListOf<List<BatteryObservation>>()
        var run = mutableListOf<BatteryObservation>()
        fun finish() {
            if (run.isNotEmpty()) runs.add(run)
            run = mutableListOf()
        }
        for (row in rows) {
            if (row.charge == BatteryObservation.Charge.charging || row.charge == BatteryObservation.Charge.full) {
                finish()
                continue
            }
            // Link rows repeat cached values; they must not extend a measured plateau.
            val value = row.plotValue
            if (!row.connected || value == null) continue
            if (!(row.charge == BatteryObservation.Charge.unplugged && row.isPercent == (yMax == 100.0) &&
                    value in 0.0..yMax)) {
                finish()
                continue
            }
            val last = run.lastOrNull()
            if (last != null && (value > last.plotValue!! || row.at.timeIntervalSince(last.at) > maxReadingAge)) {
                finish()
            }
            run.add(row)
        }
        finish()
        for (r in runs.reversed()) {
            val last = r.lastOrNull() ?: continue
            val recent = r.filter { last.at.timeIntervalSince(it.at) <= dischargeWindow }
            val first = recent.firstOrNull() ?: continue
            val hours = last.at.timeIntervalSince(first.at) / 3600
            val drop = first.plotValue!! - last.plotValue!!
            val minimumDrop = if (yMax == 100.0) minDischargePercent else 1.0
            if (!(hours >= minDischargeHours && drop >= minimumDrop)) continue
            return drop / hours
        }
        return null
    }

    /** Only the current charge session can teach its full clock. Keep its plateaus too. */
    private fun chargeRate(samples: List<BatteryObservation>): Double? {
        var run = mutableListOf<BatteryObservation>()
        for (row in samples) {
            if (row.charge == BatteryObservation.Charge.unplugged || row.charge == BatteryObservation.Charge.full) {
                run = mutableListOf()
                continue
            }
            val value = row.plotValue
            if (!row.connected || value == null) continue
            if (!(row.isPercent && row.charge == BatteryObservation.Charge.charging && value in 0.0..100.0)) {
                run = mutableListOf()
                continue
            }
            val last = run.lastOrNull()
            if (last != null && (value < last.plotValue!! || row.at.timeIntervalSince(last.at) > maxReadingAge)) {
                run = mutableListOf()
            }
            run.add(row)
        }
        val first = run.firstOrNull() ?: return null
        val last = run.lastOrNull() ?: return null
        val hours = last.at.timeIntervalSince(first.at) / 3600
        val gain = last.plotValue!! - first.plotValue!!
        if (!(hours >= 0.4 && gain >= 1)) return null
        return gain / hours
    }

    /** One rough clock: full if the last heard packet is charging, empty if it
     *  is unplugged. Bars, a full pack, and an unlearned slope stay silent. */
    fun eta(samples: List<BatteryObservation>, now: Instant): BatteryEta? {
        val ordered = collapse(samples.filter { it.at <= now })
        val last = ordered.lastOrNull { it.connected && it.plotValue != null } ?: return null
        val value = last.plotValue ?: return null
        if (!(last.isPercent && value in 0.0..100.0 && now.timeIntervalSince(last.at) <= maxReadingAge)) return null
        // A later state-only event may already have put the band on a charger.
        if (ordered.any { it.at > last.at && it.charge != BatteryObservation.Charge.unknown && it.charge != last.charge }) return null
        val aged = max(0.0, now.timeIntervalSince(last.at) / 3600)
        return when (last.charge) {
            BatteryObservation.Charge.charging -> {
                if (value >= 99.5) return null
                val rate = chargeRate(ordered) ?: return null
                if (rate <= 0) return null
                val current = min(100.0, value + rate * aged)
                val hours = (100 - current) / rate
                if (!(hours > 0.05 && hours <= maxChargeHours)) return null
                BatteryEta.Full(now.addingTimeInterval(hours * 3600))
            }
            BatteryObservation.Charge.unplugged, BatteryObservation.Charge.unknown -> {
                if (value <= 0.5) return null
                val rate = learnedDrainRate(ordered, 100.0, now) ?: return null
                if (rate <= 0) return null
                val current = max(0.0, value - rate * aged)
                val hours = current / rate
                if (!(hours > 0.08 && hours <= maxEmptyHours)) return null
                BatteryEta.Empty(now.addingTimeInterval(hours * 3600))
            }
            BatteryObservation.Charge.full -> null
        }
    }

    /** Remaining wear from the learned unplugged slope. Silent wherever `eta`
     *  is silent — charging, full, bars, or an unlearned rate. */
    fun left(samples: List<BatteryObservation>, now: Instant): BatteryLeft? {
        val e = eta(samples, now) as? BatteryEta.Empty ?: return null
        val hours = e.at.timeIntervalSince(now) / 3600
        if (hours <= 0.08) return null
        if (hours < leftHourCutoff) return BatteryLeft.Hours(max(1, hours.rounded().toInt()))
        return BatteryLeft.Days(max(1, (hours / 24).rounded().toInt()))
    }

    fun project(last: BatteryPoint, to: Instant, yMax: Double, drainPerHour: Double): Double {
        val hours = to.timeIntervalSince(last.at) / 3600
        if (hours <= 0) return last.value
        return when (last.charge) {
            BatteryObservation.Charge.charging -> {
                val rise = (yMax / 100) * chargePerHourAt100 * hours
                min(yMax, last.value + rise)
            }
            BatteryObservation.Charge.unplugged, BatteryObservation.Charge.unknown, BatteryObservation.Charge.full ->
                max(0.0, last.value - drainPerHour * hours)
        }
    }

    /** Points between `start` and `end`, not including either end. Empty when
     *  the span is too short to bend. */
    fun interiorCurve(start: BatteryPoint, end: BatteryPoint): List<BatteryPoint> {
        val span = end.at.timeIntervalSince(start.at)
        if (span < minCurveSpan) return emptyList()
        val rising = end.value > start.value
        val steps = min(maxSteps, max(2, (span / step).toInt()))
        val points = mutableListOf<BatteryPoint>()
        for (i in 1 until steps) {
            val u = i.toDouble() / steps.toDouble()
            val s = progress(u, rising)
            points.add(BatteryPoint(
                at = start.at.addingTimeInterval(span * u),
                value = start.value + (end.value - start.value) * s,
                charge = start.charge,
                estimated = true))
        }
        return points
    }
}
