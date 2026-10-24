package com.nextbody.hoop.band

import com.nextbody.hoop.model.instantFromEpochSeconds

// From Services/Band/FuelWindowMath.swift — only the value type `DailyMetrics` stores.
// FuelWindowMath itself is ported by its owner; it must not redeclare this type.

/** Published energy weights, not raw sensor MET. Both components exclude resting. */
data class FuelEnergyPoint(
    val epoch: Double,
    val originWeight: Double,
    val strengthWeight: Double,
) {
    val tick: VitalSample
        get() = VitalSample(ts = instantFromEpochSeconds(epoch), hr = null, stress = null,
            met = 1 + (originWeight + strengthWeight) / 300)
}
