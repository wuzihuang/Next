package com.nextbody.hoop.features.fuel

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.FuelClockPoint
import com.nextbody.hoop.band.FuelDayFacts
import com.nextbody.hoop.band.FuelWindowMath
import com.nextbody.hoop.band.MealMicroTotals
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.data.MealEntry
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.isSameDay
import com.nextbody.hoop.services.MealPhotoStore
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.lineSkin
import java.time.Instant

// MARK: text helper

/**
 * SwiftUI `Text` with `.lineLimit(maxLines)` and `.minimumScaleFactor(minScale)`: the style
 * shrinks (down to [minScale]) until the text fits instead of truncating first.
 */
@Composable
internal fun FitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 1f,
    maxLines: Int = 1,
    align: TextAlign? = null,
) {
    var scale by remember(text, style) { mutableFloatStateOf(1f) }
    val sized = if (scale == 1f) style else style.copy(
        fontSize = style.fontSize * scale,
        letterSpacing = style.letterSpacing,
    )
    Text(
        text = text,
        modifier = modifier,
        style = sized,
        color = color,
        maxLines = maxLines,
        softWrap = maxLines > 1,
        overflow = if (scale <= minScale) TextOverflow.Ellipsis else TextOverflow.Clip,
        textAlign = align,
        onTextLayout = { layout ->
            if (layout.hasVisualOverflow && scale > minScale) {
                scale = maxOf(minScale, scale * 0.92f)
            }
        },
    )
}

/** Paper 09H · stacked IN / OUT / DIFF. Five-digit Doto never sits side by side. */
@Composable
fun FuelStackedHero(intake: String, burned: String, gap: String, gapTint: Color = NB.cyan1) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        HeroRow(L("IN"), intake, NB.ember1)
        HeroRow(L("OUT"), burned, NB.cyan1)
        HeroRow(L("DIFF"), gap, gapTint)
    }
}

@Composable
private fun HeroRow(label: String, value: String, tint: Color) {
    Row(Modifier.fillMaxWidth()) {
        FitText(label, NBFont.ui(500, 11f).tracking(0.12f), NB.text3Prod, Modifier.alignByBaseline())
        // 8 + 8 + 8, as SwiftUI spaces around the Spacer
        Spacer(Modifier.width(24.dp))
        FitText(value, NBFont.dot(700, 28f).tracking(-0.02f), tint, Modifier.alignByBaseline().weight(1f), minScale = 0.7f,
            align = TextAlign.End)
    }
}

/** 09E-C / 09H-A · 24h clock. Orange step is IN, cyan burn follows movement, white is NOW. */
@Composable
fun FuelDayChart(
    meals: List<Pair<Instant, Double>>,
    burnedNow: Double?,
    restingNow: Double?,
    burnedAt: Instant,
    burnedFull: Double?,
    budget: Double?,
    now: Instant,
    dayStart: Instant,
    happenedIntake: Double,
    burnTicks: List<VitalSample> = emptyList(),
    outUnknown: Boolean = false,
) {
    val maxY = FuelWindowMath.chartMax(budget = budget, intake = happenedIntake,
        burnedNow = burnedNow, burnedFull = burnedFull)
    val intake = FuelWindowMath.intakeSteps(meals = meals, dayStart = dayStart, now = now, projectTo = budget)
    val burn = burnedNow?.let {
        FuelWindowMath.burnCurve(dayStart = dayStart, now = minOf(now, burnedAt), burnedNow = it,
            burnedFull = burnedFull, restingNow = restingNow, ticks = burnTicks)
    }
    val nowX = FuelWindowMath.clockFraction(at = now, dayStart = dayStart)
    val label = L("THE DAY SO FAR")
    val value = L("IN %@ · OUT %@", Fmt.kcal(happenedIntake), if (outUnknown) Fmt.dash else Fmt.kcal(burnedNow))
    Column(
        Modifier.clearAndSetSemantics { contentDescription = label; stateDescription = value },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Canvas(Modifier.fillMaxWidth().height(148.dp)) {
            val w = size.width
            val h = size.height
            fun px(p: FuelClockPoint): Offset = Offset((w * p.x).toFloat(), (h * (1 - p.y / maxY)).toFloat())
            if (budget != null && budget > 0) {
                val y = (h * (1 - budget / maxY)).toFloat()
                drawLine(NB.white.copy(alpha = 0.22f), Offset(0f, y), Offset(w, y), strokeWidth = 1.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())))
            }
            if (!outUnknown && burn != null) {
                val fill = band(intake.solid, burn.solid, ::px)
                if (fill != null) drawPath(fill, NB.lime2.copy(alpha = 0.14f))
                strokePoints(burn.solid, ::px, NB.cyan1, dashed = false)
                strokePoints(burn.dashed, ::px, NB.cyan1, dashed = true)
            }
            strokePoints(intake.solid, ::px, NB.ember1, dashed = false)
            strokePoints(intake.dashed, ::px, NB.ember1, dashed = true)

            val nx = (w * nowX).toFloat()
            drawLine(NB.white.copy(alpha = 0.85f), Offset(nx, 0f), Offset(nx, h), strokeWidth = 1.dp.toPx())

            intake.solid.lastOrNull()?.let { drawCircle(NB.ember1, 3.5.dp.toPx(), px(it)) }
            if (!outUnknown) burn?.solid?.lastOrNull()?.let { drawCircle(NB.cyan1, 3.5.dp.toPx(), px(it)) }
        }
        Row(Modifier.fillMaxWidth()) {
            val labels = FuelWindowMath.clockLabels(dayStart = dayStart)
            labels.forEachIndexed { index, text ->
                Text(text, style = NBFont.dot(if (index == 4) 700 else 500, 9f),
                    color = if (index == 4) NB.ember1 else NB.white.copy(alpha = 0.34f), maxLines = 1)
                if (index < 4) Spacer(Modifier.weight(1f))
            }
        }
    }
}

private fun DrawScope.strokePoints(points: List<FuelClockPoint>, px: (FuelClockPoint) -> Offset,
                                   color: Color, dashed: Boolean) {
    if (points.size < 2) return
    val path = Path()
    val first = px(points[0])
    path.moveTo(first.x, first.y)
    for (p in points.drop(1)) { val o = px(p); path.lineTo(o.x, o.y) }
    drawPath(path, color, style = Stroke(
        width = 2.dp.toPx(),
        pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx())) else null,
    ))
}

private fun band(intake: List<FuelClockPoint>, burn: List<FuelClockPoint>, px: (FuelClockPoint) -> Offset): Path? {
    if (intake.size < 2 || burn.size < 2) return null
    val path = Path()
    val first = px(intake[0])
    path.moveTo(first.x, first.y)
    for (p in intake.drop(1)) { val o = px(p); path.lineTo(o.x, o.y) }
    for (p in burn.reversed()) { val o = px(p); path.lineTo(o.x, o.y) }
    path.close()
    return path
}

@Composable
fun FuelWeekBars(days: List<FuelDayFacts>, budget: Double?) {
    val maxY = FuelWindowMath.chartMax(
        budget = budget,
        intake = days.mapNotNull { it.intake }.maxOrNull() ?: 0.0,
        burnedNow = days.mapNotNull { it.burned }.maxOrNull(),
        burnedFull = null)
    val label = L("THIS WEEK")
    Column(Modifier.clearAndSetSemantics { contentDescription = label }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(132.dp)) {
            val h = maxHeight
            if (budget != null && budget > 0) {
                Box(Modifier.offset(y = h * (1 - budget / maxY).toFloat()).width(maxWidth).height(1.dp)
                    .background(NB.white.copy(alpha = 0.22f)))
            }
            Row(Modifier.fillMaxWidth().height(h), verticalAlignment = Alignment.Bottom) {
                days.forEach { row ->
                    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.Bottom) {
                        Bar(row.intake, NB.ember1, h, maxY, 9.dp, 2.dp)
                        Bar(row.burned, NB.cyan1, h, maxY, 9.dp, 2.dp)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            days.forEachIndexed { i, row ->
                val last = i == days.size - 1
                Text(Fmt.weekday(row.day.date).take(2), Modifier.weight(1f),
                    style = NBFont.dot(if (last) 700 else 500, 9f),
                    color = if (last) NB.ember1 else NB.white.copy(alpha = 0.34f),
                    textAlign = TextAlign.Center, maxLines = 1)
            }
        }
    }
}

@Composable
private fun Bar(value: Double?, tint: Color, height: Dp, maxY: Double, width: Dp, radius: Dp) {
    val fraction = (value ?: 0.0) / maxY
    val barHeight = maxOf(if (value == null) 0.dp else 3.dp, height * fraction.toFloat())
    Box(Modifier.size(width, barHeight)
        .background(if (value == null) Color.Transparent else tint, RoundedCornerShape(radius)))
}

@Composable
fun FuelMonthBars(days: List<FuelDayFacts>, budget: Double?) {
    val chunks = days.chunked(7)
    val maxY = FuelWindowMath.chartMax(
        budget = budget,
        intake = days.mapNotNull { it.intake }.maxOrNull() ?: 0.0,
        burnedNow = null, burnedFull = null)
    val label = L("A TYPICAL DAY")
    Column(Modifier.clearAndSetSemantics { contentDescription = label }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(120.dp)) {
            val h = maxHeight
            if (budget != null && budget > 0) {
                Box(Modifier.offset(y = h * (1 - budget / maxY).toFloat()).width(maxWidth).height(1.dp)
                    .background(NB.white.copy(alpha = 0.22f)))
            }
            Row(Modifier.fillMaxWidth().height(h), horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Bottom) {
                chunks.forEach { week ->
                    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.Bottom) {
                        week.forEach { row -> Bar(row.intake, NB.ember1, h, maxY, 6.dp, 1.5.dp) }
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            chunks.forEachIndexed { i, week ->
                val last = i == chunks.size - 1
                val mark = monthMark(week.firstOrNull()?.day)
                FitText(if (last) L("%@ · NOW", mark) else mark,
                    NBFont.dot(if (last) 700 else 500, 9f),
                    if (last) NB.ember1 else NB.white.copy(alpha = 0.34f),
                    Modifier.weight(1f), minScale = 0.7f)
            }
        }
    }
}

private fun monthMark(day: UserDay?): String {
    if (day == null) return ""
    return Fmt.displayDate(day.date, "d MMM").uppercase()
}

/** Fixed-width ledger. Numbers never share a slot and never wrap. */
@Composable
fun FuelLedgerTable(
    title: String,
    trailing: String,
    dayHeader: String,
    rows: List<FuelLedgerRow>,
    footer: FuelLedgerRow? = null,
) {
    Column(Modifier.width(NB.Layout.contentWidth).lineSkin(top = 16.dp)) {
        Row(Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
            Text(title, style = NBFont.ui(500, 11f).tracking(0.2f), color = NB.text3Prod, maxLines = 1)
            Spacer(Modifier.width(16.dp))
            Text(trailing, style = NBFont.ui(500, 11f).tracking(0.06f), color = NB.text3Prod, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f), textAlign = TextAlign.End)
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 6.dp)) {
            Text(dayHeader, Modifier.width(110.dp), style = NBFont.ui(500, 10f).tracking(0.12f), color = NB.text3Prod)
            HeaderCell(L("IN"), NB.ember1)
            HeaderCell(L("OUT"), NB.cyan1)
            HeaderCell(L("DIFF"), NB.text3Prod)
        }
        rows.forEach { row ->
            Hairline()
            LedgerRow(row)
        }
        if (footer != null) {
            Hairline()
            LedgerRow(footer, muted = true)
        }
    }
}

@Composable
private fun HeaderCell(title: String, tint: Color) {
    Text(title, Modifier.width(72.dp), style = NBFont.ui(500, 10f).tracking(0.12f), color = tint,
        maxLines = 1, textAlign = TextAlign.End)
}

@Composable
private fun LedgerRow(row: FuelLedgerRow, muted: Boolean = false) {
    val label = "${row.title} ${row.caption ?: ""} ${row.intake} ${row.burned} ${row.gap}"
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp).clearAndSetSemantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.width(110.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(row.title, style = NBFont.ui(if (muted) 500 else 600, 13f),
                color = if (muted) NB.text3Prod else NB.text1, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (row.caption != null) {
                Text(row.caption, style = NBFont.ui(500, 10f).tracking(0.04f), color = row.captionTint, maxLines = 3)
            }
        }
        NumberCell(row.intake, NB.ember1)
        NumberCell(row.burned, NB.cyan1)
        NumberCell(row.gap, row.gapTint)
    }
}

@Composable
private fun NumberCell(value: String, tint: Color) {
    FitText(value, NBFont.ui(600, 15f), tint, Modifier.width(72.dp), minScale = 0.7f, align = TextAlign.End)
}

data class FuelLedgerRow(
    val id: String,
    val title: String,
    val caption: String? = null,
    val captionTint: Color = NB.text3Prod,
    val intake: String,
    val burned: String,
    val gap: String,
    val gapTint: Color = NB.cyan1,
)

/**
 * A plate that is being read right now. AI is off on this build (`AIFeature.enabled = false`),
 * so nothing ever sets one; the type stays so the table's shape matches iOS.
 */
data class ReadingPlate(val at: Instant, val caption: String)

/** One flat meal list. TIME / ITEM / KCAL / P / C / F — no breakfast / lunch / dinner groups. */
@Composable
fun FuelFoodTable(
    meals: List<MealEntry>,
    trailing: String,
    reading: ReadingPlate? = null,
    onSelect: (MealEntry) -> Unit,
) {
    Column(Modifier.width(NB.Layout.contentWidth).lineSkin(top = 16.dp)) {
        Row(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
            Text(L("FOOD"), style = NBFont.ui(500, 11f).tracking(0.2f), color = NB.text3Prod)
            Spacer(Modifier.width(16.dp))
            FitText(trailing, NBFont.dot(700, 12f).tracking(0.04f), NB.ember1, Modifier.weight(1f), minScale = 0.7f,
                align = TextAlign.End)
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 6.dp)) {
            Col(L("TIME"), 46.dp, TextAlign.Start, NB.text3Prod, tracking = true)
            Col(L("ITEM"), null, TextAlign.Start, NB.text3Prod, tracking = true)
            Col(L("KCAL"), 56.dp, TextAlign.End, NB.text3Prod, tracking = true)
            Col(L("P"), 40.dp, TextAlign.End, NB.violet1, tracking = true)
            Col(L("C"), 40.dp, TextAlign.End, NB.optimal2, tracking = true)
            Col(L("F"), 40.dp, TextAlign.End, NB.run1, tracking = true)
        }
        meals.forEach { meal ->
            Hairline()
            Box(Modifier.hotZoneTap(pressedOpacity = 1f, pressedScale = 1f) { onSelect(meal) }) { FoodRow(meal) }
        }
        if (reading != null) {
            Hairline()
            ReadingRow(reading)
        }
        if (meals.isNotEmpty()) {
            Hairline()
            Totals(meals)
            Micros(meals)
        }
    }
}

/** Fibre, sugar and sodium for the day, when every row could say. One silent row and the
 *  line says how many — a part-day sum printed as a day would be the same lie as a 0 kcal plate. */
@Composable
private fun Micros(meals: List<MealEntry>) {
    val fiber = meals.map { it.fiber }
    val sugar = meals.map { it.sugar }
    val sodium = meals.map { it.sodium }
    if (MealMicroTotals.anyKnown(fiber) || MealMicroTotals.anyKnown(sugar) || MealMicroTotals.anyKnown(sodium)) {
        Row(Modifier.fillMaxWidth().padding(top = 10.dp)) {
            MicroCell(L("FIBER"), MealMicroTotals.total(fiber), L("G"), MealMicroTotals.unknownCount(fiber))
            MicroCell(L("SUGAR"), MealMicroTotals.total(sugar), L("G"), MealMicroTotals.unknownCount(sugar))
            MicroCell(L("SODIUM"), MealMicroTotals.total(sodium), L("MG"), MealMicroTotals.unknownCount(sodium))
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.MicroCell(label: String, value: Double?, unit: String, missing: Int) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(label, style = NBFont.ui(500, 10f).tracking(0.12f), color = NB.text3Prod)
        Text(value?.let { "${Fmt.nutrient(it)} $unit" } ?: Fmt.dash, style = NBFont.dot(700, 13f).tracking(0.02f),
            color = if (value == null) NB.white.copy(alpha = 0.32f) else NB.text1)
        if (value == null && missing > 0) {
            Text(L("%d rows unknown", missing), style = NBFont.ui(400, 9.5f), color = NB.white.copy(alpha = 0.28f))
        }
    }
}

/** ⚠️ The numbers column says READING, not 0 and not a spinner's worth of guessed kcal. */
@Composable
private fun ReadingRow(plate: ReadingPlate) {
    Row(Modifier.fillMaxWidth().height(38.dp), verticalAlignment = Alignment.CenterVertically) {
        Col(Fmt.clock(plate.at), 46.dp, TextAlign.Start, NB.text3Prod, size = 12f)
        Box(Modifier.weight(1f)) {
            FitText(plate.caption.ifEmpty { L("THE PLATE") }, NBFont.ui(600, 14f), NB.white.copy(alpha = 0.52f), minScale = 0.8f)
        }
        Text(L("READING"), Modifier.width(176.dp), style = NBFont.dot(600, 11f).tracking(0.12f),
            color = NB.ember1.copy(alpha = 0.8f), textAlign = TextAlign.End)
    }
}

@Composable
private fun FoodRow(meal: MealEntry) {
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Col(clock(meal), 46.dp, TextAlign.Start, NB.text3Prod, size = 12f)
        // The columns stay fixed-width and unwrapped; the plate's own evidence rides inside the
        // one flexible cell — a thumbnail when photographed, and the portion, dim, after the name.
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            if (meal.photoPath != null) MealThumbnail(meal.photoPath, side = 22.dp, radius = 6.dp)
            FitText(meal.text.ifEmpty { L(meal.slot.raw) }, NBFont.ui(600, 14f), NB.text1,
                Modifier.weight(1f, fill = false), minScale = 0.8f)
            val portion = meal.portion
            if (!portion.isNullOrEmpty()) {
                Text(portion, Modifier.weight(1f, fill = false), style = NBFont.ui(400, 11.5f),
                    color = NB.white.copy(alpha = 0.36f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Col(Fmt.nutrient(meal.kcal), 56.dp, TextAlign.End, NB.ember1, size = 14f, weight = 600)
        Col(Fmt.nutrient(meal.protein), 40.dp, TextAlign.End, NB.violet1, size = 13f, weight = 600)
        Col(Fmt.nutrient(meal.carb), 40.dp, TextAlign.End, NB.optimal2, size = 13f, weight = 600)
        Col(Fmt.nutrient(meal.fat), 40.dp, TextAlign.End, NB.run1, size = 13f, weight = 600)
    }
}

@Composable
private fun Totals(meals: List<MealEntry>) {
    Row(Modifier.fillMaxWidth().padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(L("LOGGED"), Modifier.weight(1f), style = NBFont.ui(600, 11f).tracking(0.12f), color = NB.text2, maxLines = 1)
        Col(Fmt.nutrient(meals.sumOf { it.kcal }), 56.dp, TextAlign.End, NB.text1, size = 14f, weight = 600)
        Col(Fmt.nutrient(meals.sumOf { it.protein }), 40.dp, TextAlign.End, NB.violet1, size = 13f, weight = 600)
        Col(Fmt.nutrient(meals.sumOf { it.carb }), 40.dp, TextAlign.End, NB.optimal2, size = 13f, weight = 600)
        Col(Fmt.nutrient(meals.sumOf { it.fat }), 40.dp, TextAlign.End, NB.run1, size = 13f, weight = 600)
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.Col(
    text: String, width: Dp?, align: TextAlign, tint: Color,
    size: Float = 10f, weight: Int = 500, tracking: Boolean = false,
) {
    val style = NBFont.ui(weight, size).tracking(if (tracking) 0.12f else 0f)
    val m = if (width == null) Modifier.weight(1f) else Modifier.width(width)
    FitText(text, style, tint, m, minScale = 0.7f, align = align)
}

private fun clock(meal: MealEntry): String {
    val clock = Fmt.clock(meal.at)
    val same = meal.at.isSameDay(meal.day.start)
    return if (same) clock else "$clock+1"
}

/** A plate thumbnail that fills its frame, or an empty carbon tile while there is nothing to show.
 *  (Swift: `MealThumbnail` in Services/MealPhotoStore.swift.) */
@Composable
internal fun MealThumbnail(path: String?, side: Dp = 44.dp, radius: Dp = 10.dp) {
    val generation by MealPhotoStore.generation.collectAsState()
    val image = remember(path, generation) { MealPhotoStore.image(path) }
    val shape = RoundedCornerShape(radius)
    if (image != null) {
        Image(image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop,
            modifier = Modifier.size(side).clip(shape))
    } else {
        Box(Modifier.size(side).background(NB.carbon3, shape).border(1.dp, NB.hairline, shape))
    }
}
