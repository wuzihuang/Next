package com.nextbody.hoop.band

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Platform seams the Swift band layer got for free from Foundation: the main actor,
 * os.Logger / NightDiagnostics, and UserDefaults. Kept in one place so the pure math files
 * stay free of Android types and run under plain JUnit.
 */

/** Swift `@MainActor` + `Task { }`. Tests set [dispatcher] (e.g. `Dispatchers.Unconfined`). */
object BandMain {
    @Volatile var dispatcher: CoroutineDispatcher? = null
    private val resolved: CoroutineDispatcher
        get() = dispatcher ?: runCatching { Dispatchers.Main.immediate.also { it.isDispatchNeeded(kotlin.coroutines.EmptyCoroutineContext) } }
            .getOrElse { Dispatchers.Default }

    val scope: CoroutineScope get() = CoroutineScope(SupervisorJob() + resolved)

    /** `Task { @MainActor in … }`. */
    fun launch(block: suspend CoroutineScope.() -> Unit): Job = scope.launch(block = block)
}

/** `Logger(subsystem: "com.nextbody.hoop", category: "band")` and `NightDiagnostics.shared.record`. */
object BandTrace {
    /** Set by the app to forward into NightDiagnostics once the services layer has one. */
    @Volatile var recorder: ((String, Map<String, String>) -> Unit)? = null

    fun notice(message: String) = log("I", message)
    fun error(message: String) = log("E", message)
    fun debug(message: String) = log("D", message)

    fun record(event: String, fields: Map<String, String> = emptyMap()) {
        runCatching { recorder?.invoke(event, fields) }
        log("D", "$event $fields")
    }

    private fun log(level: String, message: String) {
        runCatching {
            when (level) {
                "E" -> android.util.Log.e("band", message)
                "I" -> android.util.Log.i("band", message)
                else -> android.util.Log.d("band", message)
            }
        }
    }
}

/**
 * `UserDefaults.standard` for the band layer. A thin typed view over the data layer's
 * [com.nextbody.hoop.data.Defaults] (the one `nb` SharedPreferences file, in-memory before
 * `Defaults.init` — JVM tests run on that), so the account-delete sweep sees every `nb.` key.
 */
object BandPrefs {
    private val d = com.nextbody.hoop.data.Defaults

    fun string(key: String): String? = d.getString(key)
    fun setString(key: String, value: String?) = d.putString(key, value)

    fun bool(key: String): Boolean? = if (d.contains(key)) d.getBoolean(key) else null
    fun setBool(key: String, value: Boolean?) { if (value == null) d.remove(key) else d.putBoolean(key, value) }

    fun long(key: String): Long? = d.getLong(key)
    fun setLong(key: String, value: Long?) { if (value == null) d.remove(key) else d.putLong(key, value) }

    fun int(key: String): Int? = if (d.contains(key)) d.getInt(key) else null
    fun setInt(key: String, value: Int?) { if (value == null) d.remove(key) else d.putInt(key, value) }

    /** Doubles travel as their raw bits in a long under `key#d`. */
    fun double(key: String): Double? = long("$key#d")?.let { java.lang.Double.longBitsToDouble(it) }
    fun setDouble(key: String, value: Double?) = setLong("$key#d", value?.let { java.lang.Double.doubleToRawLongBits(it) })

    /** Swift `Date` in UserDefaults. */
    fun instant(key: String): Instant? = double(key)?.let { BandTime.fromSeconds(it) }
    fun setInstant(key: String, value: Instant?) = setDouble(key, value?.let { BandTime.seconds(it) })

    fun remove(key: String) { d.remove(key); d.remove("$key#d") }

    val keys: Set<String> get() = d.keys
}

/** Foundation `Date` / `Calendar` helpers. Swift `Date` is an [Instant]; `TimeInterval` is seconds as Double. */
object BandTime {
    val distantPast: Instant = Instant.parse("0001-01-01T00:00:00Z")
    val distantFuture: Instant = Instant.parse("4001-01-01T00:00:00Z")

    fun seconds(instant: Instant): Double = instant.epochSecond + instant.nano / 1_000_000_000.0
    fun fromSeconds(seconds: Double): Instant {
        val whole = Math.floor(seconds).toLong()
        val nanos = ((seconds - whole) * 1_000_000_000.0).toLong().coerceIn(0, 999_999_999)
        return Instant.ofEpochSecond(whole, nanos)
    }

    /** `a.timeIntervalSince(b)`. */
    fun interval(a: Instant, since: Instant): Double = seconds(a) - seconds(since)

    /** `date.addingTimeInterval(seconds)`. */
    fun adding(instant: Instant, seconds: Double): Instant = fromSeconds(seconds(instant) + seconds)

    /** `calendar.startOfDay(for:)`. */
    fun startOfDay(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant =
        instant.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()

    fun localDate(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): LocalDate = instant.atZone(zone).toLocalDate()

    /** `calendar.date(byAdding: .day, value: n, to: date)`. */
    fun addingDays(instant: Instant, days: Long, zone: ZoneId = ZoneId.systemDefault()): Instant =
        instant.atZone(zone).plusDays(days).toInstant()

    /** `calendar.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day`. */
    fun daysBetween(from: Instant, to: Instant, zone: ZoneId = ZoneId.systemDefault()): Int =
        java.time.temporal.ChronoUnit.DAYS.between(localDate(from, zone), localDate(to, zone)).toInt()

    /** `calendar.isDate(a, inSameDayAs: b)`. */
    fun sameDay(a: Instant, b: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean = localDate(a, zone) == localDate(b, zone)

    /** "yyyy-MM-dd" in [zone]. */
    fun dayKey(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): String = localDate(instant, zone).toString()
}
