import Foundation

enum HomeTimeline {
    enum Accent: String, Equatable {
        case meal, workout, activity, sleep, wake, stress, weighIn, bodyScan, balanceCheck
    }

    struct Meal: Equatable {
        var kcal: Int
        var protein: Int
        var carb: Int
        var fat: Int
        var photoPath: String? = nil
    }

    struct Item: Equatable, Identifiable {
        var id: String
        var at: Date
        var title: String
        var detail: String
        var accent: Accent
        var meal: Meal?
        var trailing: String?
        var endAt: Date? = nil
        var recordID: UUID? = nil

        var day: UserDay { UserDay.containing(at) }
    }

    static func visible(_ candidates: [Item], on day: UserDay,
                        earlier: Bool, now: Date, lookbackDays: Int = 6) -> [Item] {
        let start = earlier ? day.adding(days: -max(0, lookbackDays)).start : day.start
        var seen = Set<String>()
        let recorded = candidates.filter { seen.insert($0.id).inserted }
            .filter { event in
                event.at <= now && (event.endAt.map { $0 >= event.at && $0 <= now } ?? true)
            }
        let workouts = recorded.filter { $0.accent == .workout && $0.endAt != nil }
        return recorded.filter { $0.at >= start && $0.at < day.end }
            .filter { event in
                guard event.accent == .activity else { return true }
                return !workouts.contains { workout in
                    guard let end = workout.endAt, end > workout.at else { return false }
                    guard let activityEnd = event.endAt, activityEnd > event.at else {
                        return event.at >= workout.at && event.at < end
                    }
                    let overlap = min(activityEnd, end).timeIntervalSince(max(event.at, workout.at))
                    return overlap > 0 && event.at >= workout.at.addingTimeInterval(-5 * 60)
                        && activityEnd <= end.addingTimeInterval(5 * 60)
                }
            }
            .sorted { $0.at == $1.at ? $0.id < $1.id : $0.at > $1.at }
    }
}
