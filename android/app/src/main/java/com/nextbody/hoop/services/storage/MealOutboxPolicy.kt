package com.nextbody.hoop.services.storage

import org.json.JSONObject
import java.util.UUID

internal val UUID_PATTERN = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

/** Swift `UUID(uuidString:)` — strict 8-4-4-4-12 hex. */
fun parseUuid(raw: String?): UUID? = raw?.takeIf { UUID_PATTERN.matches(it) }?.let { UUID.fromString(it) }

fun UUID.lower(): String = toString().lowercase()

private fun JSONObject.merging(other: JSONObject): JSONObject {
    val out = JSONObject(this.toString())
    other.keys().forEach { out.put(it, other.opt(it)) }
    return out
}

private fun JSONObject.str(key: String): String? = if (isNull(key)) null else opt(key) as? String

/** Durable rejection state stays attached to its operation and preserves dependency order. */
object MealOutboxPolicy {
    /** Incomplete model output must remain a pending estimate, never a zero-macro meal. */
    fun promotedEstimate(operation: LocalOperation, output: JSONObject): ByteArray {
        val envelope = fields(operation)
        val original = envelope.optJSONObject("body")
        val draft = output.str("draft_id")
        if (original == null || parseUuid(draft) == null) throw LocalDataStore.Failure.Database("Invalid meal estimate")
        fun nutrient(key: String, minimum: Double): Double {
            val value = output.opt(key) as? Number
            val d = value?.toDouble()
            if (d == null || !d.isFinite() || d < minimum || d > 100000) {
                throw LocalDataStore.Failure.Database("Incomplete meal nutrients: $key")
            }
            return d
        }
        /** Present or absent, never null; 0 is not how this product says "unknown". */
        fun optional(key: String, value: Any?, into: JSONObject) {
            if (value == null || value == JSONObject.NULL) return
            if (value is String) { if (value.isNotEmpty()) into.put(key, value); return }
            val n = (value as? Number)?.toDouble() ?: return
            if (!n.isFinite() || n < 0 || n > 100000) return
            into.put(key, n)
        }
        val micros = output.optJSONObject("micros") ?: JSONObject()
        val plate = JSONObject()
        optional("meal_group_id", output.opt("group_id"), plate)
        optional("photo_path", output.opt("photo_path"), plate)
        optional("portion", output.opt("portion"), plate)
        optional("fiber_g", micros.opt("fiber"), plate)
        optional("sugar_g", micros.opt("sugar"), plate)
        optional("sodium_mg", micros.opt("sodium"), plate)
        val body = JSONObject()
            .put("id", operation.id).put("draft_id", draft)
            .put("user_day", original.opt("user_day") ?: "").put("slot", original.opt("slot") ?: "")
            .put("name", output.opt("name") ?: original.opt("name") ?: "")
            .put("kcal", nutrient("kcal", 0.0))
            .put("protein_g", nutrient("protein_g", 0.0)).put("carb_g", nutrient("carb_g", 0.0))
            .put("fat_g", nutrient("fat_g", 0.0))
            .put("confidence", output.opt("confidence") ?: "MEDIUM")
            .put("model_version", output.opt("model_version") ?: "")
            .merging(plate)
        return JSONObject().put("kind", "create").put("meal_id", operation.id).put("body", body).sortedBytes()
    }

    fun remappingMeal(operation: LocalOperation, oldID: String, canonicalID: String): ByteArray {
        val value = fields(operation)
        fun remap(fields: JSONObject, keys: List<String>): JSONObject {
            val out = JSONObject(fields.toString())
            for (key in keys) {
                val id = fields.str(key)
                if (id != null && id.lowercase() == oldID.lowercase()) out.put(key, canonicalID)
            }
            return out
        }
        val body = value.optJSONObject("body") ?: JSONObject()
        val nextBody = remap(body, listOf("id", "meal_id"))
        val next = remap(value, listOf("meal_id")).put("body", nextBody)
        if (value.str("kind") == "create" && body.str("id")?.lowercase() == oldID.lowercase() &&
            oldID.lowercase() != canonicalID.lowercase()) {
            next.put("canonical_previous_id", oldID)
        }
        return next.sortedBytes()
    }

    fun fields(operation: LocalOperation): JSONObject =
        runCatching { JSONObject(String(operation.payload, Charsets.UTF_8)) }.getOrNull()
            ?: throw LocalDataStore.Failure.Database("Invalid pending meal")

    fun affectedMeals(operation: LocalOperation): Set<String> {
        val value = fields(operation)
        val body = value.optJSONObject("body") ?: JSONObject()
        val replacement = body.optJSONObject("replacement") ?: JSONObject()
        return setOfNotNull(value.str("meal_id"), replacement.str("id"))
    }

    fun rejection(operation: LocalOperation): String? = fields(operation).str("rejection")

    fun replacingRejection(operation: LocalOperation, message: String?): ByteArray {
        val clean = fields(operation)
        clean.remove("rejection")
        if (message != null) clean.put("rejection", message)
        return clean.sortedBytes()
    }

    /** Rejected work blocks only dependent records. Independent meals can still upload. */
    fun runnable(operations: List<LocalOperation>): List<LocalOperation> {
        val blocked = mutableSetOf<String>()
        val result = mutableListOf<LocalOperation>()
        for (operation in operations) {
            val affected = affectedMeals(operation)
            if (rejection(operation) != null || blocked.any { it in affected }) blocked += affected
            else result += operation
        }
        return result
    }

    fun rejectedChain(id: String, operations: List<LocalOperation>): List<LocalOperation> {
        val initial = operations.firstOrNull { it.id == id } ?: return emptyList()
        if (rejection(initial) == null) return emptyList()
        val affected = affectedMeals(initial).toMutableSet()
        val result = mutableListOf(initial)
        var found = false
        for (operation in operations) {
            if (operation.id == id) { found = true; continue }
            if (!found) continue
            val related = affectedMeals(operation)
            if (affected.any { it in related }) { result += operation; affected += related }
        }
        return result
    }
}
