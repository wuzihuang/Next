import Foundation

/// F3 §06 · THE QUEUE. Five boards each wrote a version of this; here it exists once.
///
/// One in-process serial queue. The number of native commands in flight is always exactly
/// one — the band's protocol cannot interleave, and a second command sent while the first is
/// still answering does not fail loudly, it corrupts the first one's reply.
///
/// P0 is something the user just pressed, P1 is a page that opened, P2 is background sync.
/// A higher priority jumps to the head of the queue but never interrupts the command already
/// in flight: cancelling mid-command is what leaves the band in a state nothing can read.
actor HoopQueue {
    enum Priority: Int, Comparable {
        /// The user pressed something: start a test, write a setting, start a firmware update.
        case p0 = 0
        /// A page opened: read version, read capabilities, list settings, read a day.
        case p1 = 1
        /// Background: pulling origin data.
        case p2 = 2

        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    struct Job {
        let id = UUID()
        let priority: Priority
        let name: String
        let run: () async throws -> Void
    }

    private var pending: [Job] = []
    private var inFlight: Job?
    private var draining = false

    /// The name is what shows up in a sync_runs row when something goes wrong.
    func enqueue(_ name: String, priority: Priority = .p1,
                 _ run: @escaping () async throws -> Void) {
        let job = Job(priority: priority, name: name, run: run)
        // Stable insert: same priority keeps arrival order, higher priority goes in front of
        // everything of lower priority but behind its own peers.
        let index = pending.firstIndex { $0.priority > priority } ?? pending.count
        pending.insert(job, at: index)
        Task { await drain() }
    }

    /// Enqueue and wait for this one job's result.
    func run<T>(_ name: String, priority: Priority = .p1,
                _ body: @escaping () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(name, priority: priority) {
                do { continuation.resume(returning: try await body()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    var depth: Int { pending.count + (inFlight == nil ? 0 : 1) }
    var current: String? { inFlight?.name }

    /// Dropping everything that has not started. The one in flight is left alone on purpose.
    func cancelPending() { pending.removeAll() }

    private func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }

        while !pending.isEmpty {
            let job = pending.removeFirst()
            inFlight = job
            do {
                try await job.run()
            } catch {
                // A failed command does not stop the queue: the next page still needs its read.
                BandLog.shared.record(job.name, error: error)
            }
            inFlight = nil
        }
    }
}

/// Enough of a trail to answer "why did the band go quiet" without a debugger.
final class BandLog: @unchecked Sendable {
    static let shared = BandLog()
    private let lock = NSLock()
    private(set) var lines: [String] = []

    func record(_ name: String, error: Error? = nil) {
        lock.lock(); defer { lock.unlock() }
        let stamp = ISO8601DateFormatter().string(from: Date())
        lines.append("\(stamp) \(name)\(error.map { " → \($0.localizedDescription)" } ?? "")")
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
    }
}
