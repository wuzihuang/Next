package com.nextbody.hoop.band

import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** How one five-minute tick sits above sitting. Sport is a raised-HR window or
 *  MET ≥ 4; a walk is MET 1.5…4; incidental is the 1.0…1.5 leftover (standing,
 *  chores). Sitting (MET 1.0) adds nothing — that energy is already in BMR. */
enum class ActiveEnergyKind(val raw: String) { sport("sport"), steps("steps"), incidental("incidental") }

data class ActiveEnergySplit(
    val resting: Double? = null,
    val sport: Double? = null,
    val steps: Double? = null,
    val incidental: Double? = null,
    val active: Double? = null,
    val out: Double? = null,
    val sportMinutes: Int? = null,
    val sportMet: Double? = null,
    val stepCount: Int? = null,
    val stepsMet: Double? = null,
    val incidentalMinutes: Int? = null,
    val incidentalMet: Double? = null,
    val bmrFull: Double? = null,
    val elapsedMinutes: Int? = null,
)

data class ActiveEnergyHour(
    /** Bar height is movement only. Lived rest hours are 0; future hours are 0, never a BMR floor. */
    val kcal: Double,
    val lived: Boolean,
)

data class ActiveEnergyWeekBar(val start: Instant, val active: Double?, val isToday: Boolean)

/** Swift's `(resting:, active:, out:)` from `totals`. */
data class ActiveEnergyTotals(val resting: Double?, val active: Double?, val out: Double?)

/** Swift's `(bars:, average:, todayDelta:)` from `week`. */
data class ActiveEnergyWeek(val bars: List<ActiveEnergyWeekBar>, val average: Double?, val todayDelta: Double?)

/** Ledger arithmetic for ACTIVE ENERGY. The OUT polyline is
 *  `FuelWindowMath.burnCurve` — the same points the calories page draws — so the
 *  two pages cannot disagree about how a walk steepens the day. Movement parts
 *  are relative MET minutes scaled onto the settled active total; this file
 *  never invents a second kcal_out. */
object ActiveEnergyMath {
    const val stillMet = 1.0
    const val walkMet = 1.5
    const val sportMet = 4.0

    fun activityMet(met: Double? = null, steps: Int?): Double? = FuelWindowMath.activityMet(met, steps)

    fun classify(met: Double, inSport: Boolean): ActiveEnergyKind? {
        if (inSport || met >= sportMet) return ActiveEnergyKind.sport
        if (met >= walkMet) return ActiveEnergyKind.steps
        if (met > stillMet) return ActiveEnergyKind.incidental
        return null
    }

    /** RESTING + ACTIVE = OUT. Keep explicit server components intact. `eTrain`
     *  is a separate component only in local seeds; production folds it into active. */
    fun totals(bmr: Double?, eActive: Double?, eTrain: Double?, eOutNow: Double?): ActiveEnergyTotals {
        val active = eActive?.let { it + (eTrain ?: 0.0) }
        // Components are the server's explicit estimates. Older total-burn revisions
        // can disagree with them; never overwrite recorded activity by subtracting OUT.
        val out = bmr?.let { rest -> active?.let { rest + it } } ?: eOutNow
        return ActiveEnergyTotals(bmr, active, out)
    }

    fun derivedBmrFull(bmr: Double?, bmrFull: Double?, dayStart: Instant, now: Instant,
                       zone: ZoneId = ZoneId.systemDefault()): Double? {
        if (bmrFull != null && bmrFull > 0) return bmrFull
        val dayEnd = FuelWindowMath.dayEnd(dayStart, zone)
        val elapsed = BandTime.interval(minOf(now, dayEnd), dayStart)
        if (bmr == null || bmr <= 0 || elapsed <= 0) return null
        return bmr * BandTime.interval(dayEnd, dayStart) / elapsed
    }

    fun split(dayStart: Instant, now: Instant, bmr: Double?, bmrFull: Double?,
              eActive: Double?, eTrain: Double?, eOutNow: Double?,
              ticks: List<VitalSample>, sportWindows: List<Pair<Instant, Instant>>,
              energyDistribution: List<FuelEnergyPoint>? = null,
              zone: ZoneId = ZoneId.systemDefault()): ActiveEnergySplit {
        val totals = totals(bmr, eActive, eTrain, eOutNow)
        val dayEnd = FuelWindowMath.dayEnd(dayStart, zone)
        val elapsed = max(0, (BandTime.interval(minOf(now, dayEnd), dayStart) / 60).toInt())
        val raw = RawBuckets()
        val samples = ticks.filter { it.ts >= dayStart && it.ts <= now }.sortedBy { it.ts }
        for (sample in samples) {
            val met = activityMet(sample.met, sample.steps) ?: continue
            val kind = classify(met, inside(sample.ts, sportWindows))
            raw.add(kind, met, sample.steps, 5)
        }

        var weights = doubleArrayOf(raw.sport, raw.steps, raw.incidental)
        if (energyDistribution != null) {
            weights = doubleArrayOf(0.0, 0.0, 0.0)
            val lo = BandTime.seconds(dayStart); val hi = BandTime.seconds(now)
            for (p in energyDistribution) {
                if (p.epoch < lo || p.epoch > hi) continue
                weights[0] += p.strengthWeight
                val at = BandTime.fromSeconds(p.epoch)
                val met = ticks.firstOrNull { abs(BandTime.interval(it.ts, at)) < 1 }
                    ?.let { activityMet(it.met, it.steps) } ?: 1.0
                when (classify(met, inside(at, sportWindows))) {
                    ActiveEnergyKind.sport -> weights[0] += p.originWeight
                    ActiveEnergyKind.steps -> weights[1] += p.originWeight
                    else -> weights[2] += p.originWeight
                }
            }
        }
        val parts = allocate(weights.toList(), totals.active)
        var sport = parts[0]
        var walk = parts[1]
        var incidental = parts[2]

        val active = totals.active
        if (sport == null && eTrain != null && eTrain > 0 && active != null && active + 0.5 >= eTrain) {
            sport = min(eTrain, active)
            val leftover = max(0.0, active - sport)
            val restRaw = raw.steps + raw.incidental
            if (restRaw > 0) {
                val remaining = allocate(listOf(raw.steps, raw.incidental), leftover)
                walk = remaining[0]
                incidental = remaining[1]
            }
        }

        return ActiveEnergySplit(
            resting = totals.resting, sport = sport, steps = walk, incidental = incidental,
            active = totals.active, out = totals.out,
            sportMinutes = if (raw.sportMinutes > 0) raw.sportMinutes else null,
            sportMet = raw.sportMet,
            stepCount = if (raw.stepCount > 0) raw.stepCount else null,
            stepsMet = raw.stepsMet,
            incidentalMinutes = if (raw.incidentalMinutes > 0) raw.incidentalMinutes else null,
            incidentalMet = raw.incidentalMet,
            bmrFull = derivedBmrFull(bmr, bmrFull, dayStart, now, zone),
            elapsedMinutes = if (elapsed > 0) elapsed else null)
    }

    /** User-day hours (23/25 on DST changes). Bar height is activity only:
     *  a lived rest hour is 0, and a future hour is 0 — BMR never paints into the column. */
    fun hourly(dayStart: Instant, now: Instant, split: ActiveEnergySplit,
               ticks: List<VitalSample>, sportWindows: List<Pair<Instant, Instant>>,
               zone: ZoneId = ZoneId.systemDefault()): List<ActiveEnergyHour> {
        val active = split.active ?: return emptyList()
        if (active < 0 || now <= dayStart) return emptyList()
        val dayEnd = FuelWindowMath.dayEnd(dayStart, zone)
        val hourCount = (BandTime.interval(dayEnd, dayStart) / 3600).roundedAway().toInt()
        val extra = DoubleArray(hourCount)
        for (sample in ticks) {
            if (sample.ts < dayStart || sample.ts > now) continue
            var index = (BandTime.interval(sample.ts, dayStart) / 3600).toInt()
            if (index > 0 && livedFraction(index, dayStart, now) == 0.0) index -= 1
            if (index !in 0 until hourCount) continue
            val met = activityMet(sample.met, sample.steps) ?: continue
            extra[index] += max(0.0, met - stillMet)
        }
        val totalExtra = extra.sum()
        // The daily total can arrive before its raw samples. Do not invent a last-hour peak.
        if (!(active == 0.0 || totalExtra > 0)) return emptyList()
        return (0 until hourCount).map { i ->
            val fraction = livedFraction(i, dayStart, now)
            val movement = if (totalExtra > 0) active * extra[i] / totalExtra else 0.0
            ActiveEnergyHour(kcal = if (fraction > 0) movement else 0.0, lived = fraction > 0)
        }
    }

    fun peakHour(hours: List<ActiveEnergyHour>): IndexedValue<Double>? {
        var best: IndexedValue<Double>? = null
        for ((i, hour) in hours.withIndex()) {
            if (!hour.lived || hour.kcal <= 0) continue
            if (best == null || hour.kcal > best.value) best = IndexedValue(i, hour.kcal)
        }
        return best
    }

    /** Same polyline the calories page draws for OUT. */
    fun outCurve(dayStart: Instant, now: Instant, burnedNow: Double, burnedFull: Double?,
                 restingNow: Double?, ticks: List<VitalSample>, zone: ZoneId = ZoneId.systemDefault()): FuelClockCurve =
        FuelWindowMath.burnCurve(dayStart, now, burnedNow, burnedFull, restingNow, ticks, zone)

    /** Elapsed BMR as a straight ruler. The dashed run keeps that slope — leftover
     *  BMR only, no guessed evening walk. */
    fun restCurve(dayStart: Instant, now: Instant, resting: Double, zone: ZoneId = ZoneId.systemDefault()): FuelClockCurve {
        val openX = FuelWindowMath.clockFraction(dayStart, dayStart, zone)
        val nowX = FuelWindowMath.clockFraction(now, dayStart, zone)
        val solid = listOf(FuelClockPoint(openX, 0.0), FuelClockPoint(nowX, resting))
        if (nowX >= 1) return FuelClockCurve(solid, emptyList())
        val span = max(0.001, nowX - openX)
        val end = resting + resting / span * (1 - nowX)
        return FuelClockCurve(solid, listOf(FuelClockPoint(nowX, resting), FuelClockPoint(1.0, end)))
    }

    fun intensity(dayStart: Instant, now: Instant, ticks: List<VitalSample>, zone: ZoneId = ZoneId.systemDefault()): FuelClockCurve {
        val nowX = FuelWindowMath.clockFraction(now, dayStart, zone)
        val samples = ticks.filter { it.ts >= dayStart && it.ts <= now }.sortedBy { it.ts }
        val solid = mutableListOf<FuelClockPoint>()
        var previousEnd: Instant? = null
        for (sample in samples) {
            val met = activityMet(sample.met, sample.steps) ?: continue
            val x = FuelWindowMath.clockFraction(sample.ts, dayStart, zone)
            if (x > nowX) break
            // A recorded MET describes one five-minute slot, never the hours until
            // the next reading. A skipped/unknown slot starts a separate path.
            val end = minOf(now, sample.ts.plusSeconds(5 * 60))
            solid.add(FuelClockPoint(x, met, startsSegment = previousEnd == null || sample.ts > previousEnd))
            solid.add(FuelClockPoint(FuelWindowMath.clockFraction(end, dayStart, zone), met))
            previousEnd = end
        }
        if (solid.isEmpty()) return FuelClockCurve.empty
        val dashed = if (nowX < 1) listOf(FuelClockPoint(nowX, stillMet), FuelClockPoint(1.0, stillMet)) else emptyList()
        return FuelClockCurve(solid, dashed)
    }

    fun week(days: List<Pair<Instant, Double?>>, todayStart: Instant): ActiveEnergyWeek {
        val bars = days.map { ActiveEnergyWeekBar(start = it.first, active = it.second, isToday = it.first == todayStart) }
        val values = bars.mapNotNull { it.active }
        val average = if (values.isEmpty()) null else values.sum() / values.size
        val today = bars.firstOrNull { it.isToday }?.active
        val delta = today?.let { t -> average?.let { t - it } }
        return ActiveEnergyWeek(bars, average, delta)
    }

    fun hoursLeft(dayStart: Instant, now: Instant, zone: ZoneId = ZoneId.systemDefault()): Int =
        max(0, ceil(BandTime.interval(FuelWindowMath.dayEnd(dayStart, zone), now) / 3600).toInt())

    // MARK: - private

    private class RawBuckets {
        var sport = 0.0
        var steps = 0.0
        var incidental = 0.0
        var sportMinutes = 0
        var incidentalMinutes = 0
        var stepCount = 0
        var sportMetSum = 0.0
        var sportMetN = 0
        var stepsMetSum = 0.0
        var stepsMetN = 0
        var incidentalMetSum = 0.0
        var incidentalMetN = 0

        val total: Double get() = sport + steps + incidental
        val sportMet: Double? get() = if (sportMetN > 0) sportMetSum / sportMetN else null
        val stepsMet: Double? get() = if (stepsMetN > 0) stepsMetSum / stepsMetN else null
        val incidentalMet: Double? get() = if (incidentalMetN > 0) incidentalMetSum / incidentalMetN else null

        fun add(kind: ActiveEnergyKind?, met: Double, steps: Int?, minutes: Int) {
            if (kind == null) return
            val extra = max(0.0, met - stillMet) * minutes
            when (kind) {
                ActiveEnergyKind.sport -> {
                    sport += extra; sportMinutes += minutes; sportMetSum += met; sportMetN += 1
                }
                ActiveEnergyKind.steps -> {
                    this.steps += extra; stepCount += max(0, steps ?: 0); stepsMetSum += met; stepsMetN += 1
                }
                ActiveEnergyKind.incidental -> {
                    incidental += extra; incidentalMinutes += minutes; incidentalMetSum += met; incidentalMetN += 1
                }
            }
        }
    }

    private fun inside(at: Instant, windows: List<Pair<Instant, Instant>>): Boolean =
        windows.any { at >= it.first && at < it.second }

    /** Round cumulative shares so the printed integer parts close to the printed total. */
    private fun allocate(weights: List<Double>, active: Double?): List<Double?> {
        val total = weights.sum()
        if (active == null || active <= 0 || total <= 0) return weights.map { null }
        var cumulative = 0.0
        var assigned = 0.0
        return weights.map { weight ->
            if (weight <= 0) return@map null
            cumulative += weight
            val next = (active * cumulative / total).roundedAway()
            val part = next - assigned
            assigned = next
            part
        }
    }

    private fun livedFraction(hour: Int, dayStart: Instant, now: Instant): Double {
        val start = dayStart.plusSeconds(hour.toLong() * 3600)
        val end = start.plusSeconds(3600)
        if (now <= start) return 0.0
        if (now >= end) return 1.0
        return BandTime.interval(now, start) / 3600
    }
}
