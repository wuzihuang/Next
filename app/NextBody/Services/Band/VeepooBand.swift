import Foundation

// The real band, against Veepoo's VeepooBleSDK.framework.
//
// ⚠️ The framework ships arm64 only — `lipo -info` says "Non-fat file: architecture: arm64" —
// so it cannot link into a simulator build at all. That is why the app is written against
// `BandService` with `MockBand` behind it: the simulator runs the whole product, and this
// file takes over the moment the framework is added to the target and the build is for a device.
//
// To enable: drag iOS_Ble_SDK/iOS_sdk_source/Framework/2.2.XX.15/VeepooBleSDK.framework into
// the target's Frameworks, Libraries, and Embedded Content as "Embed & Sign". Nothing else
// changes — `Band.live` picks this up on its own.

#if canImport(VeepooBleSDK)
import VeepooBleSDK

final class VeepooBand: BandService, @unchecked Sendable {
    private let central = VPBleCentralManage.shared()
    private let queue = HoopQueue()

    private(set) var state: BandConnectionState = .idle {
        didSet { continuation?.yield(.state(state)) }
    }
    let events: AsyncStream<BandEvent>
    private var continuation: AsyncStream<BandEvent>.Continuation?

    /// F2 §05 · what we last pushed down. The band's BIA multiplies by this, so a sample
    /// taken before a sync is discarded rather than stored.
    private var pushedWeightKg: Double?
    private var pushedAt: Date?

    init() {
        var c: AsyncStream<BandEvent>.Continuation?
        events = AsyncStream { c = $0 }
        continuation = c

        central.vpBleConnectStateChangeBlock = { [weak self] deviceState in
            guard let self else { return }
            switch deviceState {
            case .connected:    self.state = .connected
            case .disconnect:   self.state = .disconnected
            case .connecting:   self.state = .connecting
            default:            break
            }
        }
    }

    private var peripheral: VPPeripheralBaseManage? { central.peripheralManage }

    // MARK: connection

    func startScan() async {
        state = .scanning
        central.veepooSDKStartScanDeviceAndReceiveScanningDevice { [weak self] model in
            guard let self, let model else { return }
            self.continuation?.yield(.discovered(DiscoveredBand(
                // ⚠️ deviceAddress is a CoreBluetooth UUID on iOS, not a MAC.
                id: model.deviceAddress ?? UUID().uuidString,
                name: model.deviceName ?? "HOOP",
                rssi: model.rssi?.intValue ?? -99,
                batteryPercent: nil)))
        }
    }

    func stopScan() async {
        central.veepooSDKStopScanDevice()
        if state == .scanning { state = .idle }
    }

    func connect(_ device: DiscoveredBand) async throws {
        state = .connecting
        guard let model = central.peripheralModel else { throw BandError.notConnected }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            central.veepooSDKConnectDevice(model) { _ in c.resume() }
        }
    }

    /// The SDK reconnects to a peripheral it already knows by UUID; nothing is re-paired
    /// and no screen from the gate comes back.
    func reconnectIfBound() async {
        guard BoundBand.identifier != nil, state != .connected else { return }
        state = .connecting
        central.automaticConnection = true
        await startScan()
    }

    func disconnect() async {
        central.veepooSDKDisconnectDevice()
        state = .disconnected
    }

    // MARK: identity and capability

    func readIdentity() async throws -> BandIdentity {
        guard let model = central.peripheralModel else { throw BandError.notConnected }
        return BandIdentity(
            name: model.deviceName ?? "HOOP",
            model: model.deviceVersion ?? "—",
            hardware: model.deviceTestVersion ?? "—",
            firmware: model.deviceVersion ?? "—",
            // ⚠️ DeviceVersion.deviceNumber. There is no serial number in this SDK,
            // and no screen may call it one.
            deviceNumber: "HB-\(model.deviceNumber)",
            bleIdentifier: model.deviceAddress ?? "—",
            watchDataDayNumber: Int(model.saveDays))
    }

    func readCapabilities() async throws -> BandCapabilities {
        guard let model = central.peripheralModel else { throw BandError.notConnected }
        var caps = BandCapabilities()
        // The capability bitfields come back as five NSData blobs. Each bit is a
        // FunctionStatus, and we carry the value through rather than squashing it to a Bool:
        // "unknown" and "unsupported" both hide a row, but they are different problems.
        func status(_ data: Data?, byte: Int, shift: Int) -> FunctionStatus {
            guard let data, data.count > byte else { return .unknown }
            switch (data[byte] >> UInt8(shift)) & 0b11 {
            case 0: return .unsupported
            case 1: return .support
            case 2: return .open
            case 3: return .close
            default: return .unknown
            }
        }
        let f1 = model.deviceFuctionData
        let f3 = model.deviceFuctionDataThird
        caps.hrv           = status(f1, byte: 0, shift: 0)
        caps.stress        = status(f1, byte: 0, shift: 2)
        caps.ecg           = status(f1, byte: 1, shift: 0)
        caps.bodyComponent = status(f3, byte: 0, shift: 0)
        caps.autoMeasure   = status(f1, byte: 2, shift: 0)
        caps.wearDetection = status(f1, byte: 2, shift: 2)
        return caps
    }

    func readBattery() async throws -> BandBattery {
        guard let peripheral else { throw BandError.notConnected }
        return try await queue.run("readBattery", priority: .p1) {
            try await withCheckedThrowingContinuation { c in
                peripheral.veepooSDKReadDeviceBatteryAndChargeInfo { isPercent, charge, isLow, value in
                    // ⚠️ Firmware with isPercent = false gives 0–4 bars. Those are stored in a
                    // different column and never rendered with a % sign.
                    c.resume(returning: BandBattery(
                        isPercent: isPercent,
                        percent: isPercent ? Int(value) : nil,
                        level: isPercent ? nil : Int(value),
                        chargeState: {
                            switch charge {
                            case .charging: .charging
                            case .full:     .full
                            case .noCharge: .unplugged
                            default:        .unknown
                            }
                        }()))
                }
            }
        }
    }

    // MARK: personal info

    func syncPersonalInfo(_ info: PersonalInfo) async throws {
        guard let peripheral else { throw BandError.notConnected }
        try await queue.run("syncPersonalInfo", priority: .p0) {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                peripheral.veepooSDKSynchronousPersonalInformation(
                    withStature: UInt(info.heightCm),
                    weight: UInt(info.weightKg),
                    birth: UInt(info.birthYear),
                    sex: UInt(info.sexIsMale ? 1 : 0),
                    targetStep: UInt(info.targetStep)) { _ in c.resume() }
            }
        }
        pushedWeightKg = Double(info.weightKg)
        pushedAt = Date()
    }

    // MARK: reading a day

    /// ⚠️ dayOffset is the SDK's paging parameter and nothing else. Which offsets to ask for
    /// is decided by the user-day window in `OriginDataSync`, never here.
    func readOriginData(dayOffset: Int) async throws -> [OriginPoint] {
        guard let peripheral else { throw BandError.notConnected }
        return try await queue.run("readOriginData(\(dayOffset))", priority: .p2) {
            try await withCheckedThrowingContinuation { c in
                var collected: [OriginPoint] = []
                peripheral.veepooSDK_readBasicData(withDayNumber: dayOffset, maxPackage: 0) {
                    page, total, current in
                    collected.append(contentsOf: (page as? [[String: Any]] ?? []).map(Self.point))
                    if current >= total { c.resume(returning: collected) }
                }
            }
        }
    }

    func readSleep(dayOffset: Int) async throws -> SleepNight? {
        guard let peripheral else { throw BandError.notConnected }
        return try await queue.run("readSleep(\(dayOffset))", priority: .p2) {
            try await withCheckedThrowingContinuation { c in
                peripheral.veepooSDK_readSleepData(withDayNumber: dayOffset) { array in
                    guard let rows = array as? [[String: Any]], !rows.isEmpty else {
                        c.resume(returning: nil); return
                    }
                    // Stage counts only; not one of these numbers reaches a screen (F0 rule 03).
                    let total = rows.compactMap { $0["sleepTime"] as? Int }.reduce(0, +)
                    let deep = rows.filter { ($0["sleepType"] as? Int) == 1 }
                                   .compactMap { $0["sleepTime"] as? Int }.reduce(0, +)
                    c.resume(returning: SleepNight(
                        totalMinutes: total, deepMinutes: deep,
                        lightMinutes: total - deep,
                        wakeCount: rows.filter { ($0["sleepType"] as? Int) == 3 }.count))
                }
            }
        }
    }

    private static func point(_ raw: [String: Any]) -> OriginPoint {
        OriginPoint(
            time: raw["time"] as? String ?? "",
            heart: raw["heartValue"] as? Int,
            step: raw["stepValue"] as? Int,
            // ⚠️ calValue is never used for E_ACTIVE: it already contains the vendor's own
            // basal figure, and adding it to our BMR double-counts. It is stored, not summed.
            cal: raw["calValue"] as? Int,
            distance: raw["disValue"] as? Int,
            met: (raw["met"] as? NSNumber)?.doubleValue,
            spo2: raw["spo2"] as? Int,
            temperature: (raw["temperature"] as? NSNumber)?.doubleValue,
            stress: raw["stressValue"] as? Int,
            sleepState: raw["sleepStatus"] as? Int)
    }

    // MARK: measurement

    func measureHeartRate() -> AsyncThrowingStream<MeasurementProgress, Error> {
        AsyncThrowingStream { c in
            guard let peripheral else { c.finish(throwing: BandError.notConnected); return }
            c.yield(.waitingForContact)
            // F1 rule 05 · stop before the screen goes. `start(false)` is the SDK's stop, and
            // onTermination fires whether the stream ended on its own or the takeover was closed.
            c.onTermination = { _ in peripheral.veepooSDKTestHeartStart(false) { _, _ in } }
            var started = false
            peripheral.veepooSDKTestHeartStart(true) { testState, value in
                switch testState {
                case .testing:
                    // The first `testing` is the contact judgement — not the fact that we
                    // sent `start`. Lighting up on `start` is a lie the user can feel.
                    if !started { started = true; c.yield(.contact) }
                    c.yield(.measuring(fraction: 0.5,
                                       partial: PartialReading(heartRate: Int(value))))
                case .testEnd:
                    c.yield(.finished(.heartRate(hr: Int(value), hrv: nil, stress: nil)))
                    c.finish()
                case .wearError, .notWear:
                    c.yield(.lostContact)
                case .busy:
                    c.finish(throwing: BandError.busy)
                default:
                    break
                }
            }
        }
    }

    func measureBodyComposition() -> AsyncThrowingStream<MeasurementProgress, Error> {
        AsyncThrowingStream { c in
            guard let peripheral else { c.finish(throwing: BandError.notConnected); return }
            // F2 §05 · a sample taken without a fresh syncPersonalInfo is thrown away
            // rather than stored, because the BIA multiplied by a stale weight.
            guard let weight = pushedWeightKg, let at = pushedAt,
                  Date().timeIntervalSince(at) < 300 else {
                c.finish(throwing: BandError.rejected("SYNC YOUR WEIGHT FIRST"))
                return
            }
            c.yield(.waitingForContact)
            // F1 rule 05 · see measureHeartRate. A body scan left running is worse: it holds
            // the electrodes and the queue for the full thirty seconds.
            c.onTermination = { _ in peripheral.veepooSDKTestBodyCompositionStart(false) { _, _ in } }
            var hadContact = false
            peripheral.veepooSDKTestBodyCompositionStart(true) { lead, progress in
                // lead == 0 means the hand is on the electrode.
                if lead == 0 {
                    if !hadContact { hadContact = true; c.yield(.contact) }
                    c.yield(.measuring(fraction: progress.fractionCompleted, partial: nil))
                } else if hadContact {
                    // ⚠️ Body composition has no resume: lifting off restarts the 30 seconds.
                    hadContact = false
                    c.yield(.lostContact)
                }
            } testResult: { state, model in
                guard state == .success, let model else {
                    c.yield(.failed(reason: "SCAN DID NOT COMPLETE")); c.finish(); return
                }
                c.yield(.finished(.bodyComposition(BodyCompositionReading(
                    bodyFatPercent: model.bodyFatRate,
                    fatMassKg: model.bodyFatMass,
                    leanMassKg: model.leanBodyMass,
                    muscleKg: model.muscleMass,
                    boneKg: model.boneMass,
                    bodyWaterPercent: model.moistureRate,
                    proteinPercent: model.proteinRate,
                    subcutaneousFatPercent: model.subcutaneousFatRate,
                    skeletalMusclePercent: model.skeletalMuscleRate,
                    // ⚠️ The BIA's own basalMetabolicRate is a MEASURED reference only.
                    // It never enters the budget — Mifflin does. Electrode contact can move
                    // it by tens of kcal, and a budget that shifts with grip is unfindable.
                    bmrKcal: Int(model.basalMetabolicRate),
                    bmi: model.bmi,
                    inputWeightKg: weight))))
                c.finish()
            }
        }
    }

    // MARK: settings

    func writeSetting(_ setting: BandSetting) async throws -> BandSetting {
        guard let peripheral else { throw BandError.notConnected }
        // F3 · the switch renders the value that came back. Optimistic UI here means the
        // firmware wins a second later and the toggle flips under the user's finger.
        return try await queue.run("writeSetting", priority: .p0) {
            switch setting {
            case .heartRateAlarm(let on, let low, let high):
                let model = VPDeviceHeartAlarmModel()
                model.isOpen = on
                model.heartAlarmHighValue = UInt(high)
                model.heartAlarmLowValue = UInt(low)
                return try await withCheckedThrowingContinuation { c in
                    peripheral.veepooSDKSettingDeviceHeartAlarm(with: model, settingMode: 1) { back in
                        c.resume(returning: .heartRateAlarm(
                            on: back?.isOpen ?? on,
                            low: Int(back?.heartAlarmLowValue ?? UInt(low)),
                            high: Int(back?.heartAlarmHighValue ?? UInt(high))))
                    } failureResult: {
                        c.resume(throwing: BandError.rejected("HEART RATE ALARM REFUSED"))
                    }
                }
            default:
                throw BandError.unsupported("that setting")
            }
        }
    }

    func readAutoMonitoring() async throws -> [AutoMonitorSlot] {
        guard let peripheral else { throw BandError.notConnected }
        return try await queue.run("readAutoMonitoring", priority: .p1) {
            try await withCheckedThrowingContinuation { c in
                peripheral.veepooSDKReadAutoMonitSwitchInfo { models in
                    // ⚠️ One entry per measurement type, each with its own window and
                    // interval. That is why 12's row leads to a sheet rather than a switch.
                    c.resume(returning: (models ?? []).compactMap { m in
                        guard let kind = Self.kind(m.type) else { return nil }
                        return AutoMonitorSlot(
                            kind: kind, on: m.on, supportsRange: m.supportRangeTime,
                            startHour: Int(m.startHour), endHour: Int(m.endHour),
                            intervalMinutes: Int(m.timeInterval))
                    })
                }
            }
        }
    }

    func writeAutoMonitoring(_ slot: AutoMonitorSlot) async throws {
        guard let peripheral else { throw BandError.notConnected }
        try await queue.run("writeAutoMonitoring", priority: .p0) {
            let models = try await self.readAutoMonitoring()
            _ = models
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                let m = VPAutoMonitTestModel()
                m.on = slot.on
                m.startHour = UInt8(slot.startHour)
                m.endHour = UInt8(slot.endHour)
                m.timeInterval = UInt16(slot.intervalMinutes)
                peripheral.veepooSDKSetAutoMonitSwitch(with: m) { _ in c.resume() }
            }
        }
    }

    private static func kind(_ type: VPAutoMonitTestType) -> AutoMonitorSlot.Kind? {
        switch type {
        case .heartRate:       .heartRate
        case .bloodPressure:   .bloodPressure
        case .bloodGlucose:    .bloodGlucose
        case .stress:          .stress
        case .bloodOxygen:     .bloodOxygen
        case .bodyTemperature: .temperature
        case .lorentz:         .lorentz
        case .hrv:             .hrv
        case .bloodComponents: .bloodComponents
        @unknown default:      nil
        }
    }
}
#endif

/// Which band this phone is bound to. ⚠️ On iOS this is a CoreBluetooth UUID, so it is
/// meaningful only on this phone — a new phone re-pairs, and the history is on the server.
enum BoundBand {
    private static let key = "nb.band.identifier"
    static var identifier: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.setValue(newValue, forKey: key) }
    }
    /// "Forget this HOOP" is the app clearing its own device id — the history stays.
    static func forget() { UserDefaults.standard.removeObject(forKey: key) }
}

/// One place decides which band the app is talking to.
enum Band {
    static let live: BandService = {
        #if canImport(VeepooBleSDK) && !targetEnvironment(simulator)
        return VeepooBand()
        #else
        return MockBand()
        #endif
    }()

    /// True when the app is driving a real band rather than the simulator's stand-in.
    static var isReal: Bool {
        #if canImport(VeepooBleSDK) && !targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
