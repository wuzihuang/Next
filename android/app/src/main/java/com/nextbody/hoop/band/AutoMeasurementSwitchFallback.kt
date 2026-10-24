package com.nextbody.hoop.band

/** How Veepoo encodes automatic-measurement on firmware that does **not** expose
 *  `veepooSDKReadAutoMonitSwitchInfo` (`autoMonitSwitchType == 0`).
 *
 *  `VPPeripheralModel.deviceSwitchData` / `deviceSwitchTwoData` are 20-byte blobs.
 *  Bytes 0..<2 are the header; from index 2 the vendor documents each flag as
 *  0 = absent, 1 = on, 2 = off. Blood oxygen is a pair of dedicated fields, not a
 *  byte in those blobs. */
object AutoMeasurementSwitchFallback {
    enum class Kind(val raw: String) {
        heartRate("heartRate"), bloodPressure("bloodPressure"), bloodGlucose("bloodGlucose"), stress("stress"),
        bloodOxygen("bloodOxygen"), temperature("temperature"), hrv("hrv"), scientificSleep("scientificSleep"),
        bloodComponents("bloodComponents"),
    }

    data class Reading(val kind: Kind, val on: Boolean)

    /** Enough bytes to trust the local tables instead of probing over BLE. */
    fun hasSwitchTables(switchData: List<Int>, switchTwoData: List<Int>): Boolean =
        switchData.size >= 13 || switchTwoData.size >= 12

    fun readings(switchData: List<Int>, switchTwoData: List<Int>, oxygenSupported: Boolean, oxygenOn: Boolean): List<Reading> {
        val out = mutableListOf<Reading>()
        flag(switchData, 4)?.let { out.add(Reading(Kind.heartRate, it)) }
        flag(switchData, 5)?.let { out.add(Reading(Kind.bloodPressure, it)) }
        flag(switchData, 12)?.let { out.add(Reading(Kind.hrv, it)) }
        // VPSettingAutomaticPPGTest. The SDK documents this as the real controller for
        // scientific sleep; VPSettingAccurateSleep itself is currently ineffective.
        flag(switchData, 16)?.let { out.add(Reading(Kind.scientificSleep, it)) }
        if (oxygenSupported) out.add(Reading(Kind.bloodOxygen, oxygenOn))
        flag(switchTwoData, 4)?.let { out.add(Reading(Kind.temperature, it)) }
        flag(switchTwoData, 7)?.let { out.add(Reading(Kind.bloodGlucose, it)) }
        flag(switchTwoData, 9)?.let { out.add(Reading(Kind.stress, it)) }
        flag(switchTwoData, 11)?.let { out.add(Reading(Kind.bloodComponents, it)) }
        return out
    }

    /** 0 = this firmware has no such switch. 1 = on. 2 = off. Anything else is ignored. */
    private fun flag(data: List<Int>, index: Int): Boolean? {
        if (data.size <= index) return null
        return when (data[index] and 0xFF) {
            1 -> true
            2 -> false
            else -> null
        }
    }
}
