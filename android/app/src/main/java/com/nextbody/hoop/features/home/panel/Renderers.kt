package com.nextbody.hoop.features.home.panel

import android.graphics.BlurMaskFilter
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.SwiftEaseOut
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// 07 · 09 · B — the renderers cover all the types. Each one only eats the chart keys it is given.
// Every renderer fills the size its caller gives it (Swift: `.frame(height: h)` on the call site).

/** SwiftUI's `.onAppear { withAnimation(.easeOut(duration:)) { x = 1 } }`, nil under Reduce Motion. */
@Composable
internal fun rememberAppearProgress(durationMs: Int): Animatable<Float, *> {
    val reduce = rememberReduceMotion()
    val a = remember { Animatable(if (reduce) 1f else 0f) }
    LaunchedEffect(Unit) { if (!reduce) a.animateTo(1f, tween(durationMs, easing = SwiftEaseOut)) }
    return a
}

/** `.shadow(color:radius:)` under a stroked path: a blurred copy of the stroke drawn first. */
internal fun DrawScope.glowStroke(path: Path, color: Color, width: Float, blur: Float, glow: Float,
                                  cap: StrokeCap = StrokeCap.Round) {
    if (blur > 0f && glow > 0f) {
        drawIntoCanvas { canvas ->
            val paint = Paint().asFrameworkPaint().apply {
                isAntiAlias = true
                style = android.graphics.Paint.Style.STROKE
                strokeWidth = width
                strokeCap = if (cap == StrokeCap.Round) android.graphics.Paint.Cap.ROUND else android.graphics.Paint.Cap.BUTT
                strokeJoin = android.graphics.Paint.Join.ROUND
                this.color = color.copy(alpha = color.alpha * glow).toArgb()
                maskFilter = BlurMaskFilter(blur, BlurMaskFilter.Blur.NORMAL)
            }
            canvas.nativeCanvas.drawPath(path.asAndroidPathCompat(), paint)
        }
    }
    drawPath(path, color, style = Stroke(width = width, cap = cap, join = StrokeJoin.Round))
}

private fun Path.asAndroidPathCompat(): android.graphics.Path =
    (this as androidx.compose.ui.graphics.AndroidPath).internalPath

/** `.trim(from: 0, to: t)` of a polyline. */
private fun trimmed(path: Path, t: Float): Path {
    if (t >= 1f) return path
    val out = Path()
    if (t <= 0f) return out
    val m = PathMeasure()
    m.setPath(path, false)
    m.getSegment(0f, m.length * t, out, true)
    return out
}

private fun polyline(p: List<Offset>): Path = Path().apply {
    val f = p.firstOrNull() ?: return@apply
    moveTo(f.x, f.y)
    p.drop(1).forEach { lineTo(it.x, it.y) }
}

/**
 * curve · line · o2night · dual. Line, gradient fill, glow, dot.
 * [splitAt] / [accent2]: 13 col 01 · 「the night in violet, the day so far in lime」.
 * [led]: drawn behind the dot screen — the stroke is wider than one pitch, no fill, no glow.
 * [mark]: a horizontal threshold that joins the vertical scale. [marks]: hairlines at indices.
 */
@Composable
fun CurveRenderer(
    values: List<Double>,
    accent: Color,
    fill: Boolean = true,
    glow: Double = 0.35,
    dot: Boolean = true,
    splitAt: Int? = null,
    accent2: Color? = null,
    led: Boolean = false,
    mark: Double? = null,
    marks: List<Int> = emptyList(),
    modifier: Modifier = Modifier,
) {
    val draw = rememberAppearProgress(900)
    Canvas(modifier.fillMaxSize()) {
        val d = density
        val stroke = (if (led) 6f else 2f) * d
        val blur = (if (led) 0f else 6f) * d
        val all = values + listOfNotNull(mark)
        val lo = all.minOrNull() ?: 0.0
        val hi = all.maxOrNull() ?: 1.0
        val span = max(hi - lo, 0.0001)
        fun y(v: Double): Float = size.height * (1 - ((v - lo) / span).toFloat()) * 0.86f + size.height * 0.07f
        val pts = if (values.size > 1) values.mapIndexed { i, v ->
            Offset(size.width * i / (values.size - 1), y(v))
        } else emptyList()
        val t = draw.value
        if (fill && !led && pts.size > 1) {
            val area = polyline(pts).apply {
                lineTo(pts.last().x, size.height); lineTo(pts.first().x, size.height); close()
            }
            val b = area.getBounds()
            drawPath(area, Brush.verticalGradient(listOf(accent.copy(alpha = 0.40f), accent.copy(alpha = 0f)),
                startY = b.top, endY = b.bottom), alpha = t)
        }
        val k = splitAt
        if (k != null && accent2 != null && k >= 0 && k < pts.size - 1) {
            glowStroke(trimmed(polyline(pts.subList(0, k + 1)), t), accent, stroke, blur, glow.toFloat())
            glowStroke(trimmed(polyline(pts.subList(k, pts.size)), t), accent2, stroke, blur, glow.toFloat())
        } else {
            glowStroke(trimmed(polyline(pts), t), accent, stroke, blur, glow.toFloat())
        }
        if (mark != null && values.size > 1) {
            val my = y(mark)
            drawLine(accent.copy(alpha = if (led) 0.55f else 0.35f), Offset(0f, my), Offset(size.width, my),
                strokeWidth = (if (led) 3f else 1f) * d,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4 * d, 4 * d)))
        }
        for (i in marks.filter { it >= 0 && it < pts.size }) {
            drawLine(NB.white.copy(alpha = if (led) 0.30f else 0.22f), Offset(pts[i].x, 0f), Offset(pts[i].x, size.height),
                strokeWidth = (if (led) 3f else 1f) * d)
        }
        val last = pts.lastOrNull()
        if (dot && last != null && t == 1f) {
            drawCircle(accent2 ?: accent, radius = (if (led) 5f else 2.5f) * d, center = last)
        }
    }
}

/** pair · band. A hi/lo envelope with the band between them filled. */
@Composable
fun PairRenderer(hi: List<Double>, lo: List<Double>, accent: Color, led: Boolean = false, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val all = hi + lo
        val mn = all.minOrNull() ?: 0.0
        val span = max((all.maxOrNull() ?: 1.0) - mn, 0.0001)
        fun map(vs: List<Double>) = vs.mapIndexed { i, v ->
            Offset(size.width * i / max(vs.size - 1, 1), size.height * (1 - ((v - mn) / span).toFloat()) * 0.9f + size.height * 0.05f)
        }
        val h = map(hi)
        val l = map(lo)
        if (h.isNotEmpty()) {
            val band = polyline(h).apply { l.reversed().forEach { lineTo(it.x, it.y) }; close() }
            drawPath(band, accent.copy(alpha = 0.18f))
        }
        listOf(h, l).forEachIndexed { i, s ->
            if (s.isEmpty()) return@forEachIndexed
            drawPath(polyline(s), accent.copy(alpha = if (i == 0) 1f else 0.6f),
                style = Stroke(width = (if (led) 5f else 1.6f) * density))
        }
    }
}

/** dual · two series, each normalised to its own range — "two scales, one panel — read the
 *  shape, not the gap". No fill, because a fill would say the gap means something. */
@Composable
fun DualRenderer(a: List<Double>, b: List<Double>, accent: Color, secondary: Color, led: Boolean = false, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize()) {
        CurveRenderer(values = b, accent = secondary, fill = false, glow = 0.15, dot = false, led = led)
        CurveRenderer(values = a, accent = accent, fill = false, glow = 0.35, dot = true, led = led)
    }
}

/** column · bars · days · delta. delta uses the zero-axis variant. The bars go behind the dot
 *  screen and the labels in front of it; the catalogue draws both at once. */
@Composable
fun ColumnRenderer(
    bins: List<Pair<String, Double>>,
    accent: Color,
    zeroAxis: Boolean = false,
    showBars: Boolean = true,
    showLabels: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val grown = rememberAppearProgress(700)
    BoxWithConstraints(modifier.fillMaxSize()) {
        val n = max(bins.size, 1)
        val gap = 4.dp
        val w = (maxWidth - gap * (n - 1)) / n
        if (showBars) {
            Canvas(Modifier.fillMaxSize()) {
                val d = density
                val mx = max(bins.maxOfOrNull { abs(it.second) } ?: 1.0, 0.0001)
                val axisY = if (zeroAxis) size.height / 2 else size.height - 14 * d
                if (zeroAxis) drawRect(NB.white.copy(alpha = 0.10f), Offset(0f, axisY), Size(size.width, 1 * d))
                val wp = w.toPx()
                bins.forEachIndexed { i, (_, v) ->
                    val h = (abs(v) / mx).toFloat() * (if (zeroAxis) size.height / 2 - 8 * d else size.height - 22 * d) * grown.value
                    val bh = max(h, 1 * d)
                    val neg = v < 0 && zeroAxis
                    drawRoundRect(if (neg) NB.alert2 else accent,
                        topLeft = Offset(i * (wp + 4 * d), if (neg) axisY else axisY - h),
                        size = Size(wp, bh), cornerRadius = CornerRadius(2 * d))
                }
            }
        }
        if (showLabels) {
            bins.forEachIndexed { i, (label, _) ->
                BasicText(label, Modifier.offset(x = (w + gap) * i, y = maxHeight - 12.dp).width(w),
                    style = NBFont.dot(500, 9f).tracking(0.12f).copy(color = NB.white.copy(alpha = 0.32f), textAlign = TextAlign.Center),
                    maxLines = 1)
            }
        }
    }
}

/** `RingArc(from:to:)` — an arc of the inscribed circle starting at 12 o'clock, clockwise. */
internal fun DrawScope.ringArc(from: Double, to: Double, color: Color, width: Float, cap: StrokeCap,
                               inset: Float = 0f, rotation: Float = 0f) {
    if (to <= from) return
    val r = min(size.width, size.height) / 2 - inset
    val c = center
    rotate(rotation, c) {
        drawArc(color, startAngle = (360 * from - 90).toFloat(), sweepAngle = (360 * (to - from)).toFloat(),
            useCenter = false, topLeft = Offset(c.x - r, c.y - r), size = Size(2 * r, 2 * r),
            style = Stroke(width = width, cap = cap))
    }
}

/** arc · ring · gauge · battery. */
@Composable
fun ArcRenderer(fraction: Double, accent: Color, label: String, showLabel: Boolean = true, modifier: Modifier = Modifier) {
    val shown = rememberAppearProgress(900)
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val d = density
            val r = min(size.width, size.height) / 2 - 5 * d
            drawCircle(NB.barTrack, radius = r, style = Stroke(width = 10 * d))
            val to = min(fraction, 1.0) * shown.value
            if (to > 0) {
                val arc = Path().apply {
                    arcTo(Rect(center, r), -90f, (360 * to).toFloat(), true)
                }
                glowStroke(arc, accent, 10 * d, 8 * d, 0.35f)
            }
        }
        if (showLabel) {
            BasicText(label, style = NBFont.dot(700, 44f).copy(color = NB.white.copy(alpha = 0.45f)))
        }
    }
}

@Composable
fun GaugeRenderer(value: Double, zones: List<Triple<Double, Double, String>>, accent: Color, showLabel: Boolean = true,
                  modifier: Modifier = Modifier) {
    val lo = zones.firstOrNull()?.first ?: 0.0
    val hi = zones.lastOrNull()?.second ?: 1.0
    val span = max(hi - lo, 0.0001)
    val palette = listOf(NB.barTrack, NB.lime2, NB.lime1, NB.ember1, NB.ember2)
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val d = density
            zones.forEachIndexed { i, z ->
                ringArc((z.first - lo) / span * 0.75, (z.second - lo) / span * 0.75,
                    palette[min(i, 4)].copy(alpha = 0.5f), 10 * d, StrokeCap.Butt, rotation = 225f)
            }
            ringArc(0.0, (value - lo) / span * 0.75, accent, 10 * d, StrokeCap.Round, rotation = 225f)
        }
        if (showLabel) {
            BasicText(Fmt.kg(value, decimals = 0), style = NBFont.dot(700, 44f).copy(color = NB.white.copy(alpha = 0.45f)))
        }
    }
}

/** stack · split · fuel · balance. Segments on one track. [minutes]: 10 · split counts minutes,
 *  and the board prints them as "1H48 · 24%"; fuel and balance print the number. */
@Composable
fun StackRenderer(parts: List<Triple<String, Double, Color>>, minutes: Boolean = false, modifier: Modifier = Modifier) {
    val total = max(parts.sumOf { it.second }, 0.0001)
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            BoxWithConstraints(Modifier.fillMaxWidth().height(10.dp)) {
                val mw = maxWidth
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    parts.forEach { p ->
                        Box(Modifier.width(max(2.dp, mw * (p.second / total).toFloat() - 2.dp)).fillMaxHeight()
                            .background(p.third, RoundedCornerShape(3.dp)))
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                parts.forEach { p ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.size(8.dp).background(p.third, RoundedCornerShape(2.dp)))
                        BasicText(p.first.uppercase(),
                            style = NBFont.ui(500, 11f).tracking(0.12f).copy(color = NB.white.copy(alpha = 0.55f)))
                        Spacer(Modifier.weight(1f))
                        BasicText(if (minutes) stackClock(p.second, total) else Fmt.kcal(p.second),
                            style = NBFont.dot(600, 11f).copy(color = NB.white.copy(alpha = 0.80f)))
                    }
                }
            }
        }
    }
}

/** "1H48 · 24%" — the board's own legend for a night. */
private fun stackClock(value: Double, total: Double): String {
    val m = value.rounded().toInt()
    val pct = (value / total * 100).rounded().toInt()
    return if (m >= 60) "${m / 60}H${swiftFormat("%02d", m % 60)} · $pct%" else "${m}M · $pct%"
}

/** grid · cells · heat · recomp. */
@Composable
fun GridRenderer(rows: Int, cols: Int, values: List<Int>, levels: Int, accent: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val d = density
        val gap = 3 * d
        val cw = (size.width - gap * (cols - 1)) / cols
        val ch = min(cw, (size.height - gap * (rows - 1)) / rows)
        for (r in 0 until rows) for (c in 0 until cols) {
            val idx = r * cols + c
            val v = if (idx < values.size) values[idx] else 0
            val color = if (v == 0) NB.barTrack else accent.copy(alpha = (0.25 + 0.75 * v / max(levels, 1)).toFloat().coerceIn(0f, 1f))
            drawRoundRect(color, Offset(c * (cw + gap), r * (ch + gap)), Size(cw, ch), CornerRadius(3 * d))
        }
    }
}

/** strip · stacked lanes, never numbers. (level, share). */
@Composable
fun StripRenderer(segments: List<Pair<Int, Double>>, modifier: Modifier = Modifier) {
    val palette = listOf(NB.barTrack, NB.lime2, NB.lime1, NB.ember1, NB.ember2)
    val total = max(segments.sumOf { it.second }, 0.0001)
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxWidth().height(22.dp).clip(RoundedCornerShape(4.dp))) {
            var x = 0f
            for ((level, share) in segments) {
                val w = max(1 * density, (size.width * share / total).toFloat() - 1 * density)
                drawRect(palette[min(level, palette.size - 1)], Offset(x, 0f), Size(w, size.height))
                x += w + 1 * density
            }
        }
    }
}

/**
 * lanes · hypnogram. 07 · 12 · AWAKE on top, then LIGHT, then DEEP (and REM), one block per
 * run. The night reads as a shape rather than a bar. (lane, minutes) in order.
 */
@Composable
fun LaneRenderer(
    runs: List<Pair<Int, Double>>,
    from: String,
    to: String,
    showBlocks: Boolean = true,
    showLabels: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val names = listOf("AWAKE", "LIGHT", "DEEP", "REM")
    val tint = listOf(NB.white.copy(alpha = 0.75f), NB.violet1.copy(alpha = 0.65f), NB.violet1, NB.violet1.copy(alpha = 0.85f))
    val labelStyle = NBFont.dot(600, 9f).tracking(0.12f).copy(color = NB.white.copy(alpha = 0.34f))
    BoxWithConstraints(modifier.fillMaxSize()) {
        val total = max(runs.sumOf { it.second }, 1.0)
        // 12 · the strip starts under the hero and ends over the clock labels.
        val top = 34.dp
        val laneH = (maxHeight - top - 22.dp) / names.size
        if (showLabels) {
            names.forEachIndexed { l, name ->
                BasicText(name, Modifier.offset(y = top + laneH * l), style = labelStyle)
            }
        }
        if (showBlocks) {
            Canvas(Modifier.fillMaxSize()) {
                val d = density
                var x = 0f
                for ((laneRaw, minutes) in runs) {
                    val w = (size.width * minutes / total).toFloat()
                    val lane = max(0, min(laneRaw, names.size - 1))
                    drawRoundRect(tint[lane], Offset(x, (top + laneH * lane).toPx() + 15 * d),
                        Size(max(w - 1 * d, 2 * d), 14 * d), CornerRadius(2 * d))
                    x += w
                }
            }
        }
        if (showLabels) {
            Row(Modifier.fillMaxWidth().offset(y = maxHeight - 12.dp)) {
                val s = NBFont.dot(500, 9f).tracking(0.12f).copy(color = NB.white.copy(alpha = 0.32f))
                BasicText(from, style = s)
                Spacer(Modifier.weight(1f))
                BasicText(to, style = s)
            }
        }
    }
}

/** columns · zones. 07 · 13 · five columns, Z1…Z5, each in its own zone colour, minutes under
 *  them. Z1 track grey, then lime, yellow, amber, red. */
@Composable
fun ZoneColumnsRenderer(minutes: List<Double>, showBars: Boolean = true, showLabels: Boolean = true, modifier: Modifier = Modifier) {
    val palette = listOf(NB.barTrack, NB.lime2, NB.lime1, NB.ember1, NB.alert2)
    BoxWithConstraints(modifier.fillMaxSize()) {
        val n = max(minutes.size, 1)
        val gap = 10.dp
        val w = (maxWidth - gap * (n - 1)) / n
        if (showBars) {
            Canvas(Modifier.fillMaxSize()) {
                val d = density
                val mx = max(minutes.maxOrNull() ?: 1.0, 1.0)
                val plot = size.height - 18 * d
                val wp = w.toPx()
                minutes.forEachIndexed { i, m ->
                    val h = max((m / mx).toFloat() * plot, 3 * d)
                    drawRoundRect(if (m > 0) palette[min(i, 4)] else NB.barTrack.copy(alpha = 0.5f),
                        Offset(i * (wp + 10 * d), plot - h), Size(wp, h), CornerRadius(2 * d))
                }
            }
        }
        if (showLabels) {
            minutes.forEachIndexed { i, m ->
                BasicText("Z${i + 1}", Modifier.offset(x = (w + gap) * i, y = maxHeight - 12.dp).width(w),
                    style = NBFont.dot(600, 9f).tracking(0.12f)
                        .copy(color = NB.white.copy(alpha = if (m > 0) 0.55f else 0.28f), textAlign = TextAlign.Center))
            }
        }
    }
}

/** trace · wave. ECG paper: a grid in millimetres, then one line. */
@Composable
fun TraceRenderer(samples: List<Double>, hz: Double, accent: Color, led: Boolean = false, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        val d = density
        val grid = NB.white.copy(alpha = 0.06f)
        var x = 0f
        while (x < size.width) { drawLine(grid, Offset(x, 0f), Offset(x, size.height), 0.5f * d); x += 10 * d }
        var y = 0f
        while (y < size.height) { drawLine(grid, Offset(0f, y), Offset(size.width, y), 0.5f * d); y += 10 * d }
        if (samples.size <= 1) return@Canvas
        val mn = samples.min()
        val mx = samples.max()
        val span = max(mx - mn, 0.0001)
        val pts = samples.mapIndexed { i, v ->
            Offset(size.width * i / (samples.size - 1), size.height * (1 - ((v - mn) / span).toFloat()) * 0.8f + size.height * 0.1f)
        }
        drawPath(polyline(pts), accent, style = Stroke(width = (if (led) 5f else 1.6f) * d, join = StrokeJoin.Round))
    }
}

/** rows · sparks · table · events · workout · meal. */
@Composable
fun RowsRenderer(items: List<PanelData.RowItem>, accent: Color, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(Modifier.fillMaxWidth()) {
            items.forEachIndexed { i, item ->
                Row(Modifier.fillMaxWidth().height(34.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(5.dp).background(item.tint ?: accent, CircleShape))
                    Spacer(Modifier.width(10.dp))
                    BasicText(item.label.uppercase(), Modifier.weight(1f),
                        style = NBFont.ui(500, 11f).tracking(0.10f).copy(color = NB.white.copy(alpha = 0.62f)),
                        maxLines = 1, overflow = TextOverflow.Ellipsis, softWrap = false)
                    Spacer(Modifier.width(10.dp))
                    Spacer(Modifier.width(8.dp))
                    val spark = item.spark
                    if (spark != null && spark.size > 1) {
                        Spacer(Modifier.width(10.dp))
                        Sparkline(spark, item.tint ?: accent, Modifier.size(64.dp, 16.dp))
                    }
                    Spacer(Modifier.width(10.dp))
                    BasicText(item.value, Modifier.widthIn(min = 48.dp),
                        style = NBFont.dot(600, 12f).copy(color = NB.white.copy(alpha = 0.88f), textAlign = TextAlign.End))
                }
                if (i < items.size - 1) Hairline()
            }
        }
    }
}

@Composable
fun Sparkline(values: List<Double>, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        if (values.size <= 1) return@Canvas
        val mn = values.min()
        val mx = values.max()
        val span = max(mx - mn, 0.0001)
        val pts = values.mapIndexed { i, v ->
            Offset(size.width * i / (values.size - 1), size.height * (1 - ((v - mn) / span).toFloat()))
        }
        drawPath(polyline(pts), tint, style = Stroke(width = 1.4f * density, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

// MARK: - 2026-09-06 gap audit · four shapes the first ten renderers could not hold

/**
 * meter · score. A total, then the sub-scores that make it — each against its own full value.
 * The bar that scores worst takes the alert colour. Both passes (bars behind the dot screen,
 * words in front) keep the whole layout; only the paint is switched off.
 */
@Composable
fun MeterRenderer(
    parts: List<Triple<String, Double, Double>>,
    accent: Color,
    showBars: Boolean = true,
    showLabels: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val worst = if (parts.isEmpty()) null
    else parts.indices.minByOrNull { parts[it].second / max(parts[it].third, 1.0) }
    BoxWithConstraints(modifier.fillMaxSize()) {
        val n = max(parts.size, 1)
        val gap = 10.dp
        val rowH = max(10.dp, (maxHeight - gap * (n - 1)) / n)
        val barH = min(12.dp.value, rowH.value * 0.46f).dp
        val W = maxWidth
        Column(verticalArrangement = Arrangement.spacedBy(gap)) {
            parts.forEachIndexed { i, p ->
                val tint = if (i == worst) NB.alert2 else accent
                Column(Modifier.height(rowH), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(Modifier.width(W), verticalAlignment = Alignment.CenterVertically) {
                        BasicText(p.first, style = NBFont.dot(600, 9.5f).tracking(1.4f / 9.5f)
                            .copy(color = if (showLabels) NB.white.copy(alpha = 0.55f) else Color.Transparent))
                        Spacer(Modifier.width(12.dp))
                        Spacer(Modifier.weight(1f))
                        BasicText(Fmt.kg(p.second, decimals = 0), style = NBFont.dot(700, 11f).copy(
                            color = if (showLabels) (if (i == worst) NB.alert2 else NB.white.copy(alpha = 0.85f)) else Color.Transparent))
                    }
                    Box(Modifier.width(W).height(barH)) {
                        Box(Modifier.fillMaxSize().background(if (showBars) NB.barTrack else Color.Transparent, CircleShape))
                        Box(Modifier.width(max(2.dp, W * min(1.0, p.second / max(p.third, 1.0)).toFloat())).fillMaxHeight()
                            .background(if (showBars) tint else Color.Transparent, CircleShape))
                    }
                }
            }
        }
    }
}

/**
 * scatter · poincare. The beat-to-beat cloud the balance check draws inside MeasureTakeover.
 * The plot stays square; the readings take the column the square leaves over. The text pass
 * draws no plot at all and only holds its place (an empty plot prints NOT ENOUGH BEATS).
 */
@Composable
fun ScatterRenderer(
    points: List<Offset>,
    lo: Double,
    hi: Double,
    stats: List<Pair<String, String>> = emptyList(),
    accent: Color,
    showCloud: Boolean = true,
    showLabels: Boolean = true,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val side = min(maxWidth.value * 0.58f, maxHeight.value).dp
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Box(Modifier.size(side)) {
                if (showCloud) PoincarePlot(points = points, accent = accent)
            }
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                stats.forEach { s ->
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        BasicText(s.first, style = NBFont.dot(600, 9f).tracking(1.6f / 9f)
                            .copy(color = if (showLabels) NB.white.copy(alpha = 0.45f) else Color.Transparent))
                        BasicText(s.second, style = NBFont.dot(700, 17f)
                            .copy(color = if (showLabels) NB.white else Color.Transparent))
                    }
                }
            }
        }
    }
}

/**
 * verdict · call. One word out of a closed set, the alternatives it was not, and how much
 * evidence stands behind it. The choice is carried by colour and a rule under the word (an
 * inverted chip cannot survive the dot screen).
 */
@Composable
fun VerdictRenderer(
    word: String,
    options: List<String>,
    confidence: Int,
    steps: Int,
    accent: Color,
    showBars: Boolean = true,
    showLabels: Boolean = true,
    modifier: Modifier = Modifier,
) {
    fun short(option: String) = if (option == "NO_CHANGE") "NO CHG" else option.replace("_", " ")
    Column(modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            options.forEach { o ->
                val on = o == word
                Column(Modifier.width(androidx.compose.foundation.layout.IntrinsicSize.Max),
                    verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    BasicText(short(o), style = NBFont.dot(if (on) 700 else 500, 9.5f).tracking(1.0f / 9.5f)
                        .copy(color = if (showLabels) (if (on) accent else NB.white.copy(alpha = 0.28f)) else Color.Transparent),
                        maxLines = 1, softWrap = false)
                    Box(Modifier.fillMaxWidth().height(2.dp).background(if (showBars && on) accent else Color.Transparent))
                }
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            BasicText(L("CONFIDENCE"), style = NBFont.dot(600, 9f).tracking(1.6f / 9f)
                .copy(color = if (showLabels) NB.white.copy(alpha = 0.45f) else Color.Transparent))
            Spacer(Modifier.width(8.dp))
            Box(Modifier.weight(1f)) {
                Row(Modifier.widthIn(max = 150.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    repeat(max(steps, 1)) { i ->
                        // An unlit step still has to be visible or "1 of 3" reads as "1".
                        Box(Modifier.weight(1f).height(10.dp)
                            .background(if (showBars) (if (i < confidence) accent else NB.barTrack) else Color.Transparent))
                    }
                }
            }
            Spacer(Modifier.width(8.dp))
        }
    }
}

/** grid · matrix. Five states, five colours — not one ramp.
 *  0 not collected · 1 unsupported · 2 failed · 3 partial · 4 complete. */
@Composable
fun MatrixRenderer(
    rows: Int,
    cols: Int,
    values: List<Int>,
    rowLabels: List<String>,
    showCells: Boolean = true,
    showLabels: Boolean = true,
    modifier: Modifier = Modifier,
) {
    fun tint(v: Int): Color = when (v) {
        4 -> NB.lime1
        3 -> NB.ember1
        2 -> NB.alert2
        1 -> NB.white.copy(alpha = 0.10f)
        else -> NB.ledOff
    }
    BoxWithConstraints(modifier.fillMaxSize()) {
        val labelW = 62.dp
        val gap = 3.dp
        val gridW = max(0.dp, maxWidth - labelW)
        val cw = max(2.dp, (gridW - gap * max(cols - 1, 0)) / max(cols, 1))
        val ch = max(2.dp, (maxHeight - gap * max(rows - 1, 0)) / max(rows, 1))
        Column(verticalArrangement = Arrangement.spacedBy(gap)) {
            for (r in 0 until max(rows, 0)) {
                Row(horizontalArrangement = Arrangement.spacedBy(gap), verticalAlignment = Alignment.CenterVertically) {
                    BasicText(if (r < rowLabels.size) rowLabels[r] else "", Modifier.width(labelW - gap),
                        style = NBFont.dot(600, 9f).tracking(1.0f / 9f)
                            .copy(color = if (showLabels) NB.white.copy(alpha = 0.55f) else Color.Transparent),
                        maxLines = 1, softWrap = false, overflow = TextOverflow.Clip)
                    for (c in 0 until max(cols, 0)) {
                        val i = r * cols + c
                        Box(Modifier.size(cw, ch).background(if (showCells) tint(if (i < values.size) values[i] else 0) else Color.Transparent))
                    }
                }
            }
        }
    }
}

/**
 * The Poincaré plot. Axes are not labelled with numbers on purpose — the shape and the spread
 * are the reading. One square window around the cloud keeps the diagonal at 45°.
 */
@Composable
fun PoincarePlot(points: List<Offset>, accent: Color, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val emptyStyle: TextStyle = NBFont.dot(500, 9.5f).copy(color = NB.white.copy(alpha = 0.30f))
    val emptyLabel = L("NOT ENOUGH BEATS")
    Canvas(modifier.fillMaxSize()) {
        val d = density
        drawRoundRect(NB.white.copy(alpha = 0.10f), cornerRadius = CornerRadius(10 * d), style = Stroke(width = 1 * d))
        if (points.size <= 1) {
            val r = measurer.measure(emptyLabel, emptyStyle)
            drawText(r, topLeft = Offset((size.width - r.size.width) / 2, (size.height - r.size.height) / 2))
            return@Canvas
        }
        val xs = points.map { it.x.toDouble() }
        val ys = points.map { it.y.toDouble() }
        val lo = min(xs.min(), ys.min())
        val hi = max(xs.max(), ys.max())
        val pad = max(20.0, (hi - lo) * 0.18)
        val a = lo - pad
        val b = hi + pad
        val span = max(1.0, b - a)
        fun place(x: Double, y: Double) = Offset(((x - a) / span * size.width).toFloat(),
            // y up: a longer next-interval sits higher, the way the plot is read.
            (size.height - (y - a) / span * size.height).toFloat())
        drawLine(NB.white.copy(alpha = 0.16f), place(a, a), place(b, b), strokeWidth = 1 * d,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(3 * d, 4 * d)))
        for (p in points) drawCircle(accent.copy(alpha = 0.9f), radius = 2.2f * d, center = place(p.x.toDouble(), p.y.toDouble()))
    }
}

/** Shared size helper for callers: Swift's `.frame(height: h)` on a renderer. */
internal fun Modifier.rendererHeight(h: Dp): Modifier = this.fillMaxWidth().height(h)
