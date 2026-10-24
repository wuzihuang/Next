package com.nextbody.hoop.band

import com.nextbody.hoop.l10n.L
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withTimeoutOrNull
import java.time.Instant
import java.time.ZoneId

/**
 * What the app needs from a band, and nothing more. Two implementations sit behind it:
 * `MockBand` on the simulator (Android: the emulator / seeded build) and `VeepooBand` on a device.
 * A device build that cannot reach the vendor SDK gets `DisconnectedBand` — idle, invents nothing.
 */
/** Dedicated all-days commands that sit beside the origin dump. */
enum class BandAuxiliaryDomain(val raw: String) {
    hrv("hrv"), oxygen("oxygen"), temperature("temperature")
}

interface BandService {
    val state: BandConnectionState
    val events: Flow<BandEvent>

    suspend fun startScan()
    suspend fun stopScan()
    suspend fun connect(device: DiscoveredBand, progress: (Double) -> Unit)
    /** F1 · A · the gate is walked once. After that the band is bound, and every later launch
     *  reconnects to it on its own — being asked to pair again is how a user learns their
     *  history is gone. */
    suspend fun reconnectIfBound()
    suspend fun reconnectForSport() {
        if (!currentCoroutineContext().isActive) return
        reconnectIfBound()
    }
    suspend fun prepareFreshSync() {}
    suspend fun finishFreshSync() {}
    /** When this connection last finished the dedicated command. Null means it must run. */
    suspend fun auxiliaryCompletedAt(domain: BandAuxiliaryDomain): Instant? = null
    /** Drop one cached dedicated command so the next health read transfers it again. */
    suspend fun invalidateAuxiliary(domain: BandAuxiliaryDomain) {}
    /** ⚠️ The SDK only offers disconnect(). "Forget this NEXTBODY" is the app clearing its own
     *  device id — "factory reset" is not something we can do, and the two must never blur. */
    suspend fun disconnect()

    suspend fun readIdentity(): BandIdentity
    suspend fun readCapabilities(): BandCapabilities
    suspend fun readBattery(): BandBattery
    suspend fun readHealthLight(): BandHealthLightState = throw BandError.Unsupported("Health light")
    suspend fun writeHealthLight(state: BandHealthLightState): BandHealthLightState =
        throw BandError.Unsupported("Health light")
    /** 断链提醒 · the firmware's own signal when the phone link drops. null from the read
     *  means this NEXTBODY has no such switch, and the row is not drawn. */
    suspend fun readDisconnectReminder(): Boolean? = null
    suspend fun writeDisconnectReminder(on: Boolean): Boolean = throw BandError.Unsupported("Disconnect reminder")

    /** F2 §05 · the band's BIA numbers are computed from the weight we push down.
     *  Every startBodyCompositionTest must be preceded by this, or the sample is discarded. */
    suspend fun syncPersonalInfo(info: PersonalInfo)

    /** F2 §01 · dayOffset is a paging parameter and nothing else.
     *  It never becomes a primary key and never reaches a sentence the user reads. */
    suspend fun readOriginData(dayOffset: Int): List<OriginPoint>
    /** Return native snapshot timing with the exact requested calendar page. Re-querying
     *  its SDK cache does not turn an unfinished slot into a later, finalized observation. */
    suspend fun readOriginPage(calendarDay: Instant): OriginDataPage {
        val startedAt = Instant.now()
        val zone = ZoneId.systemDefault()
        val offset = BandTime.daysBetween(calendarDay, startedAt, zone)
        val points = readOriginData(offset)
        return OriginDataPage(points = points, readStartedAt = startedAt, readCompletedAt = Instant.now())
    }
    /** Existing SDK database dates, independent of the band's shorter live retention.
     *  This probe performs no Bluetooth transfer; offsets refer to user days to recover. */
    suspend fun cachedHistoryDayOffsets(limit: Int): List<Int> = emptyList()
    /** HRV, temperature and overnight oxygen live in separate SDK databases. Reading them
     *  through one command keeps the BLE operations serialized and preserves their distinct
     *  units and semantics. */
    suspend fun readHealthData(dayOffset: Int): BandHealthData
    suspend fun readSleep(dayOffset: Int): SleepNight?

    fun measureHeartRate(): Flow<MeasurementProgress>
    fun measureBodyComposition(): Flow<MeasurementProgress>
    /** 04 · one stress reading, the band's own 压力 test. One value at the end and no partials,
     *  so this is an awaited call rather than a stream like the two above — but it is not
     *  quick: a real NEXTBODY takes 19 s, reporting `progress` 0…100 in steps of 6 a second, and
     *  only the last callback carries the number.
     *  ⚠️ It holds the sensor for all of that, which is why `LiveReadout` stops the heart-rate
     *  stream around it instead of running the two together — and why the progress is passed
     *  back rather than swallowed: nineteen seconds of an unchanging label is a screen that
     *  looks stuck. */
    suspend fun measureStress(progress: (Int) -> Unit): Int
    /** For callers that only want the number. */
    suspend fun measureStress(): Int = measureStress {}
    /** 06 · Battery Check's HRV leg. The SDK may not stop itself — Demo holds ~60 s then
     *  `false`. Callers pass a timeout; a value of 0 before then is not a reading. */
    suspend fun measureHRV(timeout: Double): Int
    suspend fun measureHRV(): Int = measureHRV(60.0)

    suspend fun writeSetting(setting: BandSetting): BandSetting
    /** 12Y · phone finds the wrist. Start does not ring until this returns Enter.
     *  `.findBand` is still "Why won't it connect?" — do not reuse it here. */
    suspend fun startFindHoop()
    suspend fun stopFindHoop()
    suspend fun readConnectedRSSI(): Int
    /** Device alarm table. The adapter selects scene or text commands from device capabilities. */
    suspend fun readAlarms(): List<BandAlarm>
    suspend fun writeAlarm(alarm: BandAlarm): List<BandAlarm>
    suspend fun deleteAlarm(alarm: BandAlarm): List<BandAlarm>
    /** Ask the update server whether this band has newer firmware. `null` is "up to date";
     *  a throw is "could not ask" — the two are never drawn the same way. */
    suspend fun checkFirmwareUpdate(): FirmwareOffer?
    /** 12 rule 08 · OTA is three-state. `versionUnverified` is its own outcome — the DFU said
     *  done and the version could not be read back — and is never folded into the other two.
     *  `progress` is 0…1 while the file crosses; it is a number, never a tween. */
    suspend fun updateFirmware(version: String, progress: (Double) -> Unit): FirmwareUpdateResult
    suspend fun readAutoMonitoring(): AutoMonitoringRead
    suspend fun writeAutoMonitoring(slot: AutoMonitorSlot)
    /** DEBUG · the SDK cannot say which sports a firmware carries, so the probe asks by
     *  opening one and closing it again. `rawValue` is a VPDeviceRuningMode ordinal; true
     *  means the band took that mode, false means it does not exist on this firmware.
     *  ⚠️ Opens and immediately closes a real workout session on the band. */
    suspend fun probeSportMode(rawValue: Int): Boolean
    /** Open a sport mode and leave it running. `rawValue` is a VPDeviceRuningMode ordinal.
     *  A refusal means this firmware does not carry that mode. */
    suspend fun startSportMode(rawValue: Int)
    /** Close the sport mode previously opened with `startSportMode`. */
    suspend fun stopSportMode(rawValue: Int)
    /** 14 · the band's own report while a sport mode runs: heart rate, calories, distance
     *  and its clock, pushed by the firmware every second or so. This is the wrist during a
     *  session — the heart test is refused as busy while a mode is open. The stream stays
     *  open until cancelled; a firmware without the report simply never yields. */
    fun sportLiveInfo(): Flow<SportLiveInfo>
    /** 06 · THE PULSE STUDY. Forty seconds of the band's own beat-to-beat timing.
     *
     *  ⚠️ The command underneath is the SDK's single-lead ECG start — that is the only way to
     *  get beat-to-beat intervals out of this hardware — but NOTHING about a waveform crosses
     *  this boundary. The app never receives, holds, or draws a trace: it takes the interval
     *  series and the rate, which is what an autonomic-balance readout is computed from, and
     *  leaves the diagnostic surface the SDK offers (and its paid interpretation) alone.
     *  A product that draws a heart trace is a different regulatory animal in the US, and
     *  this one deliberately is not that animal.
     *
     *  Measured on a real NEXTBODY: 40 s, progress climbing about 3 % a second.
     *  The finger has to stay on the electrode for the whole run; `lostContact` is the SDK's
     *  `notLead` and is its own outcome, never folded into a failure. */
    fun measurePulseStudy(): Flow<PulseStudyStep>

    /** DEBUG · everything the band has stored from measurements started ON THE WATCH itself:
     *  thirteen kinds in one call, newest first, from `since` onwards.
     *  ⚠️ A read. No measurement, no sensor time, nothing lights up on the wrist.
     *  Returns one formatted line per stored record. */
    suspend fun readManualTestData(since: Instant): List<String>

    /** DEBUG · 微体检 (定制项目). One measurement → heart rate, blood oxygen, stress, blood sugar,
     *  temperature, systolic, diastolic, HRV. ⚠️ A real measurement on the wrist. */
    suspend fun probeMicroTest(progress: (Int) -> Unit): List<Pair<String, Double>>

    /** DEBUG · 微体检 (公版). One measurement, one model: the SDK's health glance carries a
     *  field per metric for a whole product family, and `functionSupport` is the band saying
     *  which of them it actually filled.
     *  ⚠️ 0 in a field is ambiguous — "this band does not have it" and "it did not read this
     *  time" look identical — which is why the bitmask is carried through beside the numbers. */
    suspend fun probeHealthGlance(progress: (Int) -> Unit): BandHealthGlance

    /** What this NEXTBODY says it can measure, in its own words.
     *  ⚠️ This is the honest answer to "what does this band do", and the reason it exists is
     *  that `readCapabilities` is partly guessed bit positions in `deviceFuctionData`. A guess
     *  that reads `.unsupported` on a working firmware silently removes a feature.
     *  This is a plain read: no measurement, no sensor time. */
    suspend fun readHealthFunctions(): List<BandHealthFunction>

    /** DEBUG · one pass over unused SDK seams. Not a product surface. */
    suspend fun probeCapabilitySweep(): List<String>
}

/** `connect(_:)` without progress. */
suspend fun BandService.connect(device: DiscoveredBand) = connect(device) { }

/** 14 · one answer from the band about its sport state: 0 not started, 1 running,
 *  2 paused; null if it says nothing within three seconds. */
suspend fun BandService.sportRunState(): Int? =
    withTimeoutOrNull(3_000) { sportLiveInfo().mapNotNull { it.runState }.first() }

/** One step of a running pulse study. */
sealed class PulseStudyStep {
    data object WaitingForContact : PulseStudyStep()
    data object Contact : PulseStudyStep()
    /** `percent` is the band's own count, 0…100. `heartRate` is what it is reporting right
     *  now — null until it has one, and the screen shows a resting tempo rather than a guess. */
    data class Measuring(val percent: Int, val heartRate: Int?) : PulseStudyStep()
    /** SDK `notLead`: the finger left the electrode. The run is over. */
    data object LostContact : PulseStudyStep()
    data class Finished(val study: PulseStudy) : PulseStudyStep()
    data class Failed(val reason: String) : PulseStudyStep()
}

/** What a completed pulse study carries. No waveform, by design — see `measurePulseStudy`. */
data class PulseStudy(
    /** The band's own average over the run. */
    val heartRate: Int?,
    /** Beat-to-beat intervals in milliseconds, in the order they were measured. This is the
     *  whole input to the balance readout.
     *  ⚠️ May be empty. A firmware that reports no intervals gets a result screen that says so. */
    val intervals: List<Double>,
    /** Where `intervals` came from. */
    val source: Source,
    /** Seconds the band actually ran, from the SDK. */
    val durationSeconds: Int?,
    /** The SDK's own HRV figure, kept for the log only.
     *  ⚠️ Never drawn. 「说不出出处的数字不上屏」. */
    val vendorHRV: Int?,
) {
    enum class Source(val raw: String) {
        /** The band's own beat-to-beat intervals. */
        intervals("intervals"),
        /** One heart rate a second, converted to the interval it implies. ⚠️ Coarser. */
        perSecondRates("perSecondRates"),
    }
}

/** What one 微体检 came back with: every field of VPHealthGlanceTestModel in the SDK's own
 *  order, and the band's own bitmask of which metrics this firmware carries. */
data class BandHealthGlance(
    /** name → the number the band put in the field. Every field, zeros included. */
    val values: List<Pair<String, Double>>,
    /** VPHealthGlanceType, verbatim. */
    val functionSupport: Long,
) {
    val supported: List<String> get() = supportBits.filter { functionSupport and it.first != 0L }.map { it.second }
    val unsupported: List<String> get() = supportBits.filter { functionSupport and it.first == 0L }.map { it.second }

    companion object {
        /** The fifteen bits of VPHealthGlanceType, in the SDK's own order. */
        val supportBits: List<Pair<Long, String>> = listOf(
            (1L shl 0) to "heart rate", (1L shl 1) to "blood oxygen", (1L shl 2) to "PPG blood pressure",
            (1L shl 3) to "cuff blood pressure", (1L shl 4) to "blood glucose", (1L shl 5) to "body temperature",
            (1L shl 6) to "stress", (1L shl 7) to "emotion", (1L shl 8) to "fatigue", (1L shl 9) to "HRV",
            (1L shl 10) to "skin conductance", (1L shl 11) to "blood components", (1L shl 12) to "body composition",
            (1L shl 13) to "ECG single", (1L shl 14) to "ECG multi",
        )
    }
}

/** One row of the band's own health-function list (VPHealthFunctionModel).
 *  ⚠️ `support == false` is the band saying no. `open` is a setting, not a capability. */
data class BandHealthFunction(
    /** VPHealthFunctionType, carried through verbatim so an unknown future kind still prints. */
    val rawValue: Int,
    val name: String,
    val support: Boolean,
    val open: Boolean,
) {
    companion object {
        /** The seventeen VPHealthFunctionType values, in the SDK's own order. */
        fun name(forRawValue: Int): String = when (forRawValue) {
            0 -> "blood glucose"; 1 -> "blood pressure"; 2 -> "blood oxygen"; 3 -> "body temperature"
            4 -> "HRV"; 5 -> "stress"; 6 -> "MET"; 7 -> "blood components"; 8 -> "body composition"
            9 -> "health glance"; 10 -> "emotion"; 11 -> "fatigue"; 12 -> "nuclear radiation"
            13 -> "fall detection"; 14 -> "AI chat"; 15 -> "AI dial"; 16 -> "skin conductance"
            else -> "type $forRawValue"
        }
    }
}

enum class BandConnectionState { idle, scanning, connecting, connected, disconnected }

sealed class BandEvent {
    data class Discovered(val band: DiscoveredBand) : BandEvent()
    data class State(val state: BandConnectionState) : BandEvent()
    data class Battery(val battery: BandBattery) : BandEvent()
    /** The band finished a measurement it started on its own wrist, not one we asked for. */
    data object DeviceInitiatedMeasurementFinished : BandEvent()
    /** Firmware find-the-wrist: Enter / Exit / Timeout after `startFindHoop`. */
    data class FindHoop(val phase: FindHoopPhase) : BandEvent()
    /** History dump tick from the SDK: 1-based day being read, days on the band, 0…100 of that day. */
    data class HistoryRead(val day: Int, val of: Int, val percent: Int) : BandEvent()
    data class ConnectionStep(val stage: BandSyncProgress.Stage) : BandEvent()
}

/** Fan-out for `BandService.events`. Each `events` access gets its own collector; a send
 *  reaches all of them, and a cancelled one just unsubscribes. */
class BandEventHub {
    private val flow = MutableSharedFlow<BandEvent>(extraBufferCapacity = 256, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    fun stream(): Flow<BandEvent> = flow

    fun send(event: BandEvent) { flow.tryEmit(event) }
}

data class PersonalInfo(
    val heightCm: Int,
    val weightKg: Int,
    val birthYear: Int,
    val sexIsMale: Boolean,
    val targetStep: Int,
)

data class OriginDataPage(
    val points: List<OriginPoint>,
    val readStartedAt: Instant,
    val readCompletedAt: Instant,
)

/** One five-minute point, exactly as OriginData gives it.
 *  ⚠️ OriginData carries a `time` string and nothing else: no date, no timezone, no offset.
 *  A page's date can only be derived from the dayOffset you asked for, which is why every
 *  batch is stamped with the calendar day at the moment it is stored. */
data class OriginPoint(
    val time: String,
    val heart: Int?,
    val step: Int?,
    val cal: Int?,
    /** Metres for this five-minute slot. The SDK's `disValue` is kilometres; the bridge
     *  converts before this is stored. */
    val distance: Int?,
    val met: Double?,
    // F5 §07 / F7 rule 04 · no spo2 here. The whitelist is applied where the SDK's object is
    // rebuilt, not downstream.
    val temperature: Double?,
    /** RMSSD in ms for this tick, joined in from the band's separate HRV history. */
    val hrv: Double?,
    val stress: Int?,
    val sleepState: Int?,
)

data class BandHealthData(
    val temperatures: List<TemperatureSample>,
    val hrv: List<HrvMinuteSample>,
    val oxygen: List<OxygenSample> = emptyList(),
    val optical: List<OpticalResponseSample> = emptyList(),
    /** Vendor rows that mapped to nothing (zeros / non-finite). ALL ZEROS uses this. */
    val opticalDroppedZeros: Int = 0,
    val temperatureStatus: BandDomainReadStatus = BandDomainReadStatus.complete,
    val hrvStatus: BandDomainReadStatus = BandDomainReadStatus.complete,
    val oxygenStatus: BandDomainReadStatus = BandDomainReadStatus.complete,
    val opticalStatus: BandDomainReadStatus = BandDomainReadStatus.complete,
    val respiration: List<RespirationSample> = emptyList(),
    val respirationStatus: BandDomainReadStatus = BandDomainReadStatus.notCollected,
    /** False when this page reused a dedicated command from the last half hour.
     *  The caller then leaves that domain's acknowledgement untouched. */
    val publishesHRV: Boolean = true,
    val publishesTemperature: Boolean = true,
    val publishesOxygen: Boolean = true,
)

/** The states the measurement takeover renders. `lead == false` is the amber nudge:
 *  it means "we need you to move", never "you failed". */
sealed class MeasurementProgress {
    data object WaitingForContact : MeasurementProgress()
    data object Contact : MeasurementProgress()
    /** `secondsLeft` is the band's own clock when it has one (body composition reports its
     *  progress); null means the phone counts, as for a heart-rate read the SDK only values. */
    data class Measuring(val fraction: Double, val partial: PartialReading?, val secondsLeft: Int? = null) : MeasurementProgress()
    data object LostContact : MeasurementProgress()
    data class Finished(val result: MeasurementResult) : MeasurementProgress()
    data class Failed(val reason: String) : MeasurementProgress()
}

data class PartialReading(
    val heartRate: Int? = null,
    val bodyFatPercent: Double? = null,
)

sealed class MeasurementResult {
    data class HeartRate(val hr: Int, val hrv: Int?, val stress: Int?) : MeasurementResult()
    /** 06 · one pulse study: the rate, and the beat-to-beat intervals behind it. */
    data class PulseStudyResult(val study: PulseStudy) : MeasurementResult()
    /** ⚠️ There is no weight in BodyCompositionTestResult: these come from the weight we
     *  pushed down with syncPersonalInfo, which is why fat and lean are not two independent
     *  measurements and Δfat + Δlean always equals Δweight. */
    data class BodyComposition(val reading: BodyCompositionReading) : MeasurementResult()
}

data class BodyCompositionReading(
    val bodyFatPercent: Double,
    val fatMassKg: Double,
    val leanMassKg: Double,
    val muscleKg: Double?,
    val boneKg: Double?,
    val bodyWaterPercent: Double?,
    val proteinPercent: Double?,
    val subcutaneousFatPercent: Double?,
    val skeletalMusclePercent: Double?,
    val bmrKcal: Int?,
    val bmi: Double?,
    /** The weight this reading was computed from — the one we pushed down, not one measured. */
    val inputWeightKg: Double,
    /** The rest of the SDK's twelve, for the baseline screen. A missing field is a dash. */
    val muscleRatePercent: Double? = null,
    val waterKg: Double? = null,
    val proteinKg: Double? = null,
)

sealed class BandSetting {
    data class HeartRateAlarm(val on: Boolean, val low: Int, val high: Int) : BandSetting()
}

data class AutoMonitorSlot(
    val kind: Kind,
    val on: Boolean,
    val supportsRange: Boolean,
    val startHour: Int,
    val endHour: Int,
    val intervalMinutes: Int,
    /** The device's own interval capability. Zero means every whole-minute value 0...180;
     *  otherwise the firmware names step, 2 × step … 180. Minutes below the step are offered
     *  as probes — the write is only believed when the band echoes the value back. */
    val intervalStepMinutes: Int = 5,
    /** 12 rule 06 · isSlotModify / isIntervalModify from readAutoMeasureSetting(). */
    val slotModifiable: Boolean = true,
    val intervalModifiable: Boolean = true,
) {
    enum class Kind(val raw: String) {
        heartRate("heartRate"), bloodPressure("bloodPressure"), bloodGlucose("bloodGlucose"), stress("stress"),
        bloodOxygen("bloodOxygen"), temperature("temperature"), lorentz("lorentz"), hrv("hrv"),
        scientificSleep("scientificSleep"), bloodComponents("bloodComponents"),
    }

    val id: Kind get() = kind

    val allowedIntervals: List<Int>
        get() = AutoMeasurementIntervalPolicy.options(minimumStepMinutes = intervalStepMinutes)

    companion object {
        /** Firmware that only exposes the older on/off switches. The interval is not a setting. */
        fun firmwareOwned(kind: Kind, on: Boolean) = AutoMonitorSlot(
            kind = kind, on = on, supportsRange = false,
            startHour = 0, endHour = 24, intervalMinutes = 0,
            intervalStepMinutes = 0, slotModifiable = false, intervalModifiable = false)
    }
}

/** What `readAutoMonitoring()` actually found. The sheet used to treat "no rows" as a blank
 *  page, which hid three different answers: interval API empty, switch-only firmware, and a
 *  read that never came back. */
sealed class AutoMonitoringRead {
    /** `autoMonitSwitchType != 0`. Each row can carry its own interval. */
    data class Interval(val rows: List<AutoMonitorSlot>) : AutoMonitoringRead()
    /** `autoMonitSwitchType == 0`. Only the older base-function switches exist. */
    data class Switches(val rows: List<AutoMonitorSlot>) : AutoMonitoringRead()
    data class Failed(val headline: String, val sentence: String) : AutoMonitoringRead()

    val slots: List<AutoMonitorSlot>
        get() = when (this) {
            is Interval -> rows
            is Switches -> rows
            is Failed -> emptyList()
        }

    companion object {
        fun failed(error: Throwable): AutoMonitoringRead {
            if (error is BandError) {
                return when (error) {
                    is BandError.NotConnected -> Failed(
                        headline = L("BAND OFFLINE"),
                        sentence = L("Connect this NEXTBODY, then open Automatic measurement again."))
                    is BandError.Timeout -> Failed(
                        headline = L("THE BAND DID NOT ANSWER"),
                        sentence = L("The automatic-measurement read timed out. Keep it on your wrist and try again."))
                    is BandError.Unsupported -> Failed(
                        headline = L("THIS NEXTBODY DOES NOT EXPOSE AUTOMATIC MEASUREMENT"),
                        sentence = L("The firmware has no interval API and no automatic-measurement switches to turn."))
                    else -> Failed(
                        headline = error.localizedDescription,
                        sentence = L("This NEXTBODY refused the automatic-measurement read."))
                }
            }
            return Failed(
                headline = L("THE BAND DID NOT ANSWER"),
                sentence = error.localizedDescription)
        }
    }
}

/** Swift `error.localizedDescription`. */
val Throwable.localizedDescription: String
    get() = message ?: this::class.simpleName ?: "Error"

sealed class BandError(message: String) : Exception(message) {
    data object NotConnected : BandError("BAND OFFLINE") { private fun readResolve(): Any = NotConnected }
    data class Unsupported(val feature: String) : BandError("THIS NEXTBODY DOES NOT MEASURE ${feature.uppercase()}")
    data object Busy : BandError("MEASURING NOW") { private fun readResolve(): Any = Busy }
    data class Timeout(val command: String) : BandError("${command.uppercase()} TIMED OUT")
    data class Rejected(val reason: String) : BandError(reason.uppercase())

    val errorDescription: String get() = message ?: ""
}

/** What the update server offers for the connected band: the version, and its release
 *  notes one per line. The server, not the band, is the source — the band cannot know. */
data class FirmwareOffer(val version: String, val notes: List<String>)

/** 12 rule 08 · completed / failed / versionUnverified. */
sealed class FirmwareUpdateResult {
    data class Completed(val version: String) : FirmwareUpdateResult()
    data class Failed(val reason: String) : FirmwareUpdateResult()
    data object VersionUnverified : FirmwareUpdateResult()
}

/** A device build with no SDK reachable. Stays idle and invents nothing — MockBand's
 *  plausible day would otherwise land on a real account. */
class DisconnectedBand : BandService {
    override var state: BandConnectionState = BandConnectionState.idle
        private set
    private val hub = BandEventHub()
    override val events: Flow<BandEvent> get() = hub.stream()

    override suspend fun startScan() {}
    override suspend fun stopScan() {}
    override suspend fun connect(device: DiscoveredBand, progress: (Double) -> Unit) = throw BandError.NotConnected
    override suspend fun reconnectIfBound() {}
    override suspend fun disconnect() { state = BandConnectionState.disconnected }

    override suspend fun readIdentity(): BandIdentity = throw BandError.NotConnected
    override suspend fun readCapabilities(): BandCapabilities = throw BandError.NotConnected
    override suspend fun readBattery(): BandBattery = throw BandError.NotConnected
    override suspend fun syncPersonalInfo(info: PersonalInfo) = throw BandError.NotConnected
    override suspend fun readOriginData(dayOffset: Int): List<OriginPoint> = throw BandError.NotConnected
    override suspend fun readHealthData(dayOffset: Int): BandHealthData = throw BandError.NotConnected
    override suspend fun readSleep(dayOffset: Int): SleepNight? = throw BandError.NotConnected
    override fun measureHeartRate(): Flow<MeasurementProgress> = flow { throw BandError.NotConnected }
    override fun measureBodyComposition(): Flow<MeasurementProgress> = flow { throw BandError.NotConnected }
    override suspend fun measureStress(progress: (Int) -> Unit): Int = throw BandError.NotConnected
    override suspend fun measureHRV(timeout: Double): Int = throw BandError.NotConnected
    override suspend fun writeSetting(setting: BandSetting): BandSetting = throw BandError.NotConnected
    override suspend fun checkFirmwareUpdate(): FirmwareOffer? = throw BandError.NotConnected
    override suspend fun updateFirmware(version: String, progress: (Double) -> Unit): FirmwareUpdateResult = throw BandError.NotConnected
    override suspend fun readAutoMonitoring(): AutoMonitoringRead = throw BandError.NotConnected
    override suspend fun writeAutoMonitoring(slot: AutoMonitorSlot) = throw BandError.NotConnected
    override suspend fun probeSportMode(rawValue: Int): Boolean = throw BandError.NotConnected
    override suspend fun startSportMode(rawValue: Int) = throw BandError.NotConnected
    override suspend fun stopSportMode(rawValue: Int) = throw BandError.NotConnected
    /** No SDK, so no wrist to report from: the stream closes rather than hanging a reader. */
    override fun sportLiveInfo(): Flow<SportLiveInfo> = emptyFlow()
    override suspend fun readHealthFunctions(): List<BandHealthFunction> = throw BandError.NotConnected
    override suspend fun probeHealthGlance(progress: (Int) -> Unit): BandHealthGlance = throw BandError.NotConnected
    override suspend fun readManualTestData(since: Instant): List<String> = throw BandError.NotConnected
    override fun measurePulseStudy(): Flow<PulseStudyStep> = flow { throw BandError.NotConnected }
    override suspend fun probeMicroTest(progress: (Int) -> Unit): List<Pair<String, Double>> = throw BandError.NotConnected
    override suspend fun probeCapabilitySweep(): List<String> = throw BandError.NotConnected
    override suspend fun startFindHoop() = throw BandError.NotConnected
    override suspend fun stopFindHoop() {}
    override suspend fun readConnectedRSSI(): Int = throw BandError.NotConnected
    override suspend fun readAlarms(): List<BandAlarm> = throw BandError.NotConnected
    override suspend fun writeAlarm(alarm: BandAlarm): List<BandAlarm> = throw BandError.NotConnected
    override suspend fun deleteAlarm(alarm: BandAlarm): List<BandAlarm> = throw BandError.NotConnected
}

