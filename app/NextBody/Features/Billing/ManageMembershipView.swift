import SwiftUI
import UIKit
#if canImport(RevenueCat)
import RevenueCat
#endif

/// 11E · what a subscriber sees from ME. It answers the three questions first — when it
/// renews, what it costs, what stops — and keeps leaving honest: one plain red line, no maze.
/// Apple owns the actual cancellation, so CANCEL hands over to the system sheet.
struct ManageMembershipView: View {
    var snapshot: BillingSnapshot
    var busy = false
    var message: String?
    var onClose: () -> Void
    var onKeep: () -> Void
    var onCancel: () -> Void
    var onRestore: () -> Void

    private let lime = Color(red: 239 / 255, green: 246 / 255, blue: 90 / 255)
    private let ground = Color(red: 13 / 255, green: 17 / 255, blue: 20 / 255)
    private let danger = Color(red: 1, green: 90 / 255, blue: 79 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }
            actions
            keepButton
        }
        .background {
            GeometryReader { geometry in
                ZStack {
                    ground
                    // The paywall's mass, lifted into the top corner and dimmed: the page is
                    // about terms, and the grain only says this is still the Pro room.
                    GrainMassBackground()
                        .offset(x: geometry.size.width * 0.18, y: -geometry.size.height * 0.46)
                        .opacity(0.6)
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .black, location: 0.10),
                                .init(color: .clear, location: 0.36)
                            ], startPoint: .top, endPoint: .bottom)
                        }
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0.30),
                                .init(color: .black, location: 0.75)
                            ], startPoint: .leading, endPoint: .trailing)
                        }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("membership.manage")
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                CloseMark().frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Close"))
            .accessibilityIdentifier("membership.manage.close")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            typeset(L("MEMBERSHIP"), font: "Doto-Bold", size: 12, line: 16, kern: 2.16,
                    color: .white.opacity(0.6))
                .padding(.top, 14)
            typeset("PRO\nIS ON", font: "InterTight-ExtraBold", size: 64, line: 60, kern: -3.2, color: lime)
                .padding(.top, 4)
            facts.padding(.top, 26)
            typeset(L("IF YOU CANCEL, THESE TURN OFF"), font: "Doto-Bold", size: 12, line: 16, kern: 2.16,
                    color: .white.opacity(0.6))
                .padding(.top, 30)
            typeset([L("Ask out loud, the screen draws it"),
                     L("Say what you ate, it does the math"),
                     L("Today's training and daily advice"),
                     L("Your band's display, on command")].joined(separator: "\n"),
                    font: "InterTight-Medium", size: 22, line: 32, kern: -0.44)
                .padding(.top, 10)
            typeset(keepsLine, font: "Jost-Regular", size: 15, line: 22, color: .white.opacity(0.7))
                .padding(.top, 16)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.custom("InterTight-Medium", size: 13))
                    .foregroundStyle(NB.ember1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("membership.manage.message")
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var facts: some View {
        HStack(alignment: .top, spacing: 0) {
            fact(L(snapshot.willRenew ? "NEXT RENEWAL" : "ENDS ON"),
                 snapshot.expiresAt.map(ProRenewalLine.dayText) ?? "—", font: "Doto-Bold")
            // `US$19.99` is the widest thing in the row; a size down keeps three lanes.
            fact(L(snapshot.isYearly ? "PER YEAR" : "PER MONTH"), snapshot.localizedPrice, font: "Doto-Bold", size: 22)
            fact(L("NOW"), L(snapshot.isTrial ? "Free month" : "Pro plan"),
                 font: "InterTight-SemiBold", size: 20, color: lime)
        }
    }

    private func fact(_ label: String, _ value: String, font: String, size: CGFloat = 28,
                      color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            typeset(label, font: "Doto-Bold", size: 12, line: 16, kern: 2.16, color: .white.opacity(0.6))
            typeset(value, font: font, size: size, line: 30, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keepsLine: String {
        let free = L("Band data, records and charts stay free, always.")
        guard let expires = snapshot.expiresAt, expires > Date() else { return free }
        return free + " " + L("After cancelling, Pro keeps working until %@.", ProRenewalLine.dayText(expires))
    }

    private var actions: some View {
        HStack {
            Button(action: onCancel) {
                typeset(L("Cancel subscription"), font: "Jost-Medium", size: 16, line: 22, color: danger)
                    .fixedSize()
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("membership.manage.cancel")
            Spacer()
            Button(action: onRestore) {
                typeset(L("Restore purchases"), font: "Jost-Medium", size: 16, line: 22,
                        color: .white.opacity(0.7))
                    .fixedSize()
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("membership.manage.restore")
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var keepButton: some View {
        Button(action: onKeep) {
            typeset(L("KEEP PRO"), font: "InterTight-Bold", size: 20, line: 24, kern: -0.4,
                    color: .black, alignment: .center)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .background(lime)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("KEEP PRO"))
        .accessibilityIdentifier("membership.manage.keep")
    }

    private func typeset(_ text: String, font: String, size: CGFloat, line: CGFloat,
                         kern: CGFloat = 0, color: Color = .white,
                         alignment: NSTextAlignment = .left) -> some View {
        PaywallText(text: text, fontName: font, fontSize: size, lineHeight: line,
                    kern: kern, color: UIColor(color), alignment: alignment)
    }
}

/// Binds the page to the verified health account, exactly as the paywall host does.
struct ManageMembershipHost: View {
    @ObservedObject var billing: BillingStore
    var onFinished: () -> Void
    @State private var identity: UUID?
    @State private var working = false
    /// Test Store and web subscriptions have no Apple sheet; RevenueCat's own centre is
    /// the only place those can be cancelled.
    @State private var showingStoreCenter = false

    var body: some View {
        ManageMembershipView(snapshot: billing.snapshot, busy: working || billing.busy,
                             message: billing.lastMessage, onClose: onFinished, onKeep: onFinished,
                             onCancel: { Task { await cancel() } },
                             onRestore: { Task { await restore() } })
            .onDisappear { Task { await billing.refresh() } }
            .task {
                guard !billing.usesStoreFreePreview else { return }
                identity = await billing.preparePaywall()
            }
            .sheet(isPresented: $showingStoreCenter, onDismiss: { Task { await billing.syncFromStore() } }) {
                CustomerCenterHost(billing: billing, onFinished: { showingStoreCenter = false })
            }
    }

    private func cancel() async {
        guard !working, !billing.usesStoreFreePreview else { return }
        #if canImport(RevenueCat)
        guard identity != nil, Purchases.isConfigured else { return }
        guard billing.cancelsInAppStore else { showingStoreCenter = true; return }
        working = true
        defer { working = false }
        do {
            try await Purchases.shared.showManageSubscriptions()
            await billing.syncFromStore()
        } catch {
            showingStoreCenter = true
        }
        #endif
    }

    private func restore() async {
        guard !working, let identity else { return }
        working = true
        let result = await billing.restore(expectedIdentity: identity)
        if case .failed(let line) = result { billing.lastMessage = line }
        working = false
    }
}
