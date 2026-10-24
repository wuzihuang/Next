package com.nextbody.hoop.features.fuel

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.MealEntry
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.ui.Chrome
import com.nextbody.hoop.features.connect.LimePillButton
import com.nextbody.hoop.features.profile.FieldBox
import com.nextbody.hoop.features.profile.SheetFrame
import com.nextbody.hoop.services.MealFavorites
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.LaunchedEffect
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.keyboardHeight
import com.nextbody.hoop.ui.swiftSpring
import com.nextbody.hoop.design.ScreenMetrics
import kotlinx.coroutines.launch
import kotlin.math.max

/**
 * Log or edit a meal. The page behind becomes a card (radius + scale) and a dim sits over it so
 * the plate reads as a layer — Profile chrome, plus-menu rise.
 */
sealed class FuelPlate {
    data object Log : FuelPlate()
    data class Edit(val entry: MealEntry) : FuelPlate()
}

@Composable
fun FuelPlateLayer(plate: FuelPlate, day: UserDay, onClose: () -> Unit) {
    val keyboard = keyboardHeight()
    val density = LocalDensity.current
    var drag by remember { mutableFloatStateOf(0f) }
    val settle = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    // Both plates ride on top of the keyboard. The IME inset is measured from the bottom of the
    // screen, so it already contains the home-indicator strip the plate is inset by.
    val rise = max(0f, (keyboard - ScreenMetrics.safeBottom).value)
    val riseAnim = remember { Animatable(0f) }
    androidx.compose.runtime.LaunchedEffect(rise) { riseAnim.animateTo(rise, tween(250, easing = com.nextbody.hoop.ui.SwiftEaseOut)) }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        Box(
            Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.34f))
                .clickable(remember { MutableInteractionSource() }, indication = null) { onClose() },
        )
        val shape = RoundedCornerShape(topStart = NB.R.panel, topEnd = NB.R.panel)
        val offsetDp = with(density) { (max(0f, drag) + settle.value).toDp() } - riseAnim.value.dp
        Column(
            Modifier
                .fillMaxWidth()
                .offset(y = offsetDp)
                .shadow(28.dp, shape, spotColor = Color.Black.copy(alpha = 0.55f))
                .background(NB.carbon2, shape)
                .drawWithContent {
                    drawContent()
                    val r = NB.R.panel.toPx()
                    drawRoundRect(NB.hairline, Offset.Zero, Size(size.width, size.height + r),
                        CornerRadius(r, r), style = Stroke(1.dp.toPx()))
                },
        ) {
            // Dismissal belongs to the handle. A pan recognizer over the entire form competes
            // with text selection and scrolling just as the keyboard changes the form's size.
            Box(
                Modifier
                    .fillMaxWidth()
                    .draggable(
                        rememberDraggableState { delta -> drag = max(0f, drag + delta) },
                        Orientation.Vertical,
                        onDragStopped = { velocity ->
                            val travelDp = with(density) { (drag * 2 + velocity * 0.1f).toDp() }.value
                            if (travelDp > 120) onClose()
                            else scope.launch {
                                val from = drag
                                drag = 0f
                                settle.snapTo(from)
                                settle.animateTo(0f, swiftSpring(0.3f, 0.86f))
                            }
                        },
                    )
                    .padding(top = 10.dp, bottom = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(36.dp, 4.dp).background(NB.white.copy(alpha = 0.18f), CircleShape))
            }
            when (plate) {
                is FuelPlate.Log -> LogMealSheet(day = day, onClose = onClose)
                is FuelPlate.Edit -> EditMealSheet(entry = plate.entry, keyboard = keyboard, onClose = onClose)
            }
        }
    }
}

/**
 * ⚠️ This plate used to demand two things: what you ate, and how many calories it was. With AI
 * on, KCAL is an override and a blank one lets the model estimate. With AI off
 * (`AIFeature.enabled = false`, this build) KCAL is required: what is typed is exactly what goes
 * on the record, with nothing estimated over it.
 */
@Composable
fun LogMealSheet(day: UserDay, onClose: () -> Unit) {
    val data = DataStore
    var text by remember { mutableStateOf("") }
    var kcal by remember { mutableStateOf("") }
    val working = false
    val failure: String? = null

    val typed = text.trim()
    val override = kcal.replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() && it >= 1 && it <= 100000 }
    // AI off: the typed number is the gate.
    val canSave = typed.isNotEmpty() && !working && override != null

    LaunchedEffect(Unit) { MealFavorites.load() }
    Box(Modifier.padding(bottom = max(8f, Chrome.homeIndicatorBlock.value - 8).dp)) { SheetFrame(
        title = L("Log a meal"), fillsHeight = false,
        content = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (MealFavorites.list.isNotEmpty()) Regulars(day, onClose)
                FieldBox(label = L("What you ate"), text = text, onText = { text = it })
                FieldBox(label = L("KCAL"), text = kcal, onText = { kcal = it }, keyboard = KeyboardType.Decimal)
            }
            Text(
                failure ?: L("Logged at exactly this number. Nothing is estimated over it."),
                Modifier.fillMaxWidth().padding(top = 6.dp),
                style = NBFont.ui(300, 12.5f).tracking(0.02f),
                color = if (failure == null) NB.white.copy(alpha = 0.38f) else NB.ember1,
            )
        },
        footer = {
            LimePillButton(title = if (working) L("READING…") else L("Save"), enabled = canSave) {
                val value = override ?: return@LimePillButton
                data.addManualMeal(text = typed, kcal = value, day = day)
                onClose()
            }
        },
    ) }
}

/** The second time you eat something costs one tap. Every number on these came from an estimate
 *  this person already accepted, so logging one calls no model and waits for nothing. */
@Composable
private fun Regulars(day: UserDay, onClose: () -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(L("REGULARS"), style = NBFont.dot(600, 10f).tracking(0.18f), color = NB.white.copy(alpha = 0.42f))
        LazyRow(
            Modifier.fillMaxWidth().height(44.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 1.dp),
        ) {
            items(MealFavorites.list, key = { it.id }) { favorite ->
                Row(
                    Modifier.height(40.dp)
                        .hotZoneTap {
                            MealFavorites.log(favorite, day, DataStore)
                            onClose()
                        }
                        .background(NB.carbon4, CircleShape)
                        .border(1.dp, NB.hairline, CircleShape)
                        .padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (favorite.photoPath != null) MealThumbnail(favorite.photoPath, side = 22.dp, radius = 6.dp)
                    Text(favorite.label, style = NBFont.ui(500, 13f), color = NB.text1, maxLines = 1)
                    Text(Fmt.nutrient(favorite.kcal), style = NBFont.dot(600, 12f), color = NB.ember1)
                }
            }
        }
    }
}
