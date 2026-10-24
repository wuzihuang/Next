package com.nextbody.hoop.band

import java.time.Instant

/**
 * One timestamped row of measurements copied from the band.
 *
 * Every value is optional because a missing sensor reading is not zero. The model lives in
 * SyncCore so the BLE upload path and the UI curve use one merge rule.
 *
 * Port note: the constructor is private so every instance goes through the normalising
 * initialiser (`VitalSample(...)` resolves to the companion's `invoke`), exactly as Swift's
 * custom `init` did. JSON key for `vendorCalories` is `cal`.
 */
@ConsistentCopyVisibility
data class VitalSample private constructor(
    val ts: Instant,
    val hr: Int?,
    val stress: Int?,
    val temp: Double?,
    val steps: Int?,
    /** Original five-minute MET; preferred over cadence estimates for energy. */
    val met: Double?,
    /** Vendor original-data calorie counter. Veepoo documents this as `cal`, not kcal, and
     *  it includes the vendor's basal component. Archive it for evidence; never sum or show it. */
    val vendorCalories: Double?,
    val dis: Double?,
    val hrv: Double?,
    /** Explicit RR evidence can revoke an older HRV value; an absent reading cannot. */
    val hrvValid: Boolean?,
    val hrvObservedAt: Instant?,
) {
    val hasReading: Boolean
        get() = hr != null || stress != null || temp != null || steps != null ||
            met != null || vendorCalories != null || dis != null || hrv != null

    companion object {
        operator fun invoke(
            ts: Instant, hr: Int?, stress: Int?, temp: Double? = null, steps: Int? = null,
            met: Double? = null, vendorCalories: Double? = null, dis: Double? = null, hrv: Double? = null,
            hrvValid: Boolean? = null, hrvObservedAt: Instant? = null,
        ): VitalSample = of(ts, hr, stress, temp, steps, met, vendorCalories, dis, hrv, hrvValid, hrvObservedAt)

        private fun of(
            ts: Instant, hr: Int?, stress: Int?, temp: Double?, steps: Int?,
            met: Double?, vendorCalories: Double?, dis: Double?, hrv: Double?,
            hrvValid: Boolean?, hrvObservedAt: Instant?,
        ): VitalSample = VitalSample(
            ts = ts,
            hr = hr,
            stress = stress,
            temp = temp,
            steps = steps,
            met = validatedMET(met),
            vendorCalories = vendorCalories,
            dis = dis,
            hrv = if (hrvValid == false) null else hrv,
            hrvValid = if (hrvValid == true && hrv == null) null else hrvValid,
            hrvObservedAt = hrvObservedAt,
        )

        /** Match the ingestion payload range. Invalid readings are missing, never zero load. */
        fun validatedMET(value: Double?): Double? =
            value?.let { if (!it.isNaN() && !it.isInfinite() && it in 0.0..100.0) it else null }

        /**
         * Merge freshly read band points into a stored curve without erasing auxiliary fields
         * that arrived from a different SDK stream. HRV carries its observation clock so a
         * stale read cannot undo a later correction; other fresh non-nil values win per tick.
         */
        fun merging(stored: List<VitalSample>, fresh: List<VitalSample>): List<VitalSample> {
            val samplesByTimestamp = HashMap<Instant, VitalSample>()

            for (raw in stored + fresh) {
                val sample = raw.copy(met = validatedMET(raw.met))
                val current = samplesByTimestamp[sample.ts]
                if (current == null) {
                    samplesByTimestamp[sample.ts] = sample
                    continue
                }
                val hasHRVEvidence = sample.hrv != null || sample.hrvValid == false
                val currentClock = current.hrvObservedAt
                val acceptsHRV = hasHRVEvidence && (currentClock == null ||
                    (sample.hrvObservedAt?.let { it > currentClock } ?: false))
                samplesByTimestamp[sample.ts] = of(
                    ts = sample.ts,
                    hr = sample.hr ?: current.hr,
                    stress = sample.stress ?: current.stress,
                    temp = sample.temp ?: current.temp,
                    steps = sample.steps ?: current.steps,
                    met = sample.met ?: current.met,
                    vendorCalories = sample.vendorCalories ?: current.vendorCalories,
                    dis = sample.dis ?: current.dis,
                    hrv = if (acceptsHRV) sample.hrv else current.hrv,
                    hrvValid = if (acceptsHRV) sample.hrvValid else current.hrvValid,
                    hrvObservedAt = if (acceptsHRV) sample.hrvObservedAt else current.hrvObservedAt,
                )
            }

            return samplesByTimestamp.values.sortedBy { it.ts }
        }

        /**
         * Issue #19 · the samples a card labelled TODAY may draw: this user day's, from
         * local midnight to now. It used to be a rolling 24 hours, which put last night's
         * evening on this morning's card.
         */
        fun today(samples: List<VitalSample>, endingAt: Instant): List<VitalSample> {
            val window = VitalsTimelinePolicy.today(endingAt)
            return samples.filter { window.contains(it.ts) }
        }
    }
}
