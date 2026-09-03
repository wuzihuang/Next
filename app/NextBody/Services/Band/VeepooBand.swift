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

    /// What the last scan reported, by CoreBluetooth identifier. `connect` hands the SDK the
    /// very model it scanned; `central.peripheralModel` is only set once a device is connected,
    /// so reading it before connecting always found nothing.
    private var scanned: [String: VPPeripheralModel] = [:]

    /// F2 §05 · what we last pushed down. The band's BIA multiplies by this, so a sample
    /// taken before a sync is discarded rather than stored.
    private var pushedWeightKg: Double?
    private var pushedAt: Date?

    init() {
        // ⚠️ Which subclass sits here decides whether the day can be read at all, and it has
        // to be set before the first connect (doc §SDK初始化).
        //  · VPPeripheralBaseManage (what the SDK leaves in place): readBasicData, readSleepData
        //    and readStepData are a single `ret`. Two syncs on a real HOOP ran exactly 90 s —
        //    the timeout — and wrote nothing, while battery and BIA worked.
        //  · VPPeripheralAddManage ("应用层自行持久化"): the commands go out and twenty packages
        //    come back, but the block's array is nil every time; the bytes pile up in a private
        //    NSMutableData and are never parsed. The header's 「暂未实现」 is literal.
        //  · VPPeripheralManage ("SDK持久化", what the vendor recommends and the demo uses):
        //    veepooSdkStartReadDeviceAllData reads every day the band holds into the SDK's own
        //    database, and VPDataBaseOperation hands it back keyed by "HH:mm". That is the path.
        central.peripheralManage = VPPeripheralManage.shareVPPeripheralManager()
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

    // MARK: connection

    func startScan() async { await startScan(auto: false) }

    /// `auto` is the SDK's automaticConnection: on, it connects to its last band the moment
    /// the scan sees it. A manual scan from 02 must never do that — the pairing chain then
    /// ran twice, once by the SDK and once by the app, and the band answered nothing after.
    private func startScan(auto: Bool) async {
        state = .scanning
        scanned = [:]
        await MainActor.run { central.automaticConnection = auto }
        // The SDK's CBCentralManager is created on first use and reports poweredOn a few
        // milliseconds later. Asked to scan before that, it does nothing at all — the device
        // log showed "scan start" 8 ms ahead of the system's "state On", then 15 s of silence.
        await waitForPoweredOn()
        Self.log.notice("scan start")
        // ⚠️ Every SDK entry point runs on the main thread. The SDK keeps its scan, connect and
        // confirm timeouts on NSTimers, which only fire on a run loop; called from a Swift
        // concurrency thread, a connect that never answers also never times out.
        await MainActor.run {
            central.veepooSDKStartScanDeviceAndReceiveScanningDevice { [weak self] model in
                guard let self, let model else { return }
                // ⚠️ deviceAddress is a CoreBluetooth UUID on iOS, not a MAC.
                let id = model.deviceAddress ?? UUID().uuidString
                let name = model.deviceName ?? "HOOP"
                let rssi = model.rssi?.intValue ?? -99
                Self.log.notice("scan found device · rssi \(rssi)")
                self.scanned[id] = model
                self.hub.send(.discovered(DiscoveredBand(id: id, name: name, rssi: rssi, batteryPercent: nil)))
            }
        }
    }

    /// Up to 5 s for the SDK's central to report poweredOn; 02 edge 2 covers the radio being
    /// off, so this only bridges the manager's own start-up.
    private func waitForPoweredOn() async {
        for _ in 0..<50 {
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
        if state == .connected, central.peripheralModel?.deviceAddress == device.id {
            Self.log.notice("connect: already verified")
            BoundBand.identifier = device.id
            return
        }
        state = .connecting
        guard let model = scanned[device.id] else {
            Self.log.error("connect: requested device was not in the last scan")
            throw BandError.notConnected
        }
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
        BoundBand.identifier = device.id
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
    func reconnectIfBound() async {
        guard BoundBand.identifier != nil, state != .connected else { return }
        state = .connecting
        await startScan(auto: true)
        // The SDK reconnects on its own once it sees the band again; callers read `state`
        // the moment this returns, so wait for that to happen — up to 15 s — then stop scanning.
        var waited = 0
        while state != .connected, waited < 150 {
            try? await Task.sleep(for: .milliseconds(100)); waited += 1
        }
        await MainActor.run { central.veepooSDKStopScanDevice(); central.automaticConnection = false }
        if state != .connected { state = .disconnected }
        Self.log.notice("reconnect \(self.state == .connected ? "ok" : "failed", privacy: .public)")
    }

    func disconnect() async {
        await MainActor.run { central.veepooSDKDisconnectDevice() }
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

    func readBattery() async throws -> BandBattery {
        guard let peripheral else { throw BandError.notConnected }
        return try await queue.run("readBattery", priority: .p1) {
            try await self.sdk("readBattery") { done in
                peripheral.veepooSDKReadDeviceBatteryAndChargeInfo { isPercent, charge, isLow, value in
                    // ⚠️ Firmware with isPercent = false gives 0–4 bars. Those are stored in a
                    // different column and never rendered with a % sign.
                    done(.success(BandBattery(
                        isPercent: isPercent,
                        percent: isPercent ? Int(value) : nil,
                        level: isPercent ? nil : Int(value),
                        chargeState: {
                            switch charge {
                            case .charging: .charging
                            case .full:     .full
                            case .normal:   .unplugged
                            default:                   .unknown
                            }
                        }())))
                }
            }
        }
    }

    // MARK: personal info

    func syncPersonalInfo(_ info: PersonalInfo) async throws {
        guard let peripheral else { throw BandError.notConnected }
        try await queue.run("syncPersonalInfo", priority: .p0) {
            try await self.sdk("syncPersonalInfo") { (done: @escaping (Result<Void, Error>) -> Void) in
                peripheral.veepooSDKSynchronousPersonalInformation(
                    withStature: UInt(info.heightCm),
                    weight: UInt(info.weightKg),
                    birth: UInt(info.birthYear),
                    sex: UInt(info.sexIsMale ? 1 : 0),
                    targetStep: UInt(info.targetStep)) { _ in done(.success(())) }
            }
        }
        pushedWeightKg = Double(info.weightKg)
        pushedAt = Date()
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
                Self.log.notice("readOriginData(\(dayOffset)) \(date, privacy: .public) · \(points.count) points · first \(first.time, privacy: .public)")
            } else {
                Self.log.notice("readOriginData(\(dayOffset)) \(date, privacy: .public) · 0 points")
            }
            return points
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
            if auxiliaryIsStale {
                if model.hrvType != 0 {
                    try await self.sdk("readHRV", seconds: 300) { (done: @escaping (Result<Void, Error>) -> Void) in
                        peripheral.veepooSdkStartReadDeviceHrvData { state, _, _, _ in
                            switch state {
                            case .complete: done(.success(()))
                            case .invalid: done(.failure(BandError.unsupported("HRV history")))
                            default: break
                            }
                        }
                    }
                }
                if [2, 4].contains(model.temperatureType) {
                    try await self.sdk("readTemperature", seconds: 300) { (done: @escaping (Result<Void, Error>) -> Void) in
                        peripheral.veepooSdkStartReadDeviceTemperatureData { state, _, _, _ in
                            switch state {
                            case .complete: done(.success(()))
                            case .invalid: done(.failure(BandError.unsupported("temperature history")))
                            default: break
                            }
                        }
                    }
                }
                self.auxiliaryDataReadAt = Date()
            }
            let date = Self.dayString(daysAgo: dayOffset)
            return await MainActor.run {
                let temperatures = ((VPDataBaseOperation
                    .veepooSDKGetDeviceTemperatureData(withDate: date, andTableID: address)
                    as? [[String: Any]]) ?? []).compactMap(HealthSampleMapping.temperature)
                let hrv = ((VPDataBaseOperation
                    .veepooSDKGetDeviceHrvData(withDate: date, andTableID: address)
                    as? [[String: Any]]) ?? []).compactMap(HealthSampleMapping.hrv)
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
                Self.log.notice("readHealthData(\(dayOffset)) \(date, privacy: .public) · hrv \(hrv.count) minute(s) padded, \(measured.count) measured, \(withRR) with ≥2 RR, \(withVendor) with vendor value · rr/min \(rr.min() ?? 0)–\(rr.max() ?? 0) · measured by hour [\(perHour, privacy: .public)] · e.g. \(sample, privacy: .public) · temp \(temperatures.count)")
                return BandHealthData(temperatures: temperatures, hrv: hrv)
            }
        }
    }

    /// The night that ends on the morning of the day `dayOffset` back. The SDK files a
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

            // "2017/02/09 07:45" · the morning of `morning`, before noon: a nap after lunch
            // is not the night, and neither is the night before.
            func endsThisMorning(_ wake: String?) -> Bool {
                guard let wake else { return false }
                let day = wake.prefix(10).replacingOccurrences(of: "/", with: "-")
                let hour = Int(wake.dropFirst(11).prefix(2)) ?? 24
                return day == morning && hour < 12
            }
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

            let accurateNight = accurate.filter { endsThisMorning($0.wakeTime) }
                .sorted { ($0.sleepTime ?? "") < ($1.sleepTime ?? "") }
            if !accurateNight.isEmpty {
                let deep = accurateNight.reduce(0.0) { $0 + num($1.deepDuration) }
                let light = accurateNight.reduce(0.0) { $0 + num($1.lightDuration) }
                let other = accurateNight.reduce(0.0) { $0 + num($1.otherDuration) }
                var total = accurateNight.reduce(0.0) { $0 + num($1.sleepDuration) }
                if total <= 0 { total = deep + light + other }
                let wakes = accurateNight.reduce(0) { $0 + Int(num($1.getUpTimes)) }
                let line = Self.runs(from: accurateNight)
                Self.log.notice("readSleep(\(dayOffset)) \(morning, privacy: .public) · accurate (sleepType \(sleepType)) · \(Int(total)) min in \(accurateNight.count) segment(s) · \(accurateNight.first?.sleepTime ?? "?", privacy: .public) → \(accurateNight.last?.wakeTime ?? "?", privacy: .public) · line \(line.count) runs")
                var result = SleepNight(totalMinutes: Int(total), deepMinutes: Int(deep),
                                        lightMinutes: Int(light), wakeCount: wakes, line: line)
                result.sleepStart = Self.instant(accurateNight.first?.sleepTime)
                result.wakeAt = Self.instant(accurateNight.last?.wakeTime)
                return result
            }

            let night = records.filter { endsThisMorning($0["WAKE_TIME"] as? String) }
            guard !night.isEmpty else {
                let stamps = (accurate.compactMap(\.wakeTime) + records.compactMap { $0["WAKE_TIME"] as? String })
                    .joined(separator: ",")
                Self.log.notice("readSleep(\(dayOffset)) \(morning, privacy: .public) · no night · sleepType \(sleepType) · accurate \(accurateTotal) record(s), plain \(records.count) · wake times [\(stamps, privacy: .public)]")
                return nil
            }
            let deep = night.reduce(0.0) { $0 + num($1["DEEP_HOUR"]) * 60 }
            let light = night.reduce(0.0) { $0 + num($1["LIGHT_HOUR"]) * 60 }
            var total = night.reduce(0.0) { $0 + num($1["SLE_HOUR"]) * 60 + num($1["SLE_MINUTE"]) }
            if total <= 0 { total = deep + light }
            let wakes = night.reduce(0) { $0 + Int(num($1["WakeUpTime"])) }
            Self.log.notice("readSleep(\(dayOffset)) \(morning, privacy: .public) · plain (sleepType \(sleepType)) · \(Int(total)) min in \(night.count) segment(s)")
            // Stage counts only; not one of these numbers reaches a screen (F0 rule 03).
            let line = await MainActor.run {
                Self.sleepLine(morning: morning, address: address, dates: dates)
            }
            return SleepNight(totalMinutes: Int(total), deepMinutes: Int(deep),
                              lightMinutes: Int(light), wakeCount: wakes, line: line)
        }
    }

    /// 04B rule 04 · one run per stage stretch, in the order the segments ran. Stage ids are
    /// the SDK's: 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake; one point is one minute.
    private static func runs(from night: [VPAccurateSleepModel]) -> [SleepStageRun] {
        var runs: [SleepStageRun] = []
        for model in night {
            for point in model.parseSleepLine() ?? [] {
                guard let type = (point["type"] as? NSNumber)?.intValue else { continue }
                if let last = runs.last, last.stage == type {
                    runs[runs.count - 1] = SleepStageRun(stage: type, minutes: last.minutes + 1)
                } else {
                    runs.append(SleepStageRun(stage: type, minutes: 1))
                }
            }
        }
        return runs
    }

    /// 04B rule 04 · the night's own sleepLine, one run per stage stretch, in the order the
    /// night ran. The accurate models answer from the same local store, are queried under both
    /// candidate dates like the dictionary records above, and are matched by the same
    /// wake-morning rule; a night without a curve answers empty and the strip falls back to
    /// the totals.
    private static func sleepLine(morning: String, address: String, dates: [String]) -> [SleepStageRun] {
        let night = dates.flatMap {
            VPDataBaseOperation.veepooSDKGetAccurateSleepData(withDate: $0, andTableID: address) ?? []
        }
            .filter { model in
                let wake = model.wakeTime ?? ""
                let day = wake.prefix(10).replacingOccurrences(of: "/", with: "-")
                let hour = Int(wake.dropFirst(11).prefix(2)) ?? 24
                return day == morning && hour < 12
            }
            .sorted { ($0.sleepTime ?? "") < ($1.sleepTime ?? "") }
        return runs(from: night)
    }

    /// "2017/02/09 07:45", the SDK's sleep stamp, read in the phone's own zone.
    private static func instant(_ stamp: String?) -> Date? {
        guard let stamp else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: stamp)
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
                    Self.log.notice("heart state \(testState.rawValue) value \(value)")
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
                        c.yield(.measuring(fraction: 0.5,
                                           partial: PartialReading(heartRate: Int(value))))
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
                        c.yield(.lostContact)
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
        let stop = { DispatchQueue.main.async { peripheral.veepooSDK_stressTestStart(false, result: { _, _, _ in }) } }
        return try await withTaskCancellationHandler {
            // Measured on a real HOOP: 19 s, progress 0…100 at 6 a second. 90 s is the
            // timeout — the ceiling for a band that stops answering, not the length.
            try await sdk("stressTest", seconds: 90) { done in
                peripheral.veepooSDK_stressTestStart(true) { state, done_progress, stress in
                    Self.log.notice("stress state \(state.rawValue) progress \(done_progress) value \(stress)")
                    // The SDK's callbacks arrive on the main thread — every entry point of this
                    // framework does — so the drawn progress is handed over there, in order,
                    // rather than hopping through a Task that could deliver 42 after 48.
                    MainActor.assumeIsolated { progress(done_progress) }
                    switch state {
                    case .complete:
                        // ⚠️ `complete` is NOT the end of the test. The SDK reports it on
                        // every progress callback, from the first one, with value 0 while the
                        // measurement is still running — device log, one session:
                        //   stressTest → · 165 ms · state 5 progress 0 value 0
                        //                          state 5 progress 6 value 0
                        // Resuming on the first of those stopped the test a sixth of a second
                        // in and answered 0, which is how STRESS stayed —— on a band that
                        // measures it perfectly well. The value is the end; nothing else is.
                        guard stress > 0 else { break }
                        // F1 rule 05 · a test that answered is still a test that is open.
                        stop()
                        done(.success(Int(stress)))
                    case .noFunction:   done(.failure(BandError.unsupported("STRESS")))
                    case .deviceBusy:   done(.failure(BandError.busy))
                    case .lowPower:     done(.failure(BandError.rejected("BAND BATTERY LOW")))
                    case .notWear:      done(.failure(BandError.rejected("NOT ON THE WRIST")))
                    // `over` is our own stop coming back. Nothing to resume with.
                    default:            break
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
            default:
                throw BandError.unsupported("that setting")
            }
        }
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
                let slots = models.compactMap { m -> AutoMonitorSlot? in
                    guard let kind = Self.kind(m.type) else { return nil }
                    return AutoMonitorSlot(
                        kind: kind, on: m.on, supportsRange: m.supportRangeTime,
                        startHour: Int(m.startHour), endHour: Int(m.endHour),
                        intervalMinutes: Int(m.timeInterval),
                        intervalStepMinutes: Int(m.minStepValue),
                        intervalModifiable: kind != .lorentz)
                }
                return .interval(slots)
            }
            return try await self.readSwitchFallback(from: model, peripheral: peripheral)
        }
    }

    func writeAutoMonitoring(_ slot: AutoMonitorSlot) async throws {
        guard let peripheral else { throw BandError.notConnected }
        guard let model = central.peripheralModel else { throw BandError.notConnected }
        try await queue.run("writeAutoMonitoring", priority: .p0) {
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
            return .switches(readings.map { Self.slot(from: $0) })
        }
        var slots: [AutoMonitorSlot] = []
        for (kind, type) in Self.fallbackSwitchTypes {
            do {
                if let on = try await self.readBaseSwitch(type, peripheral: peripheral) {
                    slots.append(.firmwareOwned(kind: kind, on: on))
                }
            } catch {
                Self.log.error("fallback switch \(kind.rawValue, privacy: .public) ← \(String(describing: error), privacy: .public)")
            }
        }
        return .switches(slots)
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
                peripheral.veepooSDKSettingDeviceRunning(1, run: mode) { _, success in
                    if success { done(.success(())) }
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
        try await queue.run("stopSportMode", priority: .p0) {
            try await self.sdk("stopSportMode") { done in
                peripheral.veepooSDKSettingDeviceRunning(0, run: mode) { _, closed in
                    if closed { done(.success(())) }
                    else {
                        Self.log.notice("sport stop failed for \(rawValue)")
                        done(.failure(BandError.rejected("SPORT MODE DID NOT CLOSE")))
                    }
                }
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
        case .HRV:             .hrv
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
