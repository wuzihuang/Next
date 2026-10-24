package com.nextbody.hoop.features.device

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandError
import com.nextbody.hoop.band.BandEvent
import com.nextbody.hoop.band.FindDistance
import com.nextbody.hoop.band.FindHoopPhase
import com.nextbody.hoop.band.FindLampGlow
import com.nextbody.hoop.band.localizedDescription
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.ui.Hairline
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Paper 12Y · 02 仪器 LED (KLF-0 / LFQ-0 live, KXX-0 timeout).
 * Opens READY with START. The wrist only rings after START.
 * STOP is a 0.12s hold (tap also works) and must paint instantly.
 * Chrome is `DeviceSheetMetrics`: the same header, gutter and key as Alarms.
 */
@Composable
fun FindHoopSheet(close: () -> Unit) {
    var beat by remember { mutableStateOf(FindBeat.ready) }
    var rssi by remember { mutableStateOf<Int?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var starting by remember { mutableStateOf(false) }
    var rssiFrozen by remember { mutableStateOf(false) }
    /** A STOP the 0.12 s hold already delivered; the release that follows is not a second tap. */
    var holdFired by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val pinned = if (BuildConfig.DEBUG && Band.allowsSeed) DebugEnv["NB_DEBUG_FIND"]?.takeIf { it.isNotEmpty() } else null

    val distance = rssi?.let { FindDistance.from(it) }

    fun lampPhrase(lamp: FindDistance): String =
        if (AppLanguage.isEnglish) lamp.label else L(lamp.copyKey)

    fun hoopMessage(error: Throwable): String =
        if (error is BandError.Busy) L("DEVICE BUSY") else error.localizedDescription

    /** Paint READY now. The band command is fire-and-forget — never wait 6s.
     *  RSSI stays live on READY; only Timeout / dismiss freeze the last number. */
    fun stopRing() {
        beat = FindBeat.ready
        message = null
        scope.launch { runCatching { Band.live.stopFindHoop() } }
    }

    fun startRing() {
        scope.launch {
            starting = true
            message = null
            rssiFrozen = false
            try {
                Band.live.startFindHoop()
                if (beat != FindBeat.timeout) beat = FindBeat.ringing
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                message = hoopMessage(e)
            } finally {
                starting = false
            }
        }
    }

    fun apply(phase: FindHoopPhase) {
        if (pinned != null && rssiFrozen) return
        when (phase) {
            FindHoopPhase.enter -> beat = FindBeat.ringing
            FindHoopPhase.exit -> if (beat == FindBeat.ringing) beat = FindBeat.ready
            FindHoopPhase.timeout -> {
                if (beat != FindBeat.ringing) return
                rssiFrozen = true
                beat = FindBeat.timeout
            }
            FindHoopPhase.unsupported -> {
                message = BandError.Unsupported("Find NEXTBODY").localizedDescription
                beat = FindBeat.ready
            }
        }
    }

    // DEBUG · `NB_DEBUG_FIND=near|close|away|far|ringing|timeout` pins a face.
    LaunchedEffect(Unit) {
        when (pinned) {
            null -> Unit
            "timeout" -> { rssiFrozen = true; beat = FindBeat.timeout; rssi = -90 }
            "near" -> { rssiFrozen = true; beat = FindBeat.ringing; rssi = -48 }
            "close" -> { rssiFrozen = true; beat = FindBeat.ringing; rssi = -65 }
            "away" -> { rssiFrozen = true; beat = FindBeat.ringing; rssi = -78 }
            "far" -> { rssiFrozen = true; beat = FindBeat.ringing; rssi = -92 }
            "ringing" -> {
                rssiFrozen = true; beat = FindBeat.ringing
                rssi = DebugEnv["NB_DEBUG_FIND_RSSI"]?.toIntOrNull() ?: -52
            }
            else -> rssiFrozen = true
        }
    }
    // The band's own Enter / Exit / Timeout.
    LaunchedEffect(Unit) {
        Band.live.events.collect { event -> if (event is BandEvent.FindHoop) apply(event.phase) }
    }
    // RSSI once a second until the face freezes.
    LaunchedEffect(Unit) {
        while (isActive) {
            if (!rssiFrozen) {
                val value = try { Band.live.readConnectedRSSI() } catch (e: CancellationException) { throw e } catch (_: Throwable) { null }
                if (value != null && !rssiFrozen) rssi = value
            }
            if (rssiFrozen) return@LaunchedEffect
            delay(1_000)
        }
    }
    DisposableEffect(Unit) {
        onDispose {
            rssiFrozen = true
            @OptIn(kotlinx.coroutines.DelicateCoroutinesApi::class)
            GlobalScope.launch { runCatching { Band.live.stopFindHoop() } }
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(NB.carbon2)
            .padding(horizontal = DeviceSheetMetrics.gutter)
            .padding(top = DeviceSheetMetrics.top, bottom = DeviceSheetMetrics.bottom),
    ) {
        SheetHeader(
            eyebrow = when (beat) {
                FindBeat.ready -> L("READY") + " · " + L("LIVE")
                FindBeat.ringing -> L("ENTER") + " · " + L("RINGING")
                FindBeat.timeout -> L("TIMEOUT")
            },
            eyebrowTint = if (beat == FindBeat.timeout) NB.ember1 else NB.lime1,
            eyebrowID = "find.status",
            title = if (beat == FindBeat.timeout) L("Timed out") else L("Find NEXTBODY"),
            subtitle = when (beat) {
                FindBeat.ready -> L("Tap START and the wrist buzzes until you stop it.")
                FindBeat.ringing -> L("Ringing. Hold STOP once you have it.")
                FindBeat.timeout -> rssi?.let { L("The band stopped on its own. Last heard %@ dBm.", FindDistance.glyph(it)) }
                    ?: L("The band stopped on its own.")
            },
        )

        if (beat == FindBeat.timeout) {
            TimeoutFace(rssi, distance, ::lampPhrase)
        } else {
            LiveFace(rssi, distance, ::lampPhrase)
        }

        val note = message
        if (note != null && beat != FindBeat.timeout) {
            SheetNote(note, Modifier.padding(top = 14.dp))
        }

        Spacer(Modifier.weight(1f))

        HoopKey(
            title = when (beat) {
                FindBeat.ready -> L("START")
                FindBeat.ringing -> L("STOP")
                FindBeat.timeout -> L("DONE")
            },
            skin = if (beat == FindBeat.timeout) HoopKeySkin.ember else HoopKeySkin.lime,
            enabled = !(starting && beat == FindBeat.ready),
            modifier = Modifier
                .padding(top = 8.dp)
                .testTag(when (beat) { FindBeat.ready -> "find.start"; FindBeat.ringing -> "find.stop"; FindBeat.timeout -> "find.done" })
                // STOP is a 0.12 s hold as well as a tap: it paints the moment the hold lands.
                .pointerInput(beat) {
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false)
                        holdFired = false
                        val up = withTimeoutOrNull(120) { waitForUpOrCancellation() }
                        if (up == null && beat == FindBeat.ringing) {
                            holdFired = true
                            stopRing()
                        }
                    }
                },
        ) {
            if (holdFired) { holdFired = false; return@HoopKey }
            when (beat) {
                FindBeat.ready -> startRing()
                FindBeat.ringing -> stopRing()
                FindBeat.timeout -> close()
            }
        }
    }
}

private enum class FindBeat { ready, ringing, timeout }

/** Hero number, then the four lamps. The number is the only large thing on the face. */
@Composable
private fun LiveFace(rssi: Int?, distance: FindDistance?, phrase: (FindDistance) -> String) {
    Column {
        Row(
            Modifier.padding(top = 28.dp, bottom = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            FitText(
                rssi?.let { FindDistance.glyph(it) } ?: Fmt.dash,
                NBFont.dot(700, 64f).tracking(-0.05f),
                NB.lime1,
                Modifier.testTag("find.rssi"),
                minScale = 0.45f,
            )
            Text(
                L("dBm"),
                style = NBFont.dot(500, 14f).tracking(0.12f),
                color = NB.white.copy(alpha = 0.42f),
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (lamp in FindDistance.entries) {
                LampCell(lamp, distance, phrase(lamp), Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun LampCell(lamp: FindDistance, current: FindDistance?, phrase: String, modifier: Modifier) {
    val glow = FindDistance.glow(lamp, current)
    val fill = when (glow) {
        FindLampGlow.hot -> NB.lime1
        FindLampGlow.warm -> NB.lime1.copy(alpha = 0.40f)
        FindLampGlow.off -> NB.hairline
    }
    val ink = when (glow) {
        FindLampGlow.hot -> NB.carbon4
        FindLampGlow.warm -> NB.white.copy(alpha = 0.60f)
        FindLampGlow.off -> NB.white.copy(alpha = 0.33f)
    }
    Box(
        modifier
            .height(64.dp)
            .background(fill, RoundedCornerShape(12.dp))
            .padding(10.dp)
            .testTag("find.lamp.${lamp.label}")
            .semantics { selected = glow == FindLampGlow.hot },
        contentAlignment = Alignment.BottomStart,
    ) {
        Text(phrase, style = NBFont.dot(700, 10f).tracking(0.12f), color = ink, maxLines = 1)
    }
}

/** Paper KXX-0. Last RSSI freezes. DONE is ember, not lime. */
@Composable
private fun TimeoutFace(rssi: Int?, distance: FindDistance?, phrase: (FindDistance) -> String) {
    Column {
        Box {
            Row(
                Modifier.fillMaxWidth().padding(top = 8.dp).padding(vertical = DeviceSheetMetrics.rowInset),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(L("RSSI"), style = NBFont.ui(500, 14f).tracking(0.02f), color = NB.text1,
                    modifier = Modifier.alignByBaseline())
                Spacer(Modifier.weight(1f))
                Text(
                    rssi?.let { FindDistance.glyph(it) } ?: Fmt.dash,
                    style = NBFont.dot(700, 28f).tracking(-0.02f),
                    color = NB.text1,
                    modifier = Modifier.alignByBaseline().testTag("find.rssi"),
                )
                Text(
                    L("dBm"),
                    style = NBFont.dot(500, 12f).tracking(0.12f),
                    color = NB.white.copy(alpha = 0.42f),
                    textAlign = TextAlign.End,
                    modifier = Modifier.alignByBaseline().width(36.dp),
                )
            }
            Hairline(modifier = Modifier.align(Alignment.BottomStart))
        }
        Box {
            Row(
                Modifier.fillMaxWidth().padding(vertical = DeviceSheetMetrics.rowInset),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L("Range"), style = NBFont.ui(500, 14f), color = NB.text1)
                Spacer(Modifier.weight(1f))
                RangePips(distance?.barsLit ?: 0)
                Text(
                    distance?.let(phrase) ?: Fmt.dash,
                    style = NBFont.dot(600, 11f).tracking(0.14f),
                    color = NB.lime1,
                    textAlign = TextAlign.End,
                    maxLines = 1,
                    modifier = Modifier.width(56.dp),
                )
            }
            Hairline(modifier = Modifier.align(Alignment.BottomStart))
        }
        Text(
            L("LAST") + " · " + L("NOT LIVE"),
            style = NBFont.dot(500, 11f).tracking(0.16f),
            color = NB.white.copy(alpha = 0.34f),
            modifier = Modifier.padding(top = 14.dp),
        )
    }
}

@Composable
private fun RangePips(lit: Int) {
    val heights = listOf(6, 9, 12, 16)
    Row(
        Modifier.size(72.dp, 16.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.Bottom,
    ) {
        for (i in 0 until 4) {
            Box(
                Modifier.size(12.dp, heights[i].dp)
                    .background(if (i < lit) NB.lime1 else NB.white.copy(alpha = 0.14f)),
            )
        }
    }
}

