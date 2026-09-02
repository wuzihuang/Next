import SwiftUI

// Generated 1:1 from the Paper design tokens of NEXTBODY-HOOP · page "新版设计".
// One concept, one name (F0 rule 01). Never hard-code a hex outside this file.
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Design tokens. Names mirror the CSS custom properties in the Paper file.
enum NB {

    // MARK: Carbon / surfaces
    static let carbon       = Color(hex: 0x0B0B0D)   // --carbon        app ground
    static let carbonDeep   = Color(hex: 0x0A0A0C)   // --carbon-deep
    static let carbon2      = Color(hex: 0x0D0D10)   // --carbon-2
    static let carbon3      = Color(hex: 0x0D0D11)   // --carbon-3
    static let carbon4      = Color(hex: 0x101014)   // --carbon-4      card fill
    static let carbon5      = Color(hex: 0x111114)   // --carbon-5
    static let smokeKey     = Color(hex: 0x1B1B20)   // --smoke-key     keyboard key
    static let ledOff       = Color(hex: 0x1A1A1F)   // --led-off
    static let panelInk     = Color(hex: 0x070709)   // AI panel ground
    static let panelWash    = Color(hex: 0x15151A)   // AI panel svg wash
    static let ringTrack    = Color(hex: 0x23232B)   // training ring track
    static let barTrack     = Color(hex: 0x26262E)   // macro bar track
    static let discInk      = Color(hex: 0x1C1C26)   // panel disc

    // MARK: Text
    static let white        = Color(hex: 0xFFFFFF)   // --white
    static let text1        = Color(hex: 0xFFFFFF)                 // --text-1
    static let text2        = Color(hex: 0xFFFFFF, opacity: 0.60)  // --text-2
    // ⚠️ F5 C10 · there is no `text3` here on purpose. --text-3 is white at 42%, which
    // measures 4.06:1 on #0B0B0D — under WCAG AA's 4.5:1 for body text. It exists in the
    // design file as a visual, and the ruling is that code never references it: secondary
    // text is --text-3-prod, and the file already holds that more conservative value rather
    // than a third one being invented. Twenty-two call sites used to read the 42% token.
    static let text3Prod    = Color(hex: 0xFFFFFF, opacity: 0.55)  // --text-3-prod
    static let hairline     = Color(hex: 0xFFFFFF, opacity: 0.08)  // --hairline
    static let macroLabel   = Color(hex: 0xB8B8C0)
    static let macroValue   = Color(hex: 0xB0B0BA)
    static let iconInk      = Color(hex: 0xE8E8EA)

    // MARK: Cyan · Training Load
    static let cyanPale     = Color(hex: 0xCFFAFE)   // --cyan-pale
    static let cyan1        = Color(hex: 0x22D3EE)   // --cyan-1
    static let cyan2        = Color(hex: 0x16A3B8)   // --cyan-2
    static let cyan3        = Color(hex: 0x0E7490)   // --cyan-3
    static let cyanDeep     = Color(hex: 0x155E75)   // --cyan-deep

    // MARK: Blue
    static let bluePale     = Color(hex: 0xBAE6FD)   // --blue-pale
    static let blue1        = Color(hex: 0x38BDF8)   // --blue-1
    static let blue2        = Color(hex: 0x2563EB)   // --blue-2
    static let blue3        = Color(hex: 0x1D4ED8)   // --blue-3
    static let blueDeep     = Color(hex: 0x0B1E3F)   // --blue-deep

    // MARK: Lime · Body Battery + dock
    static let limePale     = Color(hex: 0xD9F99D)   // --lime-pale
    static let limePip      = Color(hex: 0xBEF264)   // --lime-pip
    static let lime1        = Color(hex: 0xEFF65A)   // --lime-1
    static let lime2        = Color(hex: 0xA3E635)   // --lime-2
    static let limeMid      = Color(hex: 0x65A30D)   // --lime-mid
    static let lime3        = Color(hex: 0x4D7C0F)   // --lime-3

    // MARK: Violet
    static let violet1      = Color(hex: 0xA78BFA)   // --violet-1   PRO macro
    static let violet2      = Color(hex: 0x8F9FE8)   // --violet-2
    static let violet3      = Color(hex: 0x6D28D9)   // --violet-3
    static let violet4      = Color(hex: 0x4F46E5)   // --violet-4
    static let violetPink   = Color(hex: 0xD774B4)   // --violet-pink

    // MARK: Ember · Fuel
    static let emberPale    = Color(hex: 0xFFE9B8)   // --ember-pale
    static let ember1       = Color(hex: 0xF6A41C)   // --ember-1
    static let ember2       = Color(hex: 0xE05E10)   // --ember-2
    static let ember3       = Color(hex: 0xC2570C)   // --ember-3
    static let emberDeep    = Color(hex: 0x7C2D12)   // --ember-deep

    // MARK: Run / accents
    static let run1         = Color(hex: 0xFB923C)   // --run-1      FAT macro
    static let run2         = Color(hex: 0xDC2626)   // --run-2
    static let accentYellow = Color(hex: 0xF3E545)   // --accent-yellow
    static let compareAmber = Color(hex: 0xD9A441)   // --compare-amber
    static let filmYellow   = Color(hex: 0xFDE047)   // --film-yellow

    // MARK: States
    static let optimal1     = Color(hex: 0xA7F3D0)   // --state-optimal-1
    static let optimal2     = Color(hex: 0x34D399)   // --state-optimal-2  CARB macro
    static let optimal3     = Color(hex: 0x0F766E)   // --state-optimal-3
    static let steady2      = Color(hex: 0x38BDF8)   // --state-steady-2
    static let caution2     = Color(hex: 0xF6A41C)   // --state-caution-2
    static let alert1       = Color(hex: 0xFECACA)   // --state-alert-1
    static let alert2       = Color(hex: 0xEF4444)   // --state-alert-2
    static let alert3       = Color(hex: 0xB91C1C)   // --state-alert-3

    // MARK: Thermal (heat map)
    static let thermal1     = Color(hex: 0xE84393)   // --thermal-1
    static let thermal2     = Color(hex: 0xF97316)   // --thermal-2
    static let thermal4     = Color(hex: 0xFBBF24)   // --thermal-4

    // MARK: Radii
    enum R {
        static let key: CGFloat   = 9    // --r-key
        static let tile: CGFloat  = 13   // --r-tile
        static let inner: CGFloat = 14   // --r-inner
        static let chip: CGFloat  = 18   // --r-chip
        static let spec: CGFloat  = 22   // --r-spec
        static let mat: CGFloat   = 24   // --r-mat
        static let card: CGFloat  = 26   // --r-card
        static let aura: CGFloat  = 28   // --r-aura
        static let hero: CGFloat  = 30   // --r-hero
        static let phone: CGFloat = 34   // --r-phone
        static let panel: CGFloat = 40   // --r-panel
        static let pill: CGFloat  = 999  // --r-pill
    }

    // MARK: Spacing
    enum S {
        static let s1: CGFloat = 3,  s2: CGFloat = 4,  s3: CGFloat = 6
        static let s4: CGFloat = 7,  s5: CGFloat = 8,  s6: CGFloat = 10
        static let s7: CGFloat = 12, s8: CGFloat = 14, s9: CGFloat = 16
        static let s10: CGFloat = 18, s11: CGFloat = 22, s12: CGFloat = 26
        static let s13: CGFloat = 28, s14: CGFloat = 34, s15: CGFloat = 40
        static let s16: CGFloat = 52, s17: CGFloat = 74
        static let padGlass: CGFloat = 20
    }

    // MARK: Fixed layout constants the boards write down as law
    enum Layout {
        static let screenWidth: CGFloat = 390
        static let gutter: CGFloat = 16          // 390 - 358 = 32 → 16 each side
        static let contentWidth: CGFloat = 358
        static let panelHeight: CGFloat = 470    // F0/04: 390 → 470 after the strip shrank
        static let stripHeight: CGFloat = 136
        static let cardWidth: CGFloat = 174
        static let cardGap: CGFloat = 10
        static let dockHeight: CGFloat = 56
        static let dockSideButton: CGFloat = 54
    }
}
