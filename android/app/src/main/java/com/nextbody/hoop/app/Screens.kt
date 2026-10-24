package com.nextbody.hoop.app

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import com.nextbody.hoop.data.SessionStore
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBText

/**
 * Where the shell meets the features: every page, sheet and takeover the root can show,
 * switched in one place (RootView.swift's `navigationDestination`, `TakeoverHost`, `SheetHost`).
 */
object Screens {
    @Composable
    fun Stage() {
        val session = AppSession.session
        LaunchedEffect(Unit) {
            // Restoring the local account gates BLE, not cloud homepage hydration.
            if (session.ensureSession()) AppLifecycle.foregroundHook?.invoke("launch")
            session.resolveLaunch()
        }
        when (session.stage) {
            SessionStore.Stage.gateSignIn -> com.nextbody.hoop.features.auth.SignInFlow()
            SessionStore.Stage.gateConnect -> com.nextbody.hoop.features.connect.ConnectFlow()
            SessionStore.Stage.gateOnboarding -> com.nextbody.hoop.features.onboarding.OnboardingFlow()
            SessionStore.Stage.root -> RootStack()
        }
    }

    @Composable
    fun LaunchOverlay() {
        if (AppSession.session.holdingLaunchStill) com.nextbody.hoop.features.auth.LaunchMark()
    }

    @Composable
    fun Home() {
        com.nextbody.hoop.features.home.HomeView()
    }

    @Composable
    fun Detail(d: Destination) {
        when (d) {
            Destination.Training -> com.nextbody.hoop.features.training.TrainingDetailView()
            Destination.Fuel -> com.nextbody.hoop.features.fuel.FuelDetailView()
            is Destination.FuelDay -> com.nextbody.hoop.features.fuel.FuelDetailView(focus = d.day)
            Destination.BodyBattery -> com.nextbody.hoop.features.bodybattery.BodyBatteryDetailView()
            is Destination.Composition -> com.nextbody.hoop.features.composition.CompositionDetailView(d.date)
            Destination.Profile -> com.nextbody.hoop.features.profile.ProfileView()
            Destination.Measurements -> com.nextbody.hoop.features.measurements.MeasurementsView()
            Destination.Device, Destination.DeviceAutoMonitor -> com.nextbody.hoop.features.device.DeviceView()
            Destination.Battery -> com.nextbody.hoop.features.device.BatteryTrendView()
            is Destination.Vitals -> com.nextbody.hoop.features.vitals.VitalsDetailView(d.metric)
            Destination.SportMode -> com.nextbody.hoop.features.sport.SportModeView()
            else -> Placeholder(d.key) { Router.back() }
        }
    }

    @Composable
    fun Takeover(t: com.nextbody.hoop.app.Takeover, close: () -> Unit) {
        when (t) {
            com.nextbody.hoop.app.Takeover.Consent ->
                com.nextbody.hoop.features.consent.ConsentScreen(onContinue = close, onBack = close)
            com.nextbody.hoop.app.Takeover.Wordmark -> com.nextbody.hoop.features.auth.WordmarkAnimation(onFinish = close)
            com.nextbody.hoop.app.Takeover.NotificationPrimer -> com.nextbody.hoop.features.home.NotificationPrimer(onDone = close)
            is com.nextbody.hoop.app.Takeover.Measure -> com.nextbody.hoop.features.measure.MeasureTakeover(t.kind, close)
        }
    }

    @Composable
    fun Sheet(route: SheetRoute, close: () -> Unit) {
        when (route) {
            SheetRoute.ProfileEdit, SheetRoute.Goal, SheetRoute.Notifications, SheetRoute.Units,
            SheetRoute.Language, SheetRoute.HealthConnect, SheetRoute.Feedback, SheetRoute.Privacy,
            SheetRoute.About, SheetRoute.DeleteAccount, SheetRoute.SignOut, SheetRoute.Widgets,
            SheetRoute.Assistants, SheetRoute.WeighIn, SheetRoute.ScanWeighIn, is SheetRoute.Measurement ->
                com.nextbody.hoop.features.profile.ProfileSheet(route, close)
            SheetRoute.FindBand, SheetRoute.Unbind, SheetRoute.Disconnect, SheetRoute.Firmware,
            SheetRoute.SyncCadence, SheetRoute.BandAutoMonitor, SheetRoute.ActivateSecond, is SheetRoute.WearSwitch,
            SheetRoute.ReleaseSet, SheetRoute.FindHoop, SheetRoute.BandAlarms, SheetRoute.HealthLight ->
                com.nextbody.hoop.features.device.DeviceSheet(route, close)
            SheetRoute.Height -> com.nextbody.hoop.features.onboarding.HeightSheet(close)
            SheetRoute.WeightBaseline -> com.nextbody.hoop.features.onboarding.WeightBaselineSheet(close)
            SheetRoute.Birthday -> com.nextbody.hoop.features.onboarding.BirthdaySheet(close)
            SheetRoute.PlusMenu -> com.nextbody.hoop.features.measure.PlusMenuSheet(close)
            else -> Placeholder(route.toString(), close)
        }
    }

    @Composable
    private fun Placeholder(name: String, onTap: (() -> Unit)? = null) {
        Box(
            Modifier.fillMaxSize().background(NB.carbon)
                .let { if (onTap != null) it.clickable { onTap() } else it },
            contentAlignment = Alignment.Center,
        ) {
            Column(Modifier.padding(24.dp)) {
                NBText(name.uppercase(), size = 20f, color = NB.lime1)
            }
        }
    }
}
