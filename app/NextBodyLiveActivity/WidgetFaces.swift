import SwiftUI

/// Chrome for the widget faces. Colours match `Island` plus the band cell.
enum WidgetPaint {
    static let hairline = Color.white.opacity(0.08)
    static let track = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1F / 255)
    static let text3 = Color.white.opacity(0.55)
    static let lime2 = Color(red: 0xA3 / 255, green: 0xE6 / 255, blue: 0x35 / 255)
    static let lime3 = Color(red: 0x4D / 255, green: 0x7C / 255, blue: 0x0F / 255)
    static let limePale = Color(red: 0xD9 / 255, green: 0xF9 / 255, blue: 0x9D / 255)
    static let shell = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x44 / 255)
}

struct WidgetRing: View {
    var progress: Double
    var value: String
    var label: String
    var tint: Color
    var valueSize: CGFloat
    var diameter: CGFloat = 96
    var stroke: CGFloat = 8
    var labelSize: CGFloat = 8

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(WidgetPaint.track, lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(Island.dot(700, valueSize))
                    .foregroundStyle(tint == Island.lime ? Island.lime : Island.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
            }
            .frame(width: diameter, height: diameter)
            Text(label)
                .font(Island.dot(600, labelSize))
                .tracking(0.18 * labelSize)
                .foregroundStyle(WidgetPaint.text3)
        }
    }
}

/// The home header's 12×7 battery cell, drawn here so the widget does not
/// pull `Chrome` into the extension. No pulse — WidgetKit is a still.
struct WidgetBandPip: View {
    var progress: Double
    var text: String
    var lit: Bool

    var body: some View {
        HStack(spacing: 6) {
            Canvas { ctx, size in
                let s = size.width / 12
                func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
                    ctx.fill(Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)),
                             with: .color(c))
                }
                let shell = lit ? WidgetPaint.lime3 : WidgetPaint.shell
                rect(0, 0, 10, 1, shell)
                rect(0, 6, 10, 1, shell)
                rect(0, 1, 1, 5, shell)
                rect(9, 1, 1, 5, shell)
                rect(10, 2, 2, 3, shell)
                let fillWidth = 8 * CGFloat(max(0, min(1, progress)))
                if fillWidth > 0 {
                    rect(1, 1, fillWidth, 5, lit ? Island.lime : WidgetPaint.lime2)
                }
                if lit {
                    for (x, y) in [(5, 1), (4, 2), (5, 2), (3, 3), (4, 3),
                                   (5, 3), (6, 3), (5, 4), (6, 4), (5, 5)] {
                        let overFill = CGFloat(x) + 1 <= 1 + fillWidth
                        rect(CGFloat(x), CGFloat(y), 1, 1, overFill ? Island.carbon : Island.lime)
                    }
                }
            }
            .frame(width: 22, height: 13)
            Text(text)
                .font(Island.dot(700, 11))
                .tracking(0.06 * 11)
                .foregroundStyle(lit ? Island.lime : WidgetPaint.limePale)
        }
        .accessibilityLabel("Band · battery \(text)")
    }
}

struct TodayWidgetFace: View {
    var readout: WidgetFaceMath.TodayReadout
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge: large
        default: medium
        }
    }

    /// One number. The square is the body-battery instrument.
    private var small: some View {
        VStack(spacing: 8) {
            WidgetRing(progress: readout.batteryProgress, value: readout.batteryText,
                       label: "BODY BATTERY", tint: Island.lime, valueSize: 28,
                       diameter: 112, stroke: 9, labelSize: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Island.carbon)
    }

    /// Three rings, then the name and the band — same carbon, no second plate.
    private var medium: some View {
        VStack(spacing: 0) {
            rings(valueSize: (20, 18, 15), maxDiameter: 78)
            identityRail()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Island.carbon)
    }

    /// Brand, rings, then last night and today's movers — one carbon.
    /// TEMP stays off this face; the six cells are page two without it.
    private var large: some View {
        VStack(spacing: 0) {
            identityRail()
            rings(valueSize: (22, 20, 16), maxDiameter: 86)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    vital("SLEEP", readout.sleepText)
                    vital("ACTIVE", readout.activeText)
                    vital("HR", readout.heartText)
                }
                HStack(spacing: 0) {
                    vital("STRESS", readout.stressText)
                    vital("STEPS", readout.stepsText)
                    vital("DISTANCE", readout.distanceText)
                }
            }
            .frame(height: 124)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Island.carbon)
    }

    /// Leave air between the three circles. A fixed 108 on a 338-wide
    /// face made them kiss; the diameter follows the leftover box.
    private func rings(valueSize: (CGFloat, CGFloat, CGFloat),
                       maxDiameter: CGFloat) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = 20
            let pad: CGFloat = 18
            let label: CGFloat = 16
            let inner = geo.size.width - pad * 2
            let byWidth = (inner - gap * 2) / 3
            let byHeight = geo.size.height - label
            let d = max(56, min(maxDiameter, byWidth, byHeight))
            let stroke: CGFloat = d >= 80 ? 8 : 7
            HStack(spacing: gap) {
                WidgetRing(progress: readout.batteryProgress, value: readout.batteryText,
                           label: "BATTERY", tint: Island.lime, valueSize: valueSize.0,
                           diameter: d, stroke: stroke, labelSize: 8)
                WidgetRing(progress: readout.loadProgress, value: readout.loadText,
                           label: "LOAD", tint: Island.white, valueSize: valueSize.1,
                           diameter: d, stroke: stroke, labelSize: 8)
                WidgetRing(progress: readout.eatenProgress, value: readout.eatenText,
                           label: "EATEN", tint: Island.ember, valueSize: valueSize.2,
                           diameter: d, stroke: stroke, labelSize: 8)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Wordmark is white. The lime lives in the body-battery ring and,
    /// when the band is charging, inside the cell — not as a second pip
    /// sitting on the word.
    private func identityRail() -> some View {
        HStack {
            Text("NEXTBODY")
                .font(Island.brand(13))
                .tracking(-0.01 * 13)
                .foregroundStyle(Island.white)
            Spacer(minLength: 8)
            WidgetBandPip(progress: readout.bandProgress,
                          text: readout.bandText,
                          lit: readout.bandLit)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private func vital(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Island.dot(700, 20))
                .foregroundStyle(Island.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(Island.dot(600, 8))
                .tracking(0.12 * 8)
                .foregroundStyle(WidgetPaint.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Paper 02 LIME on a 158 face: 16 inset, 126 finder, 52 lens, the meal line.
struct ShotWidgetFace: View {
    var body: some View {
        ZStack {
            Island.carbon
            WidgetViewfinder()
                .frame(width: 126, height: 126)
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(Island.lime, lineWidth: 3)
                        .frame(width: 52, height: 52)
                    Circle()
                        .strokeBorder(WidgetPaint.track, lineWidth: 7)
                        .frame(width: 28, height: 28)
                }
                Text("LOG A MEAL")
                    .font(Island.dot(600, 7))
                    .tracking(0.12 * 7)
                    .foregroundStyle(Island.lime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Island.carbon)
        .accessibilityLabel("Log a meal")
        .accessibilityAddTraits(.isButton)
    }
}

/// Paper viewfinder: 126 box, 2 inset, 22 arms, lime.
struct WidgetViewfinder: View {
    var tint: Color = Island.lime

    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 2
            let arm: CGFloat = 22
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: inset, y: inset + arm))
            path.addLine(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: inset + arm, y: inset))
            path.move(to: CGPoint(x: w - inset - arm, y: inset))
            path.addLine(to: CGPoint(x: w - inset, y: inset))
            path.addLine(to: CGPoint(x: w - inset, y: inset + arm))
            path.move(to: CGPoint(x: w - inset, y: h - inset - arm))
            path.addLine(to: CGPoint(x: w - inset, y: h - inset))
            path.addLine(to: CGPoint(x: w - inset - arm, y: h - inset))
            path.move(to: CGPoint(x: inset + arm, y: h - inset))
            path.addLine(to: CGPoint(x: inset, y: h - inset))
            path.addLine(to: CGPoint(x: inset, y: h - inset - arm))
            ctx.stroke(
                path,
                with: .color(tint),
                style: StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter)
            )
        }
    }
}
