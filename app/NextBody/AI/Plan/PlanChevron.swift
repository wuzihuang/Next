import SwiftUI

/// Paper 04D MOTION · two 1.6pt round-cap chevrons that chase along one shared clock.
/// A second `repeatForever` on each stroke would drift; both marks read the same `t`.
struct PlanChevron: View, Equatable {
    var up = true
    var playing = false
    var flatten: CGFloat = 0
    var armed = false
    var reduceMotion = false

    var body: some View {
        TimelineView(.animation(minimumInterval: playing ? 1 / 30 : 120, paused: !playing)) { context in
            let t = playing
                ? context.date.timeIntervalSinceReferenceDate / PlanFaceMath.cycleSeconds
                : 0
            let phase = t - floor(t)
            marks(phase: phase)
        }
        .frame(width: 16 + 28 * flatten, height: 15)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func marks(phase: Double) -> some View {
        let width: CGFloat = armed ? 1.8 : 1.6
        if reduceMotion {
            restMark(width: width)
        } else if !playing {
            ZStack {
                restMark(width: 1.4).opacity(0.24).offset(y: up ? -3.2 : 3.2)
                restMark(width: width)
            }
            .opacity(1 - flatten)
            .overlay { flatBar.opacity(flatten) }
        } else {
            ZStack {
                chevron(kind: 0, phase: phase, width: width, faint: true)
                chevron(kind: 1, phase: phase, width: width, faint: false)
            }
            .opacity(1 - flatten)
            .overlay { flatBar.opacity(flatten) }
        }
    }

    private var flatBar: some View {
        Capsule()
            .fill(NB.lime1)
            .frame(width: 44, height: 2)
    }

    private func restMark(width: CGFloat) -> some View {
        PlanChevronMark(peak: 1 - flatten, down: !up)
            .stroke(NB.lime1, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .frame(width: 16 + 28 * flatten, height: max(2, 6.4 * (1 - flatten)))
    }

    private func chevron(kind: Int, phase: Double, width: CGFloat, faint: Bool) -> some View {
        let p = PlanFaceMath.phase(phase, offset: kind == 0 ? 0 : 0.5)
        let y = PlanFaceMath.offsetY(phase: p, up: up)
        let alpha = PlanFaceMath.alpha(phase: p)
        return PlanChevronMark(peak: 1, down: !up)
            .stroke(NB.lime1.opacity(faint ? 0.24 : 1),
                    style: StrokeStyle(lineWidth: faint ? 1.4 : width,
                                       lineCap: .round, lineJoin: .round))
            .frame(width: 16, height: 6.4)
            .offset(y: flatten > 0 ? 0 : y)
            .opacity(playing ? alpha : (faint ? 0.24 : 1))
    }
}

/// Paper SVG `M2.2 4.6 L8 0.9 L13.8 4.6` — peak interpolates to a flat bar when `peak` → 0.
private struct PlanChevronMark: Shape {
    var peak: CGFloat
    var down = false

    var animatableData: CGFloat {
        get { peak }
        set { peak = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rise = rect.height / 2 * peak * (down ? -1 : 1)
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rise))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - rise))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + rise))
        return path
    }
}
