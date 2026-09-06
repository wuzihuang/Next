import Foundation

/// ADR 0010 · 一次**成功完成**的主动测量留下的一行。
///
/// 主动测量 = 用户从加号菜单发起、手指按住侧键、有开始有结束的一次手环测量。第一版只有两种：
/// 身体扫描（30 秒 BIA）与平衡检查（40 秒脉律）。被动 tick（心率、压力、皮温）不是主动测量，
/// 体重录入是记录不是测量——两者都不进这个类型。
///
/// ⚠️ 失败、没读到、中途摘表的尝试不产生记录。测量屏上那句 NOTHING KEPT 是字面意思，这里
/// 没有「失败的一行」这种东西可以构造。
struct MeasurementRecord: Identifiable, Hashable {
    let id: UUID
    let at: Date
    let detail: Detail

    enum Detail: Hashable {
        case bodyScan(BodyScan)
        case balanceCheck(BalanceCheck)
    }

    /// 手环 BIA 的一次读数。落在 `body_composition` 里 `measurement_source = device_bia` 的行；
    /// health_scale 与 manual 的行不是主动测量，不进清单。
    struct BodyScan: Hashable {
        var bodyFatPercent: Double?
        var fatMassKg: Double?
        var leanMassKg: Double?
        var bmrKcal: Int?
        /// ⚠️ 手环不产生体重。BIA 是拿我们通过 syncPersonalInfo 推下去的体重算出来的，所以
        /// 这个数必须和它的来源一起显示，否则读起来像手环称出来的。
        var inputWeightKg: Double?
    }

    /// 一次平衡检查的摘要。**没有逐拍序列**：产品不呈现也不解读心律波形。
    struct BalanceCheck: Hashable {
        var lead: Lead
        /// 0–100 · SD1 / (SD1 + SD2) 的百分数。
        var restShare: Int
        var sd1Ms: Double
        var sd2Ms: Double
        var sdnnMs: Double
        var heartRate: Int?
        var beatCount: Int

        enum Lead: String, Hashable {
            case rest, drive, even

            /// 行上和 sheet 顶部那个词。
            var word: String {
                switch self {
                case .rest:  L("REST")
                case .drive: L("DRIVE")
                case .even:  L("EVEN")
                }
            }
        }

        /// 屏幕上那个 SPREAD。⚠️ 它是这次四十秒采样的 SD1，不叫 HRV 也不叫 RMSSD——夜间 HRV
        /// 是睡眠页的词，一个白天四十秒的离散度不能借那个名字，也不能和它比大小。
        var spreadMs: Double { sd1Ms }
    }

    // MARK: 行上要用的三样东西
    //
    // 模块和清单画的是同一种行，所以这三个属性只在这里算一次。两处各自再推一遍，是这两块
    // 早晚说出不同的话的方式。

    /// 类型名。
    var title: String {
        switch detail {
        case .bodyScan:     L("BODY SCAN")
        case .balanceCheck: L("BALANCE CHECK")
        }
    }

    /// 行右列那两个数。身体扫描是体脂率与瘦体重，平衡检查是结论词与心率。
    var summary: String {
        switch detail {
        case .bodyScan(let s):
            let fat = s.bodyFatPercent.map { "\(Fmt.kg($0)) %" } ?? Fmt.dash
            let lean = s.leanMassKg.map { "\(Fmt.kg($0)) KG" } ?? Fmt.dash
            return "\(fat) · \(lean)"
        case .balanceCheck(let b):
            guard let hr = b.heartRate else { return b.lead.word }
            return "\(b.lead.word) · \(hr) BPM"
        }
    }

    /// 实心点是身体扫描，空心点是平衡检查。没有第三种点——因为没有第三种主动测量。
    var isFilledDot: Bool {
        if case .bodyScan = detail { return true }
        return false
    }
}

extension MeasurementRecord {
    /// 模拟器种子。板上那几条，好让这块卡和记录页不接手环也能走通。⚠️ 真机永不走这里：
    /// 一条没有来源的测量记录比空卡糟得多。
    static var seed: [MeasurementRecord] {
        let calendar = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func scan(_ daysAgo: Int, _ h: Int, _ m: Int, fat: Double, lean: Double,
                  fatMass: Double, bmr: Int = 1_640) -> MeasurementRecord {
            MeasurementRecord(id: UUID(), at: at(daysAgo, h, m), detail: .bodyScan(.init(
                bodyFatPercent: fat, fatMassKg: fatMass, leanMassKg: lean,
                bmrKcal: bmr, inputWeightKg: 75.5)))
        }
        func balance(_ daysAgo: Int, _ h: Int, _ m: Int, lead: BalanceCheck.Lead,
                     rest: Int, hr: Int) -> MeasurementRecord {
            MeasurementRecord(id: UUID(), at: at(daysAgo, h, m), detail: .balanceCheck(.init(
                lead: lead, restShare: rest, sd1Ms: 62, sd2Ms: 74, sdnnMs: 71,
                heartRate: hr, beatCount: 44)))
        }
        return [
            scan(0, 7, 10, fat: 17.7, lean: 62.2, fatMass: 13.3, bmr: 1_642),
            scan(2, 7, 12, fat: 17.8, lean: 62.1, fatMass: 13.4),
            balance(3, 22, 10, lead: .rest, rest: 58, hr: 58),
            scan(4, 7, 30, fat: 18.0, lean: 62.3, fatMass: 13.6),
            scan(5, 7, 5, fat: 18.1, lean: 62.4, fatMass: 13.7),
            balance(8, 21, 48, lead: .even, rest: 50, hr: 63),
            scan(9, 7, 18, fat: 18.2, lean: 62.1, fatMass: 13.8, bmr: 1_636),
            scan(10, 7, 22, fat: 18.3, lean: 62.0, fatMass: 13.9),
            balance(14, 8, 3, lead: .drive, rest: 41, hr: 71),
            scan(14, 7, 8, fat: 18.4, lean: 61.9, fatMass: 14.0, bmr: 1_632),
            scan(18, 7, 15, fat: 18.5, lean: 61.8, fatMass: 14.1, bmr: 1_628),
            scan(23, 7, 6, fat: 18.6, lean: 61.7, fatMass: 14.2, bmr: 1_624),
            scan(27, 7, 20, fat: 18.8, lean: 61.5, fatMass: 14.4, bmr: 1_618),
        ]
    }
}

extension Array where Element == MeasurementRecord {
    /// 卡头右侧那句话的原料：距最近一次多少天。今天测的是 0。
    func daysSinceLatest(now: Date = Date()) -> Int? {
        guard let latest = first?.at else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: latest),
                                       to: calendar.startOfDay(for: now)).day
    }
}
