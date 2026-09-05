import Foundation

/// F1 §02 · after a session exists, the gate is four facts, not the last screen the
/// phone happened to be on. Band in the book + a finished About You → home. Band
/// without a profile → onboarding. No band → Connect, and a finished profile is
/// not asked again.
enum GateDecision: Sendable {
    static func stage(hasBoundBand: Bool, profileComplete: Bool) -> SessionStore.Stage {
        SessionStore.Stage(rawValue: LaunchGate.stage(hasBoundBand: hasBoundBand, profileComplete: profileComplete))
            ?? .gateConnect
    }

    /// First time through the product: no HOOP on file and About You not finished.
    static func isFirstRun(hasBoundBand: Bool, profileComplete: Bool) -> Bool {
        LaunchGate.isFirstRun(hasBoundBand: hasBoundBand, profileComplete: profileComplete)
    }

    /// GoTrue's expired OTP body is `otp_expired · Token has expired or is invalid`.
    /// Matching only "expired" AND NOT "invalid" mapped that onto a wrong code.
    static func isExpiredCode(status: Int, body: String) -> Bool {
        LaunchGate.isExpiredCode(status: status, body: body)
    }
}

/// What the server knows about this account for the gate. Weight lives on weigh_ins,
/// not on profiles; sex / height / birth_date are the About You essentials.
struct AccountGate: Sendable {
    var hasBoundBand = false
    var sex: String?
    var heightCm: Double?
    var birthDate: Date?
    var goal: Goal?
    var displayName: String?
    var weightKg: Double?

    var profileComplete: Bool { sex != nil && heightCm != nil && birthDate != nil }
    var hasAnyProfileField: Bool {
        sex != nil || heightCm != nil || birthDate != nil || !(displayName ?? "").isEmpty
    }
    var isFirstRun: Bool { GateDecision.isFirstRun(hasBoundBand: hasBoundBand, profileComplete: profileComplete) }
    var stage: SessionStore.Stage {
        GateDecision.stage(hasBoundBand: hasBoundBand, profileComplete: profileComplete)
    }
}

/// 01 rule 03 · five wrong codes lock that email for 15 minutes on this phone.
/// The server has no hook we can write; the count and the clock are per-address.
enum AuthLock {
    private static func lockKey(_ email: String) -> String {
        "nb.auth.lock.\(email.lowercased().trimmingCharacters(in: .whitespaces))"
    }
    private static func wrongKey(_ email: String) -> String {
        "nb.auth.wrong.\(email.lowercased().trimmingCharacters(in: .whitespaces))"
    }

    static func remaining(_ email: String) -> TimeInterval? {
        let until = UserDefaults.standard.double(forKey: lockKey(email))
        let left = until - Date().timeIntervalSince1970
        return left > 0 ? left : nil
    }

    static func isLocked(_ email: String) -> Bool { remaining(email) != nil }

    /// Returns true when this wrong attempt engaged the 15-minute lock.
    static func registerWrong(_ email: String) -> Bool {
        let key = wrongKey(email)
        let n = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(n, forKey: key)
        guard n >= 5 else { return false }
        UserDefaults.standard.set(Date().timeIntervalSince1970 + 15 * 60, forKey: lockKey(email))
        return true
    }

    static func clearWrongs(_ email: String) {
        UserDefaults.standard.removeObject(forKey: wrongKey(email))
    }
}

/// F1 PROFILE GAP · About You values survive a kill. Namespaced by user so a
/// sign-out cannot leak one account's draft into the next.
struct OnboardingDraft: Codable, Equatable {
    var userId: String
    var step: String
    var sex: String
    var year: Int
    var month: Int
    var day: Int
    var heightCm: Double
    var weightKg: Double
    var filled: [String]
    var synced: Bool
    var sexFromHealth: Bool
    var bornFromHealth: Bool
    var heightFromHealth: Bool
    var weightFromHealth: Bool
    var goal: String

    private static func key(_ userId: String) -> String { "nb.onboarding.draft.\(userId)" }

    static func load(userId: String) -> OnboardingDraft? {
        guard let data = UserDefaults.standard.data(forKey: key(userId)) else { return nil }
        return try? JSONDecoder().decode(OnboardingDraft.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(userId))
    }

    static func clear(userId: String) {
        UserDefaults.standard.removeObject(forKey: key(userId))
    }
}
