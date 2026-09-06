import Foundation
import CryptoKit
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
    private struct DatedPoint { let calendarDay: Date; let readAt: Date; let point: OriginPoint }

    init(band: BandService = Band.live) { self.band = band }

    // MARK: asking again

    private static var inFlight: Task<Void, Never>?
    private static var fullHistoryRequested = false
    private static var lastAttempt: Date?
    private static var lastAttemptUserId: String?

    /// The one entry point for "pull today again": the app coming back to the foreground, the
    /// device page opening, a tap on Device's SYNC, the home screen's own five-minute tick.
    /// Two of those firing together used to mean two full pulls of the same day fighting for
    /// the same serial queue; here the second one waits for the first and then finds nothing
    /// to do. A tap passes `minimumInterval: 0` so cadence does not swallow it.
    ///
    /// 补屏 rule 01 · pairing is not permission. Without consent the band is never read.
    static func refreshNow(into store: DataStore, minimumInterval: TimeInterval = SyncCadence.throttle,
                           fullHistory: Bool = false, reuseRecentLiveReceipt: Bool = false) async {
#if DEBUG
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_SLEEP_EVIDENCE"] == "1" { return }
#endif
        guard LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation, ConsentStore.shared.granted,
              let userId = await SupabaseClient.shared.currentUserId,
              let binding = BoundBand.identifier else { return }
        guard await BandReadiness.shared.ensureReady(into: store, reason: "sync", reuseRecentLiveReceipt: reuseRecentLiveReceipt),
              SupabaseClient.currentUserIdSnapshot() == userId, BoundBand.identifier == binding else { return }
        if let running = inFlight {
            if fullHistory { fullHistoryRequested = true }
            await running.value
            return
        }
        if lastAttemptUserId != userId {
            lastAttempt = nil
            lastAttemptUserId = userId
        }
        if let last = lastAttempt, Date().timeIntervalSince(last) < minimumInterval { return }
        fullHistoryRequested = fullHistory
        // The short readiness flight has finished; coalesce the separate historical/cloud lane.
        let task = Task { @MainActor in
            defer { BandSyncActivity.shared.phase = "idle" }
            BandPresence.shared.start(store: store)
            BandSyncActivity.shared.phase = "connecting"
            store.band.connected = Band.live.state == .connected
            guard LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation, store.band.connected, ConsentStore.shared.granted,
                  await SupabaseClient.shared.currentUserId == userId, BoundBand.identifier == binding else { return }
            BandSyncActivity.shared.phase = "syncing"
            do {
                await BandPresence.shared.refresh(store: store, prepared: BandReadiness.shared.snapshot)
                guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() == userId,
                      BoundBand.identifier == binding, LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else { return }
                _ = try? await BandReadiness.read(account: userId, binding: binding) {
                    await Band.live.prepareFreshSync()
                }
                guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() == userId,
                      BoundBand.identifier == binding, LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else { return }
                let sync = OriginDataSync()
                let today = UserDay.containing(Date())
                _ = await sync.sync(day: today.adding(days: -1), into: store, settle: false)
                guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() == userId,
                      BoundBand.identifier == binding, LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else { return }
                _ = await sync.sync(day: today, into: store)
                guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() == userId,
                      BoundBand.identifier == binding, LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else { return }
                if fullHistoryRequested { await sync.backfillIfNeeded(into: store, force: true) }
                lastAttempt = Date()
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    static func waitForCurrentPull() async {
        if let task = inFlight { await task.value }
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
        HealthSampleMapping.deviceDayOffsets(start: day.start, now: now, calendar: calendar)
    }

    static func nightPageOffsets(start: Date, wake: Date, now: Date,
                                 calendar: Calendar) -> [Int] {
        guard start < wake, wake <= now else { return [] }
        let today = calendar.startOfDay(for: now)
        var cursor = calendar.startOfDay(for: start)
        let finalDay = calendar.startOfDay(for: wake.addingTimeInterval(-1))
        var offsets: [Int] = []
        while cursor <= finalDay {
            if let offset = calendar.dateComponents([.day], from: cursor, to: today).day,
               offset >= 0 { offsets.append(offset) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return offsets
    }

    static func auxiliarySamples(temperatureTicks: [Date: Double],
                                 hrvTicks: [Date: Double], observedAt: Date? = nil) -> [VitalSample] {
        Set(temperatureTicks.keys).union(hrvTicks.keys).sorted().map {
            VitalSample(ts: $0, hr: nil, stress: nil, temp: temperatureTicks[$0], hrv: hrvTicks[$0],
                        hrvValid: hrvTicks[$0] == nil ? nil : true,
                        hrvObservedAt: hrvTicks[$0] == nil ? nil : observedAt)
        }
    }

    /// Pull a user day and store it. Returns how many points were written.
    /// `settle` · ask the server for the day's row straight after, and reload it. Off during
    /// a backfill, which settles its whole window once at the end.
    @discardableResult
    func sync(day: UserDay, into store: DataStore, settle: Bool = true) async -> Int {
        let now = Date()
        let iso = ISO8601DateFormatter()
        let originReadISO = ISO8601DateFormatter()
        originReadISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #if DEBUG
        var diagnosticCompleted = false
        NightDiagnostics.shared.record("sync.started", fields: ["day": day.key, "settle": String(settle)])
        defer {
            NightDiagnostics.shared.record("sync.finished", fields: [
                "day": day.key, "status": diagnosticCompleted ? lastOutcome : "exited_early",
                "cancelled": String(Task.isCancelled),
                "durationSeconds": String(Int(Date().timeIntervalSince(now)))
            ])
        }
        #endif
        // ⚠️ raw_samples.user_id is NOT NULL and its insert policy checks it against
        // auth.uid(), exactly like sync_runs and sleep_nights below — and like both of those
        // once were, the rows went up without one. Every upload was refused with a
        // not-null violation, swallowed into BandLog, and the run was still filed as
        // "success": the table stayed empty for as long as the band had been read at all.
        guard LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation, ConsentStore.shared.granted, let userId = await db.currentUserId else {
            Self.log.error("sync: no session, nothing can be uploaded")
            lastOutcome = "failed"
            return 0
        }
        await Self.flushPendingEvidence(userId: userId)
        var calendar = Calendar.current
        calendar.timeZone = .current
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day.start)!
        let readEnd = min(dayEnd, now)
        var points: [DatedPoint] = []
        /// Every measured HRV tick of this user day, by instant. Both a column on the rows
        /// this sync inserts and the payload that fills the rows earlier syncs already stored.
        var hrvTicks: [Date: Double] = [:]
        var invalidHrvTicks: Set<Date> = []
        var hrvMinuteTicks: [Date: Double] = [:]
        var invalidHrvMinutes: Set<Date> = []
        var hrvMinuteReadComplete = false
        var temperatureTicks: [Date: Double] = [:]
        var auxiliaryUploaded = true
        var hrvStatus: BandDomainReadStatus = .complete
        var temperatureStatus: BandDomainReadStatus = .complete
        var oxygenStatus: BandDomainReadStatus = .complete
        var oxygenTicks: [Date: Int] = [:]
        var respirationTicks: [Date: Double] = [:]
        var healthPages: [Int: BandHealthData] = [:]
        var nightAuxiliary: [VitalSample] = []
        var opticalStatus: BandDomainReadStatus = .complete
        var opticalTicks: [Date: Double] = [:]
        var opticalDroppedZeros = 0
        var rrRows: [[String: Any]] = []
        guard let deviceKey = BoundBand.identifier else { lastOutcome = "failed"; return 0 }
        var domainStates: [BandDomainSyncState] = []
        var pagesReturned = 0
        let wanted = Self.pages(for: day, now: now, calendar: calendar)
        let run = await beginRun(userId: userId, requested: wanted.count)

        for offset in wanted {
            guard LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else { lastOutcome = "failed"; return 0 }
            let calendarDay = calendar.startOfDay(for:
                calendar.date(byAdding: .day, value: -offset, to: now) ?? now)
            let page: [OriginPoint]
            do {
                page = try await BandReadiness.read(account: userId, binding: deviceKey) { try await band.readOriginData(dayOffset: offset) }
                pagesReturned += 1
            } catch {
                #if DEBUG
                NightDiagnostics.shared.record("sync.origin_read_failed", fields: [
                    "day": day.key, "offset": String(offset), "errorType": String(describing: type(of: error))
                ])
                #endif
                BandLog.shared.record("readOriginData(\(offset))", error: error)
                page = []
            }
            // This is the SDK database observation time, preserved through offline retries.
            // It orders revisions; it is not a device-reported measurement timestamp.
            let originReadAt = Date()
            let health: BandHealthData
            do {
                health = try await BandReadiness.read(account: userId, binding: deviceKey) { try await band.readHealthData(dayOffset: offset) }
            } catch {
                #if DEBUG
                NightDiagnostics.shared.record("sync.health_read_failed", fields: [
                    "day": day.key, "offset": String(offset), "errorType": String(describing: type(of: error))
                ])
                #endif
                auxiliaryUploaded = false
                BandLog.shared.record("readHealthData(\(offset))", error: error)
                health = BandHealthData(temperatures: [], hrv: [], oxygen: [],
                                        temperatureStatus: .failed, hrvStatus: .failed,
                                        oxygenStatus: .failed, opticalStatus: .failed)
            }
            healthPages[offset] = health
            if health.respirationStatus == .failed { auxiliaryUploaded = false }
            if health.hrvStatus != .complete && hrvStatus != .failed { hrvStatus = health.hrvStatus }
            if health.temperatureStatus != .complete && temperatureStatus != .failed { temperatureStatus = health.temperatureStatus }
            if health.oxygenStatus != .complete && oxygenStatus != .failed { oxygenStatus = health.oxygenStatus }
            if health.opticalStatus != .complete && opticalStatus != .failed { opticalStatus = health.opticalStatus }
            if health.hrvStatus == .failed || health.temperatureStatus == .failed
                || health.oxygenStatus == .failed || health.opticalStatus == .failed { auxiliaryUploaded = false }
            for (time, value) in HealthSampleMapping.hrvByMinute(health.hrv) {
                guard let ts = HealthSampleMapping.instant(time: time, calendarDay: calendarDay,
                                                           calendar: calendar), ts <= now else { continue }
                hrvMinuteTicks[ts] = value
            }
            for time in HealthSampleMapping.invalidHRVMinutes(health.hrv) {
                guard let ts = HealthSampleMapping.instant(time: time, calendarDay: calendarDay,
                                                           calendar: calendar), ts <= now else { continue }
                invalidHrvMinutes.insert(ts)
            }
            for sample in health.hrv where !sample.rrMilliseconds.isEmpty {
                guard let ts = HealthSampleMapping.instant(time: sample.time, calendarDay: calendarDay, calendar: calendar),
                      ts >= day.start, ts < dayEnd, ts <= now else { continue }
                rrRows.append(["ts": iso.string(from: ts), "rr_ms": sample.rrMilliseconds,
                               "rr_indices": sample.rrValidIndices])
            }
            for sample in health.temperatures {
                guard let ts = HealthSampleMapping.instant(time: sample.time, calendarDay: calendarDay, calendar: calendar),
                      ts >= day.start, ts < dayEnd, ts <= now else { continue }
                temperatureTicks[ts] = sample.celsius
            }
            let temperatures = Dictionary(grouping: health.temperatures, by: \.time)
                .compactMapValues { $0.last?.celsius }
            // The band measures HRV every ten minutes, all day — not only at night. Both
            // domains are read from the same page, so this is where they are joined.
            let hrvBySlot = HealthSampleMapping.hrvBySlot(health.hrv)
            for slot in HealthSampleMapping.invalidHRVSlots(health.hrv) {
                guard let ts = HealthSampleMapping.instant(time: slot, calendarDay: calendarDay,
                                                           calendar: calendar),
                      ts >= day.start, ts < dayEnd, ts <= now else { continue }
                invalidHrvTicks.insert(ts)
            }
            // Kept with their instants as well: a tick stored by an earlier sync cannot be
            // re-inserted carrying its HRV, so those rows are filled in afterwards.
            for (slot, value) in hrvBySlot {
                guard let ts = HealthSampleMapping.instant(time: slot, calendarDay: calendarDay,
                                                           calendar: calendar),
                      ts >= day.start, ts < dayEnd else { continue }
                hrvTicks[ts] = value
            }
            for sample in health.oxygen {
                guard let ts = HealthSampleMapping.instant(time: sample.time, calendarDay: calendarDay,
                                                           calendar: calendar),
                      ts <= now else { continue }
                oxygenTicks[ts] = sample.percent
            }
            for sample in health.respiration {
                guard let ts = HealthSampleMapping.instant(time: sample.time, calendarDay: calendarDay,
                                                           calendar: calendar), ts <= now else { continue }
                respirationTicks[ts] = sample.breathsPerMinute
            }
            opticalDroppedZeros += health.opticalDroppedZeros
            for sample in health.optical {
                guard let ts = HealthSampleMapping.instant(time: sample.time, calendarDay: calendarDay,
                                                           calendar: calendar),
                      ts >= day.start, ts < dayEnd, ts <= now else { continue }
                opticalTicks[ts] = sample.optical
            }
            points.append(contentsOf: page.map { point in
                DatedPoint(calendarDay: calendarDay, readAt: originReadAt, point: OriginPoint(
                    time: point.time, heart: point.heart, step: point.step, cal: point.cal,
                    distance: point.distance, met: VitalSample.validatedMET(point.met),
                    temperature: temperatures[Self.clock(point.time)],
                    hrv: hrvBySlot[Self.clock(point.time)],
                    stress: point.stress, sleepState: point.sleepState))
            })
        }

        // Read every real sync: an earlier sleep record may have extended after the user woke.
        var night: SleepNight?
        var sleepStatus: BandDomainReadStatus = .notCollected
        do {
            night = try await BandReadiness.read(account: userId, binding: deviceKey) {
                try await band.readSleep(dayOffset: wanted.max() ?? 0)
            }
        } catch {
            sleepStatus = .failed
            auxiliaryUploaded = false
            BandLog.shared.record("readSleep(\(wanted.max() ?? 0))", error: error)
        }
        // Sleep owns its recorded clock, including pre-04:00 and previous calendar pages.
        // Reuse already-read pages and fetch any missing pages serially on the BLE queue.
        if let (start, wake) = Self.nightWindow(day: day, night: night, store: store) {
            let requiredHrvPages = Self.nightPageOffsets(start: start, wake: wake, now: now, calendar: calendar)
            for offset in requiredHrvPages {
                let health: BandHealthData
                if let cached = healthPages[offset] { health = cached }
                else {
                    do {
                        health = try await BandReadiness.read(account: userId, binding: deviceKey) {
                            try await band.readHealthData(dayOffset: offset)
                        }
                        healthPages[offset] = health
                    } catch {
                        hrvStatus = .failed
                        oxygenStatus = .failed
                        auxiliaryUploaded = false
                        BandLog.shared.record("read sleep health page(\(offset))", error: error)
                        continue
                    }
                }
                if health.hrvStatus != .complete && hrvStatus != .failed { hrvStatus = health.hrvStatus }
                if health.oxygenStatus != .complete && oxygenStatus != .failed { oxygenStatus = health.oxygenStatus }
                if health.hrvStatus == .failed || health.oxygenStatus == .failed
                    || health.respirationStatus == .failed { auxiliaryUploaded = false }
                let calendarDay = calendar.startOfDay(for:
                    calendar.date(byAdding: .day, value: -offset, to: now) ?? now)
                for sample in health.oxygen {
                    guard let ts = HealthSampleMapping.instant(time: sample.time, calendarDay: calendarDay,
                                                               calendar: calendar), ts >= start, ts < wake else { continue }
                    oxygenTicks[ts] = sample.percent
                }
                for sample in health.respiration {
                    guard let ts = HealthSampleMapping.instant(time: sample.time, calendarDay: calendarDay,
                                                               calendar: calendar), ts >= start, ts < wake else { continue }
                    respirationTicks[ts] = sample.breathsPerMinute
                }
                for (time, value) in HealthSampleMapping.hrvByMinute(health.hrv) {
                    guard let ts = HealthSampleMapping.instant(time: time, calendarDay: calendarDay,
                                                               calendar: calendar), ts >= start, ts < wake else { continue }
                    hrvMinuteTicks[ts] = value
                }
                for time in HealthSampleMapping.invalidHRVMinutes(health.hrv) {
                    guard let ts = HealthSampleMapping.instant(time: time, calendarDay: calendarDay,
                                                               calendar: calendar), ts >= start, ts < wake else { continue }
                    invalidHrvMinutes.insert(ts)
                }
                let temperature = health.temperatures.compactMap { sample -> VitalSample? in
                    guard let ts = HealthSampleMapping.instant(time: sample.time, calendarDay: calendarDay,
                                                               calendar: calendar), ts >= start, ts < wake else { return nil }
                    return VitalSample(ts: ts, hr: nil, stress: nil, temp: sample.celsius)
                }
                let hrv = HealthSampleMapping.hrvBySlot(health.hrv).compactMap { clock, value -> VitalSample? in
                    guard let ts = HealthSampleMapping.instant(time: clock, calendarDay: calendarDay,
                                                               calendar: calendar), ts >= start, ts < wake else { return nil }
                    return VitalSample(ts: ts, hr: nil, stress: nil, hrv: value,
                                       hrvValid: true, hrvObservedAt: now)
                }
                nightAuxiliary = VitalSample.merging(nightAuxiliary, with: temperature + hrv)
            }
            // A missing/failed extra page is unknown, not proof of an empty RR night.
            hrvMinuteReadComplete = !requiredHrvPages.isEmpty && requiredHrvPages.allSatisfy {
                guard let status = healthPages[$0]?.hrvStatus else { return false }
                return status == .complete || status == .unsupported
            }
        }

        // SDK times have no timezone. Preserve the mapping timezone used for this batch;
        // it is a reconstruction assumption, not a device-reported historical timezone.
        let tz = TimeZone.current.identifier
        // ⚠️ One formatter, not one per tick. A day is 288 points and each one was allocating
        // its own ISO8601DateFormatter — the single most expensive thing in a sync that
        // otherwise just moves a few kilobytes.
        // Read the complete bounded pages every time. Earlier aggregates can be completed
        // by the device later; an upload watermark must never hide those revisions.
        // The latest tick this pull carried, kept aside so the panel can show it the moment it
        // is off the band rather than after the server has settled the day (12 · LIVE).
        var newest: Date?
        var latest: LiveVitals?
        var localSamples: [VitalSample] = []
        let rows = points.compactMap { dated -> [String: Any]? in
            let point = dated.point
            guard let ts = HealthSampleMapping.instant(time: point.time,
                                                       calendarDay: dated.calendarDay,
                                                       calendar: calendar),
                  ts >= day.start, ts < dayEnd else { return nil }
            // Page 0 includes future placeholders and the aggregate still accumulating.
            // Deferred slots are considered again on the next full page read.
            guard OriginObservationPolicy.accepts(slot: ts, dayStart: day.start,
                dayEnd: dayEnd, readStartedAt: now) else { return nil }
            if let temperature = point.temperature {
                temperatureTicks[ts] = temperature
            }
            let localSample = VitalSample(
                ts: ts,
                hr: point.heart,
                stress: point.stress,
                temp: point.temperature,
                steps: point.step,
                met: point.met,
                vendorCalories: point.cal.map(Double.init),
                dis: point.distance.map(Double.init),
                hrv: point.hrv,
                hrvValid: point.hrv == nil ? nil : true,
                hrvObservedAt: point.hrv == nil ? nil : now
            )
            if localSample.hasReading {
                localSamples.append(localSample)
            }
            if newest == nil || ts > newest! {
                newest = ts
                // ⚠️ A tick the band recorded off the wrist has no heart and no stress. That
                // is not a zero — it is the absence the readout draws as ——. Heart stays
                // that tick's own reading. Stress is often missing on a worn sleep tick that
                // still has PPG heart, so the last positive stress in 24h is joined rather
                // than dashed.
                if point.heart != nil || point.stress != nil {
                    latest = LiveVitals(
                        hr: VitalsTimelinePolicy.currentHeart(
                            latest: point.heart,
                            previous: latest.flatMap { reading in
                                guard let value = reading.hr, let at = reading.at else { return nil }
                                return (value, at)
                            },
                            at: ts),
                        stress: VitalsTimelinePolicy.currentStress(
                            latest: point.stress,
                            previous: latest.flatMap { reading in
                                guard let value = reading.stress, let at = reading.at else { return nil }
                                return (value, at)
                            },
                            at: ts),
                        at: ts)
                }
            }
            // Re-read the bounded SDK day to repair late facts and holes before any cursor.
            // The server acknowledges unchanged observations without rewriting them.
            guard point.heart != nil || point.step != nil || point.cal != nil || point.distance != nil
                || point.met != nil || point.stress != nil || point.sleepState != nil else { return nil }
            var row: [String: Any] = [
                "user_id": userId,
                "ts": iso.string(from: ts),
                "origin_read_at": originReadISO.string(from: dated.readAt),
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
            row["hrv"] = point.hrv ?? NSNull()
            row["stress"] = point.stress ?? NSNull()
            row["sleep_states"] = point.sleepState ?? NSNull()
            return row
        }

        invalidHrvTicks.subtract(hrvTicks.keys)
        let invalidHrvSamples = invalidHrvTicks.sorted().map {
            VitalSample(ts: $0, hr: nil, stress: nil, hrvValid: false, hrvObservedAt: now)
        }
        localSamples = VitalSample.merging(localSamples, with:
            Self.auxiliarySamples(temperatureTicks: temperatureTicks, hrvTicks: hrvTicks,
                                  observedAt: now) + nightAuxiliary + invalidHrvSamples)
        guard ConsentStore.shared.granted, await db.currentUserId == userId,
              BoundBand.identifier == deviceKey, !Task.isCancelled else { lastOutcome = "failed"; return 0 }
        Self.clearWrongDaySleep(for: day, store: store)
        invalidHrvMinutes.subtract(hrvMinuteTicks.keys)
        let measuredSleep = Self.sleepSummary(night: night, day: day, store: store,
                                             oxygen: oxygenTicks, respiration: respirationTicks,
                                             hrv: hrvMinuteTicks, hrvReadComplete: hrvMinuteReadComplete,
                                             invalidHrvMinutes: invalidHrvMinutes, observedAt: now)
        #if DEBUG
        NightDiagnostics.shared.record("sync.mapped", fields:
            HomeSnapshot.diagnosticFields(day: day, samples: localSamples, sleep: measuredSleep).merging([
                "hrvFiveMinuteSlots": String(hrvTicks.count),
                "hrvMinuteTicksAcrossReadPages": String(hrvMinuteTicks.count),
                "nightHRVReadComplete": String(hrvMinuteReadComplete),
                "hrvReadStatus": hrvStatus.rawValue,
                "temperatureReadStatus": temperatureStatus.rawValue,
                "oxygenReadStatus": oxygenStatus.rawValue,
                "sleepReadStatus": sleepStatus == .failed ? "failed" : (night != nil ? "returned" : "empty"),
                "sdkSleepPresent": String(night != nil),
                "pagesRequested": String(wanted.count), "pagesReturned": String(pagesReturned)
            ], uniquingKeysWith: { _, fresh in fresh }))
        #endif
        if let measuredSleep { Self.apply(measuredSleep, for: day, to: store) }
        let samplesByDay = Dictionary(grouping: localSamples) { UserDay.containing($0.ts, calendar: calendar) }
        // Durable measured observations precede every measurement upload and server refresh.
        do {
            for measuredDay in Set(samplesByDay.keys).union([day]) {
                let samples = samplesByDay[measuredDay] ?? []
                Self.apply(samples, for: measuredDay, to: store)
                try HomeSnapshot.saveBandObservations(day: measuredDay, samples: samples,
                    sleep: measuredDay == day ? measuredSleep : nil, userId: userId)
            }
        } catch {
            #if DEBUG
            NightDiagnostics.shared.record("sync.local_persist_failed", fields: [
                "day": day.key, "errorType": String(describing: type(of: error))
            ])
            #endif
            auxiliaryUploaded = false
            BandLog.shared.record("persist band observations", error: error)
            lastOutcome = "failed"
            return 0
        }

        do {
            _ = try persistEvidence(samples: rows, args: [
                "p_device_key": deviceKey, "p_domain": "origin", "p_day": Self.dayString(day.start),
                "p_timezone": tz, "p_start": iso.string(from: day.start), "p_end": iso.string(from: readEnd),
                "p_status": "partial", "p_mapping_version": "veepoo-rmssd-v1",
                "p_observed_at": iso.string(from: now),
            ], userId: userId)
            _ = try persistEvidence(samples: rrRows, args: [
                "p_device_key": deviceKey, "p_domain": "rr", "p_day": Self.dayString(day.start),
                "p_timezone": tz, "p_start": iso.string(from: day.start), "p_end": iso.string(from: readEnd),
                "p_status": "partial", "p_mapping_version": "veepoo-rmssd-v2",
                "p_observed_at": iso.string(from: now),
            ], userId: userId)
        } catch {
            auxiliaryUploaded = false
            BandLog.shared.record("persist RR evidence", error: error)
        }

        // The band is the immediate source for raw curves. Do not hold its 12:45 tick behind
        // settle_now: derived daily values remain server-authoritative, while measured points
        // can be shown as soon as they leave the wrist. The timestamp merge also preserves
        // HRV or temperature already loaded from their auxiliary SDK streams.
        Self.apply(latest, to: store)

        // ⚠️ The night's own HRV is not computed here and never was computable here. A night
        // that begins before midnight lies in the previous calendar day — a different SDK
        // page and a different user day — so a sync reading today's page cannot see its own
        // night's first half. The phone sends every tick's RMSSD and the server takes the
        // night from them, between the sleep window this same sync uploads
        // (nb.night_hrv · migration 20260903110000).

        // Auxiliary domains are retried even when raw_samples has no new ticks: the early
        // return below once made one failed upload permanent after the raw watermark moved.
        //
        // The sleep row is keyed to the calendar day on which the user woke. Before 04:00,
        // `wanted` is [0, 1], but this still is yesterday's user day; page 0 is tonight's
        // unfinished sleep and belongs to the next user day. The oldest requested device day
        // is always the calendar date represented by `day.start`.
        if let sleep = measuredSleep, night != nil {
            guard ConsentStore.shared.granted, await db.currentUserId == userId else { lastOutcome = "failed"; return 0 }
            do {
                // 04B rule 04 · the sleepLine rides along as compact "stage:minutes" runs, so
                // the SLEEP strip draws the band's own staging instead of re-deriving it.
                var row: [String: Any] = [
                    "user_id": userId,
                    "user_day": Self.dayString(day.start),
                    "total_minutes": sleep.totalMinutes,
                    "deep_minutes": sleep.deepMinutes,
                    "light_minutes": sleep.lightMinutes,
                    "wake_count": sleep.wakeCount,
                    "sleep_line": sleep.line.map { "\($0.stage):\($0.minutes)" }.joined(separator: ","),
                ]
                // The night's window feeds nb.night_rhr (migration 20260903090000). Until that
                // migration is on the server PostgREST refuses unknown columns, so the row
                // goes up once more without them rather than not at all.
                if let start = sleep.sleepStart, let wake = sleep.wakeAt {
                    row["sleep_start"] = iso.string(from: start)
                    row["wake_at"] = iso.string(from: wake)
                }
                let respirationRows: [[String: Any]] = (measuredSleep?.respiration ?? []).map {
                    ["ts": iso.string(from: $0.ts), "breaths_per_minute": $0.breathsPerMinute]
                }
                let intervals: [[String: Any]] = (measuredSleep?.intervals ?? []).map {
                    ["start": iso.string(from: $0.start), "end": iso.string(from: $0.end)]
                }
                let stageRows: [[String: Any]] = sleep.line.map {
                    ["stage": $0.stage, "minutes": $0.minutes, "offset_minutes": $0.offsetMinutes ?? NSNull()]
                }
                var raw: [String: Any] = ["respiration": respirationRows,
                                          "intervals": intervals, "line": stageRows]
                if let hrv = measuredSleep?.hrv {
                    raw["hrv"] = hrv.map { point -> [String: Any] in
                        var row: [String: Any] = ["ts": iso.string(from: point.ts), "rmssd_ms": point.rmssdMS]
                        if let observedAt = point.observedAt { row["observed_at"] = iso.string(from: observedAt) }
                        return row
                    }
                }
                if let invalidations = measuredSleep?.hrvInvalidatedMinutes, !invalidations.isEmpty {
                    raw["hrv_invalidated"] = invalidations.sorted { $0.key < $1.key }.map {
                        ["ts": iso.string(from: $0.key), "observed_at": iso.string(from: $0.value),
                         "reason": "insufficient_adjacent_rr"]
                    }
                }
                row["raw"] = raw
                let local = try LocalDataStore.shared()
                let payload = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                let id = "sleep-" + SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
                try local.enqueue(operation: LocalOperation(id: id, account: userId, kind: "band-sleep", payload: payload))
                try await Self.uploadSleep(row, userId: userId)
                try local.acknowledge(account: userId, id: id)
                sleepStatus = .complete
            } catch {
                auxiliaryUploaded = false
                sleepStatus = .failed
                BandLog.shared.record("upsert sleep_nights", error: error)
            }
        }

        // Every domain is acknowledged independently. Read failures keep a repair range and
        // cannot inherit another domain's success. Full-day overlap is bounded by SDK pages.
        let originStatus: BandDomainReadStatus = pagesReturned == wanted.count ? .complete : .partial
        let domains: [(String, [[String: Any]], BandDomainReadStatus)] = [
            ("origin", rows, originStatus),
            ("hrv", hrvTicks.sorted { $0.key < $1.key }.map {
                ["ts": iso.string(from: $0.key), "hrv": ($0.value * 10).rounded() / 10, "hrv_valid": true]
            } + invalidHrvTicks.sorted().map {
                ["ts": iso.string(from: $0), "hrv": NSNull(), "hrv_valid": false,
                 "hrv_invalid_reason": "insufficient_adjacent_rr"]
            }, hrvStatus),
            ("temperature", temperatureTicks.sorted { $0.key < $1.key }.map {
                ["ts": iso.string(from: $0.key), "temp": ($0.value * 10).rounded() / 10]
            }, temperatureStatus),
            ("rr", rrRows, hrvStatus),
            ("sleep", [], sleepStatus),
        ]
        var changedCount = 0
        for (domain, samples, readStatus) in domains {
            guard ConsentStore.shared.granted, await db.currentUserId == userId else {
                lastOutcome = "failed"; return changedCount
            }
            var status = readStatus
            do {
                let args: [String: Any] = [
                    "p_device_key": deviceKey, "p_domain": domain,
                    "p_day": Self.dayString(day.start), "p_timezone": tz,
                    "p_start": iso.string(from: day.start), "p_end": iso.string(from: readEnd),
                    "p_samples": samples, "p_status": readStatus.rawValue,
                    // RR adjacency changed in v2; the origin mapping is unchanged.
                    "p_mapping_version": domain == "origin" ? "veepoo-rmssd-v1" : "veepoo-rmssd-v2",
                    "p_observed_at": iso.string(from: now),
                ]
                let pending = try persistEvidence(samples: samples, args: args, userId: userId)
                let response = try await db.rpc("ingest_band_domain", args: args, expectedOwner: userId)
                guard SupabaseClient.currentUserIdSnapshot() == userId, !Task.isCancelled else { return changedCount }
                let data = try JSONSerialization.data(withJSONObject: response)
                let ack = try JSONDecoder().decode(BandIngestionAcknowledgment.self, from: data)
                changedCount += ack.inserted + ack.completed
                if ack.confirms(offered: samples.count) {
                    let local = try LocalDataStore.shared()
                    try local.acknowledge(account: userId, ids: pending)
                }
                if !ack.confirms(offered: samples.count) { status = .partial }
                else if samples.isEmpty && readStatus == .complete && domain != "sleep" { status = .notCollected }
            } catch {
                status = .failed
                BandLog.shared.record("ingest \(domain)", error: error)
            }
            let confirmed = status == .complete || status == .notCollected || status == .unsupported
            if !confirmed { auxiliaryUploaded = false }
            domainStates.append(BandDomainSyncState(domain: domain, status: status, attemptedAt: now,
                acknowledgedStart: confirmed ? day.start : nil, acknowledgedEnd: confirmed ? readEnd : nil,
                repairStart: confirmed ? nil : day.start, repairEnd: confirmed ? nil : readEnd))
        }
        let oxygenWindow = Self.nightWindow(day: day, night: night, store: store)
        var oxygenRead = oxygenStatus
        let oxygenStart: Date
        let oxygenEnd: Date
        let oxygenSamples: [[String: Any]]
        if let (start, wake) = oxygenWindow {
            oxygenStart = start
            oxygenEnd = max(wake, start.addingTimeInterval(60))
            oxygenSamples = (measuredSleep?.spo2 ?? []).map {
                ["ts": iso.string(from: $0.ts), "spo2": $0.percent]
            }
            if oxygenSamples.isEmpty && oxygenRead == .complete { oxygenRead = .notCollected }

        } else {
            oxygenStart = day.start
            oxygenEnd = readEnd
            oxygenSamples = []
            if oxygenRead == .complete { oxygenRead = .notCollected }
        }
        if ConsentStore.shared.granted, await db.currentUserId == userId {
            var status = oxygenRead
            do {
                let args: [String: Any] = [
                    "p_device_key": deviceKey, "p_domain": "oxygen",
                    "p_day": Self.dayString(day.start), "p_timezone": tz,
                    "p_start": iso.string(from: oxygenStart), "p_end": iso.string(from: oxygenEnd),
                    "p_samples": oxygenSamples, "p_status": oxygenRead.rawValue,
                    "p_mapping_version": "veepoo-spo2-v1",
                    "p_observed_at": iso.string(from: now),
                ]
                let pending = try persistEvidence(samples: oxygenSamples, args: args, userId: userId)
                let response = try await db.rpc("ingest_band_domain", args: args, expectedOwner: userId)
                guard SupabaseClient.currentUserIdSnapshot() == userId, !Task.isCancelled else { return changedCount }
                let data = try JSONSerialization.data(withJSONObject: response)
                let ack = try JSONDecoder().decode(BandIngestionAcknowledgment.self, from: data)
                changedCount += ack.inserted + ack.completed
                if ack.confirms(offered: oxygenSamples.count) {
                    let local = try LocalDataStore.shared()
                    try local.acknowledge(account: userId, ids: pending)
                }
                if !ack.confirms(offered: oxygenSamples.count) { status = .partial }
                else if oxygenSamples.isEmpty && oxygenRead == .complete { status = .notCollected }
            } catch {
                status = .failed
                BandLog.shared.record("ingest oxygen", error: error)
            }
            let confirmed = status == .complete || status == .notCollected || status == .unsupported
            if !confirmed { auxiliaryUploaded = false }
            domainStates.append(BandDomainSyncState(domain: "oxygen", status: status, attemptedAt: now,
                acknowledgedStart: confirmed ? oxygenStart : nil, acknowledgedEnd: confirmed ? oxygenEnd : nil,
                repairStart: confirmed ? nil : oxygenStart, repairEnd: confirmed ? nil : oxygenEnd))
        }
        if store.today.day == day {
            store.mealResponseZerosToday = opticalDroppedZeros > 0 && opticalTicks.isEmpty
        }
        let incomingOptical = opticalTicks.keys.sorted().map {
            MealResponseIndex.Point(ts: $0, optical: opticalTicks[$0]!)
        }
        store.mealResponsePoints = Self.mergeOptical(store.mealResponsePoints, with: incomingOptical)
        var opticalRead = opticalStatus
        let opticalSamples = opticalTicks.sorted { $0.key < $1.key }
            .map { ["ts": iso.string(from: $0.key), "optical": $0.value] }
        if opticalSamples.isEmpty && opticalRead == .complete { opticalRead = .notCollected }
        if ConsentStore.shared.granted, await db.currentUserId == userId {
            var status = opticalRead
            do {
                let args: [String: Any] = [
                    "p_device_key": deviceKey, "p_domain": "response",
                    "p_day": Self.dayString(day.start), "p_timezone": tz,
                    "p_start": iso.string(from: day.start), "p_end": iso.string(from: readEnd),
                    "p_samples": opticalSamples, "p_status": opticalRead.rawValue,
                    "p_mapping_version": "veepoo-optical-v1",
                    "p_observed_at": iso.string(from: now),
                ]
                let pending = try persistEvidence(samples: opticalSamples, args: args, userId: userId)
                let response = try await db.rpc("ingest_band_domain", args: args, expectedOwner: userId)
                guard SupabaseClient.currentUserIdSnapshot() == userId, !Task.isCancelled else { return changedCount }
                let data = try JSONSerialization.data(withJSONObject: response)
                let ack = try JSONDecoder().decode(BandIngestionAcknowledgment.self, from: data)
                changedCount += ack.inserted + ack.completed
                if ack.confirms(offered: opticalSamples.count) {
                    let local = try LocalDataStore.shared()
                    try local.acknowledge(account: userId, ids: pending)
                }
                if !ack.confirms(offered: opticalSamples.count) { status = .partial }
                else if opticalSamples.isEmpty && opticalRead == .complete { status = .notCollected }
            } catch {
                status = .failed
                BandLog.shared.record("ingest response", error: error)
            }
            let confirmed = status == .complete || status == .notCollected || status == .unsupported
            if !confirmed { auxiliaryUploaded = false }
            domainStates.append(BandDomainSyncState(domain: "response", status: status, attemptedAt: now,
                acknowledgedStart: confirmed ? day.start : nil, acknowledgedEnd: confirmed ? readEnd : nil,
                repairStart: confirmed ? nil : day.start, repairEnd: confirmed ? nil : readEnd))
        }
        guard ConsentStore.shared.granted, await db.currentUserId == userId else { lastOutcome = "failed"; return changedCount }
        do { try BandDomainSyncState.save(domainStates, userId: userId, deviceKey: deviceKey, day: Self.dayString(day.start)) }
        catch { BandLog.shared.record("save domain acknowledgments", error: error) }
        let outcome = pagesReturned == wanted.count && auxiliaryUploaded ? "success" : "partial"
        await record(run, outcome: outcome, requested: wanted.count, returned: pagesReturned)
        if outcome == "success", await db.currentUserId == userId {
            store.lastSync = now
            if let newest { Self.setWatermark(newest, for: day, userId: userId) }
            await Repository.shared.markDeviceSynced(at: now)
        }
        if settle, await db.currentUserId == userId {
            await Repository.shared.settleNow(days: day == UserDay.containing(now) ? 1 : 2)
            await Repository.shared.load(days: 1, endingAt: day, into: store)
            guard await db.currentUserId == userId else { return changedCount }
            await Repository.shared.loadSleepScores(days: 30, endingAt: store.today.day, into: store)
        }
        #if DEBUG
        diagnosticCompleted = true
        #endif
        return changedCount
    }

    /// Old cache rows sometimes filed a valid sleep under the previous user day. Sleep
    /// belongs to the calendar date of its wake, including wakes after noon.
    private static func sleepOnCalendarDay(_ sleep: SleepSummary?, day: UserDay) -> SleepSummary? {
        guard let wake = sleep?.wakeAt else { return sleep }
        return Calendar.current.isDate(wake, inSameDayAs: day.start) ? sleep : nil
    }

    private static func clearWrongDaySleep(for day: UserDay, store: DataStore) {
        if store.today.day == day {
            store.today.sleep = Self.sleepOnCalendarDay(store.today.sleep, day: day)
        }
        store.history = store.history.map { stored in
            guard stored.day == day else { return stored }
            var result = stored
            result.sleep = Self.sleepOnCalendarDay(stored.sleep, day: day)
            return result
        }
    }

    private static func sleepSummary(night: SleepNight?, day: UserDay, store: DataStore,
                                     oxygen: [Date: Int], respiration: [Date: Double],
                                     hrv: [Date: Double] = [:], hrvReadComplete: Bool = false,
                                     invalidHrvMinutes: Set<Date> = [], observedAt: Date = Date()) -> SleepSummary? {
        let existing = Self.sleepOnCalendarDay(
            (store.today.day == day ? store.today : store.history.first { $0.day == day })?.sleep, day: day)
        let sameWindow = night?.sleepStart == existing?.sleepStart && night?.wakeAt == existing?.wakeAt
        let incomingIsContained: Bool = {
            guard let oldStart = existing?.sleepStart, let oldWake = existing?.wakeAt,
                  let newStart = night?.sleepStart, let newWake = night?.wakeAt else { return false }
            return oldStart <= newStart && oldWake >= newWake
                && (existing?.totalMinutes ?? 0) >= (night?.totalMinutes ?? 0)
                && (oldStart < newStart || oldWake > newWake
                    || (existing?.totalMinutes ?? 0) > (night?.totalMinutes ?? 0))
        }()
        let summary = incomingIsContained ? existing : night.map {
            SleepSummary(totalMinutes: $0.totalMinutes, deepMinutes: $0.deepMinutes,
                         lightMinutes: $0.lightMinutes, wakeCount: $0.wakeCount,
                         line: $0.line.isEmpty && sameWindow ? existing?.line ?? [] : $0.line,
                         sleepStart: $0.sleepStart, wakeAt: $0.wakeAt)
        } ?? existing
        guard var result = summary, let start = result.sleepStart, let wake = result.wakeAt else { return summary }
        if !incomingIsContained {
            if let intervals = night?.intervals { result.intervals = intervals }
            else if sameWindow && result.intervals == nil { result.intervals = existing?.intervals }
        }
        let intervals = result.intervals ?? [SleepInterval(start: start, end: wake)]
        func inSleep(_ ts: Date) -> Bool { intervals.contains { ts >= $0.start && ts < $0.end } }
        let savedOxygen = Dictionary((existing?.spo2 ?? []).filter { inSleep($0.ts) }
            .map { ($0.ts, $0.percent) }, uniquingKeysWith: { _, fresh in fresh })
        result.spo2 = savedOxygen.merging(oxygen.filter { inSleep($0.key) }, uniquingKeysWith: { _, fresh in fresh })
            .sorted { $0.key < $1.key }.map { OvernightOxygenPoint(ts: $0.key, percent: $0.value) }
        let savedRespiration = Dictionary((existing?.respiration ?? []).filter { inSleep($0.ts) }
            .map { ($0.ts, $0.breathsPerMinute) }, uniquingKeysWith: { _, fresh in fresh })
        result.respiration = savedRespiration.merging(respiration.filter { inSleep($0.key) },
            uniquingKeysWith: { _, fresh in fresh }).sorted { $0.key < $1.key }
            .map { SleepRespirationPoint(ts: $0.key, breathsPerMinute: $0.value) }
        let invalidations = (existing?.hrvInvalidatedMinutes ?? [:])
            .merging(Dictionary(uniqueKeysWithValues: invalidHrvMinutes.map { ($0, observedAt) }),
                     uniquingKeysWith: max).filter { inSleep($0.key) }
        result.hrvInvalidatedMinutes = invalidations.isEmpty ? nil : invalidations
        let freshHRV = hrv.filter { inSleep($0.key) }.map {
            SleepHRVPoint(ts: $0.key, rmssdMS: $0.value, observedAt: observedAt)
        }
        let combinedHRV = SleepHRVPoint.merging((existing?.hrv ?? []).filter { inSleep($0.ts) },
                                               with: freshHRV, invalidatedMinutes: invalidations)
        result.hrv = combinedHRV.isEmpty && !hrvReadComplete && existing?.hrv == nil
            && invalidations.isEmpty ? nil : combinedHRV
        return result
    }

    private static func apply(_ sleep: SleepSummary, for day: UserDay, to store: DataStore) {
        if store.today.day == day { store.today.sleep = sleep }
        if let index = store.history.firstIndex(where: { $0.day == day }) {
            store.history[index].sleep = sleep
        } else {
            var metrics = DailyMetrics(day: day)
            metrics.sleep = sleep
            store.history.append(metrics)
            store.history.sort { $0.day < $1.day }
        }
    }

    /// The recorded night on this user day: this sync's row, or the one already on the store.
    private static func nightWindow(day: UserDay, night: SleepNight?, store: DataStore) -> (Date, Date)? {
        let metrics = store.today.day == day ? store.today : store.history.first { $0.day == day }
        let storedSleep = Self.sleepOnCalendarDay(metrics?.sleep, day: day)
        if let start = night?.sleepStart, let wake = night?.wakeAt, wake > start {
            if let oldStart = storedSleep?.sleepStart, let oldWake = storedSleep?.wakeAt,
               oldStart <= start, oldWake >= wake { return (oldStart, oldWake) }
            return (start, wake)
        }
        if let start = storedSleep?.sleepStart, let wake = storedSleep?.wakeAt, wake > start {
            return (start, wake)
        }
        return nil
    }

    private static func uploadSleep(_ row: [String: Any], userId: String) async throws {
        let db = SupabaseClient.shared
        guard ConsentStore.shared.granted, await db.currentUserId == userId,
              row["user_id"] as? String == userId else { throw BandError.rejected("ACCOUNT CHANGED") }
        let accepted = try await db.upsert("sleep_nights", row: row, onConflict: "user_id,user_day", expectedOwner: userId)
        guard let saved = accepted.first, saved["user_id"] as? String == userId,
              saved["user_day"] as? String == row["user_day"] as? String,
              saved["total_minutes"] as? Int == row["total_minutes"] as? Int else {
            throw BandError.rejected("SLEEP UPLOAD NOT CONFIRMED")
        }
    }

    /// Keep each unacknowledged observation once, independently of SDK retention.
    /// A stable payload-derived identifier also covers a response lost after server commit.
    private func persistEvidence(samples: [[String: Any]], args: [String: Any], userId: String) throws -> [String] {
        let local = try LocalDataStore.shared()
        let iso = ISO8601DateFormatter()
        let operations = try samples.map { sample in
            var single = args
            single["p_samples"] = [sample]
            single["p_status"] = "partial"
            // Keep the measurement range and observation clock in the durable payload.
            // A retry reuses both; a later device read is a distinct revision.
            if let raw = sample["ts"] as? String, let ts = iso.date(from: raw) {
                single["p_start"] = raw
                single["p_end"] = iso.string(from: ts.addingTimeInterval(60))
            }
            let data = try JSONSerialization.data(withJSONObject: single, options: [.sortedKeys])
            let id = "band-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return LocalOperation(id: id, account: userId, kind: "band-domain", payload: data)
        }
        try local.enqueue(operations: operations)
        return operations.map(\.id)
    }

    private static var evidenceDrains: [String: Task<Void, Never>] = [:]

    static func flushPendingEvidence(userId: String) async {
        guard !Task.isCancelled, ConsentStore.shared.granted,
              SupabaseClient.currentUserIdSnapshot() == userId else { return }
        if let running = evidenceDrains[userId] { await running.value; return }
        let task = Task { @MainActor in await drainEvidence(userId: userId) }
        evidenceDrains[userId] = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
        evidenceDrains[userId] = nil
    }

    private static func mayDrainEvidence(_ userId: String) -> Bool {
        !Task.isCancelled && ConsentStore.shared.granted
            && SupabaseClient.currentUserIdSnapshot() == userId
    }

    private static func drainEvidence(userId: String) async {
        do {
            let local = try LocalDataStore.shared()
            // Snapshot once: a producer cannot keep this pass alive indefinitely.
            let sleeps = try local.operations(account: userId, kind: "band-sleep")
            let observations = try local.operations(account: userId, kind: "band-domain")
            Self.log.notice("evidence drain start: \(sleeps.count) sleep, \(observations.count) observations")
            for batch in EvidenceDrainPolicy.batches(sleeps, limit: 30) {
                var acknowledged = 0
                for operation in batch {
                    guard mayDrainEvidence(userId) else { return }
                    guard let row = try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any] else { continue }
                    try await uploadSleep(row, userId: userId)
                    guard mayDrainEvidence(userId) else { return }
                    try local.acknowledge(account: userId, id: operation.id)
                    acknowledged += 1
                }
                guard EvidenceDrainPolicy.shouldContinue(acknowledged: acknowledged) else { break }
            }
            for batch in EvidenceDrainPolicy.batches(observations, limit: 200) {
                guard mayDrainEvidence(userId) else { return }
                let acknowledged = try await drainDomainBatch(batch, userId: userId)
                Self.log.notice("evidence drain batch: \(acknowledged)/\(batch.count) acknowledged")
                guard EvidenceDrainPolicy.shouldContinue(acknowledged: acknowledged) else { break }
            }
        } catch {
            if case SupabaseClient.Failure.http(let status, _) = error {
                Self.log.error("evidence drain stopped: HTTP \(status)")
            } else { Self.log.error("evidence drain stopped: \(String(describing: type(of: error)), privacy: .public)") }
            BandLog.shared.record("retry band observations", error: error)
        }
    }

    private static func drainDomainBatch(_ pending: [LocalOperation], userId: String) async throws -> Int {
        let decoded = try pending.compactMap { operation -> (LocalOperation, [String: Any])? in
            guard let args = try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any],
                  let samples = args["p_samples"] as? [[String: Any]], !samples.isEmpty else { return nil }
            return (operation, args)
        }
        let groups = Dictionary(grouping: decoded) { item in
            ["p_device_key", "p_domain", "p_day", "p_timezone", "p_mapping_version", "p_observed_at"].map {
                item.1[$0] as? String ?? ""
            }.joined(separator: "|")
        }
        var acknowledged = 0
        for key in groups.keys.sorted() {
            guard mayDrainEvidence(userId), let group = groups[key], var args = group.first?.1 else { return acknowledged }
            let samples = group.flatMap { $0.1["p_samples"] as? [[String: Any]] ?? [] }
            args["p_samples"] = samples
            args["p_start"] = group.compactMap { $0.1["p_start"] as? String }.min()
            args["p_end"] = group.compactMap { $0.1["p_end"] as? String }.max()
            let response = try await SupabaseClient.shared.rpc("ingest_band_domain", args: args, expectedOwner: userId)
            let ack = try JSONDecoder().decode(BandIngestionAcknowledgment.self,
                from: JSONSerialization.data(withJSONObject: response))
            guard mayDrainEvidence(userId) else { return acknowledged }
            let ids = EvidenceDrainPolicy.confirmedIDs(group.map { $0.0.id }, offeredSamples: samples.count,
                                                      acknowledgment: ack)
            try LocalDataStore.shared().acknowledge(account: userId, ids: ids)
            if ids.isEmpty {
                Self.log.error("evidence drain unconfirmed: \(samples.count) offered, \(ack.inserted) inserted, \(ack.completed) completed, \(ack.unchanged) unchanged, \(ack.rejected) rejected")
            }
            acknowledged += ids.count
        }
        return acknowledged
    }

    /// A first sync on this phone pulls what the band still holds — `watchDataDayNumber`
    /// days, seven on a HOOP — so the week bars, the heat map and HR_REST stand on a history
    /// from the first evening rather than from the second week. Once per bound band, lowest
    /// priority; the server ignores what it already has, so a re-run costs a transfer and
    /// changes nothing.
    func backfillIfNeeded(into store: DataStore, force: Bool = false) async {
        guard let bound = BoundBand.identifier,
              let userId = await db.currentUserId else { return }
        // ⚠️ "v2": the first version of this mark was set whether or not a single day had
        // come off the band, and on the phone that found the readBasicData bug it was set
        // after seven failed reads. A new key is the only way that phone asks again.
        // ⚠️ "v4" (2026-09-03): raw_samples.hrv arrived after those days were stored, so every
        // tick the backfill had already written carries a null no later sync would ever fill —
        // fill_hrv only reaches the days a sync actually asks for. One more pass writes them.
        // ⚠️ "v5": origin disValue is km; those days stored 0 m. fill_dis repairs them.
        // v9 also replays cached history into the exact-minute sleep HRV archive.
        let key = "nb.band.backfilled.v9.\(userId).\(bound).\(Self.dayString(Date()))"
        guard force || !UserDefaults.standard.bool(forKey: key) else { return }
        // Each native transfer reserves the sensor; upload/settlement leave live data running.
        let everyDayAnswered = await { () async -> Bool in
            let identity = try? await BandReadiness.read(account: userId, binding: bound) {
                try await band.readIdentity()
            }
            // saveDays of 0 is the band not having said; asking for the SDK's usual seven costs
            // nothing, because a page the band does not hold answers empty.
            let held = (identity?.watchDataDayNumber).flatMap { $0 > 0 ? $0 : nil } ?? 7
            let today = UserDay.containing(Date())
            let cachedOffsets: [Int]
            do {
                cachedOffsets = try await BandReadiness.read(account: userId, binding: bound) {
                    try await band.cachedHistoryDayOffsets(limit: 6)
                }
            } catch {
                BandLog.shared.record("cachedHistoryDayOffsets", error: error)
                return false
            }
            let offsets = BandSyncPolicy.historyDayOffsets(retained: held, cachedOffsets: cachedOffsets)
            let days = offsets.max() ?? 0
            var everyDayAnswered = true
            if days > 0 {
                for back in offsets {
                    guard LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else { return false }
                    await sync(day: today.adding(days: -back), into: store, settle: false)
                    if lastOutcome != "success" { everyDayAnswered = false }
                }
                await Repository.shared.settleNow(days: days)
                await Repository.shared.load(days: days, endingAt: today, into: store)
                guard SupabaseClient.currentUserIdSnapshot() == userId else { return false }
                await Repository.shared.loadSleepScores(days: 30, endingAt: today, into: store)
            }
            return everyDayAnswered
        }()
        // Only a backfill in which every day answered is over. A day the band did not
        // answer is asked again on the next launch — the mark is not a record of trying.
        if everyDayAnswered { UserDefaults.standard.set(true, forKey: key) }
    }

    private static func mergeOptical(_ stored: [MealResponseIndex.Point],
                                     with fresh: [MealResponseIndex.Point]) -> [MealResponseIndex.Point] {
        var byTime: [Date: Double] = [:]
        for point in stored + fresh { byTime[point.ts] = point.optical }
        return byTime.keys.sorted().map { MealResponseIndex.Point(ts: $0, optical: byTime[$0]!) }
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

    /// Keep the raw curve live even while its upload and server settlement are still running.
    /// Backfill days are merged into history; the active day is also merged into `today`.
    private static func apply(_ fresh: [VitalSample], for day: UserDay, to store: DataStore) {
        guard !fresh.isEmpty else { return }

        if store.today.day == day {
            store.today.vitalsCurve = VitalSample.merging(store.today.vitalsCurve, with: fresh)
        }
        if let index = store.history.firstIndex(where: { $0.day == day }) {
            store.history[index].vitalsCurve = VitalSample.merging(
                store.history[index].vitalsCurve,
                with: fresh
            )
        } else {
            var metrics = DailyMetrics(day: day)
            metrics.vitalsCurve = fresh.sorted { $0.ts < $1.ts }
            store.history.append(metrics)
            store.history.sort { $0.day < $1.day }
        }
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
                _ = try await db.patch("sync_runs", id: id, row: completion, expectedOwner: userId)
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
/// This does not control any sensor. Each automatic measurement uses the interval reported
/// by the device, while some historical SDK domains still return five-minute points.
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
        minutes < 60 ? L("EVERY %d MIN", minutes) : L("EVERY HOUR")
    }
}
