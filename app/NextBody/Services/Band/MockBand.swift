#if targetEnvironment(simulator)
import Foundation

/// The band the simulator has. It answers on the same timings the real one does, so the
/// choreography on 02 and 06 is exercised for real: the scan takes a couple of seconds,
/// contact does not arrive instantly, and a body scan really does take thirty seconds.
///
/// It is not a stub that returns immediately — a stub would hide every timing bug the
/// takeover has, which is the only part of this flow that is hard to get right.
final class MockBand: BandService, @unchecked Sendable {
    private(set) var state: BandConnectionState = .idle {
        didSet { hub.send(.state(state)) }
    }

    private let hub = BandEventHub()
    var events: AsyncStream<BandEvent> { hub.stream() }
    private let queue = HoopQueue()

    private var pushedWeightKg: Double = 75.6
    private var healthLight: BandHealthLightState = .slowFlash
    private var disconnectReminder = true
    private var autoMonitoringSlots: [AutoMonitorSlot] = [
        .init(kind: .heartRate, on: true, supportsRange: true,
              startHour: 0, endHour: 24, intervalMinutes: 30, intervalStepMinutes: 1),
        .init(kind: .bloodOxygen, on: true, supportsRange: true,
              startHour: 22, endHour: 7, intervalMinutes: 60, intervalStepMinutes: 5),
        .init(kind: .hrv, on: true, supportsRange: false,
              startHour: 0, endHour: 24, intervalMinutes: 60, intervalStepMinutes: 1),
        .firmwareOwned(kind: .scientificSleep, on: true),
        .init(kind: .stress, on: true, supportsRange: true,
              startHour: 9, endHour: 22, intervalMinutes: 30, intervalStepMinutes: 5),
        .init(kind: .temperature, on: false, supportsRange: false,
              startHour: 0, endHour: 24, intervalMinutes: 60, intervalStepMinutes: 5),
        .init(kind: .bloodGlucose, on: true, supportsRange: true,
              startHour: 8, endHour: 22, intervalMinutes: 30, intervalStepMinutes: 5),
    ]

    private var alarms: [BandAlarm] = [
        BandAlarm(id: 1, hour: 7, minute: 30, on: true,
                  repeatMask: BandAlarmMath.weekdaysMask,
                  date: BandAlarm.onceDatePlaceholder, scene: 0),
        BandAlarm(id: 2, hour: 8, minute: 45, on: true,
                  repeatMask: BandAlarmMath.weekdaysMask,
                  date: BandAlarm.onceDatePlaceholder, scene: 0),
    ]

    func startScan() async {
        state = .scanning
        try? await Task.sleep(for: .seconds(2.2))
        // A scan that started while the bound band reconnected (DEVICE page + activation
        // sheet at once) still answers, as the real radio does.
        guard state == .scanning || state == .connected || state == .connecting else { return }
        hub.send(.discovered(DiscoveredBand(
            id: Self.firstHoop, name: "NEXTBODY HOOP", rssi: -46, batteryPercent: 96)))
        // The second HOOP of a set sits on its charger a little further away. It arrives
        // late so Connect's first-discovered pick still lands on the first band.
        try? await Task.sleep(for: .milliseconds(900))
        guard state == .scanning || state == .connected || state == .connecting else { return }
        hub.send(.discovered(DiscoveredBand(
            id: Self.secondHoop, name: "NEXTBODY HOOP", rssi: -61, batteryPercent: 71)))
    }

    /// Two simulator bands, so the two-HOOP set (9-0) can be walked without hardware.
    static let firstHoop = "C4-2E-8F-1A-73-9D"
    static let secondHoop = "8E-41-C0-2B-77-1F"
    private var onSecond: Bool { BoundBand.identifier == Self.secondHoop }

    func stopScan() async { if state == .scanning { state = .idle } }

    func connect(_ device: DiscoveredBand, progress: @escaping @Sendable (Double) -> Void) async throws {
        state = .connecting
        // Same beats the real SDK reports: connecting → link up → password verified.
        progress(0)
        try? await Task.sleep(for: .milliseconds(600))
        progress(0.25)
        try? await Task.sleep(for: .milliseconds(600))
        progress(0.7)
        try? await Task.sleep(for: .milliseconds(600))
        progress(1)
        try? await Task.sleep(for: .milliseconds(600))
        state = .connected
        BoundBand.identifier = device.id
        hub.send(.battery(try await readBattery()))
    }

    func reconnectIfBound() async {
        guard let bound = BoundBand.identifier, state != .connected else { return }
        state = .connecting
        try? await Task.sleep(for: .milliseconds(700))
        state = .connected
        _ = try? await readBattery()
        _ = bound
    }

    func disconnect() async { state = .disconnected }

    func prepareFreshSync() async { dumpedThisRefresh = false }
    func finishFreshSync() async {}

    /// One dump per refresh, the way the real SDK reads every retained day before
    /// the per-day cache lookups. The ticks are what the device-page bar follows.
    private var dumpedThisRefresh = false
    private func simulateHistoryDump() async {
        guard !dumpedThisRefresh else { return }
        dumpedThisRefresh = true
        let days = 7
        for day in 1...days {
            hub.send(.historyRead(day: day, of: days, percent: 0))
            try? await Task.sleep(for: .milliseconds(70))
            hub.send(.historyRead(day: day, of: days, percent: 55))
            try? await Task.sleep(for: .milliseconds(70))
            hub.send(.historyRead(day: day, of: days, percent: 100))
        }
    }

    func readIdentity() async throws -> BandIdentity {
        try await requireConnection()
        return BandIdentity(
            name: "NEXTBODY HOOP", model: "KR96 PRO", hardware: "1.2", firmware: "2.4.1",
            deviceNumber: onSecond ? "HB-0107" : "HB-0042",
            bleIdentifier: onSecond ? Self.secondHoop : Self.firstHoop,
            watchDataDayNumber: 7, sportMode: "10 TYPES")
    }

    func readCapabilities() async throws -> BandCapabilities {
        try await requireConnection()
        var caps = BandCapabilities()
        caps.bodyComponent = .support
        caps.ecg = .support
        caps.hrv = .support
        caps.stress = .support
        caps.autoMeasure = .support
        caps.wearDetection = .support
        caps.functions = ["heart": .support, "spo2": .support, "blood": .support,
                          "temperature": .unsupported]
        return caps
    }

    func readBattery() async throws -> BandBattery {
        try await requireConnection()
        let battery: BandBattery
        if DebugEdge.on("charging") {
            battery = BandBattery(isPercent: true, percent: 64, level: nil, chargeState: .charging)
        } else if DebugEdge.on("charged") {
            battery = BandBattery(isPercent: true, percent: 100, level: nil, chargeState: .full)
        } else if onSecond {
            battery = BandBattery(isPercent: true, percent: 71, level: nil, chargeState: .charging)
        } else {
            battery = BandBattery(isPercent: true, percent: 82, level: nil, chargeState: .unplugged)
        }
        hub.send(.battery(battery))
        return battery
    }

    func syncPersonalInfo(_ info: PersonalInfo) async throws {
        try await requireConnection()
        pushedWeightKg = Double(info.weightKg)
        try? await Task.sleep(for: .milliseconds(220))
    }

    func readOriginData(dayOffset: Int) async throws -> [OriginPoint] {
        try await requireConnection()
        await simulateHistoryDump()
        try? await Task.sleep(for: .milliseconds(400))
        // 288 five-minute points, a plausible day: asleep until 07, a walk, a session at 18.
        return (0..<288).map { i in
            let minute = i * 5
            let hour = minute / 60
            let asleep = hour < 7
            let walking = hour == 7 && minute % 60 < 35
            let session = hour == 18 && minute % 60 < 45
            let hr = asleep ? 49 + Int.random(in: 0...5)
                   : walking ? 96 + Int.random(in: 0...14)
                   : session ? 138 + Int.random(in: 0...22)
                   : 60 + Int.random(in: 0...10)
            return OriginPoint(
                time: String(format: "%02d:%02d", hour, minute % 60),
                heart: hr, step: asleep ? 0 : Int.random(in: 0...45),
                cal: Int.random(in: 0...6), distance: Int.random(in: 0...40),
                met: max(1.0, Double(hr) / 62), temperature: nil,
                // Every ten minutes, as the band does; higher asleep, as HRV is.
                hrv: minute % 10 == 0
                    ? Double(asleep ? 52 + Int.random(in: 0...18) : 32 + Int.random(in: 0...16))
                    : nil,
                stress: asleep ? nil : 20 + Int.random(in: 0...30),
                // HOOP's original-data dictionary has no sleep stage. Accurate stages come
                // from SleepNight.line, exactly as they do on the real SDK.
                sleepState: nil)
        }
    }

    func readSleep(dayOffset: Int) async throws -> SleepNight? {
        try await requireConnection()
        await simulateHistoryDump()
        // Scientific sleep adds the band's own REM runs. Turning its automatic PPG off
        // deliberately falls back to the basic deep/light line, just like the real firmware.
        let scientificSleep = autoMonitoringSlots
            .first(where: { $0.kind == .scientificSleep })?.on ?? false
        let line = scientificSleep
            ? [
                SleepStageRun(stage: 1, minutes: 70),
                SleepStageRun(stage: 0, minutes: 55),
                SleepStageRun(stage: 1, minutes: 42),
                SleepStageRun(stage: 2, minutes: 32),
                SleepStageRun(stage: 1, minutes: 50),
                SleepStageRun(stage: 4, minutes: 6),
                SleepStageRun(stage: 0, minutes: 43),
                SleepStageRun(stage: 2, minutes: 24),
                SleepStageRun(stage: 1, minutes: 88),
            ]
            : [
                SleepStageRun(stage: 1, minutes: 70),
                SleepStageRun(stage: 0, minutes: 55),
                SleepStageRun(stage: 1, minutes: 92),
                SleepStageRun(stage: 4, minutes: 6),
                SleepStageRun(stage: 0, minutes: 43),
                SleepStageRun(stage: 1, minutes: 144),
            ]
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -dayOffset,
                                to: calendar.startOfDay(for: Date())) ?? Date()
        let wake = calendar.date(byAdding: .hour, value: 7, to: day)
        let start = wake?.addingTimeInterval(-410 * 60)
        var night = SleepNight(
            totalMinutes: 410,
            deepMinutes: 98,
            lightMinutes: scientificSleep ? 250 : 306,
            wakeCount: 1,
            line: line
        )
        night.sleepStart = start
        night.wakeAt = wake
        return night
    }

    func readHealthData(dayOffset: Int) async throws -> BandHealthData {
        try await requireConnection()
        await simulateHistoryDump()
        let temperatures = stride(from: 0, to: 24 * 60, by: 5).map { minute in
            TemperatureSample(time: String(format: "%02d:%02d", minute / 60, minute % 60),
                              celsius: 34.0 + 0.4 * sin(Double(minute) / 180))
        }
        let hrv = (0..<8 * 60).map { minute in
            HrvMinuteSample(time: String(format: "%02d:%02d", minute / 60, minute % 60),
                            rmssdMS: 48 + 5 * sin(Double(minute) / 45),
                            vendorValue: nil, rrCount: 40)
        }
        // Overnight automatic oxygen only — daytime minutes are not filed, matching Q6.
        let oxygen = stride(from: 0, to: 7 * 60, by: 5).map { minute in
            OxygenSample(time: String(format: "%02d:%02d", minute / 60, minute % 60),
                         percent: 95 + (minute / 30) % 3)
        }
        // Daytime optical meal-response slots. Night hours are left empty so the own
        // median is a daytime number, matching the RESPONSE card.
        let optical: [OpticalResponseSample] = stride(from: 10 * 60, to: 22 * 60, by: 30).map { (minute: Int) in
            let value: Double = 100 + 8 * sin(Double(minute) / 90)
            return OpticalResponseSample(time: String(format: "%02d:%02d", minute / 60, minute % 60),
                                         optical: value)
        }
        return BandHealthData(temperatures: temperatures, hrv: hrv, oxygen: oxygen, optical: optical)
    }

    func measureHeartRate() -> AsyncThrowingStream<MeasurementProgress, Error> {
        // The real SDK hands back a rate on every `testing` callback, from the first one, and
        // it wanders as the band settles. The mock does the same, so the trace on 06 beats at
        // a rate that moves, not at a constant the screen could have invented.
        stream(total: 60) { fraction in
            let second = fraction * 60
            let hr = second < 1 ? nil : 62 + Int((3 * sin(second / 7)).rounded()) + (second < 6 ? 4 : 0)
            return .measuring(fraction: fraction, partial: hr.map { PartialReading(heartRate: $0) })
        } finish: {
            .heartRate(hr: 62, hrv: 54, stress: 34)
        }
    }

    func measureBodyComposition() -> AsyncThrowingStream<MeasurementProgress, Error> {
        // ⚠️ 30s, two contacts, fourteen fields, and no resume: lifting off restarts it.
        stream(total: 30) { fraction in
            .measuring(fraction: fraction,
                       partial: fraction > 0.5 ? PartialReading(bodyFatPercent: 24.1) : nil)
        } finish: { [pushedWeightKg] in
            var r = BodyCompositionReading(
                bodyFatPercent: 14.8,
                fatMassKg: pushedWeightKg * 0.148,
                leanMassKg: pushedWeightKg * 0.852,
                muscleKg: pushedWeightKg * 0.62, boneKg: 2.7,
                bodyWaterPercent: 55.2, proteinPercent: 17.6,
                subcutaneousFatPercent: 18.9, skeletalMusclePercent: 42.1,
                bmrKcal: 1710, bmi: 21.3,
                inputWeightKg: pushedWeightKg)
            r.muscleRatePercent = 74.3
            r.waterKg = pushedWeightKg * 0.552
            r.proteinKg = pushedWeightKg * 0.176
            return .bodyComposition(r)
        }
    }

    /// 04 · the inserted stress test. It really does take half a minute and it really does
    /// hold the sensor for all of it, so the panel's live heart rate goes quiet while it
    /// runs — which is the whole behaviour `LiveReadout` exists to get right.
    func measureStress(progress: @escaping @MainActor (Int) -> Void) async throws -> Int {
        try await requireConnection()
        // DEBUG · `NB_DEBUG_EDGE=nostress` walks the firmware that has no stress test.
        if DebugEdge.on("nostress") { throw BandError.unsupported("STRESS") }
        // The real band's own shape, measured on the wrist: 0…100 in steps of 6, one a
        // second, and the value only on the last callback. 19 s, and it really does hold the
        // sensor for all of it — which is the behaviour `LiveReadout` exists to get right.
        var done = 0
        while done < 100 {
            try Task.checkCancellation()
            try? await Task.sleep(for: .seconds(1))
            done = min(100, done + 6)
            await progress(done)
        }
        return 24 + Int.random(in: 0...22)
    }

    /// Simulator stand-in for the SDK's HRV test: settles after a few seconds with a
    /// plausible resting value. Real firmware may hold the full minute.
    func measureHRV(timeout: TimeInterval) async throws -> Int {
        try await requireConnection()
        if DebugEdge.on("nohrv") { throw BandError.unsupported("HRV") }
        let steps = min(8, max(2, Int(timeout / 3)))
        for _ in 0..<steps {
            try Task.checkCancellation()
            try? await Task.sleep(for: .seconds(1))
        }
        return 48 + Int.random(in: 0...16)
    }

    private func stream(total: Int,
                        progress: @escaping (Double) -> MeasurementProgress,
                        finish: @escaping () -> MeasurementResult)
    -> AsyncThrowingStream<MeasurementProgress, Error> {
        AsyncThrowingStream { continuation in
            // F1 rule 05 · a cancelled consumer stops the measurement. Without this the mock
            // went on ticking after the takeover closed, which is exactly the bug the real
            // band has and the one the simulator exists to make visible.
            let work = Task {
                guard state == .connected else {
                    continuation.finish(throwing: BandError.notConnected); return
                }
                continuation.yield(.waitingForContact)
                // DEBUG · `NB_DEBUG_EDGE=nocontact` never finds a finger, to walk 03 edge 1.
                if DebugEdge.on("nocontact") { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }; return }
                // The finger takes about 1.2s to register, which is why the nudge is at 5s.
                try? await Task.sleep(for: .milliseconds(1200))
                continuation.yield(.contact)
                try? await Task.sleep(for: .milliseconds(800))
                for second in 0...total {
                    try? await Task.sleep(for: .seconds(1))
                    continuation.yield(progress(Double(second) / Double(total)))
                }
                continuation.yield(.finished(finish()))
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// The simulator's update server: one offer, a moment later. `NB_DEBUG_EDGE=uptodate`
    /// answers that the band is current, `otacheckfail` that the server could not be reached.
    func checkFirmwareUpdate() async throws -> FirmwareOffer? {
        try await requireConnection()
        try? await Task.sleep(for: .milliseconds(900))
        if DebugEdge.on("uptodate") { return nil }
        if DebugEdge.on("otacheckfail") { throw BandError.rejected("update server unreachable") }
        return FirmwareOffer(version: "2.5.0", notes: ["Better sleep staging", "Battery reported in percent"])
    }

    func updateFirmware(to version: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FirmwareUpdateResult {
        // A real transfer takes minutes; the mock walks the same shape in seconds.
        for step in 1...24 {
            try? await Task.sleep(for: .milliseconds(100))
            progress(Double(step) / 24)
        }
        // DEBUG · `NB_DEBUG_EDGE=otaunverified` walks 12 edge 5 on the mock.
        if DebugEdge.on("otaunverified") { return .versionUnverified }
        return .completed(version: version)
    }

    func writeSetting(_ setting: BandSetting) async throws -> BandSetting {
        try await requireConnection()
        try? await Task.sleep(for: .milliseconds(180))
        // F3 · the switch renders the value that came back, never the value we sent.
        return setting
    }

    func readHealthLight() async throws -> BandHealthLightState {
        try await requireConnection()
        return try await queue.run("mock.readHealthLight", priority: .p1) {
            try? await Task.sleep(for: .milliseconds(160))
            return self.healthLight
        }
    }

    func writeHealthLight(_ state: BandHealthLightState) async throws -> BandHealthLightState {
        try await requireConnection()
        return try await queue.run("mock.writeHealthLight", priority: .p0) {
            try? await Task.sleep(for: .milliseconds(180))
            self.healthLight = state
            return state
        }
    }

    func readDisconnectReminder() async throws -> Bool? {
        try await requireConnection()
        return try await queue.run("mock.readDisconnectReminder", priority: .p1) {
            try? await Task.sleep(for: .milliseconds(120))
            return self.disconnectReminder
        }
    }

    func writeDisconnectReminder(_ on: Bool) async throws -> Bool {
        try await requireConnection()
        return try await queue.run("mock.writeDisconnectReminder", priority: .p0) {
            try? await Task.sleep(for: .milliseconds(160))
            self.disconnectReminder = on
            return on
        }
    }

    func readAutoMonitoring() async throws -> AutoMonitoringRead {
        try await requireConnection()
        return try await queue.run("mock.readAutoMonitoring", priority: .p1) {
            if DebugEdge.on("autorefuse") {
                throw BandError.timeout("readAutoMonitoring")
            }
            if DebugEdge.on("autonone") {
                return .switches([])
            }
            if DebugEdge.on("autoempty") {
                return .interval([])
            }
            if DebugEdge.on("autoswitch") {
                return .switches([
                    .firmwareOwned(kind: .heartRate, on: true),
                    .firmwareOwned(kind: .bloodOxygen, on: true),
                    .firmwareOwned(kind: .hrv, on: false),
                    .firmwareOwned(kind: .stress, on: true),
                ])
            }
            return .interval(self.autoMonitoringSlots)
        }
    }

    func writeAutoMonitoring(_ slot: AutoMonitorSlot) async throws {
        try await requireConnection()
        try await queue.run("mock.writeAutoMonitoring", priority: .p0) {
            if slot.intervalModifiable {
                guard slot.allowedIntervals.contains(slot.intervalMinutes) else {
                    throw BandError.rejected("\(slot.intervalMinutes) minute interval is not supported")
                }
            }
            try? await Task.sleep(for: .milliseconds(160))
            if let index = self.autoMonitoringSlots.firstIndex(where: { $0.id == slot.id }) {
                self.autoMonitoringSlots[index] = slot
            } else {
                self.autoMonitoringSlots.append(slot)
            }
        }
    }

    /// The simulator stands in for a multi-mode firmware. Raw values are
    /// VPDeviceRuningMode ordinals. Every catalogued mode is accepted so the plus-menu
    /// flow can be walked end to end on a simulator.
    func probeSportMode(_ rawValue: Int) async throws -> Bool {
        try await requireConnection()
        return try await queue.run("mock.probeSportMode", priority: .p0) {
            try? await Task.sleep(for: .milliseconds(220))
            return SportModeCatalog.modes.contains(where: { $0.rawValue == rawValue })
        }
    }

    func startSportMode(_ rawValue: Int) async throws {
        try await requireConnection()
        try await queue.run("mock.startSportMode", priority: .p0) {
            try? await Task.sleep(for: .milliseconds(220))
            guard SportModeCatalog.modes.contains(where: { $0.rawValue == rawValue }) else {
                throw BandError.unsupported("sport mode \(rawValue)")
            }
        }
    }

    func stopSportMode(_ rawValue: Int) async throws {
        try await requireConnection()
        try await queue.run("mock.stopSportMode", priority: .p0) {
            try? await Task.sleep(for: .milliseconds(160))
            _ = rawValue
        }
    }

    /// 14 · a wrist that climbs from a warm-up to a working rate, once a second, with the
    /// band's own calorie count ticking beside it — the shape a real report has.
    func sportLiveInfo() -> AsyncStream<SportLiveInfo> {
        AsyncStream { c in
            let task = Task {
                let start = Date()
                var beat = 96.0
                var kcal = 0.0
                while !Task.isCancelled {
                    let t = Date().timeIntervalSince(start)
                    let target = 118 + 26 * (1 - exp(-t / 90)) + 6 * sin(t / 11)
                    beat += (target - beat) * 0.3 + Double.random(in: -1.5...1.5)
                    kcal += beat / 60 * 0.09
                    c.yield(SportLiveInfo(heartRate: Int(beat.rounded()), caloriesKcal: kcal,
                                          distanceM: Int(t * 2.6), durationSec: Int(t), runState: 1))
                    try? await Task.sleep(for: .seconds(1))
                }
                c.finish()
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    /// The simulator stands in for a firmware that carries most of the list. `nuclear
    /// radiation` and the two AI rows are off, as they are on a band without them.
    func readHealthFunctions() async throws -> [BandHealthFunction] {
        try await requireConnection()
        try? await Task.sleep(for: .milliseconds(180))
        let supported: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        var list: [BandHealthFunction] = []
        for raw in 0...16 {
            let isSup = supported.contains(raw)
            let item = BandHealthFunction(
                rawValue: raw,
                name: BandHealthFunction.name(forRawValue: raw),
                support: isSup,
                open: isSup && raw != 6
            )
            list.append(item)
        }
        return list
    }

    /// The simulator's 微体检: a firmware that carries the optical half and none of the
    /// electrode half, so the walk shows what a partial answer looks like.
    func probeHealthGlance(progress: @escaping @MainActor (Int) -> Void) async throws -> BandHealthGlance {
        try await requireConnection()
        var done = 0
        while done < 100 {
            try Task.checkCancellation()
            try? await Task.sleep(for: .milliseconds(700))
            done = min(100, done + 5)
            await progress(done)
        }
        let support: UInt = (1 << 0) | (1 << 1) | (1 << 5) | (1 << 6) | (1 << 8) | (1 << 9)
        let values: [(name: String, value: Double)] = [
            ("heart rate", 71), ("blood oxygen", 97), ("stress", 28), ("fatigue level", 2),
            ("body temperature", 36.4), ("HRV", 46),
        ]
        return BandHealthGlance(values: values, functionSupport: support)
    }

    /// The simulator's pulse study, on the real band's timings: 40 s, progress about 3 % a
    /// second, a rate that arrives a few seconds in. The intervals it finishes with carry a
    /// respiratory wobble, so the balance readout has something with real structure to chew
    /// on rather than a straight line.
    func measurePulseStudy() -> AsyncThrowingStream<PulseStudyStep, Error> {
        AsyncThrowingStream { c in
            let work = Task {
                guard state == .connected else {
                    c.finish(throwing: BandError.notConnected); return
                }
                c.yield(.waitingForContact)
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                c.yield(.contact)
                var intervals: [Double] = []
                let seconds = 40
                for second in 0...seconds {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    // Sinus arrhythmia: the interval breathes with the wearer at about
                    // 0.25 Hz, plus a little beat-to-beat scatter.
                    let base = 880.0
                    let rr = base
                        + 34 * sin(Double(second) * 2 * .pi * 0.25)
                        + Double.random(in: -12...12)
                    intervals.append(rr)
                    let percent = min(100, Int(Double(second) / Double(seconds) * 100))
                    c.yield(.measuring(percent: percent,
                                       heartRate: second > 3 ? Int((60_000 / rr).rounded()) : nil))
                }
                let mean = intervals.reduce(0, +) / Double(intervals.count)
                c.yield(.finished(PulseStudy(heartRate: Int((60_000 / mean).rounded()),
                                             intervals: intervals,
                                             source: .intervals,
                                             durationSeconds: seconds,
                                             vendorHRV: 47)))
                c.finish()
            }
            c.onTermination = { _ in work.cancel() }
        }
    }

    func readManualTestData(since: Date) async throws -> [String] {
        try await requireConnection()
        try? await Task.sleep(for: .milliseconds(300))
        let t = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        return ["health glance \(t) · hr 71 spo2 97 stress 28 fatigue 2 temp 36.4 bp 118/76 hrv 46"]
    }

    func probeMicroTest(progress: @escaping @MainActor (Int) -> Void) async throws -> [(name: String, value: Double)] {
        try await requireConnection()
        var done = 0
        while done < 100 {
            try Task.checkCancellation()
            try? await Task.sleep(for: .milliseconds(600))
            done = min(100, done + 5)
            await progress(done)
        }
        return [("heart rate", 71), ("blood oxygen", 97), ("stress", 28), ("blood sugar", 5.4),
                ("body temperature", 36.4), ("systolic", 118), ("diastolic", 76), ("HRV", 46)]
    }

    func startFindHoop() async throws {
        try await requireConnection()
        hub.send(.findHoop(.enter))
        if ProcessInfo.processInfo.environment["NB_DEBUG_FIND_TIMEOUT"] == "1" {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                hub.send(.findHoop(.timeout))
            }
        }
    }

    func stopFindHoop() async {
        hub.send(.findHoop(.exit))
    }

    func readConnectedRSSI() async throws -> Int {
        try await requireConnection()
        return -52
    }

    /// DEBUG · `NB_DEBUG_EDGE=noalarms` walks a HOOP that has never been given one,
    /// which is the only way to see the SWITCH sheet's centred key.
    func readAlarms() async throws -> [BandAlarm] {
        try await requireConnection()
        try? await Task.sleep(for: .milliseconds(180))
        if DebugEdge.on("noalarms") { alarms = [] }
        return alarms
    }

    func writeAlarm(_ alarm: BandAlarm) async throws -> [BandAlarm] {
        try await requireConnection()
        let next = BandAlarmMath.prepared(alarm)
        if let index = alarms.firstIndex(where: { $0.id == next.id }) {
            alarms[index] = next
        } else if BandAlarmMath.isFull(alarms) {
            throw BandError.rejected("THIS HOOP IS FULL")
        } else {
            alarms.append(next)
        }
        return alarms
    }

    func deleteAlarm(_ alarm: BandAlarm) async throws -> [BandAlarm] {
        try await requireConnection()
        alarms.removeAll { $0.id == alarm.id }
        return alarms
    }

    func probeCapabilitySweep() async throws -> [String] {
        try await requireConnection()
        try? await Task.sleep(for: .milliseconds(240))
        return [
            "model · MOCK-G70 hw MOCK-1 cpu 1",
            "types · heart=1 sleep=3 ecg=2 temp=2 glucose=0 bp=0 oxygen=1 hrv=1",
            "function.female=0",
            "health · stress=open HRV=open body composition=open · not: blood glucose, AI chat",
            "female · refused",
            "gsensor · 12 packets in 6.0s x -18…22 y -4…9 z 980…1024 steps 0",
            "gsensor.adc · 0 bytes",
        ]
    }

    private func requireConnection() async throws {
        guard state == .connected else { throw BandError.notConnected }
    }
}
#endif
