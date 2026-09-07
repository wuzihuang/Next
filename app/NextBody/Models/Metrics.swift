import Foundation

// F2 · The Numbers. Every symbol on screen has an entry here.
// Rule 05: unknown never degrades to 0 — the data layer writes nil, the screen writes "——".

/// F2 §06 · Daily Direction. Three colours plus two greys — never mixed with The Call's palette.
enum DailyDirection: String, Codable, Hashable {
    case deficit        // BALANCE ≤ −150 kcal · solid lemon
    case level          // −150 < BALANCE < +150 · outline only
    case surplus        // BALANCE ≥ +150 kcal · red
    case greyNothing    // UNLOGGED, or PARTIAL with a single slot
    case greyNoBurn     // logged food, but band coverage < 50%

    static func from(balance: Double?, fuel: FuelState, bandCoverage: Double) -> DailyDirection {
        let policyFuel: DailyDirectionPolicy.Fuel
        switch fuel {
        case .unlogged: policyFuel = .unlogged
        case .partial(let slots): policyFuel = .partial(slots: slots)
        case .fasted: policyFuel = .fasted
        case .confirmed: policyFuel = .confirmed
        }
        switch DailyDirectionPolicy.color(balance: balance, fuel: policyFuel, bandCoverage: bandCoverage) {
        case .deficit: return .deficit
        case .level: return .level
        case .surplus: return .surplus
        case .greyNothing: return .greyNothing
        case .greyNoBurn: return .greyNoBurn
        }
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

/// Evidence quality for reserve only. The composition verdict has a separate Confidence.
enum BodyBatteryConfidence: String, Codable, Hashable {
    case low = "LOW", medium = "MEDIUM", high = "HIGH"
}

struct BodyBatteryCoverage: Codable, Hashable {
    var nightHRV: Double?
    var nightRHR: Double?
    var nightExpectedMinutes: Int?
    var nightHRVMinutes: Int?
    var nightRHRMinutes: Int?
    var nightHRVLongestGap: Int?
    var nightRHRLongestGap: Int?
    var hrvNights: Int?
    var rhrNights: Int?
    var dayHeart: Double?
    var dayHRV: Double?
    var dayStress: Double?
    var dayExpectedTicks: Int?
    var dayObservedTicks: Int?
}

/// 13 · WHY <n>. Four user-day terms that close to current minus anchor.
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

    /// Old servers called user-day charge `last_night`. New clients never present that
    /// legacy field as the entire night's charge; a night can cross the 04:00 boundary.
    var dayCharge: Double? = nil
    var nightCharge: Double? = nil
    var wakeAt: Date? = nil
    var observedAt: Date? = nil
    var confidence: BodyBatteryConfidence? = nil
    var coverage: BodyBatteryCoverage? = nil
    var algoVersion: String? = nil

    var chargeForDay: Double { dayCharge ?? lastNight }
    var sum: Double { chargeForDay + awake + movement + stress }
}

/// 13 · LAST NIGHT'S INPUTS. Every field is optional because the card's whole job is to
/// show what the multiplier was computed from — a value we do not have has to read "——".
struct NightInputs: Codable, Hashable {
    var hrv: Double?
    var hrvBase: Double?
    var rhr: Double?
    var rhrBase: Double?
    var rhrNights: Int = 0
    /// How many of the last fourteen nights had an HRV of their own. Its own count: a night
    /// the band measured HRV through is not the same set as one it measured a resting pulse in.
    var hrvNights: Int = 0
    var multiplier: Double?

    /// The card's "n OF 3" — how many of the three inputs actually arrived.
    var present: Int { (hrv != nil ? 1 : 0) + (rhr != nil ? 1 : 0) + (multiplier != nil ? 1 : 0) }
}

/// Server-published observation coverage. Recorded time is not a wear assertion.
struct TrainingEvidence: Codable, Hashable {
    var elapsedMinutes: Int
    var recordedMinutes: Int
    var heartRateMinutes: Int
    var movementMinutes: Int
    var restingHeartRate: Double?
    var restingBaselineNights: Int
    var baselineEstimated: Bool
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

/// One five-minute tick as the band recorded it: what the heart was doing and what the
/// stress index read. Both are optional and neither is ever filled in — a tick taken off
/// the wrist has no heart and no stress, and that absence is the whole point of the row.
/// 04B · SLEEP card. The night OriginDataSync stored under this user day — what the band
/// reported, as measurements. The score built on top of it is a separate, server-settled
/// row (`SleepScore`, ADR 0008) and never a field here. The whole reason it is a struct of its own is
/// that 13 板 forbids sleep on the battery page while 04B prints it first; both read one row.
struct SleepInterval: Codable, Hashable {
    var start: Date
    var end: Date
}

/// ADR 0008 · the night's settled score, computed server-side once and read back whole.
/// Four groups, weighted 25 / 25 / 35 / 15; a group is nil when nothing it needs was
/// recorded, and the total is renormalised over the groups that remain. There is no
/// client-side arithmetic here on purpose — a score the phone re-derived could disagree
/// with the same night seen from the week window.
struct SleepScore: Codable, Hashable {
    var score: Int
    var duration: Int?
    var architecture: Int?
    var recovery: Int?
    var regularity: Int?
    /// 0 = scored against population baselines, 1 = fully against this person's own.
    /// Ramps between the 14th and 28th night; the board says so while it is below 1.
    var personalWeight: Double = 0
    /// The measured values behind the score. Membership is the point: a key that is absent
    /// is an input the night did not have, and that is what the breakdown prints.
    var inputs: [String: Double] = [:]
    var version: String = ""
    var computedAt: Date? = nil

    var isCalibrating: Bool { personalWeight < 1 }

    func value(of group: SleepScoreGroup) -> Int? {
        switch group {
        case .duration:     duration
        case .architecture: architecture
        case .recovery:     recovery
        case .regularity:   regularity
        }
    }
}

/// Cached scores remain visible while their next read is pending or unavailable.
enum SleepScoreLoadState {
    case idle, loading, ready, failed
}

/// The four groups, in the order the breakdown prints them. Splitting duration away from
/// architecture is what lets the board say "you slept enough, the structure was poor" —
/// one bar carrying both cancels that sentence out.
enum SleepScoreGroup: String, CaseIterable, Hashable {
    case duration, architecture, recovery, regularity

    var title: String {
        switch self {
        case .duration:     L("DURATION")
        case .architecture: L("STRUCTURE")
        case .recovery:     L("RECOVERY")
        case .regularity:   L("REGULARITY")
        }
    }

    var weight: Int {
        switch self {
        case .duration:     25
        case .architecture: 25
        case .recovery:     35
        case .regularity:   15
        }
    }

    /// The keys this group scores over, named as the server names them in `inputs`.
    var memberKeys: [String] {
        switch self {
        case .duration:     ["duration_min"]
        case .architecture: ["deep_pct", "rem_pct", "wakes"]
        case .recovery:     ["hrv_ms", "rhr", "spo2_min", "respiration"]
        case .regularity:   ["bed_offset"]
        }
    }
}

struct SleepSummary: Codable, Hashable {
    var totalMinutes: Int
    var deepMinutes: Int
    var lightMinutes: Int
    var wakeCount: Int
    /// 04B rule 04 · the band's own sleepLine as stage runs, drawn as-is: deep full height,
    /// light half, awake a short mark — never re-segmented by the app. Empty on nights
    /// stored before the line was kept; the strip falls back to proportions for those.
    var line: [SleepStageRun] = []
    /// The band's own window for the night. nil on rows stored before the two columns
    /// existed — the hypnogram then runs on the line's own minutes and prints no clock,
    /// because a bed time inferred from a duration is a bed time nobody measured.
    var sleepStart: Date?
    var wakeAt: Date?

    /// The night's REM and awake minutes, which only the line can answer: the row stores
    /// deep and light, and the remainder is not one stage. Zero when there is no line.
    var remMinutes: Int { line.filter { $0.stage == 2 }.reduce(0) { $0 + $1.minutes } }
    var awakeMinutes: Int { line.filter { $0.stage >= 3 }.reduce(0) { $0 + $1.minutes } }
    /// Overnight automatic SpO2 inside this night's window. Empty when the band filed none.
    var spo2: [OvernightOxygenPoint] = []
    /// Automatic respiratory measurements in the recorded sleep window; nil in older archives.
    var respiration: [SleepRespirationPoint]? = nil
    /// RMSSD at the actual recorded RR minute, independent of the five-minute origin grid.
    var hrv: [SleepHRVPoint]? = nil
    /// Explicit RR corrections by measured minute and observation clock. Missing reads
    /// never populate this map; it prevents older snapshots from restoring disproved HRV.
    var hrvInvalidatedMinutes: [Date: Date]? = nil
    /// Actual recorded sessions; the gaps between them are not sleep measurements.
    var intervals: [SleepInterval]? = nil

    func containsSleepTimestamp(_ timestamp: Date) -> Bool {
        guard let sleepStart, let wakeAt, wakeAt > sleepStart,
              timestamp >= sleepStart, timestamp < wakeAt else { return false }
        guard let intervals else { return true }
        return intervals.contains { $0.end > $0.start && timestamp >= $0.start && timestamp < $0.end }
    }
}

struct SleepHRVPoint: Codable, Hashable {
    var ts: Date
    var rmssdMS: Double
    var observedAt: Date? = nil

    static func merging(_ stored: [SleepHRVPoint], with fresh: [SleepHRVPoint],
                        invalidatedMinutes: [Date: Date]) -> [SleepHRVPoint] {
        var points: [Date: SleepHRVPoint] = [:]
        for point in stored + fresh where point.rmssdMS.isFinite && (1...300).contains(point.rmssdMS) {
            if let current = points[point.ts], let previousClock = current.observedAt,
               point.observedAt.map({ $0 <= previousClock }) ?? true { continue }
            points[point.ts] = point
        }
        return points.values.filter { point in
            guard let invalidatedAt = invalidatedMinutes[point.ts] else { return true }
            return point.observedAt.map { $0 > invalidatedAt } ?? false
        }.sorted { $0.ts < $1.ts }
    }
}

/// One respiratory reading from the SDK's automatic history, retained on the night's clock.
struct SleepRespirationPoint: Codable, Hashable {
    var ts: Date
    var breathsPerMinute: Double
}

/// One automatic oxygen reading clipped to the recorded night. Not an apnea event.
struct OvernightOxygenPoint: Codable, Hashable {
    var ts: Date
    var percent: Int
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
    /// 补屏 B · true without a weight: met ≥ 3 points × 5, and the band's own metres.
    var activeMinutes: Int?
    var distanceM: Int?
    var segments: [TrainingSegment] = []
    /// The cumulative curve 08 draws THROUGH THE DAY.
    var loadCurve: [LoadPoint] = []
    var peakHR: Int?
    var trainingEvidence: TrainingEvidence?
    var recordedSteps: Int?

    // Body Battery
    var bbWake: Int?                   // BB_WAKE — frozen for the day
    var bodyBattery: Int?              // BODY_BATTERY(t) — the live curve
    // 13 · the four attribution rows, and the curve behind them. Both come from the
    // server so the detail page never has to re-derive a number the day already settled.
    var reserveDrivers: ReserveDrivers?
    var reserveCurve: [ReserveSample] = []
    /// 13 · the ticks the battery is made of. Heart and stress are two of the four rows in
    /// WHY, so the page shows them as measurements rather than only as attributions.
    var vitalsCurve: [VitalSample] = []
    var nightInputs: NightInputs?

    /// The time of reserve evidence, never a network fetch or another metric's update.
    var bodyBatteryObservedAt: Date? {
        reserveDrivers?.observedAt ?? reserveCurve.last?.ts
    }

    var bodyBatteryWakeAt: Date? {
        guard bbWake != nil else { return nil }
        return reserveDrivers?.wakeAt ?? sleep?.wakeAt
    }

    var bodyBatteryConfidence: BodyBatteryConfidence {
        reserveDrivers?.confidence ?? .low
    }

    func bodyBatteryFreshness(at now: Date = Date()) -> TickFreshness {
        TickFreshness.of(bodyBatteryObservedAt, now: now)
    }

    func bodyBatteryForDisplay(at now: Date = Date()) -> Int? {
        guard bodyBatteryFreshness(at: now) != .gone else { return nil }
        return bodyBattery
    }
    /// ADR 0008 · the settled sleep score for the night that ended on this day. nil until
    /// the server has settled it, which is also what a night with no record looks like.
    var sleepScore: SleepScore?
    /// 04B · last night, from sleep_nights. nil until the band has answered readSleep.
    var sleep: SleepSummary?

    // Energy
    var bmr: Double?                   // the part of the baseline that has elapsed
    var bmrFull: Double?               // the whole day's baseline — 10's header is an estimate
    var eActive: Double?
    var energyDistribution: [FuelEnergyPoint]?
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
    /// All recorded activity, including steps inside elevated-heart-rate segments.
    /// Old servers do not expose a trustworthy day total; never label an ordinary-only
    /// segment as the whole day when exercise segments are also present.
    var steps: Int? {
        if let recordedSteps { return recordedSteps }
        guard segments.allSatisfy(\.allDay) else { return nil }
        return segments.first(where: \.allDay)?.steps
    }

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
    /// The local calculation is the live view of today (and the offline fallback):
    /// calendar close is not a gate, or the heat map stays empty until 04:00.
    var serverDirection: DailyDirection?
    /// ADR 0010 · settled worn day. nil until the server has said.
    var worn: Bool?
    var wearRun: Int?
    var wearMiss: Int?

    var direction: DailyDirection {
        serverDirection ?? DailyDirection.from(balance: balance, fuel: fuelState,
                                               bandCoverage: bandCoverage)
    }

    // optimalZone is a range; it stays out of the wire format and is rebuilt server-side.
    private enum CodingKeys: String, CodingKey {
        case day, trainingLoad, targetLoad, zoneMinutes, activeMinutes, distanceM, bbWake, bodyBattery
        case trainingEvidence, recordedSteps
        case bmr, eActive, eTrain, eTrainPlan, eOutNow, activeForecast, eOutFull, energyDistribution
        case eIn, balance, targetIn, nextMeal, protein, carb, fat
        case weightKg, fatKg, leanKg, fatSource
        case fatEmaDelta7d, leanEmaDelta7d, confidence, scans7d, logged7d
        case fuelState, bandCoverage, calcVersion, asOf, serverDirection
        case worn, wearRun, wearMiss, sleepScore
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
        return kcalFormatter.string(from: NSNumber(value: v)) ?? dash
    }
    // ⚠️ Formatters are built once. Each of these used to be allocated per call, and the
    // calls sit inside view bodies that run on every frame of an animation.
    private static let kcalFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE"; return f
    }()
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    static func signedKcal(_ v: Double?) -> String {
        guard let v else { return dash }
        return (v < 0 ? "−" : "+") + kcal(abs(v))
    }
    /// Paper 09C pair. Zero is "0", not "+0" — that is the end of TO GO.
    static func pairKcal(_ v: Double) -> String {
        if v == 0 { return kcal(0) }
        return signedKcal(v)
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
        if minutes < 60 { return L("%d MIN", minutes) }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? L("%dH", h) : L("%dH %dM", h, m)
    }

    static func duration(_ minutes: Int?) -> String {
        minutes.map(duration) ?? dash
    }

    static func weekday(_ d: Date) -> String {
        weekdayFormatter.locale = AppLanguage.shared.swiftLocale
        return weekdayFormatter.string(from: d).uppercased()
    }

    static func displayDate(_ d: Date, format: String) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.shared.swiftLocale
        f.dateFormat = format
        return f.string(from: d)
    }

    static func clock(_ d: Date) -> String { clockFormatter.string(from: d) }
}
