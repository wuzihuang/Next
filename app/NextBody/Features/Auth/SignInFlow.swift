import SwiftUI

/// 01 · 登录注册 Sign In. Gate → Email → Code → brand animation.
/// The word "sign up" appears nowhere: the server decides new vs returning, not the user.
struct SignInFlow: View {
    @EnvironmentObject private var session: SessionStore

    enum Step: Hashable { case gate, email, code }
    @State private var step: Step = .gate
    @State private var email = ""
    @State private var code = ""
    @State private var resendIn = 60
    @State private var verifying = false
    @State private var playingWordmark = false
    /// 01 edges · 「出错的时候，不清屏」. The email and the digits are never cleared by an error.
    enum CodeError: Equatable { case wrong, locked, expired, rateLimited, noNetwork }
    @State private var codeError: CodeError?
    @State private var sending = false
    @State private var wrongCount = 0
    @State private var authFailed = false
    @State private var appleSignIn = AppleSignIn()
    /// 02M ◇5 · where the film hands the screen over: Connect, unless this account already
    /// has a band bound to it, in which case the gate is behind them and home is next.
    @State private var nextStage: SessionStore.Stage = .gateConnect

    var body: some View {
        ZStack {
            switch step {
            case .gate:  GateScreen(failed: authFailed, onEmail: { step = .email },
                                    onApple: { signInWithApple() }, onGoogle: { provider() })
            case .email: EmailScreen(email: $email, sending: sending, error: codeError,
                                     onBack: { step = .gate }, onSend: sendCode)
            case .code:  CodeScreen(email: email, code: $code, resendIn: $resendIn,
                                    verifying: verifying, error: codeError,
                                    onBack: { step = .email }, onVerify: verify,
                                    onNewCode: { codeError = nil; code = ""; sendCode() })
            }

            // ◇1 · 「不是渐亮，是通电」. No transition on purpose: the flash *is* the cut. Fading
            // the film in spent the whole 120ms peak at partial opacity, so the power-on
            // arrived as a glow while the haptic arrived at full strength — the two came
            // apart, and the light was the half that was late.
            if playingWordmark {
                WordmarkAnimation { finish() }
            }
        }
        .carbonPage()
    }

    /// Google is not wired yet: this is the placeholder that used to stand in for both
    /// providers, and it signs nothing in. Home then falls back to the demo account.
    private func provider() {
        if DebugEdge.on("authfail") { withAnimation { authFailed = true }; return }
        finish()
    }

    /// 01 edge 5 · cancelled on the system sheet is silent; only a token failure says anything,
    /// and then the email button moves up to second. The token goes to Supabase and the
    /// session that comes back is the one the whole app then reads — the same wordmark and
    /// the same `finish()` as the six-digit path, so the server decides new vs returning here too.
    private func signInWithApple() {
        if DebugEdge.on("authfail") { withAnimation { authFailed = true }; return }
        guard !verifying else { return }
        verifying = true
        Task {
            await Analytics.shared.track("AUTH_METHOD_TAP", ["METHOD": "APPLE"])
            do {
                let cred = try await appleSignIn.request()
                try await SupabaseClient.shared.signInWithApple(idToken: cred.idToken, nonce: cred.nonce)
                email = await SupabaseClient.shared.signedInEmail() ?? ""
                await adoptAppleName(cred.fullName)
                await authSucceeded()
                verifying = false
            } catch AppleSignIn.Failure.cancelled {
                verifying = false
            } catch {
                verifying = false
                withAnimation { authFailed = true }
            }
        }
    }

    /// The one moment this product is handed a real name. It arrives on the first Apple
    /// authorization and never again, so it goes to the server here rather than waiting for
    /// a screen to ask for it — nothing ever asks. A name the user has already set is not
    /// overwritten: Apple only offers this on a first authorization, but a reinstall after
    /// revoking would otherwise undo a rename.
    private func adoptAppleName(_ components: PersonNameComponents?) async {
        guard let components else { return }
        let f = PersonNameComponentsFormatter()
        f.style = .default
        let name = f.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, DataStore.shared.profile.name.isEmpty else { return }
        DataStore.shared.profile.name = name
        await Repository.shared.saveDisplayName(name)
    }

    private func sendCode() {
        codeError = nil
        // 01 edge 3 · five a hour per email; the sixth sends nothing and explains nothing more.
        let key = "nb.auth.sends.\(email.lowercased())"
        var sends = (UserDefaults.standard.array(forKey: key) as? [Double] ?? []).filter { Date().timeIntervalSince1970 - $0 < 3600 }
        if sends.count >= 5 || DebugEdge.on("ratelimited") { withAnimation { codeError = .rateLimited }; return }
        // 01 edge 4 · no network: the button turns to Sending in place, 8 s, then one line.
        if !Reachability.shared.isOnline || DebugEdge.on("nonetwork") {
            sending = true
            Task {
                try? await Task.sleep(for: .seconds(8))
                sending = false
                withAnimation { codeError = .noNetwork }
            }
            return
        }
        sends.append(Date().timeIntervalSince1970)
        UserDefaults.standard.set(sends, forKey: key)
        // The seeded demo account has no mailbox: it skips the mail and any six digits
        // open it (verify signs in with its password). Everyone else gets a real code.
        if Self.isDemo(email) {
            Task { await Analytics.shared.track("AUTH_CODE_SENT", [:]) }
            step = .code; resendIn = 60
            if DebugEdge.on("expired") { codeError = .expired }
            return
        }
        sending = true
        Task {
            do {
                try await SupabaseClient.shared.requestCode(email: email)
                sending = false
                await Analytics.shared.track("AUTH_CODE_SENT", [:])
                withAnimation { step = .code }
                resendIn = 60
                if DebugEdge.on("expired") { codeError = .expired }
            } catch SupabaseClient.Failure.http(let code, _) where code == 429 {
                sending = false
                withAnimation { codeError = .rateLimited }
            } catch {
                sending = false
                withAnimation { codeError = .noNetwork }
            }
        }
    }

    static func isDemo(_ email: String) -> Bool {
        email.lowercased().trimmingCharacters(in: .whitespaces) == "demo@nextbody.app"
    }

    /// 01 edge 1 · red outline, a 6 px shake, one haptic, then back to the first cell.
    /// The digits are cleared, the email is not.
    private func rejectCode() {
        wrongCount += 1
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        withAnimation { codeError = wrongCount >= 5 ? .locked : .wrong }
        Task {
            await Analytics.shared.track("AUTH_CODE_ERROR", ["REASON": wrongCount >= 5 ? "LOCKED" : "WRONG"])
            try? await Task.sleep(for: .milliseconds(420))
            code = ""
        }
    }

    /// The second the code checks out there is no toast and no tick — the pixels just fall.
    /// The code is checked against Supabase auth (`/auth/v1/verify`, type email); the demo
    /// account signs in with its password instead, since it has no mailbox.
    private func verify() {
        if DebugEdge.on("wrongcode") || codeError == .locked { rejectCode(); return }
        verifying = true
        Task {
            do {
                if Self.isDemo(email) {
                    try await SupabaseClient.shared.signIn(email: "demo@nextbody.app", password: "nextbody-demo")
                } else {
                    try await SupabaseClient.shared.verifyCode(email: email, token: code)
                }
                // The button stays in its verifying state across the one question the
                // returning path asks the server, so nothing sits dead on screen.
                await authSucceeded()
                verifying = false
            } catch SupabaseClient.Failure.http(let status, let body) {
                verifying = false
                // 01 edge 2 · a code past its ten minutes says so and offers a new one;
                // anything else the server refuses is a wrong code.
                if body.localizedCaseInsensitiveContains("expired") && !body.localizedCaseInsensitiveContains("invalid") {
                    withAnimation { codeError = .expired }
                } else if status == 429 {
                    withAnimation { codeError = .rateLimited }
                } else {
                    rejectCode()
                }
            } catch {
                verifying = false
                withAnimation { codeError = .noNetwork }
            }
        }
    }

    /// 02M · 「首次注册成功后」. The film is the reward for making an account, not a loader:
    /// it plays once, for the session the server itself calls new, and at most once in a day.
    /// Everyone else — a returning address, a second sign-in on a new phone — walks straight
    /// through to whichever screen is actually next for them.
    private func authSucceeded() async {
        let isNew = await SupabaseClient.shared.isNewUser
        await Analytics.shared.track("AUTH_SUCCESS", ["IS_NEW_USER": isNew])
        // A brand-new account cannot have a band yet, so it is never asked — the flash has
        // to land on the same beat as the last digit, not after a round trip.
        nextStage = (isNew ? false : await Self.hasBoundBand()) ? .root : .gateConnect
        if isNew, Self.claimFilmForToday() {
            playingWordmark = true
        } else {
            finish()
        }
    }

    /// 02M ◇5 · 「如果该账号已经有了配对的手环，就直接进入到主页」. A forgotten HOOP keeps its
    /// row and its `unbound_at`, so only a row still bound counts as paired.
    private static func hasBoundBand() async -> Bool {
        let rows = try? await SupabaseClient.shared.select("devices", query: [
            .init(name: "select", value: "id"),
            .init(name: "unbound_at", value: "is.null"),
            .init(name: "limit", value: "1"),
        ])
        return !(rows ?? []).isEmpty
    }

    /// 02M · 「不许倒放、不许循环、更不许当加载动画反复用——它一天最多出现一次」.
    private static func claimFilmForToday() -> Bool {
        let key = "nb.wordmark.playedOn"
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: key) != today else { return false }
        UserDefaults.standard.set(today, forKey: key)
        return true
    }

    private func finish() {
        session.email = email
        session.isSignedIn = true
        session.stage = nextStage
    }
}

// MARK: 01 · 授权入口 Gate

private struct GateScreen: View {
    var failed = false
    let onEmail: () -> Void
    let onApple: () -> Void
    let onGoogle: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            GateAurora().frame(width: NB.Layout.screenWidth, height: 520)

            VStack(spacing: 0) {
                Color.clear.frame(height: Chrome.gateTopInset)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 9) {
                        Text("NEXTBODY")
                            .font(NBFont.brand(800, 46)).tracking(-0.045 * 46)
                            .foregroundStyle(NB.text1)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(NB.lime1)
                            .frame(width: 9, height: 9)
                            .padding(.top, 6)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Build your next body.")
                            .font(NBFont.ui(300, 21)).tracking(0.02 * 21)
                            .foregroundStyle(NB.white.opacity(0.82))
                        Text("TRAIN · RECOVER · REPEAT")
                            .font(NBFont.dot(600, 11)).tracking(0.3 * 11)
                            .foregroundStyle(NB.white.opacity(0.62))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 246)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    GateButton(style: .solid, action: onApple) {
                        AppleGlyph(); Text("Continue with Apple")
                            .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                            .foregroundStyle(NB.carbon)
                    }
                    // 01 edge 5 · only a token that really failed says so, and then email moves
                    // up to second. A cancel on the system sheet is silent.
                    if failed {
                        GateButton(style: .outline, action: onEmail) {
                            EnvelopeGlyph(); Text("Continue with email")
                                .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                                .foregroundStyle(NB.text1)
                        }
                    }
                    GateButton(style: .outline, action: onGoogle) {
                        GoogleGlyph(); Text("Continue with Google")
                            .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                            .foregroundStyle(NB.text1)
                    }
                    if !failed {
                        GateButton(style: .outline, action: onEmail) {
                            EnvelopeGlyph(); Text("Continue with email")
                                .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                                .foregroundStyle(NB.text1)
                        }
                    }
                    if failed {
                        HStack(spacing: 10) {
                            Circle().fill(NB.alert2).frame(width: 6, height: 6)
                            Text("Sign-in failed. Try email instead.")
                                .font(NBFont.ui(400, 14)).tracking(0.01 * 14)
                                .foregroundStyle(NB.white.opacity(0.78))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)

                // Terms sit under the buttons: tapping one is the consent, there is no checkbox.
                LegalLine()
                    .padding(.horizontal, 40)
                    .padding(.top, 22)

                Color.clear.frame(height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The 4×4 LED field with one lime bloom behind the wordmark, fading into carbon by y520.
struct GateAurora: View {
    var body: some View {
        ZStack(alignment: .top) {
            Canvas { ctx, size in
                var p = Path()
                var y: CGFloat = 1
                while y < size.height {
                    var x: CGFloat = 1
                    while x < size.width {
                        p.addRoundedRect(in: CGRect(x: x, y: y, width: 3.2, height: 3.2),
                                         cornerSize: CGSize(width: 0.8, height: 0.8))
                        x += 4
                    }
                    y += 4
                }
                ctx.fill(p, with: .color(Color(hex: 0x15151B)))
            }

            Ellipse()
                .fill(RadialGradient(stops: [
                    .init(color: NB.lime1.opacity(0.16), location: 0),
                    .init(color: NB.lime1.opacity(0.05), location: 0.55),
                    .init(color: NB.lime1.opacity(0), location: 1),
                ], center: .center, startRadius: 0, endRadius: 230))
                .frame(width: 460, height: 360)
                .offset(x: 1, y: 188)

            VStack {
                Spacer(minLength: 0)
                LinearGradient(colors: [NB.carbon.opacity(0), NB.carbon.opacity(0.75), NB.carbon],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
        }
        .clipped()
    }
}

private struct GateButton<Content: View>: View {
    enum Style { case solid, outline }
    let style: Style
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(style == .solid ? NB.white : NB.carbon4, in: Capsule())
                .overlay(style == .outline ? Capsule().stroke(NB.hairline, lineWidth: 1) : nil)
        }
        .buttonStyle(.plain)
    }
}

private struct LegalLine: View {
    var body: some View {
        (Text("By continuing you agree to our ")
            .foregroundColor(NB.text3Prod)
         + Text("Terms").foregroundColor(NB.lime1)
         + Text(" and ").foregroundColor(NB.text3Prod)
         + Text("Privacy Policy").foregroundColor(NB.lime1))
            .font(NBFont.ui(400, 12.5))
            .tracking(0.02 * 12.5)
            .multilineTextAlignment(.center)
    }
}

// MARK: 02 · 邮箱 Email

private struct EmailScreen: View {
    @Binding var email: String
    var sending = false
    var error: SignInFlow.CodeError? = nil
    let onBack: () -> Void
    let onSend: () -> Void

    @FocusState private var focused: Bool
    @StateObject private var keyboard = KeyboardHeight()

    private var valid: Bool {
        let p = #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#
        return email.range(of: p, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Chrome.gateTopInset)
            StepBar(step: "STEP 01 / 02", onBack: onBack)

            VStack(alignment: .leading, spacing: 14) {
                Text("Your email")
                    .font(NBFont.ui(500, 32)).tracking(0.01 * 32)
                    .foregroundStyle(NB.text1)
                Text("We'll send a 6-digit code.\nNo password to set.")
                    .font(NBFont.ui(300, 15)).tracking(0.02 * 15)
                    .lineSpacing(24 - 15)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(NB.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 44)

            VStack(alignment: .leading, spacing: 10) {
                Text("EMAIL ADDRESS")
                    .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                    .foregroundStyle(NB.text3Prod)

                TextField("", text: $email)
                    .focused($focused)
                    .font(NBFont.ui(400, 17))
                    .tracking(0.01 * 17)
                    .foregroundStyle(NB.text1)
                    .tint(NB.lime1)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { if valid { onSend() } }
                    .padding(.horizontal, 20)
                    .frame(height: 62)
                    .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
                        .stroke(NB.lime1.opacity(0.42), lineWidth: 1))

                // Not selling points — an answer to "why should I give you my email".
                // 01 · 02 · the keyboard rises with the screen (board: 「键盘随屏起」), so the two
                // lines have to live above it or they are never read; the key under the
                // keyboard is `go`, and the lime button is what the keyboard's dismissal reveals.
                VStack(spacing: 0) {
                    ReasonRow(lit: true, text: "A code signs you in — nothing to remember")
                        .overlay(alignment: .bottom) { Hairline() }
                    ReasonRow(lit: false, text: "Used only for sign-in and your weekly report")
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.top, 38)

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                // 01 edge 3 · the sixth send in an hour: one sentence, nothing about the address.
                if error == .rateLimited {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle().fill(NB.caution2).frame(width: 6, height: 6)
                            Text("5 SENT · 1H WINDOW").font(NBFont.dot(600, 11)).tracking(0.24 * 11).foregroundStyle(NB.caution2)
                        }
                        Text("You've hit the limit. Try again in an hour.")
                            .font(NBFont.ui(400, 14.5)).tracking(0.01 * 14.5).foregroundStyle(NB.white.opacity(0.78))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                }
                Button(action: onSend) {
                    HStack(spacing: 10) {
                        if sending {
                            // 01 edge 4 · Sending, in place, 8 s; the address is not touched.
                            Circle().stroke(NB.carbon.opacity(0.55), lineWidth: 2).frame(width: 14, height: 14)
                                .overlay(Circle().trim(from: 0, to: 0.25).stroke(NB.carbon, lineWidth: 2).rotationEffect(.degrees(-90)))
                            Text("Sending")
                                .font(NBFont.ui(500, 15)).tracking(0.01 * 15)
                                .foregroundStyle(NB.carbon.opacity(0.6))
                        } else {
                        Text("Send code")
                            .font(NBFont.ui(500, 15)).tracking(0.06 * 15)
                            .foregroundStyle(NB.carbon)
                        ArrowGlyph(color: NB.carbon)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(valid ? NB.lime1.opacity(sending ? 0.28 : 1) : NB.carbon4, in: Capsule())
                    .overlay(valid ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
                    .opacity(valid ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!valid || sending)
                if error == .noNetwork {
                    Text("No connection. Your code wasn't sent.")
                        .font(NBFont.ui(400, 13.5)).tracking(0.01 * 13.5)
                        .foregroundStyle(NB.alert1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }

                Text("Use Apple or Google instead")
                    .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text3Prod)
                    .onTapGesture(perform: onBack)
            }
            .padding(.horizontal, 16)

            Color.clear.frame(height: 16)
        }
        // ⚠️ The page neither pads itself by the keyboard's height nor ignores the keyboard
        // inset — it did both at once, which is why "Your email" ended up under the status
        // bar clock with the step bar gone entirely. Padding by 309pt while the frame was
        // already 309pt shorter made the content overflow by twice the keyboard, and the
        // overflow came off the top. The two reason rows below give up their room instead,
        // which is what leaves the Spacer enough to sit the button just above the keys.
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: keyboard.height)
        .onAppear { focused = true }
    }
}

private struct ReasonRow: View {
    let lit: Bool
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(lit ? NB.lime1 : NB.white.opacity(0.22))
                .frame(width: 6, height: 6)
            Text(text)
                .font(NBFont.ui(300, 14)).tracking(0.02 * 14)
                .foregroundStyle(NB.text2)
            Spacer(minLength: 0)
        }
        .frame(height: 52)
    }
}

// MARK: 03 · 验证码 Code

private struct CodeScreen: View {
    let email: String
    @Binding var code: String
    @Binding var resendIn: Int
    let verifying: Bool
    var error: SignInFlow.CodeError? = nil
    let onBack: () -> Void
    let onVerify: () -> Void
    var onNewCode: () -> Void = {}
    @State private var shake: CGFloat = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Chrome.gateTopInset)
            StepBar(step: "STEP 02 / 02", onBack: onBack)

            VStack(alignment: .leading, spacing: 14) {
                Text("Enter the code")
                    .font(NBFont.ui(500, 32)).tracking(0.01 * 32)
                    .foregroundStyle(NB.text1)
                HStack(spacing: 0) {
                    Text("Sent to ")
                        .font(NBFont.ui(300, 15)).tracking(0.02 * 15)
                        .foregroundStyle(NB.text2)
                    Text(email)
                        .font(NBFont.ui(400, 15)).tracking(0.02 * 15)
                        .foregroundStyle(NB.lime1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 44)

            CodeBoxes(code: code, error: error == .wrong || error == .locked)
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .offset(x: shake)
                .onChange(of: error) { _, e in
                    guard e == .wrong || e == .locked else { return }
                    // 01 edge 1 · a 6 px horizontal shake, once.
                    withAnimation(.linear(duration: 0.06).repeatCount(5, autoreverses: true)) { shake = 6 }
                    Task { try? await Task.sleep(for: .milliseconds(320)); shake = 0 }
                }

            // 01 edges 1 / 2 · the line under the cells. Expired is not red — it is not an error.
            if let error {
                Text(error == .wrong ? "That code didn't work."
                     : error == .locked ? "Too many tries. Try again in 15:00."
                     : error == .expired ? "That code has expired." : "")
                    .font(NBFont.ui(error == .expired ? 300 : 400, error == .expired ? 13.5 : 14)).tracking(0.01 * 14)
                    .foregroundStyle(error == .expired ? NB.white.opacity(0.50) : NB.alert1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
            }

            HStack(spacing: 8) {
                Text("Didn't get it?")
                    .font(NBFont.ui(400, 13.5)).tracking(0.02 * 13.5)
                    .foregroundStyle(NB.text3Prod)
                if resendIn > 0 {
                    Text("Resend in")
                        .font(NBFont.ui(400, 13.5)).tracking(0.02 * 13.5)
                        .foregroundStyle(NB.white.opacity(0.34))
                    Text(String(format: "%02d:%02d", resendIn / 60, resendIn % 60))
                        .font(NBFont.dot(700, 13.5)).tracking(0.14 * 13.5)
                        .foregroundStyle(NB.lime1)
                } else {
                    Button("Resend") { resendIn = 60 }
                        .font(NBFont.ui(500, 13.5))
                        .foregroundStyle(NB.lime1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                // The button only reports state and catches the edge case — filling the
                // sixth box submits on its own.
                if error == .expired {
                    // 01 edge 2 · the primary becomes the one step that fixes it; the address stays.
                    Button(action: onNewCode) {
                        Text("Get a new code")
                            .font(NBFont.ui(500, 15)).tracking(0.01 * 15)
                            .foregroundStyle(NB.carbon)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(NB.lime1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                HStack(spacing: 10) {
                    Text(verifying ? "Verifying…" : "Verify and continue")
                        .font(NBFont.ui(500, 15)).tracking(0.06 * 15)
                        .foregroundStyle(code.count == 6 ? NB.carbon : NB.white.opacity(0.38))
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(code.count == 6 ? NB.lime1 : NB.carbon4, in: Capsule())
                .overlay(code.count == 6 ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
                }

                Text("Use a different email")
                    .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text3Prod)
                    .onTapGesture(perform: onBack)
            }
            .padding(.horizontal, 16)

            Keypad(
                onDigit: { d in
                    guard code.count < 6 else { return }
                    code.append(d)
                    if code.count == 6 { onVerify() }
                },
                onDelete: { if !code.isEmpty { code.removeLast() } })
                .padding(.horizontal, 6)
                .padding(.top, 26)

            Color.clear.frame(height: 16)
        }
        .onReceive(timer) { _ in if resendIn > 0 { resendIn -= 1 } }
    }
}

private struct CodeBoxes: View {
    let code: String
    var error = false
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                let chars = Array(code)
                let filled = i < chars.count
                let isCursor = i == chars.count
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(error ? NB.alert2.opacity(0.06) : isCursor ? NB.lime1.opacity(0.07) : (i > chars.count ? NB.carbon2 : NB.carbon4))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(error ? NB.alert2 : isCursor ? NB.lime1.opacity(0.70) : NB.hairline, lineWidth: error || isCursor ? 1.5 : 1)
                    if filled {
                        Text(String(chars[i]))
                            .font(NBFont.dot(800, 32)).tracking(0.02 * 32)
                            .foregroundStyle(NB.text1)
                    } else if isCursor {
                        BlinkingCaret(height: 26)
                    } else {
                        RoundedRectangle(cornerRadius: 1).fill(NB.white.opacity(0.18))
                            .frame(width: 8, height: 2)
                    }
                }
                .frame(width: 50, height: 64)
                if i < 5 { Spacer(minLength: 0) }
            }
        }
    }
}

struct BlinkingCaret: View {
    var height: CGFloat = 22
    @State private var on = true
    var body: some View {
        Rectangle().fill(NB.lime1)
            .frame(width: 2, height: height)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever()) { on = false }
            }
    }
}

private struct Keypad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { d in Key(label: d) { onDigit(d) } }
                }
            }
            HStack(spacing: 6) {
                Color.clear.frame(maxWidth: .infinity).frame(height: 46)
                Key(label: "0") { onDigit("0") }
                Button(action: onDelete) {
                    BackspaceGlyph()
                        .frame(maxWidth: .infinity).frame(height: 46)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct Key: View {
        let label: String
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                Text(label)
                    .font(NBFont.ui(400, 24)).tracking(0.01 * 24)
                    .foregroundStyle(NB.text1)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(NB.smokeKey, in: RoundedRectangle(cornerRadius: NB.R.key, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

struct StepBar: View {
    let step: String
    let onBack: () -> Void
    var body: some View {
        HStack {
            Button(action: onBack) {
                ZStack {
                    Circle().fill(NB.carbon4)
                    Circle().stroke(NB.hairline, lineWidth: 1)
                    ChevronGlyph()
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text(step)
                .font(NBFont.dot(600, 11)).tracking(0.3 * 11)
                .foregroundStyle(NB.text3Prod)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .frame(height: 46)
    }
}
