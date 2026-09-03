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

    func startScan() async {
        state = .scanning
        try? await Task.sleep(for: .seconds(2.2))
        guard state == .scanning else { return }
        hub.send(.discovered(DiscoveredBand(
            id: "C4-2E-8F-1A-73-9D", name: "NEXTBODY HOOP", rssi: -46, batteryPercent: 96)))
    }

    func stopScan() async { if state == .scanning { state = .idle } }

    func connect(_ device: DiscoveredBand) async throws {
        state = .connecting
        // 02 · 04 · four real steps, not a fake tween.
        for _ in 0..<4 { try? await Task.sleep(for: .milliseconds(600)) }
        state = .connected
        BoundBand.identifier = device.id
        hub.send(.battery(try await readBattery()))
    }

    func reconnectIfBound() async {
        guard let bound = BoundBand.identifier, state != .connected else { return }
        state = .connecting
        try? await Task.sleep(for: .milliseconds(700))
        state = .connected
        hub.send(.battery(BandBattery(
            isPercent: true, percent: 82, level: nil, chargeState: .unplugged)))
        _ = bound
    }

    func disconnect() async { state = .disconnected }

    func readIdentity() async throws -> BandIdentity {
        try await requireConnection()
        return BandIdentity(
            name: "NEXTBODY HOOP", model: "KR96 PRO", hardware: "1.2", firmware: "2.4.1",
            deviceNumber: "HB-0042", bleIdentifier: "C4-2E-8F-1A-73-9D",
            watchDataDayNumber: 7)
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
        return BandBattery(isPercent: true, percent: 82, level: nil, chargeState: .unplugged)
    }

    func syncPersonalInfo(_ info: PersonalInfo) async throws {
        try await requireConnection()
        pushedWeightKg = Double(info.weightKg)
        try? await Task.sleep(for: .milliseconds(220))
    }

    func readOriginData(dayOffset: Int) async throws -> [OriginPoint] {
        try await requireConnection()
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
                stress: asleep ? nil : 20 + Int.random(in: 0...30),
                sleepState: asleep ? 2 : 0)
        }
    }

    func readSleep(dayOffset: Int) async throws -> SleepNight? {
        try await requireConnection()
        // 6H 50M as the band's own line: light → deep → light → one wake → deep → light.
        return SleepNight(totalMinutes: 410, deepMinutes: 98, lightMinutes: 306, wakeCount: 1,
                          line: [SleepStageRun(stage: 1, minutes: 70), SleepStageRun(stage: 0, minutes: 55),
                                 SleepStageRun(stage: 1, minutes: 92), SleepStageRun(stage: 4, minutes: 6),
                                 SleepStageRun(stage: 0, minutes: 43), SleepStageRun(stage: 1, minutes: 144)])
    }

    func readHealthData(dayOffset: Int) async throws -> BandHealthData {
        try await requireConnection()
        let temperatures = stride(from: 0, to: 24 * 60, by: 5).map { minute in
            TemperatureSample(time: String(format: "%02d:%02d", minute / 60, minute % 60),
                              celsius: 34.0 + 0.4 * sin(Double(minute) / 180))
        }
        let hrv = (0..<8 * 60).map { minute in
            HrvMinuteSample(time: String(format: "%02d:%02d", minute / 60, minute % 60),
                            rmssdMS: 48 + 5 * sin(Double(minute) / 45),
                            vendorValue: nil, rrCount: 40)
        }
        return BandHealthData(temperatures: temperatures, hrv: hrv)
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

    func readAutoMonitoring() async throws -> [AutoMonitorSlot] {
        try await requireConnection()
        return [
            .init(kind: .heartRate, on: true, supportsRange: true,
                  startHour: 0, endHour: 24, intervalMinutes: 30),
            .init(kind: .bloodOxygen, on: true, supportsRange: true,
                  startHour: 22, endHour: 7, intervalMinutes: 60),
            .init(kind: .hrv, on: true, supportsRange: false,
                  startHour: 0, endHour: 24, intervalMinutes: 60),
            .init(kind: .stress, on: true, supportsRange: true,
                  startHour: 9, endHour: 22, intervalMinutes: 30),
            .init(kind: .temperature, on: false, supportsRange: false,
                  startHour: 0, endHour: 24, intervalMinutes: 60),
        ]
    }

    func writeAutoMonitoring(_ slot: AutoMonitorSlot) async throws {
        try await requireConnection()
        try? await Task.sleep(for: .milliseconds(160))
    }

    private func requireConnection() async throws {
        guard state == .connected else { throw BandError.notConnected }
    }
}
