import Foundation

/// Cold-start rules for Home numbers. The screen must paint last-known same-day values
/// immediately, then replace them with the server's current row — not wait for 182 days
/// of history or a BLE pull before anything is visible.
public enum HomeLaunchPolicy: Sendable {
    /// Access tokens this close to expiry are treated as gone; refresh instead of racing
    /// a 401 on the first Home read.
    public static let accessTokenLeeway: TimeInterval = 15

    /// Home's first paint only needs today plus the previous user day (rolling 24 h vitals).
    public static let fastLoadLookbackDays = 1

    /// A snapshot taken on a different user day is yesterday's score, not today's.
    public static func shouldPaintToday(snapshotDayKey: String, currentDayKey: String) -> Bool {
        snapshotDayKey == currentDayKey
    }

    public static func isAccessTokenUsable(_ token: String, now: Date = Date()) -> Bool {
        guard let expiry = jwtExpiry(token) else { return false }
        return expiry.timeIntervalSince(now) > accessTokenLeeway
    }

    public static func jwtExpiry(_ token: String) -> Date? {
        guard let seconds = jwtNumber(token, key: "exp") else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public static func jwtSubject(_ token: String) -> String? {
        jwtPayload(token)?["sub"] as? String
    }

    public static func jwtEmail(_ token: String) -> String? {
        jwtPayload(token)?["email"] as? String
    }

    public static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded.append("=") }
        guard let data = Data(base64Encoded: encoded),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    /// PostgREST `in.(id,id)` — nil when there is nothing to ask, so a miss does not
    /// become an unfiltered table dump.
    public static func postgrestIn(_ ids: [String]) -> String? {
        let clean = ids.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return nil }
        return "in.(\(clean.joined(separator: ",")))"
    }

    private static func jwtNumber(_ token: String, key: String) -> Double? {
        guard let value = jwtPayload(token)?[key] else { return nil }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}


extension HomeLaunchPolicy {
    static func acceptsRead(account: String?, currentAccount: String?, generation: UInt,
                            currentGeneration: UInt) -> Bool {
        account != nil && account == currentAccount && generation == currentGeneration
    }
}


extension HomeLaunchPolicy {
    /// Legacy rows lack a revision until first settlement after upgrade. A missing
    /// revision is unknown freshness, never proof that a cached row is current.
    static func shouldRefreshSummary(revision: String?, cachedRevision: String?,
                                     hasCachedRow: Bool) -> Bool {
        guard let revision else { return true }
        return !hasCachedRow || revision != cachedRevision
    }
}

/// Shared connection/history and display decisions for automatic and explicit pulls.
enum BandSyncPolicy {
    static let connectionAttempts = 3

    static func matchesBoundDevice(discovered: String, sdkAddress: String? = nil,
                                   bound: String?, boundPeripheral: String? = nil) -> Bool {
        guard let bound, !bound.isEmpty else { return false }
        let matchesBinding = [discovered, sdkAddress].compactMap { $0 }.contains {
            !$0.isEmpty && $0.caseInsensitiveCompare(bound) == .orderedSame
        }
        guard !matchesBinding, let boundPeripheral, !boundPeripheral.isEmpty else {
            return matchesBinding
        }
        return !discovered.isEmpty && discovered.caseInsensitiveCompare(boundPeripheral) == .orderedSame
    }

    /// An SDK address may become a MAC after verification. Recover its local peripheral
    /// only when the SDK's remembered address proves it belongs to the existing binding.
    static func legacyPeripheralIdentifier(bound: String?, rememberedAddress: String?,
                                          rememberedPeripheral: String?) -> String? {
        guard let bound, !bound.isEmpty, let rememberedAddress, !rememberedAddress.isEmpty,
              rememberedAddress.caseInsensitiveCompare(bound) == .orderedSame,
              let rememberedPeripheral, let uuid = UUID(uuidString: rememberedPeripheral) else { return nil }
        return uuid.uuidString
    }

    static func historyDays(retained: Int?) -> Int {
        let held = retained.flatMap { $0 > 0 ? $0 : nil } ?? 7
        return max(0, min(held, 366) - 1)
    }

    static func historyDayOffsets(retained: Int?, cachedOffsets: [Int]) -> [Int] {
        let days = historyDays(retained: retained)
        let retainedOffsets = days > 0 ? Array(1...days) : []
        return Array(Set(retainedOffsets + cachedOffsets.filter { (1...6).contains($0) })).sorted()
    }

    /// SDK offsets follow the current calendar day; refresh offsets follow its captured
    /// day. Recent failures override older receipts, while recent successes are reused.
    static func historyOffsetsToSync(available: [Int], elapsedDays: Int = 0,
                                      recentDays: [Int: BandRefreshResult.Status],
                                      needsSync: (Int) -> Bool) -> [Int] {
        available.map { $0 - elapsedDays }.filter { offset in
            guard offset > 0 else { return false }
            if let status = recentDays[offset] { return status != .success }
            return needsSync(offset)
        }
    }

    /// Daily historical verification is per account/device/day through its persisted
    /// domain receipts. Missing domains and failed uploads remain repair work even after
    /// other dates passed their daily audit. Oxygen owns its recorded overnight window.
    static func needsHistorySync(states: [BandDomainSyncState], outcome: BandRefreshResult.Status?,
                                 start: Date, end: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard outcome == .success, start < end, end <= now else { return true }
        let expected = ["origin", "hrv", "temperature", "rr", "sleep", "oxygen", "response"]
        return expected.contains { domain in
            guard let state = states.first(where: { $0.domain == domain }),
                  state.status == .complete || state.status == .notCollected || state.status == .unsupported,
                  state.repairStart == nil, state.repairEnd == nil,
                  state.attemptedAt <= now, calendar.isDate(state.attemptedAt, inSameDayAs: now),
                  let acknowledgedStart = state.acknowledgedStart,
                  let acknowledgedEnd = state.acknowledgedEnd,
                  acknowledgedStart < acknowledgedEnd else { return true }
            return domain != "oxygen" && (acknowledgedStart > start || acknowledgedEnd < end)
        }
    }

    static func header(activity: String, connected: Bool, live: String) -> String {
        if activity == "connecting" { return "CONNECTING" }
        if activity == "syncing" { return "SYNCING…" }
        guard connected else { return "OFFLINE" }
        switch live {
        case "live", "stress": return "LIVE"
        case "reaching": return "REACHING"
        case "noContact": return "NO CONTACT"
        default: return "STANDBY"
        }
    }
}

extension HomeLaunchPolicy {
    /// Upload receipts confirm facts, not publication. Old dirty or unversioned results
    /// still require settlement even after the local outbox has become empty.
    static func needsEvidenceSettlement(pending: [Bool?]?) -> Bool {
        guard let pending, !pending.isEmpty else { return true }
        return pending.contains { $0 != false }
    }

    /// Issue #21 · Body Battery and the sleep score keep moving while the phone is in a
    /// pocket: the reserve drains against the clock, so today's row goes stale without a
    /// single new fact arriving and `pending` stays false. The hourly cron was the only
    /// thing that moved it, which is why opening the app could show an hour-old number.
    /// Coming forward now always asks for today, whether or not new evidence exists.
    ///
    /// The floor is the server's own calculation tick: nb.recompute_range bins `now` into
    /// five minutes and skips a day already settled at that tick, so asking more often
    /// than this cannot produce a different number — it can only cost a round trip.
    static let foregroundSettleInterval: TimeInterval = 300

    static func shouldSettleOnForeground(pending: [Bool?]?, lastSettledAt: Date?,
                                         now: Date = Date()) -> Bool {
        if needsEvidenceSettlement(pending: pending) { return true }
        guard let lastSettledAt else { return true }
        return now.timeIntervalSince(lastSettledAt) >= foregroundSettleInterval
    }
}
