package com.nextbody.hoop.features.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.hotZoneTap
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** Halftone planet used on the home screen. One canvas, no per-frame rebuild. */
@Composable
fun DottedSphere(tint: Color, modifier: Modifier = Modifier, pitch: Float = 3.4f) {
    Canvas(modifier.clearAndSetSemantics { }) {
        val d = density
        val radius = min(size.width, size.height) / 2
        if (radius <= 2 * d) return@Canvas
        val cx = size.width / 2
        val cy = size.height / 2
        val step = pitch * d
        var y = cy - radius
        while (y <= cy + radius) {
            var x = cx - radius
            while (x <= cx + radius) {
                val dx = (x - cx) / radius
                val dy = (y - cy) / radius
                val flat = dx * dx + dy * dy
                if (flat <= 1) {
                    val z = sqrt(1 - flat)
                    val light = max(0.08f, 0.12f + 0.9f * (-0.25f * dx - 0.35f * dy + 0.75f * z))
                    drawCircle(tint.copy(alpha = (tint.alpha * light).coerceIn(0f, 1f)), 0.7f * d, Offset(x, y))
                }
                x += step
            }
            y += step
        }
    }
}

/** Standing figure. The four glows are state, not buttons — the hit targets sit above this. */
@Composable
fun BodyFigure(head: Double, heart: Double, gut: Double, legs: Double, modifier: Modifier = Modifier) {
    Canvas(modifier.clearAndSetSemantics { }) {
        val w = size.width
        val h = size.height
        fun glow(cx: Float, cy: Float, r: Float, amount: Double, color: Color) {
            if (amount <= 0.05) return
            drawCircle(color.copy(alpha = (0.22 * amount).toFloat()), r, Offset(cx, cy))
            drawCircle(color.copy(alpha = (0.55 * amount).toFloat()), r * 0.55f, Offset(cx, cy))
        }
        glow(w * 0.50f, h * 0.11f, w * 0.16f, head, hex(0xF6C56A))
        glow(w * 0.55f, h * 0.30f, w * 0.14f, heart, NB.lime1)
        glow(w * 0.50f, h * 0.46f, w * 0.16f, gut, hex(0xE25B4A))
        glow(w * 0.46f, h * 0.74f, w * 0.16f, legs, NB.cyan1)

        val dots = ArrayList<Offset>()
        fun ring(cx: Float, cy: Float, rx: Float, ry: Float, count: Int) {
            for (i in 0 until count) {
                val t = i.toDouble() / count * PI * 2
                dots.add(Offset(cx + cos(t).toFloat() * rx, cy + sin(t).toFloat() * ry))
            }
        }
        fun limb(a: Offset, b: Offset, count: Int) {
            for (i in 0..count) {
                val t = i.toFloat() / count
                dots.add(Offset(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
            }
        }
        ring(w * 0.50f, h * 0.11f, w * 0.09f, h * 0.055f, 28)
        ring(w * 0.50f, h * 0.36f, w * 0.16f, h * 0.13f, 42)
        ring(w * 0.50f, h * 0.56f, w * 0.11f, h * 0.07f, 24)
        limb(Offset(w * 0.36f, h * 0.28f), Offset(w * 0.18f, h * 0.48f), 14)
        limb(Offset(w * 0.64f, h * 0.28f), Offset(w * 0.82f, h * 0.48f), 14)
        limb(Offset(w * 0.42f, h * 0.62f), Offset(w * 0.36f, h * 0.92f), 18)
        limb(Offset(w * 0.58f, h * 0.62f), Offset(w * 0.64f, h * 0.92f), 18)
        for (dot in dots) drawCircle(NB.white.copy(alpha = 0.82f), 1.1f * density, dot)
    }
}

@Composable
fun HomeMacroTrack(eaten: Int?, target: Int?, tint: Color, modifier: Modifier = Modifier) {
    val fraction = if (eaten != null && target != null && target > 0) min(1f, eaten.toFloat() / target) else 0f
    BoxWithConstraints(modifier.fillMaxWidth().height(3.dp)) {
        Box(Modifier.fillMaxWidth().height(3.dp).background(NB.barTrack, CircleShape))
        Box(Modifier.width(maxWidth * fraction).height(3.dp).background(tint, CircleShape))
    }
}

/** 0 is the body, 1 the planet, 2 the instruments. Follows the finger. */
@Composable
fun HomePageDots(progress: Float, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val slot = 18.dp
    val gap = 8.dp
    val place = min(2f, max(0f, progress))
    Box(modifier.fillMaxWidth().height(36.dp), contentAlignment = Alignment.Center) {
        Box {
            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                repeat(3) {
                    Box(Modifier.size(slot, 4.dp).background(Color.White.copy(alpha = 0.22f), CircleShape))
                }
            }
            Box(
                Modifier
                    .offset(x = (slot + gap) * place)
                    .size(slot, 4.dp)
                    .background(Color.White.copy(alpha = 0.92f), CircleShape),
            )
        }
        Row {
            repeat(3) { index ->
                val label = L("Page %d of 3", index + 1)
                Box(
                    Modifier
                        .size(36.dp)
                        .semantics { contentDescription = label }
                        .hotZoneTap(pressedOpacity = 1f, pressedScale = 1f) { onSelect(index) },
                )
            }
        }
    }
}

val HomeV2Model.BodyMetric.Tint.color: Color
    get() = when (this) {
        HomeV2Model.BodyMetric.Tint.lime -> NB.lime1
        HomeV2Model.BodyMetric.Tint.violet -> NB.violet1
        HomeV2Model.BodyMetric.Tint.ember -> NB.ember1
        HomeV2Model.BodyMetric.Tint.cyan -> NB.cyan1
        HomeV2Model.BodyMetric.Tint.white -> NB.white
    }

/**
 * Shared status ramp. The last two stops are distinct orange and orange-red,
 * reserving pure alert red for explicit alerts elsewhere in the app.
 */
val HomeV2Model.BodyStatus.color: Color
    get() = when (this) {
        HomeV2Model.BodyStatus.dim -> NB.white
        HomeV2Model.BodyStatus.good -> NB.optimal2
        HomeV2Model.BodyStatus.ok -> NB.lime2
        HomeV2Model.BodyStatus.watch -> NB.filmYellow
        HomeV2Model.BodyStatus.poor -> NB.ember1
        HomeV2Model.BodyStatus.bad -> NB.ember2
    }

