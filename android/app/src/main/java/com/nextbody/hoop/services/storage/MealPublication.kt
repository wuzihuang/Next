package com.nextbody.hoop.services.storage

import com.nextbody.hoop.services.Iso
import com.nextbody.hoop.services.SessionChangedException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.UUID

/**
 * A confirmed meal is durable before it becomes visible. Manual entries, accepted estimates
 * and later changes share identity, dependency order and acknowledgment.
 */
class MealPublication(
    private val account: String,
    private val local: LocalDataStore,
    private val isCurrent: () -> Boolean,
    private val consent: () -> Boolean,
    private val send: suspend (endpoint: String, body: JSONObject, owner: String) -> JSONObject,
    private val persistProjection: () -> Unit,
) {
    sealed class Failure(message: String) : Exception(message) {
        class InvalidMeal : Failure("Check the meal name, date and nutrients.")
        class CollectionPaused : Failure("Data collection is paused. Pending meals stay on this device.")
        class Http(val status: Int, val body: String) : Failure("Meal synchronization failed (HTTP $status).")
        class InvalidAcknowledgment : Failure("Meal acknowledgment did not match the pending operation.")
    }

    data class Submitted(val id: UUID, val fields: JSONObject)
    data class Replay(var acknowledged: Int = 0, var message: String? = null)
    data class VisibleMeal(
        val id: UUID, val day: String, val at: Instant, val slot: String, val name: String,
        val kcal: Double, val protein: Double, val carb: Double, val fat: Double,
        val confirmed: Boolean, val source: String?, val revisions: Int?, val groupID: String?,
        val portion: String?, val photoPath: String?, val fiber: Double?, val sugar: Double?, val sodium: Double?,
    )
    data class Projection(val meals: List<VisibleMeal>, val removedIDs: Set<UUID>)

    companion object {
        const val pausedMessage = "Data collection is paused. Pending meals stay on this device."
        const val rejectedMessage = "This change could not sync. Retry it or remove the pending change."
        private val strictDay: DateTimeFormatter = DateTimeFormatter.ofPattern("uuuu-MM-dd").withResolverStyle(ResolverStyle.STRICT)
    }

    private fun JSONObject.str(key: String): String? = if (isNull(key)) null else opt(key) as? String
    private fun JSONObject.num(key: String): Double? = if (isNull(key)) null else (opt(key) as? Number)?.toDouble()

    fun createManual(id: UUID = UUID.randomUUID(), day: String, slot: String, name: String,
                     kcal: Double, at: Instant): Submitted =
        create(id, JSONObject()
            .put("draft_id", id.lower()).put("user_day", day).put("slot", slot)
            .put("name", name.trim()).put("kcal", kcal)
            .put("protein_g", 0).put("carb_g", 0).put("fat_g", 0)
            .put("confidence", "HIGH").put("model_version", "manual-entry-v1")
            .put("logged_at", Iso.string(at)), source = "TYPED")

    fun confirmDraft(id: UUID = UUID.randomUUID(), day: String, slot: String,
                     output: JSONObject, at: Instant): Submitted {
        val out = JSONObject(output.toString())
        out.optJSONObject("macros")?.let { macros ->
            if (!out.has("protein_g")) macros.opt("p")?.let { out.put("protein_g", it) }
            if (!out.has("carb_g")) macros.opt("c")?.let { out.put("carb_g", it) }
            if (!out.has("fat_g")) macros.opt("f")?.let { out.put("fat_g", it) }
        }
        val envelope = JSONObject().put("kind", "estimate").put("meal_id", id.lower())
            .put("body", JSONObject().put("user_day", day).put("slot", slot).put("name", out.opt("name") ?: ""))
        val operation = LocalOperation(id.lower(), account, "meal", envelope.toString().toByteArray())
        val promoted = MealOutboxPolicy.promotedEstimate(operation, out)
        val fields = runCatching { JSONObject(String(promoted)) }.getOrNull() ?: throw Failure.InvalidMeal()
        val body = fields.optJSONObject("body") ?: throw Failure.InvalidMeal()
        body.put("logged_at", Iso.string(at))
        return create(id, body, source = if (out.str("source") == "photo") "PHOTO" else "TYPED", revisions = 1)
    }

    fun create(id: UUID, fields: JSONObject, source: String? = null, revisions: Int = 0): Submitted {
        val draft = fields.str("draft_id")
        if (parseUuid(draft) == null) throw Failure.InvalidMeal()
        validate(fields)
        val body = JSONObject(fields.toString()).put("id", id.lower())
        retain(draft!!.lowercase(), "create", id, body, source, revisions)
        return Submitted(id, body)
    }

    fun amend(id: UUID, replacement: JSONObject, source: String? = null, revisions: Int = 1,
              operationID: UUID = UUID.randomUUID()): Submitted {
        val replacementID = parseUuid(replacement.str("id")) ?: throw Failure.InvalidMeal()
        validate(replacement)
        val op = operationID.lower()
        retain(op, "amend", id, JSONObject().put("operation_id", op).put("kind", "amend")
            .put("meal_id", id.lower()).put("replacement", replacement), source, revisions)
        return Submitted(replacementID, replacement)
    }

    fun delete(id: UUID, operationID: UUID = UUID.randomUUID()) {
        val op = operationID.lower()
        retain(op, "delete", id, JSONObject().put("operation_id", op).put("kind", "delete").put("meal_id", id.lower()))
    }

    private fun requireCurrent() {
        if (account.isEmpty() || !isCurrent()) throw SessionChangedException()
    }

    private suspend fun requireCurrentActive() {
        requireCurrent()
        if (!currentCoroutineContext().isActive) throw SessionChangedException("cancelled")
    }

    private fun retain(id: String, kind: String, mealID: UUID, body: JSONObject, source: String? = null, revisions: Int = 0) {
        requireCurrent()
        if (kind != "delete" && !consent()) throw Failure.CollectionPaused()
        val envelope = JSONObject().put("kind", kind).put("meal_id", mealID.lower()).put("body", body).put("revisions", revisions)
        if (source != null) envelope.put("source", source)
        val bytes = envelope.sortedBytes()
        local.enqueue(LocalOperation(id, account, "meal", bytes), "meal.${mealID.lower()}", bytes)
    }

    /** Display metadata lives in the durable envelope, outside the server's immutable meal fields. */
    fun projection(): Projection {
        requireCurrent()
        val entries = mutableListOf<VisibleMeal>()
        val removed = mutableSetOf<UUID>()
        for (operation in local.operations(account, "meal")) {
            val envelope = MealOutboxPolicy.fields(operation)
            val kind = envelope.str("kind") ?: continue
            val body = envelope.optJSONObject("body") ?: continue
            val originalID = parseUuid(envelope.str("meal_id")) ?: continue
            parseUuid(envelope.str("canonical_previous_id"))?.let { oldID ->
                removed += oldID; entries.removeAll { it.id == oldID }
            }
            if (kind == "amend" || kind == "delete") {
                removed += originalID; entries.removeAll { it.id == originalID }
            }
            if (kind == "delete") continue
            val fields = (if (kind == "amend") body.optJSONObject("replacement") else body) ?: continue
            val id = parseUuid(fields.str("id")) ?: continue
            val day = fields.str("user_day") ?: continue
            val date = runCatching { LocalDate.parse(day) }.getOrNull() ?: continue
            val noon = date.atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant()
            val slot = fields.str("slot") ?: continue
            val at = Iso.parse(fields.str("logged_at")) ?: noon
            entries.removeAll { it.id == id }
            entries += VisibleMeal(
                id = id, day = day, at = at, slot = slot, name = fields.str("name") ?: "",
                kcal = fields.num("kcal") ?: 0.0, protein = fields.num("protein_g") ?: 0.0,
                carb = fields.num("carb_g") ?: 0.0, fat = fields.num("fat_g") ?: 0.0,
                confirmed = kind != "estimate" && !envelope.has("rejection"),
                source = envelope.str("source"),
                revisions = (envelope.opt("revisions") as? Number)?.toInt(),
                groupID = fields.str("meal_group_id"), portion = fields.str("portion"),
                photoPath = fields.str("photo_path"), fiber = fields.num("fiber_g"),
                sugar = fields.num("sugar_g"), sodium = fields.num("sodium_mg"))
        }
        return Projection(entries, removed)
    }

    private fun validate(fields: JSONObject) {
        fun validNutrient(raw: Any?): Boolean {
            val n = (raw as? Number)?.toDouble() ?: return false
            return n.isFinite() && n in 0.0..100000.0
        }
        val name = fields.str("name")
        val day = fields.str("user_day")
        val slot = fields.str("slot")
        val ok = name != null && name.trim().isNotEmpty() && name.length <= 8000 && day != null &&
            slot != null && slot in listOf("BREAKFAST", "LUNCH", "DINNER", "SNACK") &&
            validNutrient(fields.opt("kcal")) &&
            listOf("protein_g", "carb_g", "fat_g").all { validNutrient(fields.opt(it)) } &&
            listOf("fiber_g", "sugar_g", "sodium_mg").all { !fields.has(it) || validNutrient(fields.opt(it)) }
        if (!ok) throw Failure.InvalidMeal()
        if (runCatching { LocalDate.parse(day, strictDay) }.getOrNull()?.toString() != day) throw Failure.InvalidMeal()
    }

    /**
     * Drain one finite snapshot. Rejected changes block only their dependents; lost replies and
     * local save failures leave the original operation available to retry.
     */
    suspend fun replay(): Replay {
        requireCurrentActive()
        val result = Replay()
        var collectionPaused = !consent()
        for (queued in local.operations(account, "meal")) {
            requireCurrentActive()
            val rows = local.operations(account, "meal")
            val operation = rows.firstOrNull { it.id == queued.id } ?: continue
            val fields = MealOutboxPolicy.fields(operation)
            val probe = fields.has("rejection") && fields.str("kind") == "create" &&
                fields.opt("canonical_probe_attempted") != true
            val runnable = MealOutboxPolicy.runnable(rows)
            if (!probe && runnable.none { it.id == operation.id }) continue
            try {
                val envelope = MealOutboxPolicy.fields(operation)
                val kind = envelope.str("kind")
                if (!(kind == "delete" || (!collectionPaused && consent()))) {
                    result.message = pausedMessage; continue
                }
                if (kind == "estimate") {
                    val message = "Send this meal again to review and confirm its estimate."
                    val payload = MealOutboxPolicy.replacingRejection(operation, message)
                    local.replaceOperation(operation, payload, "meal.${operation.id}")
                    result.message = message; continue
                }
                val body = envelope.optJSONObject("body")
                if (body == null || kind == null) throw Failure.InvalidMeal()
                val request = if (probe) JSONObject(body.toString()).put("reconcile_only", true) else body
                val response = send(if (kind == "create") "meal-commit" else "meal-operation", request, account)
                requireCurrent()
                if (!(kind == "delete" || consent())) throw Failure.CollectionPaused()
                val ack = response.str(if (kind == "create") "client_op_id" else "operation_id")
                val acceptedID = response.str("id")?.lowercase()
                val requestedID = body.str("id")?.lowercase()
                val canonicalMatch = kind == "create" && parseUuid(acceptedID) != null &&
                    response.str("requested_meal_id")?.lowercase() == requestedID &&
                    response.str("meal_id")?.lowercase() == acceptedID
                val expectedAck = if (kind == "create") body.str("draft_id")?.lowercase() else operation.id.lowercase()
                if (ack?.lowercase() != expectedAck || !(kind != "create" || acceptedID == requestedID || canonicalMatch)) {
                    throw Failure.InvalidAcknowledgment()
                }
                if (kind == "create" && requestedID != null && acceptedID != null && (canonicalMatch || probe)) {
                    val changes = local.operations(account, "meal").map { row ->
                        val mapped = MealOutboxPolicy.remappingMeal(row, requestedID, acceptedID)
                        val remapped = LocalOperation(row.id, row.account, row.kind, mapped)
                        val payload = if (row.id == operation.id) MealOutboxPolicy.replacingRejection(remapped, null) else mapped
                        val f = MealOutboxPolicy.fields(remapped)
                        Triple(row, payload, "meal.${f.str("meal_id") ?: row.id}")
                    }
                    local.replaceOperations(changes)
                }
                // The pending projection includes canonical aliases, so the saved display and
                // dependent changes agree before the acknowledged fact leaves the queue.
                persistProjection()
                requireCurrent()
                local.acknowledge(account, operation.id)
                result.acknowledged += 1
            } catch (e: Failure.Http) {
                val code = e.status
                if (code == 403) {
                    requireCurrent()
                    collectionPaused = true; result.message = pausedMessage
                } else if (code in 400..499 && code != 401 && code != 408 && code != 429) {
                    requireCurrent()
                    val serverBody = runCatching { JSONObject(e.body) }.getOrNull()
                    val serverError = serverBody?.str("error")
                    // The server's own word for the refusal rides in the message.
                    val reason = listOfNotNull(serverBody?.str("reason"), serverError)
                        .firstOrNull { it.isNotEmpty() && it != "E_SCHEMA" }
                    val rejected = MealOutboxPolicy.replacingRejection(operation,
                        reason?.let { "$rejectedMessage [$it]" } ?: rejectedMessage)
                    val rejectedOperation = LocalOperation(operation.id, operation.account, operation.kind, rejected)
                    val f = MealOutboxPolicy.fields(rejectedOperation)
                    val definitiveMismatch = code == 409 && (serverError ?: "") in listOf("NO_CANONICAL_MATCH", "OPERATION_CONFLICT")
                    if (probe && definitiveMismatch) f.put("canonical_probe_attempted", true)
                    local.replaceOperation(operation, f.sortedBytes(), "meal.${operation.id}")
                } else {
                    throw e
                }
            }
        }
        return result
    }
}
