package com.nextbody.hoop.band

import com.nextbody.hoop.app.MeasureKind
import com.nextbody.hoop.model.SleepInterval
import java.time.Instant

// Value types from Services/Band/BandService.swift that the data layer reads. The BLE
// service itself (the `BandService` interface, VeepooBand, MockBand…) lives in BandService.kt.

data class DiscoveredBand(
    /** ⚠️ On iOS this is a CoreBluetooth UUID, on Android the BLE address. It is never a
     *  cross-platform device identity. */
    val id: String,
    val name: String,
    val rssi: Int,
    val batteryPercent: Int?,
)

data class BandIdentity(
    val name: String,
    val model: String,
    val hardware: String,
    val firmware: String,
    /** DeviceVersion.deviceNumber. ⚠️ The SDK has no serial number, and nothing in the
     *  product may call this one an SN. */
    val deviceNumber: String,
    val bleIdentifier: String,
    /** How many days of history the band still holds. Missing days are drawn empty,
     *  never as 0, and never averaged. */
    val watchDataDayNumber: Int,
    /** The band's own sport-mode tier: NONE, SINGLE, or "10 TYPES (…)". The SDK has no
     *  way to ask WHICH sports a firmware carries — the band's own workout list does. */
    val sportMode: String,
)

/** FunctionStatus values are carried through verbatim. On screen `unknown` and `unsupported`
 *  both mean the row is not drawn — but when something is broken they are two different facts. */
enum class FunctionStatus(val raw: String) {
    support("support"), unsupported("unsupported"), `open`("open"), close("close"), unknown("unknown");

    companion object {
        fun fromRaw(raw: String): FunctionStatus? = entries.firstOrNull { it.raw == raw }
        fun from(raw: String): FunctionStatus? = fromRaw(raw)
    }
}

data class BandCapabilities(
    val functions: Map<String, FunctionStatus> = emptyMap(),
    val bodyComponent: FunctionStatus = FunctionStatus.unknown,
    val ecg: FunctionStatus = FunctionStatus.unknown,
    val hrv: FunctionStatus = FunctionStatus.unknown,
    val stress: FunctionStatus = FunctionStatus.unknown,
    val autoMeasure: FunctionStatus = FunctionStatus.unknown,
    /** ⚠️ Android has no read command for wearDetection. V1 is iOS only, so this is
     *  readable here — the Android note stays in the boards, marked for later. */
    val wearDetection: FunctionStatus = FunctionStatus.unknown,
) {
    /** F6 §05 · an unsupported row is not drawn at all — 「加号单子少一行，好过让人惦记一件这台
     *  机器做不到的事」. This is deliberately not `!supports(kind)`: `unknown` is not
     *  `unsupported`, and before the band has answered its capability read the menu would empty
     *  itself on every cold start and fill back in a second later. Only a definite no hides a row. */
    fun knownUnsupported(kind: MeasureKind): Boolean {
        fun no(s: FunctionStatus?): Boolean = s == FunctionStatus.unsupported
        return when (kind) {
            MeasureKind.heartRate -> no(hrv) && no(functions["heart"] ?: FunctionStatus.unknown)
            MeasureKind.bodyComposition -> no(bodyComponent)
            MeasureKind.bloodOxygen -> no(functions["spo2"] ?: FunctionStatus.unknown)
            MeasureKind.bloodPressure -> no(functions["blood"] ?: FunctionStatus.unknown)
            MeasureKind.ecg -> no(ecg)
            MeasureKind.temperature -> no(functions["temperature"] ?: FunctionStatus.unknown)
        }
    }

    fun supports(kind: MeasureKind): Boolean = when (kind) {
        MeasureKind.heartRate -> hrv == FunctionStatus.support || functions["heart"] == FunctionStatus.support ||
            hrv == FunctionStatus.`open`
        MeasureKind.bodyComposition -> bodyComponent == FunctionStatus.support
        MeasureKind.bloodOxygen -> functions["spo2"] == FunctionStatus.support
        MeasureKind.bloodPressure -> functions["blood"] == FunctionStatus.support
        MeasureKind.ecg -> ecg == FunctionStatus.support
        MeasureKind.temperature -> functions["temperature"] == FunctionStatus.support
    }
}

/**
 * ⚠️ Three values together: firmware with isPercent = false only reports 0–4 bars, and
 * collapsing them loses the difference between "82%" and "4 bars" forever.
 */
data class BandBattery(
    val isPercent: Boolean,
    val percent: Int?,
    val level: Int?,
    val chargeState: ChargeState,
) {
    enum class ChargeState(val raw: String) {
        unplugged("unplugged"), charging("charging"), full("full"), unknown("unknown");

        companion object {
            fun fromRaw(raw: String): ChargeState? = entries.firstOrNull { it.raw == raw }
            fun from(raw: String): ChargeState? = fromRaw(raw)
        }
    }

    /** Firmware often stays on `.charging` after the pack is already full. */
    val settled: BandBattery
        get() {
            val charge = BatteryDrainMath.settle(
                BatteryObservation.Charge.fromRaw(chargeState.raw) ?: BatteryObservation.Charge.unknown,
                isPercent, percent, level)
            val next = ChargeState.fromRaw(charge.raw) ?: chargeState
            if (next == chargeState) return this
            return BandBattery(isPercent, percent, level, next)
        }

    /** What the ring can draw. A bar count is not a percentage and is never shown as one. */
    val ringFraction: Double?
        get() {
            if (isPercent && percent != null) return percent.toDouble() / 100
            if (level != null) return level.toDouble() / 4
            return null
        }
}

/**
 * 04B rule 04 · one run of the band's own sleepLine: a stage and how many minutes it held.
 * Stages are the SDK's (VPAccurateSleepModel): 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake —
 * KH firmware emits no 2 or 3.
 */
data class SleepStageRun(
    val stage: Int,
    val minutes: Int,
    /** Offset from the first recorded sleep start; absent in older stored curves. */
    val offsetMinutes: Int? = null,
)

data class SleepNight(
    val totalMinutes: Int,
    val deepMinutes: Int,
    val lightMinutes: Int,
    val wakeCount: Int,
    /** 04B rule 04 · the night's sleepLine compressed into runs, in the order the night ran.
     *  Empty when the band answered without a curve — the strip falls back to proportions. */
    val line: List<SleepStageRun> = emptyList(),
    /** When the night began and ended, from the band's own record. The server's night
     *  resting heart rate is the 5th percentile of the ticks between them — raw_samples
     *  carries no sleep flag on this SDK, so without these two the number cannot exist. */
    val sleepStart: Instant? = null,
    val wakeAt: Instant? = null,
    val intervals: List<SleepInterval>? = null,
)
