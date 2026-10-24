package com.nextbody.hoop.features.device

import com.nextbody.hoop.features.connect.BandPortrait
import com.nextbody.hoop.features.connect.DottedProgress
import com.nextbody.hoop.features.connect.LimePillButton
import com.nextbody.hoop.features.connect.SignalBars

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.AppSession
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandEvent
import com.nextbody.hoop.band.BluetoothState
import com.nextbody.hoop.band.DeviceReleaseError
import com.nextbody.hoop.band.DeviceSetStore
import com.nextbody.hoop.band.DeviceSlots
import com.nextbody.hoop.band.DiscoveredBand
import com.nextbody.hoop.band.HoopSlot
import com.nextbody.hoop.band.localizedDescription
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.SessionStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.NotificationFeedback
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.rememberFrameClock
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

// 9-0 A · the three sheets the two-NEXTBODY set adds to DEVICE
// (docs/plans/2026-09-12-dual-device-continuity.md §04.5, §12).
//
// Activate the second (A·S1–S6: one sheet, four faces), `I'm wearing B` (A·S8) and Release
// both (A·S7). The activation faces are cut from Connect's own screens 02–05: the same
// scan rings, the same dotted progress that moves when the band answers, not on a timer.

// MARK: A·S1–S6 · activate the second NEXTBODY

private sealed class Face {
    data object Preparing : Face()
    data object Searching : Face()
    data object NothingFound : Face()
    data object Found : Face()
    data object Pairing : Face()
    data object Paired : Face()
    data class Stopped(val why: String) : Face()
}

private val stageNames = listOf("Connect", "Verify it's yours", "Read capabilities", "Activate")

@OptIn(DelicateCoroutinesApi::class)
@Composable
fun ActivateSecondSheet(close: () -> Unit) {
    val hoops = DeviceSetStore.shared
    val data = DataStore
    val reduceMotion = rememberReduceMotion()
    var face by remember { mutableStateOf<Face>(Face.Searching) }
    var nearby by remember { mutableStateOf<List<DiscoveredBand>>(emptyList()) }
    var picked by remember { mutableStateOf<String?>(null) }
    var progress by remember { mutableStateOf(0.0) }
    var stage by remember { mutableStateOf(0) }
    var scanTask by remember { mutableStateOf<Job?>(null) }
    var activated by remember { mutableStateOf<DeviceSetStore.SlotSnapshot?>(null) }
    var activatedAt by remember { mutableStateOf<Instant?>(null) }
    val activationOwner = remember { UUID.randomUUID() }
    var targetSlot by remember { mutableStateOf<HoopSlot?>(null) }
    val scope = rememberCoroutineScope()

    val slot = targetSlot ?: hoops.openSlot ?: HoopSlot.b
    val worn = slot.other
    val bound = DeviceSlots.bindings.map { it.identifier }.toSet()
    val candidates = nearby.filter { it.id !in bound }.sortedByDescending { it.rssi }
    val pick = candidates.firstOrNull { it.id == picked } ?: candidates.firstOrNull()

    InteractiveDismissDisabled(face == Face.Pairing)

    /** `A · STILL RECORDING · 82%` — the worn band keeps recording on the wrist whatever the
     *  link does; its last known charge, never a guess. */
    val wornLine = "${worn.raw} · " + L("STILL RECORDING") + (data.band.batteryPercent?.let { " · $it%" } ?: "")

    /** 02 rule 01 · scan 15 s. Every band in range is listed; the ones already in the set are
     *  shown greyed. The strongest new one is picked, 1.5 s after the first answers. */
    fun startScan() {
        nearby = emptyList(); picked = null; progress = 0.0; stage = 0
        face = Face.Preparing
        scanTask?.cancel()
        scanTask = scope.launch {
            try {
                hoops.prepareActivation(activationOwner)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                face = Face.Stopped(L("The NEXTBODY is switching or finishing a command. Try again shortly."))
                return@launch
            }
            BluetoothState.shared.waitForState()
            if (BluetoothState.shared.poweredOff) { face = Face.Stopped(L("Bluetooth is off.")); return@launch }
            if (BluetoothState.shared.permissionDenied) { face = Face.Stopped(L("Bluetooth permission is off for NextBody.")); return@launch }
            face = Face.Searching
            val timeout = launch {
                delay(15_000)
                val fresh = nearby.filter { it.id !in DeviceSlots.bindings.map { b -> b.identifier }.toSet() }
                if (fresh.isEmpty() && face == Face.Searching) {
                    Band.live.stopScan()
                    face = Face.NothingFound
                }
            }
            var settle: Job? = null
            // Listen before the radio starts: the mock answers from inside startScan.
            val listening = launch(start = CoroutineStart.UNDISPATCHED) {
                Band.live.events.collect { event ->
                    if (event !is BandEvent.Discovered) return@collect
                    val device = event.band
                    val i = nearby.indexOfFirst { it.id == device.id }
                    nearby = if (i >= 0) nearby.toMutableList().also { it[i] = device } else nearby + device
                    val boundNow = DeviceSlots.bindings.map { it.identifier }.toSet()
                    if (settle == null && device.id !in boundNow) {
                        timeout.cancel()
                        settle = launch {
                            delay(1_500)
                            if (face != Face.Searching) return@launch
                            Band.live.stopScan()
                            face = Face.Found
                        }
                    }
                }
            }
            val scanning = launch { Band.live.startScan() }
            try {
                listening.join()
            } finally {
                scanning.cancel()
                timeout.cancel()
                settle?.cancel()
            }
        }
    }

    /** 02 rule 02 · four fixed segments: connect 0–35, verify 35–60, capabilities 60–85,
     *  activate 85–100. Whichever does not return, the bar stops there. */
    fun activate(device: DiscoveredBand) {
        scanTask?.cancel()
        progress = 0.0; stage = 0
        face = Face.Pairing
        scope.launch {
            Band.live.stopScan()
            try {
                activated = hoops.activateSecond(device, data, activationOwner,
                    stage = { s -> stage = s.raw },
                    progress = { p -> progress = maxOf(progress, p) })
                progress = 1.0; stage = 3
                activatedAt = Instant.now()
                Haptics.notification(NotificationFeedback.Success)
                face = Face.Paired
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                face = Face.Stopped(e.localizedDescription)
            }
        }
    }

    LaunchedEffect(Unit) { targetSlot = hoops.openSlot; startScan() }
    DisposableEffect(Unit) {
        onDispose {
            val pending = scanTask
            pending?.cancel()
            GlobalScope.launch(Dispatchers.Main) {
                pending?.join()
                if (hoops.activationGate.owner != activationOwner) return@launch
                Band.live.stopScan()
                hoops.endActivation(activationOwner)
            }
        }
    }

    Box(Modifier.fillMaxSize().background(NB.carbon2)) {
        AnimatedContent(
            targetState = face,
            contentKey = { it::class },
            transitionSpec = { fadeIn(tween(250)) togetherWith fadeOut(tween(250)) },
            label = "activate.face",
        ) { f ->
            Column(Modifier.fillMaxSize()) {
                when (f) {
                    Face.Preparing -> {
                        SheetHead(L("PREPARING"), L("Preparing to pair"),
                            L("Finishing the current NEXTBODY command before searching. Your other NEXTBODY stays paired."))
                        SmallSpinner(NB.lime1, Modifier.padding(24.dp), size = 20.dp)
                        Spacer(Modifier.height(8.dp))
                        Spacer(Modifier.weight(1f))
                        OutlineKey(L("CANCEL"), NB.lime1, Modifier.padding(horizontal = 16.dp).padding(bottom = 28.dp)) { close() }
                    }
                    Face.Searching, Face.NothingFound -> {
                        val nothing = f == Face.NothingFound
                        SheetHead(
                            L("SEARCHING · SLOT") + " ${slot.raw}",
                            L("Fill slot") + " ${slot.raw}",
                            if (nothing) L("Nothing answered. Is it lit up, within an arm's reach, and not still linked to another phone?")
                            else L("Take the second NEXTBODY off its charger and hold it near the phone. The one on your wrist steps off the link for a moment and comes back on its own."),
                        )
                        val t = rememberFrameClock(running = !(reduceMotion || nothing))
                        val time = if (nothing) 0.0 else t
                        BandPortrait(
                            scanRings = (0 until 4).map { i ->
                                val p = (time * 0.35 + i * 0.25) % 1.0
                                60f + p.toFloat() * 130f
                            },
                            modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 2.dp)
                                .size(190.dp, 229.dp).alpha(if (nothing) 0.18f else 1f),
                        )
                        Text(
                            if (nothing) L("NOTHING FOUND") else L("SCANNING"),
                            style = NBFont.dot(600, 12f).tracking(0.34f),
                            color = NB.white.copy(alpha = 0.42f),
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
                        )
                        FooterLine(wornLine, Modifier.padding(top = 18.dp))
                        Spacer(Modifier.weight(1f))
                        if (nothing) {
                            LimePillButton(L("Search again"), modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp)) { startScan() }
                        }
                        OutlineKey(L("CANCEL"), NB.lime1, Modifier.padding(horizontal = 16.dp).padding(bottom = 28.dp)) { close() }
                    }
                    Face.Found -> {
                        SheetHead(
                            L("FOUND") + " · ${nearby.size} " + L("NEARBY"),
                            if (candidates.size == 1) L("Found one") else L("Found") + " ${candidates.size}",
                            L("The one that isn't already yours is picked. The NEXTBODY you wear shows up too, but it stays where it is."),
                        )
                        Column(Modifier.padding(horizontal = 24.dp)) {
                            for (band in candidates) {
                                NearbyCard(band, if (band.id == pick?.id) NearbyState.Picked else NearbyState.Other) { picked = band.id }
                            }
                            for (band in nearby.filter { it.id in bound }) {
                                val inSlot = DeviceSlots.bindings.firstOrNull { it.identifier == band.id }?.slot ?: worn
                                NearbyCard(band, NearbyState.InSet(inSlot)) {}
                            }
                        }
                        FooterLine(wornLine, Modifier.padding(top = 18.dp))
                        Spacer(Modifier.weight(1f))
                        LimePillButton(
                            L("PAIR AS") + " ${slot.raw}",
                            modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 28.dp).alpha(if (pick == null) 0.5f else 1f),
                            enabled = pick != null,
                        ) { pick?.let { activate(it) } }
                    }
                    Face.Pairing -> {
                        SheetHead(L("PAIRING"), L("Joining as") + " ${slot.raw}",
                            L("Keep it within arm's reach. Four real steps — the number moves when the band answers, not on a timer.")) {
                            Percent(progress, ember = false)
                        }
                        DottedProgress(progress, Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp)
                            .size(NB.Layout.contentWidth - 16.dp, 6.dp))
                        StageRows(slot, current = stage, failed = false, pairing = true, paired = false)
                        FooterLine(wornLine)
                        Spacer(Modifier.weight(1f))
                        Text(
                            L("Keep it within arm's reach."),
                            style = NBFont.ui(300, 13f).tracking(0.02f),
                            color = NB.white.copy(alpha = 0.55f),
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().padding(bottom = 28.dp),
                        )
                    }
                    Face.Paired -> {
                        SheetHead(L("PAIRED · SLOT") + " ${slot.raw}", "NEXTBODY ${slot.raw} " + L("is in"),
                            L("When you swap, tell the app you're wearing it. Until then it just waits on the charger — nothing from it is counted."))
                        val pct = activated?.battery?.percent
                        FigureRow(L("Battery"), pct?.toString() ?: Fmt.dash, if (pct == null) "" else "%")
                        FigureRow(L("Firmware"), activated?.firmware ?: Fmt.dash, "")
                        val holds = activated?.holdsDays
                        FigureRow(L("Holds"), holds?.toString() ?: Fmt.dash, if (holds == null) "" else L("DAYS"))
                        FooterLine(L("SLOT") + " ${slot.raw} · " + L("ACTIVE") + " " + (activatedAt?.let(::clock) ?: "") +
                            " · " + L("STILL ON") + " ${worn.raw}")
                        Spacer(Modifier.weight(1f))
                        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            LimePillButton(L("DONE · STILL WEARING") + " ${worn.raw}") { close() }
                            Text(
                                L("I'm wearing") + " ${slot.raw} " + L("now"),
                                style = NBFont.ui(400, 13f).tracking(0.02f),
                                color = NB.lime1,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth().testTag("activate.wearingNow")
                                    .hotZoneTap(pressedScale = 1f) {
                                        val now = slot
                                        close()
                                        hoops.declareWearing(now, store = data)
                                    },
                            )
                        }
                    }
                    is Face.Stopped -> {
                        SheetHead(L("STOPPED · SLOT") + " ${slot.raw}", L("Couldn't reach it"),
                            f.why + " " + L("Your other NEXTBODY remains paired."), ember = true) {
                            Percent(progress, ember = true)
                        }
                        DottedProgress(progress, Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp)
                            .size(NB.Layout.contentWidth - 16.dp, 6.dp),
                            lit = NB.ember1, track = NB.ember1.copy(alpha = 0.10f))
                        StageRows(slot, current = stage, failed = true, pairing = false, paired = false)
                        FooterLine(wornLine)
                        Spacer(Modifier.weight(1f))
                        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            LimePillButton(L("Try again")) { startScan() }
                            Text(
                                L("Not now"),
                                style = NBFont.ui(400, 13f).tracking(0.02f),
                                color = NB.white.copy(alpha = 0.55f),
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth().hotZoneTap(pressedScale = 1f) { close() },
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun clock(at: Instant): String =
    DateTimeFormatter.ofPattern("HH:mm").format(at.atZone(ZoneId.systemDefault()))

@Composable
private fun Percent(progress: Double, ember: Boolean) {
    Text(
        "${(progress * 100).toInt()}%",
        style = NBFont.dot(700, 22f).tracking(0.02f),
        color = if (ember) NB.ember1 else NB.lime1,
    )
}

@Composable
private fun StageRows(slot: HoopSlot, current: Int, failed: Boolean, pairing: Boolean, paired: Boolean) {
    Column {
        for (i in 0 until 4) {
            val name = if (i == 3) L("Activate") + " ${slot.raw}" else L(stageNames[i])
            val done = i < current || paired
            val now = i == current && !failed && pairing
            Row(
                Modifier.fillMaxWidth().topRule().padding(horizontal = 24.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    name,
                    style = NBFont.ui(500, 14f).tracking(0.02f),
                    color = if (done) NB.white.copy(alpha = 0.55f) else if (now) NB.white else NB.white.copy(alpha = 0.24f),
                    modifier = Modifier.weight(1f).alignByBaseline(),
                )
                Spacer(Modifier.width(16.dp)) // 8 + 0 + 8, as SwiftUI spaces around the Spacer
                Text(
                    if (done) L("DONE") else if (now) L("NOW") else if (failed && i == current) L("STOPPED") else "—",
                    style = NBFont.dot(if (done || now) 600 else 500, 11f).tracking(0.12f),
                    color = if (done || now) NB.lime1 else if (failed && i == current) NB.ember1 else NB.white.copy(alpha = 0.24f),
                    modifier = Modifier.alignByBaseline(),
                )
            }
        }
    }
}

@Composable
private fun FooterLine(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = NBFont.dot(500, 11f).tracking(0.16f),
        color = NB.white.copy(alpha = 0.34f),
        modifier = modifier.fillMaxWidth().topRule().padding(horizontal = 24.dp).padding(top = 12.dp),
    )
}

/** Eyebrow · title · body, the sheet head every face shares (24pt gutters, 8pt gaps). */
@Composable
private fun SheetHead(
    eyebrow: String,
    title: String,
    body: String,
    ember: Boolean = false,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 22.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(eyebrow, style = NBFont.dot(600, 11f).tracking(0.28f), color = if (ember) NB.ember1 else NB.lime1,
                modifier = Modifier.weight(1f))
            if (trailing != null) {
                Spacer(Modifier.width(16.dp))
                trailing()
            }
        }
        FitText(title, NBFont.ui(700, 32f).tracking(-0.03f), NB.text1, minScale = 0.8f)
        Text(body, style = NBFont.ui(300, 14f).copy(lineHeight = androidx.compose.ui.unit.TextUnit(22f, androidx.compose.ui.unit.TextUnitType.Sp)),
            color = NB.white.copy(alpha = 0.5f))
    }
}

private sealed class NearbyState {
    data object Picked : NearbyState()
    data object Other : NearbyState()
    data class InSet(val slot: HoopSlot) : NearbyState()
}

/** 03's found card: lime-edged when it is the pick, greyed when it is already in the set. */
@Composable
private fun NearbyCard(band: DiscoveredBand, state: NearbyState, action: () -> Unit) {
    val inSet = state is NearbyState.InSet
    val isPicked = state == NearbyState.Picked
    Row(
        Modifier
            .fillMaxWidth()
            .height(72.dp)
            .alpha(if (inSet) 0.42f else 1f)
            .topRule(if (isPicked) NB.lime1.copy(alpha = 0.55f) else NB.hairline)
            .hotZoneTap(enabled = !inSet, pressedScale = 1f) { action() }
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(34.dp)) {
                val c = Offset(size.width / 2, size.height / 2)
                if (isPicked) drawCircle(NB.lime1.copy(alpha = 0.12f), size.width / 2, c)
                drawCircle(if (isPicked) NB.lime1.copy(alpha = 0.35f) else NB.white.copy(alpha = 0.25f),
                    size.width / 2 - 0.5.dp.toPx(), c, style = Stroke(1.dp.toPx()))
                val ink = if (isPicked) NB.lime1 else NB.white.copy(alpha = 0.55f)
                drawCircle(ink, 5.5.dp.toPx(), c, style = Stroke(2.dp.toPx()))
                drawRect(ink, Offset(c.x - 1.dp.toPx(), c.y - 6.dp.toPx() - 3.5.dp.toPx()), Size(2.dp.toPx(), 7.dp.toPx()))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(band.name.uppercase(), style = NBFont.ui(500, 15f).tracking(0.02f), color = NB.text1, maxLines = 1)
            Text(
                when (state) {
                    NearbyState.Picked -> L("READY TO PAIR")
                    NearbyState.Other -> L("NEARBY")
                    is NearbyState.InSet -> L("ALREADY IN SLOT") + " ${state.slot.raw}"
                },
                style = NBFont.dot(600, 10f).tracking(0.2f),
                color = if (isPicked) NB.lime1 else NB.white.copy(alpha = 0.55f),
            )
        }
        Spacer(Modifier.width(0.dp))
        Text(band.batteryPercent?.let { "$it%" } ?: Fmt.dash, style = NBFont.dot(600, 10f).tracking(0.1f),
            color = NB.white.copy(alpha = 0.55f))
        SignalBars(bars(band.rssi), if (isPicked) Modifier else Modifier.grayscale())
    }
}

/** RSSI in dBm, not a percentage. −50 is on the desk, −90 is in the next room. */
private fun bars(rssi: Int): Int = when {
    rssi >= -55 -> 4
    rssi >= -67 -> 3
    rssi >= -80 -> 2
    else -> 1
}

/** 12Y's figure row: name left, 28pt dot numeral, a 36pt unit column. */
@Composable
private fun FigureRow(name: String, value: String, unit: String) {
    Row(Modifier.fillMaxWidth().topRule().padding(horizontal = 24.dp, vertical = 18.dp)) {
        Text(name, style = NBFont.ui(500, 14f).tracking(0.02f), color = NB.text1, modifier = Modifier.alignByBaseline())
        Spacer(Modifier.weight(1f))
        Text(value, style = NBFont.dot(700, 28f).tracking(-0.02f), color = NB.text1, modifier = Modifier.alignByBaseline())
        Text(unit, style = NBFont.dot(500, 12f).tracking(0.12f), color = NB.white.copy(alpha = 0.42f),
            textAlign = TextAlign.End, modifier = Modifier.alignByBaseline().width(36.dp))
    }
}

// MARK: A·S8 · the switch, and the one line that can correct its start

/**
 * There are only two HOOPs, so tapping the other one's card is the choice; this sheet only
 * confirms it. No picker, no time: the band itself says when it went on the wrist and the
 * server moves the start once the phone has read it (§04.5 W2).
 */
@Composable
fun WearSwitchSheet(to: HoopSlot, close: () -> Unit) {
    val hoops = DeviceSetStore.shared
    /** Two taps land before the sheet is gone; the second must not file a second switch. */
    var sent by remember { mutableStateOf(false) }
    SheetColumn {
        SheetTitle(L("Switch to NEXTBODY") + " ${to.raw}?")
        SheetBody(L("From now on your record comes from this one. The app works out when you put it on from the NEXTBODY itself, so there is nothing to set."))
        if (hoops.snapshot(to)?.isFlat == true) {
            Text(
                L("It was out of charge when the app last read it. Say you are wearing it anyway — your record follows your wrist, not the link — but charge it or it records nothing."),
                style = NBFont.ui(400, 13f).tracking(0.01f).lineGap(6f),
                color = NB.ember1,
            )
        }
        val snap = hoops.snapshot(to)
        if (snap != null) {
            Row(
                Modifier.fillMaxWidth().height(66.dp).sheetLines().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                HoopKeyGlyph(to.raw, lit = true)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(snap.name, style = NBFont.ui(500, 14f).tracking(0.02f), color = NB.text1)
                    Text(
                        hoops.snapshot(to.other)?.let { L("NEXTBODY") + " ${to.other.raw} " + L("goes on the charger") } ?: "",
                        style = NBFont.dot(500, 10f).tracking(0.16f),
                        color = NB.white.copy(alpha = 0.34f),
                    )
                }
                Spacer(Modifier.width(0.dp))
            }
        }
        Spacer(Modifier.weight(1f))
        LimePillButton(L("I'm wearing NEXTBODY") + " ${to.raw}", modifier = Modifier.testTag("wearSwitch.confirm")) {
            if (sent) return@LimePillButton
            sent = true
            val slot = to
            close()
            hoops.declareWearing(slot, store = DataStore)
        }
        OutlineKey(L("NOT NOW"), NB.text2) { close() }
    }
}

// MARK: Remove one binding, keeping the other slot and account history.

@Composable
fun ReleaseSetSheet(close: () -> Unit, initialSlot: HoopSlot? = null) {
    val hoops = DeviceSetStore.shared
    var selected by remember { mutableStateOf(initialSlot) }
    var removing by remember { mutableStateOf(false) }
    var failureMessage by remember { mutableStateOf<String?>(null) }
    var removed by remember { mutableStateOf<HoopSlot?>(null) }
    val scope = rememberCoroutineScope()

    InteractiveDismissDisabled(removing || removed != null)

    SheetColumn {
        val gone = removed
        if (gone != null) {
            SheetTitle(L("%@ removed", gone.displayName))
            SheetBody(L("Pairing removed successfully. All synced history is still in your account."))
            Spacer(Modifier.weight(1f))
            LimePillButton(L("Done")) {
                if (hoops.slots.isEmpty()) AppSession.session.stage = SessionStore.Stage.gateConnect
                close()
            }
        } else {
            SheetTitle(selected?.let { L("Remove %@?", it.displayName) } ?: L("Remove a NEXTBODY"))
            if (hoops.hasSecond) {
                for (slot in HoopSlot.entries) {
                    OutlineKey(
                        slot.displayName + if (selected == slot) " ✓" else "",
                        if (selected == slot) NB.lime1 else NB.text2,
                        enabled = !removing,
                    ) {
                        selected = slot
                        failureMessage = null
                    }
                }
                SheetBody(L("Only the selected NEXTBODY is removed. Your other NEXTBODY stays paired and becomes the active NEXTBODY. All synced history stays."))
            } else {
                SheetBody(L("This NEXTBODY will be unpaired. All synced history stays. You can pair a NEXTBODY again anytime."))
            }
            failureMessage?.let { Text(L(it), style = NBFont.brand(400, 14f), color = NB.alert2) }
            if (removing) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    SmallSpinner(NB.lime1, size = 20.dp)
                    Text(L("Confirming removal…"), style = NBFont.brand(400, 14f), color = NB.text2)
                }
            }
            Spacer(Modifier.weight(1f))
            LimePillButton(L("Keep it paired"), enabled = !removing) { close() }
            OutlineKey(
                if (removing) L("REMOVING…") else selected?.let { L("REMOVE %@", it.displayName) } ?: L("SELECT A NEXTBODY"),
                NB.alert2,
                enabled = selected != null && !removing,
            ) {
                val target = selected ?: return@OutlineKey
                if (removing) return@OutlineKey
                removing = true
                failureMessage = null
                scope.launch {
                    try {
                        hoops.release(target, DataStore)
                        removed = target
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Throwable) {
                        failureMessage = DeviceReleaseError.message(e)
                    } finally {
                        removing = false
                    }
                }
            }
        }
    }
}

// MARK: shared pieces

@Composable
private fun SheetColumn(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .background(NB.carbon2)
            .padding(horizontal = 16.dp)
            .padding(top = 26.dp, bottom = 26.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        content = content,
    )
}

@Composable
private fun SheetTitle(text: String) {
    Text(text, style = NBFont.ui(500, 22f).tracking(0.01f), color = NB.text1)
}

@Composable
private fun SheetBody(text: String) {
    Text(text, style = NBFont.brand(400, 14f).lineGap(7f), color = NB.text2)
}

@Composable
private fun OutlineKey(
    title: String,
    tint: Color,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    action: () -> Unit,
) {
    Box(
        modifier
            .fillMaxWidth()
            .height(52.dp)
            .border(1.dp, if (tint == NB.text2) NB.hairline else tint.copy(alpha = 0.55f), CircleShape)
            .alpha(if (enabled) 1f else 0.6f)
            // ⚠️ The whole capsule is the key, not just the glyphs.
            .hotZoneTap(enabled = enabled, pressedScale = 1f) { action() },
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = NBFont.dot(700, 13f).tracking(0.2f), color = tint, maxLines = 1)
    }
}

/** The slot letter in a 28pt ring — lit when it is the one being named; carbon on lime. */
@Composable
fun HoopKeyGlyph(letter: String, modifier: Modifier = Modifier, lit: Boolean = false, onLime: Boolean = false) {
    Box(
        modifier
            .size(28.dp)
            .background(if (onLime) NB.carbon4 else if (lit) NB.lime1 else NB.white.copy(alpha = 0.08f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(letter, style = NBFont.dot(700, 12f).tracking(0.04f),
            color = if (onLime) NB.lime1 else if (lit) NB.carbon4 else NB.text1)
    }
}
