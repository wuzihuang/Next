package com.nextbody.hoop.band

import com.nextbody.hoop.services.Iso
import com.nextbody.hoop.services.Query
import com.nextbody.hoop.services.SessionChangedException
import com.nextbody.hoop.services.SupabaseFailure
import com.nextbody.hoop.services.optStringOrNull
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/**
 * A complete health read is published once, after all of its tables agree on a revision.
 * Derived nulls remain null; device observations are merged at publication time so a network
 * response cannot erase a tick collected while it was in flight.
 *
 * (Server snapshot reads — not HealthKit. Ported as-is.)
 */
class HealthSnapshotRead(
    private val transport: Transport,
    private val now: Instant = Instant.now(),
    private val accepts: () -> Boolean,
) {
    class Transport(
        val select: suspend (String, Query) -> List<JSONObject>,
        val status: suspend (String, String) -> List<JSONObject>,
        val metrics: suspend (String, String) -> JSONObject,
        val missingCapability: (Throwable, String) -> Boolean,
    )

    sealed class Failure(message: String) : Exception(message) {
        object RevisionChanged : Failure("revision changed")
        object Unavailable : Failure("unavailable")
    }

    data class Energy(
        val intake: Double?, val burn: Double?, val protein: Double?,
        val resting: Double?, val active: Double?,
    ) {
        val balance: Double? get() = intake?.let { eaten -> burn?.let { eaten - it } }
    }

    class Snapshot(val rows: List<JSONObject>, val fuel: List<JSONObject>) {
        var reserve: List<JSONObject> = emptyList()
        var training: List<JSONObject> = emptyList()
        var weighIns: List<JSONObject> = emptyList()
        var meals: List<JSONObject> = emptyList()
        var reserveSamples: List<JSONObject> = emptyList()
        var nights: List<JSONObject>? = null
        var oxygen: List<JSONObject>? = null
        var response: List<JSONObject>? = null
        var live: List<JSONObject> = emptyList()
        var liveStress: List<JSONObject>? = null
        var liveHeart: List<JSONObject>? = null
        internal var formalMetrics: List<JSONObject>? = null
        internal var remoteVitals: List<VitalSample> = emptyList()
        internal var accepts: () -> Boolean = { false }
        internal var didPublish: () -> Unit = {}

        /** Formal availability is distinct from a missing value. */
        val hasFormalMetrics: Boolean get() = formalMetrics != null

        fun value(metric: String, day: String, legacy: Any? = null): Double? {
            val formal = formalMetrics ?: return number(legacy)
            val points = formal.firstOrNull { it.optStringOrNull("metric") == metric }?.optJSONArray("points")
            val point = points?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } }
                ?.firstOrNull { it.optStringOrNull("dayKey") == day }
            return number(point?.opt("value"))
        }

        fun energy(day: String, legacy: JSONObject): Energy {
            val intake = value("intakeKcal", day, legacy.opt("kcal_in"))
            var burn = value("burnKcal", day, legacy.opt("kcal_out"))
            var resting = number(legacy.opt("bmr_kcal"))
            var active = number(legacy.opt("active_kcal"))
            if (hasFormalMetrics) {
                // Stale components cannot reconstruct an explicitly unavailable OUT.
                val sum = resting?.let { rest -> active?.let { rest + it } }
                if (burn == null || sum != burn) { resting = null; active = null }
            } else {
                // ActiveEnergyMath.totals(bmr:, eActive:, eTrain: nil, eOutNow:).out
                burn = resting?.let { rest -> active?.let { rest + it } } ?: burn
            }
            return Energy(intake, burn, value("proteinG", day, legacy.opt("protein_in_g")), resting, active)
        }

        fun vitals(day: UserDay, local: List<VitalSample>): List<VitalSample> {
            val remote = remoteVitals.filter { it.ts >= day.start && it.ts < day.end }
            return VitalSample.merging(remote, local.filter { it.ts >= day.start && it.ts < day.end })
        }

        /** Sleep windows can cross the activity-day boundary or be extended by the user. */
        fun sleepVitals(local: List<VitalSample>): List<VitalSample> = VitalSample.merging(remoteVitals, local)

        /**
         * No suspension occurs between this final eligibility check and updating the store, so a
         * late read cannot partially paint. Call on the main thread.
         */
        fun publish(apply: (Snapshot) -> Unit): Boolean {
            if (!accepts()) return false
            apply(this)
            didPublish()
            return true
        }
    }

    companion object {
        private const val dailyColumns = "id,user_day,training_load,reserve_score,fuel_balance_kcal,daily_direction,the_call,the_call_confidence,fat_delta_7d,lean_delta_7d,scans_7d,computed_at,algo_version,result_revision,worn,wear_run,wear_miss"
        private val optionalMealColumns = setOf("meal_group_id", "portion", "photo_path", "fiber_g", "sugar_g", "sodium_mg")

        fun number(any: Any?): Double? = when (any) {
            null, JSONObject.NULL -> null
            is Number -> any.toDouble()
            is String -> any.toDoubleOrNull()
            else -> null
        }

        /** PostgREST timestamps, hand-parsed (ISOTimestamp). */
        fun timestamp(raw: String?): Instant? = Iso.parse(raw)

        /** HomeLaunchPolicy.postgrestIn */
        internal fun postgrestIn(ids: List<String>): String? {
            val clean = ids.filter { it.isNotEmpty() }
            if (clean.isEmpty()) return null
            return "in.(${clean.joinToString(",")})"
        }

        /** HomeLaunchPolicy.shouldRefreshSummary */
        internal fun shouldRefreshSummary(revision: String?, cachedRevision: String?, hasCachedRow: Boolean): Boolean {
            if (revision == null) return true
            return !hasCachedRow || revision != cachedRevision
        }

        /** The plate migration is additive; only an explicit missing-column response permits the fallback. */
        fun isMissingMealFields(error: Throwable): Boolean {
            val http = error as? SupabaseFailure.Http ?: return false
            if (http.code != 400 && http.code != 404) return false
            val payload = runCatching { JSONObject(http.body) }.getOrNull() ?: return false
            val code = payload.optStringOrNull("code") ?: return false
            val message = payload.optStringOrNull("message") ?: return false
            val columns = optionalMealColumns.sorted().joinToString("|")
            val pattern = when (code) {
                "42703" -> "^column\\s+(?:\"?meals\"?\\.)?\"?(?:$columns)\"?\\s+does not exist$"
                "PGRST204" -> "^Could not find the '(?:$columns)' column of 'meals' in the schema cache$"
                else -> return false
            }
            return Regex(pattern, RegexOption.IGNORE_CASE).containsMatchIn(message)
        }

        fun decodeVitals(rows: List<JSONObject>): List<VitalSample> = rows.mapNotNull { row ->
            val at = timestamp(row.optStringOrNull("ts")) ?: return@mapNotNull null
            val hr = number(row.opt("heart"))?.toInt()
            val stress = number(row.opt("stress"))?.toInt()
            val temp = number(row.opt("temp"))
            val steps = number(row.opt("step"))?.toInt()
            val met = number(row.opt("met"))
            val evidence = row.optJSONObject("domain_sources")?.optJSONObject("hrv")
            val valid = evidence?.let { if (it.isNull("hrv_valid")) null else it.opt("hrv_valid") as? Boolean }
            val observedAt = timestamp(evidence?.optStringOrNull("observed_at"))
            val hrv = if (valid == false) null else number(row.opt("hrv"))
            if (hr == null && stress == null && temp == null && steps == null && met == null && hrv == null && valid != false) {
                return@mapNotNull null
            }
            VitalSample(ts = at, hr = hr, stress = stress, temp = temp, steps = steps, met = met,
                vendorCalories = number(row.opt("cal")), dis = number(row.opt("dis")), hrv = hrv,
                hrvValid = valid, hrvObservedAt = observedAt)
        }

        /** A 409 is an optimistic-read conflict; other failures keep their meaning. */
        private fun readFailure(error: Throwable): Throwable =
            if (error is SupabaseFailure.Http && error.code == 409) Failure.RevisionChanged else error
    }

    private suspend fun checkCurrent() {
        if (!accepts() || !currentCoroutineContext().isActive) throw SessionChangedException()
    }

    private suspend fun select(table: String, query: Query): List<JSONObject> {
        try {
            checkCurrent()
            val rows = transport.select(table, query)
            checkCurrent()
            return rows
        } catch (e: Throwable) {
            throw readFailure(e)
        }
    }

    private suspend fun selectSamplePages(table: String, query: Query): List<JSONObject> {
        val base = query.filter { it.first !in setOf("order", "offset", "limit") }
        return SamplePageRead.all { offset ->
            select(table, base + listOf("order" to "ts.asc,src.asc", "offset" to offset.toString(), "limit" to "1000"))
        }
    }

    private fun stripColumns(query: Query, columns: Set<String>): Query = query.map { (k, v) ->
        if (k == "select") k to v.split(",").filter { it !in columns }.joinToString(",") else k to v
    }

    private suspend fun selectMealsCompat(query: Query): List<JSONObject> = try {
        select("meals", query)
    } catch (e: Throwable) {
        if (!transport.missingCapability(e, "meal_fields")) throw e
        // Exactly one retry, with identical IDs, window, ordering and privacy filters.
        select("meals", stripColumns(query, optionalMealColumns))
    }

    private suspend fun selectDailyResultsCompat(initial: Query): Pair<List<JSONObject>, Boolean> {
        var query = initial
        var versioned = true
        val removed = mutableSetOf<String>()
        while (true) {
            try {
                return select("daily_results", query) to versioned
            } catch (e: Throwable) {
                val capability = when {
                    "worn" !in removed && transport.missingCapability(e, "worn") -> "worn"
                    "result_revision" !in removed && transport.missingCapability(e, "result_revision") -> {
                        versioned = false; "result_revision"
                    }
                    else -> throw e
                }
                removed += capability
                val columns = if (capability == "worn") setOf("worn", "wear_run", "wear_miss") else setOf("result_revision")
                query = stripColumns(query, columns)
            }
        }
    }

    private suspend fun metricReadIfAvailable(from: String, to: String): JSONObject? = try {
        checkCurrent()
        val reply = transport.metrics(from, to)
        checkCurrent()
        reply
    } catch (e: Throwable) {
        if (!transport.missingCapability(e, "metric-read")) throw readFailure(e)
        null
    }

    private suspend fun calculationStatusIfAvailable(from: String, to: String): List<JSONObject>? = try {
        checkCurrent()
        val reply = transport.status(from, to)
        checkCurrent()
        reply
    } catch (e: Throwable) {
        if (!transport.missingCapability(e, "calculation_status")) throw readFailure(e)
        null
    }

    private suspend fun verify(rows: List<JSONObject>, versioned: Boolean, formalMetrics: List<JSONObject>?,
                               from: String, to: String, statusRequired: Boolean = false) {
        if (!versioned) return
        for (metric in formalMetrics ?: emptyList()) {
            if (metric.optStringOrNull("metric") == "sleepMinutes") continue
            val points = metric.optJSONArray("points") ?: JSONArray()
            for (i in 0 until points.length()) {
                val point = points.optJSONObject(i) ?: continue
                val row = rows.firstOrNull { it.optStringOrNull("user_day") == point.optStringOrNull("dayKey") }
                if (row != null && row.optStringOrNull("result_revision") != point.optStringOrNull("resultRevision")) {
                    throw Failure.RevisionChanged
                }
            }
        }
        val status = calculationStatusIfAvailable(from, to)
        if (status != null) {
            val all = rows.all { row ->
                status.any {
                    it.optStringOrNull("user_day") == row.optStringOrNull("user_day") &&
                        it.optStringOrNull("result_revision") == row.optStringOrNull("result_revision")
                }
            }
            if (!all) throw Failure.RevisionChanged
        } else if (statusRequired) throw Failure.RevisionChanged
    }

    private suspend fun selectByResultId(table: String, columns: String, ids: List<String>): List<JSONObject> {
        val clean = ids.filter { it.isNotEmpty() }
        val rows = mutableListOf<JSONObject>()
        for (chunk in clean.chunked(80)) {
            val filter = postgrestIn(chunk) ?: continue
            rows += select(table, listOf("select" to columns, "result_id" to filter))
        }
        return rows
    }

    private suspend fun selectTrainingExtras(ids: List<String>): List<JSONObject>? =
        runCatching { selectByResultId("daily_training", "result_id,active_minutes,distance_m", ids) }.getOrNull()

    private suspend fun selectTrainingEvidence(ids: List<String>): List<JSONObject>? = try {
        selectByResultId("daily_training", "result_id,recorded_steps,evidence", ids)
    } catch (e: Throwable) {
        if (transport.missingCapability(e, "training_evidence")) null else throw e
    }

    private suspend fun selectFuelBasis(ids: List<String>): List<JSONObject>? =
        runCatching { selectByResultId("day_fuel", "result_id,target_basis_kcal,target_basis_days", ids) }.getOrNull()

    private fun byResultId(rows: List<JSONObject>): Map<String, JSONObject> =
        rows.mapNotNull { r -> r.optStringOrNull("result_id")?.let { it to r } }.toMap()

    suspend fun detail(days: Int, endingAt: UserDay): Snapshot? {
        checkCurrent()
        val day = endingAt
        val from = day.adding(-days).key
        val to = day.key
        val (rows, versioned) = selectDailyResultsCompat(listOf(
            "select" to dailyColumns, "user_day" to "gte.$from", "user_day" to "lte.$to", "order" to "user_day.asc"))
        val resultIds = rows.mapNotNull { it.optStringOrNull("id") }
        val dayStart = Iso.string(day.start)
        val dayEnd = Iso.string(day.adding(1).start)
        val vitalsStart = Iso.string(day.adding(-maxOf(days, 1) - 1).start)
        val responseStart = Iso.string(day.adding(-30).start)
        val observedUntil = Iso.string(now)

        return coroutineScope {
            // Raw samples are available before settle_now has produced daily_results; these
            // independent requests run together so correctness adds no serial round trips.
            val formalRead = async { runCatching { metricReadIfAvailable(from, to) } }
            val fuelRows = async { runCatching { selectByResultId("day_fuel",
                "result_id,intake_state,kcal_in,kcal_out,protein_in_g,slot_states,bmr_kcal,active_kcal,bmr_full_kcal,target_in,target_basis_kcal,resting_source,resting_measured_at,goal_offset_kcal,protein_g,fat_g,carb_g,carb_in_g,fat_in_g,weight_kg,energy_distribution",
                resultIds) } }
            val reserveRows = async { runCatching { selectByResultId("reserve_daily",
                "result_id,wake_value,current_value,min_value,drain_drivers,night_inputs", resultIds) } }
            val trainingRows = async { runCatching { selectByResultId("daily_training",
                "result_id,zone_minutes,peak_hr,curve,segments", resultIds) } }
            val trainingExtras = async { selectTrainingExtras(resultIds) }
            val fuelBasisRows = async { selectFuelBasis(resultIds) }
            val trainingEvidenceRows = async { runCatching { selectTrainingEvidence(resultIds) } }
            val weighInRows = async { runCatching { select("weigh_ins", listOf(
                "select" to "id,measured_at,weight_kg,source", "order" to "measured_at.desc", "limit" to "60")) } }
            val weekMealRows = async { runCatching { selectMealsCompat(listOf(
                "select" to "id,user_day,slot,logged_at,text_input,kcal,protein_g,carb_g,fat_g,meal_group_id,portion,photo_path,fiber_g,sugar_g,sodium_mg",
                "deleted_at" to "is.null",
                // Dev seeds carry model_version = seed; they must not populate 09 or the dock.
                "model_version" to "neq.seed",
                "user_day" to "gte.${day.adding(-maxOf(days, 6)).key}",
                "user_day" to "lte.${day.key}",
                "order" to "logged_at.asc")) } }
            val sampleRows = async { runCatching { select("reserve_samples", listOf(
                "select" to "ts,value", "ts" to "gte.$dayStart", "ts" to "lt.$dayEnd", "order" to "ts.asc")) } }
            val vitalRows = async { runCatching { selectSamplePages("raw_samples", listOf(
                "select" to "ts,heart,stress,temp,step,met,cal,dis,hrv,domain_sources",
                "ts" to "gte.$vitalsStart", "ts" to "lt.$dayEnd", "order" to "ts.asc")) } }
            val liveRows = async { runCatching { select("raw_samples", listOf(
                "select" to "ts,heart,stress", "ts" to "lte.$observedUntil", "order" to "ts.desc", "limit" to "1")) } }
            val liveStressRows = async { runCatching { select("raw_samples", listOf(
                "select" to "ts,stress", "stress" to "gt.0", "ts" to "lte.$observedUntil", "order" to "ts.desc", "limit" to "1")) }.getOrNull() }
            val liveHeartRows = async { runCatching { select("raw_samples", listOf(
                "select" to "ts,heart", "heart" to "gt.0", "ts" to "lte.$observedUntil", "order" to "ts.desc", "limit" to "1")) }.getOrNull() }
            val nightRows = async { runCatching { select("sleep_nights", listOf(
                "select" to "user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_line,sleep_start,wake_at,raw,corrected_start,corrected_end,corrected_at",
                "user_day" to "gte.$from", "user_day" to "lte.$to")) }.getOrNull() }
            val oxygenRows = async { runCatching { select("oxygen_samples", listOf(
                "select" to "ts,spo2", "ts" to "gte.$vitalsStart", "ts" to "lt.$dayEnd", "order" to "ts.asc")) }.getOrNull() }
            val responseRows = async { runCatching { select("response_samples", listOf(
                "select" to "ts,optical", "ts" to "gte.$responseStart", "ts" to "lt.$dayEnd", "order" to "ts.asc")) }.getOrNull() }

            var fuel = fuelRows.await().getOrThrow()
            fuelBasisRows.await()?.let { basisRows ->
                val by = byResultId(basisRows)
                fuel = fuel.map { row ->
                    val basis = row.optStringOrNull("result_id")?.let { by[it] } ?: return@map row
                    JSONObject(row.toString())
                        .put("target_basis_kcal", basis.opt("target_basis_kcal") ?: JSONObject.NULL)
                        .put("target_basis_days", basis.opt("target_basis_days") ?: JSONObject.NULL)
                }
            }
            val reserve = reserveRows.await().getOrThrow()
            var training = trainingRows.await().getOrThrow()
            trainingExtras.await()?.let { extras ->
                val by = byResultId(extras)
                training = training.map { row ->
                    val e = row.optStringOrNull("result_id")?.let { by[it] } ?: return@map row
                    JSONObject(row.toString())
                        .put("active_minutes", e.opt("active_minutes") ?: JSONObject.NULL)
                        .put("distance_m", e.opt("distance_m") ?: JSONObject.NULL)
                }
            }
            trainingEvidenceRows.await().getOrThrow()?.let { evidenceRows ->
                val by = byResultId(evidenceRows)
                training = training.map { row ->
                    val evidence = row.optStringOrNull("result_id")?.let { by[it] } ?: return@map row
                    JSONObject(row.toString())
                        .put("recorded_steps", evidence.opt("recorded_steps") ?: JSONObject.NULL)
                        .put("evidence", evidence.opt("evidence") ?: JSONObject.NULL)
                }
            }
            val weighIns = weighInRows.await().getOrThrow()
            val weekRows = weekMealRows.await().getOrThrow()
            val samples = sampleRows.await().getOrThrow()
            val vitals = vitalRows.await().getOrThrow()
            val nights = nightRows.await()
            val oxygen = oxygenRows.await()
            val response = responseRows.await()
            val live = liveRows.await().getOrThrow()
            val liveStress = liveStressRows.await()
            val liveHeart = liveHeartRows.await()
            val formal = formalRead.await().getOrThrow()
            val formalMetrics: List<JSONObject>? = if (formal != null) {
                val data = formal.optJSONArray("data")
                if (formal.opt("ok") != true || data == null) throw Failure.Unavailable
                (0 until data.length()).mapNotNull { data.optJSONObject(it) }
            } else null
            verify(rows, versioned, formalMetrics, from, to)
            checkCurrent()
            Snapshot(rows, fuel).also { s ->
                s.reserve = reserve; s.training = training
                s.weighIns = weighIns; s.meals = weekRows
                s.reserveSamples = samples; s.nights = nights
                s.oxygen = oxygen; s.response = response
                s.live = live; s.liveStress = liveStress; s.liveHeart = liveHeart
                s.formalMetrics = formalMetrics; s.remoteVitals = decodeVitals(vitals)
                s.accepts = accepts
            }
        }
    }

    /**
     * Status narrows summaries to changed days. Revisions become known only after the complete
     * result was accepted, never merely because a request returned.
     */
    suspend fun summaries(days: Int, endingAt: UserDay, known: Map<String, String>,
                          cachedDays: Set<String>, didPublish: (Map<String, String>) -> Unit): Snapshot? {
        checkCurrent()
        val day = endingAt
        val from = day.adding(-minOf(days, 182)).key
        val status = calculationStatusIfAvailable(from, day.key)
        var range: Query = listOf("user_day" to "gte.$from")
        if (status != null) {
            val changed = status.mapNotNull { row ->
                val key = row.optStringOrNull("user_day") ?: return@mapNotNull null
                if (shouldRefreshSummary(row.optStringOrNull("result_revision"), known[key], key in cachedDays)) key else null
            }
            val filter = postgrestIn(changed) ?: return null
            range = listOf("user_day" to filter)
        }
        val (rows, versioned) = selectDailyResultsCompat(listOf(
            "select" to dailyColumns, "user_day" to "lte.${day.key}", "order" to "user_day.asc") + range)
        val ids = rows.mapNotNull { it.optStringOrNull("id") }
        return coroutineScope {
            val trainingRows = async { runCatching { selectTrainingEvidence(ids) } }
            val fuel = selectByResultId("day_fuel",
                "result_id,kcal_in,kcal_out,protein_in_g,carb_in_g,fat_in_g,weight_kg,intake_state,slot_states", ids)
            val training = trainingRows.await().getOrThrow() ?: emptyList()
            if (status != null) verify(rows, versioned, null, from, day.key, statusRequired = true)
            checkCurrent()
            Snapshot(rows, fuel).also { s ->
                s.training = training
                s.accepts = accepts
                s.didPublish = {
                    val revisions = known.toMutableMap()
                    for (row in rows) {
                        val key = row.optStringOrNull("user_day") ?: continue
                        val revision = row.optStringOrNull("result_revision") ?: continue
                        revisions[key] = revision
                    }
                    didPublish(revisions)
                }
            }
        }
    }
}
