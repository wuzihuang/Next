import Foundation

// F2 · The Numbers. Every symbol on screen has an entry here.
// Rule 05: unknown never degrades to 0 — the data layer writes nil, the screen writes "——".

/// F2 rule 03 · one calendar. A user day runs local 04:00 → 04:00 next day.
struct UserDay: Hashable, Identifiable, Comparable, Codable {
    /// The instant the window opens: local 04:00 on the day it starts.
    let date: Date
    var id: Date { date }

    /// Two user days are the same day if they start on the same calendar date.
    /// ⚠️ Comparing the instants directly breaks across a DST change and across the two
    /// places a UserDay is built — from `now`, and from a `yyyy-MM-dd` string off the wire.
    static func == (a: UserDay, b: UserDay) -> Bool {
        Calendar.current.isDate(a.date, inSameDayAs: b.date)
    }

    func hash(into hasher: inout Hasher) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        hasher.combine(c.year); hasher.combine(c.month); hasher.combine(c.day)
    }

    static let boundaryHour = 4

    static func containing(_ instant: Date, calendar: Calendar = .current) -> UserDay {
        var cal = calendar
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: instant)
        var start = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day))!
        if (comps.hour ?? 0) < boundaryHour {
            start = cal.date(byAdding: .day, value: -1, to: start)!
        }
        return UserDay(date: cal.date(byAdding: .hour, value: boundaryHour, to: start)!)
    }

    var start: Date { date }
    var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: date)! }

    func adding(days: Int) -> UserDay {
        UserDay(date: Calendar.current.date(byAdding: .day, value: days, to: date)!)
    }

    /// Minutes elapsed inside the window at `now`, capped to the full window.
    func elapsedMinutes(at now: Date = Date()) -> Int {
        max(0, min(1440, Int(now.timeIntervalSince(start) / 60)))
    }

    var isClosed: Bool { Date() >= end }

    static func < (a: UserDay, b: UserDay) -> Bool { a.date < b.date }
}

/// F2 §06 · Daily Direction. Three colours plus two greys — never mixed with The Call's palette.
enum DailyDirection: String, Codable, Hashable {
    case deficit        // BALANCE ≤ −150 kcal · solid lemon
    case level          // −150 < BALANCE < +150 · outline only
    case surplus        // BALANCE ≥ +150 kcal · red
    case greyNothing    // UNLOGGED, or PARTIAL with a single slot
    case greyNoBurn     // logged food, but band coverage < 50%

    static func from(balance: Double?, fuel: FuelState, bandCoverage: Double, closed: Bool) -> DailyDirection {
        guard closed else { return .greyNothing }
        switch fuel {
        case .unlogged: return .greyNothing
        case .partial(let slots) where slots < 2: return .greyNothing
        default: break
        }
        guard bandCoverage >= 0.5 else { return .greyNoBurn }
        guard let b = balance else { return .greyNothing }
        if b <= -150 { return .deficit }
        if b >= 150 { return .surplus }
        return .level
    }
}

/// The state of a day's eating record. FASTED's 0 is an assertion; UNLOGGED's nil is silence.
enum FuelState: Hashable, Codable {
    case unlogged
    case partial(slots: Int)
    case fasted
    case confirmed
}

/// F2 §05 · The Call. Four quadrants, never mixed with Daily Direction's colours.
enum TheCall: String, Codable, Hashable {
    case recomp = "RECOMP"
    case cut = "CUT"
    case bulk = "BULK"
    case drift = "DRIFT"
    case noChange = "MEASURED, NO CHANGE"

    static let fatBand = 0.15   // kg
    static let leanBand = 0.10  // kg

    static func from(fatDelta7d: Double, leanDelta7d: Double) -> TheCall {
        let fatDown = fatDelta7d < -fatBand, fatUp = fatDelta7d > fatBand
        let leanUp = leanDelta7d > leanBand, leanDown = leanDelta7d < -leanBand
        if leanUp { return fatUp ? .bulk : .recomp }
        if leanDown { return fatUp ? .drift : .cut }
        if fatDown { return .cut }
        if fatUp { return .bulk }
        return .noChange
    }
}

/// Three spellings only — never a fourth (F2 §05).
enum Confidence: String, Codable, Hashable {
    case pending = "PENDING", medium = "MEDIUM", high = "HIGH"

    static func from(scans7d n: Int, sigma: Double) -> Confidence {
        if n >= 7 && sigma <= 0.35 { return .high }
        if n >= 5 && sigma <= 0.70 { return .medium }
        return .pending
    }
}

enum Goal: String, Codable, CaseIterable, Hashable {
    case cut = "CUT", recomp = "RECOMP", bulk = "BULK"

    var energyDelta: Double { switch self { case .cut: -600; case .recomp: -380; case .bulk: 300 } }
    var proteinPerKg: Double { switch self { case .cut: 2.0; case .recomp: 1.9; case .bulk: 1.6 } }
    var fatPerKg: Double { switch self { case .cut: 0.8; case .recomp: 0.8; case .bulk: 0.9 } }
}

/// F2 §03 · one set of boundaries used for both zones and load weights.
enum HRZone: Int, CaseIterable, Hashable {
    case below = 0, z1, z2, z3, z4, z5

    /// Lower bound of heart-rate reserve.
    var hrrFloor: Double { [0, 0.30, 0.40, 0.55, 0.70, 0.85][rawValue] }
    var loadWeight: Double { [0.00, 0.15, 0.50, 1.20, 3.00, 6.00][rawValue] }
    var label: String { ["BELOW", "Z1", "Z2", "Z3", "Z4", "Z5"][rawValue] }

    static func of(hrr: Double) -> HRZone {
        for z in HRZone.allCases.reversed() where hrr >= z.hrrFloor { return z }
        return .below
    }
}

/// 13 · WHY <n>. Four terms that must add up to the number printed on top, ±0.5.
/// They are additive on purpose: a multiplicative model cannot be listed as rows.
struct ReserveDrivers: Codable, Hashable {
    var lastNight: Double
    var awake: Double
    var movement: Double
    var stress: Double
    /// Where the day started at 04:00 — yesterday's closing value.
    var anchor: Int
    /// True when there was no yesterday and the 20 is the cold-start assumption. The page
    /// has to say so in words rather than let it read as something we measured.
    var assumedAnchor: Bool = false

    var sum: Double { lastNight + awake + movement + stress }
}

/// 13 · LAST NIGHT'S INPUTS. Every field is optional because the card's whole job is to
/// show what the multiplier was computed from — a value we do not have has to read "——".
struct NightInputs: Codable, Hashable {
    var hrv: Double?
    var hrvBase: Double?
    var rhr: Double?
    var rhrBase: Double?
    var rhrNights: Int = 0
    var multiplier: Double?

    /// The card's "n OF 3" — how many of the three inputs actually arrived.
    var present: Int { (hrv != nil ? 1 : 0) + (rhr != nil ? 1 : 0) + (multiplier != nil ? 1 : 0) }
}

/// 08 · one row of TODAY'S BUILD. The rows are shares of the day's raw work, so the
/// column adds up to the number on the ring rather than overshooting it.
struct TrainingSegment: Codable, Hashable, Identifiable {
    var id: Date { at }
    var at: Date
    var name: String
    var minutes: Int?
    var avgHR: Int?
    var steps: Int?
    var delta: Double
    var allDay: Bool
}

/// One point on the cumulative load curve — TRAINING_LOAD as it stood at that instant.
struct LoadPoint: Codable, Hashable {
    let ts: Date
    let load: Double
}

/// One point on the reserve curve. 288 of them make a day at five-minute ticks.
struct ReserveSample: Codable, Hashable {
    let ts: Date
    let value: Int
}

/// F2 §02 · one row of daily_metrics. Everything is computed server-side; the app only lays it out.
struct DailyMetrics: Codable, Hashable, Identifiable {
    var id: Date { day.date }
    let day: UserDay

    // Training Load 0–21 · never a percentage
    var trainingLoad: Double?          // TRAINING_LOAD
    var targetLoad: Double?            // TARGET_LOAD, from BB_WAKE
    var optimalZone: ClosedRange<Double>?
    var zoneMinutes: [Int]?            // ZONE_MIN[1..5], always multiples of 5
    var segments: [TrainingSegment] = []
    /// The cumulative curve 08 draws THROUGH THE DAY.
    var loadCurve: [LoadPoint] = []
    var peakHR: Int?

    // Body Battery
    var bbWake: Int?                   // BB_WAKE — frozen for the day
    var bodyBattery: Int?              // BODY_BATTERY(t) — the live curve
    // 13 · the four attribution rows, and the curve behind them. Both come from the
    // server so the detail page never has to re-derive a number the day already settled.
    var reserveDrivers: ReserveDrivers?
    var reserveCurve: [ReserveSample] = []
    var nightInputs: NightInputs?

    // Energy
    var bmr: Double?                   // the part of the baseline that has elapsed
    var bmrFull: Double?               // the whole day's baseline — 10's header is an estimate
    var eActive: Double?
    var eTrain: Double?
    var eTrainPlan: Double?
    var eOutNow: Double?
    var activeForecast: Double?
    var eOutFull: Double?
    var eIn: Double?                   // nil = UNLOGGED
    var balance: Double?               // E_IN − E_OUT_NOW
    var targetIn: Double?              // TARGET_IN
    var protein: MacroSlot?
    var carb: MacroSlot?
    var fat: MacroSlot?
    var nextMeal: Double?
    /// What actually went in that day, and the weight its targets were set against.
    /// 12 averages the protein over seven days to score one of THE CALL's four signals.
    var proteinIn: Int?
    var carbIn: Int?
    var fatIn: Int?
    /// The day's steps, taken off the all-day segment rather than stored twice.
    var steps: Int? { segments.first(where: \.allDay)?.steps }              // NEXT_MEAL

    // Composition
    var weightKg: Double?
    var fatKg: Double?
    var leanKg: Double?
    var fatSource: MeasurementSource?
    var fatEmaDelta7d: Double?
    var leanEmaDelta7d: Double?
    /// THE_CALL as the server settled it. F3 §00 · one source, one instant.
    var serverCall: TheCall?
    var confidence: Confidence = .pending
    var scans7d: Int = 0
    var logged7d: Int = 0

    // Bookkeeping
    var fuelState: FuelState = .unlogged
    var bandCoverage: Double = 0
    var calcVersion: String = "1.0.0"
    var asOf: Date?

    /// F2 rule 02 · the direction is computed server-side and written to daily_results.
    /// The local calculation only exists for the provisional, offline view of today.
    var serverDirection: DailyDirection?

    var direction: DailyDirection {
        serverDirection ?? DailyDirection.from(balance: balance, fuel: fuelState,
                                               bandCoverage: bandCoverage, closed: day.isClosed)
    }

    // optimalZone is a range; it stays out of the wire format and is rebuilt server-side.
    private enum CodingKeys: String, CodingKey {
        case day, trainingLoad, targetLoad, zoneMinutes, bbWake, bodyBattery
        case bmr, eActive, eTrain, eTrainPlan, eOutNow, activeForecast, eOutFull
        case eIn, balance, targetIn, nextMeal, protein, carb, fat
        case weightKg, fatKg, leanKg, fatSource
        case fatEmaDelta7d, leanEmaDelta7d, confidence, scans7d, logged7d
        case fuelState, bandCoverage, calcVersion, asOf, serverDirection
    }

    init(day: UserDay) { self.day = day }
}

/// One macro row: a target and how much of it has been eaten.
struct MacroSlot: Codable, Hashable {
    var target: Int
    var eaten: Int
}

enum MeasurementSource: String, Codable, Hashable {
    case measured = "MEASURED"     // band BIA or a body-fat scale — re-anchors the EMA
    case derived = "DERIVED"       // weight × body-fat %
    case estimated = "ESTIMATED"
}

/// F2 rule 05 rendered: a number that isn't there is an em-dash, never a zero.
enum Fmt {
    static let dash = "——"

    static func load(_ v: Double?) -> String { v.map { String(format: "%.1f", min($0, 20.9)) } ?? dash }
    static func kcal(_ v: Double?) -> String {
        guard let v else { return dash }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? dash
    }
    static func signedKcal(_ v: Double?) -> String {
        guard let v else { return dash }
        return (v < 0 ? "−" : "+") + kcal(abs(v))
    }
    static func kg(_ v: Double?, decimals: Int = 1) -> String {
        v.map { String(format: "%.\(decimals)f", $0) } ?? dash
    }
    static func signedKg(_ v: Double?, decimals: Int = 2) -> String {
        guard let v else { return dash }
        return (v < 0 ? "−" : "+") + String(format: "%.\(decimals)f", abs(v))
    }
    static func int(_ v: Int?) -> String { v.map(String.init) ?? dash }
    /// 13 · the attribution rows carry their own sign, and a zero row reads "0", not "+0".
    static func signed(_ v: Double) -> String {
        let n = Int(v.rounded())
        return n > 0 ? "+\(n)" : "\(n)"
    }
    static func pct(_ v: Int?) -> String { v.map { "\($0)%" } ?? dash }
    /// 08 · zone time. Minutes below an hour read plainly; an hour or more takes the
    /// board's "4H 12M" shape. ⚠️ Every duration here is a multiple of five, because the
    /// raw points are five minutes apart — never round one to something finer.
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) MIN" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)H" : "\(h)H \(m)M"
    }

    static func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"; return f.string(from: d).uppercased()
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}
