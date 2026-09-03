import Foundation

/// The automatic-measurement interval is a device capability, not an app-wide constant.
/// Veepoo reports either a positive step (step, 2 × step … 180 minutes) or zero when every
/// whole-minute value from 0 through 180 is accepted. A firmware that reports a positive
/// step may still accept finer whole-minute values, so the minutes below the step are
/// offered too — the write is only believed when the band echoes the value back.
enum AutoMeasurementIntervalPolicy {
    static let maximumMinutes = 180

    static func options(minimumStepMinutes: Int) -> [Int] {
        guard minimumStepMinutes >= 0 else { return [] }
        guard minimumStepMinutes > 0 else { return Array(0...maximumMinutes) }
        guard minimumStepMinutes <= maximumMinutes else { return [] }
        let probed = Array(1..<minimumStepMinutes)
        return probed + Array(stride(from: minimumStepMinutes,
                                     through: maximumMinutes,
                                     by: minimumStepMinutes))
    }

    static func isValid(_ minutes: Int, minimumStepMinutes: Int) -> Bool {
        options(minimumStepMinutes: minimumStepMinutes).contains(minutes)
    }
}
