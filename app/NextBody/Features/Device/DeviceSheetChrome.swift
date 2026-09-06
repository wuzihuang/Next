import SwiftUI

/// 12Y · one chrome for the two action-tile sheets (Find HOOP, Alarms).
/// They used to each invent their own: a different ground, a different gutter, a
/// headline on one face and none on the other, and three fonts for the same 52pt key.
/// Now both share the DEVICE sheet anatomy — eyebrow → title → one sentence on
/// carbon-2 inside the 16pt gutter every other sheet on this page uses — and one key.
enum DeviceSheet {
    static let gutter: CGFloat = NB.Layout.gutter
    static let top: CGFloat = 26
    static let bottom: CGFloat = 26
    /// Vertical rhythm of a full-width row (a clock, RSSI, Range).
    static let rowInset: CGFloat = 18
}

/// Eyebrow (dot, tracked) over a 22pt title over an optional one-line sentence.
/// The eyebrow is the sheet's live word — READY · LIVE, TIMEOUT, NEW ALARM — so it
/// carries the tint; the title never does.
struct SheetHeader<Trailing: View>: View {
    let eyebrow: String
    var eyebrowTint: Color = NB.lime1
    var eyebrowID: String? = nil
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(eyebrow)
                    .font(NBFont.dot(600, 11))
                    .tracking(0.28 * 11)
                    .foregroundStyle(eyebrowTint)
                    .accessibilityIdentifier(eyebrowID ?? "")
                Spacer(minLength: 0)
                trailing()
            }
            Text(title)
                .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
                .foregroundStyle(NB.text1)
            if let subtitle {
                Text(subtitle)
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .lineSpacing(5)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SheetHeader where Trailing == EmptyView {
    init(eyebrow: String, eyebrowTint: Color = NB.lime1, eyebrowID: String? = nil,
         title: String, subtitle: String? = nil) {
        self.eyebrow = eyebrow
        self.eyebrowTint = eyebrowTint
        self.eyebrowID = eyebrowID
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

/// The one 52pt capsule key both sheets press. Lime for the thing you came to do,
/// ember for the way out of a timeout, outline for a second choice under a list.
struct HoopKey: View {
    enum Skin { case lime, ember, outline }

    let title: String
    var skin: Skin = .lime
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NBFont.ui(600, 14)).tracking(0.06 * 14)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(fill, in: Capsule())
                .overlay(skin == .outline ? Capsule().stroke(NB.lime1.opacity(0.55), lineWidth: 1) : nil)
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var ink: Color {
        switch skin {
        case .lime, .ember: NB.carbon4
        case .outline: NB.lime1
        }
    }

    private var fill: Color {
        switch skin {
        case .lime: NB.lime1
        case .ember: NB.ember1
        case .outline: .clear
        }
    }
}

/// One ember line under the face — a refusal, DEVICE BUSY, a band that has no Find.
struct SheetNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(NBFont.dot(600, 10)).tracking(0.12 * 10)
            .foregroundStyle(NB.ember1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
