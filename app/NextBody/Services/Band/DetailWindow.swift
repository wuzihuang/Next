import Foundation

/// Surface-specific overrides on top of `RollingPills`: period words, load,
/// debug keys, and HEART slot minutes. Grain lives on the pills; hero
/// arithmetic stays in each page's WindowMath.
///
/// ⚠️ Fuel's month is 28 user days (four weeks, spoken as a typical day). Everything
/// else that counts days uses 30. Sleep counts nights. Every DAY window is the user day.
enum DetailSurface: String, Sendable {
    case sleep, heart, response, metric, active, fuel, training, composition, battery
    /// 13 / ADR 0017 · 身体电量。跟设备页的 `.battery` 不是同一个表面。
    case bodyBattery
}

struct DetailWindow: Hashable, Sendable {
    var surface: DetailSurface
    var range: RollingPills

    init(_ surface: DetailSurface, _ range: RollingPills) {
        self.surface = surface
        self.range = range
    }

    init?(_ surface: DetailSurface, raw: String) {
        guard let range = RollingPills(rawValue: raw) else { return nil }
        self.surface = surface
        self.range = range
    }

    /// Slots drawn. Sleep counts nights. Fuel month is 28. Battery day is still 1 (24h).
    var days: Int {
        range.userDays(month: surface == .fuel ? 28 : 30)
    }

    var hours: Int { days * 24 }

    /// English source for `L()`. Metric / active day is empty — the instrument keeps its own label.
    var periodKey: String {
        switch (surface, range) {
        case (.sleep, .day): return "LAST NIGHT"
        case (.sleep, .week): return "LAST 7 NIGHTS"
        case (.sleep, .month): return "LAST 30 NIGHTS"
        // Issue #19 · a day is a day. No surface answers DAY with a rolling 24 hours.
        case (.heart, .day), (.response, .day), (.battery, .day),
             (.fuel, .day), (.training, .day), (.composition, .day), (.bodyBattery, .day): return "TODAY"
        case (.metric, .day), (.active, .day): return ""
        case (.fuel, .week): return "7 DAYS"
        case (.fuel, .month): return "4 WEEKS"
        case (_, .week): return "LAST 7 DAYS"
        case (_, .month): return "LAST 30 DAYS"
        }
    }

    var slotMinutes: Double {
        switch (surface, range) {
        case (.heart, .day), (.metric, .day), (.active, .day): return 15
        case (.heart, _), (.metric, _), (.active, _): return 1440
        default: return 0
        }
    }

    var responseHorizon: MealResponseIndex.Horizon {
        switch range {
        case .day: return .userDays(1)
        case .week: return .userDays(7)
        case .month: return .userDays(30)
        }
    }

    var debugEnvironmentKey: String {
        switch surface {
        case .sleep: return "NB_DEBUG_SLEEP_RANGE"
        case .heart: return "NB_DEBUG_HEART_RANGE"
        case .response: return "NB_DEBUG_RESPONSE_RANGE"
        case .metric, .active: return "NB_DEBUG_METRIC_RANGE"
        case .fuel: return "NB_DEBUG_FUEL_RANGE"
        case .training: return "NB_DEBUG_TRAINING_RANGE"
        case .composition: return "NB_DEBUG_COMP_RANGE"
        case .battery: return "NB_DEBUG_BATTERY_RANGE"
        case .bodyBattery: return "NB_DEBUG_BODY_BATTERY_RANGE"
        }
    }

    enum Load: Equatable, Sendable {
        case none
        case dailyResults(lookback: Int)
        case heartTicks(days: Int)
        case dailyResultsAndHeartTicks(lookback: Int, heartDays: Int)
        case composition
    }

    var load: Load {
        switch surface {
        case .sleep, .response:
            return .none
        case .battery:
            return .dailyResults(lookback: DetailWindow(.battery, .month).days - 1)
        case .composition:
            return .composition
        case .fuel:
            return .dailyResults(lookback: DetailWindow(.fuel, .month).days - 1)
        case .training, .bodyBattery:
            return .dailyResults(lookback: DetailWindow(.training, .month).days - 1)
        case .heart:
            return range == .day ? .none : .heartTicks(days: days)
        case .metric:
            // The week hero says how the window compares with the seven days before it,
            // and STRESS and TEMP can only say that from ticks — so a week pulls fourteen.
            // The month's comparison would need sixty and is left unsaid instead.
            return range == .day ? .none : .heartTicks(days: range == .week ? days * 2 : days)
        case .active:
            return range == .day
                ? .dailyResults(lookback: 6)
                : .dailyResultsAndHeartTicks(lookback: days - 1, heartDays: days)
        }
    }

    static func debugRange(for surface: DetailSurface) -> RollingPills? {
        #if DEBUG
        let key = DetailWindow(surface, .day).debugEnvironmentKey
        guard let raw = ProcessInfo.processInfo.environment[key] else { return nil }
        return RollingPills(rawValue: raw)
        #else
        return nil
        #endif
    }
}
