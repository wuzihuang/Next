package com.nextbody.hoop.band

import com.nextbody.hoop.services.SupabaseFailure

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/** `[String: Any]` from JSONSerialization, in Kotlin: maps, lists, strings, numbers, booleans, null. */
internal fun jsonToKotlin(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONObject -> value.keys().asSequence().associateWith { jsonToKotlin(value.opt(it)) }
    is JSONArray -> (0 until value.length()).map { jsonToKotlin(value.opt(it)) }
    else -> value
}

internal fun kotlinToJson(value: Any?): Any? = when (value) {
    null -> JSONObject.NULL
    is Map<*, *> -> JSONObject().also { o -> value.forEach { (k, v) -> o.put(k.toString(), kotlinToJson(v)) } }
    is Collection<*> -> JSONArray().also { a -> value.forEach { a.put(kotlinToJson(it)) } }
    is Instant -> value.toString()
    else -> value
}

class BandBundleReply(response: Any?) {
    sealed class Entry {
        data class Ok(val acknowledgment: BandIngestionAcknowledgment) : Entry()
        data object Deferred : Entry()
        data class Error(val code: String, val message: String) : Entry()
    }

    sealed class SleepEntry {
        data class Ok(val rows: List<Map<String, Any?>>) : SleepEntry()
        data object Deferred : SleepEntry()
        data class Error(val code: String, val message: String) : SleepEntry()
    }

    val results: List<Entry>
    val sleep: SleepEntry?

    init {
        val normalized = if (response is JSONObject || response is JSONArray) jsonToKotlin(response) else response
        val obj = normalized as? Map<*, *>
        val rawResults = obj?.get("results") as? List<*>
            ?: throw SupabaseFailure.Http(500, "Invalid ingest_band_bundle response")
        results = rawResults.map(::entry)
        val rawSleep = obj["sleep"]
        sleep = if (rawSleep != null) sleepEntry(rawSleep) else null
    }

    private companion object {
        fun error(obj: Map<*, *>): Map<*, *>? = obj["error"] as? Map<*, *>

        fun entry(value: Any?): Entry {
            val obj = value as? Map<*, *> ?: return Entry.Error("INVALID_BUNDLE_REPLY", "Invalid result entry")
            if (obj["deferred"] == true) return Entry.Deferred
            error(obj)?.let { return Entry.Error(it["code"] as? String ?: "UNKNOWN", it["message"] as? String ?: "") }
            val ack = obj["ok"]
            if (ack != null) {
                val decoded = runCatching { BandIngestionAcknowledgment.fromJson(kotlinToJson(ack) as JSONObject) }.getOrNull()
                if (decoded != null) return Entry.Ok(decoded)
            }
            return Entry.Error("INVALID_BUNDLE_REPLY", "Missing domain acknowledgment")
        }

        fun sleepEntry(value: Any?): SleepEntry {
            val obj = value as? Map<*, *> ?: return SleepEntry.Error("INVALID_BUNDLE_REPLY", "Invalid sleep entry")
            if (obj["deferred"] == true) return SleepEntry.Deferred
            error(obj)?.let { return SleepEntry.Error(it["code"] as? String ?: "UNKNOWN", it["message"] as? String ?: "") }
            val rows = obj["ok"] as? List<*>
            if (rows != null && rows.all { it is Map<*, *> }) {
                @Suppress("UNCHECKED_CAST")
                return SleepEntry.Ok(rows.map { (it as Map<*, *>).mapKeys { e -> e.key.toString() } } as List<Map<String, Any?>>)
            }
            return SleepEntry.Error("INVALID_BUNDLE_REPLY", "Missing sleep acknowledgment")
        }
    }
}

/** App and database releases are independent. A server without the additive delta RPC
 *  keeps receiving the original full observations until its migration becomes available.
 *  Main-thread confined (Swift @MainActor). */
class BandDeltaTransport(
    private val now: () -> Instant = { Instant.now() },
    private val rpc: suspend (String, Map<String, Any?>, String) -> BandIngestionAcknowledgment,
    private val bundleRPC: (suspend (Map<String, Any?>, String) -> BandBundleReply)? = null,
) {
    private var legacyUntil: Instant? = null
    private var bundleUntil: Instant? = null

    suspend fun bundle(domains: List<Map<String, Any?>>, sleep: Map<String, Any?>?, budgetMs: Int?,
                       owner: String): BandBundleReply? {
        val bundleRPC = bundleRPC ?: return null
        if (bundleUntil?.let { it > now() } == true) return null
        val args = mutableMapOf<String, Any?>("p_domains" to domains)
        if (sleep != null) args["p_sleep"] = sleep
        if (budgetMs != null) args["p_budget_ms"] = budgetMs
        return try {
            val reply = bundleRPC(args, owner)
            bundleUntil = null
            reply
        } catch (error: Throwable) {
            if (!missingRPC(error)) throw error
            bundleUntil = BandTime.adding(now(), 300.0)
            null
        }
    }

    suspend fun ingest(args: Map<String, Any?>, owner: String): BandIngestionAcknowledgment {
        if (legacyUntil?.let { it > now() } != true) {
            try {
                val result = rpc("ingest_band_delta", args, owner)
                legacyUntil = null
                return result
            } catch (error: Throwable) {
                if (!missingRPC(error)) throw error
                legacyUntil = BandTime.adding(now(), 300.0)
            }
        }
        // The publisher still owns full durable samples. Ask it to resend them before
        // calling the legacy RPC; never silently drop referenced measurements.
        val references = (args["p_receipts"] as? List<*>)?.mapNotNull { it as? Map<*, *> } ?: emptyList()
        if (references.isNotEmpty()) {
            return BandIngestionAcknowledgment(inserted = 0, completed = 0, unchanged = 0, rejected = 0,
                affectedDays = emptyList(), needsSamples = references.mapNotNull { it["ts"] as? String })
        }
        val full = args.toMutableMap()
        full.remove("p_receipts")
        return rpc("ingest_band_domain", full, owner)
    }

    private companion object {
        fun missingRPC(error: Throwable): Boolean {
            if (error !is SupabaseFailure.Http || error.code != 404) return false
            val json = runCatching { JSONObject(error.body) }.getOrNull() ?: return false
            return json.optString("code") == "PGRST202"
        }
    }
}
