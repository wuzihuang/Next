package com.nextbody.hoop.features.home.panel

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.sp
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.ui.hotZoneTap
import java.time.Instant
import java.util.UUID
import kotlin.math.max

// 07 · AI 屏 MCP 渲染契约.
// The server sends one envelope; the panel is the only thing that renders it.
// Ten renderers cover the types. Four fields are required: type, title, sentence, data.

/** The types. The type decides the chart and, through the ACCENT MAP, the colour. */
enum class PanelType(val raw: String) {
    battery("battery"), metric("metric"), text("text"), line("line"), band("band"), bars("bars"),
    days("days"), sparks("sparks"), ring("ring"), gauge("gauge"), split("split"),
    cells("cells"), hypnogram("hypnogram"), zones("zones"), wave("wave"), table("table"),
    workout("workout"), events("events"), heat("heat"), o2night("o2night"),
    food("food"), meal("meal"), fuel("fuel"), balance("balance"), recomp("recomp"), delta("delta"), dual("dual"),
    /** ADR 0018 · numbered suggestions; `plan` remains the wire identifier. */
    plan("plan"),
    /** 2026-09-06 gap audit · six shapes the database had data for and the screen did not. */
    score("score"), poincare("poincare"), matrix("matrix"), call("call"), curve("curve"), response("response");

    /** The night's three are drawn again (ruling reversed 2026-09-03); the catalogue still groups them. */
    val isSleepWidget: Boolean get() = this == hypnogram || this == split || this == o2night

    /** 09 · B — the renderers over the types. */
    val renderer: PanelRenderer
        get() = when (this) {
            metric, text -> PanelRenderer.number
            line, o2night -> PanelRenderer.curve
            dual -> PanelRenderer.dual
            band -> PanelRenderer.pair
            bars, days, delta -> PanelRenderer.column
            ring, gauge, battery -> PanelRenderer.arc
            split, fuel, balance -> PanelRenderer.stack
            cells, heat, recomp -> PanelRenderer.grid
            // 07 · 12 vs 13 · the night is three lanes of run-length blocks; zones is five columns.
            hypnogram -> PanelRenderer.lanes
            zones -> PanelRenderer.columns
            wave -> PanelRenderer.trace
            sparks, table, events, workout, meal, food, plan -> PanelRenderer.rows
            // curve and response ride the curve renderer; the marks and threshold are its slots.
            curve, response -> PanelRenderer.curve
            score -> PanelRenderer.meter
            poincare -> PanelRenderer.scatter
            matrix -> PanelRenderer.matrix
            call -> PanelRenderer.verdict
        }

    /** 05 · ACCENT MAP — colour is the data domain, not decoration. */
    val accent: Color
        get() = when (this) {
            battery, days, cells, recomp, plan -> NB.lime1                 // move · steps
            fuel, meal, food, balance, split -> NB.cyan1                   // fuel · protein
            hypnogram, delta, dual -> NB.violet1                           // recover · sleep
            metric, ring, gauge, line, bars, heat, workout, events, table -> NB.ember1 // heart · fat
            o2night, band -> NB.blue1                                      // spo2 · carbs
            zones, curve -> NB.ember1
            score, poincare -> NB.violet1
            matrix, call -> NB.lime1
            response -> NB.cyan1
            wave -> NB.alert2                                              // warning · rr
            sparks, text -> NB.white                                       // stress · hrv
        }

    /** Slot 3 · which hero layout this type uses. */
    val hero: HeroStyle
        get() = when (this) {
            metric -> HeroStyle.large
            ring, gauge, battery -> HeroStyle.ring
            sparks -> HeroStyle.none
            // ⚠️ Not .large: a six-letter verdict at 60 pt ran straight through the chart.
            text, food -> HeroStyle.own
            else -> HeroStyle.small
        }

    /** The fallback for frames the app builds itself. A frame off the wire uses the target the
     *  envelope declared — see [PanelWidget.targetOverride]. `plan` targets the plan face,
     *  which is AI-only and absent on Android (AIFeature.enabled = false): null, no page. */
    val target: Destination?
        get() = when (this) {
            battery, hypnogram, o2night -> Destination.BodyBattery
            food, meal, fuel, balance -> Destination.Fuel
            recomp, delta, dual -> Destination.Composition(null)
            plan -> null
            score, poincare, wave -> Destination.BodyBattery
            response -> Destination.Fuel
            call -> Destination.Composition(null)
            matrix -> Destination.Profile
            else -> Destination.Training
        }

    companion object {
        fun fromRaw(raw: String): PanelType? = entries.firstOrNull { it.raw == raw }
    }
}

enum class PanelRenderer {
    number, curve, pair, column, arc, stack, grid, strip, trace, rows,
    /** score · a total plus the sub-scores that make it. */
    meter,
    /** poincare · the beat-to-beat cloud. */
    scatter,
    /** matrix · domain × day, five states in five colours. */
    matrix,
    /** call · one word out of a closed set, with the evidence behind it. */
    verdict,
    /** 26 · dual · two series on their own scales. */
    dual,
    /** 12 · hypnogram · AWAKE / LIGHT / DEEP lanes. */
    lanes,
    /** 13 · zones · five columns. */
    columns,
}

enum class HeroStyle { large, small, ring, own, none }

/**
 * 07 · 04 信封. Fourteen fields, four required. Anything outside the table is dropped.
 * Equality is identity ([id]), as in Swift; `copy()` keeps the id the way a Swift value copy does.
 */
data class PanelWidget(
    var type: PanelType,
    var title: String,                     // ≤ 18, upper-cased
    var tag: PanelTag? = null,             // MOVE / FUEL / RECOVER / ALERT — classification only
    var sentence: String,                  // ≤ 48, two lines max
    var footer: String? = null,            // ≤ 42, segments joined by " · "
    var action: String? = null,            // ≤ 32, upper-cased, takes the accent
    /** An explicit `data.hero`; when present this wins over the shape. */
    var hero: String? = null,
    var accentOverride: Color? = null,
    /** 13 col 01 · where the night ends and the day begins on a curve, and the day's colour. */
    var curveSplit: Int? = null,
    var curveSecondary: Color? = null,
    /** The threshold a curve is read against, and the sample indices worth a hairline. */
    var curveMark: Double? = null,
    var curveMarks: List<Int> = emptyList(),
    /** F0 rule 06 · where a tap lands, as the envelope declared it. */
    var targetOverride: Destination? = null,
    var data: PanelData,
    /** 05 · C·07 · the photo track's answer: source chip on top, the logged line at the bottom. */
    var photo: PhotoAnswer? = null,
    /** 06 · 20 · the body scan's result on the panel. */
    var composition: CompositionAnswer? = null,
    /** 06 · the balance check's own frame. */
    var balance: BalanceAnswer? = null,
    /** 07 · rule 6 · `text`'s eyebrow / lime headline / sub. */
    var headline: HeadlineBlock? = null,
    /** 07 · 20 · `food` is the plate. */
    var plate: PlateBlock? = null,
    /** 06 · 17 · a measurement's result "becomes a message" (AI only). */
    var replyPrompt: String? = null,
    /** 06 · 16 · the measured number as the 60 pt hero, with its own line under it. */
    var heroLarge: Boolean = false,
    var heroSub: String? = null,
    var ttlMinutes: Int = 20,
    var priority: Priority = Priority.normal,
    /** When this frame went up. */
    var startedAt: Instant = Instant.now(),
    /** Original server payload retained for faithful chat history replay. */
    var envelopeData: ByteArray? = null,
    val id: UUID = UUID.randomUUID(),
) {
    enum class Priority { normal, alert }

    val accent: Color get() = accentOverride ?: type.accent

    override fun equals(other: Any?): Boolean = other is PanelWidget && other.id == id
    override fun hashCode(): Int = id.hashCode()

    companion object {
        /** The echo's ceiling: three lines of the panel's 11 pt dot face. */
        const val thinkingEcho = 120

        /** The panel while she is working. Not a type — a state of the same surface. */
        fun thinking(question: String = ""): PanelWidget =
            PanelWidget(type = PanelType.text, title = "THINKING", sentence = question.take(thinkingEcho), data = PanelData.None)
    }
}

enum class PanelTag(val raw: String) { move("MOVE"), fuel("FUEL"), recover("RECOVER"), alert("ALERT") }

/** The payload shapes behind the renderers. */
sealed class PanelData {
    data object None : PanelData()
    data class Series(val values: List<Double>) : PanelData()                                  // curve
    data class Pair(val hi: List<Double>, val lo: List<Double>) : PanelData()                  // pair
    data class Bins(val bins: List<kotlin.Pair<String, Double>>) : PanelData()                 // column
    data class Ring(val value: Double, val goal: Double, val unit: String) : PanelData()       // arc
    data class Gauge(val value: Double, val zones: List<Triple<Double, Double, String>>) : PanelData()
    data class Parts(val parts: List<Triple<String, Double, Color>>) : PanelData()             // stack
    data class Cells(val rows: Int, val cols: Int, val values: List<Int>, val levels: Int) : PanelData() // grid
    data class Strip(val segments: List<kotlin.Pair<Int, Double>>) : PanelData()               // (level, share)
    /** 12 · (lane, minutes) in order, plus the night's ends. */
    data class Lanes(val runs: List<kotlin.Pair<Int, Double>>, val from: String, val to: String) : PanelData()
    /** 13 · five minute counts, Z1…Z5. */
    data class Zones(val minutes: List<Double>) : PanelData()
    data class Trace(val samples: List<Double>, val hz: Double) : PanelData()                  // trace
    data class Rows(val items: List<RowItem>) : PanelData()                                    // rows
    /** score · (label, value, full value) per sub-score. */
    data class Meter(val parts: List<Triple<String, Double, Double>>) : PanelData()
    /** poincare · consecutive interval pairs (ms), the box, and the readings beside it. */
    data class Scatter(val points: List<Offset>, val lo: Double, val hi: Double,
                       val stats: List<kotlin.Pair<String, String>>) : PanelData()
    /** matrix · domain rows × day columns, one state code per cell. */
    data class Matrix(val rows: Int, val cols: Int, val values: List<Int>, val rowLabels: List<String>) : PanelData()
    /** call · the verdict, what it was not, and how much evidence stands behind it. */
    data class Verdict(val word: String, val options: List<String>, val confidence: Int, val steps: Int) : PanelData()

    data class RowItem(
        var label: String,
        var value: String,
        var spark: List<Double>? = null,
        var tint: Color? = null,
    )
}

/** 07 · rule 6 · text's own three lines. */
data class HeadlineBlock(var eyebrow: String? = null, var headline: String, var sub: String? = null)

/** 07 · 20 · the plate, as the board lays it out. */
data class PlateBlock(
    var name: String,
    var portion: String? = null,
    var kcal: Double? = null,
    var protein: Double? = null,
    var carb: Double? = null,
    var fat: Double? = null,
    var pctOfBudget: Int? = null,
)

/** 06 · what the balance check puts on the panel — all from the band's interval series. */
data class BalanceAnswer(
    var headline: String,
    var note: String,
    /** 0…1 · the beat-to-beat half's share of the cloud. */
    var restShare: Double,
    var footer: String,
    /** Consecutive interval pairs in milliseconds, already paired: (this beat, the next). */
    var points: List<Offset>,
)

/** 06 · 20 · what the body scan's frame carries beyond the template. Never a placeholder. */
data class CompositionAnswer(
    var heroSub: String,          // BODY FAT · 22.1% IN JUNE
    var fields: List<Field>,      // MUSCLE · WATER · PROTEIN · BMR
) {
    data class Field(var label: String, var value: String, var tint: Color)
}

/** 05 · C·07 · what the photo answer adds to the panel. */
class PhotoAnswer(
    var thumbnail: ImageBitmap? = null,
    var chip: String,            // IMG · PLATE · PARSED OK
    var quote: String,           // the caption, said back in Doto
    var pulled: String,          // Pulled from photo — PRO 84/145 g · 61 g still to place
    var logged: String,          // LOGGED TO TODAY'S FUEL
) {
    override fun equals(other: Any?): Boolean =
        other is PhotoAnswer && other.chip == chip && other.quote == quote && other.pulled == pulled
    override fun hashCode(): Int = 31 * chip.hashCode() + quote.hashCode()
}

// MARK: - The renderer

/** `PanelWidgetView.Layer`. */
object PanelWidgetView {
    /** 07 · the panel is printed through a dot screen: the chart layer behind the screen, the
     *  text layer in front of it. `all` is the flat rendering the catalogue keeps. */
    enum class Layer { all, chart, text }
}

private object Slot {
    val safeX = 22.dp
    val topY = 16.dp
    val heroSmallX = 24.dp
    val heroSmallY = 44.dp
    val heroLargeY = 118.dp
    val heroRingX = 95.dp
    val heroRingY = 146.dp
    val heroRingSide = 168.dp
    val heroRefY = 56.dp
    val subY = 216.dp
    val chartY = 96.dp
    val chartBottom = 336.dp
    val sentenceX = 26.dp
    val sentenceY = 352.dp
    val sentenceW = 306.dp
    val factsY = 408.dp
    val actionY = 434.dp
}

private val W358 = 358.dp

/** SwiftUI `.lineSpacing(pt)` on a multi-line text. */
private fun TextStyle.lineSpacing(pt: Float): TextStyle = copy(
    lineHeight = (fontSize.value * 1.2f + pt).sp,
    lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.Both),
)

/** A text placed at board coordinates inside the 358-wide canvas. */
@Composable
private fun At(
    text: String,
    style: TextStyle,
    color: Color,
    x: Dp = 0.dp,
    y: Dp,
    width: Dp? = null,
    align: TextAlign = TextAlign.Start,
    maxLines: Int = Int.MAX_VALUE,
) {
    BasicText(
        text,
        Modifier.offset(x, y).then(if (width != null) Modifier.width(width) else Modifier),
        style = style.copy(color = color, textAlign = align),
        maxLines = maxLines,
    )
}

/** One-line text scaled to fit a fixed lane (`.lineLimit(1).minimumScaleFactor`), aligned in it. */
@Composable
private fun FitAt(text: String, style: TextStyle, x: Dp = 0.dp, y: Dp, width: Dp, minScale: Float,
                  alignment: Alignment = Alignment.Center) {
    Box(Modifier.offset(x, y).width(width), contentAlignment = alignment) {
        ShrinkText(text, style, minScale = minScale)
    }
}

/**
 * 07 · 03 面板解剖. Eight slots at absolute Y inside 358 × 470. Only three things are truly
 * nailed down: the top row at y16, the action at y434, and the 306-wide two-line sentence box
 * at y352. [showsCloseControl]: AIPanel reserves the top-right lane for its dismiss key.
 * [canvasHeight]: balance results use the full available panel height in board coordinates.
 */
@Composable
fun PanelWidgetView(
    widget: PanelWidget,
    onTap: (Destination) -> Unit,
    layer: PanelWidgetView.Layer = PanelWidgetView.Layer.all,
    showsCloseControl: Boolean = false,
    canvasHeight: Dp = 470.dp,
    modifier: Modifier = Modifier,
) {
    val go = { (widget.targetOverride ?: widget.type.target)?.let(onTap); Unit }
    val tapMod = when {
        // The LEDs do not take taps; the text layer above them does.
        layer == PanelWidgetView.Layer.chart -> Modifier
        // 06 · 20 · a composition result is the reading: tapping the numbers must not leave it.
        widget.composition != null || widget.balance != null -> Modifier
        // ADR-0001 · a hot zone: a touch that travels past the slop is the page drag's.
        else -> Modifier.hotZoneTap(pressedScale = 1f) { go() }
    }
    Box(
        modifier
            .semantics { contentDescription = "${L(widget.title)} · ${L(widget.sentence)}" }
            .then(tapMod)
            .size(W358, canvasHeight),
    ) {
        PanelCanvas(widget, layer, showsCloseControl, canvasHeight, go)
    }
}

@Composable
private fun BoxScope.PanelCanvas(
    widget: PanelWidget,
    layer: PanelWidgetView.Layer,
    showsCloseControl: Boolean,
    canvasHeight: Dp,
    go: () -> Unit,
) {
    val topRowWidth = W358 - Slot.safeX * 2 - (if (showsCloseControl) 42.dp else 0.dp)
    val notChart = layer != PanelWidgetView.Layer.chart
    // Photo answers sit on an opaque unlit plate, never on the orbit.
    if (widget.photo != null) UnlitField()

    val photo = widget.photo
    val composition = widget.composition
    val balance = widget.balance
    val h = widget.headline
    val plate = widget.plate
    when {
        photo != null -> PhotoCanvas(widget, photo, topRowWidth)
        composition != null -> CompositionCanvas(widget, composition, showsCloseControl, go)
        balance != null -> BalanceCanvas(widget, balance, showsCloseControl, canvasHeight)
        h != null -> if (notChart) HeadlineCanvas(widget, h, topRowWidth)
        plate != null -> if (notChart) PlateCanvas(widget, plate, topRowWidth, go)
        else -> {
            if (notChart) {
                // Slot 1 · title
                At(L(widget.title).uppercase(), NBFont.dot(500, 11.5f).tracking(0.08f), widget.accent, Slot.safeX, Slot.topY)
                // Slot 2 · tag — never takes the accent
                widget.tag?.let {
                    At(L(it.raw), NBFont.dot(600, 10f).tracking(0.24f), NB.white.copy(alpha = 0.30f),
                        Slot.safeX, Slot.topY, topRowWidth, TextAlign.End)
                }
                Hero(widget, layer)
            }
            Chart(widget, layer)
            if (notChart) {
                // Slot 6 · sentence — the brightest text on the screen
                At(L(widget.sentence), NBFont.dot(500, 14f).lineSpacing(6f), NB.white,
                    Slot.sentenceX, Slot.sentenceY, Slot.sentenceW, TextAlign.Center)
                // Slot 7 · facts
                widget.footer?.let {
                    At(it, NBFont.dot(400, 11.5f), NB.white.copy(alpha = 0.50f), y = Slot.factsY, width = W358, align = TextAlign.Center)
                }
                // Slot 8 · action
                widget.action?.let {
                    At(L(it).uppercase(), NBFont.dot(500, 10.5f).tracking(0.16f), widget.accent,
                        y = Slot.actionY, width = W358, align = TextAlign.Center)
                }
            }
        }
    }
    // ALERT is the fourth and last layer of the stack; nothing draws above it.
    if (widget.priority == PanelWidget.Priority.alert) {
        Box(Modifier.matchParentSize().background(hex(0xEF4444, 0.12f)))
    }
}

// MARK: 07 · rule 6 · TEXT — the one big word

/** eyebrow y128 · headline y168 (Doto 800 · 44, lime, the only highlight) · sub y232, then the
 *  facts line at y352, the action at y388 and a dim footnote at y434. No sentence slot. */
@Composable
private fun HeadlineCanvas(widget: PanelWidget, h: HeadlineBlock, topRowWidth: Dp) {
    At(L(widget.title).uppercase(), NBFont.dot(500, 11.5f).tracking(0.08f), widget.accent, Slot.safeX, Slot.topY)
    widget.tag?.let {
        At(L(it.raw), NBFont.dot(600, 10f).tracking(0.24f), NB.white.copy(alpha = 0.30f), Slot.safeX, Slot.topY, topRowWidth, TextAlign.End)
    }
    h.eyebrow?.let {
        At(it.uppercase(), NBFont.dot(500, 11f).tracking(0.16f), NB.white.copy(alpha = 0.45f), y = 128.dp, width = W358, align = TextAlign.Center)
    }
    FitAt(h.headline.uppercase(), NBFont.dot(800, 44f).tracking(0.02f).copy(color = NB.lime1),
        Slot.safeX, 168.dp, W358 - Slot.safeX * 2, 0.6f)
    h.sub?.let {
        At(it.uppercase(), NBFont.dot(500, 11f).tracking(0.16f), NB.white.copy(alpha = 0.55f), y = 232.dp, width = W358, align = TextAlign.Center)
    }
    At(L(widget.sentence), NBFont.dot(400, 13f), NB.white.copy(alpha = 0.72f), Slot.sentenceX, 352.dp, Slot.sentenceW, TextAlign.Center)
    widget.action?.let {
        At(L(it).uppercase(), NBFont.dot(500, 10.5f).tracking(0.16f), widget.accent, y = 388.dp, width = W358, align = TextAlign.Center)
    }
    widget.footer?.let {
        At(it.uppercase(), NBFont.dot(500, 9.5f).tracking(0.14f), NB.white.copy(alpha = 0.32f), y = Slot.actionY, width = W358, align = TextAlign.Center)
    }
}

// MARK: 07 · 20 · FOOD — one plate

/** name y104 (30) · kcal y150 (62, the hero) · the budget line y228 · three macro rows from y248
 *  · sentence y376 · the CONFIRM pill at y420, or the footer at y434 when nothing to confirm. */
@Composable
private fun PlateCanvas(widget: PanelWidget, plate: PlateBlock, topRowWidth: Dp, go: () -> Unit) {
    val macros = listOf(
        Triple("PROTEIN", plate.protein, NB.cyan1),
        Triple("CARBS", plate.carb, NB.blue1),
        Triple("FAT", plate.fat, NB.run1),
    )
    val present = macros.filter { (it.second ?: 0.0) > 0 }
    val mx = max(present.mapNotNull { it.second }.maxOrNull() ?: 1.0, 1.0)
    val lane = W358 - Slot.safeX * 2
    At(L(widget.title).uppercase(), NBFont.dot(500, 11.5f).tracking(0.08f), widget.accent, Slot.safeX, Slot.topY)
    At((plate.portion ?: widget.tag?.raw ?: "").uppercase(), NBFont.dot(600, 10f).tracking(0.24f),
        NB.white.copy(alpha = 0.30f), Slot.safeX, Slot.topY, topRowWidth, TextAlign.End)
    FitAt(plate.name, NBFont.dot(700, 30f).copy(color = NB.white), Slot.safeX, 104.dp, lane, 0.6f)
    // ⚠️ No kcal unless a tool returned one: an absent number is a long dash rather than a guess.
    FitAt(plate.kcal?.let { "${Fmt.nutrient(it)} kcal" } ?: Fmt.dash,
        NBFont.dot(700, 62f).copy(color = NB.white.copy(alpha = 0.45f)), Slot.safeX, 150.dp, lane, 0.6f)
    plate.pctOfBudget?.let {
        At(L("%d%% OF TODAY'S BUDGET", it), NBFont.dot(500, 10.5f).tracking(0.16f), NB.white.copy(alpha = 0.42f),
            y = 228.dp, width = W358, align = TextAlign.Center)
    }
    present.forEachIndexed { i, row ->
        Column(Modifier.offset(Slot.safeX, 248.dp + 44.dp * i).width(lane), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth()) {
                BasicText(L(row.first), style = NBFont.dot(600, 10f).tracking(0.14f).copy(color = row.third))
                Spacer(Modifier.weight(1f))
                BasicText("${Fmt.nutrient(row.second)} g", style = NBFont.dot(600, 10.5f).copy(color = NB.white.copy(alpha = 0.60f)))
            }
            Box(Modifier.fillMaxWidth().height(5.dp)) {
                Box(Modifier.fillMaxSize().background(NB.barTrack, CircleShape))
                Box(Modifier.width(lane * (row.second!! / mx).toFloat()).fillMaxHeight().background(row.third, CircleShape))
            }
        }
    }
    At(L(widget.sentence), NBFont.dot(500, 13f).lineSpacing(4f), NB.white, Slot.sentenceX, 376.dp, Slot.sentenceW, TextAlign.Center)
    // Slot 8 · on this canvas the action is a control (issue #22): the outlined pill, in the
    // card's own accent, never lime. The footer keeps y434 when there is nothing to confirm.
    val action = widget.action
    val footer = widget.footer
    if (action != null) {
        Box(Modifier.offset(y = 420.dp).width(W358), contentAlignment = Alignment.Center) {
            Box(
                Modifier.size(200.dp, 38.dp)
                    .border(2.5.dp, widget.accent.copy(alpha = 0.65f), CircleShape)
                    .clip(CircleShape)
                    .hotZoneTap(pressedScale = 1f) { go() },
                contentAlignment = Alignment.Center,
            ) {
                BasicText(L(action).uppercase(), style = NBFont.dot(600, 11f).tracking(0.16f).copy(color = widget.accent))
            }
        }
    } else if (footer != null) {
        At(footer.uppercase(), NBFont.dot(500, 9.5f).tracking(0.14f), NB.white.copy(alpha = 0.34f),
            y = Slot.actionY, width = W358, align = TextAlign.Center)
    }
}

// MARK: 06 · THE BALANCE FRAME

/** A Poincaré plot of the beat-to-beat intervals, the two shares under it, and one sentence.
 *  Every dot is a pair of consecutive intervals the band measured; nothing is smoothed. */
@Composable
private fun BalanceCanvas(widget: PanelWidget, b: BalanceAnswer, showsCloseControl: Boolean, canvasHeight: Dp) {
    // AIPanel owns the edge-to-edge LED surface; only standalone renders need a local ground.
    if (!showsCloseControl) UnlitField()
    Column(Modifier.size(W358, canvasHeight).padding(horizontal = 22.dp, vertical = 18.dp)) {
        Row(Modifier.fillMaxWidth()) {
            BasicText(L(widget.title).uppercase(), style = NBFont.dot(500, 11.5f).tracking(0.08f).copy(color = NB.lime1))
            Spacer(Modifier.width(16.dp))
            Spacer(Modifier.weight(1f))
            // The panel's own close mark sits in this corner; without the gap the two overlap.
            BasicText(L("JUST NOW"), Modifier.padding(end = 30.dp),
                style = NBFont.dot(600, 10f).tracking(0.24f).copy(color = NB.white.copy(alpha = 0.30f)))
        }
        BasicText(b.headline, Modifier.padding(top = 14.dp), style = NBFont.dot(500, 21f).copy(color = NB.text1))
        Box(Modifier.fillMaxWidth().padding(top = 12.dp), contentAlignment = Alignment.Center) {
            PoincarePlot(points = b.points, accent = NB.lime1, modifier = Modifier.size(214.dp))
        }
        // The two shares, as one split bar. Rest takes the accent; drive takes the amber.
        Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            BoxWithConstraints(Modifier.fillMaxWidth().height(10.dp).clip(CircleShape)) {
                val mw = maxWidth
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Box(Modifier.width(max(2.dp, mw * b.restShare.toFloat())).fillMaxHeight().background(NB.lime1))
                    Box(Modifier.weight(1f).fillMaxHeight().background(NB.ember1.copy(alpha = 0.85f)))
                }
            }
            Row(Modifier.fillMaxWidth()) {
                val pct = (b.restShare * 100).toInt()
                BasicText(L("REST %d%%", pct), style = NBFont.dot(600, 10.5f).tracking(0.16f).copy(color = NB.lime1))
                Spacer(Modifier.weight(1f))
                BasicText(L("DRIVE %d%%", 100 - pct), style = NBFont.dot(600, 10.5f).tracking(0.16f).copy(color = NB.ember1.copy(alpha = 0.9f)))
            }
        }
        BasicText(b.note, Modifier.padding(top = 12.dp),
            style = NBFont.ui(300, 13f).tracking(0.01f).copy(color = NB.text2, lineHeight = 20.sp))
        Spacer(Modifier.weight(1f))
        BasicText(b.footer, style = NBFont.dot(500, 10f).tracking(0.16f).copy(color = NB.white.copy(alpha = 0.34f)))
    }
}

/** Opaque unlit LED plate: panel ink with a 4 pt pitch of 3.2 pt unlit LEDs. */
@Composable
internal fun UnlitField(modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(NB.R.hero)
    Box(modifier.size(W358, 470.dp).clip(shape).background(NB.panelInk)) {
        Canvas(Modifier.fillMaxSize()) {
            val d = density
            val led = hex(0x131318)
            var y = 1.4f * d
            while (y < size.height) {
                var x = 1.4f * d
                while (x < size.width) {
                    drawRoundRect(led, Offset(x, y), Size(3.2f * d, 3.2f * d), CornerRadius(0.8f * d))
                    x += 4 * d
                }
                y += 4 * d
            }
        }
    }
}

// MARK: 06 · 20 · BODY COMPOSITION · JUST NOW

/** 358 × 470, its own LED ground, header at y16, hero at y70, the four tiles at y206, the
 *  sentence at y300, the spine at y378. */
@Composable
private fun CompositionCanvas(widget: PanelWidget, c: CompositionAnswer, showsCloseControl: Boolean, go: () -> Unit) {
    UnlitField()
    // header · the title in the accent, JUST NOW where the tag sits
    Row(Modifier.offset(20.dp, 16.dp).size(318.dp - (if (showsCloseControl) 42.dp else 0.dp), 14.dp),
        verticalAlignment = Alignment.CenterVertically) {
        BasicText(L(widget.title).uppercase(), style = NBFont.dot(500, 11.5f).tracking(0.08f).copy(color = NB.lime1))
        Spacer(Modifier.width(16.dp))
        Spacer(Modifier.weight(1f))
        BasicText(L("JUST NOW"), style = NBFont.dot(600, 10f).tracking(0.24f).copy(color = NB.white.copy(alpha = 0.30f)))
    }
    // hero · the number the scan settled, and where it stood last time
    Column(Modifier.offset(20.dp, 70.dp).size(318.dp, 89.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
        BasicText(widget.hero ?: Fmt.dash, style = NBFont.dot(700, 66f).copy(color = NB.lime1))
        BasicText(L(c.heroSub).uppercase(), style = NBFont.dot(600, 10f).tracking(0.24f).copy(color = NB.white.copy(alpha = 0.39f)))
    }
    // four fields · label in the field's own colour, value in white
    Row(Modifier.offset(20.dp, 206.dp).size(318.dp, 59.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        c.fields.forEach { f ->
            Column(Modifier.weight(1f).height(59.dp).background(NB.carbon5, RoundedCornerShape(14.dp)).padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterVertically)) {
                BasicText(f.label, style = NBFont.dot(600, 9f).tracking(0.16f).copy(color = f.tint))
                BasicText(f.value, style = NBFont.dot(600, 18f).copy(color = NB.white))
            }
        }
    }
    // the sentence · the brightest text on the screen
    Box(Modifier.offset(32.dp, 300.dp).size(294.dp, 52.dp), contentAlignment = Alignment.Center) {
        BasicText(L(widget.sentence), style = NBFont.dot(500, 15f).lineSpacing(6f).copy(color = NB.white, textAlign = TextAlign.Center))
    }
    // the spine · hairline, the facts, the one tap
    Column(Modifier.offset(20.dp, 378.dp).width(318.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(318.dp, 1.dp).background(NB.hairline))
        widget.footer?.let {
            BasicText(it, style = NBFont.dot(400, 11.5f).tracking(0.02f).copy(color = NB.white.copy(alpha = 0.50f)))
        }
        widget.action?.let {
            Box(Modifier.size(318.dp, 28.dp).hotZoneTap(pressedScale = 1f) { go() }, contentAlignment = Alignment.Center) {
                BasicText(L(it).uppercase(), style = NBFont.dot(600, 10.5f).tracking(0.16f).copy(color = NB.lime1.copy(alpha = 0.85f)))
            }
        }
    }
}

// MARK: 05 · C·07 · FROM YOUR PHOTO

@Composable
private fun PhotoCanvas(widget: PanelWidget, photo: PhotoAnswer, topRowWidth: Dp) {
    At(L("FROM YOUR PHOTO"), NBFont.dot(500, 11.5f).tracking(0.08f), NB.white.copy(alpha = 0.70f), Slot.safeX, Slot.topY)
    At(L("PHOTO + TEXT"), NBFont.dot(600, 10f).tracking(0.24f), NB.white.copy(alpha = 0.40f), Slot.safeX, Slot.topY, topRowWidth, TextAlign.End)
    // the source chip · 310 × 42 at y44
    val chipShape = RoundedCornerShape(12.dp)
    Row(
        Modifier.offset(24.dp, 44.dp).size(310.dp, 42.dp)
            .background(hex(0x101014), chipShape)
            .border(1.5.dp, NB.white.copy(alpha = 0.13f), chipShape)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val t = photo.thumbnail
        if (t != null) {
            Image(t, null, Modifier.size(18.dp).clip(RoundedCornerShape(4.dp)), contentScale = ContentScale.Crop)
        } else {
            Box(Modifier.size(18.dp).background(hex(0x2A2A32), RoundedCornerShape(4.dp)))
        }
        BasicText(photo.chip, style = NBFont.dot(600, 10.5f).tracking(0.14f).copy(color = NB.white.copy(alpha = 0.55f)))
    }
    // the caption, said back
    At("\"${photo.quote.uppercase()}\"", NBFont.dot(500, 11f).tracking(0.16f), NB.white.copy(alpha = 0.55f),
        y = 118.dp, width = W358, align = TextAlign.Center)
    At(L(widget.sentence), NBFont.dot(500, 17f).lineSpacing(7f), NB.white, 36.dp, 174.dp, 286.dp, TextAlign.Center)
    widget.footer?.let {
        At(it.uppercase(), NBFont.dot(700, 13f).tracking(0.18f), NB.lime1, y = 246.dp, width = W358, align = TextAlign.Center)
    }
    // two pills at y318 · the plate is already logged; the second opens fuel
    Row(Modifier.offset(y = 318.dp).width(W358), horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally)) {
        Box(Modifier.size(120.dp, 40.dp).border(2.5.dp, NB.lime1.copy(alpha = 0.6f), CircleShape), contentAlignment = Alignment.Center) {
            BasicText(L("LOG THE PLATE"), style = NBFont.dot(600, 10f).tracking(0.14f).copy(color = NB.lime1))
        }
        Box(Modifier.size(120.dp, 40.dp).border(2.dp, NB.white.copy(alpha = 0.30f), CircleShape), contentAlignment = Alignment.Center) {
            BasicText(L("SHOW FUEL"), style = NBFont.dot(600, 10f).tracking(0.14f).copy(color = NB.white.copy(alpha = 0.55f)))
        }
    }
    Box(Modifier.offset(24.dp, 381.dp).size(310.dp, 2.dp).background(hex(0x24242C)))
    At(photo.pulled, NBFont.dot(400, 11.5f), NB.white.copy(alpha = 0.50f), y = 398.dp, width = W358, align = TextAlign.Center)
    At(photo.logged, NBFont.dot(500, 10f).tracking(0.16f), NB.white.copy(alpha = 0.35f), y = 428.dp, width = W358, align = TextAlign.Center)
}

// MARK: hero

@Composable
private fun Hero(widget: PanelWidget, layer: PanelWidgetView.Layer) {
    when (widget.type.hero) {
        HeroStyle.large -> {
            FitAt(heroValue(widget), NBFont.dot(700, 84f).copy(color = NB.white.copy(alpha = 0.45f)),
                y = Slot.heroLargeY, width = W358, minScale = 0.5f)
            // 01 · metric · the reference line under the giant number, in Doto.
            widget.heroSub?.let {
                At(it.uppercase(), NBFont.dot(500, 10.5f).tracking(0.20f), NB.white.copy(alpha = 0.42f),
                    y = Slot.subY, width = W358, align = TextAlign.Center)
            }
            subText(widget)?.let {
                At(it, NBFont.dot(500, 10.5f).tracking(0.20f), NB.white.copy(alpha = 0.42f),
                    y = Slot.subY, width = W358, align = TextAlign.Center)
            }
        }
        HeroStyle.small -> {
            val size = if (widget.heroLarge) 60f else 44f
            At(heroValue(widget), NBFont.dot(700, size),
                if (widget.heroLarge) widget.accent else NB.white.copy(alpha = 0.45f), Slot.heroSmallX, Slot.heroSmallY)
            val sub = widget.heroSub
            if (widget.heroLarge && sub != null) {
                At(sub.uppercase(), NBFont.dot(500, 10.5f).tracking(0.20f), NB.white.copy(alpha = 0.42f),
                    Slot.heroSmallX + 2.dp, Slot.heroSmallY + size.dp + 14.dp)
            }
            heroRef(widget)?.let {
                At(it, NBFont.dot(600, 10.5f).tracking(0.14f), widget.accent, Slot.safeX, Slot.heroRefY,
                    W358 - Slot.safeX * 2, TextAlign.End)
            }
        }
        HeroStyle.ring -> {
            // The number inside the ring is text: on the printed panel it sits in front of the dot
            // screen while the arc sits behind it. The flat rendering leaves it to the renderer.
            if (layer == PanelWidgetView.Layer.text) {
                Box(Modifier.offset(Slot.heroRingX, Slot.heroRingY).size(Slot.heroRingSide), contentAlignment = Alignment.Center) {
                    BasicText(arcLabel(widget), style = NBFont.dot(700, 44f).copy(color = NB.white.copy(alpha = 0.45f)))
                }
                // 08 · under the ring: the value, then what it is out of.
                val d = widget.data
                if (d is PanelData.Ring && d.goal > 0) {
                    Column(Modifier.offset(y = Slot.heroRingY + Slot.heroRingSide - 34.dp).width(W358),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        BasicText(Fmt.kg(d.value, decimals = 0),
                            style = NBFont.dot(600, 12f).tracking(0.08f).copy(color = NB.white.copy(alpha = 0.55f)))
                        BasicText(L("OF %@%@", Fmt.kg(d.goal, decimals = 0), d.unit),
                            style = NBFont.dot(500, 10f).tracking(0.16f).copy(color = NB.white.copy(alpha = 0.34f)))
                    }
                }
            }
        }
        HeroStyle.own, HeroStyle.none -> Unit
    }
}

/** 08 · a ring's centre is the percentage; a gauge's and the battery's is the reading. */
private fun arcLabel(widget: PanelWidget): String = when (val d = widget.data) {
    is PanelData.Ring ->
        if (widget.type == PanelType.ring && d.goal > 0) "${(d.value / d.goal * 100).rounded().toInt()}%"
        else if (d.unit == "%") "${Fmt.kg(d.value, decimals = 0)}%" else Fmt.kg(d.value, decimals = 0)
    is PanelData.Gauge -> Fmt.kg(d.value, decimals = 0)
    else -> ""
}

private fun heroValue(widget: PanelWidget): String {
    widget.hero?.let { if (it.isNotEmpty()) return it }
    val type = widget.type
    return when (val d = widget.data) {
        // 09 · o2night's HERO is the night's average with a percent, not its last point.
        is PanelData.Series -> if (type == PanelType.o2night) {
            if (d.values.isEmpty()) Fmt.dash else "${(d.values.sum() / d.values.size).rounded().toInt()}%"
        } else d.values.lastOrNull()?.let { Fmt.kg(it) } ?: Fmt.dash
        is PanelData.Ring -> if (d.unit.isEmpty()) "${d.value.toInt()}/${d.goal.toInt()}" else "${d.value.toInt()}${d.unit}"
        is PanelData.Gauge -> Fmt.kg(d.value)
        // 09 · HERO by type: bars is the total, days the average of the days, delta the signed net.
        is PanelData.Bins -> when (type) {
            PanelType.days -> {
                val vals = d.bins.map { it.second }
                if (vals.isEmpty()) Fmt.dash else "${Fmt.kg(vals.sum() / vals.size, decimals = 1)} AVG"
            }
            PanelType.delta -> {
                val net = d.bins.sumOf { it.second }
                "${if (net > 0) "+" else ""}${Fmt.kg(net, decimals = 1)}"
            }
            else -> Fmt.kcal(d.bins.sumOf { it.second })
        }
        is PanelData.Parts -> d.parts.firstOrNull()?.let { Fmt.kcal(it.second) } ?: Fmt.dash
        // 09 · cells' HERO is "filled of total".
        is PanelData.Cells -> "${d.values.count { it > 0 }} OF ${d.values.size}"
        is PanelData.Rows -> d.items.firstOrNull()?.value ?: Fmt.dash
        // 09 · band's HERO is the day's hi/lo pair, high first; dual's is series a's last point.
        is PanelData.Pair -> if (type == PanelType.band) {
            val h = d.hi.lastOrNull()
            val l = d.lo.lastOrNull()
            if (h == null || l == null) Fmt.dash else "${Fmt.kg(h, decimals = 0)}/${Fmt.kg(l, decimals = 0)}"
        } else d.hi.lastOrNull()?.let { Fmt.kg(it) } ?: Fmt.dash
        // The trace is the RR tachogram in milliseconds — never averaged into BPM.
        is PanelData.Trace -> if (d.samples.isEmpty()) Fmt.dash
        else "${(d.samples.sum() / d.samples.size).rounded().toInt()} MS AVG"
        is PanelData.Strip -> "${d.segments.size}"
        is PanelData.Lanes -> {
            val total = d.runs.sumOf { it.second }.toInt()
            "${total / 60}H${swiftFormat("%02d", total % 60)}"
        }
        // 09 · zones' HERO is `current_zone`, which the board writes as "Z4 · 26 min".
        is PanelData.Zones -> {
            val z = d.minutes
            val top = z.indices.maxByOrNull { z[it] }
            if (top == null || z[top] <= 0) Fmt.dash else "Z${top + 1} · ${z[top].toInt()} MIN"
        }
        is PanelData.Meter -> if (d.parts.isEmpty()) Fmt.dash
        else Fmt.kg(d.parts.sumOf { it.second } / d.parts.size, decimals = 0)
        is PanelData.Verdict -> d.word
        is PanelData.Matrix -> "${d.values.count { it != 4 }} OF ${d.values.size}"
        // The reading is SDNN, not the number of dots; the server names it.
        is PanelData.Scatter -> d.stats.firstOrNull()?.second ?: (if (d.points.isEmpty()) Fmt.dash else "${d.points.size}")
        PanelData.None -> ""
    }
}

private fun heroRef(widget: PanelWidget): String? =
    (widget.data as? PanelData.Ring)?.let { "OF ${it.goal.toInt()}${it.unit}" }

private fun subText(widget: PanelWidget): String? =
    (widget.data as? PanelData.Ring)?.let { "OF ${it.goal.toInt()}${it.unit}" }

// MARK: chart

/** Which layer each renderer belongs to: shapes are LEDs and go behind the screen; rows, stacks
 *  and axis labels are text and stay in front of it. The flat rendering draws everything. */
@Composable
private fun Chart(widget: PanelWidget, layer: PanelWidgetView.Layer) {
    val h = Slot.chartBottom - Slot.chartY
    val led = layer == PanelWidgetView.Layer.chart
    val shapes = layer != PanelWidgetView.Layer.text
    val text = layer != PanelWidgetView.Layer.chart
    val isArc = widget.type.renderer == PanelRenderer.arc
    val accent = widget.accent
    val d = widget.data
    val rh = Modifier.fillMaxWidth().height(h)
    Box(
        Modifier
            .offset(if (isArc) Slot.heroRingX else Slot.safeX, if (isArc) Slot.heroRingY else Slot.chartY)
            .width(if (isArc) Slot.heroRingSide else W358 - Slot.safeX * 2),
    ) {
        when (widget.type.renderer) {
            PanelRenderer.number -> Unit
            PanelRenderer.curve -> if (shapes && d is PanelData.Series) {
                CurveRenderer(values = d.values, accent = accent, splitAt = widget.curveSplit, accent2 = widget.curveSecondary,
                    led = led, mark = widget.curveMark, marks = widget.curveMarks, modifier = rh)
            }
            PanelRenderer.pair -> if (shapes && d is PanelData.Pair) {
                PairRenderer(d.hi, d.lo, accent, led, rh)
            }
            // ⚠️ dual through the curve renderer ate one series. Two scales, one panel.
            PanelRenderer.dual -> if (shapes && d is PanelData.Pair) {
                DualRenderer(d.hi, d.lo, accent, widget.curveSecondary ?: NB.white.copy(alpha = 0.45f), led, rh)
            }
            // 09 · B · delta 用带零轴的变体.
            PanelRenderer.column -> if (d is PanelData.Bins) {
                ColumnRenderer(d.bins, accent, zeroAxis = widget.type == PanelType.delta, showBars = shapes, showLabels = text, modifier = rh)
            }
            PanelRenderer.arc -> {
                val ring = Modifier.size(Slot.heroRingSide)
                if (shapes && d is PanelData.Ring) {
                    ArcRenderer(if (d.goal > 0) d.value / d.goal else 0.0, accent, Fmt.kg(d.value, decimals = 0),
                        showLabel = layer == PanelWidgetView.Layer.all, modifier = ring)
                } else if (shapes && d is PanelData.Gauge) {
                    GaugeRenderer(d.value, d.zones, accent, showLabel = layer == PanelWidgetView.Layer.all, modifier = ring)
                }
            }
            PanelRenderer.stack -> if (text && d is PanelData.Parts) {
                StackRenderer(d.parts, minutes = widget.type == PanelType.split, modifier = rh)
            }
            PanelRenderer.grid -> if (shapes && d is PanelData.Cells) {
                GridRenderer(d.rows, d.cols, d.values, d.levels, accent, rh)
            }
            PanelRenderer.strip -> if (shapes && d is PanelData.Strip) {
                StripRenderer(d.segments, rh)
            }
            // 12 · the lanes are LEDs; their names and the two clock labels are text.
            PanelRenderer.lanes -> if (d is PanelData.Lanes) {
                LaneRenderer(d.runs, d.from, d.to, showBlocks = shapes, showLabels = text, modifier = rh)
            }
            PanelRenderer.columns -> if (d is PanelData.Zones) {
                ZoneColumnsRenderer(d.minutes, showBars = shapes, showLabels = text, modifier = rh)
            }
            PanelRenderer.trace -> if (shapes && d is PanelData.Trace) {
                TraceRenderer(d.samples, d.hz, accent, led, rh)
            }
            PanelRenderer.rows -> if (text && d is PanelData.Rows) {
                RowsRenderer(d.items, accent, rh)
            }
            PanelRenderer.meter -> if (d is PanelData.Meter) {
                MeterRenderer(d.parts, accent, showBars = shapes, showLabels = text, modifier = rh)
            }
            PanelRenderer.scatter -> if (d is PanelData.Scatter) {
                ScatterRenderer(d.points, d.lo, d.hi, d.stats, accent, showCloud = shapes, showLabels = text, modifier = rh)
            }
            PanelRenderer.matrix -> if (d is PanelData.Matrix) {
                MatrixRenderer(d.rows, d.cols, d.values, d.rowLabels, showCells = shapes, showLabels = text, modifier = rh)
            }
            PanelRenderer.verdict -> if (d is PanelData.Verdict) {
                VerdictRenderer(d.word, d.options, d.confidence, d.steps, accent, showBars = shapes, showLabels = text, modifier = rh)
            }
        }
    }
}
