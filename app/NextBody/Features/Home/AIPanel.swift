import SwiftUI

/// 04 + 07 · the panel. 358 × 470, the only place she speaks.
/// One widget at a time; every widget is tappable and carries the page it lands on (F0 rule 06).
struct AIPanel: View {
    @ObservedObject private var consent = ConsentStore.shared
    /// 07 · 16 · she names the tool she is on while the singularity turns.
    @ObservedObject private var ai = AIService.shared
    /// 04 · the band measuring right now. While this resting face is what the user is
    /// looking at, HomeView keeps the session open (`liveReadoutWanted`) and HR / STRESS are
    /// the wrist, not the library. The tick is what they fall back to the moment it closes.
    @ObservedObject private var live = LiveReadout.shared
    @ObservedObject private var syncActivity = BandSyncActivity.shared
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
    var onDismissWidget: () -> Void = {}
    let onWidget: (Destination) -> Void

    private var ceremony: Bool { firstRun?.playing == true }
    var body: some View {
        ZStack {
            // Idle planet and an AI frame must not share this ZStack. Two sibling
            // if-chains used to disagree (photo still drew StandbyArt) and the
            // widget's opacity transition composited them — that is the overlap.
            Group {
                if let firstRun, ceremony {
                    ceremonyPlate(firstRun)
                } else if let widget {
                    occupiedPlate(widget)
                } else {
                    idlePlate
                }
            }
            .transaction { $0.animation = nil }

            if widget != nil, !ceremony {
                Button(action: onDismissWidget) {
                    PixelCloseMark()
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Return to standby"))
                .accessibilityIdentifier("panel-dismiss")
                .accessibilitySortPriority(100)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 8)
                .padding(.trailing, 2)
                .zIndex(10)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(NB.panelInk)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(widget?.composition != nil ? NB.lime1.opacity(0.18)
                    : NB.white.opacity(ceremony ? 0 : 0.08), lineWidth: 1))
    }

    @ViewBuilder private func ceremonyPlate(_ firstRun: FirstRun) -> some View {
        ZStack {
            HalftoneScreen {
                FirstRunArt(coreLit: firstRun.coreLit,
                            orbitFraction: firstRun.orbitFraction,
                            spinning: firstRun.orbitSpinning)
            }
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
        }
    }

    /// One surface. The planet is not in this tree.
    @ViewBuilder private func occupiedPlate(_ widget: PanelWidget) -> some View {
        ZStack {
            if widget.title != "THINKING", widget.composition == nil, widget.photo == nil, widget.balance == nil {
                // 07 · the widget is printed, not lit. Chart behind the dot screen, words in front.
                HalftoneScreen {
                    ZStack {
                        NB.ledOff
                        widgetLayer(widget, .chart)
                    }
                }
            } else {
                HalftoneScreen { NB.ledOff }
            }

            if widget.title == "THINKING" {
                ThinkingStage(question: widget.sentence, reading: ai.reading, thoughts: ai.thoughts, startedAt: widget.startedAt)
            } else {
                filledWidget(widget)
            }
        }
    }

    @ViewBuilder private var idlePlate: some View {
        ZStack {
            HalftoneScreen {
                StandbyArt(
                    charge: m.bodyBattery.map { Double($0) / 100 } ?? 0,
                    chargeKnown: m.bodyBattery != nil
                )
            }
            if !consent.granted {
                // 补屏 edge 1 / 2 · NOT COLLECTING. 「—— 是沉默」 at its limit.
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(L("NOT COLLECTING"))
                            .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                            .foregroundStyle(NB.ember1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 22)
                    Spacer(minLength: 0)
                    VStack(spacing: 14) {
                        Text(L("HOOP isn't reading anything yet."))
                            .font(NBFont.brand(400, 18)).tracking(-0.01 * 18)
                            .foregroundStyle(NB.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                        Button(action: onTurnOn) {
                            Text(L("Turn it on"))
                                .font(NBFont.ui(500, 13.5)).tracking(0.15 * 13.5)
                                .foregroundStyle(NB.carbon)
                                .frame(height: 44)
                                .padding(.horizontal, 26)
                                .background(NB.ember1, in: Capsule())
                        }
                        .buttonStyle(HotZoneTap(pressedScale: 1))
                        .accessibilityHint(L("Opens the consent screen"))
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
    }

    private func filledWidget(_ widget: PanelWidget) -> some View {
        // Self-contained result canvases draw once above the shared LED surface.
        widgetLayer(widget, widget.composition == nil && widget.photo == nil && widget.balance == nil ? .text : .all)
    }

    /// One layer of the widget on the board's 358 × 470 canvas, scaled to the panel the
    /// phone left. The chart layer and the text layer use the same transform, so the words
    /// land exactly over their LEDs.
    private func widgetLayer(_ widget: PanelWidget, _ layer: PanelWidgetView.Layer) -> some View {
        let bw = NB.Layout.boardContentWidth
        let bh = NB.Layout.panelHeight
        let scale = min(size.width / bw, size.height / bh)
        let canvasHeight = widget.balance != nil ? size.height / scale : bh
        return PanelWidgetView(widget: widget, onTap: onWidget, layer: layer,
                               showsCloseControl: true, canvasHeight: canvasHeight)
            .frame(width: bw, height: canvasHeight)
            .scaleEffect(scale)
            .frame(width: size.width, height: size.height)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(L(headerLine))
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(headerTint)
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
                        Text(L("%"))
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
                // 04 · the pip beats at the rate that was just measured, and only when the
                // number under it came off the wrist seconds ago. It is the number told
                // again — the one animation here that is not decoration.
                vitalsColumn(Fmt.int(readout.hr), label: L("HR"), beat: live.liveHR)
                vitalsColumn(Fmt.int(readout.stress), label: L("STRESS"),
                             live: live.liveStress != nil, working: live.phase == .stress)
            }
            .padding(.top, 12)

            Text(L("%@ · TAP OR TALK — I'M UP", sourceLine))
                .font(NBFont.dot(500, 10.5)).tracking(0.18 * 10.5)
                .foregroundStyle(NB.white.opacity(0.42))
                .padding(.top, 10)
        }
    }

    /// 04 · one vitals slot: the reading above its label, centred in a fixed column so
    /// HR and STRESS stay put as the numbers change width. A number measured this second is
    /// lime and carries a pip; a number read out of the library is white, as it always was.
    /// `working` is the stress test running — the value under it is the previous one, ageing.
    private func vitalsColumn(_ value: String, label: String,
                              live isLive: Bool = false, beat: Int? = nil,
                              working: Bool = false) -> some View {
        let lit = isLive || beat != nil
        return VStack(spacing: 4) {
            Text(value).font(NBFont.dot(700, 28)).tracking(0.04 * 28)
                .foregroundStyle(lit ? NB.lime1 : NB.white.opacity(working ? 0.55 : 0.9))
                .contentTransition(.numericText())
            HStack(spacing: 5) {
                if let beat { BeatPip(bpm: beat) }
                Text(label).font(NBFont.dot(600, 10.5)).tracking(0.2 * 10.5)
                    .foregroundStyle(NB.white.opacity(lit ? 0.72 : 0.5))
            }
        }
        .frame(width: 96)
        .animation(.easeInOut(duration: 0.2), value: value)
    }

    /// 13 · past six hours the tick's numbers are gone, not dimmed and not carried forward.
    /// 04 · a live reading outranks the tick, and each half falls back on its own: the stress
    /// test runs on a cadence, so a live HR beside a stored STRESS is the normal case.
    private var readout: (hr: Int?, stress: Int?) {
        let tick: (hr: Int?, stress: Int?) = vitals.freshness == .gone ? (nil, nil)
                                                                       : (vitals.hr, vitals.stress)
        return (live.liveHR ?? tick.hr, live.liveStress ?? tick.stress)
    }

    /// 04 · the state word. OFFLINE is the link, NO CONTACT is the wrist, and LIVE is only
    /// said while the band is actually answering — never as a label for a stored number.
    private var headerLine: String {
        let phase: String
        switch live.phase {
        case .live: phase = live.liveHR == nil ? "reaching" : "live"
        case .stress: phase = "stress"
        case .reaching: phase = "reaching"
        case .noContact: phase = "noContact"
        case .off, .offline: phase = "off"
        }
        return L(BandSyncPolicy.header(activity: syncActivity.phase,
                                      connected: band.connected, live: phase))
    }

    private var headerTint: Color {
        if syncActivity.phase != "idle" { return NB.lime1 }
        guard band.connected else { return NB.white.opacity(0.55) }
        switch live.phase {
        case .live where live.liveHR != nil, .stress: return NB.lime1
        case .noContact:                              return NB.ember1
        default:                                      return NB.white.opacity(0.55)
        }
    }

    /// 04 · where the two numbers come from, said in three words. The moment the session
    /// closes this goes back to the age of the tick, which is the only other thing they
    /// could be — nothing here ever calls a stored number "now".
    private var sourceLine: String {
        guard band.connected else { return agoText }
        switch live.phase {
        case .live where live.liveHR != nil: return L("LIVE")
        // 04 · the stress test holds the sensor for 19 s. The percentage is the band's own
        // count, not a tween over an expected duration — it stops when the band stops.
        case .stress:                        return live.stressProgress.map { L("MEASURING STRESS · %d%%", $0) }
                                                 ?? L("MEASURING STRESS")
        case .reaching, .live:               return L("REACHING FOR A BEAT")
        case .noContact:                     return L("PUT THE HOOP BACK ON")
        case .off, .offline:                 return agoText
        }
    }

    /// ⚠️ 1CVO · the only prediction on the product, and it renders only when all four of
    /// board 13's conditions hold. Otherwise the row is empty — never a placeholder, and
    /// never a discharge sentence the board never wrote.
    private var chargeLine: String {
        guard m.bodyBattery != nil else { return L("NO NIGHT ON RECORD") }
        if vitals.freshness == .stale, let at = vitals.at {
            return L("SYNCED %@", Fmt.clock(at))
        }
        return ChargeForecast.line(curve: m.reserveCurve) ?? ""
    }

    private var agoText: String {
        guard let at = vitals.at else { return L("NO TICK") }
        let mins = max(0, Int(Date().timeIntervalSince(at) / 60))
        if mins < 1 { return L("JUST NOW") }
        if mins < 60 { return L("%d MIN AGO", mins) }
        return L("%d HR AGO", mins / 60)
    }
}

/// 04 · THE PIP. It blinks at the rate the band just reported: 68 BPM is one blink every
/// 0.88 s. Nothing here is invented — the period is the number — which is why it is a pip
/// and not a spinner: a spinner would turn at the same speed for a resting wrist and a
/// sprint. Reduce Motion gets a steady dot, because the fact it carries is "this is live"
/// and that fact does not need to move.
private struct BeatPip: View {
    let bpm: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Clamped to what a wrist can report; a garbled value must not stall or strobe it.
        let period = 60 / Double(min(220, max(35, bpm)))
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let phase = t.truncatingRemainder(dividingBy: period) / period
            // A beat, not a fade: bright on the upstroke, decaying across the rest of it.
            let glow = pow(1 - phase, 2.2)
            Circle()
                .fill(NB.lime1)
                .frame(width: 6, height: 6)
                .opacity(reduceMotion ? 0.9 : 0.22 + 0.78 * glow)
        }
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)
    }
}

/// 07 · 16 · 02 · THINKING — the singularity.
///
/// The board reuses Connect 04's gravitational collapse on purpose: idle → thinking has to
/// read as one planet being pulled in, not as a page change, or the user thinks they left
/// the screen. Five arms, a black core, no spinner, no skeleton, no fake progress bar.
///
/// The foot of the panel is her own reasoning. The server cuts the model's reasoning stream
/// into lines and each one lands here the moment it is whole: typed out behind a lime
/// cursor, the line above lifting a step and dropping a grey, four kept, the fifth pushing
/// the oldest off. No status label stands in for her — a turn that streams no thoughts
/// names the tool it is reading, and nothing pretends to be a thought.
///
/// The disk answers the stream: every thought that lands sends one ring out from the core.
struct ThinkingStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The question, echoed at the top: an LED has no input field, and without the echo
    /// nobody remembers what they just asked.
    var question: String = ""
    /// What she is reading right now, named as she reads it — the fallback line.
    var reading: String?
    /// Her reasoning, oldest first, as the server streamed it.
    var thoughts: [AIService.Thought] = []
    var startedAt: Date = Date()

    private static let arms = 5
    /// Lines the foot holds. A fifth arrival pushes the first off.
    private static let shown = 4
    /// Characters a second while a line types out. Faster than reading, slower than a paste.
    private static let typeRate = 46.0
    /// How long the ring a thought sends out lives.
    private static let pulseLife = 1.4

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let now = tl.date
            let t = now.timeIntervalSince(startedAt)
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
                let pulses = reduceMotion ? [] : thoughts.map { now.timeIntervalSince($0.at) }
                    .filter { $0 >= 0 && $0 < Self.pulseLife }
                // The disk takes whatever height the header and the four lines leave — a
                // fixed 260 pushed the header off the top of a shorter phone's panel.
                Canvas { ctx, size in draw(&ctx, size: size, t: reduceMotion ? 0 : t, pulses: pulses) }
                    .frame(maxHeight: .infinity)
                stream(now: now)
            }
            // 07 · 16 · 02 · the stream you can feel. One hair-light tap under the characters
            // as the live line types itself out, a rounder one when a line is whole.
            .onChange(of: typedCount(now: now)) { old, new in
                if new > old { StreamHaptics.shared.type() }
            }
            .onChange(of: thoughts.last?.id) { _, _ in StreamHaptics.shared.lineLanded() }
        }
        .onAppear { StreamHaptics.shared.activate() }
        .onDisappear {
            StreamHaptics.shared.deactivate()
            // Leaving THINKING means the frame is drawn: one crisp tap for the answer.
            StreamHaptics.shared.settled()
        }
    }

    /// How much of the live line has been typed, as a number the view can watch. The rest of
    /// the stack is already whole, so only the newest line can produce a character.
    private func typedCount(now: Date) -> Int {
        guard let last = thoughts.last else { return 0 }
        if reduceMotion { return last.text.count }
        return min(last.text.count, Int(max(0, now.timeIntervalSince(last.at)) * Self.typeRate))
    }

    private func header(elapsed: Double) -> some View {
        HStack(spacing: 0) {
            Text(L("THINKING"))
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(NB.lime1)
            Spacer(minLength: 0)
            Text(String(format: "%.1fS", max(0, elapsed)))
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.30))
                .monospacedDigit()
        }
        .padding(.leading, 22)
        .padding(.trailing, 64)
        .padding(.top, 16)
    }

    // MARK: the thought stream

    private static let lineH: CGFloat = 14, lineGap: CGFloat = 7
    /// Seconds the stack takes to settle after a line lands.
    private static let lift = 0.4

    /// The foot holds four lines. A new line lands one step below the frame and the whole
    /// stack slides up to make room, the oldest line leaving through the top as it goes. The
    /// slide is a function of the newest line's age, not a SwiftUI transition: the timeline
    /// redraws every frame, and a transition's ghost rows were stacking up under the panel.
    private func stream(now: Date) -> some View {
        // Nothing streamed yet: the tool she is on, dimmed so it does not pass for a thought,
        // with the cursor waiting behind it.
        let rows: [(text: String, at: Date, dim: Double)] = thoughts.isEmpty
            ? [(readingLine, startedAt, 0.55)]
            : thoughts.suffix(Self.shown + 1).map { ($0.text, $0.at, 1) }
        let age = reduceMotion ? Self.lift : max(0, now.timeIntervalSince(rows[rows.count - 1].at))
        let settle = min(1, age / Self.lift)
        let eased = 1 - pow(1 - settle, 3)
        let step = Self.lineH + Self.lineGap
        // Five rows means the top one is on its way out.
        let leaving = rows.count > Self.shown
        return VStack(alignment: .leading, spacing: Self.lineGap) {
            ForEach(rows.indices, id: \.self) { i in
                let rank = rows.count - 1 - i
                let out = leaving && i == 0
                line(rows[i].text, live: rank == 0, rank: rank, at: rows[i].at, now: now,
                     dim: rows[i].dim * (out ? 1 - eased : rank == 0 ? eased : 1))
            }
        }
        .offset(y: CGFloat(1 - eased) * step)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CGFloat(Self.shown) * Self.lineH + CGFloat(Self.shown - 1) * Self.lineGap,
               alignment: .bottom)
        .clipped()
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }

    /// One line at the foot. `rank` is its distance from the live line: each step up drops a grey.
    private func line(_ text: String, live: Bool, rank: Int, at: Date, now: Date, dim: Double = 1) -> some View {
        let upper = text.uppercased()
        let typed = reduceMotion ? upper.count
            : min(upper.count, Int(max(0, now.timeIntervalSince(at)) * Self.typeRate))
        let shown = live ? String(upper.prefix(typed)) : upper
        let ladder: [Double] = [0.95, 0.55, 0.32, 0.18]
        let alpha = ladder[min(rank, ladder.count - 1)] * dim
        // Solid while a line types, blinking once it is out and she is on the next one.
        let typing = live && typed < upper.count
        let blink = Int(now.timeIntervalSinceReferenceDate * 2.4) % 2 == 0
        return HStack(spacing: 6) {
            Text(shown)
                .font(live ? NBFont.dot(600, 12) : NBFont.dot(500, 11))
                .tracking((live ? 0.16 : 0.14) * (live ? 12 : 11))
                .foregroundStyle(NB.white.opacity(alpha))
                .lineLimit(1).truncationMode(.tail)
            if live {
                Rectangle().fill(NB.lime1)
                    .frame(width: 6, height: 12)
                    .opacity(typing || blink || reduceMotion ? 1 : 0.15)
            }
        }
        .frame(height: Self.lineH)
    }

    /// The tool she is on, in the board's words rather than the wire's.
    private var readingLine: String {
        switch reading {
        case .none:                       return L("PULLING YOUR WEEK IN")
        case .some(let t) where t.hasPrefix("screen.render"): return L("DRAWING IT")
        case .some(let t) where t.hasPrefix("series"):        return L("PULLING YOUR WEEK IN")
        case .some(let t) where t.hasPrefix("day"):           return L("READING TODAY")
        case .some(let t) where t.hasPrefix("meals"):         return L("READING YOUR PLATES")
        case .some(let t) where t.hasPrefix("profile"):       return L("READING YOUR PROFILE")
        case .some(let t) where t.hasPrefix("device"):        return L("ASKING THE BAND")
        case .some(let t) where t.hasPrefix("measurement"):   return L("READING YOUR SCANS")
        case .some:                                           return L("PULLING YOUR WEEK IN")
        }
    }

    // MARK: the singularity

    /// A black hole seen from a little above its disk. Five arms of matter slide down a
    /// logarithmic spiral into the core and are replaced at the rim; the side of the disk
    /// coming toward us runs hotter (Doppler); the light from the far side is bent over
    /// and under the hole as two thin arcs; a photon ring hugs the horizon with a wave of
    /// brightness running round it. Behind all of it, a still field of faint stars.
    /// One colour, lime, at many brightnesses — the pale lime is the hottest point only.
    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, pulses: [Double]) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2 + 4)
        // The board's disk is r150 on a 358-wide panel; a taller panel does not grow it past that.
        let rMax = min(150, min(size.width, size.height) * 0.55)
        let core = rMax * 0.19
        // The disk is seen from above at a lean — flattened, and turned a little off the
        // horizontal so it never reads as an eye. The hole and the bent light stay upright.
        let tilt: CGFloat = 0.68
        let lean = -16.0 * .pi / 180
        let (lc, ls) = (CGFloat(cos(lean)), CGFloat(sin(lean)))
        func onDisk(_ a: Double, _ r: CGFloat) -> CGPoint {
            let x = CGFloat(cos(a)) * r, y = CGFloat(sin(a)) * r * tilt
            return CGPoint(x: c.x + x * lc - y * ls, y: c.y + x * ls + y * lc)
        }
        let spin = t * 0.42

        func dot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat, _ alpha: Double, _ color: Color = NB.lime1) {
            ctx.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                     with: .color(color.opacity(max(0, min(1, alpha)))))
        }

        // Stars. Fixed positions from the index, each breathing at its own slow rate.
        for i in 0..<64 {
            let h = Self.scatter(i)
            let breathe = 0.65 + 0.35 * sin(t * (0.5 + h.2 * 1.3) + h.3 * .pi * 2)
            dot(CGFloat(h.0) * size.width, CGFloat(h.1) * size.height, 1.5, (0.04 + 0.11 * h.3) * breathe)
        }

        // The far side's light, bent over the top of the hole and under it.
        for (over, base) in [(true, 0.34), (false, 0.16)] {
            let rr = core * 1.78
            for i in 0..<34 {
                let f = Double(i) / 33.0
                let a = (over ? .pi : 0) + 0.32 + f * (.pi - 0.64)
                let envelope = sin(f * .pi)
                let glide = 0.75 + 0.25 * sin(a * 2 + t * 1.4)
                dot(c.x + CGFloat(cos(a)) * rr, c.y + CGFloat(sin(a)) * rr * 0.92, 2.6, base * envelope * glide)
            }
        }

        // The disk. Two passes so the near half crosses in front of the hole.
        struct Grain { let x: CGFloat; let y: CGFloat; let d: CGFloat; let alpha: Double; let near: Bool }
        var grains: [Grain] = []
        grains.reserveCapacity(Self.arms * 30)
        for arm in 0..<Self.arms {
            let phase = Double(arm) * (.pi * 2 / Double(Self.arms))
            for i in 0..<30 {
                // Matter slides down the arm: u runs 0 (rim) → 1 (core) and wraps.
                let u = (Double(i) / 30.0 + t * 0.045).truncatingRemainder(dividingBy: 1)
                let r = core * 1.22 + (rMax - core * 1.22) * pow(1 - u, 1.7)
                let a = phase + spin + u * 2.6
                let ca = cos(a), sa = sin(a)
                // Hotter toward the core; hotter on the side coming toward us.
                var alpha = (0.06 + 0.70 * pow(u, 1.4)) * (1 + 0.42 * ca)
                // Born dim at the rim, gone dim at the horizon, so the wrap is never seen.
                alpha *= min(1, u * 9, (1 - u) * 9)
                let p = onDisk(a, CGFloat(r))
                grains.append(Grain(x: p.x, y: p.y, d: u > 0.72 ? 3.6 : 2.8, alpha: alpha, near: sa > 0))
            }
        }
        for g in grains where !g.near { dot(g.x, g.y, g.d, g.alpha) }

        // The hole, and the photon ring around it with a wave of heat running round.
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core * 0.96, width: core * 2, height: core * 1.92)),
                 with: .color(NB.panelInk))
        for i in 0..<40 {
            let a = spin * 1.6 + Double(i) * (.pi * 2 / 40)
            let heat = 0.5 + 0.5 * sin(a * 3 - t * 3.2)
            let x = c.x + CGFloat(cos(a)) * core, y = c.y + CGFloat(sin(a)) * core * 0.96
            dot(x, y, 4.6, 0.55 + 0.4 * heat, heat > 0.92 ? NB.limePale : NB.lime1)
        }

        for g in grains where g.near { dot(g.x, g.y, g.d, g.alpha) }

        // A thought landed: one ring leaves the core along the disk and fades.
        for age in pulses {
            let f = age / Self.pulseLife
            let rr = core * 1.3 + CGFloat(f) * (rMax - core * 1.3) * 1.05
            let alpha = 0.6 * pow(1 - f, 1.6)
            for i in 0..<48 {
                let p = onDisk(Double(i) * (.pi * 2 / 48) + spin, rr)
                dot(p.x, p.y, 2.6, alpha)
            }
        }
    }

    /// Four fixed pseudo-random numbers in 0…1 for star `i` — the same sky every frame.
    private static func scatter(_ i: Int) -> (Double, Double, Double, Double) {
        func f(_ k: Double) -> Double {
            let v = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
            return v - floor(v)
        }
        return (f(1), f(2), f(3), f(4))
    }
}
