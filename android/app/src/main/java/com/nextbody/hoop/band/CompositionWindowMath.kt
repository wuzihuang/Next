package com.nextbody.hoop.band

import java.time.Instant
import kotlin.math.max

data class CompositionPoint(
    val at: Instant,
    val day: UserDay,
    val value: Double,
    val x: Double,
)

data class CompositionPlot(
    val runs: List<List<CompositionPoint>>,
    val bandLow: Double?,
    val bandHigh: Double?,
    val median: Double?,
    val yMin: Double,
    val yMax: Double,
    val start: Instant,
    val end: Instant,
    val now: Double?,
    val windowLow: Double?,
    val windowHigh: Double?,
    val scanCount: Int,
) {
    val points: List<CompositionPoint> get() = runs.flatten()
}

data class CompositionFieldDelta(val before: Double?, val now: Double?) {
    val delta: Double?
        get() {
            if (now == null || before == null) return null
            return now - before
        }
}

data class CompositionDayReading(
    val current: CompositionScan,
    val previous: CompositionScan?,
    val bodyFat: CompositionFieldDelta,
    val fatMass: CompositionFieldDelta,
    val leanMass: CompositionFieldDelta,
    val bmr: CompositionFieldDelta,
    val inputWeight: CompositionFieldDelta,
)

data class CompositionWeekBucket(
    /** 0 is the week ending on the focus day; 1 is the seven days before that. */
    val offset: Int,
    val start: UserDay,
    val end: UserDay,
    val averageFat: Double?,
    val scanCount: Int,
    val delta: Double?,
)

data class CompositionSpan(val first: Double?, val last: Double?)

/** Swift's `(start: Date, end: Date)` from `bounds`. */
data class CompositionBounds(val start: Instant, val end: Instant)

/** Swift's `(min: Double, max: Double)` from `scale`. */
data class CompositionScale(val min: Double, val max: Double)

/** Which way the user's training goal points, so a week cell can tell aligned from drift.
 *  Mirrors `Goal`'s three cases; kept separate because `Goal` lives in the app module. */
enum class CompositionAim(val raw: String) { cut("CUT"), recomp("RECOMP"), bulk("BULK") }

/** A week cell's tone on the ME card. Colour is a fact about measured fat and lean,
 *  never a judgement about the day and never about eating. */
enum class CompositionWeekTone {
    /** No scan landed in this week. */
    noScan,
    /** Measured, but the delta sits inside the noise band — or there is no earlier
     *  measured week to compare against. An outline, not a verdict. */
    held,
    /** Fat down or lean up, read toward the aim. */
    aligned,
    /** The week moved against the aim. */
    drift,
}

/** One cell of the ME card's 26-week grid. */
data class CompositionWeekCell(
    /** The user day this week ends on; tapping the cell opens composition there. */
    val end: UserDay,
    /** The week's representative — the latest scan inside it. */
    val scan: CompositionScan?,
    val tone: CompositionWeekTone,
)

/** Arithmetic for the composition page's three windows. No UI: the view only
 *  lays out what this file already reduced. */
object CompositionWindowMath {
    fun bounds(range: RollingPills, endingOn: UserDay, now: Instant): CompositionBounds {
        val last = minOf(now, endingOn.end)
        val days = DetailWindow(DetailSurface.composition, range).days
        return CompositionBounds(endingOn.adding(days = -(days - 1)).start, last)
    }

    /** Newest first, then filtered. A scan after `end` is someone else's tomorrow. */
    fun asOf(scans: List<CompositionScan>, end: Instant): List<CompositionScan> =
        scans.filter { it.at <= end }.sortedByDescending { it.at }

    fun inWindow(scans: List<CompositionScan>, from: Instant, to: Instant): List<CompositionScan> =
        scans.filter { it.at >= from && it.at <= to }.sortedBy { it.at }

    fun current(scans: List<CompositionScan>, asOf: Instant): CompositionScan? = asOf(scans, asOf).firstOrNull()

    fun previous(before: CompositionScan, scans: List<CompositionScan>): CompositionScan? =
        asOf(scans, before.at.minusMillis(1)).firstOrNull()

    fun dayReading(scans: List<CompositionScan>, asOf: Instant): CompositionDayReading? {
        val current = current(scans, asOf) ?: return null
        val previous = previous(current, scans)
        return CompositionDayReading(
            current = current,
            previous = previous,
            bodyFat = CompositionFieldDelta(previous?.bodyFatPercent, current.bodyFatPercent),
            fatMass = CompositionFieldDelta(previous?.fatMassKg, current.fatMassKg),
            leanMass = CompositionFieldDelta(previous?.leanMassKg, current.leanMassKg),
            bmr = CompositionFieldDelta(previous?.bmrKcal, current.bmrKcal),
            inputWeight = CompositionFieldDelta(previous?.inputWeightKg, current.inputWeightKg),
        )
    }

    /** One point a user day: the latest scan that day. Empty days stay empty. */
    fun weekPoints(scans: List<CompositionScan>, days: List<UserDay>): List<CompositionPoint> {
        if (days.isEmpty()) return emptyList()
        val denom = max(1, days.size - 1)
        return days.withIndex().mapNotNull { (index, day) ->
            val onDay = scans.filter { UserDay.containing(it.at) == day }
            val last = onDay.maxByOrNull { it.at } ?: return@mapNotNull null
            val value = last.bodyFatPercent ?: return@mapNotNull null
            CompositionPoint(at = last.at, day = day, value = value, x = index.toDouble() / denom)
        }
    }

    /** Adjacent measured days stay one run. A gap day breaks the line. */
    fun runs(points: List<CompositionPoint>, days: List<UserDay>): List<List<CompositionPoint>> {
        val runs = mutableListOf<List<CompositionPoint>>()
        var current = mutableListOf<CompositionPoint>()
        var lastIndex: Int? = null
        for (point in points) {
            val index = days.indexOf(point.day).takeIf { it >= 0 }
            if (index != null && lastIndex != null && index == lastIndex + 1) {
                current.add(point)
            } else {
                if (current.isNotEmpty()) runs.add(current)
                current = mutableListOf(point)
            }
            lastIndex = index
        }
        if (current.isNotEmpty()) runs.add(current)
        return runs
    }

    fun monthPoints(scans: List<CompositionScan>, from: Instant, to: Instant): List<CompositionPoint> {
        val span = max(0.001, BandTime.interval(to, from))
        return scans.mapNotNull { scan ->
            val value = scan.bodyFatPercent ?: return@mapNotNull null
            CompositionPoint(at = scan.at, day = UserDay.containing(scan.at), value = value,
                x = BandTime.interval(scan.at, from) / span)
        }
    }

    fun plot(scans: List<CompositionScan>, range: RollingPills, endingOn: UserDay, now: Instant): CompositionPlot {
        val window = bounds(range, endingOn, now)
        val inside = inWindow(scans, window.start, window.end)
        val days = endingOn.rollingBack(DetailWindow(DetailSurface.composition, range).days)
        val points: List<CompositionPoint>
        val runs: List<List<CompositionPoint>>
        when (range) {
            RollingPills.day -> { points = emptyList(); runs = emptyList() }
            RollingPills.week -> { points = weekPoints(inside, days); runs = runs(points, days) }
            RollingPills.month -> {
                points = monthPoints(inside, window.start, window.end)
                runs = if (points.isEmpty()) emptyList() else listOf(points)
            }
        }
        val values = points.map { it.value }
        val scale = scale(values)
        val low = values.minOrNull()
        val high = values.maxOrNull()
        return CompositionPlot(
            runs = runs, bandLow = low, bandHigh = high, median = median(values),
            yMin = scale.min, yMax = scale.max, start = window.start, end = window.end,
            now = values.lastOrNull(), windowLow = low, windowHigh = high, scanCount = inside.size)
    }

    fun weekBuckets(scans: List<CompositionScan>, endingOn: UserDay, count: Int = 4): List<CompositionWeekBucket> {
        if (count <= 0) return emptyList()
        val buckets = (0 until count).map { offset ->
            val end = endingOn.adding(days = -offset * 7)
            val start = end.adding(days = -6)
            val inside = inWindow(scans, start.start, end.end)
            val fats = inside.mapNotNull { it.bodyFatPercent }
            val average = if (fats.isEmpty()) null else fats.sum() / fats.size
            CompositionWeekBucket(offset = offset, start = start, end = end,
                averageFat = average, scanCount = inside.size, delta = null)
        }
        return buckets.withIndex().map { (index, bucket) ->
            if (index + 1 < buckets.size) {
                val now = bucket.averageFat
                val then = buckets[index + 1].averageFat
                if (now != null && then != null) return@map bucket.copy(delta = now - then)
            }
            bucket
        }
    }

    fun span(pick: (CompositionScan) -> Double?, scans: List<CompositionScan>): CompositionSpan {
        val values = scans.sortedBy { it.at }.mapNotNull(pick)
        return CompositionSpan(values.firstOrNull(), values.lastOrNull())
    }

    /** Room around the line so a quiet week is not a flat ruler. */
    fun scale(values: List<Double>): CompositionScale {
        val low = values.minOrNull() ?: return CompositionScale(0.0, 1.0)
        val high = values.maxOrNull() ?: return CompositionScale(0.0, 1.0)
        val spread = high - low
        if (spread < 0.2) return CompositionScale(low - 0.4, high + 0.4)
        val pad = max(0.3, spread * 0.25)
        return CompositionScale(low - pad, high + pad)
    }

    fun median(values: List<Double>): Double? = medianOf(values)

    /** The F2 §05 noise bands, restated so the week grid shares The Call's thresholds. */
    const val weekFatBand = 0.15
    const val weekLeanBand = 0.10

    /** 26 cells, one per user week ending on `day`, oldest first. A week is coloured by
     *  comparing its latest scan against the latest scan of the nearest earlier week that
     *  has one — empty weeks stay `noScan` and never stretch a comparison. */
    fun weekCells(scans: List<CompositionScan>, aim: CompositionAim, endingOn: UserDay, count: Int = 26): List<CompositionWeekCell> {
        val cells = mutableListOf<CompositionWeekCell>()
        var baseline: CompositionScan? = null
        for (offset in (count - 1) downTo 0) {
            val end = endingOn.adding(days = -offset * 7)
            val start = end.adding(days = -6)
            val inside = inWindow(scans, start.start, end.end)
            val rep = inside.lastOrNull()
            val tone: CompositionWeekTone
            if (rep != null) {
                val b = baseline
                tone = classify(
                    fatDelta = rep.fatMassKg?.let { now -> b?.fatMassKg?.let { now - it } },
                    leanDelta = rep.leanMassKg?.let { now -> b?.leanMassKg?.let { now - it } },
                    aim = aim)
                baseline = rep
            } else {
                tone = CompositionWeekTone.noScan
            }
            cells.add(CompositionWeekCell(end = end, scan = rep, tone = tone))
        }
        return cells
    }

    /** Goal-aware direction of one measured week. `null` deltas read as inside the band —
     *  an unmeasured field is not evidence for either direction. */
    fun classify(fatDelta: Double?, leanDelta: Double?, aim: CompositionAim): CompositionWeekTone {
        val fat = fatDelta ?: 0.0
        val lean = leanDelta ?: 0.0
        val fatDown = fat < -weekFatBand; val fatUp = fat > weekFatBand
        val leanUp = lean > weekLeanBand; val leanDown = lean < -weekLeanBand
        return when (aim) {
            CompositionAim.cut, CompositionAim.recomp -> when {
                fatUp -> CompositionWeekTone.drift
                leanDown && !fatDown -> CompositionWeekTone.drift
                fatDown || leanUp -> CompositionWeekTone.aligned
                else -> CompositionWeekTone.held
            }
            CompositionAim.bulk -> when {
                leanDown -> CompositionWeekTone.drift
                fatUp && !leanUp -> CompositionWeekTone.drift
                leanUp -> CompositionWeekTone.aligned
                else -> CompositionWeekTone.held
            }
        }
    }
}
