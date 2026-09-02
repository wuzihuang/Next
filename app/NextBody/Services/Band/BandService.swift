import Foundation

/// What the app needs from a band, and nothing more. Two implementations sit behind it:
/// `MockBand` on the simulator and `VeepooBand` on a device with the framework linked.
/// Every screen talks to this, so the flow is walkable either way.
protocol BandService: AnyObject {
    var state: BandConnectionState { get }
    var events: AsyncStream<BandEvent> { get }

    func startScan() async
    func stopScan() async
    func connect(_ device: DiscoveredBand) async throws
    /// F1 · A · the gate is walked once. After that the band is bound, and every later launch
    /// reconnects to it on its own — being asked to pair again is how a user learns their
    /// history is gone.
    func reconnectIfBound() async
    /// ⚠️ The SDK only offers disconnect(). "Forget this HOOP" is the app clearing its own
    /// device id — "factory reset" is not something we can do, and the two must never blur.
    func disconnect() async

    func readIdentity() async throws -> BandIdentity
    func readCapabilities() async throws -> BandCapabilities
    func readBattery() async throws -> BandBattery

    /// F2 §05 · the band's BIA numbers are computed from the weight we push down.
    /// Every startBodyCompositionTest must be preceded by this, or the sample is discarded.
    func syncPersonalInfo(_ info: PersonalInfo) async throws

    /// F2 §01 · dayOffset is a paging parameter and nothing else.
    /// It never becomes a primary key and never reaches a sentence the user reads.
    func readOriginData(dayOffset: Int) async throws -> [OriginPoint]
    func readSleep(dayOffset: Int) async throws -> SleepNight?

    func measureHeartRate() -> AsyncThrowingStream<MeasurementProgress, Error>
    func measureBodyComposition() -> AsyncThrowingStream<MeasurementProgress, Error>

    func writeSetting(_ setting: BandSetting) async throws -> BandSetting
    func readAutoMonitoring() async throws -> [AutoMonitorSlot]
    func writeAutoMonitoring(_ slot: AutoMonitorSlot) async throws
}

enum BandConnectionState: Equatable {
    case idle, scanning, connecting, connected, disconnected
}

enum BandEvent {
    case discovered(DiscoveredBand)
    case state(BandConnectionState)
    case battery(BandBattery)
    /// The band finished a measurement it started on its own wrist, not one we asked for.
    case deviceInitiatedMeasurementFinished
}

struct DiscoveredBand: Identifiable, Hashable {
    /// ⚠️ On iOS this is a CoreBluetooth UUID, not a MAC. It changes with the phone,
    /// so it is never a cross-platform device identity.
    let id: String
    let name: String
    let rssi: Int
    let batteryPercent: Int?
}

struct BandIdentity {
    let name: String
    let model: String
    let hardware: String
    let firmware: String
    /// DeviceVersion.deviceNumber. ⚠️ The SDK has no serial number, and nothing in the
    /// product may call this one an SN.
    let deviceNumber: String
    let bleIdentifier: String
    /// How many days of history the band still holds. Missing days are drawn empty,
    /// never as 0, and never averaged.
    let watchDataDayNumber: Int
}

/// FunctionStatus values are carried through verbatim. On screen `unknown` and `unsupported`
/// both mean the row is not drawn — but when something is broken they are two different facts.
enum FunctionStatus: String {
    case support, unsupported, open, close, unknown
}

struct BandCapabilities {
    var functions: [String: FunctionStatus] = [:]
    var bodyComponent: FunctionStatus = .unknown
    var ecg: FunctionStatus = .unknown
    var hrv: FunctionStatus = .unknown
    var stress: FunctionStatus = .unknown
    var autoMeasure: FunctionStatus = .unknown
    /// ⚠️ Android has no read command for wearDetection. V1 is iOS only, so this is
    /// readable here — the Android note stays in the boards, marked for later.
    var wearDetection: FunctionStatus = .unknown

    /// F6 §05 · an unsupported row is not drawn at all — 「加号单子少一行，好过让人惦记一件这台
    /// 机器做不到的事」. This is deliberately not `!supports(kind)`: `unknown` is not
    /// `unsupported`, and before the band has answered its capability read the menu would empty
    /// itself on every cold start and fill back in a second later. Only a definite no hides a row.
    func knownUnsupported(_ kind: MeasureKind) -> Bool {
        func no(_ s: FunctionStatus?) -> Bool { s == .unsupported }
        switch kind {
        case .heartRate:        return no(hrv) && no(functions["heart"] ?? .unknown)
        case .bodyComposition:  return no(bodyComponent)
        case .bloodOxygen:      return no(functions["spo2"] ?? .unknown)
        case .bloodPressure:    return no(functions["blood"] ?? .unknown)
        case .ecg:              return no(ecg)
        case .temperature:      return no(functions["temperature"] ?? .unknown)
        }
    }

    func supports(_ kind: MeasureKind) -> Bool {
        switch kind {
        case .heartRate:        hrv == .support || functions["heart"] == .support || hrv == .open
        case .bodyComposition:  bodyComponent == .support
        case .bloodOxygen:      functions["spo2"] == .support
        case .bloodPressure:    functions["blood"] == .support
        case .ecg:              ecg == .support
        case .temperature:      functions["temperature"] == .support
        }
    }
}

/// ⚠️ Three values together: firmware with isPercent = false only reports 0–4 bars, and
/// collapsing them loses the difference between "82%" and "4 bars" forever.
struct BandBattery {
    let isPercent: Bool
    let percent: Int?
    let level: Int?
    let chargeState: ChargeState

    enum ChargeState: String { case unplugged, charging, full, unknown }

    /// What the ring can draw. A bar count is not a percentage and is never shown as one.
    var ringFraction: Double? {
        if isPercent, let p = percent { return Double(p) / 100 }
        if let l = level { return Double(l) / 4 }
        return nil
    }
}

struct PersonalInfo {
    let heightCm: Int
    let weightKg: Int
    let birthYear: Int
    let sexIsMale: Bool
    let targetStep: Int
}

/// One five-minute point, exactly as OriginData gives it.
/// ⚠️ OriginData carries a `time` string and nothing else: no date, no timezone, no offset.
/// A page's date can only be derived from the dayOffset you asked for, which is why every
/// batch is stamped with the calendar day at the moment it is stored.
struct OriginPoint {
    let time: String
    let heart: Int?
    let step: Int?
    let cal: Int?
    let distance: Int?
    let met: Double?
    let spo2: Int?
    let temperature: Double?
    let stress: Int?
    let sleepState: Int?
}

struct SleepNight {
    let totalMinutes: Int
    let deepMinutes: Int
    let lightMinutes: Int
    let wakeCount: Int
}

/// The states the measurement takeover renders. `lead == false` is the amber nudge:
/// it means "we need you to move", never "you failed".
enum MeasurementProgress {
    case waitingForContact
    case contact
    case measuring(fraction: Double, partial: PartialReading?)
    case lostContact
    case finished(MeasurementResult)
    case failed(reason: String)
}

struct PartialReading {
    var heartRate: Int?
    var bodyFatPercent: Double?
}

enum MeasurementResult {
    case heartRate(hr: Int, hrv: Int?, stress: Int?)
    /// ⚠️ There is no weight in BodyCompositionTestResult: these come from the weight we
    /// pushed down with syncPersonalInfo, which is why fat and lean are not two independent
    /// measurements and Δfat + Δlean always equals Δweight.
    case bodyComposition(BodyCompositionReading)
}

struct BodyCompositionReading {
    let bodyFatPercent: Double
    let fatMassKg: Double
    let leanMassKg: Double
    let muscleKg: Double?
    let boneKg: Double?
    let bodyWaterPercent: Double?
    let proteinPercent: Double?
    let subcutaneousFatPercent: Double?
    let skeletalMusclePercent: Double?
    let bmrKcal: Int?
    let bmi: Double?
    /// The weight this reading was computed from — the one we pushed down, not one measured.
    let inputWeightKg: Double
}

enum BandSetting {
    case heartRateAlarm(on: Bool, low: Int, high: Int)
    case moveReminder(on: Bool, intervalMinutes: Int, startHour: Int, endHour: Int)
    case drinkNudge(on: Bool)
    case wearDetection(on: Bool)
    case disconnectAlert(on: Bool)
    case lowPower(on: Bool)
    /// ⚠️ Alarms are replaced as a whole set, and the band's capacity is 3, 10 or 20
    /// depending on firmware — you only find out you exceeded it from the failure.
    case alarms([BandAlarm])
}

struct BandAlarm: Hashable {
    var hour: Int
    var minute: Int
    /// 1 = Monday … 7 = Sunday
    var weekdays: Set<Int>
    var on: Bool
}

struct AutoMonitorSlot: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case heartRate, bloodPressure, bloodGlucose, stress
        case bloodOxygen, temperature, lorentz, hrv, bloodComponents
    }
    var id: Kind { kind }
    let kind: Kind
    var on: Bool
    let supportsRange: Bool
    var startHour: Int
    var endHour: Int
    var intervalMinutes: Int
}

enum BandError: LocalizedError {
    case notConnected
    case unsupported(String)
    case busy
    case timeout(String)
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:        "BAND OFFLINE"
        case .unsupported(let f):  "THIS HOOP DOES NOT MEASURE \(f.uppercased())"
        case .busy:                "MEASURING NOW"
        case .timeout(let c):      "\(c.uppercased()) TIMED OUT"
        case .rejected(let r):     r.uppercased()
        }
    }
}
