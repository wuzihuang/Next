import SwiftUI
import UIKit

/// 11D · the page after Pro turns on. It keeps the paywall's own grain mass behind it, so
/// the purchase reads as the same room with the lights coming up rather than a new screen.
struct ProSuccessView: View {
    var snapshot: BillingSnapshot
    var onStart: () -> Void

    private let lime = Color(red: 239 / 255, green: 246 / 255, blue: 90 / 255)
    private let ground = Color(red: 13 / 255, green: 17 / 255, blue: 20 / 255)

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                headline
                renewal
                startButton
            }
            .padding(.top, max(0, 62 - geometry.safeAreaInsets.top))
            .background {
                // Opaque first: the lifted mass no longer reaches the bottom edge, and this
                // page sits over home.
                ground.ignoresSafeArea()
                GrainMassBackground()
                    // The renderer composes its mass low and right for the paywall's price.
                    // Here the words own the lower half, so the same mass is lifted above them.
                    .offset(y: -geometry.size.height * 0.26)
                    // The mass turns behind the words; the lower half fades to the paywall's
                    // ground so the headline never competes with a bright grain.
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: ground.opacity(0.85), location: 0.68),
                            .init(color: ground, location: 0.86)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("membership.success")
        .onAppear { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            typeset(L("MEMBERSHIP · ACTIVE"), font: "Doto-ExtraBold", size: 12, line: 16, kern: 2.16)
            typeset("PRO\nIS ON", font: "InterTight-ExtraBold", size: 92, line: 84, kern: -4.6, color: lime)
            typeset(L("You're subscribed."), font: "InterTight-SemiBold", size: 24, line: 32)
                .padding(.top, 10)
            typeset(L("Ask out loud, say what you ate, plan today's training — it's all yours now."),
                    font: "Jost-Regular", size: 15, line: 22, color: .white.opacity(0.62))
        }
        .padding(.horizontal, 16)
    }

    private var renewal: some View {
        HStack(alignment: .center, spacing: 12) {
            typeset(ProRenewalLine.text(for: snapshot), font: "Doto-SemiBold", size: 12, line: 16,
                    kern: 2.16, color: .white.opacity(0.62))
            Spacer(minLength: 0)
            typeset(L(snapshot.isYearly ? "%@ / YEAR" : "%@ / MONTH", snapshot.localizedPrice), font: "Doto-SemiBold", size: 12, line: 16,
                    kern: 2.16, color: .white.opacity(0.62), alignment: .right)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var startButton: some View {
        Button(action: onStart) {
            typeset(L("GET STARTED"), font: "InterTight-Bold", size: 20, line: 24, kern: -0.4,
                    color: .black, alignment: .center)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .background(lime)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("GET STARTED"))
        .accessibilityIdentifier("membership.success.start")
    }

    private func typeset(_ text: String, font: String, size: CGFloat, line: CGFloat,
                         kern: CGFloat = 0, color: Color = .white,
                         alignment: NSTextAlignment = .left) -> some View {
        PaywallText(text: text, fontName: font, fontSize: size, lineHeight: line,
                    kern: kern, color: UIColor(color), alignment: alignment)
    }
}

/// The one dated line both Pro pages print. What it says follows the server row: a free
/// month, a renewal, or an end date once the subscriber has already cancelled.
enum ProRenewalLine {
    static func text(for snapshot: BillingSnapshot, now: Date = Date()) -> String {
        guard let expires = snapshot.expiresAt, expires > now else {
            return snapshot.isTrial ? L("FIRST MONTH FREE") : L("PRO PLAN")
        }
        let day = dayText(expires)
        if !snapshot.willRenew { return L("ENDS %@", day) }
        return snapshot.isTrial ? L("FIRST MONTH FREE · RENEWS %@", day) : L("RENEWS %@", day)
    }

    /// `13 OCT` — the board's dot-matrix date, the same in every language.
    static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date).uppercased()
    }
}
