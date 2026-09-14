import Foundation

enum ASRStreamResult: Sendable {
    case text(String)
    case silence
    case failed(String)
}

/// One push-to-talk WebSocket. Audio writes and the final commit share a serial queue, so the
/// commit can never overtake the last PCM chunk. Any failure is returned to AIService, which
/// keeps the WAV upload endpoint as the reliability fallback.
final class ASRStreamingSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "nb.asr.stream")
    private let task: URLSessionWebSocketTask
    private var sendQueue: [URLSessionWebSocketTask.Message] = []
    private var sending = false
    private var result: ASRStreamResult?
    private var waiter: CheckedContinuation<ASRStreamResult, Never>?
    private var closed = false
    private var idleWork: DispatchWorkItem?
    /// Idle only. Any provider event resets this. An 8 s wall clock after `finish`
    /// used to fail a stream that was still speaking, then the file path added ~20 s.
    private static let idleSeconds: TimeInterval = 20

    init(request: URLRequest) {
        task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        receiveNext()
    }

    func append(_ pcm: Data) {
        guard !pcm.isEmpty else { return }
        queue.async { [weak self] in
            self?.enqueue(.data(pcm))
        }
    }

    func finish() async -> ASRStreamResult {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .failed("STREAM_RELEASED"))
                    return
                }
                if let result {
                    continuation.resume(returning: result)
                    return
                }
                waiter = continuation
                guard let payload = try? JSONSerialization.data(withJSONObject: ["type": "finish"]),
                      let text = String(data: payload, encoding: .utf8) else {
                    complete(.failed("E_SCHEMA"))
                    return
                }
                enqueue(.string(text))
                self.armIdleClock()
            }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self, !closed else { return }
            if let payload = try? JSONSerialization.data(withJSONObject: ["type": "cancel"]),
               let text = String(data: payload, encoding: .utf8) {
                enqueue(.string(text))
            }
            complete(.failed("CANCELLED"))
        }
    }

    private func enqueue(_ message: URLSessionWebSocketTask.Message) {
        guard !closed else { return }
        sendQueue.append(message)
        sendNext()
    }

    private func sendNext() {
        guard !sending, !sendQueue.isEmpty, !closed else { return }
        sending = true
        let message = sendQueue.removeFirst()
        task.send(message) { [weak self] error in
            self?.queue.async {
                guard let self else { return }
                self.sending = false
                if let error {
                    self.complete(.failed(error.localizedDescription))
                } else {
                    self.sendNext()
                }
            }
        }
    }

    private func receiveNext() {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .success(let message):
                    self.handle(message)
                    if !self.closed { self.receiveNext() }
                case .failure(let error):
                    self.complete(.failed(error.localizedDescription))
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let value):
            data = value
        case .string(let value):
            data = Data(value.utf8)
        @unknown default:
            return
        }
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }
        if waiter != nil { armIdleClock() }
        switch type {
        case "done":
            if let text = (event["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                complete(.text(text))
            } else if event["error"] as? String == "NO_SPEECH" {
                complete(.silence)
            } else {
                complete(.failed(event["error"] as? String ?? "MODEL_UNAVAILABLE"))
            }
        case "error":
            complete(.failed(event["error"] as? String ?? "MODEL_UNAVAILABLE"))
        default:
            break
        }
    }

    private func armIdleClock() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.complete(.failed("STREAM_STALL"))
        }
        idleWork = work
        queue.asyncAfter(deadline: .now() + Self.idleSeconds, execute: work)
    }

    private func complete(_ value: ASRStreamResult) {
        guard result == nil else { return }
        idleWork?.cancel()
        idleWork = nil
        result = value
        closed = true
        sendQueue.removeAll(keepingCapacity: false)
        task.cancel(with: .normalClosure, reason: nil)
        waiter?.resume(returning: value)
        waiter = nil
    }
}
