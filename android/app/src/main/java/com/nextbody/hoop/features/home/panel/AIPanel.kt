package com.nextbody.hoop.features.home.panel

import androidx.compose.animation.core.animateDpAsState
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.band.BandBattery
import com.nextbody.hoop.band.BandSyncActivity
import com.nextbody.hoop.band.BandSyncPolicy
import com.nextbody.hoop.band.BandSyncProgress
import com.nextbody.hoop.band.IdlePlateLock
import com.nextbody.hoop.band.LiveReadout
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.data.BandState
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.data.LiveVitals
import com.nextbody.hoop.design.MetricNames
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.connect.DottedProgress
import com.nextbody.hoop.features.home.FirstRun
import com.nextbody.hoop.features.home.FirstRunArt
import com.nextbody.hoop.features.home.FirstRunSubtitle
import com.nextbody.hoop.features.home.HalftoneScreen
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.BodyBattery
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.TickFreshness
import com.nextbody.hoop.model.timeIntervalSince
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.services.SessionKeychain
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.PixelCloseMark
import com.nextbody.hoop.ui.bandSyncTint
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.rememberFrameClock
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlinx.coroutines.delay
import java.time.Instant
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * 04 + 07 · the panel. 358 × 470. One widget at a time; every widget is tappable and carries the
 * page it lands on (F0 rule 06).
 *
 * Android port: AI is off (`AIFeature.enabled = false`), so the THINKING stage, the web-sources
 * chip and the "TAP OR TALK" suffix are not drawn — exactly what iOS hides when disabled. What
 * remains: the first-run ceremony plate, a widget printed through the dot screen, and the idle
 * plate (standby art, NOT COLLECTING, the sync header and the Body Battery readout).
 */
@Composable
fun AIPanel(
    /** 补屏 · the NOT COLLECTING button. The panel does not own the router. */
    onTurnOn: () -> Unit = {},
    m: DailyMetrics,
    band: BandState,
    lastSync: Instant?,
    /** 04 · the last five-minute tick. Its age decides whether the readout prints, dims, or dashes. */
    vitals: LiveVitals = LiveVitals(),
    widget: PanelWidget? = null,
    /** 01M · while the ceremony runs, this same surface is the whole screen. */
    firstRun: FirstRun? = null,
    /** Home owns visibility; an offscreen panel retains its pose without drawing frames. */
    idleAnimationActive: Boolean = true,
    size: DpSize = DpSize(NB.Layout.contentWidth, NB.Layout.panelHeight),
    radius: Dp = NB.R.hero,
    onDismissWidget: () -> Unit = {},
    onWidget: (Destination) -> Unit,
) {
    val ceremony = firstRun?.playing == true
    val shape = RoundedCornerShape(radius)
    Box(
        Modifier
            .size(size)
            .clip(shape)
            .background(NB.panelInk)
            .border(1.dp,
                if (widget?.composition != null) NB.lime1.copy(alpha = 0.18f)
                else NB.white.copy(alpha = if (ceremony) 0f else 0.08f), shape),
    ) {
        // Idle planet and a frame never share this box: one plate at a time, no cross-fade.
        when {
            firstRun != null && ceremony -> CeremonyPlate(firstRun, band, size)
            widget != null -> OccupiedPlate(widget, size, onWidget)
            else -> IdlePlate(m, band, vitals, idleAnimationActive, onTurnOn)
        }
        if (widget != null && !ceremony) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 8.dp, end = 2.dp)
                    .size(44.dp)
                    .testTag("panel-dismiss")
                    .semantics { contentDescription = L("Return to standby"); role = Role.Button }
                    .hotZoneTap(pressedOpacity = 1f, pressedScale = 1f) { onDismissWidget() },
                contentAlignment = Alignment.Center,
            ) { PixelCloseMark() }
        }
    }
}

@Composable
private fun CeremonyPlate(firstRun: FirstRun, band: BandState, size: DpSize) {
    Box(Modifier.fillMaxSize()) {
        HalftoneScreen(Modifier.fillMaxSize()) {
            FirstRunArt(coreLit = firstRun.coreLit, orbitFraction = firstRun.orbitFraction,
                spinning = firstRun.orbitSpinning, modifier = Modifier.fillMaxSize())
        }
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            // ◇5 · the hairline pulls open from the centre over 0.3s.
            val w by animateDpAsState(if (firstRun.hairlineOpen) 236.dp else 0.dp, tween(300, easing = com.nextbody.hoop.ui.SwiftEaseOut),
                label = "hairline")
            Box(Modifier.padding(bottom = 22.dp).size(w, 1.dp).background(NB.hairline))
            FirstRunSubtitle(typed = firstRun.typed, bandPaired = band.connected,
                showsCursor = firstRun.beat >= FirstRun.Beat.type && firstRun.beat < FirstRun.Beat.idle)
            Spacer(Modifier.height(size.height * 0.16f))
        }
    }
}

/** One surface. The planet is not in this tree. 07 · the widget is printed, not lit: chart
 *  behind the dot screen, words in front. */
@Composable
private fun OccupiedPlate(widget: PanelWidget, size: DpSize, onWidget: (Destination) -> Unit) {
    Box(Modifier.fillMaxSize()) {
        val printed = widget.title != "THINKING" && widget.composition == null && widget.photo == null && widget.balance == null
        HalftoneScreen(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().background(NB.ledOff)) {
                if (printed) WidgetLayer(widget, PanelWidgetView.Layer.chart, size, onWidget)
            }
        }
        // THINKING is AI-only (AIFeature.enabled = false): never drawn on Android.
        if (widget.title != "THINKING") {
            // Self-contained result canvases draw once above the shared LED surface.
            WidgetLayer(widget,
                if (widget.composition == null && widget.photo == null && widget.balance == null) PanelWidgetView.Layer.text
                else PanelWidgetView.Layer.all,
                size, onWidget)
        }
    }
}

/** One layer of the widget on the board's 358 × 470 canvas, scaled to the panel the phone left.
 *  Both layers use the same transform, so the words land exactly over their LEDs. */
@Composable
private fun WidgetLayer(widget: PanelWidget, layer: PanelWidgetView.Layer, size: DpSize, onWidget: (Destination) -> Unit) {
    val bw = NB.Layout.boardContentWidth
    val bh = NB.Layout.panelHeight.value
    val scale = min(size.width.value / bw, size.height.value / bh)
    val canvasHeight = if (widget.balance != null) size.height.value / scale else bh
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Box(Modifier.requiredSize(bw.dp, canvasHeight.dp).graphicsLayer { scaleX = scale; scaleY = scale }) {
            PanelWidgetView(widget = widget, onTap = onWidget, layer = layer, showsCloseControl = true,
                canvasHeight = canvasHeight.dp)
        }
    }
}

// MARK: idle

/** DEBUG default: each time the app becomes active, walk one look on the review roster so every
 *  paint can be judged. Release stays one plate per user-day. Pin with `NB_DEBUG_PLATE`;
 *  restore the playbook with `NB_DEBUG_PLATE_DAILY=1`. */
private val visitRotateEnabled: Boolean
    get() {
        if (!BuildConfig.DEBUG) return false
        if (IdlePlateDump.requested) return false
        if (DebugEnv["NB_DEBUG_PLATE"] != null) return false
        if (DebugEnv["NB_DEBUG_PLATE_DAILY"] == "1") return false
        return true
    }

@Composable
private fun IdlePlate(
    m: DailyMetrics,
    band: BandState,
    vitals: LiveVitals,
    idleAnimationActive: Boolean,
    onTurnOn: () -> Unit,
) {
    val live = LiveReadout.shared
    var plateLock by remember { mutableStateOf(IdlePlateStore.load()) }
    var visitRotatedForActive by remember { mutableStateOf(false) }

    fun applyVisitPlate(day: String) {
        if (visitRotatedForActive && plateLock?.lockedBy == IdlePlateLock.LockedBy.visit) return
        visitRotatedForActive = true
        val plate = IdlePlateLock.advanceVisit(IdlePlateStore.loadVisitPlate())
        IdlePlateStore.saveVisitPlate(plate)
        plateLock = IdlePlateLock.Snapshot(day = day, plate = plate, lockedBy = IdlePlateLock.LockedBy.visit)
    }

    /** `appear: true` is a new idle show (day may flip). `false` is an in-place tick that may
     *  apply a one-shot event but must not redraw the day pick. */
    fun resolveIdlePlate(appear: Boolean) {
        val day = m.day.key
        val wearer = SessionKeychain.userId ?: band.mac
        if (BuildConfig.DEBUG) {
            val forced = DebugEnv["NB_DEBUG_PLATE"]?.toIntOrNull()
            if (forced != null && forced > 0) {
                val snap = IdlePlateLock.Snapshot(day = day, plate = forced, lockedBy = IdlePlateLock.LockedBy.daily)
                plateLock = snap
                IdlePlateStore.save(snap)
                return
            }
            if (visitRotateEnabled) {
                if (appear) { applyVisitPlate(day); return }
                if (plateLock?.lockedBy == IdlePlateLock.LockedBy.visit) return
            }
        }
        IdlePlateStore.noteConnection(band.connected)
        val stored = plateLock ?: IdlePlateStore.load()
        var snap = IdlePlateLock.appear(wearer = wearer, day = day, stored = stored, idleVisible = !appear,
            hour = Instant.now().atZone(java.time.ZoneId.systemDefault()).hour, bpm = live.liveHR)
        val charge = band.displayedCharge
        val ev = IdlePlateLock.edge(
            reserve = m.bodyBatteryForDisplay(),
            wakeReserve = m.bbWake,
            bandPercent = band.batteryPercent,
            charging = charge == BandBattery.ChargeState.charging || charge == BandBattery.ChargeState.full,
            disconnectedFor = IdlePlateLock.disconnectedFor(bound = band.mac.isNotEmpty(), connected = band.connected,
                disconnectStamp = IdlePlateStore.disconnectStamp(), now = Instant.now()),
            reaching = live.phase == LiveReadout.Phase.reaching,
            noContact = !band.connected,
            bpm = live.liveHR)
        if (ev != null) snap = IdlePlateLock.applyEvent(ev, snap, day)
        plateLock = snap
        IdlePlateStore.save(snap)
    }

    // .onAppear + DEBUG scenePhase: a foreground is a new idle show.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        resolveIdlePlate(appear = true)
        val observer = LifecycleEventObserver { _, event ->
            if (!BuildConfig.DEBUG) return@LifecycleEventObserver
            if (event == Lifecycle.Event.ON_STOP) visitRotatedForActive = false
            else if (event == Lifecycle.Event.ON_RESUME) resolveIdlePlate(appear = true)
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    var first by remember { mutableStateOf(true) }
    LaunchedEffect(m.bodyBattery, band.batteryPercent) {
        if (first) { first = false; return@LaunchedEffect }
        resolveIdlePlate(appear = false)
    }
    var lastConnected by remember { mutableStateOf(band.connected) }
    LaunchedEffect(band.connected) {
        if (band.connected == lastConnected) return@LaunchedEffect
        lastConnected = band.connected
        IdlePlateStore.noteConnection(band.connected)
        resolveIdlePlate(appear = false)
    }

    // #25 · the plate reads the same readout every other entry reads. A wrist that stopped
    // answering leaves the art unknown rather than drawing the last number it saw.
    val reserve = m.bodyBatteryForDisplay()
    Box(Modifier.fillMaxSize()) {
        StandbyArt(
            plate = plateLock?.plate ?: 1,
            charge = reserve?.let { it / 100.0 } ?: 0.0,
            chargeKnown = reserve != null,
            animate = idleAnimationActive,
            modifier = Modifier.fillMaxSize(),
        )
        if (!ConsentStore.granted) {
            // 补屏 edge 1 / 2 · NOT COLLECTING. 「—— 是沉默」 at its limit.
            Column(Modifier.fillMaxSize().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 22.dp)) {
                    BasicText(L("NOT COLLECTING"), style = NBFont.brand(500, 11.5f).tracking(0.08f).copy(color = NB.ember1))
                }
                Spacer(Modifier.weight(1f))
                Column(Modifier.padding(bottom = 30.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    BasicText(L("NEXTBODY isn't reading anything yet."),
                        style = NBFont.brand(400, 18f).tracking(-0.01f).copy(color = NB.white.copy(alpha = 0.88f), textAlign = TextAlign.Center))
                    Box(
                        Modifier.height(44.dp).background(NB.ember1, CircleShape)
                            .semantics { contentDescription = L("Opens the consent screen") }
                            .hotZoneTap(pressedScale = 1f) { onTurnOn() }
                            .padding(horizontal = 26.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        BasicText(L("Turn it on"), style = NBFont.ui(500, 13.5f).tracking(0.15f).copy(color = NB.carbon))
                    }
                }
            }
        } else {
            // The charge cluster sits below the planet's limb; the source line needs 18 of air.
            Column(Modifier.fillMaxSize().padding(top = 16.dp, bottom = 18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Header(band, plateLock)
                Spacer(Modifier.weight(1f))
                StandbyReadout(m, band, vitals)
            }
        }
    }
}

private fun BandSyncProgress.tint(): Color = bandSyncTint(stage.destination == BandSyncProgress.Destination.cloud)

@Composable
private fun Header(band: BandState, plateLock: IdlePlateLock.Snapshot?) {
    val sync = BandSyncActivity.shared
    val live = LiveReadout.shared
    Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f, fill = false).testTag("panel.syncStatus")) {
                ShrinkText(L(headerLine(band, sync, live)),
                    NBFont.brand(500, 11.5f).tracking(0.08f).copy(color = headerTint(band, sync, live)), minScale = 0.75f)
            }
            Spacer(Modifier.weight(1f))
            if (BuildConfig.DEBUG && (visitRotateEnabled || DebugEnv["NB_DEBUG_PLATE"] != null)) {
                BasicText(String.format(java.util.Locale.ROOT, "%02d", plateLock?.plate ?: 0),
                    Modifier.padding(end = 8.dp).testTag("panel.idlePlate"),
                    style = NBFont.dot(600, 10f).tracking(0.24f).copy(color = NB.lime1.copy(alpha = 0.55f)))
            }
            BasicText(Fmt.clock(Instant.now()), style = NBFont.dot(600, 10f).tracking(0.24f).copy(color = NB.white.copy(alpha = 0.30f)))
        }
        if (sync.showsProgress) {
            DottedProgress(progress = sync.fraction, modifier = Modifier.fillMaxWidth().height(4.dp).testTag("panel.syncProgress"),
                lit = sync.workflow.tint(), track = NB.white.copy(alpha = 0.12f))
        }
    }
}

/** 04 · the state word. OFFLINE is the link, NO CONTACT is the wrist, and LIVE is only said
 *  while the band is actually answering — never as a label for a stored number. */
private fun headerLine(band: BandState, sync: BandSyncActivity, live: LiveReadout): String {
    if (sync.showsProgress) return sync.progressLine
    sync.failureLine?.let { return it }
    val phase = when (live.phase) {
        LiveReadout.Phase.live -> if (live.liveHR == null) "reaching" else "live"
        LiveReadout.Phase.stress -> "stress"
        LiveReadout.Phase.reaching -> "reaching"
        LiveReadout.Phase.noContact -> "noContact"
        LiveReadout.Phase.off, LiveReadout.Phase.offline -> "off"
    }
    return BandSyncPolicy.header(activity = sync.phase, connected = band.connected, live = phase)
}

private fun headerTint(band: BandState, sync: BandSyncActivity, live: LiveReadout): Color {
    if (sync.showsProgress) return sync.workflow.tint()
    if (sync.failureLine != null) return NB.ember1
    if (!band.connected) return NB.white.copy(alpha = 0.55f)
    return when {
        live.phase == LiveReadout.Phase.live && live.liveHR != null -> NB.lime1
        live.phase == LiveReadout.Phase.stress -> NB.lime1
        live.phase == LiveReadout.Phase.noContact -> NB.ember1
        else -> NB.white.copy(alpha = 0.55f)
    }
}

/**
 * 04 · the board's type stack: eyebrow over a 64pt hero number, the charge line, HR / STRESS as
 * two centred columns, and the one-line hint at the bottom. Display, not a button.
 * (TimelineView .periodic(by: 60).)
 */
@Composable
private fun StandbyReadout(m: DailyMetrics, band: BandState, vitals: LiveVitals) {
    val now by produceState(Instant.now()) { while (true) { delay(60_000); value = Instant.now() } }
    val live = LiveReadout.shared
    val sync = BandSyncActivity.shared
    val value = m.bodyBatteryForDisplay(now)
    val dim = m.bodyBatteryFreshness(now) != TickFreshness.fresh
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Hairline(width = 236.dp)
        Spacer(Modifier.height(12.dp))
        BasicText(MetricNames.bodyBattery, style = NBFont.dot(600, 11f).tracking(0.34f).copy(color = NB.white.copy(alpha = 0.55f)))
        BasicText(Fmt.int(value), Modifier.padding(top = 4.dp),
            style = NBFont.dot(700, 64f).tracking(-0.045f).copy(color = if (dim) NB.text3Prod else NB.lime1))
        BasicText(chargeLine(m, now), Modifier.padding(top = 6.dp),
            style = NBFont.dot(500, 11f).tracking(0.1f).copy(color = NB.white.copy(alpha = 0.6f)))
        // 13 · past six hours the tick's numbers are gone; a live reading outranks the tick, and
        // each half falls back on its own. A step-only newest tick must not dash HR.
        val gone = vitals.freshness == TickFreshness.gone
        val samples = VitalSample.today(m.vitalsCurve, Instant.now())
        val tickHR = if (gone) null else (vitals.hr ?: samples.lastOrNull { it.hr != null }?.hr)
        val tickStress = if (gone) null else (vitals.stress ?: samples.lastOrNull { it.stress != null }?.stress)
        Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(40.dp)) {
            // 04 · the pip beats at the rate that was just measured — the number told again.
            VitalsColumn(Fmt.int(live.liveHR ?: tickHR), L("HR"), beat = live.liveHR)
            VitalsColumn(Fmt.int(live.liveStress ?: tickStress), L("STRESS"),
                isLive = live.liveStress != null, working = live.phase == LiveReadout.Phase.stress)
        }
        // AIFeature.enabled = false: the source line alone, no "TAP OR TALK — I'M UP".
        BasicText(sourceLine(band, vitals, sync, live), Modifier.padding(top = 8.dp),
            style = NBFont.dot(500, 10.5f).tracking(0.18f).copy(color = NB.white.copy(alpha = 0.42f)))
    }
}

/** 04 · one vitals slot: the reading above its label, centred in a fixed 96 column. A number
 *  measured this second is lime and carries a pip; `working` is the stress test running. */
@Composable
private fun VitalsColumn(value: String, label: String, isLive: Boolean = false, beat: Int? = null, working: Boolean = false) {
    val lit = isLive || beat != null
    Column(Modifier.width(96.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        BasicText(value, style = NBFont.dot(700, 28f).tracking(0.04f)
            .copy(color = if (lit) NB.lime1 else NB.white.copy(alpha = if (working) 0.55f else 0.9f)))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            if (beat != null) BeatPip(beat)
            BasicText(label, style = NBFont.dot(600, 10.5f).tracking(0.2f).copy(color = NB.white.copy(alpha = if (lit) 0.72f else 0.5f)))
        }
    }
}

/** 04 · where the two numbers come from, said in three words. */
private fun sourceLine(band: BandState, vitals: LiveVitals, sync: BandSyncActivity, live: LiveReadout): String {
    if (sync.workflow.active) return L("SYNCING…")
    if (!band.connected) return agoText(vitals)
    return when (live.phase) {
        LiveReadout.Phase.live -> if (live.liveHR != null) L("LIVE") else L("REACHING FOR A BEAT")
        // 04 · the stress test holds the sensor for 19 s; the percentage is the band's own count.
        LiveReadout.Phase.stress -> live.stressProgress?.let { L("MEASURING STRESS · %d%%", it) } ?: L("MEASURING STRESS")
        LiveReadout.Phase.reaching -> L("REACHING FOR A BEAT")
        LiveReadout.Phase.noContact -> L("PUT THE NEXTBODY BACK ON")
        LiveReadout.Phase.off, LiveReadout.Phase.offline -> agoText(vitals)
    }
}

/** State and timestamps describe this battery result, independently of live vitals. */
private fun chargeLine(m: DailyMetrics, now: Instant): String {
    val current = m.bodyBatteryForDisplay(now) ?: return L("NO RECENT READINESS READING")
    val at = m.bodyBatteryObservedAt
    if (m.bodyBatteryFreshness(now) != TickFreshness.fresh && at != null) return L("SYNCED %@", Fmt.clock(at))
    val morning = m.bbWake ?: return L("FROM WRIST DATA")
    return BodyBattery.standbyLine(current, morning)
}

private fun agoText(vitals: LiveVitals): String {
    val at = vitals.at ?: return L("NO TICK")
    val mins = max(0, (Instant.now().timeIntervalSince(at) / 60).toInt())
    if (mins < 1) return L("JUST NOW")
    if (mins < 60) return L("%d MIN AGO", mins)
    return L("%d HR AGO", mins / 60)
}

/**
 * 04 · THE PIP. It blinks at the rate the band just reported: 68 BPM is one blink every 0.88 s.
 * The period is the number. Reduce Motion gets a steady dot.
 */
@Composable
private fun BeatPip(bpm: Int) {
    val reduce = rememberReduceMotion()
    // Clamped to what a wrist can report; a garbled value must not stall or strobe it.
    val period = 60.0 / min(220, max(35, bpm))
    val t = rememberFrameClock(running = !reduce)
    val phase = (t % period) / period
    // A beat, not a fade: bright on the upstroke, decaying across the rest of it.
    val glow = (1 - phase).pow(2.2)
    val alpha = if (reduce) 0.9f else (0.22 + 0.78 * glow).toFloat()
    Canvas(Modifier.size(6.dp).clearAndSetSemantics { }) { drawCircle(NB.lime1.copy(alpha = alpha)) }
}
