import Foundation

/// A complete health read is published once, after all of its tables agree on a revision.
/// Derived nulls remain null; device observations are merged at publication time so a
/// network response cannot erase a tick collected while it was in flight.
@MainActor
final class HealthSnapshotRead {
    typealias Row = [String: Any]

    // JSON stays on MainActor, including the concurrently awaited transport replies.
    @MainActor struct Rows { let values: [Row]; init(_ values: [Row]) { self.values = values } }
    @MainActor struct Object { let value: Row; init(_ value: Row) { self.value = value } }

    struct Transport {
        var select: @MainActor (String, [URLQueryItem]) async throws -> Rows
        var status: @MainActor (String, String) async throws -> Rows
        var metrics: @MainActor (String, String) async throws -> Object
        var missingCapability: @MainActor (Error, String) -> Bool
    }

    enum Failure: Error, Equatable { case revisionChanged, unavailable }

    struct Energy {
        let intake: Double?
        let burn: Double?
        let protein: Double?
        let resting: Double?
        let active: Double?
        var balance: Double? { intake.flatMap { eaten in burn.map { eaten - $0 } } }
    }

    @MainActor struct Snapshot {
        let rows: [Row]
        let fuel: [Row]
        var reserve: [Row] = []
        var training: [Row] = []
        var weighIns: [Row] = []
        var meals: [Row] = []
        var reserveSamples: [Row] = []
        var nights: [Row]? = nil
        var oxygen: [Row]? = nil
        var response: [Row]? = nil
        var live: [Row] = []
        var liveStress: [Row]? = nil
        var liveHeart: [Row]? = nil
        fileprivate var formalMetrics: [Row]? = nil
        fileprivate var remoteVitals: [VitalSample] = []
        fileprivate var accepts: @MainActor () -> Bool = { false }
        fileprivate var didPublish: @MainActor () -> Void = {}

        /// Formal availability is distinct from a missing value. An authoritative null
        /// never falls back to an older daily_results or child-table value.
        var hasFormalMetrics: Bool { formalMetrics != nil }
        func value(_ metric: String, day: String, legacy: Any? = nil) -> Double? {
            guard let formalMetrics else { return HealthSnapshotRead.number(legacy) }
            let points = formalMetrics.first { $0["metric"] as? String == metric }?["points"] as? [Row]
            return HealthSnapshotRead.number(points?.first { $0["dayKey"] as? String == day }?["value"])
        }

        func energy(day: String, legacy row: Row) -> Energy {
            let intake = value("intakeKcal", day: day, legacy: row["kcal_in"])
            var burn = value("burnKcal", day: day, legacy: row["kcal_out"])
            var resting = HealthSnapshotRead.number(row["bmr_kcal"])
            var active = HealthSnapshotRead.number(row["active_kcal"])
            if hasFormalMetrics {
                // Stale components cannot reconstruct an explicitly unavailable OUT.
                if burn == nil || resting.flatMap({ rest in active.map { rest + $0 } }) != burn {
                    resting = nil; active = nil
                }
            } else {
                burn = ActiveEnergyMath.totals(bmr: resting, eActive: active, eTrain: nil, eOutNow: burn).out
            }
            return Energy(intake: intake, burn: burn,
                protein: value("proteinG", day: day, legacy: row["protein_in_g"]),
                resting: resting, active: active)
        }

        func vitals(for day: UserDay, local: [VitalSample]) -> [VitalSample] {
            let remote = remoteVitals.filter { $0.ts >= day.start && $0.ts < day.end }
            return VitalSample.merging(remote, with: local.filter { $0.ts >= day.start && $0.ts < day.end })
        }

        /// No await occurs between this final eligibility check and updating the store,
        /// pending-write overlay and durable snapshot. A late read cannot partially paint.
        @discardableResult
        func publish(_ apply: @MainActor (Snapshot) -> Void) -> Bool {
            guard accepts(), !Task.isCancelled else { return false }
            apply(self)
            didPublish()
            return true
        }
    }

    private let transport: Transport
    private let accepts: @MainActor () -> Bool
    private let now: Date

    init(transport: Transport, now: Date = Date(), accepts: @escaping @MainActor () -> Bool) {
        self.transport = transport; self.now = now; self.accepts = accepts
    }

    private static let dailyColumns = "id,user_day,training_load,reserve_score,fuel_balance_kcal,daily_direction,the_call,the_call_confidence,fat_delta_7d,lean_delta_7d,scans_7d,computed_at,algo_version,result_revision,worn,wear_run,wear_miss"

    func detail(days: Int, endingAt day: UserDay) async throws -> Snapshot? {
        try checkCurrent()
        let from = day.adding(days: -days).key, to = day.key
        let dailyRead = try await selectDailyResultsCompat(query: [
            .init(name: "select", value: Self.dailyColumns),
            .init(name: "user_day", value: "gte.\(from)"),
            .init(name: "user_day", value: "lte.\(to)"),
            .init(name: "order", value: "user_day.asc"),
        ])
        let rows = dailyRead.rows
        // Raw samples are available before settle_now has produced daily_results. They
        // must still load: otherwise a successful 12:45 band upload leaves an 08:00 curve
        // on screen merely because the derived row is late. These independent requests
        // run together so that correctness does not add serial round trips.
        // Child tables are keyed to the rows just returned — an unfiltered select used
        // to download every day's fuel/training curve before Home could paint.
        async let formalRead = metricReadIfAvailable(from: from, to: to)
        let resultIds = rows.compactMap { $0["id"] as? String }
        let stamp = ISO8601DateFormatter()
        let dayStart = stamp.string(from: day.start)
        let dayEnd = stamp.string(from: day.adding(days: 1).start)
        let vitalsStart = stamp.string(from: day.adding(days: -max(days, 1) - 1).start)
        let responseStart = stamp.string(from: day.adding(days: -30).start)
        let observedUntil = stamp.string(from: now)

        async let fuelRows = selectByResultId(
            "day_fuel",
            columns: "result_id,intake_state,kcal_in,kcal_out,protein_in_g,slot_states,bmr_kcal,active_kcal,bmr_full_kcal,target_in,protein_g,fat_g,carb_g,carb_in_g,fat_in_g,weight_kg,energy_distribution",
            ids: resultIds)
        async let reserveRows = selectByResultId(
            "reserve_daily",
            columns: "result_id,wake_value,current_value,min_value,drain_drivers,night_inputs",
            ids: resultIds)
        async let trainingRows = selectByResultId(
            "daily_training",
            columns: "result_id,zone_minutes,peak_hr,curve,segments",
            ids: resultIds)
        // 补屏 B · active_minutes / distance_m arrive with migration 20260902040000. Asked
        // for separately so a project without them still loads the day — naming an
        // unknown column is a 400 for the whole select, and that 400 took the home
        // screen offline.
        async let trainingExtras = selectTrainingExtras(ids: resultIds)
        async let trainingEvidenceRows = try? selectByResultId(
            "daily_training", columns: "result_id,recorded_steps,evidence", ids: resultIds)
        async let weighInRows = select("weigh_ins", query: [
            .init(name: "select", value: "id,measured_at,weight_kg,source"),
            .init(name: "order", value: "measured_at.desc"),
            .init(name: "limit", value: "60"),
        ])
        // 12 · WEEK needs the week's meals, not just today's. Today's used to be a ninth
        // request for a strict subset of these same rows; it is now filtered out of them.
        async let weekMealRows = select("meals", query: [
            .init(name: "select", value: "id,user_day,slot,logged_at,text_input,kcal,protein_g,carb_g,fat_g"),
            .init(name: "deleted_at", value: "is.null"),
            // Dev seeds carry model_version = seed; they must not populate 09 or the dock.
            .init(name: "model_version", value: "neq.seed"),
            .init(name: "user_day", value: "gte.\(day.adding(days: -max(days, 6)).key)"),
            .init(name: "user_day", value: "lte.\(day.key)"),
            .init(name: "order", value: "logged_at.asc"),
        ])
        // 13 · the curve is 288 five-minute ticks of the shown day, not a shape we draw
        // from the day's endpoints. Bounded by the user day like everything else.
        async let sampleRowsAsync = select("reserve_samples", query: [
            .init(name: "select", value: "ts,value"),
            .init(name: "ts", value: "gte.\(dayStart)"),
            .init(name: "ts", value: "lt.\(dayEnd)"),
            .init(name: "order", value: "ts.asc"),
        ])
        // 13 · heart and stress are not a footnote to the battery — two of the four
        // attribution rows are made of them, so the detail page gets the day's own ticks
        // in the same user-day window as the reserve curve.
        // 04B · the second page draws the same ticks: skin temperature and the five
        // minutes' steps, kcal and metres ride along on the columns the sync already writes.
        // Rolling traces need the preceding user day too; every sample is partitioned
        // back into its own user-day window after the response arrives.
        async let vitalRowsAsync = selectSamplePages("raw_samples", query: [
            .init(name: "select", value: "ts,heart,stress,temp,step,met,cal,dis,hrv,domain_sources"),
            .init(name: "ts", value: "gte.\(vitalsStart)"),
            .init(name: "ts", value: "lt.\(dayEnd)"),
            .init(name: "order", value: "ts.asc"),
        ])
        // 04 · the HR / STRESS row is the last tick, not an average and not a guess.
        async let liveRowsAsync = select("raw_samples", query: [
            .init(name: "select", value: "ts,heart,stress"),
            // A tick in the future is a tick the band cannot have reported.
            .init(name: "ts", value: "lte.\(observedUntil)"),
            .init(name: "order", value: "ts.desc"),
            .init(name: "limit", value: "1"),
        ])
        // The newest row is often a sleep PPG tick with heart and no stress. The
        // STRESS card's "now" is the last positive reading, not that newest null.
        async let liveStressRowsAsync = select("raw_samples", query: [
            .init(name: "select", value: "ts,stress"),
            .init(name: "stress", value: "gt.0"),
            .init(name: "ts", value: "lte.\(observedUntil)"),
            .init(name: "order", value: "ts.desc"),
            .init(name: "limit", value: "1"),
        ])
        // The inverse: a step / MET tick with no PPG. HEART's "now" is the last
        // positive heart, not the newest null — same 24h join as stress.
        async let liveHeartRowsAsync = select("raw_samples", query: [
            .init(name: "select", value: "ts,heart"),
            .init(name: "heart", value: "gt.0"),
            .init(name: "ts", value: "lte.\(observedUntil)"),
            .init(name: "order", value: "ts.desc"),
            .init(name: "limit", value: "1"),
        ])
        // 04B · SLEEP card. Prefetched with the rest so Home does not wait a serial hop.
        async let nightRowsAsync = select("sleep_nights", query: [
            .init(name: "select", value: "user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_line,sleep_start,wake_at,raw"),
            .init(name: "user_day", value: "gte.\(from)"),
            .init(name: "user_day", value: "lte.\(to)"),
        ])
        async let oxygenRowsAsync = select("oxygen_samples", query: [
            .init(name: "select", value: "ts,spo2"),
            .init(name: "ts", value: "gte.\(vitalsStart)"),
            .init(name: "ts", value: "lt.\(dayEnd)"),
            .init(name: "order", value: "ts.asc"),
        ])
        async let responseRowsAsync = select("response_samples", query: [
            .init(name: "select", value: "ts,optical"),
            .init(name: "ts", value: "gte.\(responseStart)"),
            .init(name: "ts", value: "lt.\(dayEnd)"),
            .init(name: "order", value: "ts.asc"),
        ])

        let fuel = try await fuelRows.values
        let reserve = try await reserveRows.values
        var training = try await trainingRows.values
        if let extras = await trainingExtras?.values {
            let by = Dictionary(uniqueKeysWithValues: extras.compactMap { r in (r["result_id"] as? String).map { ($0, r) } })
            training = training.map { row in
                guard let id = row["result_id"] as? String, let e = by[id] else { return row }
                var r = row; r["active_minutes"] = e["active_minutes"]; r["distance_m"] = e["distance_m"]; return r
            }
        }
        if let evidenceRows = await trainingEvidenceRows?.values {
            let by = Dictionary(uniqueKeysWithValues: evidenceRows.compactMap { row in
                (row["result_id"] as? String).map { ($0, row) }
            })
            training = training.map { row in
                guard let id = row["result_id"] as? String, let evidence = by[id] else { return row }
                var merged = row
                merged["recorded_steps"] = evidence["recorded_steps"]
                merged["evidence"] = evidence["evidence"]
                return merged
            }
        }
        let weighIns = try await weighInRows.values
        let weekRows = try await weekMealRows.values
        let sampleRows = try await sampleRowsAsync.values
        let vitalRows = try await vitalRowsAsync.values
        let nightRows = try? await nightRowsAsync.values
        let oxygenRows = try? await oxygenRowsAsync.values
        let responseRows = try? await responseRowsAsync.values
        let liveRows = try await liveRowsAsync.values
        let liveStressRows = try? await liveStressRowsAsync.values
        let liveHeartRows = try? await liveHeartRowsAsync.values
        let formal = try await formalRead?.value
        let formalMetrics: [[String: Any]]?
        if let formal {
            guard formal["ok"] as? Bool == true,
                  let metrics = formal["data"] as? [[String: Any]] else {
                throw Failure.unavailable
            }
            formalMetrics = metrics
        } else {
            formalMetrics = nil
        }
        try await verify(rows: rows, versioned: dailyRead.versioned,
                         formalMetrics: formalMetrics, from: from, to: to)
        try checkCurrent()
        var snapshot = Snapshot(rows: rows, fuel: fuel)
        snapshot.reserve = reserve; snapshot.training = training
        snapshot.weighIns = weighIns; snapshot.meals = weekRows
        snapshot.reserveSamples = sampleRows; snapshot.nights = nightRows
        snapshot.oxygen = oxygenRows; snapshot.response = responseRows
        snapshot.live = liveRows; snapshot.liveStress = liveStressRows; snapshot.liveHeart = liveHeartRows
        snapshot.formalMetrics = formalMetrics; snapshot.remoteVitals = Self.decodeVitals(vitalRows)
        snapshot.accepts = accepts
        return snapshot
    }

    /// Status narrows summaries to changed days. Revisions become known only after the
    /// complete result was accepted, never merely because a request returned.
    func summaries(days: Int, endingAt day: UserDay, known: [String: String],
                   cachedDays: Set<String>, didPublish: @escaping @MainActor ([String: String]) -> Void) async throws -> Snapshot? {
        try checkCurrent()
        let from = day.adding(days: -min(days, 182)).key
        let status = try await calculationStatusIfAvailable(from: from, to: day.key)
        var range = [URLQueryItem(name: "user_day", value: "gte.\(from)")]
        if let status {
            let changed = status.compactMap { row -> String? in
                guard let key = row["user_day"] as? String else { return nil }
                return HomeLaunchPolicy.shouldRefreshSummary(revision: row["result_revision"] as? String,
                    cachedRevision: known[key], hasCachedRow: cachedDays.contains(key)) ? key : nil
            }
            guard let filter = HomeLaunchPolicy.postgrestIn(changed) else { return nil }
            range = [.init(name: "user_day", value: filter)]
        }
        let selection = try await selectDailyResultsCompat(query: [
            .init(name: "select", value: Self.dailyColumns),
            .init(name: "user_day", value: "lte.\(day.key)"),
            .init(name: "order", value: "user_day.asc"),
        ] + range)
        let rows = selection.rows
        let fuel = try await selectByResultId("day_fuel",
            columns: "result_id,kcal_in,kcal_out,protein_in_g,carb_in_g,fat_in_g,weight_kg,intake_state,slot_states",
            ids: rows.compactMap { $0["id"] as? String }).values
        if status != nil {
            try await verify(rows: rows, versioned: selection.versioned, formalMetrics: nil,
                             from: from, to: day.key, statusRequired: true)
        }
        try checkCurrent()
        var snapshot = Snapshot(rows: rows, fuel: fuel)
        snapshot.accepts = accepts
        snapshot.didPublish = {
            let revisions = rows.reduce(into: known) { result, row in
                if let key = row["user_day"] as? String, let revision = row["result_revision"] as? String {
                    result[key] = revision
                }
            }
            didPublish(revisions)
        }
        return snapshot
    }

    private func checkCurrent() throws {
        guard accepts(), !Task.isCancelled else { throw CancellationError() }
    }

    private func select(_ table: String, query: [URLQueryItem]) async throws -> Rows {
        try checkCurrent()
        let rows = try await transport.select(table, query)
        try checkCurrent()
        return rows
    }

    private func selectSamplePages(_ table: String, query: [URLQueryItem]) async throws -> Rows {
        let base = query.filter { !["order", "offset", "limit"].contains($0.name) }
        let rows = try await SamplePageRead.all { offset in
            try await select(table, query: base + [
                .init(name: "order", value: "ts.asc,src.asc"),
                .init(name: "offset", value: String(offset)), .init(name: "limit", value: "1000"),
            ]).values
        }
        return Rows(rows)
    }

    private func selectDailyResultsCompat(query: [URLQueryItem]) async throws -> (rows: [Row], versioned: Bool) {
        var query = query
        var versioned = true
        var removed: Set<String> = []
        while true {
            do { return (try await select("daily_results", query: query).values, versioned) }
            catch {
                let capability: String
                if !removed.contains("worn"), transport.missingCapability(error, "worn") { capability = "worn" }
                else if !removed.contains("result_revision"), transport.missingCapability(error, "result_revision") {
                    capability = "result_revision"; versioned = false
                } else { throw error }
                removed.insert(capability)
                let columns: Set<String> = capability == "worn" ? ["worn", "wear_run", "wear_miss"] : ["result_revision"]
                query = query.map { item in
                    item.name == "select" ? URLQueryItem(name: item.name, value:
                        item.value?.split(separator: ",").filter { !columns.contains(String($0)) }.joined(separator: ",")) : item
                }
            }
        }
    }

    private func metricReadIfAvailable(from: String, to: String) async throws -> Object? {
        do {
            try checkCurrent()
            let reply = try await transport.metrics(from, to)
            try checkCurrent()
            return reply
        } catch {
            guard transport.missingCapability(error, "metric-read") else { throw error }
            return nil
        }
    }

    private func calculationStatusIfAvailable(from: String, to: String) async throws -> [Row]? {
        do {
            try checkCurrent()
            let reply = try await transport.status(from, to)
            try checkCurrent()
            return reply.values
        } catch {
            guard transport.missingCapability(error, "calculation_status") else { throw error }
            return nil
        }
    }

    private func verify(rows: [Row], versioned: Bool, formalMetrics: [Row]?,
                        from: String, to: String, statusRequired: Bool = false) async throws {
        guard versioned else { return }
        for metric in formalMetrics ?? [] where metric["metric"] as? String != "sleepMinutes" {
            for point in metric["points"] as? [Row] ?? [] {
                if let row = rows.first(where: { $0["user_day"] as? String == point["dayKey"] as? String }),
                   row["result_revision"] as? String != point["resultRevision"] as? String {
                    throw Failure.revisionChanged
                }
            }
        }
        if let status = try await calculationStatusIfAvailable(from: from, to: to) {
            guard rows.allSatisfy({ row in status.contains {
                ($0["user_day"] as? String) == (row["user_day"] as? String)
                    && ($0["result_revision"] as? String) == (row["result_revision"] as? String)
            } }) else { throw Failure.revisionChanged }
        } else if statusRequired { throw Failure.revisionChanged }
    }

    private func selectByResultId(_ table: String, columns: String, ids: [String]) async throws -> Rows {
        let clean = ids.filter { !$0.isEmpty }
        var rows: [Row] = []
        for offset in stride(from: 0, to: clean.count, by: 80) {
            let chunk = Array(clean[offset..<min(offset + 80, clean.count)])
            guard let filter = HomeLaunchPolicy.postgrestIn(chunk) else { continue }
            rows += try await select(table, query: [
                .init(name: "select", value: columns), .init(name: "result_id", value: filter),
            ]).values
        }
        return Rows(rows)
    }

    private func selectTrainingExtras(ids: [String]) async -> Rows? {
        try? await selectByResultId("daily_training", columns: "result_id,active_minutes,distance_m", ids: ids)
    }

    static func decodeVitals(_ rows: [Row]) -> [VitalSample] {
        rows.compactMap { row in
            guard let t = row["ts"] as? String, let at = timestamp(t) else { return nil }
            let hr = number(row["heart"]).map(Int.init), stress = number(row["stress"]).map(Int.init)
            let temp = number(row["temp"]), steps = number(row["step"]).map(Int.init), met = number(row["met"])
            let evidence = (row["domain_sources"] as? Row)?["hrv"] as? Row
            let valid = evidence?["hrv_valid"] as? Bool
            let observedAt = (evidence?["observed_at"] as? String).flatMap(timestamp)
            let hrv = valid == false ? nil : number(row["hrv"])
            guard hr != nil || stress != nil || temp != nil || steps != nil || met != nil || hrv != nil || valid == false else { return nil }
            return VitalSample(ts: at, hr: hr, stress: stress, temp: temp, steps: steps, met: met,
                vendorCalories: number(row["cal"]), dis: number(row["dis"]), hrv: hrv,
                hrvValid: valid, hrvObservedAt: observedAt)
        }
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let s = any as? String { return Double(s) }
        return (any as? NSNumber)?.doubleValue
    }

    nonisolated static func timestamp(_ raw: String) -> Date? {
        let strict = ISO8601DateFormatter(); strict.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = strict.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return date }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                       "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            f.dateFormat = format
            if let date = f.date(from: raw) { return date }
        }
        return nil
    }
}
