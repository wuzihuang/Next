import Foundation

/// F3 §05 · reading. The home screen reads one row of daily_results. A detail page reads
/// daily_results plus its detail row, joined by result_id.
/// ⚠️ No detail page ever starts a second computation. If the join misses, the screen
/// degrades in place to "——" — it does not compute a substitute and does not send a second request.
@MainActor
final class Repository {
    static let shared = Repository()

    let db = SupabaseClient.shared

    /// The bound HOOP's row id. Cached because sync_runs and device_capabilities both name
    /// it, and neither is worth a round trip of its own.
    private(set) var deviceId: String?

    private var homeFastTask: Task<Void, Never>?
    private var evidencePublicationTask: Task<Void, Never>?
    private var homeFastDone = false
    private var readGeneration: UInt = 0
    private(set) var sessionGeneration: UInt = 0
    private var summaryRevisions: [String: [String: String]] = [:]

    /// Open a session before Home reads. A real session from the gate is never replaced.
    /// Simulator: restore, or sign in as the seeded demo account.
    /// Device: restore only; a leftover demo@ session is dropped so the gate comes back.
    func openSession() async throws {
        if await db.restoreSession() {
            if !Band.allowsSeed, DemoAccount.matches(await db.signedInEmail() ?? "") {
                await db.signOut()
            }
            return
        }
        guard Band.allowsSeed else { return }
        try await db.signIn(email: DemoAccount.email, password: DemoAccount.password)
    }

    func resetBootstrap() {
        deviceId = nil
        summaryRevisions = [:]
        homeFastTask?.cancel()
        evidencePublicationTask?.cancel()
        evidencePublicationTask = nil
        readGeneration &+= 1
        sessionGeneration &+= 1
        homeFastTask = nil
        homeFastDone = false
    }

    /// Session plus today's row. History, composition and capability tables follow in the
    /// background so Home is not held behind 182 days of `daily_results`.
    func bootstrapHome(into store: DataStore) async {
        if let homeFastTask { await homeFastTask.value }
        if homeFastDone { return }
        let task = Task { @MainActor in
            let started = Date()
            try? await openSession()
            let account = SupabaseClient.currentUserIdSnapshot()
            guard account != nil, !Task.isCancelled else { return }
            await loadHomeFast(into: store)
            store.hydrateBatteryLog()
            guard account == SupabaseClient.currentUserIdSnapshot(), !Task.isCancelled else { return }
            HomeSnapshot.save(from: store)
            #if DEBUG
            NSLog("Repository.bootstrapHome fast %.0f ms",
                  Date().timeIntervalSince(started) * 1000)
            #endif
            guard !store.isOffline else { return }
            homeFastDone = true
            Task { @MainActor in
                guard account == SupabaseClient.currentUserIdSnapshot() else { return }
                await loadHomeRest(into: store)
                guard account == SupabaseClient.currentUserIdSnapshot() else { return }
                HomeSnapshot.save(from: store)
            }
        }
        homeFastTask = task
        await task.value
    }

    func loadToday(into store: DataStore) async {
        await bootstrapHome(into: store)
    }

    private func loadHomeFast(into store: DataStore) async {
        let today = UserDay.containing(Date())
        async let profile: Void = loadProfile(into: store, ensureRow: false)
        async let day: Void = load(days: HomeLaunchPolicy.fastLoadLookbackDays,
                                   endingAt: today, into: store)
        _ = await (profile, day)
    }

    private func loadHomeRest(into store: DataStore) async {
        let generation = sessionGeneration
        let today = UserDay.containing(Date())
        guard generation == sessionGeneration else { return }
        await loadProfile(into: store, ensureRow: true)
        // 11 · the heat map is twenty-six columns of seven days.
        guard generation == sessionGeneration else { return }
        await loadHistorySummaries(days: 182, endingAt: today, into: store)
        guard generation == sessionGeneration else { return }
        // ADR 0008 · thirty nights of sleep score. The sleep board's week and month windows
        // are drawn from this dictionary; nothing on that page fetches.
        await loadSleepScores(days: 30, endingAt: today, into: store)
        guard generation == sessionGeneration else { return }
        await loadComposition(into: store)
        guard generation == sessionGeneration else { return }
        // ADR 0010 · 「我的」那块 MEASUREMENTS 和测量记录页都读它，两张表两次小查询。
        await loadMeasurements(into: store)
        guard generation == sessionGeneration else { return }
        await loadCapabilities(into: store)
        guard generation == sessionGeneration else { return }
        await loadLastSync(into: store)
        guard generation == sessionGeneration else { return }
        await WeighInQueue.shared.flush()
        guard generation == sessionGeneration else { return }
        await BodyCompositionQueue.shared.flush()
        guard generation == sessionGeneration else { return }
        await BalanceCheckQueue.shared.flush()
        guard generation == sessionGeneration else { return }
        await flushPendingEvidence()
    }

    /// Account-owned outboxes can retry without a connected band or an active sensor read.
    func flushPendingEvidence() async {
        guard let account = SupabaseClient.currentUserIdSnapshot(), Reachability.shared.isOnline else { return }
        if let running = evidencePublicationTask { await running.value; return }
        let generation = sessionGeneration
        let task = Task { @MainActor in
            await publishPendingEvidence(account: account, generation: generation)
        }
        evidencePublicationTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if generation == sessionGeneration { evidencePublicationTask = nil }
    }

    private func publishPendingEvidence(account: String, generation: UInt) async {
        guard account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration,
              !Task.isCancelled else { return }
        await MealQueue.shared.flush()
        guard account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration else { return }
        await OriginDataSync.flushPendingEvidence(userId: account)
        guard account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration,
              !Task.isCancelled else { return }
        let today = UserDay.containing(Date())
        do {
            let status = try await calculationStatusIfAvailable(from: today.key, to: today.key)
            let pending: [Bool?]? = status.map { rows in
                rows.map { row in
                    guard row["result_revision"] as? String != nil else { return nil }
                    return row["pending"] as? Bool
                }
            }
            guard HomeLaunchPolicy.needsEvidenceSettlement(pending: pending),
                  account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration,
                  !Task.isCancelled else { return }
            // The server drains its persisted dirty range, even when this retry uploaded
            // no new facts. Its revision check avoids replaying already-current days.
            _ = try await db.rpc("settle_now", args: ["p_days": 0], expectedOwner: account)
            guard account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration,
                  !Task.isCancelled else { return }
            // loadToday is a cached bootstrap and would keep showing the old result.
            await load(days: HomeLaunchPolicy.fastLoadLookbackDays, endingAt: today, into: DataStore.shared)
            guard account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration else { return }
            HomeSnapshot.save(from: DataStore.shared)
        } catch { BandLog.shared.record("publish drained evidence", error: error) }
    }

    func loadLastSync(into store: DataStore) async {
        let generation = sessionGeneration
        let account = SupabaseClient.currentUserIdSnapshot()
        guard let rows = try? await db.select("devices", query: [
            .init(name: "select", value: "id,last_origin_sync_at,bound_at"),
            .init(name: "unbound_at", value: "is.null"),
            .init(name: "limit", value: "1"),
        ]), let row = rows.first else { return }
        guard account != nil, account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration else { return }
        if let id = row["id"] as? String { deviceId = id }
        store.lastSync = (row["last_origin_sync_at"] as? String).flatMap(Self.timestamp)
        await loadCompanionSince(into: store, generation: generation, account: account)
    }

    /// The profile exists from onboarding onwards; failing to read it is a serious fault,
    /// so the screen keeps whatever it already had rather than blanking the identity card.
    func loadProfile(into store: DataStore, ensureRow: Bool = true) async {
        let generation = sessionGeneration
        let account = SupabaseClient.currentUserIdSnapshot()
        async let profileRows = db.select("profiles", query: [
            .init(name: "select", value: "display_name,sex,height_cm,birth_date,goal,units_metric,timezone"),
            .init(name: "limit", value: "1"),
        ])
        async let deviceRows = db.select("devices", query: [
            .init(name: "select", value: "id,firmware_version,battery_percent,device_number,last_origin_sync_at,bound_at"),
            // The bound one. A forgotten HOOP keeps its row (12 · "your history stays") and
            // must not lend the header its last battery reading.
            .init(name: "unbound_at", value: "is.null"),
            .init(name: "limit", value: "1"),
        ])
        let found = (try? await profileRows)?.first
        let device = (try? await deviceRows)?.first
        guard account != nil, account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration else { return }
        // The row must exist and carry this phone's zone before anything can be computed.
        if ensureRow {
            await ensureProfileRow(existingTimezone: found?["timezone"] as? String)
        }
        guard account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration else { return }
        let mail = await db.signedInEmail()
        guard account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration else { return }
        if let d = device {
            deviceId = d["id"] as? String
            // Network hydration may finish after early BLE readiness. Never replace a
            // session's real device observation with a cached cloud row.
            if store.bandObservationRevision == 0, !store.band.connected {
                if let fw = d["firmware_version"] as? String { store.band.firmware = fw }
                if let pct = number(d["battery_percent"]) { store.band.batteryPercent = Int(pct) }
            }
            if store.lastSync == nil {
                store.lastSync = (d["last_origin_sync_at"] as? String).flatMap(Self.timestamp)
            }
        }
        await loadCompanionSince(into: store, generation: generation, account: account)
        guard let row = found else { return }

        if let name = row["display_name"] as? String, !name.isEmpty { store.profile.name = name }
        // The address is whoever is signed in — never a placeholder next to real numbers.
        if let mail { store.profile.email = mail }
        if let h = number(row["height_cm"]) { store.profile.heightCm = h }
        if let sex = row["sex"] as? String { store.profile.sexIsMale = (sex == "male") }
        if let goal = (row["goal"] as? String).flatMap(Goal.init(rawValue:)) { store.profile.goal = goal }
        if let metric = row["units_metric"] as? Bool { store.profile.usesMetric = metric }
        if let birth = row["birth_date"] as? String {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: String(birth.prefix(10))) { store.profile.birthdate = d }
        }
    }

    /// F0 rule 09 · every field carries its own source. MEASURED re-anchors the EMA;
    /// weight × body-fat % is DERIVED and never written back over history.
    func loadComposition(into store: DataStore) async {
        let generation = sessionGeneration
        let account = SupabaseClient.currentUserIdSnapshot()
        guard let rows = try? await db.select("body_composition", query: [
            .init(name: "select",
                  value: "id,measured_at,body_fat_pct,fat_mass_kg,lean_body_mass_kg,bmr_kcal,input_weight_kg,measurement_source"),
            .init(name: "order", value: "measured_at.desc"),
            .init(name: "limit", value: "200"),
        ]) else { return }

        guard account != nil, account == SupabaseClient.currentUserIdSnapshot(), generation == sessionGeneration else { return }
        store.compositionScans = compositionScans(from: rows)
        guard let latest = rows.first else { return }
        store.today.fatKg = number(latest["fat_mass_kg"])
        store.today.leanKg = number(latest["lean_body_mass_kg"])
        store.today.fatSource = (latest["measurement_source"] as? String) == "manual" ? .derived : .measured

        // 12 · WEEK averages fat and lean across seven days and compares that to the seven
        // before it. Holding the scan only on `today` left both weeks empty and the card
        // said NO PREVIOUS WEEK on an account with 111 scans.
        var byDay: [UserDay: (fat: Double?, lean: Double?)] = [:]
        for row in rows {
            guard let iso = row["measured_at"] as? String, let at = Self.timestamp(iso) else { continue }
            byDay[UserDay.containing(at)] = (number(row["fat_mass_kg"]), number(row["lean_body_mass_kg"]))
        }
        for i in store.history.indices {
            if let scan = byDay[store.history[i].day] {
                store.history[i].fatKg = scan.fat
                store.history[i].leanKg = scan.lean
            }
        }

        // ⚠️ Not ISO8601DateFormatter(): PostgREST returns measured_at with an offset the
        // plain parser will take but a fractional-second column will not, and every row
        // then fails its date test — scans7d came back 0 and board 12 sat in its empty
        // state on an account with six months of measurements.
        /// The oldest row at least `daysAgo` old — or, if the history is shorter than that,
        /// the oldest row there is. A net change over "as much history as exists" is honest;
        /// refusing to show one because the window is not full is not.
        func at(daysAgo: Int) -> [String: Any]? {
            let cutoff = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
            let older = rows.first { row in
                guard let s = row["measured_at"] as? String, let d = Self.timestamp(s) else { return false }
                return d <= cutoff
            }
            return older ?? rows.last
        }

        if let weekAgo = at(daysAgo: 7) {
            store.today.fatEmaDelta7d = (number(latest["fat_mass_kg"]) ?? 0)
                - (number(weekAgo["fat_mass_kg"]) ?? 0)
            store.today.leanEmaDelta7d = (number(latest["lean_body_mass_kg"]) ?? 0)
                - (number(weekAgo["lean_body_mass_kg"]) ?? 0)
        }
        store.today.scans7d = rows.filter { row in
            guard let s = row["measured_at"] as? String, let d = Self.timestamp(s) else { return false }
            return d >= Date().addingTimeInterval(-7 * 86_400)
        }.count

        // 11 · the three tiles are 12-week net changes, except BODY FAT which is absolute.
        if let twelveWeeks = at(daysAgo: 84) {
            store.netFatMass12w = (number(latest["fat_mass_kg"]) ?? 0)
                - (number(twelveWeeks["fat_mass_kg"]) ?? 0)
            store.netLeanMass12w = (number(latest["lean_body_mass_kg"]) ?? 0)
                - (number(twelveWeeks["lean_body_mass_kg"]) ?? 0)
        }
        store.bodyFatPercent = number(latest["body_fat_pct"])
    }

    /// F1 §02 facts for the gate. RLS scopes both reads; a missing row is "not yet", not an error.
    func fetchAccountGate() async -> AccountGate {
        var facts = AccountGate()
        async let deviceRows = db.select("devices", query: [
            .init(name: "select", value: "id"),
            .init(name: "unbound_at", value: "is.null"),
            .init(name: "limit", value: "1"),
        ])
        async let profileRows = db.select("profiles", query: [
            .init(name: "select", value: "display_name,sex,height_cm,birth_date,goal"),
            .init(name: "limit", value: "1"),
        ])
        async let weighRows = db.select("weigh_ins", query: [
            .init(name: "select", value: "weight_kg"),
            .init(name: "order", value: "measured_at.desc"),
            .init(name: "limit", value: "1"),
        ])
        if let device = (try? await deviceRows)?.first {
            facts.hasBoundBand = true
            if let id = device["id"] as? String { deviceId = id }
        }
        if let row = (try? await profileRows)?.first {
            facts.displayName = row["display_name"] as? String
            facts.sex = row["sex"] as? String
            facts.heightCm = number(row["height_cm"])
            if let birth = row["birth_date"] as? String {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                facts.birthDate = f.date(from: String(birth.prefix(10)))
            }
            if let raw = row["goal"] as? String { facts.goal = Goal(rawValue: raw) }
        }
        if let weigh = (try? await weighRows)?.first {
            facts.weightKg = number(weigh["weight_kg"])
        }
        return facts
    }

    /// The bound HOOP's row. Written at the end of pairing, not only after Home reconnects
    /// — a kill on the onboarding screens used to leave the account with no devices row.
    /// One bound row per user (unbound_at is null): patched when it is the same band,
    /// unbound + inserted when the ble identifier changed.
    func registerDevice(identity: BandIdentity?, battery: BandBattery?) async {
        guard let userId = await db.currentUserId else { return }
        var row: [String: Any] = [:]
        if let identity {
            row["firmware_version"] = identity.firmware
            row["device_number"] = identity.deviceNumber
        }
        if let battery {
            // ⚠️ Three columns together (02 rule 05): a bar count is never stored as a percent.
            row["battery_is_percent"] = battery.isPercent
            if let p = battery.percent { row["battery_percent"] = p }
            if let l = battery.level { row["battery_level"] = l }
        }
        let ble = identity?.bleIdentifier ?? BoundBand.identifier
        do {
            let bound = try await db.select("devices", query: [
                .init(name: "select", value: "id,ble_identifier,device_number,bound_at"),
                .init(name: "unbound_at", value: "is.null"),
                .init(name: "limit", value: "1"),
            ]).first
            if let id = bound?["id"] as? String {
                let existingBle = bound?["ble_identifier"] as? String
                let sameHoop = {
                    guard let number = identity?.deviceNumber, !number.isEmpty,
                          number == bound?["device_number"] as? String else { return false }
                    return true
                }()
                // Simulator seed must not steal a real binding and reset companionship.
                if let ble, ble == BoundBand.seedIdentifier, existingBle != ble {
                    deviceId = id
                    applyBoundAt(bound?["bound_at"], into: DataStore.shared)
                } else if let ble, existingBle != ble, !sameHoop {
                    _ = try await db.patch("devices", id: id, row: [
                        "unbound_at": ISO8601DateFormatter().string(from: Date()),
                    ])
                    var insert = row
                    insert["user_id"] = userId
                    insert["ble_identifier"] = ble
                    insert["ble_identifier_kind"] = "uuid"
                    rememberInsertedDevice(try await db.insert("devices", row: insert).first)
                } else {
                    deviceId = id
                    applyBoundAt(bound?["bound_at"], into: DataStore.shared)
                    if ble != nil, existingBle != ble { row["ble_identifier"] = ble }
                    if !row.isEmpty { _ = try await db.patch("devices", id: id, row: row) }
                }
            } else if let ble {
                row["user_id"] = userId
                row["ble_identifier"] = ble
                row["ble_identifier_kind"] = "uuid"
                rememberInsertedDevice(try await db.insert("devices", row: row).first)
            }
            await loadCompanionSince(into: DataStore.shared)
        } catch {
            #if DEBUG
            NSLog("Repository.registerDevice failed: %@", "\(error)")
            #endif
        }
    }

    /// F3 · Forget this HOOP writes unbound_at. The row stays so history still has a device
    /// to name; the unique "one bound per user" slot opens for the next pair.
    func unbindBoundDevice() async {
        do {
            let bound = try await db.select("devices", query: [
                .init(name: "select", value: "id"),
                .init(name: "unbound_at", value: "is.null"),
                .init(name: "limit", value: "1"),
            ]).first
            let id = bound?["id"] as? String ?? deviceId
            guard let id else { return }
            _ = try await db.patch("devices", id: id, row: [
                "unbound_at": ISO8601DateFormatter().string(from: Date()),
            ])
            deviceId = nil
        } catch {
            #if DEBUG
            NSLog("Repository.unbindBoundDevice failed: %@", "\(error)")
            #endif
        }
    }

    /// `devices.last_origin_sync_at` and the in-memory SYNCED label share this one meaning:
    /// the completion time of a fully successful band sync, never the timestamp of a sample.
    func markDeviceSynced(at date: Date) async {
        guard let deviceId else { return }
        do {
            _ = try await db.patch("devices", id: deviceId, row: [
                "last_origin_sync_at": ISO8601DateFormatter().string(from: date),
            ])
        } catch { BandLog.shared.record("patch last_origin_sync_at", error: error) }
    }

    /// F3 · the day's row is computed on the server and nowhere else. The cron settles every
    /// hour; this asks for the caller's own window now, so a page that just came off the band
    /// is on the screen before the hour turns. `days` back from today, today included.
    /// Quiet when the RPC is not deployed yet — the cron still comes round.
    func settleNow(days: Int) async {
        do { _ = try await db.rpc("settle_now", args: ["p_days": days]) }
        catch {
            #if DEBUG
            NSLog("Repository.settleNow failed: %@", "\(error)")
            #endif
        }
    }

    /// 06 rule 09 · a band scan is a row in body_composition, not a number in memory.
    /// device_bia, computed from the weight we pushed down (input_weight_kg); the BIA's own
    /// BMR is stored as a reference and never enters the budget.
    func recordBodyComposition(_ r: BodyCompositionReading, at date: Date = Date()) async {
        guard let userId = await db.userId else { return }
        do { try BodyCompositionQueue.shared.enqueue(r, at: date, ownerUserId: userId) }
        catch { BandLog.shared.record("persist body composition", error: error); return }
    }

    /// ADR 0010 · 一次平衡检查的摘要行。只在测量真的完成（`.finished` 且区间够算出结论）之后
    /// 调用——失败态不写，NOTHING KEPT 是字面意思。
    func recordBalanceCheck(_ balance: AutonomicBalance, heartRate: Int?,
                            at date: Date = Date()) async {
        guard let userId = await db.userId else { return }
        do { try BalanceCheckQueue.shared.enqueue(balance, heartRate: heartRate, at: date,
                                                  ownerUserId: userId) }
        catch { BandLog.shared.record("persist balance check", error: error) }
    }

    /// ADR 0010 · 「我的」那块 MEASUREMENTS 和测量记录页读的同一个数组。两张表各取一次，按时间
    /// 倒序混排。
    ///
    /// ⚠️ 身体扫描只认 `measurement_source = device_bia`：体脂秤和手动录入不是主动测量。这个
    /// 过滤在服务端做，不要挪到客户端——否则 limit 会先砍掉真正的扫描。
    func loadMeasurements(into store: DataStore, limit: Int = 200) async {
        let generation = sessionGeneration
        let account = SupabaseClient.currentUserIdSnapshot()

        async let scanRows = db.select("body_composition", query: [
            .init(name: "select",
                  value: "id,measured_at,body_fat_pct,fat_mass_kg,lean_body_mass_kg,bmr_kcal,input_weight_kg"),
            .init(name: "measurement_source", value: "eq.device_bia"),
            .init(name: "order", value: "measured_at.desc"),
            .init(name: "limit", value: String(limit)),
        ])
        async let balanceRows = db.select("balance_checks", query: [
            .init(name: "select",
                  value: "id,measured_at,lead,rest_share,sd1_ms,sd2_ms,sdnn_ms,heart_rate,beat_count"),
            .init(name: "order", value: "measured_at.desc"),
            .init(name: "limit", value: String(limit)),
        ])

        var records: [MeasurementRecord] = []
        for row in (try? await scanRows) ?? [] {
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let iso = row["measured_at"] as? String,
                  let at = Self.timestamp(iso) else { continue }
            records.append(MeasurementRecord(id: id, at: at, detail: .bodyScan(.init(
                bodyFatPercent: number(row["body_fat_pct"]),
                fatMassKg: number(row["fat_mass_kg"]),
                leanMassKg: number(row["lean_body_mass_kg"]),
                bmrKcal: number(row["bmr_kcal"]).map { Int($0) },
                inputWeightKg: number(row["input_weight_kg"])))))
        }
        for row in (try? await balanceRows) ?? [] {
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let iso = row["measured_at"] as? String,
                  let at = Self.timestamp(iso),
                  let lead = (row["lead"] as? String)
                      .flatMap(MeasurementRecord.BalanceCheck.Lead.init(rawValue:)) else { continue }
            records.append(MeasurementRecord(id: id, at: at, detail: .balanceCheck(.init(
                lead: lead,
                restShare: Int(number(row["rest_share"]) ?? 50),
                sd1Ms: number(row["sd1_ms"]) ?? 0,
                sd2Ms: number(row["sd2_ms"]) ?? 0,
                sdnnMs: number(row["sdnn_ms"]) ?? 0,
                heartRate: number(row["heart_rate"]).map { Int($0) },
                beatCount: Int(number(row["beat_count"]) ?? 0)))))
        }

        guard account != nil, account == SupabaseClient.currentUserIdSnapshot(),
              generation == sessionGeneration else { return }
        store.measurements = records.sorted { $0.at > $1.at }
    }

    /// Heat map and week summaries never download historical training curves.
    /// ADR 0008 · the sleep board's week and month windows, in one query of thirty small
    /// rows. The score is settled server-side precisely so this can be cheap: the two inputs
    /// that make a night legible — per-minute overnight SpO2 and the respiration series
    /// buried in `sleep_nights.raw` — never leave the database.
    func loadSleepScores(days: Int, endingAt day: UserDay, into store: DataStore) async {
        let generation = readGeneration
        do {
            guard SupabaseClient.currentUserIdSnapshot() != nil else { return }
            let rows = try await db.select("night_score", query: [
                .init(name: "select", value: "user_day,score,duration_score,architecture_score,recovery_score,regularity_score,personal_weight,inputs,score_version"),
                .init(name: "user_day", value: "gte.\(day.adding(days: -max(days, 1)).key)"),
                .init(name: "user_day", value: "lte.\(day.key)"),
                .init(name: "order", value: "user_day.asc"),
            ])
            var scores: [String: SleepScore] = [:]
            for row in rows {
                guard let key = row["user_day"] as? String,
                      let total = Self.integer(row["score"]) else { continue }
                var inputs: [String: Double] = [:]
                for (name, value) in (row["inputs"] as? [String: Any] ?? [:]) {
                    if let number = Self.decimal(value) { inputs[name] = number }
                }
                scores[key] = SleepScore(
                    score: total,
                    duration: Self.integer(row["duration_score"]),
                    architecture: Self.integer(row["architecture_score"]),
                    recovery: Self.integer(row["recovery_score"]),
                    regularity: Self.integer(row["regularity_score"]),
                    personalWeight: Self.decimal(row["personal_weight"]) ?? 0,
                    inputs: inputs,
                    version: row["score_version"] as? String ?? "")
            }
            guard generation == readGeneration else { return }
            await MainActor.run {
                store.sleepScores = scores
                store.today.sleepScore = scores[store.today.day.key]
                for index in store.history.indices {
                    store.history[index].sleepScore = scores[store.history[index].day.key]
                }
            }
        } catch {
            // A night without a score reads as a night without a score. There is nothing to
            // fall back to and nothing to tell the user about a window that simply has no row.
        }
    }

    /// ⚠️ `Int(_: Double)` traps on NaN, on infinity and out of range, so the string branch
    /// checks before it converts: a blank or malformed score reads as no score, never a crash.
    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        guard let text = value as? String, let number = Double(text), number.isFinite,
              number >= -1e9, number <= 1e9 else { return nil }
        return Int(number)
    }

    private static func decimal(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
    }

    func loadHistorySummaries(days: Int, endingAt day: UserDay, into store: DataStore) async {
        let account = SupabaseClient.currentUserIdSnapshot()
        let generation = readGeneration
        do {
            guard let account else { return }
            let from = day.adding(days: -min(days, 182)).key
            let status = try await calculationStatusIfAvailable(from: from, to: day.key)
            let known = summaryRevisions[account] ?? [:]
            var range = [URLQueryItem(name: "user_day", value: "gte.\(from)")]
            if let status {
                let changed = status.compactMap { row -> String? in
                    guard let key = row["user_day"] as? String else { return nil }
                    let hasCachedRow = store.today.day.key == key || store.history.contains { $0.day.key == key }
                    return HomeLaunchPolicy.shouldRefreshSummary(revision: row["result_revision"] as? String,
                        cachedRevision: known[key], hasCachedRow: hasCachedRow) ? key : nil
                }
                guard let changedFilter = HomeLaunchPolicy.postgrestIn(changed) else { return }
                range = [.init(name: "user_day", value: changedFilter)]
            }
            let selection = try await selectDailyResultsCompat(query: [
                .init(name: "select", value: "id,user_day,training_load,reserve_score,fuel_balance_kcal,daily_direction,the_call,the_call_confidence,fat_delta_7d,lean_delta_7d,scans_7d,computed_at,algo_version,result_revision,worn,wear_run,wear_miss"),
                .init(name: "user_day", value: "lte.\(day.key)"),
                .init(name: "order", value: "user_day.asc"),
            ] + range)
            let rows = selection.rows
            let fuel = try await selectByResultId("day_fuel",
                columns: "result_id,kcal_in,kcal_out,protein_in_g,carb_in_g,fat_in_g,weight_kg,intake_state,slot_states",
                ids: rows.compactMap { $0["id"] as? String })
            if status != nil && selection.versioned {
                guard let latestStatus = try await calculationStatusIfAvailable(from: from, to: day.key),
                    rows.allSatisfy({ row in latestStatus.contains {
                        ($0["user_day"] as? String) == (row["user_day"] as? String)
                            && ($0["result_revision"] as? String) == (row["result_revision"] as? String)
                    } }) else { return }
            }
            guard HomeLaunchPolicy.acceptsRead(account: account,
                currentAccount: SupabaseClient.currentUserIdSnapshot(), generation: generation,
                currentGeneration: readGeneration), !Task.isCancelled else { return }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
            let summaries: [DailyMetrics] = rows.compactMap { row in
                guard let key = row["user_day"] as? String, let date = f.date(from: key) else { return nil }
                let d = UserDay(date: Calendar.current.date(bySettingHour: UserDay.boundaryHour,
                    minute: 0, second: 0, of: date) ?? date)
                let asOf = (row["computed_at"] as? String).flatMap(Self.timestamp)
                // Preserve an already loaded detail only when its result is the same or newer.
                if let existing = store.metrics(for: d), let at = existing.asOf,
                   let asOf, at >= asOf {
                    var retained = existing
                    retained.sleep = Self.sleepOnWakeDay(existing.sleep, day: d)
                    return retained
                }
                var m = DailyMetrics(day: d)
                m.trainingLoad = number(row["training_load"])
                m.bodyBattery = number(row["reserve_score"]).map(Int.init)
                m.balance = number(row["fuel_balance_kcal"])
                m.asOf = asOf; m.calcVersion = row["algo_version"] as? String ?? "?"
                m.serverDirection = (row["daily_direction"] as? String).flatMap {
                    switch $0 {
                    case "DEFICIT": .deficit
                    case "LEVEL": .level
                    case "SURPLUS": .surplus
                    case "GREY_NO_BURN": .greyNoBurn
                    default: .greyNothing
                    }
                }
                m.serverCall = (row["the_call"] as? String).flatMap {
                    $0 == "NO_CHANGE" ? .noChange : TheCall(rawValue: $0)
                }
                m.confidence = Confidence(rawValue: row["the_call_confidence"] as? String ?? "") ?? .pending
                m.fatEmaDelta7d = number(row["fat_delta_7d"])
                m.leanEmaDelta7d = number(row["lean_delta_7d"])
                m.scans7d = Int(number(row["scans_7d"]) ?? 0)
                applyWear(row, to: &m)
                if let energy = fuel.first(where: { ($0["result_id"] as? String) == (row["id"] as? String) }) {
                    m.eIn = number(energy["kcal_in"]); m.eOutNow = number(energy["kcal_out"])
                    m.proteinIn = number(energy["protein_in_g"]).map(Int.init)
                    m.carbIn = number(energy["carb_in_g"]).map(Int.init)
                    m.fatIn = number(energy["fat_in_g"]).map(Int.init)
                    m.weightKg = number(energy["weight_kg"])
                    switch energy["intake_state"] as? String {
                    case "FASTED": m.fuelState = .fasted
                    case "CONFIRMED": m.fuelState = .confirmed
                    case "PARTIAL": m.fuelState = .partial(slots: (energy["slot_states"] as? [String: String])?.values.filter { $0 == "CONFIRMED" }.count ?? 0)
                    default: m.fuelState = .unlogged
                    }
                }
                // Summary revisions invalidate computed details, not device observations.
                if let existing = store.metrics(for: d) {
                    m.sleep = Self.sleepOnWakeDay(existing.sleep, day: d)
                    m.vitalsCurve = existing.vitalsCurve
                    m.fatKg = existing.fatKg
                    m.leanKg = existing.leanKg
                }
                return m
            }
            summaryRevisions[account] = known.merging(Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard let key = row["user_day"] as? String, let revision = row["result_revision"] as? String else { return nil }
                return (key, revision)
            }), uniquingKeysWith: { _, new in new })
            store.history = (store.history.filter { old in !summaries.contains { $0.day == old.day } }
                + summaries).sorted { $0.day < $1.day }
            HomeSnapshot.save(from: store)
        } catch {
            // Keep valid cached history when an independent background read fails.
            NSLog("History summary refresh failed: %@", String(describing: error))
        }
    }

    func loadDetail(day: UserDay, into store: DataStore) async {
        guard let account = SupabaseClient.currentUserIdSnapshot() ?? SessionKeychain.userId else { return }
        if var cached = HomeSnapshot.loadDetail(day: day, userId: account),
           store.metrics(for: day)?.asOf == nil || (store.metrics(for: day)?.asOf ?? .distantPast) < (cached.asOf ?? .distantPast) {
            cached.sleep = Self.sleepOnWakeDay(cached.sleep, day: day)
            if day == UserDay.containing(Date()) { store.today = cached }
            store.history = (store.history.filter { $0.day != day } + [cached]).sorted { $0.day < $1.day }
        }
        guard !store.isOffline else { return }
        await load(days: 0, endingAt: day, into: store)
    }

    /// One hydrate seam for a second-level page. The window names the tables; the page
    /// does not pick a loader.
    func hydrate(_ window: DetailWindow, endingAt day: UserDay, focus: UserDay? = nil,
                 into store: DataStore) async {
        switch window.load {
        case .none:
            break
        case .dailyResults(let lookback):
            await load(days: lookback, endingAt: day, into: store)
            if let focus, focus != day {
                await loadDetail(day: focus, into: store)
            }
        case .heartTicks(let days):
            await loadHeartWindow(days: days, into: store)
        case .dailyResultsAndHeartTicks(let lookback, let heartDays):
            await load(days: lookback, endingAt: day, into: store)
            await loadHeartWindow(days: heartDays, into: store)
        case .composition:
            await loadComposition(into: store)
        }
    }

    /// HEART week/month needs more than the one day of `raw_samples` Home preloads.
    /// This is not `load(days:)` — that also pulls meals, fuel, training and nights.
    func loadHeartWindow(days: Int, into store: DataStore) async {
        guard days > 1, !Band.allowsSeed, !store.isOffline else { return }
        guard SupabaseClient.currentUserIdSnapshot() != nil || SessionKeychain.userId != nil else { return }
        let day = store.today.day
        let stamp = ISO8601DateFormatter()
        let from = day.adding(days: -days - 1)
        let to = day.adding(days: 1)
        do {
            async let vitalRowsAsync = db.select("raw_samples", query: [
                .init(name: "select", value: "ts,heart,stress,temp,step,cal,dis,hrv"),
                .init(name: "ts", value: "gte.\(stamp.string(from: from.start))"),
                .init(name: "ts", value: "lt.\(stamp.string(from: to.start))"),
                .init(name: "order", value: "ts.asc"),
            ])
            async let oxygenRowsAsync = db.select("oxygen_samples", query: [
                .init(name: "select", value: "ts,spo2"),
                .init(name: "ts", value: "gte.\(stamp.string(from: from.start))"),
                .init(name: "ts", value: "lt.\(stamp.string(from: to.start))"),
                .init(name: "order", value: "ts.asc"),
            ])
            let vitalRows = try await vitalRowsAsync
            let oxygenRows = try? await oxygenRowsAsync
            let vitals: [VitalSample] = vitalRows.compactMap { row in
                guard let t = row["ts"] as? String, let at = Self.timestamp(t) else { return nil }
                let hr = number(row["heart"]).map { Int($0) }
                let stress = number(row["stress"]).map { Int($0) }
                let temp = number(row["temp"])
                let steps = number(row["step"]).map { Int($0) }
                let hrv = number(row["hrv"])
                guard hr != nil || stress != nil || temp != nil || steps != nil || hrv != nil
                else { return nil }
                return VitalSample(ts: at, hr: hr, stress: stress,
                                   temp: temp,
                                   steps: steps,
                                   vendorCalories: number(row["cal"]),
                                   dis: number(row["dis"]),
                                   hrv: hrv)
            }
            let oxygen: [OvernightOxygenPoint] = (oxygenRows ?? []).compactMap { row in
                guard let at = (row["ts"] as? String).flatMap(Self.timestamp),
                      let percent = number(row["spo2"]).map({ Int($0) }),
                      (50...100).contains(percent) else { return nil }
                return OvernightOxygenPoint(ts: at, percent: percent)
            }
            mergeHeartWindow(vitals: vitals, oxygen: oxygen,
                             from: day.adding(days: -(days - 1)), through: day, into: store)
        } catch {
            NSLog("Heart window load failed: %@", String(describing: error))
        }
    }

    private func mergeHeartWindow(vitals: [VitalSample], oxygen: [OvernightOxygenPoint],
                                  from: UserDay, through: UserDay, into store: DataStore) {
        func apply(_ metrics: inout DailyMetrics, day: UserDay) {
            let remote = vitals.filter { $0.ts >= day.start && $0.ts < day.end }
            metrics.vitalsCurve = VitalSample.merging(metrics.vitalsCurve, with: remote)
            guard let start = metrics.sleep?.sleepStart, let wake = metrics.sleep?.wakeAt,
                  wake > start else { return }
            let nightOxygen = oxygen.filter { $0.ts >= start && $0.ts < wake }
            guard !nightOxygen.isEmpty, var sleep = metrics.sleep else { return }
            sleep.spo2 = Dictionary((sleep.spo2 + nightOxygen).map { ($0.ts, $0) },
                                    uniquingKeysWith: { local, _ in local })
                .values.sorted { $0.ts < $1.ts }
            metrics.sleep = sleep
        }

        var cursor = from
        while cursor <= through {
            if store.today.day == cursor {
                apply(&store.today, day: cursor)
            }
            if let index = store.history.firstIndex(where: { $0.day == cursor }) {
                apply(&store.history[index], day: cursor)
            } else if store.today.day != cursor {
                var row = DailyMetrics(day: cursor)
                apply(&row, day: cursor)
                if !row.vitalsCurve.isEmpty {
                    store.history.append(row)
                }
            }
            cursor = cursor.adding(days: 1)
        }
        store.history.sort { $0.day < $1.day }
    }

    func load(days: Int, endingAt day: UserDay, into store: DataStore) async {
        readGeneration &+= 1
        let generation = readGeneration
        let account = SupabaseClient.currentUserIdSnapshot()
        func isCurrent() -> Bool {
            HomeLaunchPolicy.acceptsRead(account: account,
                currentAccount: SupabaseClient.currentUserIdSnapshot(),
                generation: generation, currentGeneration: readGeneration)
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        let from = f.string(from: day.adding(days: -days).start)
        let to = f.string(from: day.start)

        do {
            let dailyRead = try await selectDailyResultsCompat(query: [
                .init(name: "select",
                      value: "id,user_day,training_load,reserve_score,fuel_balance_kcal,daily_direction,the_call,the_call_confidence,fat_delta_7d,lean_delta_7d,scans_7d,computed_at,algo_version,result_revision,worn,wear_run,wear_miss"),
                .init(name: "user_day", value: "gte.\(from)"),
                .init(name: "user_day", value: "lte.\(to)"),
                .init(name: "order", value: "user_day.asc"),
            ])
            let rows = dailyRead.rows
            #if DEBUG
            NSLog("Repository.load: %d daily_results rows", rows.count)
            #endif

            // Raw samples are available before settle_now has produced daily_results. They
            // must still load: otherwise a successful 12:45 band upload leaves an 08:00 curve
            // on screen merely because the derived row is late. These independent requests
            // run together so that correctness does not add serial round trips.
            // Child tables are keyed to the rows just returned — an unfiltered select used
            // to download every day's fuel/training curve before Home could paint.
            async let formalRead = metricReadIfAvailable(from: from, to: to)
            let resultIds = rows.compactMap { $0["id"] as? String }
            let stamp = ISO8601DateFormatter()
            async let fuelRows = selectByResultId(
                "day_fuel",
                columns: "result_id,intake_state,kcal_in,kcal_out,protein_in_g,slot_states,bmr_kcal,active_kcal,bmr_full_kcal,target_in,protein_g,fat_g,carb_g,carb_in_g,fat_in_g,weight_kg",
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
            async let weighInRows = db.select("weigh_ins", query: [
                .init(name: "select", value: "id,measured_at,weight_kg,source"),
                .init(name: "order", value: "measured_at.desc"),
                .init(name: "limit", value: "60"),
            ])
            // 12 · WEEK needs the week's meals, not just today's. Today's used to be a ninth
            // request for a strict subset of these same rows; it is now filtered out of them.
            async let weekMealRows = db.select("meals", query: [
                .init(name: "select", value: "id,user_day,slot,logged_at,text_input,kcal,protein_g,carb_g,fat_g"),
                .init(name: "deleted_at", value: "is.null"),
                // Dev seeds carry model_version = seed; they must not populate 09 or the dock.
                .init(name: "model_version", value: "neq.seed"),
                .init(name: "user_day", value: "gte.\(f.string(from: day.adding(days: -max(days, 6)).start))"),
                .init(name: "user_day", value: "lte.\(f.string(from: day.start))"),
                .init(name: "order", value: "logged_at.asc"),
            ])
            // 13 · the curve is 288 five-minute ticks of the shown day, not a shape we draw
            // from the day's endpoints. Bounded by the 04:00 cut like everything else.
            async let sampleRowsAsync = db.select("reserve_samples", query: [
                .init(name: "select", value: "ts,value"),
                .init(name: "ts", value: "gte.\(stamp.string(from: day.start))"),
                .init(name: "ts", value: "lt.\(stamp.string(from: day.adding(days: 1).start))"),
                .init(name: "order", value: "ts.asc"),
            ])
            // 13 · heart and stress are not a footnote to the battery — two of the four
            // attribution rows are made of them, so the detail page gets the day's own ticks
            // in the same 04:00 → 04:00 window as the reserve curve.
            // 04B · the second page draws the same ticks: skin temperature and the five
            // minutes' steps, kcal and metres ride along on the columns the sync already writes.
            // Rolling traces need the preceding user day too; every sample is partitioned
            // back into its own 04:00 window after the response arrives.
            async let vitalRowsAsync = db.select("raw_samples", query: [
                .init(name: "select", value: "ts,heart,stress,temp,step,cal,dis,hrv"),
                .init(name: "ts", value: "gte.\(stamp.string(from: day.adding(days: -max(days, 1) - 1).start))"),
                .init(name: "ts", value: "lt.\(stamp.string(from: day.adding(days: 1).start))"),
                .init(name: "order", value: "ts.asc"),
            ])
            // 04 · the HR / STRESS row is the last tick, not an average and not a guess.
            async let liveRowsAsync = db.select("raw_samples", query: [
                .init(name: "select", value: "ts,heart,stress"),
                // A tick in the future is a tick the band cannot have reported.
                .init(name: "ts", value: "lte.\(stamp.string(from: Date()))"),
                .init(name: "order", value: "ts.desc"),
                .init(name: "limit", value: "1"),
            ])
            // The newest row is often a sleep PPG tick with heart and no stress. The
            // STRESS card's "now" is the last positive reading, not that newest null.
            async let liveStressRowsAsync = db.select("raw_samples", query: [
                .init(name: "select", value: "ts,stress"),
                .init(name: "stress", value: "gt.0"),
                .init(name: "ts", value: "lte.\(stamp.string(from: Date()))"),
                .init(name: "order", value: "ts.desc"),
                .init(name: "limit", value: "1"),
            ])
            // 04B · SLEEP card. Prefetched with the rest so Home does not wait a serial hop.
            async let nightRowsAsync = db.select("sleep_nights", query: [
                .init(name: "select", value: "user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_line,sleep_start,wake_at,raw"),
                .init(name: "user_day", value: "gte.\(from)"),
                .init(name: "user_day", value: "lte.\(to)"),
            ])
            async let oxygenRowsAsync = db.select("oxygen_samples", query: [
                .init(name: "select", value: "ts,spo2"),
                .init(name: "ts", value: "gte.\(stamp.string(from: day.adding(days: -max(days, 1) - 1).start))"),
                .init(name: "ts", value: "lt.\(stamp.string(from: day.adding(days: 1).start))"),
                .init(name: "order", value: "ts.asc"),
            ])
            async let responseRowsAsync = db.select("response_samples", query: [
                .init(name: "select", value: "ts,optical"),
                .init(name: "ts", value: "gte.\(stamp.string(from: day.adding(days: -30).start))"),
                .init(name: "ts", value: "lt.\(stamp.string(from: day.adding(days: 1).start))"),
                .init(name: "order", value: "ts.asc"),
            ])

            let fuel = try await fuelRows
            let reserve = try await reserveRows
            var training = try await trainingRows
            if let extras = await trainingExtras {
                let by = Dictionary(uniqueKeysWithValues: extras.compactMap { r in (r["result_id"] as? String).map { ($0, r) } })
                training = training.map { row in
                    guard let id = row["result_id"] as? String, let e = by[id] else { return row }
                    var r = row; r["active_minutes"] = e["active_minutes"]; r["distance_m"] = e["distance_m"]; return r
                }
            }
            let weighIns = try await weighInRows
            let weekRows = try await weekMealRows
            let sampleRows = try await sampleRowsAsync
            let vitalRows = try await vitalRowsAsync
            let nightRows = try? await nightRowsAsync
            let oxygenRows = try? await oxygenRowsAsync
            let responseRows = try? await responseRowsAsync
            let liveRows = try await liveRowsAsync
            let liveStressRows = try? await liveStressRowsAsync
            let formal = try await formalRead
            let formalMetrics: [[String: Any]]?
            if let formal {
                guard formal["ok"] as? Bool == true,
                      let metrics = formal["data"] as? [[String: Any]] else {
                    throw SupabaseClient.Failure.http(503, "Metric read unavailable")
                }
                formalMetrics = metrics
            } else {
                formalMetrics = nil
            }
            if dailyRead.versioned {
                for metric in formalMetrics ?? [] where metric["metric"] as? String != "sleepMinutes" {
                    for point in metric["points"] as? [[String: Any]] ?? [] {
                        if let row = rows.first(where: { $0["user_day"] as? String == point["dayKey"] as? String }),
                           row["result_revision"] as? String != point["resultRevision"] as? String {
                            throw SupabaseClient.Failure.http(409, "Metric revision changed during read")
                        }
                    }
                }
                if let status = try await calculationStatusIfAvailable(from: from, to: to) {
                    guard rows.allSatisfy({ row in
                        status.contains { ($0["user_day"] as? String) == (row["user_day"] as? String)
                            && ($0["result_revision"] as? String) == (row["result_revision"] as? String) }
                    }) else { throw SupabaseClient.Failure.http(409, "Calculation changed during read") }
                }
            }
            guard isCurrent(), !Task.isCancelled else { return }
            func formalValue(_ metric: String, _ key: String) -> Double? {
                let points = formalMetrics?.first { $0["metric"] as? String == metric }?["points"] as? [[String: Any]]
                return number(points?.first { $0["dayKey"] as? String == key }?["value"])
            }

            let fuelBy = Dictionary(uniqueKeysWithValues:
                fuel.compactMap { r in (r["result_id"] as? String).map { ($0, r) } })
            let reserveBy = Dictionary(uniqueKeysWithValues:
                reserve.compactMap { r in (r["result_id"] as? String).map { ($0, r) } })
            let trainingBy = Dictionary(uniqueKeysWithValues:
                training.compactMap { r in (r["result_id"] as? String).map { ($0, r) } })

            var history: [DailyMetrics] = []
            for row in rows {
                guard let dayString = row["user_day"] as? String,
                      let date = f.date(from: String(dayString.prefix(10))) else { continue }
                let userDay = UserDay(date: Calendar.current.date(
                    bySettingHour: UserDay.boundaryHour, minute: 0, second: 0, of: date) ?? date)
                var m = DailyMetrics(day: userDay)
                let id = row["id"] as? String ?? ""

                m.trainingLoad = number(row["training_load"])
                m.serverDirection = (row["daily_direction"] as? String).flatMap {
                    switch $0 {
                    case "DEFICIT": DailyDirection.deficit
                    case "LEVEL": DailyDirection.level
                    case "SURPLUS": DailyDirection.surplus
                    case "GREY_NO_BURN": DailyDirection.greyNoBurn
                    default: DailyDirection.greyNothing
                    }
                }
                m.balance = formalMetrics == nil ? number(row["fuel_balance_kcal"]) : formalValue("deltaKcal", userDay.key)
                m.calcVersion = row["algo_version"] as? String ?? "?"
                m.confidence = Confidence(rawValue: row["the_call_confidence"] as? String ?? "") ?? .pending
                // F3 · computed in Postgres like everything else; the local derivation is
                // the offline fallback, never a second opinion.
                // ⚠️ The column stores NO_CHANGE while the token on screen is "MEASURED,
                // NO CHANGE" — mapping by rawValue alone silently drops that one verdict.
                m.serverCall = (row["the_call"] as? String).flatMap { raw in
                    raw == "NO_CHANGE" ? TheCall.noChange : TheCall(rawValue: raw)
                }
                // 12 · the working behind the verdict, so any day can show it and not only
                // the one the composition fetch happens to have filled in.
                m.fatEmaDelta7d = number(row["fat_delta_7d"])
                m.leanEmaDelta7d = number(row["lean_delta_7d"])
                m.scans7d = Int(number(row["scans_7d"]) ?? 0)
                applyWear(row, to: &m)
                if let iso = row["computed_at"] as? String {
                    m.asOf = Self.timestamp(iso)
                }
                // A valid daytime-only score lives on daily_results even before a night can
                // freeze BB_WAKE. reserve_daily normally carries the same current value, but
                // its absence must not turn a measured reserve_score back into unknown.
                m.bodyBattery = number(row["reserve_score"]).map { Int($0) }

                if let r = reserveBy[id] {
                    m.bbWake = number(r["wake_value"]).map { Int($0) }
                    m.bodyBattery = number(r["current_value"]).map { Int($0) } ?? m.bodyBattery
                    if let d = r["drain_drivers"] as? [String: Any], !d.isEmpty {
                        m.reserveDrivers = ReserveDrivers(
                            lastNight: number(d["last_night"]) ?? 0,
                            awake: number(d["awake"]) ?? 0,
                            movement: number(d["movement"]) ?? 0,
                            stress: number(d["stress"]) ?? 0,
                            anchor: Int(number(d["anchor"]) ?? 0),
                            assumedAnchor: d["assumed_anchor"] as? Bool ?? false)
                    }
                    if let n = r["night_inputs"] as? [String: Any], !n.isEmpty {
                        m.nightInputs = NightInputs(
                            hrv: number(n["hrv"]), hrvBase: number(n["hrv_base"]),
                            rhr: number(n["rhr"]), rhrBase: number(n["rhr_base"]),
                            rhrNights: Int(number(n["rhr_nights"]) ?? 0),
                            hrvNights: Int(number(n["hrv_nights"]) ?? 0),
                            multiplier: number(n["multiplier"]))
                    }
                    if let wake = m.bbWake {
                        let band = BodyBattery.band(for: wake)
                        m.targetLoad = band.target
                        m.optimalZone = band.optimal
                    }
                }
                if let t = trainingBy[id] {
                    m.zoneMinutes = (t["zone_minutes"] as? [Any])?.compactMap { number($0).map(Int.init) }
                    m.peakHR = number(t["peak_hr"]).map { Int($0) }
                    m.activeMinutes = number(t["active_minutes"]).map { Int($0) }
                    m.distanceM = number(t["distance_m"]).map { Int($0) }
                    m.segments = ((t["segments"] as? [Any]) ?? []).compactMap { any in
                        guard let r = any as? [String: Any],
                              let at = (r["at"] as? String).flatMap(Self.timestamp) else { return nil }
                        return TrainingSegment(
                            at: at, name: r["name"] as? String ?? "",
                            minutes: number(r["minutes"]).map { Int($0) },
                            avgHR: number(r["avg_hr"]).map { Int($0) },
                            steps: number(r["steps"]).map { Int($0) },
                            delta: number(r["delta"]) ?? 0,
                            allDay: r["all_day"] as? Bool ?? false)
                    }
                    // The cumulative curve arrives as [[epoch, load]] — one array per tick.
                    m.loadCurve = ((t["curve"] as? [Any]) ?? []).compactMap { any in
                        guard let pair = any as? [Any], pair.count == 2,
                              let epoch = number(pair[0]), let load = number(pair[1]) else { return nil }
                        return LoadPoint(ts: Date(timeIntervalSince1970: epoch), load: load)
                    }
                }
                if let fu = fuelBy[id] {
                    m.eIn = formalMetrics == nil ? number(fu["kcal_in"]) : formalValue("intakeKcal", userDay.key)
                    m.eOutNow = formalMetrics == nil ? number(fu["kcal_out"]) : formalValue("burnKcal", userDay.key)
                    m.proteinIn = (formalMetrics == nil ? number(fu["protein_in_g"]) : formalValue("proteinG", userDay.key)).map { Int($0) }
                    m.carbIn = number(fu["carb_in_g"]).map { Int($0) }
                    m.fatIn = number(fu["fat_in_g"]).map { Int($0) }
                    m.weightKg = number(fu["weight_kg"]) ?? m.weightKg
                    m.bmr = number(fu["bmr_kcal"])
                    m.eActive = number(fu["active_kcal"])
                    // 10 · the header is an estimate of where the day lands. Baseline for
                    // the whole day, today's movement carried forward at the rate it has
                    // actually run at, and the session that is still owed.
                    let elapsed = Double(userDay.elapsedMinutes()) / 1440
                    let full = number(fu["bmr_full_kcal"])
                    m.bmrFull = full
                    let forecast = elapsed > 0.05
                        ? (number(fu["active_kcal"]) ?? 0) / elapsed
                        : number(fu["active_kcal"]) ?? 0
                    m.activeForecast = forecast
                    m.eTrainPlan = nil
                    // The estimate itself is assembled in merge(), once every row it is
                    // made of is known.
                    m.targetIn = number(fu["target_in"])
                    // The macro targets are the server's split, not a second one computed
                    // here — two answers to "what is my protein target" is one too many.
                    if let p = number(fu["protein_g"]) { m.protein = MacroSlot(target: Int(p), eaten: 0) }
                    if let c = number(fu["carb_g"])    { m.carb    = MacroSlot(target: Int(c), eaten: 0) }
                    if let f = number(fu["fat_g"])     { m.fat     = MacroSlot(target: Int(f), eaten: 0) }
                    switch fu["intake_state"] as? String {
                    case "FASTED": m.fuelState = .fasted
                    case "CONFIRMED": m.fuelState = .confirmed
                    case "PARTIAL":
                        let slots = (fu["slot_states"] as? [String: Any])?
                            .filter { ($0.value as? String) == "CONFIRMED" }.count ?? 0
                        m.fuelState = .partial(slots: slots)
                    default: m.fuelState = .unlogged
                    }
                }
                if m.nightInputs != nil, formalMetrics != nil {
                    m.nightInputs?.hrv = formalValue("nightHRV", userDay.key)
                    m.nightInputs?.hrvBase = formalValue("hrvBaseline", userDay.key)
                    m.nightInputs?.rhr = formalValue("nightRHR", userDay.key)
                }
                history.append(m)
            }

            // A just-synced day can have raw_samples before it has a daily_results row.
            // Preserve any local metrics for the two chart days and add only the missing
            // shells; the raw response below will fill their curves.
            for requiredDay in (0...max(days, 1)).map({ day.adding(days: -$0) }) where
                !history.contains(where: { $0.day == requiredDay }) {
                if let existing = store.history.first(where: { $0.day == requiredDay }) {
                    history.append(existing)
                } else if store.today.day == requiredDay {
                    history.append(store.today)
                } else {
                    history.append(DailyMetrics(day: requiredDay))
                }
            }
            history.sort { $0.day < $1.day }

            // The meal list belongs to the same row of truth as the fuel state: if the
            // server says UNLOGGED, an old locally-seeded meal must not survive on screen.
            // 12 · WEEK needs the week's meals, not just today's. Fetched once for the
            // window; `store.meals` stays today's so 09 keeps reading exactly what it did.
            let loadedMeals: [MealEntry] = weekRows.compactMap { row in
                guard let slot = MealEntry.Slot(rawValue: row["slot"] as? String ?? ""),
                      let iso = row["logged_at"] as? String,
                      let at = Self.timestamp(iso),
                      let dayString = row["user_day"] as? String,
                      let date = f.date(from: String(dayString.prefix(10))) else { return nil }
                let d = UserDay(date: Calendar.current.date(
                    bySettingHour: UserDay.boundaryHour, minute: 0, second: 0, of: date) ?? date)
                return MealEntry(
                    id: UUID(uuidString: row["id"] as? String ?? "") ?? UUID(),
                    day: d, at: at, slot: slot, status: .confirmed,
                    text: row["text_input"] as? String ?? "",
                    kcal: number(row["kcal"]) ?? 0,
                    protein: Int(number(row["protein_g"]) ?? 0),
                    carb: Int(number(row["carb_g"]) ?? 0),
                    fat: Int(number(row["fat_g"]) ?? 0),
                    source: .typed)
            }

            // Today's list is the shown day's rows out of the week just fetched — the same
            // columns, the same filter, one fewer request. `store.meals` stays today's so 09
            // keeps reading exactly what it did.
            if day != UserDay.containing(Date()) {
                let loadedDays = Set(loadedMeals.map(\.day))
                store.recentMeals = store.recentMeals.filter { !loadedDays.contains($0.day) } + loadedMeals
            }
            if day == UserDay.containing(Date()) {
                store.recentMeals = loadedMeals
                store.meals = loadedMeals.filter { $0.day == day }
            }

            let curve: [ReserveSample] = sampleRows.compactMap { row in
                guard let t = row["ts"] as? String,
                      let at = Self.timestamp(t),
                      let v = number(row["value"]) else { return nil }
                return ReserveSample(ts: at, value: Int(v))
            }
            if !history.isEmpty { history[history.count - 1].reserveCurve = curve }

            // ⚠️ A tick with neither heart nor stress is the band off the wrist. It is dropped
            // here rather than drawn as a zero, so the two traces stop where the wearing did.
            let vitals: [VitalSample] = vitalRows.compactMap { row in
                guard let t = row["ts"] as? String, let at = Self.timestamp(t) else { return nil }
                let hr = number(row["heart"]).map { Int($0) }
                let stress = number(row["stress"]).map { Int($0) }
                let temp = number(row["temp"])
                let steps = number(row["step"]).map { Int($0) }
                // ⚠️ hrv counts as a reading of its own here. It arrives on its own ten-minute
                // cadence and a tick carrying only HRV is still a tick — dropping it would
                // punch a hole in the very curve it is there to draw.
                let hrv = number(row["hrv"])
                guard hr != nil || stress != nil || temp != nil || steps != nil || hrv != nil
                else { return nil }
                return VitalSample(ts: at, hr: hr, stress: stress,
                                   temp: temp,
                                   steps: steps,
                                   vendorCalories: number(row["cal"]),
                                   dis: number(row["dis"]),
                                   hrv: hrv)
            }
            for index in history.indices {
                let remoteSamples = vitals.filter {
                    $0.ts >= history[index].day.start && $0.ts < history[index].day.end
                }
                let localSamples = store.history.first(where: {
                    $0.day == history[index].day
                })?.vitalsCurve ?? (store.today.day == history[index].day
                    ? store.today.vitalsCurve
                    : [])
                history[index].vitalsCurve = VitalSample.merging(remoteSamples, with: localSamples)
            }

            // Raw device sleep is independent of settled sleepMinutes. A pending formal
            // calculation must not hide a night already received from the band.
            for index in history.indices {
                let key = history[index].day.key
                let local = Self.sleepOnWakeDay(store.metrics(for: history[index].day)?.sleep, day: history[index].day)
                guard let night = nightRows?.first(where: {
                    guard $0["user_day"] as? String == key else { return false }
                    guard let wake = ($0["wake_at"] as? String).flatMap(Self.timestamp) else { return true }
                    return Calendar.current.isDate(wake, inSameDayAs: history[index].day.start)
                }),
                      let total = number(night["total_minutes"]), total.isFinite, total > 0 else {
                    history[index].sleep = local
                    continue
                }
                let line = ((night["sleep_line"] as? String) ?? "").split(separator: ",").compactMap { pair -> SleepStageRun? in
                    let parts = pair.split(separator: ":")
                    guard parts.count == 2, let stage = Int(parts[0]), let minutes = Int(parts[1]), minutes > 0 else { return nil }
                    return SleepStageRun(stage: stage, minutes: minutes)
                }
                let start = (night["sleep_start"] as? String).flatMap(Self.timestamp)
                let wake = (night["wake_at"] as? String).flatMap(Self.timestamp)
                // Cloud publication can lag the completed SDK night. A shorter remote
                // window must not truncate observations already confirmed on this device.
                if let local, let localStart = local.sleepStart, let localWake = local.wakeAt,
                   let start, let wake, localStart <= start, localWake >= wake,
                   (localStart < start || localWake > wake) {
                    history[index].sleep = local
                    continue
                }
                let sameWindow = start != nil && wake != nil && local?.sleepStart == start && local?.wakeAt == wake
                let oxygen = Self.overnightOxygen(rows: oxygenRows, start: start, wake: wake)
                let respiration = Self.sleepRespiration(raw: night["raw"], start: start, wake: wake)
                let hrv = Self.sleepHRV(raw: night["raw"], start: start, wake: wake)
                let rawIntervals = ((night["raw"] as? [String: Any])?["intervals"] as? [[String: Any]] ?? []).compactMap { row -> SleepInterval? in
                    guard let intervalStart = (row["start"] as? String).flatMap(Self.timestamp),
                          let intervalEnd = (row["end"] as? String).flatMap(Self.timestamp),
                          intervalEnd > intervalStart,
                          let start, let wake, intervalStart >= start, intervalEnd <= wake else { return nil }
                    return SleepInterval(start: intervalStart, end: intervalEnd)
                }.sorted { $0.start < $1.start }

                // Absence predates segmented sleep: retain nil so old records use their
                // measured start/wake window. Explicit empty or malformed intervals stay
                // empty; converting them to nil would invent continuous sleep evidence.
                let hasIntervals = (night["raw"] as? [String: Any])?["intervals"] != nil
                let intervals: [SleepInterval]? = hasIntervals ? rawIntervals : sameWindow ? local?.intervals : nil
                let rawLine = ((night["raw"] as? [String: Any])?["line"] as? [[String: Any]] ?? []).compactMap { row -> SleepStageRun? in
                    guard let stage = number(row["stage"]), let minutes = number(row["minutes"]),
                          stage.isFinite, minutes.isFinite, minutes > 0 else { return nil }
                    let offset = number(row["offset_minutes"]).flatMap { $0.isFinite && $0 >= 0 ? Int($0) : nil }
                    return SleepStageRun(stage: Int(stage), minutes: Int(minutes), offsetMinutes: offset)
                }
                func inSleep(_ at: Date) -> Bool {
                    guard let start, let wake, at >= start, at < wake else { return false }
                    guard let intervals else { return true }
                    return intervals.contains { at >= $0.start && at < $0.end }
                }
                let displayLine = !rawLine.isEmpty ? rawLine : sameWindow &&
                    (line.isEmpty || local?.line.contains(where: { $0.offsetMinutes != nil }) == true)
                    ? local?.line ?? [] : line
                // A corrected reading at the same timestamp is one observation. Local
                // observations win while their cloud publication is still catching up.
                let combinedOxygen = Dictionary((oxygen + (sameWindow ? local?.spo2 ?? [] : []))
                    .map { ($0.ts, $0) }, uniquingKeysWith: { _, local in local })
                    .values.filter { inSleep($0.ts) }.sorted { $0.ts < $1.ts }
                let combinedRespiration = Dictionary((respiration + (sameWindow ? local?.respiration ?? [] : []))
                    .map { ($0.ts, $0) }, uniquingKeysWith: { _, local in local })
                    .values.filter { inSleep($0.ts) }.sorted { $0.ts < $1.ts }
                let combinedHRV: [SleepHRVPoint]? = hrv == nil && (!sameWindow || local?.hrv == nil) ? nil :
                    Dictionary(((hrv ?? []) + (sameWindow ? local?.hrv ?? [] : []))
                        .map { ($0.ts, $0) }, uniquingKeysWith: { _, local in local })
                        .values.filter { inSleep($0.ts) }.sorted { $0.ts < $1.ts }
                history[index].sleep = SleepSummary(
                    totalMinutes: Int(total),
                    deepMinutes: number(night["deep_minutes"]).map { Int($0) } ?? 0,
                    lightMinutes: number(night["light_minutes"]).map { Int($0) } ?? 0,
                    wakeCount: number(night["wake_count"]).map { Int($0) } ?? 0,
                    line: displayLine, sleepStart: start, wakeAt: wake,
                    spo2: combinedOxygen,
                    respiration: combinedRespiration,
                    hrv: combinedHRV,
                    intervals: intervals)
            }

            if let live = liveRows.first,
               let at = (live["ts"] as? String).flatMap(Self.timestamp) {
                // ⚠️ The sync writes the tick it just pulled off the band into `store.vitals`
                // before the row has finished its trip through settle_now. The server's answer
                // is the same tick or an older one, never a newer one, so it only overwrites
                // when it is at least as recent — otherwise the panel jumps backwards to the
                // previous tick a second after showing the current one.
                if store.vitals.at == nil || at >= store.vitals.at! {
                    let lastStress = liveStressRows?.first.flatMap { row -> (Int, Date)? in
                        guard let ts = (row["ts"] as? String).flatMap(Self.timestamp),
                              let value = number(row["stress"]).map({ Int($0) }) else { return nil }
                        return (value, ts)
                    }
                    store.vitals = LiveVitals(
                        hr: number(live["heart"]).map { Int($0) },
                        stress: VitalsTimelinePolicy.currentStress(
                            latest: number(live["stress"]).map { Int($0) },
                            previous: lastStress,
                            at: at),
                        at: at)
                }
            }

            // ⚠️ Merge, never replace. A one-day refresh after a band sync calls this with
            // days: 1, and assigning the result would drop the other eighty-three — which
            // is exactly what the week bars and the heat map are made of.
            var merged = store.history.filter { existing in
                !history.contains { $0.day == existing.day }
            }
            merged.append(contentsOf: history)
            merged.sort { $0.day < $1.day }
            store.history = merged
            if let responseRows {
                let loaded = Self.opticalResponse(rows: responseRows)
                if !loaded.isEmpty || store.mealResponsePoints.isEmpty {
                    store.mealResponsePoints = loaded
                }
            }
            if let last = history.first(where: { $0.day == UserDay.containing(Date()) }) {
                // 04 · a slot is open until it has a conclusion — logged or SKIPPED.
                let settled = Set(store.meals.filter { $0.status != .open }.map(\.slot))
                store.today = merge(last, into: store.today,
                                    openSlots: MealEntry.Slot.allCases.count - settled.count)
                store.rebaseBodyBatteryPreview()
            }

            // The macro rows are the day's own meals added up. The targets are computed
            // locally from bodyweight and goal (F2 §04, P → F → C); what was eaten is not
            // a target minus a guess, it is the sum of the rows the user can go and read.
            if day == UserDay.containing(Date()), !store.meals.isEmpty {
                let eatenP = store.meals.reduce(0) { $0 + $1.protein }
                let eatenC = store.meals.reduce(0) { $0 + $1.carb }
                let eatenF = store.meals.reduce(0) { $0 + $1.fat }
                store.today.proteinIn = eatenP
                store.today.carbIn = eatenC
                store.today.fatIn = eatenF
                store.today.protein = store.today.protein.map { MacroSlot(target: $0.target, eaten: eatenP) }
                store.today.carb    = store.today.carb.map    { MacroSlot(target: $0.target, eaten: eatenC) }
                store.today.fat     = store.today.fat.map     { MacroSlot(target: $0.target, eaten: eatenF) }
            }
            // WEIGHT_KG · the most recent weigh-in is what the identity card shows.
            if let latest = weighIns.first, let kg = number(latest["weight_kg"]) {
                store.today.weightKg = kg
            }
            store.weighIns = weighIns.compactMap { row in
                guard let iso = row["measured_at"] as? String,
                      let kg = number(row["weight_kg"]) else { return nil }
                return WeighIn(id: UUID(uuidString: row["id"] as? String ?? "") ?? UUID(),
                               date: Self.timestamp(iso) ?? Date(),
                               weightKg: kg, bodyFatPercent: nil,
                               source: .measured,
                               origin: (row["source"] as? String) == "health" ? .health : .manual)
            }
            store.isOffline = false
            if let account {
                MealQueue.shared.overlayPending(into: store, ownerUserId: account)
                if let detail = store.metrics(for: day) { HomeSnapshot.saveDetail(detail, userId: account) }
            }
            HomeSnapshot.save(from: store)
            await WeighInQueue.shared.flush()
        } catch {
            #if DEBUG
            NSLog("Repository.load failed: %@", "\(error)")
            #endif
            // Offline shows the last row that was successfully stored, with AS OF HH:MM
            // on the card header. The client never computes a substitute.
            if case SupabaseClient.Failure.http(409, _) = error {
                // A concurrent settlement is not a loss of connectivity. Keep the prior
                // coherent snapshot; the next refresh will observe the new revision.
                return
            }
            if isCurrent() { store.isOffline = true }
        }
    }

    /// The server's row wins on every metric it carries; anything it does not carry keeps
    /// the value already on screen rather than blanking.
    /// ⚠️ F2 rule 05 · when the server says UNLOGGED, every number derived from intake goes
    /// back to nil. Carrying a stale 660 forward would put a number on screen that no longer
    /// has a source, which is exactly the failure the ledger exists to prevent.
    private func merge(_ server: DailyMetrics, into local: DailyMetrics,
                       openSlots: Int) -> DailyMetrics {
        var m = server
        m.weightKg = server.weightKg ?? local.weightKg
        m.fatKg = local.fatKg
        m.leanKg = local.leanKg
        m.fatEmaDelta7d = server.fatEmaDelta7d ?? local.fatEmaDelta7d
        m.leanEmaDelta7d = server.leanEmaDelta7d ?? local.leanEmaDelta7d
        m.targetIn = server.targetIn ?? local.targetIn
        m.bmr = server.bmr ?? local.bmr
        m.bmrFull = server.bmrFull ?? local.bmrFull
        m.eActive = server.eActive ?? local.eActive
        m.eTrain = local.eTrain
        // A9 · what the planned session would actually cost this person, from their own
        // weight — never a fixed 480. It is the same session board 08 is offering.
        let gap = (server.targetLoad ?? 0) - (server.trainingLoad ?? 0)
        let plan: (minutes: Double, met: Double)? =
            gap >= 8 ? (45, 6.0) : gap >= 3 ? (30, 6.0) : gap > 0 ? (20, 3.5) : nil
        m.eTrainPlan = plan.flatMap { p in
            m.weightKg.map { (p.met - 1) * 1.05 * $0 * (p.minutes / 60) }
        }
        m.activeForecast = server.activeForecast ?? local.activeForecast
        m.scans7d = server.scans7d > 0 ? server.scans7d : local.scans7d
        m.proteinIn = server.proteinIn
        m.carbIn = server.carbIn
        m.fatIn = server.fatIn
        m.serverCall = server.serverCall ?? local.serverCall
        m.logged7d = local.logged7d
        m.bandCoverage = local.bandCoverage
        m.worn = server.worn ?? local.worn
        m.wearRun = server.wearRun ?? local.wearRun
        m.wearMiss = server.wearMiss ?? local.wearMiss

        // The targets come from the server; only what was eaten is decided here.
        let pTarget = server.protein ?? local.protein
        let cTarget = server.carb ?? local.carb
        let fTarget = server.fat ?? local.fat
        if server.fuelState == .fasted {
            m.proteinIn = 0; m.carbIn = 0; m.fatIn = 0
            m.protein = pTarget.map { MacroSlot(target: $0.target, eaten: 0) }
            m.carb = cTarget.map { MacroSlot(target: $0.target, eaten: 0) }
            m.fat = fTarget.map { MacroSlot(target: $0.target, eaten: 0) }
            m.nextMeal = nil
        } else if case .unlogged = server.fuelState {
            m.protein = pTarget.map { MacroSlot(target: $0.target, eaten: 0) }
            m.carb = cTarget.map { MacroSlot(target: $0.target, eaten: 0) }
            m.fat = fTarget.map { MacroSlot(target: $0.target, eaten: 0) }
            m.nextMeal = nil
        } else {
            m.protein = pTarget
            m.carb = cTarget
            m.fat = fTarget
            // NEXT_MEAL · F2 · the remaining budget divided by the open slots. One open slot
            // left means a plain subtraction; more than one rounds down to 50 and clamps
            // 150–1200.
            // ⚠️ The divisor was missing entirely, so every multi-slot day printed the whole
            // day's remainder as though it were one meal — 1,073 left over two open slots
            // rendered as 1,050 rather than 500. It read like a budget, which is the one
            // thing F2 says this number is not.
            if let target = m.targetIn, let eaten = m.eIn, openSlots > 0 {
                let remaining = target - eaten
                if remaining <= 0 {
                    m.nextMeal = nil
                } else if openSlots == 1 {
                    m.nextMeal = remaining
                } else {
                    let share = remaining / Double(openSlots)
                    m.nextMeal = min(1200, max(150, (share / 50).rounded(.down) * 50))
                }
            } else {
                m.nextMeal = nil
            }
        }
        // ⚠️ Assembled last, and out of exactly the three rows board 10 lists. Computing it
        // earlier meant a later assignment overwrote it and the card's header disagreed
        // with the numbers directly beneath it.
        if let baseline = m.bmrFull {
            m.eOutFull = baseline + (m.activeForecast ?? 0) + (m.eTrainPlan ?? 0)
        }
        return m
    }

    /// Overnight automatic SpO2 clipped to the recorded night. A row written before
    /// `oxygen_samples` existed, or a select that 400s on an unmigrated project, is empty.
    static func overnightOxygen(rows: [[String: Any]]?, start: Date?, wake: Date?) -> [OvernightOxygenPoint] {
        guard let start, let wake, wake > start else { return [] }
        return (rows ?? []).compactMap { row -> OvernightOxygenPoint? in
            guard let at = (row["ts"] as? String).flatMap(Self.timestamp),
                  let percent = numberStatic(row["spo2"]).map({ Int($0) }),
                  (50...100).contains(percent) else { return nil }
            guard at >= start && at < wake else { return nil }
            return OvernightOxygenPoint(ts: at, percent: percent)
        }
    }

    /// Sleep belongs to its calendar wake date, independent of the 04:00 activity cut.
    /// Preserve pre-window legacy records, but never attach a known different night's
    /// measurements to a stale server user_day or a previously mis-keyed local cache.
    private static func sleepOnWakeDay(_ sleep: SleepSummary?, day: UserDay) -> SleepSummary? {
        guard let sleep else { return nil }
        guard let wake = sleep.wakeAt else { return sleep }
        return Calendar.current.isDate(wake, inSameDayAs: day.start) ? sleep : nil
    }

    static func sleepRespiration(raw: Any?, start: Date?, wake: Date?) -> [SleepRespirationPoint] {
        guard let start, let wake, wake > start else { return [] }
        let rows = (raw as? [String: Any])?["respiration"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let at = (row["ts"] as? String).flatMap(Self.timestamp),
                  at >= start, at < wake,
                  let rate = numberStatic(row["breaths_per_minute"]), rate.isFinite,
                  rate > 0, rate < 255 else { return nil }
            return SleepRespirationPoint(ts: at, breathsPerMinute: rate)
        }.sorted { $0.ts < $1.ts }
    }

    /// nil is a legacy row without minute-resolution HRV; [] is an observed empty night.
    static func sleepHRV(raw: Any?, start: Date?, wake: Date?) -> [SleepHRVPoint]? {
        guard let payload = raw as? [String: Any], payload["hrv"] != nil else { return nil }
        guard let start, let wake, wake > start else { return [] }
        let rows = payload["hrv"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let at = (row["ts"] as? String).flatMap(Self.timestamp),
                  at >= start, at < wake,
                  let value = numberStatic(row["rmssd_ms"]), value.isFinite, value > 0 else { return nil }
            return SleepHRVPoint(ts: at, rmssdMS: value)
        }.sorted { $0.ts < $1.ts }
    }

    /// Wrist optical meal-response scalars. The column is `optical`; zeros never arrive.
    static func opticalResponse(rows: [[String: Any]]?) -> [MealResponseIndex.Point] {
        (rows ?? []).compactMap { row -> MealResponseIndex.Point? in
            guard let at = (row["ts"] as? String).flatMap(Self.timestamp),
                  let optical = numberStatic(row["optical"]),
                  optical.isFinite, optical > 0 else { return nil }
            return MealResponseIndex.Point(ts: at, optical: optical)
        }
    }

    private static func numberStatic(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    /// Earliest bind or wrist tick on this account. A later rebind must not win.
    private func loadCompanionSince(into store: DataStore, generation: UInt? = nil,
                                    account: String? = nil) async {
        let generation = generation ?? sessionGeneration
        let account = account ?? SupabaseClient.currentUserIdSnapshot()
        async let bindRows = db.select("devices", query: [
            .init(name: "select", value: "bound_at"),
            .init(name: "order", value: "bound_at.asc"),
            .init(name: "limit", value: "1"),
        ])
        async let sampleRows = db.select("raw_samples", query: [
            .init(name: "select", value: "ts"),
            .init(name: "order", value: "ts.asc"),
            .init(name: "limit", value: "1"),
        ])
        let bindAt = ((try? await bindRows)?.first?["bound_at"] as? String).flatMap(Self.timestamp)
        let sampleAt = ((try? await sampleRows)?.first?["ts"] as? String).flatMap(Self.timestamp)
        guard account != nil, account == SupabaseClient.currentUserIdSnapshot(),
              generation == sessionGeneration else { return }
        if let start = DeviceCompanionMath.start(candidates: [bindAt, sampleAt, store.boundAt]) {
            store.boundAt = start
        }
    }

    /// Current binding start. A new insert that does not echo `bound_at` still started now.
    private func rememberInsertedDevice(_ row: [String: Any]?) {
        if let id = row?["id"] as? String { deviceId = id }
        applyBoundAt(row?["bound_at"], into: DataStore.shared, fallback: Date())
    }

    /// Companionship only moves earlier. A seed rebind must not shrink WITH YOU.
    private func applyBoundAt(_ raw: Any?, into store: DataStore, fallback: Date? = nil) {
        let incoming = (raw as? String).flatMap(Self.timestamp) ?? fallback
        guard let incoming else { return }
        if let existing = store.boundAt {
            if incoming < existing { store.boundAt = incoming }
        } else {
            store.boundAt = incoming
        }
    }

    /// PostgREST hands back fractional seconds and no zone suffix on some columns;
    /// the plain ISO parser rejects both, so try the strict form first and fall back.
    static func timestamp(_ raw: String) -> Date? {
        let strict = ISO8601DateFormatter()
        strict.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = strict.date(from: raw) { return d }
        if let d = ISO8601DateFormatter().date(from: raw) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            f.dateFormat = pattern
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }

    /// Additive server releases may lag an app update. Only a positively identified
    /// missing capability permits legacy reads; authorization and service failures do not.
    static func isMissingReadCapability(_ error: Error, capability: String) -> Bool {
        guard case let SupabaseClient.Failure.http(status, body) = error,
              status == 400 || status == 404 else { return false }
        let text = body.lowercased()
        switch capability {
        case "result_revision":
            return text.contains("result_revision") &&
                (text.contains("42703") || text.contains("does not exist") ||
                 (text.contains("pgrst204") && text.contains("column")))
        case "worn":
            return (text.contains("worn") || text.contains("wear_run") || text.contains("wear_miss")) &&
                (text.contains("42703") || text.contains("does not exist") ||
                 (text.contains("pgrst204") && text.contains("column")))
        case "metric-read":
            return status == 404 && (text.contains("requested function was not found") ||
                text.contains("function not found"))
        case "calculation_status":
            return text.contains("calculation_status") &&
                (text.contains("pgrst202") || text.contains("could not find") ||
                 (text.contains("42883") && text.contains("does not exist")))
        default:
            return false
        }
    }

    private func selectDailyResultsCompat(query: [URLQueryItem]) async throws
        -> (rows: [[String: Any]], versioned: Bool) {
        do {
            return (try await db.select("daily_results", query: query), true)
        } catch {
            if Self.isMissingReadCapability(error, capability: "worn") {
                let withoutWear = query.map { item in
                    item.name == "select" ? URLQueryItem(name: item.name, value:
                        item.value?.split(separator: ",").filter {
                            $0 != "worn" && $0 != "wear_run" && $0 != "wear_miss"
                        }.joined(separator: ",")) : item
                }
                return try await selectDailyResultsCompat(query: withoutWear)
            }
            guard Self.isMissingReadCapability(error, capability: "result_revision") else { throw error }
            let legacy = query.map { item in
                item.name == "select" ? URLQueryItem(name: item.name, value:
                    item.value?.split(separator: ",").filter { $0 != "result_revision" }.joined(separator: ",")) : item
            }
            return (try await db.select("daily_results", query: legacy), false)
        }
    }

    private func applyWear(_ row: [String: Any], to metrics: inout DailyMetrics) {
        if let worn = row["worn"] as? Bool {
            metrics.worn = worn
        } else if let n = number(row["worn"]) {
            metrics.worn = n != 0
        }
        if let n = number(row["wear_run"]) { metrics.wearRun = Int(n) }
        if let n = number(row["wear_miss"]) { metrics.wearMiss = Int(n) }
    }

    private func metricReadIfAvailable(from: String, to: String) async throws -> [String: Any]? {
        do {
            return try await db.callFunction("metric-read", payload: [
                "metrics": ["intakeKcal", "burnKcal", "deltaKcal", "proteinG", "nightHRV", "hrvBaseline", "nightRHR", "sleepMinutes"],
                "from": from, "to": to, "timezone": TimeZone.current.identifier,
            ])
        } catch {
            guard Self.isMissingReadCapability(error, capability: "metric-read") else { throw error }
            return nil
        }
    }

    private func calculationStatusIfAvailable(from: String, to: String) async throws -> [[String: Any]]? {
        do {
            guard let status = try await db.rpc("calculation_status", args: ["p_from": from, "p_to": to]) as? [[String: Any]] else {
                throw SupabaseClient.Failure.http(503, "Invalid calculation status")
            }
            return status
        } catch {
            guard Self.isMissingReadCapability(error, capability: "calculation_status") else { throw error }
            return nil
        }
    }

    private func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private func selectByResultId(_ table: String, columns: String,
                                  ids: [String]) async throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for chunk in Self.resultIdChunks(ids) {
            guard let filter = HomeLaunchPolicy.postgrestIn(chunk) else { continue }
            rows += try await db.select(table, query: [
                .init(name: "select", value: columns),
                .init(name: "result_id", value: filter),
            ])
        }
        return rows
    }

    private func selectTrainingExtras(ids: [String]) async -> [[String: Any]]? {
        let chunks = Self.resultIdChunks(ids)
        guard !chunks.isEmpty else { return [] }
        var rows: [[String: Any]] = []
        for chunk in chunks {
            guard let filter = HomeLaunchPolicy.postgrestIn(chunk) else { continue }
            guard let part = try? await db.select("daily_training", query: [
                .init(name: "select", value: "result_id,active_minutes,distance_m"),
                .init(name: "result_id", value: filter),
            ]) else { return nil }
            rows += part
        }
        return rows
    }

    private static func resultIdChunks(_ ids: [String]) -> [[String]] {
        let clean = ids.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return [] }
        let size = 80
        return stride(from: 0, to: clean.count, by: size).map {
            Array(clean[$0..<min($0 + size, clean.count)])
        }
    }

    /// 10E · every persisted `body_composition` row is a point. Source is not filtered:
    /// a scale reading and a band BIA are both body-fat history.
    private func compositionScans(from rows: [[String: Any]]) -> [CompositionScan] {
        rows.compactMap { row in
            guard let iso = row["measured_at"] as? String, let at = Self.timestamp(iso) else { return nil }
            let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            return CompositionScan(
                id: id,
                at: at,
                bodyFatPercent: number(row["body_fat_pct"]),
                fatMassKg: number(row["fat_mass_kg"]),
                leanMassKg: number(row["lean_body_mass_kg"]),
                bmrKcal: number(row["bmr_kcal"]),
                inputWeightKg: number(row["input_weight_kg"])
            )
        }
        .sorted { $0.at > $1.at }
    }
}
