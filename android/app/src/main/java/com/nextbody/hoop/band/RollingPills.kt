package com.nextbody.hoop.band

/**
 * DAY / WEEK / MONTH on a second-level page. Same three English words;
 * grain and hero stay per instrument (ADR 0012). A natural week is not a window.
 *
 * Default last-N is 1 / 7 / 30 user days. Fuel's month is 28 — the caller
 * writes `userDays(month = 28)`. Battery borrows the words and keeps wall hours.
 */
enum class RollingPills(val raw: String) {
    day("DAY"),
    week("WEEK"),
    month("MONTH");

    val userDays: Int get() = userDays(month = 30)

    fun userDays(month: Int): Int = when (this) {
        day -> 1
        week -> 7
        RollingPills.month -> month
    }

    val periodKey: String get() = periodKey(day = "TODAY", week = "LAST 7 DAYS", month = "LAST 30 DAYS")

    fun periodKey(
        day: String = "TODAY",
        week: String = "LAST 7 DAYS",
        month: String = "LAST 30 DAYS",
    ): String = when (this) {
        RollingPills.day -> day
        RollingPills.week -> week
        RollingPills.month -> month
    }

    companion object {
        val words: List<String> get() = entries.map { it.raw }

        fun fromRaw(raw: String): RollingPills? = entries.firstOrNull { it.raw == raw }

        fun parse(raw: String): RollingPills = fromRaw(raw) ?: day
    }
}
