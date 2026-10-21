import SwiftUI

/// Halftone planet used on the home screen. One canvas, no per-frame rebuild.
struct DottedSphere: View {
    var tint: Color
    var pitch: CGFloat = 3.4

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            guard radius > 2 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var y = center.y - radius
            while y <= center.y + radius {
                var x = center.x - radius
                while x <= center.x + radius {
                    let dx = (x - center.x) / radius
                    let dy = (y - center.y) / radius
                    let flat = dx * dx + dy * dy
                    if flat <= 1 {
                        let z = sqrt(1 - flat)
                        let light = max(0.08, 0.12 + 0.9 * (-0.25 * dx - 0.35 * dy + 0.75 * z))
                        let dot = CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4)
                        context.fill(Path(ellipseIn: dot), with: .color(tint.opacity(Double(light))))
                    }
                    x += pitch
                }
                y += pitch
            }
        }
        .accessibilityHidden(true)
    }
}

/// Standing figure. The four glows are state, not buttons — the hit targets sit above this.
struct BodyFigure: View {
    var head: Double
    var heart: Double
    var gut: Double
    var legs: Double

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            func glow(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ amount: Double, _ color: Color) {
                guard amount > 0.05 else { return }
                let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.22 * amount)))
                context.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.45, dy: r * 0.45)),
                             with: .color(color.opacity(0.55 * amount)))
            }
            glow(w * 0.50, h * 0.11, w * 0.16, head, Color(hex: 0xF6C56A))
            glow(w * 0.55, h * 0.30, w * 0.14, heart, NB.lime1)
            glow(w * 0.50, h * 0.46, w * 0.16, gut, Color(hex: 0xE25B4A))
            glow(w * 0.46, h * 0.74, w * 0.16, legs, NB.cyan1)

            var dots: [CGPoint] = []
            func ring(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ count: Int) {
                for i in 0..<count {
                    let t = Double(i) / Double(count) * .pi * 2
                    dots.append(CGPoint(x: cx + CGFloat(cos(t)) * rx, y: cy + CGFloat(sin(t)) * ry))
                }
            }
            func limb(_ a: CGPoint, _ b: CGPoint, _ count: Int) {
                for i in 0...count {
                    let t = CGFloat(i) / CGFloat(count)
                    dots.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            ring(w * 0.50, h * 0.11, w * 0.09, h * 0.055, 28)
            ring(w * 0.50, h * 0.36, w * 0.16, h * 0.13, 42)
            ring(w * 0.50, h * 0.56, w * 0.11, h * 0.07, 24)
            limb(CGPoint(x: w * 0.36, y: h * 0.28), CGPoint(x: w * 0.18, y: h * 0.48), 14)
            limb(CGPoint(x: w * 0.64, y: h * 0.28), CGPoint(x: w * 0.82, y: h * 0.48), 14)
            limb(CGPoint(x: w * 0.42, y: h * 0.62), CGPoint(x: w * 0.36, y: h * 0.92), 18)
            limb(CGPoint(x: w * 0.58, y: h * 0.62), CGPoint(x: w * 0.64, y: h * 0.92), 18)
            for dot in dots {
                let rect = CGRect(x: dot.x - 1.1, y: dot.y - 1.1, width: 2.2, height: 2.2)
                context.fill(Path(ellipseIn: rect), with: .color(NB.white.opacity(0.82)))
            }
        }
        .accessibilityHidden(true)
    }
}

struct HomeMacroTrack: View {
    var eaten: Int?
    var target: Int?
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction: CGFloat = {
                guard let eaten, let target, target > 0 else { return 0 }
                return min(1, CGFloat(eaten) / CGFloat(target))
            }()
            ZStack(alignment: .leading) {
                Capsule().fill(NB.barTrack)
                Capsule().fill(tint).frame(width: max(0, width * fraction))
            }
        }
        .frame(height: 3)
    }
}

struct HomePageDots: View {
    /// 0 is the body, 1 the planet, 2 the instruments. Follows the finger.
    var progress: CGFloat
    var onSelect: (Int) -> Void

    private let slot: CGFloat = 18
    private let gap: CGFloat = 8

    var body: some View {
        let place = min(2, max(0, progress))
        ZStack {
            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: slot, height: 4)
                    }
                }
                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: slot, height: 4)
                    .offset(x: place * (slot + gap))
            }
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    Button {
                        onSelect(index)
                    } label: {
                        Color.clear
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Page %d of 3", index + 1))
                }
            }
        }
        .frame(height: 36)
    }
}

extension HomeV2Model.BodyMetric.Tint {
    var color: Color {
        switch self {
        case .lime: NB.lime1
        case .violet: NB.violet1
        case .ember: NB.ember1
        case .cyan: NB.cyan1
        case .white: NB.white
        }
    }
}

extension HomeV2Model.BodyStatus {
    /// The map's five-stop ramp, green to red, so「还行」does not wear「糟糕」's amber.
    var color: Color {
        switch self {
        case .dim: NB.white
        case .good: NB.optimal2
        case .ok: NB.lime2
        case .watch: NB.filmYellow
        case .poor: NB.run1
        case .bad: NB.alert2
        }
    }
}
