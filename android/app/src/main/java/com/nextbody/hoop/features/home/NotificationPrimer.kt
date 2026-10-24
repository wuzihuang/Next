package com.nextbody.hoop.features.home

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.NotificationReach
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * F5 C4 · the notification primer. NEXTBODY taps on edges (ADR 0019), not only last night.
 * Two buttons, Not now / Turn on. The system dialog appears only after Turn on, and once
 * refused is never shown again. Not now is not a refusal: the primer comes back the next morning.
 */
@Composable
fun NotificationPrimer(onDone: () -> Unit) {
    val ink = hex(0xF4F4F6)
    val lede = hex(0xA6A6AE)
    val scope = rememberCoroutineScope()
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { _ ->
        scope.launch {
            NotificationReach.didGainAuthorization()
            onDone()
        }
    }

    LaunchedEffect(Unit) { Analytics.track("NOTIF_PRIMER_SHOWN") }

    fun turnOn() {
        scope.launch { Analytics.track("NOTIF_PRIMER_CHOICE", mapOf("CHOICE" to "turn_on")) }
        Defaults.putBoolean(NotificationPrimerPolicy.askedKey, true)
        if (Build.VERSION.SDK_INT >= 33) launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        else scope.launch {
            NotificationReach.didGainAuthorization()
            onDone()
        }
    }

    fun notNow() {
        Defaults.putString(NotificationPrimerPolicy.notNowKey, UserDay.containing(Instant.now()).key)
        scope.launch { Analytics.track("NOTIF_PRIMER_CHOICE", mapOf("CHOICE" to "not_now")) }
        onDone()
    }

    Box(Modifier.fillMaxSize().background(NB.carbon), contentAlignment = Alignment.BottomCenter) {
        Column(
            // Laid out inside the safe area, as the iOS ZStack is; only the ground bleeds.
            Modifier.width(NB.Layout.screenWidth).padding(horizontal = 24.dp).padding(bottom = ScreenMetrics.safeBottom),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text(
                L("NEXTBODY taps you when something changes."),
                style = NBFont.brand(600, 30f).tracking(-0.02f).copy(lineHeight = (30 * 1.2f + 4).sp),
                color = ink,
            )
            Text(
                L("Last night lands, a meal is still open, training is under, or the band goes dark."),
                style = NBFont.ui(300, 17f).copy(lineHeight = (17 * 1.2f + 8).sp),
                color = lede,
            )
            Spacer(Modifier.height(140.dp))
        }

        Column(
            Modifier.padding(bottom = 34.dp + ScreenMetrics.safeBottom),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // LimePillButton (Connect) · 56 tall, lime capsule, carbon ink.
            Box(
                Modifier
                    .size(NB.Layout.contentWidth - 16.dp, 56.dp)
                    .hotZoneTap(pressedScale = 1f, onClick = ::turnOn)
                    .background(NB.lime1, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(L("Turn on"), style = NBFont.ui(500, 15f).tracking(0.06f), color = NB.carbon)
            }
            Box(
                Modifier
                    .size(NB.Layout.contentWidth - 16.dp, 44.dp)
                    .hotZoneTap(pressedOpacity = 1f, pressedScale = 1f, role = Role.Button, onClick = ::notNow),
                contentAlignment = Alignment.Center,
            ) {
                Text(L("Not now"), style = NBFont.ui(500, 15f).tracking(0.04f), color = NB.white.copy(alpha = 0.55f))
            }
        }
    }
}

/** The static half of Swift's `NotificationPrimer`: when the primer is offered. */
object NotificationPrimerPolicy {
    const val notNowKey = "nb.notif.primer.notNowDay"
    /** Android has no `.notDetermined`: the app remembers that it has asked once. */
    const val askedKey = "nb.notif.primer.asked"

    /**
     * Offered only while the system has never been asked, and not twice on one day.
     * Below API 33 notifications are on unless the person switched them off: there is
     * nothing to ask, so the primer never shows.
     */
    @Suppress("RedundantSuspendModifier")
    suspend fun shouldOffer(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return false
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return false
        if (Defaults.getBoolean(askedKey)) return false
        return Defaults.getString(notNowKey) != UserDay.containing(Instant.now()).key
    }
}
