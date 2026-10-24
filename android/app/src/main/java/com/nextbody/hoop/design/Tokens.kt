package com.nextbody.hoop.design

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// Generated 1:1 from the Paper design tokens of NEXTBODY-NEXTBODY · page "新版设计".
// One concept, one name (F0 rule 01). Never hard-code a hex outside this file.
fun hex(hex: Long, opacity: Float = 1f): Color = Color(
    red = ((hex shr 16) and 0xFF).toInt(),
    green = ((hex shr 8) and 0xFF).toInt(),
    blue = (hex and 0xFF).toInt(),
    alpha = (opacity * 255).toInt().coerceIn(0, 255),
)

/** Design tokens. Names mirror the CSS custom properties in the Paper file. */
object NB {
    // MARK: Carbon / surfaces
    val carbon = hex(0x0B0B0D)        // --carbon        app ground
    val carbonDeep = hex(0x0A0A0C)    // --carbon-deep
    val carbon2 = hex(0x0D0D10)       // --carbon-2
    val carbon3 = hex(0x0D0D11)       // --carbon-3
    val carbon4 = hex(0x101014)       // --carbon-4      card fill
    val carbon5 = hex(0x111114)       // --carbon-5
    val smokeKey = hex(0x1B1B20)      // --smoke-key     keyboard key
    val ledOff = hex(0x1A1A1F)        // --led-off
    val panelInk = hex(0x070709)      // AI panel ground
    val panelWash = hex(0x15151A)     // AI panel svg wash
    val ringTrack = hex(0x23232B)     // training ring track
    val barTrack = hex(0x26262E)      // macro bar track
    val discInk = hex(0x1C1C26)       // panel disc

    // MARK: Text
    val white = hex(0xFFFFFF)                 // --white
    val text1 = hex(0xFFFFFF)                 // --text-1
    val text2 = hex(0xFFFFFF, 0.60f)          // --text-2
    // ⚠️ F5 C10 · there is no `text3` here on purpose. --text-3 is white at 42%, which
    // measures 4.06:1 on #0B0B0D — under WCAG AA's 4.5:1 for body text. Secondary text is
    // --text-3-prod.
    val text3Prod = hex(0xFFFFFF, 0.55f)      // --text-3-prod
    val hairline = hex(0xFFFFFF, 0.08f)       // --hairline
    val macroLabel = hex(0xB8B8C0)
    val macroValue = hex(0xB0B0BA)
    val iconInk = hex(0xE8E8EA)

    // MARK: Cyan · Training Load
    val cyanPale = hex(0xCFFAFE)
    val cyan1 = hex(0x22D3EE)
    val cyan2 = hex(0x16A3B8)
    val cyan3 = hex(0x0E7490)
    val cyanDeep = hex(0x155E75)

    // MARK: Blue
    val bluePale = hex(0xBAE6FD)
    val blue1 = hex(0x38BDF8)
    val blue2 = hex(0x2563EB)
    val blue3 = hex(0x1D4ED8)
    val blueDeep = hex(0x0B1E3F)

    // MARK: Lime · Body Battery + dock
    val limePale = hex(0xD9F99D)
    val limePip = hex(0xBEF264)
    val lime1 = hex(0xEFF65A)
    val lime2 = hex(0xA3E635)
    val limeMid = hex(0x65A30D)
    val lime3 = hex(0x4D7C0F)

    // MARK: Violet
    val violet1 = hex(0xA78BFA)     // PRO macro
    val violet2 = hex(0x8F9FE8)
    val violet3 = hex(0x6D28D9)
    val violet4 = hex(0x4F46E5)
    val violetPink = hex(0xD774B4)

    // MARK: Ember · Fuel
    val emberPale = hex(0xFFE9B8)
    val ember1 = hex(0xF6A41C)
    val ember2 = hex(0xE05E10)
    val ember3 = hex(0xC2570C)
    val emberDeep = hex(0x7C2D12)

    // MARK: Run / accents
    val run1 = hex(0xFB923C)        // FAT macro
    val run2 = hex(0xDC2626)
    val accentYellow = hex(0xF3E545)
    val compareAmber = hex(0xD9A441)
    val filmYellow = hex(0xFDE047)

    // MARK: States
    val optimal1 = hex(0xA7F3D0)
    val optimal2 = hex(0x34D399)    // CARB macro
    val optimal3 = hex(0x0F766E)
    val steady2 = hex(0x38BDF8)
    val caution2 = hex(0xF6A41C)
    val alert1 = hex(0xFECACA)
    val alert2 = hex(0xEF4444)
    val alert3 = hex(0xB91C1C)

    // MARK: Thermal (heat map)
    val thermal1 = hex(0xE84393)
    val thermal2 = hex(0xF97316)
    val thermal4 = hex(0xFBBF24)

    /** Radii (pt on iOS → dp here). */
    object R {
        val key: Dp = 9.dp
        val tile: Dp = 13.dp
        val inner: Dp = 14.dp
        val chip: Dp = 18.dp
        val spec: Dp = 22.dp
        val mat: Dp = 24.dp
        val card: Dp = 26.dp
        val aura: Dp = 28.dp
        val hero: Dp = 30.dp
        val phone: Dp = 34.dp
        val panel: Dp = 40.dp
        val pill: Dp = 999.dp
    }

    /** Spacing. */
    object S {
        val s1 = 3.dp; val s2 = 4.dp; val s3 = 6.dp
        val s4 = 7.dp; val s5 = 8.dp; val s6 = 10.dp
        val s7 = 12.dp; val s8 = 14.dp; val s9 = 16.dp
        val s10 = 18.dp; val s11 = 22.dp; val s12 = 26.dp
        val s13 = 28.dp; val s14 = 34.dp; val s15 = 40.dp
        val s16 = 52.dp; val s17 = 74.dp
        val padGlass = 20.dp
    }

    /**
     * Layout. The boards are drawn at 390 × 844 with a 358 column; the phone is whatever it
     * is. Widths derive from the device, so every content width fills the same 16dp gutters.
     */
    object Layout {
        /** the board's own width; the reference frame for absolute board coordinates */
        const val boardWidth = 390f
        const val boardContentWidth = 358f
        val screenWidth: Dp get() = ScreenMetrics.width
        val screenHeight: Dp get() = ScreenMetrics.height
        val gutter: Dp = 16.dp
        val contentWidth: Dp get() = screenWidth - gutter * 2
        /** How far a card's fill reaches into the gutter. */
        val cardBleed: Dp = 12.dp
        val panelHeight: Dp = 470.dp
        val stripHeight: Dp = 136.dp
        val cardWidth: Dp get() = (contentWidth - cardGap) / 2
        val cardGap: Dp = 10.dp
        val dockHeight: Dp = 56.dp
        val dockSideButton: Dp = 54.dp
    }
}

/** Device size in dp, refreshed by the root on every configuration. */
object ScreenMetrics {
    var width: Dp by mutableStateOf(390.dp)
    var height: Dp by mutableStateOf(844.dp)
    var safeTop: Dp by mutableStateOf(47.dp)
    var safeBottom: Dp by mutableStateOf(34.dp)
}
