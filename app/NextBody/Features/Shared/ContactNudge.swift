import SwiftUI

/// 03 · Scanning, edge 1 · NO CONTACT. The count sits at 30 and nothing moves, which reads as
/// "broken" — so after a few seconds a sheet rises from the bottom and shows, on a loop, the
/// one thing to do: the index finger coming to rest on the band's side key. The key lights when
/// it lands, a ripple leaves it, the finger lifts, and it plays again. It goes away the moment
/// the band reports contact; it is never dismissed by hand, because there is nothing else to do.
struct ContactNudgeSheet: View {
    /// True when the fingers were on and came off: the wording changes, the picture does not.
    var lifted: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(NB.white.opacity(0.18)).frame(width: 36, height: 4).padding(.top, 10)

            Text(lifted ? "FINGER OFF · SCAN ON HOLD" : "NO CONTACT · WAITING")
                .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                .foregroundStyle(NB.ember1)
                .padding(.top, 18)

            Text(lifted ? "Put your finger back on the side key." : "Index finger on the side key.")
                .font(NBFont.brand(500, 20))
                .foregroundStyle(NB.text1)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            TimelineView(.animation(paused: reduceMotion)) { tl in
                KeyTouchLoop(t: reduceMotion ? 1.0 : tl.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: 260, height: 132)
            .padding(.top, 14)

            Text("Rest it on the metal key at the band's side. Skin, not a nail or a sleeve — let it rest, don't press.")
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13).lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.white.opacity(0.55))
                .frame(width: 300)
                .padding(.top, 10)
                .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: NB.R.panel, topTrailingRadius: NB.R.panel, style: .continuous)
                .fill(NB.carbon2)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: NB.R.panel, topTrailingRadius: NB.R.panel, style: .continuous)
                    .stroke(NB.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 30, y: -8)
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lifted ? "Put your finger back on the side key" : "Put your index finger on the side key")
    }
}

/// One 2.4 s loop: the index finger approaches (0–0.30), rests on the key (0.30–0.66, the
/// key lights and a ripple leaves it), lifts away (0.66–1). Drawn with the same dashed band as
/// FingersOn, so the thing on the sheet is the thing in the user's other hand.
private struct KeyTouchLoop: View {
    let t: TimeInterval

    var body: some View {
        Canvas { ctx, size in
            let period = 2.4
            let p = (t / period).truncatingRemainder(dividingBy: 1)

            // band
            let band = CGRect(x: 44, y: 14, width: 62, height: 104)
            ctx.stroke(Path(roundedRect: band, cornerRadius: 26),
                       with: .color(NB.lime1.opacity(0.42)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2.2, 3.2]))
            ctx.stroke(Path(roundedRect: band.insetBy(dx: 11, dy: 11), cornerRadius: 18),
                       with: .color(NB.lime1.opacity(0.10)), lineWidth: 1)

            // key on the right edge
            let key = CGRect(x: band.maxX + 2, y: band.midY - 19, width: 6, height: 38)
            let resting = p >= 0.30 && p < 0.66
            ctx.fill(Path(roundedRect: key, cornerRadius: 3),
                     with: .color(resting ? NB.lime1 : NB.lime1.opacity(0.45)))

            // fingertip travel: 0…1 = away…touching
            func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
            let reach: Double
            if p < 0.30 { reach = ease(p / 0.30) }
            else if p < 0.66 { reach = 1 }
            else { reach = 1 - ease((p - 0.66) / 0.34) }
            let far = key.maxX + 96, near = key.maxX + 14
            let fx = far - (far - near) * reach
            // one fingertip — the index finger, the way FingersOn draws it
            let r: CGFloat = 17
            let c = CGRect(x: fx - r, y: key.midY - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: c), with: .color(NB.white.opacity(reach > 0.98 ? 0.92 : 0.70)))
            ctx.stroke(Path(ellipseIn: c.insetBy(dx: 4, dy: 4)), with: .color(NB.carbon2.opacity(0.35)), lineWidth: 1)

            // ripple leaving the key while the fingers rest
            if resting {
                let q = (p - 0.30) / 0.36
                for k in 0..<2 {
                    let s = (q + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                    let rad = 10 + CGFloat(s) * 40
                    ctx.stroke(Path(ellipseIn: CGRect(x: key.midX - rad, y: key.midY - rad, width: 2 * rad, height: 2 * rad)),
                               with: .color(NB.lime1.opacity((1 - s) * 0.55)), lineWidth: 2)
                }
            }
        }
    }
}
