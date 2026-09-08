import SwiftUI
import UIKit

/// The three families the design file loads: Jost (UI), Inter Tight (brand), Doto (dot-matrix numerals).
/// Chinese has no glyphs in those cuts, so Fusion Pixel (12px proportional zh_hans) is the
/// CJK cascade — and the primary face for UI/brand copy when the app language is Chinese.
enum NBFont {
    static let cjkPixel = "Fusion-Pixel-12px-Prop-zh_hans-Regular"

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
        let latin = "\(family.rawValue)-\(style(weight, family: family))"
        // 2026-09-07 · the whole screen is pixel type, in every language. Chinese already
        // read as Fusion Pixel and Latin did not, so one board could hold a dot-matrix
        // number, a pixel Chinese caption and an Inter Tight English sentence — the
        // "these charts stopped feeling pixel" report. Fusion Pixel is now the primary
        // face for UI and brand copy whatever the language; Doto keeps the dot-matrix
        // grid it was picked for and never falls back to it.
        if family != .dot {
            return cascaded(primary: cjkPixel, fallback: latin, size: size)
        }
        return cascaded(primary: latin, fallback: cjkPixel, size: size)
    }

    private static func cascaded(primary: String, fallback: String, size: CGFloat) -> Font {
        let base = UIFont(name: primary, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .medium)
        guard let fallbackFont = UIFont(name: fallback, size: size) else {
            return Font(base)
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName.cascadeList: [fallbackFont.fontDescriptor]
        ])
        return Font(UIFont(descriptor: descriptor, size: size))
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
