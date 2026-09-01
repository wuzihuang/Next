import SwiftUI

/// 04 · 03 训练环 The Ring.
/// An absolute 0–21 gauge, never a percentage: the ruler does not change shape from day to day.
/// Inner ring 80×80 · inner stroke 7.5 at r27 · outer zone stroke 4 at r35.5 · target dot r3.25,
/// all three concentric. The zone arc and the target dot only appear once the day has a
/// Body Battery result; the rest of the time the outer lane stays empty.
struct TrainingRing: View {
    var load: Double?              // TRAINING_LOAD 0–21
    var target: Double?            // TARGET_LOAD
    var zone: ClosedRange<Double>? // OPTIMAL_ZONE
    var size: CGFloat = 80
    var animate = true

    static let fullRing: Double = 21

    @State private var shown: Double = 0

    private var s: CGFloat { size / 80 }

    var body: some View {
        ZStack {
            // Full ring · the ruler itself
            Circle()
                .strokeBorder(NB.ringTrack, lineWidth: 7.5 * s)
                .frame(width: 61.5 * s, height: 61.5 * s)   // r27 centre-line ⇒ 54 + stroke

            // Training now
            RingArc(from: 0, to: shown / Self.fullRing)
                .stroke(NB.cyan1, style: StrokeStyle(lineWidth: 7.5 * s, lineCap: .round))
                .frame(width: 54 * s, height: 54 * s)

            // Optimal zone, on the outer lane
            if let zone {
                RingArc(from: zone.lowerBound / Self.fullRing, to: zone.upperBound / Self.fullRing)
                    .stroke(NB.cyan2, style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
                    .frame(width: 71 * s, height: 71 * s)
            }

            // Target — a point, not an arc
            if let target {
                let a = Angle.degrees(360 * target / Self.fullRing - 90)
                Circle()
                    .fill(NB.cyanPale)
                    .frame(width: 6.5 * s, height: 6.5 * s)
                    .offset(x: 35.5 * s * cos(a.radians), y: 35.5 * s * sin(a.radians))
            }

            Text(Fmt.load(load))
                .font(NBFont.dot(700, 16 * s))
                .tracking(-0.02 * 16 * s)
                .foregroundStyle(NB.cyan1)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard let load else { return }
            if animate {
                withAnimation(.easeOut(duration: 0.9)) { shown = load }
            } else { shown = load }
        }
        .onChange(of: load) { _, v in
            withAnimation(.easeOut(duration: 0.6)) { shown = v ?? 0 }
        }
    }
}

/// A clockwise arc measured from 12 o'clock, in ring fractions.
struct RingArc: Shape {
    var from: Double
    var to: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { .init(from, to) }
        set { from = newValue.first; to = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard to > from else { return p }
        let r = min(rect.width, rect.height) / 2
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: r,
                 startAngle: .degrees(360 * from - 90),
                 endAngle: .degrees(360 * to - 90),
                 clockwise: false)
        return p
    }
}
