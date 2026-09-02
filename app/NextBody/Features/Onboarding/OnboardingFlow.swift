import SwiftUI

/// 03 · Onboarding 建档与基线. Two counters, kept apart: ABOUT YOU 01–03 and BASELINE 01–03.
/// The back key works inside a段 only; once the scan starts it disappears.
/// The whole BASELINE段 is skippable.
struct OnboardingFlow: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var data: DataStore

    // 补屏 A · 六屏变七屏. Consent comes first: before HealthKit's dialog, before the first
    // band read. An account that has already answered this version skips straight past it.
    enum Step: Hashable { case consent, healthSync, confirm, goal, fingersOn, scanning, baseline }
    /// 03 edge 3 · after the band dropped mid-scan and Connect ran again, the profile is on
    /// record and the run resumes at BASELINE 01, not at the first question.
    @State private var step: Step = {
        if UserDefaults.standard.bool(forKey: "nb.onboarding.resumeAtBaseline") {
            UserDefaults.standard.removeObject(forKey: "nb.onboarding.resumeAtBaseline")
            return .fingersOn
        }
        if DebugEdge.on("nothingsynced") || DebugEdge.on("outofrange") { return .confirm }
        if DebugEdge.on("lowbattery") { return .fingersOn }
        if DebugEdge.on("lifted") || DebugEdge.on("banddropped") { return .scanning }
        return ConsentStore.shared.decided ? .healthSync : .consent
    }()
    /// 03 rule 02 · which of the four fields has a value at all, and where each came from.
    /// A field that is neither synced nor typed shows ADD; nothing synced makes the CTA
    /// "Save and continue", dead until all four are in.
    @State private var filled: Set<String> = DebugEdge.on("outofrange") ? ["sex", "born", "height", "weight"] : []
    @State private var synced = false
    @State private var sheet: SheetRoute?
    @State private var underage = false

    @State private var sex = "Female"
    @State private var born = DateComponents(year: 1998, month: 6, day: 12)
    @State private var heightCm: Double = 172
    @State private var weightKg: Double = 63
    @State private var heightFromHealth = false
    @State private var weightFromHealth = false
    @State private var bornFromHealth = false
    @State private var sexFromHealth = false
    @State private var goal: Goal = .cut

    var body: some View {
        ZStack {
            switch step {
            case .consent:
                // Declining (the chevron) is not a dead end — the rest of onboarding still runs,
                // and nothing is ever read until the screen is answered again from Settings.
                ConsentScreen(onContinue: { step = .healthSync }, onBack: { step = .healthSync })
            case .healthSync:
                HealthSync(onSync: { Task { await syncFromHealth() } }, onManual: { step = .confirm })
            case .confirm:
                ConfirmScreen(sex: $sex, born: born,
                              heightCm: DebugEdge.on("outofrange") ? 40 : heightCm, weightKg: weightKg,
                              heightFromHealth: heightFromHealth, weightFromHealth: weightFromHealth,
                              bornFromHealth: bornFromHealth, sexFromHealth: sexFromHealth,
                              filled: filled, nothingSynced: !synced,
                              onSexTap: { filled.insert("sex") },
                              onBack: { step = .healthSync },
                              onEdit: { sheet = $0 },
                              // F5 C5 · 「judged on 03/02 Looks right, not live on the birthday wheel」.
                              onNext: { if age(from: born) < 18 { underage = true } else { step = .goal } })
            case .goal:
                GoalScreen(goal: $goal, onBack: { step = .confirm }, onNext: { step = .fingersOn })
            case .fingersOn:
                FingersOn(onBack: { step = .goal }, onStart: { step = .scanning }, onSkip: {
                    Task { await Analytics.shared.track("SCAN_SKIP", ["REASON": "USER"]) }
                    enter()
                })
            case .scanning:
                ScanningScreen(onDone: { step = .baseline }, onReconnect: {
                    // 03 edge 3 · reuse the whole pairing chain, then come back to BASELINE 01.
                    UserDefaults.standard.set(true, forKey: "nb.onboarding.resumeAtBaseline")
                    session.stage = .gateConnect
                })
            case .baseline:
                BaselineScreen(onEnter: enter)
            }

            // F5 · D08 — the 18 gate is caught on the birthday screen, not buried in the terms.
            if underage { AgeGate { underage = false } }
        }
        .carbonPage()
        .sheet(item: $sheet) { route in
            Group {
                switch route {
                case .weightBaseline:
                    WeightRulerSheet(value: $weightKg) { weightFromHealth = false; filled.insert("weight"); sheet = nil }
                case .height:
                    HeightRulerSheet(value: $heightCm) { heightFromHealth = false; filled.insert("height"); sheet = nil }
                case .birthday:
                    BirthdayWheelSheet(value: $born) { comps in
                        born = comps
                        bornFromHealth = false
                        filled.insert("born")
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

    /// 02 · the system sheet, then one read. Only the values that came back are marked as
    /// Health's; the rest keep the defaults and the dot that says "tap to correct".
    private func syncFromHealth() async {
        await HealthService.shared.requestRead()
        let b = await HealthService.shared.readBaseline()
        if let m = b.sexIsMale { sex = m ? "Male" : "Female"; sexFromHealth = true; filled.insert("sex") }
        if let d = b.born { born = d; bornFromHealth = true; filled.insert("born") }
        if let h = b.heightCm { heightCm = h; heightFromHealth = true; filled.insert("height") }
        if let w = b.weightKg { weightKg = w; weightFromHealth = true; filled.insert("weight") }
        synced = !b.isEmpty
        if synced { data.profile.appleHealthLinked = true }
        await Analytics.shared.track("HEALTH_PROMPT", ["GRANTED_FIELDS": filled.count])
        step = .confirm
    }

    private func enter() {
        Task { await Analytics.shared.track("ONBOARD_DONE", [:]) }
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
            Color.clear.frame(height: Chrome.gateTopInset)
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
            Color.clear.frame(height: 10)
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
    var filled: Set<String> = ["sex", "born", "height", "weight"]
    var nothingSynced = false
    var onSexTap: () -> Void = {}
    let onBack: () -> Void
    let onEdit: (SheetRoute) -> Void
    let onNext: () -> Void

    /// 03 edge 5 · outside 90–230 cm / 25–250 kg is not an error, it is probably a slip:
    /// amber border and a question. Never cleared, never blocks Looks right.
    private var heightOut: Bool { filled.contains("height") && !(90...230).contains(heightCm) }
    private var weightOut: Bool { filled.contains("weight") && !(25...250).contains(weightKg) }

    private func tag(_ field: String, fromHealth: Bool) -> String {
        fromHealth ? "HEALTH" : filled.contains(field) ? "EDIT" : "ADD"
    }
    private func shown(_ field: String, _ value: String) -> String { filled.contains(field) ? value : "" }

    private var bornText: String {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"
        return Calendar.current.date(from: born).map { f.string(from: $0) } ?? "—"
    }

    var body: some View {
        OnbPage(counter: "ABOUT YOU 02 / 03",
                title: "Does this look right?",
                sub: "Pulled from Apple Health. Tap any value to correct it before we calibrate.",
                onBack: onBack,
                // 03 edge 1 · NOTHING SYNCED: the same screen, values empty, ADD instead of HEALTH,
                // and the key is "Save and continue", dead until all four are in. No error line —
                // 「我们无法证明它失败了」.
                cta: nothingSynced ? "Save and continue" : "Looks right",
                ctaEnabled: !nothingSynced || filled.count == 4,
                onCTA: onNext,
                footnote: "Nothing synced? Just type it in") {
            VStack(spacing: 10) {
                // Sex has no sheet: two options are not worth a panel, so it toggles in place.
                ValueRow(label: "Sex", value: shown("sex", sex), tag: tag("sex", fromHealth: sexFromHealth)) {
                    if filled.contains("sex") { sex = (sex == "Female") ? "Male" : "Female" }
                    onSexTap()
                }
                ValueRow(label: "Born", value: shown("born", bornText), tag: tag("born", fromHealth: bornFromHealth)) {
                    onEdit(.birthday)
                }
                ValueRow(label: "Height", value: shown("height", "\(Int(heightCm)) cm"),
                         tag: tag("height", fromHealth: heightFromHealth), warn: heightOut) { onEdit(.height) }
                ValueRow(label: "Weight", value: shown("weight", String(format: "%.0f kg", weightKg)),
                         tag: tag("weight", fromHealth: weightFromHealth), warn: weightOut) { onEdit(.weightBaseline) }
                if heightOut || weightOut {
                    Text("That's outside what we can measure. Check it?")
                        .font(NBFont.ui(400, 14)).tracking(0.01 * 14)
                        .foregroundStyle(NB.emberPale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
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
    var warn = false
    let action: () -> Void

    private var tagTint: Color { tag == "HEALTH" ? NB.white.opacity(0.42) : tag == "ADD" ? NB.ember1 : NB.lime1 }

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
                    .foregroundStyle(tagTint)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(NB.white.opacity(0.04)))
                    .overlay(Capsule().stroke(tag == "HEALTH" ? NB.hairline : tagTint.opacity(0.4), lineWidth: 1))
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
                .stroke(warn ? NB.ember1 : NB.hairline, lineWidth: warn ? 1.5 : 1))
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
    /// 03 edge 4 · gated before the scan starts, not discovered halfway through.
    @State private var lowBattery: Int?

    var body: some View {
        OnbPage(counter: "BASELINE 01 / 03",
                title: "Now, your baseline",
                sub: "Rest your hand on the table and touch the side key with your index finger. Hold still.",
                onBack: onBack,
                cta: "Start body scan", ctaEnabled: lowBattery == nil, onCTA: {
                    Task { await Analytics.shared.track("SCAN_START", [:]) }
                    onStart()
                },
                footnote: "Takes about 30 seconds") {
            ZStack {
                if let lowBattery {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            BatteryGlyph()
                            Text("BATTERY \(lowBattery)%")
                                .font(NBFont.dot(600, 12)).tracking(0.2 * 12).foregroundStyle(NB.ember1)
                        }
                        Text("Charge the band before the first scan — it needs about 15%.")
                            .font(NBFont.ui(400, 14.5)).tracking(0.01 * 14.5).lineSpacing(6)
                            .foregroundStyle(NB.white.opacity(0.80))
                        Button {
                            Task { await Analytics.shared.track("SCAN_SKIP", ["REASON": "LOW_BATTERY"]) }
                            onSkip()
                        } label: {
                            Text("先跳过，稍后再测 →").font(NBFont.ui(500, 14)).tracking(0.02 * 14).foregroundStyle(NB.lime1)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .frame(width: NB.Layout.contentWidth, height: 176, alignment: .leading)
                    .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous).stroke(NB.hairline, lineWidth: 1))
                    .offset(y: -40)
                }
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
        .task {
            if DebugEdge.on("lowbattery") { lowBattery = 8; return }
            if let b = try? await Band.live.readBattery(), b.isPercent, let p = b.percent, p < 15 { lowBattery = p }
        }
    }
}

/// 03 edge 4 · the board's 26 × 13 outline with one amber bar inside.
private struct BatteryGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3).stroke(NB.ember1, lineWidth: 1.5)
            .frame(width: 26, height: 13)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1).fill(NB.ember1).frame(width: 4, height: 7).padding(.leading, 2)
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
    var onReconnect: () -> Void = {}
    @State private var remaining = 30
    /// 03 edge 2 · a lifted finger pauses the count; the second lift in one attempt restarts it.
    @State private var holding = false
    @State private var restarts = 0
    /// 03 edge 3 · the one edge this screen cannot fix itself.
    @State private var dropped = false
    @State private var startedAt = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Chrome.gateTopInset)
            // Once the scan starts the back key is gone — you cannot half-measure a body.
            OnbHeader(counter: "BASELINE 02 / 03")
            OnbTitle(title: "Scanning",
                     sub: "A tiny current maps your body — you won't feel a thing. Keep your fingers on the frame.")
                .padding(.top, 24)

            if dropped {
                VStack(alignment: .leading, spacing: 14) {
                    Text("BAND DISCONNECTED")
                        .font(NBFont.dot(600, 12)).tracking(0.2 * 12).foregroundStyle(NB.ember1)
                    Text("The band went quiet mid-scan.\nNothing you filled in is lost.")
                        .font(NBFont.ui(400, 14.5)).tracking(0.01 * 14.5).lineSpacing(6)
                        .foregroundStyle(NB.white.opacity(0.80))
                    Button(action: onReconnect) {
                        Text("重新连接 →").font(NBFont.ui(500, 14)).tracking(0.02 * 14).foregroundStyle(NB.lime1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .frame(width: NB.Layout.contentWidth, height: 176, alignment: .leading)
                .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous).stroke(NB.hairline, lineWidth: 1))
                .padding(.top, 60)
            } else {
            TimelineView(.animation) { tl in
                // Edge 2 · the wave fades to amber and stops moving while the finger is off.
                ECGTrace(t: holding ? 0 : tl.date.timeIntervalSinceReferenceDate)
                    .grayscale(holding ? 1 : 0)
                    .colorMultiply(holding ? NB.ember1 : .white)
                    .opacity(holding ? 0.5 : 1)
            }
            .frame(height: 190)
            .padding(.top, 40)

            Text("BODY COMPOSITION")
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.34))
                .padding(.top, 28)

            // The counter counts down, not up: the ETA belongs before the wait, not during it.
            // Edge 2 · it holds — never resets to zero; zero looks like 「白干了」.
            Text(holding ? String(format: "HOLDING · 00:%02d", remaining) : String(format: "00:%02d", remaining))
                .font(holding ? NBFont.dot(600, 12) : NBFont.dot(700, 26)).tracking(holding ? 0.2 * 12 : 0.14 * 26)
                .foregroundStyle(holding ? NB.ember1 : NB.lime1)
                .padding(.top, 12)
                .contentTransition(.numericText(countsDown: true))
            }

            Spacer(minLength: 0)

            // Grey, in front — what to do if it breaks, said before it breaks.
            Text(holding ? "Put your fingers back — we'll pick it up."
                 : restarts > 0 ? "Second lift — starting over from 30."
                 : "Lift your fingers and the scan restarts.")
                .font(holding ? NBFont.ui(400, 14.5) : NBFont.ui(300, 13)).tracking(0.02 * 13)
                .foregroundStyle(holding ? NB.emberPale : NB.white.opacity(0.42))

            Color.clear.frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(tick) { _ in
            guard !holding, !dropped else { return }
            if remaining > 0 { withAnimation { remaining -= 1 } } else {
                Task { await Analytics.shared.track("SCAN_DONE", ["MS": Int(Date().timeIntervalSince(startedAt) * 1000), "RESTARTS": restarts]) }
                onDone()
            }
        }
        .onAppear { remaining = 6; startedAt = Date() }   // mock: the real scan is 30s of SDK time
        .task {
            // ⚠️ The mock scan has no wear events; the real one arrives as TestState=notWear on the
            // measurement stream. DEBUG walks: `lifted` pauses at 3 s and lifts again at 9 s;
            // `banddropped` loses the band at 2 s.
            if DebugEdge.on("lifted") {
                remaining = 30
                try? await Task.sleep(for: .seconds(3)); withAnimation { holding = true }
                try? await Task.sleep(for: .seconds(3)); withAnimation { holding = false }
                try? await Task.sleep(for: .seconds(3)); withAnimation { holding = true }
                try? await Task.sleep(for: .seconds(2)); withAnimation { holding = false; restarts += 1; remaining = 30 }
            } else if DebugEdge.on("banddropped") {
                try? await Task.sleep(for: .seconds(2)); withAnimation { dropped = true }
            } else {
                for await event in Band.live.events {
                    if case .state(.disconnected) = event { withAnimation { dropped = true }; return }
                }
            }
        }
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
                let beat = phase - phase.rounded(.down)   // wrap to [0,1); a negative phase must not skip the beat
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
            Color.clear.frame(height: Chrome.gateTopInset)
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
            Color.clear.frame(height: 10)
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
