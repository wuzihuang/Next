package com.nextbody.hoop.band

import com.nextbody.hoop.data.Defaults

/** Raw values follow the SDK's VPHealthLightStatusType wire contract. */
enum class BandHealthLightState(val raw: Int) {
    off(0),
    slowFlash(1),
    continuousFlashing(2),
    stayOn(3);

    val id: Int get() = raw

    val title: String
        get() = when (this) {
            off -> "Off"
            slowFlash -> "Slow flash"
            continuousFlashing -> "Continuous flashing"
            stayOn -> "Stay on"
        }

    companion object {
        fun fromRaw(raw: Int): BandHealthLightState? = entries.firstOrNull { it.raw == raw }

        /** The returned device state is authoritative, even if it differs from the request. */
        @Throws(BandHealthLightError::class)
        fun confirmedState(success: Boolean, rawValue: Int): BandHealthLightState {
            if (!success) throw BandHealthLightError.Rejected
            return fromRaw(rawValue) ?: throw BandHealthLightError.UnknownState
        }
    }
}

sealed class BandHealthLightError(message: String) : Exception(message) {
    object Rejected : BandHealthLightError("The device rejected the health light setting.")
    object UnknownState : BandHealthLightError("The device returned an unknown health light state.")

    val errorDescription: String? get() = message
}

/**
 * The state chosen on the Device page, kept on the phone and written to the band again
 * on every connect (`BandHealthLightKeeper`). `nil` is "never chosen": the firmware's own
 * default stands and the app sends nothing.
 */
object BandHealthLightPreference {
    const val key = "nb.band.healthLight"

    fun stored(): BandHealthLightState? {
        if (!Defaults.contains(key)) return null
        return BandHealthLightState.fromRaw(Defaults.getInt(key))
    }

    fun store(state: BandHealthLightState?) {
        if (state != null) Defaults.putInt(key, state.raw) else Defaults.remove(key)
    }
}
