package com.nextbody.hoop.band

import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.data.DebugEnv

/**
 * Surface-specific overrides on top of `RollingPills`: period words, load,
 * debug keys, and HEART slot minutes. Grain lives on the pills; hero
 * arithmetic stays in each page's WindowMath.
 *
 * ⚠️ Fuel's month is 28 user days (four weeks, spoken as a typical day). Everything
 * else that counts days uses 30. Sleep counts nights. Every DAY window is the user day.
 */
enum class DetailSurface(val raw: String) {
    sleep("sleep"), heart("heart"), response("response"), metric("metric"), active("active"),
    fuel("fuel"), training("training"), composition("composition"), battery("battery"),
    /** 13 / ADR 0017 · 身体电量。跟设备页的 `.battery` 不是同一个表面。 */
    bodyBattery("bodyBattery");

    companion object {
        fun fromRaw(raw: String): DetailSurface? = entries.firstOrNull { it.raw == raw }
    }
}

data class DetailWindow(var surface: DetailSurface, var range: RollingPills) {

    /** Slots drawn. Sleep counts nights. Fuel month is 28. Battery day is still 1 (24h). */
    val days: Int get() = range.userDays(month = if (surface == DetailSurface.fuel) 28 else 30)

    val hours: Int get() = days * 24

    /** English source for `L()`. Metric / active day is empty — the instrument keeps its own label. */
    val periodKey: String
        get() = when {
            surface == DetailSurface.sleep && range == RollingPills.day -> "LAST NIGHT"
            surface == DetailSurface.sleep && range == RollingPills.week -> "LAST 7 NIGHTS"
            surface == DetailSurface.sleep && range == RollingPills.month -> "LAST 30 NIGHTS"
            // Issue #19 · a day is a day. No surface answers DAY with a rolling 24 hours.
            range == RollingPills.day && surface in setOf(
                DetailSurface.heart, DetailSurface.response, DetailSurface.battery, DetailSurface.fuel,
                DetailSurface.training, DetailSurface.composition, DetailSurface.bodyBattery) -> "TODAY"
            range == RollingPills.day && (surface == DetailSurface.metric || surface == DetailSurface.active) -> ""
            surface == DetailSurface.fuel && range == RollingPills.week -> "7 DAYS"
            surface == DetailSurface.fuel && range == RollingPills.month -> "4 WEEKS"
            range == RollingPills.week -> "LAST 7 DAYS"
            else -> "LAST 30 DAYS"
        }

    val slotMinutes: Double
        get() {
            val hm = surface == DetailSurface.heart || surface == DetailSurface.metric || surface == DetailSurface.active
            return when {
                hm && range == RollingPills.day -> 15.0
                hm -> 1440.0
                else -> 0.0
            }
        }

    val responseHorizon: MealResponseIndex.Horizon
        get() = when (range) {
            RollingPills.day -> MealResponseIndex.Horizon.UserDays(1)
            RollingPills.week -> MealResponseIndex.Horizon.UserDays(7)
            RollingPills.month -> MealResponseIndex.Horizon.UserDays(30)
        }

    val debugEnvironmentKey: String
        get() = when (surface) {
            DetailSurface.sleep -> "NB_DEBUG_SLEEP_RANGE"
            DetailSurface.heart -> "NB_DEBUG_HEART_RANGE"
            DetailSurface.response -> "NB_DEBUG_RESPONSE_RANGE"
            DetailSurface.metric, DetailSurface.active -> "NB_DEBUG_METRIC_RANGE"
            DetailSurface.fuel -> "NB_DEBUG_FUEL_RANGE"
            DetailSurface.training -> "NB_DEBUG_TRAINING_RANGE"
            DetailSurface.composition -> "NB_DEBUG_COMP_RANGE"
            DetailSurface.battery -> "NB_DEBUG_BATTERY_RANGE"
            DetailSurface.bodyBattery -> "NB_DEBUG_BODY_BATTERY_RANGE"
        }

    sealed class Load {
        data object None : Load()
        data class DailyResults(val lookback: Int) : Load()
        data class HeartTicks(val days: Int) : Load()
        data class DailyResultsAndHeartTicks(val lookback: Int, val heartDays: Int) : Load()
        data object Composition : Load()
    }

    val load: Load
        get() = when (surface) {
            DetailSurface.sleep, DetailSurface.response -> Load.None
            DetailSurface.battery ->
                Load.DailyResults(lookback = DetailWindow(DetailSurface.battery, RollingPills.month).days - 1)
            DetailSurface.composition -> Load.Composition
            DetailSurface.fuel ->
                Load.DailyResults(lookback = DetailWindow(DetailSurface.fuel, RollingPills.month).days - 1)
            DetailSurface.training, DetailSurface.bodyBattery ->
                Load.DailyResults(lookback = DetailWindow(DetailSurface.training, RollingPills.month).days - 1)
            DetailSurface.heart ->
                if (range == RollingPills.day) Load.None else Load.HeartTicks(days = days)
            // The week hero says how the window compares with the seven days before it,
            // and STRESS and TEMP can only say that from ticks — so a week pulls fourteen.
            // The month's comparison would need sixty and is left unsaid instead.
            DetailSurface.metric ->
                if (range == RollingPills.day) Load.None
                else Load.HeartTicks(days = if (range == RollingPills.week) days * 2 else days)
            DetailSurface.active ->
                if (range == RollingPills.day) Load.DailyResults(lookback = 6)
                else Load.DailyResultsAndHeartTicks(lookback = days - 1, heartDays = days)
        }

    companion object {
        /** Swift's failable `init?(_ surface:, raw:)`. */
        fun of(surface: DetailSurface, raw: String): DetailWindow? {
            val range = RollingPills.fromRaw(raw) ?: return null
            return DetailWindow(surface, range)
        }

        fun debugRange(surface: DetailSurface): RollingPills? {
            if (!BuildConfig.DEBUG) return null
            val key = DetailWindow(surface, RollingPills.day).debugEnvironmentKey
            val raw = DebugEnv[key] ?: return null
            return RollingPills.fromRaw(raw)
        }
    }
}
