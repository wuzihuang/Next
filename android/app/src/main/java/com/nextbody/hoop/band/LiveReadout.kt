package com.nextbody.hoop.band

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nextbody.hoop.services.SupabaseClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield
import java.time.Instant
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * App-owned heart stream. It follows the screen (`BandLivePolicy`, ADR 0023): the home
 * panel asks for it while someone is looking, and leaving the app ends it — the band is
 * never left measuring for a number nobody reads. `background` below means "not `.active`",
 * so its guards only ever fire during an `.inactive` scene (a call, Control Center), which
 * keeps the open stream rather than churning it and inserts no new stress test.
 */
class LiveReadout private constructor() {
    companion object {
        val shared: LiveReadout by lazy { LiveReadout() }

        val currentOwner: BandLivePolicy.Owner?
            get() {
                val account = SupabaseClient.currentUserIdSnapshot() ?: return null
                val binding = BoundBand.identifier ?: return null
                if (binding.isEmpty()) return null
                return BandLivePolicy.Owner(account = account, binding = binding)
            }
    }

    /** What the panel is allowed to say about itself. `offline` is the link, `noContact` is
     *  the wrist — they are two different sentences and never drawn the same way. */
    enum class Phase {
        /** Nothing is running: the panel falls back to the last tick, as it always did. */
        off,
        offline,
        /** The command went out; the band has not judged contact yet. */
        reaching,
        live,
        noContact,
        /** The stress test holds the sensor. The heart rate on screen is the one from just
         *  before it, ageing — which is why this is its own phase and not `live`. */
        stress,
    }

    /** The one place the cadence is written down. */
    object Cadence {
        /** How long the first heart rates get before the stress test interrupts them. Short
         *  enough that a user who lingers sees a live stress number, long enough that the
         *  beat is on screen first — the beat is what tells them the band is awake. */
        const val firstStress: Double = 20.0
        /** Between stress tests after that. The band's own auto-monitoring runs every half
         *  hour; this cadence only exists while someone is watching. */
        const val stressEvery: Double = 300.0
        /** A live number older than this is not live any more: the panel drops back to the
         *  stored tick rather than leaving a stale beat on screen. */
        const val liveWindow: Double = 15.0
        /** After a refused or failed command, before trying again. */
        const val retry: Double = 3.0
        /** What the band gets between the heart test being stopped and the stress test being
         *  started. The stop is a command, not an instant — see `readStress`. */
        const val settle: Double = 1.2
        /** The longest a single heart-rate stream is left open before it is reopened. The
         *  SDK ends its own test eventually; this is the ceiling if it does not. */
        const val heartRun: Double = 600.0
    }

    var phase by mutableStateOf(Phase.off)
        private set
    /** The band's last reported rate and the instant it reported it. */
    var hr by mutableStateOf<Int?>(null)
        private set
    var hrAt by mutableStateOf<Instant?>(null)
        private set
    /** The last completed stress test. Kept for the whole session — a stress number is a
     *  one-shot measurement, and five minutes old is what it is, not a dash. */
    var stress by mutableStateOf<Int?>(null)
        private set
    var stressAt by mutableStateOf<Instant?>(null)
        private set
    /** 0…100 while the stress test runs, null the rest of the time. The band's own count —
     *  19 s of it. ⚠️ Never a tween: if the band stops counting, so does this. */
    var stressProgress by mutableStateOf<Int?>(null)
        private set

    private var running = false
    private var background = false
    private var sessionOwner: BandLivePolicy.Owner? = null
    private var heartDeadline: Instant? = null
    private var receivedSamples = 0

    private suspend fun acceptsSample(): Boolean = currentCoroutineContext().isActive && acceptsSampleNow()

    private fun acceptsSampleNow(): Boolean {
        val live = BandHost.liveSession()
        return sessionOwner != null && sessionOwner == currentOwner
            && BandHost.consentGranted() && Band.live.state == BandConnectionState.connected
            && !live.hasSession && !live.opening
    }

    /** Only a recently received sample in this exact account/binding can prove warm readiness. */
    fun hasRecentReceipt(maxAge: Double): Boolean {
        val at = hrAt
        if (!acceptsSampleNow() || at == null) return false
        val age = BandTime.interval(Instant.now(), at)
        return BandReadinessReceiptPolicy.canReuse(requested = true,
            connected = Band.live.state == BandConnectionState.connected,
            exclusive = BandLiveLifecycle.shared.hasExclusiveOperation,
            ownerMatches = acceptsSampleNow(), age = age, maxAge = maxAge)
    }

    fun setBackground(value: Boolean) {
        background = value
        val deadline = heartDeadline
        if (!value && deadline != null && !Instant.now().isBefore(deadline)) bandTask?.cancel()
    }

    /** Set when the band answers "no such test". Only the attempt is authoritative — and once
     *  it has answered, the cadence drops it rather than asking every three seconds. */
    private var heartUnsupported = false
    private var stressUnsupported = false
    /** Whether the last stress test got an answer of any kind, as opposed to being cut short. */
    private var stressAnswered = false
    /** Consecutive stress tests that got no answer, for the backoff. */
    private var stressMisses = 0
    /** The one child task talking to the band right now — a heart stream or a stress test.
     *  Held here so `standDown` can end it from outside the session's own loop. */
    private var bandTask: Job? = null
    /** While this is up the loop keeps its hands off the band. Counted, not a flag: two
     *  pulls in a row must not have the first one's release let the readout back in. */
    private var suspended = 0

    /** The heart rate, but only while it is still now. Everything on screen reads this and
     *  never `hr` directly. */
    val liveHR: Int?
        get() {
            val hr = hr ?: return null
            val at = hrAt ?: return null
            return if (BandTime.interval(Instant.now(), at) < Cadence.liveWindow) hr else null
        }

    /** The stress number this session measured — kept for as long as the session lasts, and
     *  gone with it. */
    val liveStress: Int? get() = if (stressAt == null) null else stress

    /** Whether the panel is showing the band rather than the library. */
    val isLive: Boolean get() = liveHR != null || phase == Phase.stress

    /** Held by BandLiveLifecycle for the current account and device. */
    suspend fun run() {
        // One session per process. Two would fight over the same command channel, and the
        // second one's `stop` would end the first one's test.
        if (running) return
        val owner = currentOwner ?: return
        if (!BandHost.consentGranted()) return
        sessionOwner = owner
        running = true
        receivedSamples = 0
        heartUnsupported = false
        stressUnsupported = false
        BandTrace.notice("live stream start background=$background")
        try {
            var nextStress = BandTime.adding(Instant.now(), Cadence.firstStress)
            while (currentCoroutineContext().isActive && !heartUnsupported && acceptsSample()) {
                if (Band.live.state != BandConnectionState.connected) {
                    phase = Phase.offline
                    hr = null; hrAt = null
                    sleepSeconds(Cadence.retry)
                    continue
                }
                // F3 §06 · a day pull holds the same command channel, and it is the one that
                // must not be dropped — it is the day itself. While it has the band the readout
                // keeps its hands off; talking over it corrupts its reply rather than failing.
                if (suspended > 0) {
                    // Nothing is being measured, so the panel says so: STANDBY over the tick's
                    // own age.
                    phase = Phase.off
                    hr = null; hrAt = null
                    runCatching { delay(300) }
                    continue
                }
                if (stressDue(nextStress)) {
                    stressAnswered = false
                    hold { readStress() }
                    // A test that was cut short, or refused because the band was still winding
                    // down the heart test, is not a reading. Only an answer buys the full
                    // cadence; a miss comes back sooner, backing off.
                    if (stressAnswered) {
                        stressMisses = 0
                        nextStress = BandTime.adding(Instant.now(), Cadence.stressEvery)
                    } else {
                        stressMisses += 1
                        val backoff = Cadence.retry * 2.0.pow((stressMisses - 1).toDouble())
                        nextStress = BandTime.adding(Instant.now(), min(Cadence.stressEvery, backoff))
                    }
                    continue
                }
                // The heart stream stays open until the stress test comes due — or, if this
                // firmware has none, until the SDK ends its own test and the loop reopens it.
                hold(until = if (stressUnsupported) null else nextStress) { consumeHeart() }
            }
        } finally {
            BandTrace.notice("live stream stop samples=$receivedSamples")
            sessionOwner = null
            running = false
            phase = Phase.off
            // ⚠️ The numbers are dropped with the session on purpose. Kept, they would
            // reappear on the next entry as "now" for a wrist that has since moved.
            hr = null; hrAt = null
            stress = null; stressAt = null
        }
    }

    /** `try? await Task.sleep` — a cancelled sleep just returns; the loop checks cancellation. */
    private suspend fun sleepSeconds(seconds: Double) {
        try { delay((seconds * 1000).toLong()) } catch (_: CancellationException) {}
    }

    /**
     * F3 §06 · everything that talks to the band goes through here: exactly one child task
     * at a time, ended by the deadline, by `standDown`, or with the session.
     * ⚠️ Unstructured on purpose — the task has to be cancellable from outside this loop —
     * so the cancellation handler carries lifecycle revocation into the SDK stream.
     */
    private suspend fun hold(until: Instant? = null, work: suspend () -> Unit) {
        val task = BandMain.launch { work() }
        bandTask = task
        heartDeadline = until
        val timer = until?.let { at ->
            BandMain.launch {
                val seconds = min(Cadence.heartRun, max(0.0, BandTime.interval(at, Instant.now())))
                delay((seconds * 1000).toLong())
                if (!isActive || background) return@launch
                task.cancel()
            }
        }
        try {
            task.join()
        } catch (e: CancellationException) {
            task.cancel()
            withContext(NonCancellable) { task.join() }
        } finally {
            timer?.cancel()
            bandTask = null
            heartDeadline = null
            withContext(NonCancellable) { drainNativeStop() }
        }
    }

    /** Take the band away from the readout for the length of `work`. The day pull calls this
     *  around itself: the open test is stopped first and awaited, so the pull's first command
     *  goes out to a band that is not in the middle of anything. */
    suspend fun <T> standDown(work: suspend () -> T): T {
        suspended += 1
        try {
            val held = bandTask
            held?.cancel()
            held?.join()
            drainNativeStop()
            return work()
        } finally {
            suspended -= 1
        }
    }

    /** Flow cancellation schedules the SDK stop; cross one dispatch boundary before a new
     *  consumer installs its callback or sends its first command. */
    private suspend fun drainNativeStop() { yield() }

    /** Only the band's own answer takes the stress test off the cadence.
     *  ⚠️ Deliberately NOT gated on `capabilities.stress`. That flag comes from a guessed bit
     *  position in `deviceFuctionData` — the same kind of guess that read `.unsupported` on
     *  real firmware and greyed out a working auto-measure row. The test itself answers
     *  `noFunction` when there is none, and that answer — not a guessed bit — is what sets
     *  `stressUnsupported`. */
    private fun stressDue(at: Instant): Boolean {
        if (stressUnsupported || background) return false
        return !Instant.now().isBefore(at)
    }

    // MARK: heart · the continuous one

    /** Publish every rate the band reports for as long as the stream is open. Returning —
     *  or being cancelled — terminates it, and each `BandService` stops the test when its
     *  flow is cancelled; revoking collection always stops the physical test. */
    private suspend fun consumeHeart() {
        phase = Phase.reaching
        try {
            Band.live.measureHeartRate().first { progress ->
                if (!acceptsSample()) return@first true
                when (progress) {
                    is MeasurementProgress.WaitingForContact -> { phase = Phase.reaching; false }
                    is MeasurementProgress.Contact -> { phase = Phase.live; false }
                    is MeasurementProgress.Measuring -> {
                        val beat = progress.partial?.heartRate
                        if (beat != null && beat > 0) acceptHeart(beat)
                        false
                    }
                    is MeasurementProgress.LostContact -> {
                        // 06 rule 07 ·「我们需要你动一下」, never "you failed". The number goes with
                        // the contact: a rate from before the wrist moved is not a rate now.
                        phase = Phase.noContact
                        hr = null; hrAt = null
                        false
                    }
                    is MeasurementProgress.Finished -> {
                        val result = progress.result
                        if (result is MeasurementResult.HeartRate && result.hr > 0) acceptHeart(result.hr)
                        // The SDK closes its own test after a while. The loop above reopens it.
                        true
                    }
                    is MeasurementProgress.Failed -> true
                }
            }
        } catch (_: NoSuchElementException) {
            // The stream ended on its own; the loop reopens it.
        } catch (e: BandError.Unsupported) {
            // No heart-rate test on this firmware: there is nothing to run, and reopening it
            // every three seconds is a flat band for no reading.
            heartUnsupported = true
            phase = Phase.off
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            BandLog.shared.record("liveReadout.heart", error = e)
            phase = Phase.offline
            sleepSeconds(Cadence.retry)
        }
    }

    // MARK: stress · the inserted one

    private suspend fun acceptHeart(beat: Int) {
        if (!acceptsSample()) return
        val now = Instant.now()
        receivedSamples += 1
        BandTrace.notice("live sample received count=$receivedSamples at=${now.epochSecond} background=$background")
        hr = beat
        hrAt = now
        phase = Phase.live
    }

    private suspend fun readStress() {
        phase = Phase.stress
        // The heart test was stopped a moment ago — the band has not necessarily finished
        // winding the sensor down when this line runs. Insurance, not a fix. It is the band's
        // beat, not the screen's.
        sleepSeconds(Cadence.settle)
        if (!acceptsSample() || background) return
        BandTrace.notice("stress test due · asking the band")
        stressProgress = 0
        try {
            val value = Band.live.measureStress { done ->
                if (acceptsSampleNow()) stressProgress = done
            }
            if (!acceptsSample()) return
            stressAnswered = true
            BandTrace.notice("stress sample received")
            if (value <= 0) return
            stress = value
            stressAt = Instant.now()
        } catch (e: BandError.Unsupported) {
            // The band itself says there is no stress test on this firmware. The only
            // authority on that, and the only thing that stops us asking again.
            BandTrace.notice("stress: this NEXTBODY has no stress test")
            stressUnsupported = true
            stressAnswered = true
        } catch (e: BandError.Busy) {
            // Still winding down, or measuring something of its own. Not a refusal —
            // the backoff asks again rather than waiting out the whole cadence.
            BandTrace.notice("stress ← device busy")
        } catch (e: CancellationException) {
            // The day pull took the band. Not an answer, and not the band's fault.
            BandTrace.notice("stress cut short by a day pull")
        } catch (e: Throwable) {
            // A refusal is an answer: OFF WRIST or LOW BATTERY will say the same thing three
            // seconds from now, and asking again that fast is the band's battery for nothing.
            BandTrace.error("stress ← $e")
            BandLog.shared.record("liveReadout.stress", error = e)
            stressAnswered = true
        } finally {
            stressProgress = null
        }
    }
}
