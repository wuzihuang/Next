package com.nextbody.hoop.features.home

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import com.nextbody.hoop.design.NB

/**
 * The panel is printed, not lit: every pixel of art is punched through a 4dp dot screen,
 * and the space between dots is the panel's own ink. Reproduces the SVG `<pattern>` the
 * board uses on 04 · 07 · 13.
 *
 * ⚠️ Performance. The screen is rasterised once, as an ink sheet with holes punched in it,
 * and laid over the art as a plain image: a single bitmap composite per frame, never a mask
 * that re-rasterises the whole subtree every frame the art moves.
 */
@Composable
fun HalftoneScreen(
    modifier: Modifier = Modifier,
    pitch: Float = 4f,
    radius: Float = 1.6f,
    ink: Color = NB.panelInk,
    content: @Composable BoxScope.() -> Unit,
) {
    val density = LocalDensity.current.density
    val config = LocalConfiguration.current
    Box(modifier.clipToBounds().background(ink)) {
        content()
        // The sheet is cut at the screen's own size and pinned top-leading, so a panel of any
        // size — including one whose frame is mid-fold — sees exactly the grid a mask of its
        // own size would have given it.
        val sheet = DotScreen.sheet(pitch, radius, ink, density,
            (config.screenWidthDp * density).toInt(), (config.screenHeightDp * density).toInt() + 400)
        Canvas(Modifier.fillMaxSize()) { drawImage(sheet) }
    }
}

/** One rasterised ink sheet per (pitch, radius, ink) for the life of the process. */
private object DotScreen {
    private data class Key(val pitch: Float, val radius: Float, val ink: Int, val w: Int, val h: Int, val d: Float)
    private val cache = HashMap<Key, ImageBitmap>()

    fun sheet(pitch: Float, radius: Float, ink: Color, density: Float, w: Int, h: Int): ImageBitmap {
        val key = Key(pitch, radius, ink.toArgb(), w, h, density)
        cache[key]?.let { return it }
        val bitmap = Bitmap.createBitmap(maxOf(1, w), maxOf(1, h), Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        canvas.drawColor(ink.toArgb())
        // Holes, not white dots: clearing through the ink is what lets the art show.
        val clear = Paint(Paint.ANTI_ALIAS_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR) }
        val p = pitch * density
        val r = radius * density
        var y = p / 2
        while (y < h + p) {
            var x = p / 2
            while (x < w + p) {
                canvas.drawCircle(x, y, r, clear)
                x += p
            }
            y += p
        }
        val image = bitmap.asImageBitmap()
        cache[key] = image
        return image
    }
}
