package com.nextbody.hoop.model

import com.nextbody.hoop.band.BodyBatteryReadout
import com.nextbody.hoop.band.BodyBatteryReadoutPolicy
import com.nextbody.hoop.band.DailyDirectionPolicy
import com.nextbody.hoop.band.FuelEnergyPoint
import com.nextbody.hoop.band.SleepStageRun
import com.nextbody.hoop.band.SleepWindowCorrection
import com.nextbody.hoop.band.TrainingSettlement
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import java.math.RoundingMode
import java.text.NumberFormat
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min

// F2 · The Numbers. Every symbol on screen has an entry here.
// Rule 05: unknown never degrades to 0 — the data layer writes nil, the screen writes "——".
//
// Port note: Swift structs are data classes with `var` fields so seed code can be written the
// way the Swift is. Compose state holds them by value: never mutate an instance that is already
// inside a `mutableStateOf` — `copy()` it, mutate the copy, assign it back (DataStore does).

/** F2 §06 · Daily Direction. Three colours plus two greys — never mixed with The Call's palette. */
enum class DailyDirection(val raw: String) {
    deficit("deficit"),        // BALANCE ≤ −150 kcal · solid lemon
    level("level"),            // −150 < BALANCE < +150 · outline only
    surplus("surplus"),        // BALANCE ≥ +150 kcal · red
    greyNothing("greyNothing"), // UNLOGGED, or PARTIAL with a single slot
    greyNoBurn("greyNoBurn");   // logged food, but band coverage < 50%

    companion object {
        fun fromRaw(raw: String): DailyDirection? = entries.firstOrNull { it.raw == raw }

        fun from(balance: Double?, fuel: FuelState, bandCoverage: Double): DailyDirection {
            val policyFuel: DailyDirectionPolicy.Fuel = when (fuel) {
                FuelState.Unlogged -> DailyDirectionPolicy.Fuel.Unlogged
                is FuelState.Partial -> DailyDirectionPolicy.Fuel.Partial(fuel.slots)
                FuelState.Fasted -> DailyDirectionPolicy.Fuel.Fasted
                FuelState.Confirmed -> DailyDirectionPolicy.Fuel.Confirmed
            }
            return when (DailyDirectionPolicy.color(balance, policyFuel, bandCoverage)) {
                DailyDirectionPolicy.Color.deficit -> deficit
                DailyDirectionPolicy.Color.level -> level
                DailyDirectionPolicy.Color.surplus -> surplus
                DailyDirectionPolicy.Color.greyNothing -> greyNothing
                DailyDirectionPolicy.Color.greyNoBurn -> greyNoBurn
            }
        }
    }
}

/** The state of a day's eating record. FASTED's 0 is an assertion; UNLOGGED's nil is silence. */
sealed class FuelState {
    data object Unlogged : FuelState()
    data class Partial(val slots: Int) : FuelState()
    data object Fasted : FuelState()
    data object Confirmed : FuelState()
}

/** F2 §05 · The Call. Four quadrants, never mixed with Daily Direction's colours. */
enum class TheCall(val raw: String) {
    recomp("RECOMP"),
    cut("CUT"),
    bulk("BULK"),
    drift("DRIFT"),
    noChange("MEASURED, NO CHANGE");

    companion object {
        const val fatBand = 0.15   // kg
        const val leanBand = 0.10  // kg

        fun fromRaw(raw: String): TheCall? = entries.firstOrNull { it.raw == raw }

        fun from(fatDelta7d: Double, leanDelta7d: Double): TheCall {
            val fatDown = fatDelta7d < -fatBand
            val fatUp = fatDelta7d > fatBand
            val leanUp = leanDelta7d > leanBand
            val leanDown = leanDelta7d < -leanBand
            if (leanUp) return if (fatUp) bulk else recomp
            if (leanDown) return if (fatUp) drift else cut
            if (fatDown) return cut
            if (fatUp) return bulk
            return noChange
        }
    }
}

/** Three spellings only — never a fourth (F2 §05). */
enum class Confidence(val raw: String) {
    pending("PENDING"), medium("MEDIUM"), high("HIGH");

    companion object {
        fun fromRaw(raw: String): Confidence? = entries.firstOrNull { it.raw == raw }

        fun from(scans7d: Int, sigma: Double): Confidence {
            if (scans7d >= 7 && sigma <= 0.35) return high
            if (scans7d >= 5 && sigma <= 0.70) return medium
            return pending
        }
    }
}

enum class Goal(val raw: String) {
    cut("CUT"), recomp("RECOMP"), bulk("BULK");

    val energyDelta: Double get() = when (this) { cut -> -600.0; recomp -> -380.0; bulk -> 300.0 }
    val proteinPerKg: Double get() = when (this) { cut -> 2.0; recomp -> 1.9; bulk -> 1.6 }
    val fatPerKg: Double get() = when (this) { cut -> 0.8; recomp -> 0.8; bulk -> 0.9 }

    companion object {
        fun fromRaw(raw: String): Goal? = entries.firstOrNull { it.raw == raw }
    }
}

/** F2 §03 · one set of boundaries used for both zones and load weights. */
enum class HRZone(val raw: Int) {
    below(0), z1(1), z2(2), z3(3), z4(4), z5(5);

    /** Lower bound of heart-rate reserve. */
    val hrrFloor: Double get() = listOf(0.0, 0.30, 0.40, 0.55, 0.70, 0.85)[raw]
    val loadWeight: Double get() = listOf(0.00, 0.15, 0.50, 1.20, 3.00, 6.00)[raw]
    val label: String get() = listOf("BELOW", "Z1", "Z2", "Z3", "Z4", "Z5")[raw]

    companion object {
        fun fromRaw(raw: Int): HRZone? = entries.firstOrNull { it.raw == raw }

        fun of(hrr: Double): HRZone {
            for (z in entries.reversed()) if (hrr >= z.hrrFloor) return z
            return below
        }
    }
}

/** Evidence quality for reserve only. The composition verdict has a separate Confidence. */
enum class BodyBatteryConfidence(val raw: String) {
    low("LOW"), medium("MEDIUM"), high("HIGH");

    companion object {
        fun fromRaw(raw: String): BodyBatteryConfidence? = entries.firstOrNull { it.raw == raw }
    }
}

data class BodyBatteryCoverage(
    var nightHRV: Double? = null,
    var nightRHR: Double? = null,
    var nightExpectedMinutes: Int? = null,
    var nightHRVMinutes: Int? = null,
    var nightRHRMinutes: Int? = null,
    var nightHRVLongestGap: Int? = null,
    var nightRHRLongestGap: Int? = null,
    var hrvNights: Int? = null,
    var rhrNights: Int? = null,
    var dayHeart: Double? = null,
    var dayHRV: Double? = null,
    var dayStress: Double? = null,
    var dayExpectedTicks: Int? = null,
    var dayObservedTicks: Int? = null,
)

/**
 * 13 · WHY <n>. Four user-day terms that close to current minus anchor.
 * They are additive on purpose: a multiplicative model cannot be listed as rows.
 */
data class ReserveDrivers(
    var lastNight: Double,
    var awake: Double,
    var movement: Double,
    var stress: Double,
    /** Where the local day started at midnight — yesterday's closing value. */
    var anchor: Int,
    /** True when there was no yesterday and the 20 is the cold-start assumption. The page
     *  has to say so in words rather than let it read as something we measured. */
    var assumedAnchor: Boolean = false,
    /** Old servers called user-day charge `last_night`. New clients never present that
     *  legacy field as the entire night's charge; a night can cross the 04:00 boundary. */
    var dayCharge: Double? = null,
    var nightCharge: Double? = null,
    var wakeAt: Instant? = null,
    var observedAt: Instant? = null,
    var confidence: BodyBatteryConfidence? = null,
    var coverage: BodyBatteryCoverage? = null,
    var algoVersion: String? = null,
) {
    val chargeForDay: Double get() = dayCharge ?: lastNight
    val sum: Double get() = chargeForDay + awake + movement + stress
}

/**
 * 13 · LAST NIGHT'S INPUTS. Every field is optional because the card's whole job is to
 * show what the multiplier was computed from — a value we do not have has to read "——".
 */
data class NightInputs(
    var hrv: Double? = null,
    var hrvBase: Double? = null,
    var rhr: Double? = null,
    var rhrBase: Double? = null,
    var rhrNights: Int = 0,
    /** How many of the last fourteen nights had an HRV of their own. Its own count: a night
     *  the band measured HRV through is not the same set as one it measured a resting pulse in. */
    var hrvNights: Int = 0,
    var multiplier: Double? = null,
) {
    /** The card's "n OF 3" — how many of the three inputs actually arrived. */
    val present: Int get() = (if (hrv != null) 1 else 0) + (if (rhr != null) 1 else 0) + (if (multiplier != null) 1 else 0)
}

/** Server-published observation coverage. Recorded time is not a wear assertion. */
data class TrainingEvidence(
    var elapsedMinutes: Int,
    var recordedMinutes: Int,
    var heartRateMinutes: Int,
    var movementMinutes: Int,
    var restingHeartRate: Double?,
    var restingBaselineNights: Int,
    var baselineEstimated: Boolean,
)

/**
 * 08 · one row of TODAY'S BUILD. The rows are shares of the day's raw work, so the
 * column adds up to the number on the ring rather than overshooting it.
 */
data class TrainingSegment(
    var at: Instant,
    var name: String,
    var minutes: Int?,
    var avgHR: Int?,
    var steps: Int?,
    var delta: Double,
    var allDay: Boolean,
) {
    val id: Instant get() = at
}

/** One point on the cumulative load curve — TRAINING_LOAD as it stood at that instant. */
data class LoadPoint(val ts: Instant, val load: Double)

/** One point on the reserve curve. 288 of them make a day at five-minute ticks. */
data class ReserveSample(val ts: Instant, val value: Int)

/**
 * 04B · SLEEP card. The night OriginDataSync stored under this user day — what the band
 * reported, as measurements. The score built on top of it is a separate, server-settled
 * row (`SleepScore`, ADR 0008) and never a field here. The whole reason it is a struct of its own is
 * that 13 板 forbids sleep on the battery page while 04B prints it first; both read one row.
 */
data class SleepInterval(var start: Instant, var end: Instant)

/**
 * ADR 0008 · the night's settled score, computed server-side once and read back whole.
 * Four groups, weighted 25 / 25 / 35 / 15; a group is nil when nothing it needs was
 * recorded, and the total is renormalised over the groups that remain. There is no
 * client-side arithmetic here on purpose — a score the phone re-derived could disagree
 * with the same night seen from the week window.
 */
data class SleepScore(
    var score: Int,
    var duration: Int? = null,
    var architecture: Int? = null,
    var recovery: Int? = null,
    var regularity: Int? = null,
    /** 0 = scored against population baselines, 1 = fully against this person's own.
     *  Ramps between the 14th and 28th night; the board says so while it is below 1. */
    var personalWeight: Double = 0.0,
    /** The measured values behind the score. Membership is the point: a key that is absent
     *  is an input the night did not have, and that is what the breakdown prints. */
    var inputs: Map<String, Double> = emptyMap(),
    var version: String = "",
    var computedAt: Instant? = null,
) {
    val isCalibrating: Boolean get() = !usesContributors && personalWeight < 1

    val usesContributors: Boolean get() = inputs["contributor_policy"] == 3.0

    fun contributorScore(contributor: SleepContributor): Double? {
        if (!usesContributors) return null
        val value = inputs["score_${contributor.raw}"] ?: return null
        if (!value.isFiniteValue || value !in 0.0..100.0) return null
        return value
    }

    fun contributorWeight(contributor: SleepContributor): Double? {
        val present = SleepContributor.entries.mapNotNull { item ->
            if (contributorScore(item) == null) return@mapNotNull null
            val weight = inputs["weight_${item.raw}"] ?: return@mapNotNull null
            if (!weight.isFiniteValue || weight <= 0) return@mapNotNull null
            item to weight
        }
        val total = present.fold(0.0) { acc, p -> acc + p.second }
        val weight = present.firstOrNull { it.first == contributor }?.second
        if (total <= 0 || weight == null) return null
        return weight / total * 100
    }

    fun value(of: SleepScoreGroup): Int? = when (of) {
        SleepScoreGroup.duration -> duration
        SleepScoreGroup.architecture -> architecture
        SleepScoreGroup.recovery -> recovery
        SleepScoreGroup.regularity -> regularity
    }
}

/** Cached scores remain visible while their next read is pending or unavailable. */
enum class SleepScoreLoadState { idle, loading, ready, failed }

/**
 * The four groups, in the order the breakdown prints them. Splitting duration away from
 * architecture is what lets the board say "you slept enough, the structure was poor" —
 * one bar carrying both cancels that sentence out.
 */
enum class SleepScoreGroup(val raw: String) {
    duration("duration"), architecture("architecture"), recovery("recovery"), regularity("regularity");

    val title: String
        get() = when (this) {
            duration -> L("DURATION")
            architecture -> L("STRUCTURE")
            recovery -> L("RECOVERY")
            regularity -> L("REGULARITY")
        }

    val weight: Int
        get() = when (this) {
            duration -> 25
            architecture -> 25
            recovery -> 35
            regularity -> 15
        }

    /** The keys this group scores over, named as the server names them in `inputs`. */
    val memberKeys: List<String>
        get() = when (this) {
            duration -> listOf("duration_min")
            architecture -> listOf("deep_pct", "rem_pct", "wakes")
            recovery -> listOf("hrv_ms", "rhr", "spo2_min", "respiration")
            regularity -> listOf("bed_offset")
        }
}

enum class SleepContributor(val raw: String) {
    totalSleep("total_sleep"),
    efficiency("efficiency"), restfulness("restfulness"), rem("rem"), deep("deep"),
    latency("latency"), timing("timing");

    val id: String get() = raw

    val title: String
        get() = when (this) {
            totalSleep -> L("TOTAL SLEEP")
            efficiency -> L("SLEEP EFFICIENCY")
            restfulness -> L("RESTFULNESS")
            rem -> L("REM SLEEP")
            deep -> L("DEEP SLEEP")
            latency -> L("SLEEP LATENCY")
            timing -> L("SLEEP TIMING")
        }

    val explanation: String
        get() = when (this) {
            totalSleep -> L("Time asleep, excluding recorded wakefulness. Most adults need 7–9 hours. NEXTBODY gives full duration marks from 7.5 hours and limits short-night scores.")
            efficiency -> L("Time asleep divided by the fully staged recording. 85% meets the reference. This is recorded-period efficiency, not time-in-bed efficiency.")
            restfulness -> L("Based on recorded awake minutes and wake episodes. Movement and out-of-bed events are not measured here.")
            rem -> L("Scored against 90 minutes of REM; the percentage is context, not a substitute for enough sleep. An absent REM channel stays unmeasured.")
            deep -> L("Scored against 60 minutes of deep sleep. Adults commonly spend around 15–20% of sleep in this stage; needs vary with age.")
            latency -> L("Time from trying to sleep to falling asleep. The band does not record this. Time to first deep sleep is not latency. This factor is excluded.")
            timing -> L("The longest recorded sleep period's midpoint is compared with 00:00–03:00 local time. This is a population reference, not a measured personal chronotype.")
        }

    companion object {
        fun fromRaw(raw: String): SleepContributor? = entries.firstOrNull { it.raw == raw }

        fun rating(score: Double): String = when {
            score >= 85 -> L("OPTIMAL")
            score >= 70 && score < 85 -> L("GOOD")
            score >= 60 && score < 70 -> L("FAIR")
            else -> L("PAY ATTENTION")
        }
    }
}

data class SleepSummary(
    var totalMinutes: Int,
    var deepMinutes: Int,
    var lightMinutes: Int,
    var wakeCount: Int,
    /** 04B rule 04 · the band's own sleepLine as stage runs, drawn as-is: deep full height,
     *  light half, awake a short mark — never re-segmented by the app. Empty on nights
     *  stored before the line was kept; the strip falls back to proportions for those. */
    var line: List<SleepStageRun> = emptyList(),
    /** The band's own window for the night. nil on rows stored before the two columns
     *  existed — the hypnogram then runs on the line's own minutes and prints no clock,
     *  because a bed time inferred from a duration is a bed time nobody measured. */
    var sleepStart: Instant? = null,
    var wakeAt: Instant? = null,
    /** Overnight automatic SpO2 inside this night's window. Empty when the band filed none. */
    var spo2: List<OvernightOxygenPoint> = emptyList(),
    /** Automatic respiratory measurements in the recorded sleep window; nil in older archives. */
    var respiration: List<SleepRespirationPoint>? = null,
    /** RMSSD at the actual recorded RR minute, independent of the five-minute origin grid. */
    var hrv: List<SleepHRVPoint>? = null,
    /** Explicit RR corrections by measured minute and observation clock. Missing reads
     *  never populate this map; it prevents older snapshots from restoring disproved HRV. */
    var hrvInvalidatedMinutes: Map<Instant, Instant>? = null,
    /** Actual recorded sessions; the gaps between them are not sleep measurements. */
    var intervals: List<SleepInterval>? = null,
    /** #28 · when the person wearing it said the band was wrong about this night. The window
     *  above is then theirs, and `bandStart` / `bandEnd` keep the one the band filed, so the
     *  page can name both without pretending the published window is still a measurement. */
    var correctedAt: Instant? = null,
    var bandStart: Instant? = null,
    var bandEnd: Instant? = null,
    /** A person's reported window remains distinct from a device measurement. */
    var source: String? = null,
    /** Actual heart observations in the full edited window, including its preceding day. */
    var heartRate: List<VitalSample>? = null,
) {
    /** The night's REM and awake minutes, which only the line can answer: the row stores
     *  deep and light, and the remainder is not one stage. Zero when there is no line. */
    val remMinutes: Int get() = line.filter { it.stage == 2 }.sumOf { it.minutes }
    val awakeMinutes: Int get() = line.filter { it.stage >= 3 }.sumOf { it.minutes }
    val isCorrected: Boolean get() = correctedAt != null
    val isUserReported: Boolean get() = source == "user_reported"

    val unstagedMinutes: Int
        get() {
            val sleepStart = sleepStart
            val wakeAt = wakeAt
            if (!(isCorrected || isUserReported) || sleepStart == null || wakeAt == null) return 0
            return SleepWindowCorrection.unstagedMinutes(
                line.map { SleepWindowCorrection.LineRun(it.stage, it.minutes, it.offsetMinutes) },
                start = sleepStart, end = wakeAt)
        }

    fun containsSleepTimestamp(timestamp: Instant): Boolean {
        val sleepStart = sleepStart ?: return false
        val wakeAt = wakeAt ?: return false
        if (!(wakeAt > sleepStart && timestamp >= sleepStart && timestamp < wakeAt)) return false
        val intervals = intervals
        if (isCorrected || isUserReported || intervals == null) return true
        return intervals.any { it.end > it.start && timestamp >= it.start && timestamp < it.end }
    }
}

data class SleepHRVPoint(
    var ts: Instant,
    var rmssdMS: Double,
    var observedAt: Instant? = null,
) {
    companion object {
        fun merging(
            stored: List<SleepHRVPoint>, fresh: List<SleepHRVPoint>,
            invalidatedMinutes: Map<Instant, Instant>,
        ): List<SleepHRVPoint> {
            val points = LinkedHashMap<Instant, SleepHRVPoint>()
            for (point in stored + fresh) {
                if (!(point.rmssdMS.isFiniteValue && point.rmssdMS in 1.0..300.0)) continue
                val current = points[point.ts]
                val previousClock = current?.observedAt
                if (current != null && previousClock != null &&
                    (point.observedAt?.let { it <= previousClock } ?: true)) continue
                points[point.ts] = point
            }
            return points.values.filter { point ->
                val invalidatedAt = invalidatedMinutes[point.ts] ?: return@filter true
                point.observedAt?.let { it > invalidatedAt } ?: false
            }.sortedBy { it.ts }
        }
    }
}

/** One respiratory reading from the SDK's automatic history, retained on the night's clock. */
data class SleepRespirationPoint(var ts: Instant, var breathsPerMinute: Double)

/** One automatic oxygen reading clipped to the recorded night. Not an apnea event. */
data class OvernightOxygenPoint(var ts: Instant, var percent: Int)

/**
 * F2 §02 · one row of daily_metrics. Everything is computed server-side; the app only lays it out.
 *
 * Port note: every field is a constructor parameter so `copy()` carries all of them.
 */
data class DailyMetrics(
    val day: UserDay,

    // Training Load 0–21 · never a percentage
    var trainingLoad: Double? = null,          // TRAINING_LOAD
    var targetLoad: Double? = null,            // Server-published recovery-led recommendation
    var optimalZone: ClosedFloatingPointRange<Double>? = null,
    var zoneMinutes: List<Int>? = null,        // ZONE_MIN[1..5], always multiples of 5
    /** 补屏 B · true without a weight: met ≥ 3 points × 5, and the band's own metres. */
    var activeMinutes: Int? = null,
    var distanceM: Int? = null,
    var segments: List<TrainingSegment> = emptyList(),
    /** The cumulative curve 08 draws THROUGH THE DAY. */
    var loadCurve: List<LoadPoint> = emptyList(),
    var peakHR: Int? = null,
    var trainingEvidence: TrainingEvidence? = null,
    var trainingSettlement: TrainingSettlement? = null,
    var recordedSteps: Int? = null,

    // Body Battery
    var bbWake: Int? = null,                   // BB_WAKE — frozen for the day
    var bodyBattery: Int? = null,              // BODY_BATTERY(t) — the live curve
    // 13 · the four attribution rows, and the curve behind them. Both come from the
    // server so the detail page never has to re-derive a number the day already settled.
    var reserveDrivers: ReserveDrivers? = null,
    var reserveCurve: List<ReserveSample> = emptyList(),
    /** 13 · the ticks the battery is made of. Heart and stress are two of the four rows in
     *  WHY, so the page shows them as measurements rather than only as attributions. */
    var vitalsCurve: List<VitalSample> = emptyList(),
    var nightInputs: NightInputs? = null,
    /** ADR 0008 · the settled sleep score for the night that ended on this day. nil until
     *  the server has settled it, which is also what a night with no record looks like. */
    var sleepScore: SleepScore? = null,
    /** 04B · last night, from sleep_nights. nil until the band has answered readSleep. */
    var sleep: SleepSummary? = null,

    // Energy
    var bmr: Double? = null,                   // the part of the baseline that has elapsed
    var bmrFull: Double? = null,               // the whole day's baseline — 10's header is an estimate
    var eActive: Double? = null,
    var energyDistribution: List<FuelEnergyPoint>? = null,
    var eTrain: Double? = null,
    var eTrainPlan: Double? = null,
    var eOutNow: Double? = null,
    var activeForecast: Double? = null,
    var eOutFull: Double? = null,
    var eIn: Double? = null,                   // nil = UNLOGGED
    var balance: Double? = null,               // E_IN − E_OUT_NOW
    var targetIn: Double? = null,              // TARGET_IN
    /** Where TARGET_IN came from (#29): `targetBasis` is resting for the whole day plus
     *  the activity measured so far, before the goal offset, the floor and the macro
     *  split. `restingSource` says whether that resting figure is the body scan's
     *  (`BODY_SCAN`, taken at `restingMeasuredAt`) or Mifflin (`MIFFLIN`), and
     *  `goalOffset` is the profile goal's −500 / −380 / +300. 09 prints all of it,
     *  because a budget that moves without saying why is a number nobody can plan
     *  against. `targetBasisDays` is retired with fuel-2.0 and stays nil. */
    var targetBasis: Double? = null,
    var targetBasisDays: Int? = null,
    var restingSource: String? = null,
    var restingMeasuredAt: Instant? = null,
    var goalOffset: Double? = null,
    var protein: MacroSlot? = null,
    var carb: MacroSlot? = null,
    var fat: MacroSlot? = null,
    var nextMeal: Double? = null,
    /** What actually went in that day, and the weight its targets were set against.
     *  12 averages the protein over seven days to score one of THE CALL's four signals. */
    var proteinIn: Int? = null,
    var carbIn: Int? = null,
    var fatIn: Int? = null,

    // Composition
    var weightKg: Double? = null,
    var fatKg: Double? = null,
    var leanKg: Double? = null,
    var fatSource: MeasurementSource? = null,
    var fatEmaDelta7d: Double? = null,
    var leanEmaDelta7d: Double? = null,
    /** THE_CALL as the server settled it. F3 §00 · one source, one instant. */
    var serverCall: TheCall? = null,
    var confidence: Confidence = Confidence.pending,
    var scans7d: Int = 0,
    var logged7d: Int = 0,

    // Bookkeeping
    var fuelState: FuelState = FuelState.Unlogged,
    var bandCoverage: Double = 0.0,
    var calcVersion: String = "1.0.0",
    var asOf: Instant? = null,

    /** F2 rule 02 · the direction is computed server-side and written to daily_results.
     *  The local calculation is the live view of today (and the offline fallback):
     *  calendar close is not a gate, or the heat map stays empty until 04:00. */
    var serverDirection: DailyDirection? = null,
    /** ADR 0010 · settled worn day. nil until the server has said. */
    var worn: Boolean? = null,
    var wearRun: Int? = null,
    var wearMiss: Int? = null,
) {
    val id: Instant get() = day.date

    /** The time of reserve evidence, never a network fetch or another metric's update. */
    val bodyBatteryObservedAt: Instant?
        get() = reserveDrivers?.observedAt ?: reserveCurve.lastOrNull()?.ts

    val bodyBatteryWakeAt: Instant?
        get() {
            if (bbWake == null) return null
            return reserveDrivers?.wakeAt ?: sleep?.wakeAt
        }

    val bodyBatteryConfidence: BodyBatteryConfidence
        get() = reserveDrivers?.confidence ?: BodyBatteryConfidence.low

    fun bodyBatteryFreshness(now: Instant = Instant.now()): TickFreshness =
        TickFreshness.of(bodyBatteryObservedAt, now)

    /** #25 · the single answer to 「现在该印数字还是 ——」. Every entry asks this one,
     *  so a not-worn wrist can never reach a screen dressed as a real reserve. */
    fun bodyBatteryReadout(now: Instant = Instant.now()): BodyBatteryReadout =
        BodyBatteryReadoutPolicy.readout(value = bodyBattery, observedAt = bodyBatteryObservedAt, now = now)

    fun bodyBatteryForDisplay(now: Instant = Instant.now()): Int? = bodyBatteryReadout(now).value

    /** All recorded activity, including steps inside elevated-heart-rate segments.
     *  Old servers do not expose a trustworthy day total; never label an ordinary-only
     *  segment as the whole day when exercise segments are also present. */
    val steps: Int?
        get() {
            recordedSteps?.let { return it }
            if (!segments.all { it.allDay }) return null
            return segments.firstOrNull { it.allDay }?.steps
        }

    val direction: DailyDirection
        get() = serverDirection ?: DailyDirection.from(balance, fuelState, bandCoverage)

    // optimalZone is a range; it stays out of the wire format and is rebuilt server-side.

    /** Mutates this instance (Swift `mutating`). Call on a copy, never on a value held in state. */
    fun applyTrainingSettlement(settlement: TrainingSettlement) {
        trainingSettlement = settlement
        val recommendation = settlement.recommendation(legacyTarget = targetLoad, legacyZone = optimalZone)
        targetLoad = recommendation.target
        optimalZone = recommendation.zone
    }
}

/** One macro row: a target and how much of it has been eaten. */
data class MacroSlot(var target: Int, var eaten: Int)

enum class MeasurementSource(val raw: String) {
    measured("MEASURED"),     // band BIA or a body-fat scale — re-anchors the EMA
    derived("DERIVED"),       // weight × body-fat %
    estimated("ESTIMATED");

    companion object {
        fun fromRaw(raw: String): MeasurementSource? = entries.firstOrNull { it.raw == raw }
    }
}

/** F2 rule 05 rendered: a number that isn't there is an em-dash, never a zero. */
object Fmt {
    const val dash = "——"

    /** Food records show one decimal; daily energy/target dials keep their own format. */
    fun nutrient(value: Double?): String {
        if (value == null || !value.isFiniteValue) return dash
        return swiftFormat("%.1f", value)
    }

    fun load(v: Double?): String = v?.let { swiftFormat("%.1f", min(it, 20.9)) } ?: dash

    fun kcal(v: Double?): String {
        if (v == null) return dash
        if (!v.isFiniteValue) return dash
        return synchronized(kcalFormatter) { kcalFormatter.format(v) }
    }

    // ⚠️ Formatters are built once. Each of these used to be allocated per call, and the
    // calls sit inside view bodies that run on every frame of an animation.
    private val kcalFormatter: NumberFormat = NumberFormat.getNumberInstance().apply {
        maximumFractionDigits = 0
        roundingMode = RoundingMode.HALF_EVEN
        isGroupingUsed = true
    }
    private val clockFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")
    private val monthDayFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("MM-dd", Locale.US)

    /** 09 · the day a body scan was taken, beside the resting figure it supplied. */
    fun monthDay(d: Instant): String = monthDayFormatter.format(d.atZone(currentZone()))

    fun signedKcal(v: Double?): String {
        if (v == null) return dash
        return (if (v < 0) "−" else "+") + kcal(abs(v))
    }

    /** Paper 09C pair. Zero is "0", not "+0" — that is the end of TO GO. */
    fun pairKcal(v: Double): String {
        if (v == 0.0) return kcal(0.0)
        return signedKcal(v)
    }

    fun kg(v: Double?, decimals: Int = 1): String = v?.let { swiftFormat("%.${decimals}f", it) } ?: dash

    fun signedKg(v: Double?, decimals: Int = 2): String {
        if (v == null) return dash
        return (if (v < 0) "−" else "+") + swiftFormat("%.${decimals}f", abs(v))
    }

    fun int(v: Int?): String = v?.toString() ?: dash

    /** 13 · the attribution rows carry their own sign, and a zero row reads "0", not "+0". */
    fun signed(v: Double): String {
        val n = v.roundedInt()
        return if (n > 0) "+$n" else "$n"
    }

    fun pct(v: Int?): String = v?.let { "$it%" } ?: dash

    /** 08 · zone time. Minutes below an hour read plainly; an hour or more takes the
     *  board's "4H 12M" shape. ⚠️ Every duration here is a multiple of five, because the
     *  raw points are five minutes apart — never round one to something finer. */
    fun duration(minutes: Int): String {
        if (minutes < 60) return L("%d MIN", minutes)
        val h = minutes / 60
        val m = minutes % 60
        return if (m == 0) L("%dH", h) else L("%dH %dM", h, m)
    }

    fun duration(minutes: Int?): String = minutes?.let { duration(it) } ?: dash

    fun weekday(d: Instant): String =
        DateTimeFormatter.ofPattern("EEE", AppLanguage.locale.javaLocale)
            .format(d.atZone(currentZone())).uppercase(Locale.ROOT)

    fun displayDate(d: Instant, format: String): String =
        DateTimeFormatter.ofPattern(format, AppLanguage.locale.javaLocale).format(d.atZone(currentZone()))

    fun clock(d: Instant): String = clockFormatter.format(d.atZone(currentZone()))
}
