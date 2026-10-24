package com.nextbody.hoop.services

import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.HomeLaunchPolicy
import com.nextbody.hoop.band.SleepStageRun
import com.nextbody.hoop.band.SleepWindowCorrection
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.HomeSnapshotPort
import com.nextbody.hoop.data.LiveVitals
import com.nextbody.hoop.data.MealEntry
import com.nextbody.hoop.data.Profile
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.LoadPoint
import com.nextbody.hoop.model.NightInputs
import com.nextbody.hoop.model.OvernightOxygenPoint
import com.nextbody.hoop.model.ReserveDrivers
import com.nextbody.hoop.model.ReserveSample
import com.nextbody.hoop.model.SleepHRVPoint
import com.nextbody.hoop.model.SleepInterval
import com.nextbody.hoop.model.SleepRespirationPoint
import com.nextbody.hoop.model.SleepScore
import com.nextbody.hoop.model.SleepScoreLoadState
import com.nextbody.hoop.model.SleepSummary
import com.nextbody.hoop.model.TheCall
import com.nextbody.hoop.model.TrainingSegment
import com.nextbody.hoop.model.isSameDay
import com.nextbody.hoop.services.storage.LocalDataStore
import com.nextbody.hoop.services.storage.ReflectJson
import java.time.Instant

/**
 * Last successful Home payload on this phone. Painted before the first network round trip so a
 * returning launch is not three seconds of dashes; replaced by `loadHomeFast`.
 *
 * Android: persisted through [ReflectJson] (a local cache format; Swift used Codable). A payload
 * that no longer decodes after an app update is a cache miss, never a crash.
 */
object HomeSnapshot : HomeSnapshotPort {
    private const val version = 1
    private var hydratedAccount: String? = null

    /** Local detail must retain these fields explicitly, including the inputs behind WHY and THE CALL. */
    class Detail(
        var dayKey: String,
        var optimalZone: ClosedFloatingPointRange<Double>?,
        var segments: List<TrainingSegment>,
        var loadCurve: List<LoadPoint>,
        var peakHR: Int?,
        var reserveDrivers: ReserveDrivers?,
        var reserveCurve: List<ReserveSample>,
        var vitalsCurve: List<VitalSample>,
        var nightInputs: NightInputs?,
        var sleep: SleepSummary?,
        var bmrFull: Double?,
        var proteinIn: Int?,
        var carbIn: Int?,
        var fatIn: Int?,
        var serverCall: TheCall?,
    ) {
        constructor(m: DailyMetrics) : this(m.day.key, m.optimalZone, m.segments, m.loadCurve, m.peakHR,
            m.reserveDrivers, m.reserveCurve, m.vitalsCurve, m.nightInputs, m.sleep, m.bmrFull,
            m.proteinIn, m.carbIn, m.fatIn, m.serverCall)

        fun restore(source: DailyMetrics): DailyMetrics {
            val m = source.copy()
            m.optimalZone = optimalZone; m.segments = segments; m.loadCurve = loadCurve
            m.peakHR = peakHR; m.reserveDrivers = reserveDrivers; m.reserveCurve = reserveCurve
            m.vitalsCurve = vitalsCurve; m.nightInputs = nightInputs
            m.sleep = sleepForDay(sleep, m.day)
            m.bmrFull = bmrFull; m.proteinIn = proteinIn; m.carbIn = carbIn
            m.fatIn = fatIn; m.serverCall = serverCall
            m.trainingSettlement?.let { m.applyTrainingSettlement(it) }
            return m
        }
    }

    class Payload(
        var version: Int,
        var userId: String,
        var savedAt: Instant,
        var dayKey: String,
        var today: DailyMetrics,
        var todayVitals: List<VitalSample>,
        var todaySleep: SleepSummary?,
        var todaySegments: List<TrainingSegment>,
        var todayReserve: List<ReserveSample>,
        var yesterday: DailyMetrics?,
        var yesterdayVitals: List<VitalSample>,
        var meals: List<MealEntry>,
        var recentMeals: List<MealEntry>,
        var live: LiveVitals,
        var profile: Profile,
        var lastSync: Instant?,
        var boundAt: Instant? = null,
        var batteryPercent: Int?,
        var firmware: String,
        var netFatMass12w: Double?,
        var netLeanMass12w: Double?,
        var bodyFatPercent: Double?,
        var history: List<DailyMetrics>,
        var details: List<Detail>? = null,
        var sleepScores: Map<String, SleepScore>? = null,
    )

    /** Device measurements have no cache expiry; server-derived metrics remain in the snapshot. */
    class BandDay(var day: UserDay, var samples: List<VitalSample>, var sleep: SleepSummary?)

    class CachedDay(var metrics: DailyMetrics, var detail: Detail)

    private fun encode(value: Any): ByteArray = ReflectJson.stringify(value).toByteArray(Charsets.UTF_8)
    private inline fun <reified T> decode(bytes: ByteArray): T = ReflectJson.decode(String(bytes, Charsets.UTF_8), T::class.java)

    override fun hydrate(store: DataStore) = hydrate(store, Instant.now())

    fun hydrate(store: DataStore, now: Instant) {
        if (Band.allowsSeed) return
        val userId = SessionKeychain.userId ?: Jwt.subject(SessionKeychain.accessToken ?: "") ?: return
        hydratedAccount = userId
        load(userId)?.let { apply(it, store, now) }
        restoreBandObservations(store, userId, now)
        MealQueue.overlayPending(store, userId)
    }

    fun saveBandObservations(day: UserDay, samples: List<VitalSample>, sleep: SleepSummary?, userId: String) {
        val database = LocalDataStore.shared()
        val key = "band-day:" + day.key
        val existing = database.readObservationDocument(userId, key)?.let { decode<BandDay>(it) }
        val archived = BandDay(day,
            VitalSample.merging(existing?.samples ?: emptyList(), samples),
            mergedSleep(sleepForDay(existing?.sleep, day), sleepForDay(sleep, day)))
        database.writeObservationDocument(userId, key, encode(archived))
    }

    /** Sleep is filed under its local wake calendar date, independent of the user-day boundary. */
    private fun sleepForDay(sleep: SleepSummary?, day: UserDay): SleepSummary? {
        if (sleep == null) return null
        val wake = sleep.wakeAt
        if (wake != null && !wake.isSameDay(day.date)) return null
        return filteredSleep(sleep)
    }

    private fun filteredSleep(sleep: SleepSummary): SleepSummary {
        val result = sleep.copy()
        result.hrvInvalidatedMinutes = sleep.hrvInvalidatedMinutes?.filterKeys { sleep.containsSleepTimestamp(it) }
        result.hrv = sleep.hrv?.let { points ->
            SleepHRVPoint.merging(emptyList(), points, result.hrvInvalidatedMinutes ?: emptyMap())
                .filter { sleep.containsSleepTimestamp(it.ts) }
        }
        return result
    }

    private fun maxMerge(a: Map<Instant, Instant>, b: Map<Instant, Instant>): Map<Instant, Instant> {
        val out = HashMap(a)
        b.forEach { (k, v) -> out[k] = out[k]?.let { maxOf(it, v) } ?: v }
        return out
    }

    private fun mergedSleep(stored: SleepSummary?, fresh: SleepSummary?): SleepSummary? {
        if (fresh == null) return stored
        if (stored == null) return fresh
        // #28 · a corrected night's window is the person's answer.
        if (stored.isCorrected && !fresh.isCorrected) {
            val carried = fresh.copy()
            val anchor = fresh.sleepStart
            val start = stored.sleepStart
            val end = stored.wakeAt
            if (anchor != null && start != null && end != null) {
                val restored = SleepWindowCorrection.restoreReportedWindow(
                    totalMinutes = stored.totalMinutes,
                    deviceRuns = fresh.line.map { SleepWindowCorrection.LineRun(it.stage, it.minutes, it.offsetMinutes) },
                    bandStart = anchor, start = start, end = end,
                    recordedIntervals = fresh.intervals ?: emptyList())
                carried.line = restored.line.map { SleepStageRun(stage = it.stage, minutes = it.minutes, offsetMinutes = it.offsetMinutes) }
                carried.totalMinutes = restored.totalMinutes
                // Fresh totals belong to the band's unedited window.
                if (carried.line.isNotEmpty()) {
                    carried.deepMinutes = carried.line.filter { it.stage == 0 }.sumOf { it.minutes }
                    carried.lightMinutes = carried.line.filter { it.stage == 1 }.sumOf { it.minutes }
                } else {
                    carried.deepMinutes = stored.deepMinutes
                    carried.lightMinutes = stored.lightMinutes
                }
            }
            carried.sleepStart = stored.sleepStart
            carried.wakeAt = stored.wakeAt
            carried.correctedAt = stored.correctedAt
            carried.source = stored.source
            carried.bandStart = fresh.sleepStart ?: stored.bandStart
            carried.bandEnd = fresh.wakeAt ?: stored.bandEnd
            carried.totalMinutes = stored.totalMinutes
            carried.wakeCount = stored.wakeCount
            carried.heartRate = stored.heartRate
            return mergedSleep(stored, carried)
        }
        val sameWindow = stored.sleepStart == fresh.sleepStart && stored.wakeAt == fresh.wakeAt
        val oldStart = stored.sleepStart; val oldEnd = stored.wakeAt
        val newStart = fresh.sleepStart; val newEnd = fresh.wakeAt
        val containedPartial = oldStart != null && oldEnd != null && newStart != null && newEnd != null &&
            newStart >= oldStart && newEnd <= oldEnd && !sameWindow
        val invalidations = maxMerge(stored.hrvInvalidatedMinutes ?: emptyMap(), fresh.hrvInvalidatedMinutes ?: emptyMap())
        if (!sameWindow && !containedPartial) {
            val result = fresh.copy()
            // Corrections identify measured instants; retain them across an overlapping revision.
            result.hrvInvalidatedMinutes = invalidations.ifEmpty { null }
            val overlappingHRV = (stored.hrv ?: emptyList()).filter { fresh.containsSleepTimestamp(it.ts) }
            if (overlappingHRV.isNotEmpty() || fresh.hrv != null) {
                result.hrv = SleepHRVPoint.merging(overlappingHRV, fresh.hrv ?: emptyList(), invalidations)
            }
            return filteredSleep(result)
        }
        val result = (if (containedPartial) stored else fresh).copy()
        result.hrvInvalidatedMinutes = invalidations.ifEmpty { null }
        result.intervals = result.intervals ?: stored.intervals
        if (result.line.isEmpty()) result.line = stored.line
        result.spo2 = LinkedHashMap<Instant, OvernightOxygenPoint>().also { m ->
            (stored.spo2 + fresh.spo2).forEach { m[it.ts] = it }
        }.values.sortedBy { it.ts }
        if (stored.respiration != null || fresh.respiration != null) {
            result.respiration = LinkedHashMap<Instant, SleepRespirationPoint>().also { m ->
                ((stored.respiration ?: emptyList()) + (fresh.respiration ?: emptyList())).forEach { m[it.ts] = it }
            }.values.sortedBy { it.ts }
        }
        if (stored.hrv != null || fresh.hrv != null) {
            result.hrv = SleepHRVPoint.merging(stored.hrv ?: emptyList(), fresh.hrv ?: emptyList(), invalidations)
        }
        return filteredSleep(result)
    }

    /** The same observation overlay is used at launch and when reopening a cached detail. */
    fun restoringObservations(metrics: DailyMetrics, samples: List<VitalSample>, sleep: SleepSummary?): DailyMetrics {
        val result = metrics.copy()
        result.vitalsCurve = VitalSample.merging(metrics.vitalsCurve, samples)
        result.sleep = mergedSleep(sleepForDay(metrics.sleep, metrics.day), sleepForDay(sleep, metrics.day))
        return result
    }

    private fun restoreBandObservations(store: DataStore, userId: String, now: Instant) {
        try {
            val documents = LocalDataStore.shared().observationDocuments(userId)
            val current = UserDay.containing(now)
            val history = store.history.toMutableList()
            for (document in documents) {
                val archived = try { decode<BandDay>(document) } catch (e: Exception) {
                    ServiceLog.record("Band observation archive decode failed", e); continue
                }
                fun restore(m: DailyMetrics) = restoringObservations(m, archived.samples, archived.sleep)
                if (archived.day == current) {
                    store.today = restore(store.today)
                } else {
                    val index = history.indexOfFirst { it.day == archived.day }
                    if (index >= 0) history[index] = restore(history[index])
                    else history += restore(DailyMetrics(day = archived.day))
                }
            }
            store.history = history.sortedBy { it.day }
        } catch (e: Exception) { ServiceLog.record("Band observation archive read failed", e) }
    }

    fun save(store: DataStore): Boolean = save(store, Instant.now())

    fun save(store: DataStore, now: Instant): Boolean {
        if (Band.allowsSeed) return true
        val userId = SupabaseClient.currentUserIdSnapshot() ?: SessionKeychain.userId ?: return false
        hydratedAccount = userId
        val today = store.today
        val yesterdayDay = today.day.adding(-1)
        val yesterday = store.history.firstOrNull { it.day == yesterdayDay }
        val payload = Payload(
            version = version, userId = userId, savedAt = now, dayKey = today.day.key,
            today = today, todayVitals = today.vitalsCurve, todaySleep = today.sleep,
            todaySegments = today.segments, todayReserve = today.reserveCurve,
            yesterday = yesterday, yesterdayVitals = yesterday?.vitalsCurve ?: emptyList(),
            meals = store.meals, recentMeals = store.recentMeals, live = store.vitals,
            profile = store.profile, lastSync = store.lastSync, boundAt = store.boundAt,
            batteryPercent = store.band.batteryPercent, firmware = store.band.firmware,
            netFatMass12w = store.netFatMass12w, netLeanMass12w = store.netLeanMass12w,
            bodyFatPercent = store.bodyFatPercent,
            history = store.history.takeLast(183),
            details = (store.history.takeLast(14) + today).map { Detail(it) },
            sleepScores = store.sleepScores)
        val data = try { encode(payload) } catch (e: Exception) {
            ServiceLog.record("Home cache encode failed", e); return false
        }
        return try {
            val cache = LocalDataStore.shared()
            cache.writeDocument(userId, "home", data, expiresAt = now.epochSecond + 30.0 * 86_400)
            cache.pruneCache(16 * 1024 * 1024, now.epochSecond.toDouble())
            WidgetGlancePublisher.publish(store, numbersAt = now)
            true
        } catch (e: Exception) {
            ServiceLog.record("Home cache save failed", e)
            false
        }
    }

    fun saveDetail(metrics: DailyMetrics, userId: String, now: Instant = Instant.now()) {
        try {
            val data = encode(CachedDay(metrics, Detail(metrics)))
            val cache = LocalDataStore.shared()
            cache.writeDocument(userId, "day:" + metrics.day.key, data, expiresAt = now.epochSecond + 14.0 * 86_400)
            cache.pruneCache(16 * 1024 * 1024, now.epochSecond.toDouble())
        } catch (e: Exception) { ServiceLog.record("Detail cache save failed", e) }
    }

    fun loadDetail(day: UserDay, userId: String): DailyMetrics? = try {
        val database = LocalDataStore.shared()
        database.readDocument(userId, "day:" + day.key)?.let { data ->
            val cached = decode<CachedDay>(data)
            if (cached.metrics.day != day || cached.detail.dayKey != day.key) null
            else {
                val restored = cached.detail.restore(cached.metrics)
                val archived = runCatching {
                    database.readObservationDocument(userId, "band-day:" + day.key)?.let { decode<BandDay>(it) }
                }.getOrNull()
                if (archived == null || archived.day != day) restored
                else restoringObservations(restored, archived.samples, archived.sleep)
            }
        }
    } catch (e: Exception) { ServiceLog.record("Detail cache read failed", e); null }

    fun remove(userId: String) {
        runCatching { LocalDataStore.shared().removeDocuments(userId) }
    }

    override fun removeAll() {
        val account = hydratedAccount ?: SessionKeychain.userId ?: SupabaseClient.currentUserIdSnapshot()
        if (account != null) runCatching { LocalDataStore.shared().removeDocuments(account) }
        hydratedAccount = null
    }

    fun apply(payload: Payload, store: DataStore, now: Instant) {
        val current = UserDay.containing(now)
        store.profile = payload.profile.restoringHealthSync()
        var band = store.band.copy()
        payload.batteryPercent?.let { band = band.copy(batteryPercent = it) }
        if (payload.firmware.isNotEmpty()) band = band.copy(firmware = payload.firmware)
        store.band = band
        store.netFatMass12w = payload.netFatMass12w
        store.netLeanMass12w = payload.netLeanMass12w
        store.bodyFatPercent = payload.bodyFatPercent
        store.recentMeals = payload.recentMeals
        payload.boundAt?.let { store.boundAt = it }

        fun restored(m: DailyMetrics): DailyMetrics {
            val result = payload.details?.lastOrNull { it.dayKey == m.day.key }?.restore(m) ?: m.copy()
            // Targets and sessions live in the metrics for the whole history.
            result.trainingSettlement?.let { result.applyTrainingSettlement(it) }
            result.sleep = sleepForDay(result.sleep, result.day)
            return result
        }
        val history = payload.history.map(::restored).toMutableList()
        if (HomeLaunchPolicy.shouldPaintToday(payload.dayKey, current.key)) {
            val today = restored(payload.today)
            today.vitalsCurve = payload.todayVitals
            today.sleep = sleepForDay(payload.todaySleep, today.day)
            today.segments = payload.todaySegments
            today.reserveCurve = payload.todayReserve
            store.today = today
            store.meals = payload.meals
            store.recentMeals = payload.recentMeals
            store.vitals = payload.live
            store.lastSync = payload.lastSync
            payload.yesterday?.let { y ->
                val row = restored(y)
                row.vitalsCurve = payload.yesterdayVitals
                val index = history.indexOfFirst { it.day == row.day }
                if (index >= 0) history[index] = row else history += row
            }
        }
        store.history = history.sortedBy { it.day }
        // The dictionary is authoritative; a deleted score must not reappear from an older detail.
        val from = current.adding(-29).key
        store.sleepScores = (payload.sleepScores ?: emptyMap()).filterKeys { it >= from && it <= current.key }
        store.sleepScoreLoadState = SleepScoreLoadState.idle
        store.today = store.today.copy().also { it.sleepScore = store.sleepScores[it.day.key] }
        store.history = store.history.map { m -> m.copy().also { it.sleepScore = store.sleepScores[m.day.key] } }
    }

    private fun load(userId: String): Payload? = try {
        val data = LocalDataStore.shared().readDocument(userId, "home")
        val payload = data?.let { runCatching { decode<Payload>(it) }.getOrNull() }
        if (payload == null || payload.version != version || payload.userId != userId ||
            Instant.now().epochSecond - payload.savedAt.epochSecond > 30L * 86_400) null else payload
    } catch (e: Exception) {
        ServiceLog.record("Home cache read failed", e); null
    }
}
