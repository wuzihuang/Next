import Foundation

/// One row of the device alarm table. Preserve text read from text-alarm firmware.
struct BandAlarm: Identifiable, Equatable, Hashable, Sendable {
    var id: Int
    var hour: Int
    var minute: Int
    var on: Bool
    var repeatMask: Int
    var date: String
    var scene: Int
    var text: String = ""

    static let onceDatePlaceholder = "0000-00-00"
    static let demoCeiling = 20
    static let silentScene = 0

    var repeats: Bool { repeatMask != 0 }
    var showsSwitch: Bool { repeats }

    var isValidDeviceValue: Bool {
        (1...255).contains(id) && (0...23).contains(hour) && (0...59).contains(minute)
            && (0...127).contains(repeatMask) && text.utf8.count <= 60
    }

    var clock: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Empty model the read command accepts. IDs and times come back from the band.
    static func emptyRead() -> BandAlarm {
        BandAlarm(id: 0, hour: 0, minute: 0, on: false, repeatMask: 0,
                  date: onceDatePlaceholder, scene: silentScene)
    }
}

enum BandAlarmProtocol: Equatable, Sendable {
    case scene, text

    init?(functionData: Data?) {
        guard let functionData, functionData.count > 17 else { return nil }
        switch functionData[17] {
        case 1...4: self = .scene
        case 5...7: self = .text
        default: return nil
        }
    }

    var capacity: Int { self == .text ? 10 : 20 }

    /// App operations are delete=0, write=1, read=2; text SDK operations start at 1.
    func sdkMode(for operation: UInt) -> UInt {
        self == .text ? operation + 1 : operation
    }
}

enum BandAlarmMath: Sendable {
    /// LSB Monday … bit 6 Sunday. Bit 7 stays 0, matching the vendor week string.
    enum Weekday: Int, CaseIterable, Sendable {
        case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

        var bit: Int { 1 << rawValue }

        var short: String {
            switch self {
            case .monday: "MON"
            case .tuesday: "TUE"
            case .wednesday: "WED"
            case .thursday: "THU"
            case .friday: "FRI"
            case .saturday: "SAT"
            case .sunday: "SUN"
            }
        }

        var pill: String {
            switch self {
            case .monday: "M"
            case .tuesday: "T"
            case .wednesday: "W"
            case .thursday: "T"
            case .friday: "F"
            case .saturday: "S"
            case .sunday: "S"
            }
        }
    }

    static let weekdaysMask =
        Weekday.monday.bit | Weekday.tuesday.bit | Weekday.wednesday.bit
        | Weekday.thursday.bit | Weekday.friday.bit
    static let weekendMask = Weekday.saturday.bit | Weekday.sunday.bit
    static let everyDayMask = 0b0111_1111

    static func has(_ mask: Int, _ day: Weekday) -> Bool {
        mask & day.bit != 0
    }

    static func toggling(_ mask: Int, _ day: Weekday) -> Int {
        mask ^ day.bit
    }

    static func phrase(_ mask: Int) -> String {
        let days = mask & everyDayMask
        if days == 0 { return "ONCE" }
        if days == everyDayMask { return "EVERY DAY" }
        if days == weekdaysMask { return "WEEKDAYS" }
        if days == weekendMask { return "WEEKEND" }
        return Weekday.allCases.filter { has(days, $0) }.map(\.short).joined(separator: " · ")
    }

    static func nextID(in alarms: [BandAlarm], ceiling: Int = BandAlarm.demoCeiling) -> Int? {
        guard ceiling > 0 else { return nil }
        let used = Set(alarms.map(\.id))
        // Match VPDeviceNewAlarmModel.getMinimumAlarmID: writable IDs start at 1.
        // Zero belongs to the empty read model, not a newly created alarm.
        return (1...ceiling).first { !used.contains($0) }
    }

    static func isFull(_ alarms: [BandAlarm], ceiling: Int = BandAlarm.demoCeiling) -> Bool {
        alarms.count >= ceiling
    }

    /// A one-shot needs a date the firmware will still accept. If today's clock
    /// already passed, the fire day is tomorrow.
    static func onceDate(hour: Int, minute: Int, now: Date, calendar: Calendar = .current) -> String {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        let today = calendar.date(from: parts) ?? now
        let fire = today > now ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        return String(format: "%04d-%02d-%02d",
                      calendar.component(.year, from: fire),
                      calendar.component(.month, from: fire),
                      calendar.component(.day, from: fire))
    }

    static func prepared(_ draft: BandAlarm, now: Date = Date(), calendar: Calendar = .current) -> BandAlarm {
        var next = draft
        next.scene = BandAlarm.silentScene
        if next.repeatMask == 0 {
            next.date = onceDate(hour: next.hour, minute: next.minute, now: now, calendar: calendar)
        } else {
            next.date = BandAlarm.onceDatePlaceholder
        }
        return next
    }
}
