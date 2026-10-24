package com.nextbody.hoop.band

import com.nextbody.hoop.services.SupabaseClient
import kotlinx.coroutines.Job

/**
 * Process-owned live collection. The heart stream runs only while a screen asks for it
 * (`BandLivePolicy`, ADR 0023); leaving the app ends it, so the band is not left
 * measuring — LED lit, battery draining — for nobody. Background day pulls are a
 * different lane and do not go through here.
 */
class BandLiveLifecycle private constructor() {
    companion object {
        val shared: BandLiveLifecycle by lazy { BandLiveLifecycle() }
    }

    private var phase: BandLivePolicy.Phase = BandLivePolicy.Phase.active
    private var foregroundWanted = false
    private var exclusive = false
    private val tasks = BandLiveTaskOwner()
    private var observers = mutableListOf<Job>()
    private var events: Job? = null

    fun start() {
        if (events != null) return
        // ConsentStore / LiveSessionStore objectWillChange.
        observers += BandMain.launch { BandHost.changes.collect { scheduleRefresh() } }
        // TODO(wire): iOS also refreshes on UserDefaults.didChangeNotification (a binding
        // written elsewhere). Binding writes here go through BoundBand, whose callers refresh.
        events = BandMain.launch {
            Band.live.events.collect { event ->
                if (event is BandEvent.State) refreshEligibility()
            }
        }
        observers += BandMain.launch {
            SupabaseClient.accountDidChange.collect {
                BandReadiness.shared.invalidateSnapshot()
                refreshEligibility()
            }
        }
        BandHealthLightKeeper.shared.start()
        refreshEligibility()
    }

    private fun scheduleRefresh() {
        // objectWillChange fires before the new property is written.
        BandMain.launch { refreshEligibility() }
    }

    /** Swift takes SwiftUI's ScenePhase; Android passes the mapped policy phase. */
    fun setPhase(scenePhase: BandLivePolicy.Phase) {
        BandTrace.notice("lifecycle scene phase=$scenePhase")
        phase = scenePhase
        LiveReadout.shared.setBackground(phase != BandLivePolicy.Phase.active)
        refreshEligibility()
    }

    fun setForegroundWanted(wanted: Boolean) {
        foregroundWanted = wanted
        refreshEligibility()
    }

    fun setExclusiveOperation(value: Boolean) {
        exclusive = value
        refreshEligibility()
    }

    val hasExclusiveOperation: Boolean
        get() {
            val live = BandHost.liveSession()
            return exclusive || DeviceSetStore.shared.activationGate.isHeld
                || live.hasSession || live.opening
                || live.cleaningUp || BandMeasurementLifetimeShared.instance.isBusy
        }

    fun refreshEligibility() {
        val owner = LiveReadout.currentOwner
        val allowed = BandLivePolicy.shouldRun(phase = phase, foregroundWanted = foregroundWanted,
            hasOwner = owner != null, consent = BandHost.consentGranted(),
            connected = Band.live.state == BandConnectionState.connected,
            exclusive = hasExclusiveOperation)
        tasks.update(owner = if (allowed) owner else null) {
            LiveReadout.shared.run()
        }
    }
}

/** Swift `extension BandMeasurementLifetime { static let shared }`. */
object BandMeasurementLifetimeShared {
    val instance: BandMeasurementLifetime by lazy {
        BandMeasurementLifetime(
            acquire = { BandReadiness.shared.beginMeasurement() },
            release = { BandReadiness.shared.endMeasurement() },
            changed = { BandLiveLifecycle.shared.refreshEligibility() })
    }
}
