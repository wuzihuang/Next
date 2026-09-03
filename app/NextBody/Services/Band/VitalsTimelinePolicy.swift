import Foundation

/// A closed display range. `end` is the last instant the chart may claim to contain.
struct VitalsTimelineRange: Equatable {
    let start: Date
    let end: Date

    var span: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    func contains(_ timestamp: Date) -> Bool {
        timestamp >= start && timestamp <= end
    }
}

/// Product time semantics shared by the sync tests and the eight Vitals detail pages.
enum VitalsTimelinePolicy {
    static func rolling24Hours(endingAt now: Date) -> VitalsTimelineRange {
        VitalsTimelineRange(
            start: now.addingTimeInterval(-24 * 60 * 60),
            end: now
        )
    }

    static func userDay(start: Date, end: Date, now: Date) -> VitalsTimelineRange {
        let visibleEnd = min(end, max(start, now))
        return VitalsTimelineRange(start: start, end: visibleEnd)
    }
}
