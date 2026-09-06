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
    func reconnectForSport() async
    func prepareFreshSync() async
    /// ⚠️ The SDK only offers disconnect(). "Forget this HOOP" is the app clearing its own
    /// device id — "factory reset" is not something we can do, and the two must never blur.
    func disconnect() async

    func readIdentity() async throws -> BandIdentity
    func readCapabilities() async throws -> BandCapabilities
    func readBattery() async throws -> BandBattery
    func readHealthLight() async throws -> BandHealthLightState
    func writeHealthLight(_ state: BandHealthLightState) async throws -> BandHealthLightState

    /// F2 §05 · the band's BIA numbers are computed from the weight we push down.
    /// Every startBodyCompositionTest must be preceded by this, or the sample is discarded.
    func syncPersonalInfo(_ info: PersonalInfo) async throws

    /// F2 §01 · dayOffset is a paging parameter and nothing else.
    /// It never becomes a primary key and never reaches a sentence the user reads.
    func readOriginData(dayOffset: Int) async throws -> [OriginPoint]
    /// Existing SDK database dates, independent of the band's shorter live retention.
    /// This probe performs no Bluetooth transfer; offsets refer to user days to recover.
    func cachedHistoryDayOffsets(limit: Int) async throws -> [Int]
    /// HRV, temperature and overnight oxygen live in separate SDK databases. Reading them
    /// through one command keeps the BLE operations serialized and preserves their distinct
    /// units and semantics.
    func readHealthData(dayOffset: Int) async throws -> BandHealthData
    func readSleep(dayOffset: Int) async throws -> SleepNight?

    func measureHeartRate() -> AsyncThrowingStream<MeasurementProgress, Error>
    func measureBodyComposition() -> AsyncThrowingStream<MeasurementProgress, Error>
    /// 04 · one stress reading, the band's own 压力 test. One value at the end and no partials,
    /// so this is an awaited call rather than a stream like the two above — but it is not
    /// quick: a real HOOP takes 19 s, reporting `progress` 0…100 in steps of 6 a second, and
    /// only the last callback carries the number.
    /// ⚠️ It holds the sensor for all of that, which is why `LiveReadout` stops the heart-rate
    /// stream around it instead of running the two together — and why the progress is passed
    /// back rather than swallowed: nineteen seconds of an unchanging label is a screen that
    /// looks stuck.
    func measureStress(progress: @escaping @MainActor (Int) -> Void) async throws -> Int
    /// 06 · Battery Check's HRV leg. The SDK may not stop itself — Demo holds ~60 s then
    /// `false`. Callers pass a timeout; a value of 0 before then is not a reading.
    func measureHRV(timeout: TimeInterval) async throws -> Int

    func writeSetting(_ setting: BandSetting) async throws -> BandSetting
    /// Ask the update server whether this band has newer firmware. `nil` is "up to date";
    /// a throw is "could not ask" — the two are never drawn the same way.
    func checkFirmwareUpdate() async throws -> FirmwareOffer?
    /// 12 rule 08 · OTA is three-state. `versionUnverified` is its own outcome — the DFU said
    /// done and the version could not be read back — and is never folded into the other two.
    /// `progress` is 0…1 while the file crosses; it is a number, never a tween.
    func updateFirmware(to version: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FirmwareUpdateResult
    func readAutoMonitoring() async throws -> AutoMonitoringRead
    func writeAutoMonitoring(_ slot: AutoMonitorSlot) async throws
    /// DEBUG · the SDK cannot say which sports a firmware carries, so the probe asks by
    /// opening one and closing it again. `rawValue` is a VPDeviceRuningMode ordinal; true
    /// means the band took that mode, false means it does not exist on this firmware.
    /// ⚠️ Opens and immediately closes a real workout session on the band.
    func probeSportMode(_ rawValue: Int) async throws -> Bool
    /// Open a sport mode and leave it running. `rawValue` is a VPDeviceRuningMode ordinal.
    /// A refusal means this firmware does not carry that mode.
    func startSportMode(_ rawValue: Int) async throws
    /// Close the sport mode previously opened with `startSportMode`.
    func stopSportMode(_ rawValue: Int) async throws
    /// 14 · the band's own report while a sport mode runs: heart rate, calories, distance
    /// and its clock, pushed by the firmware every second or so. This is the wrist during a
    /// session — the heart test is refused as busy while a mode is open. The stream stays
    /// open until cancelled; a firmware without the report simply never yields.
    func sportLiveInfo() -> AsyncStream<SportLiveInfo>
    /// 06 · THE PULSE STUDY. Forty seconds of the band's own beat-to-beat timing.
    ///
    /// ⚠️ The command underneath is the SDK's single-lead ECG start — that is the only way to
    /// get beat-to-beat intervals out of this hardware — but NOTHING about a waveform crosses
    /// this boundary. The app never receives, holds, or draws a trace: it takes the interval
    /// series and the rate, which is what an autonomic-balance readout is computed from, and
    /// leaves the diagnostic surface the SDK offers (and its paid interpretation) alone.
    /// A product that draws a heart trace is a different regulatory animal in the US, and
    /// this one deliberately is not that animal.
    ///
    /// Measured on a real HOOP: 40 s, progress climbing about 3 % a second.
    /// The finger has to stay on the electrode for the whole run; `lostContact` is the SDK's
    /// `notLead` and is its own outcome, never folded into a failure.
    func measurePulseStudy() -> AsyncThrowingStream<PulseStudyStep, Error>

    /// DEBUG · everything the band has stored from measurements started ON THE WATCH itself:
    /// thirteen kinds in one call, newest first, from `since` onwards.
    /// ⚠️ A read. No measurement, no sensor time, nothing lights up on the wrist — which is
    /// what makes it the one way to get a full set out of a firmware that will not take the
    /// measurement commands the app sends.
    /// Returns one formatted line per stored record: this is a probe, and inventing thirteen
    /// structs before knowing which of them this band ever fills would be inventing.
    func readManualTestData(since: Date) async throws -> [String]

    /// DEBUG · 微体检 (定制项目), a different command from the 公版 one below and answered by
    /// different firmware. One measurement → heart rate, blood oxygen, stress, blood sugar,
    /// temperature, systolic, diastolic, HRV.
    /// ⚠️ A real measurement on the wrist.
    func probeMicroTest(progress: @escaping @MainActor (Int) -> Void) async throws -> [(name: String, value: Double)]

    /// DEBUG · 微体检 (公版). One measurement, one model: the SDK's health glance carries a
    /// field per metric for a whole product family, and `functionSupport` is the band saying
    /// which of them it actually filled.
    /// ⚠️ Starts a real measurement on the wrist and holds the sensor for its whole length.
    /// ⚠️ 0 in a field is ambiguous — "this band does not have it" and "it did not read this
    /// time" look identical — which is why the bitmask is carried through beside the numbers
    /// and never collapsed into them.
    func probeHealthGlance(progress: @escaping @MainActor (Int) -> Void) async throws -> BandHealthGlance

    /// What this HOOP says it can measure, in its own words.
    /// ⚠️ This is the honest answer to "what does this band do", and the reason it exists is
    /// that `readCapabilities` is partly guessed bit positions in `deviceFuctionData`. A guess
    /// that reads `.unsupported` on a working firmware silently removes a feature — it has
    /// already happened twice here (the auto-measure row, and the stress test's own gate).
    /// This is a plain read: no measurement, no sensor time.
    func readHealthFunctions() async throws -> [BandHealthFunction]
}

extension BandService {
    func cachedHistoryDayOffsets(limit: Int) async throws -> [Int] { [] }
    func readHealthLight() async throws -> BandHealthLightState { throw BandError.unsupported("Health light") }
    func writeHealthLight(_ state: BandHealthLightState) async throws -> BandHealthLightState {
        throw BandError.unsupported("Health light")
    }
    func reconnectForSport() async {
        guard !Task.isCancelled else { return }
        await reconnectIfBound()
    }
    func prepareFreshSync() async {}
    /// 14 · one answer from the band about its sport state: 0 not started, 1 running,
    /// 2 paused; nil if it says nothing within three seconds.
    func sportRunState() async -> Int? {
        let stream = sportLiveInfo()
        let read = Task { () -> Int? in
            for await info in stream { if let state = info.runState { return state } }
            return nil
        }
        let clock = Task { try? await Task.sleep(for: .seconds(3)); read.cancel() }
        let state = await read.value
        clock.cancel()
        return state
    }
    /// For callers that only want the number.
    func measureStress() async throws -> Int { try await measureStress(progress: { _ in }) }
    func measureHRV() async throws -> Int { try await measureHRV(timeout: 60) }
}

/// One step of a running pulse study.
enum PulseStudyStep {
    case waitingForContact
    case contact
    /// `percent` is the band's own count, 0…100. `heartRate` is what it is reporting right
    /// now — nil until it has one, and the screen shows a resting tempo rather than a guess.
    case measuring(percent: Int, heartRate: Int?)
    /// SDK `notLead`: the finger left the electrode. The run is over.
    case lostContact
    case finished(PulseStudy)
    case failed(reason: String)
}

/// What a completed pulse study carries. No waveform, by design — see `measurePulseStudy`.
struct PulseStudy {
    enum Source: String {
        /// The band's own beat-to-beat intervals.
        case intervals
        /// One heart rate a second, converted to the interval it implies. ⚠️ Coarser: the
        /// sampling blunts exactly the fast variation the balance read is about, so a result
        /// built on this says so on screen.
        case perSecondRates
    }

    /// The band's own average over the run.
    let heartRate: Int?
    /// Beat-to-beat intervals in milliseconds, in the order they were measured. This is the
    /// whole input to the balance readout: every number on the result screen is derived from
    /// this series and nothing else.
    /// ⚠️ May be empty. A firmware that reports no intervals gets a result screen that says
    /// so — an autonomic split computed from nothing is the worst thing this screen could do.
    let intervals: [Double]
    /// Where `intervals` came from. The band does not always send beat-to-beat timing, and a
    /// screen that reads one thing off another has to say which it read.
    let source: Source
    /// Seconds the band actually ran, from the SDK.
    let durationSeconds: Int?
    /// The SDK's own HRV figure, kept for the log only.
    /// ⚠️ Never drawn: it came back 12 on a wrist whose HRV history sits at 40–70 ms, with no
    /// unit documented anywhere. 「说不出出处的数字不上屏」.
    let vendorHRV: Int?
}

/// What one 微体检 came back with: every field of VPHealthGlanceTestModel in the SDK's own
/// order, and the band's own bitmask of which metrics this firmware carries.
struct BandHealthGlance {
    /// name → the number the band put in the field. Every field, zeros included: a zero is
    /// evidence too, and dropping it here would hide which fields the band left alone.
    let values: [(name: String, value: Double)]
    /// VPHealthGlanceType, verbatim.
    let functionSupport: UInt

    /// The fifteen bits of VPHealthGlanceType, in the SDK's own order.
    static let supportBits: [(bit: UInt, name: String)] = [
        (1 << 0,  "heart rate"), (1 << 1,  "blood oxygen"), (1 << 2,  "PPG blood pressure"),
        (1 << 3,  "cuff blood pressure"), (1 << 4, "blood glucose"), (1 << 5, "body temperature"),
        (1 << 6,  "stress"), (1 << 7,  "emotion"), (1 << 8,  "fatigue"), (1 << 9, "HRV"),
        (1 << 10, "skin conductance"), (1 << 11, "blood components"), (1 << 12, "body composition"),
        (1 << 13, "ECG single"), (1 << 14, "ECG multi"),
    ]

    var supported: [String] { Self.supportBits.filter { functionSupport & $0.bit != 0 }.map(\.name) }
    var unsupported: [String] { Self.supportBits.filter { functionSupport & $0.bit == 0 }.map(\.name) }
}

/// One row of the band's own health-function list (VPHealthFunctionModel): what it is,
/// whether this firmware carries it, and whether it is switched on.
/// ⚠️ `support == false` is the band saying no. `open` is a setting, not a capability —
/// a supported function that is closed can be opened; an unsupported one cannot.
struct BandHealthFunction: Hashable {
    /// VPHealthFunctionType, carried through verbatim so an unknown future kind still prints.
    let rawValue: Int
    let name: String
    let support: Bool
    let open: Bool

    /// The seventeen VPHealthFunctionType values, in the SDK's own order.
    static func name(forRawValue raw: Int) -> String {
        switch raw {
        case 0:  "blood glucose"
        case 1:  "blood pressure"
        case 2:  "blood oxygen"
        case 3:  "body temperature"
        case 4:  "HRV"
        case 5:  "stress"
        case 6:  "MET"
        case 7:  "blood components"
        case 8:  "body composition"
        case 9:  "health glance"
        case 10: "emotion"
        case 11: "fatigue"
        case 12: "nuclear radiation"
        case 13: "fall detection"
        case 14: "AI chat"
        case 15: "AI dial"
        case 16: "skin conductance"
        default: "type \(raw)"
        }
    }
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
struct BandBattery: Hashable {
    let isPercent: Bool
    let percent: Int?
    let level: Int?
    let chargeState: ChargeState

    enum ChargeState: String, Hashable { case unplugged, charging, full, unknown }

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
    var oxygen: [OxygenSample] = []
    var optical: [OpticalResponseSample] = []
    /// Vendor rows that mapped to nothing (zeros / non-finite). ALL ZEROS uses this.
    var opticalDroppedZeros: Int = 0
    var temperatureStatus: BandDomainReadStatus = .complete
    var hrvStatus: BandDomainReadStatus = .complete
    var oxygenStatus: BandDomainReadStatus = .complete
    var opticalStatus: BandDomainReadStatus = .complete
    var respiration: [RespirationSample] = []
    var respirationStatus: BandDomainReadStatus = .notCollected
}

/// 04B rule 04 · one run of the band's own sleepLine: a stage and how many minutes it held.
/// Stages are the SDK's (VPAccurateSleepModel): 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake —
/// KH firmware emits no 2 or 3.
struct SleepStageRun: Codable, Hashable {
    let stage: Int
    let minutes: Int
    /// Offset from the first recorded sleep start; absent in older stored curves.
    var offsetMinutes: Int? = nil
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
    var intervals: [SleepInterval]? = nil
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
    /// 06 · one pulse study: the rate, and the beat-to-beat intervals behind it.
    case pulseStudy(PulseStudy)
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
}

struct AutoMonitorSlot: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case heartRate, bloodPressure, bloodGlucose, stress
        case bloodOxygen, temperature, lorentz, hrv, scientificSleep, bloodComponents
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

    /// Firmware that only exposes the older on/off switches. The interval is not a setting.
    static func firmwareOwned(kind: Kind, on: Bool) -> AutoMonitorSlot {
        AutoMonitorSlot(
            kind: kind, on: on, supportsRange: false,
            startHour: 0, endHour: 24, intervalMinutes: 0,
            intervalStepMinutes: 0, slotModifiable: false, intervalModifiable: false)
    }
}

/// What `readAutoMonitoring()` actually found. The sheet used to treat "no rows" as a blank
/// page, which hid three different answers: interval API empty, switch-only firmware, and a
/// read that never came back.
enum AutoMonitoringRead: Equatable {
    /// `autoMonitSwitchType != 0`. Each row can carry its own interval.
    case interval([AutoMonitorSlot])
    /// `autoMonitSwitchType == 0`. Only the older base-function switches exist.
    case switches([AutoMonitorSlot])
    case failed(headline: String, sentence: String)

    var slots: [AutoMonitorSlot] {
        switch self {
        case .interval(let slots), .switches(let slots): return slots
        case .failed: return []
        }
    }

    static func failed(_ error: Error) -> AutoMonitoringRead {
        if let error = error as? BandError {
            switch error {
            case .notConnected:
                return .failed(
                    headline: L("BAND OFFLINE"),
                    sentence: L("Connect this HOOP, then open Automatic measurement again."))
            case .timeout:
                return .failed(
                    headline: L("THE BAND DID NOT ANSWER"),
                    sentence: L("The automatic-measurement read timed out. Keep it on your wrist and try again."))
            case .unsupported:
                return .failed(
                    headline: L("THIS HOOP DOES NOT EXPOSE AUTOMATIC MEASUREMENT"),
                    sentence: L("The firmware has no interval API and no automatic-measurement switches to turn."))
            default:
                return .failed(
                    headline: error.localizedDescription,
                    sentence: L("This HOOP refused the automatic-measurement read."))
            }
        }
        return .failed(
            headline: L("THE BAND DID NOT ANSWER"),
            sentence: error.localizedDescription)
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
    func measureStress(progress _: @escaping @MainActor (Int) -> Void) async throws -> Int { throw BandError.notConnected }
    func measureHRV(timeout _: TimeInterval) async throws -> Int { throw BandError.notConnected }
    func writeSetting(_: BandSetting) async throws -> BandSetting { throw BandError.notConnected }
    func checkFirmwareUpdate() async throws -> FirmwareOffer? { throw BandError.notConnected }
    func updateFirmware(to _: String, progress _: @escaping @Sendable (Double) -> Void) async throws -> FirmwareUpdateResult {
        throw BandError.notConnected
    }
    func readAutoMonitoring() async throws -> AutoMonitoringRead { throw BandError.notConnected }
    func writeAutoMonitoring(_: AutoMonitorSlot) async throws { throw BandError.notConnected }
    func probeSportMode(_ rawValue: Int) async throws -> Bool { throw BandError.notConnected }
    func startSportMode(_ rawValue: Int) async throws { throw BandError.notConnected }
    func stopSportMode(_ rawValue: Int) async throws { throw BandError.notConnected }
    /// No SDK, so no wrist to report from: the stream closes rather than hanging a reader.
    func sportLiveInfo() -> AsyncStream<SportLiveInfo> { AsyncStream { $0.finish() } }
    func readHealthFunctions() async throws -> [BandHealthFunction] { throw BandError.notConnected }
    func probeHealthGlance(progress _: @escaping @MainActor (Int) -> Void) async throws -> BandHealthGlance { throw BandError.notConnected }
    func readManualTestData(since _: Date) async throws -> [String] { throw BandError.notConnected }
    func measurePulseStudy() -> AsyncThrowingStream<PulseStudyStep, Error> {
        AsyncThrowingStream { $0.finish(throwing: BandError.notConnected) }
    }
    func probeMicroTest(progress _: @escaping @MainActor (Int) -> Void) async throws -> [(name: String, value: Double)] { throw BandError.notConnected }
}
