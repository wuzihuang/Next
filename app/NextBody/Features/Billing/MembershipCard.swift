import SwiftUI
import UIKit
import RevenueCat

/// One native Paper layout for welcome, AI gates, and Profile. Store-free previews
/// use this same surface; only a real RevenueCat package enables production purchase.
struct MembershipCard: View {
    /// One billing period — the big figure. On the yearly plan `listPrice` is what the
    /// 80% comes off and `perMonthPrice` is the year divided by twelve.
    var amount: String
    var currency: String
    var listPrice: String? = nil
    var perMonthPrice: String? = nil
    var intro: String? = nil
    var busy = false
    var canPurchase = false
    var canRestore = false
    var preparing = false
    var preview = false
    var message: String?
    var onDismiss: () -> Void
    var onStart: () -> Void
    var onRestore: () -> Void
    var onRetry: () -> Void
    @State private var legal: LegalDocument?

    private let lime = Color(red: 239 / 255, green: 246 / 255, blue: 90 / 255)
    private enum LegalDocument: String, Identifiable {
        case terms, privacy
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView { content }
                }
                startButton
            }
            // Paper's status row is 62 pt. The real system status bar remains native.
            .padding(.top, max(0, 62 - geometry.safeAreaInsets.top))
            .background {
                GrainMassBackground()
                    // Keep the small price caption readable as bright grains rotate
                    // behind it, like the lower fade in Paper's original sky.
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.62),
                            .init(color: .black.opacity(0.65), location: 0.90),
                            .init(color: .black.opacity(0.72), location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .sheet(item: $legal) { document in
            LegalSheet(document == .terms ? .terms : .privacy)
                .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Close"))
            .accessibilityIdentifier("membership.close")
            Spacer()
            Menu {
                Button(L("RESTORE PURCHASES"), action: onRestore)
                    .disabled(!canRestore || busy)
                    .accessibilityIdentifier("membership.restore")
                Button(L("Terms of service")) { legal = .terms }
                Button(L("Privacy policy")) { legal = .privacy }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("Subscription options"))
            .accessibilityIdentifier("membership.options")
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            typeset("NextBody Pro", font: "InterTight-ExtraBold", size: 48, line: 56, kern: -1.44, color: lime)
                .accessibilityIdentifier(preview ? "membership.preview" : "membership.native")
                .padding(.top, 28)
            VStack(alignment: .leading, spacing: 22) {
                benefit("AI AGENT · ZERO TAPS", "Say what you want. Your AI agent handles it all.")
                benefit("YOUR AI COACH", "Answers, personal plans, custom features and advice tailored to you.")
                benefit("YOUR AI NUTRITION EXPERT", "Top-tier AI nutrition expertise. Understand today's meals with a personal dietary assessment.")
            }
            .padding(.top, 28)
            Spacer(minLength: 40)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.custom("InterTight-Medium", size: 13))
                    .foregroundStyle(NB.ember1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("membership.message")
                    .padding(.bottom, 12)
            }
            if preparing {
                ProgressView().tint(lime).frame(height: 68)
            } else if amount.isEmpty {
                Button(L("Try again"), action: onRetry)
                    .font(.custom("InterTight-Medium", size: 22))
                    .foregroundStyle(lime)
                    .frame(height: 68)
                    .accessibilityIdentifier("membership.retry")
            } else {
                if let listPrice {
                    // 80% OFF, and the price it comes off, struck through beside it.
                    HStack(alignment: .center, spacing: 10) {
                        typeset(L("%d%% OFF", BillingCatalog.yearlySavingsPercent), font: "Doto-Bold", size: 12,
                                line: 16, kern: 2.4, color: .black, alignment: .center)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(lime)
                            .accessibilityIdentifier("membership.savings")
                        typeset(listPrice, font: "Jost-Medium", size: 20, line: 24, color: .white.opacity(0.55),
                                strikethrough: true)
                            .fixedSize()
                            .accessibilityIdentifier("membership.listPrice")
                    }
                    .padding(.bottom, 8)
                }
                HStack(alignment: .bottom, spacing: 5) {
                    typeset(currency, font: "Jost-Medium", size: 26, line: 46)
                        .fixedSize(horizontal: true, vertical: false)
                    typeset(amount, font: "Doto-Medium", size: 72, line: 68)
                        .fixedSize(horizontal: true, vertical: false)
                    if perMonthPrice != nil {
                        typeset(L("/ year"), font: "Jost-Medium", size: 22, line: 46, color: .white.opacity(0.65))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.leading, 4)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("membership.price")
            }
            if let perMonthPrice {
                typeset(L("ONLY %@ / MONTH · CANCEL ANYTIME", perMonthPrice), font: "Doto-SemiBold", size: 12,
                        line: 16, kern: 2.4, color: lime)
                    .padding(.top, 6)
                    .accessibilityIdentifier("membership.perMonth")
            } else {
                typeset(L("A MONTH · CANCEL ANYTIME"), font: "Doto-SemiBold", size: 12, line: 16,
                        kern: 2.4, color: .white.opacity(0.65))
                    .padding(.top, 6)
            }
            if let intro {
                typeset(intro, font: "InterTight-Medium", size: 14, line: 18, color: .white.opacity(0.8))
                    .padding(.top, 6)
                    .accessibilityIdentifier("membership.intro")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var startButton: some View {
        Button(action: onStart) {
            typeset(L(busy ? "STARTING…" : "START PRO"), font: "InterTight-Bold", size: 20,
                    line: 24, kern: -0.4, color: .black, alignment: .center)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .background(lime)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canPurchase || busy)
        .accessibilityLabel(L(busy ? "STARTING…" : "START PRO"))
        .accessibilityIdentifier("membership.start")
    }

    private func benefit(_ title: String, _ copy: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            typeset(L(title), font: "Doto-SemiBold", size: 10, line: 14, kern: 1.8, color: lime)
            typeset(L(copy), font: "InterTight-Medium", size: 22, line: 28, kern: -0.66)
        }
    }

    private func typeset(_ text: String, font: String, size: CGFloat, line: CGFloat,
                         kern: CGFloat = 0, color: Color = .white,
                         alignment: NSTextAlignment = .left, strikethrough: Bool = false) -> some View {
        PaywallText(text: text, fontName: font, fontSize: size, lineHeight: line,
                    kern: kern, color: UIColor(color), alignment: alignment, strikethrough: strikethrough)
    }
}

/// Local CSS typography adapter. The rest of the app intentionally uses pixel UI
/// fonts; this Paper page specifies the bundled Inter Tight/Jost faces explicitly.
struct PaywallText: UIViewRepresentable {
    var text: String
    var fontName: String
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var kern: CGFloat
    var color: UIColor
    var alignment: NSTextAlignment
    var strikethrough = false

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: paragraph,
            .baselineOffset: (lineHeight - font.lineHeight) / 2
        ]
        if strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = color
        }
        label.attributedText = NSAttributedString(string: text, attributes: attributes)
        label.accessibilityLabel = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let lines = max(1, ceil(size.height / lineHeight))
        // UILabel includes final negative kern in its advance width, although
        // the last glyph still paints beyond that advance (notably PRO's O).
        // Keep the proposed text column, or allow that final ink for hug-sized rows.
        return CGSize(width: proposal.width ?? ceil(size.width + max(0, -kern)),
                      height: lines * lineHeight)
    }
}

/// Shared host binds the displayed SDK product to the verified health-account
/// identity. The store owns the transaction task and server entitlement sync.
struct MembershipCardHost: View {
    @ObservedObject var billing: BillingStore
    var source: MembershipPresentation? = nil
    var onFinished: () -> Void
    @State private var offer: BillingPaywallOffer?
    @State private var restoreIdentity: UUID?
    @State private var preparing = true
    @State private var synchronizing = false
    @State private var finished = false

    var body: some View {
        MembershipCard(amount: displayAmount, currency: displayCurrency,
                       listPrice: displayListPrice, perMonthPrice: displayPerMonthPrice,
                       intro: offer?.introductoryText, busy: synchronizing || billing.busy,
                       canPurchase: offer != nil || billing.usesStoreFreePreview,
                       canRestore: restoreIdentity != nil || billing.usesStoreFreePreview,
                       preparing: preparing, preview: billing.usesStoreFreePreview,
                       message: billing.lastMessage, onDismiss: dismiss,
                       onStart: { Task { await purchase() } },
                       onRestore: { Task { await restore() } },
                       onRetry: { Task { await prepare() } })
            .onAppear {
                if let source { billing.presentation = source }
                billing.cardViewed()
            }
            .task { await prepare() }
    }

    private var displayAmount: String {
        #if DEBUG
        if billing.usesStoreFreePreview { return "19.99" }
        #endif
        return offer?.priceAmount ?? ""
    }
    private var displayListPrice: String? {
        #if DEBUG
        if billing.usesStoreFreePreview { return BillingCatalog.fallbackListPrice }
        #endif
        return offer?.listPrice
    }
    private var displayPerMonthPrice: String? {
        #if DEBUG
        if billing.usesStoreFreePreview { return BillingCatalog.fallbackMonthlyEquivalent }
        #endif
        return offer?.perMonthPrice
    }
    private var displayCurrency: String {
        #if DEBUG
        if billing.usesStoreFreePreview { return "$" }
        #endif
        return offer?.currencySymbol ?? ""
    }

    private func prepare() async {
        guard !billing.usesStoreFreePreview else { preparing = false; return }
        preparing = true
        billing.lastMessage = nil
        offer = nil
        restoreIdentity = nil
        defer { preparing = false }
        // Restoring an existing subscription does not require a sellable package.
        // Preserve the verified identity even when the offering fails to load.
        restoreIdentity = await billing.preparePaywall()
        guard !Task.isCancelled else { return }
        do {
            let loaded = try await billing.loadPaywallOffer()
            guard !Task.isCancelled else { return }
            #if DEBUG
            if let expected = ProcessInfo.processInfo.environment["NB_DEBUG_BILLING_EXPECT_IDENTITY"] {
                guard Purchases.shared.appUserID == expected,
                      SupabaseClient.currentUserIdSnapshot() == expected,
                      let token = SessionKeychain.accessToken,
                      HomeLaunchPolicy.isAccessTokenUsable(token),
                      HomeLaunchPolicy.jwtSubject(token) == expected else {
                    billing.lastMessage = "Test account identity or session mismatch."
                    return
                }
            }
            #endif
            offer = loaded
        } catch {
            guard !Task.isCancelled else { return }
            billing.lastMessage = L("NextBody Pro is temporarily unavailable. Please try again later.")
        }
    }

    private func purchase() async {
        guard !synchronizing else { return }
        #if DEBUG
        if billing.usesStoreFreePreview { await showResult(billing.purchase()); return }
        #endif
        guard let offer else { return }
        synchronizing = true
        let result = await billing.purchase(package: offer.package, expectedIdentity: offer.identity)
        synchronizing = false
        await showResult(result)
    }

    private func restore() async {
        guard !synchronizing else { return }
        #if DEBUG
        if billing.usesStoreFreePreview { await showResult(billing.restore()); return }
        #endif
        guard let restoreIdentity else { return }
        synchronizing = true
        let result = await billing.restore(expectedIdentity: restoreIdentity)
        synchronizing = false
        await showResult(result)
    }

    private func showResult(_ result: BillingPurchaseResult) async {
        switch result {
        case .success:
            guard billing.isPro else { return }
            finish()
        case .cancelled: break
        case .unavailable: billing.lastMessage = L("App Store purchases are not configured on this build.")
        case .failed(let line): billing.lastMessage = line
        }
    }

    private func dismiss() {
        billing.markWelcomeSeen()
        billing.dismiss()
        finish()
    }
    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}
