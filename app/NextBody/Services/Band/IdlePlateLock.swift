import Foundation

/// 04 · idle 星球的日子。一天一张，开二十次也是这一张。
///
/// Pure: wearer + user-day + stored lock + optional one-shot event.
/// Hour-of-day and LIVE BPM are accepted so callers cannot smuggle them in
/// as a second picker — they do not change the plate.
public enum IdlePlateLock: Sendable {
    /// Playbook day-pool. Forbidden 13/17/18/19/24 never enter. Event plates
    /// 11/20/25 stay out of the daily draw so a normal morning is not an alarm.
    public static let dayPool: [Int] = [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
        12, 14, 15, 16, 21, 22, 23, 26, 27, 28,
    ]
    public static let forbidden: Set<Int> = [13, 17, 18, 19, 24]
    public static let lowReservePlate = 25
    public static let lowBandChargePlate = 11
    public static let bandAwayPlate = 20
    public static let bandAwaySeconds: TimeInterval = 4 * 3600

    public enum LockedBy: String, Equatable, Sendable, Codable {
        case daily, event, visit
    }

    /// Every painted look, including event and forbidden plates. Product idle
    /// never draws from this list — `appear` still uses `dayPool`.
    public static let reviewRoster: [Int] = Array(1...28)

    public enum Event: Equatable, Sendable {
        case lowReserve
        case lowBandCharge
        case bandAway
    }

    public struct Snapshot: Equatable, Sendable, Codable {
        public var day: String
        public var plate: Int
        public var lockedBy: LockedBy

        public init(day: String, plate: Int, lockedBy: LockedBy) {
            self.day = day
            self.plate = plate
            self.lockedBy = lockedBy
        }
    }

    /// Deterministic daily draw. Adjacent days skip yesterday when the pool allows.
    /// 02 and 23 are both moons: if yesterday was one, today will not be the other.
    public static func dailyPlate(wearer: String, day: String, yesterday: Int?) -> Int {
        let pool = dayPool
        guard !pool.isEmpty else { return 1 }
        var idx = Int(fnv(wearer + "\u{1}" + day) % UInt64(pool.count))
        var plate = pool[idx]
        if let y = yesterday, plate == y, pool.count > 1 {
            idx = (idx + 1) % pool.count
            plate = pool[idx]
        }
        if let y = yesterday, isMoon(plate), isMoon(y), plate != y, pool.count > 2 {
            idx = (idx + 1) % pool.count
            plate = pool[idx]
            if plate == y {
                idx = (idx + 1) % pool.count
                plate = pool[idx]
            }
        }
        return plate
    }

    /// Next look on the review roster. Unknown / missing previous starts at 01.
    /// Product idle does not call this — a DEBUG visit walk does.
    public static func advanceVisit(previous: Int?) -> Int {
        let roster = reviewRoster
        guard !roster.isEmpty else { return 1 }
        guard let previous, let i = roster.firstIndex(of: previous) else {
            return roster[0]
        }
        return roster[(i + 1) % roster.count]
    }

    /// First idle appear of a user-day writes the lock. Same day keeps it.
    /// A new user-day only takes if idle is not already on screen (`idleVisible`).
    /// `hour` and `bpm` are ignored on purpose.
    public static func appear(
        wearer: String,
        day: String,
        stored: Snapshot?,
        idleVisible: Bool,
        hour: Int = 12,
        bpm: Int? = nil
    ) -> Snapshot {
        _ = hour
        _ = bpm
        if let stored {
            if stored.day == day { return stored }
            if idleVisible { return stored }
        }
        let plate = dailyPlate(wearer: wearer, day: day, yesterday: stored?.plate)
        return Snapshot(day: day, plate: plate, lockedBy: .daily)
    }

    /// One-shot override for the stored day. A second edge the same day is ignored.
    /// Clearing the edge is not this function — the snapshot stays.
    public static func applyEvent(_ event: Event, stored: Snapshot, day: String) -> Snapshot {
        guard stored.day == day else { return stored }
        if stored.lockedBy != .daily { return stored }
        return Snapshot(day: stored.day, plate: plate(for: event), lockedBy: .event)
    }

    public static func plate(for event: Event) -> Int {
        switch event {
        case .lowReserve: return lowReservePlate
        case .lowBandCharge: return lowBandChargePlate
        case .bandAway: return bandAwayPlate
        }
    }

    /// Seconds since the BLE-down stamp. Unbound, still connected, or a missing
    /// stamp is 0 — `lastSync` / `.distantPast` is not a disconnect clock.
    public static func disconnectedFor(
        bound: Bool,
        connected: Bool,
        disconnectStamp: Date?,
        now: Date
    ) -> TimeInterval {
        guard bound, !connected, let stamp = disconnectStamp else { return 0 }
        return max(0, now.timeIntervalSince(stamp))
    }

    /// Named edges only. REACHING, brief NO CONTACT, recovered reserve, and BPM
    /// are accepted so a caller cannot invent a fourth picker.
    public static func edge(
        reserve: Int?,
        wakeReserve: Int?,
        bandPercent: Int?,
        charging: Bool,
        disconnectedFor: TimeInterval,
        reaching: Bool = false,
        noContact: Bool = false,
        bpm: Int? = nil
    ) -> Event? {
        _ = reaching
        _ = noContact
        _ = bpm
        if let r = reserve, r <= 25, let wake = wakeReserve, r < wake {
            return .lowReserve
        }
        if let p = bandPercent, p <= 15, !charging {
            return .lowBandCharge
        }
        if disconnectedFor >= bandAwaySeconds {
            return .bandAway
        }
        return nil
    }

    private static func isMoon(_ plate: Int) -> Bool { plate == 2 || plate == 23 }

    private static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in s.utf8 {
            h ^= UInt64(b)
            h &*= 1_099_511_628_211
        }
        return h
    }
}
