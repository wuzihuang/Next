package com.nextbody.hoop.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.MealEntry
import com.nextbody.hoop.data.MealQueuePort
import com.nextbody.hoop.data.Ports
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.FuelState
import com.nextbody.hoop.services.storage.LocalDataStore
import com.nextbody.hoop.services.storage.MealOutboxPolicy
import com.nextbody.hoop.services.storage.MealPublication
import com.nextbody.hoop.services.storage.lower
import com.nextbody.hoop.services.storage.parseUuid
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** Meals use the same durable, account-owned ordered outbox as measurements. */
object MealQueue : MealQueuePort {
    data class Rejected(val id: String, val name: String, val reason: String)

    var lastError: String? by mutableStateOf(null)
        private set
    var pendingCount: Int by mutableStateOf(0)
        private set
    var rejected: List<Rejected> by mutableStateOf(emptyList())
        private set
    private var flushing = false
    private var flushRequested = false
    private var retry: Job? = null
    private var retryDelay: Long = 2

    fun init() {
        onReconnect { flush() }
    }

    private fun publication(owner: String): MealPublication {
        val session = SupabaseClient.currentRequestSessionSnapshot()
        return MealPublication(account = owner, local = LocalDataStore.shared(),
            isCurrent = { session.owner == owner && SupabaseClient.currentRequestSessionSnapshot() == session },
            consent = { ConsentStore.granted },
            send = { endpoint, body, o ->
                try { SupabaseClient.callFunction(endpoint, body, expectedOwner = o) }
                catch (e: SupabaseFailure.Http) { throw MealPublication.Failure.Http(e.code, e.body) }
            },
            persistProjection = {
                applyPending(DataStore, owner)
                if (!HomeSnapshot.save(DataStore)) {
                    throw LocalDataStore.Failure.Database(L("Could not save synchronized meals locally"))
                }
            })
    }

    override fun createManual(text: String, kcal: Double, day: UserDay, store: DataStore): UUID {
        val owner = SupabaseClient.currentUserIdSnapshot()
        if (!kcal.isFinite() || kcal < 1 || kcal > 100000 || owner == null) throw MealPublication.Failure.InvalidMeal()
        ensureCanAdd(day, store)
        val at = day.pinningClock(Instant.now())
        val submitted = publication(owner).createManual(day = day.key,
            slot = MealEntry.Slot.guess(at, day).raw, name = text, kcal = kcal, at = at)
        didSubmit(owner, store)
        return submitted.id
    }

    /** A row whose numbers are already known and accepted — a 常吃 logged again. No model call. */
    fun createKnown(item: MealFavorites.Item, day: UserDay, store: DataStore): UUID {
        val owner = SupabaseClient.currentUserIdSnapshot() ?: throw MealPublication.Failure.InvalidMeal()
        ensureCanAdd(day, store)
        val at = day.pinningClock(Instant.now())
        val id = UUID.randomUUID()
        val fields = JSONObject()
            .put("draft_id", id.lower()).put("user_day", day.key)
            .put("slot", MealEntry.Slot.guess(at, day).raw)
            .put("name", item.name.trim())
            .put("kcal", item.kcal).put("protein_g", item.protein).put("carb_g", item.carb).put("fat_g", item.fat)
            .put("confidence", "HIGH").put("model_version", "favourite-v1")
            .put("logged_at", Iso.string(at))
        item.portion?.takeIf { it.isNotEmpty() }?.let { fields.put("portion", it.take(64)) }
        item.fiber?.let { fields.put("fiber_g", it) }
        item.sugar?.let { fields.put("sugar_g", it) }
        item.sodium?.let { fields.put("sodium_mg", it) }
        val submitted = publication(owner).create(id, fields, source = "TYPED")
        didSubmit(owner, store)
        return submitted.id
    }

    fun confirmDraft(output: JSONObject, mealID: UUID, day: UserDay, slot: MealEntry.Slot,
                     owner: String, store: DataStore): MealPublication.Submitted {
        ensureCanAdd(day, store)
        val result = publication(owner).confirmDraft(mealID, day.key, slot.raw, output, day.pinningClock(Instant.now()))
        didSubmit(owner, store)
        return result
    }

    private fun ensureCanAdd(day: UserDay, store: DataStore) {
        if (!ConsentStore.granted) throw MealPublication.Failure.CollectionPaused()
        if (day == store.today.day && store.today.fuelState is FuelState.Fasted) {
            throw LocalDataStore.Failure.Database(L("This day is marked as fasted."))
        }
    }

    private fun didSubmit(owner: String, store: DataStore) {
        applyPending(store, owner)
        refreshStatus(owner)
        Ports.notificationReach.evaluate(store)
        queueScope.launch { flush() }
    }

    override fun enqueueDelete(mealID: UUID, ownerUserId: String) {
        publication(ownerUserId).delete(mealID)
        didSubmit(ownerUserId, DataStore)
    }

    override fun enqueueAmend(mealID: UUID, replacement: Map<String, Any?>, source: MealEntry.Source,
                              revisions: Int, ownerUserId: String) {
        publication(ownerUserId).amend(mealID, Json.obj(replacement), source.raw, revisions)
        didSubmit(ownerUserId, DataStore)
    }

    fun overlayPending(store: DataStore, ownerUserId: String) {
        try { applyPending(store, ownerUserId) } catch (e: Exception) { lastError = e.message }
    }

    private fun applyPending(store: DataStore, ownerUserId: String) {
        if (SupabaseClient.currentUserIdSnapshot() != ownerUserId) throw SessionChangedException()
        refreshStatus(ownerUserId)
        val projection = publication(ownerUserId).projection()
        val zone = ZoneId.systemDefault()
        val entries = projection.meals.mapNotNull { row ->
            val date = runCatching { LocalDate.parse(row.day) }.getOrNull() ?: return@mapNotNull null
            val noon = date.atTime(12, 0).atZone(zone).toInstant()
            val slot = MealEntry.Slot.fromRaw(row.slot) ?: return@mapNotNull null
            val previous = store.meals.firstOrNull { it.id == row.id } ?: store.recentMeals.firstOrNull { it.id == row.id }
            MealEntry(id = row.id, day = UserDay.containing(noon), at = row.at,
                slot = slot, status = if (row.confirmed) MealEntry.Status.confirmed else MealEntry.Status.`open`,
                text = row.name, kcal = row.kcal, protein = row.protein, carb = row.carb, fat = row.fat,
                revisions = row.revisions ?: previous?.revisions ?: 0,
                source = row.source?.let { MealEntry.Source.fromRaw(it.uppercase()) } ?: previous?.source ?: MealEntry.Source.voice,
                groupID = parseUuid(row.groupID) ?: previous?.groupID,
                portion = row.portion ?: previous?.portion,
                photoPath = row.photoPath ?: previous?.photoPath,
                fiber = row.fiber ?: previous?.fiber,
                sugar = row.sugar ?: previous?.sugar,
                sodium = row.sodium ?: previous?.sodium)
        }
        if (entries.isEmpty() && projection.removedIDs.isEmpty()) return
        store.overlayPendingMeals(entries, projection.removedIDs)
    }

    fun refreshStatus(owner: String) {
        if (SupabaseClient.currentUserIdSnapshot() != owner) { rejected = emptyList(); pendingCount = 0; return }
        try {
            val operations = LocalDataStore.shared().operations(owner, "meal")
            pendingCount = operations.size
            rejected = operations.mapNotNull { operation ->
                val message = MealOutboxPolicy.rejection(operation) ?: return@mapNotNull null
                val body = MealOutboxPolicy.fields(operation).optJSONObject("body") ?: JSONObject()
                Rejected(operation.id, body.optStringOrNull("name") ?: L("Meal change"), message)
            }
        } catch (e: Exception) { lastError = e.message }
    }

    fun retryRejected(id: String) {
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return
        try {
            val store = LocalDataStore.shared()
            val operation = store.operations(owner, "meal").firstOrNull { it.id == id } ?: return
            val payload = MealOutboxPolicy.replacingRejection(operation, null)
            store.replaceOperation(operation, payload, "meal.$id")
            refreshStatus(owner)
            queueScope.launch { flush() }
        } catch (e: Exception) { lastError = e.message }
    }

    /** Explicitly removes only a rejected local change and its dependent changes. */
    fun discardRejected(id: String, data: DataStore) {
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return
        try {
            val store = LocalDataStore.shared()
            val chain = MealOutboxPolicy.rejectedChain(id, store.operations(owner, "meal"))
            val removed = mutableSetOf<UUID>()
            for (operation in chain) removed += MealOutboxPolicy.affectedMeals(operation).mapNotNull { parseUuid(it) }
            data.overlayPendingMeals(emptyList(), removed)
            // A previous successful operation may have cached these pending changes too.
            if (!HomeSnapshot.save(data)) throw LocalDataStore.Failure.Database("Could not save discarded meals locally")
            for (operation in chain) store.acknowledge(owner, operation.id)
            refreshStatus(owner)
            queueScope.launch { Repository.loadToday(data) }
        } catch (e: Exception) { lastError = e.message }
    }

    suspend fun flush(): Unit = withContext(Dispatchers.Main.immediate) {
        if (flushing) { flushRequested = true; return@withContext }
        if (!Reachability.isOnline || DebugEdgeFlag.on("offline")) return@withContext
        val owner = SupabaseClient.currentUserId ?: return@withContext
        flushing = true
        try {
            lastError = null
            val result = publication(owner).replay()
            lastError = result.message?.let { L(it) }
            retryDelay = 2
        } catch (e: CancellationException) {
            if (e !is SessionChangedException) throw e
        } catch (e: Exception) {
            lastError = e.message
            if (e is MealPublication.Failure.CollectionPaused) return@withContext
            if (e is MealPublication.Failure.Http && (e.status == 401 || e.status == 403)) return@withContext
            val wait = retryDelay
            retryDelay = minOf(60, retryDelay * 2)
            retry?.cancel()
            retry = queueScope.launch {
                delay(wait * 1000)
                flush()
            }
        } finally {
            flushing = false
            refreshStatus(owner)
            if (flushRequested) {
                flushRequested = false
                queueScope.launch { flush() }
            }
        }
    }

    override fun purge(ownerUserId: String) {
        retry?.cancel()
        LocalDataStore.shared().purge(ownerUserId)
        pendingCount = 0; rejected = emptyList()
    }
}

/**
 * 常吃 — a plate worth keeping. ⚠️ A favourite is a copy, not a reference: the server table has
 * no foreign key to `meals`.
 */
object MealFavorites {
    data class Item(
        var name: String,
        var portion: String? = null,
        var kcal: Double,
        var protein: Double,
        var carb: Double,
        var fat: Double,
        var fiber: Double? = null,
        var sugar: Double? = null,
        var sodium: Double? = null,
    ) {
        fun toJson(): JSONObject = JSONObject().put("name", name).put("kcal", kcal).put("protein", protein)
            .put("carb", carb).put("fat", fat).also { o ->
                portion?.let { o.put("portion", it) }
                fiber?.let { o.put("fiber", it) }
                sugar?.let { o.put("sugar", it) }
                sodium?.let { o.put("sodium", it) }
            }

        companion object {
            /** Swift JSONDecoder: required keys must be present, optionals may be absent. */
            fun fromJson(o: JSONObject): Item? {
                val name = o.optStringOrNull("name") ?: return null
                return Item(name = name, portion = o.optStringOrNull("portion"),
                    kcal = o.number("kcal") ?: return null, protein = o.number("protein") ?: return null,
                    carb = o.number("carb") ?: return null, fat = o.number("fat") ?: return null,
                    fiber = o.number("fiber"), sugar = o.number("sugar"), sodium = o.number("sodium"))
            }
        }
    }

    data class Favorite(val id: UUID, var label: String, var items: List<Item>, var photoPath: String?, var uses: Int) {
        val kcal: Double get() = items.sumOf { it.kcal }
    }

    var list: List<Favorite> by mutableStateOf(emptyList())
        private set
    var lastError: String? by mutableStateOf(null)
    private var loadedFor: String? = null

    suspend fun load(force: Boolean = false) = withContext(Dispatchers.Main.immediate) {
        val owner = SupabaseClient.currentUserIdSnapshot()
        if (owner == null) { list = emptyList(); loadedFor = null; return@withContext }
        if (!force && loadedFor == owner) return@withContext
        try {
            val rows = SupabaseClient.select("meal_favorites", listOf(
                "select" to "id,label,items,photo_path,uses,last_used_at",
                "order" to "last_used_at.desc.nullslast",
                "limit" to "12"))
            if (SupabaseClient.currentUserIdSnapshot() != owner) return@withContext
            list = rows.mapNotNull(::decode)
            loadedFor = owner
        } catch (e: Exception) {
            if (e is CancellationException && e !is SessionChangedException) throw e
            lastError = e.message
        }
    }

    /** Keep the rows of one plate. A row in a group takes the whole group with it. */
    suspend fun save(entry: MealEntry, meals: List<MealEntry>) = withContext(Dispatchers.Main.immediate) {
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return@withContext
        val rows = entry.groupID?.let { group -> meals.filter { it.groupID == group }.sortedBy { it.at } } ?: listOf(entry)
        val items = (rows.ifEmpty { listOf(entry) }).take(12).map {
            Item(name = it.text, portion = it.portion, kcal = it.kcal, protein = it.protein,
                carb = it.carb, fat = it.fat, fiber = it.fiber, sugar = it.sugar, sodium = it.sodium)
        }
        if (items.isEmpty()) return@withContext
        val label = if (items.size == 1) items[0].name else items.take(3).joinToString(" · ") { it.name }
        try {
            SupabaseClient.insert("meal_favorites", mapOf(
                "user_id" to owner,
                "label" to label.take(120),
                "items" to org.json.JSONArray().also { a -> items.forEach { a.put(it.toJson()) } },
                "photo_path" to entry.photoPath))
            load(force = true)
        } catch (e: Exception) {
            if (e is CancellationException && e !is SessionChangedException) throw e
            lastError = e.message
        }
    }

    /** Write it again. No model call, no estimate, no confirmation. */
    fun log(favorite: Favorite, day: UserDay, data: DataStore) {
        val written = mutableListOf<UUID>()
        for (item in favorite.items) {
            if (item.kcal < 1) continue
            if (Band.allowsSeed) {
                data.addManualMeal(item.name, item.kcal, day)
                continue
            }
            try { written += MealQueue.createKnown(item, day, data) } catch (e: Exception) { lastError = e.message }
        }
        if (written.isNotEmpty()) data.postMealReceipt(favorite.label, written)
        queueScope.launch { touch(favorite) }
    }

    suspend fun remove(favorite: Favorite) {
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return
        list = list.filter { it.id != favorite.id }
        runCatching { SupabaseClient.deleteWhere("meal_favorites", "id", favorite.id.lower(), expectedOwner = owner) }
    }

    private suspend fun touch(favorite: Favorite) {
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return
        runCatching {
            SupabaseClient.patch("meal_favorites", favorite.id.lower(),
                mapOf("uses" to favorite.uses + 1, "last_used_at" to Iso.string(Instant.now())), expectedOwner = owner)
        }
    }

    private fun decode(row: JSONObject): Favorite? {
        val id = parseUuid(row.optStringOrNull("id")) ?: return null
        val label = row.optStringOrNull("label") ?: return null
        val raw = row.arrayOrNull("items") ?: return null
        val items = mutableListOf<Item>()
        for (i in 0 until raw.length()) items += Item.fromJson(raw.optJSONObject(i) ?: return null) ?: return null
        if (items.isEmpty()) return null
        return Favorite(id, label, items, row.optStringOrNull("photo_path"), (row.opt("uses") as? Number)?.toInt() ?: 0)
    }
}
