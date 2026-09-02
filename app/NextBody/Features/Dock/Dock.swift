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
    @Binding var draft: String
    var onSend: (String) -> Void
    var onCamera: () -> Void
    var onPlus: () -> Void
    /// 05 · the middle key's two edges. The dock does not own the microphone — it reports the
    /// press and lets the caller decide whether listening actually began.
    var onListen: () -> Void
    var onStopListening: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Left slot · switches input mode. It never does anything else.
            DockCircleButton(ringed: mode == .keyboard, action: {
                // 05M · A · OPEN 0.38S, DISMISS 0.24S — the board's own numbers, not a house spring.
                withAnimation(.spring(response: mode == .keyboard ? 0.24 : 0.38, dampingFraction: 0.82)) {
                    mode = (mode == .keyboard) ? .idle : .keyboard
                }
                focused = mode == .keyboard
            }) { KeyboardGlyph() }

            centre

            // Right slot · asks for an action. 06 · 01: it is a plus, not a camera —
            // the camera is only one of the five things behind it, and naming the entry
            // after one item hides the other four. Composing turns it into send.
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
                DockCircleButton(action: onPlus) { PlusGlyph() }
            }
        }
        .frame(width: NB.Layout.contentWidth, height: NB.Layout.dockHeight)
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
        case .idle:
            Button {
                // The mode change is the caller's to make: it flips to .listening only once the
                // microphone is actually running, so the wave never plays over a dead mic.
                onListen()
            } label: {
                ZStack {
                    Capsule().fill(NB.lime1)
                    DotMatrix()
                }
                .frame(height: NB.Layout.dockHeight)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PressDimStyle())
            .accessibilityLabel("说话")

        case .listening:
            Button { onStopListening() } label: {
                ZStack {
                    Capsule().fill(NB.lime1)
                    ListeningWave()
                }
                .frame(height: NB.Layout.dockHeight)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("正在听 · 点一下结束")

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
    let action: () -> Void
    @ViewBuilder let glyph: Glyph

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(NB.carbon4)
                Circle().stroke(ringed ? NB.lime1.opacity(0.6) : NB.hairline,
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

/// While listening the same matrix becomes a level meter: columns rise and fall,
/// the dots never move off their grid.
struct ListeningWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0
    private let cols = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                // F5 C11 · a level meter that does not move is still a level meter.
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let sx = size.width / 96, sy = size.height / 32
                let s = min(sx, sy)
                let ox = (size.width - 96 * s) / 2, oy = (size.height - 32 * s) / 2
                for col in 0..<cols {
                    let amp = 0.5 + 0.5 * sin(t * 6 + Double(col) * 0.55)
                    let lit = Int((amp * 2.4).rounded()) + 1        // 1…3 rows out from the middle
                    for row in 0..<5 {
                        let d = abs(row - 2)
                        let on = d <= lit
                        let x = ox + (3.2 + 6.4 * CGFloat(col)) * s
                        let y = oy + (3.2 + 6.4 * CGFloat(row)) * s
                        let r = 1.3 * s
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(.black.opacity(on ? 0.78 : 0.14)))
                    }
                }
            }
            .frame(width: 96, height: 32)
        }
        .allowsHitTesting(false)
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
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            var p = Path()
            p.move(to: CGPoint(x: 12 * s, y: 5 * s)); p.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
            p.move(to: CGPoint(x: 5 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 19 * s, y: 12 * s))
            ctx.stroke(p, with: .color(NB.iconInk),
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
