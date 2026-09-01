import Foundation

/// 13 · 昨夜与 Body Battery.
/// Sleep never reaches the screen (F0 rule 03). Duration, stages and depth ratios exist only
/// as inputs to this model; what the user sees is how much last night charged the battery,
/// plus one of four words.
enum BodyBattery {

    /// 13 · Sec 04 — nine bands, no interpolation inside a band.
    /// The target is fixed at wake and does not move as the battery drains through the day;
    /// a target that slid every five minutes would read as a live number and people would chase it.
    struct Band {
        let range: ClosedRange<Int>
        let target: Double
        let optimal: ClosedRange<Double>
        let ringPercent: Int
        let dayLooksLike: String
    }

    static let bands: [Band] = [
        .init(range: 0...19,   target: 4.0,  optimal: 0.0...6.0,   ringPercent: 19,
              dayLooksLike: "今天什么都不练是一个合法答案，落在区间里，不是失败"),
        .init(range: 20...29,  target: 6.0,  optimal: 3.0...8.5,   ringPercent: 29,
              dayLooksLike: "走路和日常活动就够到区间"),
        .init(range: 30...39,  target: 8.0,  optimal: 5.0...10.5,  ringPercent: 38,
              dayLooksLike: "一次轻度有氧"),
        .init(range: 40...49,  target: 10.0, optimal: 7.0...12.5,  ringPercent: 48,
              dayLooksLike: "一次中等强度的课"),
        .init(range: 50...59,  target: 11.5, optimal: 8.5...14.0,  ringPercent: 55,
              dayLooksLike: "正常一天"),
        .init(range: 60...69,  target: 13.0, optimal: 10.5...15.5, ringPercent: 62,
              dayLooksLike: "正常一天，可以加一次力量"),
        .init(range: 70...79,  target: 14.5, optimal: 12.5...16.5, ringPercent: 69,
              dayLooksLike: "身体准备好了，一次力量正好"),
        .init(range: 80...89,  target: 16.0, optimal: 14.0...18.0, ringPercent: 76,
              dayLooksLike: "身体准备好了，可以上强度"),
        // The full ring stays above the top band: the target is never allowed to reach 21.
        .init(range: 90...100, target: 18.0, optimal: 15.5...20.0, ringPercent: 86,
              dayLooksLike: "满环 21 依然留在上面，不许把目标顶到 21"),
    ]

    static func band(for wake: Int) -> Band {
        bands.first { $0.range.contains(max(0, min(100, wake))) } ?? bands[0]
    }

    /// The four words the morning line is allowed to use. There is no fifth.
    static func chargeWord(_ delta: Int) -> String {
        switch delta {
        case ..<20:  return "LIGHT CHARGE"
        case ..<32:  return "BELOW USUAL"
        case ..<45:  return "NORMAL CHARGE"
        default:     return "FULL CHARGE"
        }
    }

    /// 13 · Sec 02 — discharge is three independent terms added together, never a product.
    /// The detail page has to list those three lines separately; a multiplicative model
    /// cannot be taken apart, and if it cannot be taken apart the page has no reason to exist.
    struct Tick {
        var awakeBase: Double = 0.30       // per tick
        var activity: Double = 0            // 0.22 × Δmet above 1
        var stress: Double = 0              // 0.25 × (stress − 40), only above 40
        var sleepCharge: Double = 0         // 0.75 × q × M while asleep
    }

    /// Clamps: awake recharge tops out at 95, the daily rest budget is 25,
    /// M sits between 0.65 and 1.30, and a cold-start first night begins at 20.
    enum Clamp {
        static let awakeRechargeCeiling = 95.0
        static let dailyRestBudget = 25.0
        static let mRange = 0.65...1.30
        static let coldStartFloor = 20.0
    }

    static func apply(_ t: Tick, to level: Double, asleep: Bool) -> Double {
        let delta = asleep ? t.sleepCharge : -(t.awakeBase + t.activity + t.stress)
        return min(100, max(0, level + delta))
    }
}
