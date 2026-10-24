package com.nextbody.hoop.band

import com.nextbody.hoop.app.DebugLaunch
import com.nextbody.hoop.model.SportModeCatalog
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random

/**
 * The band the simulator has (Android: the emulator / seeded build). It answers on the same
 * timings the real one does, so the choreography on 02 and 06 is exercised for real: the scan
 * takes a couple of seconds, contact does not arrive instantly, and a body scan really does
 * take thirty seconds.
 *
 * It is not a stub that returns immediately — a stub would hide every timing bug the
 * takeover has, which is the only part of this flow that is hard to get right.
 */
class MockBand : BandService {
    override var state: BandConnectionState = BandConnectionState.idle
        private set(value) {
            field = value
            hub.send(BandEvent.State(value))
        }

    private val hub = BandEventHub()
    override val events: Flow<BandEvent> get() = hub.stream()
    private val queue = HoopQueue()

    @Volatile private var pushedWeightKg: Double = 75.6
    @Volatile private var healthLight: BandHealthLightState = BandHealthLightState.slowFlash
    @Volatile private var disconnectReminder = true
    private var autoMonitoringSlots: MutableList<AutoMonitorSlot> = mutableListOf(
        AutoMonitorSlot(kind = AutoMonitorSlot.Kind.heartRate, on = true, supportsRange = true,
            startHour = 0, endHour = 24, intervalMinutes = 30, intervalStepMinutes = 1),
        AutoMonitorSlot(kind = AutoMonitorSlot.Kind.bloodOxygen, on = true, supportsRange = true,
            startHour = 22, endHour = 7, intervalMinutes = 60, intervalStepMinutes = 5),
        AutoMonitorSlot(kind = AutoMonitorSlot.Kind.hrv, on = true, supportsRange = false,
            startHour = 0, endHour = 24, intervalMinutes = 60, intervalStepMinutes = 1),
        AutoMonitorSlot.firmwareOwned(kind = AutoMonitorSlot.Kind.scientificSleep, on = true),
        AutoMonitorSlot(kind = AutoMonitorSlot.Kind.stress, on = true, supportsRange = true,
            startHour = 9, endHour = 22, intervalMinutes = 30, intervalStepMinutes = 5),
        AutoMonitorSlot(kind = AutoMonitorSlot.Kind.temperature, on = false, supportsRange = false,
            startHour = 0, endHour = 24, intervalMinutes = 60, intervalStepMinutes = 5),
        AutoMonitorSlot(kind = AutoMonitorSlot.Kind.bloodGlucose, on = true, supportsRange = true,
            startHour = 8, endHour = 22, intervalMinutes = 30, intervalStepMinutes = 5),
    )

    private var alarms: MutableList<BandAlarm> = mutableListOf(
        BandAlarm(id = 1, hour = 7, minute = 30, on = true,
            repeatMask = BandAlarmMath.weekdaysMask,
            date = BandAlarm.onceDatePlaceholder, scene = 0),
        BandAlarm(id = 2, hour = 8, minute = 45, on = true,
            repeatMask = BandAlarmMath.weekdaysMask,
            date = BandAlarm.onceDatePlaceholder, scene = 0),
    )

    override suspend fun startScan() {
        state = BandConnectionState.scanning
        delay(2_200)
        // A scan that started while the bound band reconnected (DEVICE page + activation
        // sheet at once) still answers, as the real radio does.
        if (!scanAnswers()) return
        hub.send(BandEvent.Discovered(DiscoveredBand(
            id = firstHoop, name = "NEXTBODY", rssi = -46, batteryPercent = 96)))
        // The second NEXTBODY of a set sits on its charger a little further away. It arrives
        // late so Connect's first-discovered pick still lands on the first band.
        delay(900)
        if (!scanAnswers()) return
        hub.send(BandEvent.Discovered(DiscoveredBand(
            id = secondHoop, name = "NEXTBODY", rssi = -61, batteryPercent = 71)))
    }

    private fun scanAnswers() = state == BandConnectionState.scanning ||
        state == BandConnectionState.connected || state == BandConnectionState.connecting

    private val onSecond: Boolean get() = BoundBand.identifier == secondHoop

    override suspend fun stopScan() { if (state == BandConnectionState.scanning) state = BandConnectionState.idle }

    override suspend fun connect(device: DiscoveredBand, progress: (Double) -> Unit) {
        state = BandConnectionState.connecting
        // Same beats the real SDK reports: connecting → link up → password verified.
        progress(0.0)
        delay(600)
        progress(0.25)
        delay(600)
        progress(0.7)
        delay(600)
        progress(1.0)
        delay(600)
        state = BandConnectionState.connected
        BoundBand.identifier = device.id
        hub.send(BandEvent.Battery(readBattery()))
    }

    override suspend fun reconnectIfBound() {
        BoundBand.identifier ?: return
        if (state == BandConnectionState.connected) return
        hub.send(BandEvent.ConnectionStep(BandSyncProgress.Stage.searching))
        state = BandConnectionState.connecting
        hub.send(BandEvent.ConnectionStep(BandSyncProgress.Stage.connecting))
        delay(700)
        hub.send(BandEvent.ConnectionStep(BandSyncProgress.Stage.verifying))
        state = BandConnectionState.connected
        runCatching { readBattery() }
    }

    override suspend fun disconnect() { state = BandConnectionState.disconnected }

    override suspend fun prepareFreshSync() { dumpedThisRefresh = false }
    override suspend fun finishFreshSync() {}

    /** One dump per refresh, the way the real SDK reads every retained day before
     *  the per-day cache lookups. The ticks are what the device-page bar follows. */
    @Volatile private var dumpedThisRefresh = false
    private suspend fun simulateHistoryDump() {
        if (dumpedThisRefresh) return
        dumpedThisRefresh = true
        val days = 7
        for (day in 1..days) {
            hub.send(BandEvent.HistoryRead(day = day, of = days, percent = 0))
            delay(70)
            hub.send(BandEvent.HistoryRead(day = day, of = days, percent = 55))
            delay(70)
            hub.send(BandEvent.HistoryRead(day = day, of = days, percent = 100))
        }
    }

    override suspend fun readIdentity(): BandIdentity {
        requireConnection()
        return BandIdentity(
            name = "NEXTBODY", model = "KR96 PRO", hardware = "1.2", firmware = "2.4.1",
            deviceNumber = if (onSecond) "HB-0107" else "HB-0042",
            bleIdentifier = if (onSecond) secondHoop else firstHoop,
            watchDataDayNumber = 7, sportMode = "10 TYPES")
    }

    override suspend fun readCapabilities(): BandCapabilities {
        requireConnection()
        return BandCapabilities(
            bodyComponent = FunctionStatus.support,
            ecg = FunctionStatus.support,
            hrv = FunctionStatus.support,
            stress = FunctionStatus.support,
            autoMeasure = FunctionStatus.support,
            wearDetection = FunctionStatus.support,
            functions = mapOf("heart" to FunctionStatus.support, "spo2" to FunctionStatus.support,
                "blood" to FunctionStatus.support, "temperature" to FunctionStatus.unsupported),
        )
    }

    override suspend fun readBattery(): BandBattery {
        requireConnection()
        val battery = when {
            edge("charging") -> BandBattery(isPercent = true, percent = 64, level = null, chargeState = BandBattery.ChargeState.charging)
            edge("charged") -> BandBattery(isPercent = true, percent = 100, level = null, chargeState = BandBattery.ChargeState.full)
            onSecond -> BandBattery(isPercent = true, percent = 71, level = null, chargeState = BandBattery.ChargeState.charging)
            else -> BandBattery(isPercent = true, percent = 82, level = null, chargeState = BandBattery.ChargeState.unplugged)
        }
        hub.send(BandEvent.Battery(battery))
        return battery
    }

    override suspend fun syncPersonalInfo(info: PersonalInfo) {
        requireConnection()
        pushedWeightKg = info.weightKg.toDouble()
        delay(220)
    }

    override suspend fun readOriginData(dayOffset: Int): List<OriginPoint> {
        requireConnection()
        simulateHistoryDump()
        delay(400)
        // 288 five-minute points, a plausible day: asleep until 07, a walk, a session at 18.
        return (0 until 288).map { i ->
            val minute = i * 5
            val hour = minute / 60
            val asleep = hour < 7
            val walking = hour == 7 && minute % 60 < 35
            val session = hour == 18 && minute % 60 < 45
            val hr = when {
                asleep -> 49 + (0..5).random()
                walking -> 96 + (0..14).random()
                session -> 138 + (0..22).random()
                else -> 60 + (0..10).random()
            }
            OriginPoint(
                time = hhmm(hour, minute % 60),
                heart = hr, step = if (asleep) 0 else (0..45).random(),
                cal = (0..6).random(), distance = (0..40).random(),
                met = max(1.0, hr / 62.0), temperature = null,
                // Every ten minutes, as the band does; higher asleep, as HRV is.
                hrv = if (minute % 10 == 0)
                    (if (asleep) 52 + (0..18).random() else 32 + (0..16).random()).toDouble()
                else null,
                stress = if (asleep) null else 20 + (0..30).random(),
                // NEXTBODY's original-data dictionary has no sleep stage. Accurate stages come
                // from SleepNight.line, exactly as they do on the real SDK.
                sleepState = null)
        }
    }

    override suspend fun readSleep(dayOffset: Int): SleepNight? {
        requireConnection()
        simulateHistoryDump()
        // Scientific sleep adds the band's own REM runs. Turning its automatic PPG off
        // deliberately falls back to the basic deep/light line, just like the real firmware.
        val scientificSleep = synchronized(this) {
            autoMonitoringSlots.firstOrNull { it.kind == AutoMonitorSlot.Kind.scientificSleep }?.on ?: false
        }
        val line = if (scientificSleep) listOf(
            SleepStageRun(stage = 1, minutes = 70),
            SleepStageRun(stage = 0, minutes = 55),
            SleepStageRun(stage = 1, minutes = 42),
            SleepStageRun(stage = 2, minutes = 32),
            SleepStageRun(stage = 1, minutes = 50),
            SleepStageRun(stage = 4, minutes = 6),
            SleepStageRun(stage = 0, minutes = 43),
            SleepStageRun(stage = 2, minutes = 24),
            SleepStageRun(stage = 1, minutes = 88),
        ) else listOf(
            SleepStageRun(stage = 1, minutes = 70),
            SleepStageRun(stage = 0, minutes = 55),
            SleepStageRun(stage = 1, minutes = 92),
            SleepStageRun(stage = 4, minutes = 6),
            SleepStageRun(stage = 0, minutes = 43),
            SleepStageRun(stage = 1, minutes = 144),
        )
        val zone = ZoneId.systemDefault()
        val day = java.time.LocalDate.now(zone).minusDays(dayOffset.toLong()).atStartOfDay(zone)
        val wake = day.plusHours(7).toInstant()
        val start = wake.minusSeconds(410L * 60)
        return SleepNight(
            totalMinutes = 410,
            deepMinutes = 98,
            lightMinutes = if (scientificSleep) 250 else 306,
            wakeCount = 1,
            line = line,
            sleepStart = start,
            wakeAt = wake,
        )
    }

    override suspend fun readHealthData(dayOffset: Int): BandHealthData {
        requireConnection()
        simulateHistoryDump()
        val temperatures = (0 until 24 * 60 step 5).map { minute ->
            TemperatureSample(time = hhmm(minute / 60, minute % 60),
                celsius = 34.0 + 0.4 * sin(minute / 180.0))
        }
        val hrv = (0 until 8 * 60).map { minute ->
            HrvMinuteSample(time = hhmm(minute / 60, minute % 60),
                rmssdMS = 48 + 5 * sin(minute / 45.0),
                vendorValue = null, rrCount = 40)
        }
        // Overnight automatic oxygen only — daytime minutes are not filed, matching Q6.
        val oxygen = (0 until 7 * 60 step 5).map { minute ->
            OxygenSample(time = hhmm(minute / 60, minute % 60), percent = 95 + (minute / 30) % 3)
        }
        // Daytime optical meal-response slots. Night hours are left empty so the own
        // median is a daytime number, matching the RESPONSE card.
        val optical = (10 * 60 until 22 * 60 step 30).map { minute ->
            val value = 100 + 8 * sin(minute / 90.0)
            OpticalResponseSample(time = hhmm(minute / 60, minute % 60), optical = value)
        }
        return BandHealthData(temperatures = temperatures, hrv = hrv, oxygen = oxygen, optical = optical)
    }

    override fun measureHeartRate(): Flow<MeasurementProgress> =
        // The real SDK hands back a rate on every `testing` callback, from the first one, and
        // it wanders as the band settles. The mock does the same, so the trace on 06 beats at
        // a rate that moves, not at a constant the screen could have invented.
        stream(total = 60, progress = { fraction ->
            val second = fraction * 60
            val hr = if (second < 1) null else 62 + (3 * sin(second / 7)).roundToInt() + (if (second < 6) 4 else 0)
            MeasurementProgress.Measuring(fraction = fraction, partial = hr?.let { PartialReading(heartRate = it) })
        }, finish = {
            MeasurementResult.HeartRate(hr = 62, hrv = 54, stress = 34)
        })

    override fun measureBodyComposition(): Flow<MeasurementProgress> {
        // ⚠️ 30s, two contacts, fourteen fields, and no resume: lifting off restarts it.
        val weight = pushedWeightKg
        return stream(total = 30, progress = { fraction ->
            MeasurementProgress.Measuring(fraction = fraction,
                partial = if (fraction > 0.5) PartialReading(bodyFatPercent = 24.1) else null)
        }, finish = {
            MeasurementResult.BodyComposition(BodyCompositionReading(
                bodyFatPercent = 14.8,
                fatMassKg = weight * 0.148,
                leanMassKg = weight * 0.852,
                muscleKg = weight * 0.62, boneKg = 2.7,
                bodyWaterPercent = 55.2, proteinPercent = 17.6,
                subcutaneousFatPercent = 18.9, skeletalMusclePercent = 42.1,
                bmrKcal = 1710, bmi = 21.3,
                inputWeightKg = weight,
                muscleRatePercent = 74.3,
                waterKg = weight * 0.552,
                proteinKg = weight * 0.176))
        })
    }

    /** 04 · the inserted stress test. It really does take half a minute and it really does
     *  hold the sensor for all of it, so the panel's live heart rate goes quiet while it
     *  runs — which is the whole behaviour `LiveReadout` exists to get right. */
    override suspend fun measureStress(progress: (Int) -> Unit): Int {
        requireConnection()
        // DEBUG · `NB_DEBUG_EDGE=nostress` walks the firmware that has no stress test.
        if (edge("nostress")) throw BandError.Unsupported("STRESS")
        // The real band's own shape, measured on the wrist: 0…100 in steps of 6, one a
        // second, and the value only on the last callback. 19 s.
        var done = 0
        while (done < 100) {
            currentCoroutineContext().ensureActive()
            delay(1_000)
            done = min(100, done + 6)
            progress(done)
        }
        return 24 + (0..22).random()
    }

    /** Simulator stand-in for the SDK's HRV test: settles after a few seconds with a
     *  plausible resting value. Real firmware may hold the full minute. */
    override suspend fun measureHRV(timeout: Double): Int {
        requireConnection()
        if (edge("nohrv")) throw BandError.Unsupported("HRV")
        val steps = min(8, max(2, (timeout / 3).toInt()))
        repeat(steps) {
            currentCoroutineContext().ensureActive()
            delay(1_000)
        }
        return 48 + (0..16).random()
    }

    private fun stream(
        total: Int,
        progress: (Double) -> MeasurementProgress,
        finish: () -> MeasurementResult,
    ): Flow<MeasurementProgress> = flow {
        // F1 rule 05 · a cancelled consumer stops the measurement. A cold flow is cancelled
        // with its collector, so the mock never ticks on after the takeover closes.
        if (state != BandConnectionState.connected) throw BandError.NotConnected
        emit(MeasurementProgress.WaitingForContact)
        // DEBUG · `NB_DEBUG_EDGE=nocontact` never finds a finger, to walk 03 edge 1.
        if (edge("nocontact")) { while (currentCoroutineContext().isActive) delay(1_000); return@flow }
        // The finger takes about 1.2s to register, which is why the nudge is at 5s.
        delay(1_200)
        emit(MeasurementProgress.Contact)
        delay(800)
        for (second in 0..total) {
            delay(1_000)
            emit(progress(second.toDouble() / total))
        }
        emit(MeasurementProgress.Finished(finish()))
    }

    /** The simulator's update server: one offer, a moment later. `NB_DEBUG_EDGE=uptodate`
     *  answers that the band is current, `otacheckfail` that the server could not be reached. */
    override suspend fun checkFirmwareUpdate(): FirmwareOffer? {
        requireConnection()
        delay(900)
        if (edge("uptodate")) return null
        if (edge("otacheckfail")) throw BandError.Rejected("update server unreachable")
        return FirmwareOffer(version = "2.5.0", notes = listOf("Better sleep staging", "Battery reported in percent"))
    }

    override suspend fun updateFirmware(version: String, progress: (Double) -> Unit): FirmwareUpdateResult {
        // A real transfer takes minutes; the mock walks the same shape in seconds.
        for (step in 1..24) {
            delay(100)
            progress(step / 24.0)
        }
        // DEBUG · `NB_DEBUG_EDGE=otaunverified` walks 12 edge 5 on the mock.
        if (edge("otaunverified")) return FirmwareUpdateResult.VersionUnverified
        return FirmwareUpdateResult.Completed(version = version)
    }

    override suspend fun writeSetting(setting: BandSetting): BandSetting {
        requireConnection()
        delay(180)
        // F3 · the switch renders the value that came back, never the value we sent.
        return setting
    }

    override suspend fun readHealthLight(): BandHealthLightState {
        requireConnection()
        return queue.run("mock.readHealthLight", priority = HoopQueue.Priority.p1) {
            delay(160)
            healthLight
        }
    }

    override suspend fun writeHealthLight(state: BandHealthLightState): BandHealthLightState {
        requireConnection()
        return queue.run("mock.writeHealthLight", priority = HoopQueue.Priority.p0) {
            delay(180)
            healthLight = state
            state
        }
    }

    override suspend fun readDisconnectReminder(): Boolean? {
        requireConnection()
        return queue.run("mock.readDisconnectReminder", priority = HoopQueue.Priority.p1) {
            delay(120)
            disconnectReminder
        }
    }

    override suspend fun writeDisconnectReminder(on: Boolean): Boolean {
        requireConnection()
        return queue.run("mock.writeDisconnectReminder", priority = HoopQueue.Priority.p0) {
            delay(160)
            disconnectReminder = on
            on
        }
    }

    override suspend fun readAutoMonitoring(): AutoMonitoringRead {
        requireConnection()
        return queue.run("mock.readAutoMonitoring", priority = HoopQueue.Priority.p1) {
            when {
                edge("autorefuse") -> throw BandError.Timeout("readAutoMonitoring")
                edge("autonone") -> AutoMonitoringRead.Switches(emptyList())
                edge("autoempty") -> AutoMonitoringRead.Interval(emptyList())
                edge("autoswitch") -> AutoMonitoringRead.Switches(listOf(
                    AutoMonitorSlot.firmwareOwned(kind = AutoMonitorSlot.Kind.heartRate, on = true),
                    AutoMonitorSlot.firmwareOwned(kind = AutoMonitorSlot.Kind.bloodOxygen, on = true),
                    AutoMonitorSlot.firmwareOwned(kind = AutoMonitorSlot.Kind.hrv, on = false),
                    AutoMonitorSlot.firmwareOwned(kind = AutoMonitorSlot.Kind.stress, on = true),
                ))
                else -> AutoMonitoringRead.Interval(synchronized(this) { autoMonitoringSlots.toList() })
            }
        }
    }

    override suspend fun writeAutoMonitoring(slot: AutoMonitorSlot) {
        requireConnection()
        queue.run("mock.writeAutoMonitoring", priority = HoopQueue.Priority.p0) {
            if (slot.intervalModifiable) {
                if (!slot.allowedIntervals.contains(slot.intervalMinutes)) {
                    throw BandError.Rejected("${slot.intervalMinutes} minute interval is not supported")
                }
            }
            delay(160)
            synchronized(this) {
                val index = autoMonitoringSlots.indexOfFirst { it.id == slot.id }
                if (index >= 0) autoMonitoringSlots[index] = slot else autoMonitoringSlots.add(slot)
            }
        }
    }

    /** The simulator stands in for a multi-mode firmware. Raw values are
     *  VPDeviceRuningMode ordinals. Every catalogued mode is accepted so the plus-menu
     *  flow can be walked end to end on a simulator. */
    override suspend fun probeSportMode(rawValue: Int): Boolean {
        requireConnection()
        return queue.run("mock.probeSportMode", priority = HoopQueue.Priority.p0) {
            delay(220)
            SportModeCatalog.modes.any { it.rawValue == rawValue }
        }
    }

    override suspend fun startSportMode(rawValue: Int) {
        requireConnection()
        queue.run("mock.startSportMode", priority = HoopQueue.Priority.p0) {
            delay(220)
            if (SportModeCatalog.modes.none { it.rawValue == rawValue }) {
                throw BandError.Unsupported("sport mode $rawValue")
            }
        }
    }

    override suspend fun stopSportMode(rawValue: Int) {
        requireConnection()
        queue.run("mock.stopSportMode", priority = HoopQueue.Priority.p0) {
            delay(160)
        }
    }

    /** 14 · a wrist that climbs from a warm-up to a working rate, once a second, with the
     *  band's own calorie count ticking beside it — the shape a real report has. */
    override fun sportLiveInfo(): Flow<SportLiveInfo> = flow {
        val start = Instant.now()
        var beat = 96.0
        var kcal = 0.0
        while (currentCoroutineContext().isActive) {
            val t = BandTime.interval(Instant.now(), since = start)
            val target = 118 + 26 * (1 - exp(-t / 90)) + 6 * sin(t / 11)
            beat += (target - beat) * 0.3 + Random.nextDouble(-1.5, 1.5)
            kcal += beat / 60 * 0.09
            emit(SportLiveInfo(heartRate = beat.roundToInt(), caloriesKcal = kcal,
                distanceM = (t * 2.6).toInt(), durationSec = t.toInt(), runState = 1))
            delay(1_000)
        }
    }

    /** The simulator stands in for a firmware that carries most of the list. `nuclear
     *  radiation` and the two AI rows are off, as they are on a band without them. */
    override suspend fun readHealthFunctions(): List<BandHealthFunction> {
        requireConnection()
        delay(180)
        val supported = setOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
        return (0..16).map { raw ->
            val isSup = raw in supported
            BandHealthFunction(
                rawValue = raw,
                name = BandHealthFunction.name(forRawValue = raw),
                support = isSup,
                open = isSup && raw != 6)
        }
    }

    /** The simulator's 微体检: a firmware that carries the optical half and none of the
     *  electrode half, so the walk shows what a partial answer looks like. */
    override suspend fun probeHealthGlance(progress: (Int) -> Unit): BandHealthGlance {
        requireConnection()
        var done = 0
        while (done < 100) {
            currentCoroutineContext().ensureActive()
            delay(700)
            done = min(100, done + 5)
            progress(done)
        }
        val support: Long = (1L shl 0) or (1L shl 1) or (1L shl 5) or (1L shl 6) or (1L shl 8) or (1L shl 9)
        val values = listOf(
            "heart rate" to 71.0, "blood oxygen" to 97.0, "stress" to 28.0, "fatigue level" to 2.0,
            "body temperature" to 36.4, "HRV" to 46.0,
        )
        return BandHealthGlance(values = values, functionSupport = support)
    }

    /** The simulator's pulse study, on the real band's timings: 40 s, progress about 3 % a
     *  second, a rate that arrives a few seconds in. The intervals it finishes with carry a
     *  respiratory wobble, so the balance readout has something with real structure to chew
     *  on rather than a straight line. */
    override fun measurePulseStudy(): Flow<PulseStudyStep> = flow {
        if (state != BandConnectionState.connected) throw BandError.NotConnected
        emit(PulseStudyStep.WaitingForContact)
        delay(1_200)
        emit(PulseStudyStep.Contact)
        val intervals = mutableListOf<Double>()
        val seconds = 40
        for (second in 0..seconds) {
            delay(1_000)
            // Sinus arrhythmia: the interval breathes with the wearer at about
            // 0.25 Hz, plus a little beat-to-beat scatter.
            val base = 880.0
            val rr = base + 34 * sin(second * 2 * Math.PI * 0.25) + Random.nextDouble(-12.0, 12.0)
            intervals.add(rr)
            val percent = min(100, (second.toDouble() / seconds * 100).toInt())
            emit(PulseStudyStep.Measuring(percent = percent,
                heartRate = if (second > 3) (60_000 / rr).roundToInt() else null))
        }
        val mean = intervals.sum() / intervals.size
        emit(PulseStudyStep.Finished(PulseStudy(heartRate = (60_000 / mean).roundToInt(),
            intervals = intervals.toList(),
            source = PulseStudy.Source.intervals,
            durationSeconds = seconds,
            vendorHRV = 47)))
    }

    override suspend fun readManualTestData(since: Instant): List<String> {
        requireConnection()
        delay(300)
        val t = DateTimeFormatter.ISO_INSTANT.format(Instant.now().minusSeconds(3600).truncatedTo(java.time.temporal.ChronoUnit.SECONDS))
        return listOf("health glance $t · hr 71 spo2 97 stress 28 fatigue 2 temp 36.4 bp 118/76 hrv 46")
    }

    override suspend fun probeMicroTest(progress: (Int) -> Unit): List<Pair<String, Double>> {
        requireConnection()
        var done = 0
        while (done < 100) {
            currentCoroutineContext().ensureActive()
            delay(600)
            done = min(100, done + 5)
            progress(done)
        }
        return listOf("heart rate" to 71.0, "blood oxygen" to 97.0, "stress" to 28.0, "blood sugar" to 5.4,
            "body temperature" to 36.4, "systolic" to 118.0, "diastolic" to 76.0, "HRV" to 46.0)
    }

    override suspend fun startFindHoop() {
        requireConnection()
        hub.send(BandEvent.FindHoop(FindHoopPhase.enter))
        if (DebugLaunch["NB_DEBUG_FIND_TIMEOUT"] == "1") {
            BandMain.scope.launch {
                delay(400)
                hub.send(BandEvent.FindHoop(FindHoopPhase.timeout))
            }
        }
    }

    override suspend fun stopFindHoop() {
        hub.send(BandEvent.FindHoop(FindHoopPhase.exit))
    }

    override suspend fun readConnectedRSSI(): Int {
        requireConnection()
        return -52
    }

    /** DEBUG · `NB_DEBUG_EDGE=noalarms` walks a NEXTBODY that has never been given one,
     *  which is the only way to see the SWITCH sheet's centred key. */
    override suspend fun readAlarms(): List<BandAlarm> {
        requireConnection()
        delay(180)
        return synchronized(this) {
            if (edge("noalarms")) alarms.clear()
            alarms.toList()
        }
    }

    override suspend fun writeAlarm(alarm: BandAlarm): List<BandAlarm> {
        requireConnection()
        val next = BandAlarmMath.prepared(alarm)
        return synchronized(this) {
            val index = alarms.indexOfFirst { it.id == next.id }
            when {
                index >= 0 -> alarms[index] = next
                BandAlarmMath.isFull(alarms) -> throw BandError.Rejected("THIS NEXTBODY IS FULL")
                else -> alarms.add(next)
            }
            alarms.toList()
        }
    }

    override suspend fun deleteAlarm(alarm: BandAlarm): List<BandAlarm> {
        requireConnection()
        return synchronized(this) {
            alarms.removeAll { it.id == alarm.id }
            alarms.toList()
        }
    }

    override suspend fun probeCapabilitySweep(): List<String> {
        requireConnection()
        delay(240)
        return listOf(
            "model · MOCK-G70 hw MOCK-1 cpu 1",
            "types · heart=1 sleep=3 ecg=2 temp=2 glucose=0 bp=0 oxygen=1 hrv=1",
            "function.female=0",
            "health · stress=open HRV=open body composition=open · not: blood glucose, AI chat",
            "female · refused",
            "gsensor · 12 packets in 6.0s x -18…22 y -4…9 z 980…1024 steps 0",
            "gsensor.adc · 0 bytes",
        )
    }

    private fun requireConnection() {
        if (state != BandConnectionState.connected) throw BandError.NotConnected
    }

    companion object {
        /** Two simulator bands, so the two-NEXTBODY set (9-0) can be walked without hardware. */
        const val firstHoop = "C4-2E-8F-1A-73-9D"
        const val secondHoop = "8E-41-C0-2B-77-1F"

        private fun hhmm(hour: Int, minute: Int) = String.format(java.util.Locale.US, "%02d:%02d", hour, minute)

        /** `DebugEdge.on(_:)` — DEBUG builds only, from the launch extra `NB_DEBUG_EDGE`. */
        private fun edge(name: String): Boolean = DebugLaunch["NB_DEBUG_EDGE"] == name
    }
}
