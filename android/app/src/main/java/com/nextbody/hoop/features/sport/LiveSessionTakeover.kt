package com.nextbody.hoop.features.sport

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import com.nextbody.hoop.band.SportHeartFreshness
import com.nextbody.hoop.band.SportSessionRecap
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.measure.MText
import com.nextbody.hoop.features.measure.PanelWidgetSpec
import com.nextbody.hoop.features.measure.toPanelWidget
import com.nextbody.hoop.features.home.panel.PanelWidget
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.ui.Chrome
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.ImpactStyle
import com.nextbody.hoop.ui.pressHold
import com.nextbody.hoop.ui.rememberReduceMotion
import com.nextbody.hoop.ui.swiftSpring
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.math.max
import kotlin.math.min

/**
 * Home's sport-session layer — Swift `HomeView.liveSessionLayer` (zIndex 6, over everything on
 * home) plus the recap sheet the fold leaves behind. Keep it composed on home at all times:
 * it draws nothing until a session starts, and the recap sheet outlives the session.
 *
 * @param panelFrame where the panel sits on home, in home's own coordinates — the frame the
 *   takeover grows from and folds back into.
 * @param onWidget the widget the panel takes when the screen folds (the session summary, or the
 *   refusal line). Swift: `withAnimation(.spring(0.50, 0.80)) { widget = summary }`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LiveSessionLayer(panelFrame: DpRect, onWidget: (PanelWidget) -> Unit) {
    val store = LiveSessionStore
    var completedSport by remember { mutableStateOf<SportSessionRecap?>(null) }

    // DEBUG · the session takeover does not need home hydration.
    LaunchedEffect(Unit) {
        if (store.debugFakeWrist) {
            delay(800)
            store.debugAutoStart(DataStore.profile, DataStore.today.weightKg)
        }
    }

    if (store.session != null) {
        LiveSessionTakeover(panelFrame) { summary ->
            val recap = if (summary?.type == PanelWidgetSpec.Type.workout) store.lastRecap else null
            store.end()
            completedSport = recap
            if (summary != null) onWidget(summary.toPanelWidget())
        }
    }

    completedSport?.let { recap ->
        val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { completedSport = null },
            sheetState = sheet,
            containerColor = NB.panelInk,
            dragHandle = null,
        ) {
            val scope = rememberCoroutineScope()
            SportRecapView(recap) {
                scope.launch { sheet.hide() }.invokeOnCompletion { completedSport = null }
            }
        }
    }
}

/**
 * 14 · LIVE SESSION · the panel grown over the whole home screen for as long as the band is
 * running a sport mode. Not a page and not a cover: the panel's own rectangle, animating its
 * frame and corner radius to full bleed, and folding back into the panel — carrying the
 * session's numbers as one widget — when STOP is held.
 *
 * Three regions and nothing else: LIVE and the sport at the top; the dithered world with the
 * clock and the two wrist numbers; the lime key at the foot, the only way out. Held, not
 * tapped: a session ended by accident cannot be resumed.
 */
@Composable
fun LiveSessionTakeover(panelFrame: DpRect, onFolded: (PanelWidgetSpec?) -> Unit) {
    val store = LiveSessionStore
    val scope = rememberCoroutineScope()
    val reduceMotion = rememberReduceMotion()
    val density = LocalDensity.current

    var grown by remember { mutableStateOf(false) }
    var globeCenter by remember { mutableStateOf(Offset.Zero) }
    var globeRadius by remember { mutableStateOf(110f) }
    val hold = remember { Animatable(0f) }
    var holding by remember { mutableStateOf(false) }
    var hint by remember { mutableStateOf(false) }
    var closing by remember { mutableStateOf(false) }
    val rootCoords = remember { arrayOfNulls<LayoutCoordinates>(1) }

    val mode = store.session?.mode
    val connected = DataStore.band.connected || store.debugFakeWrist
    // The world answers effort three ways: it turns faster, warms into amber, kicks harder.
    val effort = store.effort
    val effortAnimated by animateFloatAsState(effort.toFloat(), tween(1200), label = "effort")
    val turnRate = 0.08 + 0.26 * effort

    // A workout screen that goes dark half-way through a set is a screen nobody can read.
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    fun stopNow() {
        if (closing || store.stopping || store.opening) return
        holding = false
        Haptics.impact(ImpactStyle.Rigid)
        scope.launch {
            val widget = store.stop()
            closing = true
            hold.snapTo(1f)
            // A breath on DONE, then the fold: the panel takes the numbers back.
            delay(700)
            grown = false
            delay(480)
            onFolded(widget)
        }
    }

    LaunchedEffect(Unit) {
        // Now, not after the pop: the panel is already growing under the page's slide.
        delay(40)
        grown = true
        DebugEnv["NB_DEBUG_SESSION_STOP"]?.toDoubleOrNull()?.let { sec ->
            launch { delay((sec * 1000).toLong()); stopNow() }
        }
        DebugEnv["NB_DEBUG_SESSION_HOLD"]?.toFloatOrNull()?.let { frac ->
            holding = true
            hold.snapTo(min(1f, max(0f, frac)))
        }
        if (DebugEnv["NB_DEBUG_SESSION_HINT"] == "1") hint = true
    }

    // The band said no. The screen folds back the way it came, with the reason.
    LaunchedEffect(store.refusal) {
        val line = store.refusal ?: return@LaunchedEffect
        val s = store.session ?: return@LaunchedEffect
        if (closing) return@LaunchedEffect
        closing = true
        val widget = store.refusalWidget(s, line)
        delay(900)
        grown = false
        delay(440)
        onFolded(widget)
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val screenW = maxWidth
        val screenH = maxHeight
        val p by animateFloatAsState(if (grown) 1f else 0f,
            if (grown) swiftSpring(0.42f, 0.86f) else swiftSpring(0.46f, 0.86f), label = "grow")
        val w = lerp(panelFrame.right - panelFrame.left, screenW, p)
        val h = lerp(panelFrame.bottom - panelFrame.top, screenH, p)
        val x = lerp(panelFrame.left, 0.dp, p)
        val y = lerp(panelFrame.top, 0.dp, p)
        val corner = lerp(NB.R.hero, 0.dp, p.coerceIn(0f, 1f))
        val strokeAlpha = (0.08f * (1 - p)).coerceIn(0f, 0.08f)
        val chromeAlpha by animateFloatAsState(if (grown) 1f else 0f,
            tween(220, delayMillis = if (grown) 80 else 0), label = "chrome")

        Box(
            Modifier
                .offset(x, y)
                .requiredSize(max(w.value, 1f).dp, max(h.value, 1f).dp)
                .clip(RoundedCornerShape(corner))
                .border(1.dp, NB.white.copy(alpha = strokeAlpha), RoundedCornerShape(corner))
                .background(NB.panelInk)
                .onGloballyPositioned { rootCoords[0] = it },
            contentAlignment = Alignment.TopStart,
        ) {
            BayerGlobe(center = globeCenter, radius = globeRadius, bpm = store.liveHR,
                effort = effortAnimated.toDouble(), turnRate = turnRate, modifier = Modifier.fillMaxSize())

            // The column is laid out at the screen's size and clipped by the growing panel.
            Column(
                Modifier
                    .requiredSize(screenW, screenH)
                    .offset(x = (screenW - w) / 2, y = (screenH - h) / 2)
                    .alpha(chromeAlpha),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(Modifier.height(ScreenMetrics.safeTop + Chrome.gateTopInset))
                Header(mode?.name ?: "", closing, store.refusal != null, connected)
                // Air under the eyebrow, so the world sits low in its room.
                Spacer(Modifier.height(screenH * 0.055f))
                // The world's room. Its centre is where the globe is drawn — measured in the
                // takeover's own space, so the halo can bleed across the whole screen.
                Box(Modifier.fillMaxWidth().weight(1f).onGloballyPositioned { c ->
                    val root = rootCoords[0] ?: return@onGloballyPositioned
                    if (!root.isAttached || !c.isAttached) return@onGloballyPositioned
                    val origin = root.localPositionOf(c, Offset.Zero)
                    val wDp = with(density) { c.size.width.toDp().value }
                    val hDp = with(density) { c.size.height.toDp().value }
                    if (wDp <= 0 || hDp <= 0) return@onGloballyPositioned
                    globeCenter = Offset(with(density) { origin.x.toDp().value } + wDp / 2,
                        with(density) { origin.y.toDp().value } + hDp / 2)
                    // The disc: 58 % of the column, and never taller than the room it has.
                    globeRadius = min(screenW.value * 0.29f, hDp * 0.46f)
                })
                SessionClock(store.session?.startedAt)
                Stats(store, Modifier.padding(top = 22.dp))
                AnimatedContent(statusLine(store, closing, hint),
                    transitionSpec = { fadeIn(tween(240)) togetherWith fadeOut(tween(240)) }, label = "status",
                    modifier = Modifier.padding(top = 20.dp)) { line ->
                    MText(line, NBFont.dot(600, 10.5f).tracking(0.16f), statusTint(store, closing, hint),
                        Modifier.width(NB.Layout.contentWidth), align = TextAlign.Center)
                }
                StopKey(
                    label = when {
                        store.stopping -> "STOPPING…"
                        closing -> if (store.refusal == null) "SAVED" else "NOT STARTED"
                        holding -> "KEEP HOLDING"
                        else -> "STOP SESSION"
                    },
                    fill = hold.value, holding = holding,
                    enabled = !(closing || store.stopping || store.opening),
                    dim = store.opening,
                    modifier = Modifier.padding(top = 16.dp),
                    onTouch = { down ->
                        if (down) {
                            if (!holding && !closing && !store.stopping && !store.opening) {
                                holding = true
                                hint = false
                                scope.launch { hold.animateTo(1f, tween(900, easing = LinearEasing)) }
                            }
                        } else if (holding) {
                            holding = false
                            if (!closing && !store.stopping && !store.opening) {
                                scope.launch { hold.animateTo(0f, swiftSpring(0.3f, 0.8f)) }
                            }
                        }
                    },
                    onArm = { stopNow() },
                    onTap = {
                        if (!closing && !store.stopping && !store.opening) {
                            hint = true
                            scope.launch { delay(2_400); hint = false }
                        }
                    },
                    onAccessibilityStop = { stopNow() },
                )
                MText(
                    if (closing) L("The session lands on the panel.")
                    else store.energyExplanation ?: L("Hold to stop. The band keeps the session open until you do."),
                    NBFont.ui(300, 12.5f), NB.white.copy(alpha = 0.42f),
                    Modifier.padding(top = 12.dp).width(318.dp), align = TextAlign.Center)
                Spacer(Modifier.height(max(22f, (ScreenMetrics.safeBottom + 8.dp).value).dp))
            }
        }
    }
}

/** LIVE, in lime, with a pip that breathes; the sport beside it. The band's link on the right. */
@Composable
private fun Header(sport: String, closing: Boolean, refused: Boolean, connected: Boolean) {
    Row(Modifier.width(NB.Layout.contentWidth).height(34.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f)) {
            LivePip(on = !closing)
            MText(if (closing) (if (!refused) "DONE" else "REFUSED") else "LIVE",
                NBFont.dot(600, 11f).tracking(0.24f), NB.lime1)
            MText(L("·"), NBFont.dot(600, 11f), NB.white.copy(alpha = 0.28f))
            MText(sport.uppercase(), NBFont.dot(600, 11f).tracking(0.18f), NB.white.copy(alpha = 0.78f), maxLines = 1)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Box(Modifier.size(5.dp).background(if (connected) NB.lime1 else NB.ember1, CircleShape))
            MText(if (connected) "NEXTBODY" else "OFFLINE", NBFont.dot(600, 10f).tracking(0.2f),
                if (connected) NB.white.copy(alpha = 0.42f) else NB.ember1)
        }
    }
}

/** The clock, under the world. Doto, big, white — the world is left whole above it. */
@Composable
private fun SessionClock(startedAt: Instant?) {
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = Instant.now()
            delay(1_000 - (System.currentTimeMillis() % 1_000))
        }
    }
    val text = elapsed(startedAt, now)
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.semantics { contentDescription = L("Elapsed %@", text) }) {
        MText(text, NBFont.dot(700, 56f).tracking(0.02f).copy(fontFeatureSettings = "tnum"), NB.text1)
        MText(L("ELAPSED"), NBFont.dot(600, 10f).tracking(0.3f), NB.white.copy(alpha = 0.42f))
    }
}

private fun elapsed(startedAt: Instant?, now: Instant): String {
    val sec = max(0L, ChronoUnit.SECONDS.between(startedAt ?: now, now)).toInt()
    if (sec >= 3600) return swiftFormat("%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
    return swiftFormat("%02d:%02d", sec / 60, sec % 60)
}

/** The two wrist numbers, each in its own fixed column. Lime while the wrist is being read this
 *  second; 32 % once it is not — a number from before the wrist moved is not a number now. */
@Composable
private fun Stats(store: LiveSessionStore, modifier: Modifier = Modifier) {
    val burn = when {
        !store.hasCalories -> Fmt.dash
        store.wrist == LiveSessionStore.Wrist.off && store.kcal <= 0 -> Fmt.dash
        else -> "${Math.round(store.kcal)}"
    }
    Row(modifier.width(NB.Layout.contentWidth).padding(top = 8.dp)) {
        Readout(store.liveHR?.toString() ?: Fmt.dash, "BPM", L("HEART RATE"),
            store.heartFreshness == SportHeartFreshness.State.live)
        Readout(burn, "KCAL", store.energyLabel, store.wrist == LiveSessionStore.Wrist.live)
    }
}

@Composable
private fun RowScope.Readout(value: String, unit: String, label: String, lit: Boolean) {
    val valueTint by animateColorAsState(if (lit) NB.lime1 else NB.white.copy(alpha = 0.32f), tween(240), label = "v")
    val unitTint by animateColorAsState(NB.white.copy(alpha = if (lit) 0.42f else 0.20f), tween(240), label = "u")
    val labelTint by animateColorAsState(NB.white.copy(alpha = if (lit) 0.34f else 0.20f), tween(240), label = "l")
    Column(Modifier.weight(1f).semantics { contentDescription = "$label $value" },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MText(value, NBFont.brand(700, 34f).tracking(-0.045f).copy(fontFeatureSettings = "tnum"), valueTint,
                Modifier.alignByBaseline())
            MText(unit, NBFont.dot(500, 12f), unitTint, Modifier.alignByBaseline())
        }
        MText(label, NBFont.dot(500, 10f).tracking(0.2f), labelTint)
    }
}

/**
 * The only exit. Held for 0.9 s: the ink wipes across the key under the thumb and the session
 * ends as it reaches the far edge; let go early and it springs back.
 */
@Composable
private fun StopKey(
    label: String, fill: Float, holding: Boolean, enabled: Boolean, dim: Boolean,
    modifier: Modifier = Modifier,
    onTouch: (Boolean) -> Unit, onArm: () -> Unit, onTap: () -> Unit, onAccessibilityStop: () -> Unit,
) {
    val pressScale by animateFloatAsState(if (holding) 0.985f else 1f, tween(120), label = "press")
    val stopLabel = L("Stop session")
    Box(
        modifier
            .width(NB.Layout.contentWidth)
            .height(52.dp)
            .scale(pressScale)
            .alpha(if (dim) 0.55f else 1f)
            .clip(CircleShape)
            .background(NB.lime1)
            .then(if (enabled) Modifier.pressHold(minimumDurationMs = 900, allowsQualifiedRelease = true,
                onTouch = onTouch, onArm = onArm, onLift = { onTouch(false) }, onTap = onTap) else Modifier)
            .semantics {
                contentDescription = stopLabel
                onClick(label = L("Press and hold for one second")) { onAccessibilityStop(); true }
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.align(Alignment.CenterStart).fillMaxHeight().fillMaxWidth(fill.coerceIn(0f, 1f))
            .background(NB.carbon.copy(alpha = 0.34f), CircleShape))
        AnimatedContent(label, transitionSpec = { fadeIn(tween(160)) togetherWith fadeOut(tween(160)) }, label = "key") {
            MText(it, NBFont.ui(500, 12f).tracking(0.2f), NB.carbon)
        }
    }
}

/** The LIVE pip: lime, breathing on a slow two-second cycle. Under Reduce Motion it holds. */
@Composable
private fun LivePip(on: Boolean) {
    val reduceMotion = rememberReduceMotion()
    val transition = rememberInfiniteTransition(label = "pip")
    val breathe by transition.animateFloat(0.22f, 0.06f,
        infiniteRepeatable(tween(1100, easing = androidx.compose.animation.core.FastOutSlowInEasing), RepeatMode.Reverse),
        label = "pipAlpha")
    val halo = if (on && !reduceMotion) breathe else 0.22f
    Box(Modifier.size(14.dp).alpha(if (on) 1f else 0.5f), contentAlignment = Alignment.Center) {
        Box(Modifier.size(14.dp).background(NB.lime1.copy(alpha = halo), CircleShape))
        Box(Modifier.size(6.dp).background(NB.lime1, CircleShape))
    }
}

private fun statusLine(store: LiveSessionStore, closing: Boolean, hint: Boolean): String {
    store.refusal?.let { return L("REFUSED · %@", it.uppercase()) }
    if (closing) return L("SAVED · FOLDING BACK")
    if (store.stopping) return L("CLOSING THE MODE ON THE BAND")
    if (store.opening) return L("OPENING %@ ON THE BAND", (store.session?.mode?.name ?: "").uppercase())
    store.delayedHeartNote?.let { return it }
    if (store.session?.joined == true && store.wrist == LiveSessionStore.Wrist.live) {
        return L("JOINED THE SESSION ALREADY ON THE BAND · LIVE")
    }
    store.errorLine?.let { return it.uppercase() }
    if (hint) return L("HOLD THE KEY TO STOP")
    return when (store.wrist) {
        LiveSessionStore.Wrist.off -> L("TIMING · THE WRIST IS NOT BEING READ")
        LiveSessionStore.Wrist.reaching -> L("READING HEART RATE")
        LiveSessionStore.Wrist.live -> L("HEART RATE FROM THE WRIST · LIVE")
        LiveSessionStore.Wrist.noContact -> L("NO CONTACT · TIGHTEN THE BAND")
        LiveSessionStore.Wrist.offline -> L("BAND OFFLINE · THE CLOCK KEEPS RUNNING")
        LiveSessionStore.Wrist.paused -> L("PAUSED ON THE BAND")
    }
}

private fun statusTint(store: LiveSessionStore, closing: Boolean, hint: Boolean) = when {
    store.refusal != null -> NB.ember2
    closing || store.stopping || store.opening -> NB.lime1.copy(alpha = 0.85f)
    store.errorLine != null -> NB.ember2
    hint -> NB.white.copy(alpha = 0.55f)
    store.delayedHeartNote != null -> NB.white.copy(alpha = 0.55f)
    else -> when (store.wrist) {
        LiveSessionStore.Wrist.live -> NB.lime1
        LiveSessionStore.Wrist.reaching -> NB.lime1.copy(alpha = 0.85f)
        LiveSessionStore.Wrist.noContact -> NB.ember2
        // 06 rule 07 · device-side states are 32 % grey, not amber and not red.
        LiveSessionStore.Wrist.off, LiveSessionStore.Wrist.offline, LiveSessionStore.Wrist.paused -> NB.white.copy(alpha = 0.32f)
    }
}
