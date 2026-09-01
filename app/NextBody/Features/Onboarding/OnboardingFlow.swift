import SwiftUI

/// 03 · Onboarding 建档与基线. Two counters, kept apart: ABOUT YOU 01–03 and BASELINE 01–03.
/// The back key works inside a段 only; once the scan starts it disappears.
/// The whole BASELINE段 is skippable.
struct OnboardingFlow: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var data: DataStore

    enum Step: Hashable { case healthSync, confirm, goal, fingersOn, scanning, baseline }
    @State private var step: Step = .healthSync
    @State private var sheet: SheetRoute?
    @State private var underage = false

    @State private var sex = "Female"
    @State private var born = DateComponents(year: 1998, month: 6, day: 12)
    @State private var heightCm: Double = 172
    @State private var weightKg: Double = 63
    @State private var heightFromHealth = true
    @State private var weightFromHealth = true
    @State private var bornFromHealth = true
    @State private var sexFromHealth = true
    @State private var goal: Goal = .cut

    var body: some View {
        ZStack {
            switch step {
            case .healthSync:
                HealthSync(onSync: { step = .confirm }, onManual: { step = .confirm })
            case .confirm:
                ConfirmScreen(sex: $sex, born: born, heightCm: heightCm, weightKg: weightKg,
                              heightFromHealth: heightFromHealth, weightFromHealth: weightFromHealth,
                              bornFromHealth: bornFromHealth, sexFromHealth: sexFromHealth,
                              onBack: { step = .healthSync },
                              onEdit: { sheet = $0 },
                              onNext: { step = .goal })
            case .goal:
                GoalScreen(goal: $goal, onBack: { step = .confirm }, onNext: { step = .fingersOn })
            case .fingersOn:
                FingersOn(onBack: { step = .goal }, onStart: { step = .scanning }, onSkip: enter)
            case .scanning:
                ScanningScreen { step = .baseline }
            case .baseline:
                BaselineScreen(onEnter: enter)
            }

            // F5 · D08 — the 18 gate is caught on the birthday screen, not buried in the terms.
            if underage { AgeGate { underage = false } }
        }
        .carbonPage()
        .ignoresSafeArea(.container, edges: .vertical)
        .animation(.easeInOut(duration: 0.24), value: step)
        .sheet(item: $sheet) { route in
            Group {
                switch route {
                case .weightBaseline:
                    WeightRulerSheet(value: $weightKg) { weightFromHealth = false; sheet = nil }
                case .height:
                    HeightRulerSheet(value: $heightCm) { heightFromHealth = false; sheet = nil }
                case .birthday:
                    BirthdayWheelSheet(value: $born) { comps in
                        born = comps
                        bornFromHealth = false
                        if age(from: comps) < 18 { underage = true }
                        sheet = nil
                    } onCancel: { sheet = nil }
                default: EmptyView()
                }
            }
            .presentationDetents([.fraction(0.62)])
            .presentationDragIndicator(.visible)
            .presentationBackground(NB.carbon2)
            .presentationCornerRadius(NB.R.panel)
        }
    }

    private func age(from c: DateComponents) -> Int {
        guard let d = Calendar.current.date(from: c) else { return 30 }
        return Calendar.current.dateComponents([.year], from: d, to: Date()).year ?? 30
    }

    private func enter() {
        data.profile.heightCm = heightCm
        data.profile.goal = goal
        data.profile.sexIsMale = (sex == "Male")
        if let d = Calendar.current.date(from: born) { data.profile.birthdate = d }
        data.today.weightKg = weightKg
        session.stage = .root
    }
}

// MARK: shared

private struct OnbHeader: View {
    let counter: String
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
            Text(counter)
                .font(NBFont.dot(600, 11)).tracking(0.3 * 11)
                .foregroundStyle(NB.text3Prod)
        }
        .frame(width: NB.Layout.contentWidth, height: 44)
    }
}

private struct OnbTitle: View {
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

private struct OnbPage<Content: View>: View {
    let counter: String
    let title: String
    let sub: String
    var onBack: (() -> Void)?
    let cta: String
    var ctaEnabled = true
    let onCTA: () -> Void
    var footnote: String?
    var onFootnote: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 66)
            OnbHeader(counter: counter, onBack: onBack)
            OnbTitle(title: title, sub: sub).padding(.top, 24)
            content.padding(.top, 28)
            Spacer(minLength: 0)
            LimePillButton(title: cta, enabled: ctaEnabled, action: onCTA)
            if let footnote {
                Text(footnote)
                    .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .padding(.top, 16)
                    .onTapGesture { onFootnote?() }
            }
            HomeIndicator().padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: 01 · 读档案 Health sync

private struct HealthSync: View {
    let onSync: () -> Void
    let onManual: () -> Void

    /// Four chips. ⚠️ HealthKit read permission cannot be probed, so once granted these
    /// never turn back — "Enter manually instead" is plain text with no dot and no state.
    private let chips = ["HEIGHT", "WEIGHT", "BIRTHDAY", "SEX"]

    var body: some View {
        OnbPage(counter: "ABOUT YOU 01 / 03",
                title: "First, about you",
                sub: "We can pull height, weight and birthday straight from Apple Health.",
                cta: "Sync from Apple Health", onCTA: onSync,
                footnote: "Enter manually instead", onFootnote: onManual) {
            VStack(spacing: 22) {
                HealthMark()
                Text("Apple Health")
                    .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text2)
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { c in
                        Text(c)
                            .font(NBFont.dot(600, 9)).tracking(0.16 * 9)
                            .foregroundStyle(NB.text3Prod)
                            .padding(.horizontal, 12).frame(height: 26)
                            .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
                    }
                }
                .padding(.top, 60)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }
}

private struct HealthMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white)
            HeartShape()
                .fill(LinearGradient(colors: [Color(hex: 0xFB6E7E), Color(hex: 0xF23A54)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 50, height: 46)
        }
        .frame(width: 92, height: 92)
    }
}

private struct HeartShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: w / 2, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.32),
                   control1: CGPoint(x: -w * 0.1, y: h * 0.72), control2: CGPoint(x: 0, y: h * 0.52))
        p.addArc(center: CGPoint(x: w * 0.25, y: h * 0.32), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: w * 0.75, y: h * 0.32), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: w / 2, y: h),
                   control1: CGPoint(x: w, y: h * 0.52), control2: CGPoint(x: w * 1.1, y: h * 0.72))
        return p
    }
}

// MARK: 02 · 对答案 Confirm

private struct ConfirmScreen: View {
    @Binding var sex: String
    let born: DateComponents
    let heightCm: Double
    let weightKg: Double
    let heightFromHealth: Bool
    let weightFromHealth: Bool
    let bornFromHealth: Bool
    let sexFromHealth: Bool
    let onBack: () -> Void
    let onEdit: (SheetRoute) -> Void
    let onNext: () -> Void

    private var bornText: String {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"
        return Calendar.current.date(from: born).map { f.string(from: $0) } ?? "—"
    }

    var body: some View {
        OnbPage(counter: "ABOUT YOU 02 / 03",
                title: "Does this look right?",
                sub: "Pulled from Apple Health. Tap any value to correct it before we calibrate.",
                onBack: onBack,
                cta: "Looks right", onCTA: onNext,
                footnote: "Nothing synced? Just type it in") {
            VStack(spacing: 10) {
                // Sex has no sheet: two options are not worth a panel, so it toggles in place.
                ValueRow(label: "Sex", value: sex, tag: sexFromHealth ? "HEALTH" : "EDIT") {
                    sex = (sex == "Female") ? "Male" : "Female"
                }
                ValueRow(label: "Born", value: bornText, tag: bornFromHealth ? "HEALTH" : "EDIT") {
                    onEdit(.birthday)
                }
                ValueRow(label: "Height", value: "\(Int(heightCm)) cm",
                         tag: heightFromHealth ? "HEALTH" : "EDIT") { onEdit(.height) }
                ValueRow(label: "Weight", value: String(format: "%.0f kg", weightKg),
                         tag: weightFromHealth ? "HEALTH" : "EDIT") { onEdit(.weightBaseline) }
            }
            .frame(width: NB.Layout.contentWidth)
        }
    }
}

/// Once it has really been edited, the tag reads EDIT for good — a later HealthKit sync
/// skips that field, because we no longer have the right to overwrite it.
private struct ValueRow: View {
    let label: String
    let value: String
    let tag: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(NBFont.ui(400, 11)).tracking(0.06 * 11)
                        .foregroundStyle(NB.white.opacity(0.38))
                    Text(value)
                        .font(NBFont.ui(400, 18)).tracking(0.01 * 18)
                        .foregroundStyle(NB.text1)
                }
                Spacer(minLength: 0)
                Text(tag)
                    .font(NBFont.dot(600, 9)).tracking(0.18 * 9)
                    .foregroundStyle(tag == "HEALTH" ? NB.white.opacity(0.42) : NB.lime1)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(NB.white.opacity(0.04)))
                    .overlay(Capsule().stroke(tag == "HEALTH" ? NB.hairline : NB.lime1.opacity(0.4), lineWidth: 1))
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
                .stroke(NB.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: 03 · 定目标 Goal

private struct GoalScreen: View {
    @Binding var goal: Goal
    let onBack: () -> Void
    let onNext: () -> Void

    private static let options: [(Goal, String, String)] = [
        (.cut, "Lose fat", "Burn more than you take in"),
        (.bulk, "Build muscle", "Fuel the work, protect the gains"),
        (.recomp, "Lose fat + build muscle", "Recomposition — slower, but both"),
    ]

    var body: some View {
        OnbPage(counter: "ABOUT YOU 03 / 03",
                title: "What brings you here?",
                sub: "Pick one focus. It sets your daily MOVE and FUEL targets — change it anytime.",
                onBack: onBack,
                cta: "Continue", onCTA: onNext,
                footnote: "You can switch goals later in Profile") {
            // The only real question in the whole of onboarding — and the first option is
            // already selected, so Continue is never grey.
            VStack(spacing: 10) {
                ForEach(Self.options, id: \.0) { g, title, sub in
                    Button { goal = g } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(NBFont.ui(400, 16)).tracking(0.01 * 16)
                                    .foregroundStyle(NB.text1)
                                Text(sub)
                                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                                    .foregroundStyle(NB.white.opacity(0.42))
                            }
                            Spacer(minLength: 0)
                            ZStack {
                                Circle().stroke(goal == g ? NB.lime1 : NB.white.opacity(0.22), lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                if goal == g { Circle().fill(NB.lime1).frame(width: 11, height: 11) }
                            }
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 78)
                        .background(goal == g ? NB.lime1.opacity(0.06) : NB.carbon4,
                                    in: RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous)
                            .stroke(goal == g ? NB.lime1.opacity(0.7) : NB.hairline,
                                    lineWidth: goal == g ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: NB.Layout.contentWidth)
        }
    }
}

// MARK: 04 · 上手 Fingers on

private struct FingersOn: View {
    let onBack: () -> Void
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnbPage(counter: "BASELINE 01 / 03",
                title: "Now, your baseline",
                sub: "Rest your hand on the table and touch the side key with your index finger. Hold still.",
                onBack: onBack,
                cta: "Start body scan", onCTA: onStart,
                footnote: "Takes about 30 seconds") {
            ZStack {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    BandOutline(pulse: (sin(t * 2) + 1) / 2)
                }
                .frame(width: 240, height: 300)

                Text("INDEX FINGER ON THE SIDE KEY")
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.lime1.opacity(0.75))
                    .offset(y: 190)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
        }
    }
}

/// The band drawn as a lit outline of LEDs, with the fingertip meeting the side key.
private struct BandOutline: View {
    let pulse: Double
    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(x: size.width / 2 - 62, y: size.height / 2 - 82, width: 124, height: 164)
            let path = Path(roundedRect: rect, cornerRadius: 40)
            ctx.stroke(path, with: .color(NB.lime1.opacity(0.35 + 0.35 * pulse)),
                       style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [2.4, 3.4]))
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: 14, dy: 14), cornerRadius: 28),
                       with: .color(NB.lime1.opacity(0.12)), lineWidth: 1)
            // side key + fingertip
            ctx.fill(Path(roundedRect: CGRect(x: rect.maxX + 2, y: rect.midY - 22, width: 7, height: 44),
                          cornerRadius: 3.5), with: .color(NB.lime1))
            ctx.stroke(Path(ellipseIn: CGRect(x: rect.maxX + 16, y: rect.midY - 18, width: 36, height: 36)),
                       with: .color(NB.lime1.opacity(0.55)), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            var lead = Path()
            lead.move(to: CGPoint(x: rect.maxX + 52, y: rect.midY))
            lead.addLine(to: CGPoint(x: size.width, y: rect.midY))
            ctx.stroke(lead, with: .color(NB.lime1.opacity(0.28)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}

// MARK: 05 · 测量 Scanning

private struct ScanningScreen: View {
    let onDone: () -> Void
    @State private var remaining = 30

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 66)
            // Once the scan starts the back key is gone — you cannot half-measure a body.
            OnbHeader(counter: "BASELINE 02 / 03")
            OnbTitle(title: "Scanning",
                     sub: "A tiny current maps your body — you won't feel a thing. Keep your fingers on the frame.")
                .padding(.top, 24)

            TimelineView(.animation) { tl in
                ECGTrace(t: tl.date.timeIntervalSinceReferenceDate)
            }
            .frame(height: 190)
            .padding(.top, 40)

            Text("BODY COMPOSITION")
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.34))
                .padding(.top, 28)

            // The counter counts down, not up: the ETA belongs before the wait, not during it.
            Text(String(format: "00:%02d", remaining))
                .font(NBFont.dot(700, 26)).tracking(0.14 * 26)
                .foregroundStyle(NB.lime1)
                .padding(.top, 12)
                .contentTransition(.numericText(countsDown: true))

            Spacer(minLength: 0)

            // Grey, in front — what to do if it breaks, said before it breaks.
            Text("Lift your fingers and the scan restarts.")
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .foregroundStyle(NB.white.opacity(0.42))

            HomeIndicator().padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(tick) { _ in
            if remaining > 0 { withAnimation { remaining -= 1 } } else { onDone() }
        }
        .onAppear { remaining = 6 }   // mock: the real scan is 30s of SDK time
    }
}

private struct ECGTrace: View {
    let t: TimeInterval
    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            var p = Path()
            let n = 220
            for i in 0..<n {
                let x = size.width * CGFloat(i) / CGFloat(n - 1)
                let phase = Double(i) / Double(n) * 4 - t * 0.9
                let beat = phase.truncatingRemainder(dividingBy: 1)
                var v: Double = 0
                if beat > 0.30 && beat < 0.36 { v = -0.18 }
                else if beat > 0.36 && beat < 0.42 { v = 1.0 }
                else if beat > 0.42 && beat < 0.48 { v = -0.55 }
                else if beat > 0.55 && beat < 0.68 { v = 0.22 }
                else { v = sin(phase * 12) * 0.03 }
                let pt = CGPoint(x: x, y: mid - CGFloat(v) * mid * 0.82)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            ctx.stroke(p, with: .color(NB.lime1),
                       style: StrokeStyle(lineWidth: 2.2, lineJoin: .round, dash: [2.6, 2.2]))
            ctx.fill(Path(ellipseIn: CGRect(x: size.width - 70, y: mid - 60, width: 44, height: 44)),
                     with: .radialGradient(Gradient(colors: [NB.lime1.opacity(0.35), NB.lime1.opacity(0)]),
                                           center: CGPoint(x: size.width - 48, y: mid - 38),
                                           startRadius: 0, endRadius: 26))
        }
    }
}

// MARK: 06 · 交底 Baseline

private struct BaselineScreen: View {
    let onEnter: () -> Void

    /// The full twelve the SDK returns, laid out flat — this screen collects,
    /// it does not judge. No good/high/low anywhere: day zero has nothing to compare to.
    private static let tiles: [(String, String, String, Color)] = [
        ("FAT MASS", "13.5", "kg", NB.lime1),
        ("LEAN MASS", "49.5", "kg", NB.lime1),
        ("MUSCLE", "46.8", "kg", NB.lime1),
        ("MUSCLE RATE", "74.3", "%", NB.lime1),
        ("SKELETAL", "42.1", "%", NB.lime1),
        ("BONE", "2.7", "kg", NB.lime1),
        ("BODY WATER", "55.2", "%", NB.cyan1),
        ("WATER", "34.8", "kg", NB.cyan1),
        ("PROTEIN", "17.6", "%", NB.cyan1),
        ("PROTEIN MASS", "11.1", "kg", NB.cyan1),
        ("SUBCUT FAT", "18.9", "%", NB.cyan1),
        ("BMR", "1386", "kcal", NB.ember1),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 66)
            OnbHeader(counter: "BASELINE 03 / 03")
            OnbTitle(title: "Your baseline", sub: "First scan complete — this is day zero.")
                .padding(.top, 24)

            HStack(spacing: 0) {
                HeadlineStat(value: "21.4", unit: "%", label: "BODY FAT", labelTint: NB.lime1)
                Rectangle().fill(NB.white.opacity(0.08)).frame(width: 1, height: 72)
                HeadlineStat(value: "21.3", unit: nil, label: "BMI", labelTint: NB.white.opacity(0.42))
            }
            .frame(width: NB.Layout.contentWidth, height: 116)
            .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
                .stroke(NB.white.opacity(0.08), lineWidth: 1))
            .padding(.top, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(114), spacing: 8), count: 3), spacing: 8) {
                ForEach(Self.tiles, id: \.0) { t in
                    BaselineTile(label: t.0, value: t.1, unit: t.2, tint: t.3)
                }
            }
            .frame(width: NB.Layout.contentWidth)
            .padding(.top, 16)

            Spacer(minLength: 0)

            // "Enter NEXTBODY", never "Done" — the end point is the product, not the form.
            LimePillButton(title: "Enter NEXTBODY", action: onEnter)
            Text("Scan again anytime from the Device page")
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .foregroundStyle(NB.white.opacity(0.42))
                .padding(.top, 16)
            HomeIndicator().padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct HeadlineStat: View {
    let value: String
    let unit: String?
    let label: String
    let labelTint: Color
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(NBFont.brand(700, 46)).tracking(-0.045 * 46)
                    .foregroundStyle(NB.white)
                if let unit {
                    Text(unit)
                        .font(NBFont.brand(500, 18)).tracking(-0.01 * 18)
                        .foregroundStyle(NB.white.opacity(0.42))
                }
            }
            Text(label)
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(labelTint)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BaselineTile: View {
    let label: String
    let value: String
    let unit: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(NBFont.dot(600, 9)).tracking(0.16 * 9)
                .foregroundStyle(tint)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(NBFont.brand(600, 21)).tracking(-0.02 * 21)
                    .foregroundStyle(NB.white)
                Text(unit)
                    .font(NBFont.ui(300, 11))
                    .foregroundStyle(NB.white.opacity(0.42))
            }
        }
        .padding(.leading, 14)
        .padding(.top, 14)
        .frame(width: 114, height: 78, alignment: .topLeading)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
            .stroke(NB.white.opacity(0.06), lineWidth: 1))
    }
}

/// F5 · D08 — the 18 threshold is enforced on the birthday screen itself.
private struct AgeGate: View {
    let onBack: () -> Void
    var body: some View {
        ZStack {
            NB.carbon.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("NEXTBODY IS 18+")
                    .font(NBFont.dot(700, 13)).tracking(0.3 * 13)
                    .foregroundStyle(NB.alert2)
                Text("We can't create an account for someone under 18.")
                    .font(NBFont.ui(400, 17)).tracking(0.01 * 17)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NB.text1)
                    .frame(width: 280)
                Button(action: onBack) {
                    Text("Change date of birth")
                        .font(NBFont.ui(500, 15)).tracking(0.06 * 15)
                        .foregroundStyle(NB.text1)
                        .frame(width: 280, height: 52)
                        .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
