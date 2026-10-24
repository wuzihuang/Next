package com.nextbody.hoop.band

import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.LiveVitals
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.OvernightOxygenPoint
import com.nextbody.hoop.model.SleepHRVPoint
import com.nextbody.hoop.model.SleepInterval
import com.nextbody.hoop.model.SleepRespirationPoint
import com.nextbody.hoop.model.SleepSummary
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.services.SupabaseFailure
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

/**
 * The services OriginDataSync reaches outside the band layer, behind one seam so JVM tests can
 * swap them. Defaults are the real ports: services.Repository, services.HomeSnapshot and the
 * sport feature's LiveSessionStore.
 */
object OriginSyncPorts {
    interface RepositoryPort {
        /** `Repository.shared.settleNow(days:)`. */
        suspend fun settleNow(days: Int)
        suspend fun load(days: Int, endingAt: UserDay, into: DataStore)
        suspend fun loadSleepScores(days: Int, endingAt: UserDay, into: DataStore)
        suspend fun markDeviceSynced(at: Instant)
        suspend fun waitForEvidencePublication()
        val deviceId: String?
    }

    interface HomeSnapshotPort {
        /** `HomeSnapshot.saveBandObservations(day:samples:sleep:userId:)`. Throws on failure. */
        fun saveBandObservations(day: UserDay, samples: List<VitalSample>, sleep: SleepSummary?, userId: String)
    }

    @Volatile var repository: RepositoryPort = object : RepositoryPort {
        private val r get() = com.nextbody.hoop.services.Repository
        override suspend fun settleNow(days: Int) { r.settleNow(days) }
        override suspend fun load(days: Int, endingAt: UserDay, into: DataStore) { r.load(days, endingAt, into) }
        override suspend fun loadSleepScores(days: Int, endingAt: UserDay, into: DataStore) { r.loadSleepScores(days, endingAt, into) }
        override suspend fun markDeviceSynced(at: Instant) = r.markDeviceSynced(at)
        override suspend fun waitForEvidencePublication() { r.waitForEvidencePublication() }
        override val deviceId: String? get() = r.deviceId
    }

    @Volatile var homeSnapshot: HomeSnapshotPort = object : HomeSnapshotPort {
        override fun saveBandObservations(day: UserDay, samples: List<VitalSample>, sleep: SleepSummary?, userId: String) =
            com.nextbody.hoop.services.HomeSnapshot.saveBandObservations(day, samples, sleep, userId)
    }

    /** `LiveSessionStore.shared.session != nil`. */
    @Volatile var liveSessionActive: () -> Boolean = { com.nextbody.hoop.features.sport.LiveSessionStore.session != null }
}

/**
 * The shared refresh reads the current user day and the previous day. User days start
 * at local midnight (ADR 0020); sleep still belongs to its recorded wake day.
 */
class OriginDataSync(private val band: BandService = Band.live) {
    private data class DatedPoint(
        val calendarDay: Instant,
        val readStartedAt: Instant,
        val readAt: Instant,
        val point: OriginPoint,
    )

    /** Internal per-day outcome. Only the shared refresh combines days into a caller result. */
    private var lastOutcome = "none"
    private var pendingNetwork: Deferred<Unit>? = null
    private var pendingRun: PendingRun? = null

    private data class PendingRun(
        var startedAt: Instant,
        var requested: Int,
        var returned: Int,
        var filed: Boolean = false,
    )

    private suspend fun awaitPendingNetwork() {
        pendingNetwork?.let {
            it.await()
            pendingNetwork = null
        }
    }

    /** Pull a user day and store it. Returns how many observations changed on the server.
     *  Settlement happens after the day returns, so today can be published before yesterday. */
    private suspend fun sync(day: UserDay, scope: BandRefreshCoordinator.Scope, store: DataStore): Int {
        val points = publishDay(day, scope, store)
        filePendingRun(userId = scope.account)
        return points
    }

    private suspend fun publishDay(day: UserDay, scope: BandRefreshCoordinator.Scope, store: DataStore): Int {
        lastOutcome = "failed"
        BandSyncActivity.shared.show(BandSyncProgress.Stage.reading)
        val now = Instant.now()
        var checkpointAt = now
        fun checkpoint(segment: String) {
            val at = Instant.now()
            BandTrace.record("sync.segment", mapOf(
                "segment" to segment, "durationSeconds" to BandTime.interval(at, checkpointAt).toString(),
                "day" to day.key))
            checkpointAt = at
        }
        // ⚠️ raw_samples.user_id is NOT NULL and its insert policy checks it against
        // auth.uid(), exactly like sync_runs and sleep_nights below. Every row names its owner.
        if (refreshState().rejection(expected = scope) != null) return 0
        val userId = scope.account
        val deviceKey = scope.binding
        val outcomeKey = historyOutcomeKey(scope, day)
        // Archive/local failures are not all represented by publication domain receipts.
        // A crash or early exit must leave this date as repair work on the next refresh.
        BandPrefs.setString(outcomeKey, "failed")
        try {
            return publishDayBody(day, scope, store, now, userId, deviceKey, ::checkpoint)
        } finally {
            if (refreshState().rejection(expected = scope) == null) BandPrefs.setString(outcomeKey, lastOutcome)
        }
    }

    private suspend fun publishDayBody(
        day: UserDay, scope: BandRefreshCoordinator.Scope, store: DataStore, now: Instant,
        userId: String, deviceKey: String, checkpoint: (String) -> Unit,
    ): Int {
        val zone = ZoneId.systemDefault()
        val dayEnd = day.start.atZone(zone).plusDays(1).toInstant()
        val readEnd = minOf(dayEnd, now)
        var originReadEnd = readEnd
        var originSnapshotCoversDay = true
        val points = mutableListOf<DatedPoint>()
        /** Every measured HRV tick of this user day, by instant. */
        val hrvTicks = HashMap<Instant, Double>()
        val invalidHrvTicks = HashSet<Instant>()
        val hrvMinuteTicks = HashMap<Instant, Double>()
        val invalidHrvMinutes = HashSet<Instant>()
        var hrvMinuteReadComplete = false
        val temperatureTicks = HashMap<Instant, Double>()
        var auxiliaryUploaded = true
        var hrvStatus = BandDomainReadStatus.complete
        var temperatureStatus = BandDomainReadStatus.complete
        var oxygenStatus = BandDomainReadStatus.complete
        val oxygenTicks = HashMap<Instant, Int>()
        val respirationTicks = HashMap<Instant, Double>()
        val healthPages = HashMap<Int, BandHealthData>()
        var nightAuxiliary: List<VitalSample> = emptyList()
        var opticalStatus = BandDomainReadStatus.complete
        val opticalTicks = HashMap<Instant, Double>()
        var opticalDroppedZeros = 0
        val rrRows = mutableListOf<Map<String, Any?>>()
        val domainStates = mutableListOf<BandDomainSyncState>()
        var pagesReturned = 0
        var publishHRV = false
        var publishTemperature = false
        var publishOxygen = false
        val wanted = pages(day, now, zone)
        pendingRun = PendingRun(startedAt = Instant.now(), requested = wanted.size, returned = 0)
        try {
            // The bar's movement inside this day. Each checkpoint is a band command that has
            // actually come back, not a tween.
            var stagesDone = 0
            val stageCount = wanted.size * 2 + 2
            fun stage() {
                stagesDone += 1
                BandSyncActivity.shared.within(percent = min(99, 100 * stagesDone / stageCount))
            }

            for (offset in wanted) {
                if (OriginSyncPorts.liveSessionActive() || BandLiveLifecycle.shared.hasExclusiveOperation) {
                    lastOutcome = "failed"; return 0
                }
                val calendarDay = BandTime.startOfDay(now.atZone(zone).minusDays(offset.toLong()).toInstant(), zone)
                val page: OriginDataPage = try {
                    val p = BandReadiness.read(account = userId, binding = deviceKey) {
                        band.readOriginPage(calendarDay = calendarDay)
                    }
                    pagesReturned += 1
                    stage()
                    val end = OriginObservationPolicy.coverageEnd(dayStart = day.start, dayEnd = dayEnd,
                        readStartedAt = now, snapshotStartedAt = p.readStartedAt)
                    if (end != null) originReadEnd = minOf(originReadEnd, end) else originSnapshotCoversDay = false
                    p
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    BandSyncActivity.shared.failed(e)
                    BandLog.shared.record("readOriginData($offset)", error = e)
                    OriginDataPage(points = emptyList(), readStartedAt = now, readCompletedAt = now)
                }
                if (band.state != BandConnectionState.connected) { lastOutcome = "failed"; return 0 }
                // Preserve the actual native snapshot clock through cache reuse and retries.
                val originReadAt = page.readCompletedAt
                val health: BandHealthData = try {
                    BandReadiness.read(account = userId, binding = deviceKey) { band.readHealthData(dayOffset = offset) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    auxiliaryUploaded = false
                    BandSyncActivity.shared.failed(e)
                    BandLog.shared.record("readHealthData($offset)", error = e)
                    BandHealthData(temperatures = emptyList(), hrv = emptyList(), oxygen = emptyList(),
                        temperatureStatus = BandDomainReadStatus.failed, hrvStatus = BandDomainReadStatus.failed,
                        oxygenStatus = BandDomainReadStatus.failed, opticalStatus = BandDomainReadStatus.failed)
                }
                healthPages[offset] = health
                publishHRV = publishHRV || health.publishesHRV
                publishTemperature = publishTemperature || health.publishesTemperature
                publishOxygen = publishOxygen || health.publishesOxygen
                stage()
                if (health.respirationStatus == BandDomainReadStatus.failed) auxiliaryUploaded = false
                if (health.hrvStatus != BandDomainReadStatus.complete && hrvStatus != BandDomainReadStatus.failed) hrvStatus = health.hrvStatus
                if (health.temperatureStatus != BandDomainReadStatus.complete && temperatureStatus != BandDomainReadStatus.failed) temperatureStatus = health.temperatureStatus
                if (health.oxygenStatus != BandDomainReadStatus.complete && oxygenStatus != BandDomainReadStatus.failed) oxygenStatus = health.oxygenStatus
                if (health.opticalStatus != BandDomainReadStatus.complete && opticalStatus != BandDomainReadStatus.failed) opticalStatus = health.opticalStatus
                if (health.hrvStatus == BandDomainReadStatus.failed || health.temperatureStatus == BandDomainReadStatus.failed ||
                    health.oxygenStatus == BandDomainReadStatus.failed || health.opticalStatus == BandDomainReadStatus.failed) auxiliaryUploaded = false
                fun instant(time: String) = HealthSampleMapping.instant(time = time, calendarDay = calendarDay, zone = zone)
                for ((time, value) in HealthSampleMapping.hrvByMinute(health.hrv)) {
                    val ts = instant(time) ?: continue
                    if (ts > now) continue
                    hrvMinuteTicks[ts] = value
                }
                for (time in HealthSampleMapping.invalidHRVMinutes(health.hrv)) {
                    val ts = instant(time) ?: continue
                    if (ts > now) continue
                    invalidHrvMinutes.add(ts)
                }
                for (sample in health.hrv) {
                    if (sample.rrMilliseconds.isEmpty()) continue
                    val ts = instant(sample.time) ?: continue
                    if (ts < day.start || ts >= dayEnd || ts > now) continue
                    rrRows.add(mapOf("ts" to iso(ts), "rr_ms" to sample.rrMilliseconds,
                        "rr_indices" to sample.rrValidIndices))
                }
                for (sample in health.temperatures) {
                    val ts = instant(sample.time) ?: continue
                    if (ts < day.start || ts >= dayEnd || ts > now) continue
                    temperatureTicks[ts] = sample.celsius
                }
                val temperatures = health.temperatures.groupBy { it.time }.mapValues { it.value.last().celsius }
                // The band measures HRV every ten minutes, all day — not only at night. Both
                // domains are read from the same page, so this is where they are joined.
                val hrvBySlot = HealthSampleMapping.hrvBySlot(health.hrv)
                for (slot in HealthSampleMapping.invalidHRVSlots(health.hrv)) {
                    val ts = instant(slot) ?: continue
                    if (ts < day.start || ts >= dayEnd || ts > now) continue
                    invalidHrvTicks.add(ts)
                }
                // Kept with their instants as well: a tick stored by an earlier sync cannot be
                // re-inserted carrying its HRV, so those rows are filled in afterwards.
                for ((slot, value) in hrvBySlot) {
                    val ts = instant(slot) ?: continue
                    if (ts < day.start || ts >= dayEnd) continue
                    hrvTicks[ts] = value
                }
                for (sample in health.oxygen) {
                    val ts = instant(sample.time) ?: continue
                    if (ts > now) continue
                    oxygenTicks[ts] = sample.percent
                }
                for (sample in health.respiration) {
                    val ts = instant(sample.time) ?: continue
                    if (ts > now) continue
                    respirationTicks[ts] = sample.breathsPerMinute
                }
                opticalDroppedZeros += health.opticalDroppedZeros
                for (sample in health.optical) {
                    val ts = instant(sample.time) ?: continue
                    if (ts < day.start || ts >= dayEnd || ts > now) continue
                    opticalTicks[ts] = sample.optical
                }
                points.addAll(page.points.map { point ->
                    DatedPoint(calendarDay = calendarDay, readStartedAt = page.readStartedAt, readAt = originReadAt,
                        point = OriginPoint(
                            time = point.time, heart = point.heart, step = point.step, cal = point.cal,
                            distance = point.distance, met = VitalSample.validatedMET(point.met),
                            temperature = temperatures[clock(point.time)],
                            hrv = hrvBySlot[clock(point.time)],
                            stress = point.stress, sleepState = point.sleepState))
                })
            }

            // Read every real sync: an earlier sleep record may have extended after the user woke.
            var night: SleepNight? = null
            var sleepStatus = BandDomainReadStatus.notCollected
            var sleepRow: Map<String, Any?>? = null
            try {
                night = BandReadiness.read(account = userId, binding = deviceKey) {
                    band.readSleep(dayOffset = wanted.maxOrNull() ?: 0)
                }
                stage()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                sleepStatus = BandDomainReadStatus.failed
                auxiliaryUploaded = false
                BandSyncActivity.shared.failed(e)
                BandLog.shared.record("readSleep(${wanted.maxOrNull() ?: 0})", error = e)
            }
            // Sleep owns its recorded clock, including pre-04:00 and previous calendar pages.
            // Reuse already-read pages and fetch any missing pages serially on the BLE queue.
            nightWindow(day, night, store)?.let { (start, wake) ->
                val requiredHrvPages = nightPageOffsets(start, wake, now, zone)
                for (offset in requiredHrvPages) {
                    val health: BandHealthData = healthPages[offset] ?: try {
                        BandReadiness.read(account = userId, binding = deviceKey) {
                            band.readHealthData(dayOffset = offset)
                        }.also { healthPages[offset] = it }
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Throwable) {
                        hrvStatus = BandDomainReadStatus.failed
                        oxygenStatus = BandDomainReadStatus.failed
                        auxiliaryUploaded = false
                        BandLog.shared.record("read sleep health page($offset)", error = e)
                        continue
                    }
                    if (health.hrvStatus != BandDomainReadStatus.complete && hrvStatus != BandDomainReadStatus.failed) hrvStatus = health.hrvStatus
                    if (health.oxygenStatus != BandDomainReadStatus.complete && oxygenStatus != BandDomainReadStatus.failed) oxygenStatus = health.oxygenStatus
                    if (health.hrvStatus == BandDomainReadStatus.failed || health.oxygenStatus == BandDomainReadStatus.failed ||
                        health.respirationStatus == BandDomainReadStatus.failed) auxiliaryUploaded = false
                    val calendarDay = BandTime.startOfDay(now.atZone(zone).minusDays(offset.toLong()).toInstant(), zone)
                    fun inNight(time: String): Instant? {
                        val ts = HealthSampleMapping.instant(time = time, calendarDay = calendarDay, zone = zone) ?: return null
                        return if (ts >= start && ts < wake) ts else null
                    }
                    for (sample in health.oxygen) { inNight(sample.time)?.let { oxygenTicks[it] = sample.percent } }
                    for (sample in health.respiration) { inNight(sample.time)?.let { respirationTicks[it] = sample.breathsPerMinute } }
                    for ((time, value) in HealthSampleMapping.hrvByMinute(health.hrv)) { inNight(time)?.let { hrvMinuteTicks[it] = value } }
                    for (time in HealthSampleMapping.invalidHRVMinutes(health.hrv)) { inNight(time)?.let { invalidHrvMinutes.add(it) } }
                    val temperature = health.temperatures.mapNotNull { sample ->
                        inNight(sample.time)?.let { VitalSample(ts = it, hr = null, stress = null, temp = sample.celsius) }
                    }
                    val hrv = HealthSampleMapping.hrvBySlot(health.hrv).mapNotNull { (clock, value) ->
                        inNight(clock)?.let { VitalSample(ts = it, hr = null, stress = null, hrv = value,
                            hrvValid = true, hrvObservedAt = now) }
                    }
                    nightAuxiliary = VitalSample.merging(nightAuxiliary, temperature + hrv)
                }
                // A missing/failed extra page is unknown, not proof of an empty RR night.
                hrvMinuteReadComplete = requiredHrvPages.isNotEmpty() && requiredHrvPages.all {
                    val status = healthPages[it]?.hrvStatus ?: return@all false
                    status == BandDomainReadStatus.complete || status == BandDomainReadStatus.unsupported
                }
            }

            // SDK times have no timezone. Preserve the mapping timezone used for this batch;
            // it is a reconstruction assumption, not a device-reported historical timezone.
            val tz = zone.id
            // The latest tick this pull carried, kept aside so the panel can show it the moment it
            // is off the band rather than after the server has settled the day (12 · LIVE).
            var newest: Instant? = null
            var latest: LiveVitals? = null
            val localSamples = mutableListOf<VitalSample>()
            val rows = points.mapNotNull { dated ->
                val point = dated.point
                val ts = HealthSampleMapping.instant(time = point.time, calendarDay = dated.calendarDay, zone = zone)
                    ?: return@mapNotNull null
                if (ts < day.start || ts >= dayEnd) return@mapNotNull null
                // Page 0 includes future placeholders and the aggregate still accumulating.
                // Deferred slots are considered again on the next full page read.
                if (!OriginObservationPolicy.accepts(slot = ts, dayStart = day.start, dayEnd = dayEnd,
                        readStartedAt = now, snapshotStartedAt = dated.readStartedAt)) return@mapNotNull null
                point.temperature?.let { temperatureTicks[ts] = it }
                val localSample = VitalSample(
                    ts = ts, hr = point.heart, stress = point.stress, temp = point.temperature,
                    steps = point.step, met = point.met, vendorCalories = point.cal?.toDouble(),
                    dis = point.distance?.toDouble(), hrv = point.hrv,
                    hrvValid = if (point.hrv == null) null else true,
                    hrvObservedAt = if (point.hrv == null) null else now)
                if (localSample.hasReading) localSamples.add(localSample)
                if (newest == null || ts > newest) {
                    newest = ts
                    // ⚠️ A tick the band recorded off the wrist has no heart and no stress. That
                    // is not a zero — it is the absence the readout draws as ——. Heart stays
                    // that tick's own reading. Stress is often missing on a worn sleep tick that
                    // still has PPG heart, so the last positive stress in 24h is joined rather
                    // than dashed.
                    if (point.heart != null || point.stress != null) {
                        val prev = latest
                        latest = LiveVitals(
                            hr = VitalsTimelinePolicy.currentHeart(
                                latest = point.heart,
                                previous = prev?.let { r -> val v = r.hr; val a = r.at; if (v != null && a != null) v to a else null },
                                at = ts),
                            stress = VitalsTimelinePolicy.currentStress(
                                latest = point.stress,
                                previous = prev?.let { r -> val v = r.stress; val a = r.at; if (v != null && a != null) v to a else null },
                                at = ts),
                            at = ts)
                    }
                }
                // Re-read the bounded SDK day to repair late facts and holes before any cursor.
                if (point.heart == null && point.step == null && point.cal == null && point.distance == null &&
                    point.met == null && point.stress == null && point.sleepState == null) return@mapNotNull null
                // ⚠️ PostgREST refuses a batch whose rows carry different key sets (PGRST102), so
                // every row names every column and an absent reading travels as an explicit null.
                linkedMapOf<String, Any?>(
                    "user_id" to userId,
                    "ts" to iso(ts),
                    "origin_read_at" to isoFractional(dated.readAt),
                    "sampled_tz" to tz,
                    // ⚠️ F7 rule 09 / F2 · on its way out; the live table still has it NOT NULL.
                    "src" to "band",
                    "heart" to point.heart,
                    "step" to point.step,
                    "cal" to point.cal,
                    "dis" to point.distance,
                    "met" to point.met,
                    "temp" to point.temperature,
                    "hrv" to point.hrv,
                    "stress" to point.stress,
                    "sleep_states" to point.sleepState,
                )
            }

            invalidHrvTicks.removeAll(hrvTicks.keys)
            val invalidHrvSamples = invalidHrvTicks.sorted().map {
                VitalSample(ts = it, hr = null, stress = null, hrvValid = false, hrvObservedAt = now)
            }
            val mergedSamples = VitalSample.merging(localSamples,
                auxiliarySamples(temperatureTicks, hrvTicks, observedAt = now) + nightAuxiliary + invalidHrvSamples)
            if (!ConsentStore.granted || SupabaseClient.currentUserIdSnapshot() != userId ||
                BoundBand.identifier != deviceKey || !currentCoroutineContext().isActive) {
                lastOutcome = "failed"; return 0
            }
            checkpoint("ble_and_mapping")
            clearWrongDaySleep(day, store)
            invalidHrvMinutes.removeAll(hrvMinuteTicks.keys)
            val measuredSleep = sleepSummary(night = night, day = day, store = store,
                oxygen = oxygenTicks, respiration = respirationTicks,
                hrv = hrvMinuteTicks, hrvReadComplete = hrvMinuteReadComplete,
                invalidHrvMinutes = invalidHrvMinutes, observedAt = now)
            if (measuredSleep != null) apply(measuredSleep, day, store)
            val samplesByDay = mergedSamples.groupBy { UserDay.containing(it.ts, zone) }
            // Durable measured observations precede every measurement upload and server refresh.
            try {
                for (measuredDay in samplesByDay.keys + day) {
                    val samples = samplesByDay[measuredDay] ?: emptyList()
                    apply(samples, measuredDay, store)
                    OriginSyncPorts.homeSnapshot.saveBandObservations(day = measuredDay, samples = samples,
                        sleep = if (measuredDay == day) measuredSleep else null, userId = userId)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                auxiliaryUploaded = false
                BandLog.shared.record("persist band observations", error = e)
                lastOutcome = "failed"
                return 0
            }

            checkpoint("local_persistence")
            BandSyncActivity.shared.show(BandSyncProgress.Stage.saving)
            awaitPendingNetwork()
            checkpoint("wait_publication")
            val publication: BandEvidencePublication = try {
                evidencePublication(userId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                BandLog.shared.record("open band publication", error = e)
                lastOutcome = "failed"
                return 0
            }
            fun evidenceDomain(name: String, samples: List<Map<String, Any?>>, status: BandDomainReadStatus,
                               version: String, window: Pair<Instant, Instant>? = null,
                               statusFollowsSleep: Boolean = false) =
                BandEvidencePublication.Domain(name = name, deviceKey = deviceKey, day = dayString(day.start),
                    timezone = tz, start = window?.first ?: day.start, end = window?.second ?: readEnd,
                    observedAt = now, mappingVersion = version, status = status, samples = samples,
                    statusFollowsSleep = statusFollowsSleep)
            try {
                publication.stage(evidenceDomain("origin", rows, BandDomainReadStatus.partial, version = "veepoo-rmssd-v1",
                    window = day.start to originReadEnd))
                publication.stage(evidenceDomain("rr", rrRows, BandDomainReadStatus.partial, version = "veepoo-rmssd-v2"))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                auxiliaryUploaded = false
                BandLog.shared.record("persist RR evidence", error = e)
            }

            // The band is the immediate source for raw curves. Do not hold its 12:45 tick behind
            // settle_now: derived daily values remain server-authoritative, while measured points
            // can be shown as soon as they leave the wrist.
            apply(latest, store)

            // ⚠️ The night's own HRV is not computed here and never was computable here. The phone
            // sends every tick's RMSSD and the server takes the night from them (nb.night_hrv).
            //
            // The sleep row is keyed to the calendar day on which the user woke.
            if (measuredSleep != null && night != null) {
                val sleep = measuredSleep
                if (!ConsentStore.granted || SupabaseClient.currentUserIdSnapshot() != userId ||
                    BoundBand.identifier != deviceKey) { lastOutcome = "failed"; return 0 }
                // 04B rule 04 · the sleepLine rides along as compact "stage:minutes" runs.
                val row = linkedMapOf<String, Any?>(
                    "user_id" to userId,
                    "user_day" to dayString(day.start),
                    // §04.5 D6 · the night names the band that measured it.
                    "device_key" to deviceKey,
                    "total_minutes" to sleep.totalMinutes,
                    "deep_minutes" to sleep.deepMinutes,
                    "light_minutes" to sleep.lightMinutes,
                    "wake_count" to sleep.wakeCount,
                    "sleep_line" to sleep.line.joinToString(",") { "${it.stage}:${it.minutes}" },
                )
                val sStart = sleep.sleepStart
                val sWake = sleep.wakeAt
                if (sStart != null && sWake != null) {
                    row["sleep_start"] = iso(sStart)
                    row["wake_at"] = iso(sWake)
                }
                val raw = linkedMapOf<String, Any?>(
                    "respiration" to (sleep.respiration ?: emptyList()).map {
                        mapOf("ts" to iso(it.ts), "breaths_per_minute" to it.breathsPerMinute)
                    },
                    "intervals" to (sleep.intervals ?: emptyList()).map {
                        mapOf("start" to iso(it.start), "end" to iso(it.end))
                    },
                    "line" to sleep.line.map {
                        mapOf("stage" to it.stage, "minutes" to it.minutes, "offset_minutes" to it.offsetMinutes)
                    },
                )
                sleep.hrv?.let { hrv ->
                    raw["hrv"] = hrv.map { point ->
                        val r = linkedMapOf<String, Any?>("ts" to iso(point.ts), "rmssd_ms" to point.rmssdMS)
                        point.observedAt?.let { r["observed_at"] = iso(it) }
                        r
                    }
                }
                val invalidations = sleep.hrvInvalidatedMinutes
                if (!invalidations.isNullOrEmpty()) {
                    raw["hrv_invalidated"] = invalidations.entries.sortedBy { it.key }.map {
                        mapOf("ts" to iso(it.key), "observed_at" to iso(it.value), "reason" to "insufficient_adjacent_rr")
                    }
                }
                row["raw"] = raw
                sleepRow = row
            }

            // Every domain is acknowledged independently. Read failures keep a repair range and
            // cannot inherit another domain's success. Full-day overlap is bounded by SDK pages.
            val originStatus = if (pagesReturned == wanted.size && originSnapshotCoversDay)
                BandDomainReadStatus.complete else BandDomainReadStatus.partial
            val skippedDomains = HashSet<String>()
            if (!publishHRV) skippedDomains.addAll(listOf("hrv", "rr"))
            if (!publishTemperature) skippedDomains.add("temperature")
            if (!publishOxygen) skippedDomains.add("oxygen")
            val domains: List<Triple<String, List<Map<String, Any?>>, BandDomainReadStatus>> = listOf(
                Triple("origin", rows, originStatus),
                Triple("hrv", hrvTicks.entries.sortedBy { it.key }.map {
                    mapOf("ts" to iso(it.key), "hrv" to (it.value * 10).roundToLong() / 10.0, "hrv_valid" to true)
                } + invalidHrvTicks.sorted().map {
                    mapOf("ts" to iso(it), "hrv" to null, "hrv_valid" to false,
                        "hrv_invalid_reason" to "insufficient_adjacent_rr")
                }, hrvStatus),
                Triple("temperature", temperatureTicks.entries.sortedBy { it.key }.map {
                    mapOf("ts" to iso(it.key), "temp" to (it.value * 10).roundToLong() / 10.0)
                }, temperatureStatus),
                Triple("rr", rrRows, hrvStatus),
                Triple("sleep", emptyList(), sleepStatus),
            ).filter { it.first !in skippedDomains }
            val publications = domains.map { (name, samples, status) ->
                evidenceDomain(name, samples, status, version = if (name == "origin") "veepoo-rmssd-v1" else "veepoo-rmssd-v2",
                    window = if (name == "origin") day.start to originReadEnd else null,
                    statusFollowsSleep = name == "sleep" && sleepRow != null)
            }.toMutableList()
            val oxygenWindow = nightWindow(day, night, store)
            var oxygenRead = oxygenStatus
            val oxygenStart: Instant
            val oxygenEnd: Instant
            val oxygenSamples: List<Map<String, Any?>>
            if (oxygenWindow != null) {
                val (start, wake) = oxygenWindow
                oxygenStart = start
                oxygenEnd = maxOf(wake, start.plusSeconds(60))
                oxygenSamples = (measuredSleep?.spo2 ?: emptyList()).map { mapOf("ts" to iso(it.ts), "spo2" to it.percent) }
                if (oxygenSamples.isEmpty() && oxygenRead == BandDomainReadStatus.complete) oxygenRead = BandDomainReadStatus.notCollected
            } else {
                oxygenStart = day.start
                oxygenEnd = readEnd
                oxygenSamples = emptyList()
                if (oxygenRead == BandDomainReadStatus.complete) oxygenRead = BandDomainReadStatus.notCollected
            }
            if ("oxygen" !in skippedDomains) {
                publications.add(evidenceDomain("oxygen", oxygenSamples, oxygenRead, version = "veepoo-spo2-v1",
                    window = oxygenStart to oxygenEnd))
            }
            if (store.today.day == day) {
                store.mealResponseZerosToday = opticalDroppedZeros > 0 && opticalTicks.isEmpty()
            }
            val incomingOptical = opticalTicks.keys.sorted().map { MealResponseIndex.Point(ts = it, optical = opticalTicks.getValue(it)) }
            store.mealResponsePoints = mergeOptical(store.mealResponsePoints, incomingOptical)
            val opticalSamples = opticalTicks.entries.sortedBy { it.key }.map { mapOf("ts" to iso(it.key), "optical" to it.value) }
            publications.add(evidenceDomain("response", opticalSamples, opticalStatus, version = "veepoo-optical-v1"))

            var changedCount = 0
            val published = publication.publish(publications, sleep = sleepRow)
            val metrics = publication.uploadMetrics
            BandTrace.record("sync.upload_calls", mapOf(
                "calls" to metrics.calls.toString(), "rounds" to metrics.rounds.toString(), "domains" to metrics.domains.toString()))
            published.sleep?.let { sleepResult ->
                sleepResult.onSuccess { sleepStatus = BandDomainReadStatus.complete }
                sleepResult.onFailure { e ->
                    if (e is CancellationException) { lastOutcome = "failed"; return 0 }
                    auxiliaryUploaded = false
                    sleepStatus = BandDomainReadStatus.failed
                    BandLog.shared.record("upsert sleep_nights", error = e)
                }
            }
            for ((domain, publicationResult) in publications.zip(published.domains)) {
                val result = publicationResult.getOrElse { e ->
                    if (e is CancellationException) { lastOutcome = "failed"; return changedCount }
                    auxiliaryUploaded = false
                    BandSyncActivity.shared.failed(e)
                    BandLog.shared.record("ingest ${domain.name}", error = e)
                    domainStates.add(BandDomainSyncState(domain = domain.name, status = BandDomainReadStatus.failed,
                        attemptedAt = now, acknowledgedStart = null, acknowledgedEnd = null,
                        repairStart = domain.start, repairEnd = domain.end))
                    null
                } ?: continue
                changedCount += result.changedCount
                BandTrace.record("sync.domain", mapOf("domain" to domain.name,
                    "status" to result.state.status.raw, "confirmed" to result.confirmed.toString()))
                if (!result.confirmed) auxiliaryUploaded = false
                domainStates.add(result.state)
            }
            if (!ConsentStore.granted || SupabaseClient.currentUserIdSnapshot() != userId ||
                BoundBand.identifier != deviceKey) { lastOutcome = "failed"; return changedCount }
            val kept = BandSyncPolicy.keepingSkippedDomains(
                domainStates,
                previous = BandDomainSyncState.load(userId = userId, deviceKey = deviceKey, day = dayString(day.start)),
                skipped = skippedDomains)
            try {
                BandDomainSyncState.save(kept, userId = userId, deviceKey = deviceKey, day = dayString(day.start))
            } catch (e: Throwable) {
                BandLog.shared.record("save domain acknowledgments", error = e)
            }
            checkpoint("upload")
            stage()
            val outcome = BandSyncPolicy.dayStatus(pagesReturned = pagesReturned, wanted = wanted.size,
                auxiliaryUploaded = auxiliaryUploaded).raw
            lastOutcome = outcome
            if (outcome == "success" && refreshState().rejection(expected = scope) == null) {
                newest?.let { setWatermark(it, day, userId) }
            }
            return changedCount
        } finally {
            pendingRun?.returned = pagesReturned
        }
    }

    /** Check retained and locally cached history once per successful user day. Every
     *  refresh repairs missing/failed dates; dates already completed earlier in this same
     *  refresh are reused. There is no "attempted the whole week" success flag. */
    private suspend fun backfillIfNeeded(
        scope: BandRefreshCoordinator.Scope, today: UserDay,
        recentDays: Map<Int, BandRefreshResult>, auditToday: Boolean, store: DataStore,
    ): BandRefreshCoordinator.HistoryResult {
        if (refreshState().rejection(expected = scope) != null) {
            return BandRefreshCoordinator.HistoryResult(result = BandRefreshResult(status = BandRefreshResult.Status.cancelled))
        }
        val bound = scope.binding
        val userId = scope.account
        val identity = try {
            BandReadiness.read(account = userId, binding = bound) { band.readIdentity() }
        } catch (e: CancellationException) { throw e } catch (e: Throwable) { null }
        val cachedOffsets: List<Int> = try {
            BandReadiness.read(account = userId, binding = bound) { band.cachedHistoryDayOffsets(limit = 6) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            BandLog.shared.record("cachedHistoryDayOffsets", error = e)
            return BandRefreshCoordinator.HistoryResult(result = BandRefreshResult(status = BandRefreshResult.Status.failed))
        }
        val now = Instant.now()
        // SDK offsets are relative to its current calendar date. Translate them to the
        // refresh's captured day so a slow pull crossing midnight keeps its original dates.
        val zone = ZoneId.systemDefault()
        val elapsedDays = BandTime.daysBetween(today.start, now, zone)
        val candidates = BandSyncPolicy.historyDayOffsets(retained = identity?.watchDataDayNumber, cachedOffsets = cachedOffsets)
        val offsets = BandSyncPolicy.historyOffsetsToSync(available = candidates, elapsedDays = elapsedDays,
            recentDays = recentDays.mapValues { it.value.status }) { offset ->
            val day = today.adding(days = -offset)
            BandSyncPolicy.needsHistorySync(
                states = BandDomainSyncState.load(userId = userId, deviceKey = bound, day = dayString(day.start)),
                outcome = BandPrefs.string(historyOutcomeKey(scope, day))?.let { BandRefreshResult.Status.fromRaw(it) },
                start = day.start, end = day.end, now = now, requireAcknowledgedToday = auditToday)
        }
        // Two recent days are already counted; these are the retained days still to read.
        BandSyncActivity.shared.revise(total = 2 + offsets.size)
        val days = offsets.maxOrNull() ?: return BandRefreshCoordinator.HistoryResult(result = null)
        if (days > 1) BandSyncActivity.shared.beginHistory()
        // The retained days this pull will walk are only known once the band has answered.
        BandSyncActivity.shared.expect(total = 2 + offsets.size)
        val results = mutableListOf<BandRefreshResult>()
        val recoveredDays = HashSet<Int>()
        fun cancelled(status: BandRefreshResult.Status) = BandRefreshCoordinator.HistoryResult(
            result = BandRefreshResult(status = status, points = results.sumOf { it.points }),
            recoveredDays = recoveredDays)
        for (offset in offsets) {
            refreshState().rejection(expected = scope)?.let { return cancelled(it) }
            BandSyncActivity.shared.show(BandSyncProgress.Stage.reading)
            val points = sync(today.adding(days = -offset), scope, store)
            val status = BandRefreshResult.Status.fromRaw(lastOutcome) ?: BandRefreshResult.Status.failed
            BandSyncActivity.shared.step()
            results.add(BandRefreshResult(status = status, points = points))
            if (status == BandRefreshResult.Status.success && recentDays[offset] != null) recoveredDays.add(offset)
        }
        refreshState().rejection(expected = scope)?.let { return cancelled(it) }
        BandSyncActivity.shared.updatingResults()
        OriginSyncPorts.repository.settleNow(days = days + max(0, elapsedDays))
        refreshState().rejection(expected = scope)?.let { return cancelled(it) }
        val reloadStarted = Instant.now()
        OriginSyncPorts.repository.load(days = days, endingAt = today, into = store)
        refreshState().rejection(expected = scope)?.let { return cancelled(it) }
        OriginSyncPorts.repository.loadSleepScores(days = if (auditToday) 30 else 2, endingAt = today, into = store)
        BandTrace.record("sync.reload", mapOf(
            "durationSeconds" to BandTime.interval(Instant.now(), reloadStarted).toString(),
            "day" to today.key, "days" to days.toString()))
        BandSyncActivity.shared.resultsLoaded()
        return BandRefreshCoordinator.HistoryResult(result = BandRefreshResult.combining(results, at = Instant.now()),
            recoveredDays = recoveredDays)
    }

    /** One row when the day finishes, including a read that stopped early. Inserting at the
     *  start and patching at the end was two round trips for the same fact. */
    private suspend fun filePendingRun(userId: String) {
        val run = pendingRun ?: return
        if (run.filed) return
        run.filed = true
        if (SupabaseClient.currentUserIdSnapshot() != userId) return
        BandSyncActivity.shared.show(BandSyncProgress.Stage.saving)
        val started = Instant.now()
        try {
            val row = linkedMapOf<String, Any?>(
                "user_id" to userId,
                "started_at" to iso(run.startedAt),
                "finished_at" to iso(Instant.now()),
                "outcome" to lastOutcome,
                "days_requested" to run.requested,
                "days_returned" to run.returned,
            )
            OriginSyncPorts.repository.deviceId?.let { row["device_id"] = it }
            try {
                SupabaseClient.insert("sync_runs", rows = listOf(row), expectedOwner = userId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                BandLog.shared.record("finish sync_runs", error = e)
            }
        } finally {
            BandTrace.record("sync.run_receipt", mapOf(
                "durationSeconds" to BandTime.interval(Instant.now(), started).toString()))
        }
    }

    companion object {
        private val refreshCoordinator = BandRefreshCoordinator(state = { refreshState() })

        private fun refreshState(): BandRefreshCoordinator.State = BandRefreshCoordinator.State(
            account = SupabaseClient.currentUserIdSnapshot(), binding = BoundBand.identifier,
            consent = ConsentStore.granted, exclusive = BandLiveLifecycle.shared.hasExclusiveOperation,
            connected = Band.live.state == BandConnectionState.connected)

        /**
         * Every caller enters the same account-scoped refresh. Readiness and history upgrades
         * belong to that shared work; a screen never has to prepare the band or infer success.
         * `onTodayReady` runs after today has been uploaded and settled, before yesterday.
         */
        suspend fun refreshNow(
            store: DataStore = DataStore,
            request: BandRefreshRequest = BandRefreshRequest.automatic,
            onTodayReady: (suspend () -> Unit)? = null,
        ): BandRefreshResult {
            if (Band.allowsSeed && com.nextbody.hoop.app.DebugLaunch["NB_DEBUG_SYNC_STAGE"] != null) {
                return BandRefreshResult(status = BandRefreshResult.Status.throttled)
            }
            if (Band.allowsSeed && com.nextbody.hoop.app.DebugLaunch["NB_DEBUG_SLEEP_EVIDENCE"] == "1") {
                return BandRefreshResult(status = BandRefreshResult.Status.throttled)
            }
            // Alarm warm-up (PhoneToolRunner.primeAlarms) is AI-only; AIFeature.enabled is false.
            return refreshCoordinator.refresh(request, cadence = SyncCadence.interval,
                work = refreshWork(store, request, onTodayReady))
        }

        private fun refreshWork(
            store: DataStore, request: BandRefreshRequest,
            onTodayReady: (suspend () -> Unit)? = null,
        ): BandRefreshCoordinator.Work {
            val scope = refreshState().scope
            val sync = OriginDataSync()
            var today = UserDay.containing(Instant.now())
            var refreshStartedAt = Instant.now()
            fun resolvedTier(): BandRefreshTier {
                if (request.tier == BandRefreshTier.daily && store.lastSync == null) return BandRefreshTier.full
                return request.tier
            }
            fun plannedDays(): List<Int> {
                val confirmed = scope?.let { yesterdayIsConfirmed(it, Instant.now()) } ?: false
                return BandSyncPolicy.refreshDayOffsets(
                    tier = resolvedTier(),
                    includesYesterday = BandSyncPolicy.refreshIncludesYesterday(
                        tier = resolvedTier(), now = Instant.now(), yesterdayConfirmed = confirmed))
            }
            return BandRefreshCoordinator.Work(
                prepare = prepare@{ reuseReceipt ->
                    if (scope == null) return@prepare false
                    refreshStartedAt = Instant.now()
                    BandTrace.notice("refresh begin request=$request")
                    BandSyncActivity.shared.phase = "connecting"
                    BandSyncActivity.shared.beginCounting()
                    if (resolvedTier() == BandRefreshTier.full) BandSyncActivity.shared.beginHistory()
                    if (request != BandRefreshRequest.phoneTool) {
                        val readinessStarted = Instant.now()
                        if (!BandReadiness.shared.ensureReady(store, reason = "sync",
                                reuseRecentLiveReceipt = reuseReceipt)) return@prepare false
                        BandTrace.record("sync.prepare", mapOf("segment" to "readiness",
                            "durationSeconds" to BandTime.interval(Instant.now(), readinessStarted).toString()))
                    }
                    if (refreshState().rejection(expected = scope) != null ||
                        Band.live.state != BandConnectionState.connected) return@prepare false
                    BandPresence.shared.start(store)
                    store.setBandConnected(true)
                    val metadataStarted = Instant.now()
                    BandPresence.shared.refresh(store, prepared = BandReadiness.shared.snapshot)
                    BandTrace.record("sync.prepare", mapOf("segment" to "device_metadata",
                        "durationSeconds" to BandTime.interval(Instant.now(), metadataStarted).toString()))
                    if (refreshState().rejection(expected = scope) != null) return@prepare false
                    try {
                        BandReadiness.read(account = scope.account, binding = scope.binding) {
                            Band.live.prepareFreshSync()
                        }
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Throwable) { return@prepare false }
                    today = UserDay.containing(Instant.now())
                    val tier = resolvedTier()
                    prepareAuxiliaryReads(scope, today, tier, sync.band)
                    // The previous upload holds the account lock. Let it finish while the band is read,
                    // and wait for it before this refresh publishes. The two must not upload together.
                    val networkStarted = Instant.now()
                    sync.pendingNetwork = BandMain.scope.async {
                        OriginSyncPorts.repository.waitForEvidencePublication()
                        BandTrace.record("sync.prepare", mapOf("segment" to "wait_publication",
                            "durationSeconds" to BandTime.interval(Instant.now(), networkStarted).toString()))
                        val drainStarted = Instant.now()
                        flushPendingEvidence(userId = scope.account)
                        BandTrace.record("sync.prepare", mapOf("segment" to "drain_evidence",
                            "durationSeconds" to BandTime.interval(Instant.now(), drainStarted).toString()))
                    }
                    if (refreshState().rejection(expected = scope) != null) return@prepare false
                    BandSyncActivity.shared.phase = "syncing"
                    BandSyncActivity.shared.show(BandSyncProgress.Stage.reading)
                    val held = BandReadiness.shared.snapshot?.identity?.watchDataDayNumber
                    val planned = plannedDays().size
                    BandSyncActivity.shared.expect(total = if (tier == BandRefreshTier.full) max(planned, held ?: planned) else max(planned, 1))
                    true
                },
                day = day@{ daysAgo ->
                    if (scope == null) return@day BandRefreshResult(status = BandRefreshResult.Status.cancelled)
                    if (Band.live.state != BandConnectionState.connected) return@day BandRefreshResult(status = BandRefreshResult.Status.disconnected)
                    val day = today.adding(days = -daysAgo)
                    val points = sync.sync(day, scope, store)
                    val status = BandRefreshResult.Status.fromRaw(sync.lastOutcome) ?: BandRefreshResult.Status.failed
                    if (daysAgo == 0 && (status == BandRefreshResult.Status.success || status == BandRefreshResult.Status.partial) &&
                        refreshState().rejection(expected = scope) == null) {
                        val started = Instant.now()
                        BandSyncActivity.shared.show(BandSyncProgress.Stage.updating)
                        OriginSyncPorts.repository.settleNow(days = 0)
                        val reloadStarted = Instant.now()
                        if (refreshState().rejection(expected = scope) == null) {
                            OriginSyncPorts.repository.load(days = 1, endingAt = day, into = store)
                        }
                        if (refreshState().rejection(expected = scope) == null) {
                            val sleepDays = if (resolvedTier() == BandRefreshTier.full) 30 else 2
                            OriginSyncPorts.repository.loadSleepScores(days = sleepDays, endingAt = day, into = store)
                        }
                        BandTrace.record("sync.reload", mapOf(
                            "durationSeconds" to BandTime.interval(Instant.now(), reloadStarted).toString(), "day" to day.key))
                        BandTrace.record("sync.segment", mapOf("segment" to "settlement_and_reload",
                            "durationSeconds" to BandTime.interval(Instant.now(), started).toString(), "day" to day.key))
                        if (refreshState().rejection(expected = scope) == null) onTodayReady?.invoke()
                    } else if (daysAgo > 0 && points > 0 && refreshState().rejection(expected = scope) == null) {
                        BandSyncActivity.shared.show(BandSyncProgress.Stage.updating)
                        OriginSyncPorts.repository.settleNow(days = daysAgo)
                    }
                    BandSyncActivity.shared.step()
                    BandRefreshResult(status = status, points = points)
                },
                history = history@{ recentDays ->
                    if (scope == null) return@history BandRefreshCoordinator.HistoryResult(
                        result = BandRefreshResult(status = BandRefreshResult.Status.cancelled))
                    if (Band.live.state != BandConnectionState.connected) return@history BandRefreshCoordinator.HistoryResult(
                        result = BandRefreshResult(status = BandRefreshResult.Status.disconnected))
                    sync.backfillIfNeeded(scope, today, recentDays, auditToday = resolvedTier() == BandRefreshTier.full, store = store)
                },
                days = { plannedDays() },
                checkHistory = { resolvedTier() != BandRefreshTier.light },
                finish = {
                    BandSyncActivity.shared.show(BandSyncProgress.Stage.saving)
                    sync.awaitPendingNetwork()
                    BandSyncActivity.shared.show(BandSyncProgress.Stage.finishing)
                    Band.live.finishFreshSync()
                },
                completed = { result ->
                    val at = result.syncedAt
                    if (result.status == BandRefreshResult.Status.success && at != null && scope != null &&
                        refreshState().rejection(expected = scope) == null) {
                        BandSyncActivity.shared.show(BandSyncProgress.Stage.saving)
                        val receiptStarted = Instant.now()
                        OriginSyncPorts.repository.markDeviceSynced(at = at)
                        BandTrace.record("sync.completion_receipt", mapOf(
                            "durationSeconds" to BandTime.interval(Instant.now(), receiptStarted).toString()))
                        if (refreshState().rejection(expected = scope) == null) store.lastSync = at
                    }
                    BandTrace.record("sync.refresh_finished", mapOf(
                        "status" to result.status.raw,
                        "durationSeconds" to BandTime.interval(Instant.now(), refreshStartedAt).toString(),
                        "kind" to if (BandSyncActivity.shared.workflow.isHistory) "history" else "daily"))
                    BandTrace.notice("refresh end status=${result.status.raw}")
                    BandSyncActivity.shared.complete(success = result.status == BandRefreshResult.Status.success &&
                        scope?.let { refreshState().rejection(expected = it) == null } == true)
                },
            )
        }

        suspend fun waitForCurrentPull() = refreshCoordinator.waitForCurrentPull()
        val isIdle: Boolean get() = refreshCoordinator.isIdle

        /** The app calls this only after releasing the consent takeover's exclusive gate. */
        suspend fun refreshAfterConsent(store: DataStore = DataStore): BandRefreshResult? =
            refreshCoordinator.refreshAfterConsent(cadence = SyncCadence.interval,
                work = refreshWork(store, BandRefreshRequest.fullHistory))

        /** A night domain counts as confirmed when its last acknowledgement succeeded and
         *  nothing is waiting to be repaired. Unsupported and not-collected stay confirmed. */
        private fun domainConfirmed(scope: BandRefreshCoordinator.Scope, domain: String, day: UserDay, now: Instant): Boolean {
            val state = BandDomainSyncState.load(userId = scope.account, deviceKey = scope.binding,
                day = dayString(day.start)).firstOrNull { it.domain == domain } ?: return false
            if (state.repairStart != null || state.repairEnd != null || state.attemptedAt > now) return false
            return when (state.status) {
                BandDomainReadStatus.complete, BandDomainReadStatus.unsupported, BandDomainReadStatus.notCollected -> true
                else -> false
            }
        }

        private fun yesterdayIsConfirmed(scope: BandRefreshCoordinator.Scope, now: Instant): Boolean {
            val day = UserDay.containing(now).adding(days = -1)
            val outcome = BandPrefs.string(historyOutcomeKey(scope, day))?.let { BandRefreshResult.Status.fromRaw(it) }
            val states = BandDomainSyncState.load(userId = scope.account, deviceKey = scope.binding, day = dayString(day.start))
            return !BandSyncPolicy.needsHistorySync(states = states, outcome = outcome,
                start = day.start, end = day.end, now = now, requireAcknowledgedToday = false)
        }

        /** Force a dedicated dump when the tier or an unconfirmed night says the cached one is not enough. */
        private suspend fun prepareAuxiliaryReads(scope: BandRefreshCoordinator.Scope, day: UserDay,
                                                  tier: BandRefreshTier, band: BandService) {
            val now = Instant.now()
            val forces = listOf(
                BandAuxiliaryDomain.hrv to domainConfirmed(scope, "hrv", day, now),
                BandAuxiliaryDomain.oxygen to domainConfirmed(scope, "oxygen", day, now),
                BandAuxiliaryDomain.temperature to true,
            )
            for ((domain, confirmed) in forces) {
                val last = band.auxiliaryCompletedAt(domain)
                if (BandSyncPolicy.needsAuxiliaryDump(nightConfirmed = confirmed, lastCompletedAt = last, now = now, tier = tier)) {
                    band.invalidateAuxiliary(domain)
                }
            }
        }

        /** Which SDK pages a given user day needs. The only place dayOffset is ever decided. */
        fun pages(day: UserDay, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<Int> =
            HealthSampleMapping.deviceDayOffsets(start = day.start, now = now, zone = zone)

        fun nightPageOffsets(start: Instant, wake: Instant, now: Instant, zone: ZoneId): List<Int> {
            if (!(start < wake && wake <= now)) return emptyList()
            val today = BandTime.localDate(now, zone)
            var cursor = BandTime.localDate(start, zone)
            val finalDay = BandTime.localDate(wake.minusSeconds(1), zone)
            val offsets = mutableListOf<Int>()
            while (!cursor.isAfter(finalDay)) {
                val offset = ChronoUnit.DAYS.between(cursor, today).toInt()
                if (offset >= 0) offsets.add(offset)
                cursor = cursor.plusDays(1)
            }
            return offsets
        }

        fun auxiliarySamples(temperatureTicks: Map<Instant, Double>, hrvTicks: Map<Instant, Double>,
                             observedAt: Instant? = null): List<VitalSample> =
            (temperatureTicks.keys + hrvTicks.keys).sorted().map {
                VitalSample(ts = it, hr = null, stress = null, temp = temperatureTicks[it], hrv = hrvTicks[it],
                    hrvValid = if (hrvTicks[it] == null) null else true,
                    hrvObservedAt = if (hrvTicks[it] == null) null else observedAt)
            }

        /** Old cache rows sometimes filed a valid sleep under the previous user day. Sleep
         *  belongs to the calendar date of its wake, including wakes after noon. */
        private fun sleepOnCalendarDay(sleep: SleepSummary?, day: UserDay): SleepSummary? {
            val wake = sleep?.wakeAt ?: return sleep
            return if (BandTime.sameDay(wake, day.start)) sleep else null
        }

        private fun clearWrongDaySleep(day: UserDay, store: DataStore) {
            if (store.today.day == day) {
                store.today = store.today.copy(sleep = sleepOnCalendarDay(store.today.sleep, day))
            }
            store.history = store.history.map { stored ->
                if (stored.day != day) stored else stored.copy(sleep = sleepOnCalendarDay(stored.sleep, day))
            }
        }

        private fun sleepSummary(
            night: SleepNight?, day: UserDay, store: DataStore,
            oxygen: Map<Instant, Int>, respiration: Map<Instant, Double>,
            hrv: Map<Instant, Double> = emptyMap(), hrvReadComplete: Boolean = false,
            invalidHrvMinutes: Set<Instant> = emptySet(), observedAt: Instant = Instant.now(),
        ): SleepSummary? {
            val existing = sleepOnCalendarDay(
                (if (store.today.day == day) store.today else store.history.firstOrNull { it.day == day })?.sleep, day)
            val sameWindow = night?.sleepStart == existing?.sleepStart && night?.wakeAt == existing?.wakeAt
            val incomingIsContained: Boolean = run {
                val oldStart = existing?.sleepStart; val oldWake = existing?.wakeAt
                val newStart = night?.sleepStart; val newWake = night?.wakeAt
                if (oldStart == null || oldWake == null || newStart == null || newWake == null) return@run false
                val oldTotal = existing?.totalMinutes ?: 0
                val newTotal = night?.totalMinutes ?: 0
                oldStart <= newStart && oldWake >= newWake && oldTotal >= newTotal &&
                    (oldStart < newStart || oldWake > newWake || oldTotal > newTotal)
            }
            val summary = if (incomingIsContained) existing else night?.let {
                SleepSummary(totalMinutes = it.totalMinutes, deepMinutes = it.deepMinutes,
                    lightMinutes = it.lightMinutes, wakeCount = it.wakeCount,
                    line = if (it.line.isEmpty() && sameWindow) existing?.line ?: emptyList() else it.line,
                    sleepStart = it.sleepStart, wakeAt = it.wakeAt)
            } ?: existing
            var result = summary?.copy() ?: return summary
            val start = result.sleepStart ?: return summary
            val wake = result.wakeAt ?: return summary
            if (!incomingIsContained) {
                val nightIntervals = night?.intervals
                if (nightIntervals != null) result.intervals = nightIntervals
                else if (sameWindow && result.intervals == null) result.intervals = existing?.intervals
            }
            // Issue #20 · the band's wake is the last word only until the phone contradicts it.
            // Cutting here, before the per-minute series are filtered, keeps oxygen, respiration
            // and HRV inside the night that is actually filed rather than the one the wrist
            // guessed. `start` cannot move; only the end of the night can.
            result = SleepWakeClamp.applying(AwakeEvidence.marks(), result)
            val ended = result.wakeAt ?: wake
            val intervals = result.intervals ?: listOf(SleepInterval(start = start, end = ended))
            fun inSleep(ts: Instant) = intervals.any { ts >= it.start && ts < it.end }
            val savedOxygen = (existing?.spo2 ?: emptyList()).filter { inSleep(it.ts) }.associate { it.ts to it.percent }
            result.spo2 = (savedOxygen + oxygen.filterKeys { inSleep(it) }).entries.sortedBy { it.key }
                .map { OvernightOxygenPoint(ts = it.key, percent = it.value) }
            val savedRespiration = (existing?.respiration ?: emptyList()).filter { inSleep(it.ts) }
                .associate { it.ts to it.breathsPerMinute }
            result.respiration = (savedRespiration + respiration.filterKeys { inSleep(it) }).entries.sortedBy { it.key }
                .map { SleepRespirationPoint(ts = it.key, breathsPerMinute = it.value) }
            val invalidations = HashMap(existing?.hrvInvalidatedMinutes ?: emptyMap())
            for (minute in invalidHrvMinutes) {
                val prior = invalidations[minute]
                invalidations[minute] = if (prior == null) observedAt else maxOf(prior, observedAt)
            }
            val keptInvalidations = invalidations.filterKeys { inSleep(it) }
            result.hrvInvalidatedMinutes = keptInvalidations.ifEmpty { null }
            val freshHRV = hrv.filterKeys { inSleep(it) }.map {
                SleepHRVPoint(ts = it.key, rmssdMS = it.value, observedAt = observedAt)
            }
            val combinedHRV = SleepHRVPoint.merging((existing?.hrv ?: emptyList()).filter { inSleep(it.ts) },
                freshHRV, invalidatedMinutes = keptInvalidations)
            result.hrv = if (combinedHRV.isEmpty() && !hrvReadComplete && existing?.hrv == null &&
                keptInvalidations.isEmpty()) null else combinedHRV
            return result
        }

        private fun apply(sleep: SleepSummary, day: UserDay, store: DataStore) {
            if (store.today.day == day) store.today = store.today.copy(sleep = sleep)
            val index = store.history.indexOfFirst { it.day == day }
            if (index >= 0) {
                store.history = store.history.toMutableList().also { it[index] = it[index].copy(sleep = sleep) }
            } else {
                store.history = (store.history + DailyMetrics(day = day).copy(sleep = sleep)).sortedBy { it.day }
            }
        }

        /** The recorded night on this user day: this sync's row, or the one already on the store. */
        private fun nightWindow(day: UserDay, night: SleepNight?, store: DataStore): Pair<Instant, Instant>? {
            val metrics = if (store.today.day == day) store.today else store.history.firstOrNull { it.day == day }
            val storedSleep = sleepOnCalendarDay(metrics?.sleep, day)
            val start = night?.sleepStart
            val wake = night?.wakeAt
            if (start != null && wake != null && wake > start) {
                val oldStart = storedSleep?.sleepStart
                val oldWake = storedSleep?.wakeAt
                if (oldStart != null && oldWake != null && oldStart <= start && oldWake >= wake) return oldStart to oldWake
                return start to wake
            }
            val s = storedSleep?.sleepStart
            val w = storedSleep?.wakeAt
            if (s != null && w != null && w > s) return s to w
            return null
        }

        private val evidenceDrains = HashMap<String, Deferred<Unit>>()

        suspend fun flushPendingEvidence(userId: String) {
            if (!currentCoroutineContext().isActive || !ConsentStore.granted ||
                SupabaseClient.currentUserIdSnapshot() != userId) return
            evidenceDrains[userId]?.let { it.await(); return }
            val task = BandMain.scope.async { drainEvidence(userId) }
            evidenceDrains[userId] = task
            try {
                task.await()
            } catch (e: CancellationException) {
                task.cancel()
                throw e
            } finally {
                evidenceDrains.remove(userId)
            }
        }

        private suspend fun drainEvidence(userId: String) {
            try {
                val publication = evidencePublication(userId)
                val acknowledged = publication.replay()
                BandTrace.notice("evidence drain finished: $acknowledged acknowledged")
            } catch (e: CancellationException) {
                return
            } catch (e: Throwable) {
                if (e is SupabaseFailure.Http) BandTrace.error("evidence drain stopped: HTTP ${e.code}")
                else BandTrace.error("evidence drain stopped: ${e::class.simpleName}")
                BandLog.shared.record("retry band observations", error = e)
            }
        }

        private fun historyOutcomeKey(scope: BandRefreshCoordinator.Scope, day: UserDay): String =
            "nb.sync.day-outcome.v1.${scope.account}.${scope.binding}.${dayString(day.start)}"

        private fun mergeOptical(stored: List<MealResponseIndex.Point>, fresh: List<MealResponseIndex.Point>): List<MealResponseIndex.Point> {
            val byTime = HashMap<Instant, Double>()
            for (point in stored + fresh) byTime[point.ts] = point.optical
            return byTime.keys.sorted().map { MealResponseIndex.Point(ts = it, optical = byTime.getValue(it)) }
        }

        private val clockPattern = Regex("""(\d{1,2}):(\d{2})""")

        private fun clock(raw: String): String {
            val match = clockPattern.find(raw) ?: return raw
            val parts = match.value.split(":").mapNotNull { it.toIntOrNull() }
            if (parts.size != 2) return raw
            return String.format(java.util.Locale.US, "%02d:%02d", parts[0], parts[1])
        }

        private fun dayString(date: Instant): String = BandTime.dayKey(date)

        /** ISO8601DateFormatter's default: whole seconds, UTC, `Z`. */
        private val isoFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX").withZone(ZoneOffset.UTC)
        private val isoFractionalFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSXXX").withZone(ZoneOffset.UTC)
        private fun iso(at: Instant): String = isoFormatter.format(at)
        private fun isoFractional(at: Instant): String = isoFractionalFormatter.format(at)

        /** Keep the raw curve live even while its upload and server settlement are still running.
         *  Backfill days are merged into history; the active day is also merged into `today`. */
        private fun apply(fresh: List<VitalSample>, day: UserDay, store: DataStore) {
            if (fresh.isEmpty()) return
            if (store.today.day == day) {
                store.today = store.today.copy(vitalsCurve = VitalSample.merging(store.today.vitalsCurve, fresh))
            }
            val index = store.history.indexOfFirst { it.day == day }
            if (index >= 0) {
                store.history = store.history.toMutableList().also {
                    it[index] = it[index].copy(vitalsCurve = VitalSample.merging(it[index].vitalsCurve, fresh))
                }
            } else {
                store.history = (store.history + DailyMetrics(day = day).copy(vitalsCurve = fresh.sortedBy { it.ts }))
                    .sortedBy { it.day }
            }
        }

        /** ⚠️ Forwards only. The backfill syncs last week one day at a time, and each of those days
         *  ends at 03:55 this morning — assigning them straight across replaced this minute's tick
         *  with a six-hour-old one, and the panel that exists to show the band is live went ——. */
        private fun apply(latest: LiveVitals?, store: DataStore) {
            val at = latest?.at ?: return
            val current = store.vitals.at
            if (current != null && current >= at) return
            if (store.vitals != latest) store.vitals = latest
        }

        // MARK: what has already been sent

        /** Per bound band, per user day. The band is in the key because a different NEXTBODY has a
         *  different history; forgetting one leaves its marks behind. */
        private fun watermarkKey(day: UserDay, userId: String): String =
            "nb.sync.mark.$userId.${BoundBand.identifier ?: "none"}.${dayString(day.start)}"

        fun watermark(day: UserDay, userId: String): Instant? {
            val seconds = BandPrefs.double(watermarkKey(day, userId)) ?: 0.0
            return if (seconds > 0) BandTime.fromSeconds(seconds) else null
        }

        fun setWatermark(ts: Instant, day: UserDay, userId: String) {
            // Never backwards. Two syncs can overlap — a foreground refresh and the home screen's
            // own — and the one that finishes second is not necessarily the one that read further.
            val existing = watermark(day, userId)
            if (existing != null && existing >= ts) return
            BandPrefs.setDouble(watermarkKey(day, userId), BandTime.seconds(ts))
        }

        private val domainTransport = BandDeltaTransport(rpc = { name, args, owner ->
            val response = SupabaseClient.rpc(name, args = args, expectedOwner = owner)
            BandIngestionAcknowledgment.fromJson(response as? org.json.JSONObject
                ?: throw BandEvidencePublication.Failure.Server("decode", "unexpected $name reply"))
        }, bundleRPC = { args, owner ->
            BandBundleReply(SupabaseClient.rpc("ingest_band_bundle", args = args, expectedOwner = owner))
        })

        private fun evidencePublication(userId: String): BandEvidencePublication =
            BandEvidencePublication(account = userId,
                local = com.nextbody.hoop.services.storage.LocalDataStore.shared().asBandLocalStore(),
                authorized = { ConsentStore.granted && SupabaseClient.currentUserIdSnapshot() == userId },
                transport = BandEvidencePublication.Transport(
                    ingest = { args, owner -> domainTransport.ingest(args, owner = owner) },
                    // publish_sleep_night files the wearer's night and holds the other band's
                    // (returned with `held: true`), so the receipt is honest either way.
                    sleep = { row, owner ->
                        val response = SupabaseClient.rpc("publish_sleep_night", args = mapOf("p_row" to row), expectedOwner = owner)
                        @Suppress("UNCHECKED_CAST")
                        (jsonToKotlin(response) as? List<Map<String, Any?>>) ?: emptyList()
                    },
                    bundle = { domains, sleep, budgetMs, owner ->
                        domainTransport.bundle(domains = domains, sleep = sleep, budgetMs = budgetMs, owner = owner)
                    }))
    }
}

/**
 * 12 · how often the app asks the band for the day. Chosen on the device page and kept on
 * this phone: it is about this phone's radio and battery, not about the account, so it is
 * not a profile field and never reaches the server.
 *
 * This does not control any sensor. Each automatic measurement uses the interval reported
 * by the device, while some historical SDK domains still return five-minute points.
 */
object SyncCadence {
    val options = listOf(5, 10, 15, 30, 60)
    const val default = 5
    private const val key = "nb.sync.everyMinutes"

    var minutes: Int
        get() {
            val v = BandPrefs.int(key) ?: 0
            return if (v in options) v else default
        }
        set(value) = BandPrefs.setInt(key, value)

    val interval: Double get() = (minutes * 60).toDouble()

    fun label(minutes: Int): String = if (minutes < 60) L("EVERY %d MIN", minutes) else L("EVERY HOUR")
}
