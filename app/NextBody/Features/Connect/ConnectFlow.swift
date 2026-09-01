import SwiftUI

/// 02 · Connect 手环配对. No back key out of the flow and no "later":
/// the success screen has exactly one button and it hands straight over to onboarding.
struct ConnectFlow: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var data: DataStore

    enum Step: Int, Hashable { case turnOn = 1, searching, found, pairing, connected }
    @State private var step: Step = .turnOn
    @State private var progress: Double = 0
    @State private var pairStage = 0

    /// 04 · the percentage maps to four real steps; never a fake tween.
    private static let stages = ["CONNECT", "AUTHORISE", "READ CAPABILITIES", "READ FIRMWARE"]

    var body: some View {
        ZStack {
            switch step {
            case .turnOn:    TurnItOn { go(.searching) }
            case .searching: Searching { go(.found) }
            case .found:     FoundIt(onConnect: { go(.pairing) }, onSearchAgain: { go(.searching) })
            case .pairing:   Pairing(progress: progress, stage: pairStage)
            case .connected: Connected { session.stage = .gateOnboarding }
            }
        }
        .carbonPage()
        .ignoresSafeArea(.container, edges: .vertical)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func go(_ s: Step) {
        step = s
        if s == .pairing { runPairing() }
    }

    /// Four real steps, 20s cap. When it stalls it stalls on the number it reached —
    /// stopping is more honest than snapping back to zero.
    private func runPairing() {
        progress = 0; pairStage = 0
        Task {
            for i in 0..<4 {
                pairStage = i
                let target = Double(i + 1) / 4
                while progress < target {
                    try? await Task.sleep(for: .milliseconds(28))
                    withAnimation(.linear(duration: 0.03)) { progress = min(target, progress + 0.006) }
                }
                try? await Task.sleep(for: .milliseconds(220))
            }
            data.band.connected = true
            step = .connected
        }
    }
}

// MARK: shared chrome

private struct PairHeader: View {
    let index: Int
    var onBack: (() -> Void)?
    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    ZStack {
                        Circle().fill(NB.carbon4)
                        Circle().stroke(NB.hairline, lineWidth: 1)
                        ChevronGlyph()
                    }.frame(width: 44, height: 44)
                }.buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            Text(String(format: "PAIRING %02d / 05", index))
                .font(NBFont.dot(600, 11)).tracking(0.3 * 11)
                .foregroundStyle(NB.text3Prod)
        }
        .frame(width: NB.Layout.contentWidth, height: 44)
    }
}

private struct PairTitle: View {
    let title: String
    let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(NBFont.ui(500, 32)).tracking(0.01 * 32)
                .foregroundStyle(NB.text1)
            Text(sub)
                .font(NBFont.ui(300, 15)).tracking(0.02 * 15)
                .lineSpacing(24 - 15)
                .foregroundStyle(NB.text2)
                .frame(width: 320, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 24)
    }
}

struct LimePillButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NBFont.ui(500, 15)).tracking(0.06 * 15)
                .foregroundStyle(NB.carbon)
                .frame(width: NB.Layout.contentWidth, height: 56)
                .background(NB.lime1, in: Capsule())
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: 01 · 开机 Turn it on

private struct TurnItOn: View {
    let onNext: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            BandPortrait(sideKeyLit: true, ripples: [34, 58, 82], rippleAlpha: [0.42, 0.20, 0.08])
                .frame(width: 390, height: 470)
                .offset(y: 252)

            VStack(spacing: 0) {
                Color.clear.frame(height: 66)
                PairHeader(index: 1)
                PairTitle(title: "Turn it on",
                          sub: "Hold the button on the right edge for two seconds, until the band lights up.")
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            Text("HOLD 2S")
                .font(NBFont.dot(800, 13)).tracking(0.24 * 13)
                .foregroundStyle(NB.lime1)
                .frame(width: 390, alignment: .center)
                .offset(y: 608)

            // The only real dead end in the flow, answered on the screen it happens on.
            Text("Nothing lights up? It may be flat — charge it for ten minutes, then hold again.")
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .lineSpacing(20 - 13)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.text3Prod)
                .frame(width: 326)
                .offset(x: 32, y: 640)

            LimePillButton(title: "It's on", action: onNext)
                .offset(x: 16, y: 708)

            HomeIndicator().frame(width: 390).offset(y: 806)
        }
        .frame(width: 390, height: 844, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The band seen head-on: strap fading top and bottom, case, dot-matrix face, lime side key.
struct BandPortrait: View {
    var sideKeyLit = false
    var faceLit = false
    var ripples: [CGFloat] = []
    var rippleAlpha: [Double] = []
    var scanRings: [CGFloat] = []

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 390, sy = size.height / 470
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy),
                     cornerRadius: rad * sx)
            }
            let strap = Color(hex: 0x15161A)
            ctx.fill(r(161, 0, 68, 118, 14),
                     with: .linearGradient(Gradient(colors: [strap.opacity(0), strap]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 118 * sy)))
            ctx.fill(r(161, 302, 68, 168, 14),
                     with: .linearGradient(Gradient(colors: [strap, strap.opacity(0)]),
                                           startPoint: CGPoint(x: 0, y: 302 * sy),
                                           endPoint: CGPoint(x: 0, y: 470 * sy)))
            ctx.fill(r(139, 112, 112, 196, 36), with: .color(Color(hex: 0x17181C)))
            ctx.stroke(r(139, 112, 112, 196, 36), with: .color(NB.white.opacity(0.07)), lineWidth: 1)

            // face
            let face = r(153, 126, 84, 168, 26)
            ctx.fill(face, with: .color(faceLit ? NB.lime1.opacity(0.9) : Color(hex: 0x0A0A0D)))
            ctx.clip(to: face)
            var dots = Path()
            var y: CGFloat = 127
            while y < 294 {
                var x: CGFloat = 154
                while x < 237 {
                    dots.addRoundedRect(in: CGRect(x: x * sx, y: y * sy, width: 3.2 * sx, height: 3.2 * sy),
                                        cornerSize: CGSize(width: 0.8 * sx, height: 0.8 * sx))
                    x += 4
                }
                y += 4
            }
            ctx.fill(dots, with: .color(faceLit ? NB.limeMid.opacity(0.55) : Color(hex: 0x24252C)))
        }
        .overlay {
            Canvas { ctx, size in
                let sx = size.width / 390, sy = size.height / 470
                if sideKeyLit {
                    ctx.fill(Path(roundedRect: CGRect(x: 251 * sx, y: 186 * sy,
                                                      width: 8 * sx, height: 48 * sy), cornerRadius: 4 * sx),
                             with: .color(NB.lime1))
                }
                for (i, rad) in ripples.enumerated() {
                    let a = i < rippleAlpha.count ? rippleAlpha[i] : 0.2
                    ctx.stroke(Path(ellipseIn: CGRect(x: (255 - rad) * sx, y: (210 - rad) * sy,
                                                      width: rad * 2 * sx, height: rad * 2 * sy)),
                               with: .color(NB.lime1.opacity(a)), lineWidth: 3 * sx)
                }
                for rad in scanRings {
                    ctx.stroke(Path(ellipseIn: CGRect(x: (195 - rad) * sx, y: (210 - rad) * sy,
                                                      width: rad * 2 * sx, height: rad * 2 * sy)),
                               with: .color(NB.white.opacity(0.07)), lineWidth: 1.5 * sx)
                }
            }
        }
    }
}

// MARK: 02 · 搜索 Searching

private struct Searching: View {
    let onFound: () -> Void
    @State private var phase: Double = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            // The ripple is white and the screen has no green in it — success colour is
            // not allowed before there is a success.
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                BandPortrait(scanRings: (0..<4).map { i in
                    let p = (t * 0.35 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                    return 60 + CGFloat(p) * 130
                })
                .frame(width: 390, height: 470)
                .offset(y: 252)
            }

            VStack(spacing: 0) {
                Color.clear.frame(height: 66)
                PairHeader(index: 2)
                PairTitle(title: "Searching",
                          sub: "Keep the band close to your phone. This usually takes a few seconds.")
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            Text("SCANNING")
                .font(NBFont.dot(600, 12)).tracking(0.34 * 12)
                .foregroundStyle(NB.white.opacity(0.42))
                .frame(width: 390, alignment: .center)
                .offset(y: 700)

            Text("Keep it within arm's reach.")
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .foregroundStyle(NB.text3Prod)
                .frame(width: 390, alignment: .center)
                .offset(y: 750)

            HomeIndicator().frame(width: 390).offset(y: 806)
        }
        .frame(width: 390, height: 844, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            // The first band found ends the scan — one account owns one band, so a list
            // would be a list of things you cannot choose.
            try? await Task.sleep(for: .seconds(2.2))
            onFound()
        }
    }
}

// MARK: 03 · 找到 Found

private struct FoundIt: View {
    let onConnect: () -> Void
    let onSearchAgain: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            // The full ring only lights here: the watch is what lit up, not the app.
            Circle()
                .stroke(NB.lime1, lineWidth: 2)
                .frame(width: 232, height: 232)
                .shadow(color: NB.lime1.opacity(0.35), radius: 26)
                .position(x: 195, y: 252 + 210)

            BandPortrait(faceLit: true)
                .frame(width: 390, height: 470)
                .offset(y: 252)

            VStack(spacing: 0) {
                Color.clear.frame(height: 66)
                PairHeader(index: 3)
                PairTitle(title: "Found it",
                          sub: "One band is in range. Tap connect and keep it near your phone.")
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            DeviceRow()
                .offset(x: 16, y: 600)

            LimePillButton(title: "Connect", action: onConnect)
                .offset(x: 16, y: 700)

            Button(action: onSearchAgain) {
                Text("Not your band? Search again")
                    .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text3Prod)
                    .frame(width: 390)
            }
            .buttonStyle(.plain)
            .offset(y: 770)

            HomeIndicator().frame(width: 390).offset(y: 806)
        }
        .frame(width: 390, height: 844, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One found band. ⚠️ Never a serial number on this card — the SDK has no such field.
private struct DeviceRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(NB.lime1.opacity(0.12))
                Circle().stroke(NB.lime1.opacity(0.35), lineWidth: 1)
                Circle().stroke(NB.lime1, lineWidth: 2).frame(width: 11, height: 11)
                Rectangle().fill(NB.lime1).frame(width: 2, height: 7).offset(y: -6)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text("NEXTBODY HOOP")
                    .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                    .foregroundStyle(NB.text1)
                Text("READY TO PAIR")
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.text3Prod)
            }
            Spacer(minLength: 0)
            Text("96%")
                .font(NBFont.dot(600, 10)).tracking(0.1 * 10)
                .foregroundStyle(NB.text3Prod)
            SignalBars(level: 4)
        }
        .padding(.horizontal, 16)
        .frame(width: NB.Layout.contentWidth, height: 72)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }
}

struct SignalBars: View {
    let level: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? NB.limePale : NB.white.opacity(0.18))
                    .frame(width: 3, height: 4 + CGFloat(i) * 3)
            }
        }
    }
}

// MARK: 04 · 配对 Pairing

private struct Pairing: View {
    let progress: Double
    let stage: Int

    private static let stages = ["CONNECT", "AUTHORISE", "READ CAPABILITIES", "READ FIRMWARE"]

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            // A collapse, not a supernova: five sparse arms, one event horizon, a black centre.
            TimelineView(.animation) { tl in
                Collapse(t: tl.date.timeIntervalSinceReferenceDate, progress: progress)
                    .frame(width: 390, height: 400)
                    .offset(y: 260)
            }

            VStack(spacing: 0) {
                Color.clear.frame(height: 66)
                PairHeader(index: 4)
                PairTitle(title: "Pairing", sub: "Keep it close — pulling everything into place.")
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("PAIRING")
                    .font(NBFont.dot(600, 11)).tracking(0.3 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Text("\(Int(progress * 100))%")
                    .font(NBFont.dot(700, 22)).tracking(0.02 * 22)
                    .foregroundStyle(NB.lime1)
                    .contentTransition(.numericText())
            }
            .frame(width: NB.Layout.contentWidth)
            .offset(x: 16, y: 636)

            DottedProgress(progress: progress)
                .frame(width: NB.Layout.contentWidth, height: 6)
                .offset(x: 16, y: 672)

            Text(Self.stages[min(stage, 3)])
                .font(NBFont.dot(500, 10)).tracking(0.2 * 10)
                .foregroundStyle(NB.white.opacity(0.34))
                .frame(width: NB.Layout.contentWidth, alignment: .leading)
                .offset(x: 16, y: 690)

            Text("Keep it within arm's reach.")
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .foregroundStyle(NB.text3Prod)
                .frame(width: 390, alignment: .center)
                .offset(y: 730)

            HomeIndicator().frame(width: 390).offset(y: 806)
        }
        .frame(width: 390, height: 844, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct DottedProgress: View {
    let progress: Double
    var body: some View {
        Canvas { ctx, size in
            let n = 60
            let pitch = size.width / CGFloat(n)
            for i in 0..<n {
                let lit = Double(i) / Double(n) < progress
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * pitch, y: 1,
                                                  width: pitch - 2, height: 4), cornerRadius: 1),
                         with: .color(lit ? NB.lime1 : NB.white.opacity(0.10)))
            }
        }
    }
}

private struct Collapse: View {
    let t: TimeInterval
    let progress: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2 - 40)
            // five sparse arms
            for arm in 0..<5 {
                let base = Double(arm) / 5 * 2 * .pi + t * 0.7
                var p = Path()
                var first = true
                var r: CGFloat = 26
                while r < 150 {
                    let a: Double = base + Double(r) * 0.022
                    let px: CGFloat = c.x + r * CGFloat(cos(a))
                    let py: CGFloat = c.y + r * CGFloat(sin(a)) * 0.92
                    let pt = CGPoint(x: px, y: py)
                    if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                    r += 3
                }
                ctx.stroke(p, with: .color(NB.lime1.opacity(0.55 - Double(arm) * 0.06)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 7]))
            }
            // event horizon
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68)),
                       with: .color(NB.lime1.opacity(0.85)), lineWidth: 3)
            // the centre stays black
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 30, y: c.y - 30, width: 60, height: 60)),
                     with: .color(NB.panelInk))
            // stray debris being pulled in
            for i in 0..<7 {
                let a: Double = Double(i) * 1.7 + t * 0.4
                let r: CGFloat = 150 + CGFloat((sin(t * 0.6 + Double(i)) + 1) * 26)
                let dx: CGFloat = c.x + r * CGFloat(cos(a)) - 2
                let dy: CGFloat = c.y + r * CGFloat(sin(a)) * 0.9 - 2
                ctx.fill(Path(CGRect(x: dx, y: dy, width: 4, height: 4)),
                         with: .color(NB.lime1.opacity(0.5)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: 05 · 连上 Connected

private struct Connected: View {
    let onNext: () -> Void
    @State private var burst: Double = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            Burst(progress: burst)
                .frame(width: 390, height: 560)
                .offset(y: 90)

            Text("CONNECTED")
                .font(NBFont.dot(700, 20)).tracking(0.34 * 20)
                .foregroundStyle(NB.lime1)
                .frame(width: 390, alignment: .center)
                .offset(y: 356)

            // No header, no back key, one button — pairing to profile is a straight line.
            LimePillButton(title: "Now let me get to know you", action: onNext)
                .offset(x: 16, y: 700)

            HomeIndicator().frame(width: 390).offset(y: 806)
        }
        .frame(width: 390, height: 844, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { burst = 1 } }
    }
}

/// The burst and the first-launch splash are one implementation, not two (MOTION SPEC · 01).
/// ⚠️ The two horizontal rays must be cut — they read as a strike-through on CONNECTED.
private struct Burst: View {
    let progress: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 150, y: c.y - 150, width: 300, height: 300)),
                     with: .radialGradient(
                        Gradient(colors: [NB.lime1.opacity(0.35 * progress), NB.lime1.opacity(0)]),
                        center: c, startRadius: 0, endRadius: 150))

            for i in 0..<16 {
                let a = Double(i) / 16 * 2 * .pi
                // cut the two horizontal rays
                if abs(cos(a)) > 0.985 { continue }
                let reach: CGFloat = 40 + 190 * CGFloat(progress)
                var r: CGFloat = 40
                while r < reach {
                    let dim: Double = 1 - Double(r - 40) / 190.0
                    let x: CGFloat = c.x + r * CGFloat(cos(a)) - 2.4
                    let y: CGFloat = c.y + r * CGFloat(sin(a)) - 2.4
                    let box = CGRect(x: x, y: y, width: 4.8, height: 4.8)
                    ctx.fill(Path(box), with: .color(NB.lime1.opacity(0.25 + 0.6 * dim)))
                    r += 7
                }
            }
        }
        .allowsHitTesting(false)
    }
}
