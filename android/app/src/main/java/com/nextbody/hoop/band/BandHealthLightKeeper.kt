package com.nextbody.hoop.band

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

/**
 * Writes the user's health-light choice back to the band on every connect.
 *
 * The choice is made once, on the Device page. Firmware may forget it across a reboot or
 * a re-pair, and a light the user turned off has to stay off without them opening the
 * app again — so each `.connected` transition re-sends it. No choice, nothing sent: the
 * firmware's own default stands.
 */
class BandHealthLightKeeper private constructor() {
    companion object {
        val shared: BandHealthLightKeeper by lazy { BandHealthLightKeeper() }

        /** Readiness reads identity and battery first, and a pairing takeover holds the band
         *  for a while; the write waits its turn and asks again rather than giving up once.
         *  ⚠️ A slot is spent only on a real failure. A band held by a workout or a measurement
         *  is not a refusal — that pass waits and asks again without using one up. */
        private val attemptDelays: List<Double> = listOf(3.0, 8.0, 15.0, 30.0, 60.0)
        /** Backstop for the passes that do not spend a slot (a held band, a reconcile). */
        private const val maxPasses = 24
    }

    private var events: Job? = null
    private var apply: Job? = null

    fun start() {
        if (events != null) return
        events = BandMain.launch {
            Band.live.events.collect { event ->
                if (event !is BandEvent.State) return@collect
                if (event.state == BandConnectionState.connected) schedule() else cancelPending()
            }
        }
    }

    /** Called when the link drops. ⚠️ Not called by the sheet after its own write: a write
     *  already queued behind a day pull cannot be recalled, so cancelling here would only
     *  blind the keeper to the stale value it is about to send. It reconciles instead. */
    fun cancelPending() {
        apply?.cancel()
        apply = null
    }

    private fun schedule() {
        cancelPending()
        if (BandHealthLightPreference.stored() == null) return
        apply = BandMain.launch {
            var attempt = 0
            var passes = 0
            // Set when the last write landed a value the user has since changed. The newer
            // choice goes out immediately instead of waiting out the ladder.
            var reconciling = false
            while (attempt < attemptDelays.size && passes < maxPasses) {
                passes += 1
                if (!reconciling) {
                    try { delay((attemptDelays[attempt] * 1000).toLong()) } catch (_: CancellationException) {}
                }
                reconciling = false
                if (!currentCoroutineContext().isActive || Band.live.state != BandConnectionState.connected) return@launch
                // Read again each pass: the sheet may have changed the choice meanwhile.
                val wanted = BandHealthLightPreference.stored() ?: return@launch
                // A takeover, a workout or a measurement owns the band. Wait for it.
                if (BandLiveLifecycle.shared.hasExclusiveOperation) continue
                val owner = LiveReadout.currentOwner ?: continue
                try {
                    val band = BandReadiness.read(account = owner.account, binding = owner.binding) {
                        Band.live.writeHealthLight(wanted)
                    }
                    BandTrace.notice("health light applied wanted=${wanted.raw} band=${band.raw} attempt=${attempt + 1}")
                    BandTrace.record("band.health_light_applied",
                        mapOf("wanted" to wanted.raw.toString(), "band" to band.raw.toString(), "attempt" to (attempt + 1).toString()))
                    // ⚠️ This write may have waited behind a day pull while the user chose
                    // something else on the sheet. The band now holds the older value, and
                    // the queue cannot be recalled — so send the newer one straight away.
                    if (BandHealthLightPreference.stored() == band) return@launch
                    reconciling = true
                    continue
                } catch (e: BandError.Unsupported) {
                    BandTrace.notice("health light: this NEXTBODY has no light control")
                    return@launch
                } catch (e: CancellationException) {
                    // The band was taken mid-command. Not a refusal; ask again for free.
                    if (!currentCoroutineContext().isActive) return@launch
                    continue
                } catch (e: Throwable) {
                    BandLog.shared.record("healthLight.apply", error = e)
                    BandTrace.record("band.health_light_apply_failed", mapOf("attempt" to (attempt + 1).toString()))
                    attempt += 1
                }
            }
        }
    }
}
