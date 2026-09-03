import Foundation

/// What the app needs from a band, and nothing more. Two implementations sit behind it:
/// `MockBand` on the simulator and `VeepooBand` on a device with the framework linked.
/// A device build that cannot import the SDK gets `DisconnectedBand` — idle, invents nothing.
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
    /// HRV and temperature live in separate SDK databases. Reading them through one command
    /// keeps the BLE operations serialized and preserves their distinct units and semantics.
    func readHealthData(dayOffset: Int) async throws -> BandHealthData
    func readSleep(dayOffset: Int) async throws -> SleepNight?

    func measureHeartRate() -> AsyncThrowingStream<MeasurementProgress, Error>
    func measureBodyComposition() -> AsyncThrowingStream<MeasurementProgress, Error>

    func writeSetting(_ setting: BandSetting) async throws -> BandSetting
    /// Ask the update server whether this band has newer firmware. `nil` is "up to date";
    /// a throw is "could not ask" — the two are never drawn the same way.
    func checkFirmwareUpdate() async throws -> FirmwareOffer?
    /// 12 rule 08 · OTA is three-state. `versionUnverified` is its own outcome — the DFU said
    /// done and the version could not be read back — and is never folded into the other two.
    /// `progress` is 0…1 while the file crosses; it is a number, never a tween.
    func updateFirmware(to version: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FirmwareUpdateResult
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

/// Fan-out for `BandService.events`. A bare `AsyncStream` has one consumer and ends for good
/// the moment that consumer's task is cancelled — 02's "search again" cancels the previous
/// scan task, and 06's ECG screen reads the same stream — so a single shared stream silently
/// dropped every discovery after the first retry. Each `events` access now gets its own stream;
/// a send reaches all of them, and a cancelled one just unsubscribes.
final class BandEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<BandEvent>.Continuation] = [:]

    func stream() -> AsyncStream<BandEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock(); subscribers[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.subscribers[id] = nil; self.lock.unlock()
            }
        }
    }

    func send(_ event: BandEvent) {
        lock.lock(); let live = Array(subscribers.values); lock.unlock()
        for c in live { c.yield(event) }
    }
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
    /// The band's own sport-mode tier: NONE, SINGLE, or "10 TYPES (…)". The SDK has no
    /// way to ask WHICH sports a firmware carries — the band's own workout list does.
    let sportMode: String
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
    /// Metres for this five-minute slot. The SDK's `disValue` is kilometres; the bridge
    /// converts before this is stored.
    let distance: Int?
    let met: Double?
    // F5 §07 / F7 rule 04 · no spo2 here. The whitelist is applied where the SDK's object is
    // rebuilt, not downstream — a value that never crosses the bridge cannot reach a table,
    // a screen, an export or a tool return.
    let temperature: Double?
    /// RMSSD in ms for this tick, joined in from the band's separate HRV history. The
    /// original-data dictionary carries no HRV of its own, so this is nil at the SDK bridge
    /// and filled where the two domains meet.
    let hrv: Double?
    let stress: Int?
    let sleepState: Int?
}

struct BandHealthData {
    let temperatures: [TemperatureSample]
    let hrv: [HrvMinuteSample]
}

/// 04B rule 04 · one run of the band's own sleepLine: a stage and how many minutes it held.
/// Stages are the SDK's (VPAccurateSleepModel): 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake —
/// KH firmware emits no 2 or 3.
struct SleepStageRun: Codable, Hashable {
    let stage: Int
    let minutes: Int
}

struct SleepNight {
    let totalMinutes: Int
    let deepMinutes: Int
    let lightMinutes: Int
    let wakeCount: Int
    /// 04B rule 04 · the night's sleepLine compressed into runs, in the order the night ran.
    /// Empty when the band answered without a curve — the strip falls back to proportions.
    var line: [SleepStageRun] = []
    /// When the night began and ended, from the band's own record. The server's night
    /// resting heart rate is the 5th percentile of the ticks between them — raw_samples
    /// carries no sleep flag on this SDK, so without these two the number cannot exist.
    var sleepStart: Date? = nil
    var wakeAt: Date? = nil
}

/// The states the measurement takeover renders. `lead == false` is the amber nudge:
/// it means "we need you to move", never "you failed".
enum MeasurementProgress {
    case waitingForContact
    case contact
    /// `secondsLeft` is the band's own clock when it has one (body composition reports its
    /// progress); nil means the phone counts, as for a heart-rate read the SDK only values.
    case measuring(fraction: Double, partial: PartialReading?, secondsLeft: Int? = nil)
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
    /// The rest of the SDK's twelve, for the baseline screen. Absent when the firmware sent
    /// an empty string; a missing field is a dash, never a number.
    var muscleRatePercent: Double? = nil
    var waterKg: Double? = nil
    var proteinKg: Double? = nil
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
    /// The device's own interval capability. Zero means every whole-minute value 0...180;
    /// otherwise the firmware names step, 2 × step … 180. Minutes below the step are offered
    /// as probes — the write is only believed when the band echoes the value back.
    var intervalStepMinutes: Int = 5
    /// 12 rule 06 · isSlotModify / isIntervalModify from readAutoMeasureSetting().
    var slotModifiable = true
    var intervalModifiable = true

    var allowedIntervals: [Int] {
        AutoMeasurementIntervalPolicy.options(minimumStepMinutes: intervalStepMinutes)
    }
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


/// What the update server offers for the connected band: the version, and its release
/// notes one per line. The server, not the band, is the source — the band cannot know.
struct FirmwareOffer: Equatable {
    let version: String
    let notes: [String]
}

/// 12 rule 08 · completed / failed / versionUnverified.
enum FirmwareUpdateResult: Equatable {
    case completed(version: String)
    case failed(reason: String)
    case versionUnverified
}

/// A device build with no SDK linked. Stays idle and invents nothing — MockBand's
/// plausible day would otherwise land on a real account.
final class DisconnectedBand: BandService, @unchecked Sendable {
    private(set) var state: BandConnectionState = .idle
    private let hub = BandEventHub()
    var events: AsyncStream<BandEvent> { hub.stream() }

    func startScan() async {}
    func stopScan() async {}
    func connect(_: DiscoveredBand) async throws { throw BandError.notConnected }
    func reconnectIfBound() async {}
    func disconnect() async { state = .disconnected }

    func readIdentity() async throws -> BandIdentity { throw BandError.notConnected }
    func readCapabilities() async throws -> BandCapabilities { throw BandError.notConnected }
    func readBattery() async throws -> BandBattery { throw BandError.notConnected }
    func syncPersonalInfo(_: PersonalInfo) async throws { throw BandError.notConnected }
    func readOriginData(dayOffset _: Int) async throws -> [OriginPoint] { throw BandError.notConnected }
    func readHealthData(dayOffset _: Int) async throws -> BandHealthData { throw BandError.notConnected }
    func readSleep(dayOffset _: Int) async throws -> SleepNight? { throw BandError.notConnected }
    func measureHeartRate() -> AsyncThrowingStream<MeasurementProgress, Error> {
        AsyncThrowingStream { $0.finish(throwing: BandError.notConnected) }
    }
    func measureBodyComposition() -> AsyncThrowingStream<MeasurementProgress, Error> {
        AsyncThrowingStream { $0.finish(throwing: BandError.notConnected) }
    }
    func writeSetting(_: BandSetting) async throws -> BandSetting { throw BandError.notConnected }
    func checkFirmwareUpdate() async throws -> FirmwareOffer? { throw BandError.notConnected }
    func updateFirmware(to _: String, progress _: @escaping @Sendable (Double) -> Void) async throws -> FirmwareUpdateResult {
        throw BandError.notConnected
    }
    func readAutoMonitoring() async throws -> [AutoMonitorSlot] { throw BandError.notConnected }
    func writeAutoMonitoring(_: AutoMonitorSlot) async throws { throw BandError.notConnected }
}
