package com.nextbody.hoop.band

import java.time.Instant

/** Per-session, transport-independent metrics. The adapter must normalize native energy
 *  into kcal before calling this type; native reports are cumulative, never increments. */
class SportMetricAccumulator private constructor(
    val heartRate: Int?,
    val heartRateAt: Instant?,
    val kcal: Double,
    val calorieSource: CalorieSource,
    /** An authoritative downward correction is explicit, including estimate-to-band zero.
     *  Cleared on the next report; callers can announce or log the source correction. */
    val calorieCorrection: CalorieCorrection?,
    /** Seconds covered by adjacent, valid reports in the current estimate. This is
     *  evidence coverage, not the session clock. */
    val estimatedSeconds: Double,
    val sampleCount: Int,
    val peakHR: Int?,
    private val heartRateSum: Int,
    private val integrationAt: Instant?,
    private val integrationRate: Double?,
    private val profile: EnergyProfile?,
    private val strengthMet: Double?,
    private val heartRateModel: Boolean,
    private val lastReportAt: Instant?,
) {
    enum class CalorieSource { estimate, band }
    data class CalorieCorrection(val previousKcal: Double, val replacementKcal: Double)

    constructor(weightKg: Double?, age: Int?, male: Boolean, sportMode: Int? = null) : this(
        heartRate = null, heartRateAt = null, kcal = 0.0, calorieSource = CalorieSource.estimate,
        calorieCorrection = null, estimatedSeconds = 0.0,
        sampleCount = 0, peakHR = null, heartRateSum = 0,
        integrationAt = null, integrationRate = null,
        profile = EnergyProfile.make(weightKg, age, male),
        strengthMet = strengthMET(sportMode),
        heartRateModel = sportMode?.let { it in listOf(1, 2, 3, 4, 7, 8, 45) } ?: false,
        lastReportAt = null)

    val averageHR: Int? get() = if (sampleCount == 0) null else heartRateSum / sampleCount
    val estimationAvailable: Boolean
        get() = if (strengthMet == null) heartRateModel && profile?.supportsHeartRate == true else profile != null
    /** A complete profile only makes an estimate possible. A number becomes
     *  publishable after a valid interval, or after an authoritative native report. */
    val hasEnergyEvidence: Boolean get() = calorieSource == CalorieSource.band || estimatedSeconds > 0

    fun liveHR(at: Instant): Int? {
        val heartRateAt = heartRateAt ?: return null
        val age = BandTime.interval(at, heartRateAt)
        return if (age >= 0 && age < liveWindow) heartRate else null
    }

    fun accepting(report: SportLiveInfo): SportMetricAccumulator =
        accepting(report.receivedAt, report.heartRate, report.caloriesKcal, report.runState)

    fun canAccept(at: Instant): Boolean = lastReportAt?.let { at > it } ?: true

    /** null runState is the heart-test fallback. Explicit paused/stopped/unknown states
     *  cannot establish contact or contribute HR samples. Never clamp a raw sentinel
     *  into the valid byte range, or smooth a real abrupt heart-rate change. */
    fun accepting(timestamp: Instant, heartRate: Int?, caloriesKcal: Double?, runState: Int?): SportMetricAccumulator {
        if (!canAccept(timestamp)) return this
        val running = runState == null || runState == 1
        val beat = if (running) heartRate?.takeIf { it in 1..255 } else null
        val native = caloriesKcal?.takeIf { it.isFinite() && it >= 0 }
        val source = if (native == null) calorieSource else CalorieSource.band
        val rate: Double? = when {
            source != CalorieSource.estimate -> null
            // Strength evidence requires an explicit band running state. A fallback
            // heart callback may still be displayed, but it cannot prove duration.
            strengthMet != null -> if (runState == 1) profile?.netKcalPerMinute(strengthMet) else null
            heartRateModel -> beat?.let { profile?.kcalPerMinute(it) }
            else -> null
        }
        val elapsed = integrationAt?.let { BandTime.interval(timestamp, it) }
        val estimate: Pair<Double, Double> =
            if (source == CalorieSource.estimate) integrated(rate, elapsed) else 0.0 to 0.0
        val total = native ?: (kcal + estimate.first)
        val correction = if (total < kcal) CalorieCorrection(previousKcal = kcal, replacementKcal = total) else null
        val baselineAllowed = rate != null && (elapsed?.let { it >= 0 } ?: true)
        return SportMetricAccumulator(
            heartRate = beat, heartRateAt = if (beat == null) null else timestamp,
            kcal = total, calorieSource = source, calorieCorrection = correction,
            estimatedSeconds = estimatedSeconds + estimate.second,
            sampleCount = sampleCount + (if (beat == null) 0 else 1),
            peakHR = beat?.let { maxOf(peakHR ?: it, it) } ?: peakHR,
            heartRateSum = heartRateSum + (beat ?: 0),
            integrationAt = if (baselineAllowed) timestamp else null,
            integrationRate = if (baselineAllowed) rate else null, profile = profile,
            strengthMet = strengthMet, heartRateModel = heartRateModel,
            lastReportAt = timestamp)
    }

    /** A disconnect, stream replacement or loss of contact cannot bridge an energy interval.
     *  Totals and accepted sample statistics survive interruptions within this session. */
    fun interrupted(): SportMetricAccumulator = SportMetricAccumulator(
        heartRate = null, heartRateAt = null, kcal = kcal, calorieSource = calorieSource,
        calorieCorrection = null, estimatedSeconds = estimatedSeconds,
        sampleCount = sampleCount, peakHR = peakHR, heartRateSum = heartRateSum,
        integrationAt = null, integrationRate = null, profile = profile,
        strengthMet = strengthMet, heartRateModel = heartRateModel,
        lastReportAt = lastReportAt)

    private fun integrated(rate: Double?, elapsed: Double?): Pair<Double, Double> {
        val previous = integrationRate
        if (rate == null || previous == null || elapsed == null || elapsed <= 0 || elapsed > liveWindow) return 0.0 to 0.0
        val result = (previous / 2 + rate / 2) * elapsed / 60
        return if (result.isFinite() && result >= 0 && (kcal + result).isFinite()) result to elapsed else 0.0 to 0.0
    }

    override fun equals(other: Any?): Boolean {
        if (other !is SportMetricAccumulator) return false
        return heartRate == other.heartRate && heartRateAt == other.heartRateAt && kcal == other.kcal &&
            calorieSource == other.calorieSource && calorieCorrection == other.calorieCorrection &&
            estimatedSeconds == other.estimatedSeconds && sampleCount == other.sampleCount &&
            peakHR == other.peakHR && heartRateSum == other.heartRateSum &&
            integrationAt == other.integrationAt && integrationRate == other.integrationRate &&
            profile == other.profile && strengthMet == other.strengthMet &&
            heartRateModel == other.heartRateModel && lastReportAt == other.lastReportAt
    }

    override fun hashCode(): Int = listOf(heartRate, kcal, sampleCount, lastReportAt).hashCode()

    private data class EnergyProfile(val weightKg: Double, val age: Int?, val male: Boolean) {
        val supportsHeartRate: Boolean
            get() = age?.let { it in 18..45 } == true && weightKg in 47.0..120.0

        /** Existing Keytel estimate; it is used only while native energy is unavailable. */
        fun kcalPerMinute(heartRate: Int): Double? {
            val age = age
            if (!supportsHeartRate || age == null || heartRate !in 90..150) return null
            val h = heartRate.toDouble(); val a = age.toDouble()
            val kj = if (male) -55.0969 + 0.6309 * h + 0.1988 * weightKg + 0.2017 * a
            else -20.4022 + 0.4472 * h - 0.1263 * weightKg + 0.0740 * a
            val rate = kj / 4.184 - 3.5 * weightKg / 200
            return if (rate.isFinite() && rate > 0) rate else null
        }

        /** Net activity energy, excluding the standard 1 MET already represented
         *  by the daily resting-energy component. */
        fun netKcalPerMinute(met: Double): Double? {
            val rate = maxOf(0.0, met - 1) * 3.5 * weightKg / 200
            return if (rate.isFinite()) rate else null
        }

        companion object {
            fun make(weightKg: Double?, age: Int?, male: Boolean): EnergyProfile? {
                if (weightKg == null || !weightKg.isFinite() || weightKg <= 0) return null
                return EnergyProfile(weightKg, age?.takeIf { it > 0 }, male)
            }
        }
    }

    companion object {
        const val liveWindow: Double = 15.0

        /** Conservative session-average MET values from the 2024 Adult Compendium.
         *  These modes are explicit strength activities in the SDK catalog. Ambiguous
         *  modes such as Fitness/Common remain on the existing heart-rate path. */
        fun strengthMET(sportMode: Int?): Double? = when (sportMode) {
            25, 47 -> 3.5 // weightlifting / dumbbell, general multi-exercise
            29 -> 5.0     // squat training, slow or explosive effort
            46 -> 3.0     // body-weight resistance, general
            else -> null
        }
    }
}
