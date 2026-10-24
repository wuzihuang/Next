package com.nextbody.hoop.band

import java.time.Instant
import java.time.ZoneId

/** One row of the device alarm table. Preserve text read from text-alarm firmware. */
data class BandAlarm(
    val id: Int,
    val hour: Int,
    val minute: Int,
    val on: Boolean,
    val repeatMask: Int,
    val date: String,
    val scene: Int,
    val text: String = "",
) {
    val repeats: Boolean get() = repeatMask != 0
    val showsSwitch: Boolean get() = repeats

    val isValidDeviceValue: Boolean
        get() = id in 1..255 && hour in 0..23 && minute in 0..59
            && repeatMask in 0..127 && text.toByteArray(Charsets.UTF_8).size <= 60

    val clock: String get() = String.format(java.util.Locale.ROOT, "%02d:%02d", hour, minute)

    companion object {
        const val onceDatePlaceholder = "0000-00-00"
        const val demoCeiling = 20
        const val silentScene = 0

        /** Empty model the read command accepts. IDs and times come back from the band. */
        fun emptyRead(): BandAlarm = BandAlarm(id = 0, hour = 0, minute = 0, on = false, repeatMask = 0,
            date = onceDatePlaceholder, scene = silentScene)
    }
}

enum class BandAlarmProtocol {
    scene, text;

    val capacity: Int get() = if (this == text) 10 else 20

    /** App operations are delete=0, write=1, read=2; text SDK operations start at 1. */
    fun sdkMode(operation: Int): Int = if (this == text) operation + 1 else operation

    companion object {
        /** Swift `init?(functionData:)`. */
        fun from(functionData: ByteArray?): BandAlarmProtocol? {
            if (functionData == null || functionData.size <= 17) return null
            return when (functionData[17].toInt() and 0xFF) {
                in 1..4 -> scene
                in 5..7 -> text
                else -> null
            }
        }
    }
}

object BandAlarmMath {
    /** LSB Monday … bit 6 Sunday. Bit 7 stays 0, matching the vendor week string. */
    enum class Weekday(val raw: Int) {
        monday(0), tuesday(1), wednesday(2), thursday(3), friday(4), saturday(5), sunday(6);

        val bit: Int get() = 1 shl raw

        val short: String
            get() = when (this) {
                monday -> "MON"; tuesday -> "TUE"; wednesday -> "WED"; thursday -> "THU"
                friday -> "FRI"; saturday -> "SAT"; sunday -> "SUN"
            }

        val pill: String
            get() = when (this) {
                monday -> "M"; tuesday -> "T"; wednesday -> "W"; thursday -> "T"
                friday -> "F"; saturday -> "S"; sunday -> "S"
            }
    }

    val weekdaysMask = Weekday.monday.bit or Weekday.tuesday.bit or Weekday.wednesday.bit or
        Weekday.thursday.bit or Weekday.friday.bit
    val weekendMask = Weekday.saturday.bit or Weekday.sunday.bit
    const val everyDayMask = 0b0111_1111

    fun has(mask: Int, day: Weekday): Boolean = mask and day.bit != 0

    fun toggling(mask: Int, day: Weekday): Int = mask xor day.bit

    fun phrase(mask: Int): String {
        val days = mask and everyDayMask
        if (days == 0) return "ONCE"
        if (days == everyDayMask) return "EVERY DAY"
        if (days == weekdaysMask) return "WEEKDAYS"
        if (days == weekendMask) return "WEEKEND"
        return Weekday.entries.filter { has(days, it) }.joinToString(" · ") { it.short }
    }

    fun nextID(alarms: List<BandAlarm>, ceiling: Int = BandAlarm.demoCeiling): Int? {
        if (ceiling <= 0) return null
        val used = alarms.map { it.id }.toSet()
        // Match VPDeviceNewAlarmModel.getMinimumAlarmID: writable IDs start at 1.
        // Zero belongs to the empty read model, not a newly created alarm.
        return (1..ceiling).firstOrNull { it !in used }
    }

    fun isFull(alarms: List<BandAlarm>, ceiling: Int = BandAlarm.demoCeiling): Boolean = alarms.size >= ceiling

    /** A one-shot needs a date the firmware will still accept. If today's clock
     *  already passed, the fire day is tomorrow. */
    fun onceDate(hour: Int, minute: Int, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        val today = now.atZone(zone).toLocalDate().atTime(hour, minute, 0).atZone(zone)
        val fire = if (today.toInstant() > now) today else today.plusDays(1)
        return String.format(java.util.Locale.ROOT, "%04d-%02d-%02d", fire.year, fire.monthValue, fire.dayOfMonth)
    }

    fun prepared(draft: BandAlarm, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): BandAlarm {
        val date = if (draft.repeatMask == 0) onceDate(draft.hour, draft.minute, now, zone) else BandAlarm.onceDatePlaceholder
        return draft.copy(scene = BandAlarm.silentScene, date = date)
    }
}
