import Foundation

/// Builds the page-two RESPONSE index from the day the app already holds. Sleep windows
/// come from nights on file; optical points are a dedicated series, not origin ticks.
enum MealResponsePresentation {
    struct Board: Equatable, Sendable {
        var index: MealResponseIndex.Result
        var range: RollingPills
        var window: MealResponseIndex.HorizonWindow

        var heroPoint: Double? {
            switch range {
            case .day: return index.latestPoint
            case .week, .month: return window.dailyMean
            }
        }

        var heroPercent: Int? {
            switch range {
            case .day: return index.hero
            case .week, .month:
                guard let mean = window.dailyMean else { return nil }
                return MealResponseIndex.percent(of: mean, ownMedian: index.ownMedian ?? 0)
            }
        }

        var split: (below: Int, near: Int, above: Int) {
            switch range {
            case .day: return (index.below, index.near, index.above)
            case .week, .month: return (window.below, window.near, window.above)
            }
        }

        var pointCount: Int {
            switch range {
            case .day: return index.trendPoints.count
            case .week, .month: return window.points.count
            }
        }
    }

    static func index(
        today: DailyMetrics,
        history: [DailyMetrics],
        points: [MealResponseIndex.Point],
        zerosToday: Bool,
        now: Date = Date(),
        switchOff: Bool = OpticalAutoSwitch.isOff
    ) -> MealResponseIndex.Result {
        let windows = ([today] + history).compactMap { day -> MealResponseIndex.SleepWindow? in
            guard let start = day.sleep?.sleepStart, let wake = day.sleep?.wakeAt, wake > start
            else { return nil }
            return MealResponseIndex.SleepWindow(start: start, end: wake)
        }
        return MealResponseIndex.make(
            points: points,
            sleepWindows: windows,
            now: now,
            switchOff: switchOff,
            allZeros: zerosToday)
    }

    static func board(
        today: DailyMetrics,
        history: [DailyMetrics],
        points: [MealResponseIndex.Point],
        zerosToday: Bool,
        now: Date = Date(),
        range: RollingPills = .day,
        switchOff: Bool = OpticalAutoSwitch.isOff
    ) -> Board {
        let index = index(
            today: today, history: history, points: points,
            zerosToday: zerosToday, now: now, switchOff: switchOff)
        return Board(
            index: index,
            range: range,
            window: MealResponseIndex.horizonWindow(
                points: points,
                ownMedian: index.ownMedian,
                now: now,
                horizon: DetailWindow(.response, range).responseHorizon))
    }
}
