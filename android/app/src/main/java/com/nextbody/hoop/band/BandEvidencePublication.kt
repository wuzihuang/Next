package com.nextbody.hoop.band

import com.nextbody.hoop.services.Iso
import com.nextbody.hoop.services.storage.LocalDataStore
import com.nextbody.hoop.services.storage.LocalOperation
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException

/** The part of `LocalDataStore` publication uses. Production wraps the services store
 *  ([LocalDataStore.asBandLocalStore]); tests pass an in-memory fake. */
interface BandLocalStore {
    fun enqueue(operation: LocalOperation)
    fun enqueue(operations: List<LocalOperation>)
    fun operations(account: String, kind: String): List<LocalOperation>
    fun readDocument(account: String, key: String): ByteArray?
    fun acknowledge(account: String, id: String)
    fun acknowledge(account: String, ids: List<String>, documents: Map<String, ByteArray>)
}

fun LocalDataStore.asBandLocalStore(): BandLocalStore = object : BandLocalStore {
    override fun enqueue(operation: LocalOperation) = this@asBandLocalStore.enqueue(operation)
    override fun enqueue(operations: List<LocalOperation>) = this@asBandLocalStore.enqueue(operations)
    override fun operations(account: String, kind: String) = this@asBandLocalStore.operations(account, kind)
    override fun readDocument(account: String, key: String) = this@asBandLocalStore.readDocument(account, key)
    override fun acknowledge(account: String, id: String) { this@asBandLocalStore.acknowledge(account, id) }
    override fun acknowledge(account: String, ids: List<String>, documents: Map<String, ByteArray>) =
        this@asBandLocalStore.acknowledge(account, ids, documents)
}

/** `JSONSerialization` with `.sortedKeys`: a deterministic encoding for identities and sizes. */
internal object BandJson {
    fun encode(value: Any?, sorted: Boolean = true): String = StringBuilder().also { write(it, value, sorted) }.toString()
    fun data(value: Any?, sorted: Boolean = true): ByteArray = encode(value, sorted).toByteArray(Charsets.UTF_8)

    fun decode(bytes: ByteArray): Any? = runCatching {
        val text = String(bytes, Charsets.UTF_8).trim()
        jsonToKotlin(if (text.startsWith("[")) JSONArray(text) else JSONObject(text))
    }.getOrNull()

    private fun write(out: StringBuilder, value: Any?, sorted: Boolean) {
        when (value) {
            null, JSONObject.NULL -> out.append("null")
            is String -> out.append(JSONObject.quote(value))
            is Boolean -> out.append(value)
            is Int, is Long, is Short, is Byte -> out.append(value)
            is Number -> {
                val d = value.toDouble()
                if (d.isFinite() && d == Math.rint(d) && Math.abs(d) < 1e15) out.append(d.toLong()) else out.append(d)
            }
            is Instant -> out.append(JSONObject.quote(Iso.string(value)))
            is Map<*, *> -> {
                out.append('{')
                val keys = value.keys.map { it.toString() }.let { if (sorted) it.sorted() else it }
                keys.forEachIndexed { i, k ->
                    if (i > 0) out.append(',')
                    out.append(JSONObject.quote(k)).append(':')
                    write(out, value[k], sorted)
                }
                out.append('}')
            }
            is JSONObject -> write(out, jsonToKotlin(value), sorted)
            is JSONArray -> write(out, jsonToKotlin(value), sorted)
            is Iterable<*> -> {
                out.append('[')
                value.forEachIndexed { i, v -> if (i > 0) out.append(','); write(out, v, sorted) }
                out.append(']')
            }
            else -> out.append(JSONObject.quote(value.toString()))
        }
    }
}

@Suppress("UNCHECKED_CAST")
private fun Any?.asRows(): List<Map<String, Any?>> =
    (this as? List<*>)?.mapNotNull { it as? Map<String, Any?> } ?: emptyList()

/** Account-owned publication: callers provide measured facts and read coverage, while
 *  this module owns durable identity, replay, acknowledgment and repair bookkeeping.
 *  Main-thread confined (Swift @MainActor). */
class BandEvidencePublication(
    private val account: String,
    private val local: BandLocalStore,
    private val authorized: () -> Boolean,
    private val transport: Transport,
) {
    data class Domain(
        val name: String,
        val deviceKey: String,
        val day: String,
        val timezone: String,
        val start: Instant,
        val end: Instant,
        val observedAt: Instant,
        val mappingVersion: String,
        val status: BandDomainReadStatus,
        val samples: List<Map<String, Any?>>,
        val statusFollowsSleep: Boolean = false,
    ) {
        internal val arguments: Map<String, Any?>
            get() = mapOf(
                "p_device_key" to deviceKey, "p_domain" to name, "p_day" to day,
                "p_timezone" to timezone, "p_start" to Iso.string(start),
                "p_end" to Iso.string(end), "p_observed_at" to Iso.string(observedAt),
                "p_mapping_version" to mappingVersion,
                "p_status" to if (statusFollowsSleep) "pending_sleep" else status.raw,
                "p_samples" to samples,
            )

        internal fun followingSleep(succeeded: Boolean): Domain =
            copy(status = if (succeeded) BandDomainReadStatus.complete else BandDomainReadStatus.failed, statusFollowsSleep = true)
    }

    data class Publication(val changedCount: Int, val state: BandDomainSyncState) {
        val confirmed: Boolean
            get() = state.status == BandDomainReadStatus.complete || state.status == BandDomainReadStatus.notCollected ||
                state.status == BandDomainReadStatus.unsupported
    }

    class UploadMetrics internal constructor(calls: Int, rounds: Int, val domains: Int) {
        var calls: Int = calls; internal set
        var rounds: Int = rounds; internal set
    }

    /** The owned transport has a production adapter and a deterministic test adapter.
     *  Both must return the server's acknowledgment rather than infer success locally. */
    class Transport(
        val ingest: suspend (Map<String, Any?>, String) -> BandIngestionAcknowledgment,
        val sleep: suspend (Map<String, Any?>, String) -> List<Map<String, Any?>>,
        val bundle: (suspend (List<Map<String, Any?>>, Map<String, Any?>?, Int?, String) -> BandBundleReply?)? = null,
    )

    sealed class Failure(message: String) : Exception(message) {
        data object SleepNotConfirmed : Failure("sleepNotConfirmed") { private fun readResolve(): Any = SleepNotConfirmed }
        data object InvalidOwner : Failure("invalidOwner") { private fun readResolve(): Any = InvalidOwner }
        data object Deferred : Failure("deferred") { private fun readResolve(): Any = Deferred }
        data class Server(val code: String, val serverMessage: String) : Failure("$code: $serverMessage")
    }

    var uploadMetrics = UploadMetrics(0, 0, 0)
        private set

    private data class DomainOffer(val args: Map<String, Any?>, val references: List<Map<String, Any?>>)

    private data class PendingDomain(val index: Int, val args: Map<String, Any?>, val ids: List<String>, val fullSamples: Boolean = false)

    private data class ReplayPage(val args: Map<String, Any?>, val ids: List<String>)

    private data class ContentReceipt(val content: String, val token: String)

    private suspend fun cancelled() = !currentCoroutineContext().isActive

    /** Staging has no network work. Origin and RR must already be durable before the
     *  bundled sleep publication can suspend or fail the current sync. */
    suspend fun stage(domain: Domain) { retain(domain.arguments) }

    suspend fun publish(domain: Domain): Publication {
        val args = domain.arguments.toMutableMap()
        if (domain.statusFollowsSleep) args["p_status"] = domain.status.raw
        val ids = retain(args)
        val ack = submitDomain(args, ids)
        return publication(domain, ack)
    }

    /** Independent domains overlap only their network waits. All local transactions
     *  remain main-confined; the server serializes account mutations itself.
     *  Keep input order even when replies arrive out of order, and never let one
     *  rejected domain cancel another domain's durable publication. */
    suspend fun publish(domains: List<Domain>): List<Result<Publication>> {
        val results = MutableList<Result<Publication>>(domains.size) { Result.failure(CancellationException()) }
        var start = 0
        while (start < domains.size) {
            if (cancelled() || !authorized()) break
            val end = minOf(start + 3, domains.size)
            coroutineScope {
                (start until end).map { index ->
                    async {
                        results[index] = try { Result.success(publish(domains[index])) }
                        catch (e: CancellationException) { throw e }
                        catch (e: Throwable) { Result.failure(e) }
                    }
                }.forEach { it.await() }
            }
            start += 3
        }
        return results
    }

    suspend fun publishSleep(row: Map<String, Any?>) {
        requireAuthorization()
        if (row["user_id"] as? String != account) throw Failure.InvalidOwner
        val payload = BandJson.data(row)
        val id = identifier("sleep-", payload)
        local.enqueue(LocalOperation(id, account, "band-sleep", payload))
        submitSleep(row, id)
    }

    data class BundleResult(val domains: List<Result<Publication>>, val sleep: Result<Unit>?)

    suspend fun publish(domains: List<Domain>, sleep: Map<String, Any?>?): BundleResult {
        val row = sleep
        uploadMetrics = UploadMetrics(0, 0, domains.size)
        val results = MutableList<Result<Publication>>(domains.size) { Result.failure(CancellationException()) }
        if (cancelled() || !authorized()) {
            return BundleResult(results, row?.let { Result.failure(CancellationException()) })
        }

        val retained = MutableList<List<String>?>(domains.size) { null }
        for ((index, domain) in domains.withIndex()) {
            try { retained[index] = retain(domain.arguments) }
            catch (e: Throwable) { results[index] = Result.failure(e) }
        }

        var sleepID: String? = null
        var sleepResult: Result<Unit>? = null
        if (row != null) {
            try {
                requireAuthorization()
                if (row["user_id"] as? String != account) throw Failure.InvalidOwner
                val payload = BandJson.data(row)
                val id = identifier("sleep-", payload)
                local.enqueue(LocalOperation(id, account, "band-sleep", payload))
                sleepID = id
            } catch (e: Throwable) { sleepResult = Result.failure(e) }
        }

        val bundle = transport.bundle
            ?: return publishLegacy(domains, retained, results, row, sleepID, sleepResult)

        var pending = domains.indices.mapNotNull { index ->
            retained[index]?.let { PendingDomain(index, domains[index].arguments, it) }
        }
        var sleepPending = sleepID != null
        var sleepSucceeded = false

        for (round in 1..3) {
            if (pending.isEmpty() && !sleepPending) break
            if (cancelled() || !authorized()) break
            uploadMetrics.rounds = round

            val offers = mutableListOf<Pair<PendingDomain, DomainOffer>>()
            val nextPending = mutableListOf<PendingDomain>()
            for (item in pending) {
                try {
                    val domain = domains[item.index]
                    val args = item.args.toMutableMap()
                    if (domain.statusFollowsSleep && row != null && !sleepPending) {
                        args["p_status"] = if (sleepSucceeded) "complete" else "failed"
                    }
                    offers.add(item to domainOffer(args, item.fullSamples))
                } catch (e: Throwable) {
                    results[item.index] = Result.failure(e)
                }
            }

            val chunks = bundleChunks(offers, if (sleepPending) row else null)
            var sleepDeferredThisRound = false
            var unsupported = false
            for ((chunkIndex, chunk) in chunks.withIndex()) {
                if (cancelled() || !authorized()) break
                val attachedSleep = if (chunkIndex == 0 && sleepPending) row else null
                val isBlocked = { pair: Pair<PendingDomain, DomainOffer> ->
                    sleepDeferredThisRound && chunkIndex > 0 && domains[pair.first.index].statusFollowsSleep
                }
                nextPending.addAll(chunk.filter(isBlocked).map { it.first })
                val eligible = chunk.filterNot(isBlocked).map { (item, offer) ->
                    val args = offer.args.toMutableMap()
                    if (domains[item.index].statusFollowsSleep) {
                        args["p_status"] = if (attachedSleep != null || row == null) "pending_sleep"
                            else if (sleepSucceeded) "complete" else "failed"
                    }
                    item to DomainOffer(args, offer.references)
                }
                if (eligible.isEmpty() && attachedSleep == null) continue
                val callOffers = eligible.map { it.second.args }
                val reply: BandBundleReply?
                try {
                    uploadMetrics.calls += 1
                    reply = bundle(callOffers, attachedSleep, null, account)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    if (attachedSleep != null) {
                        sleepResult = Result.failure(e)
                        sleepPending = false
                    }
                    for ((item, _) in eligible) results[item.index] = Result.failure(e)
                    continue
                }
                if (reply == null) {
                    unsupported = true
                    break
                }
                try { requireAuthorization() } catch (e: Throwable) {
                    for ((item, _) in eligible) results[item.index] = Result.failure(e)
                    break
                }

                if (attachedSleep != null) {
                    when (val s = reply.sleep) {
                        is BandBundleReply.SleepEntry.Ok -> try {
                            confirmSleep(s.rows, row!!, sleepID!!)
                            sleepResult = Result.success(Unit)
                            sleepSucceeded = true
                            sleepPending = false
                        } catch (e: Throwable) {
                            sleepResult = Result.failure(e)
                            sleepSucceeded = false
                            sleepPending = false
                        }
                        is BandBundleReply.SleepEntry.Deferred -> sleepDeferredThisRound = true
                        is BandBundleReply.SleepEntry.Error -> {
                            sleepResult = Result.failure(Failure.Server(s.code, s.message))
                            sleepSucceeded = false
                            sleepPending = false
                        }
                        null -> {
                            sleepResult = Result.failure(Failure.Server("INVALID_BUNDLE_REPLY", "Missing sleep result"))
                            sleepSucceeded = false
                            sleepPending = false
                        }
                    }
                }

                for ((resultIndex, pair) in eligible.withIndex()) {
                    val (item, offer) = pair
                    if (resultIndex >= reply.results.size) {
                        results[item.index] = Result.failure(Failure.Server("INVALID_BUNDLE_REPLY", "Missing domain result"))
                        continue
                    }
                    when (val entry = reply.results[resultIndex]) {
                        is BandBundleReply.Entry.Ok -> {
                            val ack = entry.acknowledgment
                            if (offer.references.isNotEmpty() && !(ack.needsSamples ?: emptyList()).isEmpty()) {
                                nextPending.add(PendingDomain(item.index, item.args, item.ids, fullSamples = true))
                                continue
                            }
                            try {
                                acknowledgeDomain(item.args, item.ids, ack, offer.references)
                                val domain = domains[item.index]
                                results[item.index] = Result.success(publication(domain, ack,
                                    if (domain.statusFollowsSleep) sleepSucceeded else null))
                            } catch (e: Throwable) { results[item.index] = Result.failure(e) }
                        }
                        is BandBundleReply.Entry.Deferred -> nextPending.add(item)
                        is BandBundleReply.Entry.Error -> results[item.index] = Result.failure(Failure.Server(entry.code, entry.message))
                    }
                }
            }

            if (unsupported) {
                return publishLegacy(domains, retained, results, row, sleepID, sleepResult)
            }
            pending = nextPending
            if (cancelled() || !authorized()) break
        }

        if (cancelled() || !authorized()) {
            for (item in pending) results[item.index] = Result.failure(CancellationException())
            if (row != null && sleepPending) sleepResult = Result.failure(CancellationException())
            return BundleResult(results, if (row == null) null else sleepResult)
        }
        if (sleepPending) sleepResult = Result.failure(Failure.Deferred)
        for (item in pending) results[item.index] = Result.failure(Failure.Deferred)
        return BundleResult(results, if (row == null) null else sleepResult)
    }

    private suspend fun publishLegacy(domains: List<Domain>, retained: List<List<String>?>,
                                      initial: List<Result<Publication>>, row: Map<String, Any?>?,
                                      sleepID: String?, initialSleepResult: Result<Unit>?): BundleResult {
        val results = initial.toMutableList()
        var sleepResult = initialSleepResult
        var sleepSucceeded = false
        if (row != null && sleepID != null) {
            try {
                requireAuthorization()
                uploadMetrics.calls += 1
                submitSleep(row, sleepID)
                sleepResult = Result.success(Unit)
                sleepSucceeded = true
            } catch (e: Throwable) {
                sleepResult = Result.failure(e)
            }
        }

        val active = domains.indices.filter { retained[it] != null }
        val legacyDomains = active.map { index ->
            if (domains[index].statusFollowsSleep) domains[index].followingSleep(sleepSucceeded) else domains[index]
        }
        if (legacyDomains.isNotEmpty()) {
            uploadMetrics.calls += legacyDomains.size
            uploadMetrics.rounds = maxOf(uploadMetrics.rounds, (legacyDomains.size + 2) / 3)
            val legacyResults = publish(legacyDomains)
            for ((index, result) in active.zip(legacyResults)) results[index] = result
        }
        return BundleResult(results, if (row == null) null else sleepResult)
    }

    private fun publication(domain: Domain, acknowledgment: BandIngestionAcknowledgment,
                            sleepSucceeded: Boolean? = null): Publication {
        var status = domain.status
        if (domain.statusFollowsSleep && sleepSucceeded != null) {
            status = if (sleepSucceeded) BandDomainReadStatus.complete else BandDomainReadStatus.failed
            if (sleepSucceeded && !acknowledgment.confirms(domain.samples.size)) status = BandDomainReadStatus.partial
        } else if (domain.statusFollowsSleep) {
            if (status == BandDomainReadStatus.complete && !acknowledgment.confirms(domain.samples.size)) {
                status = BandDomainReadStatus.partial
            }
        } else if (!acknowledgment.confirms(domain.samples.size)) {
            status = BandDomainReadStatus.partial
        } else if (domain.samples.isEmpty() && status == BandDomainReadStatus.complete && domain.name != "sleep") {
            status = BandDomainReadStatus.notCollected
        }
        val confirmed = status == BandDomainReadStatus.complete || status == BandDomainReadStatus.notCollected ||
            status == BandDomainReadStatus.unsupported
        return Publication(acknowledgment.inserted + acknowledgment.completed,
            BandDomainSyncState(domain.name, status, domain.observedAt,
                acknowledgedStart = if (confirmed) domain.start else null, acknowledgedEnd = if (confirmed) domain.end else null,
                repairStart = if (confirmed) null else domain.start, repairEnd = if (confirmed) null else domain.end))
    }

    private fun domainOffer(args: Map<String, Any?>, fullSamples: Boolean = false): DomainOffer {
        if (fullSamples) {
            val full = args.toMutableMap()
            full.remove("p_receipts")
            return DomainOffer(full, emptyList())
        }
        val samples = args["p_samples"].asRows()
        val key = receiptKey(args)
        val cached = receipts(key)
        val values = mutableListOf<Map<String, Any?>>()
        val references = mutableListOf<Map<String, Any?>>()
        for (sample in samples) {
            val ts = sample["ts"] as? String
            val receipt = ts?.let { cached[it] }
            if (ts != null && receipt != null && receipt.content == contentFingerprint(sample)) {
                val reference = mutableMapOf<String, Any?>("ts" to ts, "receipt" to receipt.token)
                sample["origin_read_at"]?.let { reference["origin_read_at"] = it }
                val referenceBytes = BandJson.data(reference, sorted = false).size
                val sampleBytes = BandJson.data(sample, sorted = false).size
                if (referenceBytes + 24 < sampleBytes) references.add(reference) else values.add(sample)
            } else {
                values.add(sample)
            }
        }
        val offer = args.toMutableMap()
        offer["p_samples"] = values
        if (references.isNotEmpty()) offer["p_receipts"] = references
        return DomainOffer(offer, references)
    }

    private fun acknowledgeDomain(args: Map<String, Any?>, ids: List<String>,
                                  ack: BandIngestionAcknowledgment, references: List<Map<String, Any?>>) {
        val samples = args["p_samples"].asRows()
        if (samples.isEmpty() || !ack.confirms(samples.size)) return
        val key = receiptKey(args)
        val confirmed = receipts(key).toMutableMap()
        val verifiedTokens = HashMap<String, String>()
        for (reference in references) {
            val ts = reference["ts"] as? String ?: continue
            val token = reference["receipt"] as? String ?: continue
            verifiedTokens[ts] = token
        }
        for (sample in samples) {
            val ts = sample["ts"] as? String ?: continue
            val token = ack.receipts?.get(ts) ?: (if (ack.receipts == null) null else verifiedTokens[ts])
            if (token != null && token.isNotEmpty() && token.toByteArray(Charsets.UTF_8).size <= 256) {
                confirmed[ts] = ContentReceipt(contentFingerprint(sample), token)
            } else {
                confirmed.remove(ts)
            }
        }
        val json = JSONObject()
        for ((ts, r) in confirmed) json.put(ts, JSONObject().put("content", r.content).put("token", r.token))
        local.acknowledge(account, ids, mapOf(key to json.toString().toByteArray(Charsets.UTF_8)))
    }

    private fun bundleChunks(offers: List<Pair<PendingDomain, DomainOffer>>,
                             sleep: Map<String, Any?>?): List<List<Pair<PendingDomain, DomainOffer>>> {
        if (offers.isEmpty() && sleep == null) return emptyList()
        val maximumBytes = 1_500_000
        val chunks = mutableListOf<List<Pair<PendingDomain, DomainOffer>>>()
        var chunk = mutableListOf<Pair<PendingDomain, DomainOffer>>()
        var bytes = sleep?.let { serializedSize(it) } ?: 2
        for (pair in offers) {
            val size = serializedSize(pair.second.args) + 1
            if (chunk.isNotEmpty() && (chunk.size == 8 || bytes + size > maximumBytes)) {
                chunks.add(chunk)
                chunk = mutableListOf()
                bytes = 2
            }
            chunk.add(pair)
            bytes += size
            if (bytes > maximumBytes) {
                chunks.add(chunk)
                chunk = mutableListOf()
                bytes = 2
            }
        }
        if (chunk.isNotEmpty()) chunks.add(chunk)
        if (chunks.isEmpty()) chunks.add(emptyList())
        return chunks
    }

    private fun serializedSize(value: Any?): Int = runCatching { BandJson.data(value).size }.getOrDefault(0)

    /** One finite snapshot per pass. New observations wait for the next pass; a group
     *  without a complete acknowledgment retains every operation; a batch with no
     *  progress stops that lane. */
    suspend fun replay(): Int {
        requireAuthorization()
        val sleeps = local.operations(account, "band-sleep")
        val observations = local.operations(account, "band-domain")
        var total = 0
        for (batch in sleeps.chunked(30)) {
            var acknowledged = 0
            for (operation in batch) {
                requireAuthorization()
                @Suppress("UNCHECKED_CAST")
                val row = BandJson.decode(operation.payload) as? Map<String, Any?> ?: continue
                submitSleep(row, operation.id)
                acknowledged += 1
            }
            total += acknowledged
            if (acknowledged == 0) break
        }
        for (batch in observations.chunked(200)) {
            requireAuthorization()
            val expected = replayableOperationCount(batch)
            val acknowledged = replayDomainBatch(batch)
            total += acknowledged
            if (acknowledged == 0 || acknowledged < expected) break
        }
        return total
    }

    private fun replayableOperationCount(operations: List<LocalOperation>): Int = operations.count { operation ->
        val args = BandJson.decode(operation.payload) as? Map<*, *> ?: return@count false
        args["p_samples"].asRows().isNotEmpty()
    }

    private suspend fun requireAuthorization() {
        if (cancelled() || !authorized()) throw CancellationException()
        if (account.isEmpty()) throw Failure.InvalidOwner
    }

    private fun identifier(prefix: String, payload: ByteArray): String =
        prefix + MessageDigest.getInstance("SHA-256").digest(payload).joinToString("") { "%02x".format(it) }

    private suspend fun retain(args: Map<String, Any?>): List<String> {
        requireAuthorization()
        val operations = args["p_samples"].asRows().map { sample ->
            val single = args.toMutableMap()
            single["p_samples"] = listOf(sample)
            single["p_status"] = "partial"
            // Preserve the existing payload identity and original observation clock.
            // A retry must never become a newer measurement revision.
            val raw = sample["ts"] as? String
            val ts = raw?.let { Iso.parse(it) }
            if (raw != null && ts != null) {
                single["p_start"] = raw
                single["p_end"] = Iso.string(ts.plusSeconds(60))
            }
            val payload = BandJson.data(single)
            LocalOperation(identifier("band-", payload), account, "band-domain", payload)
        }
        local.enqueue(operations)
        return operations.map { it.id }
    }

    private suspend fun submitDomain(args: Map<String, Any?>, ids: List<String>): BandIngestionAcknowledgment {
        requireAuthorization()
        val offer = domainOffer(args)
        var ack = transport.ingest(offer.args, account)
        requireAuthorization()
        // A token can expire or another phone can revise the same measurement. A miss
        // changes nothing on the server; replay the durable full observation once.
        var references = offer.references
        if (references.isNotEmpty() && !(ack.needsSamples ?: emptyList()).isEmpty()) {
            ack = transport.ingest(args, account)
            requireAuthorization()
            references = emptyList()
        }
        acknowledgeDomain(args, ids, ack, references)
        return ack
    }

    private fun receiptKey(args: Map<String, Any?>): String {
        val scope = listOf("p_device_key", "p_domain", "p_day", "p_timezone", "p_mapping_version").map { args[it] as? String ?: "" }
        return identifier("band.receipts.v1.", BandJson.data(scope))
    }

    private fun receipts(key: String): Map<String, ContentReceipt> {
        val data = local.readDocument(account, key) ?: return emptyMap()
        return runCatching {
            val o = JSONObject(String(data, Charsets.UTF_8))
            o.keys().asSequence().associateWith { k ->
                val r = o.getJSONObject(k)
                ContentReceipt(r.getString("content"), r.getString("token"))
            }
        }.getOrDefault(emptyMap())
    }

    private fun contentFingerprint(sample: Map<String, Any?>): String {
        val content = sample.toMutableMap()
        content.remove("origin_read_at")
        return identifier("", BandJson.data(content))
    }

    private suspend fun submitSleep(row: Map<String, Any?>, id: String) {
        requireAuthorization()
        if (row["user_id"] as? String != account) throw Failure.InvalidOwner
        val accepted = transport.sleep(row, account)
        requireAuthorization()
        confirmSleep(accepted, row, id)
    }

    private fun confirmSleep(accepted: List<Map<String, Any?>>, row: Map<String, Any?>, id: String) {
        // The server may merge HRV revisions into raw: confirmation is intentionally
        // about the recorded night, not byte equality with the submitted row.
        val saved = accepted.firstOrNull()
        fun int(v: Any?): Long? = (v as? Number)?.let { n -> n.toDouble().takeIf { it == Math.rint(it) }?.toLong() }
        if (saved == null || saved["user_id"] as? String != account ||
            saved["user_day"] as? String != row["user_day"] as? String ||
            int(saved["total_minutes"]) == null || int(saved["total_minutes"]) != int(row["total_minutes"])) {
            throw Failure.SleepNotConfirmed
        }
        local.acknowledge(account, id)
    }

    private suspend fun replayDomainBatch(pending: List<LocalOperation>): Int {
        val decoded = pending.mapNotNull { operation ->
            @Suppress("UNCHECKED_CAST")
            val args = BandJson.decode(operation.payload) as? Map<String, Any?> ?: return@mapNotNull null
            if (args["p_samples"].asRows().isEmpty()) null else operation to args
        }
        val groups = decoded.groupBy { item ->
            listOf("p_device_key", "p_domain", "p_day", "p_timezone", "p_mapping_version", "p_observed_at")
                .joinToString("|") { item.second[it] as? String ?: "" }
        }
        var acknowledged = 0
        for (key in groups.keys.sorted()) {
            val group = groups[key] ?: continue
            // p_observed_at has second precision. Distinct durable revisions captured
            // within that second must remain ordered, not collide in one delta batch.
            val pages = mutableListOf<List<Pair<LocalOperation, Map<String, Any?>>>>()
            var page = mutableListOf<Pair<LocalOperation, Map<String, Any?>>>()
            var seen = mutableSetOf<String>()
            for (entry in group) {
                val times = entry.second["p_samples"].asRows().mapNotNull { sample ->
                    val raw = sample["ts"] as? String ?: return@mapNotNull null
                    Iso.parse(raw)?.let { BandTime.seconds(it).toString() } ?: raw
                }.toSet()
                if (seen.any { it in times }) { pages.add(page); page = mutableListOf(); seen = mutableSetOf() }
                page.add(entry)
                seen.addAll(times)
            }
            if (page.isNotEmpty()) pages.add(page)
            val pagesToReplay = mutableListOf<ReplayPage>()
            for (p in pages) {
                val args = p.firstOrNull()?.second?.toMutableMap() ?: continue
                args["p_samples"] = p.flatMap { it.second["p_samples"].asRows() }
                args["p_start"] = p.mapNotNull { it.second["p_start"] as? String }.minOrNull()
                args["p_end"] = p.mapNotNull { it.second["p_end"] as? String }.maxOrNull()
                pagesToReplay.add(ReplayPage(args, p.map { it.first.id }))
            }
            val replayed = replayPages(pagesToReplay)
            acknowledged += replayed
            if (replayed < pagesToReplay.sumOf { it.ids.size }) return acknowledged
        }
        return acknowledged
    }

    private suspend fun replayPages(pages: List<ReplayPage>): Int {
        val bundle = transport.bundle ?: return replayIndividually(pages)
        var acknowledged = 0
        var index = 0
        while (index < pages.size) {
            requireAuthorization()
            val chunk = pages.subList(index, minOf(index + 8, pages.size))
            val offers = chunk.map { domainOffer(it.args) }
            val reply = bundle(offers.map { it.args }, null, null, account)
            requireAuthorization()
            if (reply == null) {
                acknowledged += replayIndividually(pages.subList(index, pages.size))
                return acknowledged
            }
            for ((offset, page) in chunk.withIndex()) {
                if (offset >= reply.results.size) return acknowledged
                var acknowledgment: BandIngestionAcknowledgment
                var references = offers[offset].references
                when (val entry = reply.results[offset]) {
                    is BandBundleReply.Entry.Ok -> {
                        acknowledgment = entry.acknowledgment
                        if (references.isNotEmpty() && !(acknowledgment.needsSamples ?: emptyList()).isEmpty()) {
                            val full = domainOffer(page.args, fullSamples = true)
                            val fullReply = bundle(listOf(full.args), null, null, account)
                            if (fullReply == null) {
                                val fullAck = submitDomain(page.args, page.ids)
                                if (!fullAck.confirms(page.args["p_samples"].asRows().size)) return acknowledged
                                acknowledged += page.ids.size
                                continue
                            }
                            requireAuthorization()
                            when (val first = fullReply.results.firstOrNull() ?: return acknowledged) {
                                is BandBundleReply.Entry.Ok -> acknowledgment = first.acknowledgment
                                is BandBundleReply.Entry.Deferred -> return acknowledged
                                is BandBundleReply.Entry.Error -> throw Failure.Server(first.code, first.message)
                            }
                            references = emptyList()
                        }
                    }
                    is BandBundleReply.Entry.Deferred -> return acknowledged
                    is BandBundleReply.Entry.Error -> throw Failure.Server(entry.code, entry.message)
                }
                val offered = page.args["p_samples"].asRows().size
                if (!acknowledgment.confirms(offered)) return acknowledged
                acknowledgeDomain(page.args, page.ids, acknowledgment, references)
                acknowledged += page.ids.size
            }
            index += chunk.size
        }
        return acknowledged
    }

    private suspend fun replayIndividually(pages: List<ReplayPage>): Int {
        var acknowledged = 0
        for (page in pages) {
            requireAuthorization()
            val samples = page.args["p_samples"].asRows()
            val ack = submitDomain(page.args, page.ids)
            if (!ack.confirms(samples.size)) return acknowledged
            acknowledged += page.ids.size
        }
        return acknowledged
    }
}
