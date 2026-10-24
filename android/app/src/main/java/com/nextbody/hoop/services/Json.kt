package com.nextbody.hoop.services

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * The Swift side reads PostgREST rows as `[String: Any]`. Kotlin keeps them as [JSONObject]
 * and writes from `Map<String, Any?>` / [JSONObject] / lists, converted here.
 */
object Json {
    fun parse(text: String): Any? {
        if (text.isBlank()) return null
        return runCatching { JSONTokener(text).nextValue() }.getOrNull()
    }

    fun rows(any: Any?): List<JSONObject>? {
        val array = any as? JSONArray ?: return null
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }

    /** Any Kotlin value → a JSON value (Map → JSONObject, List → JSONArray, null → NULL). */
    fun wrap(value: Any?): Any = when (value) {
        null -> JSONObject.NULL
        JSONObject.NULL -> JSONObject.NULL
        is JSONObject, is JSONArray, is String, is Boolean -> value
        is Int, is Long, is Short, is Byte -> value
        is Double -> if (value.isFinite()) value else JSONObject.NULL
        is Float -> if (value.isFinite()) value.toDouble() else JSONObject.NULL
        is Number -> value
        is Map<*, *> -> JSONObject().also { o -> value.forEach { (k, v) -> o.put(k.toString(), wrap(v)) } }
        is Iterable<*> -> JSONArray().also { a -> value.forEach { a.put(wrap(it)) } }
        is Array<*> -> JSONArray().also { a -> value.forEach { a.put(wrap(it)) } }
        is Instant -> Iso.string(value)
        is java.util.Date -> Iso.string(value.toInstant())
        is java.util.UUID -> value.toString().lowercase()
        else -> value.toString()
    }

    fun obj(value: Any?): JSONObject = when (value) {
        is JSONObject -> value
        is Map<*, *> -> wrap(value) as JSONObject
        null -> JSONObject()
        else -> throw IllegalArgumentException("Not a JSON object: ${value::class.java.simpleName}")
    }

    fun array(value: List<Any?>): JSONArray = JSONArray().also { a -> value.forEach { a.put(wrap(it)) } }

    /** JSONObject → Map with nested values unwrapped. */
    fun toMap(o: JSONObject): Map<String, Any?> = o.keys().asSequence().associateWith { unwrap(o.opt(it)) }
    fun toList(a: JSONArray): List<Any?> = (0 until a.length()).map { unwrap(a.opt(it)) }
    fun unwrap(v: Any?): Any? = when (v) {
        JSONObject.NULL, null -> null
        is JSONObject -> toMap(v)
        is JSONArray -> toList(v)
        else -> v
    }
}

/** Swift `number(_:)`: Double, Int, numeric String, NSNumber. */
fun number(any: Any?): Double? = when (any) {
    null, JSONObject.NULL -> null
    is Number -> any.toDouble()
    is String -> any.toDoubleOrNull()
    else -> null
}

fun JSONObject.optStringOrNull(key: String): String? {
    if (!has(key) || isNull(key)) return null
    return opt(key) as? String
}

fun JSONObject.number(key: String): Double? = if (isNull(key)) null else com.nextbody.hoop.services.number(opt(key))
fun JSONObject.optBoolOrNull(key: String): Boolean? = if (isNull(key)) null else opt(key) as? Boolean
fun JSONObject.objOrNull(key: String): JSONObject? = if (isNull(key)) null else opt(key) as? JSONObject
fun JSONObject.arrayOrNull(key: String): JSONArray? = if (isNull(key)) null else opt(key) as? JSONArray
fun JSONArray.objects(): List<JSONObject> = (0 until length()).mapNotNull { optJSONObject(it) }

/** ISO-8601 the way the Swift side writes and reads it. */
object Iso {
    private val fractional: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSXXX").withZone(ZoneOffset.UTC)
    private val plain: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX").withZone(ZoneOffset.UTC)

    /** `ISO8601DateFormatter()` — seconds, `Z`. */
    fun string(at: Instant): String = plain.format(at.truncatedTo(ChronoUnit.SECONDS)).replace("+00:00", "Z")

    /** `[.withInternetDateTime, .withFractionalSeconds]` — milliseconds, `Z`. */
    fun fractional(at: Instant): String = fractional.format(at).replace("+00:00", "Z")

    /**
     * PostgREST hands back fractional seconds and sometimes no zone suffix. Port of
     * HealthSnapshotRead.timestamp / ISOTimestamp: `YYYY-MM-DD[T ]HH:MM:SS[.fraction][Z | ±HH[:MM]]`
     * parsed by hand (no zone means UTC), then the formatter fallbacks.
     */
    fun parse(raw: String?): Instant? {
        if (raw.isNullOrEmpty()) return null
        fast(raw)?.let { return it }
        runCatching { return OffsetDateTime.parse(raw).toInstant() }
        runCatching { return Instant.parse(raw) }
        runCatching { return java.time.LocalDateTime.parse(raw).toInstant(ZoneOffset.UTC) }
        return null
    }

    private fun fast(raw: String): Instant? {
        val b = raw
        var i = 0
        fun digits(count: Int): Int? {
            if (i + count > b.length) return null
            var v = 0
            for (k in 0 until count) {
                val c = b[i + k]
                if (c !in '0'..'9') return null
                v = v * 10 + (c - '0')
            }
            i += count
            return v
        }
        fun expect(c: Char): Boolean {
            if (i >= b.length || b[i] != c) return false
            i += 1; return true
        }
        val year = digits(4) ?: return null
        if (!expect('-')) return null
        val month = digits(2) ?: return null
        if (!expect('-')) return null
        val day = digits(2) ?: return null
        if (i >= b.length || (b[i] != 'T' && b[i] != ' ')) return null
        i += 1
        val hour = digits(2) ?: return null
        if (!expect(':')) return null
        val minute = digits(2) ?: return null
        if (!expect(':')) return null
        val second = digits(2) ?: return null
        if (month !in 1..12 || day !in 1..31 || hour >= 24 || minute >= 60 || second >= 61) return null
        var nanos = 0L
        if (i < b.length && b[i] == '.') {
            i += 1
            var scale = 100_000_000L
            var any = false
            while (i < b.length && b[i] in '0'..'9') {
                nanos += (b[i] - '0') * scale; scale /= 10; i += 1; any = true
            }
            if (!any) return null
        }
        var offset = 0
        if (i < b.length) {
            if (b[i] == 'Z') {
                i += 1
            } else if (b[i] == '+' || b[i] == '-') {
                val sign = if (b[i] == '-') -1 else 1
                i += 1
                val oh = digits(2) ?: return null
                var om = 0
                if (i < b.length) {
                    if (b[i] == ':') { i += 1; om = digits(2) ?: return null }
                    else { om = digits(2) ?: return null }
                }
                if (oh >= 24 || om >= 60) return null
                offset = sign * (oh * 3600 + om * 60)
            }
        }
        if (i != b.length) return null
        // Days since 1970-01-01, proleptic Gregorian (Howard Hinnant's civil algorithm).
        val y = if (month <= 2) year - 1 else year
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val mp = (month + 9) % 12
        val doy = (153 * mp + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        val days = era.toLong() * 146097 + doe - 719468
        val seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset
        return Instant.ofEpochSecond(seconds, nanos)
    }
}
