package com.nextbody.hoop.features.measure

import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.rounded
import kotlin.math.max
import kotlin.math.sqrt

/**
 * 06 · THE BALANCE READ. What a pulse study's beat-to-beat intervals say about which half of
 * the autonomic nervous system is doing more of the talking right now.
 *
 * The whole computation is the Poincaré (Lorenz) plot of the interval series: every interval
 * against the one after it. SD1 is the spread ACROSS the identity line (beat-to-beat change,
 * the vagal half); SD2 the spread ALONG it (the slower drift). The split is SD1 / (SD1 + SD2)
 * — a RATIO OF SPREADS, not a measurement of two nerves, and the copy says so.
 *
 * ⚠️ NOT A DIAGNOSIS AND NOT A MEDICAL READING. Nothing here names a condition.
 */
class AutonomicBalance private constructor(
    /** Milliseconds. The mean of the intervals the band reported. */
    val meanInterval: Double,
    /** Beats a minute, from that mean. */
    val beatsPerMinute: Int,
    /** Milliseconds of spread across the identity line — the fast, beat-to-beat half. */
    val sd1: Double,
    /** Milliseconds of spread along it — the slow half. */
    val sd2: Double,
    /** SDNN, the plain standard deviation of the whole series, for the footer. */
    val sdnn: Double,
    /** 0…1 · SD1 / (SD1 + SD2). */
    val parasympatheticShare: Double,
    /** The points of the plot, as (x, y) pairs of consecutive intervals in milliseconds. */
    val points: List<Pair<Double, Double>>,
) {
    val sympatheticShare: Double get() = 1 - parasympatheticShare

    enum class Lead { parasympathetic, sympathetic, even }

    val lead: Lead
        get() {
            // A ten-point margin either side of even. Below that the difference is smaller than
            // what a swallow or a change of posture moves in forty seconds.
            if (parasympatheticShare > 0.55) return Lead.parasympathetic
            if (parasympatheticShare < 0.45) return Lead.sympathetic
            return Lead.even
        }

    // MARK: what it is allowed to say

    /** The headline. Describes the cloud, names no condition. */
    val headline: String
        get() = when (lead) {
            Lead.parasympathetic -> L("Rest is leading.")
            Lead.sympathetic -> L("Drive is leading.")
            Lead.even -> L("Both sides, evenly.")
        }

    /** One sentence under it — never advice, never a finding. */
    val note: String
        get() = when (lead) {
            Lead.parasympathetic ->
                L("Your beat-to-beat spacing kept changing — the pattern a settled body makes. Forty seconds is a snapshot, not a verdict.")
            Lead.sympathetic ->
                L("Your beats came at a steadier spacing, which is what effort, caffeine or a busy head all look like from here.")
            Lead.even ->
                L("Neither half of the pattern is doing much more than the other right now.")
        }

    /** The share as a percentage pair for the two bars. */
    val split: Split
        get() {
            val rest = (parasympatheticShare * 100).rounded().toInt()
            return Split(rest, 100 - rest)
        }

    data class Split(val rest: Int, val drive: Int)

    companion object {
        /** ⚠️ Fewer than this many intervals and there is no cloud to describe. */
        const val minimumIntervals = 12

        /** Null when the band reported too little to describe. Every caller draws the empty
         *  state rather than falling back to something plausible. (Swift `init?(intervals:)`.) */
        operator fun invoke(intervals: List<Double>): AutonomicBalance? {
            // Physiological range: 300 ms is 200 bpm, 2 000 ms is 30 bpm.
            val clean = intervals.filter { it >= 300 && it <= 2000 }
            if (clean.size < minimumIntervals) return null

            val mean = clean.sum() / clean.size
            // Successive differences — the beat-to-beat half.
            val diffs = clean.drop(1).zip(clean).map { (a, b) -> a - b }
            val sdsd = standardDeviation(diffs)
            val sdnnValue = standardDeviation(clean)

            // The standard Poincaré identities.
            val sd1Value = sqrt(0.5 * sdsd * sdsd)
            val sd2Value = sqrt(max(0.0, 2 * sdnnValue * sdnnValue - 0.5 * sdsd * sdsd))

            return AutonomicBalance(
                meanInterval = mean,
                beatsPerMinute = (60_000 / mean).rounded().toInt(),
                sd1 = sd1Value,
                sd2 = sd2Value,
                sdnn = sdnnValue,
                // A metronome-flat run must not divide by zero.
                parasympatheticShare = if (sd1Value + sd2Value > 0) sd1Value / (sd1Value + sd2Value) else 0.5,
                points = clean.dropLast(1).zip(clean.drop(1)),
            )
        }

        private fun standardDeviation(xs: List<Double>): Double {
            if (xs.size <= 1) return 0.0
            val mean = xs.sum() / xs.size
            val variance = xs.fold(0.0) { acc, x -> acc + (x - mean) * (x - mean) } / (xs.size - 1)
            return sqrt(variance)
        }
    }
}
