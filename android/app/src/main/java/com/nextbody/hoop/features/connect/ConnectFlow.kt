package com.nextbody.hoop.features.connect

import android.Manifest
import android.content.Intent
import android.graphics.BlurMaskFilter
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandCapabilities
import com.nextbody.hoop.band.BandError
import com.nextbody.hoop.band.BandEvent
import com.nextbody.hoop.band.BluetoothState
import com.nextbody.hoop.band.DiscoveredBand
import com.nextbody.hoop.band.FunctionStatus
import com.nextbody.hoop.data.BandState
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.data.SessionStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.auth.GText
import com.nextbody.hoop.features.auth.GateBackKey
import com.nextbody.hoop.features.auth.GatePage
import com.nextbody.hoop.features.auth.GateRepository
import com.nextbody.hoop.features.auth.GateSession
import com.nextbody.hoop.features.auth.lineSpacing
import com.nextbody.hoop.features.auth.plainTap
import com.nextbody.hoop.features.auth.track
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.services.ServiceLog
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.ui.Chrome
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.ImpactStyle
import com.nextbody.hoop.ui.NotificationFeedback
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 02 · Connect 手环配对. No back key out of the flow and no "later": the success screen has
 * exactly one button and it hands straight over to onboarding.
 */
@Composable
fun ConnectFlow() {
    val session = GateSession.current
    val scope = rememberCoroutineScope()

    var step by remember { mutableStateOf(ConnectStep.turnOn) }
    var progress by remember { mutableDoubleStateOf(0.0) }
    var pairStage by remember { mutableIntStateOf(0) }
    var found by remember { mutableStateOf<DiscoveredBand?>(null) }
    var scanTask by remember { mutableStateOf<Job?>(null) }
    // 02 edges · every failure degrades on the screen it happened on: colour and two lines.
    var scanEdge by remember { mutableStateOf<ScanEdge?>(null) }
    var pairEdge by remember { mutableStateOf<PairEdge?>(null) }
    var pairFailures by remember { mutableIntStateOf(0) }
    // 02 rule 05 · low battery never blocks pairing; one amber line on the success screen.
    var lowBatteryLine by remember { mutableStateOf<String?>(null) }
    var scanBegan by remember { mutableStateOf<Instant?>(null) }
    val progressAnim = remember { Animatable(0f) }

    fun mark(value: Double, stage: Int) {
        pairStage = stage
        progress = max(progress, min(1.0, value))
        scope.launch { progressAnim.animateTo(progress.toFloat(), tween(200, easing = com.nextbody.hoop.ui.SwiftEaseOut)) }
    }

    lateinit var go: (ConnectStep) -> Unit

    /** 02 · 02 · the first band found ends the scan. One account owns one band. */
    fun runScan() {
        found = null
        scanEdge = null
        scanTask?.cancel()
        if (DebugEdgeFlag.on("nothingfound")) { scanEdge = ScanEdge.nothingFound; return }
        if (DebugEdgeFlag.on("btoff")) { scanEdge = ScanEdge.bluetoothOff; return }
        if (DebugEdgeFlag.on("permission")) { scanEdge = ScanEdge.permission; return }
        scanBegan = Instant.now()
        track("PAIR_START")
        scanTask = scope.launch {
            // The simulator's stand-in answers without a radio; a real phone asks the adapter.
            if (!Band.allowsSeed) {
                BluetoothState.shared.waitForState()
                if (step != ConnectStep.searching) return@launch
                if (BluetoothState.shared.poweredOff) { scanEdge = ScanEdge.bluetoothOff; return@launch }
                if (BluetoothState.shared.permissionDenied) { scanEdge = ScanEdge.permission; return@launch }
            }
            // Two bands in one room both answer: after the first advertisement the scan listens
            // 1.5 s more and keeps the strongest signal — the band on your wrist.
            var best: DiscoveredBand? = null
            var settle: Job? = null
            // 02 rule 01 · scan 15 s. Edge 1 · the ripples stop, the line changes, the screen stays.
            val timeout = launch {
                delay(15_000)
                if (found == null && step == ConnectStep.searching) {
                    Band.live.stopScan()
                    scanEdge = ScanEdge.nothingFound
                    track("PAIR_FAIL", mapOf("REASON" to "NOTHING_FOUND", "STEP" to "SCAN"))
                }
            }
            val listener = launch(start = CoroutineStart.UNDISPATCHED) {
                Band.live.events.collect { event ->
                    if (event !is BandEvent.Discovered) return@collect
                    val device = event.band
                    if (best == null || device.rssi > best!!.rssi) best = device
                    if (settle == null) {
                        timeout.cancel()
                        settle = launch {
                            delay(1_500)
                            val pick = best ?: return@launch
                            if (step != ConnectStep.searching) return@launch
                            found = pick
                            Band.live.stopScan()
                            val ms = ((System.currentTimeMillis() - (scanBegan?.toEpochMilli() ?: System.currentTimeMillis())))
                            track("PAIR_DEVICE_FOUND", mapOf("MS" to ms.toInt(), "RSSI" to pick.rssi))
                            go(ConnectStep.found)
                        }
                    }
                }
            }
            launch { runCatching { Band.live.startScan() } }
            listener.join()
        }
    }

    /**
     * 02 · 04 · the percentage maps to four real steps. When it stalls it stalls on the number
     * it reached: stopping is more honest than snapping back to zero.
     */
    fun runPairing() {
        progress = 0.0; pairStage = 0; pairEdge = null
        scope.launch { progressAnim.snapTo(0f) }
        val began = System.currentTimeMillis()
        scope.launch {
            try {
                val device = found ?: throw BandError.NotConnected
                session.ensureSession()
                // 02 rule 02 · connect 0–35, authorise 35–60, capabilities 60–85, version 85–100.
                if (DebugEdgeFlag.on("stopped")) throw BandError.Timeout("connect")
                if (DebugEdgeFlag.on("taken")) throw BandError.Rejected("paired elsewhere")
                pairStage = 0
                Band.live.connect(device) { p -> scope.launch { mark(0.35 * p, 0) } }
                mark(0.35, 1)
                val identity = Band.live.readIdentity()
                mark(0.60, 2)
                // The capability table decides which measurement entries exist at all.
                val caps = Band.live.readCapabilities()
                mark(0.85, 3)
                val battery = Band.live.readBattery()
                mark(1.0, 3)
                // 02 rule 05 · isPercent false → BATTERY LOW, never an invented percent.
                if (DebugEdgeFlag.on("lowbattery")) lowBatteryLine = "BATTERY 8%"
                else if (!battery.isPercent) { if ((battery.level ?: 4) <= 1) lowBatteryLine = "BATTERY LOW" }
                else battery.percent?.let { if (it < 10) lowBatteryLine = "BATTERY $it%" }

                DataStore.band = BandState(
                    connected = true, name = identity.name, mac = identity.bleIdentifier,
                    batteryPercent = battery.percent, chargeState = battery.chargeState,
                    firmware = identity.firmware, lastBattery = battery, lastSync = Instant.now(),
                    capabilities = capabilitySet(caps))
                DataStore.applyBandObservation(identity = identity, battery = battery)
                GateRepository.registerDevice(identity, battery)
                val deviceId = GateRepository.deviceId
                val userId = SupabaseClient.currentUserId
                if (deviceId != null && userId != null) {
                    GateRepository.saveCapabilities(caps, deviceId, userId, identity.watchDataDayNumber)
                }
                track("PAIR_SUCCESS", mapOf("MS" to (System.currentTimeMillis() - began).toInt(),
                    "FW" to identity.firmware, "BATTERY" to (battery.percent ?: -1)))
                step = ConnectStep.connected
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Every failure degrades in place, on the screen it happened on.
                ServiceLog.record("pairing", e)
                // 02 edge 4 / 5 · the arms stop, the number freezes, two lines say what happened.
                pairFailures += 1
                pairEdge = if (e is BandError.Rejected) PairEdge.taken else PairEdge.stopped
                track("PAIR_FAIL", mapOf("REASON" to if (pairEdge == PairEdge.taken) "TAKEN" else "STOPPED",
                    "STEP" to STAGES[min(pairStage, 3)]))
            }
        }
    }

    go = { s ->
        step = s
        when (s) {
            ConnectStep.searching -> runScan()
            ConnectStep.pairing -> runPairing()
            else -> scanTask?.cancel()
        }
    }

    /** UNPAIRED · a finished About You is not asked again. NEW / PROFILE GAP go to onboarding. */
    fun handOffAfterPair() {
        scope.launch {
            session.ensureSession()
            val facts = GateRepository.fetchAccountGate()
            session.stage = if (facts.profileComplete) SessionStore.Stage.root else SessionStore.Stage.gateOnboarding
        }
    }

    LaunchedEffect(Unit) { session.ensureSession() }
    // 02 edge 2 · the radio going off mid-search ends the search; coming back restarts it.
    LaunchedEffect(Unit) {
        snapshotFlow { BluetoothState.shared.poweredOff }.drop(1).collect { off ->
            if (step != ConnectStep.searching || Band.allowsSeed) return@collect
            if (off) { scanTask?.cancel(); launch { Band.live.stopScan() }; scanEdge = ScanEdge.bluetoothOff }
            else if (scanEdge == ScanEdge.bluetoothOff) runScan()
        }
    }
    LaunchedEffect(Unit) {
        snapshotFlow { BluetoothState.shared.permissionDenied }.drop(1).collect { denied ->
            if (step != ConnectStep.searching || Band.allowsSeed) return@collect
            if (denied) { scanTask?.cancel(); launch { Band.live.stopScan() }; scanEdge = ScanEdge.permission }
            else if (scanEdge == ScanEdge.permission) runScan()
        }
    }
    // DEBUG · `NB_DEBUG_CONNECT_STEP=3` opens the flow on that screen for a walk.
    LaunchedEffect(Unit) {
        val n = DebugEnv["NB_DEBUG_CONNECT_STEP"]?.toIntOrNull() ?: return@LaunchedEffect
        val st = ConnectStep.entries.firstOrNull { it.raw == n } ?: return@LaunchedEffect
        step = st
        if (st == ConnectStep.searching) {
            if (DebugEdgeFlag.on("nothingfound")) scanEdge = ScanEdge.nothingFound
            else if (DebugEdgeFlag.on("btoff")) scanEdge = ScanEdge.bluetoothOff
            else if (DebugEdgeFlag.on("permission")) scanEdge = ScanEdge.permission
        }
        if (st == ConnectStep.found && found == null) found = DiscoveredBand("debug-found", "NEXTBODY", -48, 96)
        if (st == ConnectStep.pairing) {
            progress = DebugEnv["NB_DEBUG_PAIR_PROGRESS"]?.toDoubleOrNull()?.coerceIn(0.0, 1.0) ?: 0.60
            progressAnim.snapTo(progress.toFloat())
            pairStage = 2
            if (DebugEdgeFlag.on("stopped")) { pairEdge = PairEdge.stopped; pairFailures = 1 }
            if (DebugEdgeFlag.on("taken")) pairEdge = PairEdge.taken
        }
        if (st == ConnectStep.connected && DebugEdgeFlag.on("lowbattery")) lowBatteryLine = "BATTERY 8%"
    }

    // Android's Bluetooth permission is a runtime prompt: the scan asks for it the first time,
    // and only a refusal becomes PERMISSION NEEDED (iOS's system prompt plays the same part).
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        BluetoothState.shared.start()
        go(ConnectStep.searching)
    }
    fun startSearching() {
        if (!Band.allowsSeed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            BluetoothState.shared.start()
            if (BluetoothState.shared.permissionDenied) {
                step = ConnectStep.searching
                permissionLauncher.launch(arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT))
                return
            }
        }
        go(ConnectStep.searching)
    }

    BackHandler(enabled = step == ConnectStep.searching || step == ConnectStep.found) {
        if (step == ConnectStep.searching) go(ConnectStep.turnOn) else startSearching()
    }

    GatePage {
        Box(Modifier.fillMaxSize()) {
            when (step) {
                ConnectStep.turnOn -> TurnItOn { startSearching() }
                ConnectStep.searching -> Searching(onBack = { go(ConnectStep.turnOn) }, edge = scanEdge,
                    onSearchAgain = { startSearching() })
                ConnectStep.found -> FoundIt(found, onBack = { startSearching() }, onConnect = { go(ConnectStep.pairing) },
                    onSearchAgain = { startSearching() })
                ConnectStep.pairing -> Pairing(progressAnim.value.toDouble(), pairStage, pairEdge, pairFailures,
                    onRetry = { go(ConnectStep.pairing) }, onSearchAgain = { startSearching() })
                ConnectStep.connected -> Connected(lowBatteryLine) { handOffAfterPair() }
            }
        }
    }
}

internal enum class ConnectStep(val raw: Int) { turnOn(1), searching(2), found(3), pairing(4), connected(5) }
internal enum class ScanEdge { nothingFound, bluetoothOff, permission }
internal enum class PairEdge { stopped, taken }

/** 04 · the percentage maps to four real steps; the number moves when the band answers. */
private val STAGES = listOf("CONNECT", "AUTHORISE", "READ CAPABILITIES", "READ FIRMWARE")

private fun capabilitySet(caps: BandCapabilities): Set<BandState.Capability> {
    val out = mutableSetOf<BandState.Capability>()
    val s = FunctionStatus.support
    if (caps.bodyComponent == s) out += BandState.Capability.bodyComponent
    if (caps.ecg == s) out += BandState.Capability.ecg
    if (caps.hrv == s || caps.functions["heart"] == s) out += BandState.Capability.heartRate
    if (caps.functions["temperature"] == s) out += BandState.Capability.temperature
    if (caps.autoMeasure == s) out += BandState.Capability.alarms
    if (caps.wearDetection == s) out += BandState.Capability.wearDetection
    if (caps.functions["spo2"] == s) out += BandState.Capability.bloodOxygen
    if (caps.functions["blood"] == s) out += BandState.Capability.bloodPressure
    return out
}

// MARK: shared chrome

/** A board-placed layer: top-left at (x, boardY) inside the safe area. */
private fun Modifier.at(x: Dp = 0.dp, y: Dp): Modifier = this.offset(x = x, y = y)

@Composable
private fun PairHeader(index: Int, onBack: (() -> Unit)? = null) {
    Row(Modifier.width(NB.Layout.contentWidth).height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null) GateBackKey(onBack) else Spacer(Modifier.size(44.dp))
        Spacer(Modifier.width(16.dp)) // 8 + 0 + 8, as SwiftUI spaces around the Spacer
        Spacer(Modifier.weight(1f))
        GText(L("PAIRING %02d / 05", index), NBFont.dot(600, 11f).tracking(0.3f), NB.text3Prod)
    }
}

@Composable
private fun PairTitle(title: String, sub: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(start = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        GText(title, NBFont.ui(500, 32f).tracking(0.01f), NB.text1)
        GText(sub, NBFont.ui(300, 15f).tracking(0.02f).lineSpacing(24f - 15f), NB.text2, Modifier.width(320.dp))
    }
}

/** Header + title, the column every Connect screen starts with. */
@Composable
private fun PairTop(index: Int, title: String, sub: String, onBack: (() -> Unit)? = null) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(Chrome.gateTopInset))
        PairHeader(index, onBack)
        PairTitle(title, sub, Modifier.padding(top = 24.dp))
    }
}

/** The lime 56pt pill every gate screen ends on. */
@Composable
fun LimePillButton(title: String, enabled: Boolean = true, modifier: Modifier = Modifier, action: () -> Unit) {
    Box(
        // plainTap first, so its disabled fade covers the capsule as well as the title.
        modifier.width(NB.Layout.contentWidth).height(56.dp).plainTap(enabled = enabled, onClick = action)
            .alpha(if (enabled) 1f else 0.4f).background(NB.lime1, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        GText(title, NBFont.ui(500, 15f).tracking(0.06f), NB.carbon, maxLines = 1)
    }
}

@Composable
private fun PanelPage(content: @Composable BoxScope.() -> Unit) {
    Box(Modifier.fillMaxSize().background(NB.panelInk), content = content)
}

// MARK: 01 · 开机 Turn it on

@Composable
private fun TurnItOn(onNext: () -> Unit) {
    val w = NB.Layout.screenWidth
    PanelPage {
        BandPortrait(Modifier.at(y = Chrome.boardY(252f)).size(w, 470.dp), sideKeyLit = true,
            ripples = listOf(34f, 58f, 82f), rippleAlpha = listOf(0.42f, 0.20f, 0.08f))
        PairTop(1, L("Turn it on"), L("Hold the button on the right edge for two seconds, until the band lights up."))
        GText(L("HOLD 2S"), NBFont.dot(800, 13f).tracking(0.24f), NB.lime1,
            Modifier.at(y = Chrome.boardY(608f)).width(w), align = TextAlign.Center)
        // The only real dead end in the flow, answered on the screen it happens on.
        GText(L("Nothing lights up? It may be flat — charge it for ten minutes, then hold again."),
            NBFont.ui(300, 13f).tracking(0.02f).lineSpacing(20f - 13f), NB.text3Prod,
            Modifier.at(x = 32.dp, y = Chrome.boardY(640f)).width(w - 64.dp), align = TextAlign.Center)
        LimePillButton(L("It's on"), modifier = Modifier.at(x = 16.dp, y = Chrome.boardY(708f)), action = onNext)
    }
}

/** The band seen head-on: strap fading top and bottom, case, dot-matrix face, lime side key. */
@Composable
fun BandPortrait(
    modifier: Modifier = Modifier,
    sideKeyLit: Boolean = false,
    faceLit: Boolean = false,
    ripples: List<Float> = emptyList(),
    rippleAlpha: List<Float> = emptyList(),
    scanRings: List<Float> = emptyList(),
) {
    val strap = hex(0x15161A)
    Canvas(modifier) {
        val sx = size.width / 390f
        val sy = size.height / 470f
        fun rr(x: Float, y: Float, w: Float, h: Float, r: Float, brush: Brush) =
            drawRoundRect(brush, Offset(x * sx, y * sy), Size(w * sx, h * sy), CornerRadius(r * sx))
        rr(161f, 0f, 68f, 118f, 14f, Brush.verticalGradient(listOf(strap.copy(alpha = 0f), strap), 0f, 118f * sy))
        rr(161f, 302f, 68f, 168f, 14f, Brush.verticalGradient(listOf(strap, strap.copy(alpha = 0f)), 302f * sy, 470f * sy))
        drawRoundRect(hex(0x17181C), Offset(139f * sx, 112f * sy), Size(112f * sx, 196f * sy), CornerRadius(36f * sx))
        drawRoundRect(NB.white.copy(alpha = 0.07f), Offset(139f * sx, 112f * sy), Size(112f * sx, 196f * sy),
            CornerRadius(36f * sx), style = Stroke(1.dp.toPx()))
        // face · the LEDs light up, the panel behind them does not.
        val face = androidx.compose.ui.graphics.Path().apply {
            addRoundRect(androidx.compose.ui.geometry.RoundRect(153f * sx, 126f * sy, (153f + 84f) * sx, (126f + 168f) * sy,
                CornerRadius(26f * sx)))
        }
        drawPath(face, hex(0x0A0A0D))
        clipPath(face) {
            val dot = if (faceLit) NB.lime1 else hex(0x24252C)
            var y = 127f
            while (y < 294f) {
                var x = 154f
                while (x < 237f) {
                    drawRoundRect(dot, Offset(x * sx, y * sy), Size(3.2f * sx, 3.2f * sy), CornerRadius(0.8f * sx))
                    x += 4f
                }
                y += 4f
            }
        }
        if (sideKeyLit) {
            drawRoundRect(NB.lime1, Offset(251f * sx, 186f * sy), Size(8f * sx, 48f * sy), CornerRadius(4f * sx))
        }
        ripples.forEachIndexed { i, rad ->
            val a = if (i < rippleAlpha.size) rippleAlpha[i] else 0.2f
            drawOval(NB.lime1.copy(alpha = a), Offset((255f - rad) * sx, (210f - rad) * sy), Size(rad * 2 * sx, rad * 2 * sy),
                style = Stroke(3f * sx))
        }
        for (rad in scanRings) {
            drawOval(NB.white.copy(alpha = 0.07f), Offset((195f - rad) * sx, (210f - rad) * sy), Size(rad * 2 * sx, rad * 2 * sy),
                style = Stroke(1.5f * sx))
        }
    }
}

// MARK: 02 · 搜索 Searching

@Composable
private fun Searching(onBack: () -> Unit, edge: ScanEdge?, onSearchAgain: () -> Unit) {
    val w = NB.Layout.screenWidth
    val context = LocalContext.current
    // Edge 1 · the ripples stop and go white 18%; edge 2 · the band drops to 20%.
    var t by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(edge) {
        if (edge != null) { t = 0.0; return@LaunchedEffect }
        while (isActive) withFrameNanos { t = System.currentTimeMillis() / 1000.0 }
    }
    PanelPage {
        // The ripple is white and the screen has no green in it — success colour is not
        // allowed before there is a success.
        val rings = (0 until 4).map { i ->
            val p = ((t * 0.35 + i * 0.25) % 1.0)
            60f + p.toFloat() * 130f
        }
        BandPortrait(Modifier.at(y = Chrome.boardY(252f)).size(w, 470.dp)
            .alpha(if (edge == null) 1f else if (edge == ScanEdge.bluetoothOff) 0.2f else 0.18f), scanRings = rings)
        PairTop(2, L("Searching"), L("Keep the band close to your phone. This usually takes a few seconds."), onBack)
        when (edge) {
            null -> {
                GText(L("SCANNING"), NBFont.dot(600, 12f).tracking(0.34f), NB.white.copy(alpha = 0.42f),
                    Modifier.at(y = Chrome.boardY(700f)).width(w), align = TextAlign.Center)
                GText(L("Keep it within arm's reach."), NBFont.ui(300, 13f).tracking(0.02f), NB.text3Prod,
                    Modifier.at(y = Chrome.boardY(750f)).width(w), align = TextAlign.Center)
            }
            ScanEdge.nothingFound -> {
                // 02 edge 1 · NOTHING FOUND. Not a new page — this is screen 02 itself.
                Column(Modifier.at(y = Chrome.boardY(604f)).width(w), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    GText(L("NOTHING FOUND"), NBFont.dot(600, 12f).tracking(0.22f), NB.white.copy(alpha = 0.48f))
                    GText(L("· Is the band lit up\n· Is it further than an arm away\n· Is it still linked to another phone"),
                        NBFont.ui(300, 13f).lineSpacing(8f), NB.white.copy(alpha = 0.50f), Modifier.width(NB.Layout.contentWidth))
                    Box(Modifier.width(NB.Layout.contentWidth).height(44.dp).border(1.dp, NB.white.copy(alpha = 0.16f), CircleShape)
                        .plainTap(onClick = onSearchAgain), contentAlignment = Alignment.Center) {
                        GText(L("Search again"), NBFont.ui(500, 14f).tracking(0.04f), NB.white)
                    }
                }
            }
            ScanEdge.bluetoothOff, ScanEdge.permission -> {
                // 02 edge 2 · only the status line turns amber; Settings, then rescan by itself.
                val off = edge == ScanEdge.bluetoothOff
                Column(Modifier.at(y = Chrome.boardY(660f)).width(w), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    GText(L(if (off) "BLUETOOTH IS OFF" else "PERMISSION NEEDED"), NBFont.dot(600, 12f).tracking(0.22f),
                        NB.ember1.copy(alpha = 0.85f))
                    GText(L(if (off) "I can’t look for the band without it." else "Bluetooth access is off. I can’t look for the band without it."),
                        NBFont.brand(400, 13.5f), NB.white.copy(alpha = 0.70f), align = TextAlign.Center)
                    GText(L(if (off) "Open Bluetooth →" else "Open Settings →"), NBFont.ui(500, 14f).tracking(0.04f), NB.lime1,
                        Modifier.padding(top = 6.dp).plainTap {
                            val intent = if (off) Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.fromParts("package", context.packageName, null))
                            runCatching { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                        })
                }
            }
        }
    }
}

// MARK: 03 · 找到 Found

@Composable
private fun FoundIt(band: DiscoveredBand?, onBack: () -> Unit, onConnect: () -> Unit, onSearchAgain: () -> Unit) {
    val w = NB.Layout.screenWidth
    PanelPage {
        // The full ring only lights here: the watch is what lit up, not the app.
        val ringTop = Chrome.boardY(252f) + 210.dp - 116.dp
        Canvas(Modifier.at(y = ringTop - 40.dp).size(w, 232.dp + 80.dp)) {
            val c = Offset(size.width / 2, size.height / 2)
            val r = 116.dp.toPx()
            drawIntoCanvas { cv ->
                val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = 2.dp.toPx()
                    color = NB.lime1.copy(alpha = 0.35f).toArgb()
                    maskFilter = BlurMaskFilter(26.dp.toPx() / 2, BlurMaskFilter.Blur.NORMAL)
                }
                cv.nativeCanvas.drawCircle(c.x, c.y, r, glow)
            }
            drawCircle(NB.lime1, r, c, style = Stroke(2.dp.toPx()))
        }
        BandPortrait(Modifier.at(y = Chrome.boardY(252f)).size(w, 470.dp), faceLit = true)
        PairTop(3, L("Found it"), L("One band is in range. Tap connect and keep it near your phone."), onBack)
        DeviceRow(band, Modifier.at(x = 16.dp, y = Chrome.boardY(600f)))
        LimePillButton(L("Connect"), modifier = Modifier.at(x = 16.dp, y = Chrome.boardY(700f)), action = onConnect)
        GText(L("Not your band? Search again"), NBFont.ui(400, 13f).tracking(0.02f), NB.text3Prod,
            Modifier.at(y = Chrome.boardY(770f)).width(w).plainTap(onClick = onSearchAgain), align = TextAlign.Center)
    }
}

/** RSSI in dBm, not a percentage. −50 is on the desk, −90 is in the next room. */
internal fun signalBars(rssi: Int?): Int = when {
    rssi == null -> 0
    rssi >= -55 -> 4
    rssi >= -67 -> 3
    rssi >= -80 -> 2
    else -> 1
}

/** One found band. ⚠️ Never a serial number on this card — the SDK has no such field. */
@Composable
private fun DeviceRow(band: DiscoveredBand?, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(NB.R.spec)
    Row(
        modifier.width(NB.Layout.contentWidth).height(72.dp).background(NB.carbon4, shape).border(1.dp, NB.hairline, shape)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        Canvas(Modifier.size(34.dp)) {
            val c = Offset(size.width / 2, size.height / 2)
            drawCircle(NB.lime1.copy(alpha = 0.12f))
            drawCircle(NB.lime1.copy(alpha = 0.35f), radius = size.width / 2 - 0.5.dp.toPx(), style = Stroke(1.dp.toPx()))
            drawCircle(NB.lime1, radius = 5.5.dp.toPx() - 1.dp.toPx(), center = c, style = Stroke(2.dp.toPx()))
            drawRect(NB.lime1, Offset(c.x - 1.dp.toPx(), c.y - 6.dp.toPx() - 3.5.dp.toPx()), Size(2.dp.toPx(), 7.dp.toPx()))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            GText(band?.name?.uppercase() ?: "NEXTBODY", NBFont.ui(500, 15f).tracking(0.02f), NB.text1, maxLines = 1)
            GText(L("READY TO PAIR"), NBFont.dot(600, 10f).tracking(0.2f), NB.text3Prod)
        }
        Spacer(Modifier.width(0.dp))
        // A band that has not told us its charge yet says so, rather than showing 96%.
        GText(band?.batteryPercent?.let { "$it%" } ?: Fmt.dash, NBFont.dot(600, 10f).tracking(0.1f), NB.text3Prod)
        SignalBars(signalBars(band?.rssi))
    }
}

@Composable
fun SignalBars(level: Int, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.Bottom) {
        for (i in 0 until 4) {
            Box(Modifier.size(3.dp, (4 + i * 3).dp)
                .background(if (i < level) NB.limePale else NB.white.copy(alpha = 0.18f), RoundedCornerShape(1.dp)))
        }
    }
}

// MARK: 04 · 配对 Pairing

/** SwiftUI's `.grayscale(1).colorMultiply(ember)` on one colour. */
private fun amber(c: Color): Color {
    val l = 0.2126f * c.red + 0.7152f * c.green + 0.0722f * c.blue
    return Color(NB.ember1.red * l, NB.ember1.green * l, NB.ember1.blue * l, c.alpha)
}

@Composable
private fun Pairing(
    progress: Double,
    stage: Int,
    edge: PairEdge?,
    failures: Int,
    onRetry: () -> Unit,
    onSearchAgain: () -> Unit,
) {
    val w = NB.Layout.screenWidth
    val cw = NB.Layout.contentWidth
    // An ASCII planet turning in glyphs, 24 frames a second.
    var t by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(edge) {
        if (edge != null) { t = 0.0; return@LaunchedEffect }
        while (isActive) {
            t = (System.currentTimeMillis() % 100_000_000L) / 1000.0
            delay(1000L / 24)
        }
    }
    PanelPage {
        // Edge 4 · the planet stops turning and the whole thing goes amber.
        AsciiPlanet(t = if (edge == null) t else 0.0, progress = progress, amber = edge != null,
            modifier = Modifier.at(y = Chrome.boardY(260f)).size(w, 400.dp))
        PairTop(4, L("Pairing"), L("Keep it close — pulling everything into place."))
        Row(Modifier.at(x = 16.dp, y = Chrome.boardY(636f)).width(cw), verticalAlignment = Alignment.Bottom) {
            GText(if (edge == null) L("PAIRING") else L("STOPPED"), NBFont.dot(600, 11f).tracking(0.3f),
                if (edge == null) NB.text3Prod else NB.ember1.copy(alpha = 0.85f), Modifier.weight(1f).padding(bottom = 3.dp))
            Spacer(Modifier.width(16.dp))
            // The number freezes where it was — zero would look like 「白干了」.
            GText("${(progress * 100).toInt()}%", NBFont.dot(700, 22f).tracking(0.02f), if (edge == null) NB.lime1 else NB.ember1)
        }
        DottedProgress(progress, Modifier.at(x = 16.dp, y = Chrome.boardY(672f)).size(cw, 6.dp),
            lit = if (edge == null) NB.lime1 else amber(NB.lime1),
            track = if (edge == null) NB.white.copy(alpha = 0.10f) else amber(NB.white.copy(alpha = 0.10f)))
        if (edge != null) {
            Column(Modifier.at(x = 16.dp, y = Chrome.boardY(690f)).width(cw), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (edge == PairEdge.taken) {
                    // 02 edge 5 · the most common real reason an auth fails, named, with two steps.
                    GText(L("TAKEN BY ANOTHER PHONE"), NBFont.dot(600, 12f).tracking(0.22f), NB.ember1.copy(alpha = 0.85f))
                    GText(L("This band is still paired somewhere else."), NBFont.brand(400, 13.5f), NB.white.copy(alpha = 0.70f))
                    Hairline()
                    GText(L("1 · Disconnect it on that phone\n2 · Or hold the side button to restart the band"),
                        NBFont.ui(300, 13.5f).lineSpacing(8f), NB.white.copy(alpha = 0.60f))
                } else {
                    GText(L("The band stopped answering. Nothing you did wrong."), NBFont.brand(400, 13.5f), NB.white.copy(alpha = 0.70f))
                }
                Box(Modifier.width(cw).height(44.dp).background(NB.lime1, CircleShape).plainTap(onClick = onRetry),
                    contentAlignment = Alignment.Center) {
                    GText(L("Try again"), NBFont.ui(500, 14f).tracking(0.06f), NB.carbon)
                }
                // Only the second failure offers the way back to 02.
                if (failures >= 2) {
                    GText(L("Search again"), NBFont.ui(300, 13f).tracking(0.02f), NB.text3Prod,
                        Modifier.width(cw).plainTap(onClick = onSearchAgain), align = TextAlign.Center)
                }
            }
        } else {
            GText(STAGES[min(stage, 3)], NBFont.dot(500, 10f).tracking(0.2f), NB.white.copy(alpha = 0.34f),
                Modifier.at(x = 16.dp, y = Chrome.boardY(690f)).width(cw))
            GText(L("Keep it within arm's reach."), NBFont.ui(300, 13f).tracking(0.02f), NB.text3Prod,
                Modifier.at(y = Chrome.boardY(730f)).width(w), align = TextAlign.Center)
        }
    }
}

@Composable
fun DottedProgress(
    progress: Double,
    modifier: Modifier = Modifier,
    /** The lime card needs a carbon bar; everywhere else the lime one is right. */
    lit: Color = NB.lime1,
    track: Color = NB.white.copy(alpha = 0.10f),
) {
    Canvas(modifier) {
        val n = 60
        val u = density
        val pitch = size.width / n
        for (i in 0 until n) {
            val on = i.toDouble() / n < progress
            drawRoundRect(if (on) lit else track, Offset(i * pitch, 1f * u), Size(pitch - 2f * u, 4f * u), CornerRadius(1f * u))
        }
    }
}

/** ASCII planet: a lit sphere of banded gas drawn in glyphs. Geometry once; each frame re-shades. */
private object PlanetGeometry {
    const val diameter = 240f
    // As on iOS: a coarser grid in debug builds, which keeps the per-frame shading cheap.
    val columns = if (com.nextbody.hoop.BuildConfig.DEBUG) 32 else 51
    val ramp = listOf(" ", ".", ":", "-", "=", "+", "*", "%", "#", "@")
    val cellW = diameter / columns
    val cellH = cellW * 1.45f

    class Cell(val x: Float, val y: Float, val u: Double, val v: Double, val z: Double,
               val lat: Double, val lon: Double, val hash: Double, val i: Int, val j: Int)

    val cells: List<Cell> by lazy {
        val r = (diameter / 2).toDouble()
        val ni = ceil(r / cellW).toInt() + 1
        val nj = ceil(r / cellH).toInt() + 1
        val th = 20.0 * PI / 180
        val ph = 14.0 * PI / 180
        val out = mutableListOf<Cell>()
        for (j in -nj..nj) for (i in -ni..ni) {
            val dx = i * cellW.toDouble()
            val dy = j * cellH.toDouble()
            val u = dx / r
            val v = dy / r
            val r2 = u * u + v * v
            if (r2 > 1) continue
            val z = sqrt(1 - r2)
            val u1 = u * cos(th) - v * sin(th)
            val v1 = v * cos(th) + u * sin(th)
            val yy = -v1
            val y2 = yy * cos(ph) + z * sin(ph)
            val z2 = z * cos(ph) - yy * sin(ph)
            out += Cell(dx.toFloat(), dy.toFloat(), u, v, z, y2, atan2(u1, z2), hash3(i, j, 991), i, j)
        }
        out
    }

    fun hash3(a: Int, b: Int, c: Int): Double {
        var h = (a * 374761393 + b * 668265263 + c * 1274126177).toUInt()
        h = (h xor (h shr 13)) * 1274126177u
        h = h xor (h shr 16)
        return h.toDouble() / 4294967296.0
    }

    fun noise(x: Double, y: Double, z: Double): Double {
        val xi = floor(x).toInt(); val yi = floor(y).toInt(); val zi = floor(z).toInt()
        val xf = x - xi; val yf = y - yi; val zf = z - zi
        val u = xf * xf * (3 - 2 * xf); val w = yf * yf * (3 - 2 * yf); val q = zf * zf * (3 - 2 * zf)
        fun h(a: Int, b: Int, c: Int) = hash3(a + xi, b + yi, c + zi + 7)
        val x00 = h(0, 0, 0) + (h(1, 0, 0) - h(0, 0, 0)) * u
        val x10 = h(0, 1, 0) + (h(1, 1, 0) - h(0, 1, 0)) * u
        val x01 = h(0, 0, 1) + (h(1, 0, 1) - h(0, 0, 1)) * u
        val x11 = h(0, 1, 1) + (h(1, 1, 1) - h(0, 1, 1)) * u
        val y0 = x00 + (x10 - x00) * w
        val y1 = x01 + (x11 - x01) * w
        return y0 + (y1 - y0) * q
    }

    fun clamp01(x: Double) = min(1.0, max(0.0, x))
    fun smooth(a: Double, b: Double, x: Double): Double { val k = clamp01((x - a) / (b - a)); return k * k * (3 - 2 * k) }
}

@Composable
private fun AsciiPlanet(t: Double, progress: Double, amber: Boolean, modifier: Modifier) {
    val paints = remember { arrayOfNulls<Paint>(2) }
    Canvas(modifier) {
        val g = PlanetGeometry
        val u = density
        val primary = if (amber) amber(hex(0xDBE6FF)) else hex(0xDBE6FF)
        val accent = if (amber) amber(NB.lime1) else NB.lime1
        for ((k, col) in listOf(primary, accent).withIndex()) {
            val p = paints[k] ?: Paint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
                textAlign = Paint.Align.CENTER
            }.also { paints[k] = it }
            p.textSize = g.cellH * 1.12f * u
            // iOS sets these in SF Mono Heavy; the system mono tops out at Bold, so a hairline stroke adds the rest.
            p.style = Paint.Style.FILL_AND_STROKE
            p.strokeWidth = p.textSize * 0.05f
            p.color = col.toArgb()
        }
        val fm = paints[0]!!.fontMetrics
        val baselineShift = -(fm.ascent + fm.descent) / 2

        val period = 24.0 / 1.06
        val rot = ((t % period) / period) * 2 * PI
        val shearPhase = (t / (period / 4)) * 2 * PI
        val shearA = 0.03 * 2 * PI
        val tick = floor(t * 10).toInt()
        val nb = 8.0; val fill = 0.78; val warp = 0.4; val s = 1.4; val cut = 0.15; val sFloor = 0.4
        val det = 0.35; val amb = 0.35; val con = 1.7; val empty = 0.05
        val atThr = 1 - 0.0075 * 22
        val shim = if (t == 0.0) 0.0 else 0.2 * 2 / 9
        val rimA = 0.2
        val lx = 0.2; val ly = 0.2
        val lz = sqrt(max(0.05, 1 - lx * lx - ly * ly))
        val cx = size.width / 2
        val cy = size.height / 2

        drawIntoCanvas { canvas ->
            val nc = canvas.nativeCanvas
            for (cell in g.cells) {
                val y2 = cell.lat
                val lon = cell.lon - rot + shearA * sin(shearPhase + y2 * nb * 1.3)
                val cs = cos(lon); val sn = sin(lon)
                val wn = g.noise(cs * 2.2, sn * 2.2, y2 * 5 + 11) * 0.65 + g.noise(cs * 4.4, sn * 4.4, y2 * 10 + 23) * 0.35 - 0.5
                val phase = (y2 + wn * warp * 0.25) * PI * nb
                val cc = 0.5 + 0.5 * cos(phase)
                val stripe = g.clamp01((cc - (1 - fill)) / fill)
                if (stripe <= 0) continue
                var f = 0.0; var amp = 0.5; var fr = s
                repeat(3) {
                    f += g.noise(cs * fr, sn * fr, (y2 * nb * 0.7 + 3) * (fr / s)) * amp
                    amp *= 0.5; fr *= 2
                }
                f /= 0.875
                val fs = (f - 0.5) * 2.2 + 0.5
                val streak = sFloor + (1 - sFloor) * g.smooth(cut, cut + 0.55, fs)
                var band = stripe.pow(0.5) * streak
                if (band < 0.01) continue
                band *= 1 - det + det * 2 * g.noise(cs * 14, sn * 14, y2 * 40 + 5)
                val lam = max(0.0, lx * cell.u + ly * cell.v + lz * cell.z)
                val rimK = 1 - rimA * (1 - g.smooth(0.0, 0.45, cell.z))
                var b = band * (amb + (1 - amb) * lam) * con * rimK
                if (shim > 0) b += (g.hash3(cell.i, cell.j, tick) - 0.5) * shim
                if (b < empty) continue
                var idx = 1 + floor((b - empty) / max(0.01, 1 - empty) * 8).toInt()
                if (idx > 8) idx = 8
                if (band > 0.2 && g.noise(cs * 24, sn * 24, y2 * 55 + 7) > atThr) idx = 9
                val isAccent = ((cell.u + cell.v + 2) / 4) * 0.85 + cell.hash * 0.15 < progress
                nc.drawText(g.ramp[idx], cx + cell.x * u, cy + cell.y * u + baselineShift, paints[if (isAccent) 1 else 0]!!)
            }
        }
    }
}

// MARK: 05 · 连上 Connected

@Composable
private fun Connected(lowBattery: String?, onNext: () -> Unit) {
    val reduceMotion = rememberReduceMotion()
    val pin = DebugEnv["NB_DEBUG_LINK_T"]?.toDoubleOrNull()
    var t by remember { mutableDoubleStateOf(pin ?: if (reduceMotion) LinkChoreo.finished else 0.0) }
    var lastStage by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        LinkHaptics.play(this, still = reduceMotion)
        if (pin != null || reduceMotion) return@LaunchedEffect
        // F5 C11 · Reduce Motion gets the finished picture, not a paused one.
        val start = withFrameNanos { it }
        while (isActive) {
            val now = withFrameNanos { it }
            t = (now - start) / 1e9
        }
    }
    // Hardware with no rich haptics keeps the blunt version: the contact is not silent.
    val stage = LinkChoreo.hapticStage(t)
    LaunchedEffect(stage) {
        if (stage != lastStage) {
            lastStage = stage
            if (!LinkHaptics.isSupported) {
                when (stage) {
                    1 -> Haptics.impact(ImpactStyle.Rigid)
                    2 -> Haptics.notification(NotificationFeedback.Success)
                }
            }
        }
    }

    val w = NB.Layout.screenWidth
    val handsTop = 67f
    val top = Chrome.boardY(handsTop)
    // 520 on the board; compressed with the column on a short phone so the lines keep their room.
    val h = Chrome.boardY(handsTop + 520f) - top
    val pictureHeight = w * 4 / 3
    val touchX = w * LinkChoreo.touchU
    val touchY = pictureHeight * LinkChoreo.touchV - (pictureHeight - h) / 2
    val footer = LinkChoreo.footer(t).toFloat()

    PanelPage {
        // The rays leave the point where the fingertips meet — one burst, one implementation.
        Burst(LinkChoreo.burst(t), Modifier.at(x = touchX - w / 2, y = top + touchY - 280.dp).size(w, 560.dp)
            .alpha((LinkChoreo.burstAlpha(t) * 0.55).toFloat()))
        HandsLink(t, w, h, Modifier.at(y = top))
        Box(Modifier.at(y = Chrome.boardY(584f)).width(w), contentAlignment = Alignment.TopCenter) {
            TypeIn(L("YOU'RE CONNECTED"), LinkChoreo.title(t), NBFont.dot(700, 20f).tracking(0.34f), 20f, NB.lime1)
        }
        Box(Modifier.at(y = Chrome.boardY(618f)).width(w), contentAlignment = Alignment.TopCenter) {
            TypeIn(L("You're now linked to the future you."), LinkChoreo.subtitle(t), NBFont.ui(300, 14f).tracking(0.02f), 14f,
                NB.white.copy(alpha = 0.72f))
        }
        GText(L("LINK LOCKED · DOUBLE TAP"), NBFont.dot(500, 10.5f).tracking(0.24f), NB.white.copy(alpha = 0.40f),
            Modifier.at(y = Chrome.boardY(650f)).width(w).alpha(footer), align = TextAlign.Center)
        // 9-0 00B · the second NEXTBODY is not paired here. One line says where it goes.
        GText(L("KEEP WEARING. CHARGE THE OTHER.") + "\n" + L("Add your second NEXTBODY from the Device page."),
            NBFont.dot(500, 10.5f).tracking(0.16f).lineSpacing(5f), NB.white.copy(alpha = 0.28f),
            Modifier.at(y = Chrome.boardY(if (lowBattery == null) 674f else 694f)).width(w).alpha(footer), align = TextAlign.Center)
        // 02 rule 05 · low battery does not block pairing; it gets one amber line here.
        if (lowBattery != null) {
            GText(lowBattery, NBFont.dot(600, 11f).tracking(0.2f), NB.ember1,
                Modifier.at(y = Chrome.boardY(672f)).width(w).alpha(footer), align = TextAlign.Center)
        }
        // No header, no back key, one button — pairing to profile is a straight line.
        LimePillButton(L("Now let me get to know you"), enabled = true,
            modifier = Modifier.at(x = 16.dp, y = Chrome.boardY(if (lowBattery == null) 728f else 746f) + (14f * (1 - footer)).dp)
                .alpha(footer),
            action = { if (footer > 0.9f) onNext() })
    }
}

/**
 * The burst and the first-launch splash are one implementation (MOTION SPEC · 01).
 * ⚠️ The two horizontal rays must be cut — they read as a strike-through on CONNECTED.
 */
@Composable
private fun Burst(progress: Double, modifier: Modifier) {
    Canvas(modifier) {
        val u = density
        val c = Offset(size.width / 2, size.height / 2)
        drawCircle(Brush.radialGradient(listOf(NB.lime1.copy(alpha = (0.35 * progress).toFloat()), NB.lime1.copy(alpha = 0f)),
            center = c, radius = 150f * u), radius = 150f * u, center = c)
        for (i in 0 until 16) {
            val a = i / 16.0 * 2 * PI
            if (kotlin.math.abs(cos(a)) > 0.985) continue
            val reach = 40f + 190f * progress.toFloat()
            var r = 40f
            while (r < reach) {
                val dim = 1 - (r - 40f) / 190f
                val x = c.x + (r * cos(a)).toFloat() * u - 2.4f * u
                val y = c.y + (r * sin(a)).toFloat() * u - 2.4f * u
                drawRect(NB.lime1.copy(alpha = (0.25f + 0.6f * dim).coerceIn(0f, 1f)), Offset(x, y), Size(4.8f * u, 4.8f * u))
                r += 7f
            }
        }
    }
}
