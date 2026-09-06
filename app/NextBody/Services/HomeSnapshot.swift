import Foundation

/// Last successful Home payload on this phone. Painted before the first network round
/// trip so a returning launch is not three seconds of dashes; replaced by `loadHomeFast`
/// with the server's current row.
enum HomeSnapshot {
    private static let version = 1
    @MainActor private static var hydratedAccount: String?

    /// DailyMetrics deliberately has a narrow wire encoding. Local detail must retain
    /// these additional fields explicitly, including the inputs behind WHY and THE CALL.
    struct Detail: Codable {
        var dayKey: String
        var optimalZone: ClosedRange<Double>?
        var segments: [TrainingSegment]
        var loadCurve: [LoadPoint]
        var peakHR: Int?
        var reserveDrivers: ReserveDrivers?
        var reserveCurve: [ReserveSample]
        var vitalsCurve: [VitalSample]
        var nightInputs: NightInputs?
        var sleep: SleepSummary?
        var bmrFull: Double?
        var proteinIn: Int?
        var carbIn: Int?
        var fatIn: Int?
        var serverCall: TheCall?

        init(_ m: DailyMetrics) {
            dayKey = m.day.key; optimalZone = m.optimalZone; segments = m.segments
            loadCurve = m.loadCurve; peakHR = m.peakHR; reserveDrivers = m.reserveDrivers
            reserveCurve = m.reserveCurve; vitalsCurve = m.vitalsCurve; nightInputs = m.nightInputs
            sleep = m.sleep; bmrFull = m.bmrFull; proteinIn = m.proteinIn
            carbIn = m.carbIn; fatIn = m.fatIn; serverCall = m.serverCall
        }
        func restore(_ source: DailyMetrics) -> DailyMetrics {
            var m = source
            m.optimalZone = optimalZone; m.segments = segments; m.loadCurve = loadCurve
            m.peakHR = peakHR; m.reserveDrivers = reserveDrivers; m.reserveCurve = reserveCurve
            m.vitalsCurve = vitalsCurve; m.nightInputs = nightInputs
            m.sleep = HomeSnapshot.sleepForDay(sleep, day: m.day)
            m.bmrFull = bmrFull; m.proteinIn = proteinIn; m.carbIn = carbIn
            m.fatIn = fatIn; m.serverCall = serverCall
            return m
        }
    }

    struct Payload: Codable {
        var version: Int
        var userId: String
        var savedAt: Date
        var dayKey: String
        var today: DailyMetrics
        var todayVitals: [VitalSample]
        var todaySleep: SleepSummary?
        var todaySegments: [TrainingSegment]
        var todayReserve: [ReserveSample]
        var yesterday: DailyMetrics?
        var yesterdayVitals: [VitalSample]
        var meals: [MealEntry]
        var recentMeals: [MealEntry]
        var live: LiveVitals
        var profile: Profile
        var lastSync: Date?
        var boundAt: Date? = nil
        var batteryPercent: Int?
        var firmware: String
        var netFatMass12w: Double?
        var netLeanMass12w: Double?
        var bodyFatPercent: Double?
        var history: [DailyMetrics]
        var details: [Detail]? = nil
    }

    @MainActor
    static func hydrate(into store: DataStore, now: Date = Date()) {
        guard !Band.allowsSeed else { return }
        guard let userId = SessionKeychain.userId
                ?? HomeLaunchPolicy.jwtSubject(SessionKeychain.accessToken ?? "")
        else { return }
        hydratedAccount = userId
        if let payload = load(userId: userId) { apply(payload, to: store, now: now) }
        restoreBandObservations(into: store, userId: userId, now: now)
        MealQueue.shared.overlayPending(into: store, ownerUserId: userId)
    }

    /// Device measurements have no cache expiry; server-derived metrics remain in the snapshot.
    struct BandDay: Codable {
        var day: UserDay
        var samples: [VitalSample]
        var sleep: SleepSummary?
    }

    #if DEBUG
    /// Counts and windows only: never include account/device identifiers or measured values.
    static func diagnosticFields(day: UserDay, samples: [VitalSample], sleep: SleepSummary?) -> [String: String] {
        guard NightDiagnostics.shared.isEnabled else { return [:] }
        let iso = ISO8601DateFormatter()
        return [
            "day": day.key, "sampleCount": String(samples.count),
            "hrvSampleCount": String(samples.filter { $0.hrv.map { $0.isFinite && $0 > 0 } ?? false }.count),
            "temperatureSampleCount": String(samples.filter { $0.temp != nil }.count),
            "sleepPresent": String(sleep != nil),
            "sleepStart": sleep?.sleepStart.map { iso.string(from: $0) } ?? "unknown",
            "wakeAt": sleep?.wakeAt.map { iso.string(from: $0) } ?? "unknown",
            "sleepMinutes": sleep.map { String($0.totalMinutes) } ?? "unknown",
            "nightHRVKnown": String(sleep?.hrv != nil),
            "nightHRVCount": sleep?.hrv.map { String($0.count) } ?? "unknown",
            "sleepRespirationCount": sleep?.respiration.map { String($0.count) } ?? "unknown",
            "sleepOxygenCount": sleep.map { String($0.spo2.count) } ?? "unknown"
        ]
    }

    /// Independent same-account readback; a diagnostic failure never changes production save semantics.
    private static func recordReadback(expected: Data, event: String, fields: [String: String],
                                       read: () throws -> Data?) {
        guard NightDiagnostics.shared.isEnabled else { return }
        do {
            let actual = try read()
            NightDiagnostics.shared.record(event, fields: fields.merging([
                "status": actual == nil ? "missing" : (actual == expected ? "matched" : "mismatched")
            ], uniquingKeysWith: { _, fresh in fresh }))
        } catch {
            NightDiagnostics.shared.record(event, fields: fields.merging([
                "status": "failed", "errorType": String(describing: type(of: error))
            ], uniquingKeysWith: { _, fresh in fresh }))
        }
    }
    #endif

    @MainActor
    static func saveBandObservations(day: UserDay, samples: [VitalSample], sleep: SleepSummary?, userId: String) throws {
        let database = try LocalDataStore.shared()
        let key = "band-day:" + day.key
        let data = try database.readObservationDocument(account: userId, key: key)
        let existing = try data.map { try JSONDecoder().decode(BandDay.self, from: $0) }
        let archived = BandDay(day: day,
            samples: VitalSample.merging(existing?.samples ?? [], with: samples),
            sleep: mergedSleep(sleepForDay(existing?.sleep, day: day), with: sleepForDay(sleep, day: day)))
        let encoded = try JSONEncoder().encode(archived)
        try database.writeObservationDocument(account: userId, key: key, data: encoded)
        #if DEBUG
        if NightDiagnostics.shared.isEnabled {
            let fields = diagnosticFields(day: day, samples: archived.samples, sleep: archived.sleep)
            NightDiagnostics.shared.record("storage.observations_saved", fields: fields)
            recordReadback(expected: encoded, event: "storage.observations_readback", fields: fields) {
                try database.readObservationDocument(account: userId, key: key)
            }
        }
        #endif
    }

    /// Sleep is filed under its local wake calendar date, independent of the 04:00 user-day boundary.
    private static func sleepForDay(_ sleep: SleepSummary?, day: UserDay) -> SleepSummary? {
        guard let sleep else { return nil }
        if let wake = sleep.wakeAt, !Calendar.current.isDate(wake, inSameDayAs: day.date) { return nil }
        return filteredSleep(sleep)
    }

    private static func filteredSleep(_ sleep: SleepSummary) -> SleepSummary {
        var result = sleep
        result.hrv = sleep.hrv.map { points in
            Dictionary(points.map { ($0.ts, $0) }, uniquingKeysWith: { _, fresh in fresh })
                .values.filter { sleep.containsSleepTimestamp($0.ts) }.sorted { $0.ts < $1.ts }
        }
        return result
    }

    private static func mergedSleep(_ stored: SleepSummary?, with fresh: SleepSummary?) -> SleepSummary? {
        guard let fresh else { return stored }
        guard let stored else { return fresh }
        let sameWindow = stored.sleepStart == fresh.sleepStart && stored.wakeAt == fresh.wakeAt
        let containedPartial: Bool
        if let oldStart = stored.sleepStart, let oldEnd = stored.wakeAt,
           let newStart = fresh.sleepStart, let newEnd = fresh.wakeAt {
            containedPartial = newStart >= oldStart && newEnd <= oldEnd && !sameWindow
        } else { containedPartial = false }
        guard sameWindow || containedPartial else { return fresh }
        var result = containedPartial ? stored : fresh
        result.intervals = result.intervals ?? stored.intervals
        if result.line.isEmpty { result.line = stored.line }
        result.spo2 = (stored.spo2 + fresh.spo2).reduce(into: [Date: OvernightOxygenPoint]()) {
            $0[$1.ts] = $1
        }.values.sorted { $0.ts < $1.ts }
        if stored.respiration != nil || fresh.respiration != nil {
            result.respiration = ((stored.respiration ?? []) + (fresh.respiration ?? []))
                .reduce(into: [Date: SleepRespirationPoint]()) { $0[$1.ts] = $1 }
                .values.sorted { $0.ts < $1.ts }
        }
        if stored.hrv != nil || fresh.hrv != nil {
            result.hrv = ((stored.hrv ?? []) + (fresh.hrv ?? []))
                .reduce(into: [Date: SleepHRVPoint]()) { $0[$1.ts] = $1 }
                .values.sorted { $0.ts < $1.ts }
        }
        return filteredSleep(result)
    }

    @MainActor
    private static func restoreBandObservations(into store: DataStore, userId: String, now: Date) {
        do {
            let documents = try LocalDataStore.shared().observationDocuments(account: userId)
            let current = UserDay.containing(now)
            var history = store.history
            for document in documents {
                let archived: BandDay
                do { archived = try JSONDecoder().decode(BandDay.self, from: document) }
                catch {
                    NSLog("Band observation archive decode failed: %@", String(describing: error))
                    continue
                }
                func restore(_ metrics: DailyMetrics) -> DailyMetrics {
                    var result = metrics
                    result.vitalsCurve = VitalSample.merging(metrics.vitalsCurve, with: archived.samples)
                    result.sleep = mergedSleep(sleepForDay(metrics.sleep, day: archived.day),
                                               with: sleepForDay(archived.sleep, day: archived.day))
                    return result
                }
                if archived.day == current {
                    store.today = restore(store.today)
                } else if let index = history.firstIndex(where: { $0.day == archived.day }) {
                    history[index] = restore(history[index])
                } else {
                    history.append(restore(DailyMetrics(day: archived.day)))
                }
                #if DEBUG
                NightDiagnostics.shared.record("storage.observations_restored", fields:
                    diagnosticFields(day: archived.day, samples: archived.samples, sleep: archived.sleep))
                #endif
            }
            store.history = history.sorted { $0.day < $1.day }
        } catch { NSLog("Band observation archive read failed: %@", String(describing: error)) }
    }

    @MainActor
    @discardableResult
    static func save(from store: DataStore, now: Date = Date()) -> Bool {
        guard !Band.allowsSeed else { return true }
        guard let userId = SupabaseClient.currentUserIdSnapshot() ?? SessionKeychain.userId
        else { return false }
        hydratedAccount = userId
        let today = store.today
        let yesterdayDay = today.day.adding(days: -1)
        let yesterday = store.history.first { $0.day == yesterdayDay }
        let payload = Payload(
            version: version,
            userId: userId,
            savedAt: now,
            dayKey: today.day.key,
            today: today,
            todayVitals: today.vitalsCurve,
            todaySleep: today.sleep,
            todaySegments: today.segments,
            todayReserve: today.reserveCurve,
            yesterday: yesterday,
            yesterdayVitals: yesterday?.vitalsCurve ?? [],
            meals: store.meals,
            recentMeals: store.recentMeals,
            live: store.vitals,
            profile: store.profile,
            lastSync: store.lastSync,
            boundAt: store.boundAt,
            batteryPercent: store.band.batteryPercent,
            firmware: store.band.firmware,
            netFatMass12w: store.netFatMass12w,
            netLeanMass12w: store.netLeanMass12w,
            bodyFatPercent: store.bodyFatPercent,
            history: Array(store.history.suffix(183)),
            details: (Array(store.history.suffix(14)) + [today]).map(Detail.init)
        )
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        do {
            let cache = try LocalDataStore.shared()
            try cache.writeDocument(account: userId, key: "home", data: data,
                expiresAt: now.addingTimeInterval(30 * 86_400))
            try cache.pruneCache(maxBytes: 16 * 1024 * 1024, now: now)
            #if DEBUG
            if NightDiagnostics.shared.isEnabled {
                let fields = diagnosticFields(day: today.day, samples: today.vitalsCurve, sleep: today.sleep)
                NightDiagnostics.shared.record("storage.home_saved", fields: fields)
                recordReadback(expected: data, event: "storage.home_readback", fields: fields) {
                    try cache.readDocument(account: userId, key: "home")
                }
            }
            #endif
            return true
        } catch {
            #if DEBUG
            NightDiagnostics.shared.record("storage.home_save_failed", fields: ["errorType": String(describing: type(of: error))])
            #endif
            NSLog("Home cache save failed: %@", String(describing: error))
            return false
        }
    }

    struct CachedDay: Codable {
        var metrics: DailyMetrics
        var detail: Detail
    }

    static func saveDetail(_ metrics: DailyMetrics, userId: String, now: Date = Date()) {
        do {
            let data = try JSONEncoder().encode(CachedDay(metrics: metrics, detail: Detail(metrics)))
            let cache = try LocalDataStore.shared()
            try cache.writeDocument(account: userId, key: "day:" + metrics.day.key, data: data,
                expiresAt: now.addingTimeInterval(14 * 86_400))
            try cache.pruneCache(maxBytes: 16 * 1024 * 1024, now: now)
        } catch { NSLog("Detail cache save failed: %@", String(describing: error)) }
    }

    static func loadDetail(day: UserDay, userId: String) -> DailyMetrics? {
        do {
            guard let data = try LocalDataStore.shared().readDocument(account: userId, key: "day:" + day.key) else { return nil }
            let cached = try JSONDecoder().decode(CachedDay.self, from: data)
            guard cached.metrics.day == day, cached.detail.dayKey == day.key else { return nil }
            return cached.detail.restore(cached.metrics)
        } catch { NSLog("Detail cache read failed: %@", String(describing: error)); return nil }
    }

    static func remove(userId: String) {
        try? LocalDataStore.shared().removeDocuments(account: userId)
        try? FileManager.default.removeItem(at: url(userId: userId))
    }

    @MainActor
    static func removeAll() {
        if let account = hydratedAccount ?? SessionKeychain.userId ?? SupabaseClient.currentUserIdSnapshot() {
            try? LocalDataStore.shared().removeDocuments(account: account)
        }
        hydratedAccount = nil
        let dir = directory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    @MainActor
    static func apply(_ payload: Payload, to store: DataStore, now: Date) {
        let current = UserDay.containing(now)
        store.profile = payload.profile.restoringHealthSync()
        if payload.batteryPercent != nil { store.band.batteryPercent = payload.batteryPercent }
        if !payload.firmware.isEmpty { store.band.firmware = payload.firmware }
        store.netFatMass12w = payload.netFatMass12w
        store.netLeanMass12w = payload.netLeanMass12w
        store.bodyFatPercent = payload.bodyFatPercent
        store.recentMeals = payload.recentMeals
        if let boundAt = payload.boundAt { store.boundAt = boundAt }

        func restored(_ m: DailyMetrics) -> DailyMetrics {
            var result = payload.details?.last(where: { $0.dayKey == m.day.key })?.restore(m) ?? m
            result.sleep = sleepForDay(result.sleep, day: result.day)
            return result
        }
        var history = payload.history.map(restored)
        if HomeLaunchPolicy.shouldPaintToday(
            snapshotDayKey: payload.dayKey, currentDayKey: current.key) {
            var today = restored(payload.today)
            today.vitalsCurve = payload.todayVitals
            today.sleep = sleepForDay(payload.todaySleep, day: today.day)
            today.segments = payload.todaySegments
            today.reserveCurve = payload.todayReserve
            store.today = today
            store.meals = payload.meals
            store.recentMeals = payload.recentMeals
            store.vitals = payload.live
            store.lastSync = payload.lastSync
            store.rebaseBodyBatteryPreview(at: payload.savedAt)
            if let yesterday = payload.yesterday {
                var row = restored(yesterday)
                row.vitalsCurve = payload.yesterdayVitals
                if let index = history.firstIndex(where: { $0.day == row.day }) {
                    history[index] = row
                } else {
                    history.append(row)
                }
            }
        }
        history.sort { $0.day < $1.day }
        store.history = history
    }

    private static func load(userId: String) -> Payload? {
        do {
            let cache = try LocalDataStore.shared()
            let cached = try cache.readDocument(account: userId, key: "home")
            let legacy = cached == nil ? try? Data(contentsOf: url(userId: userId)) : nil
            guard let data = cached ?? legacy,
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  payload.version == version, payload.userId == userId,
                  Date().timeIntervalSince(payload.savedAt) <= 30 * 86_400 else { return nil }
            if cached == nil {
                try cache.writeDocument(account: userId, key: "home", data: data,
                    expiresAt: payload.savedAt.addingTimeInterval(30 * 86_400))
                // Only remove the old snapshot after the migrated document is readable.
                if try cache.readDocument(account: userId, key: "home") == data {
                    try? FileManager.default.removeItem(at: url(userId: userId))
                }
            }
            return payload
        } catch {
            NSLog("Home cache read failed: %@", String(describing: error))
            return nil
        }
    }

    private static func directory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextBody", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(userId: String) -> URL {
        directory().appendingPathComponent("home-\(userId).json")
    }
}
