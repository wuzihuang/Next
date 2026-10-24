package com.nextbody.hoop.features.home

import com.nextbody.hoop.features.home.panel.PanelData
import com.nextbody.hoop.features.home.panel.PanelTag
import com.nextbody.hoop.features.home.panel.PanelType
import com.nextbody.hoop.features.home.panel.PanelWidget
import com.nextbody.hoop.app.DebugLaunch
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.BodyBattery
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.services.SupabaseClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * 13 col 01 · 昨夜 · ONE WIDGET · ONCE A DAY · WAKE + 6H.
 *
 * The one thing the night is allowed to say, said once. Rule 09: shown at most once per
 * 04:00 day, stamped `bb_morning_shown_at` on the day row. Not rendered at all without a
 * night on the band (edge 1) — the panel simply stays in standby.
 */
object MorningWidget {
    const val shownKey = "nb.bb.morningShownDay"

    /** DEBUG only · `NB_DEBUG_NOW=2026-09-01T08:30:00Z` pretends it is that morning. */
    val debugNow: Instant?
        get() {
            if (!Band.allowsSeed) return null
            return DebugLaunch["NB_DEBUG_NOW"]?.let { runCatching { Instant.parse(it) }.getOrNull() }
        }

    fun frame(today: DailyMetrics, history: List<DailyMetrics>, now: Instant? = null,
              ignoreShown: Boolean = false): PanelWidget? {
        @Suppress("UNUSED_VARIABLE") val unusedHistory = history
        val m = today
        val clock = now ?: debugNow ?: Instant.now()
        val pinMorning = Band.allowsSeed && DebugLaunch["NB_DEBUG_MORNING"] == "1"
        if (!pinMorning && !ConsentStore.granted) return suppress("NO_CONSENT")
        val wake = m.bbWake
        val wakeAt = m.bodyBatteryWakeAt
        val drivers = m.reserveDrivers
        val nightCharge = drivers?.nightCharge
        if (wake == null || wakeAt == null || drivers == null || nightCharge == null) return suppress("NO_NIGHT")
        if (!pinMorning && !ignoreShown && Defaults.getString(shownKey) == m.day.key) {
            return suppress("ALREADY_SHOWN")
        }
        if (!pinMorning) {
            if (clock < wakeAt || clock > wakeAt.plusSeconds(6 * 3600)) return suppress("PAST_WINDOW")
        }

        val title: String
        val sentence: String
        if (drivers.assumedAnchor) {
            title = L("ESTIMATED START")
            sentence = L("The starting readiness was estimated because earlier readings were missing. Later readings still carry that uncertainty.")
        } else {
            title = L("MORNING READINESS · %@", Fmt.clock(wakeAt))
            sentence = L("%@ recovered overnight.", Fmt.signed(nightCharge))
        }
        val footer = BodyBattery.overnightLine(delta = nightCharge, morning = wake)
        return PanelWidget(
            type = PanelType.line, title = title, tag = PanelTag.recover, sentence = sentence,
            footer = footer, action = L("TAP TO SEE WHY"), hero = "$wake",
            accentOverride = NB.lime1,
            targetOverride = Destination.BodyBattery,
            data = PanelData.Series(m.reserveCurve.map { it.value.toDouble() }),
            ttlMinutes = 60,
        )
    }

    /** Rule 09 · the stamp goes to the phone and to the cloud. */
    suspend fun markShown(day: UserDay, widget: PanelWidget) {
        Defaults.putString(shownKey, day.key)
        val iso = Instant.now().toString()
        runCatching {
            SupabaseClient.patchWhere("daily_results", column = "user_day", equals = day.key,
                row = mapOf("bb_morning_shown_at" to iso))
        }
        Analytics.track("READINESS_MORNING_SHOWN", mapOf(
            "SCORE" to (widget.hero ?: ""), "DELTA" to (widget.footer ?: ""),
            "TIER" to BodyBattery.tierWord(widget.hero?.toIntOrNull() ?: 0),
        ))
    }

    private fun suppress(reason: String): PanelWidget? {
        if (Band.allowsSeed) android.util.Log.d("NB", "MorningWidget suppressed: $reason")
        CoroutineScope(Dispatchers.Default).launch { Analytics.track("BB_MORNING_SUPPRESSED", mapOf("REASON" to reason)) }
        return null
    }
}
