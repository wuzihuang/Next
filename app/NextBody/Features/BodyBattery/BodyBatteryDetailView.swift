import SwiftUI

/// 13 · Body Battery 详情. It answers exactly one question: why am I 72 today.
/// Same shape as 08's "why 14.5" card, because that is the product's pattern for earning trust:
/// the conclusion first, then the breakdown, then where the breakdown came from, then how sure.
struct BodyBatteryDetailView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    private var m: DailyMetrics { data.today }
    private var hasNight: Bool { m.bbWake != nil }

    var body: some View {
        DetailScroll(glow: NB.violet1) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if hasNight {
                    heroCard
                    whyCard
                    inputsCard
                    targetCard
                    confidenceCard
                    footer
                } else {
                    emptyCard
                    needsCard
                    LimePillButton(title: "Wear it tonight") { router.backToRoot() }
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
    }

    private var header: some View {
        HStack {
            Text("BODY BATTERY")
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
            Spacer(minLength: 0)
            Text(hasNight ? "TODAY" : "DAY 01")
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
        }
        .padding(.top, 14)
    }

    /// The curve: violet while charging overnight, white while discharging awake,
    /// with one lime dot at NOW. There is not a single sleep number on it.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(Fmt.int(m.bodyBattery))
                        .font(NBFont.dot(800, 64))
                        .foregroundStyle(NB.text1)
                    Text("OF 100")
                        .font(NBFont.dot(600, 12)).tracking(0.18 * 12)
                        .foregroundStyle(NB.white.opacity(0.42))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("PEAK 07:12")
                        .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                        .foregroundStyle(NB.white.opacity(0.42))
                    Text("+38 LAST NIGHT")
                        .font(NBFont.dot(700, 12)).tracking(0.12 * 12)
                        .foregroundStyle(NB.violet1)
                }
            }
            BatteryCurve().frame(width: 318, height: 120)
            HStack {
                ForEach(["04", "10", "NOW", "22"], id: \.self) { t in
                    Text(t)
                        .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                        .foregroundStyle(t == "NOW" ? NB.lime1 : NB.white.opacity(0.34))
                    if t != "22" { Spacer(minLength: 0) }
                }
            }
        }
        .padding(20)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .background(Color(hex: 0x0F0F13), in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.hairline, lineWidth: 1))
    }

    /// Four rows that must add up to the number at the top, within ±0.5.
    /// The order cannot change: last night first, then the three ways the day spent it.
    private var whyCard: some View {
        CardBlock(title: "WHY \(Fmt.int(m.bodyBattery))", trailing: "FROM 60 AT 04:00") {
            VStack(spacing: 11) {
                ContribRow(label: "Last night", value: 38, maxAbs: 38, tint: NB.violet1)
                ContribRow(label: "Just being awake", value: -14, maxAbs: 38, tint: NB.white.opacity(0.35))
                ContribRow(label: "Moving around", value: -9, maxAbs: 38, tint: NB.white.opacity(0.35))
                ContribRow(label: "Stress", value: -3, maxAbs: 38, tint: NB.white.opacity(0.35))
            }
            Hairline()
            HStack {
                Text("THESE FOUR ADD UP TO +12")
                    .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Text("60  →  \(Fmt.int(m.bodyBattery))")
                    .font(NBFont.dot(700, 11)).tracking(0.08 * 11)
                    .foregroundStyle(NB.text2)
            }
        }
    }

    /// HRV and resting heart rate are allowed on screen because we measure them and they have
    /// a unit. Sleep duration and stages are not, here or anywhere.
    private var inputsCard: some View {
        CardBlock(title: "LAST NIGHT'S INPUTS", trailing: "3 OF 3") {
            VStack(spacing: 12) {
                InputRow(name: "HRV", value: "54", unit: "MS", base: "BASE 61")
                Hairline()
                InputRow(name: "Resting heart rate", value: "51", unit: "BPM", base: "BASE 48")
                Hairline()
                InputRow(name: "Charge multiplier", value: "0.88", unit: nil, base: nil)
            }
        }
    }

    private var targetCard: some View {
        let band = BodyBattery.band(for: m.bbWake ?? 0)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY'S TARGET")
                    .font(NBFont.dot(700, 11)).tracking(0.22 * 11)
                    .foregroundStyle(NB.white)
                Spacer(minLength: 0)
                Text("SET AT 07:12")
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.white.opacity(0.42))
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%.1f", band.target))
                    .font(NBFont.dot(800, 38))
                    .foregroundStyle(NB.lime1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "RANGE %.1f – %.1f", band.optimal.lowerBound, band.optimal.upperBound))
                        .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                        .foregroundStyle(NB.white.opacity(0.42))
                    Text("BAND \(band.range.lowerBound) – \(band.range.upperBound)")
                        .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                        .foregroundStyle(NB.white.opacity(0.42))
                }
            }
            Text("Set once this morning. It does not move as the battery drops through the day.")
                .font(NBFont.brand(400, 14))
                .lineSpacing(8)
                .foregroundStyle(NB.white.opacity(0.70))
            Button { router.path = [.training] } label: {
                HStack(spacing: 8) {
                    Text("OPEN TRAINING")
                        .font(NBFont.dot(600, 10.5)).tracking(0.18 * 10.5)
                        .foregroundStyle(NB.white.opacity(0.55))
                    Text("→")
                        .font(NBFont.dot(700, 11))
                        .foregroundStyle(NB.lime1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .background(Color(hex: 0x0F0F13), in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.lime1.opacity(0.22), lineWidth: 1))
    }

    /// Three tiers, drawn as three segments — never a percentage. Once you draw 73%
    /// people read it as a measurement.
    private var confidenceCard: some View {
        CardBlock(title: "CONFIDENCE", trailing: m.confidence.rawValue, trailingIsDot: true) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i < tierIndex ? NB.lime1 : NB.white.opacity(0.10))
                        .frame(height: 5)
                }
            }
            Text("HRV BASELINE 9 / 14 NIGHTS")
                .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private var tierIndex: Int {
        switch m.confidence { case .pending: 1; case .medium: 2; case .high: 3 }
    }

    private var footer: some View {
        HStack {
            Text("SYNCED 07:12")
                .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.text3)
            Spacer(minLength: 0)
            Button {
                // A manual BATTERY CHECK is the only thing allowed to re-anchor the day.
                data.today.bodyBattery = m.bbWake
            } label: {
                Text("BATTERY CHECK")
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.text2)
                    .padding(.horizontal, 16).frame(height: 34)
                    .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    /// Unlike the training page, this empty state keeps no skeleton: the curve, the breakdown,
    /// the target and the confidence are all simply absent. No grey placeholders, no empty boxes.
    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(Fmt.dash)
                    .font(NBFont.dot(800, 36))
                    .foregroundStyle(NB.text3)
                Text("OF 100")
                    .font(NBFont.dot(600, 12)).tracking(0.18 * 12)
                    .foregroundStyle(NB.white.opacity(0.30))
            }
            Text("NOTHING TO CHARGE FROM YET")
                .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                .foregroundStyle(NB.ember1)
            Text("The first number arrives after your first night with the band on. Nothing to do today.")
                .font(NBFont.brand(400, 16))
                .lineSpacing(8)
                .foregroundStyle(NB.text1)
        }
        .padding(20)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .background(Color(hex: 0x0F0F13), in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.hairline, lineWidth: 1))
    }

    /// Three lines, and the last one is the point: fourteen nights before it knows your normal.
    private var needsCard: some View {
        CardBlock(title: "WHAT IT NEEDS") {
            VStack(alignment: .leading, spacing: 14) {
                NeedRow("One night with the band on your wrist")
                NeedRow("Five nights before the number settles")
                NeedRow("Fourteen nights before it knows your normal")
            }
        }
    }
}

private struct NeedRow: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        HStack(spacing: 10) {
            Circle().stroke(NB.white.opacity(0.28), lineWidth: 1).frame(width: 9, height: 9)
            Text(text)
                .font(NBFont.brand(400, 13))
                .foregroundStyle(NB.text2)
        }
    }
}

private struct ContribRow: View {
    let label: String
    let value: Double
    let maxAbs: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(NBFont.brand(400, 13))
                .foregroundStyle(NB.text2)
                .frame(width: 118, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(tint)
                    .frame(width: geo.size.width * CGFloat(abs(value) / maxAbs), height: 6)
                    .offset(y: 4)
            }
            .frame(height: 14)
            Text(value > 0 ? "+\(Int(value))" : "\(Int(value))")
                .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                .foregroundStyle(value > 0 ? NB.violet1 : NB.text2)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private struct InputRow: View {
    let name: String
    let value: String
    let unit: String?
    let base: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(NBFont.brand(400, 13))
                .foregroundStyle(NB.text2)
            Spacer(minLength: 0)
            Text(value)
                .font(NBFont.dot(700, 14)).tracking(0.04 * 14)
                .foregroundStyle(NB.text1)
            if let unit {
                Text(unit)
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.white.opacity(0.42))
            }
            if let base {
                Text(base)
                    .font(NBFont.dot(500, 9)).tracking(0.14 * 9)
                    .foregroundStyle(NB.white.opacity(0.28))
            }
        }
    }
}

/// Violet up through the night, white down through the day, one lime dot at NOW.
struct BatteryCurve: View {
    private static let charge: [CGPoint] = [
        .init(x: 4, y: 96), .init(x: 28, y: 92), .init(x: 52, y: 74),
        .init(x: 76, y: 50), .init(x: 96, y: 34), .init(x: 108, y: 30),
    ]
    private static let drain: [CGPoint] = [
        .init(x: 108, y: 30), .init(x: 132, y: 40), .init(x: 158, y: 52),
        .init(x: 184, y: 48), .init(x: 210, y: 60), .init(x: 236, y: 56), .init(x: 258, y: 66),
    ]

    @State private var draw: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 318, sy = size.height / 120
            func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x * sx, y: pt.y * sy) }

            for y in [30.0, 70.0] {
                ctx.fill(Path(CGRect(x: 0, y: y * sy, width: size.width, height: 1)),
                         with: .color(NB.white.opacity(0.06)))
            }

            var area = Path()
            area.move(to: p(Self.charge[0]))
            (Self.charge.dropFirst() + Self.drain.dropFirst()).forEach { area.addLine(to: p($0)) }
            area.addLine(to: p(.init(x: 258, y: 112)))
            area.addLine(to: p(.init(x: 4, y: 112)))
            area.closeSubpath()
            ctx.fill(area, with: .color(NB.violet1.opacity(0.10)))

            var up = Path()
            up.move(to: p(Self.charge[0]))
            Self.charge.dropFirst().forEach { up.addLine(to: p($0)) }
            ctx.stroke(up, with: .color(NB.violet1),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            var down = Path()
            down.move(to: p(Self.drain[0]))
            Self.drain.dropFirst().forEach { down.addLine(to: p($0)) }
            ctx.stroke(down, with: .color(NB.white.opacity(0.42)),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            let now = p(.init(x: 258, y: 66))
            ctx.fill(Path(ellipseIn: CGRect(x: now.x - 4.5, y: now.y - 4.5, width: 9, height: 9)),
                     with: .color(NB.lime1))
        }
    }
}
