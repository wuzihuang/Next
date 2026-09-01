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

    var body: some View {
        ZStack {
            switch step {
            case .gate:  GateScreen(onEmail: { step = .email }, onApple: finish, onGoogle: finish)
            case .email: EmailScreen(email: $email, onBack: { step = .gate }, onSend: sendCode)
            case .code:  CodeScreen(email: email, code: $code, resendIn: $resendIn,
                                    verifying: verifying,
                                    onBack: { step = .email }, onVerify: verify)
            }

            if playingWordmark {
                WordmarkAnimation { finish() }
                    .transition(.opacity)
            }
        }
        .carbonPage()
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func sendCode() {
        step = .code
        resendIn = 60
    }

    /// The second the code checks out there is no toast and no tick — the pixels just fall.
    private func verify() {
        verifying = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            verifying = false
            withAnimation { playingWordmark = true }
        }
    }

    private func finish() {
        session.email = email
        session.isSignedIn = true
        session.stage = .gateConnect
    }
}

// MARK: 01 · 授权入口 Gate

private struct GateScreen: View {
    let onEmail: () -> Void
    let onApple: () -> Void
    let onGoogle: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            GateAurora().frame(width: 390, height: 520)

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
                    GateButton(style: .outline, action: onGoogle) {
                        GoogleGlyph(); Text("Continue with Google")
                            .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                            .foregroundStyle(NB.text1)
                    }
                    GateButton(style: .outline, action: onEmail) {
                        EnvelopeGlyph(); Text("Continue with email")
                            .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                            .foregroundStyle(NB.text1)
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
                // They are read before typing starts, so once the keyboard is up they give
                // their room to the button rather than fighting it for space.
                if keyboard.height == 0 {
                    VStack(spacing: 0) {
                        ReasonRow(lit: true, text: "A code signs you in — nothing to remember")
                            .overlay(alignment: .bottom) { Hairline() }
                        ReasonRow(lit: false, text: "Used only for sign-in and your weekly report")
                    }
                    .padding(.top, 22)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 38)

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Button(action: onSend) {
                    HStack(spacing: 10) {
                        Text("Send code")
                            .font(NBFont.ui(500, 15)).tracking(0.06 * 15)
                            .foregroundStyle(NB.carbon)
                        ArrowGlyph(color: NB.carbon)
                    }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(valid ? NB.lime1 : NB.carbon4, in: Capsule())
                    .overlay(valid ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
                    .opacity(valid ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!valid)

                Text("Use Apple or Google instead")
                    .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text3Prod)
                    .onTapGesture(perform: onBack)
            }
            .padding(.horizontal, 16)

            Color.clear.frame(height: 16)
        }
        // The keyboard takes the bottom of the screen; the layout above it does not move.
        .padding(.bottom, keyboard.height)
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
    let onBack: () -> Void
    let onVerify: () -> Void

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

            CodeBoxes(code: code)
                .padding(.horizontal, 24)
                .padding(.top, 40)

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
                HStack(spacing: 10) {
                    Text(verifying ? "Verifying…" : "Verify and continue")
                        .font(NBFont.ui(500, 15)).tracking(0.06 * 15)
                        .foregroundStyle(code.count == 6 ? NB.carbon : NB.white.opacity(0.38))
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(code.count == 6 ? NB.lime1 : NB.carbon4, in: Capsule())
                .overlay(code.count == 6 ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))

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
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                let chars = Array(code)
                let filled = i < chars.count
                let isCursor = i == chars.count
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isCursor ? NB.lime1.opacity(0.07) : (i > chars.count ? NB.carbon2 : NB.carbon4))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isCursor ? NB.lime1.opacity(0.70) : NB.hairline, lineWidth: isCursor ? 1.5 : 1)
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
