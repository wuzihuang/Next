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
    /// 05M · B·03 · the chamber's waveform: the last `Self.bars` input levels, 0…1, oldest
    /// first. Sampled from the recorder's own meter at 25 Hz on the audio queue and handed to
    /// main as one array, so the view never touches the recorder.
    @MainActor @Published private(set) var levels: [Double] = Array(repeating: 0, count: SpeechCapture.bars)
    static let bars = 34

    private let queue = DispatchQueue(label: "nb.speech.capture")
    private var recorder: AVAudioRecorder?      // touched only on `queue`
    private var meter: DispatchSourceTimer?     // touched only on `queue`
    private var pcmReader: FileHandle?           // touched only on `queue`
    private var pcmOffset: UInt64?
    private var streamTick = 0
    private var streamedBytes = 0
    private var onPCMChunk: (@Sendable (Data) -> Void)?

    /// Returns false when the microphone was refused *or* would not open. The caller stays idle
    /// on a false — a listening animation with nothing behind it is the bug this file exists
    /// to fix, and a recorder that failed to start is as empty as a denied permission.
    /// 05 edge 1 · the second time iOS never asks again; the dock has to know it was refused.
    static var permissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }
    /// 05 edge 6 · a call or an alarm took the microphone. Set once per take, read by the dock.
    @MainActor private(set) var interruptedAt: TimeInterval?
    private var startedAt = Date()
    private var interruptionObserver: NSObjectProtocol?

    func start(onPCMChunk: (@Sendable (Data) -> Void)? = nil) async -> Bool {
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
                // ⚠️ WAV, not AAC. The endpoint was proven with a 16 kHz mono WAV from
                // `afconvert` (docs/STATUS.md · asr) and the app then sent AAC in an .m4a under
                // the made-up type `audio/m4a`, which was never tried against DashScope. PCM is
                // the format that is known to transcribe; at 16 kHz × 16 bit × mono it is
                // 32 KB/s, so the 60 s cap below keeps the clip under asr's 2 MB.
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("nb-\(UUID().uuidString).wav")
                do {
                    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    let rec = try AVAudioRecorder(url: url, settings: [
                        AVFormatIDKey: Int(kAudioFormatLinearPCM),
                        AVSampleRateKey: 16_000,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                    ])
                    rec.isMeteringEnabled = true
                    // ⚠️ `record()` returns a Bool, and ignoring it was the same bug a second
                    // time: the wave lit over a microphone that had refused to open.
                    guard rec.record(forDuration: 60) else {
                        try? session.setActive(false, options: .notifyOthersOnDeactivation)
                        try? FileManager.default.removeItem(at: url)
                        return c.resume(returning: false)
                    }
                    self.recorder = rec
                    self.pcmReader = try? FileHandle(forReadingFrom: url)
                    self.pcmOffset = nil
                    self.streamTick = 0
                    self.streamedBytes = 0
                    self.onPCMChunk = onPCMChunk
                    self.startMeter(rec)
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
                self.meter?.cancel(); self.meter = nil
                rec.stop()
                self.drainPCM()
                #if DEBUG
                NSLog("NB latency · asr stream pcm_bytes=\(self.streamedBytes)")
                #endif
                try? self.pcmReader?.close()
                self.pcmReader = nil
                self.pcmOffset = nil
                self.onPCMChunk = nil
                self.recorder = nil
                try? AVAudioSession.sharedInstance()
                    .setActive(false, options: .notifyOthersOnDeactivation)
                c.resume(returning: rec.url)
            }
        }
        await MainActor.run {
            self.recording = false
            self.levels = Array(repeating: 0, count: Self.bars)
        }
        return url
    }

    /// The meter runs on `queue` with the recorder. Average power comes back in dBFS
    /// (−160 … 0); anything under −50 dB is the room, 0 dB is clipping, and the bar in
    /// between is linear so a normal speaking voice fills about two thirds of the chamber.
    private func startMeter(_ rec: AVAudioRecorder) {
        meter?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(40))
        t.setEventHandler { [weak self, weak rec] in
            guard let self, let rec, rec.isRecording else { return }
            rec.updateMeters()
            let db = Double(rec.averagePower(forChannel: 0))
            let level = min(1, max(0, (db + 50) / 50))
            self.streamTick += 1
            if self.streamTick >= 3 {
                self.streamTick = 0
                self.drainPCM()
            }
            Task { @MainActor in
                var l = self.levels
                l.removeFirst()
                l.append(level)
                self.levels = l
            }
        }
        t.resume()
        meter = t
    }

    /// AVAudioRecorder keeps writing the fallback WAV while the same PCM frames are tailed to
    /// the realtime socket. The RIFF header is skipped, and only complete Int16 samples leave.
    private func drainPCM() {
        guard let reader = pcmReader, let onPCMChunk else { return }
        do {
            if pcmOffset == nil {
                try reader.seek(toOffset: 0)
                let header = try reader.read(upToCount: 4_096) ?? Data()
                let marker = Data("data".utf8)
                guard let range = header.range(of: marker), range.upperBound + 4 <= header.endIndex else {
                    return
                }
                pcmOffset = UInt64(range.upperBound + 4)
            }
            guard let offset = pcmOffset else { return }
            try reader.seek(toOffset: offset)
            let available = try reader.readToEnd() ?? Data()
            let completeCount = available.count - available.count % MemoryLayout<Int16>.size
            guard completeCount > 0 else { return }
            let pcm = available.prefix(completeCount)
            pcmOffset = offset + UInt64(completeCount)
            #if DEBUG
            if streamedBytes == 0 {
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
                NSLog("NB latency · asr stream first_pcm ms=\(elapsedMs)")
            }
            #endif
            streamedBytes += completeCount
            onPCMChunk(Data(pcm))
        } catch {
            // The WAV remains complete and will be uploaded after release. Streaming is an
            // acceleration rail, so a transient file-tail error must never stop recording.
        }
    }

    private static func permission() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await AVAudioApplication.requestRecordPermission()
    }
}
