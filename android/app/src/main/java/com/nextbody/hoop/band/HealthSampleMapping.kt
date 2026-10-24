package com.nextbody.hoop.band

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.sqrt

data class RespirationSample(val time: String, val breathsPerMinute: Double)

data class TemperatureSample(val time: String, val celsius: Double)

data class HrvMinuteSample(
    val time: String,
    /** RMSSD from the vendor RR intervals; the only HRV value that may be labelled milliseconds. */
    val rmssdMS: Double?,
    /** The vendor's opaque HRV scalar. Retained for diagnostics, never substituted for RMSSD. */
    val vendorValue: Double?,
    val rrCount: Int,
    val rrMilliseconds: List<Double> = emptyList(),
    /** Original zero-based SDK positions. Gaps are missing beats, never adjacent pairs. */
    val rrValidIndices: List<Int> = emptyList(),
)

/** One automatic oxygen reading from the SDK oxygen history, not from origin ticks. */
data class OxygenSample(val time: String, val percent: Int)

/** One wrist optical meal-response slot. Zeros are empty slots, not a reading on the median. */
data class OpticalResponseSample(val time: String, val optical: Double)

/**
 * Pure conversion at the closed-source SDK boundary (not HealthKit — the band's own history
 * dictionaries). Free of vendor types so the unit and missing-value rules stay testable.
 */
object HealthSampleMapping {
    private val sleepFormat: DateTimeFormatter =
        DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm", Locale.US).withResolverStyle(ResolverStyle.STRICT)

    /** SDK sleep timestamps use both slash and hyphen calendar dates in the phone's zone. */
    fun sleepInstant(stamp: String?, zone: ZoneId = ZoneId.systemDefault()): Instant? {
        if (stamp == null) return null
        val normalized = stamp.replace("/", "-")
        val local = runCatching { LocalDateTime.parse(normalized, sleepFormat) }.getOrNull() ?: return null
        if (local.format(sleepFormat) != normalized) return null
        return local.atZone(zone).toInstant()
    }

    /** The same sleep segment can appear in both queried SDK pages; keep one copy of each, by start. */
    fun sleepRecordIndices(stamps: List<Pair<String?, String?>>, wakeDay: String,
                           now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<Int> {
        val day = sleepInstant("$wakeDay 00:00", zone) ?: return emptyList()
        val end = day.atZone(zone).plusDays(1).toInstant()
        val valid = stamps.withIndex().mapNotNull { (index, s) ->
            val start = sleepInstant(s.first, zone) ?: return@mapNotNull null
            val wake = sleepInstant(s.second, zone) ?: return@mapNotNull null
            if (start < wake && wake <= now && wake >= day && wake < end) Triple(index, start, wake) else null
        }.sortedWith(compareBy<Triple<Int, Instant, Instant>> { it.second }.thenBy { it.first })
        return valid.withIndex().filter { (position, row) ->
            valid.take(position).none { it.second == row.second && it.third == row.third }
        }.map { it.value.first }
    }

    /** Respiration is independent of the oxygen measurement in the same history row. */
    fun respiration(raw: Map<String, Any?>): RespirationSample? {
        val time = clock(raw["Time"] as? String ?: raw["time"] as? String) ?: return null
        val rate = number(raw["RespirationRate"] ?: raw["respirationRate"]) ?: return null
        if (!rate.isFinite() || rate <= 0 || rate >= 255) return null
        return RespirationSample(time, rate)
    }

    fun deviceDayOffsets(daysBack: Int, straddles: Boolean): List<Int> {
        if (!straddles) return listOf(maxOf(0, daysBack))
        if (daysBack == 0) return listOf(0, 1)
        return listOf(daysBack, daysBack - 1)
    }

    /** SDK page zero is the current calendar day; enumerate the days the window intersects. */
    fun deviceDayOffsets(start: Instant, now: Instant, zone: ZoneId = ZoneId.systemDefault()): List<Int> {
        if (start > now) return emptyList()
        val end = start.atZone(zone).plusDays(1).toInstant()
        val today = now.atZone(zone).toLocalDate()
        val finalDay = minOf(now, end.minusSeconds(1)).atZone(zone).toLocalDate()
        var cursor = start.atZone(zone).toLocalDate()
        val offsets = mutableListOf<Int>()
        while (cursor <= finalDay) {
            val offset = ChronoUnit.DAYS.between(cursor, today).toInt()
            if (offset >= 0) offsets += offset
            cursor = cursor.plusDays(1)
        }
        return offsets
    }

    fun instant(time: String, calendarDay: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant? {
        val normalized = clock(time) ?: return null
        val parts = normalized.split(":").map { it.toInt() }
        val day: LocalDate = calendarDay.atZone(zone).toLocalDate()
        return day.atTime(parts[0], parts[1]).atZone(zone).toInstant()
    }

    fun temperature(raw: Map<String, Any?>): TemperatureSample? {
        val hour = integer(raw["hour"]) ?: return null
        val minute = integer(raw["minute"]) ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null
        // The product stores skin temperature, which Veepoo names originalValue.
        val unscaled = number(raw["originalValue"] ?: raw["riginalValue"]) ?: return null
        val celsius = if (unscaled > 100) unscaled / 10 else unscaled
        if (celsius !in 10.0..50.0) return null
        return TemperatureSample(String.format(Locale.US, "%02d:%02d", hour, minute), celsius)
    }

    /** Overnight SpO2 only. 0 is the band's empty slot; apnea flags are ignored (ADR-0002). */
    fun oxygen(raw: Map<String, Any?>): OxygenSample? {
        val time = clock(raw["Time"] as? String ?: raw["time"] as? String) ?: return null
        val percent = integer(raw["OxygenValue"] ?: raw["oxygenValue"]) ?: return null
        if (percent !in 50..100) return null
        return OxygenSample(time, percent)
    }

    /** Vendor zeros, non-finite values and risk-level keys are dropped; one median per slot. */
    fun opticalResponse(raw: Map<String, Any?>): OpticalResponseSample? {
        val time = clock(raw["time"] as? String ?: raw["Time"] as? String) ?: return null
        val list = (raw["bloodGlucoses"] as? List<*>) ?: (raw["optical"] as? List<*>) ?: emptyList<Any?>()
        val values = list.mapNotNull { number(it) }.filter { it.isFinite() && it != 0.0 }
        val optical = median(values) ?: return null
        if (optical <= 0) return null
        return OpticalResponseSample(time, optical)
    }

    /** (mean, min) of the night's percents, mean rounded half away from zero. */
    fun overnightOxygenSummary(percents: List<Int>): Pair<Int, Int>? {
        if (percents.isEmpty()) return null
        val mean = (percents.sum().toDouble() / percents.size).roundedAway().toInt()
        return mean to percents.min()
    }

    fun hrv(raw: Map<String, Any?>): HrvMinuteSample? {
        val time = clock(raw["time"] as? String) ?: return null
        val rr = ((raw["hearts"] as? List<*>) ?: emptyList<Any?>()).withIndex().mapNotNull { (index, v) ->
            val value = number(v) ?: return@mapNotNull null
            val ms = value * 10
            if (!ms.isFinite() || ms !in 250.0..2500.0) null else index to ms
        }
        val squared = rr.drop(1).zip(rr).mapNotNull { (next, previous) ->
            if (next.first != previous.first + 1) null else (next.second - previous.second).let { it * it }
        }
        val rmssd = if (squared.isEmpty()) null else sqrt(squared.sum() / squared.size)
        return HrvMinuteSample(time, rmssd, number(raw["hrvValue"]), rr.size,
            rr.map { it.second }, rr.map { it.first })
    }

    /** Exact measured minutes for the sleep surface. */
    fun hrvByMinute(samples: List<HrvMinuteSample>): Map<String, Double> {
        val valid = samples.mapNotNull { s ->
            val time = clock(s.time) ?: return@mapNotNull null
            val value = s.rmssdMS ?: return@mapNotNull null
            if (!value.isFinite() || value !in 1.0..300.0) null else time to value
        }
        return valid.groupBy({ it.first }, { it.second }).mapNotNull { (k, v) -> median(v)?.let { k to it } }.toMap()
    }

    /** The day's HRV on the five-minute grid; RMSSD only, 1–300 ms (nb.night_hrv_parts). */
    fun hrvBySlot(samples: List<HrvMinuteSample>): Map<String, Double> {
        val measured = samples.mapNotNull { s ->
            val minutes = minutesSinceMidnight(s.time) ?: return@mapNotNull null
            val value = s.rmssdMS ?: return@mapNotNull null
            if (!value.isFinite() || value !in 1.0..300.0) return@mapNotNull null
            val slot = (minutes / 5) * 5
            String.format(Locale.US, "%02d:%02d", slot / 60, slot % 60) to value
        }
        return measured.groupBy({ it.first }, { it.second }).mapNotNull { (k, v) -> median(v)?.let { k to it } }.toMap()
    }

    /** Revoke only a legacy cross-gap result that this read disproves. */
    fun invalidHRVMinutes(samples: List<HrvMinuteSample>): Set<String> {
        val valid = hrvByMinute(samples).keys
        return samples.mapNotNull { s ->
            if (s.rmssdMS != null || s.rrMilliseconds.size < 2 || s.rrValidIndices.size != s.rrMilliseconds.size) return@mapNotNull null
            val time = clock(s.time) ?: return@mapNotNull null
            if (s.rrValidIndices.drop(1).zip(s.rrValidIndices).any { it.first == it.second + 1 }) return@mapNotNull null
            if (time in valid) null else time
        }.toSet()
    }

    /** Another valid minute in the same five-minute slot keeps that slot. */
    fun invalidHRVSlots(samples: List<HrvMinuteSample>): Set<String> {
        val valid = hrvBySlot(samples).keys
        return invalidHRVMinutes(samples).mapNotNull { time ->
            val minutes = minutesSinceMidnight(time) ?: return@mapNotNull null
            val slot = minutes / 5 * 5
            val c = String.format(Locale.US, "%02d:%02d", slot / 60, slot % 60)
            if (c in valid) null else c
        }.toSet()
    }

    /** A fractional value is kilometres; a whole one is already metres. */
    fun distanceMeters(value: Any?): Int? {
        val raw = number(value) ?: return null
        if (!raw.isFinite() || raw < 0) return null
        val isKilometres = raw % 1.0 != 0.0
        val m = (if (isKilometres) raw * 1000 else raw).roundedAway()
        return if (m <= Int.MAX_VALUE) m.toInt() else null
    }

    private fun number(value: Any?): Double? {
        val parsed = when (value) {
            is Boolean -> if (value) 1.0 else 0.0
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull()
            else -> null
        }
        return parsed?.takeIf { it.isFinite() }
    }

    private fun integer(value: Any?): Int? = number(value)?.let { if (it % 1.0 == 0.0 && it in -2e9..2e9) it.toInt() else null }

    private val clockRegex = Regex("(\\d{1,2}):(\\d{2})")

    private fun clock(value: String?): String? {
        if (value == null) return null
        val m = clockRegex.find(value) ?: return null
        val h = m.groupValues[1].toIntOrNull() ?: return null
        val min = m.groupValues[2].toIntOrNull() ?: return null
        if (h !in 0..23 || min !in 0..59) return null
        return String.format(Locale.US, "%02d:%02d", h, min)
    }

    private fun minutesSinceMidnight(time: String): Int? {
        val parts = time.split(":").mapNotNull { it.toIntOrNull() }
        if (parts.size != 2) return null
        return parts[0] * 60 + parts[1]
    }

    private fun median(values: List<Double>): Double? = medianOf(values)
}

/**
 * A server may cap a page below the requested limit. Only an empty page ends the bounded
 * sample read; callers receive the complete result or an error.
 */
object SamplePageRead {
    suspend fun <Row> all(fetch: suspend (offset: Int) -> List<Row>): List<Row> {
        val rows = mutableListOf<Row>()
        while (true) {
            currentCoroutineContext().ensureActive()
            val page = fetch(rows.size)
            if (page.isEmpty()) return rows
            rows.addAll(page)
        }
    }
}
