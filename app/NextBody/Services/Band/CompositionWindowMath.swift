import Foundation

/// One `body_composition` row the page is allowed to draw. Only fields that actually
/// land in Postgres — SDK extras that never left RAM are not here.
struct CompositionScan: Equatable, Sendable, Identifiable {
    var id: UUID
    var at: Date
    var bodyFatPercent: Double?
    var fatMassKg: Double?
    var leanMassKg: Double?
    var bmrKcal: Double?
    var inputWeightKg: Double?
}

struct CompositionPoint: Equatable, Sendable {
    var at: Date
    var day: UserDay
    var value: Double
    var x: Double
}

struct CompositionPlot: Equatable, Sendable {
    var runs: [[CompositionPoint]]
    var bandLow: Double?
    var bandHigh: Double?
    var median: Double?
    var yMin: Double
    var yMax: Double
    var start: Date
    var end: Date
    var now: Double?
    var windowLow: Double?
    var windowHigh: Double?
    var scanCount: Int

    var points: [CompositionPoint] { runs.flatMap { $0 } }
}

struct CompositionFieldDelta: Equatable, Sendable {
    var before: Double?
    var now: Double?

    var delta: Double? {
        guard let now, let before else { return nil }
        return now - before
    }
}

struct CompositionDayReading: Equatable, Sendable {
    var current: CompositionScan
    var previous: CompositionScan?
    var bodyFat: CompositionFieldDelta
    var fatMass: CompositionFieldDelta
    var leanMass: CompositionFieldDelta
    var bmr: CompositionFieldDelta
    var inputWeight: CompositionFieldDelta
}

struct CompositionWeekBucket: Equatable, Sendable {
    /// 0 is the week ending on the focus day; 1 is the seven days before that.
    var offset: Int
    var start: UserDay
    var end: UserDay
    var averageFat: Double?
    var scanCount: Int
    var delta: Double?
}

struct CompositionSpan: Equatable, Sendable {
    var first: Double?
    var last: Double?
}

/// Arithmetic for the composition page's three windows. No SwiftUI: the view only
/// lays out what this file already reduced.
enum CompositionWindowMath {
    static func bounds(range: RollingPills, endingOn day: UserDay, now: Date) -> (start: Date, end: Date) {
        let last = min(now, day.end)
        let days = DetailWindow(.composition, range).days
        return (day.adding(days: -(days - 1)).start, last)
    }

    /// Newest first, then filtered. A scan after `end` is someone else's tomorrow.
    static func asOf(_ scans: [CompositionScan], end: Date) -> [CompositionScan] {
        scans.filter { $0.at <= end }.sorted { $0.at > $1.at }
    }

    static func inWindow(_ scans: [CompositionScan], from start: Date, to end: Date) -> [CompositionScan] {
        scans.filter { $0.at >= start && $0.at <= end }.sorted { $0.at < $1.at }
    }

    static func current(in scans: [CompositionScan], asOf end: Date) -> CompositionScan? {
        asOf(scans, end: end).first
    }

    static func previous(before scan: CompositionScan, in scans: [CompositionScan]) -> CompositionScan? {
        asOf(scans, end: scan.at.addingTimeInterval(-0.001)).first
    }

    static func dayReading(scans: [CompositionScan], asOf end: Date) -> CompositionDayReading? {
        guard let current = current(in: scans, asOf: end) else { return nil }
        let previous = previous(before: current, in: scans)
        return CompositionDayReading(
            current: current,
            previous: previous,
            bodyFat: .init(before: previous?.bodyFatPercent, now: current.bodyFatPercent),
            fatMass: .init(before: previous?.fatMassKg, now: current.fatMassKg),
            leanMass: .init(before: previous?.leanMassKg, now: current.leanMassKg),
            bmr: .init(before: previous?.bmrKcal, now: current.bmrKcal),
            inputWeight: .init(before: previous?.inputWeightKg, now: current.inputWeightKg)
        )
    }

    /// One point a user day: the latest scan that day. Empty days stay empty.
    static func weekPoints(scans: [CompositionScan], days: [UserDay]) -> [CompositionPoint] {
        guard !days.isEmpty else { return [] }
        let denom = max(1, days.count - 1)
        return days.enumerated().compactMap { index, day in
            let onDay = scans.filter { UserDay.containing($0.at) == day }
            guard let last = onDay.max(by: { $0.at < $1.at }),
                  let value = last.bodyFatPercent else { return nil }
            return CompositionPoint(
                at: last.at,
                day: day,
                value: value,
                x: Double(index) / Double(denom)
            )
        }
    }

    /// Adjacent measured days stay one run. A gap day breaks the line.
    static func runs(from points: [CompositionPoint], days: [UserDay]) -> [[CompositionPoint]] {
        var runs: [[CompositionPoint]] = []
        var current: [CompositionPoint] = []
        var lastIndex: Int?
        for point in points {
            let index = days.firstIndex(of: point.day)
            if let index, let lastIndex, index == lastIndex + 1 {
                current.append(point)
            } else {
                if !current.isEmpty { runs.append(current) }
                current = [point]
            }
            lastIndex = index
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    static func monthPoints(scans: [CompositionScan], from start: Date, to end: Date) -> [CompositionPoint] {
        let span = max(0.001, end.timeIntervalSince(start))
        return scans.compactMap { scan in
            guard let value = scan.bodyFatPercent else { return nil }
            return CompositionPoint(
                at: scan.at,
                day: UserDay.containing(scan.at),
                value: value,
                x: scan.at.timeIntervalSince(start) / span
            )
        }
    }

    static func plot(
        scans: [CompositionScan],
        range: RollingPills,
        endingOn day: UserDay,
        now: Date
    ) -> CompositionPlot {
        let window = bounds(range: range, endingOn: day, now: now)
        let inside = inWindow(scans, from: window.start, to: window.end)
        let days = day.rollingBack(DetailWindow(.composition, range).days)
        let points: [CompositionPoint]
        let runs: [[CompositionPoint]]
        switch range {
        case .day:
            points = []
            runs = []
        case .week:
            points = weekPoints(scans: inside, days: days)
            runs = self.runs(from: points, days: days)
        case .month:
            points = monthPoints(scans: inside, from: window.start, to: window.end)
            runs = points.isEmpty ? [] : [points]
        }
        let values = points.map(\.value)
        let scale = Self.scale(values)
        let low = values.min()
        let high = values.max()
        return CompositionPlot(
            runs: runs,
            bandLow: low,
            bandHigh: high,
            median: median(values),
            yMin: scale.min,
            yMax: scale.max,
            start: window.start,
            end: window.end,
            now: values.last,
            windowLow: low,
            windowHigh: high,
            scanCount: inside.count
        )
    }

    static func weekBuckets(
        scans: [CompositionScan],
        endingOn day: UserDay,
        count: Int = 4
    ) -> [CompositionWeekBucket] {
        guard count > 0 else { return [] }
        let buckets: [CompositionWeekBucket] = (0..<count).map { offset in
            let end = day.adding(days: -offset * 7)
            let start = end.adding(days: -6)
            let inside = inWindow(scans, from: start.start, to: end.end)
            let fats = inside.compactMap(\.bodyFatPercent)
            let average = fats.isEmpty ? nil : fats.reduce(0, +) / Double(fats.count)
            return CompositionWeekBucket(
                offset: offset,
                start: start,
                end: end,
                averageFat: average,
                scanCount: inside.count,
                delta: nil
            )
        }
        return buckets.enumerated().map { index, bucket in
            var next = bucket
            if index + 1 < buckets.count {
                if let now = bucket.averageFat, let then = buckets[index + 1].averageFat {
                    next.delta = now - then
                }
            }
            return next
        }
    }

    static func span(_ pick: (CompositionScan) -> Double?, in scans: [CompositionScan]) -> CompositionSpan {
        let ordered = scans.sorted { $0.at < $1.at }
        let values = ordered.compactMap(pick)
        return CompositionSpan(first: values.first, last: values.last)
    }

    /// Room around the line so a quiet week is not a flat ruler.
    static func scale(_ values: [Double]) -> (min: Double, max: Double) {
        guard let low = values.min(), let high = values.max() else { return (0, 1) }
        let spread = high - low
        if spread < 0.2 {
            return (low - 0.4, high + 0.4)
        }
        let pad = max(0.3, spread * 0.25)
        return (low - pad, high + pad)
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
