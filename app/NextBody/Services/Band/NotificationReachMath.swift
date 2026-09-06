import Foundation

/// F1 Sec 03 + ADR 0019 · deep links and which notification edge may fire.
/// Pure Foundation so SyncCore can test it without UserNotifications.
enum NotificationDeepLink: Equatable, Sendable {
    case homePanel
    case fuel(slot: String?)
    case device
    case composition(day: String?)
    case logPhoto
    case training
    case home

    static func parse(_ url: URL) -> NotificationDeepLink? {
        guard url.scheme == "nextbody" else { return nil }
        let host = (url.host ?? "").lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        switch host {
        case "home":
            if query("panel") == "body_battery" { return .homePanel }
            if query("panel") == nil { return .home }
            return nil
        case "fuel":
            return .fuel(slot: query("slot"))
        case "device":
            return .device
        case "composition":
            return .composition(day: query("date"))
        case "log":
            return query("via") == "photo" ? .logPhoto : nil
        case "training":
            return .training
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .homePanel:
            return URL(string: "nextbody://home?panel=body_battery")!
        case .home:
            return URL(string: "nextbody://home")!
        case .fuel(let slot):
            if let slot, !slot.isEmpty {
                return URL(string: "nextbody://fuel?slot=\(slot)")!
            }
            return URL(string: "nextbody://fuel")!
        case .device:
            return URL(string: "nextbody://device")!
        case .composition(let day):
            if let day, !day.isEmpty {
                return URL(string: "nextbody://composition?date=\(day)")!
            }
            return URL(string: "nextbody://composition")!
        case .logPhoto:
            return URL(string: "nextbody://log?via=photo")!
        case .training:
            return URL(string: "nextbody://training")!
        }
    }
}

enum NotifyKind: String, Equatable, Sendable, CaseIterable {
    case morning, meal, training, daily, reserve, bandBattery, bandAway

    var priority: Int {
        switch self {
        case .bandBattery: return 0
        case .bandAway: return 1
        case .morning: return 2
        case .reserve: return 3
        case .training: return 4
        case .meal: return 5
        case .daily: return 6
        }
    }

    var requestId: String { "nb.notif.\(rawValue)" }

    var deepLink: NotificationDeepLink {
        switch self {
        case .morning, .reserve: return .homePanel
        case .meal: return .fuel(slot: nil)
        case .training: return .training
        case .daily: return .home
        case .bandBattery, .bandAway: return .device
        }
    }
}

enum NotifyPage: Equatable, Sendable {
    case fuel, training, device, bodyBattery, other
}

enum NotifyPlan: Equatable, Sendable {
    case skip
    case later(NotifyKind, at: Date, mealSlot: String?, weekly: Bool)
    case fire(NotifyKind, mealSlot: String?, weekly: Bool)
}

struct NotifySnapshot: Equatable, Sendable {
    var now: Date
    var quietEnabled: Bool
    var deliveredCount: Int
    var delivered: Set<NotifyKind>
    var page: NotifyPage

    var morningOn: Bool
    var trainingOn: Bool
    var mealsOn: Bool
    var wrapOn: Bool
    var energyOn: Bool
    var bandOn: Bool

    var wakePeak: Date?
    var morningShown: Bool

    var daySealed: Bool
    var mealsInLast7Days: Int
    var breakfastConfirmed: Bool
    var lunchConfirmed: Bool
    var dinnerConfirmed: Bool
    var moved: Bool

    var trainingLoad: Double?
    var targetLoad: Double?
    var reserveNow: Int?
    var prevReserve: Int?
    var bbWake: Int?
    var dayHighReserve: Int?
    var liveSession: Bool
    var reserveFresh: Bool

    var hasNightCharge: Bool
    var hasConfirmedMeal: Bool
    var weekRolled: Bool
    var priorWeekValidDays: Int
    var appOpenedAfterComplete: Bool

    var bandBound: Bool
    var bandConnected: Bool
    var bandCharging: Bool
    var bandPercent: Int?
    var bandBars: Int?
    var disconnectStarted: Date?
}

enum MorningNotifyPlan: Equatable, Sendable {
    case skip(String)
    case fireAt(Date)
}

enum NotificationReachMath: Sendable {
    static let morningHour = 7
    static let morningMinute = 0
    static let quietStartMinutes = 22 * 60 + 30
    static let quietEndMinutes = 7 * 60
    static let window: TimeInterval = 6 * 3600
    static let away: TimeInterval = 4 * 3600
    static let morningRequestId = NotifyKind.morning.requestId
    static let budget = 4
    static let reserveLine = 25
    static let bandPercentLine = 15
    static let bandBarsLine = 1
    static let trainingReserveFraction = 0.6
    static let dailyNeed = 2

    static func wakePeak(dayStart: Date, curve: [(Date, Int)]) -> Date? {
        let noon = dayStart.addingTimeInterval(8 * 3600)
        return curve.filter { $0.0 < noon }.max(by: { $0.1 < $1.1 })?.0
    }

    static func isQuiet(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hm = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        return hm >= quietStartMinutes || hm < quietEndMinutes
    }

    static func sevenAM(on day: Date, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = morningHour
        comps.minute = morningMinute
        comps.second = 0
        return calendar.date(from: comps) ?? day
    }

    static func quietEnd(after now: Date, calendar: Calendar = .current) -> Date {
        let seven = sevenAM(on: now, calendar: calendar)
        return now < seven ? seven : (calendar.date(byAdding: .day, value: 1, to: seven) ?? seven)
    }

    static func swallows(_ kind: NotifyKind, page: NotifyPage) -> Bool {
        switch (kind, page) {
        case (.morning, .bodyBattery), (.reserve, .bodyBattery): return true
        case (.meal, .fuel): return true
        case (.training, .training): return true
        case (.bandBattery, .device), (.bandAway, .device): return true
        default: return false
        }
    }

    static func nextMealSlot(_ s: NotifySnapshot) -> String? {
        if s.breakfastConfirmed, !s.lunchConfirmed { return "lunch" }
        if s.lunchConfirmed, !s.dinnerConfirmed { return "dinner" }
        if !s.breakfastConfirmed, !s.lunchConfirmed, !s.dinnerConfirmed {
            return "breakfast"
        }
        if s.breakfastConfirmed, s.lunchConfirmed, !s.dinnerConfirmed { return "dinner" }
        return nil
    }

    /// ADR 0019 · one edge, or nothing. Clock times are only the quiet gate.
    static func decide(_ s: NotifySnapshot, calendar: Calendar = .current) -> NotifyPlan {
        guard s.deliveredCount < budget else { return .skip }

        struct Cand: Equatable {
            var kind: NotifyKind
            var at: Date
            var mealSlot: String?
            var weekly: Bool
        }
        var cands: [Cand] = []

        if s.morningOn, !s.delivered.contains(.morning), let wake = s.wakePeak, !s.morningShown {
            let deadline = wake.addingTimeInterval(window)
            if s.now <= deadline {
                cands.append(Cand(kind: .morning, at: s.now, mealSlot: nil, weekly: false))
            }
        }

        if s.mealsOn, !s.delivered.contains(.meal), !s.daySealed,
           s.mealsInLast7Days >= 1, s.moved, let slot = nextMealSlot(s) {
            cands.append(Cand(kind: .meal, at: s.now, mealSlot: slot, weekly: false))
        }

        if s.trainingOn, !s.delivered.contains(.training), !s.liveSession,
           let load = s.trainingLoad, let target = s.targetLoad, load < target,
           s.reserveFresh, let nowR = s.reserveNow {
            let wake = s.bbWake ?? s.dayHighReserve
            if let wake {
                let line = Int((Double(wake) * trainingReserveFraction).rounded(.down))
                let high = max(s.dayHighReserve ?? nowR, s.prevReserve ?? nowR)
                let prev = s.prevReserve
                let crossed = nowR <= line && high > line && (prev == nil || prev! > line)
                if crossed, nowR < wake {
                    cands.append(Cand(kind: .training, at: s.now, mealSlot: nil, weekly: false))
                }
            }
        }

        if s.wrapOn, !s.delivered.contains(.daily), !s.appOpenedAfterComplete {
            var n = 0
            if s.hasNightCharge { n += 1 }
            if s.trainingLoad != nil { n += 1 }
            if s.hasConfirmedMeal { n += 1 }
            if s.reserveNow != nil, s.reserveFresh { n += 1 }
            if n >= dailyNeed {
                let weekly = s.weekRolled && s.priorWeekValidDays >= 4
                cands.append(Cand(kind: .daily, at: s.now, mealSlot: nil, weekly: weekly))
            }
        }

        if s.energyOn, !s.delivered.contains(.reserve), s.reserveFresh, let nowR = s.reserveNow {
            let wake = s.bbWake ?? s.dayHighReserve
            if let wake, nowR <= reserveLine, nowR < wake {
                let high = max(s.dayHighReserve ?? nowR, s.prevReserve ?? nowR, wake)
                if high > reserveLine {
                    cands.append(Cand(kind: .reserve, at: s.now, mealSlot: nil, weekly: false))
                }
            }
        }

        let bandUsed = s.delivered.contains(.bandBattery) || s.delivered.contains(.bandAway)
        if s.bandOn, s.bandBound, !bandUsed, !s.bandCharging {
            let low: Bool
            if let p = s.bandPercent {
                low = p <= bandPercentLine
            } else if let bars = s.bandBars {
                low = bars <= bandBarsLine
            } else {
                low = false
            }
            if low {
                cands.append(Cand(kind: .bandBattery, at: s.now, mealSlot: nil, weekly: false))
            }
        }

        if s.bandOn, s.bandBound, !s.bandConnected, !bandUsed,
           let start = s.disconnectStarted {
            cands.append(Cand(kind: .bandAway, at: start.addingTimeInterval(away), mealSlot: nil, weekly: false))
        }

        cands.removeAll { swallows($0.kind, page: s.page) }
        let ready = cands.filter { $0.at <= s.now }.sorted { $0.kind.priority < $1.kind.priority }
        let pending = cands.filter { $0.at > s.now }.sorted {
            if $0.at != $1.at { return $0.at < $1.at }
            return $0.kind.priority < $1.kind.priority
        }
        guard let pick = ready.first ?? pending.first else { return .skip }

        var when = pick.at
        if s.quietEnabled, isQuiet(when, calendar: calendar) || isQuiet(s.now, calendar: calendar), when <= s.now {
            when = max(when, quietEnd(after: s.now, calendar: calendar))
        } else if s.quietEnabled, isQuiet(when, calendar: calendar), when > s.now {
            when = max(when, quietEnd(after: when, calendar: calendar))
        }

        if when > s.now {
            return .later(pick.kind, at: when, mealSlot: pick.mealSlot, weekly: pick.weekly)
        }
        return .fire(pick.kind, mealSlot: pick.mealSlot, weekly: pick.weekly)
    }

    /// Disconnect clock. Callers may schedule this even when another edge fires now.
    static func awayFireAt(_ s: NotifySnapshot) -> Date? {
        let bandUsed = s.delivered.contains(.bandBattery) || s.delivered.contains(.bandAway)
        guard s.bandOn, s.bandBound, !s.bandConnected, !bandUsed,
              let start = s.disconnectStarted else { return nil }
        return start.addingTimeInterval(away)
    }

    /// Kept for the 昨夜 window / quiet helpers the panel still shares.
    static func planMorning(
        now: Date,
        wakePeak: Date?,
        alreadyShown: Bool,
        morningEnabled: Bool,
        quietEnabled: Bool,
        calendar: Calendar = .current
    ) -> MorningNotifyPlan {
        let snap = NotifySnapshot(
            now: now, quietEnabled: quietEnabled, deliveredCount: 0, delivered: [],
            page: .other, morningOn: morningEnabled, trainingOn: false, mealsOn: false,
            wrapOn: false, energyOn: false, bandOn: false, wakePeak: wakePeak,
            morningShown: alreadyShown, daySealed: false, mealsInLast7Days: 0,
            breakfastConfirmed: false, lunchConfirmed: false, dinnerConfirmed: false,
            moved: false, trainingLoad: nil, targetLoad: nil, reserveNow: nil,
            prevReserve: nil, bbWake: nil, dayHighReserve: nil, liveSession: false,
            reserveFresh: false, hasNightCharge: false, hasConfirmedMeal: false,
            weekRolled: false, priorWeekValidDays: 0, appOpenedAfterComplete: false,
            bandBound: false, bandConnected: true, bandCharging: false,
            bandPercent: nil, bandBars: nil, disconnectStarted: nil)
        switch decide(snap, calendar: calendar) {
        case .skip: return alreadyShown ? .skip("ALREADY_SHOWN")
            : wakePeak == nil ? .skip("NO_NIGHT")
            : !morningEnabled ? .skip("OFF")
            : .skip("PAST_WINDOW")
        case .later(_, let at, _, _): return .fireAt(at)
        case .fire: return .fireAt(now)
        }
    }
}
