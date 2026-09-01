import Foundation

/// F3 §05 · reading. The home screen reads one row of daily_results. A detail page reads
/// daily_results plus its detail row, joined by result_id.
/// ⚠️ No detail page ever starts a second computation. If the join misses, the screen
/// degrades in place to "——" — it does not compute a substitute and does not send a second request.
@MainActor
final class Repository {
    static let shared = Repository()

    private let db = SupabaseClient.shared

    /// Signing in to the seeded demo account. In production this is the six-digit code path.
    func signInDemo() async throws {
        try await db.signIn(email: "demo@nextbody.app", password: "nextbody-demo")
    }

    func loadToday(into store: DataStore) async {
        let today = UserDay.containing(Date())
        await loadProfile(into: store)
        await load(days: 84, endingAt: today, into: store)
        await loadComposition(into: store)
    }

    /// The profile exists from onboarding onwards; failing to read it is a serious fault,
    /// so the screen keeps whatever it already had rather than blanking the identity card.
    func loadProfile(into store: DataStore) async {
        guard let row = try? await db.select("profiles", query: [
            .init(name: "select", value: "sex,height_cm,birth_date,goal,units_metric,timezone"),
            .init(name: "limit", value: "1"),
        ]).first else { return }

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

        let iso = ISO8601DateFormatter()
        /// The oldest row at least `daysAgo` old — or, if the history is shorter than that,
        /// the oldest row there is. A net change over "as much history as exists" is honest;
        /// refusing to show one because the window is not full is not.
        func at(daysAgo: Int) -> [String: Any]? {
            let cutoff = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
            let older = rows.first { row in
                guard let s = row["measured_at"] as? String, let d = iso.date(from: s) else { return false }
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
            guard let s = row["measured_at"] as? String, let d = iso.date(from: s) else { return false }
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

    func load(days: Int, endingAt day: UserDay, into store: DataStore) async {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        let from = f.string(from: day.adding(days: -days).start)
        let to = f.string(from: day.start)

        do {
            let rows = try await db.select("daily_results", query: [
                .init(name: "select",
                      value: "id,user_day,training_load,reserve_score,fuel_balance_kcal,daily_direction,the_call,the_call_confidence,computed_at,algo_version"),
                .init(name: "user_day", value: "gte.\(from)"),
                .init(name: "user_day", value: "lte.\(to)"),
                .init(name: "order", value: "user_day.asc"),
            ])
            guard !rows.isEmpty else { return }

            let fuel = try await db.select("day_fuel", query: [
                .init(name: "select", value: "result_id,intake_state,kcal_in,kcal_out,slot_states"),
            ])
            let reserve = try await db.select("reserve_daily", query: [
                .init(name: "select", value: "result_id,wake_value,current_value,min_value,drain_drivers,night_inputs"),
            ])
            let training = try await db.select("daily_training", query: [
                .init(name: "select", value: "result_id,zone_minutes,peak_hr,curve"),
            ])
            let weighIns = try await db.select("weigh_ins", query: [
                .init(name: "select", value: "id,measured_at,weight_kg,source"),
                .init(name: "order", value: "measured_at.desc"),
                .init(name: "limit", value: "60"),
            ])

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
                }
                if let fu = fuelBy[id] {
                    m.eIn = number(fu["kcal_in"])
                    m.eOutNow = number(fu["kcal_out"])
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
            let mealRows = try await db.select("meals", query: [
                .init(name: "select", value: "id,user_day,slot,logged_at,text_input,kcal,protein_g,carb_g,fat_g"),
                .init(name: "deleted_at", value: "is.null"),
                .init(name: "user_day", value: "eq.\(f.string(from: day.start))"),
                .init(name: "order", value: "logged_at.asc"),
            ])
            store.meals = mealRows.compactMap { row in
                guard let slot = MealEntry.Slot(rawValue: row["slot"] as? String ?? ""),
                      let iso = row["logged_at"] as? String,
                      let at = Self.timestamp(iso) else { return nil }
                return MealEntry(
                    id: UUID(uuidString: row["id"] as? String ?? "") ?? UUID(),
                    day: day, at: at, slot: slot, status: .confirmed,
                    text: row["text_input"] as? String ?? "",
                    kcal: number(row["kcal"]) ?? 0,
                    protein: Int(number(row["protein_g"]) ?? 0),
                    carb: Int(number(row["carb_g"]) ?? 0),
                    fat: Int(number(row["fat_g"]) ?? 0),
                    source: .typed)
            }

            // 13 · the curve is 288 five-minute ticks of the shown day, not a shape we draw
            // from the day's endpoints. Bounded by the 04:00 cut like everything else.
            let stamp = ISO8601DateFormatter()
            let sampleRows = try await db.select("reserve_samples", query: [
                .init(name: "select", value: "ts,value"),
                .init(name: "ts", value: "gte.\(stamp.string(from: day.start))"),
                .init(name: "ts", value: "lt.\(stamp.string(from: day.adding(days: 1).start))"),
                .init(name: "order", value: "ts.asc"),
            ])
            let curve: [ReserveSample] = sampleRows.compactMap { row in
                guard let t = row["ts"] as? String,
                      let at = Self.timestamp(t),
                      let v = number(row["value"]) else { return nil }
                return ReserveSample(ts: at, value: Int(v))
            }
            if !history.isEmpty { history[history.count - 1].reserveCurve = curve }

            // 04 · the HR / STRESS row is the last tick, not an average and not a guess.
            let liveRows = try await db.select("raw_samples", query: [
                .init(name: "select", value: "ts,heart,stress"),
                // A tick in the future is a tick the band cannot have reported.
                .init(name: "ts", value: "lte.\(stamp.string(from: Date()))"),
                .init(name: "order", value: "ts.desc"),
                .init(name: "limit", value: "1"),
            ])
            if let live = liveRows.first {
                store.vitals = LiveVitals(
                    hr: number(live["heart"]).map { Int($0) },
                    stress: number(live["stress"]).map { Int($0) },
                    at: (live["ts"] as? String).flatMap(Self.timestamp))
                if let at = store.vitals.at { store.lastSync = at }
            }

            store.history = history
            if let last = history.last { store.today = merge(last, into: store.today) }

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
        } catch {
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
    private func merge(_ server: DailyMetrics, into local: DailyMetrics) -> DailyMetrics {
        var m = server
        m.weightKg = server.weightKg ?? local.weightKg
        m.fatKg = local.fatKg
        m.leanKg = local.leanKg
        m.fatEmaDelta7d = local.fatEmaDelta7d
        m.leanEmaDelta7d = local.leanEmaDelta7d
        m.targetIn = local.targetIn
        m.bmr = local.bmr
        m.eActive = local.eActive
        m.eTrain = local.eTrain
        m.eTrainPlan = local.eTrainPlan
        m.eOutFull = local.eOutFull
        m.activeForecast = local.activeForecast
        m.scans7d = local.scans7d
        m.logged7d = local.logged7d
        m.bandCoverage = local.bandCoverage

        if case .unlogged = server.fuelState {
            m.protein = local.protein.map { MacroSlot(target: $0.target, eaten: 0) }
            m.carb = local.carb.map { MacroSlot(target: $0.target, eaten: 0) }
            m.fat = local.fat.map { MacroSlot(target: $0.target, eaten: 0) }
            m.nextMeal = nil
        } else {
            m.protein = local.protein
            m.carb = local.carb
            m.fat = local.fat
            // NEXT_MEAL · the remaining budget divided by the open slots. One open slot left
            // means a plain subtraction; more than one rounds down to 50 and clamps 150–1200.
            if let target = m.targetIn, let eaten = m.eIn {
                let remaining = target - eaten
                m.nextMeal = remaining > 0 ? min(1200, max(150, (remaining / 50).rounded(.down) * 50)) : nil
            } else {
                m.nextMeal = nil
            }
        }
        return m
    }

    /// PostgREST hands back fractional seconds and no zone suffix on some columns;
    /// the plain ISO parser rejects both, so try the strict form first and fall back.
    private static func timestamp(_ raw: String) -> Date? {
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
