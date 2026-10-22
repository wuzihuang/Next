import Foundation
import SwiftUI
import UIKit

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

    /// Categorical status ramp for sleep, heart and calorie allowance. The leg tint is
    /// a separate movement-volume ramp; `dim` remains the neutral off-ramp.
    enum BodyStatus: Int, Equatable, Comparable {
        case dim = -1, good = 0, ok, watch, poor, bad
        static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
        func escalated() -> Self {
            BodyStatus(rawValue: min(BodyStatus.bad.rawValue, rawValue + 1)) ?? .bad
        }
    }

    struct BodyGlow: Equatable {
        var lit: Bool
        /// 0.35…1 when the domain has data. 0 when it does not.
        var intensity: Double
        var eyebrow: String
        var value: String
        /// Short second lines under the value — the rest of the part's readings.
        var details: [String] = []
        /// Only meaningful while `lit`; an unlit part draws in dim white.
        var status: BodyStatus = .ok
        /// A data-specific hue can replace the shared status ramp (e.g. macros or step volume).
        var tint: Color? = nil
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
        var heart: BodyGlow
        var gut: BodyGlow
        var legs: BodyGlow
        var primary: [BodyMetric]
        var more: [BodyMetric]
    }

    /// The four lit parts, top to bottom. `BodyCloud.zones` paints its motes in this order.
    enum Zone: String, Equatable, Identifiable, CaseIterable {
        case head, heart, gut, legs
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
        /// The part's light as it stood on the map. nil keeps the page in neutral white.
        var status: BodyStatus?
        var tint: Color? = nil
    }

    typealias TimelineMeal = HomeTimeline.Meal
    typealias TimelineItem = HomeTimeline.Item

    /// The page a home card opens. Empty numbers still open it — the detail
    /// page is where a missing night or an unlogged day is allowed to say so.
    static func destination(for zone: Zone) -> Destination {
        switch zone {
        case .head: return .vitals(.sleep)
        case .heart: return .vitals(.heart)
        case .gut: return .fuel
        case .legs: return .vitals(.steps)
        }
    }

    static func destination(for item: TimelineItem) -> Destination? {
        switch item.accent {
        case .meal: return .fuelDay(item.day)
        case .stress: return .vitals(.stress)
        case .workout, .activity: return .training
        case .sleep, .wake: return .vitals(.sleep)
        case .bodyScan: return .composition(date: item.at)
        case .balanceCheck: return .measurements
        case .weighIn: return nil
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
        let latest = scans.max { $0.at < $1.at }
        let fields = compositionFields(latest: latest, scans: scans, heightCm: heightCm)
        return Body(
            scannedAt: latest?.at,
            head: headGlow(metrics: metrics),
            heart: heartGlow(metrics: metrics),
            gut: gutGlow(food: food),
            legs: legsGlow(metrics: metrics),
            primary: [fields.fat, fields.muscle, fields.lean],
            more: [fields.fatMass, fields.water, fields.protein, fields.bone, fields.bmr, fields.bmi])
    }

    /// The glow burns with the status, not with the number: fine reads at a third,
    /// a bad reading at full. Unlit parts stay dark.
    private static func glowIntensity(lit: Bool, status: BodyStatus) -> Double {
        lit ? 0.35 + 0.65 * Double(max(0, status.rawValue)) / Double(BodyStatus.bad.rawValue) : 0
    }

    private static func latestStress(_ metrics: DailyMetrics) -> Int? {
        metrics.vitalsCurve.last(where: { $0.stress != nil })?.stress
    }

    /// Head owns the night: the sleep numbers plus the day's stress index. HRV is a
    /// heart measurement and lives on the chest, not here.
    static func headGlow(metrics: DailyMetrics) -> BodyGlow {
        let night = metrics.sleep
        let minutes = night?.totalMinutes
        let stress = latestStress(metrics)
        let status = sleepStatus(metrics: metrics)
        let lit = (minutes ?? 0) > 0 || stress != nil
        var details: [String] = []
        var nightBits: [String] = []
        if let score = metrics.sleepScore?.score { nightBits.append(L("SCORE %d", score)) }
        if let deep = night?.deepMinutes, deep > 0 { nightBits.append(L("DEEP %@", sleepHours(deep))) }
        let rem = night?.remMinutes ?? 0
        if rem > 0 { nightBits.append(L("REM %@", sleepHours(rem))) }
        if !nightBits.isEmpty { details.append(nightBits.joined(separator: " · ")) }
        if let stress { details.append(L("STRESS %d", stress)) }
        return BodyGlow(
            lit: lit,
            intensity: glowIntensity(lit: lit, status: status),
            eyebrow: L("HEAD"),
            value: minutes.map { $0 > 0 ? L("SLEPT %@", sleepHours($0)) : Fmt.dash } ?? Fmt.dash,
            details: details,
            status: status)
    }

    /// The head's light is the night's light: the settled score when it exists, duration
    /// when it does not, pushed one stop worse by a high stress index.
    static func sleepStatus(metrics: DailyMetrics) -> BodyStatus {
        let status: BodyStatus
        if let score = metrics.sleepScore?.score {
            status = score >= 85 ? .good : score >= 70 ? .ok : score >= 55 ? .watch
                 : score >= 40 ? .poor : .bad
        } else if let minutes = metrics.sleep?.totalMinutes, minutes > 0 {
            status = minutes >= 570 ? .ok : minutes >= 450 ? .good : minutes >= 390 ? .ok
                 : minutes >= 300 ? .watch : minutes >= 240 ? .poor : .bad
        } else {
            status = .watch
        }
        guard let stress = latestStress(metrics), stress >= 75 else { return status }
        return status.escalated()
    }

    /// Every pulse-derived reading in one place: the live rate, the resting rate against
    /// its seven-day base, the night's oxygen floor and the sleeping breath rate.
    struct HeartInputs {
        var live: Int?
        var rhr: Double?
        var rhrBase: Double?
        var spo2: Int?
        var resp: Double?
        var hrv: Double?
        var hrvBase: Double?
        var hasAny: Bool { live != nil || rhr != nil || spo2 != nil || resp != nil }
    }

    static func heartInputs(_ metrics: DailyMetrics) -> HeartInputs {
        let breaths = metrics.sleep?.respiration?.map(\.breathsPerMinute) ?? []
        return HeartInputs(
            live: metrics.vitalsCurve.last(where: { $0.hr != nil })?.hr,
            rhr: metrics.nightInputs?.rhr,
            rhrBase: metrics.nightInputs?.rhrBase,
            spo2: metrics.sleep?.spo2.map(\.percent).min(),
            resp: breaths.isEmpty ? nil : breaths.reduce(0, +) / Double(breaths.count),
            hrv: metrics.nightInputs?.hrv,
            hrvBase: metrics.nightInputs?.hrvBase)
    }

    /// Worst signal wins: one bad reading is enough to pull the light down.
    static func heartStatus(_ inputs: HeartInputs) -> BodyStatus {
        var status: BodyStatus?
        if let rhr = inputs.rhr, let base = inputs.rhrBase {
            let delta = rhr - base
            status = delta <= 2 ? .good : delta <= 6 ? .watch : delta <= 10 ? .poor : .bad
        }
        if let spo2 = inputs.spo2 {
            let s: BodyStatus = spo2 >= 95 ? .good : spo2 >= 93 ? .watch : spo2 >= 90 ? .poor : .bad
            status = max(status ?? s, s)
        }
        if let resp = inputs.resp {
            let s: BodyStatus = (12...20).contains(resp) ? .good : (8...26).contains(resp) ? .watch : .poor
            status = max(status ?? s, s)
        }
        return status ?? .ok
    }

    static func heartGlow(metrics: DailyMetrics) -> BodyGlow {
        let inputs = heartInputs(metrics)
        let status = heartStatus(inputs)
        let lit = inputs.hasAny
        var details: [String] = []
        var resting: [String] = []
        if let rhr = inputs.rhr { resting.append(L("RHR %d", Int(rhr.rounded()))) }
        if let spo2 = inputs.spo2 { resting.append(L("SpO2 %d%%", spo2)) }
        if !resting.isEmpty { details.append(resting.joined(separator: " · ")) }
        if let resp = inputs.resp { details.append(L("RESP %@", String(format: "%.1f", resp))) }
        return BodyGlow(
            lit: lit,
            intensity: glowIntensity(lit: lit, status: status),
            eyebrow: L("HEART"),
            value: inputs.live.map { L("%d BPM", $0) }
                ?? inputs.rhr.map { L("RHR %d", Int($0.rounded())) } ?? Fmt.dash,
            details: details,
            status: status)
    }

    static func gutGlow(food: Food) -> BodyGlow {
        let status = gutStatus(food: food)
        guard food.face == .complete || food.face == .remaining,
              let eaten = food.eatenKcal, let target = food.targetKcal, target > 0 else {
            return BodyGlow(lit: false, intensity: 0, eyebrow: L("GUT"), value: Fmt.dash,
                            status: status)
        }
        let delta = eaten - target
        let text = delta == 0 ? L("ON ALLOWANCE") : L("%@ KCAL", Fmt.signedKcal(Double(delta)))
        return BodyGlow(lit: true, intensity: glowIntensity(lit: true, status: status),
                        eyebrow: L("GUT"), value: text,
                        details: [L("%@ / %@ EATEN", Fmt.kcal(Double(eaten)), Fmt.kcal(Double(target)))],
                        status: status, tint: gutTint(food: food))
    }

    /// Mixes the established protein, carbohydrate and fat colours by their share of
    /// recorded macro calories. Missing macros do not contribute a made-up zero.
    static func gutTint(food: Food) -> Color? {
        BodyTintMath.gut(protein: food.protein.eaten, carb: food.carb.eaten, fat: food.fat.eaten,
                         proteinColor: rgb(NB.optimal2), carbColor: rgb(NB.lime1),
                         fatColor: rgb(NB.run1)).map(color)
    }

    /// How far the plate sits from the allowance. Overshooting advances through amber
    /// and orange before orange-red; it is not a clinical warning.
    static func gutStatus(food: Food) -> BodyStatus {
        guard food.face == .complete || food.face == .remaining,
              let eaten = food.eatenKcal, let target = food.targetKcal, target > 0 else {
            return .ok
        }
        let fraction = Double(eaten - target) / Double(target)
        if fraction > 0.30 { return .bad }
        if fraction > 0.15 { return .poor }
        if fraction > 0.02 { return .watch }
        if fraction < -0.30 { return .poor }
        if fraction < -0.15 { return .watch }
        if fraction < -0.03 { return .ok }
        return .good
    }

    /// Legs own the day's ground: step volume sets the colour; distance and movement kcal
    /// remain supporting readouts, not substitutes for an unreported step count.
    static func legsGlow(metrics: DailyMetrics) -> BodyGlow {
        let steps = VitalsReadout.daySteps(metrics)
        let metres = VitalsReadout.dayMetres(metrics)
        let active = VitalsReadout.dayActiveKcal(metrics)
        let status = legsStatus(steps: steps)
        let lit = steps != nil || metres != nil
        var details: [String] = []
        if let metres { details.append(L("DIST %@ KM", String(format: "%.1f", metres / 1000))) }
        if let active { details.append(L("ACTIVE %@", Fmt.kcal(active))) }
        return BodyGlow(
            lit: lit,
            intensity: lit ? BodyTintMath.legsIntensity(steps: steps) : 0,
            eyebrow: L("LEGS"),
            value: steps.map { L("%@ STEPS", Fmt.kcal($0)) }
                ?? metres.map { L("%@ KM", String(format: "%.1f", $0 / 1000)) } ?? Fmt.dash,
            details: details,
            status: status, tint: legsTint(steps: steps))
    }

    /// Low steps are neutral, not a warning. At 10k the hue is yellow; 20–30k
    /// moves from orange toward orange-red as activity volume rises.
    static func legsTint(steps: Double?) -> Color {
        color(BodyTintMath.legs(steps: steps, palette: .init(
            neutral: BodyRGB(red: 1, green: 1, blue: 1, alpha: 0.28),
            green: rgb(NB.optimal2), yellow: rgb(NB.filmYellow),
            orange: rgb(NB.ember1), orangeRed: rgb(NB.ember2))))
    }

    private static func rgb(_ color: Color) -> BodyRGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return BodyRGB(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    private static func color(_ rgb: BodyRGB) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: rgb.alpha)
    }

    /// Walking volume is not a body-status warning; only zero or unavailable stays neutral.
    static func legsStatus(steps: Double?) -> BodyStatus {
        guard let steps, steps > 0 else { return .dim }
        return .good
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
        case .heart: return heartDetail(metrics: metrics)
        case .gut: return foodDetail(metrics: metrics, meals: meals)
        case .legs: return legsDetail(metrics: metrics, history: history)
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
        let stress = latestStress(metrics)
        let stressPeak = metrics.vitalsCurve.compactMap(\.stress).max()
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
                Stat(id: "light", label: L("LIGHT SLEEP"), value: night.map { sleepHours($0.lightMinutes) } ?? Fmt.dash,
                     unit: L("H"), foot: averageFoot(night?.lightMinutes, history.compactMap { $0.sleep?.lightMinutes })),
                Stat(id: "score", label: L("SLEEP SCORE"), value: metrics.sleepScore.map { String($0.score) } ?? Fmt.dash,
                     unit: "", foot: metrics.sleepScore?.isCalibrating == true ? L("CALIBRATING") : Fmt.dash),
                Stat(id: "stress", label: L("STRESS"), value: stress.map(String.init) ?? Fmt.dash,
                     unit: "", foot: stressPeak.map { $0 >= 60 ? L("PEAK %d", $0) : L("TODAY") } ?? Fmt.dash),
                Stat(id: "bed", label: L("BEDTIME"), value: night?.sleepStart.map { Fmt.clock($0) } ?? Fmt.dash,
                     unit: "", foot: bedtimeFoot(night?.sleepStart)),
            ],
            noteLabel: L("TONIGHT"),
            note: note,
            status: sleepStatus(metrics: metrics))
    }

    static func heartDetail(metrics: DailyMetrics) -> Detail {
        let inputs = heartInputs(metrics)
        let status = heartStatus(inputs)
        let verdict: String
        switch status {
        case .dim: verdict = Fmt.dash
        case .good, .ok: verdict = L("IN RANGE")
        case .watch: verdict = L("WATCH")
        case .poor: verdict = L("ELEVATED")
        case .bad: verdict = L("ATTENTION")
        }
        return Detail(
            zone: .heart,
            eyebrow: L("HEART · TODAY"),
            hero: (inputs.live ?? inputs.rhr.map { Int($0.rounded()) }).map(String.init) ?? Fmt.dash,
            heroUnit: L("BPM"),
            aside: Fmt.dash,
            verdict: verdict,
            stats: [
                Stat(id: "now", label: L("NOW"), value: inputs.live.map(String.init) ?? Fmt.dash,
                     unit: L("BPM"), foot: inputs.live == nil ? Fmt.dash : L("TODAY")),
                Stat(id: "rhr", label: L("RESTING HR"), value: inputs.rhr.map { String(Int($0.rounded())) } ?? Fmt.dash,
                     unit: L("BPM"), foot: deltaFoot(inputs.rhr, inputs.rhrBase, unit: L("BPM"))),
                Stat(id: "peak", label: L("PEAK HR"), value: metrics.peakHR.map(String.init) ?? Fmt.dash,
                     unit: L("BPM"), foot: metrics.peakHR == nil ? Fmt.dash : L("TODAY")),
                Stat(id: "hrv", label: L("HRV"), value: inputs.hrv.map { String(Int($0.rounded())) } ?? Fmt.dash,
                     unit: L("MS"), foot: deltaFoot(inputs.hrv, inputs.hrvBase, unit: L("MS"))),
                Stat(id: "spo2", label: L("SPO2 MIN"), value: inputs.spo2.map(String.init) ?? Fmt.dash,
                     unit: "%", foot: inputs.spo2 == nil ? Fmt.dash : L("LAST NIGHT")),
                Stat(id: "resp", label: L("BREATH / MIN"), value: inputs.resp.map { String(format: "%.1f", $0) } ?? Fmt.dash,
                     unit: "", foot: inputs.resp == nil ? Fmt.dash : L("STEADY")),
            ],
            noteLabel: L("TODAY"),
            note: nil,
            status: status)
    }

    static func legsDetail(metrics: DailyMetrics, history: [DailyMetrics]) -> Detail {
        let steps = VitalsReadout.daySteps(metrics)
        let metres = VitalsReadout.dayMetres(metrics)
        let active = VitalsReadout.dayActiveKcal(metrics)
        let status = legsStatus(steps: steps)
        let prior = history.suffix(8).dropLast().compactMap { VitalsReadout.daySteps($0) }
        let versus: String = {
            guard let steps, prior.count >= 3 else { return Fmt.dash }
            let mean = prior.reduce(0, +) / Double(prior.count)
            return L("%@ VS AVG", Fmt.signed(steps - mean))
        }()
        let sessions = metrics.segments.filter { !$0.allDay }.count
        let verdict: String
        switch status {
        case .dim: verdict = Fmt.dash
        case .good: verdict = L("ON PACE")
        case .ok: verdict = L("YOUR USUAL RANGE")
        case .watch: verdict = L("BELOW USUAL")
        case .poor, .bad: verdict = L("WELL BELOW")
        }
        return Detail(
            zone: .legs,
            eyebrow: L("MOVEMENT · TODAY"),
            hero: steps.map { Fmt.kcal($0) } ?? metres.map { String(format: "%.1f", $0 / 1000) } ?? Fmt.dash,
            heroUnit: steps != nil ? L("STEPS") : L("KM"),
            aside: versus,
            verdict: verdict,
            stats: [
                Stat(id: "dist", label: L("DISTANCE"), value: metres.map { String(format: "%.2f", $0 / 1000) } ?? Fmt.dash,
                     unit: L("KM"), foot: metres.map { L("%@ M WALKED", Fmt.kcal($0)) } ?? L("NO DISTANCE YET")),
                Stat(id: "active", label: L("ACTIVE"), value: active.map { Fmt.kcal($0) } ?? Fmt.dash,
                     unit: L("KCAL"), foot: active == nil ? L("NEEDS YOUR WEIGHT") : L("MOVEMENT ONLY")),
                Stat(id: "time", label: L("ACTIVE TIME"), value: Fmt.duration(metrics.activeMinutes),
                     unit: "", foot: metrics.activeMinutes == nil ? Fmt.dash : L("TODAY")),
                Stat(id: "load", label: L("STRAIN"), value: Fmt.load(metrics.trainingLoad),
                     unit: "/21", foot: L("TODAY")),
                Stat(id: "sessions", label: L("SESSIONS"), value: sessions > 0 ? String(sessions) : Fmt.dash,
                     unit: "", foot: L("TODAY")),
            ],
            noteLabel: L("TODAY"),
            note: nil,
            status: status == .dim ? nil : status,
            tint: legsTint(steps: steps))
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
            note: note,
            status: deck.face == .complete || deck.face == .remaining ? gutStatus(food: deck) : nil,
            tint: gutTint(food: deck))
    }

    static func timeline(day: UserDay, metrics: DailyMetrics, history: [DailyMetrics],
                         meals: [MealEntry], recaps: [SportSessionRecap],
                         weighIns: [WeighIn], measurements: [MeasurementRecord], usesMetric: Bool,
                         earlier: Bool, now: Date = Date(), lookbackDays: Int = 6) -> [TimelineItem] {
        var seenDays = Set<UserDay>()
        let firstDay = earlier ? day.adding(days: -max(0, lookbackDays)) : day
        let pool = ([metrics] + history).filter {
            $0.day >= firstDay && $0.day <= day.adding(days: 1) && seenDays.insert($0.day).inserted
        }
        var items = pool.flatMap { dayItems(metrics: $0, now: now) }
        var seenMeals = Set<UUID>()
        for plate in meals where seenMeals.insert(plate.id).inserted && plate.status == .confirmed {
            items.append(TimelineItem(
                id: "meal-\(plate.id.uuidString)",
                at: plate.at,
                title: L("%@ · %@", L(plate.slot.rawValue).localizedCapitalized,
                         plate.text.isEmpty ? L("Meal") : plate.text),
                detail: "",
                accent: .meal,
                meal: TimelineMeal(kcal: Int(plate.kcal.rounded()),
                                   protein: Int(plate.protein.rounded()),
                                   carb: Int(plate.carb.rounded()),
                                   fat: Int(plate.fat.rounded())),
                trailing: nil))
        }
        for recap in recaps where recap.isValid {
            let delta = recap.loadAfter.flatMap { after in recap.loadBefore.map { after - $0 } }
            items.append(TimelineItem(
                id: "sport-\(recap.id)",
                at: recap.startedAt,
                title: recap.title,
                detail: ["\(Fmt.clock(recap.startedAt))–\(timelineClock(recap.endedAt, on: UserDay.containing(recap.startedAt)))",
                         recap.seconds < 60 ? L("%d SEC", recap.seconds) : Fmt.duration(recap.seconds / 60),
                         recap.avgHR.map { L("HR %d", $0) },
                         recap.hasEnergy ? L("%@ kcal", Fmt.kcal(recap.kcal)) : nil]
                    .compactMap { $0 }.joined(separator: " · "),
                accent: .workout,
                meal: nil,
                trailing: delta.map { String(format: "%+.1f", $0) },
                endAt: recap.endedAt))
        }
        for entry in weighIns where entry.origin != .band && entry.weightKg.isFinite && entry.weightKg > 0 {
            let weight = usesMetric ? entry.weightKg : entry.weightKg * 2.2046226
            let unit = usesMetric ? L("KG") : L("LB")
            items.append(TimelineItem(
                id: "weight-\(entry.id.uuidString)",
                at: entry.date,
                title: L("Weigh-in"),
                detail: "\(Fmt.kg(weight)) \(unit) · \(entry.origin == .health ? L("Apple Health") : L("Manual entry"))",
                accent: .weighIn,
                meal: nil,
                trailing: nil))
        }
        for record in measurements {
            let accent: HomeTimeline.Accent
            let detail: String
            switch record.detail {
            case .bodyScan(let scan):
                accent = .bodyScan
                let fat = scan.bodyFatPercent.map { "\(Fmt.kg($0))%" } ?? Fmt.dash
                let lean = scan.leanMassKg.map {
                    "\(Fmt.kg(usesMetric ? $0 : $0 * 2.2046226)) \(usesMetric ? L("KG") : L("LB"))"
                } ?? Fmt.dash
                detail = L("Body fat %@ · Lean mass %@", fat, lean)
            case .balanceCheck:
                accent = .balanceCheck
                detail = record.summary
            }
            items.append(TimelineItem(
                id: "measurement-\(record.id.uuidString)",
                at: record.at,
                title: record.title,
                detail: detail,
                accent: accent,
                meal: nil,
                trailing: nil,
                recordID: record.id))
        }
        return HomeTimeline.visible(items, on: day, earlier: earlier, now: now,
                                    lookbackDays: lookbackDays)
    }

    private static func dayItems(metrics: DailyMetrics, now: Date) -> [TimelineItem] {
        var items = sleepItems(metrics: metrics)
        items += metrics.segments.filter { !$0.allDay }.map(segmentItem)
        let readings = metrics.vitalsCurve.filter {
            $0.ts >= metrics.day.start && $0.ts < metrics.day.end && $0.ts <= now
        }
        if let peak = readings.max(by: { ($0.stress ?? -1) < ($1.stress ?? -1) }),
           let stress = peak.stress, stress >= 60 {
            items.append(TimelineItem(
                id: "stress-\(metrics.day.key)",
                at: peak.ts,
                title: L("Stress peak · %d", stress),
                detail: L("Highest recorded stress that day."),
                accent: .stress,
                meal: nil,
                trailing: nil))
        }
        return items
    }

    private static func sleepItems(metrics: DailyMetrics) -> [TimelineItem] {
        guard let night = metrics.sleep else { return [] }
        if let start = night.sleepStart, let wake = night.wakeAt, wake <= start { return [] }
        let source = night.isUserReported ? L("Manually logged sleep")
            : night.isCorrected ? L("Edited sleep times") : L("Recorded by HOOP")
        var items: [TimelineItem] = []
        if let start = night.sleepStart {
            items.append(TimelineItem(
                id: "sleep-start-\(metrics.day.key)",
                at: start,
                title: L("Fell asleep"),
                detail: source,
                accent: .sleep,
                meal: nil,
                trailing: nil,
                endAt: night.wakeAt))
        }
        if let wake = night.wakeAt {
            items.append(TimelineItem(
                id: "sleep-wake-\(metrics.day.key)",
                at: wake,
                title: metrics.sleepScore.map { L("Woke up · sleep %d", $0.score) } ?? L("Woke up"),
                detail: [night.totalMinutes > 0 ? Fmt.duration(night.totalMinutes) : nil,
                         night.sleepStart.map { L("Asleep at %@", timelineClock($0, on: UserDay.containing(wake))) },
                         metrics.nightInputs?.hrv.map { L("HRV %d ms", Int($0.rounded())) },
                         night.spo2.map(\.percent).min().map { L("SpO2 %d%%", $0) },
                         night.isUserReported || night.isCorrected ? source : nil]
                    .compactMap { $0 }.joined(separator: " · "),
                accent: .wake,
                meal: nil,
                trailing: nil))
        }
        return items
    }

    private static func timelineClock(_ at: Date, on day: UserDay) -> String {
        UserDay.containing(at) == day ? Fmt.clock(at) : Fmt.displayDate(at, format: "MMM d HH:mm")
    }

    private static func segmentItem(_ segment: TrainingSegment) -> TimelineItem {
        TimelineItem(
            id: "segment-\(segment.at.timeIntervalSince1970)",
            at: segment.at,
            title: L("Activity · %@", segment.name),
            detail: [segment.minutes.map { Fmt.duration($0) },
                     segment.avgHR.map { L("HR %d", $0) },
                     segment.steps.map { L("%@ steps", Fmt.kcal(Double($0))) }]
                .compactMap { $0 }.joined(separator: " · "),
            accent: .activity,
            meal: nil,
            trailing: String(format: "%+.1f", segment.delta),
            endAt: segment.minutes.map { segment.at.addingTimeInterval(Double($0) * 60) })
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
