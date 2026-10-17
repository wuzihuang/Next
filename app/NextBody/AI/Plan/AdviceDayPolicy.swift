import CryptoKit
import Foundation

/// ADR 0022 · one run that produces (or fails to produce) a day's set, as this device knows
/// it. The server keeps the truth: replaying the run's turn id returns its result, or says
/// the run is still in progress. A run whose outcome is unknown is one this device has
/// not yet heard the end of.
struct AdviceDayRun: Codable, Equatable {
    enum Kind: String, Codable { case automatic, refresh }
    enum Outcome: String, Codable { case delivered, failed }

    let ownerUserId: String
    let dayKey: String
    let kind: Kind
    /// 1-based for automatic runs; a refresh is always 1.
    let attempt: Int
    let turnID: UUID
    let startedAt: Date
    var outcome: Outcome?
}

/// ADR 0022 · the day's set is generated once, in the background, by whichever phone opens
/// the day first. Every decision about whether to start, attach to, or give up on that
/// generation is here, so it can be read and tested without a network.
enum AdviceDayPolicy {
    /// Automatic attempts per user day; after that only REFRESH remains.
    static let automaticAttempts = 3
    /// The first attempt of a day waits this long for the band before generating from
    /// what the server already has.
    static let bandWait: TimeInterval = 20
    /// A run this device never heard the end of is trusted for this long. The server's
    /// budget is 110 s plus prefetch; past this, the lease has expired and the run is dead.
    static let unknownRunLifetime: TimeInterval = 5 * 60
    /// The server names how long its lease has left; the probe waits inside these bounds.
    static let probeFloor: TimeInterval = 3
    static let probeCeiling: TimeInterval = 10

    enum Step: Equatable {
        /// The stored set is today's: nothing to generate.
        case showToday
        /// A run is in flight somewhere: replay its turn until it answers.
        case attach(AdviceDayRun)
        /// Start this automatic attempt now.
        case start(attempt: Int)
        /// First attempt of the day, band not synced yet: give it a moment.
        case waitForBand
        /// Every automatic attempt failed; REFRESH is the only way left.
        case exhausted
    }

    struct Situation: Equatable {
        var dayKey: String
        /// Day of the set currently held, if any.
        var storedDayKey: String?
        var runs: [AdviceDayRun]
        /// The band delivered today's data during this user day.
        var bandSynced: Bool
        /// Seconds since the app came to the foreground for this user day.
        var foregroundElapsed: TimeInterval
        var now: Date
    }

    static func next(_ s: Situation) -> Step {
        if s.storedDayKey == s.dayKey { return .showToday }
        let today = s.runs.filter { $0.dayKey == s.dayKey }
        if let open = today.first(where: { $0.outcome == nil && s.now.timeIntervalSince($0.startedAt) < unknownRunLifetime }) {
            return .attach(open)
        }
        // The set was made but could not be read back (a failed read, or none yet on a fresh
        // launch): replaying the run's key returns its stored frame without a model call.
        if let delivered = today.last(where: { $0.outcome == .delivered }) { return .attach(delivered) }
        let automatic = today.filter { $0.kind == .automatic }
        let used = automatic.map(\.attempt).max() ?? 0
        let nextAttempt = used + 1
        if nextAttempt > automaticAttempts { return .exhausted }
        if nextAttempt == 1, !s.bandSynced, s.foregroundElapsed < bandWait { return .waitForBand }
        return .start(attempt: nextAttempt)
    }

    /// Runs older than a couple of days are noise; runs whose end was never heard and whose
    /// lease has long expired count as failed, so the attempt they used is not re-spent.
    static func settled(_ runs: [AdviceDayRun], now: Date, keepDays: Set<String>) -> [AdviceDayRun] {
        runs.filter { keepDays.contains($0.dayKey) }.map { run in
            guard run.outcome == nil, now.timeIntervalSince(run.startedAt) >= unknownRunLifetime else { return run }
            var dead = run
            dead.outcome = .failed
            return dead
        }
    }

    static func probeDelay(retryAfter: Int?) -> TimeInterval {
        min(max(TimeInterval(retryAfter ?? Int(probeFloor)), probeFloor), probeCeiling)
    }

    /// Two phones on one account fire the same key and the server answers the second with
    /// a replay or "in progress": one automatic generation per user day, no table needed.
    static func automaticTurnID(owner: String, dayKey: String, attempt: Int) -> UUID {
        uuidV5(name: "\(owner)/\(dayKey)/advice/\(attempt)")
    }

    /// RFC 4122 name-based UUID under a fixed NextBody namespace.
    private static let namespace: [UInt8] = [
        0x6e, 0x62, 0x61, 0x64, 0x76, 0x69, 0x63, 0x65, 0x2d, 0x64, 0x61, 0x79, 0x2d, 0x73, 0x65, 0x74,
    ]

    static func uuidV5(name: String) -> UUID {
        var digest = Array(Insecure.SHA1.hash(data: Data(namespace + Array(name.utf8))))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }
}
