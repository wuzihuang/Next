import Foundation
import SwiftUI

/// Everything the screens read. Backed by Supabase in production; seeded with the
/// exact numbers printed on the design boards so the flow is walkable without a band.
@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var today: DailyMetrics
    @Published var history: [DailyMetrics] = []
    @Published var meals: [MealEntry] = []
    /// The window 12's WEEK view reads. Today's list stays in `meals` so 09 is untouched.
    @Published var recentMeals: [MealEntry] = []
    @Published var weighIns: [WeighIn] = []
    @Published var band: BandState = .mock
    @Published var profile: Profile = .mock
    @Published var lastSync: Date = Date().addingTimeInterval(-12 * 60)
    /// 04 · the HR / STRESS row under the readout, and the tick it came from. 13 · the age
    /// of that tick is what decides whether the numbers are shown, dimmed, or dashed.
    @Published var vitals: LiveVitals = .mock
    /// 12 · what this HOOP reports it can do, as last stored. The device page and 07's
    /// capabilities() gate read this so they are right before the band answers, and still
    /// right when it is out of range.
    @Published var capabilities = BandCapabilities()
    @Published var capabilitiesReadAt: Date?
    @Published var isOffline = false

    // 11 · the three tiles. Two net changes over twelve weeks and one absolute value,
    // which is why the third one is labelled apart from the other two.
    @Published var netFatMass12w: Double?
    @Published var netLeanMass12w: Double?
    @Published var bodyFatPercent: Double?

    private init() {
        // The seeded demo account is a returning user: the gate was walked, the band is
        // bound, and the app reconnects to it the way it would on any later launch.
        if BoundBand.identifier == nil { BoundBand.identifier = "C4-2E-8F-1A-73-9D" }
        today = DataStore.seedToday()
        history = DataStore.seedHistory()
        meals = MealEntry.seed
        weighIns = WeighIn.seed
    }

    /// Board 04 · 01 默认 — the screen the whole product is measured against.
    static func seedToday() -> DailyMetrics {
        var m = DailyMetrics(day: UserDay.containing(Date()))
        m.trainingLoad = 12.4
        m.targetLoad = 14.5
        m.optimalZone = 13.0...16.0
        m.zoneMinutes = [46, 38, 22, 15, 5]
        m.bbWake = 72
        m.bodyBattery = 72
        // 13 · the four rows the board prints, and they add up to the 72 above.
        m.reserveDrivers = ReserveDrivers(lastNight: 38, awake: -14, movement: -9,
                                          stress: -3, anchor: 60)
        m.nightInputs = NightInputs(hrv: 54, hrvBase: 61, rhr: 51, rhrBase: 48,
                                    rhrNights: 9, multiplier: 0.88)
        m.bmr = 1480
        m.eActive = 320
        m.eTrain = 60
        m.eTrainPlan = 480
        m.eOutNow = 1860
        m.activeForecast = 260
        m.eOutFull = 2280
        m.eIn = 1240
        m.balance = -620
        m.targetIn = 1900
        m.protein = MacroSlot(target: 145, eaten: 84)
        m.carb = MacroSlot(target: 195, eaten: 132)
        m.fat = MacroSlot(target: 60, eaten: 42)
        m.nextMeal = 660
        m.weightKg = 68.4
        m.fatKg = 12.9
        m.leanKg = 55.5
        m.fatSource = .measured
        m.fatEmaDelta7d = -0.42
        m.leanEmaDelta7d = 0.18
        m.confidence = .medium
        m.scans7d = 5
        m.logged7d = 6
        m.fuelState = .partial(slots: 3)
        m.bandCoverage = 0.86
        m.asOf = Date()
        return m
    }

    /// 12 weeks of history so the heat map on 11 · Profile has something honest to draw.
    static func seedHistory() -> [DailyMetrics] {
        let today = UserDay.containing(Date())
        var out: [DailyMetrics] = []
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 10_000) / 10_000
        }
        for back in stride(from: 84, through: 1, by: -1) {
            var m = DailyMetrics(day: today.adding(days: -back))
            let r = rnd()
            if r < 0.12 {                       // grey A · nothing logged
                m.fuelState = .unlogged
                m.bandCoverage = 0.7 + rnd() * 0.3
            } else if r < 0.19 {                // grey B · no burn
                m.fuelState = .confirmed
                m.eIn = 1700 + rnd() * 500
                m.bandCoverage = rnd() * 0.45
            } else {
                m.fuelState = .confirmed
                m.bandCoverage = 0.6 + rnd() * 0.4
                let out_ = 2050 + rnd() * 420
                let inn = 1500 + rnd() * 900
                m.bmr = 1480
                m.eOutNow = out_
                m.eIn = inn
                m.balance = inn - out_
            }
            m.trainingLoad = 2 + rnd() * 17
            m.bbWake = Int(48 + rnd() * 45)
            m.weightKg = 69.8 - Double(84 - back) * 0.016 + (rnd() - 0.5) * 0.5
            out.append(m)
        }
        out.append(seedToday())
        return out
    }

    // MARK: mutations the UI performs

    func logMeal(_ entry: MealEntry) {
        meals.append(entry)
        recomputeFuel()
    }

    func updateMeal(_ id: UUID, kcal: Double, text: String) {
        guard let i = meals.firstIndex(where: { $0.id == id }) else { return }
        meals[i].kcal = kcal
        meals[i].text = text
        meals[i].revisions += 1
        recomputeFuel()
    }

    func applyMacros(_ id: UUID, protein: Int, carb: Int, fat: Int) {
        guard let i = meals.firstIndex(where: { $0.id == id }) else { return }
        meals[i].protein = protein
        meals[i].carb = carb
        meals[i].fat = fat
        recomputeFuel()
    }

    /// F0 right column: 09 needs an edit/delete entry point. Range-limited to 7 user days (F2 §08).
    func deleteMeal(_ id: UUID) {
        meals.removeAll { $0.id == id }
        recomputeFuel()
    }

    func canEdit(_ entry: MealEntry) -> Bool {
        entry.day >= UserDay.containing(Date()).adding(days: -6)
    }

    private func recomputeFuel() {
        let day = UserDay.containing(Date())
        let confirmed = meals.filter { $0.day == day && $0.status == .confirmed }
        today.eIn = confirmed.isEmpty ? nil : confirmed.reduce(0) { $0 + $1.kcal }
        if let eIn = today.eIn, let out = today.eOutNow { today.balance = eIn - out }
        let slots = Set(confirmed.map(\.slot)).count
        today.fuelState = confirmed.isEmpty ? .unlogged : (slots >= 4 ? .confirmed : .partial(slots: slots))
        objectWillChange.send()
    }

    func addWeighIn(_ w: WeighIn) {
        weighIns.append(w)
        weighIns.sort { $0.date > $1.date }
        today.weightKg = w.weightKg
        if let bf = w.bodyFatPercent {
            today.fatKg = w.weightKg * bf / 100
            today.leanKg = w.weightKg - (today.fatKg ?? 0)
            today.fatSource = w.source
        }
    }
}

struct MealEntry: Identifiable, Hashable {
    enum Slot: String, CaseIterable, Hashable { case breakfast = "BREAKFAST", lunch = "LUNCH", dinner = "DINNER", snack = "SNACK" }
    enum Status: String, Hashable { case open = "OPEN", skipped = "SKIPPED", confirmed = "CONFIRMED" }

    let id: UUID
    var day: UserDay
    var at: Date
    var slot: Slot
    var status: Status
    var text: String
    var kcal: Double
    var protein: Int
    var carb: Int
    var fat: Int
    var revisions: Int = 0
    var source: Source = .voice

    enum Source: String, Hashable { case voice = "VOICE", typed = "TYPED", photo = "PHOTO" }

    /// Board 09 · the four meal slots printed on the axis, including the 01:20 +1 late snack
    /// that only exists because the day is cut at 04:00.
    static var seed: [MealEntry] {
        let day = UserDay.containing(Date())
        func at(_ h: Int, _ m: Int, plusDay: Bool = false) -> Date {
            Calendar.current.date(byAdding: .minute, value: (h - 4) * 60 + m + (plusDay ? 1440 : 0), to: day.start)!
        }
        return [
            MealEntry(id: UUID(), day: day, at: at(1, 20, plusDay: false), slot: .snack, status: .confirmed,
                      text: "半碗面 + 一个鸡蛋", kcal: 310, protein: 14, carb: 42, fat: 9, source: .voice),
            MealEntry(id: UUID(), day: day, at: at(8, 10), slot: .breakfast, status: .confirmed,
                      text: "燕麦、希腊酸奶、蓝莓", kcal: 420, protein: 28, carb: 52, fat: 11, source: .typed),
            MealEntry(id: UUID(), day: day, at: at(12, 40), slot: .lunch, status: .confirmed,
                      text: "鸡胸沙拉配藜麦", kcal: 510, protein: 42, carb: 38, fat: 22, source: .photo),
            MealEntry(id: UUID(), day: day, at: at(19, 0), slot: .dinner, status: .open,
                      text: "", kcal: 0, protein: 0, carb: 0, fat: 0),
        ]
    }
}

struct WeighIn: Identifiable, Hashable {
    let id: UUID
    var date: Date
    var weightKg: Double
    var bodyFatPercent: Double?
    var source: MeasurementSource
    var origin: Origin
    enum Origin: String, Hashable { case band = "BAND BIA", scale = "SCALE", health = "APPLE HEALTH", manual = "MANUAL" }

    static var seed: [WeighIn] {
        var out: [WeighIn] = []
        for i in 0..<9 {
            let day: Date = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let kg: Double = 68.4 + Double(i) * 0.09
            let measured: Bool = i % 2 == 0
            let bf: Double? = measured ? 18.9 + Double(i) * 0.05 : nil
            let src: MeasurementSource = measured ? .measured : .derived
            let origin: Origin
            switch i % 3 {
            case 0: origin = .band
            case 1: origin = .health
            default: origin = .manual
            }
            out.append(WeighIn(id: UUID(), date: day, weightKg: kg,
                               bodyFatPercent: bf, source: src, origin: origin))
        }
        return out
    }
}

struct Profile: Hashable {
    var name: String
    var email: String
    var birthdate: Date
    var heightCm: Double
    var sexIsMale: Bool
    var goal: Goal
    var usesMetric: Bool
    var appleHealthLinked: Bool

    var age: Int { Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 34 }
    var hrMax: Int { Int((208 - 0.7 * Double(age)).rounded()) }   // Tanaka

    static let mock = Profile(
        name: "ZEPH",
        email: "you@nextbody.app",
        birthdate: Calendar.current.date(byAdding: .year, value: -34, to: Date())!,
        heightCm: 176, sexIsMale: true, goal: .recomp,
        usesMetric: true, appleHealthLinked: true)
}

/// The most recent five-minute tick. Nothing here is extrapolated: if the band has been
/// off the wrist for six hours these are simply absent (13 · CURVE STOPS AT THE LAST REAL TICK).
struct LiveVitals: Hashable {
    var hr: Int?
    var stress: Int?
    var at: Date?

    static let mock = LiveVitals(hr: 72, stress: 31, at: Date().addingTimeInterval(-90))
    var freshness: TickFreshness { TickFreshness.of(at) }
}

struct BandState: Hashable {
    var connected: Bool
    var name: String
    var mac: String
    var batteryPercent: Int
    var firmware: String
    var lastSync: Date
    var capabilities: Set<Capability>

    enum Capability: String, Hashable, CaseIterable {
        case heartRate, bloodOxygen, bloodPressure, ecg, temperature, bodyComponent, wearDetection, alarms
    }

    static let mock = BandState(connected: true, name: "NEXT HOOP", mac: "C4:2E:8F:1A:73:9D",
                                batteryPercent: 82, firmware: "1.4.7",
                                lastSync: Date().addingTimeInterval(-12 * 60),
                                capabilities: Set(Capability.allCases))
}

/// F1 · A. The gate is walked once per account; after that none of its screens is reachable
/// again unless the band is unbound or swapped.
@MainActor
final class SessionStore: ObservableObject {
    enum Stage: String, Hashable { case gateSignIn, gateConnect, gateOnboarding, root }

    private static let key = "nb.gate.stage"

    @Published var stage: Stage {
        didSet { UserDefaults.standard.set(stage.rawValue, forKey: Self.key) }
    }
    @Published var email = ""
    @Published var isSignedIn = false

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        stage = raw.flatMap(Stage.init(rawValue:)) ?? .gateSignIn
    }

    func reset() { stage = .gateSignIn; isSignedIn = false; email = "" }
}
