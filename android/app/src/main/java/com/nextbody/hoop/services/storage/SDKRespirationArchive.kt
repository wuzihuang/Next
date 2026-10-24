package com.nextbody.hoop.services.storage

import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle

/**
 * Isolated read-only access to fields that the vendor's public getters discard. On iOS this is
 * the Veepoo SDK's sqlite `oxygen_table`; the Android SDK keeps its own database — callers pass
 * whatever file the Android SDK writes, and an absent or differently shaped file is
 * [Failure.Unavailable] / [Failure.IncompatibleSchema].
 */
object SDKRespirationArchive {
    data class Reading(val time: String, val rate: Double)

    sealed class Failure(message: String) : Exception(message) {
        class InvalidSelector : Failure("Invalid SDK respiratory history selector")
        class Unavailable : Failure("SDK respiratory archive is unavailable")
        class IncompatibleSchema : Failure("SDK respiratory archive schema is unsupported")
        class ReadFailed : Failure("SDK respiratory archive could not be read")
        class InvalidJSON : Failure("SDK respiratory archive contains invalid data")
        class AmbiguousPartition : Failure("SDK respiratory archive contains ambiguous device/day records")
    }

    private val mac = Regex("^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$")
    private val clock = Regex("^([01][0-9]|2[0-3]):[0-5][0-9]$")
    private val strictDay: DateTimeFormatter = DateTimeFormatter.ofPattern("uuuu-MM-dd").withResolverStyle(ResolverStyle.STRICT)

    /** Never opens another device's partition or creates/modifies the SDK database. */
    fun read(file: File, deviceAddress: String, day: String): List<Reading> {
        if (!mac.matches(deviceAddress) || !validDay(day)) throw Failure.InvalidSelector()
        if (!file.exists()) throw Failure.Unavailable()
        val db = try {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY)
        } catch (e: Exception) { throw Failure.Unavailable() }
        db.use {
            val cursor = try {
                it.rawQuery("SELECT json FROM oxygen_table WHERE accountUser = ? AND createdTime = ? LIMIT 2",
                    arrayOf(deviceAddress, day))
            } catch (e: Exception) { throw Failure.IncompatibleSchema() }
            cursor.use { c ->
                if (!c.moveToFirst()) return emptyList()
                val text = try { c.getString(0) } catch (e: Exception) { throw Failure.ReadFailed() }
                    ?: throw Failure.ReadFailed()
                if (c.moveToNext()) throw Failure.AmbiguousPartition()
                return readings(text)
            }
        }
    }

    private fun validDay(day: String): Boolean =
        runCatching { LocalDate.parse(day, strictDay).toString() == day }.getOrDefault(false)

    private fun readings(text: String): List<Reading> {
        val rows = runCatching { JSONArray(text) }.getOrNull() ?: throw Failure.InvalidJSON()
        val out = mutableListOf<Reading>()
        for (i in 0 until rows.length()) {
            val row = rows.opt(i) as? JSONObject ?: throw Failure.InvalidJSON()
            val raw = row.opt("RespirationRate")
            val rate: Double? = when (raw) {
                is Boolean -> continue
                is Number -> raw.toDouble()
                is String -> raw.toDoubleOrNull()
                else -> null
            }
            // 0/255 are empty SDK slots. This is an encoding boundary, not a health range.
            if (rate == null || !rate.isFinite() || rate <= 0 || rate >= 255) continue
            val time = row.opt("Time") as? String
            if (time == null || !clock.matches(time)) throw Failure.InvalidJSON()
            out += Reading(time, rate)
        }
        return out.sortedBy { it.time }
    }
}
