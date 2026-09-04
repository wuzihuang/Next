import Foundation

/// Builds the page-two RESPONSE index from the day the app already holds. Sleep windows
/// come from nights on file; optical points are a dedicated series, not origin ticks.
enum MealResponsePresentation {
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
}
