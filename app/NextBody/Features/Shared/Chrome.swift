import SwiftUI
import UIKit

/// Design geometry: the boards are 390 × 844 with a 358 content column and draw their own
/// 62pt status bar and 19pt home-indicator block. On device iOS draws both, at whatever
/// height the phone has, so the page reads the real safe area and never reserves a
/// board-sized block.
enum Chrome {
    /// The board's own status-bar block. Only for converting a board Y into a Y measured
    /// from the top of the safe area (`y - boardStatusBar + gateTopInset`).
    static let boardStatusBar: CGFloat = 62
    /// The board's own home-indicator block. A real phone is ~34pt; the extra used to
    /// sit as a black void under PLAN. Home drops the lip into that extra.
    static let boardHomeIndicator: CGFloat = 19
    /// The device's status bar — what a page that draws under it must leave clear.
    static var statusBarBlock: CGFloat { ScreenMetrics.safeArea.top }
    /// The device's home-indicator inset.
    static var homeIndicatorBlock: CGFloat { ScreenMetrics.safeArea.bottom }

    /// The gate screens put their header line at y = 66. Inside the safe area that is 19pt.
    static let gateTopInset: CGFloat = 19

    /// A Y written on the board (from the board's top edge) as a Y measured from the top of
    /// the safe area. The board's column is 763pt between its status bar and its indicator;
    /// on a phone whose safe area is shorter than that (an SE) the column is compressed to
    /// fit, so nothing the board places near the bottom falls off the screen.
    static func boardY(_ y: CGFloat) -> CGFloat {
        let boardSafe: CGFloat = 844 - boardStatusBar - boardHomeIndicator
        let s = ScreenMetrics.size, i = ScreenMetrics.safeArea
        let deviceSafe = s.height - i.top - i.bottom
        return (y - boardStatusBar + gateTopInset) * min(1, deviceSafe / boardSafe)
    }
}

struct HomeIndicator: View {
    var body: some View {
        Capsule()
            .fill(NB.white.opacity(0.35))
            .frame(width: 134, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }
}

/// The one page background. #0B0B0D, edge to edge.
struct CarbonBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack { NB.carbon.ignoresSafeArea(); content }
    }
}

extension View {
    func carbonPage() -> some View { modifier(CarbonBackground()) }
}

/// NEXTBODY · lime pip. Inter Tight 800 @24, tracking −0.01em.
struct Wordmark: View {
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: 7) {
            Text(L("NEXTBODY"))
                .font(NBFont.brand(800, size))
                .tracking(-0.01 * size)
                .foregroundStyle(NB.text1)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(NB.lime1)
                .frame(width: 6, height: 6)
        }
    }
}

/// The band's own battery, as the header draws it — a 12×7 dot-matrix cell scaled to
/// 22×13, plus a Doto percentage. Charging adds a pixel bolt and a live fill pulse.
struct BandBatteryPip: View {
    /// nil = the band has not said. The shell is drawn empty and the label is a dash; a
    /// percentage is printed only once one has actually been read.
    let percent: Int?
    var chargeState: BandBattery.ChargeState = .unknown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCharging: Bool { chargeState == .charging }
    private var showBolt: Bool { chargeState == .charging || chargeState == .full }

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.animation(paused: reduceMotion || !isCharging)) { timeline in
                let pulse: CGFloat = isCharging && !reduceMotion
                    ? CGFloat((sin(timeline.date.timeIntervalSinceReferenceDate * 2.6) + 1) / 2)
                    : 1
                Canvas { ctx, size in
                    let s = size.width / 12                       // viewBox is 12 × 7
                    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
                        ctx.fill(Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)), with: .color(c))
                    }
                    let shell = showBolt ? NB.lime3 : Color(hex: 0x3A3A44)
                    rect(0, 0, 10, 1, shell)
                    rect(0, 6, 10, 1, shell)
                    rect(0, 1, 1, 5, shell)
                    rect(9, 1, 1, 5, shell)
                    rect(10, 2, 2, 3, shell)
                    let fillWidth = percent.map { 8 * CGFloat($0) / 100 } ?? 0
                    if fillWidth > 0 {
                        let fill = showBolt
                            ? NB.lime1.opacity(0.55 + 0.45 * pulse)
                            : NB.lime2
                        rect(1, 1, fillWidth, 5, fill)
                    }
                    if showBolt {
                        // Pixel lightning on the cell. A pixel over the fill is punched
                        // out; a pixel over empty interior stays lime so a low charge
                        // still reads as charging.
                        for (x, y) in [(5, 1), (4, 2), (5, 2), (3, 3), (4, 3), (5, 3), (6, 3), (5, 4), (6, 4), (5, 5)] {
                            let overFill = CGFloat(x) + 1 <= 1 + fillWidth
                            rect(CGFloat(x), CGFloat(y), 1, 1, overFill ? NB.carbon : NB.lime1)
                        }
                    }
                }
            }
            .frame(width: 22, height: 13)

            Text(percent.map { "\($0)%" } ?? Fmt.dash)
                .font(NBFont.dot(700, 11))
                .tracking(0.06 * 11)
                .foregroundStyle(showBolt ? NB.lime1 : NB.limePale)
        }
    }
}

/// The avatar. 36pt in the home header, 44pt on 11 · Profile, 26pt where a board draws the
/// smaller one. It used to be `Image("Avatar")` — one photograph of one stranger, shipped in
/// the bundle and worn by every account. It carries the initials of the name instead, and
/// since an account with no name of its own is called YOU, it is never empty.
struct Avatar: View {
    var size: CGFloat = 36
    var initials: String
    /// 11C · the identity plate inks the letters lime; everywhere else they stay white.
    var ink: Color = NB.text1

    var body: some View {
        ZStack {
            Circle().fill(NB.smokeKey)
            Circle().stroke(NB.hairline, lineWidth: 1)
            Text(initials)
                .font(NBFont.ui(600, size * 0.32))
                .tracking(0.06 * size * 0.32)
                .foregroundStyle(ink)
        }
        .frame(width: size, height: size)
    }
}

/// The only way into 11 · Profile.
struct AvatarButton: View {
    var size: CGFloat = 26
    var initials: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Avatar(size: size, initials: initials)
                // F1 · 上线前必须成立 · 「热区不小于 44×44」. The padding is added and taken
                // back out so the hit area reaches 44 while the row keeps its own height.
                .padding(max(0, (44 - size) / 2))
                .contentShape(Rectangle())
                .padding(-max(0, (44 - size) / 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Profile"))
    }
}

/// 04 · header row, laid out the way an iOS navigation bar is: 44pt tall, the identity on
/// the left (avatar 36 + the day over the name), the band battery on the right. The whole
/// left block is the one way into 11 · Profile.
struct HomeHeader: View {
    let name: String
    let initials: String
    let batteryPercent: Int?
    var chargeState: BandBattery.ChargeState = .unknown
    let flame: WearRun.Flame
    var width: CGFloat = NB.Layout.contentWidth
    let onProfile: () -> Void
    /// 12 · the band battery is the way into the device page.
    var onDevice: () -> Void = {}
    #if DEBUG
    @State private var catalogue = false
    #endif

    static let height: CGFloat = 44

    /// ⚠️ One formatter for the process. Building a DateFormatter costs milliseconds, and
    /// this line was rebuilding one on every pass of the header — which re-renders with
    /// every battery tick and every store change behind it.
    private var dayLine: String {
        let f = DateFormatter()
        f.locale = AppLanguage.shared.swiftLocale
        f.dateFormat = AppLanguage.shared.isEnglish ? "EEE · d MMM" : "EEE · M月d日"
        return f.string(from: Date()).uppercased()
    }

    private var pipLabel: String {
        let level = batteryPercent.map { "Band · battery \($0)%" } ?? "Band · battery not read"
        switch chargeState {
        case .charging: return "\(level) · charging"
        case .full:     return "\(level) · charged"
        default:        return level
        }
    }

    private var profileLabel: String {
        switch flame {
        case .live(let n):
            return L("Profile · %@ · %d-day wear run", name, n)
        case .amber:
            return L("Profile · %@ · wear run broken yesterday", name)
        case .gray:
            return L("Profile · %@", name)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Avatar(size: 36, initials: initials)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLine)
                        .font(NBFont.dot(600, 10))
                        .tracking(0.18 * 10)
                        .foregroundStyle(NB.text3Prod)
                    HStack(spacing: 6) {
                        Text(name)
                            .font(NBFont.brand(700, 20))
                            .tracking(-0.01 * 20)
                            .foregroundStyle(NB.text1)
                            .lineLimit(1)
                        WearFlameMark(flame: flame)
                            .layoutPriority(1)
                    }
                }
            }
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: onProfile)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(profileLabel)
            .accessibilityAddTraits(.isButton)
            #if DEBUG
            // 07's catalogue is the one board that cannot be audited by using the app,
            // because which widget appears is the model's choice. A long press opens
            // every type at once. DEBUG only — it is not a product surface.
            .onLongPressGesture(minimumDuration: 0.8) { if Band.allowsSeed { catalogue = true } }
            .fullScreenCover(isPresented: $catalogue) { WidgetCatalogue() }
            #endif

            Spacer(minLength: 0)
            Button(action: onDevice) {
                BandBatteryPip(percent: batteryPercent, chargeState: chargeState)
                    .frame(height: Self.height)
                    .padding(.leading, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pipLabel)
        }
        .frame(width: width, height: Self.height)
    }
}

/// ADR 0010 · the flame outline, drawn in a 26 × 34 box and scaled to the frame. It is off
/// the header's pixel grid on purpose: a 2pt-cell dot matrix this small reads as a blob, and
/// the notch between the two tongues is the only thing that separates a flame from a drop.
private struct WearFlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 26, sy = rect.height / 34
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: p(15, 0.6))
        path.addCurve(to: p(21, 14.6), control1: p(16.5, 6.2), control2: p(19, 10.2))
        path.addCurve(to: p(16.5, 30.7), control1: p(23.5, 20), control2: p(22, 27.6))
        path.addCurve(to: p(2.4, 25), control1: p(11, 33.7), control2: p(4, 31))
        path.addCurve(to: p(6.6, 13.4), control1: p(1, 19.8), control2: p(4, 16.4))
        path.addCurve(to: p(8.4, 8.6), control1: p(7.6, 12.2), control2: p(8.2, 10.6))
        path.addCurve(to: p(13.2, 14.1), control1: p(10, 11.7), control2: p(11.4, 13.1))
        path.addCurve(to: p(15, 0.6), control1: p(12.6, 9.7), control2: p(13.2, 4.5))
        path.closeSubpath()
        return path
    }
}

/// ADR 0010 · one flame plus an optional count, to the right of the name.
struct WearFlameMark: View {
    let flame: WearRun.Flame

    private var tint: Color {
        switch flame {
        case .live: return NB.lime1
        case .amber: return NB.caution2
        // The same unlit gray the battery shell next to it uses. `barTrack` is a chart
        // track at 15% and disappears on carbon; two dead marks in one header have to be
        // the same dead.
        case .gray: return Color(hex: 0x3A3A44)
        }
    }

    private var count: Int? {
        if case .live(let n) = flame { return n }
        return nil
    }

    var body: some View {
        // ⚠️ No placeholder digit. This used to print "0" at zero opacity inside an 18pt
        // `minWidth` slot, so the moment the run broke the name carried 18pt of dead space
        // to its right. ADR 0010 says the gray flame holds the slot — the number does not.
        HStack(spacing: 4) {
            WearFlameShape()
                .fill(tint)
                .frame(width: 14, height: 18)

            if let count {
                Text(String(count))
                    .font(NBFont.dot(700, 11))
                    .tracking(0.06 * 11)
                    .foregroundStyle(tint)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The device's own geometry, read once from the key window. The boards are drawn at
/// 390 × 844 with a 62pt status block and a 19pt indicator block; on device the page is
/// laid out against the real safe area instead, so every phone gets the same anatomy:
/// header under the status bar, dock over the home indicator, the panel taking the rest.
enum ScreenMetrics {
    /// Read once and kept. Every `.frame(width: NB.Layout.contentWidth)` in the app comes
    /// through here — over a hundred call sites, re-evaluated on every body pass of every
    /// animating view — and each read used to walk `connectedScenes` and every window to
    /// find the key one. The phone is portrait-only and does not change shape, so the
    /// first honest reading is the only one needed.
    private static var cached: (size: CGSize, safe: UIEdgeInsets)?

    static var size: CGSize { metrics.size }
    static var safeArea: UIEdgeInsets { metrics.safe }

    private static var metrics: (size: CGSize, safe: UIEdgeInsets) {
        if let cached { return cached }
        guard let w = window else {
            return (UIScreen.main.bounds.size, UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0))
        }
        let m = (size: w.bounds.size, safe: w.safeAreaInsets)
        // A window reports zero insets until it is attached; a zero would be wrong forever.
        if m.safe.top > 0 { cached = m }
        return m
    }

    private static var window: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ??
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first
    }
}

// MARK: detail page chrome · shared by 08 · 09 · 10 · 11 · 12 · 13

/// Invisible 热区 around `‹ TITLE`. Tall enough to hit without drawing a disc.
enum DetailBack {
    static let hitHeight: CGFloat = 56
    static let hitMinWidth: CGFloat = 48
    static let edgeWidth: CGFloat = 32
    static let commitFraction: CGFloat = 0.4
    static let commitVelocity: CGFloat = 300

    static func shouldPop(translation: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        translation > width * commitFraction || velocity > commitVelocity
    }
}

/// Every detail page is one scroll with a coloured bloom behind the top, and **one** title.
/// At rest it is the headline the boards drew: `‹ TRAINING`, big, the chevron and the word
/// one button. As the page scrolls that row lifts off — the eyebrow and the trailing
/// figure go with it — and the word itself shrinks and slides into the centre of the
/// 44pt bar. The chevron stays pinned at the bar's left so every second level keeps a
/// back mark in the top-left, including after the title has docked. One title, not two
/// copies that cut. The bar is glass at rest; a carbon ground fades in so a headline
/// never collides with the clock.
struct DetailScroll<Trailing: View, Content: View>: View {
    let glow: Color
    /// The page's own name — what the bar prints once the page has scrolled.
    let title: String
    /// What the big row prints when it is not the name: 10's date, 09's closed day.
    /// The name then sits above it as the eyebrow.
    let headline: String?
    /// An eyebrow of its own. Defaults to the name whenever the headline is something else.
    let eyebrow: String?
    /// The right end of the big row: 08's `2.1 TO GO`, 10's pager, 12's CONNECTED pill.
    let trailing: Trailing
    let content: Content
    let onBack: () -> Void

    init(glow: Color, title: String, headline: String? = nil, eyebrow: String? = nil,
         @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content,
         onBack: @escaping () -> Void) {
        self.glow = glow
        self.title = title
        self.headline = headline
        self.eyebrow = eyebrow
        self.trailing = trailing()
        self.content = content()
        self.onBack = onBack
    }

    private let barHeight: CGFloat = 44
    private let topPad: CGFloat = 14
    private let rowHeight: CGFloat = 34
    private let bottomPad: CGFloat = 14
    /// how far the page has scrolled, in points; 0 at rest
    @State private var scrolled: CGFloat = 0
    /// Centre of the large title in chrome-space at rest. Read off the placeholder so the
    /// morph starts on the same baseline the chevron was drawn against.
    @State private var restTitleCenter: CGPoint = .zero

    private var largeWord: String { headline ?? title }
    private var sameWord: Bool { largeWord == title }
    private var eyebrowText: String? { eyebrow ?? (headline == nil ? nil : title) }
    private var eyebrowSlot: CGFloat { eyebrowText == nil ? 0 : 22 }
    private var expandedHeight: CGFloat { topPad + eyebrowSlot + rowHeight + bottomPad }
    private var largeRowTop: CGFloat { topPad + eyebrowSlot }
    private var largeRowCenterY: CGFloat { largeRowTop + rowHeight / 2 }

    /// 0 at rest, 1 once the large row has handed the title to the bar.
    private var collapse: CGFloat { min(1, max(0, scrolled / 52)) }
    /// At rest the bar is glass: the bloom runs straight through it and the page reads as
    /// one surface. A carbon ground fades in as the page goes under it.
    private var ground: CGFloat { max(min(1, scrolled / 36), collapse) }

    private let largeSize: CGFloat = 28
    private let compactSize: CGFloat = 15
    private var largeChevronH: CGFloat { 19 }
    private var largeChevronW: CGFloat { 8 * largeChevronH / 13 }
    private var titleLeading: CGFloat { NB.Layout.gutter + largeChevronW + 10 }
    private var largeTitleWidth: CGFloat { Self.measure(largeWord, size: largeSize, tracking: -0.02 * largeSize) }

    var body: some View {
        ZStack(alignment: .top) {
            NB.carbon.ignoresSafeArea()

            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: expandedHeight).id("detail-top")
                    content
                    Color.clear.frame(height: 1).id("detail-bottom")
                }
                .background {
                    // iOS 17 has no scroll geometry API; the content reports its own top.
                    if #unavailable(iOS 18) {
                        GeometryReader { g in
                            Color.clear.preference(key: DetailOffsetKey.self,
                                                   value: -g.frame(in: .named("detail")).minY)
                        }
                    }
                }
            }
            .coordinateSpace(name: "detail")
            // ⚠️ A background, not a sibling in the ZStack: the bloom is 430pt wide, and as a
            // sibling it made the stack 430pt too, so every page sat 14pt left of centre.
            .background(alignment: .top) {
                Ellipse()
                    .fill(RadialGradient(stops: [
                        .init(color: glow.opacity(0.13), location: 0),
                        .init(color: glow.opacity(0.035), location: 0.6),
                        .init(color: glow.opacity(0), location: 1),
                    ], center: .center, startRadius: 0, endRadius: 215))
                    .frame(width: 430, height: 370)
                    .offset(y: -60)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            .modifier(ScrollOffsetWatcher { scrolled = max(0, $0) })
            #if DEBUG
            // `SIMCTL_CHILD_NB_DEBUG_SCROLL=1` drives the page down, part way back up, then to
            // the top, so the bar's states can be screenshotted without a finger.
            .task {
                guard ProcessInfo.processInfo.environment["NB_DEBUG_SCROLL"] != nil else { return }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeInOut(duration: 0.8)) { proxy.scrollTo("detail-bottom", anchor: .bottom) }
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeInOut(duration: 0.8)) { proxy.scrollTo("detail-top", anchor: UnitPoint(x: 0.5, y: -1.2)) }
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeInOut(duration: 0.8)) { proxy.scrollTo("detail-top", anchor: .top) }
            }
            #endif
            }

            departingRow
            barGround
            chrome
                .zIndex(1)
        }
        .coordinateSpace(name: "chrome")
        .onPreferenceChange(TitleCenterKey.self) { restTitleCenter = $0 }
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .detailEdgeBack(onBack)
    }

    /// The sticky title. One word, interpolating from the large-left slot into the bar's
    /// centre. Trailing lives in `departingRow`, under the ground; the chevron stays here
    /// so the top-left back mark never leaves with the large row.
    private var chrome: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t = collapse
            chromeLayers(width: w, t: t)
        }
        .frame(height: expandedHeight)
    }

    private func chromeLayers(width w: CGFloat, t: CGFloat) -> some View {
        let startX = restTitleCenter == .zero ? titleLeading + largeTitleWidth / 2 : restTitleCenter.x
        let startY = restTitleCenter == .zero ? largeRowCenterY : restTitleCenter.y
        let endX = w / 2
        let endY = barHeight / 2
        // At rest the ‹ and the word are one 热区, as the boards drew. Docked, it
        // shrinks to the mark on the bar's left — never a second disc.
        let hitW = mix(titleLeading + largeTitleWidth, DetailBack.hitMinWidth, t)

        let chevronH = mix(largeChevronH, 13, t)
        let chevronW = 8 * chevronH / 13

        return ZStack(alignment: .top) {
            if sameWord {
                morphingTitle(t: t, startX: startX, startY: startY, endX: endX, endY: endY)
            } else {
                Text(title)
                    .font(NBFont.brand(700, compactSize)).tracking(0.04 * compactSize)
                    .foregroundStyle(NB.text1)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                    .position(x: endX, y: endY)
                    .opacity(t)
                    .allowsHitTesting(false)
            }

            BackChevron(height: chevronH, line: mix(2.2, 1.6, t))
                .offset(y: mix(1, 0, t))
                .allowsHitTesting(false)
                .position(x: NB.Layout.gutter + chevronW / 2, y: mix(startY, endY, t))

            Button(action: onBack) {
                Color.white.opacity(0.001)
                    .frame(width: max(hitW, DetailBack.hitMinWidth), height: DetailBack.hitHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HotZoneTap(pressedOpacity: 1, pressedScale: 1))
            .accessibilityLabel(L("Back"))
            .accessibilityValue(title)
            .position(x: hitW / 2, y: mix(startY, endY, t))
        }
    }

    /// Eyebrow, trailing, and (when it is a different word) the large headline.
    /// They scroll away with the page; the docked title and the back chevron are not
    /// among them. Drawn under the bar ground so they never paint over the clock.
    private var departingRow: some View {
        let t = collapse
        return VStack(alignment: .leading, spacing: 8) {
            if let eyebrowText {
                Text(eyebrowText)
                    .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 10) {
                    Color.clear
                        .frame(width: largeChevronW, height: largeChevronH)
                    if sameWord {
                        Text(largeWord)
                            .font(NBFont.brand(700, largeSize)).tracking(-0.02 * largeSize)
                            .lineLimit(1)
                            .fixedSize()
                            .opacity(0)
                            .overlay {
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: TitleCenterKey.self,
                                        value: CGPoint(
                                            x: g.frame(in: .named("chrome")).midX,
                                            y: g.frame(in: .named("chrome")).midY + scrolled
                                        )
                                    )
                                }
                            }
                            .accessibilityHidden(true)
                    } else {
                        Text(largeWord)
                            .font(NBFont.brand(700, largeSize)).tracking(-0.02 * largeSize)
                            .foregroundStyle(NB.text1)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                trailing
            }
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .padding(.horizontal, NB.Layout.gutter)
        .padding(.top, topPad)
        .offset(y: -scrolled)
        .opacity(max(0, 1 - t * 1.2))
        .allowsHitTesting(t < 0.35)
        .accessibilityHidden(t > 0.5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func morphingTitle(t: CGFloat, startX: CGFloat, startY: CGFloat,
                               endX: CGFloat, endY: CGFloat) -> some View {
        Text(largeWord)
            .font(NBFont.brand(700, largeSize)).tracking(-0.02 * largeSize)
            .foregroundStyle(NB.text1)
            .lineLimit(1)
            .fixedSize()
            .scaleEffect(mix(1, compactSize / largeSize, t), anchor: .center)
            .position(x: mix(startX, endX, t), y: mix(startY, endY, t))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Carbon from the clock down through the 44pt bar, then a short fade so the edge is
    /// not a line. The 44pt slot stays in the safe area; the fill climbs into the status
    /// bar as a background so the inset is not eaten out of the 44.
    private var barGround: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: barHeight)
                .frame(maxWidth: .infinity)
                .background(NB.carbon.ignoresSafeArea(edges: .top))
            LinearGradient(colors: [NB.carbon, NB.carbon.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
                .frame(maxWidth: .infinity)
        }
        .opacity(ground)
        .allowsHitTesting(false)
    }

    private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// Inter Tight Bold at the large size, so the morph starts on the same width the
    /// placeholder holds open in the large row.
    private static func measure(_ s: String, size: CGFloat, tracking: CGFloat) -> CGFloat {
        let font = UIFont(name: "InterTight-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .bold)
        return ceil((s as NSString).size(withAttributes: [.font: font, .kern: tracking]).width)
    }
}

extension DetailScroll where Trailing == EmptyView {
    init(glow: Color, title: String, headline: String? = nil, eyebrow: String? = nil,
         @ViewBuilder content: () -> Content, onBack: @escaping () -> Void) {
        self.init(glow: glow, title: title, headline: headline, eyebrow: eyebrow,
                  trailing: { EmptyView() }, content: content, onBack: onBack)
    }
}

/// The page's scroll offset, 0 at rest and positive once the page has moved up. iOS 18 reads
/// the scroll view's own geometry; iOS 17 reads the preference the content publishes.
private struct ScrollOffsetWatcher: ViewModifier {
    let onChange: (CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { g in
                g.contentOffset.y + g.contentInsets.top
            } action: { _, new in onChange(new) }
        } else {
            content.onPreferenceChange(DetailOffsetKey.self) { onChange($0) }
        }
    }
}

private struct DetailOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TitleCenterKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

/// Keep the previous page visible beneath the custom edge drag. NavigationStack's
/// inactive hosting view is not a drawable backdrop until its route is popped.
extension View {
    func detailEdgeBack(_ action: @escaping () -> Void) -> some View {
        modifier(InteractiveEdgeBack(action: action))
    }
}

private struct InteractiveEdgeBack: ViewModifier {
    let action: () -> Void
    @EnvironmentObject private var router: Router
    @State private var x: CGFloat = 0
    @State private var committing = false
    @State private var depth = 0
    @State private var backdrop: UIImage?

    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .offset(x: x)
            .background {
                if x > 0, let backdrop {
                    GeometryReader { geometry in
                        Image(uiImage: backdrop)
                            .resizable()
                            .frame(width: ScreenMetrics.size.width, height: ScreenMetrics.size.height)
                            .offset(x: -geometry.frame(in: .global).minX,
                                    y: -geometry.frame(in: .global).minY)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .background {
                EdgePanProbe(enabled: !committing && !router.path.isEmpty
                             && router.sheet == nil && router.takeover == nil,
                             onChanged: { translation in
                    var drag = Transaction()
                    drag.disablesAnimations = true
                    withTransaction(drag) { x = max(0, translation) }
                }, onEnded: finish)
            }
            .onAppear {
                depth = router.path.count
                backdrop = router.returnBackdrop
                x = 0
                committing = false
            }
    }

    private func finish(_ translation: CGFloat, _ velocity: CGFloat) {
        let width = ScreenMetrics.size.width
        guard DetailBack.shouldPop(translation: translation, velocity: velocity, width: width) else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { x = 0 }
            return
        }
        committing = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.90)) {
            x = width
        } completion: {
            var cut = Transaction()
            cut.disablesAnimations = true
            withTransaction(cut) {
                action()
                // Some back actions change local content (Fuel's past day → today)
                // rather than removing the page. Leave that page ready for another drag.
                if router.path.count == depth {
                    x = 0
                    committing = false
                }
            }
        }
    }
}

/// A window recognizer does not cover the back button's hit target.
private struct EdgePanProbe: UIViewRepresentable {
    var enabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onWindow = { context.coordinator.attach(window: $0) }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeView: UIView {
        var onWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindow?(window)
        }
    }

    final class Coordinator {
        var enabled = false
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
        private var listener: EdgeBackGate.Listener?

        func attach(window: UIWindow?) {
            detach()
            guard let window else { return }
            listener = EdgeBackGate.shared.push(window: window,
                enabled: { [weak self] in self?.enabled ?? false },
                onChanged: { [weak self] in self?.onChanged($0) },
                onEnded: { [weak self] in self?.onEnded($0, $1) })
        }

        func detach() {
            if let listener { EdgeBackGate.shared.pop(listener) }
            listener = nil
        }
    }
}

private final class EdgeBackGate: NSObject, UIGestureRecognizerDelegate {
    static let shared = EdgeBackGate()

    final class Listener {
        let enabled: () -> Bool
        let onChanged: (CGFloat) -> Void
        let onEnded: (CGFloat, CGFloat) -> Void
        init(enabled: @escaping () -> Bool, onChanged: @escaping (CGFloat) -> Void,
             onEnded: @escaping (CGFloat, CGFloat) -> Void) {
            self.enabled = enabled
            self.onChanged = onChanged
            self.onEnded = onEnded
        }
    }

    private weak var window: UIWindow?
    private var pan: LeftEdgePan?
    private var listeners: [Listener] = []
    private var owner: Listener?

    func push(window: UIWindow, enabled: @escaping () -> Bool,
              onChanged: @escaping (CGFloat) -> Void,
              onEnded: @escaping (CGFloat, CGFloat) -> Void) -> Listener {
        let listener = Listener(enabled: enabled, onChanged: onChanged, onEnded: onEnded)
        listeners.append(listener)
        if self.window !== window || pan == nil {
            if let pan { self.window?.removeGestureRecognizer(pan) }
            let pan = LeftEdgePan(target: self, action: #selector(handle(_:)))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = true
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            window.addGestureRecognizer(pan)
            self.pan = pan
            self.window = window
        }
        return listener
    }

    func pop(_ listener: Listener) {
        listeners.removeAll { $0 === listener }
        if listeners.isEmpty {
            if let pan { window?.removeGestureRecognizer(pan) }
            pan = nil
            window = nil
            owner = nil
        }
    }

    @objc private func handle(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        let dx = max(0, gesture.translation(in: view).x)
        switch gesture.state {
        case .began:
            owner = listeners.last { $0.enabled() }
            owner?.onChanged(dx)
        case .changed:
            owner?.onChanged(dx)
        case .ended:
            let current = owner
            owner = nil
            current?.onEnded(dx, gesture.velocity(in: view).x)
        case .cancelled, .failed:
            let current = owner
            owner = nil
            current?.onEnded(0, 0)
        default: break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard listeners.last?.enabled() == true,
              let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
        let velocity = pan.velocity(in: view)
        return velocity.x > 0 && velocity.x >= abs(velocity.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // A recognized edge drag owns the touch, including row/button recognizers.
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

private final class LeftEdgePan: UIPanGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let view else { return }
        if touch.location(in: view).x > DetailBack.edgeWidth { state = .failed }
    }
}

/// The back chevron. The 8 × 13 mark the boards drew, scaled. 19pt tall beside the
/// large headline; it stays in the 44pt bar's left once the title has docked.
struct BackChevron: View {
    var height: CGFloat = 13
    var line: CGFloat = 1.6
    var color: Color = NB.macroLabel
    var body: some View {
        let s = height / 13
        Path { p in
            p.move(to: CGPoint(x: 7 * s, y: 1 * s))
            p.addLine(to: CGPoint(x: 1.5 * s, y: 6.5 * s))
            p.addLine(to: CGPoint(x: 7 * s, y: 12 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .square))
        .frame(width: 8 * s, height: height)
    }
}

/// The close mark. The only exit from a takeover.
struct CloseMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(NB.carbon4)
                .overlay(Circle().stroke(NB.hairline, lineWidth: 1))
            Path { p in
                p.move(to: CGPoint(x: 8, y: 8)); p.addLine(to: CGPoint(x: 18, y: 18))
                p.move(to: CGPoint(x: 18, y: 8)); p.addLine(to: CGPoint(x: 8, y: 18))
            }
            .stroke(NB.iconInk, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 26, height: 26)
        }
        .frame(width: 36, height: 36)
    }
}

/// The AI display's small mosaic exit: five square pixels per diagonal, printed directly
/// onto the panel with no surrounding key. Its caller supplies the invisible 44pt hit target.
struct PixelCloseMark: View {
    private static let cells = [
        (0, 0), (0, 4),
        (1, 1), (1, 3),
        (2, 2),
        (3, 1), (3, 3),
        (4, 0), (4, 4),
    ]

    var body: some View {
        Canvas { context, _ in
            let pixel: CGFloat = 3
            let step: CGFloat = 4
            for (row, column) in Self.cells {
                let rect = CGRect(
                    x: CGFloat(column) * step,
                    y: CGFloat(row) * step,
                    width: pixel,
                    height: pixel
                )
                context.fill(Path(rect), with: .color(NB.iconInk))
            }
        }
        .frame(width: 19, height: 19)
        .accessibilityHidden(true)
    }
}

/// A hairline rule. 1px, white 8%.
struct Hairline: View {
    var width: CGFloat? = nil
    var body: some View {
        Rectangle().fill(NB.hairline).frame(width: width, height: 1)
    }
}

/// 05 · the dock is the only thing that moves when the keyboard comes up.
/// Everything else on the home screen stays exactly where it was.
@MainActor
final class KeyboardHeight: ObservableObject {
    @Published var height: CGFloat = 0

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                        as? CGRect else { return }
                let screen = UIScreen.main.bounds.height
                MainActor.assumeIsolated { self?.height = max(0, screen - frame.origin.y) }
            })
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.height = 0 }
            })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
