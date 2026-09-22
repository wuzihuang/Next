import Foundation

/// Deterministic reference for bb-3.0. The server publishes the complete replay;
/// this model is used for scenario tests, never to replace a settled UI value.
enum BodyBatteryEngine {
    struct Baseline: Equatable {
        var restingHeartRate: Double
        var maximumHeartRate: Double
        /// Matched-context baselines: quiet daytime RMSSD must not use sleeping RMSSD.
        var hrvMS: Double?
        var sleepHRVMS: Double?
        var daytimeHeartRate: Double
        var recoveryMultiplier: Double
        var sleepDebt: Double
        var daytimeTemperature: Double?
        var sleepingTemperature: Double?
        var temperatureScale: Double

        init(restingHeartRate: Double, maximumHeartRate: Double,
             hrvMS: Double?, recoveryMultiplier: Double, sleepDebt: Double = 1,
             sleepHRVMS: Double? = nil, daytimeHeartRate: Double? = nil,
             daytimeTemperature: Double? = nil, sleepingTemperature: Double? = nil,
             temperatureScale: Double = 0.5) {
            self.restingHeartRate = restingHeartRate.isFinite ? min(120, max(30, restingHeartRate)) : 55
            self.maximumHeartRate = maximumHeartRate.isFinite
                ? max(self.restingHeartRate + 1, maximumHeartRate) : 190
            self.hrvMS = valid(hrvMS, in: 1...300)
            self.sleepHRVMS = valid(sleepHRVMS, in: 1...300)
            self.daytimeHeartRate = valid(daytimeHeartRate, in: 30...150) ?? self.restingHeartRate + 10
            self.recoveryMultiplier = recoveryMultiplier.isFinite ? min(1.30, max(0.65, recoveryMultiplier)) : 1
            self.sleepDebt = sleepDebt.isFinite ? min(1.6, max(1, sleepDebt)) : 1
            self.daytimeTemperature = valid(daytimeTemperature, in: 10...50)
            self.sleepingTemperature = valid(sleepingTemperature, in: 10...50)
            self.temperatureScale = temperatureScale.isFinite ? max(0.5, temperatureScale) : 0.5
        }
    }

    static func sleepDebt(sleptMinutes: Double?, wornThroughTheNight: Bool = false) -> Double {
        guard let slept = sleptMinutes, slept.isFinite, slept > 0 else { return wornThroughTheNight ? 1.6 : 1 }
        return 1 + 0.6 * unit((420 - slept) / 180)
    }

    struct Tick: Equatable {
        var durationMinutes: Double
        var heartRate: Int?
        var hrvMS: Double?
        var stress: Int?
        var steps: Int?
        var met: Double?
        /// Recorded sleep staging, including a recorded nap; never inferred from pulse alone.
        var sleepStage: Int?
        var temperature: Double?
        /// Automatic, timestamp-matched night oxygen. No daytime carry-forward.
        var oxygen: Double?

        init(durationMinutes: Double = 5, heartRate: Int? = nil, hrvMS: Double? = nil,
             stress: Int? = nil, steps: Int? = nil, met: Double? = nil,
             sleepStage: Int? = nil, temperature: Double? = nil, oxygen: Double? = nil) {
            self.durationMinutes = durationMinutes.isFinite ? max(0, durationMinutes) : 0
            self.heartRate = heartRate.flatMap { (30...250).contains($0) ? $0 : nil }
            self.hrvMS = valid(hrvMS, in: 1...300)
            self.stress = stress.flatMap { (1...100).contains($0) ? $0 : nil }
            self.steps = steps.flatMap { $0 >= 0 ? $0 : nil }
            self.met = valid(met, in: 0.5...25)
            self.sleepStage = sleepStage.flatMap { (0...4).contains($0) ? $0 : nil }
            self.temperature = valid(temperature, in: 10...50)
            self.oxygen = valid(oxygen, in: 50...100)
        }
    }

    struct Drivers: Equatable {
        var recovery = 0.0
        var awake = 0.0
        var movement = 0.0
        var stress = 0.0
        var restorativeRest = 0.0
    }

    struct Result: Equatable {
        var value: Double
        var drivers: Drivers
        var wornMinutes: Double
    }

    private struct State {
        var value: Double
        var drivers = Drivers()
        var wornMinutes = 0.0
        var quietMinutes = 0.0
        var temperatureRisks: [(value: Double, minutes: Double)] = []
        var oxygenRisks: [(value: Double, minutes: Double)] = []
        var wasSleeping = false
    }

    static func replay(anchor: Double, ticks: [Tick], baseline: Baseline) -> Result {
        var state = State(value: anchor.isFinite ? min(100, max(0, anchor)) : 50)
        for tick in ticks { apply(tick, baseline: baseline, to: &state) }
        return Result(value: state.value, drivers: state.drivers, wornMinutes: state.wornMinutes)
    }

    private static func apply(_ tick: Tick, baseline: Baseline, to state: inout State) {
        let sleeping = tick.sleepStage.map { $0 != 4 } ?? false
        let worn = tick.sleepStage != nil || tick.heartRate != nil || tick.hrvMS != nil
            || tick.stress != nil || (tick.steps ?? 0) > 0 || (tick.met ?? 1) > 1.05
        guard tick.durationMinutes > 0, worn else {
            state.quietMinutes = 0
            state.temperatureRisks = []
            state.oxygenRisks = []
            return
        }
        if sleeping != state.wasSleeping {
            state.temperatureRisks = []
            state.oxygenRisks = []
        }
        state.wasSleeping = sleeping
        state.wornMinutes += tick.durationMinutes
        let scale = tick.durationMinutes / 5
        let temperatureBase = sleeping ? baseline.sleepingTemperature : baseline.daytimeTemperature
        let temperatureRisk = tick.temperature.flatMap { t in
            temperatureBase.map { unit((t - $0 - baseline.temperatureScale) / 1.0) }
        }
        let oxygenRisk = sleeping ? tick.oxygen.map { unit((95 - $0) / 5) } : nil
        let auxiliary = max(sustained(temperatureRisk, minutes: tick.durationMinutes, history: &state.temperatureRisks),
                            sustained(oxygenRisk, minutes: tick.durationMinutes, history: &state.oxygenRisks))
        let hrvBase = sleeping ? baseline.sleepHRVMS : baseline.hrvMS
        let normalizedSteps = tick.steps.map { Double($0) * 5 / max(0.01, tick.durationMinutes) }
        let rates = rates(heart: tick.heartRate.map(Double.init), hrv: tick.hrvMS,
                          stress: tick.stress.map(Double.init), steps: normalizedSteps, met: tick.met,
                          resting: baseline.restingHeartRate, maximum: baseline.maximumHeartRate,
                          referenceHeart: sleeping ? baseline.restingHeartRate : baseline.daytimeHeartRate,
                          referenceHRV: hrvBase, auxiliary: auxiliary)
        let rawAwake = sleeping ? 0 : 0.15 * baseline.sleepDebt * (1 - 0.75 * rates.rest) * scale
        let rawMovement = sleeping ? 0 : rates.movement * scale
        let rawStrain = rates.strain * (sleeping ? 0.75 : 1) * scale
        let requested = rawAwake + rawMovement + rawStrain
        // Integrate the reserve-dependent drain: one five-minute observation and
        // five one-minute intervals have the same price when the evidence is constant.
        let integrated = requested > 0 ? -expm1(-0.0065 * requested) / (0.0065 * requested) : 1
        let soften = (0.35 + 0.65 * state.value / 100) * integrated
        let previousQuiet = state.quietMinutes
        state.quietMinutes = !sleeping && rates.rest > 0 ? previousQuiet + tick.durationMinutes : 0
        // Only minutes after the sustained-evidence window earn credit; no retroactive gain.
        let credited = max(0, state.quietMinutes - max(20, previousQuiet))
        let ramp = unit((state.quietMinutes - 20) / 20)
        let rest = sleeping ? 0 : max(0, 90 - state.value)
            * (1 - exp(-0.006 * rates.rest * ramp * credited / 5))
        let sleepGain = sleeping ? max(0, 95 - state.value)
            * (1 - exp(-0.011 * sleepQuality(tick.sleepStage!) * baseline.recoveryMultiplier
                       * rates.recovery * scale)) : 0
        let awake = rawAwake * soften
        let movement = rawMovement * soften
        let strain = rawStrain * soften
        let charge = sleepGain + rest
        let drain = awake + movement + strain
        let effective = drain > 0 ? min(1, (state.value + charge) / drain) : 1
        state.value = min(100, max(0, state.value + charge - drain * effective))
        state.drivers.recovery += sleepGain
        state.drivers.restorativeRest += rest
        state.drivers.awake += awake * effective
        state.drivers.movement += movement * effective
        state.drivers.stress += strain * effective
    }

    /// SQL counterpart: nb.reserve_rates. Correlated autonomic channels use their
    /// strongest signal; a corroborating channel adds at most 15%, not another full bill.
    static func rates(heart: Double?, hrv: Double?, stress: Double?, steps: Double?, met: Double?,
                      resting: Double, maximum: Double, referenceHeart: Double,
                      referenceHRV: Double?, auxiliary: Double)
    -> (movement: Double, strain: Double, rest: Double, recovery: Double) {
        let hrr = heart.map { unit(($0 - resting) / max(1, maximum - resting)) } ?? 0
        let heartCost = interpolate(hrr, x: [0, 0.30, 0.40, 0.55, 0.70, 0.85, 1],
                                   y: [0, 0.06, 0.30, 1.20, 3.60, 6.40, 6.40])
        let movementKnown = met != nil || steps != nil
        let activityShare = movementKnown ? max(unit(((met ?? 1) - 1.2) / 0.3), unit((steps ?? 0) / 25)) : 1
        let movement = max(heartCost * activityShare, min(6.4, 0.12 * max(0, (met ?? 1) - 1)),
                           min(6.4, (steps ?? 0) / 800 * 0.60))
        let signals = [stress.map { unit(($0 - 40) / 50) },
                       heart.map { unit(($0 - referenceHeart - 5) / 30) },
                       hrv.flatMap { h in referenceHRV.map { unit((0.90 - h / $0) / 0.50) } }]
            .compactMap { $0 }.sorted(by: >)
        let intensity = unit((signals.first ?? 0) + 0.15 * (signals.dropFirst().first ?? 0))
        let nonExercise = max(0.2, 1 - movement / 3.6)
        let strain = (0.65 * intensity * intensity + 0.15 * auxiliary * intensity) * nonExercise
        let recovery = pow(1 - intensity, 2) * (1 - 0.6 * auxiliary)
        let heartCalm = heart.map { unit((resting + 15 - $0) / 12) } ?? 0
        let motionCalm = movementKnown ? min(unit((1.5 - (met ?? 1)) / 0.3), unit((25 - (steps ?? 0)) / 20)) : 0
        let calm = [stress.map { unit((50 - $0) / 25) },
                    hrv.flatMap { h in referenceHRV.map { unit((h / $0 - 0.65) / 0.35) } }].compactMap { $0 }
        let support = calm.count == 2 ? 1.0 : (calm.count == 1 ? 0.8 : 0.55)
        let rest = heartCalm * motionCalm * (calm.min() ?? 1) * support * recovery
        return (movement, strain, rest, recovery)
    }

    private static func sustained(_ risk: Double?, minutes: Double,
                                  history: inout [(value: Double, minutes: Double)]) -> Double {
        guard let risk else { history = []; return 0 }
        history.append((risk, minutes))
        var duration = history.reduce(0) { $0 + $1.minutes }
        while history.count > 1, duration - history[0].minutes >= 15 {
            duration -= history.removeFirst().minutes
        }
        return duration >= 15 ? history.map(\.value).min()! : 0
    }

    private static func sleepQuality(_ stage: Int) -> Double { [1.25, 0.85, 1, 0.15, 0][stage] }
    private static func valid(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
    }
    private static func unit(_ value: Double) -> Double { min(1, max(0, value)) }
    private static func interpolate(_ value: Double, x: [Double], y: [Double]) -> Double {
        for i in 1..<x.count where value <= x[i] {
            return y[i - 1] + (y[i] - y[i - 1]) * (value - x[i - 1]) / (x[i] - x[i - 1])
        }
        return y.last!
    }
}
