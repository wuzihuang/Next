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
    /// ADR 0008 · the settled sleep score per wake-day, keyed by `UserDay.key`. Thirty rows
    /// of smallints, refreshed after settlement and cached with their account's snapshot.
    @Published var sleepScores: [String: SleepScore] = [:]
    @Published var sleepScoreLoadState: SleepScoreLoadState = .idle
    @Published var meals: [MealEntry] = []
    /// The window 12's WEEK view reads. Today's list stays in `meals` so 09 is untouched.
    @Published var recentMeals: [MealEntry] = []
    @Published var weighIns: [WeighIn] = []
    /// ADR 0010 · 主动测量记录，最近的在前。「我的」页那块 MEASUREMENTS 取前三条，测量记录页
    /// 列全部。⚠️ 只有成功完成的测量在这里；体重录入和被动 tick 不进这个数组。
    @Published var measurements: [MeasurementRecord] = []
    /// 10E · 成分页读的每一行 `body_composition`。不限 `device_bia`——秤和手录同样是一次体脂点。
    @Published var compositionScans: [CompositionScan] = []
    @Published var band: BandState = Band.allowsSeed ? .mock : .unknown
    /// Every battery packet and charge switch this phone kept. The device ring opens it.
    @Published var batteryLog: [BatteryObservation] = []
    /// Session-local freshness guard: cloud hydration must not overwrite a BLE observation.
    private(set) var bandObservationRevision = 0

    func applyBandObservation(identity: BandIdentity? = nil, battery: BandBattery? = nil) {
        guard identity != nil || battery != nil else { return }
        if let identity {
            band.name = identity.name
            band.mac = identity.bleIdentifier
            band.firmware = identity.firmware
        }
        if let battery {
            let battery = battery.settled
            band.applyBattery(battery)
            recordBattery(battery, connected: band.connected)
            NotificationReach.evaluate(store: self)
        }
        bandObservationRevision += 1
    }

    func recordBandLink(connected: Bool) {
        let was = band.connected
        band.connected = connected
        guard was != connected else { return }
        NotificationReach.stampDisconnect(connected: connected)
        NotificationReach.evaluate(store: self)
        if connected {
            // A reconnect must not stamp the last packet at NOW. That packet is hours
            // old and sits on the first fresh read as a noon cliff.
            batteryLog = BatteryLog.record(
                batteryLog, at: Date(),
                isPercent: band.lastBattery?.isPercent ?? (band.batteryPercent != nil),
                percent: nil, level: nil,
                charge: BatteryObservation.Charge(rawValue: band.chargeState.rawValue) ?? .unknown,
                connected: true)
            persistBatteryLog()
            return
        }
        if let battery = band.lastBattery {
            recordBattery(battery, connected: false)
        } else {
            // No packet has arrived, so this row carries no reading — and claiming percent
            // here would cast a vote in the plot's unit ballot on behalf of a bars-only band.
            batteryLog = BatteryLog.record(
                batteryLog, at: Date(), isPercent: band.batteryPercent != nil,
                percent: band.batteryPercent, level: nil,
                charge: BatteryObservation.Charge(rawValue: band.chargeState.rawValue) ?? .unknown,
                connected: false)
            persistBatteryLog()
        }
    }

    func hydrateBatteryLog() {
        guard !Band.allowsSeed else { return }
        let loaded = BatteryLogStore.load(owner: batteryOwner)
        let cleaned = loaded.filter { !BatteryDrainMath.isGhost($0) }
        if batteryLog.isEmpty {
            batteryLog = cleaned
            if cleaned.count != loaded.count { persistBatteryLog() }
            return
        }
        let stripped = batteryLog.filter { !BatteryDrainMath.isGhost($0) }
        if stripped.count != batteryLog.count {
            batteryLog = stripped
            persistBatteryLog()
        }
    }

    private var batteryOwner: String {
        let account = SupabaseClient.currentUserIdSnapshot() ?? "none"
        let binding = BoundBand.identifier ?? "none"
        return "\(account).\(binding)"
    }

    private func recordBattery(_ battery: BandBattery, connected: Bool) {
        hydrateBatteryLog()
        if battery.chargeState == .unknown { return }
        batteryLog = BatteryLog.record(
            batteryLog,
            at: Date(),
            isPercent: battery.isPercent,
            percent: battery.percent,
            level: battery.level,
            charge: BatteryObservation.Charge(rawValue: battery.chargeState.rawValue) ?? .unknown,
            connected: connected)
        persistBatteryLog()
    }

    private func persistBatteryLog() {
        guard !Band.allowsSeed else { return }
        BatteryLogStore.save(batteryLog, owner: batteryOwner)
    }
    @Published var profile: Profile = Band.allowsSeed ? .mock : .blank
    /// F3 rule 09 · the moment of the last readOriginData that succeeded. nil until one has:
    /// a phone that has never synced says so, it does not say "12 MIN AGO".
    @Published var lastSync: Date? = Band.allowsSeed ? Date().addingTimeInterval(-12 * 60) : nil
    /// Earliest bind or wrist tick on this account. WITH YOU counts user days from here.
    @Published var boundAt: Date? = Band.allowsSeed
        ? UserDay.containing(Date()).adding(days: -84).start
        : nil
    /// 04 · the HR / STRESS row under the readout, and the tick it came from. 13 · the age
    /// of that tick is what decides whether the numbers are shown, dimmed, or dashed.
    @Published var vitals: LiveVitals = Band.allowsSeed ? .mock : LiveVitals()
    /// 12 · what this HOOP reports it can do, as last stored. The device page and 07's
    /// capabilities() gate read this so they are right before the band answers, and still
    /// right when it is out of range.
    @Published var capabilities = BandCapabilities()
    @Published var capabilitiesReadAt: Date?
    @Published var isOffline = false
    /// Wrist optical meal-response points, last ~30 user days. Dedicated series, never origin ticks.
    @Published var mealResponsePoints: [MealResponseIndex.Point] = []
    /// True when today's vendor table had rows but every value was a zero / empty slot.
    @Published var mealResponseZerosToday = false

    // 11 · the three tiles. Two net changes over twelve weeks and one absolute value,
    // which is why the third one is labelled apart from the other two.
    @Published var netFatMass12w: Double?
    @Published var netLeanMass12w: Double?
    @Published var bodyFatPercent: Double?

    /// Reserve, explanations and curve always come from the same settlement. Live heart
    /// callbacks remain measurements; they cannot publish a second reserve calculation.
    var bodyBatteryNow: Int? { today.bodyBatteryForDisplay() }

    var todayForDisplay: DailyMetrics {
        var metrics = today
        metrics.bodyBattery = today.bodyBatteryForDisplay()
        return metrics
    }

    /// Header flame. Local ticks can light today before the next settle; yesterday's
    /// settled run/miss never cools an open day.
    var wearFlame: WearRun.Flame {
        let todayWorn = WearRun.isWornDay(samples: today.vitalsCurve, day: today.day, now: Date())
            || today.worn == true
        let yesterday = metrics(for: today.day.adding(days: -1))
        return WearRun.display(
            todayWorn: todayWorn,
            yesterday: yesterday.map {
                WearRun.yesterday(
                    worn: $0.worn,
                    run: $0.wearRun,
                    miss: $0.wearMiss,
                    localWorn: WearRun.isWornDay(
                        samples: $0.vitalsCurve, day: $0.day, now: $0.day.end))
            })
    }

    /// Today's merged row, otherwise the history row. The heat map used to look only
    /// at `history`, so the current user day stayed GREY_NOTHING while Fuel already
    /// had the live balance.
    func metrics(for day: UserDay) -> DailyMetrics? {
        if today.day == day { return today }
        return history.first { $0.day == day }
    }

    private init() {
        // The seeded demo account is a returning user: the gate was walked, the band is
        // bound, and the app reconnects to it the way it would on any later launch.
        // ⚠️ Simulator only. On a device a made-up identifier makes the app believe a band
        // is bound before the gate was ever walked, and every launch would try to reconnect.
        if Band.allowsSeed, BoundBand.identifier == nil { BoundBand.identifier = "C4-2E-8F-1A-73-9D" }
        #if DEBUG
        // Simulator regression: enter the real add flow immediately after local removal.
        if Band.allowsSeed, let raw = ProcessInfo.processInfo.environment["NB_DEBUG_RELEASED_SLOT"],
           let released = HoopSlot(rawValue: raw) {
            DeviceSlots.set(SlotBinding(slot: .a, identifier: "C4-2E-8F-1A-73-9D"))
            DeviceSlots.set(SlotBinding(slot: .b, identifier: "8E-41-C0-2B-77-1F"))
            DeviceSlots.remove(released)
        }
        // `SIMCTL_CHILD_NB_DEBUG_SECOND_HOOP=1` seeds the mock's second band into slot B so the
        // two-HOOP DEVICE page (9-0 A) can be walked without tapping through activation.
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_SECOND_HOOP"] != nil,
           DeviceSlots.binding(.b) == nil,
           ProcessInfo.processInfo.environment["NB_DEBUG_RELEASED_SLOT"] == nil {
            DeviceSlots.set(SlotBinding(slot: .b, identifier: "8E-41-C0-2B-77-1F", name: "NEXTBODY HOOP",
                                        boundAt: Date().addingTimeInterval(-2 * 86_400)))
        }
        #endif
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
            measurements = MeasurementRecord.seed
            compositionScans = Self.compositionScans(from: measurements)
            mealResponsePoints = DataStore.seedMealResponse()
            sleepScores = DataStore.seedSleepScores()
            sleepScoreLoadState = .ready
            today.sleepScore = sleepScores[today.day.key]
            for index in history.indices { history[index].sleepScore = sleepScores[history[index].day.key] }
            batteryLog = BatteryLog.seed(now: Date(), percent: band.batteryPercent ?? 82)
        } else {
            today = DailyMetrics(day: UserDay.containing(Date()))
            HomeSnapshot.hydrate(into: self)
            hydrateBatteryLog()
        }
        #if DEBUG
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_SLEEP_EVIDENCE"] == "1" {
            seedSleepEvidenceForUITests()
        }
        #endif
        WidgetGlancePublisher.publish(from: self)
    }

    #if DEBUG
    /// Deterministic simulator fixture for missing evidence and peaks above the old ruler.
    /// It never runs on a physical band or uploads measurements.
    private func seedSleepEvidenceForUITests() {
        let wake = Calendar.current.date(bySettingHour: 12, minute: 39, second: 0, of: Date()) ?? Date()
        let start = wake.addingTimeInterval(-751 * 60)
        let minutes = Array(0..<129) + Array(217..<751)
        let hrvMinutes = Array(0..<82) + Array(491..<751)
        let score = SleepScore(score: 87, duration: 77, architecture: 80, recovery: 99,
            inputs: ["duration_min": 663, "deep_pct": 24.6, "light_pct": 61.4, "rem_pct": 13.3,
                     "rem_min": 88, "wakes": 2, "hrv_ms": 67.4, "hrv_base": 40,
                     "rhr": 54, "rhr_base": 60, "spo2_min": 96, "respiration": 16.9,
                     "hrv_sample_count": 342, "hrv_coverage": 342.0 / 663,
                     "hrv_expected_minutes": 663, "hrv_longest_gap_min": 274,
                     "rhr_sample_count": 133, "rhr_coverage": 1,
                     "rhr_expected_minutes": 663, "rhr_longest_gap_min": 0,
                     "spo2_sample_count": 660, "spo2_coverage": 660.0 / 663,
                     "spo2_expected_minutes": 663, "spo2_longest_gap_min": 3,
                     "respiration_sample_count": 661, "respiration_coverage": 661.0 / 663,
                     "respiration_expected_minutes": 663, "respiration_longest_gap_min": 2,
                     "bed_offset": 368, "baseline_nights": 3, "baseline_hrv_nights": 2, "baseline_rhr_nights": 3,
                     "hrv_personal_weight": 0, "rhr_personal_weight": 0],
            version: "sleep-v1.2", computedAt: Date())
        today.sleep = SleepSummary(totalMinutes: 663, deepMinutes: 163, lightMinutes: 407,
            wakeCount: 2, sleepStart: start, wakeAt: wake,
            spo2: minutes.dropFirst(3).map { .init(ts: start.addingTimeInterval(Double($0) * 60), percent: 97) },
            respiration: minutes.dropFirst(2).map { .init(ts: start.addingTimeInterval(Double($0) * 60), breathsPerMinute: 16.9) },
            hrv: hrvMinutes.enumerated().map { index, minute in
                .init(ts: start.addingTimeInterval(Double(minute) * 60), rmssdMS: index == 0 ? 168 : 67)
            },
            intervals: [.init(start: start, end: start.addingTimeInterval(129 * 60)),
                        .init(start: start.addingTimeInterval(217 * 60), end: wake)])
        sleepScores[today.day.key] = score
        today.sleepScore = score
        sleepScoreLoadState = .ready
    }
    #endif

    /// 11 · DELETE EVERYTHING. By the time this runs the account is gone from the server,
    /// so every number still held here is an orphan — and the gate behind it is a sign-in
    /// screen that would be drawn over yesterday's readout until the app is killed.
    /// Back to the state a phone is in before any account: dashes, not the seeded board.
    /// ⚠️ `isOffline` is not the account's, it is the radio's — Reachability owns it, and
    /// clearing it here would print ONLINE at the gate of a phone in a lift.
    func purge() {
        clearAccountDisplay()
        HomeSnapshot.removeAll()
        WidgetGlancePublisher.clear()
    }

    /// Signing out clears visible identity and readings, while account-owned disk data
    /// and pending operations remain available when their owner signs in again.
    func clearAccountDisplay() {
        WidgetGlancePublisher.clear()
        bandObservationRevision = 0
        today = DailyMetrics(day: UserDay.containing(Date()))
        history = []
        sleepScores = [:]
        sleepScoreLoadState = .idle
        meals = []
        recentMeals = []
        weighIns = []
        measurements = []
        compositionScans = []
        mealResponsePoints = []
        mealResponseZerosToday = false
        band = .unknown
        profile = .blank
        lastSync = nil
        boundAt = nil
        vitals = LiveVitals()
        capabilities = BandCapabilities()
        capabilitiesReadAt = nil
        netFatMass12w = nil
        netLeanMass12w = nil
        bodyFatPercent = nil
        batteryLog = []
        Repository.shared.resetBootstrap()
    }

    static func compositionScans(from records: [MeasurementRecord]) -> [CompositionScan] {
        records.compactMap { record in
            guard case .bodyScan(let scan) = record.detail else { return nil }
            return CompositionScan(
                id: record.id,
                at: record.at,
                bodyFatPercent: scan.bodyFatPercent,
                fatMassKg: scan.fatMassKg,
                leanMassKg: scan.leanMassKg,
                bmrKcal: scan.bmrKcal.map(Double.init),
                inputWeightKg: scan.inputWeightKg
            )
        }
    }

    func rememberBodyScan(_ record: MeasurementRecord) {
        measurements.insert(record, at: 0)
        guard let scan = Self.compositionScans(from: [record]).first else { return }
        compositionScans.removeAll { $0.id == scan.id }
        compositionScans.insert(scan, at: 0)
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
        // 13A · scheme 1: last night +38 from 46, the day spends −12, now is 72.
        m.reserveDrivers = ReserveDrivers(lastNight: 38, awake: -4, movement: -6,
                                          stress: -2, anchor: 46,
                                          dayCharge: 38, nightCharge: 38,
                                          wakeAt: Calendar.current.date(bySettingHour: 7, minute: 12,
                                              second: 0, of: m.day.start),
                                          observedAt: Date(), confidence: .medium,
                                          algoVersion: "bb-2.1")
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
        // #29 · the parts 09 prints under the budget: resting (a scan's), activity so far, goal.
        m.bmrFull = 1960
        m.restingSource = "BODY_SCAN"
        m.restingMeasuredAt = m.day.start
        m.goalOffset = -380
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
        m.worn = true
        m.wearRun = 4
        m.wearMiss = 0
        m.asOf = Date()
        // The ticks the board's 72 was made of: five minutes apart from the earlier of
        // the user-day cut and last night's bed time, so the sleep page has RMSSD to plot.
        var ticks: [VitalSample] = []
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 1_000) / 1_000
        }
        let wakeAt = Calendar.current.date(bySettingHour: 7, minute: 12, second: 0, of: Date())
            ?? m.day.start.addingTimeInterval(3 * 3600 + 12 * 60)
        let sleepStart = wakeAt.addingTimeInterval(-432 * 60)
        var t = min(m.day.start, sleepStart)
        while t <= Date() {
            let hour = Calendar.current.component(.hour, from: t)
            let offWrist = hour == 13
            let asleep = t >= sleepStart && t < wakeAt
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
                    // ⚠️ Wrist skin, not core body: the night sits under the covers and runs
                    // warmer than the exposed daytime arm. 35.9 / 36.4 / 36.7 here taught the
                    // simulator a core-temperature number for a value the band records at 33.
                    temp: (asleep ? 33.8 : session ? 33.1 : 33.4) + rnd() * 0.2,
                    steps: steps,
                    vendorCalories: Double(steps) * 0.04 + (asleep ? 0.2 : 0.6),
                    dis: Double(steps) * 0.72,
                    hrv: (asleep ? 48 : 38) + rnd() * (asleep ? 18 : 16)))
            }
            t = t.addingTimeInterval(300)
        }
        m.vitalsCurve = ticks
        let now = Date()
        // Peak sits on this user day at 07:12, not on the calendar clock of `Date()`
        // — before 04:00 that clock is tomorrow morning.
        m.reserveCurve = seedReserveCurve(
            day: m.day, now: now,
            wakeAt: m.day.start.addingTimeInterval(3 * 3600 + 12 * 60),
            peak: 84, nowValue: 72, anchor: 46)
        // 04B · SLEEP · 7H 12M, DEEP 1H 48M, 2 WAKES — the board's card, with the band's own
        // line behind it (total = deep + light; the two wakes are minutes off the count).
        var spo2: [OvernightOxygenPoint] = []
        var minute = 0
        while minute < 432 {
            let wave = sin(Double(minute) / 80)
            var percent = 96 + Int((wave * 2).rounded())
            if minute == 180 { percent = 91 }
            spo2.append(OvernightOxygenPoint(
                ts: sleepStart.addingTimeInterval(Double(minute) * 60),
                percent: min(100, max(50, percent))))
            minute += 5
        }
        var respiration: [SleepRespirationPoint] = []
        minute = 0
        while minute < 432 {
            let wave = sin(Double(minute) / 55)
            respiration.append(SleepRespirationPoint(
                ts: sleepStart.addingTimeInterval(Double(minute) * 60),
                breathsPerMinute: 13.6 + wave * 2.4))
            minute += 5
        }
        m.sleep = SleepSummary(totalMinutes: 432, deepMinutes: 108, lightMinutes: 324, wakeCount: 2,
                               line: [SleepStageRun(stage: 1, minutes: 84), SleepStageRun(stage: 0, minutes: 60),
                                      SleepStageRun(stage: 1, minutes: 110), SleepStageRun(stage: 4, minutes: 4),
                                      SleepStageRun(stage: 0, minutes: 48), SleepStageRun(stage: 1, minutes: 130),
                                      SleepStageRun(stage: 4, minutes: 4)],
                               sleepStart: sleepStart, wakeAt: wakeAt, spo2: spo2,
                               respiration: respiration)
        let stepTotal = ticks.reduce(0) { $0 + ($1.steps ?? 0) }
        let sessionAt = m.day.start.addingTimeInterval(14 * 3600)
        m.segments = [
            TrainingSegment(at: sessionAt, name: "STRENGTH", minutes: 45, avgHR: 132,
                            steps: 640, delta: 3.2, allDay: false),
            TrainingSegment(at: m.day.start, name: "ALL DAY", minutes: nil, avgHR: nil,
                            steps: stepTotal, delta: 9.2, allDay: true),
        ]
        var curve: [LoadPoint] = []
        var cursor = m.day.start
        while cursor <= now {
            let hours = cursor.timeIntervalSince(m.day.start) / 3600
            let load: Double
            if hours < 5 {
                load = 1.0 * (hours / 5)
            } else if hours < 14 {
                load = 1.0 + 8.2 * ((hours - 5) / 9)
            } else {
                load = min(12.4, 9.2 + 3.2 * min(1, (hours - 14) / 1.5))
            }
            curve.append(LoadPoint(ts: cursor, load: load))
            cursor = cursor.addingTimeInterval(1800)
        }
        if curve.last.map({ abs($0.load - 12.4) > 0.05 }) ?? true {
            curve.append(LoadPoint(ts: now, load: 12.4))
        }
        m.loadCurve = curve
        return m
    }

    /// 12 weeks of history so the heat map on 11 · Profile has something honest to draw.
    /// ADR 0008 · thirty nights of settled sleep score, so the sleep board's day, week and
    /// month windows are walkable on a simulator with no band and no session. Two nights are
    /// deliberately absent — the month bar chart has to be able to show *which* night is
    /// missing — and the run is left mid-calibration so the "typical adults for now" note is
    /// on screen rather than only in the code.
    /// ⚠️ Simulator only, behind `Band.allowsSeed`, like every other number in this file.
    static func seedSleepScores() -> [String: SleepScore] {
        let today = UserDay.containing(Date())
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 10_000) / 10_000
        }
        var out: [String: SleepScore] = [:]
        for back in stride(from: 29, through: 0, by: -1) {
            // Two nights the band was not worn.
            if back == 11 || back == 19 { _ = rnd(); continue }
            let duration = Int(58 + rnd() * 42)
            let architecture = Int(52 + rnd() * 46)
            // Recovery is the group left dragging, so the week and month hero has something
            // true to name in its right foot.
            let recovery = Int(40 + rnd() * 34)
            let regularity = back < 16 ? Int(62 + rnd() * 38) : nil
            let groups: [(Int?, Int)] = [(duration, 25), (architecture, 25),
                                         (recovery, 35), (regularity, 15)]
            let present = groups.filter { $0.0 != nil }
            let total = present.reduce(0) { $0 + Double($1.0!) * Double($1.1) }
                / present.reduce(0) { $0 + Double($1.1) }
            let minutes = Double(300 + Int(rnd() * 190))
            var inputs: [String: Double] = [
                "duration_min": minutes,
                "deep_pct": 14 + rnd() * 10,
                "light_pct": 52 + rnd() * 12,
                "wakes": Double(Int(rnd() * 4)),
                "hrv_ms": 28 + rnd() * 18,
                "rhr": 52 + rnd() * 10,
                "bed_offset": 300 + rnd() * 90,
            ]
            // The habit is learned from the third prior night; the schedule chart's band
            // needs it to draw.
            if back < 27 { inputs["bed_median"] = 342 }
            // Nights the band filed no stage line have no REM to report, which is what the
            // renormalised proportions bar is there to survive.
            if back % 5 != 0 { inputs["rem_pct"] = 18 + rnd() * 9 }
            if back % 3 != 0 { inputs["spo2_min"] = 90 + rnd() * 7 }
            if back % 4 != 0 { inputs["respiration"] = 12 + rnd() * 5 }
            out[today.adding(days: -back).key] = SleepScore(
                score: Int(total.rounded()),
                duration: duration, architecture: architecture,
                recovery: recovery, regularity: regularity,
                personalWeight: 0.43, inputs: inputs, version: "sleep-v1")
        }
        return out
    }

    /// One seeded night: the band's window, and a skin tick every five minutes inside it.
    /// ⚠️ Simulator only, behind `Band.allowsSeed`, like every other number in this file.
    static func seedNight(day: UserDay, hours: Double, mean: Double,
                          rnd: () -> Double) -> (summary: SleepSummary, ticks: [VitalSample]) {
        // 23:30 local: the user day starts at midnight, so the night straddles its start
        // the way a real one does.
        let start = day.start.addingTimeInterval(-30 * 60)
        let minutes = Int(hours * 60)
        let wake = start.addingTimeInterval(Double(minutes) * 60)
        var ticks: [VitalSample] = []
        for slot in 0..<(minutes / 5) {
            ticks.append(VitalSample(
                ts: start.addingTimeInterval(Double(slot) * 300),
                hr: Int(50 + rnd() * 6),
                stress: Int(12 + rnd() * 8),
                temp: mean + (rnd() - 0.5) * 0.3,
                hrv: 44 + rnd() * 14))
        }
        let deep = Int(Double(minutes) * 0.2)
        var spo2: [OvernightOxygenPoint] = []
        var minute = 0
        while minute < minutes {
            let wave = sin(Double(minute) / 80)
            let percent = min(100, max(88, 95 + Int((wave * 2).rounded())))
            spo2.append(OvernightOxygenPoint(
                ts: start.addingTimeInterval(Double(minute) * 60),
                percent: percent))
            minute += 15
        }
        return (SleepSummary(totalMinutes: minutes, deepMinutes: deep,
                             lightMinutes: minutes - deep, wakeCount: Int(rnd() * 3),
                             sleepStart: start, wakeAt: wake, spo2: spo2),
                ticks)
    }

    /// Scheme A seed: night charges from the 04:00 anchor to the morning peak,
    /// then the day spends down to NOW. Five-minute ticks, same grid as the engine.
    static func seedReserveCurve(day: UserDay, now: Date, wakeAt: Date,
                                 peak: Int, nowValue: Int, anchor: Int) -> [ReserveSample] {
        var samples: [ReserveSample] = []
        var t = day.start
        let end = min(now, day.end)
        while t <= end {
            let value: Int
            if t <= wakeAt {
                let span = max(wakeAt.timeIntervalSince(day.start), 1)
                let p = t.timeIntervalSince(day.start) / span
                value = anchor + Int((Double(peak - anchor) * p).rounded())
            } else {
                let span = max(end.timeIntervalSince(wakeAt), 1)
                let p = min(1, t.timeIntervalSince(wakeAt) / span)
                value = peak + Int((Double(nowValue - peak) * p).rounded())
            }
            samples.append(ReserveSample(ts: t, value: min(100, max(0, value))))
            t = t.addingTimeInterval(300)
        }
        return samples
    }

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
            // ADR 0009 · the last three weeks carry a real night window and the skin ticks
            // inside it, so the TEMP card's own range forms with no band and no session.
            // Two nights are deliberately unusable — one never worn, one a 2h nap — because
            // LEARNING, NIGHT TOO SHORT and a settled range are three different screens.
            // Thirty nights so HEART's month window has bars. `back == 6` stays empty so
            // a vacant slot is visible. Skin-temp range still samples the newest 14 valid
            // nights inside 28 days, so the older extras do not move that verdict.
            if back <= 30 && back != 6 {
                let night = back == 9
                    ? DataStore.seedNight(day: m.day, hours: 2, mean: 33.7, rnd: rnd)
                    // Centred on what seedToday's asleep ticks read, so the walked default is
                    // WITHIN YOUR RANGE — the state a healthy person is in almost every night.
                    : DataStore.seedNight(day: m.day, hours: 7.5,
                                          mean: 33.85 + (rnd() - 0.5) * 0.5, rnd: rnd)
                m.sleep = night.summary
                m.vitalsCurve = night.ticks
                // The morning's resting pulse, so HEART's week and month have a line to draw.
                m.nightInputs = NightInputs(rhr: (48 + rnd() * 8).rounded(), rhrBase: 51, rhrNights: 14)
                if back <= 7 {
                    var extra: [VitalSample] = []
                    var t = m.day.start.addingTimeInterval(4 * 3600)
                    let end = m.day.start.addingTimeInterval(18 * 3600)
                    while t < end {
                        extra.append(VitalSample(
                            ts: t,
                            hr: Int(64 + rnd() * 26),
                            stress: nil,
                            hrv: extra.count.isMultiple(of: 4) ? 34 + rnd() * 10 : nil))
                        t = t.addingTimeInterval(1800)
                    }
                    m.vitalsCurve = VitalSample.merging(m.vitalsCurve, with: extra)
                }
            }
            m.bbWake = Int(48 + rnd() * 45)
            m.worn = m.bandCoverage >= 0.5
            // Empty heat cells stay empty: an unworn day has no load and no wake peak.
            if back == 6 || back == 17 {
                m.worn = false
                m.trainingLoad = nil
                m.bbWake = nil
            } else if let wake = m.bbWake {
                m.reserveDrivers = ReserveDrivers(
                    lastNight: Double(20 + Int(rnd() * 28)),
                    awake: -8, movement: -6, stress: -2,
                    anchor: max(20, wake - 30))
            }
            if m.worn == true && back != 6 && back != 17 {
                let load = 2 + rnd() * 17
                m.trainingLoad = load
                m.targetLoad = 14.5
                m.optimalZone = 13.0...16.0
                let z1 = 20 + Int(rnd() * 8) * 5
                let z2 = 15 + Int(rnd() * 6) * 5
                let z3 = 10 + Int(rnd() * 5) * 5
                let hard = load >= 14
                let z4 = (hard ? 15 : 5) + Int(rnd() * 3) * 5
                let z5 = hard ? 5 + Int(rnd() * 2) * 5 : 0
                m.zoneMinutes = [z1, z2, z3, z4, z5]
                if m.eActive == nil { m.eActive = 180 + rnd() * 280 }
                if m.eOutNow == nil { m.eOutNow = (m.bmr ?? 1480) + (m.eActive ?? 0) }
                let steps = 3500 + Int(rnd() * 9000)
                var segs = [TrainingSegment(at: m.day.start, name: "ALL DAY", minutes: nil,
                                            avgHR: nil, steps: steps, delta: load, allDay: true)]
                if hard {
                    segs.insert(TrainingSegment(
                        at: m.day.start.addingTimeInterval(14 * 3600),
                        name: "STRENGTH", minutes: 40, avgHR: 128,
                        steps: 500, delta: min(4, load * 0.25), allDay: false), at: 0)
                }
                m.segments = segs
            }
            m.weightKg = 69.8 - Double(84 - back) * 0.016 + (rnd() - 0.5) * 0.5
            out.append(m)
        }
        var run = 0
        var miss = 2
        var prevWorn = false
        for i in out.indices {
            let worn = out[i].worn == true
            if worn {
                run = prevWorn ? run + 1 : 1
                miss = 0
            } else {
                run = 0
                miss = prevWorn ? 1 : min(2, miss + 1)
            }
            out[i].wearRun = run
            out[i].wearMiss = miss
            prevWorn = worn
        }
        var seeded = seedToday()
        seeded.wearRun = (prevWorn ? run : 0) + 1
        seeded.wearMiss = 0
        seeded.worn = true
        out.append(seeded)
        return out
    }

    /// Thirty days of daytime optical points so the RESPONSE week and month boards have
    /// slots to draw. One day in the current week is left empty so a vacant bar is visible.
    static func seedMealResponse() -> [MealResponseIndex.Point] {
        let today = UserDay.containing(Date())
        var points: [MealResponseIndex.Point] = []
        for back in stride(from: 29, through: 1, by: -1) {
            if back == 3 { continue }
            let start = today.adding(days: -back).start
            let shift = Double((back % 5) - 2) * 6
            for hour in [11, 13, 16] {
                points.append(.init(
                    ts: start.addingTimeInterval(Double(hour) * 3600),
                    optical: 100 + shift))
            }
        }
        let start = today.start
        points.append(.init(ts: start.addingTimeInterval(11 * 3600), optical: 100))
        points.append(.init(ts: start.addingTimeInterval(13 * 3600), optical: 100))
        points.append(.init(ts: start.addingTimeInterval(15 * 3600), optical: 108))
        return points.filter { $0.ts <= Date() }
    }

    // MARK: mutations the UI performs

    /// Manual entries share the durable publication and visible projection used by
    /// accepted AI drafts and later amendments.
    func addManualMeal(text: String, kcal: Double, day: UserDay) {
        // The simulator's seed account is a memory-only demonstration, including
        // when real credentials were supplied for a separate debugging workflow.
        if Band.allowsSeed {
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard kcal.isFinite, kcal >= 1, kcal <= 100000,
                  !name.isEmpty, name.count <= 8000 else { return }
            let at = day.pinningClock(Date())
            let entry = MealEntry(id: UUID(), day: day, at: at,
                slot: .guess(at: at, day: day), status: .confirmed, text: name,
                kcal: Double(Int(kcal)), protein: 0, carb: 0, fat: 0, source: .typed)
            overlayPendingMeals([entry], removedIDs: [])
            NotificationReach.evaluate(store: self)
            return
        }
        do { try MealQueue.shared.createManual(text: text, kcal: kcal, day: day, into: self) }
        catch { AIService.shared.lastError = error.localizedDescription }
    }

    /// A correction appends a replacement and soft-deletes the old cloud record.
    func amendMeal(_ id: UUID, text: String, kcal: Double, protein: Int, carb: Int, fat: Int,
                   at: Date, slot: MealEntry.Slot) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = meals.first(where: { $0.id == id }) ?? recentMeals.first(where: { $0.id == id })
        guard let entry = source, canEdit(entry), kcal.isFinite, kcal >= 1, kcal <= 100000, !name.isEmpty,
              protein >= 0, carb >= 0, fat >= 0,
              let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        let eatenAt = entry.day.pinningClock(at)
        let replacementID = UUID()
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]
        let replacement: [String: Any] = [
            "id": replacementID.uuidString.lowercased(), "user_day": entry.day.key,
            "slot": slot.rawValue, "name": name, "kcal": Int(kcal),
            "protein_g": protein, "carb_g": carb, "fat_g": fat,
            "logged_at": stamp.string(from: eatenAt),
            "confidence": "HIGH", "model_version": "manual-amendment-v1",
        ]
        do { try MealQueue.shared.enqueueAmend(mealID: id, replacement: replacement, source: entry.source, revisions: entry.revisions + 1, ownerUserId: owner) }
        catch { AIService.shared.lastError = error.localizedDescription; return }
    }

    func overlayPendingMeals(_ entries: [MealEntry], removedIDs: Set<UUID>) {
        let replacementIDs = Set(entries.map(\.id))
        meals = meals.filter { !removedIDs.contains($0.id) && !replacementIDs.contains($0.id) }
            + entries.filter { $0.day == UserDay.containing(Date()) }
        recentMeals = recentMeals.filter { !removedIDs.contains($0.id) && !replacementIDs.contains($0.id) } + entries
        recomputeFuel()
    }

    /// Confirmed plates on screen are EATEN. A stale UNLOGGED/0 header after load
    /// must not blank a day the food table already lists. No plates keeps the
    /// server number so a failed meal fetch does not wipe a settled header.
    func refreshIntakeFromMeals() {
        let day = UserDay.containing(Date())
        let confirmed = meals.filter { $0.day == day && $0.status == .confirmed }
        guard !confirmed.isEmpty else { return }
        recomputeFuel()
    }

    /// F0 right column: 09 needs an edit/delete entry point. Range-limited to 7 user days (F2 §08).
    func deleteMeal(_ id: UUID) {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        do { try MealQueue.shared.enqueueDelete(mealID: id, ownerUserId: owner) }
        catch { AIService.shared.lastError = error.localizedDescription; return }
    }

    func canEdit(_ entry: MealEntry) -> Bool {
        entry.day >= UserDay.containing(Date()).adding(days: -6)
    }

    private func recomputeFuel() {
        let day = UserDay.containing(Date())
        let confirmed = meals.filter { $0.day == day && $0.status == .confirmed }
        let isFasted: Bool
        if case .fasted = today.fuelState { isFasted = confirmed.isEmpty } else { isFasted = false }
        today.eIn = confirmed.isEmpty ? (isFasted ? 0 : nil) : confirmed.reduce(0) { $0 + $1.kcal }
        today.proteinIn = confirmed.isEmpty && !isFasted ? nil : confirmed.reduce(0) { $0 + $1.protein }
        today.carbIn = confirmed.isEmpty && !isFasted ? nil : confirmed.reduce(0) { $0 + $1.carb }
        today.fatIn = confirmed.isEmpty && !isFasted ? nil : confirmed.reduce(0) { $0 + $1.fat }
        if let eIn = today.eIn, let out = today.eOutNow { today.balance = eIn - out }
        else { today.balance = nil }
        if confirmed.isEmpty {
            today.protein = today.protein.map { MacroSlot(target: $0.target, eaten: 0) }
            today.carb = today.carb.map { MacroSlot(target: $0.target, eaten: 0) }
            today.fat = today.fat.map { MacroSlot(target: $0.target, eaten: 0) }
        }
        // What is left moves with the row, the same instant — the tile and the LOGGED frame
        // both read it, and both used to wait for the next reload.
        if let t = today.targetIn { today.nextMeal = max(0, t - (today.eIn ?? 0)) }
        let slots = Set(confirmed.map(\.slot)).count
        today.fuelState = confirmed.isEmpty ? (isFasted ? .fasted : .unlogged) : (slots >= 4 ? .confirmed : .partial(slots: slots))
        WidgetGlancePublisher.publish(from: self)
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
        guard let ownerUserId = SupabaseClient.currentUserIdSnapshot() else { return }
        do { try WeighInQueue.shared.enqueue(w, ownerUserId: ownerUserId) }
        catch { AIService.shared.lastError = error.localizedDescription; return }
        weighIns = (weighIns + [w]).sorted { $0.date > $1.date }
        today.weightKg = w.weightKg
        if let bf = w.bodyFatPercent {
            today.fatKg = w.weightKg * bf / 100
            today.leanKg = w.weightKg - (today.fatKg ?? 0)
            today.fatSource = w.source
        }
    }
}

struct MealEntry: Identifiable, Hashable, Codable {
    enum Slot: String, CaseIterable, Hashable, Codable {
        case breakfast = "BREAKFAST", lunch = "LUNCH", dinner = "DINNER", snack = "SNACK"

        static func guess(at date: Date, day: UserDay) -> Slot {
            let hour = Calendar.current.component(.hour, from: date)
            if date < day.start { return .snack }
            switch hour {
            case 4..<11:  return .breakfast
            case 11..<15: return .lunch
            case 15..<21: return .dinner
            default:      return .snack
            }
        }
    }
    enum Status: String, Hashable, Codable { case open = "OPEN", skipped = "SKIPPED", confirmed = "CONFIRMED" }

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

    enum Source: String, Hashable, Codable { case voice = "VOICE", typed = "TYPED", photo = "PHOTO" }

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

struct Profile: Hashable, Codable {
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
    static var blank: Profile {
        Profile(
            name: "", email: "",
            birthdate: Calendar.current.date(byAdding: .year, value: -30, to: Date())!,
            heightCm: 170, sexIsMale: true, goal: .recomp,
            usesMetric: true, appleHealthLinked: false
        ).restoringHealthSync()
    }

    /// SYNCED records a completed import on this device, not today's read permission.
    /// Reuse the existing receipt so upgrades also restore past successful imports.
    func restoringHealthSync() -> Profile {
        var restored = self
        restored.appleHealthLinked = appleHealthLinked
            || UserDefaults.standard.object(forKey: "nb.health.lastRead") is Date
        return restored
    }

    static let mock = Profile(
        name: "ZEPH",
        email: "you@nextbody.app",
        birthdate: Calendar.current.date(byAdding: .year, value: -34, to: Date())!,
        heightCm: 176, sexIsMale: true, goal: .recomp,
        usesMetric: true, appleHealthLinked: true)
}

/// The most recent five-minute tick. Nothing here is extrapolated: if the band has been
/// off the wrist for six hours these are simply absent (13 · CURVE STOPS AT THE LAST REAL TICK).
struct LiveVitals: Hashable, Codable {
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
    /// Last charge state the band reported. The header pip and the device page read this
    /// so a known CHARGING is not wiped to UNKNOWN while another read is in flight.
    var chargeState: BandBattery.ChargeState
    var firmware: String
    /// Last full battery packet the band sent. The header pip still prints percent;
    /// the device page and the trend use this so bars-only firmware stays bars.
    var lastBattery: BandBattery?
    var lastSync: Date
    var capabilities: Set<Capability>

    /// 100% still on the charger is Charged. Firmware often never sends `.full`.
    var displayedCharge: BandBattery.ChargeState {
        if let packet = lastBattery { return packet.settled.chargeState }
        if chargeState == .charging,
           BatteryDrainMath.isToppedUp(
            isPercent: batteryPercent != nil, percent: batteryPercent, level: nil) {
            return .full
        }
        return chargeState
    }

    mutating func applyBattery(_ battery: BandBattery) {
        // An unknown read is "we did not hear", not a percent. Keep the last
        // real packet so the hero and the pip do not dip to a stale ghost.
        let battery = battery.settled
        guard battery.chargeState != .unknown else { return }
        lastBattery = battery
        if let p = battery.percent { batteryPercent = p }
        chargeState = battery.chargeState
    }

    enum Capability: String, Hashable, CaseIterable {
        case heartRate, bloodOxygen, bloodPressure, ecg, temperature, bodyComponent, wearDetection, alarms
    }

    /// A real phone before the band has answered anything. Every field fills in from the
    /// band itself (BandPresence) or from the devices row; none of them is guessed.
    static let unknown = BandState(connected: false, name: "HOOP", mac: "",
                                   batteryPercent: nil, chargeState: .unknown, firmware: "",
                                   lastBattery: nil,
                                   lastSync: .distantPast, capabilities: [])

    static let mock = BandState(connected: true, name: "NEXTBODY HOOP", mac: "C4:2E:8F:1A:73:9D",
                                batteryPercent: 82, chargeState: .unplugged, firmware: "1.4.7",
                                lastBattery: BandBattery(isPercent: true, percent: 82, level: nil,
                                                         chargeState: .unplugged),
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
    /// PingFang launch mark until `resolveLaunch` returns. No film.
    @Published var holdingLaunchStill = false
    @Published private(set) var launchReady = false

    init() {
        #if DEBUG
        // `SIMCTL_CHILD_NB_DEBUG_STAGE=gateConnect` opens the app at that gate for a walk.
        if Band.allowsSeed, let s = ProcessInfo.processInfo.environment["NB_DEBUG_STAGE"], let st = Stage(rawValue: s) {
            stage = st
            applyLaunchCover()
            return
        }
        #endif
        let persisted = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(Stage.init(rawValue:)) ?? .gateSignIn
        // No refresh token means there is no session to restore. A leftover `root` in
        // UserDefaults would otherwise flash Home over the anon key.
        if SessionKeychain.refreshToken == nil && !Band.allowsSeed {
            stage = .gateSignIn
        } else {
            stage = persisted
        }
        applyLaunchCover()
    }

    private func applyLaunchCover() {
        holdingLaunchStill = LaunchFilmPolicy.shouldHoldStill(
            environment: ProcessInfo.processInfo.environment)
    }

    func markLaunchReady() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NB_DEBUG_LAUNCH_MARK"] == "1" { return }
        #endif
        guard !launchReady else { return }
        launchReady = true
        holdingLaunchStill = false
        let ms = Int((LaunchFilmPolicy.elapsed * 1000).rounded())
        UserDefaults.standard.set(ms, forKey: LaunchFilmPolicy.lastDurationKey)
        NSLog("NB launch ready %d ms", ms)
    }

    /// F1 §02 · re-read the four facts on every cold start. The last screen is a hint,
    /// not the decision. Debug stage pins stay put.
    func resolveLaunch() async {
        defer { markLaunchReady() }
        #if DEBUG
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_STAGE"] != nil { return }
        #endif
        guard await ensureSession() else {
            if Band.allowsSeed { return }
            stage = .gateSignIn
            isSignedIn = false
            email = ""
            return
        }
        if !Band.allowsSeed, DemoAccount.matches(await SupabaseClient.shared.signedInEmail() ?? "") {
            await SupabaseClient.shared.signOut()
            stage = .gateSignIn
            isSignedIn = false
            email = ""
            return
        }
        if stage == .root {
            Task { await Repository.shared.bootstrapHome(into: DataStore.shared) }
        }
        let facts = await Repository.shared.fetchAccountGate()
        stage = facts.stage
        if stage == .root {
            Task { await Repository.shared.bootstrapHome(into: DataStore.shared) }
        }
    }

    /// Restore the Keychain refresh token. Does not invent the demo session — that
    /// stays Home's walk-through, after this gate has already decided.
    @discardableResult
    func ensureSession() async -> Bool {
        if await SupabaseClient.shared.currentUserId != nil {
            isSignedIn = true
            if email.isEmpty { email = await SupabaseClient.shared.signedInEmail() ?? "" }
            Task { await Repository.shared.flushPendingEvidence() }
            return true
        }
        guard await SupabaseClient.shared.restoreSession() else { return false }
        isSignedIn = true
        email = await SupabaseClient.shared.signedInEmail() ?? email
        Task { await Repository.shared.flushPendingEvidence() }
        return true
    }

    func reset() {
        stage = .gateSignIn; isSignedIn = false; email = ""
        DataStore.shared.clearAccountDisplay()
        // The Keychain copy of the session goes too, or the next launch would restore it
        // straight past the gate.
        Task {
            await BillingStore.shared.logOut()
            await SupabaseClient.shared.signOut()
        }
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
        if let account = SupabaseClient.currentUserIdSnapshot() ?? SessionKeychain.userId {
            BandDomainSyncState.purge(userId: account)
            do { try MealQueue.shared.purge(ownerUserId: account) }
            catch { AIService.shared.lastError = error.localizedDescription }
        }
        DataStore.shared.purge()
        WeighInQueue.shared.purge()
        BodyCompositionQueue.shared.purge()
        BalanceCheckQueue.shared.purge()
        PlanCheckQueue.shared.purge()
        PlanStore.shared.reset()
        PlanStore.purge(owner: SupabaseClient.currentUserIdSnapshot() ?? SessionKeychain.userId)
        Task { await BillingStore.shared.logOut() }
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
