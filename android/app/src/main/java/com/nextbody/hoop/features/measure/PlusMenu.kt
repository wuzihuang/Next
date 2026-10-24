package com.nextbody.hoop.features.measure

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.app.EntryPoint
import com.nextbody.hoop.app.MeasureKind
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.Takeover
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandConnectionState
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.Hairline

/**
 * 06 · 加号与那张单子. Groups by who does the work: SPORT MODE (the band runs a session),
 * MEASURE (the band takes a reading). The ADD group (camera / library) is AI-only and is not
 * drawn while `AIFeature.enabled == false`, exactly as iOS hides it.
 *
 * @param inline on the home screen the menu is a panel standing over the dock, not a system
 *   sheet: `inline` drops the sheet ground.
 * @param close how the menu is put away (the sheet's dismiss, or the home panel's close).
 */
@Composable
fun PlusMenuSheet(close: () -> Unit, modifier: Modifier = Modifier, inline: Boolean = false) {
    val data = DataStore
    // F6 §05 · a measurement this NEXTBODY cannot do is not offered at all.
    val canHeartRate = !data.capabilities.knownUnsupported(MeasureKind.heartRate)
    val canBodyScan = !data.capabilities.knownUnsupported(MeasureKind.bodyComposition)

    // 06 edge 6 · the rows are gated on the link, so the link has to be current.
    LaunchedEffect(Unit) {
        if (DebugEdgeFlag.on("noband")) {
            data.setBandConnected(false)
            return@LaunchedEffect
        }
        if (Band.live.state != BandConnectionState.connected) Band.live.reconnectIfBound()
        data.setBandConnected(Band.live.state == BandConnectionState.connected)
    }

    Column(
        (if (inline) modifier.fillMaxWidth() else modifier.fillMaxSize().background(NB.carbon2))
            .padding(horizontal = 8.dp, vertical = 14.dp),
    ) {
        GroupHeader(L("SPORT MODE"))
        val offline: String? = if (data.band.connected) null else L("The band isn't connected.")
        MenuRow(PlusIcon.sport, L("Start a session"), L("Pick a mode · the band runs it."), unavailable = offline) {
            close()
            Router.open(Destination.SportMode, EntryPoint.home)
        }

        // The header goes with the rows: a heading over nothing reads as a failed load.
        if (canHeartRate || canBodyScan) {
            Hairline(modifier = Modifier.padding(vertical = 8.dp))
            GroupHeader(L("MEASURE ON THE BAND"))
            // Pressing a row is the confirmation: "40 S" is already printed on it.
            if (canHeartRate) {
                // 06 · the balance check replaced the battery check. ⚠️ Nothing the user reads
                // names the SDK command underneath.
                MenuRow(PlusIcon.pulse, L("Balance check"), L("40 s of your pulse rhythm — rest against drive."),
                    duration = L("40 S"), unavailable = offline) {
                    close()
                    Router.setTakeover(Takeover.Measure(MeasureKind.ecg))
                }
            }
            if (canBodyScan) {
                MenuRow(PlusIcon.body, L("Body scan"), L("Fourteen fields — fat, muscle, water."),
                    duration = L("30 S"), unavailable = offline) {
                    close()
                    Router.setTakeover(Takeover.Measure(MeasureKind.bodyComposition))
                }
            }
        }
    }
}

@Composable
private fun GroupHeader(text: String) {
    MText(text, NBFont.dot(600, 10f).tracking(0.2f), NB.white.copy(alpha = 0.30f),
        Modifier.padding(start = 16.dp, end = 16.dp, bottom = 10.dp))
}

private enum class PlusIcon { sport, pulse, body }

/**
 * One row: icon, title, detail, the duration on the right. Held, the row lights lime under the
 * finger. A capability the band does not have right now keeps its row and states the reason in
 * amber — hiding it would make the user think the feature does not exist.
 */
@Composable
private fun MenuRow(
    icon: PlusIcon, title: String, detail: String, duration: String? = null,
    unavailable: String? = null, action: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val ground by animateColorAsState(if (pressed && unavailable == null) NB.lime1 else Color.Transparent,
        tween(120), label = "row")
    Row(
        Modifier
            .fillMaxWidth()
            .height(62.dp)
            .background(ground, RoundedCornerShape(NB.R.tile))
            .clickable(interaction, indication = null, enabled = unavailable == null, onClick = action)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        MenuIcon(icon, if (unavailable == null) NB.iconInk else NB.white.copy(alpha = 0.32f))
        Column(Modifier.weight(1f).padding(end = 14.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            MText(title, NBFont.ui(500, 15f).tracking(0.01f), if (unavailable == null) NB.text1 else NB.white.copy(alpha = 0.42f))
            if (unavailable == null) {
                MText(detail, NBFont.ui(400, 12f).tracking(0.02f), NB.white.copy(alpha = 0.42f))
            } else {
                MText(unavailable, NBFont.dot(600, 10f).tracking(0.16f), NB.ember1)
            }
        }
        if (duration != null) {
            MText(duration, NBFont.dot(500, 10f).tracking(0.16f), NB.white.copy(alpha = 0.30f))
        }
    }
}

@Composable
private fun MenuIcon(kind: PlusIcon, tint: Color) {
    Canvas(Modifier.size(22.dp)) {
        val s = size.width / 24
        val stroke = Stroke(width = 1.6f * s, cap = StrokeCap.Round, join = StrokeJoin.Round)
        when (kind) {
            PlusIcon.sport -> {
                drawOval(tint, Offset(4 * s, 4 * s), Size(16 * s, 16 * s), style = stroke)
                val tick = Path().apply {
                    moveTo(12 * s, 12 * s); lineTo(12 * s, 7 * s)
                    moveTo(12 * s, 12 * s); lineTo(16 * s, 14 * s)
                }
                drawPath(tick, tint, style = stroke)
            }
            PlusIcon.pulse -> {
                val p = Path().apply {
                    moveTo(2.5f * s, 12 * s); lineTo(7 * s, 12 * s); lineTo(9 * s, 6.5f * s)
                    lineTo(12 * s, 17.5f * s); lineTo(14.5f * s, 12 * s); lineTo(21.5f * s, 12 * s)
                }
                drawPath(p, tint, style = stroke)
            }
            PlusIcon.body -> {
                drawOval(tint, Offset(10 * s, 3 * s), Size(4 * s, 4 * s))
                val b = Path().apply {
                    moveTo(12 * s, 8 * s); lineTo(12 * s, 14 * s)
                    moveTo(6 * s, 10 * s); lineTo(18 * s, 10 * s)
                    moveTo(12 * s, 14 * s); lineTo(8 * s, 21 * s)
                    moveTo(12 * s, 14 * s); lineTo(16 * s, 21 * s)
                }
                drawPath(b, tint, style = stroke)
            }
        }
    }
}

