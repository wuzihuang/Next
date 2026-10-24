package com.nextbody.hoop.features.dock

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.HoldHaptics
import com.nextbody.hoop.ui.ImpactStyle
import com.nextbody.hoop.ui.OrbGlyph
import com.nextbody.hoop.ui.SwiftEaseOut
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.pressHold
import com.nextbody.hoop.ui.swiftSpring
import kotlin.math.hypot

/** `AIFeature.enabled` — AI is off in this app; the dock is the plus key alone. */
private const val AI_ENABLED = false

/**
 * 05 · Dock 输入. Three slots, written in stone:
 * left switches input mode, centre is the input itself, right asks for an action.
 * Nothing else is ever added to this row.
 *
 * With AI off (`AIFeature.enabled == false`) the row is the plus key alone, which opens the
 * plus menu (the caller sets `Router.sheet = SheetRoute.PlusMenu`).
 */
enum class DockMode { idle, keyboard, listening, plus }

/** 05 edges 1–6 · one amber line on the capsule, one sentence under the dock, at most one key. */
data class DockNote(val line: String, val text: String, val action: String? = null) {
    override fun equals(other: Any?): Boolean = other is DockNote && other.line == line
    override fun hashCode(): Int = line.hashCode()
}

@Composable
fun Dock(
    mode: DockMode,
    onModeChange: (DockMode) -> Unit,
    draft: String,
    onDraftChange: (String) -> Unit,
    onSend: (String) -> Unit,
    onCamera: () -> Unit,
    onPlus: () -> Unit,
    onListen: () -> Unit,
    onStopListening: () -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    /** 05 edges · the centre capsule says what can be done now, in an amber outline. */
    note: DockNote? = null,
    /** 05 rule 06 · with a photo attached the send key lights only at 100 % and ≥ 1 character. */
    attachmentReady: Boolean? = null,
    width: Dp = NB.Layout.contentWidth,
    /** Hold the resting orb to skip the plus menu and photograph a meal. Fires on the lift. */
    onPlusLongPress: (() -> Unit)? = null,
    /** 06 · 02 · while the menu is open the plus is the close mark: turned 45°, lime, dark ink. */
    menuOpen: Boolean = false,
    onCancelListening: () -> Unit = {},
    onKeyboardTap: (() -> Unit)? = null,
    /** The microphone's level history (Swift reads `SpeechCapture.shared.levels`). */
    levels: List<Double> = emptyList(),
    /** Seconds into the take (Swift reads `SpeechCapture.shared.elapsed`). */
    elapsed: Double = 0.0,
) {
    if (AI_ENABLED) {
        InputRow(mode, onModeChange, draft, onDraftChange, onSend, onCamera, onPlus, onListen, onStopListening,
            modifier, placeholder, note, attachmentReady, width, onPlusLongPress, menuOpen, onCancelListening,
            onKeyboardTap, levels, elapsed)
    } else {
        Box(modifier.size(width, NB.Layout.dockHeight), contentAlignment = Alignment.Center) {
            DockCircleButton(
                filled = menuOpen,
                action = onPlus,
                label = if (menuOpen) L("Close") else L("Open the plus menu"),
            ) { PlusFace(menuOpen) }
        }
    }
}

/**
 * The key at rest is the orb, not a camera outline: it opens 06's sheet. It fills the key edge
 * to edge — under about 40 pt the two shells stop reading as shells and the ball is just texture.
 */
@Composable
private fun PlusFace(menuOpen: Boolean) {
    val t by animateFloatAsState(if (menuOpen) 1f else 0f, tween(140, easing = SwiftEaseOut), label = "dock.plus")
    Box(contentAlignment = Alignment.Center) {
        OrbGlyph(Modifier.alpha(1 - t).scale(1 - 0.4f * t), side = NB.Layout.dockSideButton)
        PlusGlyph(Modifier.alpha(t).scale(0.6f + 0.4f * t).rotate(45f), tint = NB.carbon)
    }
}

@Composable
private fun InputRow(
    mode: DockMode, onModeChange: (DockMode) -> Unit, draft: String, onDraftChange: (String) -> Unit,
    onSend: (String) -> Unit, onCamera: () -> Unit, onPlus: () -> Unit, onListen: () -> Unit,
    onStopListening: () -> Unit, modifier: Modifier, placeholder: String, note: DockNote?,
    attachmentReady: Boolean?, width: Dp, onPlusLongPress: (() -> Unit)?, menuOpen: Boolean,
    onCancelListening: () -> Unit, onKeyboardTap: (() -> Unit)?, levels: List<Double>, elapsed: Double,
) {
    var pressing by remember { mutableStateOf(false) }
    var armed by remember { mutableStateOf(false) }
    var cancelling by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val listening = mode == DockMode.listening

    fun send() {
        val t = draft.trim()
        if (t.isEmpty()) return
        onDraftChange("")
        onSend(t)
        onModeChange(DockMode.idle)
    }

    Row(
        modifier.size(width, NB.Layout.dockHeight),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        // Left slot · switches input mode or opens dedicated chat.
        Box(Modifier.alpha(if (listening) 0f else 1f)) {
            DockCircleButton(ringed = mode == DockMode.keyboard, enabled = !listening, label = L("AI COACH"), action = {
                if (onKeyboardTap != null) onKeyboardTap()
                else onModeChange(if (mode == DockMode.keyboard) DockMode.idle else DockMode.keyboard)
            }) { KeyboardGlyph() }
        }

        Box(Modifier.weight(1f).height(NB.Layout.dockHeight), contentAlignment = Alignment.BottomCenter) {
            when (mode) {
                DockMode.idle, DockMode.listening -> {
                    val cancel = listening && (cancelling || DebugEdgeFlag.on("cancelling"))
                    val edge = !listening && note != null
                    val scale by animateFloatAsState(if (pressing && !listening) 0.98f else 1f, tween(120, easing = SwiftEaseOut), label = "dock.press")
                    val fill by animateColorAsState(
                        if (cancel) hex(0x141418) else if (edge) NB.ember1.copy(alpha = 0.06f) else NB.lime1,
                        tween(160, easing = SwiftEaseOut), label = "dock.fill")
                    val shape = RoundedCornerShape(if (listening) 30.dp else NB.Layout.dockHeight / 2)
                    // ⚠️ One view for the capsule and the chamber: the finger that started the
                    // gesture is still down when the mode flips, so the capsule itself grows.
                    Box(
                        Modifier
                            .then(if (listening) Modifier.size(width, RecordingChamber.height) else Modifier.fillMaxWidth().height(NB.Layout.dockHeight))
                            .scale(scale)
                            .background(fill, shape)
                            .then(if (edge) Modifier.border(1.dp, NB.ember1.copy(alpha = 0.36f), shape) else Modifier)
                            .then(if (cancel) Modifier.border(1.5.dp, NB.alert2.copy(alpha = 0.52f), shape) else Modifier)
                            .clip(shape)
                            .semantics {
                                contentDescription = if (listening) (if (cancel) "Release to cancel" else "Listening · release to send · slide up to cancel")
                                else if (edge) note?.line ?: "" else "Hold to talk"
                            }
                            .pressHold(
                                onTouch = { pressing = it },
                                // 05M · B·02 · the threshold is crossed → one haptic, mic up.
                                onArm = { armed = true; Haptics.impact(ImpactStyle.Medium); onListen() },
                                // 05M · B·04 · slide up past −56 px arms the cancel; back down re-arms send.
                                onMove = { t ->
                                    val c = armed && t.y.value < -56
                                    if (c != cancelling) { cancelling = c; Haptics.impact(ImpactStyle.Light) }
                                },
                                onLift = { interrupted ->
                                    val wasArmed = armed; val wasCancelling = cancelling
                                    pressing = false; armed = false; cancelling = false
                                    if (wasArmed) {
                                        if (wasCancelling || interrupted) onCancelListening() else onStopListening()
                                    }
                                },
                                onTap = { if (listening) onCancelListening() },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        when {
                            listening -> RecordingChamber(cancel, levels, elapsed)
                            note != null -> Text(note.line, style = NBFont.dot(600, 11f).tracking(0.2f), color = NB.ember1.copy(alpha = 0.85f))
                            else -> DotMatrix()
                        }
                    }
                    // B·03 / B·04 · the cancel mark hangs above the chamber's lip.
                    if (listening) {
                        CancelMark(cancel, Modifier.align(Alignment.TopCenter).offset(y = -(RecordingChamber.height - NB.Layout.dockHeight) - 108.dp))
                    }
                }
                DockMode.keyboard, DockMode.plus -> {
                    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
                    Row(
                        Modifier.fillMaxWidth().height(NB.Layout.dockHeight)
                            .background(NB.carbon4, CircleShape).border(1.dp, NB.hairline, CircleShape)
                            .padding(start = 18.dp, end = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                            if (draft.isEmpty()) {
                                Text(placeholder.ifEmpty { "Ask about today" }, style = NBFont.ui(400, 14f), color = NB.text3Prod)
                            }
                            BasicTextField(
                                value = draft, onValueChange = onDraftChange,
                                modifier = Modifier.fillMaxWidth().focusRequester(focus),
                                textStyle = NBFont.ui(400, 14f).copy(color = NB.text1),
                                cursorBrush = SolidColor(NB.lime1), singleLine = true,
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                                keyboardActions = KeyboardActions(onSend = { send() }),
                            )
                        }
                        // 05 · C01 · the camera lives in the field, not the right slot.
                        Box(Modifier.hotZoneTap(pressedScale = 1f, onClick = onCamera).semantics { contentDescription = L("Add a photo") }) {
                            CameraGlyph()
                        }
                    }
                }
            }
        }

        if (mode == DockMode.keyboard) {
            val sendArmed = draft.isNotBlank() && (attachmentReady ?: true)
            Box(
                Modifier.size(NB.Layout.dockSideButton)
                    .background(if (sendArmed) NB.lime1 else NB.carbon4, CircleShape)
                    .then(if (!sendArmed) Modifier.border(1.dp, NB.hairline, CircleShape) else Modifier)
                    .hotZoneTap(enabled = sendArmed, pressedScale = 1f, onClick = { send() }),
                contentAlignment = Alignment.Center,
            ) { SendArrow(tint = if (sendArmed) NB.carbon else NB.white.copy(alpha = 0.3f)) }
        } else {
            Box(Modifier.alpha(if (listening) 0f else 1f)) {
                DockCircleButton(
                    filled = menuOpen, enabled = !listening, action = onPlus, onLongPress = onPlusLongPress,
                    label = if (menuOpen) L("Close") else L("Camera"),
                ) { PlusFace(menuOpen) }
            }
        }
    }
}

/**
 * A round side key. When [onLongPress] is set, tap and hold share one recognizer (ADR-0001):
 * the finger lands and the key dips (0.96); at the threshold it swells past its own frame
 * (1.22) and the hold haptic arms; the *lift* fires. Sliding off past 44 dp lets the air out.
 */
@Composable
fun DockCircleButton(
    modifier: Modifier = Modifier,
    ringed: Boolean = false,
    filled: Boolean = false,
    enabled: Boolean = true,
    label: String? = null,
    action: () -> Unit,
    onLongPress: (() -> Unit)? = null,
    glyph: @Composable () -> Unit,
) {
    val fill by animateColorAsState(if (filled) NB.lime1 else NB.carbon4, tween(140, easing = SwiftEaseOut), label = "dock.key.fill")
    val ring = when {
        ringed -> NB.lime1.copy(alpha = 0.6f)
        filled -> Color.Transparent
        else -> NB.hairline
    }
    val face: @Composable (Modifier) -> Unit = { m ->
        Box(
            m.size(NB.Layout.dockSideButton)
                .background(fill, CircleShape)
                .border(if (ringed) 1.5.dp else 1.dp, ring, CircleShape),
            contentAlignment = Alignment.Center,
        ) { glyph() }
    }
    if (onLongPress != null) {
        var pressing by remember { mutableStateOf(false) }
        var holding by remember { mutableStateOf(false) }
        val holdEscape = 44f
        val scale by animateFloatAsState(
            if (holding) 1.22f else if (pressing) 0.96f else 1f,
            if (holding) swiftSpring(0.22f, 0.7f) else swiftSpring(0.2f, 0.8f), label = "dock.key.hold")
        face(
            modifier
                .scale(scale)
                .shadow(if (holding) 14.dp else 0.dp, CircleShape, ambientColor = NB.lime1.copy(alpha = 0.28f), spotColor = NB.lime1.copy(alpha = 0.28f))
                .semantics {
                    role = Role.Button
                    label?.let { contentDescription = it }
                    onClick { action(); true }
                }
                .then(if (!enabled) Modifier else Modifier.pressHold(
                    // 05 · a press, not a wait — far enough past a tap that opening the sheet never arms the camera.
                    minimumDurationMs = 300,
                    onTouch = { down -> pressing = down; if (down) HoldHaptics.prepare() },
                    onArm = { pressing = false; holding = true; HoldHaptics.beginHold() },
                    onMove = { t ->
                        if (holding && hypot(t.x.value, t.y.value) > holdEscape) { holding = false; HoldHaptics.cancel() }
                    },
                    onLift = { interrupted ->
                        pressing = false
                        if (holding) {
                            holding = false
                            if (interrupted) HoldHaptics.cancel() else { HoldHaptics.release(); onLongPress() }
                        }
                    },
                    onTap = action,
                )),
        )
    } else {
        face(
            modifier
                .hotZoneTap(enabled = enabled, pressedOpacity = 1f, pressedScale = 1f, onClick = action)
                .semantics { label?.let { contentDescription = it } },
        )
    }
}

private fun DrawScope.u(v: Float): Float = v * size.width / 24f

@Composable
fun SendArrow(modifier: Modifier = Modifier, tint: Color = NB.carbon) {
    Canvas(modifier.size(20.dp)) {
        val p = Path().apply {
            moveTo(u(12f), u(19f)); lineTo(u(12f), u(5f))
            moveTo(u(6f), u(11f)); lineTo(u(12f), u(5f)); lineTo(u(18f), u(11f))
        }
        drawPath(p, tint, style = Stroke(u(1.9f), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** The lime key's face: 14 × 5 dots on a 6.4 pitch, edges faded so the pill reads as printed. */
@Composable
fun DotMatrix(modifier: Modifier = Modifier) {
    Canvas(modifier.size(96.dp, 32.dp)) {
        val s = minOf(size.width / 96f, size.height / 32f)
        val ox = (size.width - 96 * s) / 2; val oy = (size.height - 32 * s) / 2
        for (row in 0 until 5) for (col in 0 until 14) {
            val a = DotMatrixSpec.alpha(row, col)
            drawCircle(Color.Black.copy(alpha = (0.78 * a).toFloat()), radius = 1.3f * s,
                center = Offset(ox + (3.2f + 6.4f * col) * s, oy + (3.2f + 6.4f * row) * s))
        }
    }
}

object DotMatrixSpec {
    fun alpha(row: Int, col: Int): Double {
        if (row == 0 || row == 4) return when (col) { 0, 13 -> 0.25; 1, 12 -> 0.55; else -> 1.0 }
        return when (col) { 0 -> 0.55; 12 -> 0.85; 13 -> 0.40; else -> 1.0 }
    }
}

/**
 * 05M · B·03 · the chamber. 358 × 138, radius 30, padding 18 / 22 / 16: a status line with the
 * timer, the level history as 34 bars, and the one instruction at the foot. B·04 turns the same
 * box carbon behind a red hairline, freezes the bars and changes both lines — nothing moves.
 */
object RecordingChamber {
    val height: Dp = 138.dp
    fun clock(t: Double): String {
        val s = maxOf(0, t.toInt())
        return "%d:%02d".format(s / 60, s % 60)
    }
    /** DEBUG · the board's own 34 bars, for a device with no microphone to hold. */
    val debugLevels: List<Double>?
        get() {
            if (!(DebugEdgeFlag.on("recording") || DebugEdgeFlag.on("cancelling"))) return null
            val h = listOf(6, 10, 16, 26, 38, 30, 20, 12, 18, 28, 44, 52, 40, 24, 14, 10, 16, 24,
                34, 46, 36, 22, 12, 8, 14, 22, 32, 42, 30, 18, 10, 14, 20, 10)
            return h.map { (it - 6) / 46.0 }
        }
}

@Composable
fun RecordingChamber(cancelling: Boolean, levels: List<Double>, elapsed: Double) {
    Column(
        Modifier.size(NB.Layout.contentWidth, RecordingChamber.height)
            .padding(top = 18.dp, start = 22.dp, end = 22.dp, bottom = 16.dp),
    ) {
        Row(Modifier.fillMaxWidth().height(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(7.dp).background(if (cancelling) NB.alert2 else NB.carbon, CircleShape))
                Text(if (cancelling) "RELEASE TO CANCEL" else "RECORDING", style = NBFont.dot(600, 10f).tracking(0.28f),
                    color = if (cancelling) NB.alert1 else NB.carbon.copy(alpha = 0.66f))
            }
            Spacer(Modifier.width(16.dp))
            Spacer(Modifier.weight(1f))
            // B·04 · the timer keeps running while the cancel is armed; the take is still alive.
            Text(RecordingChamber.clock(elapsed), style = NBFont.dot(600, 16f).tracking(0.06f),
                color = if (cancelling) NB.white.copy(alpha = 0.30f) else NB.carbon)
        }
        Spacer(Modifier.weight(1f))
        LevelBars(RecordingChamber.debugLevels ?: levels, cancelling, Modifier.fillMaxWidth().height(52.dp))
        Spacer(Modifier.weight(1f))
        Row(Modifier.height(12.dp), horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            if (!cancelling) Box(Modifier.size(9.dp, 7.dp).background(NB.carbon.copy(alpha = 0.46f), TriangleShape))
            Text(if (cancelling) "SLIDE BACK DOWN TO KEEP" else "SLIDE UP TO CANCEL", style = NBFont.dot(600, 10f).tracking(0.26f),
                color = if (cancelling) NB.white.copy(alpha = 0.30f) else NB.carbon.copy(alpha = 0.50f))
        }
    }
}

/**
 * The waveform: 34 bars 3 pt wide on a 9.3 pt pitch, 6 → 52 pt tall, rounded 1.5. Newest
 * level on the right at full ink, the history fading to 40 % on the left. B·04 freezes the
 * last picture and greys it to 17 % white.
 */
@Composable
fun LevelBars(levels: List<Double>, frozen: Boolean, modifier: Modifier = Modifier) {
    var snapshot by remember { mutableStateOf(emptyList<Double>()) }
    LaunchedEffect(frozen) { snapshot = if (frozen) levels else emptyList() }
    val shown = if (frozen && snapshot.isNotEmpty()) snapshot else levels
    Canvas(modifier) {
        val n = shown.size
        if (n == 0) return@Canvas
        val d = density
        val pitch = 9.3f * d
        val x0 = (size.width - (pitch * (n - 1) + 3 * d)) / 2
        shown.forEachIndexed { i, level ->
            val h = (6 + level.coerceIn(0.0, 1.0).toFloat() * 46) * d
            val alpha = if (frozen) 0.17f else minOf(1f, 0.4f + 0.6f * i / 23f)
            drawRoundRect((if (frozen) NB.white else NB.carbon).copy(alpha = alpha),
                topLeft = Offset(x0 + pitch * i, (size.height - h) / 2), size = Size(3 * d, h),
                cornerRadius = CornerRadius(1.5f * d))
        }
    }
}

/**
 * B·03 · the ring the finger is sliding toward: a 44 pt circle with an ×, and a dotted 36 pt
 * line down to the chamber. B·04 · past −56 px it goes red and the × turns pale.
 */
@Composable
fun CancelMark(armed: Boolean, modifier: Modifier = Modifier) {
    val k by animateFloatAsState(if (armed) 1f else 0f, tween(160, easing = SwiftEaseOut), label = "dock.cancel")
    Canvas(modifier.size(112.dp)) {
        val d = density
        fun p(x: Float, y: Float) = Offset(x * d, y * d)
        fun mix(a: Color, b: Color) = androidx.compose.ui.graphics.lerp(a, b, k)
        drawCircle(mix(NB.carbon.copy(alpha = 0.86f), NB.alert2.copy(alpha = 0.12f)), radius = 22.5f * d, center = p(56f, 40f))
        drawCircle(mix(NB.white.copy(alpha = 0.30f), NB.alert2.copy(alpha = 0.62f)), radius = 22.5f * d, center = p(56f, 40f),
            style = Stroke((1.4f + 0.1f * k) * d))
        val r = 6.5f + 0.5f * k
        val x = Path().apply {
            moveTo(56 * d - r * d, 40 * d - r * d); lineTo(56 * d + r * d, 40 * d + r * d)
            moveTo(56 * d + r * d, 40 * d - r * d); lineTo(56 * d - r * d, 40 * d + r * d)
        }
        drawPath(x, mix(NB.white.copy(alpha = 0.62f), NB.alert1), style = Stroke((1.7f + 0.1f * k) * d, cap = StrokeCap.Round))
        drawLine(mix(NB.white.copy(alpha = 0.22f), NB.alert2.copy(alpha = 0.48f)), p(56f, 66f), p(56f, 104f),
            strokeWidth = (1.5f + 0.1f * k) * d, cap = StrokeCap.Round,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(3 * d, 7 * d)))
    }
}

val TriangleShape = GenericShape { s, _ ->
    moveTo(s.width / 2, 0f); lineTo(s.width, s.height); lineTo(0f, s.height); close()
}

/**
 * B·03 · behind the chamber: the page at 52 % and a 220 pt carbon gradient rising from the
 * dock — the board's two rectangles, drawn once.
 */
@Composable
fun ListeningScrim(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().background(hex(0x09090B, 0.52f)), contentAlignment = Alignment.BottomCenter) {
        Box(
            Modifier.fillMaxWidth().height(220.dp).background(
                Brush.verticalGradient(
                    0f to NB.carbon.copy(alpha = 0f),
                    0.5f to NB.carbon.copy(alpha = 0.74f),
                    1f to NB.carbon.copy(alpha = 0.96f),
                ),
            ),
        )
    }
}

@Composable
fun KeyboardGlyph(modifier: Modifier = Modifier) {
    Canvas(modifier.size(22.dp)) {
        val ink = NB.iconInk
        drawRoundRect(ink, Offset(u(2.5f), u(5.5f)), Size(u(19f), u(13f)), CornerRadius(u(3f)), style = Stroke(u(1.6f)))
        for (x in listOf(5.6f, 9.1f, 12.6f, 16.1f)) {
            drawRoundRect(ink, Offset(u(x), u(9f)), Size(u(1.8f), u(1.8f)), CornerRadius(u(0.4f)))
        }
        for (x in listOf(5.6f, 16.1f)) {
            drawRoundRect(ink, Offset(u(x), u(12.4f)), Size(u(1.8f), u(1.8f)), CornerRadius(u(0.4f)))
        }
        drawRoundRect(ink, Offset(u(8f), u(15.8f)), Size(u(8f), u(1.6f)), CornerRadius(u(0.8f)))
    }
}

@Composable
fun CameraGlyph(modifier: Modifier = Modifier) {
    Canvas(modifier.size(22.dp)) {
        val ink = NB.iconInk
        val stroke = Stroke(u(1.6f), cap = StrokeCap.Round, join = StrokeJoin.Round)
        drawRoundRect(ink, Offset(u(3f), u(7.5f)), Size(u(18f), u(12f)), CornerRadius(u(3f)), style = stroke)
        val lid = Path().apply {
            moveTo(u(9f), u(7.5f)); lineTo(u(10.3f), u(5f)); lineTo(u(13.7f), u(5f)); lineTo(u(15f), u(7.5f))
        }
        drawPath(lid, ink, style = stroke)
        drawCircle(ink, radius = u(3.2f), center = Offset(u(12f), u(13.5f)), style = stroke)
    }
}

@Composable
fun PlusGlyph(modifier: Modifier = Modifier, tint: Color = NB.iconInk) {
    Canvas(modifier.size(22.dp)) {
        val p = Path().apply {
            moveTo(u(12f), u(5f)); lineTo(u(12f), u(19f))
            moveTo(u(5f), u(12f)); lineTo(u(19f), u(12f))
        }
        drawPath(p, tint, style = Stroke(u(1.8f), cap = StrokeCap.Round))
    }
}
