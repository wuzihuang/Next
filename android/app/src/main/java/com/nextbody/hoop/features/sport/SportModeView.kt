package com.nextbody.hoop.features.sport

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandConnectionState
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.measure.MText
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.SportModeCatalog
import com.nextbody.hoop.model.SportModeOption
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.ui.DetailScroll
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.cardSkin

/**
 * Sport Mode · pick one of the catalogued modes and open it on the band. The moment the band
 * takes it this page is done: it returns to the root, and the session lives on the home screen
 * as the panel grown full size (`LiveSessionTakeover`) until STOP is held there.
 * Entered from the plus menu and from Training's START A SESSION. Wire for `Destination.SportMode`.
 */
@Composable
fun SportModeView() {
    val data = DataStore
    var starting by remember { mutableStateOf<Int?>(null) }
    var errorLine by remember { mutableStateOf<String?>(null) }
    /** Modes this firmware refused. Kept for the page's life so a dead row is not offered twice. */
    val refused = remember { mutableStateOf(setOf<Int>()) }
    val connected = data.band.connected

    LaunchedEffect(Unit) {
        Analytics.track("SPORT_MODE_OPEN", mapOf("CONNECTED" to connected))
        if (Band.live.state != BandConnectionState.connected) Band.live.reconnectIfBound()
        data.setBandConnected(Band.live.state == BandConnectionState.connected)
    }

    /** The tap is the start. The session is handed to the store and the page leaves at once;
     *  the takeover grows out of home's panel while the band is still being asked. */
    fun start(mode: SportModeOption) {
        if (!connected || starting != null || LiveSessionStore.session != null) return
        errorLine = null
        LiveSessionStore.begin(mode, data.profile, weightKg = data.today.weightKg ?: data.weighIns.firstOrNull()?.weightKg)
        Router.backToRoot()
    }

    DetailScroll(
        glow = NB.cyan1,
        title = L("SPORT MODE"),
        onBack = { Router.backToRoot() },
        trailing = {
            Row(
                Modifier
                    .height(24.dp)
                    .then(if (connected) Modifier else Modifier.border(1.dp, NB.hairline, CircleShape))
                    .padding(horizontal = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                Box(Modifier.size(6.dp).background(if (connected) NB.lime1 else NB.white.copy(alpha = 0.3f), CircleShape))
                MText(if (connected) L("CONNECTED") else L("DISCONNECTED"), NBFont.dot(600, 10f).tracking(0.2f),
                    if (connected) NB.lime1 else NB.text3Prod)
            }
        },
    ) {
        Column(
            Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            MText(L("Pick a mode. The band opens it, and home turns into the session until you stop."),
                NBFont.ui(300, 13f).tracking(0.02f), NB.white.copy(alpha = 0.42f))
            if (!connected) {
                MText(L("THE BAND ISN'T CONNECTED"), NBFont.dot(600, 10.5f).tracking(0.12f), NB.ember1)
            }
            errorLine?.let { MText(it, NBFont.dot(600, 10.5f).tracking(0.12f), NB.ember1) }

            Column(Modifier.fillMaxWidth().cardSkin()) {
                val modes = SportModeCatalog.displayModes
                modes.forEachIndexed { index, mode ->
                    val dead = mode.rawValue in refused.value
                    val enabled = connected && starting == null && !dead
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .height(46.dp)
                            .clickable(remember { MutableInteractionSource() }, null, enabled = enabled) { start(mode) }
                            .semantics { testTag = "sport-mode-${mode.rawValue}" }
                            .padding(horizontal = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        MText(mode.displayName, NBFont.dot(500, 12f).tracking(0.1f),
                            if (dead || !connected) NB.white.copy(alpha = 0.32f) else NB.text1)
                        MText("#${mode.rawValue}", NBFont.dot(400, 10f).tracking(0.1f), NB.white.copy(alpha = 0.28f))
                        Spacer(Modifier.weight(1f))
                        when {
                            starting == mode.rawValue -> CircularProgressIndicator(Modifier.size(16.dp), color = NB.cyan1, strokeWidth = 2.dp)
                            dead -> MText(L("NO"), NBFont.dot(600, 10.5f).tracking(0.12f), NB.ember1)
                            else -> MText(L("GO"), NBFont.dot(600, 10.5f).tracking(0.12f),
                                if (connected) NB.cyan1 else NB.white.copy(alpha = 0.28f))
                        }
                    }
                    if (index < modes.size - 1) Hairline(modifier = Modifier.padding(start = 16.dp))
                }
            }
        }
    }
}
