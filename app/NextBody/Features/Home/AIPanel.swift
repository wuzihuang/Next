import SwiftUI

/// 04 + 07 · the panel. 358 × 470, the only place she speaks.
/// One widget at a time; every widget is tappable and carries the page it lands on (F0 rule 06).
struct AIPanel: View {
    let m: DailyMetrics
    let band: BandState
    let lastSync: Date
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
            } else {
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
                PanelWidgetView(widget: widget, onTap: onWidget)
                    .transition(.opacity)
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
            .stroke(NB.white.opacity(ceremony ? 0 : 0.08), lineWidth: 1))
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
    private var standbyReadout: some View {
        VStack(spacing: 0) {
            Hairline().frame(width: 236)
                .padding(.bottom, 15)

            Button {
                onWidget(.bodyBattery)
            } label: {
                VStack(spacing: 0) {
                    Text("\(MetricNames.bodyBattery) \(Fmt.pct(m.bodyBattery))")
                        .font(NBFont.dot(700, 15)).tracking(0.1 * 15)
                        .foregroundStyle(NB.lime1)
                        .frame(height: 18)
                    Text(chargeLine)
                        .font(NBFont.dot(500, 11)).tracking(0.16 * 11)
                        .foregroundStyle(NB.white.opacity(0.45))
                        .frame(height: 14)
                        .padding(.top, 8)
                }
            }
            .buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                readoutLabel("HR")
                readoutValue(Fmt.int(readout.hr))
                readoutDot
                readoutLabel("STRESS")
                readoutValue(Fmt.int(readout.stress))
                readoutDot
                Text(agoText)
                    .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.white.opacity(0.34))
            }
            .padding(.top, 10)

            Text("TAP OR TALK — I'M UP")
                .font(NBFont.dot(500, 10)).tracking(0.2 * 10)
                .foregroundStyle(NB.white.opacity(0.28))
                .padding(.top, 14)
        }
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

    private func readoutLabel(_ s: String) -> some View {
        Text(s).font(NBFont.dot(500, 10)).tracking(0.18 * 10)
            .foregroundStyle(NB.white.opacity(0.38))
    }
    private func readoutValue(_ s: String) -> some View {
        Text(s).font(NBFont.dot(700, 13)).tracking(0.06 * 13)
            .foregroundStyle(NB.white.opacity(0.82))
    }
    private var readoutDot: some View {
        Text("·").font(NBFont.dot(500, 10)).foregroundStyle(NB.white.opacity(0.2))
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
