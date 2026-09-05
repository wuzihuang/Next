import Foundation
import os
import CoreBluetooth

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
    private let central: VPBleCentralManage = VPBleCentralManage.sharedBleManager()!
    private let queue = HoopQueue()

    private(set) var state: BandConnectionState = .idle {
        didSet { hub.send(.state(state)) }
    }
    private let hub = BandEventHub()
    var events: AsyncStream<BandEvent> { hub.stream() }
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "band")
    /// Heart-rate tests share one SDK result block. A late `onTermination` stop from the
    /// previous stream must not clear the block a newer stream just installed — otherwise
    /// Battery Check sits on 「Still nothing on the key」 with a band that is measuring.
    private var heartTestGeneration = 0
    @MainActor private let sportSubscription = BandSportSubscription()
    @MainActor private var sportReaders: [UUID: AsyncStream<SportLiveInfo>.Continuation] = [:]
    @MainActor private var sportPoll: Task<Void, Never>?
    @MainActor private var sportLastReceipt = Date.distantPast

    /// What the last scan reported, by CoreBluetooth identifier. `connect` hands the SDK the
    /// very model it scanned; `central.peripheralModel` is only set once a device is connected,
    /// so reading it before connecting always found nothing.
    private var scanned: [String: VPPeripheralModel] = [:]

    /// F2 §05 · what we last pushed down. The band's BIA multiplies by this, so a sample
    /// taken before a sync is discarded rather than stored.
    private var pushedWeightKg: Double?
    private var pushedAt: Date?

    init() {
        // The app owns reconnection. Disable the SDK's default auto-connect before its
        // initial PoweredOn callback can race the early readiness lane.
        central.automaticConnection = false
        // ⚠️ Which subclass sits here decides whether the day can be read at all, and it has
        // to be set before the first connect (doc §SDK初始化).
        //  · VPPeripheralBaseManage (what the SDK leaves in place): readBasicData, readSleepData
        //    and readStepData are a single `ret`. Two syncs on a real HOOP ran exactly 90 s —
        //    the timeout — and wrote nothing, while battery and BIA worked.
        //  · VPPeripheralAddManage ("应用层自行持久化"): the commands go out and twenty packages
        //    came back with nil arrays on a previous device/protocol. The current SDK also
        //    has a protocol 3/5 terminal parser, audited only in the isolated debug launch.
        //  · VPPeripheralManage ("SDK持久化", what the vendor recommends and the demo uses):
        //    veepooSdkStartReadDeviceAllData reads every day the band holds into the SDK's own
        //    database, and VPDataBaseOperation hands it back keyed by "HH:mm". That is the path.
        // Keep app-owned timing/receipt logs; enable verbose vendor protocol logs explicitly.
        central.isLogEnable = ProcessInfo.processInfo.environment["NB_BLE_VERBOSE"] == "1"
        #if DEBUG
        if ProcessInfo.processInfo.environment["NB_HRV_FULL_PROBE"] == "1" {
            central.peripheralManage = VPPeripheralAddManage.shareVPPeripheralManager()
        } else {
            central.peripheralManage = VPPeripheralManage.shareVPPeripheralManager()
        }
        #else
        central.peripheralManage = VPPeripheralManage.shareVPPeripheralManager()
        #endif
        central.vpBleConnectStateChangeBlock = { [weak self] deviceState in
            guard let self else { return }
            Self.log.notice("connect state \(deviceState.rawValue)")
            // Real SDK enum is VPDeviceConnectState (imported without the prefix):
            // .connect / .disConnect / .connecting / .verifyPasswordSuccess / .timeout …
            switch deviceState {
            case .connectStateVerifyPasswordSuccess: self.state = .connected
            case .connectStateConnect: self.state = .connecting
            case .connectStateDisConnect, .connectStateVerifyPasswordFailure, .connectStateTimeout: self.state = .disconnected
            case .connectStateConnecting: self.state = .connecting
            // The SDK asked its server on connect and found newer firmware. Only a log here:
            // the device page asks again on its own and draws the answer, so the card is
            // never a stale flag from an earlier link.
            case .discoverNewUpdateFirm: Self.log.notice("sdk reports new firmware \(self.central.peripheralModel?.deviceNetVersion ?? "?", privacy: .public)")
            default: break
            }
        }
    }

    private var peripheral: VPPeripheralBaseManage? { central.peripheralManage }

    #if DEBUG
    /// Isolated, read-only protocol audit. The debug launch must never start normal sync/live.
    /// AddManage's terminal array is parsed only after the SDK receives its end marker;
    /// intermediate callbacks legitimately carry nil, so preserve every callback separately.
    func debugReadFullDayFromFirstPackage() async throws -> [[String: Any]] {
        guard ProcessInfo.processInfo.environment["NB_HRV_FULL_PROBE"] == "1",
              central.peripheralManage is VPPeripheralAddManage,
              let binding = BoundBand.identifier else {
            throw BandError.rejected("Full HRV probe requires isolated launch")
        }
        return try await queue.run("debugFullDay", priority: .p2) {
            try Task.checkCancellation()
            return try await self.sdk("debugFullDay", seconds: 120) { done in
                guard self.state == .connected, BoundBand.identifier == binding,
                      let peripheral = self.peripheral,
                      let model = self.central.peripheralModel,
                      let identifier = model.peripheral?.identifier.uuidString,
                      BandSyncPolicy.matchesBoundDevice(discovered: identifier,
                        bound: binding, boundPeripheral: BoundBand.peripheralIdentifier) else {
                    done(.failure(BandError.notConnected)); return
                }
                let protocolType = model.fiveProtocolType
                let hrvType = model.hrvType
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("hrv-full-callback.json")
                var callbacks: [[String: Any]] = []
                func persist() throws {
                    let payload: [String: Any] = ["fiveProtocolType": protocolType,
                        "hrvType": hrvType, "callbackCount": callbacks.count,
                        "callbacks": callbacks]
                    try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                        .write(to: url, options: .atomic)
                }
                do { try persist() } catch { done(.failure(error)); return }
                Self.log.notice("full HRV probe protocol=\(protocolType) hrvType=\(hrvType)")
                peripheral.veepooSDK_readBasicData(withDayNumber: 0, maxPackage: 1) { array, total, current in
                    guard self.state == .connected, BoundBand.identifier == binding else {
                        done(.failure(BandError.notConnected)); return
                    }
                    callbacks.append(["totalPackage": total, "currentPackage": current,
                                      "data": array.map { $0 as Any } ?? NSNull()])
                    do { try persist() } catch { done(.failure(error)); return }
                    Self.log.notice("full HRV callback count=\(callbacks.count) package=\(current)/\(total) rows=\(array?.count ?? 0)")
                    guard total > 0, current >= total else { return }
                    // Progress callbacks can reach total before the separate end marker.
                    // Nil is not completion; retain it and wait for parsed data or timeout.
                    guard array != nil else { return }
                    guard let rows = array as? [[String: Any]], !rows.isEmpty else {
                        done(.failure(BandError.rejected("Full HRV probe completed without parsed rows")))
                        return
                    }
                    done(.success(rows))
                }
            }
        }
    }
    #endif

    // MARK: connection

    func startScan() async { await startScan(auto: false) }

    /// `auto` is the SDK's automaticConnection: on, it connects to its last band the moment
    /// the scan sees it. A manual scan from 02 must never do that — the pairing chain then
    /// ran twice, once by the SDK and once by the app, and the band answered nothing after.
    private func startScan(auto: Bool) async {
        state = .scanning
        await MainActor.run {
            scanned = [:]
            central.automaticConnection = auto
        }
        // The SDK's CBCentralManager is created on first use and reports poweredOn a few
        // milliseconds later. Asked to scan before that, it does nothing at all — the device
        // log showed "scan start" 8 ms ahead of the system's "state On", then 15 s of silence.
        await waitForPoweredOn()
        guard !Task.isCancelled else { return }
        Self.log.notice("scan start")
        // ⚠️ Every SDK entry point runs on the main thread. The SDK keeps its scan, connect and
        // confirm timeouts on NSTimers, which only fire on a run loop; called from a Swift
        // concurrency thread, a connect that never answers also never times out.
        await MainActor.run {
            central.veepooSDKStartScanDeviceAndReceiveScanningDevice { [weak self] model in
                guard let self, let model else { return }
                // SDK deviceAddress can change from UUID to MAC after verification.
                // CoreBluetooth identity stays stable on this phone.
                guard let id = model.peripheral?.identifier.uuidString else { return }
                let name = model.deviceName ?? "HOOP"
                let rssi = model.rssi?.intValue ?? -99
                let bound = BoundBand.identifier
                let matches = BandSyncPolicy.matchesBoundDevice(discovered: id, sdkAddress: model.deviceAddress,
                    bound: bound, boundPeripheral: BoundBand.peripheralIdentifier)
                Self.log.notice("scan found device · rssi \(rssi) · boundMatch \(matches) · sdkAddressIsUUID \(UUID(uuidString: model.deviceAddress ?? "") != nil)")
                self.scanned[id] = model
                self.hub.send(.discovered(DiscoveredBand(id: id, name: name, rssi: rssi, batteryPercent: nil)))
            }
        }
    }

    /// Up to 5 s for the SDK's central to report poweredOn; 02 edge 2 covers the radio being
    /// off, so this only bridges the manager's own start-up.
    private func waitForPoweredOn() async {
        for _ in 0..<50 {
            guard !Task.isCancelled else { return }
            if central.centralManager?.state == .poweredOn { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        Self.log.error("scan: central never reached poweredOn (state \(self.central.centralManager?.state.rawValue ?? -1))")
    }

    func stopScan() async {
        Self.log.notice("scan stop")
        await MainActor.run { central.veepooSDKStopScanDevice() }
        if state == .scanning { state = .idle }
    }

    func connect(_ device: DiscoveredBand) async throws {
        // The SDK may already hold a verified link to this very band (a reconnect, or an
        // auto-connect it started itself). Pairing it a second time is what left the band
        // silent to every command after — so a verified link is simply kept.
        if state == .connected, central.peripheralModel?.peripheral?.identifier.uuidString == device.id {
            Self.log.notice("connect: already verified")
            BoundBand.remember(peripheralIdentifier: device.id)
            return
        }
        guard let model = await MainActor.run(body: { scanned[device.id] }) else {
            state = .disconnected
            Self.log.error("connect: requested device was not in the last scan")
            throw BandError.notConnected
        }
        state = .connecting
        var verified = false
        defer { if !verified { state = .disconnected } }
        Self.log.notice("connect start")
        let once = Once()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            // 02 edge 4 · STOPPED. The SDK's own 30 s timeout is the app's last line, not its
            // first: on the device the link to a G70 was requested and never answered, and
            // nothing came back for minutes. The bar stops where it was and offers a retry.
            Task {
                try? await Task.sleep(for: .seconds(30))
                guard once.claim() else { return }
                Self.log.error("connect: no answer in 30 s")
                await MainActor.run { central.veepooSDKDisconnectDevice() }
                c.resume(throwing: BandError.timeout("connect"))
            }
            Task { @MainActor in
                // The block reports every step (connecting → connected → password verified …).
                // A continuation may resume once, so only the terminal states do — and the
                // pairing bar's later reads need the password verified, not just the link up.
                central.veepooSDKConnectDevice(model) { step in
                    Self.log.notice("connect step \(step.rawValue)")
                    switch step {
                    case .BleVerifyPasswordSuccess:
                        if once.claim() { c.resume() }
                    case .BlePoweredOff, .BleConnectFailed, .BleVerifyPasswordFailure:
                        if once.claim() { c.resume(throwing: BandError.rejected("connect step \(step.rawValue)")) }
                    case .BleConnectTimeout, .BleConfirmTimeout:
                        if once.claim() { c.resume(throwing: BandError.timeout("connect")) }
                    case .BleConnecting, .BleConnectSuccess:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }
        try Task.checkCancellation()
        verified = true
        state = .connected
        BoundBand.remember(peripheralIdentifier: device.id)
    }

    /// Every peripheral command goes to the SDK on the main thread — its timers and
    /// callbacks live there — and answers exactly once, or throws after `seconds`. A command
    /// the band never answers is a STOPPED edge on screen, never a bar frozen at 100 %.
    private func sdk<T>(_ name: String, seconds: Double = 12,
                        _ body: @escaping (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let once = Once()
        Self.log.notice("\(name, privacy: .public) →")
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                guard once.claim() else { return }
                Self.log.error("\(name, privacy: .public): no answer in \(seconds) s")
                c.resume(throwing: BandError.timeout(name))
            }
            DispatchQueue.main.async {
                body { result in
                    guard once.claim() else { return }
                    switch result {
                    case .success: Self.log.notice("\(name, privacy: .public) ← ok")
                    case .failure(let e): Self.log.error("\(name, privacy: .public) ← \(String(describing: e), privacy: .public)")
                    }
                    c.resume(with: result)
                }
            }
        }
    }

    /// One outcome per connect: whichever of the SDK's callback and the app's timer claims
    /// first resumes the continuation, the other is ignored.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    /// The SDK reconnects to a peripheral it already knows by UUID; nothing is re-paired
    /// and no screen from the gate comes back.
    private var reconnectTask: Task<Void, Never>?
    @MainActor private var sportReconnectGeneration = 0

    /// The sport lifetime owns this attempt and cancels it before handing the sensor back.
    /// No detached shared reconnect task survives stop or an account/binding change.
    @MainActor func reconnectForSport() async {
        guard state != .connected, !Task.isCancelled, ConsentStore.shared.granted,
              let account = SupabaseClient.currentUserIdSnapshot(),
              let binding = BoundBand.identifier else { return }
        sportReconnectGeneration += 1
        let generation = sportReconnectGeneration
        let alias = BoundBand.peripheralIdentifier
        var touchedNative = false
        func ownsAttempt() -> Bool {
            sportReconnectGeneration == generation && BoundBand.identifier == binding
                && SupabaseClient.currentUserIdSnapshot() == account
        }
        func mayContinue() -> Bool { ownsAttempt() && ConsentStore.shared.granted && !Task.isCancelled }
        defer {
            if ownsAttempt(), touchedNative {
                central.veepooSDKStopScanDevice()
                if state != .connected || Task.isCancelled || !ConsentStore.shared.granted {
                    central.veepooSDKDisconnectDevice()
                    state = .disconnected
                }
            }
            if sportReconnectGeneration == generation { sportReconnectGeneration += 1 }
        }
        // A normal readiness flight may still be winding down when the workout takes over.
        // Do not replace its SDK callback while it is alive.
        while reconnectTask != nil {
            guard mayContinue() else { return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard mayContinue(), state != .connected else { return }
        touchedNative = true
        await startScan(auto: false)
        guard mayContinue() else { return }
        for _ in 0..<100 {
            guard mayContinue() else { return }
            if let target = scanned.first(where: {
                BandSyncPolicy.matchesBoundDevice(discovered: $0.key,
                    sdkAddress: $0.value.deviceAddress, bound: binding, boundPeripheral: alias)
            }) {
                central.veepooSDKStopScanDevice()
                state = .connecting
                var outcome: Bool?
                central.veepooSDKConnectDevice(target.value) { step in
                    Task { @MainActor in
                        guard self.sportReconnectGeneration == generation,
                              BoundBand.identifier == binding,
                              SupabaseClient.currentUserIdSnapshot() == account else { return }
                        switch step {
                        case .BleVerifyPasswordSuccess: outcome = true
                        case .BlePoweredOff, .BleConnectFailed, .BleVerifyPasswordFailure,
                             .BleConnectTimeout, .BleConfirmTimeout: outcome = false
                        default: break
                        }
                    }
                }
                for _ in 0..<300 {
                    guard mayContinue() else { return }
                    if let outcome {
                        if outcome {
                            BoundBand.remember(peripheralIdentifier: target.key)
                            state = .connected
                        }
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
                return
            }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
    }

    func reconnectIfBound() async {
        guard BoundBand.identifier != nil, state != .connected else { return }
        if let running = reconnectTask { await running.value; return }
        let task = Task {
            for attempt in 1...BandSyncPolicy.connectionAttempts {
                guard !Task.isCancelled, self.state != .connected else { break }
                // The SDK's remembered peripheral can differ from our durable binding.
                // Scan explicitly, then connect only the bound UUID through the verified path.
                await self.startScan(auto: false)
                for _ in 0..<200 {
                    if self.state == .connected || Task.isCancelled { break }
                    let target = await MainActor.run {
                        self.scanned.first {
                            BandSyncPolicy.matchesBoundDevice(discovered: $0.key, sdkAddress: $0.value.deviceAddress,
                                bound: BoundBand.identifier, boundPeripheral: BoundBand.peripheralIdentifier)
                        }
                    }
                    if let target {
                        await self.stopScan()
                        do {
                            try await self.connect(DiscoveredBand(id: target.key,
                                name: target.value.deviceName ?? "HOOP", rssi: target.value.rssi?.intValue ?? -99,
                                batteryPercent: nil))
                            if !Task.isCancelled { self.state = .connected }
                        } catch {
                            Self.log.error("bound reconnect failed: \(String(describing: error), privacy: .public)")
                        }
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                await MainActor.run {
                    self.central.veepooSDKStopScanDevice()
                    self.central.automaticConnection = false
                }
                if self.state == .connected { break }
                Self.log.notice("reconnect attempt \(attempt) failed")
                await MainActor.run { self.central.veepooSDKDisconnectDevice() }
                if attempt < BandSyncPolicy.connectionAttempts {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            if self.state != .connected { self.state = .disconnected }
        }
        reconnectTask = task
        await task.value
        reconnectTask = nil
    }

    func prepareFreshSync() async {
        allDataReadAt = nil
        auxiliaryDataReadAt = nil
    }

    func disconnect() async {
        reconnectTask?.cancel()
        await MainActor.run { central.veepooSDKDisconnectDevice() }
        if let running = reconnectTask { await running.value }
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
            watchDataDayNumber: Int(model.saveDays),
            // VPPeripheralModel.runningSaveTimes / runningType: zero saved sessions means
            // no sport mode at all. The header documents only runningType 0 (single
            // generic mode) and 1 (the ten-sport set) — any other value is shown raw,
            // because the SDK nowhere says what it counts. Which sports those are, only
            // the band's own workout list can say.
            sportMode: model.runningSaveTimes == 0
                ? "NONE"
                : model.runningType == 0 ? "SINGLE"
                : model.runningType == 1 ? "10 TYPES"
                : "T\(model.runningType) · UNDOCUMENTED")
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
        // autoMonitSwitchType is the explicit capability for the auto-measure sheet's
        // read/write APIs — the bit below it was a guessed position that read as
        // unsupported on real firmware and greyed out a working row.
        caps.autoMeasure   = model.autoMonitSwitchType == 0 ? .unsupported : .support
        caps.wearDetection = status(f1, byte: 2, shift: 2)
        // These are explicit post-verification capability fields. Temperature is not encoded
        // in the guessed bit positions above, and hrvType is authoritative when present.
        caps.functions["heart"] = model.heartRateType == 0 ? .unsupported : .support
        caps.functions["temperature"] = model.temperatureType == 0 ? .unsupported : .support
        if model.hrvType != 0 { caps.hrv = .support }
        return caps
    }

    /// Keep status reads and writes on the same queue as all other configuration commands.
    func readHealthLight() async throws -> BandHealthLightState {
        try await healthLightCommand(nil)
    }

    func writeHealthLight(_ state: BandHealthLightState) async throws -> BandHealthLightState {
        try await healthLightCommand(state)
    }

    private func healthLightCommand(_ requested: BandHealthLightState?) async throws -> BandHealthLightState {
        let binding = BoundBand.identifier
        let name = requested == nil ? "readHealthLight" : "writeHealthLight"
        return try await queue.run(name, priority: requested == nil ? .p1 : .p0) {
            try Task.checkCancellation()
            return try await self.sdk(name) { done in
                guard self.state == .connected,
                      binding == BoundBand.identifier, let peripheral = self.peripheral else {
                    done(.failure(BandError.notConnected)); return
                }
                guard let model = self.central.peripheralModel, model.healthLightType != 0 else {
                    done(.failure(BandError.unsupported("Health light"))); return
                }
                let reply: (Bool, VPHealthLightStatusType) -> Void = { success, state in
                    done(Result { try BandHealthLightState.confirmedState(
                        success: success, rawValue: Int(state.rawValue)) })
                }
                if let requested, let native = VPHealthLightStatusType(rawValue: UInt(requested.rawValue)) {
                    peripheral.veepooSDKSetHealthLightStatus(native, callBack: reply)
                } else {
                    peripheral.veepooSDKReadHealthLightStatus { reply(true, $0) }
                }
            }
        }
    }

    func readBattery() async throws -> BandBattery {
        guard let peripheral else { throw BandError.notConnected }
        return try await queue.run("readBattery", priority: .p1) {
            try await self.sdk("readBattery") { done in
                peripheral.veepooSDKReadDeviceBatteryAndChargeInfo { isPercent, charge, isLow, value in
                    // ⚠️ Firmware with isPercent = false gives 0–4 bars. Those are stored in a
                    // different column and never rendered with a % sign.
                    // The SDK keeps this block and fires it again when charge changes —
                    // 12 rule 07 · bind the event, do not poll. Later fires still publish
                    // even though `done` only completes the first readBattery().
                    let battery = BandBattery(
                        isPercent: isPercent,
                        percent: isPercent ? Int(value) : nil,
                        level: isPercent ? nil : Int(value),
                        chargeState: {
                            switch charge {
                            case .charging: .charging
                            case .full:     .full
                            case .normal:   .unplugged
                            default:        .unknown
                            }
                        }())
                    self.hub.send(.battery(battery))
                    done(.success(battery))
                }
            }
        }
    }

    // MARK: personal info

    func syncPersonalInfo(_ info: PersonalInfo) async throws {
        guard let peripheral else { throw BandError.notConnected }
        let account = SupabaseClient.currentUserIdSnapshot()
        let binding = BoundBand.identifier
        @MainActor func ownsRequest() -> Bool {
            self.state == .connected && BandPersonalInfoPolicy.owns(
                expectedAccount: account, expectedBinding: binding,
                account: SupabaseClient.currentUserIdSnapshot(), binding: BoundBand.identifier,
                consent: ConsentStore.shared.granted)
        }
        guard await ownsRequest() else { throw CancellationError() }
        guard info.heightCm > 0, info.weightKg > 0, info.birthYear > 0,
              info.birthYear <= Calendar.current.component(.year, from: Date()),
              (0...60000).contains(info.targetStep) else {
            throw BandError.rejected("INVALID PERSONAL INFORMATION")
        }
        try await queue.run("syncPersonalInfo", priority: .p0) {
            try await self.sdk("syncPersonalInfo") { (done: @escaping (Result<Void, Error>) -> Void) in
                // sdk() invokes its body on DispatchQueue.main.
                MainActor.assumeIsolated {
                // Recheck when the queued command actually reaches the native API.
                guard ownsRequest() else { done(.failure(CancellationError())); return }
                peripheral.veepooSDKSynchronousPersonalInformation(
                    withStature: UInt(info.heightCm),
                    weight: UInt(info.weightKg),
                    birth: UInt(info.birthYear),
                    sex: UInt(info.sexIsMale ? 1 : 0),
                    targetStep: UInt(info.targetStep)) { result in
                        if BandPersonalInfoPolicy.acknowledged(result) { done(.success(())) }
                        else { done(.failure(BandError.rejected("PERSONAL INFORMATION SYNC FAILED"))) }
                    }
                }
            }
        }
        try await MainActor.run {
            guard ownsRequest() else { throw CancellationError() }
            self.pushedWeightKg = Double(info.weightKg)
            self.pushedAt = Date()
        }
    }

    // MARK: reading a day

    /// When the band's whole store was last read into the SDK database. A sync and the
    /// backfill behind it ask for seven days in a row; one read serves them all.
    private var allDataReadAt: Date?

    /// Dedicated HRV/temperature reads also populate every retained day. Cache the command,
    /// but not the database query, so a two-page 04:00 window does not ask the band for the
    /// same history twice.
    private var auxiliaryDataReadAt: Date?

    /// The SDK reads every day the band still holds — sleep, steps, heart, stress, the lot —
    /// into its own database, day by day, and reports progress. One command, and until its
    /// `.complete` nothing else may be sent (doc §四: 「数据没有读取完成的时候不要重复调用」),
    /// which the serial queue already guarantees.
    private func readAllDataIfStale() async throws {
        if let at = allDataReadAt, Date().timeIntervalSince(at) < 60 { return }
        guard let peripheral else { throw BandError.notConnected }
        // Seven days at the band's pace can take a few minutes; the read of a single fresh
        // day is seconds. The timeout is the ceiling, not the expectation.
        try await sdk("readAllData", seconds: 300) { (done: @escaping (Result<Void, Error>) -> Void) in
            peripheral.veepooSdkStartReadDeviceAllData { state, totalDay, day, progress in
                switch state {
                case .start:
                    Self.log.notice("readAllData start · \(totalDay) days on the band")
                case .reading:
                    Self.log.notice("readAllData day \(day)/\(totalDay) · \(progress)%")
                case .complete:
                    done(.success(()))
                case .invalid:
                    done(.failure(BandError.rejected("readAllData: SDK reports invalid")))
                @unknown default:
                    break
                }
            }
        }
        allDataReadAt = Date()
    }

    /// ⚠️ dayOffset is the SDK's paging parameter and nothing else. Which offsets to ask for
    /// is decided by the user-day window in `OriginDataSync`, never here.
    func readOriginData(dayOffset: Int) async throws -> [OriginPoint] {
        guard peripheral != nil, let address = central.peripheralModel?.deviceAddress else {
            throw BandError.notConnected
        }
        return try await queue.run("readOriginData(\(dayOffset))", priority: .p2) {
            try await self.readAllDataIfStale()
            let date = Self.dayString(daysAgo: dayOffset)
            // The table is keyed by the device address the SDK connected with — on iOS the
            // CoreBluetooth identifier, exactly as the vendor demo passes it.
            let day = await MainActor.run {
                VPDataBaseOperation.veepooSDKGetOriginalData(withDate: date, andTableID: address)
                    as? [String: [String: Any]] ?? [:]
            }
            let points = day.map { Self.point(time: $0.key, $0.value) }
                .sorted { $0.time < $1.time }
            if let first = points.first {
                let heartN = points.filter { $0.heart != nil }.count
                let stressN = points.filter { $0.stress != nil }.count
                Self.log.notice("readOriginData(\(dayOffset)) \(date, privacy: .public) · \(points.count) points · heart \(heartN) · stress \(stressN) · first \(first.time, privacy: .public)")
                if let keys = day.values.first?.keys {
                    Self.log.notice("origin keys · \(Array(keys).sorted().joined(separator: ","), privacy: .public)")
                }
            } else {
                Self.log.notice("readOriginData(\(dayOffset)) \(date, privacy: .public) · 0 points")
            }
            return points
        }
    }

    /// The public SDK exposes date queries, but no date inventory for health tables.
    /// Probe at most seven calendar pages locally; never refresh the band's memory here.
    func cachedHistoryDayOffsets(limit: Int) async throws -> [Int] {
        guard let address = central.peripheralModel?.deviceAddress else { throw BandError.notConnected }
        let lastOffset = min(max(limit, 0), 6)
        guard lastOffset > 0 else { return [] }
        return await MainActor.run {
            var offsets: Set<Int> = []
            for offset in 0...lastOffset {
                let date = Self.dayString(daysAgo: offset)
                let origin = VPDataBaseOperation.veepooSDKGetOriginalData(withDate: date, andTableID: address)
                    as? [String: [String: Any]] ?? [:]
                let temperatures = VPDataBaseOperation.veepooSDKGetDeviceTemperatureData(withDate: date, andTableID: address)
                    as? [[String: Any]] ?? []
                let hrv = VPDataBaseOperation.veepooSDKGetDeviceHrvData(withDate: date, andTableID: address)
                    as? [[String: Any]] ?? []
                let oxygen = VPDataBaseOperation.veepooSDKGetDeviceOxygenData(withDate: date, andTableID: address)
                    as? [[String: Any]] ?? []
                let optical = VPDataBaseOperation.veepooSDKGetDeviceBloodGlucoseData(withDate: date, andTableID: address)
                    as? [[String: Any]] ?? []
                let accurateSleep = VPDataBaseOperation.veepooSDKGetAccurateSleepData(withDate: date, andTableID: address) ?? []
                let plainSleep = VPDataBaseOperation.veepooSDKGetSleepData(withDate: date, andTableID: address)
                    as? [[String: Any]] ?? []
                if !origin.isEmpty || !temperatures.isEmpty || !hrv.isEmpty || !oxygen.isEmpty
                    || !optical.isEmpty || !accurateSleep.isEmpty || !plainSleep.isEmpty {
                    if offset > 0 { offsets.insert(offset) }
                }
                // 00:00–03:59 belongs to the previous user day. Preserve that recovery
                // target even when the SDK's only stored page is today's calendar date.
                let clocks = Array(origin.keys)
                    + temperatures.compactMap { HealthSampleMapping.temperature(from: $0)?.time }
                    + (hrv + oxygen + optical).compactMap { $0["time"] as? String ?? $0["Time"] as? String }
                let hasEarlyReading = clocks.contains { clock in
                    Int(clock.prefix(2)).map { (0..<4).contains($0) } ?? false
                }
                if hasEarlyReading && offset < lastOffset { offsets.insert(offset + 1) }
            }
            return offsets.sorted()
        }
    }

    /// HRV and temperature are separate history domains in Veepoo's database. `allData`
    /// populates temperature only for type 5; types 2/4 require the dedicated command.
    func readHealthData(dayOffset: Int) async throws -> BandHealthData {
        guard let peripheral, let model = central.peripheralModel,
              let address = model.deviceAddress else { throw BandError.notConnected }
        return try await queue.run("readHealthData(\(dayOffset))", priority: .p2) {
            try await self.readAllDataIfStale()
            let auxiliaryIsStale = self.auxiliaryDataReadAt.map {
                Date().timeIntervalSince($0) >= 60
            } ?? true
            var hrvStatus: BandDomainReadStatus = model.hrvType == 0 ? .unsupported : .complete
            var temperatureStatus: BandDomainReadStatus = model.temperatureType == 0 ? .unsupported : .complete
            var oxygenStatus: BandDomainReadStatus = model.oxygenType == 0 ? .unsupported : .complete
            var opticalStatus: BandDomainReadStatus = model.bloodGlucoseType == 0 ? .unsupported : .complete
            if auxiliaryIsStale {
                if model.hrvType != 0 {
                    do { try await self.sdk("readHRV", seconds: 300) { (done: @escaping (Result<Void, Error>) -> Void) in
                        peripheral.veepooSdkStartReadDeviceHrvData { state, _, _, _ in
                            switch state {
                            case .complete: done(.success(()))
                            case .invalid: done(.failure(BandError.unsupported("HRV history")))
                            default: break
                            }
                        }
                    }
                    } catch {
                        if let error = error as? BandError, case .unsupported = error { hrvStatus = .unsupported }
                        else { hrvStatus = .failed }
                        BandLog.shared.record("readHRV", error: error)
                    }
                }
                if [2, 4].contains(model.temperatureType) {
                    do { try await self.sdk("readTemperature", seconds: 300) { (done: @escaping (Result<Void, Error>) -> Void) in
                        peripheral.veepooSdkStartReadDeviceTemperatureData { state, _, _, _ in
                            switch state {
                            case .complete: done(.success(()))
                            case .invalid: done(.failure(BandError.unsupported("temperature history")))
                            default: break
                            }
                        }
                    }
                    } catch {
                        if let error = error as? BandError, case .unsupported = error { temperatureStatus = .unsupported }
                        else { temperatureStatus = .failed }
                        BandLog.shared.record("readTemperature", error: error)
                    }
                }
                if model.oxygenType != 0 {
                    do { try await self.sdk("readOxygen", seconds: 300) { (done: @escaping (Result<Void, Error>) -> Void) in
                        peripheral.veepooSdkStartReadDeviceOxygenData { state, _, _, _ in
                            switch state {
                            case .complete: done(.success(()))
                            case .invalid: done(.failure(BandError.unsupported("oxygen history")))
                            default: break
                            }
                        }
                    }
                    } catch {
                        if let error = error as? BandError, case .unsupported = error { oxygenStatus = .unsupported }
                        else { oxygenStatus = .failed }
                        BandLog.shared.record("readOxygen", error: error)
                    }
                }
                if hrvStatus != .failed && temperatureStatus != .failed && oxygenStatus != .failed {
                    self.auxiliaryDataReadAt = Date()
                }
            }
            let date = Self.dayString(daysAgo: dayOffset)
            let resolvedHrvStatus = hrvStatus
            let resolvedTemperatureStatus = temperatureStatus
            let resolvedOxygenStatus = oxygenStatus
            let resolvedOpticalStatus = opticalStatus
            return await MainActor.run {
                let temperatures = ((VPDataBaseOperation
                    .veepooSDKGetDeviceTemperatureData(withDate: date, andTableID: address)
                    as? [[String: Any]]) ?? []).compactMap(HealthSampleMapping.temperature)
                let hrv = ((VPDataBaseOperation
                    .veepooSDKGetDeviceHrvData(withDate: date, andTableID: address)
                    as? [[String: Any]]) ?? []).compactMap(HealthSampleMapping.hrv)
                let rawOxygen = (VPDataBaseOperation
                    .veepooSDKGetDeviceOxygenData(withDate: date, andTableID: address)
                    as? [[String: Any]]) ?? []
                let oxygen = rawOxygen.compactMap(HealthSampleMapping.oxygen)
                // Both public SDK getters discard respiratory fields for this device. Read
                // only the bound device/day's archived respiratory minutes, without changing
                // the SDK database or exposing its other health fields.
                let respiration: [RespirationSample]
                let respirationStatus: BandDomainReadStatus
                do {
                    let archiveURL = try FileManager.default.url(for: .documentDirectory,
                        in: .userDomainMask, appropriateFor: nil, create: false)
                        .appendingPathComponent("wypDataBase.sqlite")
                    let archived = try SDKRespirationArchive.read(url: archiveURL, deviceAddress: address, day: date)
                    respiration = archived.map { RespirationSample(time: $0.time, breathsPerMinute: $0.rate) }
                    respirationStatus = respiration.isEmpty ? .notCollected : .complete
                } catch {
                    respiration = []
                    respirationStatus = .failed
                    BandLog.shared.record("read SDK respiration archive", error: error)
                }
                let rawOptical = (VPDataBaseOperation
                    .veepooSDKGetDeviceBloodGlucoseData(withDate: date, andTableID: address)
                    as? [[String: Any]]) ?? []
                let optical = rawOptical.compactMap(HealthSampleMapping.opticalResponse)
                let droppedZeros = max(0, rawOptical.count - optical.count)
                // Which hours the band actually sampled HRV in, and how many RR intervals a
                // minute carries: the shape of the domain, not its values.
                // The SDK pads every minute of the day; only minutes that carry RR intervals
                // or a vendor scalar are measurements.
                let measured = hrv.filter { $0.rrCount > 0 || ($0.vendorValue ?? 0) > 0 }
                let perHour = Dictionary(grouping: measured) { String($0.time.prefix(2)) }
                    .map { "\($0.key):\($0.value.count)" }.sorted().joined(separator: " ")
                let withRR = hrv.filter { $0.rmssdMS != nil }.count
                let withVendor = hrv.filter { ($0.vendorValue ?? 0) > 0 }.count
                let rr = measured.map(\.rrCount)
                let sample = measured.prefix(3).map { "\($0.time) rr\($0.rrCount) v\(Int($0.vendorValue ?? 0)) rmssd\(Int($0.rmssdMS ?? 0))" }.joined(separator: "; ")
                Self.log.notice("readHealthData(\(dayOffset)) \(date, privacy: .public) · hrv \(hrv.count) minute(s) padded, \(measured.count) measured, \(withRR) with ≥2 RR, \(withVendor) with vendor value · rr/min \(rr.min() ?? 0)–\(rr.max() ?? 0) · measured by hour [\(perHour, privacy: .public)] · e.g. \(sample, privacy: .public) · temp \(temperatures.count) · spo2 \(oxygen.count) · optical \(optical.count)")
                return BandHealthData(temperatures: temperatures, hrv: hrv, oxygen: oxygen,
                                      optical: optical, opticalDroppedZeros: droppedZeros,
                                      temperatureStatus: resolvedTemperatureStatus,
                                      hrvStatus: resolvedHrvStatus,
                                      oxygenStatus: resolvedOxygenStatus,
                                      opticalStatus: resolvedOpticalStatus,
                                      respiration: respiration,
                                      respirationStatus: respirationStatus)
            }
        }
    }

    /// The sleep that ends on the calendar day `dayOffset` back. The SDK files a
    /// record under one calendar date and does not say which end of the night it picks, so
    /// both candidate dates are read and the records are kept by their wake time instead.
    ///
    /// ⚠️ Two sleep stores. `VPPeripheralModel.sleepType` 0 (and 2, per the vendor demo) is
    /// 「普通睡眠」 and fills the dictionary table; 1/3 is 「精准睡眠」 and fills only the
    /// `VPAccurateSleepModel` table. The HOOP is the latter: reading the dictionary table
    /// alone answered "no night" on every sync and `sleep_nights` never got a row. The accurate
    /// table is asked first, the dictionary table second, whichever the model claims — the
    /// claim is logged, never trusted on its own.
    func readSleep(dayOffset: Int) async throws -> SleepNight? {
        guard peripheral != nil, let model = central.peripheralModel,
              let address = model.deviceAddress else {
            throw BandError.notConnected
        }
        let sleepType = model.sleepType
        return try await queue.run("readSleep(\(dayOffset))", priority: .p2) {
            try await self.readAllDataIfStale()
            let morning = Self.dayString(daysAgo: dayOffset)
            let dates = [morning, Self.dayString(daysAgo: dayOffset + 1)]

            func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) ?? 0 }

            let (accurate, accurateTotal, records) = await MainActor.run {
                () -> ([VPAccurateSleepModel], Int, [[String: Any]]) in
                let accurate = dates.flatMap {
                    VPDataBaseOperation.veepooSDKGetAccurateSleepData(withDate: $0, andTableID: address) ?? []
                }
                let records = dates.flatMap { date in
                    (VPDataBaseOperation.veepooSDKGetSleepData(withDate: date, andTableID: address)
                        as? [[String: Any]]) ?? []
                }
                return (accurate, accurate.count, records)
            }

            let accurateNight = HealthSampleMapping.sleepRecordIndices(
                stamps: accurate.map { ($0.sleepTime, $0.wakeTime) }, wakeDay: morning
            ).map { accurate[$0] }
            if !accurateNight.isEmpty {
                let result = Self.summarizeSleep(Self.sleepRecords(accurateNight))
                Self.log.notice("readSleep(\(dayOffset)) \(morning, privacy: .public) · accurate (sleepType \(sleepType)) · \(result?.totalMinutes ?? 0) min in \(accurateNight.count) segment(s) · line \(result?.line.count ?? 0) runs")
                return result
            }

            let night = HealthSampleMapping.sleepRecordIndices(
                stamps: records.map { ($0["SLEEP_TIME"] as? String, $0["WAKE_TIME"] as? String) },
                wakeDay: morning
            ).map { records[$0] }
            guard !night.isEmpty else {
                let stamps = (accurate.compactMap(\.wakeTime) + records.compactMap { $0["WAKE_TIME"] as? String })
                    .joined(separator: ",")
                Self.log.notice("readSleep(\(dayOffset)) \(morning, privacy: .public) · no night · sleepType \(sleepType) · accurate \(accurateTotal) record(s), plain \(records.count) · wake times [\(stamps, privacy: .public)]")
                return nil
            }
            let plain = night.compactMap { row -> SleepRecord? in
                guard let start = Self.instant(row["SLEEP_TIME"] as? String),
                      let end = Self.instant(row["WAKE_TIME"] as? String), start < end else { return nil }
                let deep = Int(num(row["DEEP_HOUR"]) * 60)
                let light = Int(num(row["LIGHT_HOUR"]) * 60)
                let total = Int(num(row["SLE_HOUR"]) * 60 + num(row["SLE_MINUTE"]))
                return SleepRecord(start: start, end: end, total: total > 0 ? total : deep + light,
                                   deep: deep, light: light, wakes: Int(num(row["WakeUpTime"])), stages: [])
            }
            let result = Self.summarizeSleep(plain)
            Self.log.notice("readSleep(\(dayOffset)) \(morning, privacy: .public) · plain (sleepType \(sleepType)) · \(result?.totalMinutes ?? 0) min in \(night.count) segment(s)")
            return result
        }
    }

    private struct SleepRecord {
        let start: Date
        let end: Date
        let total: Int
        let deep: Int
        let light: Int
        let wakes: Int
        /// nil retains the minute occupied by an unknown SDK stage.
        let stages: [Int?]
    }

    private static func sleepRecords(_ models: [VPAccurateSleepModel]) -> [SleepRecord] {
        func number(_ value: Any?) -> Int {
            Int((value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init) ?? 0)
        }
        return models.compactMap { model in
            guard let start = instant(model.sleepTime), let end = instant(model.wakeTime), start < end else { return nil }
            let deep = number(model.deepDuration), light = number(model.lightDuration)
            let total = number(model.sleepDuration)
            let stages = (model.parseSleepLine() ?? []).map { point -> Int? in
                let stage = (point["type"] as? NSNumber)?.intValue ?? (point["type"] as? String).flatMap(Int.init)
                return stage.flatMap { (0...4).contains($0) ? $0 : nil }
            }
            return SleepRecord(start: start, end: end,
                               total: total > 0 ? total : deep + light + number(model.otherDuration),
                               deep: deep, light: light, wakes: number(model.getUpTimes), stages: stages)
        }
    }

    /// Prefer complete records to duplicate/contained fragments before counting.
    private static func distinctSleep(_ records: [SleepRecord]) -> [SleepRecord] {
        let sorted = records.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end > $1.end }
            return $0.stages.compactMap { $0 }.count > $1.stages.compactMap { $0 }.count
        }
        return sorted.enumerated().filter { index, record in
            !sorted.prefix(index).contains { $0.start <= record.start && $0.end >= record.end }
        }.map(\.element)
    }

    private static func sleepIntervals(_ records: [SleepRecord]) -> [SleepInterval] {
        var intervals: [SleepInterval] = []
        for record in records {
            if let last = intervals.last, record.start <= last.end {
                intervals[intervals.count - 1] = SleepInterval(start: last.start, end: max(last.end, record.end))
            } else {
                intervals.append(SleepInterval(start: record.start, end: record.end))
            }
        }
        return intervals
    }

    /// One entry per real minute. Earlier complete records win overlapping conflicts;
    /// unknown stages occupy time but never create a fabricated sleep stage.
    private static func sleepMinutes(_ records: [SleepRecord]) -> [Date: Int] {
        var minutes: [Date: Int] = [:]
        for record in records {
            for (offset, stage) in record.stages.enumerated() {
                let at = record.start.addingTimeInterval(Double(offset) * 60)
                guard at < record.end, let stage, minutes[at] == nil else { continue }
                minutes[at] = stage
            }
        }
        return minutes
    }

    private static func stageRuns(_ minutes: [Date: Int], start: Date) -> [SleepStageRun] {
        var result: [SleepStageRun] = []
        for at in minutes.keys.sorted() {
            guard let stage = minutes[at] else { continue }
            let offset = Int(at.timeIntervalSince(start) / 60)
            if let last = result.last, last.stage == stage,
               (last.offsetMinutes ?? 0) + last.minutes == offset {
                result[result.count - 1] = SleepStageRun(stage: stage, minutes: last.minutes + 1,
                                                        offsetMinutes: last.offsetMinutes)
            } else {
                result.append(SleepStageRun(stage: stage, minutes: 1, offsetMinutes: offset))
            }
        }
        return result
    }

    private static func summarizeSleep(_ source: [SleepRecord]) -> SleepNight? {
        let records = distinctSleep(source)
        let intervals = sleepIntervals(records)
        guard let start = intervals.first?.start, let end = intervals.last?.end else { return nil }
        let minutes = sleepMinutes(records)
        let line = stageRuns(minutes, start: start)
        let duration = intervals.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        let individualDuration = records.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        let overlaps = duration < individualDuration
        // Disjoint records retain vendor totals (including the single-record 550-minute
        // convention). Overlaps cannot add their aggregate totals a second time.
        let total = overlaps ? duration : records.reduce(0) { $0 + $1.total }
        let deep = overlaps ? minutes.values.filter { $0 == 0 }.count : records.reduce(0) { $0 + $1.deep }
        let light = overlaps ? minutes.values.filter { $0 == 1 }.count : records.reduce(0) { $0 + $1.light }
        let wakes = overlaps ? line.filter { $0.stage == 3 || $0.stage == 4 }.count : records.reduce(0) { $0 + $1.wakes }
        return SleepNight(totalMinutes: total, deepMinutes: deep, lightMinutes: light, wakeCount: wakes,
                          line: line, sleepStart: start, wakeAt: end, intervals: intervals)
    }

    /// Stage ids: 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake. Gaps keep real offsets.
    private static func runs(from night: [VPAccurateSleepModel]) -> [SleepStageRun] {
        summarizeSleep(sleepRecords(night))?.line ?? []
    }

    /// 04B rule 04 · the night's own sleepLine, one run per stage stretch, in the order the
    /// night ran. The accurate models answer from the same local store, are queried under both
    /// candidate dates like the dictionary records above, and are matched by the same
    /// wake-date rule; a night without a curve answers empty and the strip falls back to
    /// the totals.
    private static func sleepLine(morning: String, address: String, dates: [String]) -> [SleepStageRun] {
        let records = dates.flatMap {
            VPDataBaseOperation.veepooSDKGetAccurateSleepData(withDate: $0, andTableID: address) ?? []
        }
        let night = HealthSampleMapping.sleepRecordIndices(
            stamps: records.map { ($0.sleepTime, $0.wakeTime) }, wakeDay: morning
        ).map { records[$0] }
        return runs(from: night)
    }

    /// "2017/02/09 07:45", the SDK's sleep stamp, read in the phone's own zone.
    private static func instant(_ stamp: String?) -> Date? {
        HealthSampleMapping.sleepInstant(stamp)
    }

    /// "yyyy-MM-dd" in the phone's calendar, the SDK's query key (「格式为2017-02-09」).
    private static func dayString(daysAgo: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return f.string(from: day)
    }

    /// One five-minute slot of VPDataBaseOperation's original-data dictionary. Values arrive
    /// as NSNumber or as strings depending on the SDK build, so both are read.
    private static func point(time: String, _ raw: [String: Any]) -> OriginPoint {
        func num(_ v: Any?) -> Double? {
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String { return Double(s) }
            return nil
        }
        func int(_ v: Any?) -> Int? { num(v).map { Int($0) } }
        // VPDataBaseOperation.h: 「如果有heartValue用heartValue, 如果没有则优先使用ppgs, 如果
        // heartValue和ppgs都没有就用ecgs」. On the HOOP heartValue is 0 on every slot and the
        // slot's beats sit in `ppgs`, one array per five minutes; the slot's heart rate is
        // their mean. ⚠️ 0 is the band's "nothing on the wrist", not a reading. It is
        // dropped here at the bridge, or the readout would print HR 0 and HR_REST's lowest
        // decile would be all zeros. Steps and distance keep their zeros: a still hour is a fact.
        func beats(_ key: String) -> Int? {
            let v = (raw[key] as? [Any] ?? []).compactMap(num).filter { $0 > 0 }
            return v.isEmpty ? nil : Int((v.reduce(0, +) / Double(v.count)).rounded())
        }
        let heart = int(raw["heartValue"]).flatMap { $0 > 0 ? $0 : nil } ?? beats("ppgs") ?? beats("ecgs")
        return OriginPoint(
            time: time,
            heart: heart,
            step: int(raw["stepValue"]),
            // ⚠️ calValue is never used for E_ACTIVE: it already contains the vendor's own
            // basal figure, and adding it to our BMR double-counts. It is stored, not summed.
            cal: int(raw["calValue"]),
            distance: HealthSampleMapping.distanceMeters(from: raw["disValue"]),
            met: num(raw["met"]),
            temperature: num(raw["temperature"] ?? raw["tempValue"]).flatMap { $0 > 0 ? $0 : nil },
            // The original-data dictionary has no HRV key; it is its own history domain,
            // read by its own command and joined on in OriginDataSync.
            hrv: nil,
            stress: int(raw["stress"] ?? raw["stressValue"]).flatMap { $0 > 0 ? $0 : nil },
            sleepState: int(raw["sleepStatus"] ?? raw["sleepState"]))
    }

    // MARK: measurement

    func measureHeartRate() -> AsyncThrowingStream<MeasurementProgress, Error> {
        AsyncThrowingStream { c in
            guard let peripheral else { c.finish(throwing: BandError.notConnected); return }
            c.yield(.waitingForContact)
            // Tracks whether this stream still owns the SDK slot. Assigned on the main
            // queue with the start; a cancel that arrives before then flips `dead` so we
            // never leave a heart test running with no listener.
            final class Slot: @unchecked Sendable {
                var generation = 0
                var dead = false
                var started = false
            }
            let slot = Slot()
            // F1 rule 05 · stop before the screen goes. Only this generation may stop:
            // LiveReadout's cancelled stream otherwise ends Battery Check with an empty
            // result block, and the screen stays on 「Still nothing on the key」.
            c.onTermination = { [weak self] _ in
                DispatchQueue.main.async {
                    slot.dead = true
                    guard let self, slot.generation != 0,
                          self.heartTestGeneration == slot.generation else { return }
                    peripheral.veepooSDKTestHeartStart(false, testResult: { _, _ in })
                }
            }
            DispatchQueue.main.async {
                guard !slot.dead else { return }
                self.heartTestGeneration += 1
                slot.generation = self.heartTestGeneration
                let gen = slot.generation
                Self.log.notice("heart test start gen \(gen)")
                // Clear any leftover LiveReadout test, then install our block. The stop's
                // empty callback is replaced on the next line — same main-queue turn.
                peripheral.veepooSDKTestHeartStart(false, testResult: { _, _ in })
                guard !slot.dead, self.heartTestGeneration == gen else { return }
                peripheral.veepooSDKTestHeartStart(true, testResult: { [weak self] testState, value in
                    guard self?.heartTestGeneration == gen else { return }
                    Self.log.debug("heart state \(testState.rawValue)")
                    switch testState {
                    case .start:
                        // VPTestHeartStateStart ·「开始检测心率，还没有测出结果」— the band's own
                        // answer that the sensor is on. ⚠️ It used to fall into `default: break`,
                        // and this HOOP can take ten seconds to produce a first rate: the screen
                        // sat on 「waiting for your finger」, then went amber, for a measurement
                        // that had already begun. This is the band answering, not the echo of our
                        // own `start` — that distinction is what the judgement was ever about.
                        if !slot.started { slot.started = true; c.yield(.contact) }
                    case .testing:
                        if !slot.started { slot.started = true; c.yield(.contact) }
                        // ⚠️ No progress fraction. The SDK only reports a rate — inventing
                        // 0.5 here used to pin Battery Check's countdown at 30 forever,
                        // because every callback rewrote `remaining` from that fake half.
                        // The phone's clock owns the minute; partial carries the beat.
                        let beat = Int(value)
                        c.yield(.measuring(fraction: 0,
                                           partial: beat > 0 ? PartialReading(heartRate: beat) : nil))
                    case .over:
                        // 「测试正常结束，人为结束」· the test ending, which is not the same thing
                        // as a reading. A zero here is the band saying it never got one, and a
                        // stored 0 bpm is a number nobody measured.
                        if value > 0 {
                            c.yield(.finished(.heartRate(hr: Int(value), hrv: nil, stress: nil)))
                        } else {
                            c.yield(.failed(reason: "NO READING"))
                        }
                        c.finish()
                    case .notWear:
                        // 「佩戴检测没有通过，测试已经结束」— the test is dead. Yield the
                        // lift, then finish so Battery Check can reopen after the 3 s grace
                        // instead of hanging forever on a stream that will never speak again.
                        c.yield(.lostContact)
                        c.finish()
                    case .deviceBusy:
                        c.finish(throwing: BandError.busy)
                    @unknown default:
                        break
                    }
                })
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
            Self.log.notice("body scan start")
            // F1 rule 05 · see measureHeartRate. A body scan left running is worse: it holds
            // the electrodes and the queue for the full thirty seconds.
            c.onTermination = { _ in
                Self.log.notice("body scan stop")
                DispatchQueue.main.async {
                    peripheral.veepooSDKTestBodyCompositionStart(false, progress: { _, _ in }, testResult: { _, _ in })
                }
            }
            var hadContact = false
            DispatchQueue.main.async {
            peripheral.veepooSDKTestBodyCompositionStart(true, progress: { lead, progress in
                let done = progress?.completedUnitCount ?? 0
                let total = progress?.totalUnitCount ?? 0
                Self.log.notice("body scan lead \(lead) progress \(done)/\(total)")
                // lead == 0 means the hand is on the electrode — but the SDK's first callback
                // says lead 0 at progress 0 before any finger is there (device log: 93 ms after
                // start). The circuit is closed when the band's own count advances, so contact
                // is that, never the echo of the start command.
                let fraction = progress?.fractionCompleted ?? 0
                if lead == 0, done > 0 {
                    if !hadContact { hadContact = true; c.yield(.contact) }
                    // The countdown is the band's, not the phone's. The SDK's NSProgress
                    // counts the scan's own seconds when its total is in that range;
                    // otherwise its fraction is laid over the nominal thirty.
                    let left: Int = (25...40).contains(total) ? Int(total - done)
                                                              : Int(((1 - fraction) * 30).rounded())
                    c.yield(.measuring(fraction: fraction, partial: nil, secondsLeft: max(0, left)))
                } else if lead != 0, hadContact {
                    // ⚠️ Body composition has no resume: lifting off restarts the 30 seconds.
                    hadContact = false
                    c.yield(.lostContact)
                }
            }, testResult: { state, model in
                Self.log.notice("body scan result state \(state.rawValue)")
                guard state == .complete, let model else {
                    c.yield(.failed(reason: state == .deviceBusy ? "DEVICE BUSY"
                                          : state == .lowPower ? "BAND BATTERY LOW"
                                          : state == .noFunction ? "NO BODY SCAN ON THIS BAND"
                                          : "SCAN DID NOT COMPLETE"))
                    c.finish(); return
                }
                // ⚠️ Every VPBodyCompositionValueModel field is an NSString, so each is
                // parsed to a number here (nil when the firmware sent an empty string).
                func num(_ s: String?) -> Double? { guard let s, let v = Double(s) else { return nil }; return v }
                var reading = BodyCompositionReading(
                    bodyFatPercent: num(model.bodyFatPercentage) ?? 0,
                    fatMassKg: num(model.fatMass) ?? 0,
                    leanMassKg: num(model.leanBodyMass) ?? 0,
                    muscleKg: num(model.muscleMass),
                    boneKg: num(model.boneMass),
                    // bodyMoisture is the percentage; waterContent is kilograms.
                    bodyWaterPercent: num(model.bodyMoisture),
                    proteinPercent: num(model.proportionOfProtein),
                    subcutaneousFatPercent: num(model.subcutaneousFat),
                    skeletalMusclePercent: num(model.skeletalMuscleRate),
                    // ⚠️ The BIA's own basalMetabolicRate is a MEASURED reference only.
                    // It never enters the budget — Mifflin does. Electrode contact can move
                    // it by tens of kcal, and a budget that shifts with grip is unfindable.
                    bmrKcal: num(model.basalMetabolicRate).map { Int($0) },
                    bmi: num(model.bmi),
                    inputWeightKg: weight)
                reading.muscleRatePercent = num(model.muscleRate)
                reading.waterKg = num(model.waterContent)
                reading.proteinKg = num(model.proteinAmount)
                c.yield(.finished(.bodyComposition(reading)))
                c.finish()
            })
            }
        }
    }

    /// 04 · the band's own stress test. Unlike heart rate it is a one-shot: the SDK reports
    /// progress while it runs and a single value at the end, so only `complete` is a
    /// reading — `over` is the test ending because we told it to, and carries nothing.
    ///
    /// ⚠️ Not on the queue, exactly like the two measurement streams above: it is opened
    /// directly, and `LiveReadout` is what keeps it from overlapping a day pull.
    func measureStress(progress: @escaping @MainActor (Int) -> Void) async throws -> Int {
        guard let peripheral else { throw BandError.notConnected }
        let reply = await BandMeasurementReply<Int>()
        do {
            // The measured test is ~19 seconds; 90 seconds remains the firmware ceiling.
            // Cancellation owns the continuation too, so disconnect never waits that ceiling.
            return try await reply.wait(seconds: 90, start: { done in
                peripheral.veepooSDK_stressTestStart(true) { state, doneProgress, stress in
                    Task { @MainActor in
                        guard reply.isPending else { return }
                        Self.log.notice("stress state \(state.rawValue) progress \(doneProgress)")
                        progress(doneProgress)
                        switch state {
                        case .complete:
                            // This firmware reports complete with zero during progress.
                            guard stress > 0 else { return }
                            done(.success(Int(stress)))
                        case .noFunction: done(.failure(BandError.unsupported("STRESS")))
                        case .deviceBusy: done(.failure(BandError.busy))
                        case .lowPower: done(.failure(BandError.rejected("BAND BATTERY LOW")))
                        case .notWear: done(.failure(BandError.rejected("NOT ON THE WRIST")))
                        default: break
                        }
                    }
                }
            }, stop: {
                // Executed on main, exactly once and BEFORE the old waiter is released.
                // No trailing queued stop can reach a new heart/stress session.
                peripheral.veepooSDK_stressTestStart(false, result: { _, _, _ in })
            })
        } catch is BandMeasurementReply<Int>.Timeout {
            throw BandError.timeout("stressTest")
        }
    }

    /// 06 · Battery Check's HRV leg. Demo holds ~60 s then stops; we take the first
    /// positive value, or time out with no reading rather than inventing one.
    func measureHRV(timeout: TimeInterval) async throws -> Int {
        guard let peripheral else { throw BandError.notConnected }
        let stop = { DispatchQueue.main.async { peripheral.veepooSDK_HRVTest(false, callBack: { _, _, _ in }) } }
        return try await withTaskCancellationHandler {
            try await sdk("hrvTest", seconds: timeout) { done in
                peripheral.veepooSDK_HRVTest(true) { con, ack, hrvValue in
                    Self.log.notice("hrv con \(con) ack \(ack.rawValue) value \(hrvValue)")
                    switch ack {
                    case .testing:
                        guard hrvValue > 0 else { break }
                        stop()
                        done(.success(Int(hrvValue)))
                    case .alreadyStarted, .deviceBusy:
                        done(.failure(BandError.busy))
                    case .lowPower:
                        done(.failure(BandError.rejected("BAND BATTERY LOW")))
                    case .notWear:
                        done(.failure(BandError.rejected("NOT ON THE WRIST")))
                    @unknown default:
                        break
                    }
                }
            }
        } onCancel: {
            stop()
        }
    }

    // MARK: settings

    // MARK: firmware

    /// VPDFUOperation asks Veepoo's update server about the connected band and, when there is
    /// a newer build, downloads it into the SDK's own cache — so the check is also the
    /// download, and can take a while on a slow link. An empty `newVersion` is "up to date".
    /// Nothing here touches the band.
    func checkFirmwareUpdate() async throws -> FirmwareOffer? {
        guard central.peripheralModel != nil else { throw BandError.notConnected }
        // DEBUG · `NB_DEBUG_EDGE=otatest` asks Veepoo's test server instead. ⚠️ Never in a
        // release build: the header says so, and a test build on the band is not a product.
        let testServer = DebugEdge.on("otatest")
        return try await sdk("checkOTA", seconds: 180) { done in
            let progress: (Progress?) -> Void = { p in
                Self.log.notice("ota download \(Int((p?.fractionCompleted ?? 0) * 100)) %")
            }
            let completion: (String?, String?, Error?) -> Void = { newVersion, des, error in
                if let error { done(.failure(error)); return }
                Self.log.notice("ota server: version \(newVersion ?? "none", privacy: .public) · \(des ?? "", privacy: .public)")
                guard let newVersion, !newVersion.isEmpty else { done(.success(nil)); return }
                // The server joins its notes with "$".
                let notes = (des ?? "").split(separator: "$")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                done(.success(FirmwareOffer(version: newVersion, notes: notes)))
            }
            if testServer {
                VPDFUOperation.dfuOperationShare().checkDeviceOTAInfo(withDebug: true, downloadProgress: progress, completionHandler: completion)
            } else {
                VPDFUOperation.dfuOperationShare().checkDeviceOTAInfo(downloadProgress: progress, completionHandler: completion)
            }
        }
    }

    /// 12 rule 08 · the DFU pushes the file `checkFirmwareUpdate` fetched. The SDK reports
    /// start / updating / success / failure, and on the K series a reboot after success — so
    /// "success" is only "the file crossed": the band drops the link, comes back, and the
    /// version it then reports is the only proof. Not reading it back is `versionUnverified`.
    func updateFirmware(to version: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FirmwareUpdateResult {
        guard central.peripheralModel != nil else { throw BandError.notConnected }
        let before = central.peripheralModel?.deviceVersion ?? "—"
        Self.log.notice("dfu start \(before, privacy: .public) → \(version, privacy: .public)")
        let outcome: DeviceDFUState = try await sdk("dfu", seconds: 600) { done in
            VPDFUOperation.dfuOperationShare().veepooSDKStartDfu { p, state in
                // The SDK's number has been seen both as 0…1 and 0…100; either way it is a
                // fraction on screen.
                progress(min(max(p > 1 ? p / 100 : p, 0), 1))
                Self.log.notice("dfu \(state.rawValue) \(Int(p))")
                switch state {
                case .success, .failure, .fileNotExist: done(.success(state))
                case .start, .updating, .prepared, .reboot: break
                @unknown default: break
                }
            }
        }
        switch outcome {
        case .fileNotExist:
            return .failed(reason: "No firmware file on this phone — check for the update again")
        case .failure:
            return .failed(reason: "The band rejected the update — it is still on \(before)")
        default:
            break
        }
        // The band reboots on the new build and the link goes with it. Wait for it to come
        // back — the SDK reconnects on its own when it sees the band, and if it does not, the
        // app's own reconnect scans for it — then read the version it now reports.
        var waited = 0
        while state != .connected, waited < 300 {
            try? await Task.sleep(for: .milliseconds(100)); waited += 1
            if waited == 100, state != .connected { await reconnectIfBound() }
        }
        guard state == .connected, let after = central.peripheralModel?.deviceVersion, !after.isEmpty else {
            Self.log.error("dfu done but the band did not come back to say its version")
            return .versionUnverified
        }
        Self.log.notice("dfu done, band reports \(after, privacy: .public)")
        return after == before ? .versionUnverified : .completed(version: after)
    }

    func writeSetting(_ setting: BandSetting) async throws -> BandSetting {
        guard let peripheral else { throw BandError.notConnected }
        // F3 · the switch renders the value that came back. Optimistic UI here means the
        // firmware wins a second later and the toggle flips under the user's finger.
        return try await queue.run("writeSetting", priority: .p0) {
            switch setting {
            case .heartRateAlarm(let on, let low, let high):
                let model = VPDeviceHeartAlarmModel()
                model.isOpen = on
                model.heartMaxValue = UInt(high)
                model.heartMinValue = UInt(low)
                return try await self.sdk("writeSetting.heartRateAlarm") { done in
                    peripheral.veepooSDKSettingDeviceHeartAlarm(with: model, settingMode: 1) { back in
                        done(.success(.heartRateAlarm(
                            on: back?.isOpen ?? on,
                            low: Int(back?.heartMinValue ?? UInt(low)),
                            high: Int(back?.heartMaxValue ?? UInt(high)))))
                    } failureResult: {
                        done(.failure(BandError.rejected("HEART RATE ALARM REFUSED")))
                    }
                }
            }
        }
    }

    /// 06 · the pulse study. The SDK command is its single-lead start — the only path to
    /// beat-to-beat timing on this hardware — and the waveform it streams is deliberately
    /// dropped on the floor here rather than carried up. See `measurePulseStudy`.
    func measurePulseStudy() -> AsyncThrowingStream<PulseStudyStep, Error> {
        AsyncThrowingStream { c in
            guard let peripheral else { c.finish(throwing: BandError.notConnected); return }
            c.yield(.waitingForContact)
            // F1 rule 05 · stop before the screen goes, however it goes.
            c.onTermination = { _ in
                DispatchQueue.main.async { peripheral.veepooSDKTestECGStart(false, testResult: { _, _, _ in }) }
            }
            var contacted = false
            DispatchQueue.main.async {
                // ⚠️ Logged on the way OUT, not only when something comes back. A screen stuck on
                // 「Still nothing on the key」 with no line here is a command that never left the
                // phone; with this line and nothing after it, it is a band that never answered.
                // Those are two different bugs and the log used to make them look the same.
                Self.log.notice("pulseStudy → start")
                // ⚠️ NO stop before the start, unlike the heart test. The one run that sent
                // `veepooSDKTestECGStart(false)` immediately before `(true)` ran its full forty
                // seconds, reported complete, and came back with every array empty — hearts,
                // rrs, muHearts, all zero. The probe that never sent the stop came back with
                // forty-one of each. Whether the SDK empties its accumulator on stop and the
                // start inherits the empty one, or whether that run's finger was simply not
                // making contact, the proven sequence is the bare start, so that is the one used.
                peripheral.veepooSDKTestECGStart(true) { state, progress, model in
                    // Every callback, and what is in the model: the running rate the SDK says
                    // to display, the lead flag, how many beats it has, and how many signal
                    // samples have arrived — COUNTS only, the samples themselves are never read.
                    // Nothing else separates "no finger on the key" from "the band sent nothing".
                    Self.log.notice("pulseStudy ← state \(state.rawValue) progress \(progress) · heart \(model?.aveHeart ?? "-", privacy: .public) lead \(model?.lead ?? "-", privacy: .public) · beats \(Self.numbers(model?.muHearts).count) · signal \((model?.filterSignals as? NSArray)?.count ?? -1)")
                    switch state {
                    case .start:
                        // 「开始检测ECG，还没有测出结果」· the band's own answer that the test is
                        // running. The heart test's ruling applies: this is the band speaking,
                        // not the echo of our start, and a screen that keeps saying 「nothing on
                        // the key」 over it is wrong about a measurement that has begun.
                        if !contacted { contacted = true; c.yield(.contact) }
                    case .testing:
                        if !contacted { contacted = true; c.yield(.contact) }
                        // ⚠️ muHearts is an NSMutableArray: bridge before reaching for the
                        // last value, which is the one the SDK says to display right now.
                        let live = Self.numbers(model?.muHearts).last.map { Int($0) }
                        c.yield(.measuring(percent: Int(progress),
                                           heartRate: live.flatMap { $0 > 0 ? $0 : nil }))
                    case .notLead:
                        c.yield(.lostContact)
                    case .complete:
                        // ⚠️ Only a model is the end. A terminal state on its own is what the
                        // stress test taught: `complete` arrives with nothing in it too.
                        guard let model else { break }
                        c.yield(.finished(Self.study(from: model)))
                        c.finish()
                    case .deviceBusy:
                        c.finish(throwing: BandError.busy)
                    case .noFunction:
                        c.finish(throwing: BandError.unsupported("PULSE STUDY"))
                    case .failure:
                        c.yield(.failed(reason: "NO READING"))
                        c.finish()
                    // `over` is our own stop coming back.
                    default:
                        break
                    }
                }
            }
        }
    }

    /// The finished model, reduced to the interval series and the rate. The waveform arrays
    /// are not read at all — not converted, not copied, not carried.
    private static func study(from m: VPECGTestDataModel) -> PulseStudy {
        func int(_ s: String?) -> Int? { s.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }
        let nums = Self.numbers

        let rrs = nums(m.rrs), muRrs = nums(m.muRrs)
        let hearts = nums(m.hearts), muHearts = nums(m.muHearts)
        // ⚠️ The header calls `rrs` 「App手动测试每秒的rr值」 and says nothing about its unit.
        // Forty-one of them came back on a real HOOP and every one was thrown away by the
        // physiological filter downstream, which is how a finished measurement turned into
        // 「没读够」. Whatever they are, they are printed raw here before anything judges them.
        log.notice("pulse study raw · rrs \(rrs.prefix(8).map { String(format: "%.1f", $0) }.joined(separator: ","), privacy: .public) (\(rrs.count))")
        log.notice("pulse study raw · muRrs \(muRrs.prefix(8).map { String(format: "%.1f", $0) }.joined(separator: ","), privacy: .public) (\(muRrs.count))")
        log.notice("pulse study raw · hearts \(hearts.prefix(8).map { String(format: "%.0f", $0) }.joined(separator: ","), privacy: .public) (\(hearts.count))")
        log.notice("pulse study raw · muHearts \(muHearts.prefix(8).map { String(format: "%.0f", $0) }.joined(separator: ","), privacy: .public) (\(muHearts.count))")

        let series = intervals(rrs: rrs.isEmpty ? muRrs : rrs,
                               hearts: hearts.isEmpty ? muHearts : hearts)
        log.notice("pulse study finished · \(series.values.count) interval(s) from \(series.source.rawValue, privacy: .public) · duration \(m.duration ?? "-", privacy: .public)")
        return PulseStudy(
            heartRate: int(m.aveHeart).flatMap { $0 > 0 ? $0 : nil },
            intervals: series.values,
            source: series.source,
            durationSeconds: int(m.duration),
            vendorHRV: int(m.aveHrv))
    }

    /// Every number in one of the SDK's arrays, whatever it was stored as.
    /// ⚠️ NOT `as? [NSNumber]`. This SDK keeps its numbers as strings — `aveHeart` is a
    /// String, every body-composition field is an NSString — and its arrays are no
    /// different. A run that cast them to `[NSNumber]` got nil for all four, read every
    /// interval as missing, and printed 「没读够」 over a band that had just reported 73 bpm.
    /// The probe before it only ever asked for `.count`, which is why it saw forty-one.
    static func numbers(_ array: Any?) -> [Double] {
        guard let items = array as? [Any] else { return [] }
        return items.compactMap { item in
            if let n = item as? NSNumber { return n.doubleValue }
            if let t = item as? String { return Double(t.trimmingCharacters(in: .whitespaces)) }
            return nil
        }
    }

    /// Work out what the band actually sent, rather than assuming.
    ///
    /// Three shapes have to be told apart, and only the numbers themselves can do it:
    ///  · milliseconds — a resting interval is 600–1200, so anything in the 300…2000 band is
    ///    already what this needs.
    ///  · hundredths, or any other scaling — a series whose median is 60–200 is the same
    ///    intervals in a smaller unit; multiplied back it lands in the physiological range.
    ///  · counts — a handful of beats per second, single digits. Nothing can be recovered
    ///    from those, and the per-second heart rates are used instead.
    ///
    /// ⚠️ The last of those is NOT beat-to-beat data. It is one number a second, so the fast
    /// half of the Poincaré cloud is blunted by the sampling; the result screen says where its
    /// numbers came from rather than passing it off as the real thing.
    private static func intervals(rrs: [Double], hearts: [Double]) -> (values: [Double], source: PulseStudy.Source) {
        let usable = rrs.filter { $0 > 0 }
        if usable.count >= 8 {
            let sorted = usable.sorted()
            let median = sorted[sorted.count / 2]
            if median >= 300, median <= 2000 {
                return (usable.filter { $0 >= 300 && $0 <= 2000 }, .intervals)
            }
            // A consistent scaling is recoverable; the factor is whatever brings the median
            // into the physiological band, taken from the powers of ten the SDK uses elsewhere
            // (blood glucose ×100, temperature ×10).
            for factor in [10.0, 100.0, 1000.0] where median * factor >= 300 && median * factor <= 2000 {
                let scaled = usable.map { $0 * factor }.filter { $0 >= 300 && $0 <= 2000 }
                if scaled.count >= 8 { return (scaled, .intervals) }
            }
        }
        // Per-second rates, converted to the interval each implies.
        let beats = hearts.filter { $0 >= 30 && $0 <= 220 }
        if beats.count >= 8 { return (beats.map { 60_000 / $0 }, .perSecondRates) }
        return ([], .intervals)
    }

    /// DEBUG · what the watch itself has stored. One read, thirteen kinds.
    /// ⚠️ Nothing is measured here: this is the band handing back what the user already
    /// pressed for on the watch, which is the only full set available on a firmware that
    /// ignores the app's own measurement commands.
    func readManualTestData(since: Date) async throws -> [String] {
        guard let peripheral else { throw BandError.notConnected }
        let from = UInt32(max(0, since.timeIntervalSince1970))
        return try await queue.run("readManualTestData", priority: .p1) {
            try await self.sdk("manualTestData", seconds: 20) { done in
                peripheral.readManualTestData(withTimestamp: from,
                                              dataType: VPManualTestDataType(rawValue: 0xFFFF_FFFF)) { model in
                    // ⚠️ The block's model is nullable in Swift's eyes even though the header
                    // does not say so. A firmware with nothing stored answers with nothing,
                    // and that is an empty list, not a crash and not a failure.
                    guard let model else { done(.success([])); return }
                    var lines: [String] = []
                    func stamp(_ t: UInt32) -> String {
                        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(t)))
                    }
                    for r in model.heartRateArr { lines.append("heart rate \(stamp(r.timestamp)) · \(r.heartArray)") }
                    for r in model.bloodOxygenArr { lines.append("blood oxygen \(stamp(r.timestamp)) · \(r.bloodOxygenArray)") }
                    for r in model.stressArr { lines.append("stress \(stamp(r.timestamp)) · \(r.value)") }
                    for r in model.bodyTempArr { lines.append("temperature \(stamp(r.timestamp)) · \(r.bodyTemp) skin \(r.origTemp)") }
                    for r in model.bloodPressureArr { lines.append("blood pressure \(stamp(r.timestamp))") }
                    for r in model.bloodSugarArr { lines.append("blood sugar \(stamp(r.timestamp))") }
                    for r in model.bloodCompArr { lines.append("blood components \(stamp(r.timestamp))") }
                    for r in model.hrvArr { lines.append("HRV \(stamp(r.timestamp))") }
                    for r in model.gsrArr { lines.append("skin conductance \(stamp(r.timestamp))") }
                    for r in model.emotionArr { lines.append("emotion \(stamp(r.timestamp))") }
                    for r in model.fatigueLevelArr { lines.append("fatigue \(stamp(r.timestamp))") }
                    // The one that carries a whole set at once.
                    for r in model.healthGlanceArr {
                        lines.append("health glance \(stamp(r.timestamp)) · hr \(r.heartRate) spo2 \(r.bloodOxygen) stress \(r.stress) fatigue \(r.fatigueLevel) temp \(r.bodyTemperature) skin \(r.orgTemperature) bp \(r.h_bp)/\(r.l_bp) hrv \(r.hrv) sugar \(r.bloodSugar) emotion \(r.emotionLevel) protocol \(r.protocol) support \(r.functionSupport)")
                    }
                    Self.log.notice("manual test data · \(lines.count) record(s)")
                    done(.success(lines))
                }
            }
        }
    }

    /// DEBUG · 微体检 (定制项目). A different opcode from the 公版 one; some firmware carries
    /// one, some the other, and the only way to know which is to ask.
    /// ⚠️ A real measurement on the wrist.
    func probeMicroTest(progress: @escaping @MainActor (Int) -> Void) async throws -> [(name: String, value: Double)] {
        guard let peripheral else { throw BandError.notConnected }
        let stop = { DispatchQueue.main.async { peripheral.veepooSDKMicroTestOpenState(false, andProgress: nil, andFail: nil, andSuccess: nil, andHeartRate: nil, andPPG: nil) } }
        return try await withTaskCancellationHandler {
            do {
            return try await sdk("microTest", seconds: 180) { done in
                peripheral.veepooSDKMicroTestOpenState(true, andProgress: { p in
                    Self.log.notice("micro test progress \(p)")
                    MainActor.assumeIsolated { progress(Int(p)) }
                }, andFail: { error in
                    Self.log.error("micro test failed · \(String(describing: error), privacy: .public)")
                    done(.failure(BandError.rejected("MICRO TEST FAILED")))
                }, andSuccess: { endState, model in
                    Self.log.notice("micro test success endState \(endState) model \(model == nil ? "nil" : "yes")")
                    guard let model else { return }
                    stop()
                    done(.success([
                        ("heart rate", Double(model.heartRate)),
                        ("blood oxygen", Double(model.bloodOxygen)),
                        ("stress", Double(model.pressure)),
                        ("blood sugar", Double(model.bloodSugar)),
                        ("body temperature", Double(model.bodyTemperature)),
                        ("systolic", Double(model.systolicBloodPressure)),
                        ("diastolic", Double(model.diastolicBloodPressure)),
                        ("HRV", Double(model.hrv)),
                    ]))
                }, andHeartRate: { hr in
                    Self.log.notice("micro test heart \(hr)")
                }, andPPG: { _ in })
            }
            } catch {
                stop()
                throw error
            }
        } onCancel: {
            stop()
        }
    }

    /// DEBUG · 微体检 (公版), `veepooSDK_healthGlanceTestStart`. One measurement, one model.
    /// ⚠️ A real measurement on the wrist, holding the sensor for its whole length.
    /// ⚠️ Only `complete` WITH a model is the end. The stress test taught this the hard way:
    /// that SDK reports its terminal state on every progress callback, and resuming on the
    /// first one stopped the measurement a sixth of a second in and answered zero.
    func probeHealthGlance(progress: @escaping @MainActor (Int) -> Void) async throws -> BandHealthGlance {
        guard let peripheral else { throw BandError.notConnected }
        let stop = { DispatchQueue.main.async { peripheral.veepooSDK_healthGlanceTestStart(false, andProgress: { _ in }, andResult: { _, _ in }) } }
        return try await withTaskCancellationHandler {
            // ⚠️ Same as the stress test: stop on the way out of every path.
            do {
            // No documented length for this one — the stress test is 19 s and a body scan 30 s,
            // so three minutes is a ceiling wide enough to learn the real number from the log.
            return try await sdk("healthGlance", seconds: 180) { done in
                peripheral.veepooSDK_healthGlanceTestStart(true, andProgress: { p in
                    Self.log.notice("health glance progress \(p)")
                    MainActor.assumeIsolated { progress(Int(p)) }
                }, andResult: { state, model in
                    Self.log.notice("health glance state \(state.rawValue) model \(model == nil ? "nil" : "yes")")
                    switch state {
                    case .complete:
                        guard let model else { break }
                        stop()
                        done(.success(Self.glance(from: model)))
                    case .noFunction:   done(.failure(BandError.unsupported("HEALTH GLANCE")))
                    case .deviceBusy:   done(.failure(BandError.busy))
                    case .lowPower:     done(.failure(BandError.rejected("BAND BATTERY LOW")))
                    case .notWear:      done(.failure(BandError.rejected("NOT ON THE WRIST")))
                    case .notLead:      done(.failure(BandError.rejected("FINGER OFF THE ELECTRODE")))
                    case .failure:      done(.failure(BandError.rejected("MEASUREMENT FAILED")))
                    // `over` is our own stop coming back.
                    default:            break
                    }
                })
            }
            } catch {
                stop()
                throw error
            }
        } onCancel: {
            stop()
        }
    }

    /// Every field of the SDK's model, in its own order, zeros included.
    private static func glance(from m: VPHealthGlanceTestModel) -> BandHealthGlance {
        let values: [(name: String, value: Double)] = [
            ("heart rate", Double(m.heartRate)),
            ("blood oxygen", Double(m.bloodOxygen)),
            ("stress", Double(m.stress)),
            ("fatigue level", Double(m.fatigueLevel)),
            ("blood sugar", m.bloodSugar),
            ("blood sugar type", Double(m.bloodSugarType)),
            ("blood sugar level", Double(m.bloodSugarLevel)),
            ("body temperature", m.bodyTemperature),
            ("original temperature", m.orgTemperature),
            ("systolic", Double(m.systolicBloodPressure)),
            ("diastolic", Double(m.diastolicBloodPressure)),
            ("HRV", Double(m.hrv)),
            ("PPG BP high", Double(m.ppgBloodPressureHigh)),
            ("PPG BP low", Double(m.ppgBloodPressureLow)),
            ("cuff BP high", Double(m.cuffBloodPressureHigh)),
            ("cuff BP low", Double(m.cuffBloodPressureLow)),
            ("total cholesterol", m.totalCholesterol),
            ("triglyceride", m.triglyceride),
            ("HDL", m.highDensityLipoprotein),
            ("LDL", m.lowDensityLipoprotein),
            ("uric acid", m.uricAcid),
            ("weight", Double(m.weight)),
            ("height", Double(m.height)),
            ("age", Double(m.age)),
            ("gender", Double(m.gender)),
            ("BMI", m.bmi),
            ("body fat %", m.bodyFatPercentage),
            ("fat mass", m.fatMass),
            ("lean body mass", m.leanBodyMass),
            ("muscle rate", m.muscleRate),
            ("muscle mass", m.muscleMass),
            ("subcutaneous fat", m.subcutaneousFat),
            ("body moisture", m.bodyMoisture),
            ("water content", m.waterContent),
            ("skeletal muscle rate", m.skeletalMuscleRate),
            ("bone mass", m.boneMass),
            ("protein %", m.proportionOfProtein),
            ("protein amount", m.proteinAmount),
            ("BMR", m.basalMetabolicRate),
            ("emotion level", Double(m.emotionLevel)),
            ("skin moisture", Double(m.skinMoisture)),
            ("depression risk", Double(m.depressionRisk)),
            ("SNS activation", Double(m.snsActivation)),
            ("cortisol", Double(m.cortisolValue)),
        ]
        return BandHealthGlance(values: values, functionSupport: UInt(m.functionSupport))
    }

    /// The band's own list of what it can measure — `veepooSDK_readFuncAssessment`, one read,
    /// no sensor time. Seventeen types, each with `support` and `open` straight from the band.
    /// ⚠️ Use this, not `readCapabilities`, whenever the question is "does this HOOP do X".
    /// The capability bits are partly guessed positions in `deviceFuctionData`; this is the
    /// band answering in its own words.
    func readHealthFunctions() async throws -> [BandHealthFunction] {
        guard let peripheral else { throw BandError.notConnected }
        return try await queue.run("readHealthFunctions", priority: .p1) {
            // ⚠️ 5 s, not the usual 12: a HOOP on firmware that has no such command does
            // not refuse it, it says nothing at all — and this read sits on the serial queue
            // in front of the day pull. Measured on the wrist: no answer, ever.
            try await self.sdk("readFuncAssessment", seconds: 5) { done in
                peripheral.veepooSDK_readFuncAssessment { models in
                    let rows = (models ?? []).map {
                        BandHealthFunction(rawValue: $0.type.rawValue,
                                           name: BandHealthFunction.name(forRawValue: $0.type.rawValue),
                                           support: $0.support, open: $0.open)
                    }
                    // ⚠️ An empty array is not "supports nothing" — it is a firmware with no
                    // such command, which answers by not answering. Drawn as a dash, never
                    // as seventeen noes.
                    Self.log.notice("health functions · \(rows.map { "\($0.name)=\($0.support ? ($0.open ? "open" : "support") : "no")" }.joined(separator: " "), privacy: .public)")
                    done(.success(rows))
                }
            }
        }
    }

    func readAutoMonitoring() async throws -> AutoMonitoringRead {
        guard let peripheral else { throw BandError.notConnected }
        guard let model = central.peripheralModel else { throw BandError.notConnected }
        return try await queue.run("readAutoMonitoring", priority: .p1) {
            let intervalAPI = model.autoMonitSwitchType != 0
            Self.log.notice("autoMonitSwitchType \(model.autoMonitSwitchType) · intervalAPI \(intervalAPI)")
            if intervalAPI {
                let models: [VPAutoMonitTestModel] = try await self.sdk("readAutoMonitoring") { done in
                    peripheral.veepooSDKReadAutoMonitSwitchInfo { native in
                        guard let native else {
                            done(.failure(BandError.rejected("THIS HOOP DID NOT REPORT ITS AUTOMATIC MEASUREMENTS")))
                            return
                        }
                        done(.success(native))
                    }
                }
                // ⚠️ One entry per measurement type, each with its own window and
                // interval. That is why 12's row leads to a sheet rather than a switch.
                var slots = models.compactMap { m -> AutoMonitorSlot? in
                    guard let kind = Self.kind(m.type) else { return nil }
                    return AutoMonitorSlot(
                        kind: kind, on: m.on, supportsRange: m.supportRangeTime,
                        startHour: Int(m.startHour), endHour: Int(m.endHour),
                        intervalMinutes: Int(m.timeInterval),
                        intervalStepMinutes: Int(m.minStepValue),
                        intervalModifiable: kind != .lorentz)
                }
                let cachedSleep = AutoMeasurementSwitchFallback.readings(
                    switchData: Self.bytes(model.deviceSwitchData),
                    switchTwoData: [],
                    oxygenSupported: false,
                    oxygenOn: false
                ).first { $0.kind == .scientificSleep }
                if let cachedSleep { slots.append(Self.slot(from: cachedSleep)) }
                return .interval(await self.includingScientificSleep(in: slots, peripheral: peripheral))
            }
            return try await self.readSwitchFallback(from: model, peripheral: peripheral)
        }
    }

    func writeAutoMonitoring(_ slot: AutoMonitorSlot) async throws {
        guard let peripheral else { throw BandError.notConnected }
        guard let model = central.peripheralModel else { throw BandError.notConnected }
        try await queue.run("writeAutoMonitoring", priority: .p0) {
            // The SDK's advertised accurate-sleep switch is currently ineffective.
            // Automatic PPG is the documented controller for scientific sleep on every
            // firmware generation, including devices that also expose the interval API.
            if slot.kind == .scientificSleep {
                try await self.writeSwitchFallback(slot, peripheral: peripheral)
                return
            }
            if model.autoMonitSwitchType == 0 {
                try await self.writeSwitchFallback(slot, peripheral: peripheral)
                return
            }
            let native: [VPAutoMonitTestModel] = try await self.sdk("readAutoMonitoringForWrite") { done in
                peripheral.veepooSDKReadAutoMonitSwitchInfo { done(.success($0 ?? [])) }
            }
            guard let nativeModel = native.first(where: { Self.kind($0.type) == slot.kind }) else {
                throw BandError.unsupported("automatic \(slot.kind.rawValue) monitoring")
            }
            let requested = slot.intervalMinutes
            guard (0...AutoMeasurementIntervalPolicy.maximumMinutes).contains(requested) else {
                throw BandError.rejected("\(requested) minute interval is not supported")
            }
            nativeModel.on = slot.on
            nativeModel.startHour = UInt8(slot.startHour)
            nativeModel.endHour = UInt8(slot.endHour)
            guard let requestedInterval = UInt16(exactly: slot.intervalMinutes) else {
                throw BandError.rejected("AUTO MONITORING INTERVAL IS OUT OF RANGE")
            }
            nativeModel.timeInterval = requestedInterval
            try await self.sdk("writeAutoMonitoring") { (done: @escaping (Result<Void, Error>) -> Void) in
                peripheral.veepooSDKSetAutoMonitSwitch(with: nativeModel) { success, accepted in
                    guard success else {
                        done(.failure(BandError.rejected("AUTO MONITORING REFUSED")))
                        return
                    }
                    guard accepted?.timeInterval == requestedInterval else {
                        done(.failure(BandError.rejected("AUTO MONITORING INTERVAL WAS NOT APPLIED")))
                        return
                    }
                    done(.success(()))
                }
            }
        }
    }

    private func readSwitchFallback(
        from model: VPPeripheralModel,
        peripheral: VPPeripheralBaseManage
    ) async throws -> AutoMonitoringRead {
        let switchData = Self.bytes(model.deviceSwitchData)
        let switchTwoData = Self.bytes(model.deviceSwitchTwoData)
        if AutoMeasurementSwitchFallback.hasSwitchTables(switchData: switchData, switchTwoData: switchTwoData) {
            let readings = AutoMeasurementSwitchFallback.readings(
                switchData: switchData,
                switchTwoData: switchTwoData,
                oxygenSupported: model.oxygenType != 0,
                oxygenOn: model.oxygenAutoDetectType == 1)
            let slots = readings.map { Self.slot(from: $0) }
            return .switches(await includingScientificSleep(in: slots, peripheral: peripheral))
        }
        var slots: [AutoMonitorSlot] = []
        for (kind, type) in Self.fallbackSwitchTypes where kind != .scientificSleep {
            do {
                if let on = try await self.readBaseSwitch(type, peripheral: peripheral) {
                    slots.append(.firmwareOwned(kind: kind, on: on))
                }
            } catch {
                Self.log.error("fallback switch \(kind.rawValue, privacy: .public) ← \(String(describing: error), privacy: .public)")
            }
        }
        return .switches(await includingScientificSleep(in: slots, peripheral: peripheral))
    }

    /// Scientific sleep is not one of the interval API's measurement rows. Its authoritative
    /// state is VPSettingAutomaticPPGTest: the SDK says turning that off also turns precise
    /// sleep off. A failed read preserves a cached byte-table value instead of hiding it.
    private func includingScientificSleep(
        in slots: [AutoMonitorSlot],
        peripheral: VPPeripheralBaseManage
    ) async -> [AutoMonitorSlot] {
        var result = slots
        do {
            guard let on = try await readBaseSwitch(.automaticPPGTest, peripheral: peripheral) else {
                Self.log.notice("scientific sleep · automatic PPG not exposed")
                return result
            }
            Self.log.notice("scientific sleep · automatic PPG \(on ? "on" : "off", privacy: .public)")
            let sleep = AutoMonitorSlot.firmwareOwned(kind: .scientificSleep, on: on)
            if let index = result.firstIndex(where: { $0.kind == .scientificSleep }) {
                result[index] = sleep
            } else {
                result.append(sleep)
            }
        } catch {
            Self.log.error("scientific sleep switch ← \(String(describing: error), privacy: .public)")
        }
        return result
    }

    private func writeSwitchFallback(_ slot: AutoMonitorSlot, peripheral: VPPeripheralBaseManage) async throws {
        guard let type = Self.fallbackSwitchTypes.first(where: { $0.kind == slot.kind })?.type else {
            throw BandError.unsupported("automatic \(slot.kind.rawValue) monitoring")
        }
        let wantedOn = slot.on
        try await sdk("writeAutoMonitoringSwitch") { done in
            peripheral.veepooSDKSettingBaseFunctionType(
                type,
                settingState: wantedOn ? .settingFunctionOpen : .settingFunctionClose
            ) { state in
                switch state {
                case .functionCompleteOpen:
                    done(wantedOn ? .success(()) : .failure(BandError.rejected("AUTO MONITORING STAYED ON")))
                case .functionCompleteClose:
                    done(wantedOn ? .failure(BandError.rejected("AUTO MONITORING STAYED OFF")) : .success(()))
                case .functionCompleteComplete:
                    done(.success(()))
                case .functionCompleteUnknown:
                    done(.failure(BandError.unsupported("automatic \(slot.kind.rawValue) monitoring")))
                default:
                    done(.failure(BandError.rejected("AUTO MONITORING REFUSED")))
                }
            }
        }
    }

    private func readBaseSwitch(
        _ type: VPSettingBaseFunctionSwitchType,
        peripheral: VPPeripheralBaseManage
    ) async throws -> Bool? {
        try await sdk("readAutoMonitoringSwitch.\(type.rawValue)", seconds: 8) { done in
            peripheral.veepooSDKSettingBaseFunctionType(type, settingState: .readFunctionState) { state in
                switch state {
                case .functionCompleteOpen: done(.success(true))
                case .functionCompleteClose: done(.success(false))
                case .functionCompleteUnknown: done(.success(nil))
                default: done(.failure(BandError.rejected("AUTO MONITORING SWITCH READ FAILED")))
                }
            }
        }
    }

    private static let fallbackSwitchTypes: [(kind: AutoMonitorSlot.Kind, type: VPSettingBaseFunctionSwitchType)] = [
        (.heartRate, .automaticHRTest),
        (.bloodPressure, .automaticBPTest),
        (.hrv, .automaticHRVTest),
        (.bloodOxygen, .automaticOxygenTest),
        (.temperature, .automaticTemperatureTest),
        (.bloodGlucose, .automaticBloodGlucoseTest),
        (.stress, .stress),
        (.scientificSleep, .automaticPPGTest),
        (.bloodComponents, .automaticBloodCompTest),
    ]

    private static func slot(from reading: AutoMeasurementSwitchFallback.Reading) -> AutoMonitorSlot {
        let kind = AutoMonitorSlot.Kind(rawValue: reading.kind.rawValue) ?? .heartRate
        return .firmwareOwned(kind: kind, on: reading.on)
    }

    private static func bytes(_ data: Data?) -> [UInt8] {
        guard let data else { return [] }
        return Array(data)
    }

    /// Open `mode`, let the band answer, close it again. `success` in the open callback is
    /// the verdict — the band either took the mode (it exists on this firmware) or refused.
    /// A failed close is logged only: the probe's mission is the answer, and a session left
    /// running is better than a probe that never came back.
    func probeSportMode(_ rawValue: Int) async throws -> Bool {
        do {
            try await startSportMode(rawValue)
            try? await stopSportMode(rawValue)
            return true
        } catch let error as BandError {
            switch error {
            case .unsupported, .rejected: return false
            default: throw error
            }
        }
    }

    func startSportMode(_ rawValue: Int) async throws {
        guard let peripheral else { throw BandError.notConnected }
        guard let mode = VPDeviceRuningMode(rawValue: rawValue) else {
            throw BandError.unsupported("sport mode \(rawValue)")
        }
        try await queue.run("startSportMode", priority: .p0) {
            try await self.sdk("startSportMode") { done in
                peripheral.veepooSDKSettingDeviceRunning(1, run: mode) { runningType, success in
                    if success { done(.success(())) }
                    else if runningType == 2 { done(.failure(BandError.busy)) }
                    else { done(.failure(BandError.rejected("SPORT MODE REFUSED"))) }
                }
            }
        }
    }

    func stopSportMode(_ rawValue: Int) async throws {
        guard let peripheral else { throw BandError.notConnected }
        guard let mode = VPDeviceRuningMode(rawValue: rawValue) else {
            throw BandError.unsupported("sport mode \(rawValue)")
        }
        do {
            try await queue.run("stopSportMode", priority: .p0) {
                try await self.sdk("stopSportMode") { done in
                    peripheral.veepooSDKSettingDeviceRunning(0, run: mode) { runningType, closed in
                        if closed { done(.success(())) }
                        else if runningType == 2 { done(.failure(BandError.busy)) }
                        else {
                            Self.log.notice("sport stop failed for \(rawValue)")
                            done(.failure(BandError.rejected("SPORT MODE DID NOT CLOSE")))
                        }
                    }
                }
            }
        } catch BandError.rejected {
            // 14 · the legacy close refused — a session opened on the band itself, or under
            // another mode, answers no here. The sport-control protocol's stop is the other
            // door: fire it, then ask the band where it stands. Only a `not started` answer
            // counts as closed.
            Self.log.notice("sport stop · trying the control protocol")
            try await queue.run("stopSportMode.control", priority: .p0) {
                await MainActor.run { peripheral.veepooSDK_deviceSportControl(with: .stop, type: mode) }
            }
            try? await Task.sleep(for: .milliseconds(1200))
            let state = await sportRunState()
            Self.log.notice("sport stop · state after control stop \(state.map(String.init) ?? "none", privacy: .public)")
            guard state == 0 else { throw BandError.rejected("SPORT MODE DID NOT CLOSE") }
        }
    }

    /// A single SDK subscription is shared by live readers and one-shot state probes.
    /// Native callback and polling ownership change together on the main actor.
    func sportLiveInfo() -> AsyncStream<SportLiveInfo> {
        AsyncStream { continuation in
            let id = UUID()
            let installation = Task { @MainActor in
                guard !Task.isCancelled, self.state == .connected, let peripheral = self.peripheral else {
                    continuation.finish()
                    return
                }
                self.sportReaders[id] = continuation
                guard self.sportSubscription.add(id) else { return }
                let generation = self.sportSubscription.generation
                self.sportLastReceipt = Date()
                Self.log.notice("sport info subscribe generation=\(generation)")
                peripheral.veepooSDK_deviceSportInfoSubscribe { [weak self] model in
                    guard let model else { return }
                    let info = SportLiveInfo.deviceReport(
                        heartRate: Int(model.heartRate),
                        rawCalories: model.calories,
                        durationSec: Int(model.duration),
                        runState: model.runState.rawValue,
                        distanceM: model.distance > 0 ? Int(model.distance) : nil)
                    Task { @MainActor in
                        guard let self, self.sportSubscription.generation == generation,
                              !self.sportReaders.isEmpty else { return }
                        self.sportLastReceipt = Date()
                        Self.log.notice("sport info receipt hasHR=\(info.heartRate != nil) state=\(info.runState ?? -1)")
                        for reader in self.sportReaders.values { reader.yield(info) }
                    }
                }
                self.sportPoll = Task { @MainActor [weak self] in
                    var misses = 0
                    while !Task.isCancelled {
                        guard let self, self.sportSubscription.generation == generation,
                              !self.sportReaders.isEmpty else { return }
                        guard self.state == .connected else {
                            self.finishSportReaders(generation: generation)
                            return
                        }
                        // Poll admission waits behind active native commands. Reports
                        // arrive asynchronously on the shared subscription.
                        try? await self.queue.run("sportStatePoll", priority: .p0) { [weak self] in
                            await MainActor.run {
                                guard let self, self.state == .connected,
                                      self.sportSubscription.generation == generation,
                                      !self.sportReaders.isEmpty else { return }
                                peripheral.veepooSDK_readDeviceSportState()
                            }
                        }
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                        if Date().timeIntervalSince(self.sportLastReceipt) > 2.5 {
                            misses += 1
                            if misses >= 3 {
                                Self.log.notice("sport info no answer to three reads")
                                self.finishSportReaders(generation: generation)
                                return
                            }
                        } else { misses = 0 }
                    }
                }
            }
            continuation.onTermination = { [weak self] _ in
                installation.cancel()
                Task { @MainActor in self?.removeSportReader(id) }
            }
        }
    }

    @MainActor private func removeSportReader(_ id: UUID) {
        sportReaders.removeValue(forKey: id)
        guard sportSubscription.remove(id) else { return }
        sportPoll?.cancel()
        sportPoll = nil
        peripheral?.veepooSDK_deviceSportInfoSubscribe(nil)
    }

    @MainActor private func finishSportReaders(generation: Int) {
        guard sportSubscription.generation == generation else { return }
        let readers = sportReaders
        for (id, reader) in readers {
            removeSportReader(id)
            reader.finish()
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
        case .HRV:             .hrv
        case .bloodComponents: .bloodComponents
        @unknown default:      nil
        }
    }
}
#endif

/// Preserve the existing binding/cache key while recording this phone's stable BLE UUID.
enum BoundBand {
    private static let key = "nb.band.identifier"
    private static let peripheralKey = "nb.band.peripheralIdentifier"
    private static let peripheralOwnerKey = "nb.band.peripheralBinding"
    static var identifier: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.setValue(newValue, forKey: key) }
    }

    static var peripheralIdentifier: String? {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: peripheralOwnerKey) == identifier,
           let value = defaults.string(forKey: peripheralKey), UUID(uuidString: value) != nil {
            return value
        }
        // Compatibility with this SDK's old MAC-based bindings. Accept its remembered
        // UUID only when its MAC exactly matches our binding; never pick a nearby band.
        let remembered = defaults.dictionary(forKey: "deviceMessageKey")
        return BandSyncPolicy.legacyPeripheralIdentifier(bound: identifier,
            rememberedAddress: remembered?["deviceMacKey"] as? String,
            rememberedPeripheral: remembered?["deviceUUIDKey"] as? String)
    }

    static func remember(peripheralIdentifier: String) {
        guard UUID(uuidString: peripheralIdentifier) != nil else { return }
        // A reconnect keeps legacy cache keys; a new pairing gets the stable UUID.
        if !BandSyncPolicy.matchesBoundDevice(discovered: peripheralIdentifier, bound: identifier,
                                              boundPeripheral: self.peripheralIdentifier) {
            identifier = peripheralIdentifier
        }
        UserDefaults.standard.set(peripheralIdentifier, forKey: peripheralKey)
        UserDefaults.standard.set(identifier, forKey: peripheralOwnerKey)
    }

    /// Forget only the app binding; server history stays.
    static func forget() {
        for storedKey in [key, peripheralKey, peripheralOwnerKey] {
            UserDefaults.standard.removeObject(forKey: storedKey)
        }
    }
}

/// One place decides which band the app is talking to.
enum Band {
    static let live: BandService = {
        #if targetEnvironment(simulator)
        return MockBand()
        #elseif canImport(VeepooBleSDK)
        return VeepooBand()
        #else
        return DisconnectedBand()
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

    /// Seeded walk-through: board numbers, MockBand ticks, the demo@ session.
    /// Compile-time simulator only. Independent of whether VeepooBleSDK is linked —
    /// an unlinked device build used to make `isReal` false and dump the seed onto the phone.
    static var allowsSeed: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
