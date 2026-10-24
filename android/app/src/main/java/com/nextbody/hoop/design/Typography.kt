package com.nextbody.hoop.design

import android.content.Context
import android.graphics.Typeface
import android.graphics.fonts.Font
import android.os.Build
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.nextbody.hoop.R

/**
 * The three families the design file loads: Jost (UI), Inter Tight (brand), Doto (dot-matrix
 * numerals). Fusion Pixel (12px proportional zh_hans) is the primary face for UI/brand copy in
 * every language; the Latin cut is its fallback. Doto keeps the dot-matrix grid it was picked
 * for and falls back to Fusion Pixel only for glyphs it lacks.
 */
object NBFont {
    enum class Family { UI, BRAND, DOT }

    private var appContext: Context? = null
    private val cache = HashMap<String, FontFamily>()

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    /** CSS weight → the static instance shipped in res/font. */
    private fun res(weight: Int, family: Family): Int {
        return when (family) {
            Family.DOT -> when {
                weight < 450 -> R.font.doto_regular
                weight < 550 -> R.font.doto_medium
                weight < 650 -> R.font.doto_semi_bold
                weight < 750 -> R.font.doto_bold
                weight < 850 -> R.font.doto_extra_bold
                else -> R.font.doto_black
            }
            Family.UI -> when {
                weight < 250 -> R.font.jost_extra_light
                weight < 350 -> R.font.jost_light
                weight < 450 -> R.font.jost_regular
                weight < 550 -> R.font.jost_medium
                weight < 650 -> R.font.jost_semi_bold
                else -> R.font.jost_bold
            }
            Family.BRAND -> when {
                weight < 350 -> R.font.inter_tight_light
                weight < 450 -> R.font.inter_tight_regular
                weight < 550 -> R.font.inter_tight_medium
                weight < 650 -> R.font.inter_tight_semi_bold
                weight < 750 -> R.font.inter_tight_bold
                weight < 850 -> R.font.inter_tight_extra_bold
                else -> R.font.inter_tight_black
            }
        }
    }

    fun family(family: Family, weight: Int): FontFamily {
        val latin = res(weight, family)
        val key = "$family-$latin"
        cache[key]?.let { return it }
        val ctx = appContext ?: return FontFamily.Default
        val primary = if (family == Family.DOT) latin else R.font.fusion_pixel_12px_proportional_zh_hans
        val fallback = if (family == Family.DOT) R.font.fusion_pixel_12px_proportional_zh_hans else latin
        val built = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val p = android.graphics.fonts.FontFamily.Builder(Font.Builder(ctx.resources, primary).build()).build()
                val f = android.graphics.fonts.FontFamily.Builder(Font.Builder(ctx.resources, fallback).build()).build()
                val tf = Typeface.CustomFallbackBuilder(p).addCustomFallback(f).build()
                FontFamily(tf)
            } else {
                FontFamily(androidx.compose.ui.text.font.Font(primary))
            }
        }.getOrElse { FontFamily.Default }
        cache[key] = built
        return built
    }

    fun ui(weight: Int, size: Float): TextStyle = named(Family.UI, weight, size)
    fun brand(weight: Int, size: Float): TextStyle = named(Family.BRAND, weight, size)
    fun dot(weight: Int, size: Float): TextStyle = named(Family.DOT, weight, size)

    fun named(family: Family, weight: Int, size: Float): TextStyle = TextStyle(
        fontFamily = family(family, weight),
        fontSize = size.sp,
        lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
    )

    /** The system status-bar clock is the system face, not Jost. */
    fun system(size: Float): TextStyle = TextStyle(fontFamily = FontFamily.Default, fontSize = size.sp)
}

/** Paper writes tracking in em. */
fun TextStyle.tracking(em: Float): TextStyle = copy(letterSpacing = em.em)

fun TextStyle.color(c: Color): TextStyle = copy(color = c)

/** One text style = one call, so a spec change is a one-line change (F0 rule 02). */
@Composable
fun NBText(
    text: String,
    modifier: Modifier = Modifier,
    family: NBFont.Family = NBFont.Family.UI,
    weight: Int = 500,
    size: Float = 11f,
    tracking: Float = 0f,
    color: Color = NB.text1,
    lineHeightPx: Dp? = null,
    align: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
) {
    Text(
        text = text,
        modifier = if (lineHeightPx != null) modifier.heightIn(min = lineHeightPx) else modifier,
        style = NBFont.named(family, weight, size).copy(letterSpacing = tracking.em, color = color),
        textAlign = align,
        maxLines = maxLines,
    )
}

