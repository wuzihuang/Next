import SwiftUI
import UIKit

/// 14 · SCAN AGAIN 体重门 — the dial that stands in front of a body scan.
/// Reached only from the body page's text-state scan entry: the band reads fat against a
/// weight, so a scan with a stale one would only re-print the same table. The dial opens on
/// the latest weigh-in, snaps to 0.1 kg with ruler detents under the thumb, and the confirm
/// button both records the weigh-in and fires the scan — the sheet never asks for a second tap.
struct WeighInDialSheet: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss

    /// 10S rule 03 · same hard range as the keypad: 20–300 kg.
    private static let range: ClosedRange<Double> = 20 ... 300
    /// Points of ruler travel per kilogram of drag.
    private static let ptsPerKg: CGFloat = 90

    @State private var kg: Double = 78.0
    @State private var dragFrom: Double?
    @State private var lastTick: Int = 0
    @State private var haptics = RulerHaptics()

    private var lb: Double { kg * 2.2046226 }
    private var usesMetric: Bool { data.profile.usesMetric }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("BODY SCAN · ONE NUMBER FIRST"))
                    .font(NBFont.dot(600, 11)).tracking(0.22 * 11)
                    .foregroundStyle(NB.white.opacity(0.42))
                Text(L("Weigh-in first."))
                    .font(NBFont.brand(700, 26)).tracking(-0.01 * 26)
                    .foregroundStyle(NB.text1)
                Text(L("The band reads you against a weight. Give it today's."))
                    .font(NBFont.ui(300, 13.5)).tracking(0.02 * 13.5)
                    .foregroundStyle(NB.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 22)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", usesMetric ? kg : lb))
                    .font(NBFont.dot(700, 56))
                    .foregroundStyle(NB.text1)
                    .contentTransition(.numericText())
                Text(usesMetric ? "KG" : "LB")
                    .font(NBFont.dot(500, 14))
                    .foregroundStyle(NB.white.opacity(0.4))
            }
            .padding(.top, 24)

            ruler
                .frame(height: 78)
                .padding(.top, 14)

            HStack {
                Text(L("LAST · %@", lastLabel))
                    .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.white.opacity(0.42))
                Spacer()
                Text(lastWhen)
                    .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.white.opacity(0.42))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Spacer(minLength: 0)

            Button(action: confirm) {
                Text(L("SCAN AT %@ %@", String(format: "%.1f", usesMetric ? kg : lb), usesMetric ? "KG" : "LB"))
                    .font(NBFont.ui(500, 13)).tracking(0.15 * 13)
                    .foregroundStyle(NB.carbon)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(NB.lime1, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onAppear {
            // The dial always starts from the latest recorded weigh-in — never from zero and
            // never from wherever a previous drag happened to stop.
            kg = (data.weighIns.first?.weightKg ?? data.today.weightKg ?? 70)
                .clamped(to: Self.range)
            lastTick = Int((kg * 10).rounded())
        }
    }

    // MARK: - Ruler

    private var ruler: some View {
        GeometryReader { geo in
            let mid = geo.size.width / 2
            Canvas { ctx, size in
                // ±5 kg of ticks around the needle; anything further fades at the edges anyway.
                let lo = Int((kg - 5) * 10), hi = Int((kg + 5) * 10)
                for t in lo ... hi {
                    let v = Double(t) / 10
                    let x = mid + CGFloat(v - kg) * Self.ptsPerKg
                    guard x > -4, x < size.width + 4 else { continue }
                    let major = t % 10 == 0
                    let mid5 = !major && t % 5 == 0
                    let h: CGFloat = major ? 20 : mid5 ? 13 : 8
                    let op: Double = major ? 0.55 : mid5 ? 0.34 : 0.18
                    ctx.fill(Path(CGRect(x: x - 0.75, y: 34 - h, width: 1.5, height: h)),
                             with: .color(.white.opacity(op)))
                    if major {
                        let label = Text(String(format: "%.0f", v))
                            .font(NBFont.dot(600, 10)).tracking(1)
                            .foregroundStyle(NB.white.opacity(0.5))
                        ctx.draw(label, at: CGPoint(x: x, y: 68))
                    }
                }
            }
            .overlay(alignment: .top) {
                // The needle, with a one-tick ghost trail — the dial was caught mid-settle.
                HStack(spacing: 0) {}
                    .frame(width: 0)
                Rectangle().fill(NB.lime1).frame(width: 2, height: 30)
                    .overlay(alignment: .top) {
                        Circle().fill(NB.lime1).frame(width: 5, height: 5)
                    }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(NB.lime1.opacity(0.22)).frame(width: 2, height: 30)
                    .offset(x: -7)
                Rectangle().fill(NB.lime1.opacity(0.1)).frame(width: 2, height: 30)
                    .offset(x: 7)
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black, .clear], startPoint: .trailing, endPoint: .leading)
                        .frame(width: 58)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 58)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragFrom == nil {
                            dragFrom = kg
                            haptics.prepare()
                        }
                        let raw = (dragFrom ?? kg) - Double(g.translation.width) / Double(Self.ptsPerKg)
                        let next = raw.clamped(to: Self.range)
                        kg = (next * 10).rounded() / 10
                        let tick = Int((kg * 10).rounded())
                        if tick != lastTick {
                            haptics.tick(Self.mark(crossing: lastTick, to: tick))
                            lastTick = tick
                        }
                        if raw != next { haptics.edge() }
                    }
                    .onEnded { _ in
                        dragFrom = nil
                        haptics.end()
                    }
            )
        }
    }

    /// The heaviest detent between two ticks, so a fast drag across a whole kilogram still
    /// feels the notch even when the minor clicks around it were skipped.
    private static func mark(crossing from: Int, to: Int) -> RulerHaptics.Mark {
        let crossed = from < to ? (from + 1) ... to : to ... (from - 1)
        if crossed.contains(where: { $0 % 10 == 0 }) { return .major }
        if crossed.contains(where: { $0 % 5 == 0 }) { return .half }
        return .minor
    }

    // MARK: - Labels

    private var lastLabel: String {
        let v = data.weighIns.first?.weightKg ?? data.today.weightKg
        return usesMetric ? Fmt.kg(v) + " KG" : Fmt.kg(v.map { $0 * 2.2046226 }) + " LB"
    }

    private var lastWhen: String {
        guard let at = data.weighIns.first?.date else { return L("NEVER") }
        let days = Calendar.current.dateComponents([.day], from: at, to: Date()).day ?? 0
        if days <= 0 { return L("TODAY") }
        if days == 1 { return L("YESTERDAY") }
        return L("%d DAYS AGO", days)
    }

    private func confirm() {
        Haptics.impact(.soft)
        Task { await Analytics.shared.track("DIAL_SETTLE", ["KG": kg]) }
        data.addWeighIn(WeighIn(id: UUID(), date: Date(), weightKg: kg,
                                bodyFatPercent: nil, source: .measured, origin: .manual))
        dismiss()
        router.takeover = .measure(.bodyComposition)
    }
}

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
