import Foundation
import os

/// ADR 0018 · a session is one continuous stretch of AI conversation across Chat and the
/// home dock. It ends when the user leaves Chat or thirty minutes pass without a turn;
/// then the server folds it into memory once. This side only hands out the id, closes
/// it, and pokes the summarizer at the moments that matter.
@MainActor
final class AISession {
    static let shared = AISession()
    static let idleSeconds: TimeInterval = 30 * 60

    private(set) var id = UUID()
    private var lastTurnAt: Date?
    private var settling = false

    /// The id to send with a turn. A stale session rolls into a new one here, not on a timer.
    func idForTurn() -> UUID {
        if let last = lastTurnAt, Date().timeIntervalSince(last) > Self.idleSeconds {
            id = UUID()
        }
        lastTurnAt = Date()
        return id
    }

    /// Leaving Chat ends the session: the server summarizes it and the next turn opens a new one.
    func endChat() {
        let closing = id
        id = UUID()
        lastTurnAt = nil
        Task { await settle(closing: closing) }
    }

    /// Foregrounding, the first turn of a day, or any other moment the app touches the AI:
    /// give the server a chance to fold idle sessions in. Cheap when nothing is due.
    func settleIfDue() {
        Task { await settle(closing: nil) }
    }

    private func settle(closing: UUID?) async {
        guard !settling, ConsentStore.shared.granted, Reachability.shared.isOnline,
              let owner = await SupabaseClient.shared.currentUserId else { return }
        settling = true
        defer { settling = false }
        var payload: [String: Any] = ["locale": AppLanguage.locale]
        if let closing { payload["close_session"] = closing.uuidString.lowercased() }
        do {
            let out = try await SupabaseClient.shared.callFunction("memory-settle", payload: payload, expectedOwner: owner)
            if let settled = out["settled"] as? [String], !settled.isEmpty {
                Logger(subsystem: "com.nextbody.hoop", category: "memory").notice("memory settled \(settled.count, privacy: .public) session(s)")
            }
        } catch {
            // A missed summary is retried the next time the app touches the AI.
            Logger(subsystem: "com.nextbody.hoop", category: "memory").error("memory settle failed: \(String(describing: error), privacy: .public)")
        }
    }
}
