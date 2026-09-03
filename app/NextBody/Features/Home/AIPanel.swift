import SwiftUI

/// 04 + 07 · the panel. 358 × 470, the only place she speaks.
/// One widget at a time; every widget is tappable and carries the page it lands on (F0 rule 06).
struct AIPanel: View {
    @ObservedObject private var consent = ConsentStore.shared
    /// 07 · 16 · she names the tool she is on while the singularity turns.
    @ObservedObject private var ai = AIService.shared
    /// 补屏 · the NOT COLLECTING button. The panel does not own the router.
    var onTurnOn: () -> Void = {}
    let m: DailyMetrics
    let band: BandState
    let lastSync: Date?
    /// 04 · the last five-minute tick. Its age decides whether the readout prints, dims,
    /// or dashes (13 · CURVE STOPS AT THE LAST REAL TICK).
    var vitals: LiveVitals = LiveVitals()
    var widget: PanelWidget?
    /// 01M · while the ceremony runs, this same surface is the whole screen. The fold at
    /// ◇7 animates its frame and corner radius — one layer, never a cross-fade.
    var firstRun: FirstRun?
    var size: CGSize = CGSize(width: NB.Layout.contentWidth, height: NB.Layout.panelHeight)
    var radius: CGFloat = NB.R.hero
    let onWidget: (Destination) -> Void

    private var ceremony: Bool { firstRun?.playing == true }
    var body: some View {
        ZStack {
            if let firstRun, ceremony {
                HalftoneScreen {
                    FirstRunArt(coreLit: firstRun.coreLit,
                                orbitFraction: firstRun.orbitFraction,
                                spinning: firstRun.orbitSpinning)
                }
            } else if let widget, widget.title != "THINKING", widget.composition == nil, widget.photo == nil {
                // 07 · the widget is printed, not lit. Board 07 draws every chart as LEDs on a
                // field of unlit dots — so the chart layer goes *behind* the dot screen, over
                // --led-off, and the words are drawn in front of it (see `filledWidget`). The
                // planet is the panel's idle face; a curve drawn over it read as a sticker.
                HalftoneScreen {
                    ZStack {
                        NB.ledOff
                        widgetLayer(widget, .chart)
                    }
                }
            } else if let widget, widget.title == "THINKING" {
                // 07 · 16 · 02 · the singularity draws on a bare field. The planet is the
                // thing being pulled in; leaving it behind the arms read as two objects.
                HalftoneScreen { NB.ledOff }
            } else if widget?.composition == nil {
                // A composition result draws its own LED ground and fills the panel.
                // Standby art behind a 358×470 card is what made the reading look like
                // a tile sitting in the middle of the display.
                HalftoneScreen { StandbyArt(charge: Double(m.bodyBattery ?? 0) / 100) }
            }

            if let firstRun, ceremony {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // ◇5 · the hairline pulls open from the centre over 0.3s.
                    Rectangle().fill(NB.hairline)
                        .frame(width: firstRun.hairlineOpen ? 236 : 0, height: 1)
                        .animation(.easeOut(duration: 0.3), value: firstRun.hairlineOpen)
                        .padding(.bottom, 22)
                    FirstRunSubtitle(typed: firstRun.typed,
                                     bandPaired: band.connected,
                                     showsCursor: firstRun.beat >= .type && firstRun.beat < .idle)
                    Spacer(minLength: 0).frame(height: size.height * 0.16)
                }
            } else
            // 07 · 03 · the widget owns the whole 358 × 470 surface, top row included:
            // its title and tag live at y16, exactly where STANDBY and the clock sit when
            // there is nothing to say. Only one of the two is ever drawn.
            if let widget, widget.title == "THINKING" {
                // 07 · 16 · 02 · the singularity owns the whole panel: its own header, the
                // question echoed at the top, what she is reading at the foot.
                ThinkingStage(question: widget.sentence, reading: ai.reading, startedAt: widget.startedAt)
            } else if let widget {
                // 07 · the widget is drawn on the board's 358 × 470 canvas with absolute slots.
                // Scale to fill the panel the phone actually left — up or down — so a taller
                // screen does not leave the reading as a card floating in the middle.
                filledWidget(widget)
            } else if !consent.granted {
                // 补屏 edge 1 / 2 · NOT COLLECTING. 「—— 是沉默」 at its limit: the panel says what
                // is not happening and offers the one way to change it. No widget, no readout.
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("NOT COLLECTING")
                            .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                            .foregroundStyle(NB.ember1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 22)
                    Spacer(minLength: 0)
                    VStack(spacing: 14) {
                        Text("HOOP isn't reading anything yet.")
                            .font(NBFont.brand(400, 18)).tracking(-0.01 * 18)
                            .foregroundStyle(NB.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                        Button(action: onTurnOn) {
                            Text("Turn it on")
                                .font(NBFont.ui(500, 13.5)).tracking(0.15 * 13.5)
                                .foregroundStyle(NB.carbon)
                                .frame(height: 44)
                                .padding(.horizontal, 26)
                                .background(NB.ember1, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the consent screen")
                    }
                    .padding(.bottom, 30)
                }
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    standbyReadout
                }
                .padding(.vertical, 16)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(NB.panelInk)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(widget?.composition != nil ? NB.lime1.opacity(0.18)
                    : NB.white.opacity(ceremony ? 0 : 0.08), lineWidth: 1))
    }

    private func filledWidget(_ widget: PanelWidget) -> some View {
        // Photo and composition answers carry their own canvases and draw flat, as before.
        widgetLayer(widget, widget.composition == nil && widget.photo == nil ? .text : .all)
    }

    /// One layer of the widget on the board's 358 × 470 canvas, scaled to the panel the
    /// phone left. The chart layer and the text layer use the same transform, so the words
    /// land exactly over their LEDs.
    private func widgetLayer(_ widget: PanelWidget, _ layer: PanelWidgetView.Layer) -> some View {
        let bw = NB.Layout.boardContentWidth
        let bh = NB.Layout.panelHeight
        let scale = min(size.width / bw, size.height / bh)
        return PanelWidgetView(widget: widget, onTap: onWidget, layer: layer)
            .frame(width: bw, height: bh)
            .scaleEffect(scale)
            .frame(width: size.width, height: size.height)
            .transition(.opacity)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(band.connected ? "STANDBY" : "OFFLINE")
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(NB.white.opacity(0.55))
            Spacer(minLength: 0)
            Text(Fmt.clock(Date()))
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.30))
        }
        .padding(.horizontal, 22)
    }

    /// The morning line and nothing else — sleep never reaches the screen (F0 rule 03).
    /// 04 · the board's type stack: eyebrow over a 64pt hero number, the charge line,
    /// HR / STRESS as two centred columns, and the one-line hint at the bottom.
    /// The resting face carries no target of its own: F1 gives Body Battery's page one
    /// entrance — the morning widget — so the display at standby is display, not a button.
    /// (It was a Button to .bodyBattery once; a swipe-length tap landed on it and the
    /// panel opened a page no board had drawn.)
    private var standbyReadout: some View {
        VStack(spacing: 0) {
            Hairline().frame(width: 236)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                Text(MetricNames.bodyBattery)
                    .font(NBFont.dot(600, 11)).tracking(0.34 * 11)
                    .foregroundStyle(NB.white.opacity(0.55))
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(Fmt.int(m.bodyBattery))
                        .font(NBFont.dot(700, 64)).tracking(-0.045 * 64)
                        .foregroundStyle(NB.lime1)
                    if m.bodyBattery != nil {
                        Text("%")
                            .font(NBFont.dot(700, 24))
                            .foregroundStyle(NB.lime1.opacity(0.7))
                    }
                }
                .padding(.top, 4)
                Text(chargeLine)
                    .font(NBFont.dot(500, 11)).tracking(0.1 * 11)
                    .foregroundStyle(NB.white.opacity(0.6))
                    .padding(.top, 6)
            }

            HStack(spacing: 40) {
                vitalsColumn(Fmt.int(readout.hr), label: "HR")
                vitalsColumn(Fmt.int(readout.stress), label: "STRESS")
            }
            .padding(.top, 12)

            Text("\(agoText) · TAP OR TALK — I'M UP")
                .font(NBFont.dot(500, 10.5)).tracking(0.18 * 10.5)
                .foregroundStyle(NB.white.opacity(0.42))
                .padding(.top, 10)
        }
    }

    /// 04 · one vitals slot: the reading above its label, centred in a fixed column so
    /// HR and STRESS stay put as the numbers change width.
    private func vitalsColumn(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(NBFont.dot(700, 28)).tracking(0.04 * 28)
                .foregroundStyle(NB.white.opacity(0.9))
            Text(label).font(NBFont.dot(600, 10.5)).tracking(0.2 * 10.5)
                .foregroundStyle(NB.white.opacity(0.5))
        }
        .frame(width: 96)
    }

    /// 13 · past six hours the numbers are gone, not dimmed and not carried forward.
    private var readout: (hr: Int?, stress: Int?) {
        vitals.freshness == .gone ? (nil, nil) : (vitals.hr, vitals.stress)
    }

    /// ⚠️ 1CVO · the only prediction on the product, and it renders only when all four of
    /// board 13's conditions hold. Otherwise the row is empty — never a placeholder, and
    /// never a discharge sentence the board never wrote.
    private var chargeLine: String {
        guard m.bodyBattery != nil else { return "NO NIGHT ON RECORD" }
        if vitals.freshness == .stale, let at = vitals.at {
            return "SYNCED \(Fmt.clock(at))"
        }
        return ChargeForecast.line(curve: m.reserveCurve) ?? ""
    }

    private var agoText: String {
        guard let at = vitals.at else { return "NO TICK" }
        let mins = max(0, Int(Date().timeIntervalSince(at) / 60))
        if mins < 1 { return "JUST NOW" }
        if mins < 60 { return "\(mins) MIN AGO" }
        return "\(mins / 60) HR AGO"
    }
}

/// 07 · 16 · 02 · THINKING — the singularity.
///
/// The board reuses Connect 04's gravitational collapse on purpose: idle → thinking has to
/// read as one planet being pulled in, not as a page change, or the user thinks they left
/// the screen. Five arms, a black core, no white-hot flare. No spinner, no skeleton, no
/// fake progress bar — the panel says what it is reading instead.
struct ThinkingStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The question, echoed at the top: an LED has no input field, and without the echo
    /// nobody remembers what they just asked.
    var question: String = ""
    /// What she is reading right now, named as she reads it.
    var reading: String?
    var startedAt: Date = Date()

    private static let arms = 5

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSince(startedAt)
            VStack(spacing: 0) {
                header(elapsed: t)
                if !question.isEmpty {
                    Text("\"\(question.uppercased())\"")
                        .font(NBFont.dot(500, 11)).tracking(0.16 * 11)
                        .foregroundStyle(NB.white.opacity(0.42))
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 22)
                        .padding(.top, 26)
                }
                Spacer(minLength: 0)
                Canvas { ctx, size in draw(&ctx, size: size, t: reduceMotion ? 0 : t) }
                    .frame(height: 260)
                Spacer(minLength: 0)
                Text(readingLine)
                    .font(NBFont.dot(600, 13)).tracking(0.20 * 13)
                    .foregroundStyle(NB.white.opacity(0.78))
                Text(sourceLine)
                    .font(NBFont.dot(500, 9)).tracking(0.14 * 9)
                    .foregroundStyle(NB.white.opacity(0.34))
                    .padding(.top, 8)
                    .padding(.bottom, 30)
            }
        }
    }

    private func header(elapsed: Double) -> some View {
        HStack(spacing: 0) {
            Text("THINKING")
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(NB.lime1)
            Spacer(minLength: 0)
            Text(String(format: "%.1fS", max(0, elapsed)))
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.30))
                .monospacedDigit()
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    /// The tool she is on, in the board's words rather than the wire's.
    private var readingLine: String {
        switch reading {
        case .none:                       return "PULLING YOUR WEEK IN"
        case .some(let t) where t.hasPrefix("screen.render"): return "DRAWING IT"
        case .some(let t) where t.hasPrefix("series"):        return "PULLING YOUR WEEK IN"
        case .some(let t) where t.hasPrefix("day"):           return "READING TODAY"
        case .some(let t) where t.hasPrefix("meals"):         return "READING YOUR PLATES"
        case .some(let t) where t.hasPrefix("profile"):       return "READING YOUR PROFILE"
        case .some(let t) where t.hasPrefix("device"):        return "ASKING THE BAND"
        case .some(let t) where t.hasPrefix("measurement"):   return "READING YOUR SCANS"
        case .some:                                           return "PULLING YOUR WEEK IN"
        }
    }
    private var sourceLine: String { "SLEEP · HRV · STRESS · 7 DAYS" }

    /// Five arms of dots on a logarithmic spiral, wound inward. Every arm shares the core's
    /// rotation, so the whole field turns as one body rather than as five loops.
    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let rMax = min(size.width, size.height) * 0.46
        let core = rMax * 0.19
        let spin = t * 0.42

        for arm in 0..<Self.arms {
            let phase = Double(arm) * (.pi * 2 / Double(Self.arms))
            // 26 dots an arm, packed tighter as they near the core — matter piling up.
            for i in 0..<26 {
                let u = Double(i) / 25.0
                let r = core + (rMax - core) * pow(1 - u, 1.7)
                let a = phase + spin + u * 2.4
                let x = c.x + CGFloat(cos(a)) * CGFloat(r)
                let y = c.y + CGFloat(sin(a)) * CGFloat(r) * 0.86
                // Bright at the rim of the core, fading out at the far end of the arm.
                let alpha = 0.10 + 0.70 * pow(1 - u, 1.6)
                let d: CGFloat = u < 0.25 ? 4 : 3
                ctx.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                         with: .color(NB.lime1.opacity(alpha)))
            }
        }
        // The core: a lime ring of dots around a hole the panel shows through.
        for i in 0..<40 {
            let a = spin * 1.6 + Double(i) * (.pi * 2 / 40)
            let x = c.x + CGFloat(cos(a)) * CGFloat(core)
            let y = c.y + CGFloat(sin(a)) * CGFloat(core) * 0.94
            ctx.fill(Path(ellipseIn: CGRect(x: x - 2.4, y: y - 2.4, width: 4.8, height: 4.8)),
                     with: .color(NB.lime1.opacity(0.92)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - core + 3, y: c.y - core * 0.94 + 3,
                                        width: (core - 3) * 2, height: (core * 0.94 - 3) * 2)),
                 with: .color(NB.panelInk))
    }
}
