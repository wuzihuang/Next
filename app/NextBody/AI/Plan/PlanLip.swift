import SwiftUI

/// Paper 04D · root chrome: chasing chevron, the two page dots, SUGGESTIONS under them.
/// The lane stays put through a horizontal page turn — only the dots crossfade.
/// No extra lime dots beside SUGGESTIONS. iOS still paints the Home Indicator.
struct PlanLip: View {
    var pageFade: Double
    var playing: Bool
    var flatten: CGFloat
    var armed: Bool
    var reduceMotion: Bool

    var body: some View {
        VStack(spacing: 5) {
            PlanChevron(up: true, playing: playing, flatten: flatten,
                        armed: armed, reduceMotion: reduceMotion)
                .equatable()
            pageDots
            Text(L("SUGGESTIONS"))
                .font(NBFont.dot(600, 10))
                .tracking(0.22 * 10)
                .foregroundStyle(NB.lime1)
                .shadow(color: NB.lime1.opacity(armed ? 0.55 : 0.28),
                        radius: armed ? 8 : 5)
                .opacity(1 - flatten)
        }
        .frame(height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("plan.lip")
        .accessibilityLabel(L("Suggestions"))
        .accessibilityHint(L("Swipe up for personal suggestions"))
    }

    /// Same two 4pt dots the root used to draw — white, current page bright.
    private var pageDots: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(NB.white.opacity(0.24 + 0.48 * pageFade))
                .frame(width: 4, height: 4)
            Circle()
                .fill(NB.white.opacity(0.24 + 0.48 * (1 - pageFade)))
                .frame(width: 4, height: 4)
        }
    }
}
