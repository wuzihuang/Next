package com.nextbody.hoop.band

import kotlin.math.exp
import kotlin.math.expm1
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** Deterministic reference for readiness-1.0. The server publishes the complete replay
 *  from `nb.compute_reserve`; this model is for scenario tests only. */
object BodyBatteryEngine {
    /** One hour of zone 3–4 effort lands near 14–22 points. Light daily movement is gated off first. */
    const val effortScale = 0.38

    data class Baseline internal constructor(
        val restingHeartRate: Double,
        val maximumHeartRate: Double,
        /** Matched-context baselines: quiet daytime RMSSD must not use sleeping RMSSD. */
        val hrvMS: Double?,
        val sleepHRVMS: Double?,
        val daytimeHeartRate: Double,
        val recoveryMultiplier: Double,
        val sleepDebt: Double,
        val daytimeTemperature: Double?,
        val sleepingTemperature: Double?,
        val temperatureScale: Double,
        val morningReadiness: Double?,
    ) {
        /** Quiet rest rises toward this morning's readiness, and never above 90. */
        val restCeiling: Double get() = min(90.0, morningReadiness ?: 90.0)

        companion object {
            operator fun invoke(
                restingHeartRate: Double, maximumHeartRate: Double,
                hrvMS: Double?, recoveryMultiplier: Double, sleepDebt: Double = 1.0,
                sleepHRVMS: Double? = null, daytimeHeartRate: Double? = null,
                daytimeTemperature: Double? = null, sleepingTemperature: Double? = null,
                temperatureScale: Double = 0.5, morningReadiness: Double? = null,
            ): Baseline {
                val resting = if (restingHeartRate.isFinite()) min(120.0, max(30.0, restingHeartRate)) else 55.0
                return Baseline(
                    restingHeartRate = resting,
                    maximumHeartRate = if (maximumHeartRate.isFinite()) max(resting + 1, maximumHeartRate) else 190.0,
                    hrvMS = valid(hrvMS, 1.0, 300.0),
                    sleepHRVMS = valid(sleepHRVMS, 1.0, 300.0),
                    daytimeHeartRate = valid(daytimeHeartRate, 30.0, 150.0) ?: (resting + 10),
                    recoveryMultiplier = if (recoveryMultiplier.isFinite()) min(1.30, max(0.65, recoveryMultiplier)) else 1.0,
                    sleepDebt = if (sleepDebt.isFinite()) min(1.6, max(1.0, sleepDebt)) else 1.0,
                    daytimeTemperature = valid(daytimeTemperature, 10.0, 50.0),
                    sleepingTemperature = valid(sleepingTemperature, 10.0, 50.0),
                    temperatureScale = if (temperatureScale.isFinite()) max(0.5, temperatureScale) else 0.5,
                    morningReadiness = valid(morningReadiness, 0.0, 100.0),
                )
            }
        }
    }

    fun sleepDebt(sleptMinutes: Double?, wornThroughTheNight: Boolean = false): Double {
        val slept = sleptMinutes
        if (slept == null || !slept.isFinite() || slept <= 0) return if (wornThroughTheNight) 1.6 else 1.0
        return 1 + 0.6 * unit((420 - slept) / 180)
    }

    data class Tick internal constructor(
        val durationMinutes: Double,
        val heartRate: Int?,
        val hrvMS: Double?,
        val stress: Int?,
        val steps: Int?,
        val met: Double?,
        /** Recorded sleep staging, including a recorded nap; never inferred from pulse alone. */
        val sleepStage: Int?,
        val temperature: Double?,
        /** Automatic, timestamp-matched night oxygen. No daytime carry-forward. */
        val oxygen: Double?,
        /** A recorded sport session. Strength work can cost readiness without a high heart rate. */
        val inSession: Boolean,
    ) {
        companion object {
            operator fun invoke(
                durationMinutes: Double = 5.0, heartRate: Int? = null, hrvMS: Double? = null,
                stress: Int? = null, steps: Int? = null, met: Double? = null,
                sleepStage: Int? = null, temperature: Double? = null, oxygen: Double? = null,
                inSession: Boolean = false,
            ) = Tick(
                durationMinutes = if (durationMinutes.isFinite()) max(0.0, durationMinutes) else 0.0,
                heartRate = heartRate?.takeIf { it in 30..250 },
                hrvMS = valid(hrvMS, 1.0, 300.0),
                stress = stress?.takeIf { it in 1..100 },
                steps = steps?.takeIf { it >= 0 },
                met = valid(met, 0.5, 25.0),
                sleepStage = sleepStage?.takeIf { it in 0..4 },
                temperature = valid(temperature, 10.0, 50.0),
                oxygen = valid(oxygen, 50.0, 100.0),
                inSession = inSession,
            )
        }
    }

    data class Drivers(
        var recovery: Double = 0.0,
        var awake: Double = 0.0,
        var movement: Double = 0.0,
        var stress: Double = 0.0,
        var restorativeRest: Double = 0.0,
    )

    data class Result(val value: Double, val drivers: Drivers, val wornMinutes: Double)

    data class Rates(val movement: Double, val strain: Double, val rest: Double, val recovery: Double)

    private class State(var value: Double) {
        var drivers = Drivers()
        var wornMinutes = 0.0
        var quietMinutes = 0.0
        var awakeMinutes = 0.0
        var temperatureRisks = mutableListOf<Pair<Double, Double>>()
        var oxygenRisks = mutableListOf<Pair<Double, Double>>()
        var wasSleeping = false
    }

    fun replay(anchor: Double, ticks: List<Tick>, baseline: Baseline): Result {
        val state = State(if (anchor.isFinite()) min(100.0, max(0.0, anchor)) else 50.0)
        for (tick in ticks) apply(tick, baseline, state)
        return Result(value = state.value, drivers = state.drivers.copy(), wornMinutes = state.wornMinutes)
    }

    private fun apply(tick: Tick, baseline: Baseline, state: State) {
        val sleeping = tick.sleepStage?.let { it != 4 } ?: false
        val worn = tick.sleepStage != null || tick.heartRate != null || tick.hrvMS != null ||
            tick.stress != null || (tick.steps ?: 0) > 0 || (tick.met ?: 1.0) > 1.05
        if (sleeping) {
            state.awakeMinutes = 0.0
            state.quietMinutes = 0.0
        }
        if (!(tick.durationMinutes > 0 && worn)) {
            if (!sleeping) state.awakeMinutes += tick.durationMinutes
            state.quietMinutes = 0.0
            state.temperatureRisks = mutableListOf()
            state.oxygenRisks = mutableListOf()
            return
        }
        if (sleeping != state.wasSleeping) {
            state.temperatureRisks = mutableListOf()
            state.oxygenRisks = mutableListOf()
        }
        state.wasSleeping = sleeping
        state.wornMinutes += tick.durationMinutes
        val scale = tick.durationMinutes / 5
        val temperatureBase = if (sleeping) baseline.sleepingTemperature else baseline.daytimeTemperature
        val temperatureRisk = tick.temperature?.let { t ->
            temperatureBase?.let { unit((t - it - baseline.temperatureScale) / 1.0) }
        }
        val oxygenRisk = if (sleeping) tick.oxygen?.let { unit((95 - it) / 5) } else null
        val auxiliary = max(
            sustained(temperatureRisk, tick.durationMinutes, state.temperatureRisks),
            sustained(oxygenRisk, tick.durationMinutes, state.oxygenRisks))
        val hrvBase = if (sleeping) baseline.sleepHRVMS else baseline.hrvMS
        val normalizedSteps = tick.steps?.let { it.toDouble() * 5 / max(0.01, tick.durationMinutes) }
        val heart = tick.heartRate?.toDouble()
        val rates = rates(
            heart = heart, hrv = tick.hrvMS,
            stress = tick.stress?.toDouble(), steps = normalizedSteps, met = tick.met,
            resting = baseline.restingHeartRate, maximum = baseline.maximumHeartRate,
            referenceHeart = if (sleeping) baseline.restingHeartRate else baseline.daytimeHeartRate,
            referenceHRV = hrvBase, auxiliary = auxiliary)
        val hrr = heart?.let { unit((it - baseline.restingHeartRate) / max(1.0, baseline.maximumHeartRate - baseline.restingHeartRate)) } ?: 0.0
        val lightDaily = hrr < 0.30 && (tick.met ?: 1.0) < 2 && !tick.inSession
        val previousQuiet = state.quietMinutes
        state.quietMinutes = if (!sleeping && rates.rest > 0) previousQuiet + tick.durationMinutes else 0.0
        val quietRest = !sleeping && state.quietMinutes > 20 && rates.rest > 0
        val awakeHours = state.awakeMinutes / 60
        val rawAwake = if (sleeping || quietRest) 0.0 else awakeRate(awakeHours, baseline.sleepDebt) * scale
        val rawMovement = if (sleeping || lightDaily) 0.0 else rates.movement * effortScale * scale
        val rawStrain = rates.strain * (if (sleeping) 0.75 else 1.0) * scale
        val requested = rawAwake + rawMovement + rawStrain
        // Integrate the reserve-dependent drain: one five-minute observation and
        // five one-minute intervals have the same price when the evidence is constant.
        val integrated = if (requested > 0) -expm1(-0.0065 * requested) / (0.0065 * requested) else 1.0
        val soften = (0.35 + 0.65 * state.value / 100) * integrated
        // Only minutes after the sustained-evidence window earn credit; no retroactive gain.
        val credited = max(0.0, state.quietMinutes - max(20.0, previousQuiet))
        val ramp = unit((state.quietMinutes - 20) / 20)
        val rest = if (sleeping) 0.0 else max(0.0, baseline.restCeiling - state.value) *
            (1 - exp(-0.006 * rates.rest * ramp * credited / 5))
        val sleepGain = if (sleeping) max(0.0, 95 - state.value) *
            (1 - exp(-0.011 * sleepQuality(tick.sleepStage!!) * baseline.recoveryMultiplier * rates.recovery * scale)) else 0.0
        val awake = rawAwake * soften
        val movement = rawMovement * soften
        val strain = rawStrain * soften
        val charge = sleepGain + rest
        val drain = awake + movement + strain
        val effective = if (drain > 0) min(1.0, (state.value + charge) / drain) else 1.0
        state.value = min(100.0, max(0.0, state.value + charge - drain * effective))
        state.drivers.recovery += sleepGain
        state.drivers.restorativeRest += rest
        state.drivers.awake += awake * effective
        state.drivers.movement += movement * effective
        state.drivers.stress += strain * effective
        if (!sleeping) state.awakeMinutes += tick.durationMinutes
    }

    /** Phased awake drift. A full night's first ten hours is 0.02 per five minutes.
     *  A short night adds 0.04–0.08. Past fourteen hours the slope rises to 0.10–0.15. */
    fun awakeRate(awakeHours: Double, sleepDebt: Double): Double {
        val debt = unit((sleepDebt - 1) / 0.6)
        val short = sleepDebt > 1.001
        val early = if (short) (0.04 + 0.04 * debt) else 0.02
        val late = 0.10 + 0.05 * debt
        if (awakeHours <= 10) return early
        if (awakeHours >= 14) return late
        val t = (awakeHours - 10) / 4
        return early + (late - early) * t
    }

    /** SQL counterpart: nb.reserve_rates. Correlated autonomic channels use their
     *  strongest signal; a corroborating channel adds at most 15%, not another full bill. */
    fun rates(
        heart: Double?, hrv: Double?, stress: Double?, steps: Double?, met: Double?,
        resting: Double, maximum: Double, referenceHeart: Double,
        referenceHRV: Double?, auxiliary: Double,
    ): Rates {
        val hrr = heart?.let { unit((it - resting) / max(1.0, maximum - resting)) } ?: 0.0
        val heartCost = interpolate(hrr, doubleArrayOf(0.0, 0.30, 0.40, 0.55, 0.70, 0.85, 1.0),
            doubleArrayOf(0.0, 0.06, 0.30, 1.20, 3.60, 6.40, 6.40))
        val movementKnown = met != null || steps != null
        val activityShare = if (movementKnown) max(unit(((met ?: 1.0) - 1.2) / 0.3), unit((steps ?: 0.0) / 25)) else 1.0
        val movement = maxOf(heartCost * activityShare, min(6.4, 0.12 * max(0.0, (met ?: 1.0) - 1)),
            min(6.4, (steps ?: 0.0) / 800 * 0.60))
        val signals = listOfNotNull(
            stress?.let { unit((it - 45) / 45) },
            heart?.let { unit((it - referenceHeart - 5) / 30) },
            hrv?.let { h -> referenceHRV?.let { unit((0.90 - h / it) / 0.50) } },
        ).sortedDescending()
        val intensity = unit((signals.firstOrNull() ?: 0.0) + 0.15 * (signals.getOrNull(1) ?: 0.0))
        val nonExercise = max(0.2, 1 - movement / 3.6)
        val strain = (0.65 * intensity * intensity + 0.15 * auxiliary * intensity) * nonExercise
        val recovery = (1 - intensity).pow(2) * (1 - 0.6 * auxiliary)
        val heartCalm = heart?.let { unit((resting + 15 - it) / 12) } ?: 0.0
        val motionCalm = if (movementKnown) min(unit((1.5 - (met ?: 1.0)) / 0.3), unit((25 - (steps ?: 0.0)) / 20)) else 0.0
        val calm = listOfNotNull(
            stress?.let { unit((50 - it) / 25) },
            hrv?.let { h -> referenceHRV?.let { unit((h / it - 0.65) / 0.35) } },
        )
        val support = if (calm.size == 2) 1.0 else if (calm.size == 1) 0.8 else 0.55
        val rest = heartCalm * motionCalm * (calm.minOrNull() ?: 1.0) * support * recovery
        return Rates(movement, strain, rest, recovery)
    }

    private fun sustained(risk: Double?, minutes: Double, history: MutableList<Pair<Double, Double>>): Double {
        if (risk == null) { history.clear(); return 0.0 }
        history.add(risk to minutes)
        var duration = history.sumOf { it.second }
        while (history.size > 1 && duration - history[0].second >= 15) {
            duration -= history.removeAt(0).second
        }
        return if (duration >= 15) history.minOf { it.first } else 0.0
    }

    private fun sleepQuality(stage: Int): Double = doubleArrayOf(1.25, 0.85, 1.0, 0.15, 0.0)[stage]
    private fun valid(value: Double?, lo: Double, hi: Double): Double? =
        value?.takeIf { it.isFinite() && it >= lo && it <= hi }
    private fun unit(value: Double): Double = min(1.0, max(0.0, value))
    private fun interpolate(value: Double, x: DoubleArray, y: DoubleArray): Double {
        for (i in 1 until x.size) {
            if (value <= x[i]) return y[i - 1] + (y[i] - y[i - 1]) * (value - x[i - 1]) / (x[i] - x[i - 1])
        }
        return y.last()
    }
}
