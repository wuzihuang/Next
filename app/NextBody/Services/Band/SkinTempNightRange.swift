import Foundation

/// This wrist's own night range for skin temperature, and last night measured against it.
///
/// ⚠️ Skin temperature is not core body temperature. A wrist sits around 33 °C, and the
/// daytime hours run 1–2 °C below the night because the arm is out from under the covers —
/// so a daytime tick is never judged here. Only a closed night is given a verdict, and only
/// against this person's own recent nights (ADR 0009). Nothing in this file feeds training
/// load, stress or any score.
enum SkinTempNightRange {
    struct Point: Equatable, Hashable, Sendable {
        var ts: Date
        var celsius: Double
    }

    /// One recorded sleep window. `end` is the wake instant; a window whose end is still in
    /// the future is a night in progress and carries no conclusion.
    struct Night: Equatable, Hashable, Sendable {
        var start: Date
        var end: Date

        var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
        func contains(_ ts: Date) -> Bool { ts >= start && ts < end }
    }

    /// Why there is no verdict tonight. Never a reason to blank the page: the measured skin
    /// temperature is still printed beside it.
    enum Empty: String, Equatable, Sendable {
        case noNight = "NO_NIGHT"
        case nightTooShort = "SHORT"
        case tooFewTicks = "FEW_TICKS"
        case needsFiveNights = "NEEDS5"
    }

    /// Outside by up to one range width is mild; further out is well outside. The old page
    /// had one fixed ±0.3 °C step from stable straight to red, which is what called an
    /// ordinary night a deviation.
    enum Tier: String, Equatable, Sendable {
        case within, mildAbove, mildBelow, wellAbove, wellBelow

        var isAbove: Bool { self == .mildAbove || self == .wellAbove }
        var isBelow: Bool { self == .mildBelow || self == .wellBelow }
        var isMild: Bool { self == .mildAbove || self == .mildBelow }
    }

    struct Range: Equatable, Sendable {
        var lower: Double
        var upper: Double
        var median: Double
        /// How many valid nights the range was built from.
        var nights: Int

        var width: Double { upper - lower }
        func contains(_ celsius: Double) -> Bool { celsius >= lower && celsius <= upper }
    }

    struct Result: Equatable, Sendable {
        var range: Range?
        /// Valid nights behind last night, inside the look-back. Drives the learning count.
        var sampleNights: Int = 0
        var lastNightMean: Double?
        /// The window last night's verdict belongs to — the chart bands only that stretch.
        var lastNight: Night?
        /// Signed °C against the range's median. nil when there is no range or no verdict.
        var delta: Double?
        var tier: Tier?
        var minutesBelow: Int = 0
        var minutesWithin: Int = 0
        var minutesAbove: Int = 0
        var empty: Empty?
        /// The most recent skin tick, verdict or not — the page always has this to print.
        var latestSkin: Double?
        var dayMean: Double?
        var dayLow: Double?
        var dayHigh: Double?
        /// Daytime mean minus last night's mean. Described, never scored.
        var dayNightGap: Double?

        var learningNights: Int { min(sampleNights, requiredNights) }

        var analyticsState: String {
            if tier != nil { return "VERDICT" }
            return empty?.rawValue ?? "EMPTY"
        }
    }

    /// A night the band recorded for less than three hours describes a nap, not a night.
    static let minimumNightHours: Double = 3
    /// Below this share of five-minute slots the band was off the wrist for most of it.
    static let minimumCoverage: Double = 0.6
    static let requiredNights = 5
    static let maximumSampleNights = 14
    static let lookbackDays = 28
    /// A perfectly steady sleeper would otherwise collapse the range to ±0.05 °C and be
    /// called out for every ordinary night.
    static let halfWidthFloor = 0.2
    static let tickMinutes = 5

    static func make(
        points: [Point],
        nights: [Night],
        now: Date,
        calendar: Calendar = .current,
        dayBoundaryHour: Int = UserDay.boundaryHour
    ) -> Result {
        let valid = points
            .filter { $0.celsius.isFinite && (10...50).contains($0.celsius) && $0.ts <= now }
            .sorted { $0.ts < $1.ts }
        var result = Result(latestSkin: valid.last?.celsius)

        let closed = nights
            .filter { $0.end > $0.start && $0.end <= now }
            .sorted { $0.end < $1.end }
        guard let lastNight = closed.last else {
            result.empty = .noNight
            addDaytime(&result, valid: valid, nights: nights, now: now,
                       calendar: calendar, dayBoundaryHour: dayBoundaryHour)
            return result
        }

        // The sample: valid nights behind last night, inside the look-back, most recent first.
        let earliest = calendar.date(byAdding: .day, value: -lookbackDays, to: lastNight.end)
            ?? lastNight.end.addingTimeInterval(-Double(lookbackDays) * 86_400)
        let sample = closed
            .dropLast()
            .filter { $0.end >= earliest }
            .compactMap { measure($0, in: valid)?.mean }
            .suffix(maximumSampleNights)
        result.sampleNights = sample.count
        result.range = range(of: Array(sample))

        let tonight = measure(lastNight, in: valid)
        result.lastNight = lastNight
        result.lastNightMean = tonight?.mean

        if lastNight.duration < minimumNightHours * 3600 {
            result.empty = .nightTooShort
        } else if tonight == nil {
            result.empty = .tooFewTicks
        } else if result.range == nil {
            result.empty = .needsFiveNights
        }

        if let range = result.range, let tonight, result.empty == nil {
            result.delta = tonight.mean - range.median
            result.tier = tier(of: tonight.mean, in: range)
            for celsius in tonight.slotValues {
                if celsius < range.lower { result.minutesBelow += tickMinutes }
                else if celsius > range.upper { result.minutesAbove += tickMinutes }
                else { result.minutesWithin += tickMinutes }
            }
        }

        addDaytime(&result, valid: valid, nights: nights, now: now,
                   calendar: calendar, dayBoundaryHour: dayBoundaryHour)
        return result
    }

    static func tier(of celsius: Double, in range: Range) -> Tier {
        if range.contains(celsius) { return .within }
        let width = max(range.width, halfWidthFloor * 2)
        if celsius > range.upper {
            return celsius <= range.upper + width ? .mildAbove : .wellAbove
        }
        return celsius >= range.lower - width ? .mildBelow : .wellBelow
    }

    // MARK: one night

    private struct NightMeasurement {
        var mean: Double
        /// One value per occupied five-minute slot, for the minutes split.
        var slotValues: [Double]
    }

    /// nil when the band was off the wrist for too much of the window, or the night is a nap.
    private static func measure(_ night: Night, in points: [Point]) -> NightMeasurement? {
        guard night.duration >= minimumNightHours * 3600 else { return nil }
        let slots = max(1, Int(night.duration / Double(tickMinutes * 60)))

        var bySlot: [Int: Double] = [:]
        for point in points where night.contains(point.ts) {
            let slot = Int(point.ts.timeIntervalSince(night.start)) / (tickMinutes * 60)
            bySlot[slot] = point.celsius
        }
        guard !bySlot.isEmpty,
              Double(bySlot.count) / Double(slots) >= minimumCoverage,
              let mean = mean(Array(bySlot.values))
        else { return nil }

        return NightMeasurement(mean: mean, slotValues: bySlot.sorted { $0.key < $1.key }.map(\.value))
    }

    // MARK: the range

    static func range(of nightlyMeans: [Double]) -> Range? {
        guard nightlyMeans.count >= requiredNights, let centre = median(nightlyMeans)
        else { return nil }
        let deviations = nightlyMeans.map { abs($0 - centre) }
        let halfWidth = max(halfWidthFloor, 2 * (median(deviations) ?? 0))
        return Range(lower: centre - halfWidth, upper: centre + halfWidth,
                     median: centre, nights: nightlyMeans.count)
    }

    // MARK: the daytime, described only

    private static func addDaytime(_ result: inout Result, valid: [Point], nights: [Night],
                                   now: Date, calendar: Calendar, dayBoundaryHour: Int) {
        let dayStart = UserDay.containing(now, calendar: calendar,
                                          boundaryHour: dayBoundaryHour).start
        let daytime = valid
            .filter { point in
                point.ts >= dayStart && !nights.contains(where: { $0.contains(point.ts) })
            }
            .map(\.celsius)
        guard !daytime.isEmpty else { return }
        result.dayMean = mean(daytime)
        result.dayLow = daytime.min()
        result.dayHigh = daytime.max()
        if let dayMean = result.dayMean, let night = result.lastNightMean {
            result.dayNightGap = dayMean - night
        }
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
