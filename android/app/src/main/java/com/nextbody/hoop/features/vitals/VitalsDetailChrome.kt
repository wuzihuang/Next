package com.nextbody.hoop.features.vitals

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import kotlin.math.max
import kotlin.math.min

// 04 · 8 大指标二级页 · the shared anatomy. The board draws one page eight times: a hero
// whose big read-out owns its own line, a chart on a fixed ruler, a distribution, and two
// stat tiles. Everything here is chrome — not one of these views knows a metric's name.
//
// The board's `! ZERO TEXT WRAP GUARANTEE` is the reason every number below holds one line
// and shrinks rather than wraps: 8,420 and 2,140 and +0.2 °C all have to hold one line on a
// narrow phone, and a wrapped read-out is the defect the board was drawn against.

/** SwiftUI `Gradient.Stop`s, top-down: `(location, colour)`. */
typealias GradientStops = List<Pair<Float, Color>>

/**
 * One line of text that shrinks to `minScale` before it truncates — SwiftUI's
 * `.lineLimit(1).minimumScaleFactor(x)`. With `minScale == 1` it truncates like `lineLimit(1)`.
 * `maxLines > 1` wraps (and never shrinks) like `.fixedSize(horizontal: false, vertical: true)`.
 */
@Composable
fun FitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 1f,
    maxLines: Int = 1,
    align: TextAlign? = null,
) {
    if (maxLines != 1 || minScale >= 1f) {
        Text(
            text = text, modifier = modifier, style = style, color = color,
            maxLines = maxLines, softWrap = maxLines != 1,
            overflow = TextOverflow.Ellipsis, textAlign = align,
        )
        return
    }
    var scale by remember(text, style) { mutableFloatStateOf(1f) }
    var ready by remember(text, style) { mutableStateOf(false) }
    Text(
        text = text,
        modifier = modifier.drawWithContent { if (ready) drawContent() },
        style = style.copy(fontSize = style.fontSize * scale),
        color = color,
        maxLines = 1,
        softWrap = false,
        // Shrinks first; once at the floor it truncates with an ellipsis, like SwiftUI.
        overflow = if (scale <= minScale) TextOverflow.Ellipsis else TextOverflow.Clip,
        textAlign = align,
        onTextLayout = { result ->
            if (result.didOverflowWidth && scale > minScale) {
                scale = max(minScale, scale * 0.92f)
            } else {
                ready = true
            }
        },
    )
}

/**
 * The hero. `value` is the only thing on its line — the zone name and the unit sit at its
 * baseline, the dial under it, the two facts that qualify it below that, and the sensor
 * caption last.
 */
@Composable
fun VitalsHero(
    /** What measured it, not what it means. */
    sensor: String,
    /** nil is ——. F2 rule 05 · a number that is not there is never a zero. */
    value: String?,
    unit: String?,
    tint: Color,
    dial: VitalsDial.Model?,
    footLeft: String,
    footRight: String?,
) {
    val figureTint = dial?.zoneTint ?: tint
    val access = if (value == null) "no reading"
    else "$value ${unit ?: ""}${dial?.zoneName?.let { ", $it" } ?: ""}"
    Column(
        Modifier
            .width(NB.Layout.contentWidth)
            .padding(bottom = 4.dp)
            .testTag("vitals.hero")
            .clearAndSetSemantics { contentDescription = sensor; stateDescription = access },
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FitText(
                value ?: Fmt.dash, NBFont.dot(800, 64f),
                if (value == null) NB.text3Prod else figureTint,
                Modifier.alignBy(LastBaseline), minScale = 0.6f,
            )
            Column(Modifier.alignBy(LastBaseline).weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                val name = dial?.zoneName
                if (name != null && value != null) {
                    FitText(name, NBFont.ui(600, 15f), figureTint, minScale = 0.8f)
                }
                if (unit != null) {
                    FitText(unit, NBFont.ui(500, 13f), NB.text3Prod)
                }
            }
        }

        if (dial != null) VitalsDial(dial)

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FitText(footLeft, NBFont.ui(400, 13f), NB.text2,
                Modifier.alignBy(FirstBaseline), minScale = 0.8f)
            Spacer(Modifier.weight(1f))
            if (footRight != null) {
                FitText(footRight, NBFont.ui(400, 12f), NB.text3Prod,
                    Modifier.alignBy(FirstBaseline), minScale = 0.8f)
            }
        }

        FitText(sensor, NBFont.ui(400, 11f), NB.text3Prod, minScale = 0.8f)
    }
}

/**
 * Named zones on a fixed ruler. The occupied zone lights; a white needle marks the reading.
 * This is not a fill bar and not a target — the scale is the conclusion.
 */
object VitalsDial {
    data class Zone(val name: String, val tint: Color, val weight: Double)

    data class Model(
        val zones: List<Zone>,
        /** 0…1 on the full scale, or nil when there is no reading to place. */
        val fraction: Double?,
        val activeIndex: Int?,
        /** The interior cuts the zones were built from, kept so the model can place *any*
         *  value — a capsule cannot come out red while the dial above it still lights STEADY. */
        val cuts: List<Double> = emptyList(),
    ) {
        val zoneName: String?
            get() {
                val i = activeIndex ?: return null
                if (i !in zones.indices) return null
                return zones[i].name.ifEmpty { null }
            }

        val zoneTint: Color?
            get() {
                val i = activeIndex ?: return null
                if (i !in zones.indices) return null
                return zones[i].tint
            }

        val showsLabels: Boolean get() = zones.any { it.name.isNotEmpty() }

        /** The colour this ruler gives `value`, or nil when there are no cuts to read it against. */
        fun tint(value: Double): Color? {
            if (cuts.isEmpty() || zones.isEmpty()) return null
            val i = min(zones.size - 1, VitalsDialMath.activeIndex(value, cuts))
            return zones[i].tint
        }

        /** The zone colours in equal bands, for a legend swatch, top zone first (the swatch
         *  is drawn top-down like the field it keys). A key shows the colours, not their widths. */
        val legendStops: GradientStops?
            get() {
                if (zones.size <= 1) return null
                val step = 1f / zones.size
                return zones.reversed().flatMapIndexed { i, zone ->
                    listOf(i * step to zone.tint, (i + 1) * step to zone.tint)
                }
            }

        /** Hard-edged gradient stops for a mark spanning `low…high`, top-down. */
        fun stops(low: Double, high: Double): GradientStops? {
            if (cuts.isEmpty() || zones.isEmpty()) return null
            val runs = VitalsDialMath.zoneRuns(low, high, cuts)
            if (runs.isEmpty()) return null
            return runs.flatMap { run ->
                val tint = zones[min(zones.size - 1, run.zone)].tint
                // Both ends of the run carry its own colour, so the crossing is a line, not a blend.
                listOf(run.from.toFloat() to tint, run.to.toFloat() to tint)
            }
        }
    }

    internal data class RowLayout(val gap: Dp, val widths: List<Dp>)

    internal fun row(model: Model, width: Dp): RowLayout {
        val gap = 3.dp
        val count = model.zones.size
        val usable = width - gap * max(0, count - 1)
        val total = model.zones.sumOf { max(0.001, it.weight) }
        val widths = model.zones.map { max(2f, (usable.value * (it.weight / total)).toFloat()).dp }
        return RowLayout(gap, widths)
    }
}

@Composable
fun VitalsDial(model: VitalsDial.Model) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(26.dp)) {
            val w = maxWidth
            val layout = VitalsDial.row(model, w)
            Row(Modifier.padding(top = 9.dp), horizontalArrangement = Arrangement.spacedBy(layout.gap)) {
                model.zones.forEachIndexed { i, zone ->
                    val on = model.activeIndex == i
                    Box(
                        Modifier.size(layout.widths[i], 9.dp)
                            .background(if (on) zone.tint else zone.tint.copy(alpha = 0.14f), RoundedCornerShape(2.dp)),
                    )
                }
            }
            val fraction = model.fraction
            if (fraction != null) {
                val x = min(w.value - 4, max(4f, (w.value * fraction).toFloat()))
                Column(Modifier.offset(x = (x - 4).dp).width(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(8.dp, 4.dp).background(NB.white, CircleShape))
                    Box(Modifier.size(2.dp, 22.dp).background(NB.white, CircleShape))
                }
            }
        }
        if (model.showsLabels) {
            BoxWithConstraints(Modifier.fillMaxWidth().height(12.dp)) {
                val layout = VitalsDial.row(model, maxWidth)
                Row(horizontalArrangement = Arrangement.spacedBy(layout.gap)) {
                    model.zones.forEachIndexed { i, zone ->
                        val on = model.activeIndex == i
                        FitText(
                            zone.name, NBFont.ui(if (on) 500 else 400, 9f),
                            if (on) zone.tint else NB.white.copy(alpha = 0.32f),
                            Modifier.width(layout.widths[i]), minScale = 0.65f,
                        )
                    }
                }
            }
        }
    }
}

/**
 * The vertical ruler, standing beside the field instead of inside it.
 *
 * ⚠️ The whole point of the rail is that nothing is printed over the data. Charts that adopt
 * the rail shrink their own canvas by `gutter`, and the clock under them is inset by the same.
 */
object VitalsScaleRail {
    val width: Dp = 34.dp
    val gap: Dp = 8.dp
    val gutter: Dp get() = width + gap
    /** How far the tick pokes back into the gap, towards the field it measures. */
    internal val tick: Dp = 8.dp
}

/** Top of the ruler first, the way it is read. Three marks: high, middle, low. */
@Composable
fun VitalsScaleRail(labels: List<String>, @Suppress("UNUSED_PARAMETER") tint: Color, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.width(VitalsScaleRail.width).fillMaxHeight()) {
        val h = maxHeight
        labels.forEachIndexed { i, label ->
            val fraction = if (labels.size > 1) i.toFloat() / (labels.size - 1) else 0f
            val y = h * fraction
            Box(
                Modifier
                    .offset(x = -VitalsScaleRail.gap - 3.dp, y = y)
                    .size(VitalsScaleRail.tick, 1.dp)
                    .background(NB.white.copy(alpha = 0.28f)),
            )
            // Half the cap height, so the label reads level with its own tick.
            FitText(
                label, NBFont.ui(500, 10f), NB.white.copy(alpha = 0.52f),
                Modifier.offset(y = y - 6.dp), minScale = 0.7f,
            )
        }
    }
}

/**
 * The clock under a chart. `04 · 10 · 16 · 22` on a day page, the night's own two ends on a
 * night page — and NOW in the metric's colour when the last mark is the live one.
 */
@Composable
fun VitalsAxis(labels: List<String>, highlightsLast: Boolean = true, tint: Color, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth()) {
        labels.forEachIndexed { i, label ->
            val last = highlightsLast && i == labels.size - 1
            FitText(label, NBFont.ui(if (last) 500 else 400, 10f), if (last) tint else NB.white.copy(alpha = 0.45f))
            if (i < labels.size - 1) Spacer(Modifier.weight(1f))
        }
    }
}

/**
 * What the marks in the field mean, said under the field. This row is where the captions
 * that used to be plates on top of the trace went.
 */
object VitalsChartLegend {
    data class Item(
        val text: String,
        val tint: Color,
        /** A block swatch reads as an area — the reference band. A bar reads as one mark. */
        val isArea: Boolean = false,
        /** Given the zone colours, the swatch wears them instead of a flat tint. */
        val stops: GradientStops? = null,
    )
}

@Composable
fun VitalsChartLegend(
    items: List<VitalsChartLegend.Item>,
    trailing: String? = null,
    trailingTint: Color = NB.white,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .drawBehind { drawRect(NB.white.copy(alpha = 0.06f), Offset.Zero, Size(size.width, 1.dp.toPx())) }
            .padding(top = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically) {
            items.forEach { item ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    val shape = RoundedCornerShape(2.dp)
                    val stops = item.stops
                    Box(
                        Modifier
                            .size(if (item.isArea) 12.dp else 3.dp, 11.dp)
                            .then(
                                if (stops != null) Modifier.background(Brush.verticalGradient(*stops.toTypedArray()), shape)
                                else Modifier.background(item.tint.copy(alpha = item.tint.alpha * if (item.isArea) 0.14f else 0.85f), shape),
                            ),
                    )
                    FitText(item.text, NBFont.ui(400, 11f), NB.white.copy(alpha = 0.50f), minScale = 0.75f)
                }
            }
        }
        if (trailing != null) {
            Spacer(Modifier.width(0.dp))
            FitText(trailing, NBFont.ui(500, 11f), trailingTint, minScale = 0.8f)
        }
    }
}

/**
 * Where the day went, as one bar of shares plus its legend. The shares are minutes or kcal,
 * not percentages of a target: the bar is always full because the day always happened.
 */
object VitalsSplit {
    data class Band(
        val name: String,
        val tint: Color,
        val share: Double,
        /** What the legend prints after the name — "52%" or "3H 10M". */
        val detail: String,
    )
}

@Composable
fun VitalsSplit(bands: List<VitalsSplit.Band>) {
    val present = bands.filter { it.share > 0 }
    val total = present.sumOf { it.share }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (present.isEmpty() || total <= 0) {
            Text(L("NO TICKS YET"), style = NBFont.dot(500, 10f).tracking(0.05f), color = NB.macroValue)
        } else {
            BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp)) {
                val w = maxWidth.value
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    present.forEach { b ->
                        val bw = max(2.0, (w - 3.0 * (present.size - 1)) * b.share / total)
                        Box(Modifier.size(bw.toFloat().dp, 8.dp).background(b.tint, CircleShape))
                    }
                }
            }
            // 04B · the legend is a fixed-width lane per band so four of them line up across
            // the card whatever their numbers read.
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                present.forEach { b ->
                    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(5.dp).background(b.tint, CircleShape))
                        FitText("${b.name} ${b.detail}", NBFont.ui(400, 11f), NB.text2, minScale = 0.75f)
                    }
                }
            }
        }
    }
}

/**
 * The page's key-metrics pair: two separate tiles, always exactly two, always the same
 * height. They draw `cardBleed` into the gutter on both sides, like the card sections.
 */
object VitalsStatPair {
    data class Model(
        val label: String,
        val value: String?,
        val unit: String?,
        val foot: String,
        /** nil keeps the value white — the tint is spent on the one figure that earns it. */
        val tint: Color?,
    )
}

@Composable
fun VitalsStatPair(left: VitalsStatPair.Model, right: VitalsStatPair.Model) {
    Row(
        Modifier
            .requiredWidth(NB.Layout.contentWidth + NB.Layout.cardBleed * 2)
            .height(IntrinsicSize.Min),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        StatTile(left, Modifier.weight(1f))
        StatTile(right, Modifier.weight(1f))
    }
}

@Composable
private fun StatTile(m: VitalsStatPair.Model, modifier: Modifier) {
    val access = m.value?.let { "$it ${m.unit ?: ""}, ${m.foot}" } ?: "no reading, ${m.foot}"
    Column(
        modifier
            .fillMaxHeight()
            .heightIn(min = 84.dp)
            .background(NB.white.copy(alpha = 0.06f), RoundedCornerShape(16.dp))
            .padding(14.dp)
            .clearAndSetSemantics { contentDescription = m.label; stateDescription = access },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        FitText(m.label, NBFont.ui(500, 13f), NB.text2, minScale = 0.8f)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            FitText(
                m.value ?: Fmt.dash, NBFont.dot(700, 22f),
                if (m.value == null) NB.text3Prod else (m.tint ?: NB.text1),
                Modifier.alignBy(FirstBaseline).weight(1f, fill = false), minScale = 0.7f,
            )
            if (m.unit != null && m.value != null) {
                Text(m.unit, Modifier.alignBy(FirstBaseline), style = NBFont.ui(500, 12f), color = NB.text3Prod, maxLines = 1)
            }
        }
        FitText(
            m.foot, NBFont.ui(400, 11f),
            if (m.value == null) NB.text3Prod else (m.tint ?: NB.text3Prod), minScale = 0.75f,
        )
    }
}

/**
 * What a chart card says instead of drawing, when the day has no ticks to draw. It keeps the
 * card's frame — 04B F1/F5 · an empty page, not a zeroed one.
 */
@Composable
fun VitalsChartEmpty(line: String, sub: String, height: Dp = 160.dp, subLineLimit: Int = 1) {
    Box(Modifier.fillMaxWidth().heightIn(min = height), contentAlignment = Alignment.CenterStart) {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(line, style = NBFont.dot(600, 11f).tracking(0.14f), color = NB.white.copy(alpha = 0.55f))
            FitText(sub, NBFont.dot(500, 10f).tracking(0.05f), NB.macroValue,
                minScale = if (subLineLimit == 1) 0.8f else 1f, maxLines = subLineLimit)
        }
    }
}

/** A dashed rounded outline — the "no record" slot every bar chart on these pages draws. */
@Composable
internal fun DottedSlot(radius: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val r = radius.toPx()
        drawRoundRect(
            NB.hairline,
            cornerRadius = CornerRadius(r, r),
            style = androidx.compose.ui.graphics.drawscope.Stroke(
                width = 1.dp.toPx(),
                pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 3.dp.toPx())),
            ),
        )
    }
}
