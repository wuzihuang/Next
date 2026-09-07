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
    /// Issue #19 · every card's day. Local midnight on `now`'s user day to `now`.
    /// The only window a card labelled TODAY may draw.
    static func today(endingAt now: Date, calendar: Calendar = .current) -> VitalsTimelineRange {
        let day = UserDay.containing(now, calendar: calendar)
        return userDay(start: day.start, end: day.end, now: now)
    }

    /// A tick's own freshness, not a card window: how far back a NOW reading may be
    /// joined from when the newest row carries no value of its own.
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

    /// Stress is often missing on the newest worn tick — sleep PPG still has heart.
    /// Join the last positive reading if it still sits inside the rolling 24h window.
    static func currentStress(latest: Int?, previous: (value: Int, at: Date)?, at tickAt: Date) -> Int? {
        currentJoinedReading(latest: latest, previous: previous, at: tickAt)
    }

    /// The newest row is often a step / MET / calorie tick with no PPG. Heart stays
    /// that tick's own reading when it has one; otherwise the last positive reading
    /// inside the same 24h window the instrument already uses.
    static func currentHeart(latest: Int?, previous: (value: Int, at: Date)?, at tickAt: Date) -> Int? {
        currentJoinedReading(latest: latest, previous: previous, at: tickAt)
    }

    private static func currentJoinedReading(
        latest: Int?,
        previous: (value: Int, at: Date)?,
        at tickAt: Date
    ) -> Int? {
        if let latest { return latest }
        guard let previous else { return nil }
        return rolling24Hours(endingAt: tickAt).contains(previous.at) ? previous.value : nil
    }
}
