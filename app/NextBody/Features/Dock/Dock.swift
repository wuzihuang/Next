import SwiftUI

/// 05 · Dock 输入. Three slots, written in stone:
/// left switches input mode, centre is the input itself, right asks for an action.
/// Nothing else is ever added to this row.
struct Dock: View {
    enum Mode: Hashable { case idle, keyboard, listening, plus }

    @Binding var mode: Mode
    var placeholder: String = ""
    /// 05 edges · the centre capsule says what can be done now, in an amber outline; the three
    /// slots do not move, nothing pops, nothing toasts.
    var note: DockNote? = nil
    /// 05 rule 06 · with a photo attached the send key lights only at 100 % and ≥ 1 character.
    var attachmentReady: Bool? = nil
    /// the column the row fills; 358 on the board, the device's own width minus the gutters on a phone
    var width: CGFloat = NB.Layout.contentWidth
    @Binding var draft: String
    var onSend: (String) -> Void
    var onCamera: () -> Void
    var onPlus: () -> Void
    /// 06 · 02 · while the menu is open the plus is the close mark: turned 45°, lime, dark ink.
    var menuOpen = false
    /// 05 · the middle key's two edges. The dock does not own the microphone — it reports the
    /// press and lets the caller decide whether listening actually began.
    /// 05M · B · hold to talk. `onArm` fires when the 200 ms threshold is crossed (touch down →
    /// armed); `onRelease` sends; `onCancel` is the slide-up abort past −56 px. The mode flips to
    /// .listening only inside `onArm`, once the mic is actually up.
    var onListen: () -> Void
    var onStopListening: () -> Void
    var onCancelListening: () -> Void = {}
    var onKeyboardTap: (() -> Void)? = nil
    @State private var pressing = false
    @State private var armed = false
    @State private var cancelling = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Left slot · switches input mode or opens dedicated chat.
            DockCircleButton(ringed: mode == .keyboard, action: {
                if let onKeyboardTap {
                    onKeyboardTap()
                } else {
                    // 05M · A · OPEN 0.38S, DISMISS 0.24S — the board's own numbers, not a house spring.
                    withAnimation(.spring(response: mode == .keyboard ? 0.24 : 0.38, dampingFraction: 0.82)) {
                        mode = (mode == .keyboard) ? .idle : .keyboard
                    }
                    focused = mode == .keyboard
                }
            }) { KeyboardGlyph() }
            // 05M · B·03 · while the chamber owns the lane both side keys fade out and stop
            // taking hits; a recording has two gestures, and a third tappable thing is a leak.
            .opacity(mode == .listening ? 0 : 1)
            .allowsHitTesting(mode != .listening)

            centre

            // Right slot · asks for an action. At rest it is the camera, as boards 04 / 05
            // draw the row (keyboard · voice · camera); pressing it opens 06's sheet, where
            // the photo rows come first and the band measurements sit under them. While the
            // sheet is up the key is the close mark. Composing turns it into send.
            if mode == .keyboard {
                let armed = !draft.trimmingCharacters(in: .whitespaces).isEmpty && (attachmentReady ?? true)
                Button(action: send) {
                    ZStack {
                        Circle().fill(armed ? NB.lime1 : NB.carbon4)
                        if !armed { Circle().stroke(NB.hairline, lineWidth: 1) }
                        SendArrow(tint: armed ? NB.carbon : NB.white.opacity(0.3))
                    }
                    .frame(width: NB.Layout.dockSideButton, height: NB.Layout.dockSideButton)
                }
                .buttonStyle(.plain)
                .disabled(!armed)
                .transition(.scale.combined(with: .opacity))
            } else {
                DockCircleButton(filled: menuOpen, action: onPlus) {
                    ZStack {
                        // The key at rest is the orb, not a camera outline: it opens 06's
                        // sheet, where the photo rows are one option among the band's own.
                        // It fills the key edge to edge — under about 40 pt the two shells
                        // stop reading as shells and the ball is just texture.
                        OrbGlyph(side: NB.Layout.dockSideButton)
                            .opacity(menuOpen ? 0 : 1)
                            .scaleEffect(menuOpen ? 0.6 : 1)
                        PlusGlyph(tint: NB.carbon)
                            .rotationEffect(.degrees(45))
                            .opacity(menuOpen ? 1 : 0)
                            .scaleEffect(menuOpen ? 1 : 0.6)
                    }
                    .animation(.easeOut(duration: 0.14), value: menuOpen)
                }
                .accessibilityLabel(menuOpen ? "Close" : "Camera")
                .opacity(mode == .listening ? 0 : 1)
                .allowsHitTesting(mode != .listening)
            }
        }
        .frame(width: width, height: NB.Layout.dockHeight)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: draft.isEmpty)
    }

    @ViewBuilder private var centre: some View {
        if let note, mode == .idle {
            Button { onListen() } label: {
                ZStack {
                    Capsule().fill(NB.ember1.opacity(0.06))
                    Capsule().stroke(NB.ember1.opacity(0.36), lineWidth: 1)
                    Text(note.line)
                        .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.ember1.opacity(0.85))
                }
                .frame(height: NB.Layout.dockHeight)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.line)
        } else {
        switch mode {
        case .idle, .listening:
            // 05M · B · one continuous press: down → armed at 200 ms → recording → release sends,
            // slide up past −56 px cancels. Not a tap: the board's key has this one gesture, and
            // the edge copy ("Hold, say it, then let go" · slide to cancel) presupposes it.
            //
            // ⚠️ One view for the capsule and the chamber. The finger that started the gesture
            // is still down when the mode flips, and a gesture belongs to the view it was
            // attached to: swapping views here would end the press the moment listening began.
            // So the capsule itself grows — 56 → 138 tall, its slot → the whole lane — and only
            // the face inside it is exchanged.
            let listening = mode == .listening
            let cancel = listening && (cancelling || DebugEdge.on("cancelling"))
            ZStack {
                RoundedRectangle(cornerRadius: listening ? 30 : NB.Layout.dockHeight / 2, style: .continuous)
                    .fill(cancel ? Color(hex: 0x141418) : NB.lime1)
                if cancel {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(NB.alert2.opacity(0.52), lineWidth: 1.5)
                        .transition(.opacity)
                }
                if listening {
                    RecordingChamber(cancelling: cancel).transition(.opacity)
                } else {
                    DotMatrix().transition(.opacity)
                }
            }
            .frame(width: listening ? width : nil,
                   height: listening ? RecordingChamber.height : NB.Layout.dockHeight)
            .frame(maxWidth: .infinity)
            // ADR-0001 · the press is a UIKit recognizer (PressHold), not a SwiftUI drag: under
            // the page drag's `highPriorityGesture` a child gesture hears nothing until the
            // finger lifts, and this key has to arm 200 ms into the touch.
            .overlay(
                PressHold(
                    onTouch: { down in pressing = down },
                    // 05M · B·02 · the threshold is crossed → one haptic, mic up.
                    onArm: {
                        armed = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onListen()
                    },
                    // 05M · B·04 · slide up past −56 px arms the cancel; back down re-arms send.
                    onMove: { t in
                        let c = armed && t.height < -56
                        if c != cancelling {
                            cancelling = c
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    },
                    onLift: { interrupted in
                        let wasArmed = armed, wasCancelling = cancelling
                        pressing = false; armed = false; cancelling = false
                        guard wasArmed else { return }   // a slip under 200 ms: nothing began
                        if wasCancelling || interrupted { onCancelListening() } else { onStopListening() }
                    }
                )
            )
            // B·03 / B·04 · the cancel mark hangs 68 pt above the chamber's lip, on a dotted
            // line that says how far the finger has to travel.
            .overlay(alignment: .top) {
                if listening {
                    // the 112 pt drawing's top edge sits 108 pt above the lip: ring centre
                    // at −68, the dotted line from −42 down to −6, as the board places them
                    CancelMark(armed: cancel)
                        .offset(y: -108)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            // the chamber grows upward out of the 56 pt row; the row itself never moves
            .frame(height: NB.Layout.dockHeight, alignment: .bottom)
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .scaleEffect(pressing && !listening ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: pressing)
            .animation(.easeOut(duration: 0.16), value: cancel)
            .accessibilityLabel(listening ? (cancel ? "Release to cancel" : "Listening · release to send · slide up to cancel") : "Hold to talk")
            .accessibilityAddTraits(.startsMediaSession)

        case .keyboard, .plus:
            // The keyboard rises with the screen and the caret is already in the field —
            // the placeholder is the one thing that must never move (A·04).
            HStack(spacing: 8) {
                TextField("", text: $draft, prompt:
                    Text(placeholder.isEmpty ? "Ask about today" : placeholder)
                        .font(NBFont.ui(400, 14))
                        .foregroundColor(NB.text3Prod))
                    .focused($focused)
                    .font(NBFont.ui(400, 14))
                    .foregroundStyle(NB.text1)
                    .tint(NB.lime1)
                    .submitLabel(.send)
                    .onSubmit { send() }
                // 05 · C01 · the camera lives in the field, not the right slot: in keyboard mode the
                // right slot belongs to send. Tapping it only opens the picker; nothing moves.
                Button(action: onCamera) { CameraGlyph() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a photo")
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .frame(height: NB.Layout.dockHeight)
            .frame(maxWidth: .infinity)
            .background(NB.carbon4, in: Capsule())
            .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
            .onAppear { focused = true }
        }
        }
    }

    private func send() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        onSend(t)
        // 05M · A · SEND 0.22S.
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { mode = .idle }
        focused = false
    }
}

struct DockCircleButton<Glyph: View>: View {
    var ringed = false
    var filled = false
    let action: () -> Void
    @ViewBuilder let glyph: Glyph

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(filled ? NB.lime1 : NB.carbon4)
                    .animation(.easeOut(duration: 0.14), value: filled)
                Circle().stroke(ringed ? NB.lime1.opacity(0.6) : filled ? Color.clear : NB.hairline,
                                lineWidth: ringed ? 1.5 : 1)
                glyph
            }
            .frame(width: NB.Layout.dockSideButton, height: NB.Layout.dockSideButton)
        }
        .buttonStyle(.plain)
    }
}

/// A·02 · pressing the lime key dims it to 60% at 90ms and the left key takes a lime ring.
/// One haptic tick, never two — two would read as an arm signal.
private struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.28 : 0)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

struct SendArrow: View {
    var tint: Color = NB.carbon
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            var p = Path()
            p.move(to: CGPoint(x: 12 * s, y: 19 * s)); p.addLine(to: CGPoint(x: 12 * s, y: 5 * s))
            p.move(to: CGPoint(x: 6 * s, y: 11 * s)); p.addLine(to: CGPoint(x: 12 * s, y: 5 * s))
            p.addLine(to: CGPoint(x: 18 * s, y: 11 * s))
            ctx.stroke(p, with: .color(tint),
                       style: StrokeStyle(lineWidth: 1.9 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 20, height: 20)
    }
}

/// The lime key's face: 14 × 5 dots on a 6.4 pitch, edges faded so the pill reads as printed.
struct DotMatrix: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 96, sy = size.height / 32
            let s = min(sx, sy)
            let ox = (size.width - 96 * s) / 2, oy = (size.height - 32 * s) / 2
            for row in 0..<5 {
                for col in 0..<14 {
                    let alpha = Self.alpha(row: row, col: col)
                    let x = ox + (3.2 + 6.4 * CGFloat(col)) * s
                    let y = oy + (3.2 + 6.4 * CGFloat(row)) * s
                    let r = 1.3 * s
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.black.opacity(0.78 * alpha)))
                }
            }
        }
        .frame(width: 96, height: 32)
        .allowsHitTesting(false)
    }

    static func alpha(row: Int, col: Int) -> Double {
        if row == 0 || row == 4 {
            switch col { case 0, 13: return 0.25; case 1, 12: return 0.55; default: return 1 }
        }
        switch col { case 0: return 0.55; case 12: return 0.85; case 13: return 0.40; default: return 1 }
    }
}

/// 05M · B·03 · the chamber. 358 × 138, radius 30, padding 18 / 22 / 16: a status line with the
/// timer, the level history as 34 bars, and the one instruction at the foot. B·04 turns the same
/// box carbon behind a red hairline, freezes the bars and changes both lines — nothing moves.
struct RecordingChamber: View {
    static let height: CGFloat = 138
    var cancelling: Bool
    @ObservedObject private var mic = SpeechCapture.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(cancelling ? NB.alert2 : NB.carbon).frame(width: 7, height: 7)
                    Text(cancelling ? "RELEASE TO CANCEL" : "RECORDING")
                        .font(NBFont.dot(600, 10)).tracking(0.28 * 10)
                        .foregroundStyle(cancelling ? NB.alert1 : NB.carbon.opacity(0.66))
                }
                Spacer(minLength: 0)
                // B·04 · the timer keeps running while the cancel is armed; the take is still alive.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Self.clock(mic.elapsed))
                        .font(NBFont.dot(600, 16)).tracking(0.06 * 16)
                        .foregroundStyle(cancelling ? NB.white.opacity(0.30) : NB.carbon)
                }
            }
            .frame(height: 20)
            Spacer(minLength: 0)
            LevelBars(levels: Self.debugLevels ?? mic.levels, frozen: cancelling)
                .frame(height: 52)
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                if !cancelling {
                    Triangle().fill(NB.carbon.opacity(0.46)).frame(width: 9, height: 7)
                }
                Text(cancelling ? "SLIDE BACK DOWN TO KEEP" : "SLIDE UP TO CANCEL")
                    .font(NBFont.dot(600, 10)).tracking(0.26 * 10)
                    .foregroundStyle(cancelling ? NB.white.opacity(0.30) : NB.carbon.opacity(0.50))
            }
            .frame(height: 12)
        }
        .padding(.top, 18)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .frame(width: NB.Layout.contentWidth, height: Self.height)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// DEBUG · `NB_DEBUG_EDGE=recording` / `cancelling` on a simulator with no microphone:
    /// the board's own 34 bars, so the chamber can be checked against B·03 pixel for pixel.
    private static var debugLevels: [Double]? {
        guard DebugEdge.on("recording") || DebugEdge.on("cancelling") else { return nil }
        let h: [Double] = [6, 10, 16, 26, 38, 30, 20, 12, 18, 28, 44, 52, 40, 24, 14, 10, 16, 24,
                           34, 46, 36, 22, 12, 8, 14, 22, 32, 42, 30, 18, 10, 14, 20, 10]
        return h.map { ($0 - 6) / 46 }
    }
}

/// The waveform: 34 bars 3 pt wide on a 9.3 pt pitch, 6 → 52 pt tall, rounded 1.5. Newest
/// level on the right at full ink, the history fading to 40 % on the left. B·04 freezes the
/// last picture and greys it to 17 % white — the bars are a record, not a decoration.
struct LevelBars: View {
    var levels: [Double]
    var frozen: Bool
    @State private var snapshot: [Double] = []

    var body: some View {
        let shown = frozen && !snapshot.isEmpty ? snapshot : levels
        Canvas { ctx, size in
            let n = shown.count
            let pitch: CGFloat = 9.3
            let x0 = (size.width - (pitch * CGFloat(n - 1) + 3)) / 2
            for (i, level) in shown.enumerated() {
                let h = 6 + CGFloat(max(0, min(1, level))) * 46
                let rect = CGRect(x: x0 + pitch * CGFloat(i), y: (size.height - h) / 2, width: 3, height: h)
                let alpha = frozen ? 0.17 : min(1, 0.4 + 0.6 * Double(i) / 23)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                         with: .color((frozen ? NB.white : NB.carbon).opacity(alpha)))
            }
        }
        .onChange(of: frozen) { _, f in snapshot = f ? levels : [] }
        .allowsHitTesting(false)
    }
}

/// B·03 · the ring the finger is sliding toward: a 44 pt circle with an ×, and a dotted 36 pt
/// line down to the chamber. B·04 · past −56 px it goes red and the × turns pale.
struct CancelMark: View {
    var armed: Bool
    var body: some View {
        Canvas { ctx, size in
            // the board's 112 × 112 drawing, unscaled
            let circle = Path(ellipseIn: CGRect(x: 56 - 22.5, y: 40 - 22.5, width: 45, height: 45))
            ctx.fill(circle, with: .color(armed ? NB.alert2.opacity(0.12) : NB.carbon.opacity(0.86)))
            ctx.stroke(circle, with: .color(armed ? NB.alert2.opacity(0.62) : NB.white.opacity(0.30)),
                       lineWidth: armed ? 1.5 : 1.4)
            var x = Path()
            let r: CGFloat = armed ? 7 : 6.5
            x.move(to: CGPoint(x: 56 - r, y: 40 - r)); x.addLine(to: CGPoint(x: 56 + r, y: 40 + r))
            x.move(to: CGPoint(x: 56 + r, y: 40 - r)); x.addLine(to: CGPoint(x: 56 - r, y: 40 + r))
            ctx.stroke(x, with: .color(armed ? NB.alert1 : NB.white.opacity(0.62)),
                       style: StrokeStyle(lineWidth: armed ? 1.8 : 1.7, lineCap: .round))
            var line = Path()
            line.move(to: CGPoint(x: 56, y: 66)); line.addLine(to: CGPoint(x: 56, y: 104))
            ctx.stroke(line, with: .color(armed ? NB.alert2.opacity(0.48) : NB.white.opacity(0.22)),
                       style: StrokeStyle(lineWidth: armed ? 1.6 : 1.5, lineCap: .round, dash: [3, 7]))
        }
        .frame(width: 112, height: 112)
        .animation(.easeOut(duration: 0.16), value: armed)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// B·03 · behind the chamber: the page at 52 % and a 220 pt carbon gradient rising from the
/// dock — the board's two rectangles, drawn once.
struct ListeningScrim: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x09090B).opacity(0.52)
            LinearGradient(stops: [
                .init(color: NB.carbon.opacity(0), location: 0),
                .init(color: NB.carbon.opacity(0.74), location: 0.5),
                .init(color: NB.carbon.opacity(0.96), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 220)
        }
        .ignoresSafeArea()
    }
}

struct KeyboardGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            let ink = GraphicsContext.Shading.color(NB.iconInk)
            ctx.stroke(Path(roundedRect: CGRect(x: 2.5 * s, y: 5.5 * s, width: 19 * s, height: 13 * s),
                            cornerRadius: 3 * s), with: ink, lineWidth: 1.6 * s)
            for x in [5.6, 9.1, 12.6, 16.1] {
                ctx.fill(Path(roundedRect: CGRect(x: x * s, y: 9 * s, width: 1.8 * s, height: 1.8 * s),
                              cornerRadius: 0.4 * s), with: ink)
            }
            for x in [5.6, 16.1] {
                ctx.fill(Path(roundedRect: CGRect(x: x * s, y: 12.4 * s, width: 1.8 * s, height: 1.8 * s),
                              cornerRadius: 0.4 * s), with: ink)
            }
            ctx.fill(Path(roundedRect: CGRect(x: 8 * s, y: 15.8 * s, width: 8 * s, height: 1.6 * s),
                          cornerRadius: 0.8 * s), with: ink)
        }
        .frame(width: 22, height: 22)
    }
}

struct CameraGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            let ink = GraphicsContext.Shading.color(NB.iconInk)
            let stroke = StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, lineJoin: .round)
            ctx.stroke(Path(roundedRect: CGRect(x: 3 * s, y: 7.5 * s, width: 18 * s, height: 12 * s),
                            cornerRadius: 3 * s), with: ink, style: stroke)
            var lid = Path()
            lid.move(to: CGPoint(x: 9 * s, y: 7.5 * s))
            lid.addLine(to: CGPoint(x: 10.3 * s, y: 5 * s))
            lid.addLine(to: CGPoint(x: 13.7 * s, y: 5 * s))
            lid.addLine(to: CGPoint(x: 15 * s, y: 7.5 * s))
            ctx.stroke(lid, with: ink, style: stroke)
            ctx.stroke(Path(ellipseIn: CGRect(x: 8.8 * s, y: 10.3 * s, width: 6.4 * s, height: 6.4 * s)),
                       with: ink, style: stroke)
        }
        .frame(width: 22, height: 22)
    }
}

struct PlusGlyph: View {
    var tint: Color = NB.iconInk
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            var p = Path()
            p.move(to: CGPoint(x: 12 * s, y: 5 * s)); p.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
            p.move(to: CGPoint(x: 5 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 19 * s, y: 12 * s))
            ctx.stroke(p, with: .color(tint),
                       style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
        }
        .frame(width: 22, height: 22)
    }
}


/// 05 edges 1–6 · one amber line on the capsule, one sentence under the dock, at most one key.
struct DockNote: Equatable {
    let line: String
    let text: String
    var action: String? = nil
    static func == (a: DockNote, b: DockNote) -> Bool { a.line == b.line }
}
