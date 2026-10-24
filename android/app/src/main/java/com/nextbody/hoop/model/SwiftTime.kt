package com.nextbody.hoop.model

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.sign
import kotlin.math.truncate

// Port helpers: the Foundation behaviour the Swift sources lean on, spelled once so every
// ported file does the same arithmetic (`Date` → `Instant`, `TimeInterval` → Double seconds,
// `Calendar.current` → `ZoneId.systemDefault()`).

/** `Date.distantPast`. */
val DistantPast: Instant = Instant.parse("0001-01-01T00:00:00Z")

/** `Date.distantFuture`. */
val DistantFuture: Instant = Instant.parse("4001-01-01T00:00:00Z")

/** The zone `Calendar.current` stands for. Read per call — the user can change it. */
fun currentZone(): ZoneId = ZoneId.systemDefault()

/** `a.timeIntervalSince(b)` in seconds, with sub-second precision and no overflow. */
fun Instant.timeIntervalSince(other: Instant): Double =
    (epochSecond - other.epochSecond).toDouble() + (nano - other.nano) / 1_000_000_000.0

/** `Date.addingTimeInterval(_:)`. */
fun Instant.addingTimeInterval(seconds: Double): Instant {
    val whole = floor(seconds)
    val nanos = Math.round((seconds - whole) * 1_000_000_000.0)
    return plusSeconds(whole.toLong()).plusNanos(nanos)
}

/** `Date(timeIntervalSince1970:)`. */
fun instantFromEpochSeconds(seconds: Double): Instant = Instant.EPOCH.addingTimeInterval(seconds)

/** `date.timeIntervalSince1970`. */
val Instant.timeIntervalSince1970: Double get() = timeIntervalSince(Instant.EPOCH)

fun Instant.zoned(zone: ZoneId = currentZone()): ZonedDateTime = atZone(zone)

fun Instant.localDate(zone: ZoneId = currentZone()): LocalDate = atZone(zone).toLocalDate()

/** `Calendar.current.component(.hour, from:)`. */
fun Instant.localHour(zone: ZoneId = currentZone()): Int = atZone(zone).hour

fun Instant.localMinute(zone: ZoneId = currentZone()): Int = atZone(zone).minute

/** `Calendar.current.date(bySettingHour:minute:second:of:)`. */
fun Instant.settingHour(hour: Int, minute: Int, second: Int = 0, zone: ZoneId = currentZone()): Instant =
    ZonedDateTime.of(localDate(zone), LocalTime.of(hour, minute, second), zone).toInstant()

/** `Calendar.current.date(byAdding: .day, value:, to:)`. */
fun Instant.addingDays(days: Int, zone: ZoneId = currentZone()): Instant =
    atZone(zone).plusDays(days.toLong()).toInstant()

fun Instant.addingMinutes(minutes: Int, zone: ZoneId = currentZone()): Instant =
    atZone(zone).plusMinutes(minutes.toLong()).toInstant()

fun Instant.addingYears(years: Int, zone: ZoneId = currentZone()): Instant =
    atZone(zone).plusYears(years.toLong()).toInstant()

/** `Calendar.current.startOfDay(for:)`. */
fun Instant.startOfDay(zone: ZoneId = currentZone()): Instant =
    localDate(zone).atStartOfDay(zone).toInstant()

/** `Calendar.current.isDate(_:inSameDayAs:)`. */
fun Instant.isSameDay(other: Instant, zone: ZoneId = currentZone()): Boolean =
    localDate(zone) == other.localDate(zone)

/**
 * Swift `Double.rounded()` — schoolbook rounding, half away from zero. Kotlin's `round` is
 * half-even, which would move .5 seed values and break 1:1 parity with the simulator.
 */
fun Double.rounded(): Double {
    if (isNaN() || isInfinite()) return this
    val t = truncate(this)
    return if (abs(this - t) >= 0.5) t + sign(this) else t
}

/** Swift `Int(x)` truncation of an already-rounded double. */
fun Double.roundedInt(): Int = rounded().toInt()

/** Swift `String(format:)` — POSIX formatting, always `.` as the decimal point. */
fun swiftFormat(format: String, vararg args: Any?): String = String.format(Locale.ROOT, format, *args)

/** Swift `Double.isFinite`. */
val Double.isFiniteValue: Boolean get() = !isNaN() && !isInfinite()
