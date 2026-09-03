import SwiftUI

/// 04 + 07 · the panel. 358 × 470, the only place she speaks.
/// One widget at a time; every widget is tappable and carries the page it lands on (F0 rule 06).
struct AIPanel: View {
    @ObservedObject private var consent = ConsentStore.shared
    /// 补屏 · the NOT COLLECTING button. The panel does not own the router.
    var onTurnOn: () -> Void = {}
    let m: DailyMetrics
    let band: BandState
    let lastSync: Date?
    /// 04 · the last five-minute tick. Its age decides whether the readout prints, dims,
    /// or dashes (13 · CURVE STOPS AT THE LAST REAL TICK).
    var vitals: LiveVitals = .mock
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
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    ThinkingStage()
                }
                .padding(.vertical, 16)
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
        let bw = NB.Layout.boardContentWidth
        let bh = NB.Layout.panelHeight
        let scale = min(size.width / bw, size.height / bh)
        return PanelWidgetView(widget: widget, onTap: onWidget)
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
    private var standbyReadout: some View {
        VStack(spacing: 0) {
            Hairline().frame(width: 236)
                .padding(.bottom, 12)

            Button {
                onWidget(.bodyBattery)
            } label: {
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
            }
            .buttonStyle(.plain)

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

/// 07 · 16 · the universe state while she works. No spinner, no skeleton, no fake progress —
/// the panel keeps its own dot field and lets one lime pixel travel.
struct ThinkingStage: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            VStack(spacing: 22) {
                Canvas { ctx, size in
                    let cx = size.width / 2, cy = size.height / 2
                    for i in 0..<9 {
                        let a = t * 0.8 + Double(i) * (.pi * 2 / 9)
                        let r = 26 + CGFloat(i) * 5
                        let x = cx + r * CGFloat(cos(a))
                        let y = cy + r * CGFloat(sin(a)) * 0.55
                        let alpha = 0.25 + 0.6 * (1 - Double(i) / 9)
                        ctx.fill(Path(CGRect(x: x - 2, y: y - 2, width: 4, height: 4)),
                                 with: .color(NB.lime1.opacity(alpha)))
                    }
                }
                .frame(height: 120)

                Text("THINKING")
                    .font(NBFont.dot(600, 11)).tracking(0.34 * 11)
                    .foregroundStyle(NB.white.opacity(0.42))
            }
            .padding(.bottom, 60)
        }
    }
}
