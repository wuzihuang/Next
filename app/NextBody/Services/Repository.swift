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

    func loadToday(into store: DataStore) async {
        let today = UserDay.containing(Date())
        await loadProfile(into: store)
        // 11 · the heat map is twenty-six columns of seven days.
        await load(days: 182, endingAt: today, into: store)
        await loadComposition(into: store)
        await loadCapabilities(into: store)
        await loadLastSync(into: store)
        // Reachability may never change while a user signs out and later returns. Flush the
        // account-owned outboxes on session restore as well as on network transitions.
        await WeighInQueue.shared.flush()
        await BodyCompositionQueue.shared.flush()
    }

    func loadLastSync(into store: DataStore) async {
        guard let rows = try? await db.select("devices", query: [
            .init(name: "select", value: "id,last_origin_sync_at"),
            .init(name: "unbound_at", value: "is.null"),
            .init(name: "limit", value: "1"),
        ]), let row = rows.first else { return }
        if let id = row["id"] as? String { deviceId = id }
        store.lastSync = (row["last_origin_sync_at"] as? String).flatMap(Self.timestamp)
    }

    /// The profile exists from onboarding onwards; failing to read it is a serious fault,
    /// so the screen keeps whatever it already had rather than blanking the identity card.
    func loadProfile(into store: DataStore) async {
        let found = try? await db.select("profiles", query: [
            .init(name: "select", value: "display_name,sex,height_cm,birth_date,goal,units_metric,timezone"),
            .init(name: "limit", value: "1"),
        ]).first
        // The row must exist and carry this phone's zone before anything can be computed.
        await ensureProfileRow(existingTimezone: found?["timezone"] as? String)
        guard let row = found else { return }

        if let name = row["display_name"] as? String, !name.isEmpty { store.profile.name = name }
        if let d = try? await db.select("devices", query: [
            .init(name: "select", value: "id,firmware_version,battery_percent,device_number"),
            // The bound one. A forgotten HOOP keeps its row (12 · "your history stays") and
            // must not lend the header its last battery reading.
            .init(name: "unbound_at", value: "is.null"),
            .init(name: "limit", value: "1"),
        ]).first {
            deviceId = d["id"] as? String
            if let fw = d["firmware_version"] as? String { store.band.firmware = fw }
            if let pct = number(d["battery_percent"]) { store.band.batteryPercent = Int(pct) }
        }
        // The address is whoever is signed in — never a placeholder next to real numbers.
        if let mail = await db.signedInEmail() { store.profile.email = mail }
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
        guard let rows = try? await db.select("body_composition", query: [
            .init(name: "select", value: "measured_at,body_fat_pct,fat_mass_kg,lean_body_mass_kg,measurement_source"),
            .init(name: "order", value: "measured_at.desc"),
            .init(name: "limit", value: "90"),
        ]), let latest = rows.first else { return }

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

    /// The bound HOOP's row. The demo account has one from the seed; a real phone had none —
    /// nothing wrote it after pairing — so `deviceId` stayed nil, sync_runs named no device,
    /// device_capabilities were never stored, and the header's battery came from a mock.
    /// One bound row per user (unbound_at is null): patched when it exists, inserted when not.
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
        do {
            let bound = try await db.select("devices", query: [
                .init(name: "select", value: "id"),
                .init(name: "unbound_at", value: "is.null"),
                .init(name: "limit", value: "1"),
            ]).first
            if let id = bound?["id"] as? String {
                deviceId = id
                if !row.isEmpty { _ = try await db.patch("devices", id: id, row: row) }
            } else if let ble = identity?.bleIdentifier ?? BoundBand.identifier {
                row["user_id"] = userId
                row["ble_identifier"] = ble
                row["ble_identifier_kind"] = "uuid"
                deviceId = try await db.insert("devices", row: row).first?["id"] as? String
            }
        } catch {
            #if DEBUG
            NSLog("Repository.registerDevice failed: %@", "\(error)")
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
        BodyCompositionQueue.shared.enqueue(r, at: date, ownerUserId: userId)
    }

    func load(days: Int, endingAt day: UserDay, into store: DataStore) async {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        let from = f.string(from: day.adding(days: -days).start)
        let to = f.string(from: day.start)

        do {
            let rows = try await db.select("daily_results", query: [
                .init(name: "select",
                      value: "id,user_day,training_load,reserve_score,fuel_balance_kcal,daily_direction,the_call,the_call_confidence,fat_delta_7d,lean_delta_7d,scans_7d,computed_at,algo_version"),
                .init(name: "user_day", value: "gte.\(from)"),
                .init(name: "user_day", value: "lte.\(to)"),
                .init(name: "order", value: "user_day.asc"),
            ])
            #if DEBUG
            NSLog("Repository.load: %d daily_results rows", rows.count)
            #endif
            guard !rows.isEmpty else { return }

            // ⚠️ These eight were awaited one after another: nine round trips end to end, and
            // the screen sat on all nine every time a band sync settled. Not one of them reads
            // another's answer — only `daily_results` above had to come first, because an
            // empty day means none of the rest is worth asking for. Fired together they cost
            // one round trip's wall clock instead of eight.
            let stamp = ISO8601DateFormatter()
            async let fuelRows = db.select("day_fuel", query: [
                .init(name: "select", value: "result_id,intake_state,kcal_in,kcal_out,slot_states,bmr_kcal,active_kcal,bmr_full_kcal,target_in,protein_g,fat_g,carb_g,protein_in_g,carb_in_g,fat_in_g,weight_kg"),
            ])
            async let reserveRows = db.select("reserve_daily", query: [
                .init(name: "select", value: "result_id,wake_value,current_value,min_value,drain_drivers,night_inputs"),
            ])
            async let trainingRows = db.select("daily_training", query: [
                .init(name: "select", value: "result_id,zone_minutes,peak_hr,curve,segments"),
            ])
            // 补屏 B · active_minutes / distance_m arrive with migration 20260902040000. Asked
            // for separately so a project without them still loads the day — naming an
            // unknown column is a 400 for the whole select, and that 400 took the home
            // screen offline.
            async let trainingExtras = try? await db.select("daily_training", query: [
                .init(name: "select", value: "result_id,active_minutes,distance_m"),
            ])
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
                .init(name: "user_day", value: "gte.\(f.string(from: day.adding(days: -6).start))"),
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
            async let vitalRowsAsync = db.select("raw_samples", query: [
                .init(name: "select", value: "ts,heart,stress,temp,step,cal,dis,hrv"),
                .init(name: "ts", value: "gte.\(stamp.string(from: day.start))"),
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
                m.balance = number(row["fuel_balance_kcal"])
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
                if let iso = row["computed_at"] as? String {
                    m.asOf = Self.timestamp(iso)
                }

                if let r = reserveBy[id] {
                    m.bbWake = number(r["wake_value"]).map { Int($0) }
                    m.bodyBattery = number(r["current_value"]).map { Int($0) }
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
                    m.eIn = number(fu["kcal_in"])
                    m.eOutNow = number(fu["kcal_out"])
                    m.proteinIn = number(fu["protein_in_g"]).map { Int($0) }
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
                history.append(m)
            }

            // The meal list belongs to the same row of truth as the fuel state: if the
            // server says UNLOGGED, an old locally-seeded meal must not survive on screen.
            // 12 · WEEK needs the week's meals, not just today's. Fetched once for the
            // window; `store.meals` stays today's so 09 keeps reading exactly what it did.
            let weekRows = try await weekMealRows
            store.recentMeals = weekRows.compactMap { row in
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
            store.meals = store.recentMeals.filter { $0.day == day }

            let sampleRows = try await sampleRowsAsync
            let curve: [ReserveSample] = sampleRows.compactMap { row in
                guard let t = row["ts"] as? String,
                      let at = Self.timestamp(t),
                      let v = number(row["value"]) else { return nil }
                return ReserveSample(ts: at, value: Int(v))
            }
            if !history.isEmpty { history[history.count - 1].reserveCurve = curve }

            // ⚠️ A tick with neither heart nor stress is the band off the wrist. It is dropped
            // here rather than drawn as a zero, so the two traces stop where the wearing did.
            let vitalRows = try await vitalRowsAsync
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
                                   cal: number(row["cal"]),
                                   dis: number(row["dis"]),
                                   hrv: hrv)
            }
            if !history.isEmpty { history[history.count - 1].vitalsCurve = vitals }

            // 04B · SLEEP card. The night OriginDataSync stored under this user day. Asked on
            // its own and swallowed on failure — a project without the table must still load,
            // and a night the band has not answered is a "——", not an error.
            if !history.isEmpty,
               let nightRows = try? await db.select("sleep_nights", query: [
                   .init(name: "select", value: "user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_line"),
                   .init(name: "user_day", value: "eq.\(f.string(from: day.start))"),
                   .init(name: "limit", value: "1"),
               ]),
               let night = nightRows.first, let total = number(night["total_minutes"]) {
                // 04B rule 04 · the band's own staging, stored as "stage:minutes" runs. A row
                // from before the column existed reads as no line, and the strip falls back
                // to the totals.
                let line = ((night["sleep_line"] as? String) ?? "").split(separator: ",").compactMap { pair -> SleepStageRun? in
                    let parts = pair.split(separator: ":")
                    guard parts.count == 2, let stage = Int(parts[0]), let minutes = Int(parts[1]), minutes > 0 else { return nil }
                    return SleepStageRun(stage: stage, minutes: minutes)
                }
                history[history.count - 1].sleep = SleepSummary(
                    totalMinutes: Int(total),
                    deepMinutes: number(night["deep_minutes"]).map { Int($0) } ?? 0,
                    lightMinutes: number(night["light_minutes"]).map { Int($0) } ?? 0,
                    wakeCount: number(night["wake_count"]).map { Int($0) } ?? 0,
                    line: line)
            }

            let liveRows = try await liveRowsAsync
            if let live = liveRows.first,
               let at = (live["ts"] as? String).flatMap(Self.timestamp) {
                // ⚠️ The sync writes the tick it just pulled off the band into `store.vitals`
                // before the row has finished its trip through settle_now. The server's answer
                // is the same tick or an older one, never a newer one, so it only overwrites
                // when it is at least as recent — otherwise the panel jumps backwards to the
                // previous tick a second after showing the current one.
                if store.vitals.at == nil || at >= store.vitals.at! {
                    store.vitals = LiveVitals(
                        hr: number(live["heart"]).map { Int($0) },
                        stress: number(live["stress"]).map { Int($0) },
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
            if let last = history.last {
                // 04 · a slot is open until it has a conclusion — logged or SKIPPED.
                let settled = Set(store.meals.filter { $0.status != .open }.map(\.slot))
                store.today = merge(last, into: store.today,
                                    openSlots: MealEntry.Slot.allCases.count - settled.count)
            }

            // The macro rows are the day's own meals added up. The targets are computed
            // locally from bodyweight and goal (F2 §04, P → F → C); what was eaten is not
            // a target minus a guess, it is the sum of the rows the user can go and read.
            if !store.meals.isEmpty {
                let eatenP = store.meals.reduce(0) { $0 + $1.protein }
                let eatenC = store.meals.reduce(0) { $0 + $1.carb }
                let eatenF = store.meals.reduce(0) { $0 + $1.fat }
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
            await WeighInQueue.shared.flush()
        } catch {
            #if DEBUG
            NSLog("Repository.load failed: %@", "\(error)")
            #endif
            // Offline shows the last row that was successfully stored, with AS OF HH:MM
            // on the card header. The client never computes a substitute.
            store.isOffline = true
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

        // The targets come from the server; only what was eaten is decided here.
        let pTarget = server.protein ?? local.protein
        let cTarget = server.carb ?? local.carb
        let fTarget = server.fat ?? local.fat
        if case .unlogged = server.fuelState {
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

    private func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }
}
