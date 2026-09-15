import SwiftUI

/// 03 · Onboarding 建档与基线. Two counters, kept apart: ABOUT YOU 01–03 and BASELINE 01–03.
/// The back key works inside a段 only; once the scan starts it disappears.
/// The whole BASELINE段 is skippable.
struct OnboardingFlow: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var data: DataStore

    // 补屏 A · 六屏变七屏. Consent comes first: before HealthKit's dialog, before the first
    // band read. An account that has already answered this version skips straight past it.
    enum Step: String, Hashable { case consent, healthSync, confirm, goal, fingersOn, scanning, baseline, membership }
    /// 03 edge 3 · after the band dropped mid-scan and Connect ran again, the profile is on
    /// record and the run resumes at BASELINE 01, not at the first question.
    @State private var step: Step = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["NB_DEBUG_ONB_STEP"] {
            switch raw {
            case "consent": return .consent
            case "healthSync": return .healthSync
            case "confirm": return .confirm
            case "goal": return .goal
            case "fingersOn": return .fingersOn
            case "scanning": return .scanning
            case "baseline": return .baseline
            case "membership": return .membership
            default: break
            }
        }
        #endif
        if UserDefaults.standard.bool(forKey: "nb.onboarding.resumeAtBaseline") {
            UserDefaults.standard.removeObject(forKey: "nb.onboarding.resumeAtBaseline")
            return .fingersOn
        }
        if DebugEdge.on("nothingsynced") || DebugEdge.on("outofrange") { return .confirm }
        if DebugEdge.on("lowbattery") { return .fingersOn }
        if DebugEdge.on("lifted") || DebugEdge.on("banddropped") || DebugEdge.on("nocontact") { return .scanning }
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
    /// 03 · what the band returned on the scanning screen; the baseline screen prints it.
    @State private var baseline: BodyCompositionReading?

    /// F2 §05 · the band's BIA multiplies by the weight we push down, so the weight the user
    /// just confirmed goes to the band before the scan — never the profile's old one.
    private var personalInfo: PersonalInfo {
        PersonalInfo(heightCm: Int(heightCm.rounded()),
                     weightKg: Int(weightKg.rounded()),
                     birthYear: born.year ?? 1990,
                     sexIsMale: sex == "Male",
                     targetStep: 8000)
    }

    /// 06 rule 09 · the baseline is stored like any other scan — a weigh-in that re-anchors
    /// the EMA, today's fat and lean, and a body_composition row on the server.
    private func store(_ r: BodyCompositionReading) {
        data.addWeighIn(WeighIn(id: UUID(), date: Date(), weightKg: r.inputWeightKg,
                                bodyFatPercent: r.bodyFatPercent, source: .measured, origin: .band))
        data.today.fatKg = r.fatMassKg
        data.today.leanKg = r.leanMassKg
        data.today.fatSource = .measured
        data.bodyFatPercent = r.bodyFatPercent
        data.today.scans7d += 1
        Task { await Repository.shared.recordBodyComposition(r) }
    }

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
                    finishTowardHome()
                })
            case .scanning:
                ScanningScreen(info: personalInfo, onDone: { r in
                    baseline = r
                    store(r)
                    step = .baseline
                }, onSkip: {
                    Task { await Analytics.shared.track("SCAN_SKIP", ["REASON": "FAILED"]) }
                    finishTowardHome()
                }, onReconnect: {
                    // 03 edge 3 · reuse the whole pairing chain, then come back to BASELINE 01.
                    UserDefaults.standard.set(true, forKey: "nb.onboarding.resumeAtBaseline")
                    session.stage = .gateConnect
                })
            case .baseline:
                BaselineScreen(reading: baseline, onEnter: finishTowardHome)
            case .membership:
                MembershipCardHost(billing: BillingStore.shared, onFinished: enter)
            }

            // F5 · D08 — the 18 gate is caught on the birthday screen, not buried in the terms.
            if underage { AgeGate { underage = false } }
        }
        .carbonPage()
        .task { await restoreProgress() }
        .onChange(of: step) { _, _ in persistDraft() }
        .onChange(of: filled) { _, _ in persistDraft() }
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

    private func finishTowardHome() {
        Task {
            await BillingStore.shared.refresh()
            if BillingStore.shared.isPro {
                BillingStore.shared.markWelcomeSeen()
                enter()
            } else {
                step = .membership
            }
        }
    }

    private func enter() {
        Task { await Analytics.shared.track("ONBOARD_DONE", [:]) }
        data.profile.heightCm = heightCm
        data.profile.goal = goal
        data.profile.sexIsMale = (sex == "Male")
        if let d = Calendar.current.date(from: born) { data.profile.birthdate = d }
        data.today.weightKg = weightKg
        // ⚠️ These four numbers only ever lived in memory. The server reads them off the
        // profiles row before it computes a single figure, so without this write a real
        // account stayed at "——" on every tile for as long as it existed. What the user
        // typed is marked `edit`; what Health gave is not, so a later Health sync may
        // still refresh it (F3 §02.3).
        var edited: [String] = []
        if !sexFromHealth { edited.append("sex") }
        if !bornFromHealth { edited.append("birth_date") }
        if !heightFromHealth { edited.append("height_cm") }
        let saved = data.profile
        Task { await Repository.shared.saveProfile(saved, editedFields: edited) }
        // The confirmed weight is the day's weigh-in when the scan was skipped; a scan
        // already recorded its own (input_weight_kg) on the way to the baseline screen.
        if baseline == nil {
            data.addWeighIn(WeighIn(id: UUID(), date: Date(), weightKg: weightKg, bodyFatPercent: nil,
                                    source: .measured, origin: weightFromHealth ? .health : .manual))
        }
        Task {
            if let userId = await SupabaseClient.shared.currentUserId {
                OnboardingDraft.clear(userId: userId)
            }
        }
        session.stage = .root
    }

    /// F1 KILLED MID-GATE / PROFILE GAP. A draft on this account, or a partial profiles
    /// row, lands on ABOUT YOU 02 with the values still in. A finished profile should
    /// not be here — Connect already sent those users home.
    private func restoreProgress() async {
        await session.ensureSession()
        await Analytics.shared.track("ONBOARD_ENTER", [:])
        if DebugEdge.name != nil { return }
        #if DEBUG
        // Walk-through pins must not be overwritten by a finished demo profile.
        if ProcessInfo.processInfo.environment["NB_DEBUG_ONB_STEP"] != nil { return }
        if ProcessInfo.processInfo.environment["NB_DEBUG_SCAN_LEFT"] != nil { return }
        #endif
        if UserDefaults.standard.bool(forKey: "nb.onboarding.resumeAtBaseline") {
            UserDefaults.standard.removeObject(forKey: "nb.onboarding.resumeAtBaseline")
            return
        }

        if let userId = await SupabaseClient.shared.currentUserId,
           let draft = OnboardingDraft.load(userId: userId) {
            apply(draft)
            if ConsentStore.shared.decided {
                let restored = Step(rawValue: draft.step) ?? .confirm
                if restored == .scanning || restored == .baseline { step = .fingersOn }
                else if restored == .consent { step = draft.filled.isEmpty ? .healthSync : .confirm }
                else { step = restored }
            }
            return
        }

        let facts = await Repository.shared.fetchAccountGate()
        if facts.profileComplete {
            if let userId = await SupabaseClient.shared.currentUserId {
                OnboardingDraft.clear(userId: userId)
            }
            session.stage = .root
            return
        }
        if facts.hasAnyProfileField || facts.weightKg != nil {
            apply(facts)
            if ConsentStore.shared.decided { step = .confirm }
        }
    }

    private func persistDraft() {
        Task {
            guard let userId = await SupabaseClient.shared.currentUserId else { return }
            let persistStep = step == .scanning ? Step.fingersOn : step
            OnboardingDraft(
                userId: userId,
                step: persistStep.rawValue,
                sex: sex,
                year: born.year ?? 1998,
                month: born.month ?? 6,
                day: born.day ?? 12,
                heightCm: heightCm,
                weightKg: weightKg,
                filled: Array(filled),
                synced: synced,
                sexFromHealth: sexFromHealth,
                bornFromHealth: bornFromHealth,
                heightFromHealth: heightFromHealth,
                weightFromHealth: weightFromHealth,
                goal: goal.rawValue
            ).save()
        }
    }

    private func apply(_ draft: OnboardingDraft) {
        sex = draft.sex
        born = DateComponents(year: draft.year, month: draft.month, day: draft.day)
        heightCm = draft.heightCm
        weightKg = draft.weightKg
        filled = Set(draft.filled)
        synced = draft.synced
        sexFromHealth = draft.sexFromHealth
        bornFromHealth = draft.bornFromHealth
        heightFromHealth = draft.heightFromHealth
        weightFromHealth = draft.weightFromHealth
        if let g = Goal(rawValue: draft.goal) { goal = g }
    }

    private func apply(_ facts: AccountGate) {
        if let s = facts.sex {
            sex = s == "male" ? "Male" : "Female"
            filled.insert("sex")
        }
        if let h = facts.heightCm {
            heightCm = h
            filled.insert("height")
        }
        if let d = facts.birthDate {
            born = Calendar.current.dateComponents([.year, .month, .day], from: d)
            filled.insert("born")
        }
        if let w = facts.weightKg {
            weightKg = w
            filled.insert("weight")
        }
        if let g = facts.goal { goal = g }
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
                // Plain text on the board (no dot, no state) — but a real button underneath,
                // so VoiceOver and the automation tree can find "Enter manually instead".
                Button { onFootnote?() } label: {
                    Text(footnote)
                        .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                        .foregroundStyle(NB.white.opacity(0.42))
                        .padding(.top, 16)
                }
                .buttonStyle(.plain)
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
        OnbPage(counter: L("ABOUT YOU 01 / 03"),
                title: L("First, about you"),
                sub: L("We can pull height, weight and birthday straight from Apple Health."),
                cta: L("Sync from Apple Health"), onCTA: onSync,
                footnote: L("Enter manually instead"), onFootnote: onManual) {
            VStack(spacing: 22) {
                HealthMark()
                Text(L("Apple Health"))
                    .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text2)
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { c in
                        Text(L(c))
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
        return Calendar.current.date(from: born).map { Fmt.displayDate($0, format: "LLLL yyyy") } ?? "—"
    }

    var body: some View {
        OnbPage(counter: L("ABOUT YOU 02 / 03"),
                title: L("Does this look right?"),
                sub: L("Pulled from Apple Health. Tap any value to correct it before we calibrate."),
                onBack: onBack,
                // 03 edge 1 · NOTHING SYNCED: the same screen, values empty, ADD instead of HEALTH,
                // and the key is "Save and continue", dead until all four are in. No error line —
                // 「我们无法证明它失败了」.
                cta: nothingSynced ? L("Save and continue") : L("Looks right"),
                ctaEnabled: !nothingSynced || filled.count == 4,
                onCTA: onNext,
                footnote: L("Nothing synced? Just type it in")) {
            VStack(spacing: 10) {
                // Sex has no sheet: two options are not worth a panel, so it toggles in place.
                ValueRow(label: L("Sex"), value: shown("sex", L(sex)), tag: tag("sex", fromHealth: sexFromHealth)) {
                    if filled.contains("sex") { sex = (sex == "Female") ? "Male" : "Female" }
                    onSexTap()
                }
                ValueRow(label: L("Born"), value: shown("born", bornText), tag: tag("born", fromHealth: bornFromHealth)) {
                    onEdit(.birthday)
                }
                ValueRow(label: L("Height"), value: shown("height", "\(Int(heightCm)) cm"),
                         tag: tag("height", fromHealth: heightFromHealth), warn: heightOut) { onEdit(.height) }
                ValueRow(label: L("Weight"), value: shown("weight", String(format: "%.0f kg", weightKg)),
                         tag: tag("weight", fromHealth: weightFromHealth), warn: weightOut) { onEdit(.weightBaseline) }
                if heightOut || weightOut {
                    Text(L("That's outside what we can measure. Check it?"))
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
                Text(L(tag))
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
        OnbPage(counter: L("ABOUT YOU 03 / 03"),
                title: L("What brings you here?"),
                sub: L("Pick one focus. It sets your daily MOVE and FUEL targets — change it anytime."),
                onBack: onBack,
                cta: L("Continue"), onCTA: onNext,
                footnote: L("You can switch goals later in Profile")) {
            // The only real question in the whole of onboarding — and the first option is
            // already selected, so Continue is never grey.
            VStack(spacing: 10) {
                ForEach(Self.options, id: \.0) { g, title, sub in
                    Button { goal = g } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L(title))
                                    .font(NBFont.ui(400, 16)).tracking(0.01 * 16)
                                    .foregroundStyle(NB.text1)
                                Text(L(sub))
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
        OnbPage(counter: L("BASELINE 01 / 03"),
                title: L("Now, your baseline"),
                sub: L("Rest your hand on the table and touch the side key with your index finger. Hold still."),
                onBack: onBack,
                cta: L("Start body scan"), ctaEnabled: lowBattery == nil, onCTA: {
                    Task { await Analytics.shared.track("SCAN_START", [:]) }
                    onStart()
                },
                footnote: L("Takes about 30 seconds")) {
            ZStack {
                if let lowBattery {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            BatteryGlyph()
                            Text(L("BATTERY %d%%", lowBattery))
                                .font(NBFont.dot(600, 12)).tracking(0.2 * 12).foregroundStyle(NB.ember1)
                        }
                        Text(L("Charge the band before the first scan — it needs about 15%."))
                            .font(NBFont.ui(400, 14.5)).tracking(0.01 * 14.5).lineSpacing(6)
                            .foregroundStyle(NB.white.opacity(0.80))
                        Button {
                            Task { await Analytics.shared.track("SCAN_SKIP", ["REASON": "LOW_BATTERY"]) }
                            onSkip()
                        } label: {
                            Text(L("Skip for now, measure later →")).font(NBFont.ui(500, 14)).tracking(0.02 * 14).foregroundStyle(NB.lime1)
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

                Text(L("INDEX FINGER ON THE SIDE KEY"))
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
    /// Pushed to the band before the scan starts (F2 §05).
    let info: PersonalInfo
    let onDone: (BodyCompositionReading) -> Void
    var onSkip: () -> Void = {}
    var onReconnect: () -> Void = {}
    /// The band's own seconds. Nothing on this screen is timed by the phone: the count is
    /// whatever the SDK's progress says, and it holds while the fingers are off.
    @State private var remaining = 30
    /// 03 edge 2 · a lifted finger holds the count on screen; the band itself starts over.
    @State private var holding = false
    @State private var restarts = 0
    /// 03 edge 3 · the one edge this screen cannot fix itself.
    @State private var dropped = false
    /// The SDK ran and said no — its reason, in its words. Retry or skip; never a number.
    @State private var failure: String?
    @State private var attempt = 0
    /// True only while the band is actually measuring. Before contact, and whenever the
    /// fingers are off, the trace is a flat line: a beating wave with nothing being read is
    /// a picture of a measurement that is not happening.
    @State private var measuring = false
    @State private var startedAt = Date()
    /// When the band's count last moved — the figure hops from this instant, never from a timer.
    @State private var beatAt = Date()
    /// Edge 1 · NO CONTACT. Rises after 4 s without contact (3 s after a lift), and drops the
    /// instant the band reports the fingers.
    @State private var nudge = false
    @State private var nudgeTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            if nudge {
                ContactNudgeSheet(lifted: holding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: nudge)
        // Leaving the screen cancels this task, which ends the stream, which stops the
        // band's test (F1 rule 05). `attempt` re-runs it from the failure card.
        .task(id: attempt) { await scanTask() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Chrome.gateTopInset)
            // Once the scan starts the back key is gone — you cannot half-measure a body.
            OnbHeader(counter: L("BASELINE 02 / 03"))
            OnbTitle(title: L("Scanning"),
                     sub: L("A tiny current maps your body — you won't feel a thing. Keep your finger on the key."))
                .padding(.top, 24)

            if let failure {
                VStack(alignment: .leading, spacing: 14) {
                    Text(failure)
                        .font(NBFont.dot(600, 12)).tracking(0.2 * 12).foregroundStyle(NB.ember1)
                    Text(L("The band ran the scan and could not finish it.\nNothing you filled in is lost."))
                        .font(NBFont.ui(400, 14.5)).tracking(0.01 * 14.5).lineSpacing(6)
                        .foregroundStyle(NB.white.opacity(0.80))
                    HStack(spacing: 24) {
                        Button(action: { attempt += 1 }) {
                            Text(L("Try again →")).font(NBFont.ui(500, 14)).tracking(0.02 * 14).foregroundStyle(NB.lime1)
                        }
                        .buttonStyle(.plain)
                        Button(action: onSkip) {
                            Text(L("Skip for now")).font(NBFont.ui(400, 14)).tracking(0.02 * 14).foregroundStyle(NB.white.opacity(0.42))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .frame(width: NB.Layout.contentWidth, height: 176, alignment: .leading)
                .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous).stroke(NB.hairline, lineWidth: 1))
                .padding(.top, 60)
            } else if dropped {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("BAND DISCONNECTED"))
                        .font(NBFont.dot(600, 12)).tracking(0.2 * 12).foregroundStyle(NB.ember1)
                    Text(L("The band went quiet mid-scan.\nNothing you filled in is lost."))
                        .font(NBFont.ui(400, 14.5)).tracking(0.01 * 14.5).lineSpacing(6)
                        .foregroundStyle(NB.white.opacity(0.80))
                    Button(action: onReconnect) {
                        Text(L("Reconnect →")).font(NBFont.ui(500, 14)).tracking(0.02 * 14).foregroundStyle(NB.lime1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .frame(width: NB.Layout.contentWidth, height: 176, alignment: .leading)
                .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous).stroke(NB.hairline, lineWidth: 1))
                .padding(.top, 60)
            } else {
            // BIA has no waveform. The current walks the body, one beat per band second;
            // edge 2 · a lifted finger freezes the figure where it was and turns it amber.
            BodyFill(beat: 30 - remaining, beatAt: beatAt, active: measuring, held: holding)
                .frame(height: 280)
                .padding(.top, 24)
                .onChange(of: remaining) { beatAt = Date() }

            Text(L("BODY COMPOSITION"))
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.34))
                .padding(.top, 28)

            // The counter counts down, not up: the ETA belongs before the wait, not during it.
            // Edge 2 · it holds — never resets to zero; zero looks like 「白干了」.
            Text(holding ? L("HOLDING · 00:%02d", remaining) : String(format: "00:%02d", remaining))
                .font(holding ? NBFont.dot(600, 12) : NBFont.dot(700, 26)).tracking(holding ? 0.2 * 12 : 0.14 * 26)
                .foregroundStyle(holding ? NB.ember1 : NB.lime1)
                .padding(.top, 12)
                .contentTransition(.numericText(countsDown: true))
            }

            Spacer(minLength: 0)

            // Grey, in front — what to do if it breaks, said before it breaks.
            Text(holding ? L("Put your finger back — we'll pick it up.")
                 : restarts > 0 ? L("Second lift — starting over from 30.")
                 : L("Lift your finger and the scan restarts."))
                .font(holding ? NBFont.ui(400, 14.5) : NBFont.ui(300, 13)).tracking(0.02 * 13)
                .foregroundStyle(holding ? NB.emberPale : NB.white.opacity(0.42))

            Color.clear.frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func scanTask() async {
            // DEBUG walks on the mock: `lifted` pauses at 3 s and lifts again at 9 s;
            // `banddropped` loses the band at 2 s.
            #if DEBUG
            if applyDebugScanPin() { return }
            #endif
            if DebugEdge.on("lifted") {
                remaining = 30; measuring = true
                for _ in 0..<3 { try? await Task.sleep(for: .seconds(1)); withAnimation { remaining -= 1 } }
                withAnimation { holding = true }
                try? await Task.sleep(for: .seconds(3)); withAnimation { holding = false }
                for _ in 0..<3 { try? await Task.sleep(for: .seconds(1)); withAnimation { remaining -= 1 } }
                withAnimation { holding = true }
                try? await Task.sleep(for: .seconds(2)); withAnimation { holding = false; restarts += 1; remaining = 30 }
                while remaining > 0 { try? await Task.sleep(for: .seconds(1)); withAnimation { remaining -= 1 } }
                return
            }
            if DebugEdge.on("banddropped") {
                try? await Task.sleep(for: .seconds(2)); withAnimation { dropped = true }
                return
            }
            let watch = Task {
                for await event in Band.live.events {
                    if case .state(.disconnected) = event {
                        await MainActor.run { withAnimation { dropped = true } }
                        return
                    }
                }
            }
            defer { watch.cancel() }
            await runScan()
    }

    #if DEBUG
    /// `NB_DEBUG_SCAN_LEFT=24` freezes the body-fill figure at that remaining second.
    /// `NB_DEBUG_SCAN_HOLD=1` paints the amber lift; `nocontact` raises the nudge sheet.
    private func applyDebugScanPin() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["NB_DEBUG_SCAN_LEFT"], let left = Int(raw) else { return false }
        remaining = min(30, max(0, left))
        beatAt = Date()
        measuring = env["NB_DEBUG_SCAN_HOLD"] != "1"
            && !DebugEdge.on("nocontact")
            && !DebugEdge.on("banddropped")
        holding = env["NB_DEBUG_SCAN_HOLD"] == "1" || DebugEdge.on("lifted")
        if holding { measuring = true }
        if DebugEdge.on("nocontact") {
            measuring = false
            holding = false
            nudge = true
        }
        if DebugEdge.on("banddropped") {
            dropped = true
            measuring = false
            holding = false
        }
        return true
    }
    #endif

    /// Start (or restart) the no-contact clock: the sheet rises if nothing has changed by then.
    private func armNudge(after seconds: Double) {
        nudgeTask?.cancel()
        nudgeTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, failure == nil, !dropped else { return }
            if !measuring || holding { nudge = true }
        }
    }

    private func disarmNudge() {
        nudgeTask?.cancel(); nudgeTask = nil
        if nudge { nudge = false }
    }

    /// The scan is the band's. Weight first (F2 §05), then every state on screen is one the
    /// SDK reported: contact, its own seconds, a lifted finger, the twelve fields, or why not.
    private func runScan() async {
        remaining = 30; holding = false; failure = nil; dropped = false; measuring = false
        startedAt = Date()
        disarmNudge()
        do {
            // A relaunch between pairing and this screen leaves the band bound but not
            // connected; the SDK reconnects to it on its own before anything is pushed.
            if Band.live.state != .connected { await Band.live.reconnectIfBound() }
            try await Band.live.syncPersonalInfo(info)
            armNudge(after: 4)
            for try await step in Band.live.measureBodyComposition() {
                switch step {
                case .waitingForContact:
                    break
                case .contact:
                    disarmNudge()
                    withAnimation { holding = false; measuring = true }
                case .measuring(let fraction, _, let secondsLeft):
                    disarmNudge()
                    let left = secondsLeft ?? Int(((1 - fraction) * 30).rounded())
                    withAnimation { remaining = max(0, left); holding = false; measuring = true }
                case .lostContact:
                    // 03 edge 2 · the count holds where it was; the band starts over on contact.
                    withAnimation { holding = true; restarts += 1 }
                    armNudge(after: 3)
                case .finished(.bodyComposition(let r)):
                    disarmNudge()
                    withAnimation { measuring = false }
                    await Analytics.shared.track("SCAN_DONE", ["MS": Int(Date().timeIntervalSince(startedAt) * 1000), "RESTARTS": restarts])
                    onDone(r)
                    return
                case .finished:
                    return
                case .failed(let reason):
                    disarmNudge()
                    withAnimation { failure = reason }
                    return
                }
            }
        } catch BandError.notConnected {
            disarmNudge()
            withAnimation { dropped = true }
        } catch is CancellationError {
            return
        } catch {
            disarmNudge()
            withAnimation { failure = (error as? BandError)?.errorDescription ?? "BAND OFFLINE" }
        }
    }
}

// MARK: 06 · 交底 Baseline

private struct BaselineScreen: View {
    /// What the band returned. nil only when the scan was skipped — every tile is a dash then.
    let reading: BodyCompositionReading?
    let onEnter: () -> Void

    private func f(_ v: Double?, _ decimals: Int = 1) -> String {
        v.map { String(format: "%.\(decimals)f", $0) } ?? Fmt.dash
    }

    /// The full twelve the SDK returns, laid out flat — this screen collects,
    /// it does not judge. No good/high/low anywhere: day zero has nothing to compare to.
    private var tiles: [(String, String, String, Color)] {
        let r = reading
        return [
            ("FAT MASS", f(r?.fatMassKg), "kg", NB.lime1),
            ("LEAN MASS", f(r?.leanMassKg), "kg", NB.lime1),
            ("MUSCLE", f(r?.muscleKg), "kg", NB.lime1),
            ("MUSCLE RATE", f(r?.muscleRatePercent), "%", NB.lime1),
            ("SKELETAL", f(r?.skeletalMusclePercent), "%", NB.lime1),
            ("BONE", f(r?.boneKg), "kg", NB.lime1),
            ("BODY WATER", f(r?.bodyWaterPercent), "%", NB.cyan1),
            ("WATER", f(r?.waterKg), "kg", NB.cyan1),
            ("PROTEIN", f(r?.proteinPercent), "%", NB.cyan1),
            ("PROTEIN MASS", f(r?.proteinKg), "kg", NB.cyan1),
            ("SUBCUT FAT", f(r?.subcutaneousFatPercent), "%", NB.cyan1),
            ("BMR ESTIMATE", r?.bmrKcal.map(String.init) ?? Fmt.dash, "kcal/day", NB.ember1),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Chrome.gateTopInset)
            OnbHeader(counter: L("BASELINE 03 / 03"))
            OnbTitle(title: L("Your baseline"), sub: L("First scan complete — this is day zero."))
                .padding(.top, 24)

            HStack(spacing: 0) {
                HeadlineStat(value: f(reading?.bodyFatPercent), unit: "%", label: L("BODY FAT"), labelTint: NB.lime1)
                Rectangle().fill(NB.white.opacity(0.08)).frame(width: 1, height: 72)
                HeadlineStat(value: f(reading?.bmi), unit: nil, label: L("BMI"), labelTint: NB.white.opacity(0.42))
            }
            .frame(width: NB.Layout.contentWidth, height: 116)
            .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
                .stroke(NB.white.opacity(0.08), lineWidth: 1))
            .padding(.top, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(114), spacing: 8), count: 3), spacing: 8) {
                ForEach(tiles, id: \.0) { t in
                    BaselineTile(label: t.0, value: t.1, unit: t.2, tint: t.3)
                }
            }
            .frame(width: NB.Layout.contentWidth)
            .padding(.top, 16)

            Spacer(minLength: 0)

            // "Enter NEXTBODY", never "Done" — the end point is the product, not the form.
            LimePillButton(title: L("Enter NEXTBODY"), action: onEnter)
            Text(L("Scan again anytime from the Device page"))
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
            Text(L(label))
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
            Text(L(label))
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
                Text(L("NEXTBODY IS 18+"))
                    .font(NBFont.dot(700, 13)).tracking(0.3 * 13)
                    .foregroundStyle(NB.alert2)
                Text(L("We can't create an account for someone under 18."))
                    .font(NBFont.ui(400, 17)).tracking(0.01 * 17)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NB.text1)
                    .frame(width: 280)
                Button(action: onBack) {
                    Text(L("Change date of birth"))
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
