import Foundation

/// Deterministic reference for the server's per-tick reserve model.
/// Published reserve values and explanations are always loaded together from the server.
/// SDK values stay optional: absence means "do not score this term", never zero.
enum BodyBatteryEngine {
    struct Baseline: Equatable {
        var restingHeartRate: Double
        var maximumHeartRate: Double
        var hrvMS: Double?
        var recoveryMultiplier: Double
        /// How much faster today's basal drain runs because of last night. 1 at seven
        /// hours or more, 1.6 at four or fewer. A night with no record stays at 1:
        /// missing evidence is not evidence of a short night.
        var sleepDebt: Double

        init(restingHeartRate: Double, maximumHeartRate: Double,
             hrvMS: Double?, recoveryMultiplier: Double, sleepDebt: Double = 1) {
            self.restingHeartRate = restingHeartRate
            self.maximumHeartRate = max(restingHeartRate + 1, maximumHeartRate)
            self.hrvMS = hrvMS
            self.recoveryMultiplier = min(1.30, max(0.65, recoveryMultiplier))
            self.sleepDebt = min(1.6, max(1, sleepDebt))
        }
    }

    /// The server's sleep-debt term, so the phone and the settle agree on one number.
    /// A night with no sleep at all is only charged for when the wrist was there to see
    /// it: no minutes and no wear is a missing night, not a sleepless one.
    static func sleepDebt(sleptMinutes: Double?, wornThroughTheNight: Bool = false) -> Double {
        guard let slept = sleptMinutes, slept > 0 else { return wornThroughTheNight ? 1.6 : 1 }
        return 1 + 0.6 * min(1, max(0, (420 - slept) / 180))
    }

    /// A battery under load: the same request costs less as the reserve empties. The
    /// floor keeps the drain finite, which is what still lets a sleepless day reach 0.
    private static func softener(_ value: Double) -> Double {
        0.35 + 0.65 * value / 100
    }

    /// The ceiling every movement term shares — one hard hour, not three.
    private static let movementCeiling = 6.40

    struct Tick: Equatable {
        var durationMinutes: Double
        var heartRate: Int?
        var hrvMS: Double?
        var stress: Int?
        var steps: Int?
        var met: Double?
        /// Veepoo `VPAccurateSleepModel.sleepLine`: 0 deep, 1 light, 2 REM,
        /// 3 insomnia, 4 awake. nil means this instant is outside the sleep line.
        var sleepStage: Int?

        init(durationMinutes: Double = 5, heartRate: Int? = nil, hrvMS: Double? = nil,
             stress: Int? = nil, steps: Int? = nil, met: Double? = nil,
             sleepStage: Int? = nil) {
            self.durationMinutes = max(0, durationMinutes)
            self.heartRate = heartRate.flatMap { $0 > 0 ? $0 : nil }
            self.hrvMS = hrvMS.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            self.stress = stress.flatMap { (1...100).contains($0) ? $0 : nil }
            self.steps = steps.flatMap { $0 >= 0 ? $0 : nil }
            self.met = met.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            self.sleepStage = sleepStage.flatMap { (0...4).contains($0) ? $0 : nil }
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
        var restorativeBudget = 5.0
    }

    static func replay(anchor: Double, ticks: [Tick], baseline: Baseline) -> Result {
        var state = State(value: clamp(anchor))
        for tick in ticks {
            apply(tick, baseline: baseline, to: &state)
        }
        return Result(value: state.value, drivers: state.drivers, wornMinutes: state.wornMinutes)
    }

    private static func apply(_ tick: Tick, baseline: Baseline, to state: inout State) {
        guard tick.durationMinutes > 0, isWorn(tick) else {
            state.quietMinutes = 0
            return
        }

        state.wornMinutes += tick.durationMinutes
        let tickScale = tick.durationMinutes / 5

        if let stage = tick.sleepStage, stage != 4 {
            state.quietMinutes = 0
            let quality = sleepQuality(stage)
            guard quality > 0 else { return }
            let rate = 0.011 * tickScale * quality * baseline.recoveryMultiplier
            let gain = max(0, 95 - state.value) * (1 - exp(-rate))
            state.value = clamp(state.value + gain)
            state.drivers.recovery += gain
            return
        }

        let movementRate = movementDrain(tick, baseline: baseline)
        let soften = softener(state.value)
        let movement = movementRate * tickScale * soften
        let strain = autonomicDrain(tick, baseline: baseline, movement: movementRate)
            * tickScale * soften
        let awake = 0.15 * baseline.sleepDebt * tickScale * soften
        let restorative = restorativeGain(
            tick, baseline: baseline, movement: movementRate,
            state: &state
        )

        let requestedDrain = awake + movement + strain - restorative
        let scale = requestedDrain > state.value && requestedDrain > 0
            ? state.value / requestedDrain : 1
        state.value = clamp(state.value - requestedDrain * scale)
        state.drivers.awake += awake * scale
        state.drivers.movement += movement * scale
        state.drivers.stress += strain * scale
        state.drivers.restorativeRest += restorative * scale
    }

    private static func isWorn(_ tick: Tick) -> Bool {
        if tick.sleepStage != nil { return true }
        if tick.heartRate != nil || tick.hrvMS != nil || tick.stress != nil { return true }
        if let steps = tick.steps, steps > 0 { return true }
        return tick.met.map { $0 > 1.05 } ?? false
    }

    private static func sleepQuality(_ stage: Int) -> Double {
        switch stage {
        case 0: 1.25
        case 1: 0.85
        case 2: 1.00
        case 3: 0.15
        default: 0
        }
    }

    private static func movementDrain(_ tick: Tick, baseline: Baseline) -> Double {
        let heart: Double = {
            guard let heartRate = tick.heartRate else { return 0 }
            let reserve = baseline.maximumHeartRate - baseline.restingHeartRate
            let hrr = (Double(heartRate) - baseline.restingHeartRate) / reserve
            switch hrr {
            case 0.85...: return 6.40
            case 0.70...: return 3.60
            case 0.55...: return 1.20
            case 0.40...: return 0.30
            case 0.30...: return 0.06
            default: return 0
            }
        }()
        // Steps and MET stand in for heart rate when it is missing, so they stay modest:
        // they are not a second opinion about an effort heart rate already priced.
        let met = min(movementCeiling, 0.12 * max(0, (tick.met ?? 1) - 1))
        let normalizedSteps = Double(tick.steps ?? 0) * 5 / max(0.01, tick.durationMinutes)
        let steps = min(movementCeiling, normalizedSteps / 800 * 0.60)
        // Heart, MET and steps observe the same movement. The strongest trustworthy signal
        // wins so one workout is not charged three times.
        return max(heart, met, steps)
    }

    private static func autonomicDrain(_ tick: Tick, baseline: Baseline,
                                       movement: Double) -> Double {
        let stress = tick.stress.map {
            0.15 * min(1, max(0, Double($0 - 40) / 60))
        } ?? 0
        let hrvDeficit: Double = {
            guard let current = tick.hrvMS, let normal = baseline.hrvMS, normal > 0 else { return 0 }
            return 0.12 * min(1, max(0, (normal - current) / normal))
        }()
        // Optical stress during exercise partly describes the same load as HR/MET.
        let nonExerciseShare = max(0.25, 1 - movement / movementCeiling)
        return (stress + hrvDeficit) * nonExerciseShare
    }

    private static func restorativeGain(_ tick: Tick, baseline: Baseline,
                                        movement: Double,
                                        state: inout State) -> Double {
        let heartIsQuiet = tick.heartRate.map {
            Double($0) <= baseline.restingHeartRate + 8
        } ?? false
        let stressIsQuiet = tick.stress.map { $0 <= 35 } ?? false
        let hrvIsRecovered = {
            guard let current = tick.hrvMS, let normal = baseline.hrvMS else { return false }
            return current >= normal * 0.90
        }()
        let isQuiet = heartIsQuiet && stressIsQuiet && hrvIsRecovered
            && movement < 0.03 && tick.steps == 0

        guard isQuiet else {
            state.quietMinutes = 0
            return 0
        }
        let previousQuietMinutes = state.quietMinutes
        state.quietMinutes += tick.durationMinutes
        let creditedMinutes = max(0, state.quietMinutes - max(20, previousQuietMinutes))
        guard creditedMinutes > 0, state.restorativeBudget > 0, state.value < 80 else { return 0 }

        let ceilingShare = max(0, (80 - state.value) / 80)
        let gain = min(state.restorativeBudget, 0.05 * creditedMinutes / 5 * ceilingShare)
        state.restorativeBudget -= gain
        return gain
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
