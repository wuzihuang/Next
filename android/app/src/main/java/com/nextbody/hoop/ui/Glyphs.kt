package com.nextbody.hoop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.hex

// All glyphs are drawn in a 24-unit viewBox scaled to the frame.

/** Path builder in viewBox units. */
private class VB(private val s: Float) {
    val path = Path()
    fun m(x: Float, y: Float) = path.moveTo(x * s, y * s)
    fun l(x: Float, y: Float) = path.lineTo(x * s, y * s)
    /** SwiftUI order: end point, then control1, control2. */
    fun c(x: Float, y: Float, c1x: Float, c1y: Float, c2x: Float, c2y: Float) =
        path.cubicTo(c1x * s, c1y * s, c2x * s, c2y * s, x * s, y * s)
    fun z() = path.close()
}

@Composable
fun AppleGlyph(color: Color = NB.carbon, size: Dp = 19.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val s = this.size.width / 24f
        val body = VB(s).apply {
            m(17.05f, 12.54f)
            c(19.0f, 9.10f, 17.03f, 10.25f, 18.92f, 9.15f)
            c(15.70f, 7.31f, 17.94f, 7.55f, 16.29f, 7.33f)
            c(12.25f, 8.14f, 14.30f, 7.17f, 12.96f, 8.14f)
            c(9.27f, 7.35f, 11.54f, 8.14f, 10.44f, 7.33f)
            c(5.54f, 9.61f, 7.74f, 7.37f, 6.33f, 8.24f)
            c(6.68f, 18.69f, 3.95f, 12.37f, 5.13f, 16.45f)
            c(9.53f, 20.97f, 7.44f, 19.79f, 8.34f, 21.02f)
            c(12.48f, 20.23f, 10.67f, 20.92f, 11.10f, 20.23f)
            c(15.46f, 20.95f, 13.86f, 20.23f, 14.25f, 20.97f)
            c(18.22f, 18.73f, 16.69f, 20.93f, 17.47f, 19.83f)
            c(19.47f, 16.16f, 19.09f, 17.46f, 19.45f, 16.23f)
            c(17.05f, 12.54f, 19.44f, 16.15f, 17.07f, 15.24f)
            z()
        }
        drawPath(body.path, color)
        val leaf = VB(s).apply {
            m(14.79f, 5.60f)
            c(15.73f, 2.72f, 15.42f, 4.84f, 15.84f, 3.78f)
            c(13.07f, 4.08f, 14.82f, 2.76f, 13.72f, 3.32f)
            c(12.12f, 6.86f, 12.49f, 4.75f, 11.98f, 5.83f)
            c(14.79f, 5.60f, 13.13f, 6.94f, 14.16f, 6.35f)
            z()
        }
        drawPath(leaf.path, color)
    }
}

@Composable
fun GoogleGlyph(size: Dp = 18.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val s = this.size.width / 24f
        // blue
        drawPath(VB(s).apply {
            m(22.56f, 12.25f); l(22.36f, 10.00f); l(12f, 10.00f); l(12f, 14.26f); l(17.92f, 14.26f)
            c(15.72f, 17.58f, 17.66f, 15.63f, 16.86f, 16.80f)
            l(15.72f, 20.34f); l(19.29f, 20.34f)
            c(22.56f, 12.25f, 21.37f, 18.42f, 22.56f, 15.60f)
            z()
        }.path, hex(0x4285F4))
        // green
        drawPath(VB(s).apply {
            m(12f, 23f)
            c(19.28f, 20.34f, 14.97f, 23f, 17.46f, 22.02f)
            l(15.71f, 17.58f)
            c(5.84f, 14.11f, 13.5f, 19.5f, 7.5f, 18.1f)
            l(2.18f, 16.95f)
            c(12f, 23f, 4f, 20.5f, 8f, 23f)
            z()
        }.path, hex(0x34A853))
        // yellow
        drawPath(VB(s).apply {
            m(5.84f, 14.11f)
            c(5.84f, 9.89f, 5.35f, 12.7f, 5.35f, 11.3f)
            l(2.18f, 7.05f)
            c(2.18f, 16.95f, 0.6f, 10.2f, 0.6f, 13.8f)
            z()
        }.path, hex(0xFBBC05))
        // red
        drawPath(VB(s).apply {
            m(12f, 5.38f)
            c(16.21f, 7.02f, 13.62f, 5.38f, 15.06f, 5.94f)
            l(19.36f, 3.87f)
            c(12f, 1f, 17.45f, 2.09f, 14.97f, 1f)
            c(2.18f, 7.05f, 8f, 1f, 4f, 3.5f)
            l(5.84f, 9.89f)
            c(12f, 5.38f, 6.71f, 7.29f, 9.14f, 5.38f)
            z()
        }.path, hex(0xEA4335))
    }
}

@Composable
fun EnvelopeGlyph(color: Color = NB.lime1, size: Dp = 18.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val s = this.size.width / 24f
        val stroke = 1.6f * s
        drawRoundRect(
            color,
            topLeft = Offset(2.75f * s, 5.25f * s),
            size = Size(18.5f * s, 13.5f * s),
            cornerRadius = CornerRadius(3f * s, 3f * s),
            style = Stroke(stroke),
        )
        val flap = VB(s).apply { m(4f, 8.5f); l(12f, 13.2f); l(20f, 8.5f) }
        drawPath(flap.path, color, style = Stroke(stroke, cap = StrokeCap.Round))
    }
}

@Composable
fun ArrowGlyph(color: Color = NB.carbon, size: Dp = 16.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val s = this.size.width / 24f
        val p = VB(s).apply { m(5f, 12f); l(19f, 12f); m(13f, 6f); l(19f, 12f); l(13f, 18f) }
        drawPath(p.path, color, style = Stroke(1.9f * s, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

@Composable
fun ChevronGlyph(color: Color = NB.white.copy(alpha = 0.8f), size: Dp = 18.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val s = this.size.width / 24f
        val p = VB(s).apply { m(14.5f, 5f); l(7.5f, 12f); l(14.5f, 19f) }
        drawPath(p.path, color, style = Stroke(1.7f * s, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

@Composable
fun BackspaceGlyph(size: Dp = 24.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val s = this.size.width / 24f
        val ink = NB.white.copy(alpha = 0.55f)
        val body = VB(s).apply {
            m(8.2f, 5.5f); l(20f, 5.5f); l(21.5f, 7f); l(21.5f, 17f); l(20f, 18.5f); l(8.2f, 18.5f); l(2.8f, 12f); z()
        }
        drawPath(body.path, ink, style = Stroke(1.5f * s))
        val x = VB(s).apply { m(11.5f, 9.8f); l(16.5f, 14.2f); m(16.5f, 9.8f); l(11.5f, 14.2f) }
        drawPath(x.path, ink, style = Stroke(1.5f * s, cap = StrokeCap.Round))
    }
}
