import SwiftUI
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
            case .export:        ExportSheet()
            case .privacy:       LegalSheet(title: L("Privacy policy"), body: L(Self.privacyText))
            case .about:         LegalSheet(title: L("Terms of service"), body: L(Self.termsText))
            case .deleteAccount: DeleteAccountSheet()
            case .signOut:       SignOutSheet()
            default:             EmptyView()
            }
        }
        .background(NB.carbon2)
    }

    static let privacyText = """
    We store what you log and what your band measures, and nothing else. \
    Your food descriptions are sent to our model to be turned into numbers; \
    they are not used to train anything.

    You can export everything from Profile → Export my data, and deleting your \
    account removes it all. There is no undo.
    """

    static let termsText = """
    NEXTBODY is free, forever. There is no subscription, no in-app purchase and no \
    paywall — the band is the product.

    NEXTBODY is not a medical device. Nothing it shows is a diagnosis, and nothing it \
    says is medical advice. If something about your body worries you, see a doctor.
    """
}

/// 03 · three fields, an explicit Save. The VERIFIED badge sits after the email;
/// changing it needs re-verification, which is why Save is not automatic here.
struct PersonalInfoSheet: View {
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var phone = "+1 415 ••• 0192"

    var body: some View {
        SheetFrame(title: L("Your details")) {
            VStack(spacing: 10) {
                FieldBox(label: L("Name"), text: $name)
                FieldBox(label: L("Email"), text: $email, badge: L("VERIFIED"))
                FieldBox(label: L("Phone"), text: $phone)
            }
            Text(L("Tap any field to change it"))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        } footer: {
            LimePillButton(title: L("Save")) {
                data.profile.name = name
                data.profile.email = email
                let saved = data.profile
                Task { await Repository.shared.saveProfile(saved, editedFields: ["display_name"]) }
                dismiss()
            }
        }
        .onAppear { name = data.profile.name; email = data.profile.email }
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

/// 05 · four switches, phone-side only. Move and drink buzzes live on the band, not here.
struct NotificationsSheet: View {
    @AppStorage("nb.notif.morning") private var morning = true
    @AppStorage("nb.notif.training") private var training = true
    @AppStorage("nb.notif.weekly") private var weekly = false
    @AppStorage("nb.notif.quiet") private var quiet = true
    @EnvironmentObject private var router: Router

    var body: some View {
        SheetFrame(title: L("Notifications")) {
            VStack(spacing: 0) {
                // 13 · the morning line. It is the only thing the night is allowed to say.
                SwitchRow(title: L("Morning report"), detail: L("07:00"), isOn: $morning)
                SwitchRow(title: L("Training nudge"), detail: L("ONLY IF YOU ARE UNDER BY 17:00"), isOn: $training)
                SwitchRow(title: L("Sunday report"), detail: weekly ? L("ON") : L("OFF"), isOn: $weekly)
                SwitchRow(title: L("Quiet hours"), detail: L("22:30 → 07:00"), isOn: $quiet, last: true)
            }
            .frame(width: NB.Layout.contentWidth)
            .cardSkin()
        } footer: {
            Text(L("Move and drink buzzes live on the HOOP."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
        }
        // F5 · D08 — the notification permission gets a primer before the system prompt.
        // Nothing in the product has ever asked for it before.
        .task { await requestIfNeeded() }
    }

    private func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
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
            Text(L("The screen answers in this language. Metric names stay as they are."))
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

/// 11 · EXPORT MY DATA · ALL TIME.
///
/// ⚠️ 1ACT leaves the format and the audience open — "导什么、含不含原始读数、能不能给医生看
/// ——都没定。一旦把健康数据外发，合规口径要整个重过一遍，这不是一个按钮的工作量." So this
/// does the half that is decided: it assembles everything the account owns and shows what is
/// in it. Sending it anywhere is the undecided half, and a share sheet is exactly the "把健康
/// 数据外发" that line says not to build yet.
///
/// It used to route to the Terms of Service sheet, which is not a smaller version of this —
/// it is a different screen under the wrong title.
struct ExportSheet: View {
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var counts: [(String, Int)] = []
    @State private var failed = false

    var body: some View {
        SheetFrame(title: L("Export my data")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Everything this account holds, assembled here. It goes nowhere until you send it."))
                    .font(NBFont.brand(400, 14))
                    .lineSpacing(7)
                    .foregroundStyle(NB.text2)

                if failed {
                    Text(L("Could not reach the server. Nothing was exported."))
                        .font(NBFont.ui(400, 12)).tracking(0.02 * 12)
                        .foregroundStyle(NB.alert2)
                } else if counts.isEmpty {
                    Text(L("ASSEMBLING …"))
                        .font(NBFont.dot(500, 11)).tracking(0.16 * 11)
                        .foregroundStyle(NB.text3Prod)
                } else {
                    VStack(spacing: 0) {
                        ForEach(counts, id: \.0) { name, n in
                            HStack {
                                Text(name)
                                    .font(NBFont.ui(400, 13))
                                    .foregroundStyle(NB.text2)
                                Spacer(minLength: 0)
                                Text("\(n)")
                                    .font(NBFont.dot(700, 13)).tracking(0.04 * 13)
                                    .foregroundStyle(NB.text1)
                            }
                            .frame(height: 40)
                            .overlay(alignment: .bottom) { Hairline() }
                        }
                    }
                }
            }
        } footer: {
            Text(L("SENDING IT ON IS NOT IN THIS BUILD — THE COMPLIANCE ROUTE IS UNDECIDED"))
                .font(NBFont.dot(500, 9.5)).tracking(0.14 * 9.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.text3Prod)
        }
        .task {
            do {
                data.exportPreparing = true
                defer { data.exportPreparing = false }
                guard let owner = SupabaseClient.currentUserIdSnapshot() else { return }
                let row = try await SupabaseClient.shared.callFunction("export", payload: [:], expectedOwner: owner)
                guard let files = row["payload"] as? [String: String] else { throw SupabaseClient.Failure.http(502, "Export incomplete") }
                func rows(_ filename: String) -> Int { files[filename]?.split(separator: "\n").count ?? 0 }
                counts = [("Settled days", rows("daily_rollup.ndjson")),
                          ("Weigh-ins", rows("weigh_ins.ndjson")),
                          ("Body scans", rows("measurements.ndjson")),
                          ("Meals", rows("meals.ndjson"))]
                await Analytics.shared.track("EXPORT_ASSEMBLED",
                                             ["ROWS": counts.reduce(0) { $0 + $1.1 }])
            } catch {
                failed = true
            }
        }
    }
}

struct LegalSheet: View {
    let title: String
    let body_: String
    init(title: String, body: String) { self.title = title; self.body_ = body }

    var body: some View {
        SheetFrame(title: title) {
            ScrollView(showsIndicators: false) {
                Text(body_)
                    .font(NBFont.brand(400, 14))
                    .lineSpacing(8)
                    .foregroundStyle(NB.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                .foregroundStyle(NB.text1)
            content
            Spacer(minLength: 0)
            footer.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct FieldBox: View {
    let label: String
    @Binding var text: String
    var badge: String? = nil

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
