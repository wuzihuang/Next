import SwiftUI
import UIKit
import os

/// 14 · LIVE SESSION · the one sport session the band is running, held for as long as it
/// runs. Picked on `SportModeView`; from the tap on, it lives here: the home screen's panel
/// grows over everything (`LiveSessionTakeover`) at once, while the band is still being
/// asked — a refusal folds the screen back with the reason, an answer lets it run.
///
/// Three numbers and nothing else: the clock (the phone's — `startedAt` is the tap), the
/// heart rate and the burn. Both come off the band's own sport report (`sportLiveInfo`),
/// which the firmware pushes every second while a mode is open; the heart *test* is
/// refused as busy for exactly that reason. A firmware that carries no report falls back
/// to that test anyway, and if that is refused too the clock runs alone and says so.
/// Nothing here is written anywhere: the band keeps its own record, and the phone's three
/// numbers fold back into the panel as one widget when the session ends.
@MainActor
final class LiveSessionStore: ObservableObject {
    static let shared = LiveSessionStore()
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "session")

    struct Session: Equatable {
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
    enum Wrist: Equatable { case off, reaching, live, noContact, offline }

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
    /// Kilocalories since the start — the band's own count when it reports one, otherwise
    /// integrated here from the heart rate.
    @Published private(set) var kcal: Double = 0
    @Published private(set) var stopping = false
    @Published private(set) var errorLine: String?

    /// Every rate the band reported this session, for the average and the peak at the end.
    private var samples: [Int] = []
    private var burnAt: Date?
    private var bandCounts = false
    private var weightKg = 70.0
    private var age = 34
    private var male = true
    private var openTask: Task<Void, Never>?
    /// ⚠️ Owned by the store, not by the screen. The takeover used to hold it on
    /// `scenePhase == .active`, which was right when the session was only ever on screen —
    /// but the island is the session with the phone in a pocket, so the read has to outlive
    /// the view. `bluetooth-central` in the Info.plist is what keeps the app alive for it.
    private var wristTask: Task<Void, Never>?
    private var hrMax = 190

    /// A heart rate older than this is not the wrist now. Same window as the panel's.
    static let liveWindow: TimeInterval = 15

    var liveHR: Int? {
        guard let hr, let hrAt, Date().timeIntervalSince(hrAt) < Self.liveWindow else { return nil }
        return hr
    }
    var averageHR: Int? { samples.isEmpty ? nil : samples.reduce(0, +) / samples.count }
    var peakHR: Int? { samples.max() }

    // MARK: lifecycle

    /// The tap. The session is on from here — the screen grows now, and the band is asked
    /// underneath it. `weightKg` is the latest weigh-in the day knows, for the burn.
    func begin(_ mode: SportModeOption, profile: Profile, weightKg: Double?) {
        guard session == nil else { return }
        self.weightKg = weightKg ?? 70
        self.age = profile.age
        self.male = profile.sexIsMale
        self.hrMax = profile.hrMax
        samples = []
        kcal = 0
        bandCounts = false
        hr = nil; hrAt = nil
        burnAt = nil
        errorLine = nil
        refusal = nil
        wrist = .off
        session = Session(mode: mode, startedAt: Date())
        // A workout screen that goes dark half-way through a set is a screen nobody can read.
        UIApplication.shared.isIdleTimerDisabled = true
        Self.log.notice("session on · \(mode.name, privacy: .public) #\(mode.rawValue)")

        // The island goes up with the session, not with the first heart rate: the seconds
        // are already worth showing, and a screen the user swipes away from immediately
        // should leave something behind.
        SessionActivity.start(sport: mode.name, modeRawValue: mode.rawValue, state: islandState())
        wristTask = Task { [weak self] in await self?.runWrist() }

        opening = !Self.debugFakeWrist
        guard opening else { return }
        openTask = Task { [weak self] in
            let outcome = await Self.open(mode)
            guard let self, self.session?.mode == mode else { return }
            self.opening = false
            switch outcome {
            case .opened:
                await Analytics.shared.track("SESSION_START", ["MODE": mode.rawValue, "NAME": mode.name])
            case .joined:
                self.session?.joined = true
                await Analytics.shared.track("SESSION_START", ["MODE": mode.rawValue, "NAME": mode.name, "JOINED": true])
            case .refused(let error):
                Self.log.error("session refused · \(String(describing: error), privacy: .public)")
                BandLog.shared.record("session.start", error: error)
                self.refusal = error.localizedDescription
            }
        }
    }

    private enum Open { case opened, joined, refused(Error) }

    /// Ask the band for the mode. A refusal is most often the band already running a session
    /// — one started on the wrist, or one an earlier screen never closed (device log,
    /// 2026-09-03: every open answered REFUSED while the report said `running`, 63 s in).
    /// So a refusal is followed by a close and one more try; if the band still says no but
    /// reports a session running, this screen joins that session rather than folding back
    /// over a wrist that is, in fact, being read.
    private static func open(_ mode: SportModeOption) async -> Open {
        do {
            try await Band.live.startSportMode(mode.rawValue)
            return .opened
        } catch {
            guard case BandError.rejected = error else { return .refused(error) }
            log.notice("open refused · closing what the band has and trying once more")
            try? await Band.live.stopSportMode(mode.rawValue)
            try? await Task.sleep(for: .milliseconds(600))
            do {
                try await Band.live.startSportMode(mode.rawValue)
                return .opened
            } catch {
                if let state = await Band.live.sportRunState(), state == 1 {
                    log.notice("open refused twice · the band is running a session · joining it")
                    return .joined
                }
                return .refused(error)
            }
        }
    }

    /// Close the mode on the band. Returns the widget the panel takes when the screen folds;
    /// the session itself stays up until `end()` so the fold has numbers to fold.
    func stop() async -> PanelWidget? {
        guard let session, !stopping else { return nil }
        stopping = true
        errorLine = nil
        defer { stopping = false }
        openTask?.cancel()
        var closed = true
        do {
            if !Self.debugFakeWrist { try await Band.live.stopSportMode(session.mode.rawValue) }
        } catch {
            // A refused stop is said, not hidden: the band may still be timing. The session
            // ends on the phone either way — a screen that cannot be left is worse.
            closed = false
            errorLine = error.localizedDescription
            BandLog.shared.record("session.stop", error: error)
        }
        let sec = Int(Date().timeIntervalSince(session.startedAt))
        await Analytics.shared.track("SESSION_END", [
            "MODE": session.mode.rawValue, "SEC": sec,
            "AVG_HR": averageHR ?? 0, "KCAL": Int(kcal.rounded()), "CLOSED": closed,
        ])
        return summaryWidget(session, seconds: sec, closed: closed)
    }

    /// The screen has folded back into the panel. Nothing of the session survives here.
    func end() {
        SessionActivity.end(islandState())
        wristTask?.cancel()
        wristTask = nil
        openTask?.cancel()
        openTask = nil
        session = nil
        opening = false
        wrist = .off
        hr = nil; hrAt = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: the wrist

    /// Held open by the takeover's `.task(id:)` while it is on screen and the scene is
    /// active. The band's sport report first; if it says nothing for a while, the heart
    /// test — which the firmware answers `busy` while a mode is open, in which case the
    /// report is tried again. Cancelling ends whichever is open (F1 rule 05).
    func runWrist() async {
        while !Task.isCancelled, session != nil {
            if Self.debugFakeWrist { await fakeWrist(); continue }
            guard Band.live.state == .connected else {
                wrist = .offline
                hr = nil; hrAt = nil
                try? await Task.sleep(for: .seconds(3))
                continue
            }
            // The open command has to land before the band has anything to report.
            if opening { try? await Task.sleep(for: .milliseconds(300)); continue }
            let reported = await consumeReport()
            if Task.isCancelled { break }
            if !reported { await consumeHeart() }
        }
        wrist = .off
    }

    /// The band's own report. Returns true if it said anything at all: the stream closes
    /// itself when the band stops answering, so a firmware without the report falls through
    /// to the heart test on its own.
    private func consumeReport() async -> Bool {
        wrist = .reaching
        var heard = false
        for await info in Band.live.sportLiveInfo() {
            if Task.isCancelled { break }
            heard = true
            accept(info)
        }
        if !Task.isCancelled {
            if heard { Self.log.notice("sport report went quiet") }
            else { Self.log.notice("no sport report from this firmware") }
        }
        return heard
    }

    private func consumeHeart() async {
        wrist = .reaching
        do {
            for try await progress in Band.live.measureHeartRate() {
                if Task.isCancelled { return }
                switch progress {
                case .waitingForContact: wrist = .reaching
                case .contact:           wrist = .live
                case .measuring(_, let partial, _):
                    guard let beat = partial?.heartRate, beat > 0 else { continue }
                    accept(SportLiveInfo(heartRate: beat))
                case .lostContact:
                    wrist = .noContact
                    hr = nil; hrAt = nil; burnAt = nil
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
        let now = Date()
        // The band's clock is the record. The first time it says how long it has run, the
        // screen's clock is set to it — and stays with it if the two drift apart.
        if let dur = info.durationSec, var s = session {
            let bandStart = now.addingTimeInterval(-Double(dur))
            if abs(bandStart.timeIntervalSince(s.startedAt)) > 3 {
                s.startedAt = bandStart
                session = s
            }
        }
        if let band = info.calories {
            // The band's count is the record; once it speaks, the estimate stops.
            bandCounts = true
            kcal = Double(band)
        }
        guard let beat = info.heartRate else {
            // A report with no rate is the band not reading the wrist this second.
            if info.runState != nil { wrist = .noContact }
            return
        }
        if !bandCounts, let burnAt {
            // Integrated forward from the last sample at the rate just reported; a gap longer
            // than the live window is a gap, not fifteen seconds of burn.
            let dt = min(Self.liveWindow, now.timeIntervalSince(burnAt))
            kcal += max(0, burnRate(beat)) * dt / 60
        }
        burnAt = now
        hr = beat
        hrAt = now
        wrist = .live
        samples.append(beat)
        pushIsland()
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
            live: wrist == .live && liveHR != nil,
            effort: effort,
            note: islandNote)
    }

    /// One short line, or nothing while it is simply running. The island has room for the
    /// numbers or for a sentence, never both, so silence is the good state.
    private var islandNote: String? {
        if opening { return "OPENING ON THE BAND" }
        switch wrist {
        case .live:      return nil
        case .reaching:  return "REACHING THE WRIST"
        case .noContact: return "NO CONTACT · TIGHTEN THE BAND"
        case .offline:   return "BAND OFFLINE · STILL TIMING"
        case .off:       return "TIMING · THE WRIST IS NOT BEING READ"
        }
    }

    private func pushIsland(force: Bool = false) {
        guard session != nil else { return }
        SessionActivity.update(islandState(), force: force)
    }

    /// kcal per minute from heart rate · Keytel et al. 2005, the equation with weight and
    /// age. Only for a band that reports no count of its own.
    private func burnRate(_ hr: Int) -> Double {
        let h = Double(hr), w = weightKg, a = Double(age)
        let joules = male
            ? -55.0969 + 0.6309 * h + 0.1988 * w + 0.2017 * a
            : -20.4022 + 0.4472 * h - 0.1263 * w + 0.0740 * a
        return joules / 4.184
    }

    // MARK: the fold

    /// The line the panel carries when the band refused the mode: no session, one sentence.
    func refusalWidget(_ s: Session, line: String) -> PanelWidget {
        PanelWidget(type: .text, title: "SPORT MODE", tag: .move,
                    sentence: AppLanguage.isEnglish ? "The band did not open \(s.mode.name). Nothing was started."
                                                    : "手环没有打开 \(s.mode.name)，什么都没开始。",
                    footer: line.uppercased(), action: nil, accentOverride: NB.ember1, data: .none)
    }

    private func summaryWidget(_ s: Session, seconds: Int, closed: Bool) -> PanelWidget {
        let minutes = max(1, seconds / 60)
        let hero = seconds >= 3600
            ? String(format: "%dH%02dM", seconds / 3600, (seconds % 3600) / 60)
            : "\(minutes) MIN"
        let avg = averageHR.map { "\($0)" } ?? Fmt.dash
        let burned = "\(Int(kcal.rounded()))"
        var w = PanelWidget(
            type: .workout,
            title: "SESSION · \(s.mode.name.uppercased())",
            tag: .move,
            sentence: "\(minutes) min · avg \(avg) bpm · \(burned) kcal",
            footer: closed ? "SAVED ON THE BAND · \(Fmt.clock(s.startedAt)) → \(Fmt.clock(Date()))"
                           : "BAND DID NOT CLOSE IT · CHECK THE WRIST",
            action: nil,
            hero: hero,
            data: .rows([
                .init(label: "AVG HR", value: avg),
                .init(label: "PEAK", value: peakHR.map { "\($0)" } ?? Fmt.dash),
                .init(label: "BURN", value: "\(burned) KCAL"),
            ]))
        if !closed { w.accentOverride = NB.ember1 }
        return w
    }

    // MARK: DEBUG · a session on a simulator

    /// `SIMCTL_CHILD_NB_DEBUG_SESSION=1` (or a mode number) opens a session on home with no
    /// band, and plays a wrist that climbs to a working rate — the only way to look at this
    /// screen with numbers on it without going for a run.
    static var debugFakeWrist: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["NB_DEBUG_SESSION"] != nil
        #else
        return false
        #endif
    }

    #if DEBUG
    func debugAutoStart(profile: Profile, weightKg: Double?) {
        guard let raw = ProcessInfo.processInfo.environment["NB_DEBUG_SESSION"], session == nil else { return }
        let mode = SportModeCatalog.modes.first { "\($0.rawValue)" == raw }
            ?? SportModeCatalog.modes.first { $0.rawValue == 1 }!
        begin(mode, profile: profile, weightKg: weightKg)
    }
    #endif

    private func fakeWrist() async {
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
