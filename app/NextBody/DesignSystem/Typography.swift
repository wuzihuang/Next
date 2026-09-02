import SwiftUI

/// The three families the design file loads: Jost (UI), Inter Tight (brand), Doto (dot-matrix numerals).
enum NBFont {
    enum Family: String {
        case ui = "Jost"
        case brand = "InterTight"
        case dot = "Doto"
    }

    /// CSS weight → the static instance we shipped in Resources/Fonts.
    private static func style(_ weight: Int, family: Family) -> String {
        switch weight {
        case ..<250:  return family == .dot ? "Regular" : "ExtraLight"
        case ..<350:  return family == .dot ? "Regular" : "Light"
        case ..<450:  return "Regular"
        case ..<550:  return "Medium"
        case ..<650:  return "SemiBold"
        case ..<750:  return "Bold"
        case ..<850:  return family == .ui ? "Bold" : "ExtraBold"
        default:      return family == .ui ? "Bold" : "Black"
        }
    }

    static func named(_ family: Family, _ weight: Int, _ size: CGFloat) -> Font {
        // F5 C11 · `size:` rather than `fixedSize:` so the type follows Dynamic Type up to the
        // xLarge cap RootView sets. fixedSize froze every screen at 1.0×, which is stricter
        // than the ruling — 「允许到 xLarge；再大冻结」 — and quietly stopped the largest
        // standard size from being honoured at all.
        .custom("\(family.rawValue)-\(style(weight, family: family))", size: size)
    }

    static func ui(_ weight: Int, _ size: CGFloat) -> Font { named(.ui, weight, size) }
    static func brand(_ weight: Int, _ size: CGFloat) -> Font { named(.brand, weight, size) }
    static func dot(_ weight: Int, _ size: CGFloat) -> Font { named(.dot, weight, size) }

    /// The system status-bar clock is SF, not Jost.
    static func system(_ weight: Font.Weight, _ size: CGFloat) -> Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    /// Paper writes tracking in em; SwiftUI wants points.
    func tracking(em: CGFloat, size: CGFloat) -> some View { tracking(em * size) }

    /// Paper writes line-height in px; SwiftUI's default leading differs, so we pin the frame.
    func lineHeight(_ px: CGFloat) -> some View {
        self.frame(minHeight: px).lineSpacing(0)
    }
}

/// One text style = one call, so a spec change is a one-line change (F0 rule 02).
struct NBText: View {
    let text: String
    var family: NBFont.Family = .ui
    var weight: Int = 500
    var size: CGFloat = 11
    var tracking: CGFloat = 0        // em
    var color: Color = NB.text1
    var lineHeightPx: CGFloat? = nil

    var body: some View {
        Text(text)
            .font(NBFont.named(family, weight, size))
            .tracking(tracking * size)
            .foregroundStyle(color)
            .modifier(LineHeight(px: lineHeightPx))
    }
}

private struct LineHeight: ViewModifier {
    let px: CGFloat?
    func body(content: Content) -> some View {
        if let px { content.frame(minHeight: px) } else { content }
    }
}
