package com.nextbody.hoop.band

/** Last known state of the wrist optical auto-measure switch. Page two never asks the
 *  band; it only prints SWITCH OFF when a previous Device read already saw the slot off. */
object OpticalAutoSwitch {
    private const val key = "nb.optical.auto.on"

    val isOff: Boolean
        get() {
            val stored = BandPrefs.bool(key) ?: return false
            return !stored
        }

    fun record(on: Boolean) = BandPrefs.setBool(key, on)
}
