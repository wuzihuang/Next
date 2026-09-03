import Foundation
import SwiftUI

/// Everything the screens read. Backed by Supabase in production. On the simulator it is
/// seeded with the exact numbers printed on the design boards so the flow is walkable
/// without a band; a real phone starts empty and fills in from the server and the wrist.
@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var today: DailyMetrics
    @Published var history: [DailyMetrics] = []
    @Published var meals: [MealEntry] = []
    /// The window 12's WEEK view reads. Today's list stays in `meals` so 09 is untouched.
    @Published var recentMeals: [MealEntry] = []
    @Published var weighIns: [WeighIn] = []
    @Published var band: BandState = Band.allowsSeed ? .mock : .unknown
    @Published var profile: Profile = Band.allowsSeed ? .mock : .blank
    /// F3 rule 09 · the moment of the last readOriginData that succeeded. nil until one has:
    /// a phone that has never synced says so, it does not say "12 MIN AGO".
    @Published var lastSync: Date? = Band.allowsSeed ? Date().addingTimeInterval(-12 * 60) : nil
    /// 04 · the HR / STRESS row under the readout, and the tick it came from. 13 · the age
    /// of that tick is what decides whether the numbers are shown, dimmed, or dashed.
    @Published var vitals: LiveVitals = Band.allowsSeed ? .mock : LiveVitals()
    /// A short-lived estimate between two five-minute server settlements. It is rebased from
    /// the server whenever a stored tick lands; it never becomes a second historical curve.
    @Published private(set) var bodyBatteryPreview: Int?
    /// 12 · what this HOOP reports it can do, as last stored. The device page and 07's
    /// capabilities() gate read this so they are right before the band answers, and still
    /// right when it is out of range.
    @Published var capabilities = BandCapabilities()
    @Published var capabilitiesReadAt: Date?
    @Published var isOffline = false
    /// 11 edge 3 · the export row says PREPARING… while export_all runs; the page can be left.
    @Published var exportPreparing = false

    // 11 · the three tiles. Two net changes over twelve weeks and one absolute value,
    // which is why the third one is labelled apart from the other two.
    @Published var netFatMass12w: Double?
    @Published var netLeanMass12w: Double?
    @Published var bodyFatPercent: Double?

    private var bodyBatteryPreviewAnchor: Double?
    private var bodyBatteryPreviewAt: Date?
    private var bodyBatteryPreviewTicks: [BodyBatteryEngine.Tick] = []

    var bodyBatteryNow: Int? { bodyBatteryPreview ?? today.bodyBattery }

    var todayForDisplay: DailyMetrics {
        var metrics = today
        metrics.bodyBattery = bodyBatteryNow
        return metrics
    }

    private init() {
        // The seeded demo account is a returning user: the gate was walked, the band is
        // bound, and the app reconnects to it the way it would on any later launch.
        // ⚠️ Simulator only. On a device a made-up identifier makes the app believe a band
        // is bound before the gate was ever walked, and every launch would try to reconnect.
        if Band.allowsSeed, BoundBand.identifier == nil { BoundBand.identifier = "C4-2E-8F-1A-73-9D" }
        // Earlier device builds wrote that seed; a real phone carrying it is not bound to anything.
        if !Band.allowsSeed, BoundBand.identifier == "C4-2E-8F-1A-73-9D" { BoundBand.forget() }
        // The board's numbers exist so the flow is walkable on a simulator with no band.
        // On a device every one of them would be a figure with no source behind it — F2
        // rule 05 · unknown is "——", never a plausible number — so the day starts empty and
        // fills in from daily_results and from the band, or stays a dash.
        if Band.allowsSeed {
            today = DataStore.seedToday()
            history = DataStore.seedHistory()
            meals = MealEntry.seed
            weighIns = WeighIn.seed
        } else {
            today = DailyMetrics(day: UserDay.containing(Date()))
        }
    }

    /// 11 · DELETE EVERYTHING. By the time this runs the account is gone from the server,
    /// so every number still held here is an orphan — and the gate behind it is a sign-in
    /// screen that would be drawn over yesterday's readout until the app is killed.
    /// Back to the state a phone is in before any account: dashes, not the seeded board.
    /// ⚠️ `isOffline` is not the account's, it is the radio's — Reachability owns it, and
    /// clearing it here would print ONLINE at the gate of a phone in a lift.
    func purge() {
        today = DailyMetrics(day: UserDay.containing(Date()))
        history = []
        meals = []
        recentMeals = []
        weighIns = []
        band = .unknown
        profile = .blank
        lastSync = nil
        vitals = LiveVitals()
        bodyBatteryPreview = nil
        bodyBatteryPreviewAnchor = nil
        bodyBatteryPreviewAt = nil
        bodyBatteryPreviewTicks = []
        capabilities = BandCapabilities()
        capabilitiesReadAt = nil
        exportPreparing = false
        netFatMass12w = nil
        netLeanMass12w = nil
        bodyFatPercent = nil
    }

    /// The server replay is authoritative. Every successful load replaces the preview's
    /// anchor so live sensor callbacks can only estimate the unsynced minutes after it.
    func rebaseBodyBatteryPreview(at date: Date = Date()) {
        bodyBatteryPreview = nil
        bodyBatteryPreviewAnchor = today.bodyBattery.map(Double.init)
        bodyBatteryPreviewAt = today.bodyBattery == nil ? nil : date
        bodyBatteryPreviewTicks = []
    }

    /// Heart callbacks arrive every second or two, but reserve is a slow physiological
    /// estimate. One update a minute feels live without charging the same minute repeatedly.
    func applyLiveBodyBattery(heartRate: Int?, hrvMS: Double? = nil,
                              stress: Int?, steps: Int? = nil, met: Double? = nil,
                              at date: Date = Date()) {
        guard let anchor = bodyBatteryPreviewAnchor ?? today.bodyBattery.map(Double.init) else { return }
        let previous = bodyBatteryPreviewAt ?? date
        let elapsedMinutes = date.timeIntervalSince(previous) / 60
        guard elapsedMinutes >= 1 else { return }

        let recent = today.vitalsCurve.last.flatMap {
            date.timeIntervalSince($0.ts) <= 15 * 60 ? $0 : nil
        }
        let baseline = BodyBatteryEngine.Baseline(
            restingHeartRate: today.nightInputs?.rhr ?? 55,
            maximumHeartRate: Double(profile.hrMax),
            hrvMS: today.nightInputs?.hrvBase,
            recoveryMultiplier: today.nightInputs?.multiplier ?? 1
        )
        let tick = BodyBatteryEngine.Tick(
            durationMinutes: min(5, elapsedMinutes),
            heartRate: heartRate,
            hrvMS: hrvMS ?? recent?.hrv,
            stress: stress ?? recent?.stress,
            steps: steps,
            met: met
        )
        bodyBatteryPreviewTicks.append(tick)
        // Preserve the quiet run and rest budget across live callbacks. A server reload clears
        // this list, so under normal cadence it contains only the unsynced interval.
        let result = BodyBatteryEngine.replay(
            anchor: anchor,
            ticks: bodyBatteryPreviewTicks,
            baseline: baseline
        )
        bodyBatteryPreview = Int(result.value.rounded())
        bodyBatteryPreviewAt = date
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
        // The ticks the board's 72 was made of: five minutes apart from the 04:00 cut to now,
        // asleep and low until the peak, awake and moving after it, with one hour missing
        // where the band came off — so the trace on 13 has a gap to draw rather than a
        // straight line across an hour nobody wore it.
        var ticks: [VitalSample] = []
        var t = m.day.start
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 1_000) / 1_000
        }
        while t <= Date() {
            let hour = Calendar.current.component(.hour, from: t)
            let offWrist = hour == 13
            let asleep = hour < 7
            if !offWrist {
                // 04B · the second page reads the same ticks: a skin temperature that climbs
                // through the day, and the five minutes' steps, kcal and metres — heavy in
                // the 18:00 session, nothing while asleep.
                let session = hour == 18
                let steps = asleep ? 0 : session ? Int(120 + rnd() * 60) : Int(rnd() * 40)
                ticks.append(VitalSample(
                    ts: t,
                    hr: Int((asleep ? 49 : 68) + rnd() * (asleep ? 6 : 22)),
                    stress: Int((asleep ? 12 : 26) + rnd() * (asleep ? 8 : 30)),
                    temp: (asleep ? 35.9 : session ? 36.7 : 36.4) + rnd() * 0.2,
                    steps: steps,
                    cal: Double(steps) * 0.04 + (asleep ? 0.2 : 0.6),
                    dis: Double(steps) * 0.72))
            }
            t = t.addingTimeInterval(300)
        }
        m.vitalsCurve = ticks
        // 01 · the charge line on the default screen: a steady evening charge at +2 a tick,
        // full about seventy minutes out — inside every one of 1CVO's four conditions.
        let now = Date()
        m.reserveCurve = (0...12).map { i in
            ReserveSample(ts: now.addingTimeInterval(Double(i - 12) * 300), value: 48 + i * 2)
        }
        // 04B · SLEEP · 7H 12M, DEEP 1H 48M, 2 WAKES — the board's card, with the band's own
        // line behind it (total = deep + light; the two wakes are minutes off the count).
        m.sleep = SleepSummary(totalMinutes: 432, deepMinutes: 108, lightMinutes: 324, wakeCount: 2,
                               line: [SleepStageRun(stage: 1, minutes: 84), SleepStageRun(stage: 0, minutes: 60),
                                      SleepStageRun(stage: 1, minutes: 110), SleepStageRun(stage: 4, minutes: 4),
                                      SleepStageRun(stage: 0, minutes: 48), SleepStageRun(stage: 1, minutes: 130),
                                      SleepStageRun(stage: 4, minutes: 4)])
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
        // What is left moves with the row, the same instant — the tile and the LOGGED frame
        // both read it, and both used to wait for the next reload.
        if let t = today.targetIn { today.nextMeal = max(0, t - (today.eIn ?? 0)) }
        let slots = Set(confirmed.map(\.slot)).count
        today.fuelState = confirmed.isEmpty ? .unlogged : (slots >= 4 ? .confirmed : .partial(slots: slots))
        // The macro rows are the day's own meals added up (same rule as Repository.load):
        // a plate logged just now moves the tile the same instant, not on the next reload.
        if !confirmed.isEmpty {
            let p = confirmed.reduce(0) { $0 + $1.protein }
            let c = confirmed.reduce(0) { $0 + $1.carb }
            let f = confirmed.reduce(0) { $0 + $1.fat }
            today.protein = today.protein.map { MacroSlot(target: $0.target, eaten: p) }
            today.carb    = today.carb.map    { MacroSlot(target: $0.target, eaten: c) }
            today.fat     = today.fat.map     { MacroSlot(target: $0.target, eaten: f) }
        }
        objectWillChange.send()
    }

    func addWeighIn(_ w: WeighIn) {
        weighIns.append(w)
        weighIns.sort { $0.date > $1.date }
        // 10S rule 09 · optimistic: the page updates now, the row goes up when it can.
        if let ownerUserId = SupabaseClient.currentUserIdSnapshot() {
            WeighInQueue.shared.enqueue(w, ownerUserId: ownerUserId)
        }
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
                      text: "Half a bowl of noodles + one egg", kcal: 310, protein: 14, carb: 42, fat: 9, source: .voice),
            MealEntry(id: UUID(), day: day, at: at(8, 10), slot: .breakfast, status: .confirmed,
                      text: "Oats, Greek yoghurt, blueberries", kcal: 420, protein: 28, carb: 52, fat: 11, source: .typed),
            MealEntry(id: UUID(), day: day, at: at(12, 40), slot: .lunch, status: .confirmed,
                      text: "Chicken salad with quinoa", kcal: 510, protein: 42, carb: 38, fat: 22, source: .photo),
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
    /// 10S rule 04 · the Health record's own id, so the same sample never enters twice.
    var healthUUID: String? = nil
    /// F6 §05 · D06 · the scale case is gone: V1 has no such device, and this rawValue is
    /// rendered straight onto the evidence card, so keeping it kept a way for the word to
    /// reach a screen. The three that remain are the three that can actually happen.
    enum Origin: String, Hashable { case band = "BAND BIA", health = "APPLE HEALTH", manual = "MANUAL" }

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

    /// The name every screen draws. The gate has no username field and onboarding never
    /// asks, so an account can genuinely have none — Apple hands one over at the first
    /// authorization and nowhere else. Rather than each screen inventing its own empty
    /// state, an account with no name of its own is called YOU, everywhere, always.
    var displayName: String { name.isEmpty ? "YOU" : name }

    /// What the avatar circle carries: one letter per word, at most two.
    var initials: String {
        let words = displayName.split(separator: " ")
        let letters = [words.first, words.count > 1 ? words.last : nil]
            .compactMap { $0?.first }.map(String.init)
        return letters.joined().uppercased()
    }

    var age: Int { Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 34 }
    var hrMax: Int { Int((208 - 0.7 * Double(age)).rounded()) }   // Tanaka

    /// A device before the profile row has been read: no name (the header says YOU) and no
    /// invented birthday. hrMax off this means nothing, which is fine — no zone is computed
    /// on the phone (F2 rule 02); the row from onboarding replaces it on the first load.
    static let blank = Profile(
        name: "", email: "",
        birthdate: Calendar.current.date(byAdding: .year, value: -30, to: Date())!,
        heightCm: 170, sexIsMale: true, goal: .recomp,
        usesMetric: true, appleHealthLinked: false)

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
    /// nil until the band has answered readBattery — the pip draws an empty shell and a
    /// dash, never 82% (02 rule 05 · an invented percent is the one thing it must not show).
    var batteryPercent: Int?
    var firmware: String
    var lastSync: Date
    var capabilities: Set<Capability>

    enum Capability: String, Hashable, CaseIterable {
        case heartRate, bloodOxygen, bloodPressure, ecg, temperature, bodyComponent, wearDetection, alarms
    }

    /// A real phone before the band has answered anything. Every field fills in from the
    /// band itself (BandPresence) or from the devices row; none of them is guessed.
    static let unknown = BandState(connected: false, name: "HOOP", mac: "",
                                   batteryPercent: nil, firmware: "",
                                   lastSync: .distantPast, capabilities: [])

    static let mock = BandState(connected: true, name: "NEXTBODY HOOP", mac: "C4:2E:8F:1A:73:9D",
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
        #if DEBUG
        // `SIMCTL_CHILD_NB_DEBUG_STAGE=gateConnect` opens the app at that gate for a walk.
        if let s = ProcessInfo.processInfo.environment["NB_DEBUG_STAGE"], let st = Stage(rawValue: s) { stage = st }
        #endif
    }

    func reset() {
        stage = .gateSignIn; isSignedIn = false; email = ""
        // The Keychain copy of the session goes too, or the next launch would restore it
        // straight past the gate.
        Task { await SupabaseClient.shared.signOut() }
    }

    /// 11 · DELETE EVERYTHING, the phone half of it. reset() is a sign-out, and a sign-out
    /// is explicitly not this: 「The HOOP stays paired and keeps recording. Your data comes
    /// back when you sign in.」 Delete promises the opposite in the same sheet — the band
    /// unpairs itself, and there is no undo — so nothing the account wrote may survive here.
    ///
    /// ⚠️ Everything the app stores is a `nb.` key, so this is a sweep rather than a list:
    /// a list is a thing to forget to add to, and what is forgotten is a weigh-in queue that
    /// flushes into the next account, or a sync watermark that makes a re-registered phone
    /// skip the days it has already read. The three in-memory stores are cleared by hand
    /// because they would each write their copy back over the sweep.
    func purgeAfterAccountDelete() {
        DataStore.shared.purge()
        WeighInQueue.shared.purge()
        BodyCompositionQueue.shared.purge()
        ConsentStore.shared.purge()
        Task { await Analytics.shared.purge() }

        // ⚠️ The SDK only offers disconnect(); "forget" is the app dropping its own device
        // id — the same pair of sentences as FORGET THIS HOOP, and no more than that.
        BoundBand.forget()
        Task { await Band.live.disconnect() }

        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("nb.") {
            defaults.removeObject(forKey: key)
        }

        // Last, so the gate stage it writes is the one that survives the sweep.
        reset()
    }
}
