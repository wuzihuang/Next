import Foundation

enum AIFreshnessStatus: String, Codable, Sendable {
    case ready, pending, timeout, offline, failed
    case notRequested = "not_requested"
    case cancelled
}

enum AIFreshnessPolicy {
    static func requiresRefresh(question: String, pending: Int?) -> Bool {
        guard let pending else { return true }
        if pending > 0 { return true }
        let text = question.lowercased()
        return ["now", "today", "latest", "just", "current", "刚", "今天", "现在", "最新", "目前"].contains { text.contains($0) }
    }

    /// An unstructured worker lets the deadline return even when an underlying SDK/network
    /// operation ignores cancellation. The worker must check cancellation between effects.
    @MainActor static func prepare(budget: Duration = .seconds(3),
        operation: @escaping @MainActor @Sendable () async -> AIFreshnessStatus) async -> AIFreshnessStatus {
        var finished: AIFreshnessStatus?
        let task = Task { @MainActor in finished = await operation() }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        while clock.now < deadline {
            if Task.isCancelled { task.cancel(); return .cancelled }
            if let finished { return finished }
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { task.cancel(); return .cancelled }
        }
        if let finished { return finished }
        task.cancel()
        return .timeout
    }
}
