import AVFoundation
import Foundation

/// 05 · the dock's middle key. The listening state had a level meter and no microphone behind
/// it — the wave animated, the tap ended, and nothing had been recorded. This is the missing
/// half: it records while the key is lit and hands back one file.
///
/// ⚠️ Not `@MainActor`, and that is the whole design of this file rather than a detail.
/// `AVAudioSession.setActive` and `AVAudioRecorder.record()` are synchronous and they block for
/// as long as CoreAudio takes to answer. The first version of this ran them on the main actor,
/// and when the simulator's audio server refused to start — 0x10004003, then
/// `kAudioDevicePropertyIOStoppedAbnormally` — the log read
/// 「process main thread busy for 30.0s」: the whole UI frozen, on a tap, waiting for a
/// microphone that was never going to open. The audio work happens on its own queue; only the
/// published flag crosses back to main.
final class SpeechCapture: @unchecked Sendable, ObservableObject {
    static let shared = SpeechCapture()

    @MainActor @Published private(set) var recording = false

    private let queue = DispatchQueue(label: "nb.speech.capture")
    private var recorder: AVAudioRecorder?      // touched only on `queue`

    /// Returns false when the microphone was refused *or* would not open. The caller stays idle
    /// on a false — a listening animation with nothing behind it is the bug this file exists
    /// to fix, and a recorder that failed to start is as empty as a denied permission.
    /// 05 edge 1 · the second time iOS never asks again; the dock has to know it was refused.
    static var permissionDenied: Bool {
        if #available(iOS 17.0, *) { return AVAudioApplication.shared.recordPermission == .denied }
        return AVAudioSession.sharedInstance().recordPermission == .denied
    }
    /// 05 edge 6 · a call or an alarm took the microphone. Set once per take, read by the dock.
    @MainActor private(set) var interruptedAt: TimeInterval?
    private var startedAt = Date()
    private var interruptionObserver: NSObjectProtocol?

    func start() async -> Bool {
        guard await Self.permission() else { return false }
        await MainActor.run { self.interruptedAt = nil }
        startedAt = Date()
        interruptionObserver.map { NotificationCenter.default.removeObserver($0) }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
            let t = Date().timeIntervalSince(self.startedAt)
            Task { @MainActor in self.interruptedAt = t }
        }

        let started: Bool = await withCheckedContinuation { c in
            queue.async { [weak self] in
                guard let self else { return c.resume(returning: false) }
                let session = AVAudioSession.sharedInstance()
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("nb-\(UUID().uuidString).m4a")
                do {
                    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    let rec = try AVAudioRecorder(url: url, settings: [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 16_000,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                    ])
                    // ⚠️ `record()` returns a Bool, and ignoring it was the same bug a second
                    // time: the wave lit over a microphone that had refused to open.
                    guard rec.record() else {
                        try? session.setActive(false, options: .notifyOthersOnDeactivation)
                        try? FileManager.default.removeItem(at: url)
                        return c.resume(returning: false)
                    }
                    self.recorder = rec
                    c.resume(returning: true)
                } catch {
                    try? session.setActive(false, options: .notifyOthersOnDeactivation)
                    try? FileManager.default.removeItem(at: url)
                    c.resume(returning: false)
                }
            }
        }
        await MainActor.run { self.recording = started }
        return started
    }

    /// Stops and hands back the clip. The caller owns the file and deletes it once the
    /// transcript is back — the audio never outlives the turn it belongs to.
    /// Seconds recorded so far — 05 edge 2 treats anything under 0.6 s as a slip.
    var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }

    func stop() async -> URL? {
        interruptionObserver.map { NotificationCenter.default.removeObserver($0) }
        interruptionObserver = nil
        let url: URL? = await withCheckedContinuation { c in
            queue.async { [weak self] in
                guard let self, let rec = self.recorder else { return c.resume(returning: nil) }
                rec.stop()
                self.recorder = nil
                try? AVAudioSession.sharedInstance()
                    .setActive(false, options: .notifyOthersOnDeactivation)
                c.resume(returning: rec.url)
            }
        }
        await MainActor.run { self.recording = false }
        return url
    }

    private static func permission() async -> Bool {
        if #available(iOS 17.0, *) {
            if AVAudioApplication.shared.recordPermission == .granted { return true }
            return await AVAudioApplication.requestRecordPermission()
        }
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .granted { return true }
        return await withCheckedContinuation { c in
            session.requestRecordPermission { c.resume(returning: $0) }
        }
    }
}
