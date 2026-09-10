import Foundation

/// #28 · one owner for "the user says this night ran from here to here".
///
/// Two entries reach the same server call: the sleep page's own save, and a confirmed voice
/// or text request through `write{entity:"sleep_night"}`. `correct_sleep_window` decides
/// what a legal night is — it must already exist, its end still has to date it, and its new
/// window has to hold sleep the band actually recorded — so neither entry re-implements
/// that rule. What lives here is the trip afterwards: settle the day again, then read the
/// night, the score and the charge back so the card, the detail page and the AI are looking
/// at the same night before the person's thumb has left the screen.
enum SleepCorrection {
    /// How far back a night may be corrected. The server holds the same bound; replay is
    /// chronological, so an older correction would recompute every day after it.
    static let horizonDays = 30

    static func canCorrect(day: UserDay, today: UserDay = UserDay.containing(Date())) -> Bool {
        day <= today && day.date >= today.adding(days: -horizonDays).date
    }

    @MainActor
    static func save(day: UserDay, start: String, end: String, into store: DataStore) async throws {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { throw CancellationError() }
        _ = try await SupabaseClient.shared.rpc(
            "correct_sleep_window",
            args: ["p_user_day": day.key, "p_start": start, "p_end": end], expectedOwner: owner)
        await republish(day: day.key, into: store)
    }

    @MainActor
    static func clear(day: UserDay, into store: DataStore) async throws {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { throw CancellationError() }
        _ = try await SupabaseClient.shared.rpc(
            "clear_sleep_correction", args: ["p_user_day": day.key], expectedOwner: owner)
        await republish(day: day.key, into: store)
    }

    /// The night moved, so the night's score and the charge it fed moved with it. Settling
    /// covers the corrected day and the one before it, because a night that crosses midnight
    /// is spent on both — the same day-1 the server's own invalidation reaches for.
    @MainActor
    static func republish(day: String, into store: DataStore) async {
        let today = UserDay.containing(Date())
        let corrected = Self.day(fromKey: day) ?? today
        let back = max(1, Calendar.current.dateComponents([.day], from: corrected.start, to: today.start).day ?? 1)
        await Repository.shared.settleNow(days: back + 1)
        await Repository.shared.load(days: back + 1, endingAt: today, into: store)
        await Repository.shared.loadSleepScores(days: back + 1, endingAt: today, into: store)
    }

    static func day(fromKey key: String) -> UserDay? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key).map { UserDay.containing($0) }
    }

    /// The RPC raises its refusals by name. They arrive as an HTTP body, and the name inside
    /// it is the only part worth showing anyone.
    static func code(_ error: Error) -> String {
        guard case SupabaseFailure.http(_, let body)? = error as? SupabaseFailure else {
            return error is CancellationError ? "CANCELLED" : "WRITE_FAILED"
        }
        for name in ["NO_SLEEP_NIGHT", "WINDOW_HAS_NO_SLEEP", "NO_STAGE_LINE", "END_BEFORE_START",
                     "WAKE_LEAVES_THE_DAY", "CORRECTION_TOO_OLD", "NO_CORRECTION", "BAD_TIME",
                     "RATE_LIMITED", "CONSENT_WITHDRAWN", "ACCOUNT_DELETING", "UNAUTHENTICATED"]
        where body.contains(name) {
            return name
        }
        return "WRITE_FAILED"
    }

    static func message(_ code: String) -> String {
        switch code {
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
