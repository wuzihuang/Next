import AVFoundation
import Foundation

/// 05 · the dock's middle key. The listening state had a level meter and no microphone behind
/// it — the wave animated, the tap ended, and nothing had been recorded. This is the missing
/// half: it records while the key is lit and hands back one file.
///
/// ⚠️ 16 kHz mono. `asr` caps the clip at 2 MB and qwen3-asr-flash wants speech, not fidelity;
/// at this rate a minute of audio is well inside the ceiling, which is the same minute the
/// board allows.
@MainActor
final class SpeechCapture: NSObject, ObservableObject {
    static let shared = SpeechCapture()

    @Published private(set) var recording = false
    private var recorder: AVAudioRecorder?

    /// Returns false when the microphone was refused. The caller drops back to idle rather
    /// than showing a wave over a microphone that is not on — a listening animation with
    /// nothing behind it is the bug this file exists to fix.
    func start() async -> Bool {
        guard await Self.permission() else { return false }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("nb-\(UUID().uuidString).m4a")
            let rec = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            // ⚠️ `record()` returns a Bool and ignoring it was the very bug this file claims to
            // fix. On the simulator CoreAudio refuses to start the input server — 0x10004003,
            // then kAudioDevicePropertyIOStoppedAbnormally — and with the result thrown away the
            // dock lit its wave over a microphone that never opened. A false here is the same
            // answer as a refused permission: stay idle.
            guard rec.record() else {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                try? FileManager.default.removeItem(at: url)
                return false
            }
            recorder = rec
            recording = true
            return true
        } catch {
            recording = false
            return false
        }
    }

    /// Stops and hands back the clip. The caller owns the file and deletes it once the
    /// transcript is back — the audio never outlives the turn it belongs to.
    func stop() -> URL? {
        guard let rec = recorder else { return nil }
        rec.stop()
        recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return rec.url
    }

    func discard() {
        if let url = stop() { try? FileManager.default.removeItem(at: url) }
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
