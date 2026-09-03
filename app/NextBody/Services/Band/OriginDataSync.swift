import Foundation
import os

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
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "sync")
    private struct DatedPoint { let calendarDay: Date; let point: OriginPoint }

    init(band: BandService = Band.live) { self.band = band }

    // MARK: asking again

    private static var inFlight: Task<Void, Never>?
    private static var lastAttempt: Date?
    private static var lastAttemptUserId: String?

    /// The one entry point for "pull today again": the app coming back to the foreground, the
    /// device page opening, the home screen's own five-minute tick. Two of those firing
    /// together used to mean two full pulls of the same day fighting for the same serial
    /// queue; here the second one waits for the first and then finds nothing to do.
    ///
    /// 补屏 rule 01 · pairing is not permission. Without consent the band is never read.
    static func refreshNow(into store: DataStore, minimumInterval: TimeInterval = SyncCadence.throttle) async {
        guard Band.live.state == .connected, ConsentStore.shared.granted,
              let userId = await SupabaseClient.shared.currentUserId else { return }
        if lastAttemptUserId != userId {
            lastAttempt = nil
            lastAttemptUserId = userId
        }
        if let running = inFlight { await running.value; return }
        // A tick is five minutes wide. Asking twice inside one is asking for the same answer.
        if let last = lastAttempt, Date().timeIntervalSince(last) < minimumInterval { return }
        lastAttempt = Date()
        let task = Task { @MainActor in
            _ = await OriginDataSync().sync(day: UserDay.containing(Date()), into: store)
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Whether a full cadence has passed since the band was last asked. The home screen's
    /// loop checks this every half minute instead of sleeping for the whole cadence, so a
    /// cadence shortened on the device page takes effect within thirty seconds, not after
    /// the old hour has run out.
    static var isDue: Bool {
        guard let last = lastAttempt else { return true }
        return Date().timeIntervalSince(last) >= SyncCadence.interval
    }

    /// What the last `sync` on this instance recorded: "success", "partial" or "failed".
    private(set) var lastOutcome = "none"

    /// Which SDK pages a given user day needs. The only place dayOffset is ever decided.
    static func pages(for day: UserDay, now: Date = Date(), calendar: Calendar = .current) -> [Int] {
        let today = UserDay.containing(now, calendar: calendar)
        // How many device days back the window starts. A device day is midnight-to-midnight,
        // so a user day beginning at 04:00 always sits inside one or two of them.
        let daysBack = calendar.dateComponents([.day], from: day.start, to: today.start).day ?? 0

        // Closing yesterday, or reading it while today is still young: two pages.
        let hour = calendar.component(.hour, from: now)
        let straddles = (day != today) || hour < UserDay.boundaryHour
        return HealthSampleMapping.deviceDayOffsets(daysBack: daysBack, straddles: straddles)
    }

    /// Pull a user day and store it. Returns how many points were written.
    /// `settle` · ask the server for the day's row straight after, and reload it. Off during
    /// a backfill, which settles its whole window once at the end.
    @discardableResult
    func sync(day: UserDay, into store: DataStore, settle: Bool = true) async -> Int {
        let now = Date()
        // ⚠️ raw_samples.user_id is NOT NULL and its insert policy checks it against
        // auth.uid(), exactly like sync_runs and sleep_nights below — and like both of those
        // once were, the rows went up without one. Every upload was refused with a
        // not-null violation, swallowed into BandLog, and the run was still filed as
        // "success": the table stayed empty for as long as the band had been read at all.
        guard let userId = await db.currentUserId else {
            Self.log.error("sync: no session, nothing can be uploaded")
            lastOutcome = "failed"
            return 0
        }
        var calendar = Calendar.current
        calendar.timeZone = .current
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day.start)!
        var points: [DatedPoint] = []
        var hrvNight: HrvNightReading?
        var auxiliaryUploaded = true
        var pagesReturned = 0
        let wanted = Self.pages(for: day)
        let run = await beginRun(userId: userId, requested: wanted.count)

        for offset in wanted {
            let calendarDay = calendar.startOfDay(for:
                calendar.date(byAdding: .day, value: -offset, to: now) ?? now)
            let page: [OriginPoint]
            do {
                page = try await band.readOriginData(dayOffset: offset)
                pagesReturned += 1
            } catch {
                BandLog.shared.record("readOriginData(\(offset))", error: error)
                continue
            }
            let health: BandHealthData
            do {
                health = try await band.readHealthData(dayOffset: offset)
                if Self.dayString(calendarDay) == Self.dayString(day.start) {
                    hrvNight = HealthSampleMapping.nightHRV(from: health.hrv)
                }
            } catch {
                auxiliaryUploaded = false
                BandLog.shared.record("readHealthData(\(offset))", error: error)
                health = BandHealthData(temperatures: [], hrv: [])
            }
            let temperatures = Dictionary(grouping: health.temperatures, by: \.time)
                .compactMapValues { $0.last?.celsius }
            points.append(contentsOf: page.map { point in
                DatedPoint(calendarDay: calendarDay, point: OriginPoint(
                    time: point.time, heart: point.heart, step: point.step, cal: point.cal,
                    distance: point.distance, met: point.met,
                    temperature: temperatures[Self.clock(point.time)],
                    stress: point.stress, sleepState: point.sleepState))
            })
        }

        // A batch is stamped with the phone's timezone at the moment it syncs. One batch never
        // mixes two zones, and a row already stored is never re-stamped.
        let tz = TimeZone.current.identifier
        // ⚠️ One formatter, not one per tick. A day is 288 points and each one was allocating
        // its own ISO8601DateFormatter — the single most expensive thing in a sync that
        // otherwise just moves a few kilobytes.
        let iso = ISO8601DateFormatter()
        // How far this day has already been uploaded. The band only ever appends to a day, and
        // a stored tick is never rewritten (collected data is insert-only), so everything at or
        // before the mark is already on the server and sending it again buys nothing.
        // ⚠️ Advanced only when every chunk of a sync landed. A partial upload that moved the
        // mark would leave a hole no later sync ever fills.
        let mark = Self.watermark(for: day, userId: userId)
        // The latest tick this pull carried, kept aside so the panel can show it the moment it
        // is off the band rather than after the server has settled the day (12 · LIVE).
        var newest: Date?
        var latest: LiveVitals?
        let rows = points.compactMap { dated -> [String: Any]? in
            let point = dated.point
            guard let ts = HealthSampleMapping.instant(time: point.time,
                                                       calendarDay: dated.calendarDay,
                                                       calendar: calendar),
                  ts >= day.start, ts < dayEnd else { return nil }
            // Page 0 is the whole device day, the hours still to come included, as empty
            // slots. A tick that has not happened is not a sample (04 · the readout's "last
            // tick" query already refuses the future; the table should not hold it either).
            guard ts <= now.addingTimeInterval(5 * 60) else { return nil }
            if let mark, ts <= mark { return nil }
            if newest == nil || ts > newest! {
                newest = ts
                // ⚠️ A tick the band recorded off the wrist has no heart and no stress. That
                // is not a zero and not the previous tick's number — it is the absence the
                // readout draws as ——, so it is carried through exactly as it came.
                if point.heart != nil || point.stress != nil {
                    latest = LiveVitals(hr: point.heart, stress: point.stress, at: ts)
                }
            }
            var row: [String: Any] = [
                "user_id": userId,
                "ts": iso.string(from: ts),
                "sampled_tz": tz,
                // The calendar day derived from the offset travels with the batch: without it
                // two pages cannot be put back in order.
                // ⚠️ F7 rule 09 / F2 · both of these are on their way out. They are written only
                // because the live table still has them NOT NULL; migration 20260902010000
                // relaxes that, and 20260902020000 drops them. Delete these two lines when B ships.
                "src": "band",
            ]
            // ⚠️ PostgREST inserts a batch as one statement and refuses it outright —
            // PGRST102 "All object keys must match" — when two rows carry different key
            // sets. Leaving a missing reading out of its row did exactly that (a tick off the
            // wrist has no heart; the next one does), so every row names every column and an
            // absent reading travels as an explicit null.
            row["heart"] = point.heart ?? NSNull()
            row["step"] = point.step ?? NSNull()
            row["cal"] = point.cal ?? NSNull()
            row["dis"] = point.distance ?? NSNull()
            row["met"] = point.met ?? NSNull()
            row["temp"] = point.temperature ?? NSNull()
            row["stress"] = point.stress ?? NSNull()
            row["sleep_states"] = point.sleepState ?? NSNull()
            return row
        }

        // Not one page came back: the band was asked and answered nothing.
        guard pagesReturned > 0 else {
            await record(run, outcome: "failed", requested: wanted.count, returned: pagesReturned)
            return 0
        }

        // Auxiliary domains are retried even when raw_samples has no new ticks. Previously the
        // early return below made one failed sleep/HRV upload permanent after the raw watermark
        // had advanced.
        if let hrvNight {
            do {
                _ = try await db.upsert("night_hrv", row: [
                    "user_id": userId,
                    "user_day": Self.dayString(day.start),
                    "rmssd_ms": hrvNight.rmssdMS,
                    "bucket_count": hrvNight.bucketCount,
                    "rr_count": hrvNight.rrCount,
                    "sampled_tz": tz,
                    "source": "band_rr",
                    "collected_at": iso.string(from: now),
                ], onConflict: "user_id,user_day")
            } catch {
                auxiliaryUploaded = false
                BandLog.shared.record("upsert night_hrv", error: error)
            }
        }

        // The sleep row is keyed to the calendar day on which the user woke. Before 04:00,
        // `wanted` is [0, 1], but this still is yesterday's user day; page 0 is tonight's
        // unfinished sleep and belongs to the next user day. The oldest requested device day
        // is always the calendar date represented by `day.start`.
        if !Self.sleepStored(for: day, userId: userId),
           let night = (try? await band.readSleep(dayOffset: wanted.max() ?? 0)) ?? nil {
            do {
                // 04B rule 04 · the sleepLine rides along as compact "stage:minutes" runs, so
                // the SLEEP strip draws the band's own staging instead of re-deriving it.
                _ = try await db.upsert("sleep_nights", row: [
                    "user_id": userId,
                    "user_day": Self.dayString(day.start),
                    "total_minutes": night.totalMinutes,
                    "deep_minutes": night.deepMinutes,
                    "light_minutes": night.lightMinutes,
                    "wake_count": night.wakeCount,
                    "sleep_line": night.line.map { "\($0.stage):\($0.minutes)" }.joined(separator: ","),
                ], onConflict: "user_id,user_day")
                Self.markSleepStored(for: day, userId: userId)
            } catch {
                auxiliaryUploaded = false
                BandLog.shared.record("upsert sleep_nights", error: error)
            }
        }

        // The band answered and had nothing to add — the common case, since a sync five
        // minutes after a sync finds one new tick or none at all. This is a success, not a
        // failure, and it costs no upload, no settle and no reload: those three are the whole
        // reason a repeat sync used to take as long as the first one.
        if rows.isEmpty {
            if let first = points.first {
                Self.log.notice("sync \(Self.dayString(day.start), privacy: .public): \(points.count) points read, none new · first \(first.point.time, privacy: .public) · mark \(mark.map { iso.string(from: $0) } ?? "none", privacy: .public)")
            }
            Self.apply(latest, to: store)
            let outcome = pagesReturned == wanted.count && auxiliaryUploaded ? "success" : "partial"
            await record(run, outcome: outcome, requested: wanted.count, returned: pagesReturned)
            if outcome == "success" {
                store.lastSync = now
                await Repository.shared.markDeviceSynced(at: now)
            }
            if settle, auxiliaryUploaded {
                await Repository.shared.settleNow(days: day == UserDay.containing(now) ? 1 : 2)
                await Repository.shared.load(days: 1, endingAt: day, into: store)
            }
            return 0
        }

        // Collected data is insert-only and never updated: what the band measured is not ours
        // to change. Re-syncing the same day is a no-op, not a duplicate.
        // ⚠️ The key is (user_id, ts, src). A plain insert was refused wholesale on the first
        // tick already stored — every sync after the first one, since the band only adds —
        // so the ticks that were new never arrived. Duplicates are ignored, row by row.
        let chunks = stride(from: 0, to: rows.count, by: 400).map {
            Array(rows[$0..<min($0 + 400, rows.count)])
        }
        // Chunks are independent inserts into an insert-only table: sending them one after
        // another only added round trips. A backfill day is one chunk; the first sync of a
        // week is the only place this is several, and that is exactly where the wait was.
        let uploaded = await withTaskGroup(of: Bool.self) { group in
            for chunk in chunks {
                group.addTask { [db] in
                    do {
                        _ = try await db.insert("raw_samples", rows: chunk,
                                                ignoringDuplicatesOn: "user_id,ts,src")
                        return true
                    } catch {
                        BandLog.shared.record("insert raw_samples", error: error)
                        return false
                    }
                }
            }
            return await group.reduce(into: true) { $0 = $0 && $1 }
        }
        // Only a clean upload moves the mark. A chunk that failed must be sent again by the
        // next sync, and it will be, because the day is still unmarked behind it.
        if uploaded, pagesReturned == wanted.count, let newest {
            Self.setWatermark(newest, for: day, userId: userId)
        }
        Self.apply(latest, to: store)
        Self.log.notice("sync \(Self.dayString(day.start), privacy: .public): \(rows.count) new ticks, upload \(uploaded ? "ok" : "FAILED", privacy: .public)")
        // A day read off the band and refused by the server is not a sync. The row says
        // so, so the device page cannot print SYNCED over an empty table.
        guard uploaded else {
            await record(run, outcome: "failed", requested: wanted.count, returned: pagesReturned, error: "upload")
            return 0
        }

        // outcome = 'partial' does not move last_origin_sync_at, but the row is still written:
        // that row is the whole basis for the word SYNCED.
        let outcome = pagesReturned == wanted.count && auxiliaryUploaded ? "success" : "partial"
        await record(run, outcome: outcome, requested: wanted.count, returned: pagesReturned)

        if outcome == "success" {
            store.lastSync = now
            await Repository.shared.markDeviceSynced(at: now)
        }
        if settle {
            // The page is on the server; now the day's row, and then the screen. Without
            // this the numbers waited for the hourly cron while the band sat synced.
            await Repository.shared.settleNow(days: day == UserDay.containing(now) ? 1 : 2)
            await Repository.shared.load(days: 1, endingAt: day, into: store)
        }
        return rows.count
    }

    /// A first sync on this phone pulls what the band still holds — `watchDataDayNumber`
    /// days, seven on a HOOP — so the week bars, the heat map and HR_REST stand on a history
    /// from the first evening rather than from the second week. Once per bound band, lowest
    /// priority; the server ignores what it already has, so a re-run costs a transfer and
    /// changes nothing.
    func backfillIfNeeded(into store: DataStore) async {
        guard let bound = BoundBand.identifier,
              let userId = await db.currentUserId else { return }
        // ⚠️ "v2": the first version of this mark was set whether or not a single day had
        // come off the band, and on the phone that found the readBasicData bug it was set
        // after seven failed reads. A new key is the only way that phone asks again.
        let key = "nb.band.backfilled.v3.\(userId).\(bound)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let identity = try? await band.readIdentity()
        // saveDays of 0 is the band not having said; asking for the SDK's usual seven costs
        // nothing, because a page the band does not hold answers empty.
        let held = (identity?.watchDataDayNumber).flatMap { $0 > 0 ? $0 : nil } ?? 7
        let today = UserDay.containing(Date())
        let days = max(0, min(held, 14) - 1)
        var everyDayAnswered = true
        if days > 0 {
            for back in 1...days {
                await sync(day: today.adding(days: -back), into: store, settle: false)
                if lastOutcome != "success" { everyDayAnswered = false }
            }
            await Repository.shared.settleNow(days: days)
            await Repository.shared.load(days: days, endingAt: today, into: store)
        }
        // Only a backfill in which every day answered is over. A day the band did not
        // answer is asked again on the next launch — the mark is not a record of trying.
        if everyDayAnswered { UserDefaults.standard.set(true, forKey: key) }
    }

    private static func clock(_ raw: String) -> String {
        guard let match = raw.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression)
        else { return raw }
        let parts = raw[match].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return raw }
        return String(format: "%02d:%02d", parts[0], parts[1])
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    /// ⚠️ Forwards only. The backfill syncs last week one day at a time, and each of those days
    /// ends at 03:55 this morning — assigning them straight across replaced this minute's tick
    /// with a six-hour-old one, and the panel that exists to show the band is live went ——.
    private static func apply(_ latest: LiveVitals?, to store: DataStore) {
        guard let latest, let at = latest.at else { return }
        if let current = store.vitals.at, current >= at { return }
        store.vitals = latest
    }

    // MARK: what has already been sent

    /// Per bound band, per user day. The band is in the key because a different HOOP has a
    /// different history; forgetting one leaves its marks behind, and they are keyed to an
    /// identifier nothing asks for again.
    private static func watermarkKey(_ day: UserDay, userId: String) -> String {
        "nb.sync.mark.\(userId).\(BoundBand.identifier ?? "none").\(dayString(day.start))"
    }

    static func watermark(for day: UserDay, userId: String) -> Date? {
        let seconds = UserDefaults.standard.double(forKey: watermarkKey(day, userId: userId))
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    static func setWatermark(_ ts: Date, for day: UserDay, userId: String) {
        // Never backwards. Two syncs can overlap — a foreground refresh and the home screen's
        // own — and the one that finishes second is not necessarily the one that read further.
        if let existing = watermark(for: day, userId: userId), existing >= ts { return }
        UserDefaults.standard.set(ts.timeIntervalSince1970,
                                  forKey: watermarkKey(day, userId: userId))
    }

    /// The night for a day that is over is read once and never again. Today's is re-read every
    /// two hours, because a night stored at 05:00 is a night that was still being slept.
    private static func sleepKey(_ day: UserDay, userId: String) -> String {
        "nb.sync.sleep.\(userId).\(BoundBand.identifier ?? "none").\(dayString(day.start))"
    }

    static func sleepStored(for day: UserDay, userId: String, now: Date = Date()) -> Bool {
        let seconds = UserDefaults.standard.double(forKey: sleepKey(day, userId: userId))
        guard seconds > 0 else { return false }
        guard day == UserDay.containing(now) else { return true }
        return now.timeIntervalSince1970 - seconds < 2 * 3600
    }

    static func markSleepStored(for day: UserDay, userId: String, now: Date = Date()) {
        UserDefaults.standard.set(now.timeIntervalSince1970,
                                  forKey: sleepKey(day, userId: userId))
    }

    private struct SyncRun { let id: String?; let startedAt: Date }

    private func beginRun(userId: String, requested: Int) async -> SyncRun {
        let startedAt = Date()
        var row: [String: Any] = [
            "user_id": userId,
            "started_at": ISO8601DateFormatter().string(from: startedAt),
            "days_requested": requested,
        ]
        if let deviceId = Repository.shared.deviceId { row["device_id"] = deviceId }
        do {
            let id = try await db.insert("sync_runs", rows: [row]).first?["id"] as? String
            return SyncRun(id: id, startedAt: startedAt)
        } catch {
            BandLog.shared.record("begin sync_runs", error: error)
            return SyncRun(id: nil, startedAt: startedAt)
        }
    }

    /// ⚠️ user_id is NOT NULL on this table and the insert never sent one, so every write
    /// was rejected and swallowed by the `try?` — the table that exists to explain a bad
    /// sync was empty for exactly as long as syncs had been running.
    ///
    /// outcome = 'partial' does not advance last_origin_sync_at, but the row is still
    /// written: four days out of seven and nothing at all are different events, and that
    /// difference is the whole reason for the table.
    private func record(_ run: SyncRun, outcome: String, requested: Int, returned: Int,
                        error: String? = nil) async {
        lastOutcome = outcome
        guard let userId = await db.currentUserId else { return }
        var completion: [String: Any] = [
            "finished_at": ISO8601DateFormatter().string(from: Date()),
            "outcome": outcome,
            "days_requested": requested,
            "days_returned": returned,
        ]
        if let error { completion["error_code"] = error }
        do {
            if let id = run.id {
                _ = try await db.patch("sync_runs", id: id, row: completion)
            } else {
                completion["user_id"] = userId
                completion["started_at"] = ISO8601DateFormatter().string(from: run.startedAt)
                if let deviceId = Repository.shared.deviceId { completion["device_id"] = deviceId }
                _ = try await db.insert("sync_runs", rows: [completion])
            }
        } catch { BandLog.shared.record("finish sync_runs", error: error) }
    }
}

/// 12 · how often the app asks the band for the day. Chosen on the device page and kept on
/// this phone: it is about this phone's radio and battery, not about the account, so it is
/// not a profile field and never reaches the server.
///
/// The band records a tick every five minutes whatever is chosen here; a longer cadence
/// only means the ticks arrive in bigger batches. Nothing is skipped and nothing is lost.
enum SyncCadence {
    static let options = [5, 10, 15, 30, 60]
    static let `default` = 5
    private static let key = "nb.sync.everyMinutes"

    static var minutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: key)
            return options.contains(v) ? v : `default`
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var interval: TimeInterval { TimeInterval(minutes * 60) }

    /// Two triggers inside one cadence — the app coming forward and the device page opening,
    /// say — are the same question asked twice; the second waits this long.
    static var throttle: TimeInterval { min(120, interval / 2) }

    static func label(_ minutes: Int) -> String {
        minutes < 60 ? "EVERY \(minutes) MIN" : "EVERY HOUR"
    }
}
