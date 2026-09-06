import Foundation

/// ADR 0010 · consecutive worn days as a silent header fact.
///
/// A worn day is wrist evidence in at least half of the user-day's elapsed five-minute
/// slots. Bluetooth, an empty raw row, and a valid night are all different things.
enum WearRun: Sendable {
    enum Flame: Equatable, Sendable {
        case live(Int)
        case amber
        case gray
    }

    struct Yesterday: Equatable, Sendable {
        var worn: Bool
        var run: Int
        var miss: Int
    }

    static let slotsPerDay = 288
    static let slotSeconds: TimeInterval = 300

    /// Heart, stress, HRV, or a positive step count. Skin temperature and vendor calories
    /// alone do not count — a band on the nightstand can still report those.
    static func hasWristEvidence(_ sample: VitalSample) -> Bool {
        sample.hr != nil
            || sample.stress != nil
            || sample.hrv != nil
            || (sample.steps ?? 0) > 0
    }

    static func elapsedSlots(day: UserDay, now: Date) -> Int {
        let hi = min(now, day.end)
        guard hi > day.start else { return 0 }
        return min(slotsPerDay, Int(hi.timeIntervalSince(day.start) / slotSeconds))
    }

    static func isWornDay(samples: [VitalSample], day: UserDay, now: Date) -> Bool {
        let elapsed = elapsedSlots(day: day, now: now)
        guard elapsed > 0 else { return false }
        var bins = Set<Int>()
        for sample in samples {
            guard sample.ts >= day.start, sample.ts < min(now, day.end) else { continue }
            guard hasWristEvidence(sample) else { continue }
            let slot = Int(sample.ts.timeIntervalSince(day.start) / slotSeconds)
            guard slot >= 0, slot < elapsed else { continue }
            bins.insert(slot)
        }
        return bins.count * 2 >= elapsed
    }

    /// Today never cools the flame: an open user-day that is not yet a worn day still
    /// shows yesterday's live run. A closed miss is already sitting on yesterday.
    static func display(todayWorn: Bool, yesterday: Yesterday?) -> Flame {
        if todayWorn {
            let prior = yesterday?.worn == true ? max(0, yesterday!.run) : 0
            return .live(prior + 1)
        }
        guard let yesterday else { return .gray }
        if yesterday.worn { return .live(max(1, yesterday.run)) }
        if yesterday.miss == 1 { return .amber }
        return .gray
    }
}
