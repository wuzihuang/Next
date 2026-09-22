import Foundation

/// Shared mutation and refresh path for a reported night or an edited device window.
/// Both the button and a confirmed AI request publish the same server-side evidence.
enum SleepCorrection {
    /// How far back a night may be corrected. The server holds the same bound; replay is
    /// chronological, so an older correction would recompute every day after it.
    static let horizonDays = 30

    static func canCorrect(day: UserDay, today: UserDay = UserDay.containing(Date())) -> Bool {
        day <= today && day.date >= today.adding(days: -horizonDays).date
    }

    @MainActor
    @discardableResult
    static func save(day: UserDay, start: String, end: String, into store: DataStore) async throws -> Bool {
        let session = SupabaseClient.currentRequestSessionSnapshot()
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { throw CancellationError() }
        await Repository.shared.flushPendingEvidence(afterCurrent: true)
        guard session == SupabaseClient.currentRequestSessionSnapshot(), !Task.isCancelled else {
            throw CancellationError()
        }
        _ = try await SupabaseClient.shared.rpc(
            "correct_sleep_window",
            args: ["p_user_day": day.key, "p_start": start, "p_end": end], expectedOwner: owner)
        guard session == SupabaseClient.currentRequestSessionSnapshot() else { throw CancellationError() }
        return await republish(day: day.key, into: store, expectedOwner: owner)
    }

    @MainActor
    @discardableResult
    static func create(day: UserDay, start: String, end: String, into store: DataStore) async throws -> Bool {
        let session = SupabaseClient.currentRequestSessionSnapshot()
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { throw CancellationError() }
        await Repository.shared.flushPendingEvidence(afterCurrent: true)
        guard session == SupabaseClient.currentRequestSessionSnapshot(), !Task.isCancelled else {
            throw CancellationError()
        }
        _ = try await SupabaseClient.shared.rpc(
            "create_sleep_window",
            args: ["p_user_day": day.key, "p_start": start, "p_end": end], expectedOwner: owner)
        guard session == SupabaseClient.currentRequestSessionSnapshot() else { throw CancellationError() }
        return await republish(day: day.key, into: store, expectedOwner: owner)
    }

    @MainActor
    @discardableResult
    static func clear(day: UserDay, into store: DataStore) async throws -> Bool {
        let session = SupabaseClient.currentRequestSessionSnapshot()
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { throw CancellationError() }
        await Repository.shared.flushPendingEvidence(afterCurrent: true)
        guard session == SupabaseClient.currentRequestSessionSnapshot(), !Task.isCancelled else {
            throw CancellationError()
        }
        _ = try await SupabaseClient.shared.rpc(
            "clear_sleep_correction", args: ["p_user_day": day.key], expectedOwner: owner)
        guard session == SupabaseClient.currentRequestSessionSnapshot() else { throw CancellationError() }
        return await republish(day: day.key, into: store, expectedOwner: owner)
    }

    /// The night moved, so the night's score and the charge it fed moved with it. Settling
    /// covers the corrected day and the one before it, because a night that crosses midnight
    /// is spent on both — the same day-1 the server's own invalidation reaches for.
    @MainActor
    @discardableResult
    static func republish(day: String, into store: DataStore, expectedOwner: String? = nil) async -> Bool {
        let session = SupabaseClient.currentRequestSessionSnapshot()
        guard let owner = expectedOwner ?? SupabaseClient.currentUserIdSnapshot(),
              owner == SupabaseClient.currentUserIdSnapshot() else { return false }
        func current() -> Bool { session == SupabaseClient.currentRequestSessionSnapshot() && !Task.isCancelled }
        let today = UserDay.containing(Date())
        let corrected = Self.day(fromKey: day) ?? today
        let back = max(0, Calendar.current.dateComponents([.day], from: corrected.start, to: today.start).day ?? 0)
        let windowDays = back + 2
        var settled = true
        do {
            _ = try await SupabaseClient.shared.rpc("settle_now", args: ["p_days": windowDays - 1], expectedOwner: owner)
        } catch { settled = false }
        guard current() else { return false }
        await Repository.shared.load(days: windowDays - 1, endingAt: today, into: store)
        guard current() else { return false }
        await Repository.shared.loadSleepScores(days: windowDays, endingAt: today, into: store)
        guard current(), !store.isOffline else { return false }
        if case .failed = store.sleepScoreLoadState { return false }
        do {
            guard let rows = try await SupabaseClient.shared.rpc("calculation_status",
                args: ["p_from": corrected.adding(days: -1).key, "p_to": today.key],
                expectedOwner: owner) as? [[String: Any]], !rows.isEmpty else { return false }
            return current() && settled && rows.allSatisfy { $0["pending"] as? Bool == false }
        } catch { return false }
    }

    static func day(fromKey key: String) -> UserDay? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        guard let date = f.date(from: key), f.string(from: date) == key,
              let start = Calendar.current.date(bySettingHour: UserDay.boundaryHour,
                                                minute: 0, second: 0, of: date) else { return nil }
        return UserDay(date: start)
    }

    /// The RPC raises its refusals by name. They arrive as an HTTP body, and the name inside
    /// it is the only part worth showing anyone.
    static func code(_ error: Error) -> String {
        guard case SupabaseFailure.http(_, let body)? = error as? SupabaseFailure else {
            return error is CancellationError ? "CANCELLED" : "WRITE_FAILED"
        }
        for name in ["SLEEP_NIGHT_EXISTS", "FUTURE_SLEEP_WINDOW", "NO_RECORDED_SLEEP", "NO_SLEEP_NIGHT", "WINDOW_HAS_NO_SLEEP", "NO_STAGE_LINE", "END_BEFORE_START",
                     "WAKE_LEAVES_THE_DAY", "CORRECTION_TOO_OLD", "NO_CORRECTION", "BAD_TIME",
                     "RATE_LIMITED", "CONSENT_WITHDRAWN", "ACCOUNT_DELETING", "UNAUTHENTICATED"]
        where body.contains(name) {
            return name
        }
        return "WRITE_FAILED"
    }

    static func message(_ code: String) -> String {
        switch code {
        case "SLEEP_NIGHT_EXISTS":   L("A night already exists on this day. Change its times instead.")
        case "FUTURE_SLEEP_WINDOW":  L("Sleep can only be recorded after you wake up.")
        case "NO_RECORDED_SLEEP":    L("This night was added by you and has no band times to restore.")
        case "NO_SLEEP_NIGHT":      L("There is no recorded night on that day to correct.")
        case "WINDOW_HAS_NO_SLEEP": L("The band recorded no sleep inside those times.")
        case "NO_STAGE_LINE":       L("This night has totals only, so its times cannot be re-counted.")
        case "END_BEFORE_START":    L("The end has to be a different time from the start.")
        case "WAKE_LEAVES_THE_DAY": L("A night is filed under the day you woke on; that end leaves it.")
        case "CORRECTION_TOO_OLD":  L("Nights older than %d days can no longer be corrected.", horizonDays)
        case "NO_CORRECTION":       L("This night is already the band's own.")
        case "BAD_TIME":            L("Use a clock time like 23:30.")
        case "RATE_LIMITED":        L("Too many changes at once. Try again in a minute.")
        case "CONSENT_WITHDRAWN":   L("Health storage is off, so nothing can be changed.")
        case "CANCELLED":           L("Not saved.")
        default:                    L("Couldn't save that. Check your connection and try again.")
        }
    }
}
