import SwiftUI
import UIKit
import UserNotifications

/// 11 · the thirteen sheets. New settings default to a sheet; making one a page has to be
/// argued for first. None of them is more than 78% of the screen tall.
struct ProfileSheet: View {
    let route: SheetRoute
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch route {
            case .profileEdit:   PersonalInfoSheet()
            case .goal:          TrainingGoalSheet()
            case .notifications: NotificationsSheet()
            case .units:         UnitsSheet()
            case .language:      LanguageSheet()
            case .appleHealth:   AppleHealthSheet()
            case .feedback:      FeedbackSheet()
            case .privacy:       LegalSheet(.privacy)
            case .about:         LegalSheet(.terms)
            case .deleteAccount: DeleteAccountSheet()
            case .signOut:       SignOutSheet()
            case .widgets:       WidgetsSheet()
            default:             EmptyView()
            }
        }
        .background(NB.carbon2)
    }
}

/// Body inputs remain editable without Health. Profile writes must succeed before closing;
/// manual weights use the durable weigh-in queue and the existing server settlement.
struct PersonalInfoSheet: View {
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var birthdate = Date()
    @State private var sexIsMale = true
    @State private var saving = false
    @State private var saveError = false
    @State private var originalWeightText = ""
    @State private var heightCm: Double = 170
    @State private var weightText = ""
    @State private var stepGoalText = ""
    @State private var heightSheet = false
    @State private var heightError = false
    @State private var weightError = false
    @State private var stepGoalError = false

    private var metric: Bool { data.profile.usesMetric }

    var body: some View {
        SheetFrame(title: L("Your details")) {
            ScrollView {
                VStack(spacing: 10) {
                    FieldBox(label: L("Name"), text: $name)
                    FieldBox(label: L("Email"), text: $email, badge: L("VERIFIED"))
                        .disabled(true)
                    DatePicker(L("Birthday"), selection: $birthdate,
                               in: ...Date(), displayedComponents: .date)
                        .tint(NB.lime1)
                        .accessibilityIdentifier("profile.birthday")
                    Picker(L("Sex"), selection: $sexIsMale) {
                        Text(L("Female")).tag(false)
                        Text(L("Male")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("profile.sex")
                    Button { heightSheet = true } label: {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("Height"))
                                    .font(NBFont.ui(400, 11)).tracking(0.06 * 11)
                                    .foregroundStyle(NB.white.opacity(0.38))
                                Text(heightLabel)
                                    .font(NBFont.ui(400, 16))
                                    .foregroundStyle(NB.text1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 66)
                        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
                            .stroke(NB.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.height")
                    FieldBox(label: L("Weight") + (metric ? " · KG" : " · LB"), text: $weightText, keyboard: .decimalPad)
                        .accessibilityIdentifier("profile.weight")
                    // The band's own daily step ring. It is pushed to the firmware, so this is
                    // the one number on this sheet the wrist reads back to you.
                    FieldBox(label: L("Daily step goal"), text: $stepGoalText, keyboard: .numberPad)
                        .accessibilityIdentifier("profile.stepGoal")
                }
            }
            if saveError {
                Text(L("Could not save your details. Please try again."))
                    .font(NBFont.ui(400, 12))
                    .foregroundStyle(NB.ember1)
                    .accessibilityIdentifier("profile.saveError")
            } else if heightError {
                Text(L("Height is out of range."))
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.ember1.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            } else if stepGoalError {
                Text(L("Step goal is out of range."))
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.ember1.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            } else if weightError {
                Text(L("Weight is out of range."))
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.ember1.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            } else {
                Text(L("Tap any field to change it"))
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
        } footer: {
            LimePillButton(title: saving ? L("Saving…") : L("Save")) { save() }
                .disabled(saving)
                .accessibilityIdentifier("profile.save")
        }
        .interactiveDismissDisabled(saving)
        .onAppear {
            name = data.profile.name
            email = data.profile.email
            birthdate = data.profile.birthdate
            sexIsMale = data.profile.sexIsMale
            heightCm = data.profile.heightCm
            stepGoalText = String(data.profile.stepGoal)
            if let kg = data.today.weightKg {
                weightText = metric ? String(format: "%.1f", kg)
                    : String(format: "%.1f", kg * 2.2046226)
            }
            originalWeightText = weightText
        }
        .sheet(isPresented: $heightSheet) {
            HeightRulerSheet(value: $heightCm) {
                heightError = !(120...220).contains(heightCm)
                if !heightError { heightSheet = false }
            }
        }
    }

    private var heightLabel: String {
        if metric { return "\(Int(heightCm.rounded())) cm" }
        let inches = heightCm / 2.54
        return "\(Int(inches) / 12)'\(Int(inches) % 12)\""
    }

    private func save() {
        guard !saving else { return }
        heightError = !(120...220).contains(heightCm)
        let kg = parsedKg
        weightError = kg == nil && !weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let steps = Int(stepGoalText.trimmingCharacters(in: .whitespacesAndNewlines))
        stepGoalError = steps == nil || !(1_000...60_000).contains(steps!)
        if heightError || weightError || stepGoalError { return }
        let owner = SupabaseClient.currentUserIdSnapshot()
        var saved = data.profile
        saved.name = name
        saved.heightCm = heightCm
        saved.birthdate = birthdate
        saved.sexIsMale = sexIsMale
        saved.stepGoal = steps!
        var edited = ["display_name"]
        if data.profile.heightCm != heightCm { edited.append("height_cm") }
        if data.profile.birthdate != birthdate { edited.append("birth_date") }
        if data.profile.sexIsMale != sexIsMale { edited.append("sex") }
        let weightChanged = weightText != originalWeightText && kg != nil
        if weightChanged { edited.append("weight_kg") }
        saving = true
        saveError = false
        Task { @MainActor in
            defer { saving = false }
            guard await Repository.shared.saveProfile(saved, editedFields: edited),
                  owner == SupabaseClient.currentUserIdSnapshot() else {
                saveError = true
                return
            }
            data.profile = saved
            if weightChanged, let kg {
                guard data.addWeighIn(WeighIn(id: UUID(), date: Date(), weightKg: kg,
                    bodyFatPercent: nil, source: .measured, origin: .manual)) else {
                    saveError = true
                    return
                }
            }
            // Use the same publication and settlement path as a completed measurement.
            // Pending manual weights remain durable if connectivity drops after saving.
            await Repository.shared.flushPendingEvidence(afterCurrent: true)
            guard owner == SupabaseClient.currentUserIdSnapshot() else { return }
            if let kg = kg ?? data.today.weightKg {
                let info = PersonalInfo(heightCm: Int(saved.heightCm.rounded()),
                    weightKg: Int(kg.rounded()),
                    birthYear: Calendar.current.component(.year, from: saved.birthdate),
                    sexIsMale: saved.sexIsMale, targetStep: saved.stepGoal)
                Task { try? await Band.live.syncPersonalInfo(info) }
            }
            dismiss()
        }
    }

    private var parsedKg: Double? {
        var raw = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = raw.replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "．", with: ".")
            .replacingOccurrences(of: ",", with: ".")
        guard !raw.isEmpty, let v = Double(raw) else { return nil }
        let kg = metric ? v : v / 2.2046226
        return (20...300).contains(kg) ? kg : nil
    }
}

/// 04 · four options, tapping one is the commit. There is no Save — choosing is the action.
struct TrainingGoalSheet: View {
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss

    private static let options: [(Goal, String, String)] = [
        (.bulk, "Strength", "Lean mass first, the scale second"),
        (.cut, "Endurance", "Aerobic base and recovery lead"),
        (.recomp, "Recomp", "Trade fat for muscle, same weight"),
    ]

    var body: some View {
        SheetFrame(title: L("Training goal")) {
            VStack(spacing: 10) {
                ForEach(Self.options, id: \.0) { g, title, sub in
                    Button {
                        if data.profile.goal != g {
                            UserDefaults.standard.set(UserDay.containing(Date()).key, forKey: "nb.goal.changedDay")
                        }
                        data.profile.goal = g
                        let saved = data.profile
                        Task { await Repository.shared.saveProfile(saved, editedFields: ["goal"]) }
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(NBFont.ui(500, 16)).tracking(0.01 * 16)
                                    .foregroundStyle(NB.text1)
                                Text(sub)
                                    .font(NBFont.ui(300, 12)).tracking(0.02 * 12)
                                    .foregroundStyle(NB.white.opacity(0.38))
                            }
                            Spacer(minLength: 0)
                            Circle()
                                .fill(data.profile.goal == g ? NB.lime1 : Color.clear)
                                .overlay(data.profile.goal == g ? nil
                                         : Circle().stroke(NB.white.opacity(0.2), lineWidth: 1))
                                .frame(width: 10, height: 10)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 66)
                        .background(data.profile.goal == g ? NB.lime1.opacity(0.06) : NB.carbon4,
                                    in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
                            .stroke(data.profile.goal == g ? NB.lime1.opacity(0.6) : NB.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            // Today's numbers are already spent; changing the goal cannot rewrite them.
            Text(L("Takes effect with tomorrow's numbers"))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
        }
    }
}

/// ADR 0019 · seven edge switches. Move and drink buzzes live on the band, not here.
struct NotificationsSheet: View {
    @AppStorage("nb.notif.morning") private var morning = true
    @AppStorage("nb.notif.training") private var training = true
    @AppStorage("nb.notif.meals") private var meals = true
    @AppStorage("nb.notif.wrap") private var wrap = true
    @AppStorage("nb.notif.energy") private var energy = true
    @AppStorage("nb.notif.band") private var band = true
    @AppStorage("nb.notif.quiet") private var quiet = true
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var data: DataStore
    @State private var systemStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        SheetFrame(title: L("Notifications")) {
            VStack(spacing: 12) {
                if systemDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L("Notifications are off in Settings"))
                                    .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                                    .foregroundStyle(NB.text1)
                                Text(L("ACCESS OFF"))
                                    .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                                    .foregroundStyle(NB.ember1)
                            }
                            Spacer(minLength: 0)
                            Text(L("Open Settings"))
                                .font(NBFont.ui(500, 13))
                                .foregroundStyle(NB.lime1)
                        }
                        .padding(.horizontal, 16)
                        .frame(width: NB.Layout.contentWidth, height: 62)
                        .cardSkin()
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 0) {
                    SwitchRow(title: L("Morning report"), detail: L("WHEN LAST NIGHT LANDS"), isOn: $morning)
                    SwitchRow(title: L("Training nudge"), detail: L("UNDER TARGET · RESERVE DROPS"), isOn: $training)
                    SwitchRow(title: L("Meals"), detail: L("NEXT SLOT EMPTY · YOU MOVED"), isOn: $meals)
                    SwitchRow(title: L("Daily wrap"), detail: L("WHEN THE DAY FILLS IN"), isOn: $wrap)
                    SwitchRow(title: L("Energy"), detail: L("RESERVE CROSSES 25"), isOn: $energy)
                    SwitchRow(title: L("Band"), detail: L("AWAY 4 H / CHARGE 15"), isOn: $band)
                    SwitchRow(title: L("Quiet hours"), detail: L("22:30 → 07:00"), isOn: $quiet, last: true)
                }
                .frame(width: NB.Layout.contentWidth)
                .cardSkin()
                .opacity(systemDenied ? 0.38 : 1)
                .allowsHitTesting(!systemDenied)
            }
        } footer: {
            Text(L("Move and drink buzzes live on the HOOP."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
        }
        // F5 · D08 — the notification permission gets a primer before the system prompt.
        // Nothing in the product has ever asked for it before.
        .task { await requestIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await requestIfNeeded() }
        }
        .onChange(of: morning) { _, _ in refreshReach() }
        .onChange(of: training) { _, _ in refreshReach() }
        .onChange(of: meals) { _, _ in refreshReach() }
        .onChange(of: wrap) { _, _ in refreshReach() }
        .onChange(of: energy) { _, _ in refreshReach() }
        .onChange(of: band) { _, _ in refreshReach() }
        .onChange(of: quiet) { _, _ in refreshReach() }
    }

    private var systemDenied: Bool {
        systemStatus == .denied
    }

    private func refreshReach() {
        NotificationReach.applyPrefs()
    }

    private func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        systemStatus = settings.authorizationStatus
        guard settings.authorizationStatus == .notDetermined else {
            if NotificationReach.isAuthorized(settings.authorizationStatus) {
                await NotificationReach.registerRemote()
                await NotificationReach.refresh(today: data.today, history: data.history,
                                                store: data, page: router.notifyPage, appIsActive: true)
            }
            return
        }
        // F5 C4 · the same primer the first morning shows; the system dialog only after its Turn on.
        router.takeover = .notificationPrimer
    }
}

struct SwitchRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var last = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                    .foregroundStyle(NB.text1)
                Text(detail)
                    .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.white.opacity(0.34))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(NB.lime1)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .overlay(alignment: .bottom) { last ? nil : Hairline().padding(.leading, 16) }
    }
}

/// 06 · two segmented rows plus a language row. Instant, no Save.
/// ⚠️ The unit is a display preference only: the SDK's own unit flag is never written to the band.
struct UnitsSheet: View {
    @EnvironmentObject private var data: DataStore
    @State private var weightUnit = "KG"
    @State private var heightUnit = "CM"

    var body: some View {
        SheetFrame(title: L("Units & language")) {
            VStack(spacing: 0) {
                HStack {
                    Text(L("Weight")).font(NBFont.ui(500, 14)).foregroundStyle(NB.text1)
                    Spacer(minLength: 0)
                    UnitToggle(options: ["KG", "LB"], selection: $weightUnit)
                }
                .padding(.horizontal, 16).frame(height: 62)
                .overlay(alignment: .bottom) { Hairline().padding(.leading, 16) }

                HStack {
                    Text(L("Height")).font(NBFont.ui(500, 14)).foregroundStyle(NB.text1)
                    Spacer(minLength: 0)
                    UnitToggle(options: ["CM", "FT"], selection: $heightUnit)
                }
                .padding(.horizontal, 16).frame(height: 62)
                .overlay(alignment: .bottom) { Hairline().padding(.leading, 16) }

                HStack {
                    Text(L("Language")).font(NBFont.ui(500, 14)).foregroundStyle(NB.text1)
                    Spacer(minLength: 0)
                    Text(AppLanguage.shared.locale.nativeName)
                        .font(NBFont.ui(400, 13))
                        .foregroundStyle(NB.text3Prod)
                    Chevron()
                }
                .padding(.horizontal, 16).frame(height: 62)
            }
            .frame(width: NB.Layout.contentWidth)
            .cardSkin()
        } footer: {
            Text(L("Changes everywhere, straight away"))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
        }
        .onAppear {
            #if DEBUG
            if DebugEdge.on("imperial") {
                weightUnit = "LB"
                heightUnit = "FT"
            }
            #endif
        }
        .onChange(of: weightUnit) { _, v in
            data.profile.usesMetric = (v == "KG")
            let saved = data.profile
            Task { await Repository.shared.saveProfile(saved, editedFields: ["units_metric"]) }
        }
    }
}

struct LanguageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var language = AppLanguage.shared

    var body: some View {
        SheetFrame(title: L("Language")) {
            VStack(spacing: 0) {
                ForEach(AppLocale.allCases) { loc in
                    Button { language.set(loc); dismiss() } label: {
                        HStack {
                            Text(loc.nativeName).font(NBFont.ui(500, 15)).foregroundStyle(NB.text1)
                            Spacer(minLength: 0)
                            if language.locale == loc { Circle().fill(NB.lime1).frame(width: 10, height: 10) }
                        }
                        .padding(.horizontal, 16).frame(height: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { loc == AppLocale.allCases.last ? nil : Hairline().padding(.leading, 16) }
                }
            }
            .frame(width: NB.Layout.contentWidth)
            .cardSkin()
        } footer: {
            Text(L("The screen answers in this language, including metric names."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.white.opacity(0.38))
        }
    }
}

/// ⚠️ F5 · HealthKit read permission cannot be probed. An empty read means "nothing came back",
/// never "you refused" — so this screen never claims to know the answer.
struct AppleHealthSheet: View {
    @EnvironmentObject private var data: DataStore

    var body: some View {
        SheetFrame(title: L("Apple Health")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Circle().fill(data.profile.appleHealthLinked ? NB.optimal2 : NB.ember1)
                        .accessibilityLabel(data.profile.appleHealthLinked ? "Connected" : "Needs you")
                        .frame(width: 8, height: 8)
                    Text(data.profile.appleHealthLinked ? L("SYNCED") : L("NOT CONNECTED"))
                        .font(NBFont.dot(700, 12)).tracking(0.16 * 12)
                        .foregroundStyle(data.profile.appleHealthLinked ? NB.optimal2 : NB.ember1)
                    Spacer(minLength: 0)
                }
                // ⚠️ Board 11 said "and write back the weigh-ins you enter by hand". The consent
                // screen (later, and the legal one) says "We never write anything back to Apple
                // Health", and the app does not — so this sentence follows the consent board.
                Text(L("We read your sex, date of birth, height and weight. Nothing is ever written back."))
                    .font(NBFont.brand(400, 14))
                    .lineSpacing(7)
                    .foregroundStyle(NB.text2)
                Text(L("A blank read means nothing came back — not that you refused."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            .padding(16)
            .frame(width: NB.Layout.contentWidth, alignment: .leading)
            .cardSkin()
        } footer: {
            LimePillButton(title: data.profile.appleHealthLinked ? "Re-check now" : "Connect Apple Health") {
                Task {
                    await HealthService.shared.requestRead()
                    let baseline = await HealthService.shared.readBaseline()
                    // An empty re-check cannot undo a completed import or prove revocation.
                    if !baseline.isEmpty { data.profile.appleHealthLinked = true }
                    data.profile = data.profile.restoringHealthSync()
                }
            }
        }
    }
}

/// Terms or Privacy, in the app's language. The text lives in `LegalText`.
struct LegalSheet: View {
    let kind: LegalText.Kind
    init(_ kind: LegalText.Kind) { self.kind = kind }

    var body: some View {
        let doc = LegalText.document(kind)
        SheetFrame(title: doc.title) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text(doc.updated)
                        .font(NBFont.ui(400, 12)).tracking(0.02 * 12)
                        .foregroundStyle(NB.text3Prod)
                    ForEach(Array(doc.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.heading)
                                .font(NBFont.ui(500, 15))
                                .foregroundStyle(NB.text1)
                            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(NBFont.brand(400, 14))
                                    .lineSpacing(7)
                                    .foregroundStyle(NB.text2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)
            }
        } footer: { EmptyView() }
    }
}

/// 07 · asks twice and counts the loss. The second confirm has to say what will be lost.
/// ⚠️ "There is no undo" must line up with the server: the row is deleted, not flagged.
struct DeleteAccountSheet: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var weighIns: Int?
    @State private var weeks: Int?
    @State private var nights: Int?
    @State private var failure: String?

    /// ⚠️ 1BAY · the second ask must count out what is about to be lost. Counting what is in
    /// memory counts the page size — the list is fetched 60 at a time — so these are exact
    /// counts off the server, and each one stays "——" until it arrives rather than guessing.
    private var losses: String {
        let w = weighIns.map(String.init) ?? Fmt.dash
        let c = weeks.map { L("%d weeks", $0) } ?? Fmt.dash
        let n = nights.map { L("%d nights", $0) } ?? Fmt.dash
        return L("%@ weigh-ins, %@ of composition and %@ you have slept in it go with it. The HOOP unpairs itself. There is no undo.", w, c, n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Delete your account?"))
                .font(NBFont.ui(500, 24)).tracking(0.01 * 24)
                .foregroundStyle(NB.text1)
            Text(losses)
                .font(NBFont.brand(400, 14))
                .lineSpacing(7)
                .foregroundStyle(NB.text2)

            if let failure {
                Text(failure)
                    .font(NBFont.ui(400, 12)).tracking(0.02 * 12)
                    .foregroundStyle(NB.alert2)
            }

            Spacer(minLength: 0)

            LimePillButton(title: L("Keep my account")) { dismiss() }

            Button {
                Task { await deleteEverything() }
            } label: {
                Text(L("DELETE EVERYTHING"))
                    .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                    .foregroundStyle(NB.alert2)
                    .frame(width: NB.Layout.contentWidth, height: 52)
                    .overlay(Capsule().stroke(NB.alert2.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            weighIns = await SupabaseClient.shared.count("weigh_ins")
            nights = await SupabaseClient.shared.count("sleep_nights")
            if let days = await SupabaseClient.shared.count("body_composition") {
                weeks = max(1, Int((Double(days) / 7).rounded()))
            }
            await Analytics.shared.track("ACCOUNT_DELETE_SHOWN", [:])
        }
    }

    /// ⚠️ 1DPG · account/delete failing is a legal event, not a toast. The button used to
    /// call session.reset(), which signs the user out and deletes nothing — under a sentence
    /// promising there is no undo. If the endpoint cannot be reached the account is still
    /// there, and the sheet has to say so rather than look like it worked.
    private func deleteEverything() async {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return }
        await Analytics.shared.track("ACCOUNT_DELETE_CONFIRMED", [:])
        do {
            // ⚠️ The confirmation is a literal the server checks, so a mis-routed call
            // cannot delete an account. It is the same second ask this sheet just made.
            let row = try await SupabaseClient.shared.callFunction("account-delete", payload: ["confirm": "DELETE"], expectedOwner: owner)
            guard row["deleted"] as? Bool == true else {
                // F5 C8 · the failure sentence is fixed, and the same whichever half failed.
                failure = Self.failureCopy(ref: "\(row["error"] ?? "unknown")")
                await Analytics.shared.track("ACCOUNT_DELETE_FAILED",
                                             ["ERROR": "\(row["error"] ?? "unknown")"])
                return
            }
            // Not reset() — that is the sign-out, and it leaves the band paired and every
            // nb.* key on the phone. The sheet just promised there is no undo.
            session.purgeAfterAccountDelete()
            dismiss()
        } catch {
            failure = Self.failureCopy(ref: "\(error)")
            await Analytics.shared.track("ACCOUNT_DELETE_FAILED", ["ERROR": "\(error)"])
        }
    }

    /// 11 edge 5 · ALL OR NOTHING. The sentence is the board's, and the reference is something a
    /// person can read out to support — derived from the error so the same failure gets the
    /// same number.
    static func failureCopy(ref: String) -> String {
        var h: UInt32 = 2166136261
        for b in ref.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        let ref = String(format: "%04X-%02X", h & 0xFFFF, (h >> 16) & 0xFF)
        return L("DELETION FAILED\nNothing was removed. Your account is exactly as it was. Try again, or write to us.\nREF %@", ref)
    }
}

struct SignOutSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: L("Sign out?")) {
            // 11 edge 4 · not the same as delete, and it has to say so on the spot.
            Text(L("The HOOP stays paired and keeps recording.\nYour data comes back when you sign in."))
                .font(NBFont.brand(400, 14))
                .lineSpacing(7)
                .foregroundStyle(NB.text2)
        } footer: {
            VStack(spacing: 14) {
                LimePillButton(title: L("Stay signed in")) { dismiss() }
                Button {
                    session.reset()
                    dismiss()
                } label: {
                    Text(L("Sign out"))
                        .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                        .foregroundStyle(NB.text3Prod)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: sheet chrome

struct SheetFrame<Content: View, Footer: View>: View {
    let title: String
    var fillsHeight = true
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                .foregroundStyle(NB.text1)
            content
            if fillsHeight { Spacer(minLength: 0) }
            footer.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity,
               maxHeight: fillsHeight ? .infinity : nil,
               alignment: .top)
    }
}

struct FieldBox: View {
    let label: String
    @Binding var text: String
    var badge: String? = nil
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(NBFont.ui(400, 11)).tracking(0.06 * 11)
                    .foregroundStyle(NB.white.opacity(0.38))
                TextField("", text: $text)
                    .font(NBFont.ui(400, 16))
                    .foregroundStyle(NB.text1)
                    .tint(NB.lime1)
                    .keyboardType(keyboard)
            }
            if let badge {
                Text(badge)
                    .font(NBFont.dot(600, 9)).tracking(0.18 * 9)
                    .foregroundStyle(NB.lime1)
                    .padding(.horizontal, 10).frame(height: 22)
                    .overlay(Capsule().stroke(NB.lime1.opacity(0.4), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
            .stroke(NB.hairline, lineWidth: 1))
    }
}

struct TimeFieldBox: View {
    let label: String
    @Binding var date: Date

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(NBFont.ui(400, 11)).tracking(0.06 * 11)
                    .foregroundStyle(NB.white.opacity(0.38))
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
                    .tint(NB.lime1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
            .stroke(NB.hairline, lineWidth: 1))
    }
}
