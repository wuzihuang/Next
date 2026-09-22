import SwiftUI
import UIKit
import os

/// 14 · LIVE SESSION · the one sport session the band is running, held for as long as it
/// runs. Picked on `SportModeView`; from the tap on, it lives here: the home screen's panel
/// grows over everything (`LiveSessionTakeover`) at once, while the band is still being
/// asked — a refusal folds the screen back with the reason, an answer lets it run.
///
/// Three numbers and nothing else: the clock (the phone's — `startedAt` is the tap), the
/// heart rate and the burn. Heart rate comes from the band's sport report (`sportLiveInfo`).
/// Energy uses a verified kcal counter when available, otherwise a labeled estimate
/// integrated only across valid observed heart-rate intervals. The heart *test* is
/// refused as busy for exactly that reason. A firmware that carries no report falls back
/// to that test anyway, and if that is refused too the clock runs alone and says so.
/// Valid live heart-rate observations also enter the account's durable evidence outbox.
/// Only the intervals actually observed by the phone can refine settled training load.
@MainActor
final class LiveSessionStore: ObservableObject {
    static let shared = LiveSessionStore()
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "session")

    private init() {
        lastRecap = Self.restoreSeedRecap()
    }

    struct Session: Equatable {
        let id: UUID
        let mode: SportModeOption
        /// The tap — or, once the band has said how long it has been running, the band's own
        /// start: its clock is the record and the screen's clock follows it.
        var startedAt: Date
        /// The band was already running a session when this one was asked for, and this
        /// screen joined it instead of starting another.
        var joined = false
    }

    /// What the screen may say about the wrist. Same vocabulary as `LiveReadout`: `offline`
    /// is the link, `noContact` is the wrist, and they are never drawn the same way.
    enum Wrist: Equatable { case off, reaching, live, noContact, offline, paused }

    @Published private(set) var session: Session?
    /// True from the tap until the band has answered the open command.
    @Published private(set) var opening = false
    /// The band refused the mode. The screen folds back and carries this line.
    @Published private(set) var refusal: String?
    @Published private(set) var hr: Int?
    @Published private(set) var hrAt: Date?
    @Published private(set) var wrist: Wrist = .off {
        // Contact coming or going changes what the island says, not just its numbers, so it
        // jumps the update cadence.
        didSet { if oldValue != wrist { pushIsland(force: true) } }
    }
    /// A verified cumulative kcal count, or an estimate over observed heart-rate intervals.
    /// After joining, the estimate covers only the portion observed by this app process.
    @Published private(set) var kcal: Double = 0
    @Published private(set) var stopping = false
    @Published private(set) var errorLine: String?
    @Published private(set) var lastRecap: SessionRecap?

    typealias SessionRecap = SportSessionRecap

    private var metrics = SportMetricAccumulator(weightKg: nil, age: nil, male: false)
    private var recapBeats: [SportRecapMath.Beat] = []
    private var recapSegment = 0
    private var heartEvidence = SportHeartRateEvidenceStream()
    private var energyEvidence = SportEnergyEvidenceStream()
    var caloriesAreEstimated: Bool { metrics.calorieSource == .estimate }
    var hasCalories: Bool { metrics.hasEnergyEvidence }
    var energyLabel: String {
        if !caloriesAreEstimated { return L("BURNED") }
        return session?.joined == true ? L("ESTIMATE SINCE JOIN") : L("ESTIMATED BURN")
    }
    private var openTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var lifetime: SportSessionLifetime?
    private var startDisposition: SportStartDisposition = .notIssued
    var cleaningUp: Bool { cleanupTask != nil }
    /// ⚠️ Owned by the store, not by the screen. The takeover used to hold it on
    /// `scenePhase == .active`, which was right when the session was only ever on screen —
    /// but the island is the session with the phone in a pocket, so the read has to outlive
    /// the view. `bluetooth-central` in the Info.plist is what keeps the app alive for it.
    private var wristTask: Task<Void, Never>?
    private var hrMax = 190
    /// First running report of this seek. Optical lock is timed from here, not the tap.
    private var seekBeganAt: Date?
    /// Last valid beat in this seek. Survives a zero report so a dropout is not a verdict.
    private var lastHeartAt: Date?

    /// A heart rate older than this is not the wrist now. Same window as the panel's.
    static let liveWindow = SportMetricAccumulator.liveWindow

    var heartFreshness: SportHeartFreshness.State {
        guard session != nil, wrist == .live else { return .missing }
        return SportHeartFreshness.state(receivedAt: hrAt, now: Date())
    }
    var liveHR: Int? {
        heartFreshness == .missing ? nil : hr
    }
    var delayedHeartNote: String? {
        guard wrist == .live else { return nil }
        switch heartFreshness {
        case .live: return nil
        case .stale: return L("HEART RATE DELAYED")
        case .missing: return L("WAITING FOR A NEW HEART RATE")
        }
    }
    var averageHR: Int? { metrics.averageHR }
    var peakHR: Int? { metrics.peakHR }

    // MARK: lifecycle

    /// The tap. The session is on from here — the screen grows now, and the band is asked
    /// underneath it. `weightKg` is the latest weigh-in the day knows, for the burn.
    func begin(_ mode: SportModeOption, profile: Profile, weightKg: Double?,
               authorized: @escaping @MainActor () -> Bool = { true }) {
        guard authorized() else { return }
        guard session == nil, cleanupTask == nil else { return }
        guard Self.debugFakeWrist || (ConsentStore.shared.granted
            && SupabaseClient.currentUserIdSnapshot() != nil && BoundBand.identifier != nil) else {
            refusal = L("Connect your band before starting a session.")
            return
        }
        self.hrMax = profile.hrMax
        metrics = SportMetricAccumulator(weightKg: weightKg, age: profile.age,
                                         male: profile.sexIsMale, sportMode: mode.rawValue)
        recapBeats = []
        recapSegment = 0
        let sessionID = UUID()
        heartEvidence = SportHeartRateEvidenceStream(sessionID: sessionID)
        energyEvidence = SportEnergyEvidenceStream(sessionID: sessionID)
        kcal = 0
        hr = nil; hrAt = nil
        seekBeganAt = nil
        lastHeartAt = nil
        errorLine = nil
        refusal = nil
        wrist = .off
        let owner = SportSessionLifetime(account: SupabaseClient.currentUserIdSnapshot(), binding: BoundBand.identifier)
        lifetime = owner
        startDisposition = .notIssued
        opening = !Self.debugFakeWrist
        session = Session(id: sessionID, mode: mode, startedAt: Date())
        BandLiveLifecycle.shared.refreshEligibility()
        // A workout screen that goes dark half-way through a set is a screen nobody can read.
        UIApplication.shared.isIdleTimerDisabled = true
        Self.log.notice("session on · \(mode.name, privacy: .public) #\(mode.rawValue)")

        // The island goes up with the session, not with the first heart rate: the seconds
        // are already worth showing, and a screen the user swipes away from immediately
        // should leave something behind.
        SessionActivity.start(sport: mode.name, modeRawValue: mode.rawValue, state: islandState())
        if Self.debugFakeWrist {
            wristTask = Task { [weak self] in await self?.runWrist(owner: owner) }
            return
        }
        openTask = Task { [weak self] in
            await BandReadiness.shared.awaitNativeIdle()
            guard let self else { return }
            guard (self.accepts(owner) && authorized()) else {
                if self.lifetime == owner, !Task.isCancelled {
                    self.opening = false
                    self.refusal = L("Connect your band before starting a session.")
                }
                return
            }
            let outcome = await LiveReadout.shared.standDown {
                guard (self.accepts(owner) && authorized()) else { return Open.refused(CancellationError()) }
                if Band.live.state != .connected { await Band.live.reconnectForSport() }
                guard (self.accepts(owner) && authorized()) else { return Open.refused(CancellationError()) }
                guard Band.live.state == .connected else { return Open.refused(BandError.notConnected) }
                // Every mode starts with this person's current inputs, after readiness
                // and before opening. Never send an invented default weight.
                if let weightKg, weightKg.isFinite, weightKg > 0, weightKg < Double(Int.max),
                   profile.heightCm.isFinite, profile.heightCm > 0, profile.heightCm < Double(Int.max) {
                    do {
                        try await Band.live.syncPersonalInfo(PersonalInfo(
                            heightCm: Int(profile.heightCm.rounded()), weightKg: Int(weightKg.rounded()),
                            birthYear: Calendar.current.component(.year, from: profile.birthdate),
                            sexIsMale: profile.sexIsMale, targetStep: profile.stepGoal))
                    } catch { return Open.refused(error) }
                    guard (self.accepts(owner) && authorized()) else { return Open.refused(CancellationError()) }
                }
                return await Self.open(mode, isCurrent: { (self.accepts(owner) && authorized()) },
                    disposition: { self.startDisposition = $0 })
            }
            guard (self.accepts(owner) && authorized()) else {
                if self.lifetime == owner, !Task.isCancelled {
                    self.opening = false
                    self.refusal = L("Connect your band before starting a session.")
                }
                return
            }
            self.opening = false
            switch outcome {
            case .opened, .joined:
                if case .joined = outcome { self.session?.joined = true }
                self.wristTask = Task { [weak self] in
                    await LiveReadout.shared.standDown { await self?.runWrist(owner: owner) }
                }
                let joined = self.session?.joined ?? false
                Task { await Analytics.shared.track("SESSION_START", ["MODE": mode.rawValue,
                    "NAME": mode.name, "JOINED": joined]) }
            case .refused(let error):
                Self.log.error("session refused · \(String(describing: error), privacy: .public)")
                BandLog.shared.record("session.start", error: error)
                self.refusal = error.localizedDescription
            }
        }
    }

    /// Phone actions retain their execution eligibility until the deferred BLE start settles.
    func awaitOpening(authorized: @MainActor () -> Bool) async {
        let openingOwner = lifetime
        await openTask?.value
        if !authorized(), lifetime == openingOwner { end() }
    }

    private func accepts(_ owner: SportSessionLifetime) -> Bool {
        !Task.isCancelled && session != nil && owner.accepts(current: lifetime,
            account: SupabaseClient.currentUserIdSnapshot(), binding: BoundBand.identifier,
            consent: Self.debugFakeWrist || ConsentStore.shared.granted)
    }

    private enum Open { case opened, joined, refused(Error) }

    /// Ask the band for the mode. A refusal is most often the band already running a session
    /// — one started on the wrist, or one an earlier screen never closed (device log,
    /// 2026-09-03: every open answered REFUSED while the report said `running`, 63 s in).
    /// So a refusal is followed by a close and one more try; if the band still says no but
    /// reports a session running, this screen joins that session rather than folding back
    /// over a wrist that is, in fact, being read.
    private static func open(_ mode: SportModeOption, isCurrent: () -> Bool,
                             disposition: (SportStartDisposition) -> Void) async -> Open {
        do {
            guard isCurrent() else { throw CancellationError() }
            try Task.checkCancellation()
            try await startWithBusyRetry(mode, isCurrent: isCurrent, disposition: disposition)
            try Task.checkCancellation()
            return .opened
        } catch {
            guard isCurrent(), !Task.isCancelled else { return .refused(CancellationError()) }
            if case BandError.busy = error {
                // Busy can mean another sensor, so only an actual running sport report
                // permits attaching to a workout left running across an app relaunch.
                if await joinRunningSport(isCurrent: isCurrent, disposition: disposition) { return .joined }
                return .refused(error)
            }
            guard case BandError.rejected = error else { return .refused(error) }
            log.notice("open refused · closing what the band has and trying once more")
            try? await Band.live.stopSportMode(mode.rawValue)
            do {
                try await Task.sleep(for: .milliseconds(600))
                try Task.checkCancellation()
                guard isCurrent() else { throw CancellationError() }
                try await startWithBusyRetry(mode, isCurrent: isCurrent, disposition: disposition)
                return .opened
            } catch {
                guard isCurrent(), !Task.isCancelled else { return .refused(CancellationError()) }
                if await joinRunningSport(isCurrent: isCurrent, disposition: disposition) { return .joined }
                return .refused(error)
            }
        }
    }

    private static func joinRunningSport(isCurrent: () -> Bool,
                                         disposition: (SportStartDisposition) -> Void) async -> Bool {
        guard isCurrent(), !Task.isCancelled else { return false }
        let state = await Band.live.sportRunState()
        guard isCurrent(), !Task.isCancelled,
              SportStartDisposition.canJoin(observedRunState: state) else { return false }
        disposition(.opened)
        log.notice("sport report confirms running · joining existing session")
        return true
    }

    /// The stopped optical stream needs time to release the sensor in firmware, beyond
    /// the main-queue stop fence. Busy gets one non-destructive retry after that same pause.
    private static func startWithBusyRetry(_ mode: SportModeOption, isCurrent: () -> Bool,
                                          disposition: (SportStartDisposition) -> Void) async throws {
        try await SportStartRetry.perform(settle: {
            try await Task.sleep(for: .seconds(LiveReadout.Cadence.settle))
            guard isCurrent() else { throw CancellationError() }
        }, start: {
            try await Band.live.startSportMode(mode.rawValue)
        }, isBusy: { error in
            if case BandError.busy = error { return true }
            return false
        }, disposition: disposition)
    }

    /// Close the mode on the band. Returns the widget the panel takes when the screen folds;
    /// the session itself stays up until `end()` so the fold has numbers to fold.
    func stop(authorized: @escaping @MainActor () -> Bool = { true }) async -> PanelWidget? {
        guard authorized() else { return nil }
        guard let session, let stoppingOwner = lifetime, !stopping else { return nil }
        stopping = true
        errorLine = nil
        defer { if lifetime == stoppingOwner || lifetime == nil { stopping = false } }
        let openingTask = openTask
        let readingTask = wristTask
        guard await SportSessionTaskFence.prepareStop(owner: stoppingOwner,
            current: { self.lifetime }, authorized: authorized,
            opening: openingTask, reading: readingTask, quiesce: {
                self.openTask = nil
                self.wristTask = nil
                self.opening = false
                self.heartEvidence.interrupted()
                await BandReadiness.shared.awaitNativeIdle()
            }, retire: { await self.retireStoppedSession(stoppingOwner) }) else { return nil }
        var closed = true
        do {
            if !Self.debugFakeWrist, startDisposition.needsCleanup {
                let result: Result<Void, Error> = await LiveReadout.shared.standDown {
                    guard authorized(), self.lifetime == stoppingOwner,
                          stoppingOwner.account == SupabaseClient.currentUserIdSnapshot(),
                          stoppingOwner.binding == BoundBand.identifier else {
                        return .failure(CancellationError())
                    }
                    do { try await Band.live.stopSportMode(session.mode.rawValue); return .success(()) }
                    catch { return .failure(error) }
                }
                try result.get()
                if lifetime == stoppingOwner { startDisposition = .notIssued }
            }
        } catch {
            // A refused stop is said, not hidden: the band may still be timing. The session
            // ends on the phone either way — a screen that cannot be left is worse.
            guard lifetime == stoppingOwner else { return nil }
            closed = false
            errorLine = error.localizedDescription
            BandLog.shared.record("session.stop", error: error)
        }
        guard lifetime == stoppingOwner else { return nil }
        guard authorized() else {
            await retireStoppedSession(stoppingOwner)
            return nil
        }
        let sec = Int(Date().timeIntervalSince(session.startedAt))
        let average = averageHR ?? 0
        let calories = Int(kcal.rounded())
        let didClose = closed
        rememberRecap(session, seconds: sec)
        if !Self.debugFakeWrist {
            let generation = Repository.shared.sessionGeneration
            Task {
                guard stoppingOwner.account == SupabaseClient.currentUserIdSnapshot(),
                      generation == Repository.shared.sessionGeneration else { return }
                await Repository.shared.settleAfterSport()
            }
        }
        Task { await Analytics.shared.track("SESSION_END", [
            "MODE": session.mode.rawValue, "SEC": sec,
            "AVG_HR": average, "KCAL": calories,
            "ENERGY_SEC": Int(metrics.estimatedSeconds.rounded()), "CLOSED": didClose,
        ]) }
        return summaryWidget(session, seconds: sec, closed: closed)
    }

    private func retireStoppedSession(_ owner: SportSessionLifetime) async {
        guard lifetime == owner else { return }
        end()
        await cleanupTask?.value
    }

    /// The screen has folded back into the panel. Nothing of the session survives here.
    func end() {
        guard cleanupTask == nil else { return }
        SessionActivity.end(islandState())
        let endingMode = session?.mode
        let endingOwner = lifetime
        let endingGeneration = Repository.shared.sessionGeneration
        lifetime = nil
        heartEvidence.interrupted()
        energyEvidence.interrupted()
        let readingTask = wristTask
        let openingTask = openTask
        readingTask?.cancel()
        openingTask?.cancel()
        wristTask = nil
        openTask = nil
        cleanupTask = Task { [weak self] in
            await SportSessionTaskFence.cancelAndWait(openingTask, readingTask)
            await BandReadiness.shared.awaitNativeIdle()
            await LiveReadout.shared.standDown {
                // end can also dismiss a refused/in-flight start without going through stop.
                // Finish any command already submitted before allowing another session.
                if self?.lifetime == nil, self?.startDisposition.needsCleanup == true,
                   !Self.debugFakeWrist, let endingMode,
                   endingOwner?.account == SupabaseClient.currentUserIdSnapshot(),
                   endingOwner?.binding == BoundBand.identifier {
                    do { try await Band.live.stopSportMode(endingMode.rawValue) }
                    catch { BandLog.shared.record("session.cleanup", error: error) }
                }
            }
            self?.cleanupTask = nil
            BandLiveLifecycle.shared.refreshEligibility()
            if !Self.debugFakeWrist,
               endingOwner?.account == SupabaseClient.currentUserIdSnapshot(),
               endingGeneration == Repository.shared.sessionGeneration {
                await Repository.shared.settleAfterSport()
            }
        }
        session = nil
        stopping = false
        opening = false
        wrist = .off
        hr = nil; hrAt = nil
        seekBeganAt = nil
        lastHeartAt = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: the wrist

    /// Held by this store across foreground/background changes. The band's sport report
    /// first; if it says nothing for a while, the heart
    /// test — which the firmware answers `busy` while a mode is open, in which case the
    /// report is tried again. Cancelling ends whichever is open (F1 rule 05).
    private func runWrist(owner: SportSessionLifetime) async {
        guard accepts(owner) else { return }
        // Receipt-driven updates render every new beat immediately. This clock only
        // ages a silent stream, including the island when no callback arrives at all.
        let freshnessClock = Task { @MainActor [weak self] in
            var previous: SportHeartFreshness.State?
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.accepts(owner) else { return }
                self.objectWillChange.send()
                let freshness = self.heartFreshness
                self.pushIsland(force: previous != freshness)
                previous = freshness
            }
        }
        defer { freshnessClock.cancel() }
        var reconnectFailures = 0
        while accepts(owner) {
            if Self.debugFakeWrist { await fakeWrist(); continue }
            guard Band.live.state == .connected else {
                interruptMetrics()
                wrist = .offline
                Self.log.notice("session reconnect begin")
                await Band.live.reconnectForSport()
                guard accepts(owner) else { break }
                if Band.live.state != .connected {
                    reconnectFailures += 1
                    try? await Task.sleep(for: .seconds(SportReconnectPolicy.delay(failures: reconnectFailures)))
                } else {
                    reconnectFailures = 0
                    Self.log.notice("session reconnect ready")
                }
                continue
            }
            // The open command has to land before the band has anything to report.
            if opening { try? await Task.sleep(for: .milliseconds(300)); continue }
            let reported = await consumeReport(owner: owner)
            if Task.isCancelled { break }
            if !reported { await consumeHeart(owner: owner) }
        }
        wrist = .off
    }

    /// The band's own report. Returns true if it said anything at all: the stream closes
    /// itself when the band stops answering, so a firmware without the report falls through
    /// to the heart test on its own.
    private func consumeReport(owner: SportSessionLifetime) async -> Bool {
        interruptMetrics()
        seekBeganAt = Date()
        wrist = .reaching
        var heard = false
        for await info in Band.live.sportLiveInfo() {
            guard accepts(owner) else { break }
            heard = true
            accept(info)
        }
        if !Task.isCancelled {
            interruptMetrics()
            if heard { Self.log.notice("sport report went quiet") }
            else { Self.log.notice("no sport report from this firmware") }
        }
        return heard
    }

    private func consumeHeart(owner: SportSessionLifetime) async {
        seekBeganAt = Date()
        wrist = .reaching
        do {
            for try await progress in Band.live.measureHeartRate() {
                guard accepts(owner) else { return }
                switch progress {
                case .waitingForContact: interruptMetrics(); wrist = .reaching
                case .contact:           wrist = .live
                case .measuring(_, let partial, _):
                    guard let beat = partial?.heartRate, beat > 0 else { continue }
                    accept(SportLiveInfo(heartRate: beat))
                case .lostContact:
                    interruptMetrics()
                    wrist = .noContact
                case .finished(.heartRate(let beat, _, _)):
                    if beat > 0 { accept(SportLiveInfo(heartRate: beat)) }
                    return
                case .finished, .failed:
                    return
                }
            }
        } catch BandError.busy {
            // The mode holds the sensor and the report is the only way at it. Back to the
            // report, after a pause — asking every second is the band's battery for nothing.
            Self.log.notice("heart test busy under the sport mode")
            wrist = .off
            try? await Task.sleep(for: .seconds(6))
        } catch BandError.unsupported {
            wrist = .off
            try? await Task.sleep(for: .seconds(30))
        } catch {
            BandLog.shared.record("session.heart", error: error)
            wrist = .offline
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func accept(_ info: SportLiveInfo) {
        guard info.runState == nil || info.runState == 1 || info.runState == 2 else {
            interruptMetrics()
            wrist = .reaching
            return
        }
        let now = Date()
        if !Self.debugFakeWrist, let owner = lifetime, accepts(owner),
           let account = owner.account,
           let sample = energyEvidence.accept(at: now, runState: info.runState,
                sportMode: session?.joined == true ? nil : session?.mode.rawValue,
                timeZone: TimeZone.current.identifier) {
            do { try SportEvidenceQueue.shared.enqueue(sample, ownerUserId: account) }
            catch {
                energyEvidence.interrupted()
                BandLog.shared.record("sport energy evidence persistence", error: error)
                errorLine = L("Energy evidence could not be saved on this phone.")
            }
        }
        if !Self.debugFakeWrist, let owner = lifetime, accepts(owner),
           let account = owner.account,
           let sample = heartEvidence.accept(at: now, heartRate: info.heartRate,
                runState: info.runState, sportMode: session?.joined == true ? nil : session?.mode.rawValue,
                timeZone: TimeZone.current.identifier) {
            do { try SportEvidenceQueue.shared.enqueue(sample, ownerUserId: account) }
            catch {
                // End continuity after a failed local commit; a later sample must not
                // silently span a report we could not durably retain.
                heartEvidence.interrupted()
                BandLog.shared.record("sport evidence persistence", error: error)
                errorLine = L("Heart-rate evidence could not be saved on this phone.")
            }
        }
        // The band's clock is the record. The first time it says how long it has run, the
        // screen's clock is set to it — and stays with it if the two drift apart.
        if let dur = info.durationSec, var s = session {
            let bandStart = now.addingTimeInterval(-Double(dur))
            if abs(bandStart.timeIntervalSince(s.startedAt)) > 3 {
                s.startedAt = bandStart
                session = s
            }
        }
        if seekBeganAt == nil { seekBeganAt = now }
        metrics = metrics.accepting(timestamp: now, heartRate: info.heartRate,
                                    caloriesKcal: info.caloriesKcal, runState: info.runState)
        hr = metrics.heartRate
        hrAt = metrics.heartRate == nil ? nil : info.receivedAt
        #if DEBUG
        NightDiagnostics.shared.record("sport.heart_published", fields: [
            "receiptToPublishMs": String(max(0, now.timeIntervalSince(info.receivedAt) * 1000)),
            "deviceSampleClock": "unavailable",
            "hasHeart": String(hr != nil)
        ])
        #endif
        kcal = metrics.kcal
        if hr != nil { lastHeartAt = now }
        if let beat = info.heartRate, (1...250).contains(beat),
           info.runState == nil || info.runState == 1 {
            recapBeats.append(SportRecapMath.Beat(at: info.receivedAt, bpm: beat, segment: recapSegment))
        } else {
            recapSegment += 1
        }
        if metrics.calorieCorrection != nil {
            Self.log.notice("session energy corrected by cumulative device report")
        }
        // A zero on the sport report is the sensor still locking, not a loose strap.
        // Tighten waits for the acquire window (or a dropout after a real lock).
        wrist = Self.wrist(from: SportWristMath.face(
            runState: info.runState, heartRate: hr, hadHeart: lastHeartAt != nil,
            seekingFor: now.timeIntervalSince(seekBeganAt ?? now),
            silentFor: lastHeartAt.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude))
        if hr != nil {
            Self.log.notice("session receipt count=\(self.metrics.sampleCount) mode=\(self.session?.mode.rawValue ?? -1)")
        }
        pushIsland()
    }

    private static func wrist(from face: SportWristMath.Face) -> Wrist {
        switch face {
        case .reaching: return .reaching
        case .live: return .live
        case .noContact: return .noContact
        case .paused: return .paused
        }
    }

    private func interruptMetrics() {
        recapSegment += 1
        heartEvidence.interrupted()
        energyEvidence.interrupted()
        metrics = metrics.interrupted()
        hr = nil; hrAt = nil
        lastHeartAt = nil
        seekBeganAt = nil
    }

    // MARK: the island

    /// 0…1 · where the heart sits between rest and the profile's maximum. The screen and the
    /// island read the same number, so they cannot disagree about how hard this is.
    var effort: Double {
        guard let hr = liveHR else { return 0 }
        let span = Double(max(60, hrMax - 60))
        return min(1, max(0, (Double(hr) - 60) / span))
    }

    /// What the Dynamic Island and the Lock Screen are told right now.
    private func islandState() -> SessionAttributes.ContentState {
        SessionAttributes.ContentState(
            heartRate: liveHR,
            kcal: Int(kcal.rounded()),
            startedAt: session?.startedAt ?? Date(),
            live: heartFreshness == .live && liveHR != nil,
            effort: effort,
            note: islandNote,
            energyEstimated: caloriesAreEstimated,
            energyAvailable: hasCalories)
    }

    /// One short line, or nothing while it is simply running. The island has room for the
    /// numbers or for a sentence, never both, so silence is the good state.
    private var islandNote: String? {
        if opening { return L("OPENING ON THE BAND") }
        if let delayedHeartNote { return delayedHeartNote }
        switch wrist {
        case .live:      return session?.joined == true && caloriesAreEstimated ? L("ESTIMATE SINCE JOIN") : nil
        case .reaching:  return L("READING HEART RATE")
        case .noContact: return L("NO CONTACT · TIGHTEN THE BAND")
        case .offline:   return L("BAND OFFLINE · STILL TIMING")
        case .paused:    return L("PAUSED ON THE BAND")
        case .off:       return L("TIMING · THE WRIST IS NOT BEING READ")
        }
    }

    private func pushIsland(force: Bool = false) {
        guard session != nil else { return }
        SessionActivity.update(islandState(), force: force)
    }

    // MARK: the fold

    /// The line the panel carries when the band refused the mode: no session, one sentence.
    func refusalWidget(_ s: Session, line: String) -> PanelWidget {
        PanelWidget(type: .text, title: L("SPORT MODE"), tag: .move,
                    sentence: L("The band did not open %@. Nothing was started.", s.mode.displayName),
                    footer: line.uppercased(), action: nil, accentOverride: NB.ember1, data: .none)
    }

    private func summaryWidget(_ s: Session, seconds: Int, closed: Bool) -> PanelWidget {
        let minutes = max(1, seconds / 60)
        let hero = seconds >= 3600
            ? String(format: "%dH%02dM", seconds / 3600, (seconds % 3600) / 60)
            : "\(minutes) MIN"
        let recap = lastRecap
        let avg = recap?.avgHR.map { "\($0)" } ?? (averageHR.map { "\($0)" } ?? Fmt.dash)
        let peak = recap?.peakHR.map { "\($0)" } ?? (peakHR.map { "\($0)" } ?? Fmt.dash)
        let burned = hasCalories ? "\(caloriesAreEstimated ? "≈" : "")\(Int(kcal.rounded()))" : Fmt.dash
        let conclusion = recap.map { L($0.conclusion) } ?? L("No heart-rate record.")
        let sentence = L("%d min · avg %@ bpm · %@ kcal", minutes, avg, burned)
        var w = PanelWidget(
            type: .workout,
            title: L("SESSION · %@", s.mode.displayName),
            tag: .move,
            sentence: conclusion + " · " + (s.joined && caloriesAreEstimated
                ? sentence + " · " + L("ESTIMATE SINCE JOIN") : sentence),
            footer: closed ? L("SAVED ON THE BAND · %@ → %@", Fmt.clock(s.startedAt), Fmt.clock(Date()))
                           : L("BAND DID NOT CLOSE IT · CHECK THE WRIST"),
            action: nil,
            hero: hero,
            data: .rows([
                .init(label: L("AVG HR"), value: avg, spark: recap.flatMap { $0.curve.count > 1 ? $0.curve : nil }),
                .init(label: L("PEAK"), value: peak),
                .init(label: energyLabel, value: "\(burned) KCAL"),
                .init(label: L("AEROBIC"), value: recap.flatMap { $0.hasZones ? "\($0.aerobicMinutes) MIN" : nil } ?? Fmt.dash),
                .init(label: L("ANAEROBIC"), value: recap.flatMap { $0.hasZones ? "\($0.anaerobicMinutes) MIN" : nil } ?? Fmt.dash),
            ]))
        if !closed { w.accentOverride = NB.ember1 }
        return w
    }

    private func rememberRecap(_ s: Session, seconds: Int) {
        let rest = DataStore.shared.today.nightInputs?.rhr.map { Int($0.rounded()) }
        let math = SportRecapMath.recap(beats: recapBeats, restHR: rest, maxHR: hrMax, seconds: seconds)
        let loadBefore = Band.allowsSeed ? DataStore.shared.today.trainingLoad : nil
        if Band.allowsSeed {
            DataStore.shared.applySeedSessionLoad(delta: math.loadDelta, zones: math.zoneMinutes)
        }
        let recap = SessionRecap(
            title: s.mode.displayName,
            startedAt: s.startedAt,
            endedAt: Date(),
            seconds: seconds,
            avgHR: math.avgHR,
            peakHR: math.peakHR,
            kcal: kcal,
            caloriesEstimated: caloriesAreEstimated,
            curve: math.curve,
            zoneMinutes: math.zoneMinutes,
            aerobicMinutes: math.aerobicMinutes,
            anaerobicMinutes: math.anaerobicMinutes,
            conclusion: math.conclusion.rawValue,
            sessionID: s.id,
            ownerUserID: lifetime?.account,
            loadBefore: loadBefore,
            loadAfter: Band.allowsSeed ? DataStore.shared.today.trainingLoad : nil,
            curvePoints: math.curvePoints, observedSeconds: math.observedSeconds,
            hasCalories: hasCalories, restHR: rest, maxHR: hrMax)
        lastRecap = recap
        guard Band.allowsSeed else {
            SportRecapStore.shared.record(recap)
            return
        }
        if let data = try? JSONEncoder().encode(recap) {
            UserDefaults.standard.set(data, forKey: "nb.lastSportRecap")
        }
    }

    private static func restoreSeedRecap() -> SessionRecap? {
        guard Band.allowsSeed,
              let data = UserDefaults.standard.data(forKey: "nb.lastSportRecap") else { return nil }
        return try? JSONDecoder().decode(SessionRecap.self, from: data)
    }

    // MARK: DEBUG · a session on a simulator

    /// `SIMCTL_CHILD_NB_DEBUG_SESSION=1` (or a mode number) opens a session on home with no
    /// band, and plays a wrist that climbs to a working rate — the only way to look at this
    /// screen with numbers on it without going for a run.
    static var debugFakeWrist: Bool {
        #if DEBUG
        return Band.allowsSeed && ProcessInfo.processInfo.environment["NB_DEBUG_SESSION"] != nil
        #else
        return false
        #endif
    }

    #if DEBUG
    func debugAutoStart(profile: Profile, weightKg: Double?) {
        guard Band.allowsSeed, let raw = ProcessInfo.processInfo.environment["NB_DEBUG_SESSION"], session == nil else { return }
        let mode = SportModeCatalog.modes.first { "\($0.rawValue)" == raw }
            ?? SportModeCatalog.modes.first { $0.rawValue == 1 }!
        begin(mode, profile: profile, weightKg: weightKg)
        if ProcessInfo.processInfo.environment["NB_DEBUG_SESSION_OPEN"] == "1" {
            opening = true
        }
        if let refuse = ProcessInfo.processInfo.environment["NB_DEBUG_SESSION_REFUSE"], !refuse.isEmpty {
            refusal = refuse == "1" ? L("The band refused this mode.") : refuse
        }
    }
    #endif

    private func fakeWrist() async {
        guard Band.allowsSeed else { return }
        #if DEBUG
        if let pin = ProcessInfo.processInfo.environment["NB_DEBUG_SESSION_WRIST"], !pin.isEmpty {
            switch pin {
            case "off": wrist = .off
            case "nocontact": wrist = .noContact
            case "offline": wrist = .offline
            case "paused": wrist = .paused
            default: wrist = .reaching
            }
            while !Task.isCancelled, session != nil {
                try? await Task.sleep(for: .seconds(30))
            }
            return
        }
        #endif
        wrist = .reaching
        try? await Task.sleep(for: .seconds(1))
        var beat = 96.0
        while !Task.isCancelled, session != nil {
            let t = Date().timeIntervalSince(session?.startedAt ?? Date())
            let target = 118 + 40 * (1 - exp(-t / 60)) + 8 * sin(t / 9)
            beat += (target - beat) * 0.3 + Double.random(in: -1.5...1.5)
            accept(SportLiveInfo(heartRate: Int(beat.rounded())))
            try? await Task.sleep(for: .milliseconds(1000))
        }
    }
}
