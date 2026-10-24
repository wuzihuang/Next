package com.nextbody.hoop.services.storage

import org.json.JSONObject

/** Swift `Codable` stand-in: each queued item says how it becomes JSON and back. */
interface JsonCodec<T> {
    fun encode(item: T): JSONObject
    fun decode(json: JSONObject): T
}

/** Sorted-keys JSON bytes (Swift `.sortedKeys`), so identical items compare byte-equal. */
fun JSONObject.sortedBytes(): ByteArray = sortedString(this).toByteArray(Charsets.UTF_8)

private fun sortedString(value: Any?): String = when (value) {
    is JSONObject -> value.keys().asSequence().sorted()
        .joinToString(",", "{", "}") { JSONObject.quote(it) + ":" + sortedString(value.opt(it)) }
    is org.json.JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { sortedString(value.opt(it)) }
    null, JSONObject.NULL -> "null"
    is String -> JSONObject.quote(value)
    is Number -> JSONObject.numberToString(value)
    else -> value.toString()
}

/** Imports legacy queues only after every operation has been durably read back. */
class DurableQueue<Item>(private val kind: String, private val store: LocalDataStore, private val codec: JsonCodec<Item>) {
    fun items(): List<Item> = store.allOperations(kind).map {
        codec.decode(JSONObject(String(it.payload, Charsets.UTF_8)))
    }

    fun save(item: Item, id: String, account: String) {
        store.enqueue(LocalOperation(id, account, kind, codec.encode(item).sortedBytes()))
    }

    fun acknowledge(id: String, account: String) = store.acknowledge(account, id)

    fun importLegacy(items: List<Item>, identity: (Item) -> Pair<String, String>) {
        for (item in items) {
            val (id, account) = identity(item)
            save(item, id, account)
        }
        for (item in items) {
            val (id, account) = identity(item)
            if (store.operations(account, kind).none { it.id == id }) {
                throw LocalDataStore.Failure.Database("Pending record import was not verified")
            }
        }
    }
}
