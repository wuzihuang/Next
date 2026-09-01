import SwiftUI

struct AppleGlyph: View {
    var color: Color = NB.carbon
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            var p = Path()
            p.move(to: CGPoint(x: 17.05 * s, y: 12.54 * s))
            p.addCurve(to: CGPoint(x: 19.0 * s, y: 9.10 * s),
                       control1: CGPoint(x: 17.03 * s, y: 10.25 * s), control2: CGPoint(x: 18.92 * s, y: 9.15 * s))
            p.addCurve(to: CGPoint(x: 15.70 * s, y: 7.31 * s),
                       control1: CGPoint(x: 17.94 * s, y: 7.55 * s), control2: CGPoint(x: 16.29 * s, y: 7.33 * s))
            p.addCurve(to: CGPoint(x: 12.25 * s, y: 8.14 * s),
                       control1: CGPoint(x: 14.30 * s, y: 7.17 * s), control2: CGPoint(x: 12.96 * s, y: 8.14 * s))
            p.addCurve(to: CGPoint(x: 9.27 * s, y: 7.35 * s),
                       control1: CGPoint(x: 11.54 * s, y: 8.14 * s), control2: CGPoint(x: 10.44 * s, y: 7.33 * s))
            p.addCurve(to: CGPoint(x: 5.54 * s, y: 9.61 * s),
                       control1: CGPoint(x: 7.74 * s, y: 7.37 * s), control2: CGPoint(x: 6.33 * s, y: 8.24 * s))
            p.addCurve(to: CGPoint(x: 6.68 * s, y: 18.69 * s),
                       control1: CGPoint(x: 3.95 * s, y: 12.37 * s), control2: CGPoint(x: 5.13 * s, y: 16.45 * s))
            p.addCurve(to: CGPoint(x: 9.53 * s, y: 20.97 * s),
                       control1: CGPoint(x: 7.44 * s, y: 19.79 * s), control2: CGPoint(x: 8.34 * s, y: 21.02 * s))
            p.addCurve(to: CGPoint(x: 12.48 * s, y: 20.23 * s),
                       control1: CGPoint(x: 10.67 * s, y: 20.92 * s), control2: CGPoint(x: 11.10 * s, y: 20.23 * s))
            p.addCurve(to: CGPoint(x: 15.46 * s, y: 20.95 * s),
                       control1: CGPoint(x: 13.86 * s, y: 20.23 * s), control2: CGPoint(x: 14.25 * s, y: 20.97 * s))
            p.addCurve(to: CGPoint(x: 18.22 * s, y: 18.73 * s),
                       control1: CGPoint(x: 16.69 * s, y: 20.93 * s), control2: CGPoint(x: 17.47 * s, y: 19.83 * s))
            p.addCurve(to: CGPoint(x: 19.47 * s, y: 16.16 * s),
                       control1: CGPoint(x: 19.09 * s, y: 17.46 * s), control2: CGPoint(x: 19.45 * s, y: 16.23 * s))
            p.addCurve(to: CGPoint(x: 17.05 * s, y: 12.54 * s),
                       control1: CGPoint(x: 19.44 * s, y: 16.15 * s), control2: CGPoint(x: 17.07 * s, y: 15.24 * s))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))

            var leaf = Path()
            leaf.move(to: CGPoint(x: 14.79 * s, y: 5.60 * s))
            leaf.addCurve(to: CGPoint(x: 15.73 * s, y: 2.72 * s),
                          control1: CGPoint(x: 15.42 * s, y: 4.84 * s), control2: CGPoint(x: 15.84 * s, y: 3.78 * s))
            leaf.addCurve(to: CGPoint(x: 13.07 * s, y: 4.08 * s),
                          control1: CGPoint(x: 14.82 * s, y: 2.76 * s), control2: CGPoint(x: 13.72 * s, y: 3.32 * s))
            leaf.addCurve(to: CGPoint(x: 12.12 * s, y: 6.86 * s),
                          control1: CGPoint(x: 12.49 * s, y: 4.75 * s), control2: CGPoint(x: 11.98 * s, y: 5.83 * s))
            leaf.addCurve(to: CGPoint(x: 14.79 * s, y: 5.60 * s),
                          control1: CGPoint(x: 13.13 * s, y: 6.94 * s), control2: CGPoint(x: 14.16 * s, y: 6.35 * s))
            leaf.closeSubpath()
            ctx.fill(leaf, with: .color(color))
        }
        .frame(width: 19, height: 19)
    }
}

struct GoogleGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            func fill(_ build: (inout Path) -> Void, _ c: Color) {
                var p = Path(); build(&p); ctx.fill(p, with: .color(c))
            }
            // blue
            fill({ p in
                p.move(to: CGPoint(x: 22.56 * s, y: 12.25 * s))
                p.addLine(to: CGPoint(x: 22.36 * s, y: 10.00 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 10.00 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 14.26 * s))
                p.addLine(to: CGPoint(x: 17.92 * s, y: 14.26 * s))
                p.addCurve(to: CGPoint(x: 15.72 * s, y: 17.58 * s),
                           control1: CGPoint(x: 17.66 * s, y: 15.63 * s), control2: CGPoint(x: 16.86 * s, y: 16.80 * s))
                p.addLine(to: CGPoint(x: 15.72 * s, y: 20.34 * s))
                p.addLine(to: CGPoint(x: 19.29 * s, y: 20.34 * s))
                p.addCurve(to: CGPoint(x: 22.56 * s, y: 12.25 * s),
                           control1: CGPoint(x: 21.37 * s, y: 18.42 * s), control2: CGPoint(x: 22.56 * s, y: 15.60 * s))
                p.closeSubpath()
            }, Color(hex: 0x4285F4))
            // green
            fill({ p in
                p.move(to: CGPoint(x: 12 * s, y: 23 * s))
                p.addCurve(to: CGPoint(x: 19.28 * s, y: 20.34 * s),
                           control1: CGPoint(x: 14.97 * s, y: 23 * s), control2: CGPoint(x: 17.46 * s, y: 22.02 * s))
                p.addLine(to: CGPoint(x: 15.71 * s, y: 17.58 * s))
                p.addCurve(to: CGPoint(x: 5.84 * s, y: 14.11 * s),
                           control1: CGPoint(x: 13.5 * s, y: 19.5 * s), control2: CGPoint(x: 7.5 * s, y: 18.1 * s))
                p.addLine(to: CGPoint(x: 2.18 * s, y: 16.95 * s))
                p.addCurve(to: CGPoint(x: 12 * s, y: 23 * s),
                           control1: CGPoint(x: 4 * s, y: 20.5 * s), control2: CGPoint(x: 8 * s, y: 23 * s))
                p.closeSubpath()
            }, Color(hex: 0x34A853))
            // yellow
            fill({ p in
                p.move(to: CGPoint(x: 5.84 * s, y: 14.11 * s))
                p.addCurve(to: CGPoint(x: 5.84 * s, y: 9.89 * s),
                           control1: CGPoint(x: 5.35 * s, y: 12.7 * s), control2: CGPoint(x: 5.35 * s, y: 11.3 * s))
                p.addLine(to: CGPoint(x: 2.18 * s, y: 7.05 * s))
                p.addCurve(to: CGPoint(x: 2.18 * s, y: 16.95 * s),
                           control1: CGPoint(x: 0.6 * s, y: 10.2 * s), control2: CGPoint(x: 0.6 * s, y: 13.8 * s))
                p.closeSubpath()
            }, Color(hex: 0xFBBC05))
            // red
            fill({ p in
                p.move(to: CGPoint(x: 12 * s, y: 5.38 * s))
                p.addCurve(to: CGPoint(x: 16.21 * s, y: 7.02 * s),
                           control1: CGPoint(x: 13.62 * s, y: 5.38 * s), control2: CGPoint(x: 15.06 * s, y: 5.94 * s))
                p.addLine(to: CGPoint(x: 19.36 * s, y: 3.87 * s))
                p.addCurve(to: CGPoint(x: 12 * s, y: 1 * s),
                           control1: CGPoint(x: 17.45 * s, y: 2.09 * s), control2: CGPoint(x: 14.97 * s, y: 1 * s))
                p.addCurve(to: CGPoint(x: 2.18 * s, y: 7.05 * s),
                           control1: CGPoint(x: 8 * s, y: 1 * s), control2: CGPoint(x: 4 * s, y: 3.5 * s))
                p.addLine(to: CGPoint(x: 5.84 * s, y: 9.89 * s))
                p.addCurve(to: CGPoint(x: 12 * s, y: 5.38 * s),
                           control1: CGPoint(x: 6.71 * s, y: 7.29 * s), control2: CGPoint(x: 9.14 * s, y: 5.38 * s))
                p.closeSubpath()
            }, Color(hex: 0xEA4335))
        }
        .frame(width: 18, height: 18)
    }
}

struct EnvelopeGlyph: View {
    var color: Color = NB.lime1
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            ctx.stroke(Path(roundedRect: CGRect(x: 2.75 * s, y: 5.25 * s, width: 18.5 * s, height: 13.5 * s),
                            cornerRadius: 3 * s), with: .color(color), lineWidth: 1.6 * s)
            var flap = Path()
            flap.move(to: CGPoint(x: 4 * s, y: 8.5 * s))
            flap.addLine(to: CGPoint(x: 12 * s, y: 13.2 * s))
            flap.addLine(to: CGPoint(x: 20 * s, y: 8.5 * s))
            ctx.stroke(flap, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
        }
        .frame(width: 18, height: 18)
    }
}

struct ArrowGlyph: View {
    var color: Color = NB.carbon
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            var p = Path()
            p.move(to: CGPoint(x: 5 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 19 * s, y: 12 * s))
            p.move(to: CGPoint(x: 13 * s, y: 6 * s)); p.addLine(to: CGPoint(x: 19 * s, y: 12 * s))
            p.addLine(to: CGPoint(x: 13 * s, y: 18 * s))
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.9 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 16, height: 16)
    }
}

struct ChevronGlyph: View {
    var color: Color = NB.white.opacity(0.8)
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            var p = Path()
            p.move(to: CGPoint(x: 14.5 * s, y: 5 * s))
            p.addLine(to: CGPoint(x: 7.5 * s, y: 12 * s))
            p.addLine(to: CGPoint(x: 14.5 * s, y: 19 * s))
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.7 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 18, height: 18)
    }
}

struct BackspaceGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            let ink = GraphicsContext.Shading.color(NB.white.opacity(0.55))
            var p = Path()
            p.move(to: CGPoint(x: 8.2 * s, y: 5.5 * s))
            p.addLine(to: CGPoint(x: 20 * s, y: 5.5 * s))
            p.addLine(to: CGPoint(x: 21.5 * s, y: 7 * s))
            p.addLine(to: CGPoint(x: 21.5 * s, y: 17 * s))
            p.addLine(to: CGPoint(x: 20 * s, y: 18.5 * s))
            p.addLine(to: CGPoint(x: 8.2 * s, y: 18.5 * s))
            p.addLine(to: CGPoint(x: 2.8 * s, y: 12 * s))
            p.closeSubpath()
            ctx.stroke(p, with: ink, lineWidth: 1.5 * s)
            var x = Path()
            x.move(to: CGPoint(x: 11.5 * s, y: 9.8 * s)); x.addLine(to: CGPoint(x: 16.5 * s, y: 14.2 * s))
            x.move(to: CGPoint(x: 16.5 * s, y: 9.8 * s)); x.addLine(to: CGPoint(x: 11.5 * s, y: 14.2 * s))
            ctx.stroke(x, with: ink, style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
        }
        .frame(width: 24, height: 24)
    }
}
