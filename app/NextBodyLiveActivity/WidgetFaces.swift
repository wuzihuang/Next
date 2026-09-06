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

    /// Floor for the face margin. `margin(for:)` grows it with the face so a
    /// 158 square and a 364 large breathe alike; the wordmark, the band cell
    /// and the outer rings all start at whatever it returns.
    private static let edge: CGFloat = 14

    private static func margin(for width: CGFloat) -> CGFloat {
        max(edge, min(28, width * 0.062))
    }

    var body: some View {
        GeometryReader { geo in
            let margin = Self.margin(for: geo.size.width)
            switch family {
            case .systemSmall: small
            case .systemLarge: large(margin: margin, height: geo.size.height)
            default: medium(margin: margin, height: geo.size.height)
            }
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
    ///
    /// One `breath` above the rings and the same below the wordmark, so the
    /// face reads as a centred block rather than rings jammed against the
    /// squircle with the brand floating in the leftover. The rail is the
    /// wordmark's own height here (not the large face's 36) and whatever the
    /// rings do not use sits between the labels and the rail — the one gap
    /// that may grow with the phone.
    ///
    /// The ring stroke is centred on the circle, so half of it paints outside
    /// the frame: the top inset carries that overhang, and the bottom gives
    /// a little back because the wordmark's glyphs sit inside their rail.
    /// Measured on a 364×170 and a 338×158 face this lands the ring's outer
    /// edge, the label-to-brand gap and the brand-to-edge gap within 2pt of
    /// each other; without the correction the rings read 14 from the top
    /// and the brand 20 from the bottom — still top-heavy.
    private func medium(margin: CGFloat, height: CGFloat) -> some View {
        let breath = max(16, min(22, height * 0.115))
        return VStack(spacing: 0) {
            rings(margin: margin, valueSize: (22, 20, 16), share: 0.22, topInset: breath + 4)
            identityRail(margin: margin, bottomInset: breath - 2, railHeight: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Island.carbon)
    }

    /// Brand, rings, then last night and today's movers — one carbon.
    /// TEMP stays off this face. The third row is page two's missing
    /// RESPONSE plus last night's HRV and SpO2.
    private func large(margin: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            identityRail(margin: margin, topInset: 10)
            rings(margin: margin, valueSize: (22, 20, 16), share: 0.225, centred: true)
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
                HStack(spacing: 0) {
                    vital("RESPONSE", readout.responseText)
                    vital("HRV", readout.hrvText)
                    vital("SPO2", readout.spo2Text)
                }
            }
            .frame(height: max(150, height * 0.44))
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Island.carbon)
    }

    /// The outer two rings start at the same margin the wordmark does, and the
    /// leftover width becomes the air between them. Centring three fixed circles
    /// instead left a dead band down both sides while the rail hugged the edge.
    ///
    /// `share` caps each circle at a fraction of the face width so the rings
    /// shrink with the face rather than pinning to a constant and crowding the
    /// margins on the bigger families.
    ///
    /// `centred` splits the leftover height above and below the rings instead
    /// of leaving all of it underneath — the large face wants the rings to
    /// float between the brand rail and the vitals grid, not hug the rail.
    private func rings(margin: CGFloat,
                       valueSize: (CGFloat, CGFloat, CGFloat),
                       share: CGFloat,
                       topInset: CGFloat = 0,
                       centred: Bool = false) -> some View {
        GeometryReader { geo in
            let minGap = max(14, geo.size.width * 0.05)
            let label: CGFloat = 16
            let inner = geo.size.width - margin * 2
            let byWidth = (inner - minGap * 2) / 3
            let byHeight = geo.size.height - label - topInset
            let d = max(56, min(geo.size.width * share, byWidth, byHeight))
            let stroke: CGFloat = d >= 84 ? 8 : 7
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                if centred { Spacer(minLength: 0) }
                HStack(spacing: 0) {
                    WidgetRing(progress: readout.batteryProgress, value: readout.batteryText,
                               label: "BATTERY", tint: Island.lime, valueSize: valueSize.0,
                               diameter: d, stroke: stroke, labelSize: 8)
                    Spacer(minLength: minGap)
                    WidgetRing(progress: readout.loadProgress, value: readout.loadText,
                               label: "LOAD", tint: Island.white, valueSize: valueSize.1,
                               diameter: d, stroke: stroke, labelSize: 8)
                    Spacer(minLength: minGap)
                    WidgetRing(progress: readout.eatenProgress, value: readout.eatenText,
                               label: "EATEN", tint: Island.ember, valueSize: valueSize.2,
                               diameter: d, stroke: stroke, labelSize: 8)
                }
                .padding(.horizontal, margin)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Wordmark is white. The lime lives in the body-battery ring and,
    /// when the band is charging, inside the cell — not as a second pip
    /// sitting on the word.
    ///
    /// System content margins are off, so a rail sitting at the top of the
    /// face needs `topInset` to clear the squircle's corner curve.
    private func identityRail(margin: CGFloat,
                              topInset: CGFloat = 0,
                              bottomInset: CGFloat = 0,
                              railHeight: CGFloat = 36) -> some View {
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
        .padding(.horizontal, margin)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .frame(height: railHeight + topInset + bottomInset)
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
