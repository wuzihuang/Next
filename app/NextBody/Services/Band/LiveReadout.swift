import Foundation
import os

/// App-owned heart stream. Foreground demand follows the panel; background collection
/// retains the existing stream while consent, account, binding and sensor ownership allow.
/// Stress remains available in the foreground and never inserts a new background test.
@MainActor
final class LiveReadout: ObservableObject {
    static let shared = LiveReadout()
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "live")

    /// What the panel is allowed to say about itself. `offline` is the link, `noContact` is
    /// the wrist — they are two different sentences and never drawn the same way.
    enum Phase: Equatable {
        /// Nothing is running: the panel falls back to the last tick, as it always did.
        case off
        case offline
        /// The command went out; the band has not judged contact yet.
        case reaching
        case live
        case noContact
        /// The stress test holds the sensor. The heart rate on screen is the one from just
        /// before it, ageing — which is why this is its own phase and not `live`.
        case stress
    }

    /// The one place the cadence is written down.
    enum Cadence {
        /// How long the first heart rates get before the stress test interrupts them. Short
        /// enough that a user who lingers sees a live stress number, long enough that the
        /// beat is on screen first — the beat is what tells them the band is awake.
        static let firstStress: TimeInterval = 20
        /// Between stress tests after that. The band's own auto-monitoring runs every half
        /// hour; this cadence only exists while someone is watching.
        static let stressEvery: TimeInterval = 300
        /// A live number older than this is not live any more: the panel drops back to the
        /// stored tick rather than leaving a stale beat on screen.
        static let liveWindow: TimeInterval = 15
        /// After a refused or failed command, before trying again.
        static let retry: TimeInterval = 3
        /// What the band gets between the heart test being stopped and the stress test being
        /// started. The stop is a command, not an instant — see `readStress`.
        static let settle: TimeInterval = 1.2
        /// The longest a single heart-rate stream is left open before it is reopened. The
        /// SDK ends its own test eventually; this is the ceiling if it does not.
        static let heartRun: TimeInterval = 600
    }

    @Published private(set) var phase: Phase = .off
    /// The band's last reported rate and the instant it reported it.
    @Published private(set) var hr: Int?
    @Published private(set) var hrAt: Date?
    /// The last completed stress test. Kept for the whole session — a stress number is a
    /// one-shot measurement, and five minutes old is what it is, not a dash.
    @Published private(set) var stress: Int?
    @Published private(set) var stressAt: Date?
    /// 0…100 while the stress test runs, nil the rest of the time. The band's own count —
    /// 19 s of it — so the panel can say how far in it is instead of holding one word for
    /// twenty seconds. ⚠️ Never a tween: if the band stops counting, so does this.
    @Published private(set) var stressProgress: Int?

    private var running = false
    private var background = false
    private var sessionOwner: BandLivePolicy.Owner?
    private var heartDeadline: Date?
    private var receivedSamples = 0

    static var currentOwner: BandLivePolicy.Owner? {
        guard let account = SupabaseClient.currentUserIdSnapshot(),
              let binding = BoundBand.identifier, !binding.isEmpty else { return nil }
        return BandLivePolicy.Owner(account: account, binding: binding)
    }

    private var acceptsSample: Bool {
        !Task.isCancelled && sessionOwner != nil && sessionOwner == Self.currentOwner
            && ConsentStore.shared.granted && Band.live.state == .connected
            && LiveSessionStore.shared.session == nil && !LiveSessionStore.shared.opening
    }

    /// Only a recently received sample in this exact account/binding can prove warm readiness.
    func hasRecentReceipt(maxAge: TimeInterval) -> Bool {
        guard acceptsSample, let hrAt else { return false }
        let age = Date().timeIntervalSince(hrAt)
        return BandReadinessReceiptPolicy.canReuse(requested: true,
            connected: Band.live.state == .connected,
            exclusive: BandLiveLifecycle.shared.hasExclusiveOperation,
            ownerMatches: acceptsSample, age: age, maxAge: maxAge)
    }

    func setBackground(_ value: Bool) {
        background = value
        if !value, let heartDeadline, Date() >= heartDeadline { bandTask?.cancel() }
    }
    /// Set when the band answers "no such test". A capability read says the same thing, but
    /// only the attempt is authoritative — and once it has answered, the cadence drops it
    /// rather than asking every three seconds for the life of the process.
    private var heartUnsupported = false
    private var stressUnsupported = false
    /// Whether the last stress test got an answer of any kind, as opposed to being cut short.
    private var stressAnswered = false
    /// Consecutive stress tests that got no answer, for the backoff.
    private var stressMisses = 0
    /// The one child task talking to the band right now — a heart stream or a stress test.
    /// Held here so `standDown` can end it from outside the session's own loop.
    private var bandTask: Task<Void, Never>?
    /// While this is up the loop keeps its hands off the band. Counted, not a flag: two
    /// pulls in a row must not have the first one's release let the readout back in.
    private var suspended = 0

    /// The heart rate, but only while it is still now. Everything on screen reads this and
    /// never `hr` directly.
    var liveHR: Int? {
        guard let hr, let hrAt, Date().timeIntervalSince(hrAt) < Cadence.liveWindow else { return nil }
        return hr
    }

    /// The stress number this session measured — kept for as long as the session lasts, and
    /// gone with it. Older than this session is the library's business, not the panel's.
    var liveStress: Int? { stressAt == nil ? nil : stress }

    /// Whether the panel is showing the band rather than the library.
    var isLive: Bool { liveHR != nil || phase == .stress }

    /// Held by BandLiveLifecycle for the current account and device.
    func run() async {
        // One session per process. Two would fight over the same command channel, and the
        // second one's `stop` would end the first one's test.
        guard !running, let owner = Self.currentOwner, ConsentStore.shared.granted else { return }
        sessionOwner = owner
        running = true
        receivedSamples = 0
        heartUnsupported = false
        stressUnsupported = false
        Self.log.notice("stream start background=\(self.background, privacy: .public)")
        defer {
            Self.log.notice("stream stop samples=\(self.receivedSamples, privacy: .public)")
            sessionOwner = nil
            running = false
            phase = .off
            // ⚠️ The numbers are dropped with the session on purpose. Kept, they would
            // reappear on the next entry as "now" for a wrist that has since moved.
            hr = nil; hrAt = nil
            stress = nil; stressAt = nil
        }

        var nextStress = Date().addingTimeInterval(Cadence.firstStress)
        while !Task.isCancelled, !heartUnsupported, acceptsSample {
            guard Band.live.state == .connected else {
                phase = .offline
                hr = nil; hrAt = nil
                try? await Task.sleep(for: .seconds(Cadence.retry))
                continue
            }
            // F3 §06 · a day pull holds the same command channel, and it is the one that
            // must not be dropped — it is the day itself. While it has the band the readout
            // keeps its hands off; talking over it corrupts its reply rather than failing.
            if suspended > 0 {
                // Nothing is being measured, so the panel says so: STANDBY over the tick's
                // own age. Holding the last beat here would print a number from before the
                // pull as if the wrist were still being read.
                phase = .off
                hr = nil; hrAt = nil
                try? await Task.sleep(for: .milliseconds(300))
                continue
            }
            if stressDue(nextStress) {
                stressAnswered = false
                await hold { await self.readStress() }
                // A test that was cut short, or refused because the band was still winding
                // down the heart test, is not a reading. Only an answer buys the full
                // cadence; a miss comes back sooner, backing off so a band that is busy for
                // its own reasons is not asked every three seconds for the rest of the session.
                if stressAnswered {
                    stressMisses = 0
                    nextStress = Date().addingTimeInterval(Cadence.stressEvery)
                } else {
                    stressMisses += 1
                    let backoff = Cadence.retry * pow(2, Double(stressMisses - 1))
                    nextStress = Date().addingTimeInterval(min(Cadence.stressEvery, backoff))
                }
                continue
            }
            // The heart stream stays open until the stress test comes due — or, if this
            // firmware has none, until the SDK ends its own test and the loop reopens it.
            await hold(until: stressUnsupported ? nil : nextStress) { await self.consumeHeart() }
        }
    }

    /// F3 §06 · everything that talks to the band goes through here: exactly one child task
    /// at a time, ended by the deadline, by `standDown`, or with the session.
    /// ⚠️ Unstructured on purpose — the task has to be cancellable from outside this loop —
    /// so the cancellation handler carries lifecycle revocation into the SDK stream.
    private func hold(until deadline: Date? = nil, _ work: @escaping @MainActor () async -> Void) async {
        let task = Task { @MainActor in await work() }
        bandTask = task
        heartDeadline = deadline
        let timer = deadline.map { at in
            Task {
                let seconds = min(Cadence.heartRun, max(0, at.timeIntervalSinceNow))
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, !self.background else { return }
                task.cancel()
            }
        }
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        timer?.cancel()
        bandTask = nil
        heartDeadline = nil
        await drainNativeStop()
    }

    /// Take the band away from the readout for the length of `work`. The day pull calls this
    /// around itself: the open test is stopped first and awaited, so the pull's first command
    /// goes out to a band that is not in the middle of anything.
    func standDown<T>(_ work: () async -> T) async -> T {
        suspended += 1
        defer { suspended -= 1 }
        let held = bandTask
        held?.cancel()
        await held?.value
        await drainNativeStop()
        return await work()
    }

    /// AsyncStream termination schedules the SDK stop onto main; cross that FIFO boundary
    /// before a new consumer installs its callback or sends its first command.
    private func drainNativeStop() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Only the band's own answer takes the stress test off the cadence.
    /// ⚠️ Deliberately NOT gated on `capabilities.stress`. That flag comes from a guessed bit
    /// position in `deviceFuctionData` (VeepooBand.readCapabilities) — the same kind of guess
    /// that read `.unsupported` on real firmware and greyed out a working auto-measure row.
    /// A gate built on it silently means the command is never sent even once, which is exactly
    /// the shape of "STRESS is always ——". The test itself answers `noFunction` when there is
    /// none, and that answer — not a guessed bit — is what sets `stressUnsupported`.
    private func stressDue(_ at: Date) -> Bool {
        guard !stressUnsupported, !background else { return false }
        return Date() >= at
    }

    // MARK: heart · the continuous one

    /// Publish every rate the band reports for as long as the stream is open. Returning —
    /// or being cancelled — terminates it, and each `BandService` stops the test in its
    /// `onTermination`; revoking collection always stops the physical test.
    private func consumeHeart() async {
        phase = .reaching
        do {
            for try await progress in Band.live.measureHeartRate() {
                if !acceptsSample { return }
                switch progress {
                case .waitingForContact:
                    phase = .reaching
                case .contact:
                    phase = .live
                case .measuring(_, let partial, _):
                    guard let beat = partial?.heartRate, beat > 0 else { continue }
                    acceptHeart(beat)
                case .lostContact:
                    // 06 rule 07 ·「我们需要你动一下」, never "you failed". The number goes with
                    // the contact: a rate from before the wrist moved is not a rate now.
                    phase = .noContact
                    hr = nil; hrAt = nil
                case .finished(.heartRate(let beat, _, _)):
                    if beat > 0 { acceptHeart(beat) }
                    // The SDK closes its own test after a while. The loop above reopens it.
                    return
                case .finished, .failed:
                    return
                }
            }
        } catch BandError.unsupported {
            // No heart-rate test on this firmware: there is nothing to run, and reopening it
            // every three seconds is a flat band for no reading. The session ends here and
            // the panel goes back to the stored tick.
            heartUnsupported = true
            phase = .off
        } catch {
            BandLog.shared.record("liveReadout.heart", error: error)
            phase = .offline
            try? await Task.sleep(for: .seconds(Cadence.retry))
        }
    }

    // MARK: stress · the inserted one

    private func acceptHeart(_ beat: Int) {
        guard acceptsSample else { return }
        let now = Date()
        receivedSamples += 1
        Self.log.notice("sample received count=\(self.receivedSamples, privacy: .public) at=\(now.timeIntervalSince1970, privacy: .public) background=\(self.background, privacy: .public)")
        hr = beat
        hrAt = now
        phase = .live
        DataStore.shared.applyLiveBodyBattery(
            heartRate: beat,
            stress: liveStress,
            at: now
        )
    }

    private func readStress() async {
        phase = .stress
        // The heart test was stopped a moment ago, and `veepooSDKTestHeartStart(false)` is a
        // command going out on the main queue — the band has not necessarily finished winding
        // the sensor down when this line runs. A real HOOP took the stress test anyway
        // (device log: state 5 came straight back, never `deviceBusy`), so this is insurance
        // and not a fix for anything observed. It is the band's beat, not the screen's.
        try? await Task.sleep(for: .seconds(Cadence.settle))
        guard acceptsSample, !background else { return }
        Self.log.notice("stress test due · asking the band")
        stressProgress = 0
        defer { stressProgress = nil }
        do {
            let value = try await Band.live.measureStress { [weak self] done in
                guard let self, self.acceptsSample else { return }
                self.stressProgress = done
            }
            guard acceptsSample else { return }
            stressAnswered = true
            Self.log.notice("stress sample received")
            guard value > 0 else { return }
            stress = value
            stressAt = Date()
            DataStore.shared.applyLiveBodyBattery(
                heartRate: liveHR,
                stress: value,
                at: stressAt ?? Date()
            )
        } catch is CancellationError {
            // The day pull took the band. Not an answer, and not the band's fault.
            Self.log.notice("stress cut short by a day pull")
        } catch BandError.unsupported {
            // The band itself says there is no stress test on this firmware. The only
            // authority on that, and the only thing that stops us asking again.
            Self.log.notice("stress: this HOOP has no stress test")
            stressUnsupported = true
            stressAnswered = true
        } catch BandError.busy {
            // Still winding down, or measuring something of its own. Not a refusal —
            // the backoff asks again rather than waiting out the whole cadence.
            Self.log.notice("stress ← device busy")
        } catch {
            // A refusal is an answer: OFF WRIST or LOW BATTERY will say the same thing three
            // seconds from now, and asking again that fast is the band's battery for nothing.
            Self.log.error("stress ← \(String(describing: error), privacy: .public)")
            BandLog.shared.record("liveReadout.stress", error: error)
            stressAnswered = true
        }
    }
}
