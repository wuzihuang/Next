import SwiftUI

/// 13 · Body Battery 详情. It answers exactly one question: why am I 72 today.
/// Same shape as 08's "why 14.5" card, because that is the product's pattern for earning trust:
/// the conclusion first, then the breakdown, then where the breakdown came from, then how sure.
struct BodyBatteryDetailView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    private var m: DailyMetrics { data.today }
    private var hasNight: Bool { m.bbWake != nil }

    /// ⚠️ 1CUP · the four rows are only ever present when they close within 0.5 of
    /// BB(now) − BB(anchor). The server drops them when they do not, and there is no OTHER
    /// row to absorb a difference — the whole card goes away instead.
    private var drivers: ReserveDrivers? { m.reserveDrivers }

    /// The peak is the highest point on the curve, not a fixed hour. With no curve on hand
    /// the board's 07:12 stands in.
    private var peakTime: String {
        guard let top = m.reserveCurve.max(by: { $0.value < $1.value }) else { return "07:12" }
        return Fmt.clock(top.ts)
    }

    var body: some View {
        DetailScroll(glow: NB.violet1) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if hasNight {
                    heroCard
                    if drivers != nil { whyCard }
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
        // 13 · the board names its events exactly, because each acceptance line is written
        // against one of them. A different name is a line nobody can check.
        .task {
            await Analytics.shared.track("BB_DETAIL_OPEN", ["ENTRY": "panel"])
            if let bb = m.bodyBattery {
                await Analytics.shared.track("BB_CONFIDENCE_SHOWN",
                                             ["LEVEL": m.confidence.rawValue, "SCORE": bb])
            } else {
                await Analytics.shared.track("BB_NO_SCORE",
                                             ["REASON": hasNight ? "NOT_SYNCED" : "SHORT_NIGHT"])
            }
            // ⚠️ Raised when the four rows do not close. The server withholds them rather
            // than fudging a fifth row, and this is the alarm that says it happened.
            if hasNight && m.reserveDrivers == nil {
                await Analytics.shared.track("BB_ATTRIBUTION_MISMATCH",
                                             ["TICKS": m.reserveCurve.count])
            }
            if let wake = m.bbWake, let target = m.targetLoad, let zone = m.optimalZone {
                await Analytics.shared.track("BB_TARGET_SET",
                                             ["BB": wake, "TARGET": target,
                                              "LO": zone.lowerBound, "HI": zone.upperBound])
            }
            if data.vitals.freshness == .stale, let at = data.vitals.at {
                await Analytics.shared.track("BB_STALE_SHOWN",
                                             ["MIN": Int(Date().timeIntervalSince(at) / 60)])
            }
        }
    }

    private var header: some View {
        HStack {
            Text(MetricNames.bodyBattery)
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
                    Text("PEAK \(peakTime)")
                        .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                        .foregroundStyle(NB.white.opacity(0.42))
                    Text("\(Fmt.signed(drivers?.lastNight ?? 0)) LAST NIGHT")
                        .font(NBFont.dot(700, 12)).tracking(0.12 * 12)
                        .foregroundStyle(NB.violet1)
                }
            }
            BatteryCurve(samples: m.reserveCurve).frame(width: 318, height: 120)
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
    @ViewBuilder private var whyCard: some View {
        let d = drivers ?? ReserveDrivers(lastNight: 0, awake: 0, movement: 0, stress: 0, anchor: 0)
        let scale = max(1, max(abs(d.lastNight), max(abs(d.awake), max(abs(d.movement), abs(d.stress)))))
        CardBlock(title: "WHY \(Fmt.int(m.bodyBattery))", trailing: "FROM \(d.anchor) AT 04:00") {
            VStack(spacing: 11) {
                ContribRow(label: "Last night", value: d.lastNight, maxAbs: scale, tint: NB.violet1)
                ContribRow(label: "Just being awake", value: d.awake, maxAbs: scale, tint: NB.white.opacity(0.35))
                ContribRow(label: "Moving around", value: d.movement, maxAbs: scale, tint: NB.white.opacity(0.35))
                ContribRow(label: "Stress", value: d.stress, maxAbs: scale, tint: NB.white.opacity(0.35))
            }
            Hairline()
            HStack {
                Text("THESE FOUR ADD UP TO \(Fmt.signed(d.sum))")
                    .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Text("\(d.anchor)  →  \(Fmt.int(m.bodyBattery))")
                    .font(NBFont.dot(700, 11)).tracking(0.08 * 11)
                    .foregroundStyle(NB.text2)
            }
            // ⚠️ 1CK4 · the first night has no yesterday to start from, so it starts from an
            // assumption. Say it in words; never let 20 read as something we measured.
            if d.assumedAnchor {
                Text("There was no yesterday to start from, so this day begins at an assumed 20. It stops being an assumption tomorrow.")
                    .font(NBFont.brand(400, 13))
                    .lineSpacing(6)
                    .foregroundStyle(NB.white.opacity(0.62))
            }
        }
    }

    /// HRV and resting heart rate are allowed on screen because we measure them and they have
    /// a unit. Sleep duration and stages are not, here or anywhere.
    private var inputsCard: some View {
        let n = m.nightInputs ?? NightInputs()
        return CardBlock(title: "LAST NIGHT'S INPUTS", trailing: "\(n.present) OF 3") {
            VStack(spacing: 12) {
                InputRow(name: "HRV", value: Fmt.kg(n.hrv, decimals: 0), unit: n.hrv == nil ? nil : "MS",
                         base: n.hrvBase.map { "BASE \(Int($0))" })
                Hairline()
                InputRow(name: "Resting heart rate", value: Fmt.kg(n.rhr, decimals: 0),
                         unit: n.rhr == nil ? nil : "BPM",
                         base: n.rhrBase.map { "BASE \(Int($0))" })
                Hairline()
                InputRow(name: "Charge multiplier",
                         value: n.multiplier.map { String(format: "%.2f", $0) } ?? Fmt.dash,
                         unit: nil, base: nil)
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
                Text("SET AT \(peakTime)")
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
            Text("BASELINE \(m.nightInputs?.rhrNights ?? 0) / 14 NIGHTS")
                .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private var tierIndex: Int {
        switch m.confidence { case .pending: 1; case .medium: 2; case .high: 3 }
    }

    private var footer: some View {
        HStack {
            Text("SYNCED \(Fmt.clock(data.lastSync))")
                .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.text3Prod)
            Spacer(minLength: 0)
            Button {
                // A manual BATTERY CHECK is the only thing allowed to re-anchor the day.
                let from = data.today.bodyBattery
                data.today.bodyBattery = m.bbWake
                Task {
                    await Analytics.shared.track("BB_TARGET_REANCHORED",
                                                 ["FROM": from as Any, "TO": m.bbWake as Any,
                                                  "SOURCE": "battery_check"])
                }
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
                    .foregroundStyle(NB.text3Prod)
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
/// With real samples the shape is the day's own; with none it falls back to the board's
/// path, so the page looks like the design before the first night has been recorded.
struct BatteryCurve: View {
    var samples: [ReserveSample] = []

    private static let boardCharge: [CGPoint] = [
        .init(x: 4, y: 96), .init(x: 28, y: 92), .init(x: 52, y: 74),
        .init(x: 76, y: 50), .init(x: 96, y: 34), .init(x: 108, y: 30),
    ]
    private static let boardDrain: [CGPoint] = [
        .init(x: 108, y: 30), .init(x: 132, y: 40), .init(x: 158, y: 52),
        .init(x: 184, y: 48), .init(x: 210, y: 60), .init(x: 236, y: 56), .init(x: 258, y: 66),
    ]

    /// The 318 × 120 box the board draws in. x is the 24 hours from the 04:00 cut,
    /// y is 0–100 of battery; the two are split at the peak, which is when you woke.
    private func path() -> (charge: [CGPoint], drain: [CGPoint]) {
        guard samples.count > 1,
              let first = samples.first,
              let peak = samples.enumerated().max(by: { $0.element.value < $1.element.value })
        else { return (Self.boardCharge, Self.boardDrain) }

        let day = UserDay.containing(first.ts)
        func point(_ s: ReserveSample) -> CGPoint {
            let t = min(1, max(0, s.ts.timeIntervalSince(day.start) / 86_400))
            return CGPoint(x: 4 + t * 310, y: 112 - Double(s.value) / 100 * 104)
        }
        let all = samples.map(point)
        return (Array(all[...peak.offset]), Array(all[peak.offset...]))
    }

    var body: some View {
        let (charge, drain) = path()
        Canvas { ctx, size in
            let sx = size.width / 318, sy = size.height / 120
            func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x * sx, y: pt.y * sy) }

            for y in [30.0, 70.0] {
                ctx.fill(Path(CGRect(x: 0, y: y * sy, width: size.width, height: 1)),
                         with: .color(NB.white.opacity(0.06)))
            }

            guard let head = charge.first, let tail = drain.last else { return }

            var area = Path()
            area.move(to: p(head))
            (charge.dropFirst() + drain.dropFirst()).forEach { area.addLine(to: p($0)) }
            area.addLine(to: p(.init(x: tail.x, y: 112)))
            area.addLine(to: p(.init(x: head.x, y: 112)))
            area.closeSubpath()
            ctx.fill(area, with: .color(NB.violet1.opacity(0.10)))

            var up = Path()
            up.move(to: p(head))
            charge.dropFirst().forEach { up.addLine(to: p($0)) }
            ctx.stroke(up, with: .color(NB.violet1),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            if let dhead = drain.first {
                var down = Path()
                down.move(to: p(dhead))
                drain.dropFirst().forEach { down.addLine(to: p($0)) }
                ctx.stroke(down, with: .color(NB.white.opacity(0.42)),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }

            let now = p(tail)
            ctx.fill(Path(ellipseIn: CGRect(x: now.x - 4.5, y: now.y - 4.5, width: 9, height: 9)),
                     with: .color(NB.lime1))
        }
    }
}
