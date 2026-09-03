import Foundation

/// A deterministic five-minute reserve model shared by stored-tick replay and the live preview.
/// SDK values stay optional: absence means "do not score this term", never zero.
enum BodyBatteryEngine {
    struct Baseline: Equatable {
        var restingHeartRate: Double
        var maximumHeartRate: Double
        var hrvMS: Double?
        var recoveryMultiplier: Double

        init(restingHeartRate: Double, maximumHeartRate: Double,
             hrvMS: Double?, recoveryMultiplier: Double) {
            self.restingHeartRate = restingHeartRate
            self.maximumHeartRate = max(restingHeartRate + 1, maximumHeartRate)
            self.hrvMS = hrvMS
            self.recoveryMultiplier = min(1.30, max(0.70, recoveryMultiplier))
        }
    }

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
        let movement = movementRate * tickScale
        let strain = autonomicDrain(tick, baseline: baseline, movement: movementRate) * tickScale
        let awake = 0.12 * tickScale
        let restorative = restorativeGain(
            tick, baseline: baseline, movement: movementRate,
            tickScale: tickScale, state: &state
        )

        state.value = clamp(state.value - awake - movement - strain + restorative)
        state.drivers.awake += awake
        state.drivers.movement += movement
        state.drivers.stress += strain
        state.drivers.restorativeRest += restorative
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
            case 0.85...: return 0.75
            case 0.70...: return 0.38
            case 0.55...: return 0.16
            case 0.40...: return 0.06
            case 0.30...: return 0.02
            default: return 0
            }
        }()
        let met = min(0.75, 0.08 * max(0, (tick.met ?? 1) - 1))
        let normalizedSteps = Double(tick.steps ?? 0) * 5 / max(0.01, tick.durationMinutes)
        let steps = min(0.75, normalizedSteps / 800 * 0.50)
        // Heart, MET and steps observe the same movement. The strongest trustworthy signal
        // wins so one workout is not charged three times.
        return max(heart, met, steps)
    }

    private static func autonomicDrain(_ tick: Tick, baseline: Baseline,
                                       movement: Double) -> Double {
        let stress = tick.stress.map {
            0.10 * min(1, max(0, Double($0 - 40) / 60))
        } ?? 0
        let hrvDeficit: Double = {
            guard let current = tick.hrvMS, let normal = baseline.hrvMS, normal > 0 else { return 0 }
            return 0.08 * min(1, max(0, (normal - current) / normal))
        }()
        // Optical stress during exercise partly describes the same load as HR/MET.
        let nonExerciseShare = max(0.25, 1 - movement / 0.75)
        return (stress + hrvDeficit) * nonExerciseShare
    }

    private static func restorativeGain(_ tick: Tick, baseline: Baseline,
                                        movement: Double, tickScale: Double,
                                        state: inout State) -> Double {
        let heartIsQuiet = tick.heartRate.map {
            Double($0) <= baseline.restingHeartRate + 8
        } ?? false
        let stressIsQuiet = tick.stress.map { $0 <= 35 } ?? true
        let hrvIsRecovered = {
            guard let current = tick.hrvMS, let normal = baseline.hrvMS else { return true }
            return current >= normal * 0.90
        }()
        let isQuiet = heartIsQuiet && stressIsQuiet && hrvIsRecovered
            && movement < 0.03 && (tick.steps ?? 0) == 0

        guard isQuiet else {
            state.quietMinutes = 0
            return 0
        }
        state.quietMinutes += tick.durationMinutes
        guard state.quietMinutes >= 20, state.restorativeBudget > 0, state.value < 80 else { return 0 }

        let ceilingShare = max(0, (80 - state.value) / 80)
        let gain = min(state.restorativeBudget, 0.05 * tickScale * ceilingShare)
        state.restorativeBudget -= gain
        return gain
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
