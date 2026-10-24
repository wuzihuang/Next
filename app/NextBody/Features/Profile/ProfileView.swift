import SwiftUI
import UserNotifications

/// 12-B · ME. The page answers who you are: the person, the one
/// year of direction, and the way in for outside AI assistants. Today's readiness stays
/// on Home, so this page does not draw a second Body Battery.
struct ProfileView: View {
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject private var consent = ConsentStore.shared
    @ObservedObject private var haptics = HapticsSetting.shared
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router
    @State private var notifyLamp = NotifyLamp.off
    @State private var showGuide = false
    /// how far the page has scrolled, in points; 0 at rest
    @State private var scrolled: CGFloat = 0

    private enum NotifyLamp { case on, off, denied }

    private let amber = Color(hex: 0xF59E5B)
    private let deleteRed = Color(hex: 0xF87171)

    var body: some View {
        ZStack(alignment: .top) {
            NB.carbon.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    identity
                    gauges
                    composition
                    mcpCard

                    SectionMark(L("ACCOUNT"))
                    LineGroup {
                        line(L("PROFILE"), value: data.profile.displayName.uppercased(), id: "PROFILE") {
                            router.sheet = .profileEdit
                        }
                        line(L("TRAINING GOAL"), value: goalWord, id: "TRAINING_GOAL") {
                            router.sheet = .goal
                        }
                        line(L("DEVICE"), value: deviceValue, id: "DEVICE") {
                            router.open(.device, from: .profile)
                        }
                    }

                    SectionMark(L("PREFERENCES"))
                    LineGroup {
                        line(L("NOTIFICATIONS"), value: notifyValue, valueTint: notifyTint, id: "NOTIFICATIONS") {
                            router.sheet = .notifications
                        }
                        line(L("APPLE HEALTH"), value: healthValue, valueTint: healthTint, id: "APPLE_HEALTH") {
                            router.sheet = .appleHealth
                        }
                        line(L("UNITS"), value: unitsValue, id: "UNITS") {
                            router.sheet = .units
                        }
                        toggleLine(L("HAPTICS"), isOn: hapticsBinding, id: "HAPTICS")
                        line(L("LANGUAGE"), value: language.locale.nativeName, id: "LANGUAGE") {
                            router.sheet = .language
                        }
                        line(L("WIDGETS"), value: L("HOW TO ADD"), id: "WIDGETS") {
                            router.sheet = .widgets
                        }
                    }

                    SectionMark(L("DATA & LEGAL"))
                    LineGroup {
                        line(L("AI ASSISTANTS"), value: L("MANAGE"), id: "ASSISTANTS_MANAGE") {
                            router.sheet = .assistants
                        }
                        line(L("COLLECTING HEALTH DATA"),
                             value: consent.granted ? L("ON") : L("OFF"), id: "COLLECTING") {
                            if consent.granted {
                                Task { await ConsentStore.shared.record(.withdrawn, msOnScreen: nil) }
                            } else {
                                router.takeover = .consent
                            }
                        }
                        if AIFeature.enabled {
                            line(L("AI MEMORY"), value: L("VIEW"), id: "AI_MEMORY") {
                                router.open(.aiMemory, from: .profile)
                            }
                        }
                        line(L("PRIVACY · TERMS"), value: legalStamp, id: "PRIVACY") {
                            router.sheet = .privacy
                        }
                        line(L("REPORT A PROBLEM"), id: "REPORT") {
                            router.sheet = .feedback
                        }
                        line(L("DELETE ACCOUNT"), titleTint: deleteRed, id: "DELETE") {
                            router.sheet = .deleteAccount
                        }
                    }

                    signOff
                }
                .padding(.top, 44)
                .background {
                    // iOS 17 has no scroll geometry API; the content reports its own top.
                    if #unavailable(iOS 18) {
                        GeometryReader { g in
                            Color.clear.preference(key: DetailOffsetKey.self,
                                                   value: -g.frame(in: .named("profile")).minY)
                        }
                    }
                }
            }
            .coordinateSpace(name: "profile")
            .modifier(ScrollOffsetWatcher { scrolled = $0 })
            .background(alignment: .topLeading) { bloom }
            barGround
            bar
            if showGuide {
                HomeMCPGuide(backTitle: L("ME"), onBack: {
                                 withAnimation(.easeOut(duration: 0.32)) { showGuide = false }
                             })
                    .ignoresSafeArea()
                    .zIndex(2)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .detailEdgeBack {
            if showGuide {
                withAnimation(.easeOut(duration: 0.32)) { showGuide = false }
            } else {
                router.backToRoot()
            }
        }
        .task { await refreshNotifications() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshNotifications() }
        }
        .onAppear {
            let state = latestScan?.inputWeightKg == nil ? "NO_SCAN" : "SCAN"
            Task { await Analytics.shared.track("ME_OPEN", ["STATE": state]) }
        }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ProfileBackKey()
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Circle().fill(NB.lime1).frame(width: 6, height: 6)
                Text(L("YOU"))
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.lime1)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
    }

    /// The lime glow the identity block sits in. It paints from the screen's top corner —
    /// through the clock and the glass bar — so the header and the page read as one
    /// surface, and it fades to clear before its own edge so nothing is clipped.
    private var bloom: some View {
        RadialGradient(stops: [
            .init(color: NB.lime1.opacity(0.12), location: 0),
            .init(color: NB.lime1.opacity(0.04), location: 0.55),
            .init(color: NB.lime1.opacity(0), location: 1),
        ], center: .topLeading, startRadius: 0, endRadius: 300)
            .frame(width: 480, height: 380)
            .offset(x: -70, y: -55)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    /// At rest the bar is glass and the bloom runs straight through it. Carbon fades in —
    /// through the clock, past the 44pt bar, out in a short gradient — once the page
    /// slides under. The fill climbs into the status bar so the inset is not eaten.
    private var barGround: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(NB.carbon.ignoresSafeArea(edges: .top))
            LinearGradient(colors: [NB.carbon, NB.carbon.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
                .frame(maxWidth: .infinity)
        }
        .opacity(min(1, scrolled / 36))
        .allowsHitTesting(false)
    }

    private var identity: some View {
        Button {
            track("IDENTITY")
            router.sheet = .profileEdit
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().stroke(NB.lime1, lineWidth: 2)
                    Text(data.profile.initials)
                        .font(NBFont.ui(600, 22))
                        .foregroundStyle(NB.lime1)
                }
                .frame(width: 72, height: 72)
                .shadow(color: NB.lime1.opacity(0.25), radius: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("NOW"))
                        .font(NBFont.dot(700, 10)).tracking(0.2 * 10)
                        .foregroundStyle(NB.white.opacity(0.9))
                    Text(data.profile.displayName)
                        .font(NBFont.brand(700, 38)).tracking(-0.01 * 38)
                        .foregroundStyle(NB.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .lineHeight(42)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("IDENTITY")
    }

    private var gauges: some View {
        HStack(alignment: .top, spacing: 0) {
            gauge(L("HEIGHT"), value: heightReadout.value, unit: heightReadout.unit, inset: 16)
            gauge(L("WEIGHT"), value: weightReadout.value, unit: weightReadout.unit,
                  tint: weightReadout.caption == nil ? NB.white : NB.lime1,
                  caption: weightReadout.caption, inset: 16)
            gauge(L("AGE"), value: "\(data.profile.age)", inset: 16)
        }
        .background {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle().fill(NB.hairline).frame(width: 1)
                Spacer(minLength: 0)
                Rectangle().fill(NB.hairline).frame(width: 1)
                Spacer(minLength: 0)
            }
        }
        .cardSkin()
        .padding(.horizontal, 16)
    }

    private var composition: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                track("COMPOSITION")
                router.open(.composition(date: data.today.day.start), from: .profile)
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(NB.lime1).frame(width: 6, height: 6)
                    Text(L("COMPOSITION · 26 W · %@", goalWord))
                        .font(NBFont.dot(700, 14)).tracking(0.12 * 14)
                        .foregroundStyle(NB.lime1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Spacer(minLength: 0)
                    Text("›")
                        .font(NBFont.ui(400, 16))
                        .foregroundStyle(NB.white.opacity(0.35))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("COMPOSITION")

            MonthAxis()
            CompositionWeekRow(weeks: weekCells) { week in
                router.open(.composition(date: week.end.start), from: .profile)
            }
            CompositionWeekLegend()
            HStack(alignment: .center, spacing: 12) {
                Text(L("The latest fat and lean mass are on the Body page"))
                    .font(NBFont.ui(300, 12))
                    .foregroundStyle(NB.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    openBody()
                } label: {
                    Text(L("BODY ›"))
                        .font(NBFont.dot(700, 10)).tracking(0.12 * 10)
                        .foregroundStyle(NB.lime1)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("BODY_LINK")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    /// The way in for ChatGPT, Claude, Cursor or Grok: the address to paste and the steps per client.
    private var mcpCard: some View {
        Button {
            track("AI_ASSISTANTS")
            openGuide()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(NB.lime1).frame(width: 6, height: 6)
                    Text(L("MCP"))
                        .font(NBFont.dot(700, 12)).tracking(0.2 * 12)
                        .foregroundStyle(NB.lime1)
                    Spacer(minLength: 0)
                }
                Text(L("Connect your AI"))
                    .font(NBFont.ui(700, 20)).tracking(0.04 * 20)
                    .foregroundStyle(NB.white)
                Text(L("ChatGPT, Claude, Cursor and Grok can read your own data."))
                    .font(NBFont.ui(300, 13)).lineSpacing(5)
                    .foregroundStyle(NB.white.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("How to connect"))
                    .font(NBFont.ui(600, 13)).tracking(0.12 * 13)
                    .foregroundStyle(NB.carbon4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(NB.lime1, in: Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardSkin()
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .accessibilityIdentifier("AI_ASSISTANTS")
    }

    private var signOff: some View {
        VStack(spacing: 14) {
            Button {
                track("SIGN_OUT")
                router.sheet = .signOut
            } label: {
                Text(L("SIGN OUT"))
                    .font(NBFont.ui(500, 12)).tracking(0.22 * 12)
                    .foregroundStyle(NB.white)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(buildLine)
                .font(NBFont.dot(700, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.lime1.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 34)
        .padding(.horizontal, 20)
    }

    private func line(_ title: String, value: String? = nil, valueTint: Color? = nil,
                      titleTint: Color? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button {
            track(id)
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(NBFont.ui(500, 14)).tracking(0.08 * 14)
                    .foregroundStyle(titleTint ?? NB.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(NBFont.dot(700, 11))
                        .foregroundStyle(valueTint ?? NB.white.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Chevron()
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NB.hairline).frame(height: 1).padding(.leading, 16)
        }
        .accessibilityIdentifier(id)
    }

    /// Same height and hairline as `line`, but the trailing side is a switch, not a chevron.
    private func toggleLine(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(NBFont.ui(500, 14)).tracking(0.08 * 14)
                .foregroundStyle(NB.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(NB.lime1)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NB.hairline).frame(height: 1).padding(.leading, 16)
        }
        .accessibilityIdentifier(id)
    }

    private func gauge(_ label: String, value: String, unit: String? = nil,
                       tint: Color = NB.white, caption: String? = nil,
                       inset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.white.opacity(0.9))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(NBFont.dot(800, 28)).tracking(-0.03 * 28)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(NBFont.dot(700, 9))
                        .foregroundStyle(NB.white.opacity(0.8))
                }
            }
            if let caption {
                Text(caption)
                    .font(NBFont.dot(700, 9)).tracking(0.08 * 9)
                    .foregroundStyle(NB.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, inset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func track(_ row: String) {
        Task { await Analytics.shared.track("ME_ROW_TAP", ["ROW": row]) }
    }

    private func openGuide() {
        withAnimation(.easeOut(duration: 0.32)) { showGuide = true }
        Task { await Analytics.shared.track("ME_MCP_GUIDE_OPEN", [:]) }
    }

    private func openBody() {
        Task { await Analytics.shared.track("ME_BODY_LINK_TAP", [:]) }
        router.showHome(page: 2)
    }

    private func refreshNotifications() async {
        let status = await NotificationReach.authorizationStatus()
        if NotificationReach.isAuthorized(status) {
            notifyLamp = .on
        } else if status == .denied {
            notifyLamp = .denied
        } else {
            notifyLamp = .off
        }
    }

    private var latestScan: CompositionScan? {
        data.compositionScans.max { $0.at < $1.at }
    }

    private var weekCells: [CompositionWeekCell] {
        CompositionWindowMath.weekCells(
            scans: data.compositionScans,
            aim: CompositionAim(rawValue: data.profile.goal.rawValue) ?? .recomp,
            endingOn: UserDay.containing(Date()))
    }

    private var goalWord: String { L(data.profile.goal.rawValue) }

    private var heightReadout: (value: String, unit: String) {
        if data.profile.usesMetric {
            return ("\(Int(data.profile.heightCm.rounded()))", "CM")
        }
        let inches = Int((data.profile.heightCm / 2.54).rounded())
        return ("\(inches / 12)'\(inches % 12)", "FT")
    }

    /// The same weight Home's body page reads: the latest scan, or a dash.
    private var weightReadout: (value: String, unit: String, caption: String?) {
        let metric = data.profile.usesMetric
        let unit = metric ? "KG" : "LB"
        guard let scan = latestScan, let kg = scan.inputWeightKg else {
            return (Fmt.dash, unit, nil)
        }
        let shown = metric ? kg : kg * 2.2046226
        return (Fmt.kg(shown), unit, L("SCAN · %@", stamp(scan.at)))
    }

    private var deviceValue: String {
        guard data.band.connected else { return L("DISCONNECTED") }
        if let percent = data.band.batteryPercent {
            return L("NEXTBODY · %d%%", percent)
        }
        return L("NEXTBODY · %@", Fmt.dash)
    }

    private var unitsValue: String {
        data.profile.usesMetric ? L("METRIC") : L("IMPERIAL")
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(get: { haptics.enabled }, set: { on in
            haptics.enabled = on
            track("HAPTICS")
            if on { HoldHaptics.shared.release() }
        })
    }

    private var notifyValue: String {
        switch notifyLamp {
        case .on: L("ON")
        case .off: L("OFF")
        case .denied: L("OFF IN SETTINGS")
        }
    }

    private var notifyTint: Color? { notifyLamp == .denied ? amber : nil }

    private var healthValue: String {
        data.profile.appleHealthLinked ? L("SYNCED") : L("ACCESS OFF")
    }

    private var healthTint: Color? { data.profile.appleHealthLinked ? nil : amber }

    private var legalStamp: String {
        let format = language.isEnglish ? "MMM d" : "M月d日"
        return Fmt.displayDate(LegalText.revised, format: format).uppercased()
    }

    private var buildLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? Fmt.dash
        let build = info?["CFBundleVersion"] as? String ?? Fmt.dash
        return L("NEXTBODY %@ · BUILD %@", version, build)
    }

    private func stamp(_ date: Date) -> String {
        let format = language.isEnglish ? "MMM d" : "M月d日"
        return Fmt.displayDate(date, format: format).uppercased()
    }
}

private struct SectionMark: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(NBFont.ui(700, 16)).tracking(0.1 * 16)
            .foregroundStyle(NB.lime1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 10)
    }
}

private struct LineGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // The last row's rule sits one point below the frame and is clipped, so the card's own edge closes it.
        VStack(spacing: 0) { content }
            .padding(.bottom, -1)
            .clipShape(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
            .cardSkin()
            .padding(.horizontal, 16)
    }
}

struct Chevron: View {
    var color: Color = Color(hex: 0x5A5A66)
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 1, y: 1))
            p.addLine(to: CGPoint(x: 5, y: 5))
            p.addLine(to: CGPoint(x: 1, y: 9))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
        .frame(width: 6, height: 10)
    }
}

private struct MonthAxis: View {
    var body: some View {
        let f = DateFormatter()
        let months: [String] = (0..<6).reversed().map { back in
            let d = Calendar.current.date(byAdding: .month, value: -back, to: Date())!
            f.locale = AppLanguage.shared.swiftLocale
            f.dateFormat = AppLanguage.shared.isEnglish ? "MMM" : "M月"
            return f.string(from: d).uppercased()
        }
        return HStack(spacing: 0) {
            ForEach(months, id: \.self) { m in
                Text(m)
                    .font(NBFont.dot(500, 10)).tracking(0.08 * 10)
                    .foregroundStyle(NB.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// One cell is one user week; the colour is that week's measured direction toward the
/// training goal — never what was eaten that day. BIA only means something a week apart,
/// so a single scan lights the whole week and a grey cell is a week nobody scanned.
/// Every cell is tappable and lands on composition detail at that week's end.
struct CompositionWeekRow: View {
    let weeks: [CompositionWeekCell]
    let onWeek: (CompositionWeekCell) -> Void

    private let gap: CGFloat = 3

    private var cell: CGFloat {
        (NB.Layout.screenWidth - 40 - gap * CGFloat(weeks.count - 1)) / CGFloat(weeks.count)
    }

    var body: some View {
        HStack(spacing: gap) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                Button { onWeek(week) } label: {
                    CompositionWeekCellView(tone: week.tone, current: index == weeks.count - 1,
                                            height: cell, radius: 2)
                        .frame(width: cell, height: cell)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CompositionWeekCellView: View {
    let tone: CompositionWeekTone
    var current = false
    var height: CGFloat = 34
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(stroke, lineWidth: tone == .held ? 1.5 : (current ? 2 : 0)))
            .frame(height: height)
    }

    private var fill: Color {
        switch tone {
        case .aligned: NB.lime1
        case .held: .clear
        case .drift: NB.ember1
        case .noScan: Color(hex: 0x26262E)
        }
    }
    private var stroke: Color {
        if tone == .held { return NB.white.opacity(0.35) }
        return current ? NB.white.opacity(0.7) : .clear
    }
}

struct CompositionWeekLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            chip(.aligned, L("ALIGNED"))
            chip(.held, L("HELD"))
            chip(.drift, L("DRIFT"))
            chip(.noScan, L("NO SCAN"))
        }
    }

    private func chip(_ tone: CompositionWeekTone, _ label: String) -> some View {
        HStack(spacing: 6) {
            CompositionWeekCellView(tone: tone, height: 8, radius: 2)
                .frame(width: 8, height: 8)
            Text(label)
                .font(NBFont.dot(700, 10)).tracking(0.06 * 10)
                .foregroundStyle(NB.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// ‹ ME. The edge-back host injects its slide-out into the environment inside this
/// page's own body, so the read lives here — a property on the page itself would only
/// ever see the environment above the host.
private struct ProfileBackKey: View {
    @EnvironmentObject private var router: Router
    @Environment(\.detailBackSlide) private var detailBackSlide

    var body: some View {
        Button { detailBackSlide?() ?? router.backToRoot() } label: {
            HStack(spacing: 8) {
                BackChevron(height: 16, line: 1.6, color: NB.white)
                Text(L("ME"))
                    .font(NBFont.ui(500, 16))
                    .foregroundStyle(NB.white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Back"))
        .accessibilityValue(L("ME"))
    }
}
