package com.nextbody.hoop.band

import java.net.URI
import java.net.URLDecoder
import java.time.Instant
import java.time.ZoneId

/** F1 Sec 03 + ADR 0019 · deep links and which notification edge may fire.
 *  Pure JVM so it can be tested without the notification framework. */
sealed class NotificationDeepLink {
    data object HomePanel : NotificationDeepLink()
    data class Fuel(val slot: String?) : NotificationDeepLink()
    data object Device : NotificationDeepLink()
    data class Composition(val day: String?) : NotificationDeepLink()
    data object LogPhoto : NotificationDeepLink()
    data object Training : NotificationDeepLink()
    data object Home : NotificationDeepLink()

    /** The deep link as a `nextbody://` URL string. */
    val url: String
        get() = when (this) {
            HomePanel -> "nextbody://home?panel=body_battery"
            Home -> "nextbody://home"
            is Fuel -> if (!slot.isNullOrEmpty()) "nextbody://fuel?slot=$slot" else "nextbody://fuel"
            Device -> "nextbody://device"
            is Composition -> if (!day.isNullOrEmpty()) "nextbody://composition?date=$day" else "nextbody://composition"
            LogPhoto -> "nextbody://log?via=photo"
            Training -> "nextbody://training"
        }

    companion object {
        fun parse(url: String): NotificationDeepLink? {
            val uri = runCatching { URI(url) }.getOrNull() ?: return null
            if (uri.scheme != "nextbody") return null
            val host = (uri.host ?: "").lowercase()
            val items: List<Pair<String, String?>> = (uri.rawQuery ?: "").split("&").filter { it.isNotEmpty() }.map {
                val i = it.indexOf('=')
                if (i < 0) decode(it) to null else decode(it.substring(0, i)) to decode(it.substring(i + 1))
            }
            fun query(name: String): String? = items.firstOrNull { it.first == name }?.second
            return when (host) {
                "home" -> when {
                    query("panel") == "body_battery" -> HomePanel
                    query("panel") == null -> Home
                    else -> null
                }
                "fuel" -> Fuel(query("slot"))
                "device" -> Device
                "composition" -> Composition(query("date"))
                "log" -> if (query("via") == "photo") LogPhoto else null
                "training" -> Training
                else -> null
            }
        }

        private fun decode(s: String): String = runCatching { URLDecoder.decode(s.replace("+", "%2B"), "UTF-8") }.getOrDefault(s)
    }
}

enum class NotifyKind(val raw: String) {
    morning("morning"), meal("meal"), training("training"), daily("daily"), reserve("reserve"),
    bandBattery("bandBattery"), bandAway("bandAway");

    val priority: Int
        get() = when (this) {
            bandBattery -> 0; bandAway -> 1; morning -> 2; reserve -> 3
            training -> 4; meal -> 5; daily -> 6
        }

    val requestId: String get() = "nb.notif.$raw"

    val deepLink: NotificationDeepLink
        get() = when (this) {
            morning, reserve -> NotificationDeepLink.HomePanel
            meal -> NotificationDeepLink.Fuel(slot = null)
            training -> NotificationDeepLink.Training
            daily -> NotificationDeepLink.Home
            bandBattery, bandAway -> NotificationDeepLink.Device
        }
}

enum class NotifyPage { fuel, training, device, bodyBattery, other }

sealed class NotifyPlan {
    data object Skip : NotifyPlan()
    data class Later(val kind: NotifyKind, val at: Instant, val mealSlot: String?, val weekly: Boolean) : NotifyPlan()
    data class Fire(val kind: NotifyKind, val mealSlot: String?, val weekly: Boolean) : NotifyPlan()
}

data class NotifySnapshot(
    val now: Instant,
    val quietEnabled: Boolean,
    val deliveredCount: Int,
    val delivered: Set<NotifyKind>,
    val page: NotifyPage,

    val morningOn: Boolean,
    val trainingOn: Boolean,
    val mealsOn: Boolean,
    val wrapOn: Boolean,
    val energyOn: Boolean,
    val bandOn: Boolean,

    val wakePeak: Instant?,
    val morningShown: Boolean,

    val daySealed: Boolean,
    val mealsInLast7Days: Int,
    val breakfastConfirmed: Boolean,
    val lunchConfirmed: Boolean,
    val dinnerConfirmed: Boolean,
    val moved: Boolean,

    val trainingLoad: Double?,
    val targetLoad: Double?,
    val reserveNow: Int?,
    val prevReserve: Int?,
    val bbWake: Int?,
    val dayHighReserve: Int?,
    val liveSession: Boolean,
    val reserveFresh: Boolean,

    val hasNightCharge: Boolean,
    val hasConfirmedMeal: Boolean,
    val weekRolled: Boolean,
    val priorWeekValidDays: Int,
    val appOpenedAfterComplete: Boolean,

    val bandBound: Boolean,
    val bandConnected: Boolean,
    val bandCharging: Boolean,
    val bandPercent: Int?,
    val bandBars: Int?,
    val disconnectStarted: Instant?,
)

sealed class MorningNotifyPlan {
    data class Skip(val reason: String) : MorningNotifyPlan()
    data class FireAt(val at: Instant) : MorningNotifyPlan()
}

object NotificationReachMath {
    const val morningHour = 7
    const val morningMinute = 0
    const val quietStartMinutes = 22 * 60 + 30
    const val quietEndMinutes = 7 * 60
    const val window: Double = 6.0 * 3600
    const val away: Double = 4.0 * 3600
    val morningRequestId = NotifyKind.morning.requestId
    const val budget = 4
    const val reserveLine = 35
    const val reserveBelowMorning = 15
    const val bandPercentLine = 15
    const val bandBarsLine = 1
    const val trainingReserveFraction = 0.6
    const val dailyNeed = 2

    fun wakePeak(dayStart: Instant, curve: List<Pair<Instant, Int>>): Instant? {
        val noon = BandTime.adding(dayStart, 8.0 * 3600)
        return curve.filter { it.first < noon }.maxByOrNull { it.second }?.first
    }

    fun isQuiet(date: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        val z = date.atZone(zone)
        val hm = z.hour * 60 + z.minute
        return hm >= quietStartMinutes || hm < quietEndMinutes
    }

    fun sevenAM(day: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant =
        day.atZone(zone).toLocalDate().atTime(morningHour, morningMinute, 0).atZone(zone).toInstant()

    fun quietEnd(after: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant {
        val seven = sevenAM(after, zone)
        return if (after < seven) seven else BandTime.addingDays(seven, 1, zone)
    }

    fun swallows(kind: NotifyKind, page: NotifyPage): Boolean = when {
        (kind == NotifyKind.morning || kind == NotifyKind.reserve) && page == NotifyPage.bodyBattery -> true
        kind == NotifyKind.meal && page == NotifyPage.fuel -> true
        kind == NotifyKind.training && page == NotifyPage.training -> true
        (kind == NotifyKind.bandBattery || kind == NotifyKind.bandAway) && page == NotifyPage.device -> true
        else -> false
    }

    fun nextMealSlot(s: NotifySnapshot): String? {
        if (s.breakfastConfirmed && !s.lunchConfirmed) return "lunch"
        if (s.lunchConfirmed && !s.dinnerConfirmed) return "dinner"
        if (!s.breakfastConfirmed && !s.lunchConfirmed && !s.dinnerConfirmed) return "breakfast"
        if (s.breakfastConfirmed && s.lunchConfirmed && !s.dinnerConfirmed) return "dinner"
        return null
    }

    private data class Cand(val kind: NotifyKind, val at: Instant, val mealSlot: String?, val weekly: Boolean)

    /** ADR 0019 · one edge, or nothing. Clock times are only the quiet gate. */
    fun decide(s: NotifySnapshot, zone: ZoneId = ZoneId.systemDefault()): NotifyPlan {
        if (s.deliveredCount >= budget) return NotifyPlan.Skip
        val cands = mutableListOf<Cand>()

        val wakePeak = s.wakePeak
        if (s.morningOn && NotifyKind.morning !in s.delivered && wakePeak != null && !s.morningShown) {
            val deadline = BandTime.adding(wakePeak, window)
            if (s.now <= deadline) cands += Cand(NotifyKind.morning, s.now, null, false)
        }

        if (s.mealsOn && NotifyKind.meal !in s.delivered && !s.daySealed && s.mealsInLast7Days >= 1 && s.moved) {
            nextMealSlot(s)?.let { slot -> cands += Cand(NotifyKind.meal, s.now, slot, false) }
        }

        val load = s.trainingLoad
        val target = s.targetLoad
        val nowRT = s.reserveNow
        if (s.trainingOn && NotifyKind.training !in s.delivered && !s.liveSession &&
            load != null && target != null && load < target && s.reserveFresh && nowRT != null) {
            val wake = s.bbWake ?: s.dayHighReserve
            if (wake != null) {
                val line = Math.floor(wake.toDouble() * trainingReserveFraction).toInt()
                val high = maxOf(s.dayHighReserve ?: nowRT, s.prevReserve ?: nowRT)
                val prev = s.prevReserve
                val crossed = nowRT <= line && high > line && (prev == null || prev > line)
                if (crossed && nowRT < wake) cands += Cand(NotifyKind.training, s.now, null, false)
            }
        }

        if (s.wrapOn && NotifyKind.daily !in s.delivered && !s.appOpenedAfterComplete) {
            var n = 0
            if (s.hasNightCharge) n += 1
            if (s.trainingLoad != null) n += 1
            if (s.hasConfirmedMeal) n += 1
            if (s.reserveNow != null && s.reserveFresh) n += 1
            if (n >= dailyNeed) {
                val weekly = s.weekRolled && s.priorWeekValidDays >= 4
                cands += Cand(NotifyKind.daily, s.now, null, weekly)
            }
        }

        val nowR = s.reserveNow
        val bbWake = s.bbWake
        if (s.energyOn && NotifyKind.reserve !in s.delivered && s.reserveFresh && nowR != null &&
            bbWake != null && nowR <= reserveLine && bbWake - nowR >= reserveBelowMorning) {
            val prev = s.prevReserve
            val already = prev != null && prev <= reserveLine && bbWake - prev >= reserveBelowMorning
            if (!already) cands += Cand(NotifyKind.reserve, s.now, null, false)
        }

        val bandUsed = NotifyKind.bandBattery in s.delivered || NotifyKind.bandAway in s.delivered
        if (s.bandOn && s.bandBound && !bandUsed && !s.bandCharging) {
            val p = s.bandPercent
            val bars = s.bandBars
            val low = when {
                p != null -> p <= bandPercentLine
                bars != null -> bars <= bandBarsLine
                else -> false
            }
            if (low) cands += Cand(NotifyKind.bandBattery, s.now, null, false)
        }

        val start = s.disconnectStarted
        if (s.bandOn && s.bandBound && !s.bandConnected && !bandUsed && start != null) {
            cands += Cand(NotifyKind.bandAway, BandTime.adding(start, away), null, false)
        }

        cands.removeAll { swallows(it.kind, s.page) }
        val ready = cands.filter { it.at <= s.now }.sortedBy { it.kind.priority }
        val pending = cands.filter { it.at > s.now }.sortedWith(compareBy<Cand> { it.at }.thenBy { it.kind.priority })
        val pick = ready.firstOrNull() ?: pending.firstOrNull() ?: return NotifyPlan.Skip

        var whenAt = pick.at
        if (s.quietEnabled && (isQuiet(whenAt, zone) || isQuiet(s.now, zone)) && whenAt <= s.now) {
            whenAt = maxOf(whenAt, quietEnd(s.now, zone))
        } else if (s.quietEnabled && isQuiet(whenAt, zone) && whenAt > s.now) {
            whenAt = maxOf(whenAt, quietEnd(whenAt, zone))
        }

        if (whenAt > s.now) return NotifyPlan.Later(pick.kind, whenAt, pick.mealSlot, pick.weekly)
        return NotifyPlan.Fire(pick.kind, pick.mealSlot, pick.weekly)
    }

    /** Disconnect clock. Callers may schedule this even when another edge fires now. */
    fun awayFireAt(s: NotifySnapshot): Instant? {
        val bandUsed = NotifyKind.bandBattery in s.delivered || NotifyKind.bandAway in s.delivered
        val start = s.disconnectStarted
        if (!s.bandOn || !s.bandBound || s.bandConnected || bandUsed || start == null) return null
        return BandTime.adding(start, away)
    }

    /** Kept for the 昨夜 window / quiet helpers the panel still shares. */
    fun planMorning(
        now: Instant,
        wakePeak: Instant?,
        alreadyShown: Boolean,
        morningEnabled: Boolean,
        quietEnabled: Boolean,
        zone: ZoneId = ZoneId.systemDefault(),
    ): MorningNotifyPlan {
        val snap = NotifySnapshot(
            now = now, quietEnabled = quietEnabled, deliveredCount = 0, delivered = emptySet(),
            page = NotifyPage.other, morningOn = morningEnabled, trainingOn = false, mealsOn = false,
            wrapOn = false, energyOn = false, bandOn = false, wakePeak = wakePeak,
            morningShown = alreadyShown, daySealed = false, mealsInLast7Days = 0,
            breakfastConfirmed = false, lunchConfirmed = false, dinnerConfirmed = false,
            moved = false, trainingLoad = null, targetLoad = null, reserveNow = null,
            prevReserve = null, bbWake = null, dayHighReserve = null, liveSession = false,
            reserveFresh = false, hasNightCharge = false, hasConfirmedMeal = false,
            weekRolled = false, priorWeekValidDays = 0, appOpenedAfterComplete = false,
            bandBound = false, bandConnected = true, bandCharging = false,
            bandPercent = null, bandBars = null, disconnectStarted = null)
        return when (val plan = decide(snap, zone)) {
            NotifyPlan.Skip -> when {
                alreadyShown -> MorningNotifyPlan.Skip("ALREADY_SHOWN")
                wakePeak == null -> MorningNotifyPlan.Skip("NO_NIGHT")
                !morningEnabled -> MorningNotifyPlan.Skip("OFF")
                else -> MorningNotifyPlan.Skip("PAST_WINDOW")
            }
            is NotifyPlan.Later -> MorningNotifyPlan.FireAt(plan.at)
            is NotifyPlan.Fire -> MorningNotifyPlan.FireAt(now)
        }
    }
}
