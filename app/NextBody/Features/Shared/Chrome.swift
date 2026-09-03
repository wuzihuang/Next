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
        let boardSafe: CGFloat = 844 - boardStatusBar - 19
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
            Text("NEXTBODY")
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
/// 22×13, plus a Doto percentage.
struct BandBatteryPip: View {
    /// nil = the band has not said. The shell is drawn empty and the label is a dash; a
    /// percentage is printed only once one has actually been read.
    let percent: Int?
    var body: some View {
        HStack(spacing: 6) {
            Canvas { ctx, size in
                let s = size.width / 12                       // viewBox is 12 × 7
                func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
                    ctx.fill(Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)), with: .color(c))
                }
                let shell = Color(hex: 0x3A3A44)
                rect(0, 0, 10, 1, shell)
                rect(0, 6, 10, 1, shell)
                rect(0, 1, 1, 5, shell)
                rect(9, 1, 1, 5, shell)
                rect(10, 2, 2, 3, shell)
                if let percent { rect(1, 1, 8 * CGFloat(percent) / 100, 5, NB.lime2) }
            }
            .frame(width: 22, height: 13)

            Text(percent.map { "\($0)%" } ?? Fmt.dash)
                .font(NBFont.dot(700, 11))
                .tracking(0.06 * 11)
                .foregroundStyle(NB.limePale)
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

    var body: some View {
        ZStack {
            Circle().fill(NB.smokeKey)
            Circle().stroke(NB.hairline, lineWidth: 1)
            Text(initials)
                .font(NBFont.ui(600, size * 0.32))
                .tracking(0.06 * size * 0.32)
                .foregroundStyle(NB.text1)
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
        .accessibilityLabel("Profile")
    }
}

/// 04 · header row, laid out the way an iOS navigation bar is: 44pt tall, the identity on
/// the left (avatar 36 + the day over the name), the band battery on the right. The whole
/// left block is the one way into 11 · Profile.
struct HomeHeader: View {
    let name: String
    let initials: String
    let batteryPercent: Int?
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
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE · d MMM"
        return f
    }()
    private var dayLine: String { Self.dayFormatter.string(from: Date()).uppercased() }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Avatar(size: 36, initials: initials)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLine)
                        .font(NBFont.dot(600, 10))
                        .tracking(0.18 * 10)
                        .foregroundStyle(NB.text3Prod)
                    Text(name)
                        .font(NBFont.brand(700, 20))
                        .tracking(-0.01 * 20)
                        .foregroundStyle(NB.text1)
                        .lineLimit(1)
                }
            }
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: onProfile)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Profile · \(name)")
            .accessibilityAddTraits(.isButton)
            #if DEBUG
            // 07's catalogue is the one board that cannot be audited by using the app,
            // because which widget appears is the model's choice. A long press opens
            // every type at once. DEBUG only — it is not a product surface.
            .onLongPressGesture(minimumDuration: 0.8) { catalogue = true }
            .fullScreenCover(isPresented: $catalogue) { WidgetCatalogue() }
            #endif

            Spacer(minLength: 0)
            Button(action: onDevice) {
                BandBatteryPip(percent: batteryPercent)
                    .frame(height: Self.height)
                    .padding(.leading, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(batteryPercent.map { "Band · battery \($0)%" } ?? "Band · battery not read")
        }
        .frame(width: width, height: Self.height)
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

/// Every detail page is one scroll with a coloured bloom behind the top, and **one** title.
/// At rest it is the headline the boards drew: `‹ TRAINING`, big, the chevron and the word
/// one button. As the page scrolls that row lifts off — the chevron, the eyebrow and the
/// trailing figure go with it — and the word itself shrinks and slides into the centre of
/// the 44pt bar. One title, not two copies that cut. The bar is glass at rest; a carbon
/// ground fades in so a headline never collides with the clock.
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
        }
        .coordinateSpace(name: "chrome")
        .onPreferenceChange(TitleCenterKey.self) { restTitleCenter = $0 }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        // Custom chrome hides the system back button, which also disables the edge-swipe
        // pop. A left-edge pan here calls the same `onBack` as the chevron — including
        // `backToRoot()` — so page-two vitals land back on page two, not a half-popped stack.
        .detailEdgeBack(onBack)
    }

    /// The sticky title. One word, interpolating from the large-left slot into the bar's
    /// centre. The chevron and trailing live in `departingRow`, under the ground.
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
        let hitW = mix(titleLeading + largeTitleWidth, 44, t)

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

            Button(action: onBack) {
                Color.white.opacity(0.001)
                    .frame(width: max(hitW, 44), height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .position(x: hitW / 2, y: mix(startY, endY, t))
        }
    }

    /// Chevron, eyebrow, trailing, and (when it is a different word) the large headline.
    /// They scroll away with the page; the docked title is not among them. Drawn under the
    /// bar ground so they never paint over the clock.
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
                    BackChevron(height: largeChevronH, line: 2.2)
                        .offset(y: 1)
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

/// Left-edge swipe → same `onBack` as the chevron. A fixed leading strip takes the
/// drag; the scroll and the rest of the page stay untouched. Prefer this over re-wiring
/// `interactivePopGestureRecognizer` from a background VC: that VC often has a nil
/// `navigationController`, and becoming the gesture's delegate while returning `false`
/// from `shouldBegin` silently kills the system swipe.
extension View {
    /// Leading-edge swipe that fires the same action as the page's back chevron.
    func detailEdgeBack(_ action: @escaping () -> Void) -> some View {
        // Pure SwiftUI — UIKit's screen-edge pan fights ScrollView inside NavigationStack
        // and the old background-VC enabler often never found the nav controller at all.
        overlay(alignment: .leading) {
            Color.clear
                .frame(width: 32)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .onEnded { v in
                            let dx = v.translation.width
                            let dy = v.translation.height
                            // Rightward and mostly horizontal — a vertical flick on the
                            // strip is still a scroll, not a back.
                            guard dx > 0, abs(dx) >= abs(dy) else { return }
                            let predicted = v.predictedEndTranslation.width
                            if dx > 56 || predicted > 120 { action() }
                        }
                )
                .accessibilityHidden(true)
        }
    }
}

/// The back chevron. The 8 × 13 mark the boards drew, scaled. 19pt tall beside the
/// large headline; it lifts with that row and is gone once the title has docked.
struct BackChevron: View {
    var height: CGFloat = 13
    var line: CGFloat = 1.6
    var body: some View {
        let s = height / 13
        Path { p in
            p.move(to: CGPoint(x: 7 * s, y: 1 * s))
            p.addLine(to: CGPoint(x: 1.5 * s, y: 6.5 * s))
            p.addLine(to: CGPoint(x: 7 * s, y: 12 * s))
        }
        .stroke(NB.macroLabel, style: StrokeStyle(lineWidth: line, lineCap: .square))
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
