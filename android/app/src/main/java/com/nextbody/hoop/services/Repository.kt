package com.nextbody.hoop.services

import com.nextbody.hoop.app.PushSettle
import com.nextbody.hoop.band.*
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.LiveVitals
import com.nextbody.hoop.data.MealEntry
import com.nextbody.hoop.data.RepositoryPort
import com.nextbody.hoop.data.SessionStore
import com.nextbody.hoop.data.WeighIn
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.*
import com.nextbody.hoop.services.storage.LocalDataStore
import com.nextbody.hoop.services.storage.parseUuid
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/**
 * F3 §05 · reading. The home screen reads one row of daily_results. A detail page reads
 * daily_results plus its detail row, joined by result_id.
 * ⚠️ No detail page ever starts a second computation. If the join misses, the screen degrades
 * in place to "——" — it does not compute a substitute and does not send a second request.
 *
 * Every entry point hops to the main thread (Swift `@MainActor`): DataStore is Compose state.
 */
object Repository : RepositoryPort {
    private enum class SettleAttempt { success, busy, retryableFailure, failure }

    val shared: Repository get() = this
    val db: SupabaseClient get() = SupabaseClient

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** The bound NEXTBODY's row id; sync_runs and device_capabilities both name it. */
    var deviceId: String? = null
        private set

    /** The link moved to the other slot; sync_runs and capabilities now name that row. */
    fun adoptTransportDevice(id: String?) { deviceId = id }

    private var homeFastTask: Job? = null
    private val evidencePublication = EvidencePublicationDrain()
    private var homeFastDone = false
    private var readGeneration: Long = 0
    private var sleepScoreGeneration: Long = 0
    private var summaryReadGeneration: Long = 0
    var sessionGeneration: Long = 0
        private set
    private val summaryRevisions = mutableMapOf<String, Map<String, String>>()

    /** Features/Vitals/SleepCorrection.horizonDays — the correctable window. */
    private const val SLEEP_CORRECTION_HORIZON_DAYS = 30

    /** Issue #21 · when this account last asked the server to settle today from the foreground. */
    private var lastForegroundSettleAt: Instant? = null

    private suspend fun <T> main(block: suspend CoroutineScope.() -> T): T =
        withContext(Dispatchers.Main.immediate, block)

    private fun account(): String? = SupabaseClient.currentUserIdSnapshot()

    private suspend fun cancelled(): Boolean = !currentCoroutineContext().isActive

    // region session

    /**
     * Open a session before Home reads. A real session from the gate is never replaced.
     * Emulator: restore, or sign in as the seeded demo account. Device: restore only; a leftover
     * demo@ session is dropped so the gate comes back.
     */
    suspend fun openSession() {
        if (db.restoreSession()) {
            if (!Band.allowsSeed && DemoAccount.matches(db.signedInEmail() ?: "")) db.signOut()
            return
        }
        if (!Band.allowsSeed) return
        db.signIn(DemoAccount.email, DemoAccount.password)
    }

    override fun resetBootstrap() {
        deviceId = null
        summaryRevisions.clear()
        homeFastTask?.cancel()
        evidencePublication.cancel()
        SportRecapStore.reset()
        readGeneration += 1
        sessionGeneration += 1
        sleepScoreGeneration += 1
        summaryReadGeneration += 1
        homeFastTask = null
        homeFastDone = false
    }

    /**
     * Session plus today's row. History, composition and capability tables follow in the
     * background so Home is not held behind 182 days of `daily_results`.
     */
    override suspend fun bootstrapHome(store: DataStore): Unit = main {
        // Emulator seed is the walk-through ledger; cloud rows for the demo session must not replace it.
        if (Band.allowsSeed) {
            runCatching { openSession() }
            homeFastDone = true
            return@main
        }
        homeFastTask?.join()
        if (homeFastDone) return@main
        val task = mainScope.launch {
            runCatching { openSession() }.onFailure { if (it is CancellationException) throw it }
            val account = account()
            if (account == null || !isActive) return@launch
            loadHomeFast(store)
            store.hydrateBatteryLog()
            if (account != account() || !isActive) return@launch
            HomeSnapshot.save(store)
            if (store.isOffline) return@launch
            homeFastDone = true
            mainScope.launch {
                if (account != account()) return@launch
                loadHomeRest(store)
                if (account != account()) return@launch
                HomeSnapshot.save(store)
            }
        }
        homeFastTask = task
        task.join()
    }

    suspend fun loadToday(into: DataStore) = bootstrapHome(into)

    private suspend fun loadHomeFast(store: DataStore) = coroutineScope {
        val today = UserDay.containing(Instant.now())
        val profile = async { loadProfile(store, ensureRow = false) }
        val day = async { load(HomeLaunchPolicy.fastLoadLookbackDays, today, store) }
        profile.await(); day.await()
    }

    private suspend fun loadHomeRest(store: DataStore) {
        val generation = sessionGeneration
        val today = UserDay.containing(Instant.now())
        if (generation != sessionGeneration) return
        loadProfile(store, ensureRow = true)
        if (generation != sessionGeneration) return
        // 11 · the heat map is twenty-six columns of seven days.
        loadHistorySummaries(182, today, store)
        if (generation != sessionGeneration) return
        // ADR 0008 · thirty nights of sleep score.
        loadSleepScores(30, today, store)
        if (generation != sessionGeneration) return
        loadComposition(store)
        if (generation != sessionGeneration) return
        loadMeasurements(store)
        if (generation != sessionGeneration) return
        loadCapabilities(store)
        if (generation != sessionGeneration) return
        loadLastSync(store)
        if (generation != sessionGeneration) return
        WeighInQueue.flush()
        if (generation != sessionGeneration) return
        BodyCompositionQueue.flush()
        if (generation != sessionGeneration) return
        BalanceCheckQueue.flush()
        if (generation != sessionGeneration) return
        flushPendingEvidence()
    }

    /** Hand the account's write/settlement work over to the band refresh in order. */
    suspend fun waitForEvidencePublication() = main { evidencePublication.waitForCurrent() }

    override suspend fun flushPendingEvidence() = flushPendingEvidence(afterCurrent = false)

    /** Account-owned outboxes can retry without a connected band or an active sensor read. */
    suspend fun flushPendingEvidence(afterCurrent: Boolean) = main {
        if (Band.allowsSeed) return@main
        val account = account() ?: return@main
        if (!Reachability.isOnline) return@main
        val generation = sessionGeneration
        evidencePublication.run(afterCurrent = afterCurrent,
            authorized = { account == account() && generation == sessionGeneration },
            publish = {
                if (afterCurrent) lastForegroundSettleAt = null
                publishPendingEvidence(account, generation)
            })
    }

    private fun current(account: String, generation: Long) =
        account == account() && generation == sessionGeneration

    private suspend fun publishPendingEvidence(account: String, generation: Long) {
        if (!current(account, generation) || cancelled()) return
        MealQueue.flush()
        if (!current(account, generation)) return
        OriginDataSync.flushPendingEvidence(userId = account)
        if (!current(account, generation) || cancelled()) return
        SportEvidenceQueue.flush()
        if (!current(account, generation) || cancelled()) return
        SportRecapStore.flush()
        if (!current(account, generation) || cancelled()) return
        if (!WeighInQueue.flush()) {
            if (current(account, generation)) {
                SportRecapStore.trainingError = L("Updated weight is waiting to upload. Retry sync.")
            }
            return
        }
        if (!current(account, generation) || cancelled()) return
        val today = UserDay.containing(Instant.now())
        try {
            val status = calculationStatusIfAvailable(today.key, today.key)
            val pending: List<Boolean?>? = status?.map { row ->
                if (row.optStringOrNull("result_revision") == null) null else row.opt("pending") as? Boolean
            }
            if (!HomeLaunchPolicy.shouldSettleOnForeground(pending, lastForegroundSettleAt,
                    bandRefreshActive = !OriginDataSync.isIdle) ||
                !current(account, generation) || cancelled()) return
            lastForegroundSettleAt = Instant.now()
            // The server drains its persisted dirty range, even when this retry uploaded no new facts.
            db.rpc("settle_now", mapOf("p_days" to 0), expectedOwner = account)
            if (!current(account, generation) || cancelled()) return
            // loadToday is a cached bootstrap and would keep showing the old result.
            load(HomeLaunchPolicy.fastLoadLookbackDays, today, DataStore)
            if (!current(account, generation)) return
            loadSleepScores(30, today, DataStore)
            if (!current(account, generation)) return
            HomeSnapshot.save(DataStore)
        } catch (e: Exception) {
            if (current(account, generation)) {
                SportRecapStore.trainingError = L("Training could not update. Retry sync.")
                lastForegroundSettleAt = null
            }
            BandLog.shared.record("publish drained evidence", error = e)
            if (e is CancellationException && e !is SessionChangedException) throw e
        }
    }

    // endregion

    // region profile, devices

    suspend fun loadLastSync(store: DataStore) = main {
        val generation = sessionGeneration
        val account = account()
        val rows = runCatching {
            db.select("devices", listOf(
                "select" to "id,last_origin_sync_at,bound_at",
                "unbound_at" to "is.null",
                "slot" to "eq.${BoundBand.transportSlot.raw}",
                "limit" to "1"))
        }.getOrNull() ?: return@main
        val row = rows.firstOrNull() ?: return@main
        if (account == null || account != account() || generation != sessionGeneration) return@main
        row.optStringOrNull("id")?.let { deviceId = it }
        store.lastSync = timestamp(row.optStringOrNull("last_origin_sync_at"))
        loadCompanionSince(store, generation, account)
    }

    /**
     * The profile exists from onboarding onwards; failing to read it is a serious fault, so
     * the screen keeps whatever it already had rather than blanking the identity card.
     */
    suspend fun loadProfile(store: DataStore, ensureRow: Boolean = true) = main {
        val generation = sessionGeneration
        val account = account()
        val (found, device) = coroutineScope {
            val profileRows = async { runCatching { db.select("profiles", listOf(
                "select" to "display_name,sex,height_cm,birth_date,goal,units_metric,timezone",
                "limit" to "1")) }.getOrNull() }
            val deviceRows = async { runCatching { db.select("devices", listOf(
                "select" to "id,firmware_version,battery_percent,device_number,last_origin_sync_at,bound_at",
                // The bound one in the transport slot. A forgotten NEXTBODY keeps its row.
                "unbound_at" to "is.null",
                "slot" to "eq.${BoundBand.transportSlot.raw}",
                "limit" to "1")) }.getOrNull() }
            profileRows.await()?.firstOrNull() to deviceRows.await()?.firstOrNull()
        }
        if (account == null || account != account() || generation != sessionGeneration) return@main
        // The row must exist and carry this phone's zone before anything can be computed.
        if (ensureRow) ensureProfileRow(found?.optStringOrNull("timezone"))
        if (account != account() || generation != sessionGeneration) return@main
        val mail = db.signedInEmail()
        if (account != account() || generation != sessionGeneration) return@main
        if (device != null) {
            deviceId = device.optStringOrNull("id")
            // Network hydration may finish after early BLE readiness. Never replace a session's
            // real device observation with a cached cloud row.
            if (store.bandObservationRevision == 0 && !store.band.connected) {
                var band = store.band.copy()
                device.optStringOrNull("firmware_version")?.let { band = band.copy(firmware = it) }
                device.number("battery_percent")?.let { band = band.copy(batteryPercent = it.toInt()) }
                store.band = band
            }
            if (store.lastSync == null) store.lastSync = timestamp(device.optStringOrNull("last_origin_sync_at"))
        }
        loadCompanionSince(store, generation, account)
        val row = found ?: return@main
        var profile = store.profile.copy()
        row.optStringOrNull("display_name")?.takeIf { it.isNotEmpty() }?.let { profile = profile.copy(name = it) }
        // The address is whoever is signed in — never a placeholder next to real numbers.
        if (mail != null) profile = profile.copy(email = mail)
        row.number("height_cm")?.let { profile = profile.copy(heightCm = it) }
        row.optStringOrNull("sex")?.let { profile = profile.copy(sexIsMale = it == "male") }
        row.optStringOrNull("goal")?.let(Goal::fromRaw)?.let { profile = profile.copy(goal = it) }
        row.optBoolOrNull("units_metric")?.let { profile = profile.copy(usesMetric = it) }
        row.optStringOrNull("birth_date")?.let { birth ->
            parseDay(birth.take(10))?.let { profile = profile.copy(birthdate = it) }
        }
        store.profile = profile
    }

    /** `yyyy-MM-dd` at local midnight (Swift DateFormatter in the current zone). */
    private fun parseDay(s: String): Instant? =
        runCatching { LocalDate.parse(s).atStartOfDay(ZoneId.systemDefault()).toInstant() }.getOrNull()

    /** A UserDay from the server's `user_day`, at the boundary hour. */
    private fun userDay(key: String?): UserDay? {
        val date = key?.take(10)?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: return null
        val zone = ZoneId.systemDefault()
        return UserDay(date.atTime(UserDay.boundaryHour, 0).atZone(zone).toInstant())
    }

    /**
     * F0 rule 09 · every field carries its own source. MEASURED re-anchors the EMA;
     * weight × body-fat % is DERIVED and never written back over history.
     */
    suspend fun loadComposition(store: DataStore) = main {
        val generation = sessionGeneration
        val account = account()
        val rows = runCatching { db.select("body_composition", listOf(
            "select" to "id,measured_at,body_fat_pct,fat_mass_kg,lean_body_mass_kg,bmr_kcal,input_weight_kg,measurement_source,muscle_mass_kg,body_water_pct,bone_mass_kg,protein_pct",
            "order" to "measured_at.desc",
            "limit" to "200")) }.getOrNull() ?: return@main
        if (account == null || account != account() || generation != sessionGeneration) return@main
        store.compositionScans = compositionScans(rows)
        val latest = rows.firstOrNull() ?: return@main
        store.today = store.today.copy().also { t ->
            t.fatKg = latest.number("fat_mass_kg")
            t.leanKg = latest.number("lean_body_mass_kg")
            t.fatSource = if (latest.optStringOrNull("measurement_source") == "manual") MeasurementSource.derived else MeasurementSource.measured
        }

        // 12 · WEEK averages fat and lean across seven days and compares that to the seven before.
        val byDay = HashMap<UserDay, Pair<Double?, Double?>>()
        for (row in rows) {
            val at = timestamp(row.optStringOrNull("measured_at")) ?: continue
            byDay[UserDay.containing(at)] = row.number("fat_mass_kg") to row.number("lean_body_mass_kg")
        }
        val history = store.history.map { m ->
            val scan = byDay[m.day] ?: return@map m
            m.copy().also { it.fatKg = scan.first; it.leanKg = scan.second }
        }
        if (history != store.history) store.history = history

        /** The oldest row at least `daysAgo` old — or the oldest row there is. */
        fun at(daysAgo: Int): JSONObject? {
            val cutoff = Instant.now().addingTimeInterval(-daysAgo.toDouble() * 86_400)
            val older = rows.firstOrNull { row -> timestamp(row.optStringOrNull("measured_at"))?.let { it <= cutoff } ?: false }
            return older ?: rows.lastOrNull()
        }
        val weekAgo = at(7)
        val now = Instant.now()
        store.today = store.today.copy().also { t ->
            if (weekAgo != null) {
                t.fatEmaDelta7d = (latest.number("fat_mass_kg") ?: 0.0) - (weekAgo.number("fat_mass_kg") ?: 0.0)
                t.leanEmaDelta7d = (latest.number("lean_body_mass_kg") ?: 0.0) - (weekAgo.number("lean_body_mass_kg") ?: 0.0)
            }
            t.scans7d = rows.count { row ->
                timestamp(row.optStringOrNull("measured_at"))?.let { it >= now.addingTimeInterval(-7.0 * 86_400) } ?: false
            }
        }
        // 11 · the three tiles are 12-week net changes, except BODY FAT which is absolute.
        at(84)?.let { twelveWeeks ->
            store.netFatMass12w = (latest.number("fat_mass_kg") ?: 0.0) - (twelveWeeks.number("fat_mass_kg") ?: 0.0)
            store.netLeanMass12w = (latest.number("lean_body_mass_kg") ?: 0.0) - (twelveWeeks.number("lean_body_mass_kg") ?: 0.0)
        }
        store.bodyFatPercent = latest.number("body_fat_pct")
    }

    /** F1 §02 facts for the gate. RLS scopes both reads; a missing row is "not yet", not an error. */
    suspend fun fetchAccountGate(): AccountGate = main {
        val facts = AccountGate()
        coroutineScope {
            val deviceRows = async { runCatching { db.select("devices", listOf(
                "select" to "id", "unbound_at" to "is.null", "limit" to "1")) }.getOrNull() }
            val profileRows = async { runCatching { db.select("profiles", listOf(
                "select" to "display_name,sex,height_cm,birth_date,goal", "limit" to "1")) }.getOrNull() }
            val weighRows = async { runCatching { db.select("weigh_ins", listOf(
                "select" to "weight_kg", "order" to "measured_at.desc", "limit" to "1")) }.getOrNull() }
            deviceRows.await()?.firstOrNull()?.let { device ->
                facts.hasBoundBand = true
                device.optStringOrNull("id")?.let { deviceId = it }
            }
            profileRows.await()?.firstOrNull()?.let { row ->
                facts.displayName = row.optStringOrNull("display_name")
                facts.sex = row.optStringOrNull("sex")
                facts.heightCm = row.number("height_cm")
                row.optStringOrNull("birth_date")?.let { facts.birthDate = parseDay(it.take(10)) }
                row.optStringOrNull("goal")?.let { facts.goal = Goal.fromRaw(it) }
            }
            weighRows.await()?.firstOrNull()?.let { facts.weightKg = it.number("weight_kg") }
        }
        facts
    }

    override suspend fun fetchAccountGateStage(): SessionStore.Stage = fetchAccountGate().stage

    /**
     * The transport NEXTBODY's row, written at the end of pairing. One bound row per slot; a new
     * BLE alias in the same slot is the same band on a different phone: patched, never re-inserted.
     *
     * Only `pairing` — the person choosing this band on the pairing screen — may create a row
     * or point one at a different band. A refresh only updates the facts of the row it already
     * has; it never binds the band it happens to be connected to.
     */
    suspend fun registerDevice(identity: BandIdentity?, battery: BandBattery?, slot: HoopSlot? = null,
                               pairing: Boolean = false): DeviceRegistration = main {
        val userId = db.currentUserId ?: return@main DeviceRegistration.failed
        val slot = slot ?: BoundBand.transportSlot
        val row = mutableMapOf<String, Any?>()
        if (identity != null) {
            row["firmware_version"] = identity.firmware
            row["device_number"] = identity.deviceNumber
        }
        if (battery != null) {
            // ⚠️ Three columns together (02 rule 05): a bar count is never stored as a percent.
            row["battery_is_percent"] = battery.isPercent
            battery.percent?.let { row["battery_percent"] = it }
            battery.level?.let { row["battery_level"] = it }
        }
        val ble = identity?.bleIdentifier ?: DeviceSlots.binding(slot)?.identifier
        // The key this phone files evidence under is what the wearer rule matches.
        val clientKey = DeviceSlots.binding(slot)?.identifier
        if (clientKey != null && clientKey != BoundBand.seedIdentifier) row["client_key"] = clientKey
        try {
            val bound = db.select("devices", listOf(
                "select" to "id,ble_identifier,device_number,bound_at,slot",
                "unbound_at" to "is.null",
                "slot" to "eq.${slot.raw}",
                "limit" to "1")).firstOrNull()
            val id = bound?.optStringOrNull("id")
            if (id != null) {
                val existingBle = bound.optStringOrNull("ble_identifier")
                // Emulator seed must not steal a real binding and reset companionship.
                // Outside pairing the row keeps the band it names; a refresh writes only its facts.
                DeviceRegistration.bleIdentifierWrite(pairing, existingBle, ble, BoundBand.seedIdentifier)?.let {
                    row["ble_identifier"] = it
                    row["ble_identifier_kind"] = if (isBandMac(it)) "mac" else "uuid"
                }
                if (row.isNotEmpty()) db.patch("devices", id, row)
                rememberDevice(id, slot, bound.opt("bound_at"), identity?.name)
            } else if (pairing && ble != null) {
                row["user_id"] = userId
                row["ble_identifier"] = ble
                row["ble_identifier_kind"] = if (isBandMac(ble)) "mac" else "uuid"
                row["slot"] = slot.raw
                val inserted = db.insert("devices", row).firstOrNull()
                val newId = inserted?.optStringOrNull("id") ?: return@main DeviceRegistration.failed
                rememberDevice(newId, slot, inserted.opt("bound_at")?.takeIf { it != JSONObject.NULL } ?: Instant.now(), identity?.name)
            } else return@main DeviceRegistration.failed
            loadCompanionSince(DataStore)
            DeviceRegistration.saved
        } catch (e: Exception) {
            if (e is CancellationException && e !is SessionChangedException) throw e
            ServiceLog.record("Repository.registerDevice failed", e)
            DeviceRegistration.refusal(e)
        }
    }

    /** Release exactly the selected binding. Failure must leave the phone paired. */
    suspend fun releaseDevice(id: String): JSONObject {
        val result = db.rpc("release_device", mapOf("p_device_id" to id), timeoutSeconds = 12) as? JSONObject
        if (result == null || result.opt("devices") !is JSONArray) throw BandError.Rejected("Invalid device release response")
        return result
    }

    /** The server's view of the set: both bound rows and every wear declaration. */
    suspend fun loadDeviceSet(): JSONObject = db.rpc("wear_timeline") as? JSONObject ?: JSONObject()

    /** This phone's key for one band of the set; held ticks under it are re-projected. */
    suspend fun claimDeviceKey(deviceId: String, clientKey: String): JSONObject =
        db.rpc("claim_device_key", mapOf("p_device_id" to deviceId, "p_client_key" to clientKey)) as? JSONObject ?: JSONObject()

    /**
     * One declaration: the person wears the band in `deviceId`. A null `effectiveAt` says "from
     * now, and work out when I put it on"; a date is a time the wearer pinned by hand.
     */
    suspend fun recordWearEvent(deviceId: String, effectiveAt: Instant?, opId: String): JSONObject =
        db.rpc("record_wear_event", mapOf(
            "p_device_id" to deviceId,
            "p_effective_at" to effectiveAt?.let { Iso.string(it) },
            "p_client_op_id" to opId)) as? JSONObject ?: JSONObject()

    /** After the newly worn band has been read: let its own wrist evidence move the start. */
    suspend fun settleWearStart(opId: String? = null): JSONObject =
        db.rpc("settle_wear_start", mapOf("p_client_op_id" to opId)) as? JSONObject ?: JSONObject()

    /** The transport slot's device row id and binding start, kept on the slot binding. */
    private fun rememberDevice(id: String?, slot: HoopSlot, boundAt: Any?, name: String?) {
        var binding = DeviceSlots.binding(slot)
        val identifier = BoundBand.identifier
        if (binding == null && identifier != null && slot == BoundBand.transportSlot) {
            binding = SlotBinding(slot = slot, identifier = identifier)
        }
        val b = binding?.copy() ?: return
        if (id != null) b.deviceId = id
        if (!name.isNullOrEmpty()) b.name = name
        val start = (boundAt as? String)?.let(::timestamp) ?: (boundAt as? Instant)
        if (start != null && (b.boundAt == null || start < b.boundAt!!)) b.boundAt = start
        DeviceSlots.set(b)
        if (slot == BoundBand.transportSlot) {
            deviceId = b.deviceId
            applyBoundAt(boundAt as? String, DataStore, start)
        }
    }

    /** `devices.last_origin_sync_at` — the completion time of a fully successful band sync. */
    suspend fun markDeviceSynced(at: Instant) {
        val id = deviceId ?: return
        try {
            db.patch("devices", id, mapOf("last_origin_sync_at" to Iso.string(at)))
        } catch (e: Exception) {
            if (e is CancellationException && e !is SessionChangedException) throw e
            BandLog.shared.record("patch last_origin_sync_at", error = e)
        }
    }

    /**
     * F3 · the day's row is computed on the server and nowhere else. Asks for the caller's own
     * window now. Quiet when the RPC is not deployed yet — the cron still comes round.
     */
    suspend fun settleNow(days: Int): Boolean {
        val started = Instant.now()
        try {
            return when (invokeSettle(days)) {
                SettleAttempt.success, SettleAttempt.busy -> true
                SettleAttempt.failure -> false
                SettleAttempt.retryableFailure -> {
                    NightDiagnostics.shared.record("sync.settlement_retry", mapOf("days" to days.toString()))
                    when (invokeSettle(days)) {
                        SettleAttempt.success, SettleAttempt.busy -> true
                        else -> false
                    }
                }
            }
        } finally {
            NightDiagnostics.shared.record("sync.settlement", mapOf(
                "days" to days.toString(),
                "durationSeconds" to Instant.now().timeIntervalSince(started).toString()))
        }
    }

    private suspend fun invokeSettle(days: Int): SettleAttempt {
        return try {
            val response = db.rpc("settle_now", mapOf("p_days" to days))
            if (response is Number && response.toInt() == -1) {
                NightDiagnostics.shared.record("sync.settlement_busy", mapOf("days" to days.toString()))
                SettleAttempt.busy
            } else SettleAttempt.success
        } catch (e: Exception) {
            if (e is CancellationException && e !is SessionChangedException) throw e
            BandLog.shared.record("settle_now", error = e)
            val fields = mutableMapOf("kind" to e::class.java.simpleName)
            if (e is SupabaseFailure.Http) {
                fields["httpStatus"] = e.code.toString()
                val code = runCatching { JSONObject(e.body).optStringOrNull("code") }.getOrNull()
                if (code != null && code.length <= 12 && code.all { it.code < 128 && it.isLetterOrDigit() }) fields["serverCode"] = code
            } else if (e is SupabaseFailure.Transport) {
                fields["transportCode"] = e.error::class.java.simpleName
            }
            NightDiagnostics.shared.record("sync.settlement_failed", fields)
            if (BandSyncPolicy.retriesSettle(e)) SettleAttempt.retryableFailure else SettleAttempt.failure
        }
    }

    /**
     * After a real session the ingest trigger has dirtied today. Drop the foreground throttle so
     * flush settles and reloads training load (#37).
     */
    suspend fun settleAfterSport() = main {
        if (Band.allowsSeed) return@main
        val owner = account() ?: return@main
        val generation = sessionGeneration
        val recaps = SportRecapStore
        if (!Reachability.isOnline) {
            recaps.trainingError = L("Training is waiting for a connection. Retry sync.")
            return@main
        }
        recaps.updatingTraining = true
        recaps.trainingError = null
        try {
            flushPendingEvidence(afterCurrent = true)
            if (owner != account() || generation != sessionGeneration) return@main
            try {
                val local = LocalDataStore.shared()
                val pendingHeart = local.operations(owner, "sport-heart-rate")
                val pendingEnergy = local.operations(owner, "sport-energy")
                if (pendingHeart.isNotEmpty() || pendingEnergy.isNotEmpty()) {
                    recaps.trainingError = L("Training evidence is waiting to upload. Retry sync.")
                    return@main
                }
                val today = UserDay.containing(Instant.now())
                val status = calculationStatusIfAvailable(today.key, today.key)
                if (owner != account() || generation != sessionGeneration) return@main
                if (status == null || status.isEmpty() || status.any { it.opt("pending") != false }) {
                    recaps.trainingError = L("Training could not update. Retry sync.")
                }
            } catch (e: Exception) {
                if (e is CancellationException && e !is SessionChangedException) throw e
                if (owner != account() || generation != sessionGeneration) return@main
                recaps.trainingError = L("Training could not update. Retry sync.")
                BandLog.shared.record("verify session settlement", error = e)
            }
        } finally {
            if (owner == account() && generation == sessionGeneration) recaps.updatingTraining = false
        }
    }

    /** 06 rule 09 · a band scan is a row in body_composition, not a number in memory. */
    suspend fun recordBodyComposition(r: BodyCompositionReading, at: Instant = Instant.now()) = main {
        val userId = db.userId ?: return@main
        try { BodyCompositionQueue.enqueue(r, at, userId) }
        catch (e: Exception) { BandLog.shared.record("persist body composition", error = e) }
    }

    /** ADR 0010 · one balance-check summary row, only after a measurement truly finished. */
    suspend fun recordBalanceCheck(lead: BalanceCheckQueue.Lead, restShare: Int, sd1: Double, sd2: Double,
                                   sdnn: Double, beatsPerMinute: Int?, pointCount: Int, heartRate: Int?,
                                   at: Instant = Instant.now()) = main {
        val userId = db.userId ?: return@main
        try { BalanceCheckQueue.enqueue(lead, restShare, sd1, sd2, sdnn, beatsPerMinute, pointCount, heartRate, at, userId) }
        catch (e: Exception) { BandLog.shared.record("persist balance check", error = e) }
    }

    /**
     * ADR 0010 · the MEASUREMENTS list. ⚠️ Body scans are only `measurement_source = device_bia`;
     * the filter is server-side so the limit cannot cut real scans first.
     */
    suspend fun loadMeasurements(store: DataStore, limit: Int = 200) = main {
        val generation = sessionGeneration
        val account = account()
        val (scanRows, balanceRows) = coroutineScope {
            val scans = async { runCatching { db.select("body_composition", listOf(
                "select" to "id,measured_at,body_fat_pct,fat_mass_kg,lean_body_mass_kg,bmr_kcal,input_weight_kg,muscle_mass_kg,body_water_pct,bone_mass_kg,protein_pct",
                "measurement_source" to "eq.device_bia",
                "order" to "measured_at.desc",
                "limit" to limit.toString())) }.getOrNull() ?: emptyList() }
            val balances = async { runCatching { db.select("balance_checks", listOf(
                "select" to "id,measured_at,lead,rest_share,sd1_ms,sd2_ms,sdnn_ms,heart_rate,beat_count",
                "order" to "measured_at.desc",
                "limit" to limit.toString())) }.getOrNull() ?: emptyList() }
            scans.await() to balances.await()
        }
        val records = mutableListOf<MeasurementRecord>()
        for (row in scanRows) {
            val id = parseUuid(row.optStringOrNull("id")) ?: continue
            val at = timestamp(row.optStringOrNull("measured_at")) ?: continue
            records += MeasurementRecord(id = id, at = at, detail = MeasurementRecord.BodyScan(
                bodyFatPercent = row.number("body_fat_pct"),
                fatMassKg = row.number("fat_mass_kg"),
                leanMassKg = row.number("lean_body_mass_kg"),
                bmrKcal = row.number("bmr_kcal")?.toInt(),
                inputWeightKg = row.number("input_weight_kg"),
                muscleMassKg = row.number("muscle_mass_kg"),
                bodyWaterPercent = row.number("body_water_pct"),
                boneMassKg = row.number("bone_mass_kg"),
                proteinPercent = row.number("protein_pct")))
        }
        for (row in balanceRows) {
            val id = parseUuid(row.optStringOrNull("id")) ?: continue
            val at = timestamp(row.optStringOrNull("measured_at")) ?: continue
            val lead = row.optStringOrNull("lead")?.let { raw ->
                MeasurementRecord.BalanceCheck.Lead.entries.firstOrNull { it.raw == raw }
            } ?: continue
            records += MeasurementRecord(id = id, at = at, detail = MeasurementRecord.BalanceCheck(
                lead = lead,
                restShare = (row.number("rest_share") ?: 50.0).toInt(),
                sd1Ms = row.number("sd1_ms") ?: 0.0,
                sd2Ms = row.number("sd2_ms") ?: 0.0,
                sdnnMs = row.number("sdnn_ms") ?: 0.0,
                heartRate = row.number("heart_rate")?.toInt(),
                beatCount = (row.number("beat_count") ?: 0.0).toInt()))
        }
        if (account == null || account != account() || generation != sessionGeneration) return@main
        store.measurements = records.sortedByDescending { it.at }
    }

    // endregion

    // region sleep scores, summaries

    /**
     * ADR 0008 · the sleep board's week and month windows, in one query of thirty small rows.
     * The score is settled server-side precisely so this can be cheap.
     */
    suspend fun loadSleepScores(days: Int, endingAt: UserDay, store: DataStore) = main {
        PushSettle.await()
        val account = account() ?: return@main
        sleepScoreGeneration += 1
        val request = sleepScoreGeneration
        val session = sessionGeneration
        val day = endingAt
        val from = day.adding(1 - minOf(maxOf(days, 1), SLEEP_CORRECTION_HORIZON_DAYS + 2)).key
        store.sleepScoreLoadState = SleepScoreLoadState.loading
        try {
            val rows = db.select("night_score", listOf(
                "select" to "user_day,score,duration_score,architecture_score,recovery_score,regularity_score,personal_weight,inputs,score_version,computed_at",
                "user_id" to "eq.$account",
                "user_day" to "gte.$from",
                "user_day" to "lte.${day.key}",
                "order" to "user_day.asc"))
            val scores = LinkedHashMap<String, SleepScore>()
            for (row in rows) {
                val key = row.optStringOrNull("user_day") ?: continue
                if (key < from || key > day.key) continue
                val rawTotal = decimal(row.opt("score")) ?: continue
                if (!rawTotal.isFinite() || rawTotal !in 0.0..100.0) continue
                val total = integer(row.opt("score")) ?: continue
                val inputs = LinkedHashMap<String, Double>()
                row.optJSONObject("inputs")?.let { o ->
                    o.keys().forEach { name -> decimal(o.opt(name))?.takeIf { it.isFinite() }?.let { inputs[name] = it } }
                }
                scores[key] = SleepScore(
                    score = total,
                    duration = integer(row.opt("duration_score")),
                    architecture = integer(row.opt("architecture_score")),
                    recovery = integer(row.opt("recovery_score")),
                    regularity = integer(row.opt("regularity_score")),
                    personalWeight = decimal(row.opt("personal_weight")) ?: 0.0,
                    inputs = inputs,
                    version = row.optStringOrNull("score_version") ?: "",
                    computedAt = timestamp(row.optStringOrNull("computed_at")))
            }
            if (account != account() || session != sessionGeneration || request != sleepScoreGeneration) return@main
            if (cancelled()) {
                store.sleepScoreLoadState = SleepScoreLoadState.idle
                return@main
            }
            store.sleepScores = scores
            store.today = store.today.copy().also { it.sleepScore = scores[it.day.key] }
            // ⚠️ One write.
            store.history = store.history.map { m -> m.copy().also { it.sleepScore = scores[m.day.key] } }
            store.sleepScoreLoadState = SleepScoreLoadState.ready
            HomeSnapshot.save(store)
        } catch (e: Exception) {
            if (account != account() || session != sessionGeneration || request != sleepScoreGeneration) return@main
            store.sleepScoreLoadState = if (e is CancellationException && e !is SessionChangedException)
                SleepScoreLoadState.idle else SleepScoreLoadState.failed
            if (e is CancellationException && e !is SessionChangedException) throw e
        }
    }

    /** ⚠️ A blank or malformed score reads as no score, never a crash. */
    private fun integer(value: Any?): Int? {
        if (value is Number) return value.toInt()
        val number = (value as? String)?.toDoubleOrNull() ?: return null
        if (!number.isFinite() || number < -1e9 || number > 1e9) return null
        return number.toInt()
    }

    private fun decimal(value: Any?): Double? = (value as? Number)?.toDouble() ?: (value as? String)?.toDoubleOrNull()

    private fun direction(raw: String?): DailyDirection? = when (raw) {
        null -> null
        "DEFICIT" -> DailyDirection.deficit
        "LEVEL" -> DailyDirection.level
        "SURPLUS" -> DailyDirection.surplus
        "GREY_NO_BURN" -> DailyDirection.greyNoBurn
        else -> DailyDirection.greyNothing
    }

    /** ⚠️ The column stores NO_CHANGE while the token on screen is "MEASURED, NO CHANGE". */
    private fun theCall(raw: String?): TheCall? = when (raw) {
        null -> null
        "NO_CHANGE" -> TheCall.noChange
        else -> TheCall.fromRaw(raw)
    }

    private fun fuelState(raw: String?, slotStates: JSONObject?): FuelState = when (raw) {
        "FASTED" -> FuelState.Fasted
        "CONFIRMED" -> FuelState.Confirmed
        "PARTIAL" -> FuelState.Partial(slotStates?.let { o -> o.keys().asSequence().count { o.opt(it) == "CONFIRMED" } } ?: 0)
        else -> FuelState.Unlogged
    }

    private fun trainingSettlement(evidence: JSONObject?): TrainingSettlement =
        TrainingSettlement(evidence?.let { Json.toMap(it) })

    suspend fun loadHistorySummaries(days: Int, endingAt: UserDay, store: DataStore) = main {
        summaryReadGeneration += 1
        val summaryGeneration = summaryReadGeneration
        val account = account()
        val generation = readGeneration
        try {
            if (account == null) return@main
            val reader = snapshotReader(account, generation, summaryGeneration)
            val snapshot = reader.summaries(days, endingAt,
                known = summaryRevisions[account] ?: emptyMap(),
                cachedDays = (store.history.map { it.day.key } + store.today.day.key).toSet(),
                didPublish = { revisions -> summaryRevisions[account] = revisions }) ?: return@main
            snapshot.publish { s ->
                val rows = s.rows
                val fuel = s.fuel
                val trainingBy = s.training.mapNotNull { r -> r.optStringOrNull("result_id")?.let { it to r } }.toMap()
                val summaries: List<DailyMetrics> = rows.mapNotNull { row ->
                    val d = userDay(row.optStringOrNull("user_day")) ?: return@mapNotNull null
                    val asOf = timestamp(row.optStringOrNull("computed_at"))
                    // Preserve an already loaded detail only when its result is the same or newer.
                    val existing = store.metrics(d)
                    val at = existing?.asOf
                    if (existing != null && at != null && asOf != null && at >= asOf) {
                        return@mapNotNull existing.copy().also { it.sleep = sleepOnWakeDay(existing.sleep, d) }
                    }
                    val m = DailyMetrics(day = d)
                    m.trainingLoad = row.number("training_load")
                    trainingBy[row.optStringOrNull("id") ?: ""]?.let { training ->
                        m.applyTrainingSettlement(trainingSettlement(training.objOrNull("evidence")))
                        m.recordedSteps = training.number("recorded_steps")?.toInt()
                    }
                    m.bodyBattery = row.number("reserve_score")?.toInt()
                    m.balance = row.number("fuel_balance_kcal")
                    m.asOf = asOf; m.calcVersion = row.optStringOrNull("algo_version") ?: "?"
                    m.serverDirection = direction(row.optStringOrNull("daily_direction"))
                    m.serverCall = theCall(row.optStringOrNull("the_call"))
                    m.confidence = Confidence.fromRaw(row.optStringOrNull("the_call_confidence") ?: "") ?: Confidence.pending
                    m.fatEmaDelta7d = row.number("fat_delta_7d")
                    m.leanEmaDelta7d = row.number("lean_delta_7d")
                    m.scans7d = (row.number("scans_7d") ?: 0.0).toInt()
                    applyWear(row, m)
                    fuel.firstOrNull { it.optStringOrNull("result_id") == row.optStringOrNull("id") }?.let { energy ->
                        m.eIn = energy.number("kcal_in"); m.eOutNow = energy.number("kcal_out")
                        m.proteinIn = energy.number("protein_in_g")?.toInt()
                        m.carbIn = energy.number("carb_in_g")?.toInt()
                        m.fatIn = energy.number("fat_in_g")?.toInt()
                        m.weightKg = energy.number("weight_kg")
                        m.fuelState = fuelState(energy.optStringOrNull("intake_state"), energy.objOrNull("slot_states"))
                    }
                    m.sleepScore = store.sleepScores[d.key]
                    // Summary revisions invalidate computed details, not device observations.
                    existing?.let { e ->
                        m.sleep = sleepOnWakeDay(e.sleep, d)
                        m.vitalsCurve = e.vitalsCurve
                        m.fatKg = e.fatKg
                        m.leanKg = e.leanKg
                    }
                    m
                }
                store.history = (store.history.filter { old -> summaries.none { it.day == old.day } } + summaries)
                    .sortedBy { it.day }
                HomeSnapshot.save(store)
            }
        } catch (e: Exception) {
            // Keep valid cached history when an independent background read fails.
            if (e is CancellationException && e !is SessionChangedException) throw e
            ServiceLog.record("History summary refresh failed", e)
        }
    }

    suspend fun loadDetail(day: UserDay, store: DataStore) = main {
        val account = account() ?: SessionKeychain.userId ?: return@main
        val cached = HomeSnapshot.loadDetail(day, account)
        if (cached != null && (store.metrics(day)?.asOf == null ||
                (store.metrics(day)?.asOf ?: DistantPast) < (cached.asOf ?: DistantPast))) {
            val local = store.metrics(day)
            val restored = HomeSnapshot.restoringObservations(cached, local?.vitalsCurve ?: emptyList(), local?.sleep)
            restored.sleepScore = store.sleepScores[day.key]
            if (day == UserDay.containing(Instant.now())) store.today = restored
            store.history = (store.history.filter { it.day != day } + restored).sortedBy { it.day }
        }
        if (store.isOffline) return@main
        load(0, day, store)
    }

    /** One hydrate seam for a second-level page. The window names the tables. */
    suspend fun hydrate(window: DetailWindow, endingAt: UserDay, focus: UserDay? = null, store: DataStore) = main {
        PushSettle.await()
        when (val load = window.load) {
            is DetailWindow.Load.None -> Unit
            is DetailWindow.Load.DailyResults -> {
                load(load.lookback, endingAt, store)
                if (focus != null && focus != endingAt) loadDetail(focus, store)
            }
            is DetailWindow.Load.HeartTicks -> loadHeartWindow(load.days, store)
            is DetailWindow.Load.DailyResultsAndHeartTicks -> {
                load(load.lookback, endingAt, store)
                loadHeartWindow(load.heartDays, store)
            }
            is DetailWindow.Load.Composition -> loadComposition(store)
        }
    }

    /** Raw samples exceed PostgREST's 1,000-row cap after about three days. */
    private suspend fun selectSamplePages(table: String, query: Query): List<JSONObject> {
        val owner = account()
        val base = query.filter { it.first !in setOf("order", "offset", "limit") }
        return SamplePageRead.all { offset ->
            if (account() != owner) throw SessionChangedException()
            val page = db.select(table, base + listOf("order" to "ts.asc,src.asc", "offset" to offset.toString(), "limit" to "1000"))
            if (account() != owner) throw SessionChangedException()
            page
        }
    }

    /** HEART week/month needs more than the one day of `raw_samples` Home preloads. */
    suspend fun loadHeartWindow(days: Int, store: DataStore) = main {
        if (days <= 1 || Band.allowsSeed || store.isOffline) return@main
        if (account() == null && SessionKeychain.userId == null) return@main
        val day = store.today.day
        val from = day.adding(-days - 1)
        val to = day.adding(1)
        try {
            val (vitalRows, oxygenRows) = coroutineScope {
                val v = async { runCatching { selectSamplePages("raw_samples", listOf(
                    "select" to "ts,heart,stress,temp,step,met,cal,dis,hrv,domain_sources",
                    "ts" to "gte.${Iso.string(from.start)}",
                    "ts" to "lt.${Iso.string(to.start)}",
                    "order" to "ts.asc")) } }
                val o = async { runCatching { db.select("oxygen_samples", listOf(
                    "select" to "ts,spo2",
                    "ts" to "gte.${Iso.string(from.start)}",
                    "ts" to "lt.${Iso.string(to.start)}",
                    "order" to "ts.asc")) }.getOrNull() }
                v.await().getOrThrow() to o.await()
            }
            val vitals = HealthSnapshotRead.decodeVitals(vitalRows)
            val oxygen = (oxygenRows ?: emptyList()).mapNotNull { row ->
                val at = timestamp(row.optStringOrNull("ts")) ?: return@mapNotNull null
                val percent = row.number("spo2")?.toInt() ?: return@mapNotNull null
                if (percent !in 50..100) null else OvernightOxygenPoint(ts = at, percent = percent)
            }
            mergeHeartWindow(vitals, oxygen, day.adding(-(days - 1)), day, store)
        } catch (e: Exception) {
            if (e is CancellationException && e !is SessionChangedException) throw e
            ServiceLog.record("Heart window load failed", e)
        }
    }

    private fun mergeHeartWindow(vitals: List<VitalSample>, oxygen: List<OvernightOxygenPoint>,
                                 from: UserDay, through: UserDay, store: DataStore) {
        fun apply(source: DailyMetrics, day: UserDay): DailyMetrics {
            val metrics = source.copy()
            val remote = vitals.filter { it.ts >= day.start && it.ts < day.end }
            metrics.vitalsCurve = VitalSample.merging(metrics.vitalsCurve, remote)
            val sleep = metrics.sleep?.copy() ?: return metrics
            val start = sleep.sleepStart ?: return metrics
            val wake = sleep.wakeAt ?: return metrics
            if (wake <= start) return metrics
            // The recorded segments, not the outer window: a reading in a gap is an awake reading.
            val nightOxygen = oxygen.filter { sleep.containsSleepTimestamp(it.ts) }
            if (nightOxygen.isEmpty()) return metrics
            val merged = LinkedHashMap<Instant, OvernightOxygenPoint>()
            for (p in sleep.spo2 + nightOxygen) if (!merged.containsKey(p.ts)) merged[p.ts] = p
            sleep.spo2 = merged.values.sortedBy { it.ts }
            metrics.sleep = sleep
            return metrics
        }

        var cursor = from
        val history = store.history.toMutableList()
        while (cursor <= through) {
            if (store.today.day == cursor) store.today = apply(store.today, cursor)
            val index = history.indexOfFirst { it.day == cursor }
            if (index >= 0) {
                history[index] = apply(history[index], cursor)
            } else if (store.today.day != cursor) {
                val row = apply(DailyMetrics(day = cursor), cursor)
                if (row.vitalsCurve.isNotEmpty()) history += row
            }
            cursor = cursor.adding(1)
        }
        store.history = history.sortedBy { it.day }
    }

    // endregion

    // region detail load

    suspend fun load(days: Int, endingAt: UserDay, store: DataStore) = main {
        val day = endingAt
        readGeneration += 1
        val generation = readGeneration
        val account = account()
        fun isCurrent(): Boolean = HomeLaunchPolicy.acceptsRead(account, account(), generation, readGeneration)
        try {
            if (account == null) return@main
            val reader = snapshotReader(account, generation)
            val snapshot = reader.detail(days, day) ?: return@main
            val published = snapshot.publish { s -> applyDetail(s, days, day, store, account) }
            if (published) WeighInQueue.flush()
        } catch (e: Exception) {
            ServiceLog.record("Repository.load failed", e)
            // Offline shows the last row that was successfully stored. A concurrent settlement
            // is not a loss of connectivity: keep the prior coherent snapshot.
            if (e === HealthSnapshotRead.Failure.RevisionChanged) return@main
            val cancellation = e is CancellationException
            if (isCurrent() && !cancellation) store.isOffline = true
            if (cancellation && e !is SessionChangedException) throw e
        }
    }

    private fun applyDetail(snapshot: HealthSnapshotRead.Snapshot, days: Int, day: UserDay,
                            store: DataStore, account: String) {
        val rows = snapshot.rows
        val weekRows = snapshot.meals
        val sampleRows = snapshot.reserveSamples
        val nightRows = snapshot.nights
        // Parse the window's oxygen rows once, not per night.
        val oxygenPoints = oxygenPoints(snapshot.oxygen)
        val responseRows = snapshot.response
        val liveRows = snapshot.live
        val liveStressRows = snapshot.liveStress
        val liveHeartRows = snapshot.liveHeart
        val fuelBy = snapshot.fuel.mapNotNull { r -> r.optStringOrNull("result_id")?.let { it to r } }.toMap()
        val reserveBy = snapshot.reserve.mapNotNull { r -> r.optStringOrNull("result_id")?.let { it to r } }.toMap()
        val trainingBy = snapshot.training.mapNotNull { r -> r.optStringOrNull("result_id")?.let { it to r } }.toMap()
        val todayDay = UserDay.containing(Instant.now())

        val history = mutableListOf<DailyMetrics>()
        for (row in rows) {
            val userDay = userDay(row.optStringOrNull("user_day")) ?: continue
            val m = DailyMetrics(day = userDay)
            val id = row.optStringOrNull("id") ?: ""
            m.trainingLoad = row.number("training_load")
            m.serverDirection = direction(row.optStringOrNull("daily_direction"))
            m.balance = snapshot.value("deltaKcal", userDay.key, row.opt("fuel_balance_kcal"))
            m.calcVersion = row.optStringOrNull("algo_version") ?: "?"
            m.confidence = Confidence.fromRaw(row.optStringOrNull("the_call_confidence") ?: "") ?: Confidence.pending
            // F3 · computed in Postgres; the local derivation is the offline fallback only.
            m.serverCall = theCall(row.optStringOrNull("the_call"))
            m.fatEmaDelta7d = row.number("fat_delta_7d")
            m.leanEmaDelta7d = row.number("lean_delta_7d")
            m.scans7d = (row.number("scans_7d") ?: 0.0).toInt()
            applyWear(row, m)
            row.optStringOrNull("computed_at")?.let { m.asOf = timestamp(it) }
            // A valid daytime-only score lives on daily_results even before BB_WAKE.
            m.bodyBattery = row.number("reserve_score")?.toInt()

            reserveBy[id]?.let { r ->
                m.bbWake = r.number("wake_value")?.toInt()
                m.bodyBattery = r.number("current_value")?.toInt() ?: m.bodyBattery
                val d = r.objOrNull("drain_drivers")
                if (d != null && d.length() > 0) {
                    val drivers = ReserveDrivers(
                        lastNight = d.number("last_night") ?: 0.0,
                        awake = d.number("awake") ?: 0.0,
                        movement = d.number("movement") ?: 0.0,
                        stress = d.number("stress") ?: 0.0,
                        anchor = (d.number("anchor") ?: 0.0).toInt(),
                        assumedAnchor = d.optBoolOrNull("assumed_anchor") ?: false,
                        dayCharge = d.number("day_charge"),
                        nightCharge = d.number("night_charge"),
                        wakeAt = timestamp(d.optStringOrNull("wake_at")),
                        observedAt = timestamp(d.optStringOrNull("observed_at")),
                        confidence = d.optStringOrNull("confidence")?.let { BodyBatteryConfidence.fromRaw(it.uppercase()) },
                        algoVersion = d.optStringOrNull("algo_version"))
                    d.objOrNull("coverage")?.let { c ->
                        drivers.coverage = BodyBatteryCoverage(
                            nightHRV = c.number("night_hrv"), nightRHR = c.number("night_rhr"),
                            nightExpectedMinutes = c.number("night_expected_minutes")?.toInt(),
                            nightHRVMinutes = c.number("night_hrv_minutes")?.toInt(),
                            nightRHRMinutes = c.number("night_rhr_minutes")?.toInt(),
                            nightHRVLongestGap = c.number("night_hrv_longest_gap")?.toInt(),
                            nightRHRLongestGap = c.number("night_rhr_longest_gap")?.toInt(),
                            hrvNights = c.number("hrv_nights")?.toInt(),
                            rhrNights = c.number("rhr_nights")?.toInt(),
                            dayHeart = c.number("day_heart"), dayHRV = c.number("day_hrv"),
                            dayStress = c.number("day_stress"),
                            dayExpectedTicks = c.number("day_expected_ticks")?.toInt(),
                            dayObservedTicks = c.number("day_observed_ticks")?.toInt())
                    }
                    m.reserveDrivers = drivers
                }
                val n = r.objOrNull("night_inputs")
                if (n != null && n.length() > 0) {
                    m.nightInputs = NightInputs(
                        hrv = n.number("hrv"), hrvBase = n.number("hrv_base"),
                        rhr = n.number("rhr"), rhrBase = n.number("rhr_base"),
                        rhrNights = (n.number("rhr_nights") ?: 0.0).toInt(),
                        hrvNights = (n.number("hrv_nights") ?: 0.0).toInt(),
                        multiplier = n.number("multiplier"))
                }
                m.bbWake?.let { wake ->
                    val band = BodyBattery.band(wake)
                    m.targetLoad = band.target
                    m.optimalZone = band.optimal
                }
            }
            trainingBy[id]?.let { t ->
                m.applyTrainingSettlement(trainingSettlement(t.objOrNull("evidence")))
                m.recordedSteps = t.number("recorded_steps")?.toInt()
                t.objOrNull("evidence")?.let { e ->
                    val elapsed = e.number("elapsed_minutes")
                    val recorded = e.number("recorded_minutes")
                    val heart = e.number("hr_minutes")
                    val movement = e.number("movement_minutes")
                    if (elapsed != null && recorded != null && heart != null && movement != null) {
                        m.trainingEvidence = TrainingEvidence(
                            elapsedMinutes = elapsed.toInt(), recordedMinutes = recorded.toInt(),
                            heartRateMinutes = heart.toInt(), movementMinutes = movement.toInt(),
                            restingHeartRate = e.number("hr_rest"),
                            restingBaselineNights = (e.number("hr_rest_nights") ?: 0.0).toInt(),
                            baselineEstimated = e.optBoolOrNull("baseline_estimated") ?: true)
                    }
                }
                m.zoneMinutes = t.arrayOrNull("zone_minutes")?.let { a -> (0 until a.length()).mapNotNull { number(a.opt(it))?.toInt() } }
                m.peakHR = t.number("peak_hr")?.toInt()
                m.activeMinutes = t.number("active_minutes")?.toInt()
                m.distanceM = t.number("distance_m")?.toInt()
                m.segments = (t.arrayOrNull("segments") ?: JSONArray()).objects().mapNotNull { r ->
                    val at = timestamp(r.optStringOrNull("at")) ?: return@mapNotNull null
                    TrainingSegment(
                        at = at, name = r.optStringOrNull("name") ?: "",
                        minutes = r.number("minutes")?.toInt(),
                        avgHR = r.number("avg_hr")?.toInt(),
                        steps = r.number("steps")?.toInt(),
                        delta = r.number("delta") ?: 0.0,
                        allDay = r.optBoolOrNull("all_day") ?: false)
                }
                // The cumulative curve arrives as [[epoch, load]] — one array per tick.
                val curve = t.arrayOrNull("curve") ?: JSONArray()
                m.loadCurve = (0 until curve.length()).mapNotNull { i ->
                    val pair = curve.opt(i) as? JSONArray ?: return@mapNotNull null
                    if (pair.length() != 2) return@mapNotNull null
                    val epoch = number(pair.opt(0)) ?: return@mapNotNull null
                    val load = number(pair.opt(1)) ?: return@mapNotNull null
                    LoadPoint(ts = instantFromEpochSeconds(epoch), load = load)
                }
            }
            fuelBy[id]?.let { fu ->
                val energy = snapshot.energy(userDay.key, fu)
                m.eIn = energy.intake; m.eOutNow = energy.burn
                m.proteinIn = energy.protein?.toInt()
                m.carbIn = fu.number("carb_in_g")?.toInt()
                m.fatIn = fu.number("fat_in_g")?.toInt()
                m.weightKg = fu.number("weight_kg") ?: m.weightKg
                m.bmr = energy.resting; m.eActive = energy.active
                m.energyDistribution = fu.arrayOrNull("energy_distribution")?.objects()?.mapNotNull { o ->
                    val epoch = o.number("epoch") ?: return@mapNotNull null
                    val origin = o.number("origin_weight") ?: return@mapNotNull null
                    val strength = o.number("strength_weight") ?: return@mapNotNull null
                    if (!epoch.isFinite() || !origin.isFinite() || !strength.isFinite() || origin < 0 || strength < 0) return@mapNotNull null
                    FuelEnergyPoint(epoch = epoch, originWeight = origin, strengthWeight = strength)
                }
                m.balance = energy.balance
                // 10 · the header is an estimate of where the day lands.
                val elapsed = userDay.elapsedMinutes(m.asOf ?: Instant.now()).toDouble() /
                    (userDay.end.timeIntervalSince(userDay.start) / 60)
                val full = fu.number("bmr_full_kcal")
                m.bmrFull = full
                m.activeForecast = m.eActive?.let { if (elapsed > 0.05) it / elapsed else it }
                m.eTrainPlan = null
                // The allowance is resting for the whole day plus the activity measured so far.
                val basis = fu.number("target_basis_kcal") ?: full?.let { it + (m.eActive ?: 0.0) }
                m.targetBasis = basis
                m.targetBasisDays = null
                m.restingSource = fu.optStringOrNull("resting_source")
                m.restingMeasuredAt = timestamp(fu.optStringOrNull("resting_measured_at"))
                m.goalOffset = 0.0
                m.targetIn = basis ?: fu.number("target_in")
                val p = fu.number("protein_g")?.toInt()
                val f = fu.number("fat_g")?.toInt()
                if (p != null) m.protein = MacroSlot(target = p, eaten = 0)
                if (f != null) m.fat = MacroSlot(target = f, eaten = 0)
                val allowance = m.targetIn
                if (allowance != null && p != null && f != null) {
                    val c = maxOf(0, ((allowance - (p * 4 + f * 9).toDouble()) / 4).rounded().toInt())
                    m.carb = MacroSlot(target = c, eaten = 0)
                } else fu.number("carb_g")?.let { m.carb = MacroSlot(target = it.toInt(), eaten = 0) }
                m.fuelState = fuelState(fu.optStringOrNull("intake_state"), fu.objOrNull("slot_states"))
            }
            // A versioned battery result carries the exact inputs used by its recovery multiplier.
            if (m.nightInputs != null && m.reserveDrivers?.algoVersion == null && snapshot.hasFormalMetrics) {
                m.nightInputs = m.nightInputs?.copy(
                    hrv = snapshot.value("nightHRV", userDay.key),
                    hrvBase = snapshot.value("hrvBaseline", userDay.key),
                    rhr = snapshot.value("nightRHR", userDay.key))
            }
            history += m
        }

        // A just-synced day can have raw_samples before it has a daily_results row.
        for (offset in 0..maxOf(days, 1)) {
            val requiredDay = day.adding(-offset)
            if (history.any { it.day == requiredDay }) continue
            val existing = store.history.firstOrNull { it.day == requiredDay }
            history += when {
                existing != null -> existing
                store.today.day == requiredDay -> store.today
                else -> DailyMetrics(day = requiredDay)
            }
        }
        history.sortBy { it.day }

        // The meal list belongs to the same row of truth as the fuel state.
        val loadedMeals: List<MealEntry> = weekRows.mapNotNull { row ->
            val slot = MealEntry.Slot.fromRaw(row.optStringOrNull("slot") ?: "") ?: return@mapNotNull null
            val at = timestamp(row.optStringOrNull("logged_at")) ?: return@mapNotNull null
            val d = userDay(row.optStringOrNull("user_day")) ?: return@mapNotNull null
            MealEntry(
                id = parseUuid(row.optStringOrNull("id")) ?: UUID.randomUUID(),
                day = d, at = at, slot = slot, status = MealEntry.Status.confirmed,
                text = row.optStringOrNull("text_input") ?: "",
                kcal = row.number("kcal") ?: 0.0,
                protein = row.number("protein_g") ?: 0.0,
                carb = row.number("carb_g") ?: 0.0,
                fat = row.number("fat_g") ?: 0.0,
                source = if (row.optStringOrNull("photo_path") == null) MealEntry.Source.typed else MealEntry.Source.photo,
                groupID = parseUuid(row.optStringOrNull("meal_group_id")),
                portion = row.optStringOrNull("portion"),
                photoPath = row.optStringOrNull("photo_path"),
                fiber = row.number("fiber_g"),
                sugar = row.number("sugar_g"),
                sodium = row.number("sodium_mg"))
        }
        if (day != todayDay) {
            val loadedDays = loadedMeals.map { it.day }.toSet()
            store.recentMeals = store.recentMeals.filter { it.day !in loadedDays } + loadedMeals
        }
        if (day == todayDay) {
            store.recentMeals = loadedMeals
            store.meals = loadedMeals.filter { it.day == day }
        }

        val curve = sampleRows.mapNotNull { row ->
            val at = timestamp(row.optStringOrNull("ts")) ?: return@mapNotNull null
            val v = row.number("value") ?: return@mapNotNull null
            ReserveSample(ts = at, value = v.toInt())
        }
        if (history.isNotEmpty()) history[history.size - 1] = history.last().copy().also { it.reserveCurve = curve }

        for (index in history.indices) {
            val historical = store.history.firstOrNull { it.day == history[index].day }?.vitalsCurve ?: emptyList()
            val localSamples = historical + (if (store.today.day == history[index].day) store.today.vitalsCurve else emptyList())
            history[index] = history[index].copy().also { it.vitalsCurve = snapshot.vitals(it.day, localSamples) }
        }

        val sleepSourceSamples = snapshot.sleepVitals(store.history.flatMap { it.vitalsCurve } + store.today.vitalsCurve)
        // Raw device sleep is independent of settled sleepMinutes.
        for (index in history.indices) {
            val m = history[index].copy()
            history[index] = m
            val key = m.day.key
            val local = sleepOnWakeDay(store.metrics(m.day)?.sleep, m.day)
            val night = nightRows?.firstOrNull { n ->
                if (n.optStringOrNull("user_day") != key) return@firstOrNull false
                val wake = timestamp(n.optStringOrNull("wake_at")) ?: return@firstOrNull true
                wake.isSameDay(m.day.start)
            }
            val total = night?.number("total_minutes")
            if (night == null || total == null || !total.isFinite() || total < 0) {
                m.sleep = local
                continue
            }
            m.sleep = remoteSleep(night, total, local, oxygenPoints, sleepSourceSamples)
        }

        liveRows.firstOrNull()?.let { live ->
            val at = timestamp(live.optStringOrNull("ts")) ?: return@let
            // ⚠️ The server's answer is the same tick or an older one; only overwrite when at least as recent.
            val currentAt = store.vitals.at
            if (currentAt == null || at >= currentAt) {
                val lastStress = liveStressRows?.firstOrNull()?.let { row ->
                    val ts = timestamp(row.optStringOrNull("ts")) ?: return@let null
                    val value = row.number("stress")?.toInt() ?: return@let null
                    value to ts
                }
                val lastHeart = liveHeartRows?.firstOrNull()?.let { row ->
                    val ts = timestamp(row.optStringOrNull("ts")) ?: return@let null
                    val value = row.number("heart")?.toInt() ?: return@let null
                    value to ts
                }
                store.vitals = LiveVitals(
                    hr = VitalsTimelinePolicy.currentHeart(live.number("heart")?.toInt(), lastHeart, at),
                    stress = VitalsTimelinePolicy.currentStress(live.number("stress")?.toInt(), lastStress, at),
                    at = at)
            }
        }

        // ⚠️ Merge, never replace.
        val merged = (store.history.filter { existing -> history.none { it.day == existing.day } } + history)
            .sortedBy { it.day }
            .map { m -> m.copy().also { it.sleepScore = store.sleepScores[m.day.key] } }
        store.history = merged
        if (responseRows != null) {
            val loaded = opticalResponse(responseRows)
            if (loaded.isNotEmpty() || store.mealResponsePoints.isEmpty()) store.mealResponsePoints = loaded
        }
        history.firstOrNull { it.day == todayDay }?.let { last ->
            // 04 · a slot is open until it has a conclusion — logged or SKIPPED.
            val settled = store.meals.filter { it.status != MealEntry.Status.`open` }.map { it.slot }.toSet()
            val next = merge(last, store.today, MealEntry.Slot.entries.size - settled.size)
            next.sleepScore = store.sleepScores[next.day.key]
            store.today = next
        }
        // Plates on screen are the EATEN number.
        if (day == todayDay) store.refreshIntakeFromMeals()
        // WEIGHT_KG · the most recent weigh-in is what the identity card shows.
        snapshot.weighIns.firstOrNull()?.number("weight_kg")?.let { kg ->
            store.today = store.today.copy().also { it.weightKg = kg }
        }
        store.weighIns = snapshot.weighIns.mapNotNull { row ->
            val iso = row.optStringOrNull("measured_at") ?: return@mapNotNull null
            val kg = row.number("weight_kg") ?: return@mapNotNull null
            WeighIn(id = parseUuid(row.optStringOrNull("id")) ?: UUID.randomUUID(),
                date = timestamp(iso) ?: Instant.now(),
                weightKg = kg, bodyFatPercent = null,
                source = MeasurementSource.measured,
                origin = if (row.optStringOrNull("source") == "health") WeighIn.Origin.health else WeighIn.Origin.manual)
        }
        store.isOffline = false
        MealQueue.overlayPending(store, account)
        store.metrics(day)?.let { HomeSnapshot.saveDetail(it, account) }
        HomeSnapshot.save(store)
    }

    /** One night row → SleepSummary (port of the inline block in Swift `load`). */
    private fun remoteSleep(night: JSONObject, total: Double, local: SleepSummary?,
                            oxygenPoints: List<OvernightOxygenPoint>, sleepSourceSamples: List<VitalSample>): SleepSummary? {
        val line = (night.optStringOrNull("sleep_line") ?: "").split(",").mapNotNull { pair ->
            val parts = pair.split(":")
            if (parts.size != 2) return@mapNotNull null
            val stage = parts[0].toIntOrNull() ?: return@mapNotNull null
            val minutes = parts[1].toIntOrNull() ?: return@mapNotNull null
            if (minutes <= 0) null else SleepStageRun(stage = stage, minutes = minutes)
        }
        val start = timestamp(night.optStringOrNull("sleep_start"))
        val wake = timestamp(night.optStringOrNull("wake_at"))
        // #28 · a corrected night is narrower than the band's on purpose.
        val correctedAt = timestamp(night.optStringOrNull("corrected_at"))
        val corrected = night.optStringOrNull("corrected_start") != null
        val raw = night.objOrNull("raw")
        val source = raw?.optStringOrNull("source")
        val reported = source == "user_reported"
        // Cloud publication can lag the completed SDK night.
        if (!corrected && !reported && local != null && !local.isCorrected && !local.isUserReported) {
            val localStart = local.sleepStart
            val localWake = local.wakeAt
            if (localStart != null && localWake != null && start != null && wake != null &&
                localStart <= start && localWake >= wake && (localStart < start || localWake > wake)) {
                return local
            }
        }
        val sameWindow = start != null && wake != null && local?.sleepStart == start && local?.wakeAt == wake
        val oxygen = overnightOxygen(oxygenPoints, start, wake)
        val respiration = sleepRespiration(raw, start, wake)
        val hrv = sleepHRV(raw, start, wake)
        val remoteHRVInvalidations = sleepHRVInvalidations(raw, start, wake)
        val rawIntervalRows = raw?.arrayOrNull("intervals")?.objects() ?: emptyList()
        val rawIntervals = rawIntervalRows.mapNotNull { row ->
            val intervalStart = timestamp(row.optStringOrNull("start")) ?: return@mapNotNull null
            val intervalEnd = timestamp(row.optStringOrNull("end")) ?: return@mapNotNull null
            if (intervalEnd <= intervalStart || start == null || wake == null) return@mapNotNull null
            SleepWindowCorrection.clipInterval(intervalStart, intervalEnd, start, wake)?.let { SleepInterval(it.start, it.end) }
        }.sortedBy { it.start }
        // Absence predates segmented sleep: retain null. Explicit empty stays empty.
        val hasIntervals = raw?.has("intervals") == true
        val intervals: List<SleepInterval>? = if (hasIntervals) rawIntervals else if (sameWindow) local?.intervals else null
        val rawLine = (raw?.arrayOrNull("line")?.objects() ?: emptyList()).mapNotNull { row ->
            val stage = row.number("stage") ?: return@mapNotNull null
            val minutes = row.number("minutes") ?: return@mapNotNull null
            if (!stage.isFinite() || !minutes.isFinite() || minutes <= 0) return@mapNotNull null
            val offset = row.number("offset_minutes")?.let { if (it.isFinite() && it >= 0) it.toInt() else null }
            SleepStageRun(stage = stage.toInt(), minutes = minutes.toInt(), offsetMinutes = offset)
        }
        fun inSleep(at: Instant): Boolean {
            if (start == null || wake == null || at < start || at >= wake) return false
            if (corrected || reported || intervals == null) return true
            return intervals.any { at >= it.start && at < it.end }
        }
        var displayLine = if (rawLine.isNotEmpty()) rawLine
            else if (sameWindow && (line.isEmpty() || local?.line?.any { it.offsetMinutes != null } == true)) local?.line ?: emptyList()
            else line
        // #28 · the runs are the band's; a corrected window clips them to itself.
        val bandStart = timestamp(raw?.optStringOrNull("recorded_start"))
        val bandEnd = timestamp(raw?.optStringOrNull("recorded_end"))
        if (corrected && bandStart != null && start != null && wake != null) {
            // Clip the server's original line, never a cached display line twice.
            val recordedLine = if (rawLine.isNotEmpty()) rawLine else line
            displayLine = SleepWindowCorrection.clip(
                recordedLine.map { SleepWindowCorrection.LineRun(it.stage, it.minutes, it.offsetMinutes) },
                bandStart = bandStart, start = start, end = wake,
                recordedIntervals = rawIntervalRows.mapNotNull { interval ->
                    val from = timestamp(interval.optStringOrNull("start")) ?: return@mapNotNull null
                    val to = timestamp(interval.optStringOrNull("end")) ?: return@mapNotNull null
                    if (to > from) SleepInterval(from, to) else null
                }).map { SleepStageRun(stage = it.stage, minutes = it.minutes, offsetMinutes = it.offsetMinutes) }
        }
        // A corrected reading at the same timestamp is one observation. Local observations win.
        val combinedOxygen = LinkedHashMap<Instant, OvernightOxygenPoint>().also { map ->
            for (p in oxygen) map[p.ts] = p
            for (p in if (sameWindow) local?.spo2 ?: emptyList() else emptyList()) map[p.ts] = p
        }.values.filter { inSleep(it.ts) }.sortedBy { it.ts }
        val combinedRespiration = LinkedHashMap<Instant, SleepRespirationPoint>().also { map ->
            for (p in respiration) map[p.ts] = p
            for (p in if (sameWindow) local?.respiration ?: emptyList() else emptyList()) map[p.ts] = p
        }.values.filter { inSleep(it.ts) }.sortedBy { it.ts }
        val hrvInvalidations = HashMap(remoteHRVInvalidations).also { map ->
            local?.hrvInvalidatedMinutes?.forEach { (k, v) -> map[k] = map[k]?.let { maxOf(it, v) } ?: v }
        }.filterKeys { inSleep(it) }
        // Edited snapshots contain coarse backfill too; rebuild that from the current raw samples.
        val localHRV = (if (local?.isCorrected == true || local?.isUserReported == true) emptyList()
            else local?.hrv ?: emptyList()).filter { inSleep(it.ts) }
        val hasLocalHRV = localHRV.isNotEmpty() || (sameWindow && local?.hrv != null)
        var combinedHRV: List<SleepHRVPoint>? = if (hrv == null && !hasLocalHRV && hrvInvalidations.isEmpty()) null
            else SleepHRVPoint.merging(hrv ?: emptyList(), localHRV, hrvInvalidations).filter { inSleep(it.ts) }
        val nightSamples = sleepSourceSamples.filter { inSleep(it.ts) }
        if (corrected || reported) {
            // The native minute wins. Coarser source samples only fill genuine gaps.
            val native = combinedHRV ?: emptyList()
            val fallback = SleepWindowCorrection.hrvBackfill(nightSamples, native.map { it.ts }, hrvInvalidations.keys.toList())
                .mapNotNull { sample -> sample.hrv?.let { SleepHRVPoint(ts = sample.ts, rmssdMS = it, observedAt = sample.hrvObservedAt) } }
            combinedHRV = (native + fallback).sortedBy { it.ts }
        }
        return SleepSummary(
            totalMinutes = total.toInt(),
            deepMinutes = night.number("deep_minutes")?.toInt() ?: 0,
            lightMinutes = night.number("light_minutes")?.toInt() ?: 0,
            wakeCount = night.number("wake_count")?.toInt() ?: 0,
            line = displayLine, sleepStart = start, wakeAt = wake,
            spo2 = combinedOxygen,
            respiration = combinedRespiration,
            hrv = combinedHRV,
            hrvInvalidatedMinutes = if (hrvInvalidations.isEmpty()) null else hrvInvalidations,
            intervals = intervals,
            correctedAt = if (corrected) (correctedAt ?: Instant.now()) else null,
            bandStart = if (corrected) bandStart else null,
            bandEnd = if (corrected) bandEnd else null,
            source = source,
            heartRate = nightSamples.filter { (it.hr ?: 0) > 0 })
    }

    /**
     * The server's row wins on every metric it carries; anything it does not carry keeps the
     * value already on screen. ⚠️ F2 rule 05 · when the server says UNLOGGED, every number
     * derived from intake goes back to null.
     */
    private fun merge(server: DailyMetrics, local: DailyMetrics, openSlots: Int): DailyMetrics {
        val m = server.copy()
        m.weightKg = server.weightKg ?: local.weightKg
        m.fatKg = local.fatKg
        m.leanKg = local.leanKg
        m.fatEmaDelta7d = server.fatEmaDelta7d ?: local.fatEmaDelta7d
        m.leanEmaDelta7d = server.leanEmaDelta7d ?: local.leanEmaDelta7d
        m.targetIn = server.targetIn ?: local.targetIn
        m.targetBasis = server.targetBasis ?: local.targetBasis
        m.targetBasisDays = server.targetBasisDays ?: local.targetBasisDays
        m.restingSource = server.restingSource ?: local.restingSource
        m.restingMeasuredAt = server.restingMeasuredAt ?: local.restingMeasuredAt
        m.goalOffset = server.goalOffset ?: local.goalOffset
        m.bmr = server.bmr
        m.bmrFull = server.bmrFull
        m.eActive = server.eActive
        m.eTrain = local.eTrain
        // A9 · what the planned session would actually cost this person, from their own weight.
        val gap = (server.targetLoad ?: 0.0) - (server.trainingLoad ?: 0.0)
        val plan: Pair<Double, Double>? = when {
            gap >= 8 -> 45.0 to 6.0
            gap >= 3 -> 30.0 to 6.0
            gap > 0 -> 20.0 to 3.5
            else -> null
        }
        m.eTrainPlan = plan?.let { p -> m.weightKg?.let { (p.second - 1) * 1.05 * it * (p.first / 60) } }
        m.activeForecast = server.activeForecast
        m.scans7d = if (server.scans7d > 0) server.scans7d else local.scans7d
        m.proteinIn = server.proteinIn
        m.carbIn = server.carbIn
        m.fatIn = server.fatIn
        m.serverCall = server.serverCall ?: local.serverCall
        m.logged7d = local.logged7d
        m.bandCoverage = local.bandCoverage
        m.worn = server.worn ?: local.worn
        m.wearRun = server.wearRun ?: local.wearRun
        m.wearMiss = server.wearMiss ?: local.wearMiss

        // The targets come from the server; only what was eaten is decided here.
        val pTarget = server.protein ?: local.protein
        val cTarget = server.carb ?: local.carb
        val fTarget = server.fat ?: local.fat
        when (server.fuelState) {
            is FuelState.Fasted -> {
                m.proteinIn = 0; m.carbIn = 0; m.fatIn = 0
                m.protein = pTarget?.let { MacroSlot(target = it.target, eaten = 0) }
                m.carb = cTarget?.let { MacroSlot(target = it.target, eaten = 0) }
                m.fat = fTarget?.let { MacroSlot(target = it.target, eaten = 0) }
                m.nextMeal = null
            }
            is FuelState.Unlogged -> {
                m.protein = pTarget?.let { MacroSlot(target = it.target, eaten = 0) }
                m.carb = cTarget?.let { MacroSlot(target = it.target, eaten = 0) }
                m.fat = fTarget?.let { MacroSlot(target = it.target, eaten = 0) }
                m.nextMeal = null
            }
            else -> {
                m.protein = pTarget
                m.carb = cTarget
                m.fat = fTarget
                // NEXT_MEAL · F2 · the remaining budget divided by the open slots.
                val target = m.targetIn
                val eaten = m.eIn
                m.nextMeal = if (target != null && eaten != null && openSlots > 0) {
                    val remaining = target - eaten
                    when {
                        remaining <= 0 -> null
                        openSlots == 1 -> remaining
                        else -> {
                            val share = remaining / openSlots
                            minOf(1200.0, maxOf(150.0, Math.floor(share / 50) * 50))
                        }
                    }
                } else null
            }
        }
        // ⚠️ Assembled last, out of exactly the three rows board 10 lists.
        val baseline = m.bmrFull
        val movement = m.activeForecast
        m.eOutFull = if (baseline != null && movement != null) baseline + movement + (m.eTrainPlan ?: 0.0) else null
        return m
    }

    // endregion

    // region parsing helpers (static in Swift)

    /** Overnight automatic SpO2 clipped to the recorded night. */
    @JvmName("overnightOxygenRows")
    fun overnightOxygen(rows: List<JSONObject>?, start: Instant?, wake: Instant?): List<OvernightOxygenPoint> =
        overnightOxygen(oxygenPoints(rows), start, wake)

    /** Every valid oxygen row in a read, parsed once. */
    fun oxygenPoints(rows: List<JSONObject>?): List<OvernightOxygenPoint> = (rows ?: emptyList()).mapNotNull { row ->
        val at = timestamp(row.optStringOrNull("ts")) ?: return@mapNotNull null
        val percent = number(row.opt("spo2"))?.toInt() ?: return@mapNotNull null
        if (percent !in 50..100) null else OvernightOxygenPoint(ts = at, percent = percent)
    }

    fun overnightOxygen(points: List<OvernightOxygenPoint>, start: Instant?, wake: Instant?): List<OvernightOxygenPoint> {
        if (start == null || wake == null || wake <= start) return emptyList()
        return points.filter { it.ts >= start && it.ts < wake }
    }

    /** Sleep belongs to its calendar wake date, independent of the activity cut. */
    private fun sleepOnWakeDay(sleep: SleepSummary?, day: UserDay): SleepSummary? {
        if (sleep == null) return null
        val wake = sleep.wakeAt ?: return sleep
        return if (wake.isSameDay(day.start)) sleep else null
    }

    fun sleepRespiration(raw: Any?, start: Instant?, wake: Instant?): List<SleepRespirationPoint> {
        if (start == null || wake == null || wake <= start) return emptyList()
        val rows = (raw as? JSONObject)?.arrayOrNull("respiration")?.objects() ?: emptyList()
        return rows.mapNotNull { row ->
            val at = timestamp(row.optStringOrNull("ts")) ?: return@mapNotNull null
            if (at < start || at >= wake) return@mapNotNull null
            val rate = number(row.opt("breaths_per_minute")) ?: return@mapNotNull null
            if (!rate.isFinite() || rate <= 0 || rate >= 255) null else SleepRespirationPoint(ts = at, breathsPerMinute = rate)
        }.sortedBy { it.ts }
    }

    /** null is a legacy row without minute-resolution HRV; [] is an observed empty night. */
    fun sleepHRV(raw: Any?, start: Instant?, wake: Instant?): List<SleepHRVPoint>? {
        val payload = raw as? JSONObject ?: return null
        if (!payload.has("hrv") && !payload.has("hrv_invalidated")) return null
        if (start == null || wake == null || wake <= start) return emptyList()
        val rows = payload.arrayOrNull("hrv")?.objects() ?: emptyList()
        val horizon = Instant.now().plusSeconds(300)
        val points = rows.mapNotNull { row ->
            val at = timestamp(row.optStringOrNull("ts")) ?: return@mapNotNull null
            if (at < start || at >= wake) return@mapNotNull null
            val value = number(row.opt("rmssd_ms")) ?: return@mapNotNull null
            if (!value.isFinite() || value !in 1.0..300.0) return@mapNotNull null
            val observedAt = timestamp(row.optStringOrNull("observed_at"))?.takeIf { it >= at && it <= horizon }
            SleepHRVPoint(ts = at, rmssdMS = value, observedAt = observedAt)
        }
        return SleepHRVPoint.merging(emptyList(), points, sleepHRVInvalidations(raw, start, wake))
    }

    fun sleepHRVInvalidations(raw: Any?, start: Instant?, wake: Instant?): Map<Instant, Instant> {
        if (start == null || wake == null || wake <= start) return emptyMap()
        val rows = (raw as? JSONObject)?.arrayOrNull("hrv_invalidated")?.objects() ?: emptyList()
        val horizon = Instant.now().plusSeconds(300)
        val out = HashMap<Instant, Instant>()
        for (row in rows) {
            if (row.optStringOrNull("reason") != "insufficient_adjacent_rr") continue
            val at = timestamp(row.optStringOrNull("ts")) ?: continue
            if (at < start || at >= wake) continue
            val observedAt = timestamp(row.optStringOrNull("observed_at")) ?: continue
            if (observedAt < at || observedAt > horizon) continue
            out[at] = out[at]?.let { maxOf(it, observedAt) } ?: observedAt
        }
        return out
    }

    /** Wrist optical meal-response scalars. The column is `optical`; zeros never arrive. */
    fun opticalResponse(rows: List<JSONObject>?): List<MealResponseIndex.Point> = (rows ?: emptyList()).mapNotNull { row ->
        val at = timestamp(row.optStringOrNull("ts")) ?: return@mapNotNull null
        val optical = number(row.opt("optical")) ?: return@mapNotNull null
        if (!optical.isFinite() || optical <= 0) null else MealResponseIndex.Point(ts = at, optical = optical)
    }

    /** Earliest bind or wrist tick on this account. A later rebind must not win. */
    private suspend fun loadCompanionSince(store: DataStore, generation: Long? = null, account: String? = null) {
        val generation = generation ?: sessionGeneration
        val account = account ?: account()
        val (bindAt, sampleAt) = coroutineScope {
            val bindRows = async { runCatching { db.select("devices", listOf(
                "select" to "bound_at", "order" to "bound_at.asc", "limit" to "1")) }.getOrNull() }
            val sampleRows = async { runCatching { db.select("raw_samples", listOf(
                "select" to "ts", "order" to "ts.asc", "limit" to "1")) }.getOrNull() }
            timestamp(bindRows.await()?.firstOrNull()?.optStringOrNull("bound_at")) to
                timestamp(sampleRows.await()?.firstOrNull()?.optStringOrNull("ts"))
        }
        if (account == null || account != account() || generation != sessionGeneration) return
        // DeviceCompanionMath.start: the earliest known candidate.
        listOfNotNull(bindAt, sampleAt, store.boundAt).minOrNull()?.let { store.boundAt = it }
    }

    /** Companionship only moves earlier. A seed rebind must not shrink WITH YOU. */
    private fun applyBoundAt(raw: Any?, store: DataStore, fallback: Instant? = null) {
        val incoming = (raw as? String)?.let(::timestamp) ?: fallback ?: return
        val existing = store.boundAt
        if (existing == null || incoming < existing) store.boundAt = incoming
    }

    /** PostgREST timestamps; strict form first, then the fallbacks. */
    fun timestamp(raw: String?): Instant? = HealthSnapshotRead.timestamp(raw)

    private fun snapshotReader(account: String, generation: Long, summaryGeneration: Long? = null) =
        HealthSnapshotRead(
            transport = HealthSnapshotRead.Transport(
                select = { table, query -> db.select(table, query) },
                status = { from, to ->
                    val rows = Json.rows(db.rpc("calculation_status", mapOf("p_from" to from, "p_to" to to), expectedOwner = account))
                        ?: throw HealthSnapshotRead.Failure.Unavailable
                    rows
                },
                metrics = { from, to ->
                    db.callFunction("metric-read", mapOf(
                        "metrics" to listOf("intakeKcal", "burnKcal", "deltaKcal", "proteinG", "nightHRV", "hrvBaseline", "nightRHR", "sleepMinutes"),
                        "from" to from, "to" to to, "timezone" to ZoneId.systemDefault().id), expectedOwner = account)
                },
                missingCapability = { e, capability -> isMissingReadCapability(e, capability) }),
            accepts = {
                HomeLaunchPolicy.acceptsRead(account, account(), generation, readGeneration) &&
                    (summaryGeneration == null || summaryGeneration == summaryReadGeneration)
            })

    /**
     * Additive server releases may lag an app update. Only a positively identified missing
     * capability permits legacy reads; authorization and service failures do not.
     */
    fun isMissingReadCapability(error: Throwable, capability: String): Boolean {
        val http = error as? SupabaseFailure.Http ?: return false
        if (http.code != 400 && http.code != 404) return false
        val text = http.body.lowercase()
        val missingColumn = text.contains("42703") || text.contains("does not exist") ||
            (text.contains("pgrst204") && text.contains("column"))
        return when (capability) {
            "meal_fields" -> HealthSnapshotRead.isMissingMealFields(error)
            "result_revision" -> text.contains("result_revision") && missingColumn
            "training_evidence" -> listOf("evidence", "recorded_steps").any { text.contains(it) } && missingColumn
            "worn" -> (text.contains("worn") || text.contains("wear_run") || text.contains("wear_miss")) && missingColumn
            "metric-read" -> http.code == 404 && (text.contains("requested function was not found") || text.contains("function not found"))
            "calculation_status" -> text.contains("calculation_status") &&
                (text.contains("pgrst202") || text.contains("could not find") ||
                    (text.contains("42883") && text.contains("does not exist")))
            else -> false
        }
    }

    private fun applyWear(row: JSONObject, metrics: DailyMetrics) {
        when (val worn = row.opt("worn")) {
            is Boolean -> metrics.worn = worn
            else -> number(worn)?.let { metrics.worn = it != 0.0 }
        }
        row.number("wear_run")?.let { metrics.wearRun = it.toInt() }
        row.number("wear_miss")?.let { metrics.wearMiss = it.toInt() }
    }

    private suspend fun calculationStatusIfAvailable(from: String, to: String): List<JSONObject>? = try {
        Json.rows(db.rpc("calculation_status", mapOf("p_from" to from, "p_to" to to)))
            ?: throw SupabaseFailure.Http(503, "Invalid calculation status")
    } catch (e: Exception) {
        if (!isMissingReadCapability(e, "calculation_status")) throw e
        null
    }

    /** 10E · every persisted `body_composition` row is a point. Source is not filtered. */
    private fun compositionScans(rows: List<JSONObject>): List<CompositionScan> = rows.mapNotNull { row ->
        val at = timestamp(row.optStringOrNull("measured_at")) ?: return@mapNotNull null
        CompositionScan(
            id = parseUuid(row.optStringOrNull("id")) ?: UUID.randomUUID(),
            at = at,
            bodyFatPercent = row.number("body_fat_pct"),
            fatMassKg = row.number("fat_mass_kg"),
            leanMassKg = row.number("lean_body_mass_kg"),
            bmrKcal = row.number("bmr_kcal"),
            inputWeightKg = row.number("input_weight_kg"),
            muscleMassKg = row.number("muscle_mass_kg"),
            bodyWaterPercent = row.number("body_water_pct"),
            boneMassKg = row.number("bone_mass_kg"),
            proteinPercent = row.number("protein_pct"))
    }.sortedByDescending { it.at }

    // endregion
}
