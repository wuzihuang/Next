package com.nextbody.hoop.features.device

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nextbody.hoop.app.SheetRoute
import com.nextbody.hoop.band.HoopSlot
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.launch

/**
 * 12Y · one chrome for the two action-tile sheets (Find NEXTBODY, Alarms).
 * Both share the DEVICE sheet anatomy — eyebrow → title → one sentence on carbon-2 inside
 * the 16pt gutter every other sheet on this page uses — and one key.
 * (Swift `enum DeviceSheet`; renamed so the router dispatcher below can be `DeviceSheet(...)`.)
 */
object DeviceSheetMetrics {
    val gutter: Dp = NB.Layout.gutter
    val top: Dp = 26.dp
    val bottom: Dp = 26.dp
    /** Vertical rhythm of a full-width row (a clock, RSSI, Range). */
    val rowInset: Dp = 18.dp
}

/** SwiftUI `.lineSpacing(x)`: the font's natural line plus `extra` points between lines. */
internal fun TextStyle.lineGap(extra: Float): TextStyle {
    val size = if (fontSize == TextUnit.Unspecified) 14f else fontSize.value
    return copy(lineHeight = (size * 1.2f + extra).sp)
}

/** Eyebrow (dot, tracked) over a 22pt title over an optional one-line sentence.
 *  The eyebrow is the sheet's live word — READY · LIVE, TIMEOUT, NEW ALARM — so it carries
 *  the tint; the title never does. */
@Composable
fun SheetHeader(
    eyebrow: String,
    title: String,
    modifier: Modifier = Modifier,
    eyebrowTint: Color = NB.lime1,
    eyebrowID: String? = null,
    subtitle: String? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                eyebrow,
                style = NBFont.dot(600, 11f).tracking(0.28f),
                color = eyebrowTint,
                modifier = Modifier.weight(1f).let { if (eyebrowID != null) it.testTag(eyebrowID) else it },
            )
            Spacer(Modifier.width(0.dp)) // 12 + 0 + 12, as SwiftUI spaces around the Spacer
            trailing?.invoke(this)
        }
        Text(title, style = NBFont.ui(500, 22f).tracking(0.01f), color = NB.text1)
        if (subtitle != null) {
            Text(
                subtitle,
                style = NBFont.ui(300, 12.5f).tracking(0.02f).lineGap(5f),
                color = NB.white.copy(alpha = 0.38f),
            )
        }
    }
}

/** The one 52pt capsule key both sheets press. Lime for the thing you came to do, ember for
 *  the way out of a timeout, outline for a second choice under a list. */
enum class HoopKeySkin { lime, ember, outline }

@Composable
fun HoopKey(
    title: String,
    modifier: Modifier = Modifier,
    skin: HoopKeySkin = HoopKeySkin.lime,
    enabled: Boolean = true,
    action: () -> Unit,
) {
    val ink = if (skin == HoopKeySkin.outline) NB.lime1 else NB.carbon4
    val fill = when (skin) {
        HoopKeySkin.lime -> NB.lime1
        HoopKeySkin.ember -> NB.ember1
        HoopKeySkin.outline -> Color.Transparent
    }
    Box(
        modifier
            .fillMaxWidth()
            .height(52.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .background(fill, CircleShape)
            .let { if (skin == HoopKeySkin.outline) it.border(1.dp, NB.lime1.copy(alpha = 0.55f), CircleShape) else it }
            .hotZoneTap(enabled = enabled, pressedScale = 1f) { action() },
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = NBFont.ui(600, 14f).tracking(0.06f), color = ink, maxLines = 1)
    }
}

/** One ember line under the face — a refusal, DEVICE BUSY, a band that has no Find. */
@Composable
fun SheetNote(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = NBFont.dot(600, 10f).tracking(0.12f),
        color = NB.ember1,
        modifier = modifier.fillMaxWidth(),
    )
}

/**
 * A list in a sheet: the full-width hairline above and below replace the rounded box.
 * The sheet pads its content by the gutter; the rules reach the screen edges.
 */
fun Modifier.sheetLines(): Modifier = this
    .bleed(DeviceSheetMetrics.gutter)
    .drawWithContent {
        drawContent()
        val h = 1.dp.toPx()
        drawRect(NB.hairline, Offset.Zero, Size(size.width, h))
        drawRect(NB.hairline, Offset(0f, size.height - h), Size(size.width, h))
    }

/** SwiftUI `.frame(width: w + 2g).padding(.horizontal, -g)`: the content is measured `g`
 *  wider on each side than the slot it occupies, and drawn reaching into the gutters. */
internal fun Modifier.bleed(gutter: Dp): Modifier = layout { measurable, constraints ->
    val g = gutter.roundToPx()
    val width = if (constraints.hasBoundedWidth) constraints.maxWidth else NB.Layout.contentWidth.roundToPx()
    val wide = width + 2 * g
    val placeable = measurable.measure(constraints.copy(minWidth = wide, maxWidth = wide))
    layout(width, placeable.height) { placeable.place(-g, 0) }
}

// MARK: the hosted sheet

/**
 * A sheet may refuse the drag-down while it is in the middle of something it must not
 * abandon (pairing a band, a removal in flight). SwiftUI `.interactiveDismissDisabled`.
 */
val LocalSheetDismissLock = compositionLocalOf<MutableState<Boolean>?> { null }

@Composable
internal fun InteractiveDismissDisabled(disabled: Boolean) {
    val lock = LocalSheetDismissLock.current ?: return
    androidx.compose.runtime.SideEffect { if (lock.value != disabled) lock.value = disabled }
}

/**
 * The device page presents its own sheets (`.sheet(item:)` on iOS): carbon-2, 40pt top
 * radius, a grabber, and a fixed detent per route. [heightFraction] is of the screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DevicePageSheet(
    heightFraction: Float,
    onDismiss: () -> Unit,
    large: Boolean = false,
    content: @Composable BoxScope.(close: () -> Unit) -> Unit,
) {
    val lock = remember { mutableStateOf(false) }
    val state = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { it != SheetValue.Hidden || !lock.value },
    )
    val scope = rememberCoroutineScope()
    val close: () -> Unit = {
        lock.value = false
        scope.launch { state.hide() }.invokeOnCompletion { onDismiss() }
    }
    val height = if (large) ScreenMetrics.height - ScreenMetrics.safeTop - 10.dp
    else ScreenMetrics.height * heightFraction
    ModalBottomSheet(
        onDismissRequest = { if (!lock.value) onDismiss() },
        sheetState = state,
        containerColor = NB.carbon2,
        contentColor = NB.text1,
        scrimColor = Color.Black.copy(alpha = 0.45f),
        shape = RoundedCornerShape(topStart = NB.R.panel, topEnd = NB.R.panel),
        dragHandle = null,
        contentWindowInsets = { WindowInsets(0) },
    ) {
        CompositionLocalProvider(LocalSheetDismissLock provides lock) {
            Box(Modifier.fillMaxWidth().height(height)) {
                content(close)
                // The system grabber sits over the content, as `.presentationDragIndicator`.
                Box(
                    Modifier.align(Alignment.TopCenter).padding(top = 5.dp).size(36.dp, 5.dp)
                        .background(NB.white.copy(alpha = 0.3f), CircleShape),
                )
            }
        }
    }
}

/**
 * The router-hosted device sheets. ⚠️ On iOS `SheetHost` sends `.findHoop` to FindHoopSheet
 * and every other device route to `ProfileSheet(route:)`, which draws nothing for them — the
 * real sheets are presented by DeviceView itself. This draws the same sheets DeviceView does.
 */
@Composable
fun DeviceSheet(route: SheetRoute, close: () -> Unit) {
    when (route) {
        SheetRoute.BandAutoMonitor -> AutoMeasurementSheet(initial = null, onRead = {})
        SheetRoute.SyncCadence -> {
            val minutes = remember { mutableStateOf(com.nextbody.hoop.band.SyncCadence.minutes) }
            SyncCadenceSheet(minutes.value) { minutes.value = it }
        }
        SheetRoute.Unbind -> ReleaseSetSheet(close = close, initialSlot = com.nextbody.hoop.band.DeviceSetStore.shared.wearing)
        SheetRoute.Disconnect -> DisconnectSheet(close)
        SheetRoute.FindBand, SheetRoute.Firmware -> WhyWontItConnectSheet()
        SheetRoute.FindHoop -> FindHoopSheet(close)
        SheetRoute.ActivateSecond -> ActivateSecondSheet(close)
        is SheetRoute.WearSwitch -> WearSwitchSheet(
            to = HoopSlot.fromRaw(route.slot) ?: com.nextbody.hoop.band.DeviceSetStore.shared.wearing.other,
            close = close,
        )
        SheetRoute.ReleaseSet -> ReleaseSetSheet(close = close)
        SheetRoute.BandAlarms -> AlarmsSheet()
        SheetRoute.HealthLight -> HealthLightSheet()
        else -> WhyWontItConnectSheet()
    }
}

/** How much of the screen a device sheet takes. A table or a picture wants the tall detent,
 *  a confirmation wants only the room its own sentence needs. */
fun deviceSheetFraction(route: SheetRoute): Float = when (route) {
    SheetRoute.BandAutoMonitor, SheetRoute.FindHoop, SheetRoute.BandAlarms,
    SheetRoute.HealthLight, SheetRoute.ActivateSecond -> 0.78f
    SheetRoute.ReleaseSet -> 0.82f
    // 9-0 A·S8 · a question, the NEXTBODY it names, and one key.
    is SheetRoute.WearSwitch -> 0.55f
    else -> 0.62f
}

/** The small system spinner (`ProgressView().controlSize(.small)`). */
@Composable
internal fun SmallSpinner(color: Color, modifier: Modifier = Modifier, size: Dp = 16.dp) {
    CircularProgressIndicator(modifier = modifier.size(size), color = color, strokeWidth = 2.dp, trackColor = Color.Transparent)
}

/**
 * One-line text that shrinks to fit, down to [minScale] of its size
 * (SwiftUI `.lineLimit(1).minimumScaleFactor(x)`).
 */
@Composable
internal fun FitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 0.7f,
    align: TextAlign? = null,
) {
    val base = if (style.fontSize == TextUnit.Unspecified) 14f else style.fontSize.value
    val scale = remember(text, style) { mutableStateOf(1f) }
    Text(
        text,
        style = style.copy(fontSize = (base * scale.value).sp),
        color = color,
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Clip,
        textAlign = align,
        modifier = modifier.drawWithContent { if (scale.value > 0f) drawContent() },
        onTextLayout = { r: TextLayoutResult ->
            if (r.didOverflowWidth && scale.value > minScale) {
                scale.value = maxOf(minScale, scale.value * 0.94f)
            }
        },
    )
}

/** A full-width row that leaves a hairline under itself unless it is the last. */
internal fun Modifier.rowRule(last: Boolean, inset: Dp = 16.dp): Modifier =
    if (last) this else this.drawWithContent {
        drawContent()
        val h = 1.dp.toPx()
        val i = inset.toPx()
        drawRect(NB.hairline, Offset(i, size.height - h), Size(size.width - 2 * i, h))
    }

/** A hairline across the top edge (SwiftUI `.overlay(alignment: .top) { Hairline() }`). */
internal fun Modifier.topRule(color: Color = NB.hairline): Modifier = this.drawWithContent {
    drawContent()
    drawRect(color, Offset.Zero, Size(size.width, 1.dp.toPx()))
}

/** SwiftUI `.grayscale(1)`: the content drawn through a zero-saturation layer. */
internal fun Modifier.grayscale(): Modifier = this.drawWithContent {
    val paint = androidx.compose.ui.graphics.Paint().apply {
        colorFilter = androidx.compose.ui.graphics.ColorFilter.colorMatrix(
            androidx.compose.ui.graphics.ColorMatrix().apply { setToSaturation(0f) })
    }
    drawContext.canvas.saveLayer(androidx.compose.ui.geometry.Rect(Offset.Zero, size), paint)
    drawContent()
    drawContext.canvas.restore()
}
