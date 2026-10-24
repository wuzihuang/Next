package com.nextbody.hoop.features.sport

import android.content.Context
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import com.nextbody.hoop.app.NextBodyApplication
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandConnectionState
import com.nextbody.hoop.band.BandError
import com.nextbody.hoop.band.BandHost
import com.nextbody.hoop.band.BandLiveLifecycle
import com.nextbody.hoop.band.BandLog
import com.nextbody.hoop.band.BandMain
import com.nextbody.hoop.band.BandReadiness
import com.nextbody.hoop.band.BoundBand
import com.nextbody.hoop.band.LiveReadout
import com.nextbody.hoop.band.LiveSessionGate
import com.nextbody.hoop.band.MeasurementProgress
import com.nextbody.hoop.band.MeasurementResult
import com.nextbody.hoop.band.PersonalInfo
import com.nextbody.hoop.band.SportEnergyEvidenceStream
import com.nextbody.hoop.band.SportHeartFreshness
import com.nextbody.hoop.band.SportHeartRateEvidenceStream
import com.nextbody.hoop.band.SportLiveInfo
import com.nextbody.hoop.band.SportMetricAccumulator
import com.nextbody.hoop.band.SportReconnectPolicy
import com.nextbody.hoop.band.SportRecapMath
import com.nextbody.hoop.band.SportSessionLifetime
import com.nextbody.hoop.band.SportSessionRecap
import com.nextbody.hoop.band.SportSessionTaskFence
import com.nextbody.hoop.band.SportStartDisposition
import com.nextbody.hoop.band.SportStartRetry
import com.nextbody.hoop.band.SportWristMath
import com.nextbody.hoop.band.localizedDescription
import com.nextbody.hoop.band.sportRunState
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.data.Profile
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.features.measure.PanelWidgetSpec
import com.nextbody.hoop.features.training.TrainingSportFeed
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.SportModeCatalog
import com.nextbody.hoop.model.SportModeOption
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.swiftFormat
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.services.SportEvidenceQueue
import com.nextbody.hoop.services.SportRecapStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random

/**
 * 14 · LIVE SESSION · the one sport session the band is running, held for as long as it runs.
 * Picked on `SportModeView`; from the tap on, it lives here: home's panel grows over everything
 * (`LiveSessionTakeover`) at once, while the band is still being asked — a refusal folds the
 * screen back with the reason, an answer lets it run.
 *
 * Three numbers and nothing else: the clock (the phone's — `startedAt` is the tap), the heart
 * rate and the burn. Heart rate comes from the band's sport report; energy is a verified kcal
 * counter when available, otherwise a labelled estimate over observed heart-rate intervals.
 */
object LiveSessionStore {
    private const val TAG = "session"

    data class Session(
        val id: UUID,
        val mode: SportModeOption,
        /** The tap — or, once the band has said how long it has been running, the band's own
         *  start: its clock is the record and the screen's clock follows it. */
        val startedAt: Instant,
        /** The band was already running a session and this screen joined it. */
        val joined: Boolean = false,
    )

    /** What the screen may say about the wrist. `offline` is the link, `noContact` the wrist. */
    enum class Wrist { off, reaching, live, noContact, offline, paused }

    var session: Session? by mutableStateOf(null)
        private set
    /** True from the tap until the band has answered the open command. */
    var opening: Boolean by mutableStateOf(false)
        private set
    /** The band refused the mode. The screen folds back and carries this line. */
    var refusal: String? by mutableStateOf(null)
        private set
    var hr: Int? by mutableStateOf(null)
        private set
    var hrAt: Instant? by mutableStateOf(null)
        private set
    private var _wrist by mutableStateOf(Wrist.off)
    var wrist: Wrist
        get() = _wrist
        private set(value) {
            val old = _wrist
            _wrist = value
            // Contact coming or going changes what the notification says, not just its numbers.
            if (old != value) pushIsland(force = true)
        }
    var kcal: Double by mutableStateOf(0.0)
        private set
    var stopping: Boolean by mutableStateOf(false)
        private set
    var errorLine: String? by mutableStateOf(null)
        private set
    var lastRecap: SportSessionRecap? by mutableStateOf(restoreSeedRecap())
        private set
    /** Bumped every second by the freshness clock so readers re-evaluate `heartFreshness`. */
    var freshnessTick: Int by mutableIntStateOf(0)
        private set

    private var metrics = SportMetricAccumulator(weightKg = null, age = null, male = false)
    private var recapBeats = ArrayList<SportRecapMath.Beat>()
    private var recapSegment = 0
    private var heartEvidence = SportHeartRateEvidenceStream()
    private var energyEvidence = SportEnergyEvidenceStream()
    val caloriesAreEstimated: Boolean get() = metrics.calorieSource == SportMetricAccumulator.CalorieSource.estimate
    val hasCalories: Boolean get() = metrics.hasEnergyEvidence
    val energyLabel: String
        get() {
            if (!caloriesAreEstimated) return L("BURNED")
            return if (session?.joined == true) L("ESTIMATE SINCE JOIN") else L("ESTIMATED BURN")
        }
    val energyExplanation: String?
        get() {
            if (!caloriesAreEstimated) return null
            if (!metrics.estimationAvailable) {
                return L("No supported calorie estimate for this activity or profile. Heart rate is still recorded.")
            }
            return L("Active calories over %.0f observed seconds only. Resting energy and missing intervals are excluded.",
                metrics.estimatedSeconds)
        }
    private var openTask: Job? = null
    private var cleanupTask: Job? by mutableStateOf(null)
    private var lifetime: SportSessionLifetime? = null
    private var startDisposition = SportStartDisposition.notIssued
    val cleaningUp: Boolean get() = cleanupTask != null
    /** ⚠️ Owned by the store, not by the screen: the notification is the session with the
     *  phone in a pocket, so the read has to outlive the view. */
    private var wristTask: Job? = null
    private var hrMax = 190
    /** First running report of this seek. Optical lock is timed from here, not the tap. */
    private var seekBeganAt: Instant? = null
    /** Last valid beat in this seek. Survives a zero report so a dropout is not a verdict. */
    private var lastHeartAt: Instant? = null

    /** A heart rate older than this is not the wrist now. */
    val liveWindow: Double = SportMetricAccumulator.liveWindow

    val heartFreshness: SportHeartFreshness.State
        get() {
            @Suppress("UNUSED_VARIABLE") val tick = freshnessTick
            if (session == null || wrist != Wrist.live) return SportHeartFreshness.State.missing
            return SportHeartFreshness.state(receivedAt = hrAt, now = Instant.now())
        }
    val liveHR: Int? get() = if (heartFreshness == SportHeartFreshness.State.missing) null else hr
    val delayedHeartNote: String?
        get() {
            if (wrist != Wrist.live) return null
            return when (heartFreshness) {
                SportHeartFreshness.State.live -> null
                SportHeartFreshness.State.stale -> L("HEART RATE DELAYED")
                SportHeartFreshness.State.missing -> L("WAITING FOR A NEW HEART RATE")
            }
        }
    val averageHR: Int? get() = metrics.averageHR
    val peakHR: Int? get() = metrics.peakHR

    /**
     * Wires the store into the band layer and Training. Call once at startup.
     * Wire: `LiveSessionStore.install()` from Application.onCreate (idempotent).
     */
    fun install() {
        BandHost.liveSession = { LiveSessionGate(hasSession = session != null, opening = opening, cleaningUp = cleaningUp) }
        if (installed) return
        installed = true
        TrainingSportFeed.lastRecap = lastRecap
        TrainingSportFeed.recapView = { recap, close -> SportRecapView(recap, close) }
        TrainingSportFeed.publicationStatus = { SportPublicationStatus() }
        TrainingSportFeed.load = { SportRecapStore.load() }
        TrainingSportFeed.hydrate = { window, day -> Repository.hydrate(window, day, store = DataStore) }
        // Training reads the feed; the records live in SportRecapStore. Mirror them as they move.
        BandMain.scope.launch {
            snapshotFlow { SportRecapStore.recaps }.collect { TrainingSportFeed.recaps = it }
        }
        BandMain.scope.launch {
            snapshotFlow { SportRecapStore.errorLine to SportRecapStore.trainingError }.collect { (e, t) ->
                TrainingSportFeed.errorLine = e
                TrainingSportFeed.trainingError = t
            }
        }
        BandMain.scope.launch {
            snapshotFlow { session != null to opening }.collect { changed() }
        }
    }

    private var installed = false

    private fun changed() {
        BandHost.notifyChanged()
    }

    // MARK: lifecycle

    /** The tap. The session is on from here — the screen grows now, and the band is asked
     *  underneath it. `weightKg` is the latest weigh-in the day knows, for the burn. */
    fun begin(mode: SportModeOption, profile: Profile, weightKg: Double?, authorized: () -> Boolean = { true }) {
        if (!authorized()) return
        if (session != null || cleanupTask != null) return
        if (!(debugFakeWrist || (ConsentStore.granted && SupabaseClient.currentUserIdSnapshot() != null &&
                BoundBand.identifier != null))) {
            refusal = L("Connect your band before starting a session.")
            return
        }
        hrMax = profile.hrMax
        metrics = SportMetricAccumulator(weightKg = weightKg, age = profile.age, male = profile.sexIsMale,
            sportMode = mode.rawValue)
        recapBeats = ArrayList()
        recapSegment = 0
        val sessionID = UUID.randomUUID()
        heartEvidence = SportHeartRateEvidenceStream(sessionID)
        energyEvidence = SportEnergyEvidenceStream(sessionID)
        kcal = 0.0
        hr = null; hrAt = null
        seekBeganAt = null
        lastHeartAt = null
        errorLine = null
        refusal = null
        wrist = Wrist.off
        val owner = SportSessionLifetime(account = SupabaseClient.currentUserIdSnapshot(), binding = BoundBand.identifier)
        lifetime = owner
        startDisposition = SportStartDisposition.notIssued
        opening = !debugFakeWrist
        session = Session(id = sessionID, mode = mode, startedAt = Instant.now())
        changed()
        BandLiveLifecycle.shared.refreshEligibility()
        Log.i(TAG, "session on · ${mode.name} #${mode.rawValue}")

        // The notification goes up with the session, not with the first heart rate.
        SessionActivity.start(sport = mode.name, modeRawValue = mode.rawValue, state = islandState())
        if (debugFakeWrist) {
            wristTask = BandMain.scope.launch { runWrist(owner) }
            return
        }
        openTask = BandMain.scope.launch {
            BandReadiness.shared.awaitNativeIdle()
            if (!(accepts(owner) && authorized())) {
                if (lifetime == owner && currentCoroutineContext().isActive) {
                    opening = false; changed()
                    refusal = L("Connect your band before starting a session.")
                }
                return@launch
            }
            val outcome: Open = LiveReadout.shared.standDown {
                if (!(accepts(owner) && authorized())) return@standDown Open.Refused(CancellationException())
                if (Band.live.state != BandConnectionState.connected) Band.live.reconnectForSport()
                if (!(accepts(owner) && authorized())) return@standDown Open.Refused(CancellationException())
                if (Band.live.state != BandConnectionState.connected) return@standDown Open.Refused(BandError.NotConnected)
                // Every mode starts with this person's current inputs. Never an invented weight.
                if (weightKg != null && weightKg.isFinite() && weightKg > 0 && weightKg < Int.MAX_VALUE &&
                    profile.heightCm.isFinite() && profile.heightCm > 0 && profile.heightCm < Int.MAX_VALUE) {
                    try {
                        Band.live.syncPersonalInfo(PersonalInfo(
                            heightCm = profile.heightCm.roundToInt(), weightKg = weightKg.roundToInt(),
                            birthYear = profile.birthdate.atZone(currentZone()).year,
                            sexIsMale = profile.sexIsMale, targetStep = profile.stepGoal))
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Throwable) {
                        return@standDown Open.Refused(e)
                    }
                    if (!(accepts(owner) && authorized())) return@standDown Open.Refused(CancellationException())
                }
                open(mode, isCurrent = { accepts(owner) && authorized() }, disposition = { startDisposition = it })
            }
            if (!(accepts(owner) && authorized())) {
                if (lifetime == owner && currentCoroutineContext().isActive) {
                    opening = false; changed()
                    refusal = L("Connect your band before starting a session.")
                }
                return@launch
            }
            opening = false
            changed()
            when (outcome) {
                Open.Opened, Open.Joined -> {
                    if (outcome == Open.Joined) {
                        session = session?.copy(joined = true)
                        metrics = SportMetricAccumulator(weightKg = weightKg, age = profile.age, male = profile.sexIsMale)
                    }
                    wristTask = BandMain.scope.launch { LiveReadout.shared.standDown { runWrist(owner) } }
                    val joined = session?.joined ?: false
                    BandMain.scope.launch {
                        Analytics.track("SESSION_START", mapOf("MODE" to mode.rawValue, "NAME" to mode.name, "JOINED" to joined))
                    }
                }
                is Open.Refused -> {
                    Log.e(TAG, "session refused · ${outcome.error}")
                    BandLog.shared.record("session.start", outcome.error)
                    refusal = outcome.error.localizedDescription
                }
            }
        }
    }

    /** Phone actions retain their execution eligibility until the deferred BLE start settles. */
    suspend fun awaitOpening(authorized: () -> Boolean) {
        val openingOwner = lifetime
        openTask?.join()
        if (!authorized() && lifetime == openingOwner) end()
    }

    private suspend fun accepts(owner: SportSessionLifetime): Boolean =
        currentCoroutineContext().isActive && acceptsNow(owner)

    private fun acceptsNow(owner: SportSessionLifetime): Boolean =
        session != null && owner.accepts(current = lifetime, account = SupabaseClient.currentUserIdSnapshot(),
            binding = BoundBand.identifier, consent = debugFakeWrist || ConsentStore.granted)

    private sealed class Open {
        data object Opened : Open()
        data object Joined : Open()
        data class Refused(val error: Throwable) : Open()
    }

    /** Ask the band for the mode. A refusal is most often the band already running a session,
     *  so it is followed by a close and one more try; if the band still says no but reports a
     *  session running, this screen joins that session. */
    private suspend fun open(mode: SportModeOption, isCurrent: suspend () -> Boolean,
                             disposition: (SportStartDisposition) -> Unit): Open {
        try {
            if (!isCurrent()) throw CancellationException()
            startWithBusyRetry(mode, isCurrent, disposition)
            return Open.Opened
        } catch (error: Throwable) {
            if (!isCurrent()) return Open.Refused(CancellationException())
            if (error is BandError.Busy) {
                // Busy can mean another sensor: only an actual running sport report permits joining.
                if (joinRunningSport(isCurrent, disposition)) return Open.Joined
                return Open.Refused(error)
            }
            if (error !is BandError.Rejected) return Open.Refused(error)
            Log.i(TAG, "open refused · closing what the band has and trying once more")
            runCatching { Band.live.stopSportMode(mode.rawValue) }
            try {
                delay(600)
                if (!isCurrent()) throw CancellationException()
                startWithBusyRetry(mode, isCurrent, disposition)
                return Open.Opened
            } catch (second: Throwable) {
                if (!isCurrent()) return Open.Refused(CancellationException())
                if (joinRunningSport(isCurrent, disposition)) return Open.Joined
                return Open.Refused(second)
            }
        }
    }

    private suspend fun joinRunningSport(isCurrent: suspend () -> Boolean,
                                         disposition: (SportStartDisposition) -> Unit): Boolean {
        if (!isCurrent()) return false
        val state = Band.live.sportRunState()
        if (!isCurrent() || !SportStartDisposition.canJoin(state)) return false
        disposition(SportStartDisposition.opened)
        Log.i(TAG, "sport report confirms running · joining existing session")
        return true
    }

    /** The stopped optical stream needs time to release the sensor in firmware. Busy gets one
     *  non-destructive retry after that same pause. */
    private suspend fun startWithBusyRetry(mode: SportModeOption, isCurrent: suspend () -> Boolean,
                                           disposition: (SportStartDisposition) -> Unit) {
        SportStartRetry.perform(
            settle = {
                delay((LiveReadout.Cadence.settle * 1000).toLong())
                if (!isCurrent()) throw CancellationException()
            },
            start = { Band.live.startSportMode(mode.rawValue) },
            isBusy = { it is BandError.Busy },
            disposition = disposition,
        )
    }

    /** Close the mode on the band. Returns the widget the panel takes when the screen folds;
     *  the session itself stays up until `end()` so the fold has numbers to fold. */
    suspend fun stop(authorized: () -> Boolean = { true }): PanelWidgetSpec? {
        if (!authorized()) return null
        val current = session ?: return null
        val stoppingOwner = lifetime ?: return null
        if (stopping) return null
        stopping = true
        errorLine = null
        try {
            val openingTask = openTask
            val readingTask = wristTask
            val prepared = SportSessionTaskFence.prepareStop(owner = stoppingOwner,
                current = { lifetime }, authorized = authorized,
                opening = openingTask, reading = readingTask,
                quiesce = {
                    openTask = null
                    wristTask = null
                    opening = false
                    changed()
                    heartEvidence.interrupted()
                    BandReadiness.shared.awaitNativeIdle()
                },
                retire = { retireStoppedSession(stoppingOwner) })
            if (!prepared) return null
            var closed = true
            try {
                if (!debugFakeWrist && startDisposition.needsCleanup) {
                    val result: Result<Unit> = LiveReadout.shared.standDown {
                        if (!authorized() || lifetime != stoppingOwner ||
                            stoppingOwner.account != SupabaseClient.currentUserIdSnapshot() ||
                            stoppingOwner.binding != BoundBand.identifier) {
                            return@standDown Result.failure(CancellationException())
                        }
                        try { Band.live.stopSportMode(current.mode.rawValue); Result.success(Unit) }
                        catch (e: CancellationException) { throw e }
                        catch (e: Throwable) { Result.failure(e) }
                    }
                    result.getOrThrow()
                    if (lifetime == stoppingOwner) startDisposition = SportStartDisposition.notIssued
                }
            } catch (error: Throwable) {
                // A refused stop is said, not hidden: the band may still be timing. The session
                // ends on the phone either way — a screen that cannot be left is worse.
                if (lifetime != stoppingOwner) return null
                closed = false
                errorLine = error.localizedDescription
                BandLog.shared.record("session.stop", error)
            }
            if (lifetime != stoppingOwner) return null
            if (!authorized()) {
                retireStoppedSession(stoppingOwner)
                return null
            }
            val now = Instant.now()
            val sec = ChronoUnit.SECONDS.between(current.startedAt, now).toInt()
            val average = averageHR ?: 0
            val calories = kcal.roundToInt()
            rememberRecap(current, sec)
            if (!debugFakeWrist) {
                val generation = Repository.sessionGeneration
                BandMain.scope.launch {
                    if (stoppingOwner.account != SupabaseClient.currentUserIdSnapshot() ||
                        generation != Repository.sessionGeneration) return@launch
                    Repository.settleAfterSport()
                }
            }
            val energySec = metrics.estimatedSeconds.roundToInt()
            BandMain.scope.launch {
                Analytics.track("SESSION_END", mapOf("MODE" to current.mode.rawValue, "SEC" to sec,
                    "AVG_HR" to average, "KCAL" to calories, "ENERGY_SEC" to energySec, "CLOSED" to closed))
            }
            return summaryWidget(current, sec, closed)
        } finally {
            if (lifetime == stoppingOwner || lifetime == null) stopping = false
        }
    }

    private suspend fun retireStoppedSession(owner: SportSessionLifetime) {
        if (lifetime != owner) return
        end()
        cleanupTask?.join()
    }

    /** The screen has folded back into the panel. Nothing of the session survives here. */
    fun end() {
        if (cleanupTask != null) return
        SessionActivity.end(islandState())
        val endingMode = session?.mode
        val endingOwner = lifetime
        val endingGeneration = Repository.sessionGeneration
        lifetime = null
        heartEvidence.interrupted()
        energyEvidence.interrupted()
        val readingTask = wristTask
        val openingTask = openTask
        readingTask?.cancel()
        openingTask?.cancel()
        wristTask = null
        openTask = null
        cleanupTask = BandMain.scope.launch {
            SportSessionTaskFence.cancelAndWait(openingTask, readingTask)
            BandReadiness.shared.awaitNativeIdle()
            LiveReadout.shared.standDown {
                // end can also dismiss a refused/in-flight start without going through stop.
                if (lifetime == null && startDisposition.needsCleanup && !debugFakeWrist && endingMode != null &&
                    endingOwner?.account == SupabaseClient.currentUserIdSnapshot() &&
                    endingOwner?.binding == BoundBand.identifier) {
                    try { Band.live.stopSportMode(endingMode.rawValue) }
                    catch (e: CancellationException) { throw e }
                    catch (e: Throwable) { BandLog.shared.record("session.cleanup", e) }
                }
            }
            cleanupTask = null
            changed()
            BandLiveLifecycle.shared.refreshEligibility()
            if (!debugFakeWrist && endingOwner?.account == SupabaseClient.currentUserIdSnapshot() &&
                endingGeneration == Repository.sessionGeneration) {
                Repository.settleAfterSport()
            }
        }
        session = null
        stopping = false
        opening = false
        wrist = Wrist.off
        hr = null; hrAt = null
        seekBeganAt = null
        lastHeartAt = null
        changed()
    }

    // MARK: the wrist

    /** The band's sport report first; if it says nothing for a while, the heart test — which
     *  the firmware answers `busy` while a mode is open, in which case the report is tried
     *  again. Cancelling ends whichever is open (F1 rule 05). */
    private suspend fun runWrist(owner: SportSessionLifetime) {
        if (!accepts(owner)) return
        // Receipt-driven updates render every new beat immediately. This clock only ages a
        // silent stream, including the notification when no callback arrives at all.
        val freshnessClock = BandMain.scope.launch {
            var previous: SportHeartFreshness.State? = null
            while (isActive) {
                delay(1_000)
                if (!acceptsNow(owner)) return@launch
                freshnessTick += 1
                val freshness = heartFreshness
                pushIsland(force = previous != freshness)
                previous = freshness
            }
        }
        try {
            var reconnectFailures = 0
            while (accepts(owner)) {
                if (debugFakeWrist) { fakeWrist(); continue }
                if (Band.live.state != BandConnectionState.connected) {
                    interruptMetrics()
                    wrist = Wrist.offline
                    Log.i(TAG, "session reconnect begin")
                    Band.live.reconnectForSport()
                    if (!accepts(owner)) break
                    if (Band.live.state != BandConnectionState.connected) {
                        reconnectFailures += 1
                        delay((SportReconnectPolicy.delay(reconnectFailures) * 1000).toLong())
                    } else {
                        reconnectFailures = 0
                        Log.i(TAG, "session reconnect ready")
                    }
                    continue
                }
                // The open command has to land before the band has anything to report.
                if (opening) { delay(300); continue }
                val reported = consumeReport(owner)
                if (!currentCoroutineContext().isActive) break
                if (!reported) consumeHeart(owner)
            }
        } finally {
            freshnessClock.cancel()
            wrist = Wrist.off
        }
    }

    /** The band's own report. Returns true if it said anything at all. */
    private suspend fun consumeReport(owner: SportSessionLifetime): Boolean {
        interruptMetrics()
        seekBeganAt = Instant.now()
        wrist = Wrist.reaching
        var heard = false
        try {
            Band.live.sportLiveInfo().collect { info ->
                if (!accepts(owner)) throw StopReport()
                heard = true
                accept(info)
            }
        } catch (e: StopReport) {
            // The owner changed; nothing more to read.
        }
        if (currentCoroutineContext().isActive) {
            interruptMetrics()
            Log.i(TAG, if (heard) "sport report went quiet" else "no sport report from this firmware")
        }
        return heard
    }

    private class StopReport : CancellationException("report stopped")

    private suspend fun consumeHeart(owner: SportSessionLifetime) {
        seekBeganAt = Instant.now()
        wrist = Wrist.reaching
        try {
            Band.live.measureHeartRate().collect { progress ->
                if (!accepts(owner)) throw StopReport()
                when (progress) {
                    MeasurementProgress.WaitingForContact -> { interruptMetrics(); wrist = Wrist.reaching }
                    MeasurementProgress.Contact -> wrist = Wrist.live
                    is MeasurementProgress.Measuring -> {
                        val beat = progress.partial?.heartRate
                        if (beat != null && beat > 0) accept(SportLiveInfo(heartRate = beat))
                    }
                    MeasurementProgress.LostContact -> { interruptMetrics(); wrist = Wrist.noContact }
                    is MeasurementProgress.Finished -> {
                        val r = progress.result
                        if (r is MeasurementResult.HeartRate && r.hr > 0) accept(SportLiveInfo(heartRate = r.hr))
                        throw StopReport()
                    }
                    is MeasurementProgress.Failed -> throw StopReport()
                }
            }
        } catch (e: StopReport) {
            // Finished, failed or the owner changed.
        } catch (e: CancellationException) {
            throw e
        } catch (e: BandError.Busy) {
            // The mode holds the sensor and the report is the only way at it. Back to the
            // report after a pause — asking every second is the band's battery for nothing.
            Log.i(TAG, "heart test busy under the sport mode")
            wrist = Wrist.off
            delay(6_000)
        } catch (e: BandError.Unsupported) {
            wrist = Wrist.off
            delay(30_000)
        } catch (e: Throwable) {
            BandLog.shared.record("session.heart", e)
            wrist = Wrist.offline
            delay(3_000)
        }
    }

    private fun accept(info: SportLiveInfo) {
        if (!metrics.canAccept(info.receivedAt)) return
        if (!(info.runState == null || info.runState == 1 || info.runState == 2)) {
            interruptMetrics()
            wrist = Wrist.reaching
            return
        }
        val now = Instant.now()
        val tz = ZoneId.systemDefault().id
        val owner = lifetime
        val account = owner?.account
        if (!debugFakeWrist && owner != null && acceptsNow(owner) && account != null) {
            val sample = energyEvidence.accept(at = info.receivedAt, runState = info.runState,
                sportMode = if (session?.joined == true) null else session?.mode?.rawValue, timeZone = tz)
            if (sample != null) {
                try { SportEvidenceQueue.enqueue(sample, account) } catch (e: Throwable) {
                    energyEvidence.interrupted()
                    BandLog.shared.record("sport energy evidence persistence", e)
                    errorLine = L("Energy evidence could not be saved on this phone.")
                }
            }
            val heart = heartEvidence.accept(at = info.receivedAt, heartRate = info.heartRate,
                runState = info.runState, sportMode = if (session?.joined == true) null else session?.mode?.rawValue,
                timeZone = tz)
            if (heart != null) {
                try { SportEvidenceQueue.enqueue(heart, account) } catch (e: Throwable) {
                    // End continuity after a failed local commit.
                    heartEvidence.interrupted()
                    BandLog.shared.record("sport evidence persistence", e)
                    errorLine = L("Heart-rate evidence could not be saved on this phone.")
                }
            }
        }
        // The band's clock is the record: the first time it says how long it has run, the
        // screen's clock is set to it — and stays with it if the two drift apart.
        val dur = info.durationSec
        val s = session
        if (dur != null && s != null) {
            val bandStart = info.receivedAt.minusSeconds(dur.toLong())
            if (abs(ChronoUnit.MILLIS.between(s.startedAt, bandStart)) > 3_000) session = s.copy(startedAt = bandStart)
        }
        if (seekBeganAt == null) seekBeganAt = now
        metrics = metrics.accepting(info)
        hr = metrics.heartRate
        hrAt = if (metrics.heartRate == null) null else info.receivedAt
        kcal = metrics.kcal
        if (hr != null) lastHeartAt = now
        val beat = info.heartRate
        if (beat != null && beat in 1..250 && (info.runState == null || info.runState == 1)) {
            recapBeats.add(SportRecapMath.Beat(at = info.receivedAt, bpm = beat, segment = recapSegment))
        } else {
            recapSegment += 1
        }
        if (metrics.calorieCorrection != null) Log.i(TAG, "session energy corrected by cumulative device report")
        // A zero on the sport report is the sensor still locking, not a loose strap.
        wrist = wristFrom(SportWristMath.face(
            runState = info.runState, heartRate = hr, hadHeart = lastHeartAt != null,
            seekingFor = ChronoUnit.MILLIS.between(seekBeganAt ?: now, now) / 1000.0,
            silentFor = lastHeartAt?.let { ChronoUnit.MILLIS.between(it, now) / 1000.0 } ?: Double.MAX_VALUE))
        pushIsland()
    }

    private fun wristFrom(face: SportWristMath.Face): Wrist = when (face) {
        SportWristMath.Face.reaching -> Wrist.reaching
        SportWristMath.Face.live -> Wrist.live
        SportWristMath.Face.noContact -> Wrist.noContact
        SportWristMath.Face.paused -> Wrist.paused
    }

    private fun interruptMetrics() {
        recapSegment += 1
        heartEvidence.interrupted()
        energyEvidence.interrupted()
        metrics = metrics.interrupted()
        hr = null; hrAt = null
        lastHeartAt = null
        seekBeganAt = null
    }

    // MARK: the notification

    /** 0…1 · where the heart sits between rest and the profile's maximum. The screen and the
     *  notification read the same number. */
    val effort: Double
        get() {
            val beat = liveHR ?: return 0.0
            val span = max(60, hrMax - 60).toDouble()
            return min(1.0, max(0.0, (beat - 60) / span))
        }

    /** What the ongoing notification is told right now. */
    private fun islandState(): SessionActivity.ContentState = SessionActivity.ContentState(
        heartRate = liveHR,
        kcal = kcal.roundToInt(),
        startedAt = session?.startedAt ?: Instant.now(),
        live = heartFreshness == SportHeartFreshness.State.live && liveHR != null,
        effort = effort,
        note = islandNote,
        energyEstimated = caloriesAreEstimated,
        energyAvailable = hasCalories,
    )

    /** One short line, or nothing while it is simply running. */
    private val islandNote: String?
        get() {
            if (opening) return L("OPENING ON THE BAND")
            delayedHeartNote?.let { return it }
            return when (wrist) {
                Wrist.live -> if (session?.joined == true && caloriesAreEstimated) L("ESTIMATE SINCE JOIN") else null
                Wrist.reaching -> L("READING HEART RATE")
                Wrist.noContact -> L("NO CONTACT · TIGHTEN THE BAND")
                Wrist.offline -> L("BAND OFFLINE · STILL TIMING")
                Wrist.paused -> L("PAUSED ON THE BAND")
                Wrist.off -> L("TIMING · THE WRIST IS NOT BEING READ")
            }
        }

    private fun pushIsland(force: Boolean = false) {
        if (session == null) return
        SessionActivity.update(islandState(), force)
    }

    // MARK: the fold

    /** The line the panel carries when the band refused the mode: no session, one sentence. */
    fun refusalWidget(s: Session, line: String): PanelWidgetSpec = PanelWidgetSpec(
        type = PanelWidgetSpec.Type.text, title = L("SPORT MODE"), tag = PanelWidgetSpec.Tag.move,
        sentence = L("The band did not open %@. Nothing was started.", s.mode.displayName),
        footer = line.uppercase(), action = null, accentOverride = NB.ember1)

    private fun summaryWidget(s: Session, seconds: Int, closed: Boolean): PanelWidgetSpec {
        val minutes = max(1, seconds / 60)
        val hero = if (seconds >= 3600) swiftFormat("%dH%02dM", seconds / 3600, (seconds % 3600) / 60) else "$minutes MIN"
        val recap = lastRecap
        val avg = recap?.avgHR?.toString() ?: averageHR?.toString() ?: Fmt.dash
        val peak = recap?.peakHR?.toString() ?: peakHR?.toString() ?: Fmt.dash
        val burned = if (hasCalories) (if (caloriesAreEstimated) "≈" else "") + kcal.roundToInt() else Fmt.dash
        val conclusion = recap?.let { L(it.conclusion) } ?: L("No heart-rate record.")
        val sentence = L("%d min · avg %@ bpm · %@ kcal", minutes, avg, burned)
        return PanelWidgetSpec(
            type = PanelWidgetSpec.Type.workout,
            title = L("SESSION · %@", s.mode.displayName),
            tag = PanelWidgetSpec.Tag.move,
            sentence = conclusion + " · " + if (s.joined && caloriesAreEstimated) sentence + " · " + L("ESTIMATE SINCE JOIN") else sentence,
            footer = if (closed) L("SAVED ON THE BAND · %@ → %@", Fmt.clock(s.startedAt), Fmt.clock(Instant.now()))
                else L("BAND DID NOT CLOSE IT · CHECK THE WRIST"),
            action = null,
            hero = hero,
            accentOverride = if (closed) null else NB.ember1,
            data = PanelWidgetSpec.Data.Rows(listOf(
                PanelWidgetSpec.RowItem(L("AVG HR"), avg, spark = recap?.curve?.takeIf { it.size > 1 }),
                PanelWidgetSpec.RowItem(L("PEAK"), peak),
                PanelWidgetSpec.RowItem(energyLabel, "$burned KCAL"),
                PanelWidgetSpec.RowItem(L("AEROBIC"), recap?.takeIf { it.hasZones }?.let { "${it.aerobicMinutes} MIN" } ?: Fmt.dash),
                PanelWidgetSpec.RowItem(L("ANAEROBIC"), recap?.takeIf { it.hasZones }?.let { "${it.anaerobicMinutes} MIN" } ?: Fmt.dash),
            )),
        )
    }

    private fun rememberRecap(s: Session, seconds: Int) {
        val data = DataStore
        val rest = data.today.nightInputs?.rhr?.roundToInt()
        val math = SportRecapMath.recap(beats = recapBeats, restHR = rest, maxHR = hrMax, seconds = seconds)
        val loadBefore = if (Band.allowsSeed) data.today.trainingLoad else null
        if (Band.allowsSeed) data.applySeedSessionLoad(delta = math.loadDelta, zones = math.zoneMinutes)
        val recap = SportSessionRecap(
            title = s.mode.displayName,
            startedAt = s.startedAt,
            endedAt = Instant.now(),
            seconds = seconds,
            avgHR = math.avgHR,
            peakHR = math.peakHR,
            kcal = kcal,
            caloriesEstimated = caloriesAreEstimated,
            curve = math.curve,
            zoneMinutes = math.zoneMinutes,
            aerobicMinutes = math.aerobicMinutes,
            anaerobicMinutes = math.anaerobicMinutes,
            conclusion = math.conclusion.raw,
            sessionID = s.id,
            ownerUserID = lifetime?.account,
            loadBefore = loadBefore,
            loadAfter = if (Band.allowsSeed) data.today.trainingLoad else null,
            curvePoints = math.curvePoints, observedSeconds = math.observedSeconds,
            hasCalories = hasCalories, restHR = rest, maxHR = hrMax,
            energyObservedSeconds = if (caloriesAreEstimated) metrics.estimatedSeconds else null)
        lastRecap = recap
        TrainingSportFeed.lastRecap = recap
        if (!Band.allowsSeed) {
            SportRecapStore.record(recap)
            return
        }
        runCatching {
            prefs()?.edit()?.putString(RECAP_KEY, recap.toJson().toString())?.apply()
        }
    }

    private const val RECAP_KEY = "nb.lastSportRecap"

    private fun prefs() = runCatching {
        NextBodyApplication.context.getSharedPreferences("nb", Context.MODE_PRIVATE)
    }.getOrNull()

    private fun restoreSeedRecap(): SportSessionRecap? {
        if (!Band.allowsSeed) return null
        val raw = prefs()?.getString(RECAP_KEY, null) ?: return null
        return runCatching { SportSessionRecap.fromJson(JSONObject(raw)) }.getOrNull()
    }

    // MARK: DEBUG · a session on an emulator

    /** `-e NB_DEBUG_SESSION 1` (or a mode number) opens a session on home with no band, and
     *  plays a wrist that climbs to a working rate. */
    val debugFakeWrist: Boolean get() = Band.allowsSeed && DebugEnv["NB_DEBUG_SESSION"] != null

    fun debugAutoStart(profile: Profile, weightKg: Double?) {
        val raw = DebugEnv["NB_DEBUG_SESSION"] ?: return
        if (!Band.allowsSeed || session != null) return
        val mode = SportModeCatalog.modes.firstOrNull { "${it.rawValue}" == raw }
            ?: SportModeCatalog.modes.first { it.rawValue == 1 }
        begin(mode, profile, weightKg)
        if (DebugEnv["NB_DEBUG_SESSION_OPEN"] == "1") { opening = true; changed() }
        val refuse = DebugEnv["NB_DEBUG_SESSION_REFUSE"]
        if (!refuse.isNullOrEmpty()) refusal = if (refuse == "1") L("The band refused this mode.") else refuse
    }

    private suspend fun fakeWrist() {
        if (!Band.allowsSeed) return
        val pin = DebugEnv["NB_DEBUG_SESSION_WRIST"]
        if (!pin.isNullOrEmpty()) {
            wrist = when (pin) {
                "off" -> Wrist.off
                "nocontact" -> Wrist.noContact
                "offline" -> Wrist.offline
                "paused" -> Wrist.paused
                else -> Wrist.reaching
            }
            while (currentCoroutineContext().isActive && session != null) delay(30_000)
            return
        }
        wrist = Wrist.reaching
        delay(1_000)
        var beat = 96.0
        while (currentCoroutineContext().isActive && session != null) {
            val t = ChronoUnit.MILLIS.between(session?.startedAt ?: Instant.now(), Instant.now()) / 1000.0
            val target = 118 + 40 * (1 - exp(-t / 60)) + 8 * sin(t / 9)
            beat += (target - beat) * 0.3 + Random.nextDouble(-1.5, 1.5)
            accept(SportLiveInfo(heartRate = beat.roundToInt()))
            delay(1_000)
        }
    }
}
