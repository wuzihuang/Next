import Foundation

/// Per-session, transport-independent metrics. The adapter must normalize native energy
/// into kcal before calling this type; native reports are cumulative, never increments.
struct SportMetricAccumulator {
    enum CalorieSource: Equatable { case estimate, band }
    struct CalorieCorrection: Equatable {
        let previousKcal: Double
        let replacementKcal: Double
    }

    static let liveWindow: TimeInterval = 15
    let heartRate: Int?
    let heartRateAt: Date?
    let kcal: Double
    let calorieSource: CalorieSource
    /// An authoritative downward correction is explicit, including estimate-to-band zero.
    /// Cleared on the next report; callers can announce or log the source correction.
    let calorieCorrection: CalorieCorrection?
    /// Seconds covered by adjacent, valid reports in the current estimate. This is
    /// evidence coverage, not the session clock.
    let estimatedSeconds: TimeInterval
    let sampleCount: Int
    let peakHR: Int?
    private let heartRateSum: Int
    private let integrationAt: Date?
    private let integrationRate: Double?
    private let profile: EnergyProfile?
    private let strengthMet: Double?

    var averageHR: Int? { sampleCount == 0 ? nil : heartRateSum / sampleCount }
    var estimationAvailable: Bool {
        strengthMet == nil ? profile?.age != nil : profile != nil
    }
    /// A complete profile only makes an estimate possible. A number becomes
    /// publishable after a valid interval, or after an authoritative native report.
    var hasEnergyEvidence: Bool { calorieSource == .band || estimatedSeconds > 0 }

    init(weightKg: Double?, age: Int?, male: Bool, sportMode: Int? = nil) {
        self.init(heartRate: nil, heartRateAt: nil, kcal: 0, calorieSource: .estimate,
                  calorieCorrection: nil, estimatedSeconds: 0,
                  sampleCount: 0, peakHR: nil, heartRateSum: 0,
                  integrationAt: nil, integrationRate: nil,
                  profile: EnergyProfile(weightKg: weightKg, age: age, male: male),
                  strengthMet: Self.strengthMET(sportMode: sportMode))
    }

    private init(heartRate: Int?, heartRateAt: Date?, kcal: Double,
                 calorieSource: CalorieSource, calorieCorrection: CalorieCorrection?,
                 estimatedSeconds: TimeInterval,
                 sampleCount: Int, peakHR: Int?, heartRateSum: Int,
                 integrationAt: Date?, integrationRate: Double?, profile: EnergyProfile?,
                 strengthMet: Double?) {
        self.heartRate = heartRate
        self.heartRateAt = heartRateAt
        self.kcal = kcal
        self.calorieSource = calorieSource
        self.calorieCorrection = calorieCorrection
        self.estimatedSeconds = estimatedSeconds
        self.sampleCount = sampleCount
        self.peakHR = peakHR
        self.heartRateSum = heartRateSum
        self.integrationAt = integrationAt
        self.integrationRate = integrationRate
        self.profile = profile
        self.strengthMet = strengthMet
    }

    func liveHR(at timestamp: Date) -> Int? {
        guard let heartRateAt else { return nil }
        let age = timestamp.timeIntervalSince(heartRateAt)
        return age >= 0 && age < Self.liveWindow ? heartRate : nil
    }

    /// nil runState is the heart-test fallback. Explicit paused/stopped/unknown states
    /// cannot establish contact or contribute HR samples. Never clamp a raw sentinel
    /// into the valid byte range, or smooth a real abrupt heart-rate change.
    func accepting(timestamp: Date, heartRate rawHR: Int?, caloriesKcal: Double?,
                   runState: Int?) -> Self {
        guard timestamp.timeIntervalSince1970.isFinite else { return interrupted() }
        let running = runState == nil || runState == 1
        let beat = running
            ? rawHR.flatMap { (1...255).contains($0) ? $0 : nil } : nil
        let native = caloriesKcal.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let source: CalorieSource = native == nil ? calorieSource : .band
        let rate: Double?
        if source != .estimate {
            rate = nil
        } else if let strengthMet {
            // Strength evidence requires an explicit band running state. A fallback
            // heart callback may still be displayed, but it cannot prove duration.
            rate = runState == 1 ? profile?.netKcalPerMinute(met: strengthMet) : nil
        } else {
            rate = beat.flatMap { profile?.kcalPerMinute(heartRate: $0) }
        }
        let elapsed = integrationAt.map { timestamp.timeIntervalSince($0) }
        let estimate: (kcal: Double, seconds: TimeInterval) = source == .estimate
            ? integrated(rate: rate, elapsed: elapsed) : (0, 0)
        let total = native ?? (kcal + estimate.kcal)
        let correction = total < kcal
            ? CalorieCorrection(previousKcal: kcal, replacementKcal: total) : nil
        let baselineAllowed = rate != nil && (elapsed.map { $0 >= 0 } ?? true)
        return Self(heartRate: beat, heartRateAt: beat == nil ? nil : timestamp,
                    kcal: total, calorieSource: source, calorieCorrection: correction,
                    estimatedSeconds: estimatedSeconds + estimate.seconds,
                    sampleCount: sampleCount + (beat == nil ? 0 : 1),
                    peakHR: beat.map { max(peakHR ?? $0, $0) } ?? peakHR,
                    heartRateSum: heartRateSum + (beat ?? 0),
                    integrationAt: baselineAllowed ? timestamp : nil,
                    integrationRate: baselineAllowed ? rate : nil, profile: profile,
                    strengthMet: strengthMet)
    }

    /// A disconnect, stream replacement or loss of contact cannot bridge an energy interval.
    /// Totals and accepted sample statistics survive interruptions within this session.
    func interrupted() -> Self {
        Self(heartRate: nil, heartRateAt: nil, kcal: kcal, calorieSource: calorieSource,
             calorieCorrection: nil, estimatedSeconds: estimatedSeconds,
             sampleCount: sampleCount, peakHR: peakHR, heartRateSum: heartRateSum,
             integrationAt: nil, integrationRate: nil, profile: profile,
             strengthMet: strengthMet)
    }

    private func integrated(rate: Double?, elapsed: TimeInterval?) -> (kcal: Double, seconds: TimeInterval) {
        guard let rate, let previous = integrationRate, let elapsed,
              elapsed > 0, elapsed <= Self.liveWindow else { return (0, 0) }
        let result = (previous / 2 + rate / 2) * elapsed / 60
        return result.isFinite && result >= 0 && (kcal + result).isFinite
            ? (result, elapsed) : (0, 0)
    }

    /// Conservative session-average MET values from the 2024 Adult Compendium.
    /// These modes are explicit strength activities in the SDK catalog. Ambiguous
    /// modes such as Fitness/Common remain on the existing heart-rate path.
    static func strengthMET(sportMode: Int?) -> Double? {
        switch sportMode {
        case 25, 47: return 3.5 // weightlifting / dumbbell, general multi-exercise
        case 29: return 5.0     // squat training, slow or explosive effort
        case 46: return 3.0     // body-weight resistance, general
        default: return nil
        }
    }

    private struct EnergyProfile {
        let weightKg: Double
        let age: Int?
        let male: Bool

        init?(weightKg: Double?, age: Int?, male: Bool) {
            guard let weightKg, weightKg.isFinite, weightKg > 0 else { return nil }
            self.weightKg = weightKg
            self.age = age.flatMap { $0 > 0 ? $0 : nil }
            self.male = male
        }

        /// Existing Keytel estimate; it is used only while native energy is unavailable.
        func kcalPerMinute(heartRate: Int) -> Double? {
            guard let age else { return nil }
            let h = Double(heartRate), a = Double(age)
            let kj = male
                ? -55.0969 + 0.6309 * h + 0.1988 * weightKg + 0.2017 * a
                : -20.4022 + 0.4472 * h - 0.1263 * weightKg + 0.0740 * a
            let rate = kj / 4.184
            return rate.isFinite ? max(0, rate) : nil
        }

        /// Net activity energy, excluding the standard 1 MET already represented
        /// by the daily resting-energy component.
        func netKcalPerMinute(met: Double) -> Double? {
            let rate = max(0, met - 1) * 3.5 * weightKg / 200
            return rate.isFinite ? rate : nil
        }
    }
}
