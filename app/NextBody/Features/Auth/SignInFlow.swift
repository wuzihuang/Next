import SwiftUI
import UIKit

/// 01 · 登录注册 Sign In. Gate → Email → Code → brand animation.
/// The word "sign up" appears nowhere: the server decides new vs returning, not the user.
struct SignInFlow: View {
    @EnvironmentObject private var session: SessionStore

    enum Step: Hashable { case gate, email, code }
    @State private var step: Step = .gate
    @State private var email = ""
    @State private var code = ""
    @State private var resendIn = 60
    /// Which door is waiting on the server. One flag for all three, because it is the same
    /// wait behind each of them: nothing on the gate may look tappable while a sign-in is
    /// in flight, and the door the finger chose is the one that has to say so.
    enum Door: Hashable { case apple, google, email }
    @State private var busy: Door?
    /// Eight seconds in, the copy stops implying it is nearly there. The request is *not*
    /// abandoned: a token the server already granted would leave the account signed in
    /// behind a screen that claimed it failed. We keep waiting, we just stop pretending.
    @State private var slow = false
    @State private var slowTimer: Task<Void, Never>?
    /// The account facts, asked for exactly once and awaited by whichever arrives last —
    /// the film, or the code that started it.
    @State private var gateTask: Task<AccountGate, Never>?
    @State private var playingWordmark = false
    /// 01 edges · 「出错的时候，不清屏」. The email and the digits are never cleared by an error.
    enum CodeError: Equatable { case wrong, locked, expired, rateLimited, noNetwork }
    @State private var codeError: CodeError?
    @State private var sending = false
    @State private var authFailed = false
    @State private var appleSignIn = AppleSignIn()
    /// 02M ◇5 · where the film hands the screen over: Connect, unless this account already
    /// has a band bound to it, in which case the gate is behind them and home is next.
    @State private var nextStage: SessionStore.Stage = .gateConnect

    var body: some View {
        ZStack {
            switch step {
            case .gate:  GateScreen(failed: authFailed, busy: waitPreview ?? busy,
                                    slow: waitPreview != nil ? DebugEdge.on("slowauth") : slow, onEmail: {
                                    guard busy == nil else { return }
                                    Task { await Analytics.shared.track("AUTH_METHOD_TAP", ["METHOD": "EMAIL"]) }
                                    step = .email
                                },
                                    onApple: { signInWithApple() }, onGoogle: { signInWithGoogle() })
            case .email: EmailScreen(email: $email, sending: sending, error: codeError,
                                     onBack: {
                                         Task { await Analytics.shared.track("AUTH_DROP", ["STEP": "EMAIL"]) }
                                         step = .gate
                                     }, onSend: sendCode)
            case .code:  CodeScreen(email: email, code: $code, resendIn: $resendIn,
                                    verifying: busy == .email, slow: slow, error: codeError,
                                    onBack: {
                                        Task { await Analytics.shared.track("AUTH_DROP", ["STEP": "CODE"]) }
                                        step = .email
                                    }, onVerify: verify,
                                    onNewCode: { codeError = nil; code = ""; sendCode() })
            }

            // ◇1 · 「不是渐亮，是通电」. No transition on purpose: the flash *is* the cut. Fading
            // the film in spent the whole 120ms peak at partial opacity, so the power-on
            // arrived as a glow while the haptic arrived at full strength — the two came
            // apart, and the light was the half that was late.
            if playingWordmark {
                WordmarkAnimation { Task { await filmFinished() } }
            }
        }
        .carbonPage()
    }

    /// The same shape as Apple, one endpoint later: the account picker mints an identity
    /// token, Supabase turns it into the session the whole app reads, and the wordmark plays.
    /// Cancelling the picker is silent (01 edge 5); only a real token failure moves email up.
    private func signInWithGoogle() {
        if DebugEdge.on("authfail") { withAnimation { authFailed = true }; return }
        guard busy == nil else { return }
        beginWait(.google)
        Task {
            await Analytics.shared.track("AUTH_METHOD_TAP", ["METHOD": "GOOGLE"])
            do {
                let cred = try await GoogleAuth.request()
                try await SupabaseClient.shared.signInWithGoogle(idToken: cred.idToken, nonce: cred.nonce)
                email = await SupabaseClient.shared.signedInEmail() ?? ""
                await completeSignIn(offeredName: cred.fullName)
                endWait()
            } catch GoogleAuth.Failure.cancelled {
                endWait()
            } catch {
                endWait()
                withAnimation { authFailed = true }
            }
        }
    }

    /// 01 edge 5 · cancelled on the system sheet is silent; only a token failure says anything,
    /// and then the email button moves up to second. The token goes to Supabase and the
    /// session that comes back is the one the whole app then reads — the same wordmark and
    /// the same `finish()` as the six-digit path, so the server decides new vs returning here too.
    private func signInWithApple() {
        if DebugEdge.on("authfail") { withAnimation { authFailed = true }; return }
        guard busy == nil else { return }
        beginWait(.apple)
        Task {
            await Analytics.shared.track("AUTH_METHOD_TAP", ["METHOD": "APPLE"])
            do {
                let cred = try await appleSignIn.request()
                try await SupabaseClient.shared.signInWithApple(idToken: cred.idToken, nonce: cred.nonce)
                email = await SupabaseClient.shared.signedInEmail() ?? ""
                let f = PersonNameComponentsFormatter()
                f.style = .default
                await completeSignIn(offeredName: cred.fullName.map { f.string(from: $0) })
                endWait()
            } catch AppleSignIn.Failure.cancelled {
                endWait()
            } catch {
                endWait()
                withAnimation { authFailed = true }
            }
        }
    }

    /// The gate is inert for as long as the server takes, so the wait needs a place to
    /// live. It lives in the button that was pressed — the same in-place idiom the email
    /// screen uses for Sending — and never in a spinner floating over the brand.
    /// DEBUG · `NB_DEBUG_EDGE=waitauth` (and `slowauth` for the eight-second copy) pins the
    /// gate in its waiting state so the three doors can be read without a live slow network.
    private var waitPreview: Door? {
        #if DEBUG
        if DebugEdge.on("waitauth") || DebugEdge.on("slowauth") { return .google }
        #endif
        return nil
    }

    private func beginWait(_ door: Door) {
        busy = door
        slow = false
        slowTimer?.cancel()
        slowTimer = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, busy == door else { return }
            withAnimation { slow = true }
        }
    }

    private func endWait() {
        slowTimer?.cancel()
        slowTimer = nil
        busy = nil
        slow = false
    }

    /// The one tail all three doors share. Everything past the token is identical, so the
    /// latency is hidden the same way for each.
    ///
    /// ◇ The account is asked for once. `fetchAccountGate` already returns `display_name`,
    ///   which is the only thing the name-adoption rule needs, so the extra `loadProfile`
    ///   round trip this used to make is gone and the write is no longer waited on: four
    ///   serial requests between the sheet closing and the next screen became two.
    /// ◇ The film starts *before* the facts arrive, not after. A fresh registration is
    ///   knowable from the token itself (`isNewUser`), so 2.6 s of designed motion covers
    ///   the fetch instead of queueing behind it.
    private func completeSignIn(offeredName: String?) async {
        let gate = Task { await Repository.shared.fetchAccountGate() }
        gateTask = gate

        if await SupabaseClient.shared.isNewUser, Self.claimFilmForToday() {
            playingWordmark = true
        }

        let facts = await gate.value
        nextStage = facts.stage
        await Analytics.shared.track("AUTH_SUCCESS", ["IS_NEW_USER": facts.isFirstRun])
        adoptName(offeredName, existingOnServer: facts.displayName)
        // The film owns the hand-off when it is up; finishing here too would cut it short.
        if !playingWordmark { finish() }
    }

    /// The film ends on its own clock, which may be before or after the facts land. It
    /// waits on the same task rather than starting a second one.
    private func filmFinished() async {
        if let gate = gateTask { nextStage = await gate.value.stage }
        finish()
    }

    /// The one moment this product is handed a real name — Apple offers it on the first
    /// authorization and never again, Google offers it every time, and nothing in the
    /// product ever asks for it. A name already on the server wins: Apple re-offering it
    /// after a revoke must not undo a rename.
    ///
    /// The comparison is against the `display_name` the gate fetch already carried back,
    /// so this costs no request, and the write is not waited on — the next screen is
    /// entitled to appear before a name nobody is looking at has finished saving.
    private func adoptName(_ raw: String?, existingOnServer: String?) {
        guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
        guard (existingOnServer ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { return }
        DataStore.shared.profile.name = name
        Task { await Repository.shared.saveDisplayName(name) }
    }

    private func sendCode() {
        codeError = nil
        if AuthLock.isLocked(email) {
            withAnimation { codeError = .locked }
            step = .code
            return
        }
        // 01 edge 3 · five a hour per email; the sixth sends nothing and explains nothing more.
        let key = "nb.auth.sends.\(email.lowercased())"
        let sends = (UserDefaults.standard.array(forKey: key) as? [Double] ?? []).filter { Date().timeIntervalSince1970 - $0 < 3600 }
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
        // The seeded demo account has no mailbox: it skips the mail and any six digits
        // open it (verify signs in with its password). Everyone else gets a real code.
        if Self.isDemo(email) {
            recordSend(key: key, previous: sends)
            Task { await Analytics.shared.track("AUTH_CODE_SENT", [:]) }
            step = .code; resendIn = 60
            if DebugEdge.on("expired") { codeError = .expired }
            return
        }
        sending = true
        Task {
            do {
                try await SupabaseClient.shared.requestCode(email: email)
                recordSend(key: key, previous: sends)
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

    private func recordSend(key: String, previous: [Double]) {
        var sends = previous
        sends.append(Date().timeIntervalSince1970)
        UserDefaults.standard.set(sends, forKey: key)
    }

    static func isDemo(_ email: String) -> Bool {
        Band.allowsSeed && DemoAccount.matches(email)
    }

    /// 01 edge 1 · red outline, a 6 px shake, one haptic, then back to the first cell.
    /// The digits are cleared, the email is not.
    private func rejectCode() {
        Haptics.notification(.error)
        let locked = AuthLock.registerWrong(email)
        withAnimation { codeError = locked ? .locked : .wrong }
        Task {
            await Analytics.shared.track("AUTH_CODE_ERROR", ["REASON": locked ? "LOCKED" : "WRONG"])
            try? await Task.sleep(for: .milliseconds(420))
            code = ""
        }
    }

    /// The second the code checks out there is no toast and no tick — the pixels just fall.
    /// The code is checked against Supabase auth (`/auth/v1/verify`, type email); the demo
    /// account signs in with its password instead, since it has no mailbox.
    private func verify() {
        guard busy == nil else { return }
        if AuthLock.isLocked(email) {
            withAnimation { codeError = .locked }
            return
        }
        if DebugEdge.on("wrongcode") { rejectCode(); return }
        beginWait(.email)
        Task {
            do {
                if Self.isDemo(email) {
                    try await SupabaseClient.shared.signIn(email: DemoAccount.email, password: DemoAccount.password)
                } else {
                    try await SupabaseClient.shared.verifyCode(email: email, token: code)
                }
                AuthLock.clearWrongs(email)
                // The button stays in its verifying state across the one question the
                // returning path asks the server, so nothing sits dead on screen.
                await completeSignIn(offeredName: nil)
                endWait()
            } catch SupabaseClient.Failure.http(let status, let body) {
                endWait()
                // 01 edge 2 · a code past its ten minutes says so and offers a new one;
                // anything else the server refuses is a wrong code.
                if GateDecision.isExpiredCode(status: status, body: body) {
                    withAnimation { codeError = .expired }
                } else if status == 429 {
                    withAnimation { codeError = .rateLimited }
                } else {
                    rejectCode()
                }
            } catch {
                endWait()
                withAnimation { codeError = .noNetwork }
            }
        }
    }

    /// 02M · 「首次注册成功后」. The film is the reward for making an account, not a loader:
    /// it plays once, for the session the server itself calls new, and at most once in a day.
    /// Everyone else — a returning address, a second sign-in on a new phone — walks straight
    /// through to whichever screen is actually next for them.
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
    /// The door the finger chose, while the server is still thinking.
    var busy: SignInFlow.Door?
    var slow = false
    let onEmail: () -> Void
    let onApple: () -> Void
    let onGoogle: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // The aurora is the page's ground, not a panel on it: it has to reach the
            // physical top edge, or the status bar sits on a band of bare carbon while the
            // dot lattice starts 48pt lower. The overhang keeps the glow and the bottom
            // fade at the same absolute height they had before.
            GateAurora(overhang: Chrome.statusBarBlock)
                .frame(width: NB.Layout.screenWidth, height: 520 + Chrome.statusBarBlock)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                Color.clear.frame(height: Chrome.gateTopInset)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 9) {
                        Text(L("NEXTBODY"))
                            .font(NBFont.brand(800, 46)).tracking(-0.045 * 46)
                            .foregroundStyle(NB.text1)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(NB.lime1)
                            .frame(width: 9, height: 9)
                            .padding(.top, 6)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Build your next body."))
                            .font(NBFont.ui(300, 21)).tracking(0.02 * 21)
                            .foregroundStyle(NB.white.opacity(0.82))
                        Text(L("TRAIN · RECOVER · REPEAT"))
                            .font(NBFont.dot(600, 11)).tracking(0.3 * 11)
                            .foregroundStyle(NB.white.opacity(0.62))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 246)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    GateButton(style: .solid, dimmed: busy != nil && busy != .apple,
                               disabled: busy != nil, action: onApple) {
                        if busy == .apple {
                            GateSpinner(color: NB.carbon.opacity(0.55))
                            Text(L(slow ? "Still connecting" : "Signing in"))
                                .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                                .foregroundStyle(NB.carbon.opacity(0.6))
                        } else {
                            AppleGlyph(); Text(L("Continue with Apple"))
                                .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                                .foregroundStyle(NB.carbon)
                        }
                    }
                    // 01 edge 5 · only a token that really failed says so, and then email moves
                    // up to second. A cancel on the system sheet is silent.
                    if failed {
                        GateButton(style: .outline, dimmed: busy != nil, disabled: busy != nil, action: onEmail) {
                            EnvelopeGlyph(); Text(L("Continue with email"))
                                .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                                .foregroundStyle(NB.text1)
                        }
                    }
                    GateButton(style: .outline, dimmed: busy != nil && busy != .google,
                               disabled: busy != nil, action: onGoogle) {
                        if busy == .google {
                            GateSpinner(color: NB.text1.opacity(0.55))
                            Text(L(slow ? "Still connecting" : "Signing in"))
                                .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                                .foregroundStyle(NB.text1.opacity(0.7))
                        } else {
                            GoogleGlyph(); Text(L("Continue with Google"))
                                .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                                .foregroundStyle(NB.text1)
                        }
                    }
                    if !failed {
                        GateButton(style: .outline, dimmed: busy != nil, disabled: busy != nil, action: onEmail) {
                            EnvelopeGlyph(); Text(L("Continue with email"))
                                .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                                .foregroundStyle(NB.text1)
                        }
                    }
                    if failed {
                        HStack(spacing: 10) {
                            Circle().fill(NB.alert2).frame(width: 6, height: 6)
                            Text(L("Sign-in failed. Try email instead."))
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
        .onAppear { Task { await Analytics.shared.track("AUTH_GATE_VIEW", [:]) } }
    }
}

/// The 4×4 LED field with one lime bloom behind the wordmark, fading into carbon by y520.
struct GateAurora: View {
    /// How far above the safe area this draws. Everything positioned inside is pushed down
    /// by it, so growing the canvas upward moves nothing that was already placed.
    var overhang: CGFloat = 0

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
                .offset(x: 1, y: 188 + overhang)

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
    /// The two doors not being used step back rather than disappear — the choice is still
    /// legible, it is just not available for the next second.
    var dimmed = false
    var disabled = false
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(style == .solid ? NB.white : NB.carbon4, in: Capsule())
                .overlay(style == .outline ? Capsule().stroke(NB.hairline, lineWidth: 1) : nil)
                .opacity(dimmed ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.easeOut(duration: 0.18), value: dimmed)
    }
}

/// The one waiting mark on these screens: a quarter ring, 0.9 s a turn. A ring that does
/// not turn reads as a frozen screen, which is the exact thing the wait needs to deny.
private struct GateSpinner: View {
    var color: Color
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}

private struct LegalLine: View {
    var body: some View {
        (Text(L("By continuing you agree to our "))
            .foregroundColor(NB.text3Prod)
         + Text(L("Terms")).foregroundColor(NB.lime1)
         + Text(L(" and ")).foregroundColor(NB.text3Prod)
         + Text(L("Privacy Policy")).foregroundColor(NB.lime1))
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
                Text(L("Your email"))
                    .font(NBFont.ui(500, 32)).tracking(0.01 * 32)
                    .foregroundStyle(NB.text1)
                Text(L("We'll send a 6-digit code.\nNo password to set."))
                    .font(NBFont.ui(300, 15)).tracking(0.02 * 15)
                    .lineSpacing(24 - 15)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(NB.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 44)

            VStack(alignment: .leading, spacing: 10) {
                Text(L("EMAIL ADDRESS"))
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
                    ReasonRow(lit: true, text: L("A code signs you in — nothing to remember"))
                        .overlay(alignment: .bottom) { Hairline() }
                    ReasonRow(lit: false, text: L("Used only for sign-in and your weekly report"))
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
                            Text(L("5 SENT · 1H WINDOW")).font(NBFont.dot(600, 11)).tracking(0.24 * 11).foregroundStyle(NB.caution2)
                        }
                        Text(L("You've hit the limit. Try again in an hour."))
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
                            Text(L("Sending"))
                                .font(NBFont.ui(500, 15)).tracking(0.01 * 15)
                                .foregroundStyle(NB.carbon.opacity(0.6))
                        } else {
                        Text(L("Send code"))
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
                    Text(L("No connection. Your code wasn't sent."))
                        .font(NBFont.ui(400, 13.5)).tracking(0.01 * 13.5)
                        .foregroundStyle(NB.alert1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }

                Text(L("Use Apple or Google instead"))
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
    var slow = false
    var error: SignInFlow.CodeError? = nil
    let onBack: () -> Void
    let onVerify: () -> Void
    var onNewCode: () -> Void = {}
    @State private var shake: CGFloat = 0
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var lockLine: String {
        _ = now
        guard let left = AuthLock.remaining(email) else {
            return "Too many tries. Try again in 15:00."
        }
        let seconds = Int(left.rounded(.up))
        return String(format: "Too many tries. Try again in %02d:%02d.", seconds / 60, seconds % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Chrome.gateTopInset)
            StepBar(step: "STEP 02 / 02", onBack: onBack)

            VStack(alignment: .leading, spacing: 14) {
                Text(L("Enter the code"))
                    .font(NBFont.ui(500, 32)).tracking(0.01 * 32)
                    .foregroundStyle(NB.text1)
                HStack(spacing: 0) {
                    Text(L("Sent to "))
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
                .overlay {
                    OTPCaptureField(code: $code) { if code.count == 6 { onVerify() } }
                }
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
                     : error == .locked ? lockLine
                     : error == .expired ? "That code has expired." : "")
                    .font(NBFont.ui(error == .expired ? 300 : 400, error == .expired ? 13.5 : 14)).tracking(0.01 * 14)
                    .foregroundStyle(error == .expired ? NB.white.opacity(0.50) : NB.alert1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
            }

            HStack(spacing: 8) {
                Text(L("Didn't get it?"))
                    .font(NBFont.ui(400, 13.5)).tracking(0.02 * 13.5)
                    .foregroundStyle(NB.text3Prod)
                if resendIn > 0 {
                    Text(L("Resend in"))
                        .font(NBFont.ui(400, 13.5)).tracking(0.02 * 13.5)
                        .foregroundStyle(NB.white.opacity(0.34))
                    Text(String(format: "%02d:%02d", resendIn / 60, resendIn % 60))
                        .font(NBFont.dot(700, 13.5)).tracking(0.14 * 13.5)
                        .foregroundStyle(NB.lime1)
                } else {
                    Button("Resend") { onNewCode() }
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
                        Text(L("Get a new code"))
                            .font(NBFont.ui(500, 15)).tracking(0.01 * 15)
                            .foregroundStyle(NB.carbon)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(NB.lime1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                HStack(spacing: 10) {
                    if verifying { GateSpinner(color: NB.carbon.opacity(0.55)) }
                    Text(verifying ? L(slow ? "Still connecting" : "Verifying") : L("Verify and continue"))
                        .font(NBFont.ui(500, 15)).tracking(0.06 * 15)
                        .foregroundStyle(code.count == 6 ? NB.carbon : NB.white.opacity(0.38))
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(code.count == 6 ? NB.lime1 : NB.carbon4, in: Capsule())
                .overlay(code.count == 6 ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
                }

                Text(L("Use a different email"))
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
        .onReceive(timer) { _ in
            if resendIn > 0 { resendIn -= 1 }
            now = Date()
        }
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
                Key(label: L("0")) { onDigit("0") }
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

/// Hidden field so iOS can paste a six-digit code and offer the SMS autofill.
/// The custom keypad stays on screen: the system keyboard is replaced by an empty view.
private struct OTPCaptureField: UIViewRepresentable {
    @Binding var code: String
    var onFilled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(code: $code, onFilled: onFilled) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.inputView = UIView()
        field.tintColor = .clear
        field.textColor = .clear
        field.backgroundColor = .clear
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.code = $code
        context.coordinator.onFilled = onFilled
        if field.text != code { field.text = code }
        if !field.isFirstResponder { field.becomeFirstResponder() }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var code: Binding<String>
        var onFilled: () -> Void

        init(code: Binding<String>, onFilled: @escaping () -> Void) {
            self.code = code
            self.onFilled = onFilled
        }

        @objc func changed(_ field: UITextField) {
            let digits = String((field.text ?? "").filter(\.isNumber).prefix(6))
            field.text = digits
            if code.wrappedValue != digits { code.wrappedValue = digits }
            if digits.count == 6 { onFilled() }
        }
    }
}
