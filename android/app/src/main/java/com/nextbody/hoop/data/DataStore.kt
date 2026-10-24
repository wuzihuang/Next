package com.nextbody.hoop.data

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandBattery
import com.nextbody.hoop.services.DemoAccount
import com.nextbody.hoop.band.BandCapabilities
import com.nextbody.hoop.band.BandIdentity
import com.nextbody.hoop.band.BatteryDrainMath
import com.nextbody.hoop.band.BatteryLog
import com.nextbody.hoop.band.BatteryLogStore
import com.nextbody.hoop.band.BatteryObservation
import com.nextbody.hoop.band.CompositionScan
import com.nextbody.hoop.band.MealResponseIndex
import com.nextbody.hoop.band.SleepStageRun
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.band.VitalsClock
import com.nextbody.hoop.band.WearRun
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.DistantPast
import com.nextbody.hoop.model.FuelState
import com.nextbody.hoop.model.Goal
import com.nextbody.hoop.model.LoadPoint
import com.nextbody.hoop.model.MacroSlot
import com.nextbody.hoop.model.MeasurementRecord
import com.nextbody.hoop.model.MeasurementSource
import com.nextbody.hoop.model.NightInputs
import com.nextbody.hoop.model.OvernightOxygenPoint
import com.nextbody.hoop.model.ReserveDrivers
import com.nextbody.hoop.model.ReserveSample
import com.nextbody.hoop.model.BodyBatteryConfidence
import com.nextbody.hoop.model.SleepHRVPoint
import com.nextbody.hoop.model.SleepInterval
import com.nextbody.hoop.model.SleepRespirationPoint
import com.nextbody.hoop.model.SleepScore
import com.nextbody.hoop.model.SleepScoreLoadState
import com.nextbody.hoop.model.SleepSummary
import com.nextbody.hoop.model.TickFreshness
import com.nextbody.hoop.model.TrainingSegment
import com.nextbody.hoop.model.addingDays
import com.nextbody.hoop.model.addingMinutes
import com.nextbody.hoop.model.addingTimeInterval
import com.nextbody.hoop.model.addingYears
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.localHour
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.settingHour
import com.nextbody.hoop.model.timeIntervalSince
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Swift's `Double??` for amendMeal's micronutrients: `null` = keep the row's value,
 * `Replace(null)` = clear it, `Replace(x)` = set it.
 */
data class Replace<out T>(val value: T?)

/** `seedNight`'s `(summary:, ticks:)` tuple. */
data class SeededNight(val summary: SleepSummary, val ticks: List<VitalSample>)

/**
 * Everything the screens read. Backed by Supabase in production. On the simulator it is
 * seeded with the exact numbers printed on the design boards so the flow is walkable
 * without a band; a real phone starts empty and fills in from the server and the wrist.
 *
 * Port notes:
 * - Swift's `@MainActor final class … static let shared`; here a Kotlin `object` (use
 *   `DataStore` or `DataStore.shared`). Touch it from the main thread only.
 * - Every `@Published` property is Compose state. Values are data classes: to change a
 *   field, assign a modified copy (`today = today.copy(eIn = 1240.0)`), never mutate the
 *   instance held in state — Compose would not see it, and other readers share it.
 * - `Band.allowsSeed` must be decided before the first touch of this object.
 */
object DataStore {
    val shared: DataStore get() = this

    private val scope = MainScope()

    var today: DailyMetrics by mutableStateOf(DailyMetrics(day = UserDay.containing(Instant.now())))
    var history: List<DailyMetrics> by mutableStateOf(emptyList())
    /** ADR 0008 · the settled sleep score per wake-day, keyed by `UserDay.key`. Thirty rows
     *  of smallints, refreshed after settlement and cached with their account's snapshot. */
    var sleepScores: Map<String, SleepScore> by mutableStateOf(emptyMap())
    var sleepScoreLoadState: SleepScoreLoadState by mutableStateOf(SleepScoreLoadState.idle)
    var meals: List<MealEntry> by mutableStateOf(emptyList())
    /** The window 12's WEEK view reads. Today's list stays in `meals` so 09 is untouched. */
    var recentMeals: List<MealEntry> by mutableStateOf(emptyList())
    var weighIns: List<WeighIn> by mutableStateOf(emptyList())
    /** ADR 0010 · 主动测量记录，最近的在前。「我的」页那块 MEASUREMENTS 取前三条，测量记录页
     *  列全部。⚠️ 只有成功完成的测量在这里；体重录入和被动 tick 不进这个数组。 */
    var measurements: List<MeasurementRecord> by mutableStateOf(emptyList())
    /** 10E · 成分页读的每一行 `body_composition`。不限 `device_bia`——秤和手录同样是一次体脂点。 */
    var compositionScans: List<CompositionScan> by mutableStateOf(emptyList())
    var band: BandState by mutableStateOf(if (Band.allowsSeed) BandState.mock else BandState.unknown)
    /** Every battery packet and charge switch this phone kept. The device ring opens it. */
    var batteryLog: List<BatteryObservation> by mutableStateOf(emptyList())
    /** Session-local freshness guard: cloud hydration must not overwrite a BLE observation. */
    var bandObservationRevision: Int = 0
        private set

    var profile: Profile by mutableStateOf(if (Band.allowsSeed) Profile.mock else Profile.blank)
    /** F3 rule 09 · the moment of the last readOriginData that succeeded. nil until one has:
     *  a phone that has never synced says so, it does not say "12 MIN AGO". */
    var lastSync: Instant? by mutableStateOf(
        if (Band.allowsSeed) Instant.now().addingTimeInterval(-12.0 * 60) else null)
    /** Earliest bind or wrist tick on this account. WITH YOU counts user days from here. */
    var boundAt: Instant? by mutableStateOf(
        if (Band.allowsSeed) UserDay.containing(Instant.now()).adding(-84).start else null)
    /** 04 · the HR / STRESS row under the readout, and the tick it came from. 13 · the age
     *  of that tick is what decides whether the numbers are shown, dimmed, or dashed. */
    var vitals: LiveVitals by mutableStateOf(if (Band.allowsSeed) LiveVitals.mock else LiveVitals())

    /** 12 · what this NEXTBODY reports it can do, as last stored. The device page and 07's
     *  capabilities() gate read this so they are right before the band answers, and still
     *  right when it is out of range. */
    var capabilities: BandCapabilities by mutableStateOf(BandCapabilities())
    var capabilitiesReadAt: Instant? by mutableStateOf(null)
    var isOffline: Boolean by mutableStateOf(false)
    /** Wrist optical meal-response points, last ~30 user days. Dedicated series, never origin ticks. */
    var mealResponsePoints: List<MealResponseIndex.Point> by mutableStateOf(emptyList())
    /** True when today's vendor table had rows but every value was a zero / empty slot. */
    var mealResponseZerosToday: Boolean by mutableStateOf(false)

    // 11 · the three tiles. Two net changes over twelve weeks and one absolute value,
    // which is why the third one is labelled apart from the other two.
    var netFatMass12w: Double? by mutableStateOf(null)
    var netLeanMass12w: Double? by mutableStateOf(null)
    var bodyFatPercent: Double? by mutableStateOf(null)

    var mealReceipt: MealReceipt? by mutableStateOf(null)

    /** Eight seconds is the whole of it. A receipt that outlives the glance becomes a
     *  second chrome element nobody asked for, and an undo with no memory of the tap is
     *  worse than no undo. */
    const val receiptLifetime: Double = 8.0

    private const val seedBandIdentifier = "C4-2E-8F-1A-73-9D"

    init {
        // The seeded demo account is a returning user: the gate was walked, the band is
        // bound, and the app reconnects to it the way it would on any later launch.
        // ⚠️ Simulator only. On a device a made-up identifier makes the app believe a band
        // is bound before the gate was ever walked, and every launch would try to reconnect.
        if (Band.allowsSeed && Ports.boundBand.identifier == null) Ports.boundBand.identifier = seedBandIdentifier
        // TODO(port): DEBUG `NB_DEBUG_RELEASED_SLOT` / `NB_DEBUG_SECOND_HOOP` seed DeviceSlots
        // (slot A/B bindings) for the two-NEXTBODY device page. DeviceSlots is not ported yet.
        // Earlier device builds wrote that seed; a real phone carrying it is not bound to anything.
        if (!Band.allowsSeed && Ports.boundBand.identifier == seedBandIdentifier) Ports.boundBand.forget()
        // The board's numbers exist so the flow is walkable on a simulator with no band.
        // On a device every one of them would be a figure with no source behind it — F2
        // rule 05 · unknown is "——", never a plausible number — so the day starts empty and
        // fills in from daily_results and from the band, or stays a dash.
        if (Band.allowsSeed) {
            var seededToday = seedToday()
            var seededHistory = seedHistory()
            meals = MealEntry.seed
            weighIns = WeighIn.seed
            measurements = MeasurementRecord.seed
            compositionScans = compositionScans(measurements)
            mealResponsePoints = seedMealResponse()
            val scores = seedSleepScores()
            sleepScores = scores
            sleepScoreLoadState = SleepScoreLoadState.ready
            seededToday = seededToday.copy(sleepScore = scores[seededToday.day.key])
            seededHistory = seededHistory.map { it.copy(sleepScore = scores[it.day.key]) }
            today = seededToday
            history = seededHistory
            batteryLog = BatteryLog.seed(now = Instant.now(), percent = band.batteryPercent ?: 82)
        } else {
            today = DailyMetrics(day = UserDay.containing(Instant.now()))
            Ports.homeSnapshot.hydrate(this)
            hydrateBatteryLog()
        }
        if (BuildConfig.DEBUG) {
            if (Band.allowsSeed && DebugEnv["NB_DEBUG_SLEEP_EVIDENCE"] == "1") seedSleepEvidenceForUITests()
            if (Band.allowsSeed && DebugEnv["NB_DEBUG_SLEEP_CONTRIBUTORS"] == "1") seedSleepContributorsForUITests()
        }
        Ports.widgetGlance.publish(this)
    }

    fun applyBandObservation(identity: BandIdentity? = null, battery: BandBattery? = null) {
        if (identity == null && battery == null) return
        val next = band.copy()
        if (identity != null) {
            next.name = identity.name
            next.mac = identity.bleIdentifier
            next.firmware = identity.firmware
        }
        val settled = battery?.settled
        if (settled != null) next.applyBattery(settled)
        band = next
        if (settled != null) {
            recordBattery(settled, connected = band.connected)
            Ports.notificationReach.evaluate(this)
        }
        bandObservationRevision += 1
    }

    fun recordBandLink(connected: Boolean) {
        val was = band.connected
        band = band.copy(connected = connected)
        if (was == connected) return
        Ports.notificationReach.stampDisconnect(connected)
        Ports.notificationReach.evaluate(this)
        if (connected) {
            // A reconnect must not stamp the last packet at NOW. That packet is hours
            // old and sits on the first fresh read as a noon cliff.
            batteryLog = BatteryLog.record(
                batteryLog, at = Instant.now(),
                isPercent = band.lastBattery?.isPercent ?: (band.batteryPercent != null),
                percent = null, level = null,
                charge = BatteryObservation.Charge.fromRaw(band.chargeState.raw) ?: BatteryObservation.Charge.unknown,
                connected = true)
            persistBatteryLog()
            return
        }
        val last = band.lastBattery
        if (last != null) {
            recordBattery(last, connected = false)
        } else {
            // No packet has arrived, so this row carries no reading — and claiming percent
            // here would cast a vote in the plot's unit ballot on behalf of a bars-only band.
            batteryLog = BatteryLog.record(
                batteryLog, at = Instant.now(), isPercent = band.batteryPercent != null,
                percent = band.batteryPercent, level = null,
                charge = BatteryObservation.Charge.fromRaw(band.chargeState.raw) ?: BatteryObservation.Charge.unknown,
                connected = false)
            persistBatteryLog()
        }
    }

    fun hydrateBatteryLog() {
        if (Band.allowsSeed) return
        val loaded = BatteryLogStore.load(owner = batteryOwner)
        val cleaned = loaded.filter { !BatteryDrainMath.isGhost(it) }
        if (batteryLog.isEmpty()) {
            batteryLog = cleaned
            if (cleaned.size != loaded.size) persistBatteryLog()
            return
        }
        val stripped = batteryLog.filter { !BatteryDrainMath.isGhost(it) }
        if (stripped.size != batteryLog.size) {
            batteryLog = stripped
            persistBatteryLog()
        }
    }

    private val batteryOwner: String
        get() {
            val account = Ports.supabase.currentUserIdSnapshot() ?: "none"
            val binding = Ports.boundBand.identifier ?: "none"
            return "$account.$binding"
        }

    private fun recordBattery(battery: BandBattery, connected: Boolean) {
        hydrateBatteryLog()
        if (battery.chargeState == BandBattery.ChargeState.unknown) return
        batteryLog = BatteryLog.record(
            batteryLog,
            at = Instant.now(),
            isPercent = battery.isPercent,
            percent = battery.percent,
            level = battery.level,
            charge = BatteryObservation.Charge.fromRaw(battery.chargeState.raw) ?: BatteryObservation.Charge.unknown,
            connected = connected)
        persistBatteryLog()
    }

    private fun persistBatteryLog() {
        if (Band.allowsSeed) return
        BatteryLogStore.save(batteryLog, owner = batteryOwner)
    }

    /** Every write to a @Published property republishes the whole store to its ~40 observers,
     *  equal value or not. Band sync confirms the link many times a minute; only a flip counts. */
    fun setBandConnected(connected: Boolean) {
        if (band.connected == connected) return
        band = band.copy(connected = connected)
    }

    /** Reserve, explanations and curve always come from the same settlement. Live heart
     *  callbacks remain measurements; they cannot publish a second reserve calculation. */
    val bodyBatteryNow: Int? get() = today.bodyBatteryForDisplay()

    val todayForDisplay: DailyMetrics
        get() = today.copy(bodyBattery = today.bodyBatteryForDisplay())

    /** Header flame. Local ticks can light today before the next settle; yesterday's
     *  settled run/miss never cools an open day. */
    val wearFlame: WearRun.Flame
        get() {
            val todayWorn = WearRun.isWornDay(samples = today.vitalsCurve, day = today.day, now = Instant.now()) ||
                today.worn == true
            val yesterday = metrics(today.day.adding(-1))
            return WearRun.display(
                todayWorn = todayWorn,
                yesterday = yesterday?.let {
                    WearRun.yesterday(
                        worn = it.worn,
                        run = it.wearRun,
                        miss = it.wearMiss,
                        localWorn = WearRun.isWornDay(samples = it.vitalsCurve, day = it.day, now = it.day.end))
                })
        }

    /** Today's merged row, otherwise the history row. The heat map used to look only
     *  at `history`, so the current user day stayed GREY_NOTHING while Fuel already
     *  had the live balance. (Swift `metrics(for:)`.) */
    fun metrics(day: UserDay): DailyMetrics? {
        if (today.day == day) return today
        return history.firstOrNull { it.day == day }
    }

    // DEBUG fixtures ---------------------------------------------------------------------

    private fun seedSleepContributorsForUITests() {
        val wake = Instant.now().settingHour(4, 25, 0)
        val start = wake.addingTimeInterval(-325.0 * 60)
        val score = SleepScore(score = 56, duration = 41, inputs = mapOf(
            "contributor_policy" to 3.0, "duration_min" to 289.0, "duration_recorded" to 1.0,
            "sleep_elapsed_minutes" to 325.0, "sleep_recorded_minutes" to 325.0,
            "unstaged_minutes" to 0.0, "stage_coverage" to 1.0, "bed_offset" to 300.0,
            "efficiency_pct" to 88.92, "awake_min" to 36.0, "wakes" to 1.0,
            "deep_min" to 66.0, "deep_pct" to 22.8, "rem_min" to 59.0, "rem_pct" to 20.4,
            "light_pct" to 56.7, "midpoint_min" to 102.5,
            "score_total_sleep" to 40.83, "score_efficiency" to 100.0,
            "score_restfulness" to 77.85, "score_rem" to 65.56,
            "score_deep" to 100.0, "score_timing" to 100.0,
            "weight_total_sleep" to 40.0, "weight_efficiency" to 10.0,
            "weight_restfulness" to 10.0, "weight_rem" to 15.0, "weight_deep" to 15.0,
            "weight_latency" to 5.0, "weight_timing" to 5.0,
            "duration_score_cap" to 56.33, "duration_cap_applied" to 1.0,
        ), version = "sleep-v3.0", computedAt = Instant.now())
        val sleep = SleepSummary(totalMinutes = 325, deepMinutes = 66, lightMinutes = 164,
            wakeCount = 1, line = listOf(
                SleepStageRun(stage = 0, minutes = 66, offsetMinutes = 0),
                SleepStageRun(stage = 1, minutes = 100, offsetMinutes = 66),
                SleepStageRun(stage = 4, minutes = 36, offsetMinutes = 166),
                SleepStageRun(stage = 1, minutes = 64, offsetMinutes = 202),
                SleepStageRun(stage = 2, minutes = 59, offsetMinutes = 266),
            ), sleepStart = start, wakeAt = wake)
        val scores = sleepScores.toMutableMap()
        for (back in 0 until 30) {
            if (back == 11 || back == 19) continue
            scores[today.day.adding(-back).key] = score
        }
        sleepScores = scores
        today = today.copy(sleep = sleep, sleepScore = score)
        sleepScoreLoadState = SleepScoreLoadState.ready
    }

    /** Deterministic simulator fixture for missing evidence and peaks above the old ruler.
     *  It never runs on a physical band or uploads measurements. */
    private fun seedSleepEvidenceForUITests() {
        val wake = Instant.now().settingHour(12, 39, 0)
        val start = wake.addingTimeInterval(-751.0 * 60)
        val minutes = (0 until 129).toList() + (217 until 751).toList()
        val hrvMinutes = (0 until 82).toList() + (491 until 751).toList()
        val score = SleepScore(score = 87, duration = 77, architecture = 80, recovery = 99,
            inputs = mapOf("duration_min" to 663.0, "deep_pct" to 24.6, "light_pct" to 61.4, "rem_pct" to 13.3,
                "rem_min" to 88.0, "wakes" to 2.0, "hrv_ms" to 67.4, "hrv_base" to 40.0,
                "rhr" to 54.0, "rhr_base" to 60.0, "spo2_min" to 96.0, "respiration" to 16.9,
                "hrv_sample_count" to 342.0, "hrv_coverage" to 342.0 / 663,
                "hrv_expected_minutes" to 663.0, "hrv_longest_gap_min" to 274.0,
                "rhr_sample_count" to 133.0, "rhr_coverage" to 1.0,
                "rhr_expected_minutes" to 663.0, "rhr_longest_gap_min" to 0.0,
                "spo2_sample_count" to 660.0, "spo2_coverage" to 660.0 / 663,
                "spo2_expected_minutes" to 663.0, "spo2_longest_gap_min" to 3.0,
                "respiration_sample_count" to 661.0, "respiration_coverage" to 661.0 / 663,
                "respiration_expected_minutes" to 663.0, "respiration_longest_gap_min" to 2.0,
                "bed_offset" to 368.0, "baseline_nights" to 3.0, "baseline_hrv_nights" to 2.0, "baseline_rhr_nights" to 3.0,
                "hrv_personal_weight" to 0.0, "rhr_personal_weight" to 0.0),
            version = "sleep-v1.2", computedAt = Instant.now())
        val sleep = SleepSummary(totalMinutes = 663, deepMinutes = 163, lightMinutes = 407,
            wakeCount = 2, sleepStart = start, wakeAt = wake,
            spo2 = minutes.drop(3).map { OvernightOxygenPoint(ts = start.addingTimeInterval(it.toDouble() * 60), percent = 97) },
            respiration = minutes.drop(2).map {
                SleepRespirationPoint(ts = start.addingTimeInterval(it.toDouble() * 60), breathsPerMinute = 16.9)
            },
            hrv = hrvMinutes.mapIndexed { index, minute ->
                SleepHRVPoint(ts = start.addingTimeInterval(minute.toDouble() * 60), rmssdMS = if (index == 0) 168.0 else 67.0)
            },
            intervals = listOf(SleepInterval(start = start, end = start.addingTimeInterval(129.0 * 60)),
                SleepInterval(start = start.addingTimeInterval(217.0 * 60), end = wake)))
        sleepScores = sleepScores + (today.day.key to score)
        today = today.copy(sleep = sleep, sleepScore = score)
        sleepScoreLoadState = SleepScoreLoadState.ready
    }

    /**
     * 11 · DELETE EVERYTHING. By the time this runs the account is gone from the server,
     * so every number still held here is an orphan — and the gate behind it is a sign-in
     * screen that would be drawn over yesterday's readout until the app is killed.
     * Back to the state a phone is in before any account: dashes, not the seeded board.
     * ⚠️ `isOffline` is not the account's, it is the radio's — Reachability owns it, and
     * clearing it here would print ONLINE at the gate of a phone in a lift.
     */
    fun purge() {
        clearAccountDisplay()
        Ports.homeSnapshot.removeAll()
        Ports.widgetGlance.clear()
    }

    /** Signing out clears visible identity and readings, while account-owned disk data
     *  and pending operations remain available when their owner signs in again. */
    fun clearAccountDisplay() {
        Ports.widgetGlance.clear()
        bandObservationRevision = 0
        today = DailyMetrics(day = UserDay.containing(Instant.now()))
        history = emptyList()
        sleepScores = emptyMap()
        sleepScoreLoadState = SleepScoreLoadState.idle
        meals = emptyList()
        recentMeals = emptyList()
        weighIns = emptyList()
        measurements = emptyList()
        compositionScans = emptyList()
        mealResponsePoints = emptyList()
        mealResponseZerosToday = false
        band = BandState.unknown
        profile = Profile.blank
        lastSync = null
        boundAt = null
        vitals = LiveVitals()
        capabilities = BandCapabilities()
        capabilitiesReadAt = null
        netFatMass12w = null
        netLeanMass12w = null
        bodyFatPercent = null
        batteryLog = emptyList()
        Ports.repository.resetBootstrap()
    }

    /** Swift `static func compositionScans(from:)`. */
    fun compositionScans(records: List<MeasurementRecord>): List<CompositionScan> =
        records.mapNotNull { record ->
            val scan = record.detail as? MeasurementRecord.BodyScan ?: return@mapNotNull null
            CompositionScan(
                id = record.id,
                at = record.at,
                bodyFatPercent = scan.bodyFatPercent,
                fatMassKg = scan.fatMassKg,
                leanMassKg = scan.leanMassKg,
                bmrKcal = scan.bmrKcal?.toDouble(),
                inputWeightKg = scan.inputWeightKg,
                muscleMassKg = scan.muscleMassKg,
                bodyWaterPercent = scan.bodyWaterPercent,
                boneMassKg = scan.boneMassKg,
                proteinPercent = scan.proteinPercent,
            )
        }

    fun rememberBodyScan(record: MeasurementRecord) {
        measurements = listOf(record) + measurements
        val scan = compositionScans(listOf(record)).firstOrNull() ?: return
        compositionScans = listOf(scan) + compositionScans.filter { it.id != scan.id }
    }

    // Seeds ------------------------------------------------------------------------------

    /** The board's 64-bit LCG. Swift `UInt64` wrapping arithmetic; Kotlin `Long` wraps the same
     *  way, and `ushr` is the unsigned shift. */
    private class Lcg(var seed: Long) {
        fun next(modulus: Long): Double {
            seed = seed * 6364136223846793005L + 1442695040888963407L
            return ((seed ushr 33) % modulus).toDouble() / modulus.toDouble()
        }
    }

    /** Board 04 · 01 默认 — the screen the whole product is measured against.
     *  `VitalsClock.now` so `NB_DEBUG_NOW` and the seed ticks share one evening, not 03:00. */
    fun seedToday(): DailyMetrics {
        val now = VitalsClock.now
        val m = DailyMetrics(day = UserDay.containing(now))
        m.trainingLoad = 12.4
        m.targetLoad = 14.5
        m.optimalZone = 13.0..16.0
        m.zoneMinutes = listOf(46, 38, 22, 15, 5)
        m.bbWake = 72
        m.bodyBattery = 72
        // 13 · the four rows the board prints, and they add up to the 72 above.
        // 13A · scheme 1: last night +38 from 46, the day spends −12, now is 72.
        m.reserveDrivers = ReserveDrivers(lastNight = 38.0, awake = -4.0, movement = -6.0,
            stress = -2.0, anchor = 46,
            dayCharge = 38.0, nightCharge = 38.0,
            wakeAt = m.day.start.settingHour(7, 12, 0),
            observedAt = now, confidence = BodyBatteryConfidence.medium,
            algoVersion = "bb-2.1")
        m.nightInputs = NightInputs(hrv = 54.0, hrvBase = 61.0, rhr = 51.0, rhrBase = 48.0,
            rhrNights = 9, multiplier = 0.88)
        m.bmr = 1480.0
        m.eActive = 320.0
        m.eTrain = 60.0
        m.eTrainPlan = 480.0
        m.eOutNow = 1860.0
        m.activeForecast = 260.0
        m.eOutFull = 2280.0
        m.eIn = 1240.0
        m.balance = -620.0
        m.targetIn = 2280.0
        m.targetBasis = 2280.0
        // #29 · the parts 09 prints under the allowance: resting (a scan's) plus activity so far.
        m.bmrFull = 1960.0
        m.restingSource = "BODY_SCAN"
        m.restingMeasuredAt = m.day.start
        m.goalOffset = 0.0
        m.protein = MacroSlot(target = 145, eaten = 84)
        m.carb = MacroSlot(target = 290, eaten = 132)
        m.fat = MacroSlot(target = 60, eaten = 42)
        m.nextMeal = 1040.0
        m.weightKg = 68.4
        m.fatKg = 12.9
        m.leanKg = 55.5
        m.fatSource = MeasurementSource.measured
        m.fatEmaDelta7d = -0.42
        m.leanEmaDelta7d = 0.18
        m.confidence = com.nextbody.hoop.model.Confidence.medium
        m.scans7d = 5
        m.logged7d = 6
        m.fuelState = FuelState.Partial(slots = 3)
        m.bandCoverage = 0.86
        m.worn = true
        m.wearRun = 4
        m.wearMiss = 0
        m.asOf = now
        // The ticks the board's 72 was made of: five minutes apart from the earlier of
        // the user-day cut and last night's bed time, so the sleep page has RMSSD to plot.
        var ticks = mutableListOf<VitalSample>()
        val lcg = Lcg(0x2545F4914F6CDD1DL)
        fun rnd(): Double = lcg.next(1_000)
        val wakeAt = now.settingHour(7, 12, 0)
        val sleepStart = wakeAt.addingTimeInterval(-432.0 * 60)
        var t = minOf(m.day.start, sleepStart)
        while (t <= now) {
            val hour = t.localHour()
            val offWrist = hour == 13
            val asleep = t >= sleepStart && t < wakeAt
            if (!offWrist) {
                // 04B · the second page reads the same ticks: a skin temperature that climbs
                // through the day, and the five minutes' steps, kcal and metres — heavy in
                // the 18:00 session, nothing while asleep.
                val session = hour == 18
                val steps = if (asleep) 0 else if (session) (120 + rnd() * 60).toInt() else (rnd() * 40).toInt()
                val met = if (asleep) 1.0 else if (session) 6.0 else (if (steps > 0) 1.8 else 1.0)
                ticks.add(VitalSample(
                    ts = t,
                    hr = ((if (asleep) 49.0 else 68.0) + rnd() * (if (asleep) 6 else 22)).toInt(),
                    stress = ((if (asleep) 12.0 else 26.0) + rnd() * (if (asleep) 8 else 30)).toInt(),
                    // ⚠️ Wrist skin, not core body: the night sits under the covers and runs
                    // warmer than the exposed daytime arm. 35.9 / 36.4 / 36.7 here taught the
                    // simulator a core-temperature number for a value the band records at 33.
                    temp = (if (asleep) 33.8 else if (session) 33.1 else 33.4) + rnd() * 0.2,
                    steps = steps,
                    met = met,
                    vendorCalories = steps.toDouble() * 0.04 + (if (asleep) 0.2 else 0.6),
                    dis = steps.toDouble() * 0.72,
                    hrv = (if (asleep) 48.0 else 38.0) + rnd() * (if (asleep) 18 else 16)))
            }
            t = t.addingTimeInterval(300.0)
        }
        if (BuildConfig.DEBUG && DebugEdgeFlag.on("restonly")) {
            m.eActive = 0.0
            m.eTrain = 0.0
            m.eOutNow = m.bmr
            m.activeForecast = 0.0
            m.eOutFull = m.bmrFull
            m.trainingLoad = 0.0
            m.zoneMinutes = listOf(0, 0, 0, 0, 0)
            ticks = ticks.map { sample ->
                VitalSample(ts = sample.ts, hr = sample.hr, stress = sample.stress,
                    temp = sample.temp, steps = 0, met = 1.0,
                    vendorCalories = sample.vendorCalories, dis = 0.0, hrv = sample.hrv,
                    hrvValid = sample.hrvValid, hrvObservedAt = sample.hrvObservedAt)
            }.toMutableList()
        }
        m.vitalsCurve = ticks
        // Peak sits on this user day at 07:12, not on the calendar clock of `Date()`
        // — before 04:00 that clock is tomorrow morning.
        m.reserveCurve = seedReserveCurve(
            day = m.day, now = now,
            wakeAt = m.day.start.addingTimeInterval(3.0 * 3600 + 12 * 60),
            peak = 84, nowValue = 72, anchor = 46)
        // 04B · SLEEP · 7H 12M, DEEP 1H 48M, 2 WAKES — the board's card, with the band's own
        // line behind it (total = deep + light; the two wakes are minutes off the count).
        val spo2 = mutableListOf<OvernightOxygenPoint>()
        var minute = 0
        while (minute < 432) {
            val wave = sin(minute.toDouble() / 80)
            var percent = 96 + (wave * 2).rounded().toInt()
            if (minute == 180) percent = 91
            spo2.add(OvernightOxygenPoint(
                ts = sleepStart.addingTimeInterval(minute.toDouble() * 60),
                percent = min(100, max(50, percent))))
            minute += 5
        }
        val respiration = mutableListOf<SleepRespirationPoint>()
        minute = 0
        while (minute < 432) {
            val wave = sin(minute.toDouble() / 55)
            respiration.add(SleepRespirationPoint(
                ts = sleepStart.addingTimeInterval(minute.toDouble() * 60),
                breathsPerMinute = 13.6 + wave * 2.4))
            minute += 5
        }
        m.sleep = SleepSummary(totalMinutes = 432, deepMinutes = 108, lightMinutes = 324, wakeCount = 2,
            line = listOf(SleepStageRun(stage = 1, minutes = 84), SleepStageRun(stage = 0, minutes = 60),
                SleepStageRun(stage = 1, minutes = 110), SleepStageRun(stage = 4, minutes = 4),
                SleepStageRun(stage = 0, minutes = 48), SleepStageRun(stage = 1, minutes = 130),
                SleepStageRun(stage = 4, minutes = 4)),
            sleepStart = sleepStart, wakeAt = wakeAt, spo2 = spo2,
            respiration = respiration)
        val stepTotal = ticks.sumOf { it.steps ?: 0 }
        val sessionAt = m.day.start.addingTimeInterval(14.0 * 3600)
        m.segments = listOf(
            TrainingSegment(at = sessionAt, name = "STRENGTH", minutes = 45, avgHR = 132,
                steps = 640, delta = 3.2, allDay = false),
            TrainingSegment(at = m.day.start, name = "ALL DAY", minutes = null, avgHR = null,
                steps = stepTotal, delta = 9.2, allDay = true),
        )
        val curve = mutableListOf<LoadPoint>()
        var cursor = m.day.start
        while (cursor <= now) {
            val hours = cursor.timeIntervalSince(m.day.start) / 3600
            val load: Double = if (hours < 5) {
                1.0 * (hours / 5)
            } else if (hours < 14) {
                1.0 + 8.2 * ((hours - 5) / 9)
            } else {
                min(12.4, 9.2 + 3.2 * min(1.0, (hours - 14) / 1.5))
            }
            curve.add(LoadPoint(ts = cursor, load = load))
            cursor = cursor.addingTimeInterval(1800.0)
        }
        if (curve.lastOrNull()?.let { abs(it.load - 12.4) > 0.05 } ?: true) {
            curve.add(LoadPoint(ts = now, load = 12.4))
        }
        m.loadCurve = curve
        return m
    }

    /**
     * 12 weeks of history so the heat map on 11 · Profile has something honest to draw.
     * ADR 0008 · thirty nights of settled sleep score, so the sleep board's day, week and
     * month windows are walkable on a simulator with no band and no session. Two nights are
     * deliberately absent — the month bar chart has to be able to show *which* night is
     * missing — and the run is left mid-calibration so the "typical adults for now" note is
     * on screen rather than only in the code.
     * ⚠️ Simulator only, behind `Band.allowsSeed`, like every other number in this file.
     */
    fun seedSleepScores(): Map<String, SleepScore> {
        val today = UserDay.containing(Instant.now())
        val lcg = Lcg(0x2545F4914F6CDD1DL)
        fun rnd(): Double = lcg.next(10_000)
        val out = LinkedHashMap<String, SleepScore>()
        for (back in 29 downTo 0) {
            // Two nights the band was not worn.
            if (back == 11 || back == 19) { rnd(); continue }
            val duration = (58 + rnd() * 42).toInt()
            val architecture = (52 + rnd() * 46).toInt()
            // Recovery is the group left dragging, so the week and month hero has something
            // true to name in its right foot.
            val recovery = (40 + rnd() * 34).toInt()
            val regularity: Int? = if (back < 16) (62 + rnd() * 38).toInt() else null
            val groups: List<Pair<Int?, Int>> = listOf(duration to 25, architecture to 25,
                recovery to 35, regularity to 15)
            val present = groups.filter { it.first != null }
            val total = present.fold(0.0) { acc, g -> acc + g.first!!.toDouble() * g.second.toDouble() } /
                present.fold(0.0) { acc, g -> acc + g.second.toDouble() }
            val minutes = (300 + (rnd() * 190).toInt()).toDouble()
            val inputs = LinkedHashMap<String, Double>()
            inputs["duration_min"] = minutes
            inputs["deep_pct"] = 14 + rnd() * 10
            inputs["light_pct"] = 52 + rnd() * 12
            inputs["wakes"] = (rnd() * 4).toInt().toDouble()
            inputs["hrv_ms"] = 28 + rnd() * 18
            inputs["rhr"] = 52 + rnd() * 10
            inputs["bed_offset"] = 300 + rnd() * 90
            // The habit is learned from the third prior night; the schedule chart's band
            // needs it to draw.
            if (back < 27) inputs["bed_median"] = 342.0
            // Nights the band filed no stage line have no REM to report, which is what the
            // renormalised proportions bar is there to survive.
            if (back % 5 != 0) inputs["rem_pct"] = 18 + rnd() * 9
            if (back % 3 != 0) inputs["spo2_min"] = 90 + rnd() * 7
            if (back % 4 != 0) inputs["respiration"] = 12 + rnd() * 5
            out[today.adding(-back).key] = SleepScore(
                score = total.rounded().toInt(),
                duration = duration, architecture = architecture,
                recovery = recovery, regularity = regularity,
                personalWeight = 0.43, inputs = inputs, version = "sleep-v1")
        }
        return out
    }

    /** One seeded night: the band's window, and a skin tick every five minutes inside it.
     *  ⚠️ Simulator only, behind `Band.allowsSeed`, like every other number in this file. */
    fun seedNight(day: UserDay, hours: Double, mean: Double, rnd: () -> Double): SeededNight {
        // 23:30 local: the user day starts at midnight, so the night straddles its start
        // the way a real one does.
        val start = day.start.addingTimeInterval(-30.0 * 60)
        val minutes = (hours * 60).toInt()
        val wake = start.addingTimeInterval(minutes.toDouble() * 60)
        val ticks = mutableListOf<VitalSample>()
        for (slot in 0 until (minutes / 5)) {
            ticks.add(VitalSample(
                ts = start.addingTimeInterval(slot.toDouble() * 300),
                hr = (50 + rnd() * 6).toInt(),
                stress = (12 + rnd() * 8).toInt(),
                temp = mean + (rnd() - 0.5) * 0.3,
                hrv = 44 + rnd() * 14))
        }
        val deep = (minutes.toDouble() * 0.2).toInt()
        val spo2 = mutableListOf<OvernightOxygenPoint>()
        var minute = 0
        while (minute < minutes) {
            val wave = sin(minute.toDouble() / 80)
            val percent = min(100, max(88, 95 + (wave * 2).rounded().toInt()))
            spo2.add(OvernightOxygenPoint(
                ts = start.addingTimeInterval(minute.toDouble() * 60),
                percent = percent))
            minute += 15
        }
        return SeededNight(
            SleepSummary(totalMinutes = minutes, deepMinutes = deep,
                lightMinutes = minutes - deep, wakeCount = (rnd() * 3).toInt(),
                sleepStart = start, wakeAt = wake, spo2 = spo2),
            ticks)
    }

    /** Scheme A seed: night charges from the 04:00 anchor to the morning peak,
     *  then the day spends down to NOW. Five-minute ticks, same grid as the engine. */
    fun seedReserveCurve(day: UserDay, now: Instant, wakeAt: Instant,
                         peak: Int, nowValue: Int, anchor: Int): List<ReserveSample> {
        val samples = mutableListOf<ReserveSample>()
        var t = day.start
        val end = minOf(now, day.end)
        while (t <= end) {
            val value: Int = if (t <= wakeAt) {
                val span = max(wakeAt.timeIntervalSince(day.start), 1.0)
                val p = t.timeIntervalSince(day.start) / span
                anchor + ((peak - anchor).toDouble() * p).rounded().toInt()
            } else {
                val span = max(end.timeIntervalSince(wakeAt), 1.0)
                val p = min(1.0, t.timeIntervalSince(wakeAt) / span)
                peak + ((nowValue - peak).toDouble() * p).rounded().toInt()
            }
            samples.add(ReserveSample(ts = t, value = min(100, max(0, value))))
            t = t.addingTimeInterval(300.0)
        }
        return samples
    }

    fun seedHistory(): List<DailyMetrics> {
        val today = UserDay.containing(Instant.now())
        val out = mutableListOf<DailyMetrics>()
        val lcg = Lcg(0x9E3779B97F4A7C15uL.toLong())
        val rnd: () -> Double = { lcg.next(10_000) }
        for (back in 84 downTo 1) {
            val m = DailyMetrics(day = today.adding(-back))
            val r = rnd()
            if (r < 0.12) {                       // grey A · nothing logged
                m.fuelState = FuelState.Unlogged
                m.bandCoverage = 0.7 + rnd() * 0.3
            } else if (r < 0.19) {                // grey B · no burn
                m.fuelState = FuelState.Confirmed
                m.eIn = 1700 + rnd() * 500
                m.bandCoverage = rnd() * 0.45
            } else {
                m.fuelState = FuelState.Confirmed
                m.bandCoverage = 0.6 + rnd() * 0.4
                val out_ = 2050 + rnd() * 420
                val inn = 1500 + rnd() * 900
                m.bmr = 1480.0
                m.eOutNow = out_
                m.eIn = inn
                m.balance = inn - out_
            }
            // ADR 0009 · the last three weeks carry a real night window and the skin ticks
            // inside it, so the TEMP card's own range forms with no band and no session.
            // Two nights are deliberately unusable — one never worn, one a 2h nap — because
            // LEARNING, NIGHT TOO SHORT and a settled range are three different screens.
            // Thirty nights so HEART's month window has bars. `back == 6` stays empty so
            // a vacant slot is visible. Skin-temp range still samples the newest 14 valid
            // nights inside 28 days, so the older extras do not move that verdict.
            if (back <= 30 && back != 6) {
                val night = if (back == 9)
                    seedNight(day = m.day, hours = 2.0, mean = 33.7, rnd = rnd)
                // Centred on what seedToday's asleep ticks read, so the walked default is
                // WITHIN YOUR RANGE — the state a healthy person is in almost every night.
                else seedNight(day = m.day, hours = 7.5, mean = 33.85 + (rnd() - 0.5) * 0.5, rnd = rnd)
                m.sleep = night.summary
                m.vitalsCurve = night.ticks
                // The morning's resting pulse, so HEART's week and month have a line to draw.
                m.nightInputs = NightInputs(rhr = (48 + rnd() * 8).rounded(), rhrBase = 51.0, rhrNights = 14)
                if (back <= 7) {
                    val extra = mutableListOf<VitalSample>()
                    var t = m.day.start.addingTimeInterval(4.0 * 3600)
                    val end = m.day.start.addingTimeInterval(18.0 * 3600)
                    while (t < end) {
                        extra.add(VitalSample(
                            ts = t,
                            hr = (64 + rnd() * 26).toInt(),
                            stress = null,
                            hrv = if (extra.size % 4 == 0) 34 + rnd() * 10 else null))
                        t = t.addingTimeInterval(1800.0)
                    }
                    m.vitalsCurve = VitalSample.merging(m.vitalsCurve, extra)
                }
            }
            m.bbWake = (48 + rnd() * 45).toInt()
            m.worn = m.bandCoverage >= 0.5
            // Empty heat cells stay empty: an unworn day has no load and no wake peak.
            val wake = m.bbWake
            if (back == 6 || back == 17) {
                m.worn = false
                m.trainingLoad = null
                m.bbWake = null
            } else if (wake != null) {
                m.reserveDrivers = ReserveDrivers(
                    lastNight = (20 + (rnd() * 28).toInt()).toDouble(),
                    awake = -8.0, movement = -6.0, stress = -2.0,
                    anchor = max(20, wake - 30))
            }
            if (m.worn == true && back != 6 && back != 17) {
                val load = 2 + rnd() * 17
                m.trainingLoad = load
                m.targetLoad = 14.5
                m.optimalZone = 13.0..16.0
                val z1 = 20 + (rnd() * 8).toInt() * 5
                val z2 = 15 + (rnd() * 6).toInt() * 5
                val z3 = 10 + (rnd() * 5).toInt() * 5
                val hard = load >= 14
                val z4 = (if (hard) 15 else 5) + (rnd() * 3).toInt() * 5
                val z5 = if (hard) 5 + (rnd() * 2).toInt() * 5 else 0
                m.zoneMinutes = listOf(z1, z2, z3, z4, z5)
                if (m.eActive == null) m.eActive = 180 + rnd() * 280
                if (m.eOutNow == null) m.eOutNow = (m.bmr ?: 1480.0) + (m.eActive ?: 0.0)
                val steps = 3500 + (rnd() * 9000).toInt()
                val segs = mutableListOf(TrainingSegment(at = m.day.start, name = "ALL DAY", minutes = null,
                    avgHR = null, steps = steps, delta = load, allDay = true))
                if (hard) {
                    segs.add(0, TrainingSegment(
                        at = m.day.start.addingTimeInterval(14.0 * 3600),
                        name = "STRENGTH", minutes = 40, avgHR = 128,
                        steps = 500, delta = min(4.0, load * 0.25), allDay = false))
                }
                m.segments = segs
            }
            m.weightKg = 69.8 - (84 - back).toDouble() * 0.016 + (rnd() - 0.5) * 0.5
            out.add(m)
        }
        var run = 0
        var miss = 2
        var prevWorn = false
        for (i in out.indices) {
            val worn = out[i].worn == true
            if (worn) {
                run = if (prevWorn) run + 1 else 1
                miss = 0
            } else {
                run = 0
                miss = if (prevWorn) 1 else min(2, miss + 1)
            }
            out[i].wearRun = run
            out[i].wearMiss = miss
            prevWorn = worn
        }
        val seeded = seedToday()
        seeded.wearRun = (if (prevWorn) run else 0) + 1
        seeded.wearMiss = 0
        seeded.worn = true
        out.add(seeded)
        return out
    }

    /** Thirty days of daytime optical points so the RESPONSE week and month boards have
     *  slots to draw. One day in the current week is left empty so a vacant bar is visible. */
    fun seedMealResponse(): List<MealResponseIndex.Point> {
        val today = UserDay.containing(Instant.now())
        val points = mutableListOf<MealResponseIndex.Point>()
        for (back in 29 downTo 1) {
            if (back == 3) continue
            val start = today.adding(-back).start
            val shift = ((back % 5) - 2).toDouble() * 6
            for (hour in listOf(11, 13, 16)) {
                points.add(MealResponseIndex.Point(
                    ts = start.addingTimeInterval(hour.toDouble() * 3600),
                    optical = 100 + shift))
            }
        }
        val start = today.start
        points.add(MealResponseIndex.Point(ts = start.addingTimeInterval(11.0 * 3600), optical = 100.0))
        points.add(MealResponseIndex.Point(ts = start.addingTimeInterval(13.0 * 3600), optical = 100.0))
        points.add(MealResponseIndex.Point(ts = start.addingTimeInterval(15.0 * 3600), optical = 108.0))
        val now = Instant.now()
        return points.filter { it.ts <= now }
    }

    // MARK: mutations the UI performs

    /** Manual entries share the durable publication and visible projection used by
     *  accepted AI drafts and later amendments. */
    fun addManualMeal(text: String, kcal: Double, day: UserDay) {
        // The simulator's seed account is a memory-only demonstration, including
        // when real credentials were supplied for a separate debugging workflow.
        if (Band.allowsSeed) {
            val name = text.trim()
            if (!(kcal.isFinite() && kcal >= 1 && kcal <= 100000 &&
                    name.isNotEmpty() && name.codePointCount(0, name.length) <= 8000)) return
            val at = day.pinningClock(Instant.now())
            val entry = MealEntry(id = UUID.randomUUID(), day = day, at = at,
                slot = MealEntry.Slot.guess(at, day), status = MealEntry.Status.confirmed, text = name,
                kcal = kcal, protein = 0.0, carb = 0.0, fat = 0.0, source = MealEntry.Source.typed)
            overlayPendingMeals(listOf(entry), removedIDs = emptySet())
            Ports.notificationReach.evaluate(this)
            postMealReceipt(entry.text, added = listOf(entry.id))
            return
        }
        try {
            val submitted = Ports.mealQueue.createManual(text = text, kcal = kcal, day = day, store = this)
            postMealReceipt(text.trim(), added = listOf(submitted))
        } catch (error: Exception) {
            Ports.reportError(error.localizedMessage ?: error.toString())
        }
    }

    /**
     * A correction appends a replacement and soft-deletes the old cloud record.
     * Every field is optional: what the caller leaves out keeps the value the row already
     * has. The estimate wrote four numbers for a reason — asking the person to retype all
     * four to fix one of them is how the sheet used to work, and it is not an edit, it is
     * a data-entry form. The plate's own fields (group, photo, portion, micronutrients)
     * ride across to the replacement row unless this call names a new portion.
     */
    fun amendMeal(
        id: UUID, text: String? = null, kcal: Double? = null, protein: Double? = null,
        carb: Double? = null, fat: Double? = null, at: Instant? = null, slot: MealEntry.Slot? = null,
        portion: String? = null,
        fiber: Replace<Double>? = null, sugar: Replace<Double>? = null, sodium: Replace<Double>? = null,
        announce: Boolean = true,
    ) {
        val entry = meals.firstOrNull { it.id == id } ?: recentMeals.firstOrNull { it.id == id } ?: return
        if (!canEdit(entry)) return
        val name = (text ?: entry.text).trim()
        val newKcal = kcal ?: entry.kcal
        val newProtein = protein ?: entry.protein
        val newCarb = carb ?: entry.carb
        val newFat = fat ?: entry.fat
        val newSlot = slot ?: entry.slot
        val newPortion = portion ?: entry.portion
        val newFiber = if (fiber != null) fiber.value else entry.fiber
        val newSugar = if (sugar != null) sugar.value else entry.sugar
        val newSodium = if (sodium != null) sodium.value else entry.sodium
        if (!(newKcal.isFinite() && newKcal >= 0 && newKcal <= 100000 && name.isNotEmpty() &&
                listOf(newProtein, newCarb, newFat).all { it.isFinite() && it in 0.0..100000.0 } &&
                listOfNotNull(newFiber, newSugar, newSodium).all { it.isFinite() && it in 0.0..100000.0 })) return
        val eatenAt = entry.day.pinningClock(at ?: entry.at)
        val replacementID = UUID.randomUUID()
        if (Band.allowsSeed) {
            overlayPendingMeals(listOf(
                MealEntry(id = replacementID, day = entry.day, at = eatenAt, slot = newSlot,
                    status = MealEntry.Status.confirmed, text = name, kcal = newKcal, protein = newProtein,
                    carb = newCarb, fat = newFat, revisions = entry.revisions + 1, source = entry.source,
                    groupID = entry.groupID, portion = newPortion, photoPath = entry.photoPath,
                    fiber = newFiber, sugar = newSugar, sodium = newSodium),
            ), removedIDs = setOf(id))
            Ports.notificationReach.evaluate(this)
            if (announce) postMealReceipt(name, added = listOf(replacementID), replaced = entry)
            return
        }
        val owner = Ports.supabase.currentUserIdSnapshot() ?: return
        val stamp = DateTimeFormatter.ISO_INSTANT.format(eatenAt.truncatedTo(ChronoUnit.SECONDS))
        val replacement = linkedMapOf<String, Any?>(
            "id" to replacementID.toString().lowercase(), "user_day" to entry.day.key,
            "slot" to newSlot.raw, "name" to name, "kcal" to newKcal,
            "protein_g" to newProtein, "carb_g" to newCarb, "fat_g" to newFat,
            "logged_at" to stamp,
            "confidence" to "HIGH", "model_version" to "manual-amendment-v1",
        )
        entry.groupID?.let { replacement["meal_group_id"] = it.toString().lowercase() }
        entry.photoPath?.let { replacement["photo_path"] = it }
        if (newPortion != null && newPortion.isNotEmpty()) replacement["portion"] = newPortion.take(64)
        newFiber?.let { replacement["fiber_g"] = it }
        newSugar?.let { replacement["sugar_g"] = it }
        newSodium?.let { replacement["sodium_mg"] = it }
        try {
            Ports.mealQueue.enqueueAmend(mealID = id, replacement = replacement, source = entry.source,
                revisions = entry.revisions + 1, ownerUserId = owner)
        } catch (error: Exception) {
            Ports.reportError(error.localizedMessage ?: error.toString()); return
        }
        if (announce) postMealReceipt(name, added = listOf(replacementID), replaced = entry)
    }

    fun applySeedSessionLoad(delta: Double, zones: List<Double>) {
        if (!(Band.allowsSeed && delta.isFinite() && delta > 0)) return
        val next = today.copy()
        next.trainingLoad = min(20.9, (next.trainingLoad ?: 0.0) + delta)
        val current = next.zoneMinutes
        if (current != null && current.size == 5 && zones.size == 5) {
            next.zoneMinutes = current.zip(zones).map { (a, b) -> a + b.rounded().toInt() }
        } else if (zones.size == 5) {
            next.zoneMinutes = zones.map { it.rounded().toInt() }
        }
        today = next
    }

    /**
     * What just went on the record, for the few seconds a person is still looking at the
     * screen that put it there. The phone tools have had an undo stack since ADR 0018, but
     * only the model could reach it: saying "撤销" worked, tapping did not exist. This is
     * the same right, on a surface.
     */
    class MealReceipt(
        val line: String,
        /** TARGET_IN minus what is now eaten. `nil` when there is no target to count down. */
        val left: Double?,
        /** The rows this action wrote. Undo removes exactly these. */
        val added: List<UUID>,
        /** The row this action replaced, restored verbatim if undone. */
        val replaced: MealEntry?,
    ) {
        val id: UUID = UUID.randomUUID()
        val at: Instant = Instant.now()

        override fun equals(other: Any?): Boolean = other is MealReceipt && other.id == id
        override fun hashCode(): Int = id.hashCode()
    }

    fun postMealReceipt(line: String, added: List<UUID>, replaced: MealEntry? = null) {
        val todayDay = UserDay.containing(Instant.now())
        val eaten = meals.filter { it.day == todayDay && it.status != MealEntry.Status.skipped }
            .fold(0.0) { acc, m -> acc + m.kcal }
        val left = today.targetIn?.let { it - eaten }
        val receipt = MealReceipt(line = line, left = left, added = added, replaced = replaced)
        mealReceipt = receipt
        scope.launch {
            delay((receiptLifetime * 1000).toLong())
            if (mealReceipt?.id == receipt.id) mealReceipt = null
        }
    }

    /** Undo is a real deletion, not a visual one: the rows leave by the same outbox that
     *  wrote them, so a phone that was offline for both still ends up with neither. */
    fun undoMealReceipt() {
        val receipt = mealReceipt ?: return
        mealReceipt = null
        // An edit is a soft delete plus a new row, so undoing one is another edit — the same
        // shape PhoneTools already uses for the model's undo, not a second write path.
        val previous = receipt.replaced
        val current = receipt.added.firstOrNull()
        if (previous != null && current != null) {
            amendMeal(current, text = previous.text, kcal = previous.kcal, protein = previous.protein,
                carb = previous.carb, fat = previous.fat, at = previous.at, slot = previous.slot,
                portion = previous.portion, fiber = Replace(previous.fiber),
                sugar = Replace(previous.sugar), sodium = Replace(previous.sodium), announce = false)
            return
        }
        for (id in receipt.added) deleteMeal(id)
    }

    fun overlayPendingMeals(entries: List<MealEntry>, removedIDs: Set<UUID>) {
        val replacementIDs = entries.map { it.id }.toSet()
        val todayDay = UserDay.containing(Instant.now())
        meals = meals.filter { it.id !in removedIDs && it.id !in replacementIDs } +
            entries.filter { it.day == todayDay }
        recentMeals = recentMeals.filter { it.id !in removedIDs && it.id !in replacementIDs } + entries
        recomputeFuel()
    }

    /** `items` are the committed rows as JSON-shaped maps (name, kcal, protein_g, carb_g,
     *  fat_g, portion, fiber_g, sugar_g, sodium_mg). */
    fun applyCommittedMealItems(
        items: List<Map<String, Any?>>, ids: List<UUID>,
        slot: MealEntry.Slot, day: UserDay, source: MealEntry.Source,
        groupID: UUID? = null, photoPath: String? = null,
    ) {
        val at = day.pinningClock(Instant.now())
        val entries: List<MealEntry> = items.mapIndexedNotNull { index, item ->
            val name = (item["name"] as? String)?.trim() ?: ""
            val kcal = (item["kcal"] as? Number)?.toDouble() ?: return@mapIndexedNotNull null
            if (name.isEmpty() || !kcal.isFinite() || kcal < 0 || index !in ids.indices) return@mapIndexedNotNull null
            val id = ids[index]
            val protein = (item["protein_g"] as? Number)?.toDouble() ?: 0.0
            val carb = (item["carb_g"] as? Number)?.toDouble() ?: 0.0
            val fat = (item["fat_g"] as? Number)?.toDouble() ?: 0.0
            fun micro(key: String): Double? = (item[key] as? Number)?.toDouble()
            MealEntry(id = id, day = day, at = at, slot = slot, status = MealEntry.Status.confirmed,
                text = name, kcal = kcal, protein = protein, carb = carb, fat = fat, source = source,
                groupID = groupID,
                portion = (item["portion"] as? String)?.let { if (it.isEmpty()) null else it },
                photoPath = photoPath,
                fiber = micro("fiber_g"), sugar = micro("sugar_g"), sodium = micro("sodium_mg"))
        }
        if (entries.isEmpty()) return
        overlayPendingMeals(entries, removedIDs = emptySet())
        Ports.notificationReach.evaluate(this)
        postMealReceipt(
            if (entries.size == 1) entries[0].text else entries.take(3).joinToString(" · ") { it.text },
            added = entries.map { it.id })
    }

    /** Confirmed plates on screen are EATEN. A stale UNLOGGED/0 header after load
     *  must not blank a day the food table already lists. No plates keeps the
     *  server number so a failed meal fetch does not wipe a settled header. */
    fun refreshIntakeFromMeals() {
        val day = UserDay.containing(Instant.now())
        val confirmed = meals.filter { it.day == day && it.status == MealEntry.Status.confirmed }
        if (confirmed.isEmpty()) return
        recomputeFuel()
    }

    /** F0 right column: 09 needs an edit/delete entry point. Range-limited to 7 user days (F2 §08). */
    fun deleteMeal(id: UUID) {
        if (Band.allowsSeed) {
            overlayPendingMeals(emptyList(), removedIDs = setOf(id))
            Ports.notificationReach.evaluate(this)
            return
        }
        val owner = Ports.supabase.currentUserIdSnapshot() ?: return
        try {
            Ports.mealQueue.enqueueDelete(mealID = id, ownerUserId = owner)
        } catch (error: Exception) {
            Ports.reportError(error.localizedMessage ?: error.toString()); return
        }
    }

    fun canEdit(entry: MealEntry): Boolean = entry.day >= UserDay.containing(Instant.now()).adding(-6)

    private fun recomputeFuel() {
        val day = UserDay.containing(Instant.now())
        val confirmed = meals.filter { it.day == day && it.status == MealEntry.Status.confirmed }
        val t = today.copy()
        val isFasted = if (t.fuelState is FuelState.Fasted) confirmed.isEmpty() else false
        t.eIn = if (confirmed.isEmpty()) (if (isFasted) 0.0 else null) else confirmed.fold(0.0) { a, m -> a + m.kcal }
        t.proteinIn = if (confirmed.isEmpty() && !isFasted) null else confirmed.fold(0.0) { a, m -> a + m.protein }.rounded().toInt()
        t.carbIn = if (confirmed.isEmpty() && !isFasted) null else confirmed.fold(0.0) { a, m -> a + m.carb }.rounded().toInt()
        t.fatIn = if (confirmed.isEmpty() && !isFasted) null else confirmed.fold(0.0) { a, m -> a + m.fat }.rounded().toInt()
        val eIn = t.eIn
        val out = t.eOutNow
        t.balance = if (eIn != null && out != null) eIn - out else null
        if (confirmed.isEmpty()) {
            t.protein = t.protein?.let { MacroSlot(target = it.target, eaten = 0) }
            t.carb = t.carb?.let { MacroSlot(target = it.target, eaten = 0) }
            t.fat = t.fat?.let { MacroSlot(target = it.target, eaten = 0) }
        }
        // What is left moves with the row, the same instant — the tile and the LOGGED frame
        // both read it, and both used to wait for the next reload.
        t.targetIn?.let { target -> t.nextMeal = max(0.0, target - (t.eIn ?: 0.0)) }
        val slots = confirmed.map { it.slot }.toSet().size
        t.fuelState = if (confirmed.isEmpty()) (if (isFasted) FuelState.Fasted else FuelState.Unlogged)
        else (if (slots >= 4) FuelState.Confirmed else FuelState.Partial(slots = slots))
        // The macro rows are the day's own meals added up (same rule as Repository.load):
        // a plate logged just now moves the tile the same instant, not on the next reload.
        if (confirmed.isNotEmpty()) {
            val p = confirmed.fold(0.0) { a, m -> a + m.protein }.rounded().toInt()
            val c = confirmed.fold(0.0) { a, m -> a + m.carb }.rounded().toInt()
            val f = confirmed.fold(0.0) { a, m -> a + m.fat }.rounded().toInt()
            t.protein = t.protein?.let { MacroSlot(target = it.target, eaten = p) }
            t.carb = t.carb?.let { MacroSlot(target = it.target, eaten = c) }
            t.fat = t.fat?.let { MacroSlot(target = it.target, eaten = f) }
        }
        today = t
        Ports.widgetGlance.publish(this)
    }

    fun addWeighIn(w: WeighIn): Boolean {
        if (Band.allowsSeed) {
            weighIns = (weighIns + w).sortedByDescending { it.date }
            applyWeighInToToday(w)
            return true
        }
        val ownerUserId = Ports.supabase.currentUserIdSnapshot() ?: return false
        try {
            Ports.weighInQueue.enqueue(w, ownerUserId = ownerUserId)
        } catch (error: Exception) {
            Ports.reportError(error.localizedMessage ?: error.toString()); return false
        }
        weighIns = (weighIns + w).sortedByDescending { it.date }
        applyWeighInToToday(w)
        return true
    }

    private fun applyWeighInToToday(w: WeighIn) {
        val t = today.copy()
        t.weightKg = w.weightKg
        val bf = w.bodyFatPercent
        if (bf != null) {
            t.fatKg = w.weightKg * bf / 100
            t.leanKg = w.weightKg - (t.fatKg ?: 0.0)
            t.fatSource = w.source
        }
        today = t
    }
}

data class MealEntry(
    val id: UUID,
    var day: UserDay,
    var at: Instant,
    var slot: Slot,
    var status: Status,
    var text: String,
    var kcal: Double,
    var protein: Double,
    var carb: Double,
    var fat: Double,
    var revisions: Int = 0,
    var source: Source = Source.voice,
    /** One estimate is one plate. Every row it wrote carries the same group, which is how a
     *  plate can be reopened, re-portioned or saved as a favourite while the day's table
     *  stays ungrouped (一餐 is not a row; 这一次拍的这盘 is). */
    var groupID: UUID? = null,
    /** The model's own words for how much: "1 碗", "200 g". Editable without arithmetic. */
    var portion: String? = null,
    /** Object path in the private `meal-photos` bucket. `nil` for typed and voice meals. */
    var photoPath: String? = null,
    /** Absent is absent. A missing micronutrient prints ——, never 0. */
    var fiber: Double? = null,
    var sugar: Double? = null,
    var sodium: Double? = null,
) {
    enum class Slot(val raw: String) {
        breakfast("BREAKFAST"), lunch("LUNCH"), dinner("DINNER"), snack("SNACK");

        companion object {
            fun fromRaw(raw: String): Slot? = entries.firstOrNull { it.raw == raw }

            fun guess(at: Instant, day: UserDay): Slot {
                val hour = at.localHour()
                if (at < day.start) return snack
                return when (hour) {
                    in 4 until 11 -> breakfast
                    in 11 until 15 -> lunch
                    in 15 until 21 -> dinner
                    else -> snack
                }
            }
        }
    }

    enum class Status(val raw: String) {
        `open`("OPEN"), skipped("SKIPPED"), confirmed("CONFIRMED");

        companion object {
            fun fromRaw(raw: String): Status? = entries.firstOrNull { it.raw == raw }
        }
    }

    enum class Source(val raw: String) {
        voice("VOICE"), typed("TYPED"), photo("PHOTO");

        companion object {
            fun fromRaw(raw: String): Source? = entries.firstOrNull { it.raw == raw }
        }
    }

    companion object {
        /** Board 09 · the four meal slots printed on the axis, including the 01:20 +1 late snack
         *  that only exists because the day is cut at 04:00. */
        val seed: List<MealEntry>
            get() {
                val day = UserDay.containing(Instant.now())
                fun at(h: Int, m: Int, plusDay: Boolean = false): Instant =
                    day.start.addingMinutes((h - 4) * 60 + m + (if (plusDay) 1440 else 0))
                return listOf(
                    MealEntry(id = UUID.randomUUID(), day = day, at = at(1, 20, plusDay = false), slot = Slot.snack,
                        status = Status.confirmed, text = "Half a bowl of noodles + one egg", kcal = 310.0,
                        protein = 14.0, carb = 42.0, fat = 9.0, source = Source.voice),
                    MealEntry(id = UUID.randomUUID(), day = day, at = at(8, 10), slot = Slot.breakfast,
                        status = Status.confirmed, text = "Oats", kcal = 180.0, protein = 8.0, carb = 30.0,
                        fat = 4.0, source = Source.typed),
                    MealEntry(id = UUID.randomUUID(), day = day, at = at(8, 11), slot = Slot.breakfast,
                        status = Status.confirmed, text = "Greek yoghurt", kcal = 140.0, protein = 16.0,
                        carb = 8.0, fat = 5.0, source = Source.typed),
                    MealEntry(id = UUID.randomUUID(), day = day, at = at(8, 12), slot = Slot.breakfast,
                        status = Status.confirmed, text = "Blueberries", kcal = 100.0, protein = 4.0,
                        carb = 14.0, fat = 2.0, source = Source.typed),
                    MealEntry(id = UUID.randomUUID(), day = day, at = at(12, 40), slot = Slot.lunch,
                        status = Status.confirmed, text = "Chicken salad with quinoa", kcal = 510.0,
                        protein = 42.0, carb = 38.0, fat = 22.0, source = Source.photo),
                    MealEntry(id = UUID.randomUUID(), day = day, at = at(19, 0), slot = Slot.dinner,
                        status = Status.`open`, text = "", kcal = 0.0, protein = 0.0, carb = 0.0, fat = 0.0),
                )
            }
    }
}

data class WeighIn(
    val id: UUID,
    var date: Instant,
    var weightKg: Double,
    var bodyFatPercent: Double?,
    var source: MeasurementSource,
    var origin: Origin,
    /** 10S rule 04 · the Health record's own id, so the same sample never enters twice. */
    var healthUUID: String? = null,
) {
    /** F6 §05 · D06 · the scale case is gone: V1 has no such device, and this rawValue is
     *  rendered straight onto the evidence card, so keeping it kept a way for the word to
     *  reach a screen. The three that remain are the three that can actually happen. */
    enum class Origin(val raw: String) {
        band("BAND BIA"), health("APPLE HEALTH"), manual("MANUAL");

        companion object {
            fun fromRaw(raw: String): Origin? = entries.firstOrNull { it.raw == raw }
        }
    }

    companion object {
        val seed: List<WeighIn>
            get() {
                val out = mutableListOf<WeighIn>()
                for (i in 0 until 9) {
                    val day: Instant = Instant.now().addingDays(-i)
                    val kg: Double = 68.4 + i.toDouble() * 0.09
                    val measured: Boolean = i % 2 == 0
                    val bf: Double? = if (measured) 18.9 + i.toDouble() * 0.05 else null
                    val src: MeasurementSource = if (measured) MeasurementSource.measured else MeasurementSource.derived
                    val origin: Origin = when (i % 3) {
                        0 -> Origin.band
                        1 -> Origin.health
                        else -> Origin.manual
                    }
                    out.add(WeighIn(id = UUID.randomUUID(), date = day, weightKg = kg,
                        bodyFatPercent = bf, source = src, origin = origin))
                }
                return out
            }
    }
}

data class Profile(
    var name: String,
    var email: String,
    var birthdate: Instant,
    var heightCm: Double,
    var sexIsMale: Boolean,
    var goal: Goal,
    var usesMetric: Boolean,
    var appleHealthLinked: Boolean,
    /** What the band counts a full day of walking as. It is pushed to the firmware with the
     *  rest of the personal info, so the ring on the wrist and the number here are the same
     *  number. 8,000 is the default the app shipped with and the value every older row
     *  decodes to, since the field is new. */
    var stepGoal: Int = 8_000,
) {
    /** The name every screen draws. The gate has no username field and onboarding never
     *  asks, so an account can genuinely have none — Apple hands one over at the first
     *  authorization and nowhere else. Rather than each screen inventing its own empty
     *  state, an account with no name of its own is called YOU, everywhere, always. */
    val displayName: String get() = if (name.isEmpty()) "YOU" else name

    /** What the avatar circle carries: one letter per word, at most two. */
    val initials: String
        get() {
            val words = displayName.split(' ').filter { it.isNotEmpty() }
            val letters = listOfNotNull(words.firstOrNull(), if (words.size > 1) words.lastOrNull() else null)
                .mapNotNull { it.firstOrNull()?.toString() }
            return letters.joinToString("").uppercase()
        }

    val age: Int
        get() = runCatching {
            ChronoUnit.YEARS.between(birthdate.atZone(currentZone()), Instant.now().atZone(currentZone())).toInt()
        }.getOrDefault(34)

    val hrMax: Int get() = (208 - 0.7 * age.toDouble()).rounded().toInt()   // Tanaka

    /** SYNCED records a completed import on this device, not today's read permission.
     *  Reuse the existing receipt so upgrades also restore past successful imports.
     *  (Swift checks the `nb.health.lastRead` Date receipt.) */
    fun restoringHealthSync(): Profile =
        copy(appleHealthLinked = appleHealthLinked || Defaults.contains("nb.health.lastRead"))

    companion object {
        /** A device before the profile row has been read: no name (the header says YOU) and no
         *  invented birthday. hrMax off this means nothing, which is fine — no zone is computed
         *  on the phone (F2 rule 02); the row from onboarding replaces it on the first load. */
        val blank: Profile
            get() = Profile(
                name = "", email = "",
                birthdate = Instant.now().addingYears(-30),
                heightCm = 170.0, sexIsMale = true, goal = Goal.recomp,
                usesMetric = true, appleHealthLinked = false,
            ).restoringHealthSync()

        val mock: Profile = Profile(
            name = "ZEPH",
            email = "you@nextbody.app",
            birthdate = Instant.now().addingYears(-34),
            heightCm = 176.0, sexIsMale = true, goal = Goal.recomp,
            usesMetric = true, appleHealthLinked = true)
    }
}

/**
 * The most recent five-minute tick. Nothing here is extrapolated: if the band has been
 * off the wrist for six hours these are simply absent (13 · CURVE STOPS AT THE LAST REAL TICK).
 */
data class LiveVitals(
    var hr: Int? = null,
    var stress: Int? = null,
    var at: Instant? = null,
) {
    val freshness: TickFreshness get() = TickFreshness.of(at)

    companion object {
        val mock: LiveVitals = LiveVitals(hr = 72, stress = 31, at = Instant.now().addingTimeInterval(-90.0))
    }
}

data class BandState(
    var connected: Boolean,
    var name: String,
    var mac: String,
    /** nil until the band has answered readBattery — the pip draws an empty shell and a
     *  dash, never 82% (02 rule 05 · an invented percent is the one thing it must not show). */
    var batteryPercent: Int?,
    /** Last charge state the band reported. The header pip and the device page read this
     *  so a known CHARGING is not wiped to UNKNOWN while another read is in flight. */
    var chargeState: BandBattery.ChargeState,
    var firmware: String,
    /** Last full battery packet the band sent. The header pip still prints percent;
     *  the device page and the trend use this so bars-only firmware stays bars. */
    var lastBattery: BandBattery?,
    var lastSync: Instant,
    var capabilities: Set<Capability>,
) {
    /** 100% still on the charger is Charged. Firmware often never sends `.full`. */
    val displayedCharge: BandBattery.ChargeState
        get() {
            lastBattery?.let { return it.settled.chargeState }
            if (chargeState == BandBattery.ChargeState.charging &&
                BatteryDrainMath.isToppedUp(isPercent = batteryPercent != null, percent = batteryPercent, level = null)) {
                return BandBattery.ChargeState.full
            }
            return chargeState
        }

    /** Swift `mutating func` — mutates this instance. Call on a copy, never on `DataStore.band` itself. */
    fun applyBattery(battery: BandBattery) {
        // An unknown read is "we did not hear", not a percent. Keep the last
        // real packet so the hero and the pip do not dip to a stale ghost.
        val settled = battery.settled
        if (settled.chargeState == BandBattery.ChargeState.unknown) return
        lastBattery = settled
        settled.percent?.let { batteryPercent = it }
        chargeState = settled.chargeState
    }

    enum class Capability(val raw: String) {
        heartRate("heartRate"), bloodOxygen("bloodOxygen"), bloodPressure("bloodPressure"), ecg("ecg"),
        temperature("temperature"), bodyComponent("bodyComponent"), wearDetection("wearDetection"), alarms("alarms");

        companion object {
            fun fromRaw(raw: String): Capability? = entries.firstOrNull { it.raw == raw }
        }
    }

    companion object {
        /** A real phone before the band has answered anything. Every field fills in from the
         *  band itself (BandPresence) or from the devices row; none of them is guessed. */
        val unknown: BandState = BandState(connected = false, name = "NEXTBODY", mac = "",
            batteryPercent = null, chargeState = BandBattery.ChargeState.unknown, firmware = "",
            lastBattery = null,
            lastSync = DistantPast, capabilities = emptySet())

        val mock: BandState = BandState(connected = true, name = "NEXTBODY", mac = "C4:2E:8F:1A:73:9D",
            batteryPercent = 82, chargeState = BandBattery.ChargeState.unplugged, firmware = "1.4.7",
            lastBattery = BandBattery(isPercent = true, percent = 82, level = null,
                chargeState = BandBattery.ChargeState.unplugged),
            lastSync = Instant.now().addingTimeInterval(-12.0 * 60),
            capabilities = Capability.entries.toSet())
    }
}

/**
 * F1 · A. The gate is walked once per account; after that none of its screens is reachable
 * again unless the band is unbound or swapped.
 *
 * Port note: Swift's `@StateObject` class; create one per process (the activity holds it).
 * The DEBUG stage pin reads `DebugEnv["NB_DEBUG_STAGE"]` (the launcher's intent extra).
 */
class SessionStore {
    enum class Stage(val raw: String) {
        gateSignIn("gateSignIn"), gateConnect("gateConnect"), gateOnboarding("gateOnboarding"), root("root");

        companion object {
            fun fromRaw(raw: String): Stage? = entries.firstOrNull { it.raw == raw }
        }
    }

    companion object {
        private const val key = "nb.gate.stage"
    }

    private val scope = MainScope()

    private var stageState by mutableStateOf(Stage.gateSignIn)
    var stage: Stage
        get() = stageState
        set(value) {
            stageState = value
            Defaults.putString(key, value.raw)   // Swift didSet
        }
    var email: String by mutableStateOf("")
    var isSignedIn: Boolean by mutableStateOf(false)
    /** PingFang launch mark until `resolveLaunch` returns. No film. */
    var holdingLaunchStill: Boolean by mutableStateOf(false)
    var launchReady: Boolean by mutableStateOf(false)
        private set

    init {
        run {
            if (BuildConfig.DEBUG) {
                if (Ports.flowRehearsalOn) {
                    stageState = Stage.gateSignIn
                    applyLaunchCover()
                    return@run
                }
                // `NB_DEBUG_STAGE=gateConnect` opens the app at that gate for a walk.
                val s = DebugEnv["NB_DEBUG_STAGE"]
                val st = s?.let { Stage.fromRaw(it) }
                if (Band.allowsSeed && st != null) {
                    stageState = st
                    applyLaunchCover()
                    return@run
                }
            }
            val persisted = Defaults.getString(key)?.let { Stage.fromRaw(it) } ?: Stage.gateSignIn
            // No refresh token means there is no session to restore. A leftover `root` in
            // UserDefaults would otherwise flash Home over the anon key.
            stageState = if (Ports.supabase.keychainRefreshToken == null && !Band.allowsSeed) {
                Stage.gateSignIn
            } else {
                persisted
            }
            applyLaunchCover()
        }
    }

    private fun applyLaunchCover() {
        holdingLaunchStill = Ports.launchFilm.shouldHoldStill()
    }

    fun markLaunchReady() {
        if (BuildConfig.DEBUG && DebugEnv["NB_DEBUG_LAUNCH_MARK"] == "1") return
        if (launchReady) return
        launchReady = true
        holdingLaunchStill = false
        val ms = (Ports.launchFilm.elapsed * 1000).rounded().toInt()
        Defaults.putInt(Ports.launchFilm.lastDurationKey, ms)
        Log.i("NB", "NB launch ready $ms ms")
    }

    /** F1 §02 · re-read the four facts on every cold start. The last screen is a hint,
     *  not the decision. Debug stage pins stay put. */
    suspend fun resolveLaunch() {
        try {
            if (BuildConfig.DEBUG) {
                if (Ports.flowRehearsalOn) return
                if (Band.allowsSeed && DebugEnv["NB_DEBUG_STAGE"] != null) return
            }
            if (!ensureSession()) {
                if (Band.allowsSeed) return
                stage = Stage.gateSignIn
                isSignedIn = false
                email = ""
                return
            }
            if (!Band.allowsSeed && DemoAccount.matches(Ports.supabase.signedInEmail() ?: "")) {
                Ports.supabase.signOut()
                stage = Stage.gateSignIn
                isSignedIn = false
                email = ""
                return
            }
            if (stage == Stage.root) {
                scope.launch { Ports.repository.bootstrapHome(DataStore) }
            }
            // TODO(port): Repository.fetchAccountGate() — Ports.repository returns the stage.
            stage = Ports.repository.fetchAccountGateStage()
            if (stage == Stage.root) {
                scope.launch { Ports.repository.bootstrapHome(DataStore) }
            }
        } finally {
            markLaunchReady()
        }
    }

    /** Restore the Keychain refresh token. Does not invent the demo session — that
     *  stays Home's walk-through, after this gate has already decided. */
    suspend fun ensureSession(): Boolean {
        if (Ports.supabase.currentUserId() != null) {
            isSignedIn = true
            if (email.isEmpty()) email = Ports.supabase.signedInEmail() ?: ""
            scope.launch { Ports.repository.flushPendingEvidence() }
            return true
        }
        if (!Ports.supabase.restoreSession()) return false
        isSignedIn = true
        email = Ports.supabase.signedInEmail() ?: email
        scope.launch { Ports.repository.flushPendingEvidence() }
        return true
    }

    fun reset() {
        stage = Stage.gateSignIn; isSignedIn = false; email = ""
        DataStore.clearAccountDisplay()
        Ports.notificationReach.clearAccount()
        // The Keychain copy of the session goes too, or the next launch would restore it
        // straight past the gate.
        scope.launch { Ports.supabase.signOut() }
        // The band stays this account's — on the server and in its own slots, back on the
        // next sign-in — but the link goes. The next account on this phone must not find it
        // connected, and with the session gone no binding is left to reconnect it.
        scope.launch { Ports.bandLive.disconnect() }
    }

    /**
     * 11 · DELETE EVERYTHING, the phone half of it. reset() is a sign-out, and a sign-out
     * is explicitly not this: 「The NEXTBODY stays paired and keeps recording. Your data comes
     * back when you sign in.」 Delete promises the opposite in the same sheet — the band
     * unpairs itself, and there is no undo — so nothing the account wrote may survive here.
     *
     * ⚠️ Everything the app stores is a `nb.` key, so this is a sweep rather than a list:
     * a list is a thing to forget to add to, and what is forgotten is a weigh-in queue that
     * flushes into the next account, or a sync watermark that makes a re-registered phone
     * skip the days it has already read. The three in-memory stores are cleared by hand
     * because they would each write their copy back over the sweep.
     */
    fun purgeAfterAccountDelete() {
        val account = Ports.supabase.currentUserIdSnapshot() ?: Ports.supabase.keychainUserId
        if (account != null) {
            Ports.accountPurge.purgeBandDomainSyncState(account)
            try {
                Ports.mealQueue.purge(ownerUserId = account)
            } catch (error: Exception) {
                Ports.reportError(error.localizedMessage ?: error.toString())
            }
        }
        DataStore.purge()
        Ports.weighInQueue.purge()
        Ports.accountPurge.purgeBodyCompositionQueue()
        Ports.accountPurge.purgeBalanceCheckQueue()
        Ports.accountPurge.purgePlanCheckQueue()
        Ports.accountPurge.resetPlanStore()
        Ports.accountPurge.purgePlanStore(Ports.supabase.currentUserIdSnapshot() ?: Ports.supabase.keychainUserId)
        Ports.accountPurge.purgeConsent()
        scope.launch { Ports.accountPurge.purgeAnalytics() }

        // ⚠️ The SDK only offers disconnect(); "forget" is the app dropping its own device
        // id — the same pair of sentences as FORGET THIS NEXTBODY, and no more than that.
        Ports.boundBand.forget()
        scope.launch { Ports.bandLive.disconnect() }

        for (k in Defaults.keys) if (k.startsWith("nb.")) Defaults.remove(k)

        // Last, so the gate stage it writes is the one that survives the sweep.
        reset()
    }
}
