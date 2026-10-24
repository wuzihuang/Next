package com.nextbody.hoop.band

import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.instantFromEpochSeconds
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.model.timeIntervalSince1970
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import kotlin.math.max

/**
 * One reading the phone actually heard from the band — percent or bars, charge
 * state, and whether the link was up. The trend is this log; a long quiet
 * stretch is filled with `BatteryDrainMath`, not a ruler to NOW.
 */
data class BatteryObservation(
    var at: Instant,
    var isPercent: Boolean,
    var percent: Int?,
    var level: Int?,
    var charge: Charge,
    var connected: Boolean,
) {
    enum class Charge(val raw: String) {
        unplugged("unplugged"), charging("charging"), full("full"), unknown("unknown");

        companion object {
            fun fromRaw(raw: String): Charge? = entries.firstOrNull { it.raw == raw }
            fun from(raw: String): Charge? = fromRaw(raw)
        }
    }

    /** What the chart plots. A bar count stays a bar count — it is never multiplied into %. */
    val plotValue: Double?
        get() = if (isPercent) percent?.toDouble() else level?.toDouble()
}

data class BatteryPoint(
    var at: Instant,
    var value: Double,
    var charge: BatteryObservation.Charge,
    var estimated: Boolean = false,
)

data class BatterySpan(var start: Instant, var end: Instant)

data class BatteryPlot(
    var runs: List<List<BatteryPoint>>,
    var charging: List<BatterySpan>,
    var isPercent: Boolean,
    var yMax: Double,
    var high: Double?,
    var low: Double?,
    var start: Instant,
    var end: Instant,
) {
    val points: List<BatteryPoint> get() = runs.flatten()
}

/** Swift's `(start: Date, end: Date)` window tuple. */
data class BatteryWindow(val start: Instant, val end: Instant)

/**
 * Record every real battery event, skip chatter, keep plateaus, and draw the line
 * the device page shows after a tap on the ring.
 */
object BatteryLog {
    const val plateau: Double = 30.0 * 60
    /** Long enough for the month window. Older rows fall off on the next record. */
    const val keep: Double = 30.0 * 24 * 3600
    const val cap = 2000
    const val windowDays = 7

    fun window(endingAt: Instant, days: Int = windowDays): BatteryWindow =
        BatteryWindow(endingAt.addingTimeInterval(-days.toDouble() * 24 * 3600), endingAt)

    fun window(endingAt: Instant, range: RollingPills): BatteryWindow {
        val hours = DetailWindow(DetailSurface.battery, range).hours
        return BatteryWindow(endingAt.addingTimeInterval(-hours.toDouble() * 3600), endingAt)
    }

    fun record(
        existing: List<BatteryObservation>,
        at: Instant,
        isPercent: Boolean,
        percent: Int?,
        level: Int?,
        charge: BatteryObservation.Charge,
        connected: Boolean,
    ): List<BatteryObservation> {
        val incoming = BatteryObservation(
            at = at, isPercent = isPercent, percent = percent, level = level,
            charge = BatteryDrainMath.settle(charge, isPercent, percent, level),
            connected = connected)
        var samples = existing
            .filter { at.timeIntervalSince(it.at) <= keep && !BatteryDrainMath.isGhost(it) }
            .sortedBy { it.at }
        if (BatteryDrainMath.isGhost(incoming)) return samples
        val last = samples.lastOrNull()
        if (last != null) {
            val same = last.isPercent == incoming.isPercent &&
                last.percent == incoming.percent &&
                last.level == incoming.level &&
                last.charge == incoming.charge &&
                last.connected == incoming.connected
            val dt = incoming.at.timeIntervalSince(last.at)
            if (same && dt >= 0 && dt < plateau) return samples
            if (incoming.at < last.at) return samples
        }
        samples = samples + incoming
        if (samples.size > cap) samples = samples.takeLast(cap)
        return samples
    }

    fun plot(samples: List<BatteryObservation>, from: Instant, to: Instant): BatteryPlot {
        val start = from
        val end = to
        val ordered = BatteryDrainMath.collapse(samples.filter { it.at <= end })
        val series = mutableListOf<BatteryObservation>()
        val carry = ordered.lastOrNull { it.at < start }
        if (carry != null) series.add(carry.copy(at = start))
        series.addAll(ordered.filter { it.at >= start && it.at <= end })

        // Only a sample that carries a value gets a vote. Connect/disconnect rows have no
        // reading in them and must not decide whether this band speaks percent or bars.
        val valued = series.filter { it.plotValue != null }
        val percented = valued.count { it.isPercent }
        val isPercent = percented >= valued.size - percented

        val yMax = if (isPercent) 100.0 else 4.0
        // Learn from actual timestamps, before cropping/carrying the chart window.
        // Switching DAY/WEEK/MONTH must not change the projected battery at NOW.
        val drainPerHour = BatteryDrainMath.drainRate(ordered, yMax, now = end)

        val runs = mutableListOf<List<BatteryPoint>>()
        var run = mutableListOf<BatteryPoint>()
        val charging = mutableListOf<BatterySpan>()
        var chargeStart: Instant? = null
        var lastHeard: BatteryPoint? = null

        fun flushRun() {
            val cleaned = BatteryDrainMath.scrub(run)
            if (cleaned.isNotEmpty()) runs.add(cleaned)
            run = mutableListOf()
        }
        fun closeCharge(at: Instant) {
            val started = chargeStart
            if (started != null && at > started) charging.add(BatterySpan(started, at))
            chargeStart = null
        }
        fun stitch(next: BatteryPoint) {
            val last = lastHeard ?: return
            if (next.at <= last.at) return
            run.addAll(BatteryDrainMath.interiorCurve(last, next))
        }

        for (sample in series) {
            if (!sample.connected) {
                closeCharge(sample.at)
                continue
            }
            val value = sample.plotValue ?: continue
            // A bar count is not a percentage. A sample in the other unit cannot share this
            // ruler — plotted on it, 3 bars would draw as 3 % — so the line breaks instead.
            if (sample.isPercent != isPercent) {
                flushRun()
                lastHeard = null
                continue
            }
            val point = BatteryPoint(at = sample.at, value = value, charge = sample.charge)
            stitch(point)
            run.add(point)
            lastHeard = point
            if (sample.charge == BatteryObservation.Charge.charging) {
                if (chargeStart == null) chargeStart = sample.at
            } else {
                closeCharge(sample.at)
            }
        }
        val last = lastHeard
        if (last != null) {
            if (last.at < end && end.timeIntervalSince(last.at) >= BatteryDrainMath.clash) {
                val dest = BatteryPoint(
                    at = end,
                    value = BatteryDrainMath.project(last, end, yMax, drainPerHour),
                    charge = last.charge,
                    estimated = true)
                stitch(dest)
                run.add(dest)
            }
            if (chargeStart != null) closeCharge(end)
        } else {
            chargeStart = null
        }
        flushRun()

        val values = runs.flatten().map { it.value }
        return BatteryPlot(
            runs = runs,
            charging = charging,
            isPercent = isPercent,
            yMax = yMax,
            high = values.maxOrNull(),
            low = values.minOrNull(),
            start = start,
            end = end)
    }

    /** Simulator walk-through: a month of overnight charges, then three closer days
     *  with a disconnect, ending on `percent`. */
    fun seed(now: Instant, percent: Int = 82): List<BatteryObservation> {
        fun row(hoursAgo: Double, value: Int, charge: BatteryObservation.Charge,
                connected: Boolean = true): BatteryObservation =
            BatteryObservation(
                at = now.addingTimeInterval(-hoursAgo * 3600),
                isPercent = true, percent = value, level = null,
                charge = charge, connected = connected)
        val U = BatteryObservation.Charge.unplugged
        val C = BatteryObservation.Charge.charging
        val F = BatteryObservation.Charge.full
        val rows = mutableListOf<BatteryObservation>()
        for (day in 29 downTo 4) {
            val base = day.toDouble() * 24
            val trough = 28 + (day % 5) * 6
            rows.add(row(base + 18, max(22, trough - 8), U))
            if (day % 6 == 0) {
                rows.add(row(base + 10, max(18, trough - 16), U))
                if (day == 12) {
                    rows.add(row(base + 9, max(18, trough - 16), U, connected = false))
                    rows.add(row(base + 8.5, max(18, trough - 16), U))
                }
            } else {
                rows.add(row(base + 16, trough, U))
                rows.add(row(base + 15.95, trough, C))
                rows.add(row(base + 11, 100, F))
                rows.add(row(base + 10.95, 100, U))
            }
            rows.add(row(base + 4, 78 + (day % 3) * 4, U))
        }
        rows.addAll(listOf(
            row(70.0, 100, F),
            row(69.9, 100, U),
            row(64.0, 88, U),
            row(58.0, 72, U),
            row(52.0, 55, U),
            row(48.0, 40, U),
            row(47.9, 40, C),
            row(44.0, 70, C),
            row(40.0, 100, F),
            row(39.9, 100, U),
            row(34.0, 86, U),
            row(28.0, 68, U),
            row(26.0, 68, U, connected = false),
            row(25.5, 68, U),
            row(22.0, 48, U),
            row(21.9, 48, C),
            row(16.0, 85, C),
            row(14.0, 100, F),
            row(13.9, 100, U),
            row(8.0, 94, U),
            row(4.0, 88, U),
            row(0.0, percent, U),
        ))
        return rows.sortedBy { it.at }
    }

    /** Last time the band reported it was on a charger. Pass a window when the
     *  number belongs to one range; omit it for the device page's lifetime stamp. */
    fun lastPlug(samples: List<BatteryObservation>, from: Instant? = null, to: Instant? = null): Instant? =
        samples.lastOrNull { sample ->
            if (sample.charge != BatteryObservation.Charge.charging) return@lastOrNull false
            if (from != null && sample.at < from) return@lastOrNull false
            if (to != null && sample.at > to) return@lastOrNull false
            true
        }?.at

    /** Last time the phone had the link. A connected sample counts, including
     *  the one that is still live. */
    fun lastLink(samples: List<BatteryObservation>): Instant? = samples.lastOrNull { it.connected }?.at
}

/** Persisted as JSON (dates as seconds since 1970, like the Swift encoder) in [Defaults]. */
object BatteryLogStore {
    fun key(owner: String): String = "nb.battery.log.$owner"

    fun load(owner: String): List<BatteryObservation> {
        if (owner.isEmpty()) return emptyList()
        val text = Defaults.getString(key(owner)) ?: return emptyList()
        return runCatching {
            val array = JSONArray(text)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                BatteryObservation(
                    at = instantFromEpochSeconds(o.getDouble("at")),
                    isPercent = o.getBoolean("isPercent"),
                    percent = if (o.has("percent") && !o.isNull("percent")) o.getInt("percent") else null,
                    level = if (o.has("level") && !o.isNull("level")) o.getInt("level") else null,
                    charge = BatteryObservation.Charge.fromRaw(o.getString("charge")) ?: error("charge"),
                    connected = o.getBoolean("connected"))
            }
        }.getOrDefault(emptyList())
    }

    fun save(samples: List<BatteryObservation>, owner: String) {
        if (owner.isEmpty()) return
        val array = JSONArray()
        for (s in samples) {
            array.put(JSONObject().apply {
                put("at", s.at.timeIntervalSince1970)
                put("isPercent", s.isPercent)
                s.percent?.let { put("percent", it) }
                s.level?.let { put("level", it) }
                put("charge", s.charge.raw)
                put("connected", s.connected)
            })
        }
        Defaults.putString(key(owner), array.toString())
    }
}
