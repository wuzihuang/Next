import Foundation

/// Homepage V2 · Planet / Body / Instruments.
///
/// Numbers come from the day the band and the meal ledger already settled.
/// A missing input stays nil so the screen can print ——. Nothing here invents
/// a calorie, a glow, or a delta to fill an empty slot.
enum HomeV2Model {
    static let macroHitFraction = 0.95

    enum FoodFace: String, Equatable {
        case unlogged = "A"
        case recovery = "B"
        case complete = "C"
        case remaining = "D"
    }

    enum ReadinessBand: Equatable {
        case unknown, recover, steady, peak
    }

    struct Macro: Equatable {
        var eaten: Int?
        var target: Int?

        var left: Int? {
            guard let eaten, let target else { return nil }
            return target - eaten
        }

        /// Met when intake reaches 95% of the target. 118/120 is a hit; 96/120 is not.
        var met: Bool {
            guard let eaten, let target, target > 0 else { return false }
            return Double(eaten) >= Double(target) * HomeV2Model.macroHitFraction
        }
    }

    struct Food: Equatable {
        var face: FoodFace
        var meals: Int
        var eatenKcal: Int?
        var targetKcal: Int?
        var protein: Macro
        var carb: Macro
        var fat: Macro
        /// Guide copy. Present only while nothing has been logged.
        var guide: String?

        var kcalLeft: Int? {
            guard let eatenKcal, let targetKcal else { return nil }
            return targetKcal - eatenKcal
        }

        var kcalMet: Bool {
            guard let eatenKcal, let targetKcal, targetKcal > 0 else { return false }
            return Double(eatenKcal) >= Double(targetKcal) * HomeV2Model.macroHitFraction
        }
    }

    struct Planet: Equatable {
        var readiness: Int?
        var vsAverage: Int?
        var band: ReadinessBand
        var orbitPlace: String
        var orbitState: String
        var statusWord: String
        var statusPhrase: String
        var sleepScore: Int?
        var sleepMinutes: Int?
        var sleepDeepMinutes: Int?
        var sleepFoot: String
        var load: Double?
        var loadTarget: Double?
        var food: Food
    }

    struct BodyGlow: Equatable {
        var lit: Bool
        /// 0.35…1 when the domain has data. 0 when it does not.
        var intensity: Double
        var eyebrow: String
        var value: String
    }

    struct BodyMetric: Equatable, Identifiable {
        var id: String
        var label: String
        var value: String
        var unit: String
        var delta: String
        var tint: Tint
        enum Tint: Equatable { case lime, violet, ember, cyan, white }
    }

    struct Body: Equatable {
        var scannedAt: Date?
        var head: BodyGlow
        var chest: BodyGlow
        var gut: BodyGlow
        var primary: [BodyMetric]
        var more: [BodyMetric]
    }

    enum Zone: String, Equatable, Identifiable {
        case head, chest, gut
        var id: String { rawValue }
    }

    struct Stat: Equatable, Identifiable {
        var id: String
        var label: String
        var value: String
        var unit: String
        var foot: String
    }

    struct Detail: Equatable {
        var zone: Zone
        var eyebrow: String
        var hero: String
        var heroUnit: String
        var aside: String
        var verdict: String
        var stats: [Stat]
        var noteLabel: String
        var note: String?
    }

    enum TimelineAccent: Equatable {
        case now, meal, stress, workout, sleep, sync
    }

    struct TimelineMeal: Equatable {
        var kcal: Int
        var protein: Int
        var carb: Int
        var fat: Int
    }

    struct TimelineItem: Equatable, Identifiable {
        var id: String
        var at: Date
        var title: String
        var detail: String
        var accent: TimelineAccent
        var meal: TimelineMeal?
        var trailing: String?
    }

    /// The page a home card opens. Empty numbers still open it — the detail
    /// page is where a missing night or an unlogged day is allowed to say so.
    static func destination(for zone: Zone) -> Destination {
        switch zone {
        case .head: return .vitals(.sleep)
        case .chest: return .bodyBattery
        case .gut: return .fuel
        }
    }

    static func destination(for accent: TimelineAccent) -> Destination {
        switch accent {
        case .now: return .vitals(.heart)
        case .meal: return .fuel
        case .stress: return .vitals(.stress)
        case .workout: return .training
        case .sleep: return .vitals(.sleep)
        case .sync: return .device
        }
    }

    static func planet(metrics: DailyMetrics, history: [DailyMetrics], meals: [MealEntry]) -> Planet {
        let readiness = metrics.bodyBatteryForDisplay()
        let band = readinessBand(readiness)
        let food = food(metrics: metrics, meals: meals)
        let orbit = orbit(band: band, food: food)
        let status = status(band: band)
        let night = metrics.sleep
        return Planet(
            readiness: readiness,
            vsAverage: versusAverage(readiness, history: history),
            band: band,
            orbitPlace: orbit.place,
            orbitState: orbit.state,
            statusWord: status.word,
            statusPhrase: status.phrase,
            sleepScore: metrics.sleepScore?.score,
            sleepMinutes: night?.totalMinutes,
            sleepDeepMinutes: night.map { $0.deepMinutes > 0 ? $0.deepMinutes : nil } ?? nil,
            sleepFoot: sleepFoot(night: night, score: metrics.sleepScore?.score),
            load: metrics.trainingLoad,
            loadTarget: metrics.targetLoad,
            food: food)
    }

    static func readinessBand(_ score: Int?) -> ReadinessBand {
        guard let score else { return .unknown }
        if score < 50 { return .recover }
        if score >= 80 { return .peak }
        return .steady
    }

    static func versusAverage(_ score: Int?, history: [DailyMetrics]) -> Int? {
        guard let score else { return nil }
        let prior = history.compactMap { $0.bbWake ?? $0.bodyBattery }
        guard prior.count >= 3 else { return nil }
        let mean = Double(prior.reduce(0, +)) / Double(prior.count)
        return Int((Double(score) - mean).rounded())
    }

    static func orbit(band: ReadinessBand, food: Food) -> (place: String, state: String) {
        if band == .recover {
            return (L("LOW ORBIT"), L("RECOVERY HOLD"))
        }
        if food.face == .complete {
            return (L("ORBIT LOCKED"), L("ALL TARGETS MET"))
        }
        return (L("HOME BASE"), L("STEADY"))
    }

    static func status(band: ReadinessBand) -> (word: String, phrase: String) {
        switch band {
        case .recover: return (L("RECOVER"), L("REST TODAY"))
        case .peak: return (L("PEAK"), L("FULL CHARGE"))
        case .steady: return (L("STEADY"), L("READY TO TRAIN"))
        case .unknown: return (Fmt.dash, Fmt.dash)
        }
    }

    static func sleepFoot(night: SleepSummary?, score: Int?) -> String {
        if let deep = night?.deepMinutes, deep > 0 { return L("DEEP %@", Fmt.duration(deep)) }
        if let score, score >= 85 { return L("OPTIMAL") }
        if let minutes = night?.totalMinutes, minutes < 7 * 60 { return L("SHORT") }
        if night == nil { return L("NO NIGHT YET") }
        return Fmt.dash
    }

    static func food(metrics: DailyMetrics, meals: [MealEntry]) -> Food {
        let plates = meals.filter { $0.day == metrics.day && $0.status == .confirmed }
        let rawAllowance = metrics.targetBasis
            ?? metrics.bmrFull.map { $0 + (metrics.eActive ?? 0) }
            ?? metrics.targetIn
        let targetKcal = rawAllowance.map { Int($0.rounded()) }
        let proteinTarget = metrics.protein?.target
        let carbTarget = metrics.carb?.target
        let fatTarget = metrics.fat?.target
        let logged = intake(metrics: metrics, plates: plates)
        let protein = Macro(eaten: logged.logged ? logged.protein : nil, target: proteinTarget)
        let carb = Macro(eaten: logged.logged ? logged.carb : nil, target: carbTarget)
        let fat = Macro(eaten: logged.logged ? logged.fat : nil, target: fatTarget)
        let face: FoodFace
        if !logged.logged {
            face = readinessBand(metrics.bodyBatteryForDisplay()) == .recover ? .recovery : .unlogged
        } else if protein.met && carb.met && fat.met {
            face = .complete
        } else {
            face = .remaining
        }
        let guide: String?
        switch face {
        case .unlogged, .recovery:
            guide = L("Connect MCP, then type what you eat in your personal agent.")
        case .complete, .remaining:
            guide = nil
        }
        return Food(
            face: face,
            meals: plates.count,
            eatenKcal: logged.logged ? logged.kcal : nil,
            targetKcal: targetKcal,
            protein: protein,
            carb: carb,
            fat: fat,
            guide: guide)
    }

    private struct Intake {
        var logged: Bool
        var kcal: Int?
        var protein: Int?
        var carb: Int?
        var fat: Int?
    }

    /// Confirmed plates win. A fasted day is a real zero. Server totals are used only
    /// when the day is marked logged and no plate rows are on the phone.
    private static func intake(metrics: DailyMetrics, plates: [MealEntry]) -> Intake {
        if !plates.isEmpty {
            return Intake(
                logged: true,
                kcal: Int(plates.reduce(0) { $0 + $1.kcal }.rounded()),
                protein: Int(plates.reduce(0) { $0 + $1.protein }.rounded()),
                carb: Int(plates.reduce(0) { $0 + $1.carb }.rounded()),
                fat: Int(plates.reduce(0) { $0 + $1.fat }.rounded()))
        }
        if metrics.fuelState == .fasted {
            return Intake(logged: true, kcal: 0, protein: 0, carb: 0, fat: 0)
        }
        guard metrics.fuelState != .unlogged,
              metrics.eIn != nil || metrics.proteinIn != nil else {
            return Intake(logged: false, kcal: nil, protein: nil, carb: nil, fat: nil)
        }
        return Intake(
            logged: true,
            kcal: metrics.eIn.map { Int($0.rounded()) },
            protein: metrics.proteinIn,
            carb: metrics.carbIn,
            fat: metrics.fatIn)
    }

    static func body(metrics: DailyMetrics, history: [DailyMetrics], meals: [MealEntry],
                     scans: [CompositionScan], heightCm: Double) -> Body {
        let food = food(metrics: metrics, meals: meals)
        let night = metrics.sleep
        let readiness = metrics.bodyBatteryForDisplay()
        let latest = scans.max { $0.at < $1.at }
        let head = headGlow(night: night)
        let chest = chestGlow(readiness: readiness, band: readinessBand(readiness))
        let gut = gutGlow(food: food)
        let fields = compositionFields(latest: latest, scans: scans, heightCm: heightCm)
        return Body(
            scannedAt: latest?.at,
            head: head,
            chest: chest,
            gut: gut,
            primary: [fields.fat, fields.muscle, fields.lean],
            more: [fields.fatMass, fields.water, fields.protein, fields.bone, fields.bmr, fields.bmi])
    }

    static func headGlow(night: SleepSummary?) -> BodyGlow {
        guard let minutes = night?.totalMinutes, minutes > 0 else {
            return BodyGlow(lit: false, intensity: 0, eyebrow: L("HEAD"), value: Fmt.dash)
        }
        let hours = Double(minutes) / 60
        let bend = min(1, abs(hours - 7.5) / 3)
        return BodyGlow(lit: true, intensity: 0.4 + 0.6 * bend,
                        eyebrow: L("HEAD"), value: L("SLEPT %@", sleepHours(minutes)))
    }

    static func chestGlow(readiness: Int?, band: ReadinessBand) -> BodyGlow {
        guard let readiness else {
            return BodyGlow(lit: false, intensity: 0, eyebrow: L("CHEST"), value: Fmt.dash)
        }
        let word: String
        switch band {
        case .recover: word = L("REST")
        case .peak: word = L("RECOVERED")
        case .steady: word = L("STEADY")
        case .unknown: word = Fmt.dash
        }
        let bend = min(1, abs(Double(readiness) - 75) / 40)
        return BodyGlow(lit: true, intensity: 0.4 + 0.6 * bend, eyebrow: L("CHEST"), value: word)
    }

    static func gutGlow(food: Food) -> BodyGlow {
        guard food.face == .complete || food.face == .remaining,
              let eaten = food.eatenKcal, let target = food.targetKcal, target > 0 else {
            return BodyGlow(lit: false, intensity: 0, eyebrow: L("GUT"), value: Fmt.dash)
        }
        let delta = eaten - target
        let bend = min(1, abs(Double(delta)) / Double(target))
        let text = delta == 0 ? L("ON ALLOWANCE") : L("%@ KCAL", Fmt.signedKcal(Double(delta)))
        return BodyGlow(lit: true, intensity: 0.4 + 0.6 * bend, eyebrow: L("GUT"), value: text)
    }

    /// The nine figures the band's BIA scan really returns, drawn from the latest scan only.
    /// Weight is not here: the band has no scale, so it is the weight we sent down, not a result.
    struct CompositionFields {
        var fat: BodyMetric
        var muscle: BodyMetric
        var lean: BodyMetric
        var fatMass: BodyMetric
        var water: BodyMetric
        var bone: BodyMetric
        var protein: BodyMetric
        var bmr: BodyMetric
        var bmi: BodyMetric
    }

    static func compositionFields(latest: CompositionScan?, scans: [CompositionScan],
                                  heightCm: Double) -> CompositionFields {
        let prior = scans.filter { scan in
            guard let latest else { return false }
            return scan.at <= latest.at.addingTimeInterval(-30 * 24 * 3600)
        }.max { $0.at < $1.at }
        func bmi(_ scan: CompositionScan?) -> Double? {
            guard let weight = scan?.inputWeightKg, heightCm > 0 else { return nil }
            let metres = heightCm / 100
            return weight / (metres * metres)
        }
        func metric(_ id: String, _ label: String, _ unit: String, tint: BodyMetric.Tint,
                    _ now: Double?, _ then: Double?, digits: Int = 1) -> BodyMetric {
            let change = (now != nil && then != nil)
                ? L("%@ / 30D", Fmt.signedKg(now! - then!, decimals: digits)) : L("—— / 30D")
            let value = digits == 0 ? now.map { Fmt.kcal($0) } : now.map { Fmt.kg($0) }
            return BodyMetric(id: id, label: label, value: value ?? Fmt.dash, unit: unit,
                              delta: change, tint: tint)
        }
        return CompositionFields(
            fat: metric("fat", L("BODY FAT"), "%", tint: .violet,
                        latest?.bodyFatPercent, prior?.bodyFatPercent),
            muscle: metric("muscle", L("MUSCLE"), L("KG"), tint: .lime,
                           latest?.muscleMassKg, prior?.muscleMassKg),
            lean: metric("lean", L("LEAN MASS"), L("KG"), tint: .lime,
                         latest?.leanMassKg, prior?.leanMassKg),
            fatMass: metric("fatMass", L("FAT MASS"), L("KG"), tint: .violet,
                            latest?.fatMassKg, prior?.fatMassKg),
            water: metric("water", L("WATER"), "%", tint: .cyan,
                          latest?.bodyWaterPercent, prior?.bodyWaterPercent),
            bone: metric("bone", L("BONE"), L("KG"), tint: .cyan,
                         latest?.boneMassKg, prior?.boneMassKg),
            protein: metric("protein", L("PROTEIN"), "%", tint: .cyan,
                            latest?.proteinPercent, prior?.proteinPercent),
            bmr: metric("bmr", L("BMR"), "", tint: .white,
                        latest?.bmrKcal, prior?.bmrKcal, digits: 0),
            bmi: metric("bmi", L("BMI"), "", tint: .white, bmi(latest), bmi(prior)))
    }

    static func detail(zone: Zone, metrics: DailyMetrics, history: [DailyMetrics], meals: [MealEntry]) -> Detail {
        switch zone {
        case .head: return sleepDetail(metrics: metrics, history: history)
        case .chest: return recoveryDetail(metrics: metrics)
        case .gut: return foodDetail(metrics: metrics, meals: meals)
        }
    }

    static func sleepDetail(metrics: DailyMetrics, history: [DailyMetrics]) -> Detail {
        let night = metrics.sleep
        let minutes = night?.totalMinutes
        let prior = history.compactMap { $0.sleep?.totalMinutes }
        let versus: String = {
            guard let minutes, prior.count >= 3 else { return Fmt.dash }
            let mean = Double(prior.reduce(0, +)) / Double(prior.count)
            let delta = Int((Double(minutes) - mean).rounded())
            return L("%@ VS AVG", Fmt.signed(Double(delta) / 60))
        }()
        let verdict = (minutes ?? 0) > 0 && (minutes ?? 0) < 7 * 60 ? L("SHORT ON SLEEP") : L("LAST NIGHT")
        let hrv = metrics.nightInputs?.hrv
        let rhr = metrics.nightInputs?.rhr
        let hrvBase = metrics.nightInputs?.hrvBase
        let rhrBase = metrics.nightInputs?.rhrBase
        var note: String?
        if let minutes {
            let shortNights = ([minutes] + prior.prefix(1)).filter { $0 < 7 * 60 }.count
            if shortNights >= 2 {
                note = L("Two short nights in a row. Last night was %@.", Fmt.duration(minutes))
            } else {
                note = L("Last night was %@.", Fmt.duration(minutes))
            }
        }
        return Detail(
            zone: .head,
            eyebrow: L("LAST NIGHT"),
            hero: minutes.map { sleepHours($0) } ?? Fmt.dash,
            heroUnit: L("H"),
            aside: versus,
            verdict: verdict,
            stats: [
                Stat(id: "deep", label: L("DEEP SLEEP"), value: night.map { sleepHours($0.deepMinutes) } ?? Fmt.dash,
                     unit: L("H"), foot: averageFoot(night?.deepMinutes, history.compactMap { $0.sleep?.deepMinutes })),
                Stat(id: "rem", label: L("REM"),
                     value: night.flatMap { $0.line.isEmpty ? nil : sleepHours($0.remMinutes) } ?? Fmt.dash,
                     unit: L("H"), foot: averageFoot(night?.remMinutes, history.compactMap { $0.sleep?.remMinutes })),
                Stat(id: "debt", label: L("SLEEP DEBT"), value: Fmt.dash, unit: L("H"), foot: Fmt.dash),
                Stat(id: "hrv", label: L("HRV"), value: hrv.map { String(Int($0.rounded())) } ?? Fmt.dash,
                     unit: L("MS"), foot: deltaFoot(hrv, hrvBase, unit: L("MS"))),
                Stat(id: "rhr", label: L("RESTING HR"), value: rhr.map { String(Int($0.rounded())) } ?? Fmt.dash,
                     unit: L("BPM"), foot: deltaFoot(rhr, rhrBase, unit: L("BPM"))),
                Stat(id: "bed", label: L("BEDTIME"), value: night?.sleepStart.map { Fmt.clock($0) } ?? Fmt.dash,
                     unit: "", foot: bedtimeFoot(night?.sleepStart)),
            ],
            noteLabel: L("TONIGHT"),
            note: note)
    }

    static func recoveryDetail(metrics: DailyMetrics) -> Detail {
        let readiness = metrics.bodyBatteryForDisplay()
        let band = readinessBand(readiness)
        let status = status(band: band)
        let breath = metrics.sleep?.respiration?.map(\.breathsPerMinute)
        let breathMean = breath.flatMap { points -> Double? in
            guard !points.isEmpty else { return nil }
            return points.reduce(0, +) / Double(points.count)
        }
        let hrv = metrics.nightInputs?.hrv
        let rhr = metrics.nightInputs?.rhr
        var note: String?
        if let readiness {
            note = L("Readiness is %d.", readiness)
        }
        return Detail(
            zone: .chest,
            eyebrow: L("RECOVERY · TODAY"),
            hero: readiness.map(String.init) ?? Fmt.dash,
            heroUnit: "",
            aside: Fmt.dash,
            verdict: status.phrase,
            stats: [
                Stat(id: "hrv", label: L("HRV"), value: hrv.map { String(Int($0.rounded())) } ?? Fmt.dash,
                     unit: L("MS"), foot: deltaFoot(hrv, metrics.nightInputs?.hrvBase, unit: L("MS"))),
                Stat(id: "rhr", label: L("RESTING HR"), value: rhr.map { String(Int($0.rounded())) } ?? Fmt.dash,
                     unit: L("BPM"), foot: deltaFoot(rhr, metrics.nightInputs?.rhrBase, unit: L("BPM"))),
                Stat(id: "breath", label: L("BREATH / MIN"), value: breathMean.map { String(format: "%.1f", $0) } ?? Fmt.dash,
                     unit: "", foot: breathMean == nil ? Fmt.dash : L("STEADY")),
                Stat(id: "strain", label: L("STRAIN"), value: Fmt.load(metrics.trainingLoad),
                     unit: "/21", foot: L("TODAY")),
                Stat(id: "steps", label: L("STEPS"), value: Fmt.kcal(metrics.steps.map(Double.init)),
                     unit: "", foot: Fmt.dash),
                Stat(id: "active", label: L("ACTIVE"), value: Fmt.kcal(metrics.eActive),
                     unit: L("KCAL"), foot: metrics.eActive == nil ? Fmt.dash : L("TODAY")),
            ],
            noteLabel: L("TODAY"),
            note: note)
    }

    static func foodDetail(metrics: DailyMetrics, meals: [MealEntry]) -> Detail {
        let deck = food(metrics: metrics, meals: meals)
        let plates = meals.filter { $0.day == metrics.day && $0.status == .confirmed }
        let last = plates.max { $0.at < $1.at }
        let delta = deck.kcalLeft.map { -$0 }
        let verdict: String = {
            guard let delta else { return Fmt.dash }
            if delta > Int(Double(deck.targetKcal ?? 0) * 0.02) { return L("OVER ALLOWANCE") }
            if delta < 0 { return L("UNDER ALLOWANCE") }
            return L("ON ALLOWANCE")
        }()
        var note: String?
        if let eaten = deck.eatenKcal, let target = deck.targetKcal {
            note = L("Eaten %@ of %@ kcal.", Fmt.kcal(Double(eaten)), Fmt.kcal(Double(target)))
        }
        return Detail(
            zone: .gut,
            eyebrow: L("EATEN TODAY"),
            hero: delta.map { Fmt.signedKcal(Double($0)) } ?? Fmt.dash,
            heroUnit: L("KCAL"),
            aside: "",
            verdict: verdict,
            stats: [
                Stat(id: "kcal", label: L("KCAL EATEN"), value: Fmt.kcal(deck.eatenKcal.map(Double.init)),
                     unit: "", foot: deck.targetKcal.map { L("ALLOWANCE %@", Fmt.kcal(Double($0))) } ?? Fmt.dash),
                Stat(id: "protein", label: L("PROTEIN"), value: Fmt.int(deck.protein.eaten),
                     unit: L("G"), foot: macroFoot(deck.protein)),
                Stat(id: "carbs", label: L("CARBS"), value: Fmt.int(deck.carb.eaten),
                     unit: L("G"), foot: macroFoot(deck.carb)),
                Stat(id: "fat", label: L("FAT"), value: Fmt.int(deck.fat.eaten),
                     unit: L("G"), foot: macroFoot(deck.fat)),
                Stat(id: "last", label: L("LAST MEAL"), value: last.map { Fmt.clock($0.at) } ?? Fmt.dash,
                     unit: "", foot: last.map { mealLate($0.at) ? L("LATE") : L("TODAY") } ?? Fmt.dash),
                Stat(id: "meals", label: L("MEALS"), value: deck.face == .unlogged || deck.face == .recovery ? Fmt.dash : String(deck.meals),
                     unit: "", foot: L("TODAY")),
            ],
            noteLabel: L("TODAY"),
            note: note)
    }

    static func timeline(day: UserDay, metrics: DailyMetrics, history: [DailyMetrics],
                         meals: [MealEntry], recaps: [SportSessionRecap], lastSync: Date?,
                         earlier: Bool, now: Date = Date()) -> [TimelineItem] {
        let days = earlier ? day.rollingBack(7) : [day]
        let pool = [metrics] + history
        var items: [TimelineItem] = []
        for row in pool where days.contains(row.day) {
            items += dayItems(metrics: row, meals: meals, recaps: recaps, lastSync: lastSync, now: now)
            for segment in row.segments where !segment.allDay {
                items.append(segmentItem(segment))
            }
        }
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
            .sorted { $0.at > $1.at }
    }

    private static func dayItems(metrics: DailyMetrics, meals: [MealEntry],
                                 recaps: [SportSessionRecap], lastSync: Date?, now: Date) -> [TimelineItem] {
        var items: [TimelineItem] = []
        let plates = meals.filter { $0.day == metrics.day && $0.status == .confirmed }
        for plate in plates {
            items.append(TimelineItem(
                id: "meal-\(plate.id.uuidString)",
                at: plate.at,
                title: L("%@ · %@", plate.slot.rawValue.localizedCapitalized, plate.text.isEmpty ? L("Meal") : plate.text),
                detail: "",
                accent: .meal,
                meal: TimelineMeal(kcal: Int(plate.kcal.rounded()),
                                   protein: Int(plate.protein.rounded()),
                                   carb: Int(plate.carb.rounded()),
                                   fat: Int(plate.fat.rounded())),
                trailing: nil))
        }
        if let night = metrics.sleep, let wake = night.wakeAt {
            items.append(TimelineItem(
                id: "sleep-\(metrics.day.key)",
                at: wake,
                title: metrics.sleepScore.map { L("Woke up · sleep %d", $0.score) } ?? L("Woke up"),
                detail: [Fmt.duration(night.totalMinutes),
                         metrics.nightInputs?.hrv.map { L("HRV %d ms", Int($0.rounded())) },
                         night.spo2.map(\.percent).min().map { L("SpO2 %d%%", $0) }]
                    .compactMap { $0 }.joined(separator: " · "),
                accent: .sleep,
                meal: nil,
                trailing: nil))
        }
        for recap in recaps where UserDay.containing(recap.startedAt) == metrics.day {
            let delta = recap.loadAfter.flatMap { after in recap.loadBefore.map { after - $0 } }
            items.append(TimelineItem(
                id: "sport-\(recap.id)",
                at: recap.startedAt,
                title: recap.title,
                detail: [Fmt.duration(recap.seconds / 60),
                         recap.avgHR.map { L("HR %d", $0) },
                         recap.hasEnergy ? L("%@ kcal", Fmt.kcal(recap.kcal)) : nil]
                    .compactMap { $0 }.joined(separator: " · "),
                accent: .workout,
                meal: nil,
                trailing: delta.map { String(format: "%+.1f", $0) }))
        }
        if let peak = metrics.vitalsCurve.max(by: { ($0.stress ?? -1) < ($1.stress ?? -1) }),
           let stress = peak.stress, stress >= 60 {
            items.append(TimelineItem(
                id: "stress-\(metrics.day.key)",
                at: peak.ts,
                title: L("Stress peak · %d", stress),
                detail: L("Highest reading today."),
                accent: .stress,
                meal: nil,
                trailing: nil))
        }
        if let lastSync, UserDay.containing(lastSync) == metrics.day {
            items.append(TimelineItem(
                id: "sync-\(metrics.day.key)",
                at: lastSync,
                title: L("Sync"),
                detail: L("Band readings landed."),
                accent: .sync,
                meal: nil,
                trailing: nil))
        }
        if metrics.day == UserDay.containing(now),
           let live = metrics.vitalsCurve.last(where: { $0.hr != nil && now.timeIntervalSince($0.ts) < 20 * 60 }),
           let hr = live.hr {
            items.append(TimelineItem(
                id: "now-\(metrics.day.key)",
                at: now,
                title: L("Now"),
                detail: L("HR %d", hr),
                accent: .now,
                meal: nil,
                trailing: nil))
        }
        return items
    }

    private static func segmentItem(_ segment: TrainingSegment) -> TimelineItem {
        TimelineItem(
            id: "segment-\(segment.at.timeIntervalSince1970)",
            at: segment.at,
            title: segment.name,
            detail: [segment.minutes.map { Fmt.duration($0) },
                     segment.avgHR.map { L("HR %d", $0) },
                     segment.steps.map { L("%@ steps", Fmt.kcal(Double($0))) }]
                .compactMap { $0 }.joined(separator: " · "),
            accent: .workout,
            meal: nil,
            trailing: String(format: "%+.1f", segment.delta))
    }

    static func sleepHours(_ minutes: Int) -> String {
        String(format: "%.1f", Double(minutes) / 60)
    }

    static func signedInt(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private static func averageFoot(_ value: Int?, _ prior: [Int]) -> String {
        guard let value, prior.count >= 3 else { return Fmt.dash }
        let mean = Double(prior.reduce(0, +)) / Double(prior.count)
        let deltaHours = (Double(value) - mean) / 60
        return L("%@ / AVG", String(format: "%+.1f", deltaHours))
    }

    private static func deltaFoot(_ value: Double?, _ base: Double?, unit: String) -> String {
        guard let value, let base else { return Fmt.dash }
        let delta = Int((value - base).rounded())
        return L("%@ / 7D", "\(signedInt(delta)) \(unit)")
    }

    private static func bedtimeFoot(_ start: Date?) -> String {
        guard let start else { return Fmt.dash }
        let hour = Calendar.current.component(.hour, from: start)
        if hour >= 23 || hour < 5 { return L("LATE") }
        return L("ON TIME")
    }

    private static func mealLate(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 21 || hour < 4
    }

    private static func macroFoot(_ macro: Macro) -> String {
        guard let left = macro.left, let target = macro.target else { return Fmt.dash }
        if macro.met { return L("HIT") }
        return L("%dg / %dg", target - left, target)
    }
}
