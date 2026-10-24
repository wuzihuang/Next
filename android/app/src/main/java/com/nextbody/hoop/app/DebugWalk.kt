package com.nextbody.hoop.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.features.vitals.VitalsMetric
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The walk switches from iOS `RootView` (`NB_DEBUG_ROUTE`, `NB_DEBUG_SHEET`,
 * `NB_DEBUG_TAKEOVER`, `NB_DEBUG_MEASURE`), read from debug launch extras. Release builds never
 * see an extra, so this is inert there.
 */
object DebugWalk {
    /** `device` / `battery` / `measurements` are not envelope targets, but a walk needs them. */
    fun destination(raw: String): Destination? {
        Destination.fromEnvelopeTarget(raw)?.let { return it }
        return when (raw) {
            "device" -> Destination.Device
            "deviceAutoMonitor", "autoMonitor" -> Destination.DeviceAutoMonitor
            "battery" -> Destination.Battery
            "measurements" -> Destination.Measurements
            "sportMode", "sport" -> Destination.SportMode
            "fuelDay" -> Destination.FuelDay(UserDay.containing(java.time.Instant.now()).adding(-1))
            else -> if (raw.startsWith("vitals.")) VitalsMetric.from(raw.removePrefix("vitals."))?.let { Destination.Vitals(it) } else null
        }
    }

    fun sheet(raw: String): SheetRoute? = when (raw) {
        "feedback" -> SheetRoute.Feedback
        "assistants" -> SheetRoute.Assistants
        "deleteAccount" -> SheetRoute.DeleteAccount
        "privacy" -> SheetRoute.Privacy
        "about" -> SheetRoute.About
        "language" -> SheetRoute.Language
        "units" -> SheetRoute.Units
        "plusMenu" -> SheetRoute.PlusMenu
        "weighIn" -> SheetRoute.WeighIn
        "scanWeighIn" -> SheetRoute.ScanWeighIn
        "profileEdit" -> SheetRoute.ProfileEdit
        "goal" -> SheetRoute.Goal
        "notifications" -> SheetRoute.Notifications
        "appleHealth", "healthConnect" -> SheetRoute.HealthConnect
        "signOut" -> SheetRoute.SignOut
        "widgets" -> SheetRoute.Widgets
        "height" -> SheetRoute.Height
        "weightBaseline" -> SheetRoute.WeightBaseline
        "birthday" -> SheetRoute.Birthday
        "findBand" -> SheetRoute.FindBand
        "unbind" -> SheetRoute.Unbind
        "disconnect" -> SheetRoute.Disconnect
        "firmware" -> SheetRoute.Firmware
        "syncCadence" -> SheetRoute.SyncCadence
        "bandAutoMonitor" -> SheetRoute.BandAutoMonitor
        "findHoop" -> SheetRoute.FindHoop
        "bandAlarms" -> SheetRoute.BandAlarms
        else -> null
    }

    fun takeover(raw: String): Takeover? = when (raw) {
        "wordmark" -> Takeover.Wordmark
        "bodyscan" -> Takeover.Measure(MeasureKind.bodyComposition)
        "battery" -> Takeover.Measure(MeasureKind.heartRate)
        "consent" -> Takeover.Consent
        "notify" -> Takeover.NotificationPrimer
        else -> null
    }

    @Composable
    fun Run() {
        LaunchedEffect(Unit) {
            DebugLaunch["NB_DEBUG_ROUTE"]?.let { destination(it) }?.let { d ->
                delay(1200)
                if (Router.path.isEmpty()) Router.open(d, EntryPoint.home)
            }
        }
        LaunchedEffect(Unit) {
            val raw = DebugLaunch["NB_DEBUG_SHEET"] ?: return@LaunchedEffect
            if (raw == "measurement") {
                delay(3000)
                DataStore.measurements.firstOrNull()?.let { Router.sheet = SheetRoute.Measurement(it.id) }
            } else {
                sheet(raw)?.let { delay(2500); Router.sheet = it }
            }
        }
        LaunchedEffect(Unit) {
            launch {
                DebugLaunch["NB_DEBUG_TAKEOVER"]?.let { takeover(it) }?.let { t ->
                    delay(if (t is Takeover.Wordmark) 500 else 2000)
                    Router.setTakeover(t)
                }
            }
            DebugLaunch["NB_DEBUG_MEASURE"]?.let { MeasureKind.from(it) }?.let { k ->
                delay(3000)
                if (Router.takeover == null) Router.setTakeover(Takeover.Measure(k))
            }
        }
    }
}
