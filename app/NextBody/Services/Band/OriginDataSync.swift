import Foundation
import os

/// The shared refresh reads the current user day and the previous day. User days start
/// at local midnight (ADR 0020); sleep still belongs to its recorded wake day.
@MainActor
final class OriginDataSync {
    private let band: BandService
    private let db = SupabaseClient.shared
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "sync")
    private struct DatedPoint {
        let calendarDay: Date
        let readStartedAt: Date
        let readAt: Date
        let point: OriginPoint
    }

    init(band: BandService = Band.live) { self.band = band }

    // MARK: asking again

    private static let refreshCoordinator = BandRefreshCoordinator(state: { refreshState() })

    private static func refreshState() -> BandRefreshCoordinator.State {
        .init(account: SupabaseClient.currentUserIdSnapshot(), binding: BoundBand.identifier,
              consent: ConsentStore.shared.granted, exclusive: BandLiveLifecycle.shared.hasExclusiveOperation,
              connected: Band.live.state == .connected)
    }

    /// Every caller enters the same account-scoped refresh. Readiness and history upgrades
    /// belong to that shared work; a screen never has to prepare the band or infer success.
    @discardableResult
    static func refreshNow(into store: DataStore, request: BandRefreshRequest = .automatic) async -> BandRefreshResult {
#if DEBUG
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_SYNC_STAGE"] != nil {
            return .init(status: .throttled)
        }
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_SLEEP_EVIDENCE"] == "1" {
            return .init(status: .throttled)
        }
#endif
        let result = await refreshCoordinator.refresh(request, cadence: SyncCadence.interval,
            work: refreshWork(into: store, request: request))
        // Alarm warm-up is not health sync. Do not keep the sync button busy after the
        // shared refresh has published its terminal result.
        Task { await PhoneToolRunner.shared.primeAlarms() }
        return result
    }

    private static func refreshWork(into store: DataStore, request: BandRefreshRequest) -> BandRefreshCoordinator.Work {
        let scope = refreshState().scope
        let sync = OriginDataSync()
        var today = UserDay.containing(Date())
        return .init(
            prepare: { reuseReceipt in
                guard let scope else { return false }
                BandSyncActivity.shared.phase = "connecting"
                BandSyncActivity.shared.beginCounting()
                if request != .phoneTool {
                    guard await BandReadiness.shared.ensureReady(into: store, reason: "sync",
                        reuseRecentLiveReceipt: reuseReceipt) else { return false }
                }
                guard refreshState().rejection(expected: scope) == nil,
                      Band.live.state == .connected else { return false }
                BandPresence.shared.start(store: store)
                store.band.connected = true
                BandSyncActivity.shared.show(.capabilities)
                await BandPresence.shared.refresh(store: store, prepared: BandReadiness.shared.snapshot)
                guard refreshState().rejection(expected: scope) == nil else { return false }
                do {
                    try await BandReadiness.read(account: scope.account, binding: scope.binding) {
                        await Band.live.prepareFreshSync()
                    }
                } catch { return false }
                today = UserDay.containing(Date())
                BandSyncActivity.shared.phase = "syncing"
                BandSyncActivity.shared.show(.reading)
                let held = BandReadiness.shared.snapshot?.identity?.watchDataDayNumber
                BandSyncActivity.shared.expect(total: max(2, held ?? 7))
                return true
            }, day: { daysAgo in
                guard let scope else { return .init(status: .cancelled) }
                let day = today.adding(days: -daysAgo)
                let points = await sync.sync(day: day, scope: scope, into: store, settle: daysAgo == 0)
                BandSyncActivity.shared.step()
                return .init(status: BandRefreshResult.Status(rawValue: sync.lastOutcome) ?? .failed, points: points)
            }, history: { recentDays in
                guard let scope else { return .init(result: .init(status: .cancelled)) }
                return await sync.backfillIfNeeded(scope: scope, today: today, recentDays: recentDays, into: store)
            }, checkHistory: { true }, finish: {
                BandSyncActivity.shared.show(.finishing)
                await Band.live.finishFreshSync()
            }, completed: { result in
                BandSyncActivity.shared.complete(success: result.status == .success)
            })
    }

    static func waitForCurrentPull() async { await refreshCoordinator.waitForCurrentPull() }
    static var isIdle: Bool { refreshCoordinator.isIdle }

    /// The app calls this only after releasing the consent takeover's exclusive gate.
    static func refreshAfterConsent(into store: DataStore) async -> BandRefreshResult? {
        await refreshCoordinator.refreshAfterConsent(cadence: SyncCadence.interval,
            work: refreshWork(into: store, request: .fullHistory))
    }

    /// Internal per-day outcome. Only the shared refresh combines days into a caller result.
    private var lastOutcome = "none"

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
    private func sync(day: UserDay, scope: BandRefreshCoordinator.Scope,
                      into store: DataStore, settle: Bool = true) async -> Int {
        lastOutcome = "failed"
        BandSyncActivity.shared.show(.reading)
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
        guard Self.refreshState().rejection(expected: scope) == nil else { return 0 }
        let userId = scope.account
        let deviceKey = scope.binding
        let outcomeKey = Self.historyOutcomeKey(scope: scope, day: day)
        // Archive/local failures are not all represented by publication domain receipts.
        // A crash or early exit must leave this date as repair work on the next refresh.
        UserDefaults.standard.set("failed", forKey: outcomeKey)
        defer {
            if Self.refreshState().rejection(expected: scope) == nil {
                UserDefaults.standard.set(lastOutcome, forKey: outcomeKey)
            }
        }
        await Self.flushPendingEvidence(userId: userId)
        guard Self.refreshState().rejection(expected: scope) == nil else { return 0 }
        var calendar = Calendar.current
        calendar.timeZone = .current
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day.start)!
        let readEnd = min(dayEnd, now)
        var originReadEnd = readEnd
        var originSnapshotCoversDay = true
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
        var domainStates: [BandDomainSyncState] = []
        var pagesReturned = 0
        let wanted = Self.pages(for: day, now: now, calendar: calendar)
        let run = await beginRun(userId: userId, requested: wanted.count)
        // The bar's movement inside this day. Each checkpoint is a band command that has
        // actually come back, not a tween — and all of them stand down when the SDK's own
        // dump is reporting, which is the only better source.
        var stagesDone = 0
        let stageCount = wanted.count * 2 + 2
        func stage() {
            stagesDone += 1
            BandSyncActivity.shared.within(percent: min(99, 100 * stagesDone / stageCount))
        }

        for offset in wanted {
            guard LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else { lastOutcome = "failed"; return 0 }
            let calendarDay = calendar.startOfDay(for:
                calendar.date(byAdding: .day, value: -offset, to: now) ?? now)
            let page: OriginDataPage
            do {
                page = try await BandReadiness.read(account: userId, binding: deviceKey) {
                    try await band.readOriginPage(calendarDay: calendarDay)
                }
                pagesReturned += 1
                stage()
                if let end = OriginObservationPolicy.coverageEnd(dayStart: day.start, dayEnd: dayEnd,
                    readStartedAt: now, snapshotStartedAt: page.readStartedAt) {
                    originReadEnd = min(originReadEnd, end)
                } else { originSnapshotCoversDay = false }
            } catch {
                #if DEBUG
                NightDiagnostics.shared.record("sync.origin_read_failed", fields: [
                    "day": day.key, "offset": String(offset), "errorType": String(describing: type(of: error))
                ])
                #endif
                BandLog.shared.record("readOriginData(\(offset))", error: error)
                page = OriginDataPage(points: [], readStartedAt: now, readCompletedAt: now)
            }
            // Preserve the actual native snapshot clock through cache reuse and retries.
            // A later SDK database query does not make an older measurement revision new.
            let originReadAt = page.readCompletedAt
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
            stage()
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
            points.append(contentsOf: page.points.map { point in
                DatedPoint(calendarDay: calendarDay, readStartedAt: page.readStartedAt,
                           readAt: originReadAt, point: OriginPoint(
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
            stage()
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
                dayEnd: dayEnd, readStartedAt: now, snapshotStartedAt: dated.readStartedAt) else { return nil }
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
        guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() == userId,
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

        BandSyncActivity.shared.show(.saving)
        let publication: BandEvidencePublication
        do { publication = try Self.evidencePublication(userId: userId) }
        catch {
            BandLog.shared.record("open band publication", error: error)
            lastOutcome = "failed"
            return 0
        }
        func evidenceDomain(_ name: String, _ samples: [[String: Any]], _ status: BandDomainReadStatus,
                            version: String, window: (Date, Date)? = nil) -> BandEvidencePublication.Domain {
            BandEvidencePublication.Domain(name: name, deviceKey: deviceKey, day: Self.dayString(day.start),
                timezone: tz, start: window?.0 ?? day.start, end: window?.1 ?? readEnd,
                observedAt: now, mappingVersion: version, status: status, samples: samples)
        }
        do {
            try publication.stage(evidenceDomain("origin", rows, .partial, version: "veepoo-rmssd-v1",
                window: (day.start, originReadEnd)))
            try publication.stage(evidenceDomain("rr", rrRows, .partial, version: "veepoo-rmssd-v2"))
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
            guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() == userId,
                  BoundBand.identifier == deviceKey else { lastOutcome = "failed"; return 0 }
            do {
                // 04B rule 04 · the sleepLine rides along as compact "stage:minutes" runs, so
                // the SLEEP strip draws the band's own staging instead of re-deriving it.
                var row: [String: Any] = [
                    "user_id": userId,
                    "user_day": Self.dayString(day.start),
                    // §04.5 D6 · the night names the band that measured it, so a night from
                    // the band on the charger is held rather than filed.
                    "device_key": deviceKey,
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
                try await publication.publishSleep(row)
                sleepStatus = .complete
            } catch is CancellationError {
                lastOutcome = "failed"
                return 0
            } catch {
                auxiliaryUploaded = false
                sleepStatus = .failed
                BandLog.shared.record("upsert sleep_nights", error: error)
            }
        }

        // Every domain is acknowledged independently. Read failures keep a repair range and
        // cannot inherit another domain's success. Full-day overlap is bounded by SDK pages.
        let originStatus: BandDomainReadStatus = pagesReturned == wanted.count && originSnapshotCoversDay
            ? .complete : .partial
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
        var publications = domains.map { name, samples, status in
            evidenceDomain(name, samples, status, version: name == "origin" ? "veepoo-rmssd-v1" : "veepoo-rmssd-v2",
                           window: name == "origin" ? (day.start, originReadEnd) : nil)
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
        publications.append(evidenceDomain("oxygen", oxygenSamples, oxygenRead, version: "veepoo-spo2-v1",
                                           window: (oxygenStart, oxygenEnd)))
        if store.today.day == day {
            store.mealResponseZerosToday = opticalDroppedZeros > 0 && opticalTicks.isEmpty
        }
        let incomingOptical = opticalTicks.keys.sorted().map {
            MealResponseIndex.Point(ts: $0, optical: opticalTicks[$0]!)
        }
        store.mealResponsePoints = Self.mergeOptical(store.mealResponsePoints, with: incomingOptical)
        let opticalSamples = opticalTicks.sorted { $0.key < $1.key }
            .map { ["ts": iso.string(from: $0.key), "optical": $0.value] }
        publications.append(evidenceDomain("response", opticalSamples, opticalStatus, version: "veepoo-optical-v1"))

        var changedCount = 0
        for domain in publications {
            do {
                let result = try await publication.publish(domain)
                changedCount += result.changedCount
                if !result.confirmed { auxiliaryUploaded = false }
                domainStates.append(result.state)
            } catch is CancellationError {
                lastOutcome = "failed"
                return changedCount
            } catch {
                auxiliaryUploaded = false
                BandLog.shared.record("ingest \(domain.name)", error: error)
                domainStates.append(BandDomainSyncState(domain: domain.name, status: .failed, attemptedAt: now,
                    acknowledgedStart: nil, acknowledgedEnd: nil, repairStart: domain.start, repairEnd: domain.end))
            }
        }
        guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() == userId,
              BoundBand.identifier == deviceKey else { lastOutcome = "failed"; return changedCount }
        do { try BandDomainSyncState.save(domainStates, userId: userId, deviceKey: deviceKey, day: Self.dayString(day.start)) }
        catch { BandLog.shared.record("save domain acknowledgments", error: error) }
        stage()
        let outcome = pagesReturned == wanted.count && auxiliaryUploaded ? "success" : "partial"
        await record(run, outcome: outcome, requested: wanted.count, returned: pagesReturned)
        if outcome == "success", Self.refreshState().rejection(expected: scope) == nil {
            store.lastSync = now
            if let newest { Self.setWatermark(newest, for: day, userId: userId) }
            await Repository.shared.markDeviceSynced(at: now)
        }
        if settle, Self.refreshState().rejection(expected: scope) == nil {
            BandSyncActivity.shared.show(.updating)
            await Repository.shared.settleNow(days: day == UserDay.containing(now) ? 1 : 2)
            guard Self.refreshState().rejection(expected: scope) == nil else { return changedCount }
            await Repository.shared.load(days: 1, endingAt: day, into: store)
            guard Self.refreshState().rejection(expected: scope) == nil else { return changedCount }
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
        // Issue #20 · the band's wake is the last word only until the phone contradicts it.
        // Cutting here, before the per-minute series are filtered, keeps oxygen, respiration
        // and HRV inside the night that is actually filed rather than the one the wrist
        // guessed. `start` cannot move; only the end of the night can.
        result = SleepWakeClamp.applying(AwakeEvidence.marks(), to: result)
        let ended = result.wakeAt ?? wake
        let intervals = result.intervals ?? [SleepInterval(start: start, end: ended)]
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

    private static let domainTransport = BandDeltaTransport { name, args, owner in
        let response = try await SupabaseClient.shared.rpc(name, args: args, expectedOwner: owner)
        return try JSONDecoder().decode(BandIngestionAcknowledgment.self,
            from: JSONSerialization.data(withJSONObject: response))
    }

    private static func evidencePublication(userId: String) throws -> BandEvidencePublication {
        BandEvidencePublication(account: userId, local: try LocalDataStore.shared(), authorized: {
            ConsentStore.shared.granted && SupabaseClient.currentUserIdSnapshot() == userId
        }, transport: .init(ingest: { args, owner in
            try await domainTransport.ingest(args, owner: owner)
        }, sleep: { row, owner in
            // publish_sleep_night files the wearer's night and holds the other band's
            // (returned with `held: true`), so the receipt is honest either way.
            let response = try await SupabaseClient.shared.rpc(
                "publish_sleep_night", args: ["p_row": row], expectedOwner: owner)
            return response as? [[String: Any]] ?? []
        }))
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

    private static func drainEvidence(userId: String) async {
        do {
            let publication = try evidencePublication(userId: userId)
            let acknowledged = try await publication.replay()
            Self.log.notice("evidence drain finished: \(acknowledged) acknowledged")
        } catch is CancellationError {
            return
        } catch {
            if case SupabaseClient.Failure.http(let status, _) = error {
                Self.log.error("evidence drain stopped: HTTP \(status)")
            } else { Self.log.error("evidence drain stopped: \(String(describing: type(of: error)), privacy: .public)") }
            BandLog.shared.record("retry band observations", error: error)
        }
    }

    private static func historyOutcomeKey(scope: BandRefreshCoordinator.Scope, day: UserDay) -> String {
        "nb.sync.day-outcome.v1.\(scope.account).\(scope.binding).\(dayString(day.start))"
    }

    /// Check retained and locally cached history once per successful user day. Every
    /// refresh repairs missing/failed dates; dates already completed earlier in this same
    /// refresh are reused. There is no "attempted the whole week" success flag.
    private func backfillIfNeeded(scope: BandRefreshCoordinator.Scope, today: UserDay,
                                  recentDays: [Int: BandRefreshResult],
                                  into store: DataStore) async -> BandRefreshCoordinator.HistoryResult {
        guard Self.refreshState().rejection(expected: scope) == nil else {
            return .init(result: .init(status: .cancelled))
        }
        let bound = scope.binding
        let userId = scope.account
        let identity = try? await BandReadiness.read(account: userId, binding: bound) {
            try await band.readIdentity()
        }
        let cachedOffsets: [Int]
        do {
            cachedOffsets = try await BandReadiness.read(account: userId, binding: bound) {
                try await band.cachedHistoryDayOffsets(limit: 6)
            }
        } catch {
            BandLog.shared.record("cachedHistoryDayOffsets", error: error)
            return .init(result: .init(status: .failed))
        }
        let now = Date()
        // SDK offsets are relative to its current calendar date. Translate them to the
        // refresh's captured day so a slow pull crossing midnight keeps its original dates.
        let calendar = Calendar.current
        let elapsedDays = calendar.dateComponents([.day], from: today.start,
                                                   to: calendar.startOfDay(for: now)).day ?? 0
        let candidates = BandSyncPolicy.historyDayOffsets(retained: identity?.watchDataDayNumber,
                                                           cachedOffsets: cachedOffsets)
        let offsets = BandSyncPolicy.historyOffsetsToSync(available: candidates, elapsedDays: elapsedDays,
                                                           recentDays: recentDays.mapValues(\.status)) { offset in
            let day = today.adding(days: -offset)
            return BandSyncPolicy.needsHistorySync(
                states: BandDomainSyncState.load(userId: userId, deviceKey: bound, day: Self.dayString(day.start)),
                outcome: UserDefaults.standard.string(forKey: Self.historyOutcomeKey(scope: scope, day: day))
                    .flatMap(BandRefreshResult.Status.init(rawValue:)),
                start: day.start, end: day.end, now: now)
        }
        // Two recent days are already counted; these are the retained days still to read.
        BandSyncActivity.shared.revise(total: 2 + offsets.count)
        guard let days = offsets.max() else { return .init(result: nil) }
        // The retained days this pull will walk are only known once the band has answered.
        BandSyncActivity.shared.expect(total: 2 + offsets.count)
        var results: [BandRefreshResult] = []
        var recoveredDays: Set<Int> = []
        func cancelled(_ status: BandRefreshResult.Status) -> BandRefreshCoordinator.HistoryResult {
            .init(result: .init(status: status, points: results.reduce(0) { $0 + $1.points }),
                  recoveredDays: recoveredDays)
        }
        for offset in offsets {
            if let rejected = Self.refreshState().rejection(expected: scope) { return cancelled(rejected) }
            BandSyncActivity.shared.show(.reading)
            let points = await sync(day: today.adding(days: -offset), scope: scope, into: store, settle: false)
            let status = BandRefreshResult.Status(rawValue: lastOutcome) ?? .failed
            BandSyncActivity.shared.step()
            results.append(.init(status: status, points: points))
            if status == .success, recentDays[offset] != nil { recoveredDays.insert(offset) }
        }
        if let rejected = Self.refreshState().rejection(expected: scope) { return cancelled(rejected) }
        BandSyncActivity.shared.updatingResults()
        await Repository.shared.settleNow(days: days + max(0, elapsedDays))
        if let rejected = Self.refreshState().rejection(expected: scope) { return cancelled(rejected) }
        await Repository.shared.load(days: days, endingAt: today, into: store)
        if let rejected = Self.refreshState().rejection(expected: scope) { return cancelled(rejected) }
        await Repository.shared.loadSleepScores(days: 30, endingAt: today, into: store)
        BandSyncActivity.shared.resultsLoaded()
        return .init(result: .combining(results, at: Date()), recoveredDays: recoveredDays)
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

    private struct SyncRun {
        let id: String?
        let startedAt: Date
        let account: String
        let deviceId: String?
    }

    private func beginRun(userId: String, requested: Int) async -> SyncRun {
        let startedAt = Date()
        let deviceId = Repository.shared.deviceId
        var row: [String: Any] = [
            "user_id": userId,
            "started_at": ISO8601DateFormatter().string(from: startedAt),
            "days_requested": requested,
        ]
        if let deviceId { row["device_id"] = deviceId }
        do {
            let id = try await db.insert("sync_runs", rows: [row], expectedOwner: userId).first?["id"] as? String
            return SyncRun(id: id, startedAt: startedAt, account: userId, deviceId: deviceId)
        } catch {
            BandLog.shared.record("begin sync_runs", error: error)
            return SyncRun(id: nil, startedAt: startedAt, account: userId, deviceId: deviceId)
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
        let userId = run.account
        guard SupabaseClient.currentUserIdSnapshot() == userId else { return }
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
                if let deviceId = run.deviceId { completion["device_id"] = deviceId }
                _ = try await db.insert("sync_runs", rows: [completion], expectedOwner: userId)
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

    static func label(_ minutes: Int) -> String {
        minutes < 60 ? L("EVERY %d MIN", minutes) : L("EVERY HOUR")
    }
}
