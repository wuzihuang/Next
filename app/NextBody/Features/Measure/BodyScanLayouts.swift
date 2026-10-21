import SwiftUI

/// 06 · the body scan's shared state words: the takeover's `Phase` and onboarding's
/// stream both map onto this enum, so the status / headline / help lines and their
/// tints are written once and can never drift between the two screens.
enum BodyScanState: Equatable, Hashable {
    case opening, waiting, nudge, contact
    case counting(fields: Int)
    case halfway
    case lost(grace: Int)
    case computing

    var status: String {
        switch self {
        case .opening:   ""
        case .waiting:   L("WAITING FOR YOUR FINGER")
        case .nudge:     L("NO CONTACT · %dS", 6)
        case .contact:   L("CONTACT · CIRCUIT CLOSED")
        case .counting(let fields): L("%d / 14 FIELDS", fields)
        case .halfway:   L("HALFWAY · KEEP THE FINGER THERE")
        case .lost(let grace): L("PAUSED · %dS TO RESUME", grace)
        case .computing: L("COMPUTING 14 FIELDS")
        }
    }

    var statusTint: Color {
        switch self {
        // E02 · the waiting line is lime: it is the screen saying it is ready, not a warning.
        case .waiting: NB.lime1.opacity(0.85)
        case .nudge, .lost: NB.ember2
        case .contact, .counting, .halfway: NB.lime1
        case .opening, .computing: NB.white.opacity(0.40)
        }
    }

    var headline: String {
        switch self {
        // The board's own words: which finger, and which key. 「Finger on the key」 with a
        // ring around the display was an instruction to press the screen.
        case .opening, .waiting: L("Index finger on the side key.")
        case .nudge:     L("Still nothing on the key.")
        case .contact:   L("Got it. Hold still.")
        case .counting:  L("Mapping you.")
        case .halfway:   L("Halfway.")
        case .lost:      L("Put it back.")
        case .computing: L("Working it out.")
        }
    }

    var help: String {
        switch self {
        case .opening:   ""
        case .waiting:   L("Rest your hand on the table. Nothing to press. It takes about 30 seconds.")
        case .nudge:     L("Skin, not a nail or a sleeve. Let it rest, don't press.")
        case .contact:   L("A tiny current crosses your body. You won't feel it.")
        // ⚠️ Body composition has no resume: lifting off restarts the whole 30 seconds.
        case .counting:  L("Lift a finger and the scan starts over.")
        case .halfway:   L("One steady contact makes one reading.")
        // 06 edge 2 · the board's sentence for a lifted finger.
        case .lost:      L("Your finger came off the key. This one has to start over.")
        case .computing: L("You can lift your finger now.")
        }
    }
}

/// The countdown the scanning screen carries: Doto, big, white while it runs,
/// amber the moment a finger comes off — holding where it stopped, never at zero.
struct BodyScanCount: View {
    let remaining: Int
    let held: Bool

    var body: some View {
        Text(String(format: "00:%02d", max(0, remaining)))
            .font(NBFont.dot(700, 52)).tracking(0.04 * 52)
            .foregroundStyle(held ? NB.ember1 : NB.text1)
            .frame(height: 56)
            .contentTransition(.numericText(countsDown: true))
    }
}

/// S1 · prepare: header, the stage (hoop or a card), the status sentence, the help
/// line, then the foot rule and whatever the caller puts under it. The takeover and
/// onboarding hand in their own insets — the takeover ignores the safe area, the
/// onboarding lives inside it.
struct BodyScanPrepareLayout<Header: View, Stage: View, Footer: View>: View {
    let topInset: CGFloat
    let bottomInset: CGFloat
    let status: String
    let statusTint: Color
    let headline: String
    let help: String
    let header: Header
    let stage: Stage
    let footer: Footer

    init(topInset: CGFloat, bottomInset: CGFloat,
         status: String, statusTint: Color, headline: String, help: String,
         @ViewBuilder header: () -> Header,
         @ViewBuilder stage: () -> Stage,
         @ViewBuilder footer: () -> Footer) {
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.status = status
        self.statusTint = statusTint
        self.headline = headline
        self.help = help
        self.header = header()
        self.stage = stage()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            header
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(status)
                .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(statusTint)
                .frame(minHeight: 13)
                .frame(width: NB.Layout.contentWidth)
            Text(headline)
                .font(NBFont.brand(500, 22)).tracking(-0.01 * 22)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.text1)
                .frame(width: 318)
                .padding(.top, 12)
            Text(help)
                .font(NBFont.ui(300, 12.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.white.opacity(0.42))
                .frame(width: 318)
                .padding(.top, 10)
            Spacer(minLength: 20)
            Text(L("NOTHING TO PRESS · KEEP STILL"))
                .font(NBFont.dot(500, 9.5)).tracking(0.16 * 9.5)
                .foregroundStyle(NB.white.opacity(0.30))
            footer
            Color.clear.frame(height: bottomInset)
        }
    }
}

/// S2 · scanning: header, the big count, the fields line, the body figure on a
/// measured height, the two sentences at the foot. Same stage-height rule the
/// takeover always used — the figure fills a capped share of what is left.
struct BodyScanScanningLayout<Header: View, Footer: View>: View {
    let topInset: CGFloat
    let bottomInset: CGFloat
    let headerHeight: CGFloat
    let remaining: Int
    let held: Bool
    let status: String
    let statusTint: Color
    let headline: String
    let help: String
    let beat: Int
    let total: Int
    let beatAt: Date
    let complete: Bool
    let header: Header
    let footer: Footer

    init(topInset: CGFloat, bottomInset: CGFloat, headerHeight: CGFloat,
         remaining: Int, held: Bool,
         status: String, statusTint: Color, headline: String, help: String,
         beat: Int, total: Int, beatAt: Date, complete: Bool,
         @ViewBuilder header: () -> Header,
         @ViewBuilder footer: () -> Footer) {
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.headerHeight = headerHeight
        self.remaining = remaining
        self.held = held
        self.status = status
        self.statusTint = statusTint
        self.headline = headline
        self.help = help
        self.beat = beat
        self.total = total
        self.beatAt = beatAt
        self.complete = complete
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        GeometryReader { proxy in
            let top = topInset + headerHeight + 18 + 56 + 16
            let bottom = bottomInset + 28 + 30 + 40 + 10 + 16
            let stageHeight = min(proxy.size.height * 0.53,
                                  max(220, proxy.size.height - top - bottom))
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                header
                BodyScanCount(remaining: remaining, held: held)
                    .padding(.top, 18)
                Text(status)
                    .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(statusTint)
                    .frame(width: NB.Layout.contentWidth)
                    .padding(.top, 2)
                Spacer(minLength: 8)
                ScanBody(beat: beat, total: total, beatAt: beatAt,
                         held: held, complete: complete)
                    .frame(maxWidth: .infinity)
                    .frame(height: stageHeight)
                Spacer(minLength: 8)
                Text(headline)
                    .font(NBFont.brand(500, 24)).tracking(-0.01 * 24)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NB.text1)
                    .frame(width: 318)
                Text(help)
                    .font(NBFont.ui(300, 12.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .frame(width: 318)
                    .padding(.top, 10)
                footer
                Color.clear.frame(height: bottomInset)
            }
        }
    }
}
