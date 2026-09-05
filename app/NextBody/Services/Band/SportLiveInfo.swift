import Foundation

/// One report from the band during a sport mode. Zero energy/duration are valid;
/// an unknown energy unit must never be presented as kcal.
struct SportLiveInfo: Hashable, Sendable {
    var heartRate: Int?
    /// Only populated by a source with a verified kcal contract, including a valid zero.
    var caloriesKcal: Double?
    /// VPDeviceSportControlModel does not document this counter's unit or availability.
    var rawCalories: UInt32?
    var distanceM: Int?
    var durationSec: Int?
    /// 0 not started · 1 running · 2 paused
    var runState: Int?

    static func deviceReport(heartRate: Int, rawCalories: UInt32, durationSec: Int,
                             runState: Int, distanceM: Int? = nil) -> Self {
        Self(heartRate: (1...255).contains(heartRate) ? heartRate : nil,
             caloriesKcal: nil, rawCalories: rawCalories, distanceM: distanceM,
             durationSec: durationSec >= 0 ? durationSec : nil, runState: runState)
    }
}
