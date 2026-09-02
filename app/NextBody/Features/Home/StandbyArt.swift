import SwiftUI

/// 04 · 01 默认 — the standby illustration inside the panel.
/// Two lime arcs sharing one centre, a violet orbit, one lime pip, six dust specks.
/// All coordinates are the board's, in a 358 × 470 space.
struct StandbyArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0…1 — drives the long lime arc so it reads as a charge level, not a decoration.
    var charge: Double = 0.72
    var animate = true

    @State private var orbitPhase: Double = 0
    @State private var pipPulse = false

    private static let specks: [(CGFloat, CGFloat, Double)] = [
        (52, 84, 0.50), (300, 112, 0.35), (84, 300, 0.30),
        (286, 286, 0.50), (212, 70, 0.25), (40, 208, 0.35),
    ]

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / 358, sy = geo.size.height / 470
            let s = min(sx, sy)
            let c = CGPoint(x: 179 * sx, y: 196 * sy)

            ZStack {
                NB.panelWash

                ForEach(Array(Self.specks.enumerated()), id: \.offset) { _, sp in
                    Rectangle()
                        .fill(NB.white.opacity(sp.2))
                        .frame(width: 3 * s, height: 3 * s)
                        .position(x: sp.0 * sx + 1.5 * s, y: sp.1 * sy + 1.5 * s)
                }

                Circle()
                    .fill(NB.discInk)
                    .frame(width: 148 * s, height: 148 * s)
                    .position(c)

                // Outer lime arc — 180 of a 465 dash cycle ≈ 39% of the ring, opened at −55°.
                ArcStroke(fraction: 180.0 / 465.0, rotation: -55)
                    .stroke(NB.lime1, style: StrokeStyle(lineWidth: 7 * s))
                    .frame(width: 148 * s, height: 148 * s)
                    .position(c)

                // Inner ghost arc.
                ArcStroke(fraction: 120.0 / 377.0, rotation: -45)
                    .stroke(NB.lime1.opacity(0.28), style: StrokeStyle(lineWidth: 2 * s))
                    .frame(width: 120 * s, height: 120 * s)
                    .position(c)

                // Violet orbit — the only thing on the panel that moves while idle.
                Ellipse()
                    .stroke(NB.violet2.opacity(0.5), lineWidth: 3 * s)
                    .frame(width: 252 * s, height: 68 * s)
                    .rotationEffect(.degrees(-16))
                    .position(c)

                Circle()
                    .fill(NB.lime1)
                    .frame(width: 12 * s, height: 12 * s)
                    .position(x: 292 * sx, y: 164 * sy)
                    .opacity(pipPulse ? 1 : 0.55)
                    .scaleEffect(pipPulse ? 1 : 0.86)
            }
            .onAppear {
                guard animate else { return }
                // F5 C11 · decorative; holds its pose under Reduce Motion.
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    pipPulse = true
                }
            }
        }
    }
}

/// An arc opened at `rotation` degrees covering `fraction` of the circle, drawn clockwise.
struct ArcStroke: Shape {
    var fraction: Double
    var rotation: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: r,
                 startAngle: .degrees(rotation),
                 endAngle: .degrees(rotation + 360 * fraction),
                 clockwise: false)
        return p
    }
}
