import Foundation

/// F2 §01 · work out the window first, then decide how many pages to pull.
///
/// W = [local 04:00, min(now, next 04:00))
///   · now ≥ 04:00 and the whole window is inside today  → page 0 only
///   · now < 04:00 (the day still running is yesterday's) → pages 0 and 1
///   · closing a day → always straddles two: page 1 for after 04:00, page 0 for before it
///
/// ⚠️ Pulling one page too few does not error. It just makes the number smaller, silently.
/// Opening the app in the small hours and the first close of each morning are the only two
/// moments this bites, which is exactly why it is easy to ship broken.
@MainActor
final class OriginDataSync {
    private let band: BandService
    private let db = SupabaseClient.shared

    init(band: BandService = Band.live) { self.band = band }

    /// Which SDK pages a given user day needs. The only place dayOffset is ever decided.
    static func pages(for day: UserDay, now: Date = Date(), calendar: Calendar = .current) -> [Int] {
        let today = UserDay.containing(now, calendar: calendar)
        // How many device days back the window starts. A device day is midnight-to-midnight,
        // so a user day beginning at 04:00 always sits inside one or two of them.
        let daysBack = calendar.dateComponents([.day], from: day.start, to: today.start).day ?? 0

        // Closing yesterday, or reading it while today is still young: two pages.
        let hour = calendar.component(.hour, from: now)
        let straddles = (day != today) || hour < UserDay.boundaryHour
        return straddles ? [daysBack, daysBack + 1] : [daysBack]
    }

    /// Pull a user day and store it. Returns how many points were written.
    @discardableResult
    func sync(day: UserDay, into store: DataStore) async -> Int {
        let run = SyncRun(startedAt: Date())
        var points: [OriginPoint] = []
        var pagesReturned = 0
        let wanted = Self.pages(for: day)

        for offset in wanted {
            do {
                let page = try await band.readOriginData(dayOffset: offset)
                points.append(contentsOf: page)
                pagesReturned += 1
            } catch {
                BandLog.shared.record("readOriginData(\(offset))", error: error)
            }
        }

        // A batch is stamped with the phone's timezone at the moment it syncs. One batch never
        // mixes two zones, and a row already stored is never re-stamped.
        let tz = TimeZone.current.identifier
        let rows = points.compactMap { point -> [String: Any]? in
            guard let ts = Self.instant(of: point, in: day) else { return nil }
            var row: [String: Any] = [
                "ts": ISO8601DateFormatter().string(from: ts),
                "sampled_tz": tz,
                // The calendar day derived from the offset travels with the batch: without it
                // two pages cannot be put back in order.
                // ⚠️ F7 rule 09 / F2 · both of these are on their way out. They are written only
                // because the live table still has them NOT NULL; migration 20260902010000
                // relaxes that, and 20260902020000 drops them. Delete these two lines when B ships.
                "calendar_day": Self.dayString(ts),
                "day_offset": wanted.first ?? 0,
                "src": "band",
            ]
            if let v = point.heart { row["heart"] = v }
            if let v = point.step { row["step"] = v }
            if let v = point.cal { row["cal"] = v }
            if let v = point.distance { row["dis"] = v }
            if let v = point.met { row["met"] = v }
            if let v = point.temperature { row["temp"] = v }
            if let v = point.stress { row["stress"] = v }
            if let v = point.sleepState { row["sleep_states"] = v }
            return row
        }

        guard !rows.isEmpty else {
            await record(run, outcome: "failed", requested: wanted.count, returned: pagesReturned)
            return 0
        }

        // Collected data is insert-only and never updated: what the band measured is not ours
        // to change. Re-syncing the same day is a no-op, not a duplicate.
        for chunk in stride(from: 0, to: rows.count, by: 400).map({
            Array(rows[$0..<min($0 + 400, rows.count)])
        }) {
            do { _ = try await db.insert("raw_samples", rows: chunk) }
            catch { BandLog.shared.record("insert raw_samples", error: error) }
        }

        if let night = (try? await band.readSleep(dayOffset: wanted.first ?? 0)) ?? nil {
            // D01 · sleep is an input. It is stored so Body Battery can use it, and it never
            // reaches a screen, a widget, or a sentence.
            _ = try? await db.insert("sleep_nights", rows: [[
                "user_day": Self.dayString(day.start),
                "total_minutes": night.totalMinutes,
                "deep_minutes": night.deepMinutes,
                "light_minutes": night.lightMinutes,
                "wake_count": night.wakeCount,
            ]])
        }

        // outcome = 'partial' does not move last_origin_sync_at, but the row is still written:
        // that row is the whole basis for the word SYNCED.
        let outcome = pagesReturned == wanted.count ? "success" : "partial"
        await record(run, outcome: outcome, requested: wanted.count, returned: pagesReturned)

        if outcome == "success" { store.lastSync = Date() }
        await Repository.shared.load(days: 1, endingAt: day, into: store)
        return rows.count
    }

    /// OriginData gives a clock string and nothing else — no date, no zone, no offset — so the
    /// instant can only be rebuilt from the window we asked for.
    private static func instant(of point: OriginPoint, in day: UserDay) -> Date? {
        let parts = point.time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let (hour, minute) = (parts[0], parts[1])
        var cal = Calendar.current
        cal.timeZone = .current
        // Before 04:00 belongs to the second half of this user day, i.e. the next calendar day.
        let base = hour < UserDay.boundaryHour
            ? cal.date(byAdding: .day, value: 1, to: day.start)!
            : day.start
        let comps = cal.dateComponents([.year, .month, .day], from: base)
        return cal.date(from: DateComponents(year: comps.year, month: comps.month,
                                             day: comps.day, hour: hour, minute: minute))
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    private struct SyncRun { let startedAt: Date }

    /// ⚠️ user_id is NOT NULL on this table and the insert never sent one, so every write
    /// was rejected and swallowed by the `try?` — the table that exists to explain a bad
    /// sync was empty for exactly as long as syncs had been running.
    ///
    /// outcome = 'partial' does not advance last_origin_sync_at, but the row is still
    /// written: four days out of seven and nothing at all are different events, and that
    /// difference is the whole reason for the table.
    private func record(_ run: SyncRun, outcome: String, requested: Int, returned: Int) async {
        guard let userId = await db.currentUserId else { return }
        var row: [String: Any] = [
            "user_id": userId,
            "started_at": ISO8601DateFormatter().string(from: run.startedAt),
            "finished_at": ISO8601DateFormatter().string(from: Date()),
            "outcome": outcome,
            "days_requested": requested,
            "days_returned": returned,
        ]
        if let deviceId = await Repository.shared.deviceId { row["device_id"] = deviceId }
        _ = try? await db.insert("sync_runs", rows: [row])
    }
}
