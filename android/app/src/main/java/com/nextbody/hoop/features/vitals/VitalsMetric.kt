package com.nextbody.hoop.features.vitals

import androidx.compose.ui.graphics.Color
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.l10n.L

/**
 * 04 · page-two instruments plus a deep-link alias. Page two shows seven vitals cards
 * plus Body Battery; `.hrv` is kept so `vitals.hrv` still parses, and the router sends
 * it to the sleep page. `.response` still opens the meal-response board via deep link.
 *
 * ⚠️ The tint is the home card's tint, not the board's swatch. A card that turns from lime to
 * cyan as it opens reads as a different object, which is the one thing a tap-through must not do.
 */
enum class VitalsMetric(val raw: String) {
    heart("heart"), sleep("sleep"), hrv("hrv"), response("response"), stress("stress"),
    temp("temp"), steps("steps"), distance("distance"), active("active");

    /** What `DetailScroll` prints — the card's own name, never a `VITALS ·` section prefix. */
    val title: String
        get() = when (this) {
            distance -> L("DISTANCE")
            active -> L("ACTIVE ENERGY")
            else -> L(shortName)
        }

    /** The card's label on page two, which is also the board's nav word. */
    val shortName: String
        get() = when (this) {
            heart -> "HEART"
            sleep -> "SLEEP"
            hrv -> "HRV"
            response -> "RESPONSE"
            stress -> "STRESS"
            temp -> "TEMP"
            steps -> "STEPS"
            distance -> "DIST"
            active -> "CALS"
        }

    /** The key `VitalsPage.cardStates` files this instrument under. */
    val cardKey: String
        get() = when (this) {
            distance -> "DISTANCE"
            active -> "ACTIVE"
            else -> shortName
        }

    val tint: Color
        get() = when (this) {
            heart -> NB.lime1
            sleep -> NB.violet1
            // 偏红 · RMSSD is the pulse's own variability, so it wears a heart colour. The pale
            // rose, not `alert2`: a full alert red reads as a warning about the night.
            hrv -> NB.alert1
            response -> NB.compareAmber
            stress -> NB.ember1
            temp -> NB.cyan1
            steps -> NB.optimal2
            distance -> NB.violetPink
            active -> NB.lime1
        }

    /** The board's hero eyebrow: what the number was measured by, not what it means. */
    val sensor: String
        get() = when (this) {
            heart -> L("OPTICAL PPG SENSOR")
            sleep -> L("OVERNIGHT STAGING")
            hrv -> L("RMSSD AUTONOMIC TONE")
            response -> L("WRIST OPTICAL MEAL RESPONSE")
            stress -> L("PHYSIOLOGICAL STRAIN")
            temp -> L("WRIST SKIN TEMPERATURE")
            steps -> L("DAILY CADENCE ACCUMULATED")
            distance -> L("SPATIAL DISPLACEMENT")
            active -> L("DAILY METABOLIC BURN")
        }

    /** The board's chart-card head. */
    val chartTitle: String
        get() = when (this) {
            heart -> L("TODAY'S TELEMETRY")
            sleep -> L("STAGES HYPNOGRAM")
            hrv -> L("TODAY'S RMSSD SCATTER")
            response -> L("TODAY'S FOOD RESPONSE POINTS")
            stress -> L("TODAY'S AUTONOMIC LOAD")
            temp -> L("TODAY'S SKIN TEMPERATURE")
            steps -> L("TODAY'S CADENCE HISTOGRAM")
            distance -> L("TODAY'S DISTANCE CLIMB")
            active -> L("TODAY'S METABOLIC BURN")
        }

    /** True for the charts whose vertical ruler stands in a rail beside the field. */
    val chartHasScaleRail: Boolean
        get() = when (this) {
            heart, stress, temp, steps, distance -> true
            sleep, hrv, response, active -> false
        }

    /**
     * Issue #19 · one day on every card: local midnight → now. Sleep alone belongs to one
     * completed night and keeps its own clock.
     */
    val timeline: VitalsTimelineKind
        get() = if (this == sleep) VitalsTimelineKind.lastNight else VitalsTimelineKind.userDayToNow

    val periodLabel: String
        get() = when (timeline) {
            VitalsTimelineKind.lastNight -> L("LAST NIGHT")
            VitalsTimelineKind.userDayToNow -> L("TODAY")
        }

    val isNightly: Boolean get() = timeline == VitalsTimelineKind.lastNight

    companion object {
        fun from(raw: String): VitalsMetric? = entries.firstOrNull { it.raw == raw }
    }
}

enum class VitalsTimelineKind {
    lastNight,
    /** Local midnight → now. The only day a card draws (issue #19). */
    userDayToNow,
}
