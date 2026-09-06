import SwiftUI
import UserNotifications

/// F5 C4 · the notification primer. HOOP taps on edges (ADR 0019), not only last night.
/// Two buttons, Not now / Turn on. The system dialog appears only after Turn on, and once
/// refused is never shown again. Not now is not a refusal: the primer comes back the next morning.
struct NotificationPrimer: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(hex: 0xF4F4F6)
    private let lede = Color(hex: 0xA6A6AE)

    var body: some View {
        ZStack(alignment: .bottom) {
            NB.carbon.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Text(L("HOOP taps you when something changes."))
                    .font(NBFont.brand(600, 30)).tracking(-0.02 * 30).lineSpacing(4)
                    .foregroundStyle(ink)
                Text(L("Last night lands, a meal is still open, training is under, or the band goes dark."))
                    .font(NBFont.ui(300, 17)).lineSpacing(8)
                    .foregroundStyle(lede)
                Spacer().frame(height: 140)
            }
            .padding(.horizontal, 24)
            .frame(width: NB.Layout.screenWidth, alignment: .leading)

            VStack(spacing: 12) {
                LimePillButton(title: L("Turn on")) { Task { await turnOn() } }
                    .frame(width: NB.Layout.contentWidth - 16)
                Button(action: notNow) {
                    Text(L("Not now"))
                        .font(NBFont.ui(500, 15)).tracking(0.04 * 15)
                        .foregroundStyle(NB.white.opacity(0.55))
                        .frame(width: NB.Layout.contentWidth - 16, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 34)
        }
        .task { await Analytics.shared.track("NOTIF_PRIMER_SHOWN", [:]) }
    }

    private func turnOn() async {
        await Analytics.shared.track("NOTIF_PRIMER_CHOICE", ["CHOICE": "turn_on"])
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await NotificationReach.didGainAuthorization()
        onDone()
    }
    private func notNow() {
        UserDefaults.standard.set(UserDay.containing(Date()).key, forKey: NotificationPrimer.notNowKey)
        Task { await Analytics.shared.track("NOTIF_PRIMER_CHOICE", ["CHOICE": "not_now"]) }
        onDone()
    }

    static let notNowKey = "nb.notif.primer.notNowDay"

    /// Offered only while the system has never been asked, and not twice on one day.
    static func shouldOffer() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        guard s.authorizationStatus == .notDetermined else { return false }
        return UserDefaults.standard.string(forKey: notNowKey) != UserDay.containing(Date()).key
    }
}
