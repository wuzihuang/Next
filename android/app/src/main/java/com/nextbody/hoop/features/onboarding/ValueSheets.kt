package com.nextbody.hoop.features.onboarding

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.auth.GText
import com.nextbody.hoop.features.auth.localDate
import com.nextbody.hoop.features.auth.plainTap
import com.nextbody.hoop.features.auth.startInstant
import com.nextbody.hoop.features.connect.LimePillButton
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.ImpactStyle
import kotlinx.coroutines.flow.distinctUntilChanged
import java.time.LocalDate
import java.time.Period
import java.time.YearMonth
import java.time.format.TextStyle
import kotlin.math.roundToInt

// 03 · three sheets, one rule: change a value without leaving the table.
//  01 the sheet never passes 62% of the screen; the screen underneath keeps its title and a value row
//  02 it opens on the current value — not empty, not the median
//  03 once really edited, HEALTH becomes EDIT for good
//  04 Save is the only commit. Swiping down = discard, same as Cancel, and nothing asks "are you sure"
//  05 the unit is a property of the account, switched here once and honoured everywhere
//  06 all three must work one-handed: draggable in the right half, Save under the thumb
//  07 sex has no sheet — two options do not deserve a panel

@Composable
private fun SheetShell(
    title: String,
    trailing: (@Composable () -> Unit)?,
    saveTitle: String,
    showCancel: Boolean = false,
    onSave: () -> Unit,
    onCancel: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxSize().background(NB.carbon2), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 22.dp), verticalAlignment = Alignment.CenterVertically) {
            GText(title, NBFont.ui(500, 20f).tracking(0.01f), NB.text1, Modifier.weight(1f))
            Spacer(Modifier.width(16.dp)) // 8 + 0 + 8, as SwiftUI spaces around the Spacer
            trailing?.invoke()
        }
        content()
        Spacer(Modifier.weight(1f))
        LimePillButton(L(saveTitle), modifier = Modifier.padding(bottom = if (showCancel) 8.dp else 22.dp), action = onSave)
        if (showCancel && onCancel != null) {
            GText(L("Cancel"), NBFont.ui(400, 13f).tracking(0.02f), NB.white.copy(alpha = 0.42f),
                Modifier.padding(bottom = 22.dp).plainTap(onClick = onCancel))
        }
    }
}

@Composable
fun UnitToggle(options: List<String>, selection: String, onSelect: (String) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (o in options) {
            val on = selection == o
            Box(
                Modifier.height(26.dp)
                    .background(if (on) NB.lime1 else NB.lime1.copy(alpha = 0f), CircleShape)
                    .let { if (!on) it.border(1.dp, NB.hairline, CircleShape) else it }
                    .plainTap { onSelect(o) }
                    .padding(horizontal = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                GText(o, NBFont.ui(500, 11f).tracking(0.12f), if (on) NB.carbon else NB.white.copy(alpha = 0.5f))
            }
        }
    }
}

/** The system `.alert` with a text field: title, one field, Set and Cancel. */
@Composable
private fun TypeAlert(title: String, placeholder: String, decimal: Boolean, onSet: (String) -> Unit, onDismiss: () -> Unit) {
    var typed by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, style = NBFont.ui(500, 17f), color = NB.text1) },
        text = {
            Box(Modifier.fillMaxWidth().background(NB.carbon4, RoundedCornerShape(8.dp)).padding(10.dp)) {
                if (typed.isEmpty()) GText(placeholder, NBFont.ui(400, 17f), NB.white.copy(alpha = 0.3f))
                BasicTextField(typed, { typed = it }, singleLine = true,
                    textStyle = NBFont.ui(400, 17f).copy(color = NB.text1), cursorBrush = SolidColor(NB.lime1),
                    keyboardOptions = KeyboardOptions(keyboardType = if (decimal) KeyboardType.Decimal else KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = { TextButton(onClick = { onSet(typed); onDismiss() }) { Text(L("Set"), color = NB.lime1) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(L("Cancel"), color = NB.text2) } },
        containerColor = NB.carbon4,
    )
}

// MARK: 1 · WEIGHT · RULER

/**
 * The ruler starts on the number that came back from the sync, never on a round number in the
 * middle. One notch is 0.1 kg with a light haptic per whole unit.
 */
@Composable
fun WeightRulerSheet(value: Double, onSave: (Double) -> Unit) {
    var unit by remember { mutableStateOf("KG") }
    var draft by remember { mutableDoubleStateOf(value) }
    var lastWhole by remember { mutableIntStateOf(value.toInt()) }
    var typing by remember { mutableStateOf(false) }
    val display = if (unit == "KG") draft else draft * 2.2046226

    SheetShell(title = L("Weight"), trailing = { UnitToggle(listOf("KG", "LB"), unit) { unit = it } },
        saveTitle = "Save", onSave = { onSave(draft) }) {
        // "tap the number to type" is mandatory: dragging from 63 to 95 is thirty seconds of shaking.
        Row(Modifier.padding(top = 34.dp).plainTap { typing = true }, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            GText(String.format(java.util.Locale.US, "%.1f", display), NBFont.brand(700, 64f).tracking(-0.045f), NB.text1,
                Modifier.alignByBaseline(), maxLines = 1)
            GText(unit.lowercase(), NBFont.ui(300, 18f), NB.white.copy(alpha = 0.42f), Modifier.alignByBaseline())
        }
        HorizontalRuler(draft, {
            draft = it
            if (it.toInt() != lastWhole) {
                lastWhole = it.toInt()
                Haptics.impact(ImpactStyle.Light)
            }
        }, 30.0..200.0, 0.1, 10, Modifier.padding(top = 26.dp).fillMaxWidth().height(74.dp))
        GText(L("Drag the ruler, or tap the number to type"), NBFont.ui(300, 12.5f).tracking(0.02f),
            NB.white.copy(alpha = 0.38f), Modifier.padding(top = 18.dp))
    }
    if (typing) {
        TypeAlert(L("Weight"), "kg", decimal = true, onSet = { s ->
            s.replace(',', '.').toDoubleOrNull()?.let { d -> draft = if (unit == "KG") d else d / 2.2046226 }
        }, onDismiss = { typing = false })
    }
}

@Composable
fun HorizontalRuler(
    value: Double,
    onValue: (Double) -> Unit,
    range: ClosedFloatingPointRange<Double>,
    step: Double,
    majorEvery: Int,
    modifier: Modifier = Modifier,
) {
    val measurer = rememberTextMeasurer()
    val current by rememberUpdatedState(value)
    val set by rememberUpdatedState(onValue)
    val label = NBFont.dot(500, 10f).copy(color = NB.white.copy(alpha = 0.34f))
    Canvas(
        modifier.pointerInput(Unit) {
            val pitch = 9.dp.toPx()
            var total = 0f
            detectDragGestures(onDragStart = { total = 0f }) { change, drag ->
                change.consume()
                total += drag.x
                // The same accumulation SwiftUI's DragGesture gives: the whole translation,
                // a twelfth of it, on every change.
                val delta = -(total / pitch) * step
                set((current + delta / 12).coerceIn(range.start, range.endInclusive))
            }
        },
    ) {
        val u = density
        val pitch = 9f * u
        val mid = size.width / 2
        val first = ((value - (mid / pitch) * step) / step).roundToInt()
        val count = (size.width / pitch).toInt() + 2
        for (i in 0 until count) {
            val idx = first + i
            val v = idx * step
            if (v < range.start - 1e-9 || v > range.endInclusive + 1e-9) continue
            val x = mid + ((v - value) / step).toFloat() * pitch
            val major = idx % majorEvery == 0
            val h = (if (major) 26f else 14f) * u
            drawRect(NB.white.copy(alpha = if (major) 0.55f else 0.22f), Offset(x, 24f * u - h / 2), Size(1.4f * u, h))
            if (major) {
                val text = measurer.measure(String.format(java.util.Locale.US, "%.0f", v), label)
                drawText(text, topLeft = Offset(x - text.size.width / 2f, 52f * u - text.size.height / 2f))
            }
        }
        drawRect(NB.lime1, Offset(mid - 1f * u, 24f * u - 17f * u), Size(2f * u, 34f * u))
    }
}

// MARK: 2 · HEIGHT · VERTICAL

/**
 * The same ruler, turned upright — the axis follows the quantity. Numbers on the left, ticks on
 * the right, because a thumb only reaches the right edge.
 */
@Composable
fun HeightRulerSheet(value: Double, onSave: (Double) -> Unit) {
    var unit by remember { mutableStateOf("CM") }
    var draft by remember { mutableDoubleStateOf(value) }
    var typing by remember { mutableStateOf(false) }
    fun feetInches(cm: Double): String {
        val inches = (cm / 2.54).toInt()
        return "${inches / 12}'${inches % 12}\""
    }
    SheetShell(title = L("Height"), trailing = { UnitToggle(listOf("CM", "FT"), unit) { unit = it } },
        saveTitle = "Save", onSave = { onSave(draft.coerceIn(120.0, 220.0)) }) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(Modifier.padding(start = 24.dp, top = 30.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(Modifier.plainTap { typing = true }, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    GText(if (unit == "CM") "${draft.toInt()}" else feetInches(draft), NBFont.brand(700, 64f).tracking(-0.045f),
                        NB.text1, Modifier.alignByBaseline(), maxLines = 1)
                    GText(unit.lowercase(), NBFont.ui(300, 18f), NB.white.copy(alpha = 0.42f), Modifier.alignByBaseline())
                }
                GText(L("Drag the scale, or tap the number to type"), NBFont.ui(300, 12.5f).tracking(0.02f),
                    NB.white.copy(alpha = 0.38f), Modifier.width(190.dp))
            }
            Spacer(Modifier.weight(1f))
            VerticalRuler(draft, { draft = it }, 120.0..220.0,
                Modifier.padding(end = 20.dp, top = 8.dp).size(96.dp, 250.dp))
        }
    }
    if (typing) {
        TypeAlert(L("Height"), "cm", decimal = false, onSet = { s ->
            s.toDoubleOrNull()?.takeIf { it in 120.0..220.0 }?.let { draft = it }
        }, onDismiss = { typing = false })
    }
}

@Composable
fun VerticalRuler(value: Double, onValue: (Double) -> Unit, range: ClosedFloatingPointRange<Double>, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val current by rememberUpdatedState(value)
    val set by rememberUpdatedState(onValue)
    val label = NBFont.dot(500, 10f).copy(color = NB.white.copy(alpha = 0.34f))
    Canvas(
        modifier.pointerInput(Unit) {
            val pitch = 11.dp.toPx()
            var total = 0f
            detectDragGestures(onDragStart = { total = 0f }) { change, drag ->
                change.consume()
                total += drag.y
                set((current + (total / pitch) / 10).coerceIn(range.start, range.endInclusive))
            }
        },
    ) {
        val u = density
        val pitch = 11f * u
        val mid = size.height / 2
        val count = (size.height / pitch).toInt() + 2
        val first = (value - mid / pitch).toInt()
        for (i in 0 until count) {
            val v = (first + i).toDouble()
            if (v < range.start || v > range.endInclusive) continue
            val y = mid - ((v - value) * pitch).toFloat()
            val major = v.toInt() % 5 == 0
            val w = (if (major) 30f else 18f) * u
            drawRect(NB.white.copy(alpha = if (major) 0.5f else 0.2f), Offset(size.width - w, y), Size(w, 1.4f * u))
            if (v.toInt() % 10 == 0) {
                val text = measurer.measure("${v.toInt()}", label)
                drawText(text, topLeft = Offset(size.width - 46f * u - text.size.width / 2f, y - text.size.height / 2f))
            }
        }
        drawRect(NB.lime1, Offset(size.width - 46f * u, mid - 1f * u), Size(46f * u, 2f * u))
    }
}

// MARK: 3 · BIRTHDAY · HAS CANCEL

/**
 * AGE 28 in the top-right tracks the wheel live. A birthday is the one field of the four a user
 * cannot "feel is wrong", so the derived age sits next to it. It is also the only sheet with a
 * Cancel — a wheel has no "untouched" state, so one slip has already committed.
 */
@Composable
fun BirthdayWheelSheet(value: LocalDate, onSave: (LocalDate) -> Unit, onCancel: () -> Unit) {
    var date by remember { mutableStateOf(value.coerceAtMost(LocalDate.now())) }
    val age = Period.between(date, LocalDate.now()).years
    SheetShell(
        title = L("Birthday"),
        trailing = { GText(L("AGE %d", age), NBFont.dot(600, 10f).tracking(0.24f), NB.lime1) },
        saveTitle = "Save", showCancel = true,
        onSave = { onSave(date) }, onCancel = onCancel,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            DateWheel(date, { date = it }, Modifier.padding(top = 10.dp).fillMaxWidth().height(190.dp))
            GText(L("Age drives the body-composition model — worth getting right."), NBFont.ui(300, 12.5f).tracking(0.02f),
                NB.white.copy(alpha = 0.38f), Modifier.width(300.dp), align = TextAlign.Center)
        }
    }
}

/** `DatePicker(.wheel)`: three wheels in the locale's order, capped at today. */
@Composable
private fun DateWheel(date: LocalDate, onDate: (LocalDate) -> Unit, modifier: Modifier) {
    val today = LocalDate.now()
    val locale = AppLanguage.locale.javaLocale
    val years = (1900..today.year).toList()
    val months = (1..12).toList()
    val days = (1..YearMonth.of(date.year, date.monthValue).lengthOfMonth()).toList()
    fun clamp(y: Int, m: Int, d: Int): LocalDate {
        val len = YearMonth.of(y, m).lengthOfMonth()
        return LocalDate.of(y, m, d.coerceAtMost(len)).coerceAtMost(today)
    }
    val monthName = { m: Int -> java.time.Month.of(m).getDisplayName(TextStyle.FULL, locale) }
    val yearFirst = !AppLanguage.isEnglish
    BoxWithConstraints(modifier) {
        // The selection band behind the three wheels, as the system wheel draws it.
        Box(Modifier.align(Alignment.Center).padding(horizontal = 16.dp).fillMaxWidth().height(34.dp)
            .background(NB.white.copy(alpha = 0.08f), RoundedCornerShape(8.dp)))
        Row(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            val monthWheel: @Composable () -> Unit = {
                Wheel(months.map(monthName), months.indexOf(date.monthValue), Modifier.weight(1.4f)) {
                    onDate(clamp(date.year, months[it], date.dayOfMonth))
                }
            }
            val dayWheel: @Composable () -> Unit = {
                Wheel(days.map { if (yearFirst) "${it}日" else "$it" }, date.dayOfMonth - 1, Modifier.weight(0.8f)) {
                    onDate(clamp(date.year, date.monthValue, days[it]))
                }
            }
            val yearWheel: @Composable () -> Unit = {
                Wheel(years.map { if (yearFirst) "${it}年" else "$it" }, years.indexOf(date.year), Modifier.weight(1f)) {
                    onDate(clamp(years[it], date.monthValue, date.dayOfMonth))
                }
            }
            if (yearFirst) { yearWheel(); monthWheel(); dayWheel() } else { monthWheel(); dayWheel(); yearWheel() }
        }
        // The wheel's rows fade out toward its top and bottom edges instead of being cut.
        Box(Modifier.align(Alignment.TopCenter).fillMaxWidth().height(maxHeight * 0.32f)
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(NB.carbon2, NB.carbon2.copy(alpha = 0f)))))
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(maxHeight * 0.32f)
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(NB.carbon2.copy(alpha = 0f), NB.carbon2))))
    }
}

private val ROW = 34.dp

@Composable
private fun Wheel(items: List<String>, selected: Int, modifier: Modifier, onSelect: (Int) -> Unit) {
    val state = rememberLazyListState(initialFirstVisibleItemIndex = selected.coerceAtLeast(0))
    val fling = rememberSnapFlingBehavior(state)
    val select by rememberUpdatedState(onSelect)
    // Keep the wheel on the value when another wheel clamps it (Feb 30 → Feb 28).
    LaunchedEffect(selected, items.size) {
        if (!state.isScrollInProgress && state.firstVisibleItemIndex != selected && selected >= 0) state.scrollToItem(selected)
    }
    LaunchedEffect(state) {
        snapshotFlow { state.isScrollInProgress to state.firstVisibleItemIndex }
            .distinctUntilChanged()
            .collect { (scrolling, _) ->
                if (!scrolling) {
                    val idx = (state.firstVisibleItemIndex + if (state.firstVisibleItemScrollOffset > 0) 1 else 0)
                        .coerceIn(0, items.size - 1)
                    if (idx != selected) {
                        Haptics.selection()
                        select(idx)
                    }
                }
            }
    }
    BoxWithConstraints(modifier.fillMaxSize()) {
        val pad = (maxHeight - ROW) / 2
        LazyColumn(state = state, flingBehavior = fling, contentPadding = PaddingValues(vertical = pad),
            modifier = Modifier.fillMaxSize()) {
            items(items.size) { i ->
                val dist = kotlin.math.abs(i - selected)
                Box(Modifier.fillMaxWidth().height(ROW), contentAlignment = Alignment.Center) {
                    GText(items[i], NBFont.ui(400, 20f), NB.text1, Modifier.alpha(
                        when (dist) { 0 -> 1f; 1 -> 0.45f; 2 -> 0.25f; else -> 0.15f }), maxLines = 1)
                }
            }
        }
    }
}

// MARK: root sheet routes · SheetRoute.Height / WeightBaseline / Birthday

/** `SheetRoute.Height` hosted by the root: the profile's height, saved on Save. */
@Composable
fun HeightSheet(close: () -> Unit) {
    HeightRulerSheet(DataStore.profile.heightCm) { v ->
        DataStore.profile = DataStore.profile.copy(heightCm = v)
        close()
    }
}

/** `SheetRoute.WeightBaseline` hosted by the root: today's weight. */
@Composable
fun WeightBaselineSheet(close: () -> Unit) {
    WeightRulerSheet(DataStore.today.weightKg ?: 63.0) { v ->
        DataStore.today = DataStore.today.copy(weightKg = v)
        close()
    }
}

/** `SheetRoute.Birthday` hosted by the root: the profile's birth date. */
@Composable
fun BirthdaySheet(close: () -> Unit) {
    BirthdayWheelSheet(DataStore.profile.birthdate.localDate(), onSave = { d ->
        DataStore.profile = DataStore.profile.copy(birthdate = d.startInstant())
        close()
    }, onCancel = close)
}
