package com.nextbody.hoop.band

import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.services.SupabaseClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.yield

/**
 * Connection + fresh battery only. Cloud registration and historical reads belong to
 * the full sync lane and never prevent foreground callers from checking the live link.
 */
class BandReadiness private constructor() {
    companion object {
        val shared: BandReadiness by lazy { BandReadiness() }

        private fun uptime(): Double = System.nanoTime() / 1_000_000_000.0

        /** Pause the live sensor for native commands only, never for a cloud request. */
        suspend fun <T> read(account: String, binding: String, work: suspend () -> T): T {
            if (!shared.allowed(account, binding) || Band.live.state != BandConnectionState.connected) {
                throw CancellationException("band scope changed")
            }
            shared.nativeDrain.begin()
            try {
                val result: Result<T> = LiveReadout.shared.standDown {
                    if (!shared.allowed(account, binding) || Band.live.state != BandConnectionState.connected) {
                        return@standDown Result.failure(CancellationException("band scope changed"))
                    }
                    try {
                        val value = work()
                        if (!shared.allowed(account, binding) || Band.live.state != BandConnectionState.connected) {
                            return@standDown Result.failure(CancellationException("band scope changed"))
                        }
                        Result.success(value)
                    } catch (e: Throwable) { Result.failure(e) }
                }
                return result.getOrThrow()
            } finally {
                shared.nativeDrain.end()
            }
        }
    }

    private val flight = BandReadinessFlight()
    private val nativeDrain = BandNativeDrain()
    var snapshot: Snapshot? = null
        private set

    data class Snapshot(
        val account: String,
        val binding: String,
        val identity: BandIdentity?,
        val battery: BandBattery,
    )

    suspend fun ensureReady(store: DataStore, reason: String, reuseRecentLiveReceipt: Boolean = false): Boolean {
        val account = SupabaseClient.currentUserIdSnapshot() ?: return false
        val binding = BoundBand.identifier ?: return false
        if (!allowed(account, binding)) return false
        if (reuseRecentLiveReceipt && Band.live.state == BandConnectionState.connected &&
            LiveReadout.shared.hasRecentReceipt(maxAge = 3.0)) {
            store.setBandConnected(true)
            BandTrace.notice("readiness reuse real-live-receipt")
            return true
        }
        val ready = flight.run(key = "$account:$binding") {
            if (!allowed(account, binding)) return@run false
            val start = uptime()
            // Reasons are code-owned labels. Do not log account, MAC, UUID or raw errors.
            val label = reason.filter { it.isLetter() || it == '-' }.take(40)
            BandTrace.notice("readiness start reason=$label reuse=${Band.live.state == BandConnectionState.connected}")
            BandPresence.shared.start(store)
            nativeDrain.begin()
            try {
                LiveReadout.shared.standDown {
                    if (!allowed(account, binding)) return@standDown false
                    if (Band.live.state != BandConnectionState.connected) Band.live.reconnectIfBound()
                    if (!allowed(account, binding) || Band.live.state != BandConnectionState.connected) return@standDown false
                    BandTrace.notice("readiness connected elapsed=${uptime() - start}")
                    if (reason == "sync") BandSyncActivity.shared.show(BandSyncProgress.Stage.identity)
                    val identity = runCatching { Band.live.readIdentity() }.getOrNull()
                    if (!allowed(account, binding) || Band.live.state != BandConnectionState.connected) return@standDown false
                    try {
                        if (reason == "sync") BandSyncActivity.shared.show(BandSyncProgress.Stage.battery)
                        val battery = Band.live.readBattery()
                        if (!allowed(account, binding) || Band.live.state != BandConnectionState.connected) return@standDown false
                        snapshot = Snapshot(account, binding, identity, battery)
                        store.setBandConnected(true)
                        store.applyBandObservation(identity = identity, battery = battery)
                        BandTrace.notice("readiness battery elapsed=${uptime() - start}")
                        true
                    } catch (e: Throwable) {
                        if (e is CancellationException && !currentCoroutineContext().isActive) throw e
                        BandTrace.error("readiness battery failed elapsed=${uptime() - start}")
                        false
                    }
                }
            } finally {
                nativeDrain.end()
            }
        }
        return ready && allowed(account, binding) && Band.live.state == BandConnectionState.connected
    }

    /** Call after closing native admission with the exclusive-operation gate. */
    suspend fun awaitNativeIdle() = nativeDrain.waitUntilIdle()
    val isNativeIdle: Boolean get() = nativeDrain.isIdle

    /** Measurement admission stays closed through stream cancellation and its queued stop. */
    suspend fun beginMeasurement() {
        nativeDrain.waitUntilIdle()
        nativeDrain.begin()
    }

    suspend fun endMeasurement() {
        // One hop through the main queue, so the stream's queued stop goes out first.
        yield()
        nativeDrain.end()
    }

    fun invalidateSnapshot() { snapshot = null }

    private suspend fun allowed(account: String, binding: String): Boolean {
        val live = BandHost.liveSession()
        return currentCoroutineContext().isActive && BandHost.consentGranted() && !live.hasSession
            && !BandLiveLifecycle.shared.hasExclusiveOperation
            && SupabaseClient.currentUserIdSnapshot() == account && BoundBand.identifier == binding
    }
}
