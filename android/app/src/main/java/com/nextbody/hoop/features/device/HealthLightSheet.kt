package com.nextbody.hoop.features.device

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandError
import com.nextbody.hoop.band.BandHealthLightPreference
import com.nextbody.hoop.band.BandHealthLightState
import com.nextbody.hoop.band.BandLivePolicy
import com.nextbody.hoop.band.BandLog
import com.nextbody.hoop.band.BandReadiness
import com.nextbody.hoop.band.LiveReadout
import com.nextbody.hoop.band.localizedDescription
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch

/**
 * 12S · the light on the side of the band. Selection reflects the device reply, never the
 * tapped row; a confirmed state is saved on the phone and `BandHealthLightKeeper` writes it
 * back on every connect. Below it, the firmware's own disconnect reminder.
 */
@Composable
fun HealthLightSheet() {
    var current by remember { mutableStateOf<BandHealthLightState?>(null) }
    var reminder by remember { mutableStateOf<Boolean?>(null) }
    var busy by remember { mutableStateOf(false) }
    var unsupported by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var saved by remember { mutableStateOf(false) }
    /** A reconnect that arrived while a cancelled command was still draining. */
    var rereadWhenIdle by remember { mutableStateOf(false) }
    /** ⚠️ Only reads are held here. A write is never cancelled. */
    var operation by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    val connected = DataStore.band.connected

    /** `BandError`'s own descriptions are command labels meant for logs. On a screen they
     *  have to be sentences, and translated ones. */
    fun hoopMessage(error: Throwable): String = when (error) {
        is BandError.NotConnected -> L("Connect the band first.")
        is BandError.Busy -> L("The band is measuring. Try again in a moment.")
        is BandError.Timeout -> L("The band did not answer. Try again when it is on your wrist.")
        is BandError.Unsupported -> L("This band has no disconnect reminder.")
        is BandError.Rejected -> L("The band refused this setting.")
        else -> L(error.localizedDescription)
    }

    fun owner(): BandLivePolicy.Owner? {
        val owner = LiveReadout.currentOwner
        if (!DataStore.band.connected || owner == null) {
            message = L("Connect the band first."); return null
        }
        return owner
    }

    lateinit var perform: (BandHealthLightState?) -> Unit

    fun finish() {
        busy = false
        if (!rereadWhenIdle) return
        rereadWhenIdle = false
        if (DataStore.band.connected) perform(null)
    }

    /** nil reads the light; a state writes it. The reminder is read alongside the first read,
     *  before the light, so a band without light control still shows its reminder switch. */
    perform = perform@{ requested ->
        if (busy) return@perform
        val owner = owner() ?: return@perform
        busy = true
        message = null
        saved = false
        val job = scope.launch {
            try {
                if (requested == null && reminder == null) {
                    reminder = try {
                        BandReadiness.read(owner.account, owner.binding) { Band.live.readDisconnectReminder() }
                    } catch (e: CancellationException) { throw e } catch (_: Throwable) { null }
                    ensureActive()
                }
                val state = BandReadiness.read(owner.account, owner.binding) {
                    if (requested == null) return@read Band.live.readHealthLight()
                    val confirmed = Band.live.writeHealthLight(requested)
                    // ⚠️ Stored the instant the band answers: the band's reply is the truth
                    // whatever the screen is doing.
                    if (confirmed == requested) BandHealthLightPreference.store(confirmed)
                    confirmed
                }
                ensureActive()
                current = state
                unsupported = false
                if (requested != null) {
                    if (requested == state) saved = true
                    else message = L("The band returned a different state: %@", L(state.title))
                }
            } catch (e: CancellationException) {
                current = null
                message = L("Operation interrupted. Read again when the band is ready.")
            } catch (e: BandError.Unsupported) {
                current = null
                unsupported = true
                message = L("This band does not support health light control.")
            } catch (e: Throwable) {
                current = null
                BandLog.shared.record("healthLight.sheet", error = e)
                message = hoopMessage(e)
            } finally {
                finish()
            }
        }
        // Only a read may be torn down by leaving the sheet; a write runs to its answer.
        if (requested == null) operation = job
    }

    fun performReminder(on: Boolean) {
        if (busy) return
        val owner = owner() ?: return
        busy = true
        message = null
        saved = false
        scope.launch {
            try {
                reminder = BandReadiness.read(owner.account, owner.binding) { Band.live.writeDisconnectReminder(on) }
            } catch (e: CancellationException) {
                message = L("Operation interrupted. Read again when the band is ready.")
            } catch (e: Throwable) {
                BandLog.shared.record("healthLight.reminder", error = e)
                message = hoopMessage(e)
            } finally {
                finish()
            }
        }
    }

    LaunchedEffect(Unit) { perform(null) }
    DisposableEffect(Unit) { onDispose { operation?.cancel() } }
    var lastConnected by remember { mutableStateOf(connected) }
    LaunchedEffect(connected) {
        if (connected == lastConnected) return@LaunchedEffect
        lastConnected = connected
        operation?.cancel()
        current = null
        reminder = null
        unsupported = false
        if (!connected) { rereadWhenIdle = false; return@LaunchedEffect }
        // A command from the last link may still be draining. Wait for it rather than firing
        // a second one at a band that has not finished answering the first.
        if (busy) rereadWhenIdle = true else perform(null)
    }

    val eyebrow = when {
        !connected -> L("DISCONNECTED")
        unsupported -> L("NO LIGHT")
        current != null -> L(current!!.title).uppercase()
        else -> L("NOT READ")
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(NB.carbon2)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = DeviceSheetMetrics.gutter)
            .padding(top = DeviceSheetMetrics.top, bottom = DeviceSheetMetrics.bottom),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        SheetHeader(
            eyebrow = eyebrow,
            eyebrowTint = if (unsupported) NB.ember1 else NB.lime1,
            title = L("Health light"),
            subtitle = L("The light on the side of the band. Your choice is saved here and written to the band again every time it connects."),
        ) {
            if (busy) SmallSpinner(NB.lime1, size = 20.dp)
        }
        Column(Modifier.fillMaxWidth().sheetLines()) {
            for (state in BandHealthLightState.entries) {
                val enabled = !(busy || !connected || unsupported)
                Row(
                    Modifier
                        .fillMaxWidth()
                        .testTag("healthLight.state.${state.raw}")
                        .alpha(if (enabled) 1f else 0.5f)
                        .hotZoneTap(enabled = enabled, pressedScale = 1f) { perform(state) }
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(L(state.title), style = NBFont.ui(400, 16f), color = NB.text1, modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(24.dp)) // 8 + 8 + 8, as SwiftUI spaces around the Spacer
                    if (current == state) CheckGlyph()
                }
                if (state != BandHealthLightState.stayOn) Hairline(modifier = Modifier.padding(horizontal = 16.dp))
            }
        }
        val r = reminder
        if (r != null) {
            Row(
                Modifier.fillMaxWidth().sheetLines().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(L("Disconnect reminder"), style = NBFont.ui(400, 16f), color = NB.text1)
                    Text(L("The band signals on its own when it loses this phone."), style = NBFont.ui(300, 12f), color = NB.text3Prod)
                }
                Spacer(Modifier.width(0.dp))
                // The rocker renders the confirmed value, never the tapped one.
                HoopSwitch(r, enabled = !(busy || !connected),
                    modifier = Modifier.testTag("healthLight.disconnectReminder")) { performReminder(it) }
            }
        }
        val refreshEnabled = !(busy || !connected)
        Text(
            L("Read again"),
            style = NBFont.ui(400, 17f),
            color = NB.lime1,
            modifier = Modifier.testTag("healthLight.refresh").alpha(if (refreshEnabled) 1f else 0.4f)
                .hotZoneTap(enabled = refreshEnabled, pressedScale = 1f) { perform(null) },
        )
        if (saved) {
            Text(L("Saved. It will be written to the band again on every connect."), style = NBFont.ui(400, 13f), color = NB.lime1)
        }
        message?.let { Text(it, style = NBFont.ui(400, 13f), color = NB.ember1) }
    }
}

/** SF Symbols `checkmark`, lime. */
@Composable
private fun CheckGlyph() {
    Canvas(Modifier.size(16.dp, 14.dp)) {
        val w = size.width; val h = size.height
        val stroke = 2.dp.toPx()
        drawLine(NB.lime1, Offset(w * 0.08f, h * 0.55f), Offset(w * 0.38f, h * 0.88f), stroke, StrokeCap.Round)
        drawLine(NB.lime1, Offset(w * 0.38f, h * 0.88f), Offset(w * 0.92f, h * 0.12f), stroke, StrokeCap.Round)
    }
}
