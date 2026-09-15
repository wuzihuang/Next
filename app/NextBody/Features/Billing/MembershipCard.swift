import SwiftUI

/// Full-screen membership card. Offer A or B; the only exit is the top-left X.
struct MembershipCard: View {
    var offer: BillingOffer
    var price: String
    var busy: Bool
    var message: String?
    var onDismiss: () -> Void
    var onStart: () -> Void
    var onRestore: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.carbon.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        CloseMark()
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Close"))
                    .accessibilityIdentifier("membership.close")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Text(L(BillingCopy.title(for: offer)))
                    .font(NBFont.ui(500, 32)).tracking(0.01 * 32)
                    .foregroundStyle(NB.text1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

                Text(L(BillingCopy.conditionKey(for: offer), price))
                    .font(NBFont.ui(300, 15)).tracking(0.02 * 15)
                    .foregroundStyle(NB.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 18) {
                    sellPoint(kicker: L("DISPLAY · CONTROL"),
                              line: L("Ask out loud — the screen draws your band, live."))
                    sellPoint(kicker: "MEALS",
                              line: L("Say what you ate — it splits the macros for you."))
                    sellPoint(kicker: L("COACH · SUGGEST"),
                              line: L("What to do today, and where you're going next."))
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)

                Spacer(minLength: 16)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(NBFont.ui(400, 13))
                        .foregroundStyle(NB.ember1)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }

                LimePillButton(title: busy ? L("STARTING…") : L(BillingCopy.cta(for: offer)),
                               enabled: !busy, action: onStart)
                    .accessibilityIdentifier("membership.start")

                Button(action: onRestore) {
                    Text(L("RESTORE PURCHASES"))
                        .font(NBFont.dot(600, 12)).tracking(0.2 * 12)
                        .foregroundStyle(NB.text3Prod)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("membership.restore")
                .padding(.top, 4)

                Text(L("Payment is through the App Store. NextBody never sees your card number."))
                    .font(NBFont.ui(300, 12))
                    .foregroundStyle(NB.white.opacity(0.38))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 22)
            }
        }
        .carbonPage()
    }

    private func sellPoint(kicker: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                .foregroundStyle(NB.lime1)
            Text(line)
                .font(NBFont.ui(400, 16))
                .foregroundStyle(NB.text1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Host that binds the store. Onboarding uses the same card with its own dismiss.
struct MembershipCardHost: View {
    @ObservedObject var billing: BillingStore
    var onFinished: () -> Void

    var body: some View {
        MembershipCard(
            offer: billing.offer,
            price: billing.snapshot.localizedPrice,
            busy: billing.busy,
            message: billing.lastMessage,
            onDismiss: {
                billing.markWelcomeSeen()
                billing.dismiss()
                onFinished()
            },
            onStart: {
                Task { await run(billing.purchase()) }
            },
            onRestore: {
                Task { await run(billing.restore()) }
            }
        )
        .task { await billing.refresh() }
    }

    private func run(_ result: BillingPurchaseResult) async {
        switch result {
        case .success:
            onFinished()
        case .cancelled:
            break
        case .unavailable:
            billing.lastMessage = L("App Store purchases are not configured on this build.")
        case .failed(let line):
            billing.lastMessage = line
        }
    }
}
