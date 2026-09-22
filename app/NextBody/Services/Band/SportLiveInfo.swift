import Foundation

/// One report from the band during a sport mode. Zero energy/duration are valid;
/// an unknown energy unit must never be presented as kcal.
struct SportLiveInfo: Hashable, Sendable {
    /// SDK callback receipt, not an inferred device sampling timestamp.
    var receivedAt: Date = Date()
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
                             runState: Int, distanceM: Int? = nil, receivedAt: Date = Date()) -> Self {
        Self(receivedAt: receivedAt, heartRate: (1...255).contains(heartRate) ? heartRate : nil,
             caloriesKcal: nil, rawCalories: rawCalories, distanceM: distanceM,
             durationSec: durationSec >= 0 ? durationSec : nil, runState: runState)
    }
}

/// Presentation freshness is deliberately independent of calorie/training integration.
/// A 1 Hz poll is not proof the firmware sampled at 1 Hz; the SDK exposes no sample clock.
enum SportHeartFreshness {
    enum State { case live, stale, missing }
    static func state(receivedAt: Date?, now: Date) -> State {
        guard let receivedAt else { return .missing }
        let age = now.timeIntervalSince(receivedAt)
        guard age.isFinite, age >= 0, age < 10 else { return .missing }
        return age < 3 ? .live : .stale
    }
}
