import Foundation

/// Pure F1 §02 / 01-code helpers. Kept free of UIKit so NextBodySyncCore can test them.
public enum LaunchGate: Sendable {
    public static func stage(hasBoundBand: Bool, profileComplete: Bool) -> String {
        if hasBoundBand && profileComplete { return "root" }
        if hasBoundBand { return "gateOnboarding" }
        return "gateConnect"
    }

    public static func isFirstRun(hasBoundBand: Bool, profileComplete: Bool) -> Bool {
        !hasBoundBand && !profileComplete
    }

    public static func isExpiredCode(status: Int, body: String) -> Bool {
        if status == 429 { return false }
        let text = body.lowercased()
        return text.contains("otp_expired") || text.contains("token has expired")
    }
}
