package com.nextbody.hoop.features.vitals

import androidx.compose.ui.graphics.Color
import com.nextbody.hoop.band.SkinTempNightRange
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import java.time.Instant

/** The one place the day and its history are turned into a skin-temperature night range, so
 *  the Home card and the detail page cannot disagree about last night (ADR 0009). */
object SkinTempPresentation {
    fun nightRange(today: DailyMetrics, history: List<DailyMetrics>, now: Instant = Instant.now()): SkinTempNightRange.Result {
        val days = history.toMutableList()
        if (days.lastOrNull()?.day != today.day) days.add(today)

        val curve = VitalSample.merging(days.flatMap { it.vitalsCurve }, today.vitalsCurve)
        val points = curve.mapNotNull { sample -> sample.temp?.let { SkinTempNightRange.Point(sample.ts, it) } }
        // One night per window: a day carried twice in `history` would otherwise weigh twice
        // in the median that judges tonight.
        val seen = HashSet<SkinTempNightRange.Night>()
        val nights = days.mapNotNull { day ->
            val start = day.sleep?.sleepStart ?: return@mapNotNull null
            val wake = day.sleep?.wakeAt ?: return@mapNotNull null
            if (wake <= start) return@mapNotNull null
            val night = SkinTempNightRange.Night(start, wake)
            if (seen.add(night)) night else null
        }
        return SkinTempNightRange.make(points, nights, now)
    }

    /** The badge, in the metric's own colours. */
    fun badge(tier: SkinTempNightRange.Tier): Pair<String, Color> = when (tier) {
        SkinTempNightRange.Tier.within -> L("WITHIN YOUR RANGE") to NB.optimal2
        SkinTempNightRange.Tier.mildAbove -> L("SLIGHTLY ABOVE RANGE") to NB.cyan1
        SkinTempNightRange.Tier.mildBelow -> L("SLIGHTLY BELOW RANGE") to NB.cyan1
        SkinTempNightRange.Tier.wellAbove -> L("WELL ABOVE YOUR RANGE") to NB.ember1
        SkinTempNightRange.Tier.wellBelow -> L("WELL BELOW YOUR RANGE") to NB.blue1
    }

    /** The short form the Home card prints after last night's signed number. */
    fun shortTier(tier: SkinTempNightRange.Tier): String = when (tier) {
        SkinTempNightRange.Tier.within -> L("IN RANGE")
        SkinTempNightRange.Tier.mildAbove, SkinTempNightRange.Tier.wellAbove -> L("ABOVE RANGE")
        SkinTempNightRange.Tier.mildBelow, SkinTempNightRange.Tier.wellBelow -> L("BELOW RANGE")
    }

    /** Why last night carries no verdict, in the words the card prints. */
    fun reason(empty: SkinTempNightRange.Empty, learningNights: Int): String = when (empty) {
        SkinTempNightRange.Empty.noNight -> L("NO NIGHT YET")
        SkinTempNightRange.Empty.nightTooShort -> L("NIGHT TOO SHORT")
        SkinTempNightRange.Empty.tooFewTicks -> L("TOO FEW NIGHT TICKS")
        SkinTempNightRange.Empty.needsFiveNights -> L("LEARNING · %d / 5 NIGHTS", learningNights)
    }

    /** The chart's vertical ruler: the person's own range with room around it, or the plain
     *  wrist window before there is a range. Never the 35.5–37.0 core-temperature ruler. */
    fun axis(range: SkinTempNightRange.Range?, pad: Double): ClosedFloatingPointRange<Double> {
        if (range == null) return 30.0..38.0
        return (range.lower - pad)..(range.upper + pad)
    }
}
