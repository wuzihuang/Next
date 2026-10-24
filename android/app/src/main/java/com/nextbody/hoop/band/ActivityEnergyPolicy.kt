package com.nextbody.hoop.band

/**
 * Product boundary between vendor counters and energy that is safe to label as kcal.
 *
 * `raw_samples.cal` is retained as source evidence, but Veepoo documents it as `cal` and
 * its original-data counter includes the vendor's own basal component. It is therefore
 * neither an active-kcal sample nor something that can be summed into an hourly chart.
 */
object ActivityEnergyPolicy {
    @Suppress("UNUSED_PARAMETER")
    fun displayTotal(settledActiveKcal: Double?, archivedVendorCalories: List<Double>): Double? {
        if (settledActiveKcal == null || !settledActiveKcal.isFinite() || settledActiveKcal < 0) return null
        return settledActiveKcal
    }

    @Suppress("UNUSED_PARAMETER")
    fun hourlyBins(count: Int, archivedVendorCalories: List<Double>): List<Double?> =
        List(maxOf(0, count)) { null }
}
