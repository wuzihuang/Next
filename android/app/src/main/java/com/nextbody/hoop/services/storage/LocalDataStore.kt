package com.nextbody.hoop.services.storage

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File

data class LocalOperation(
    val id: String,
    val account: String,
    val kind: String,
    val payload: ByteArray,
) {
    override fun equals(other: Any?): Boolean = other is LocalOperation && id == other.id &&
        account == other.account && kind == other.kind && payload.contentEquals(other.payload)
    override fun hashCode(): Int = id.hashCode() * 31 + account.hashCode()
}

/** One account-scoped durable store. Pending documents are protected from cache eviction. */
class LocalDataStore private constructor(file: File) {
    sealed class Failure(message: String) : Exception(message) {
        class Database(message: String) : Failure(message)
        class ConflictingOperation : Failure("Conflicting operation")
        class InvalidOwner : Failure("Invalid owner")
    }

    private val db: SQLiteDatabase
    private val lock = Any()

    init {
        file.parentFile?.mkdirs()
        db = try {
            SQLiteDatabase.openOrCreateDatabase(file, null)
        } catch (e: Exception) {
            throw Failure.Database("Cannot open local data")
        }
        db.enableWriteAheadLogging()
        runCatching { db.execSQL("PRAGMA synchronous=FULL") }
        db.execSQL("CREATE TABLE IF NOT EXISTS documents(account TEXT NOT NULL,key TEXT NOT NULL,payload BLOB NOT NULL,revision TEXT NOT NULL,expiry REAL,accessed REAL NOT NULL,PRIMARY KEY(account,key))")
        db.execSQL("CREATE TABLE IF NOT EXISTS outbox(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL,account TEXT NOT NULL,kind TEXT NOT NULL,payload BLOB NOT NULL,document_key TEXT,UNIQUE(account,id))")
        db.execSQL("CREATE INDEX IF NOT EXISTS outbox_document ON outbox(account,document_key)")
        db.execSQL("CREATE TABLE IF NOT EXISTS observation_documents(account TEXT NOT NULL,key TEXT NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(account,key))")
    }

    companion object {
        @Volatile private var instance: LocalDataStore? = null
        private var appContext: Context? = null

        fun init(context: Context) { appContext = context.applicationContext }

        fun shared(): LocalDataStore {
            instance?.let { return it }
            synchronized(this) {
                instance?.let { return it }
                val ctx = appContext ?: throw Failure.Database("Cannot open local data")
                val store = LocalDataStore(File(File(ctx.filesDir, "NEXTBODY"), "local-data.sqlite"))
                instance = store
                return store
            }
        }

        /** Test seam: a store at an explicit path. */
        fun open(file: File): LocalDataStore = LocalDataStore(file)

        private fun now(): Double = System.currentTimeMillis() / 1000.0
    }

    private inline fun <T> locked(body: () -> T): T = synchronized(lock) { body() }

    private fun requireAccount(account: String) { if (account.isEmpty()) throw Failure.InvalidOwner() }

    /** Received measurements remain available after cache eviction and upload acknowledgement. */
    fun writeObservationDocument(account: String, key: String, data: ByteArray) = locked {
        requireAccount(account)
        db.execSQL("INSERT INTO observation_documents(account,key,payload) VALUES(?,?,?) ON CONFLICT(account,key) DO UPDATE SET payload=excluded.payload",
            arrayOf<Any>(account, key, data))
    }

    fun readObservationDocument(account: String, key: String): ByteArray? = locked {
        requireAccount(account)
        db.rawQuery("SELECT payload FROM observation_documents WHERE account=? AND key=?", arrayOf(account, key)).use {
            if (it.moveToFirst()) it.getBlob(0) else null
        }
    }

    fun observationDocuments(account: String): List<ByteArray> = locked {
        requireAccount(account)
        db.rawQuery("SELECT payload FROM observation_documents WHERE account=? ORDER BY key", arrayOf(account)).use {
            val out = mutableListOf<ByteArray>()
            while (it.moveToNext()) out += it.getBlob(0)
            out
        }
    }

    fun writeDocument(account: String, key: String, data: ByteArray, revision: String = "1", expiresAt: Double? = null) = locked {
        requireAccount(account)
        db.execSQL("INSERT INTO documents VALUES(?,?,?,?,?,?) ON CONFLICT(account,key) DO UPDATE SET payload=excluded.payload,revision=excluded.revision,expiry=excluded.expiry,accessed=excluded.accessed",
            arrayOf(account, key, data, revision, expiresAt, now()))
    }

    fun readDocument(account: String, key: String, nowSeconds: Double = now()): ByteArray? = locked {
        val data = db.rawQuery("SELECT payload FROM documents WHERE account=? AND key=? AND (expiry IS NULL OR expiry>?)",
            arrayOf(account, key, nowSeconds.toString())).use { if (it.moveToFirst()) it.getBlob(0) else null }
        if (data != null) db.execSQL("UPDATE documents SET accessed=? WHERE account=? AND key=?", arrayOf<Any>(nowSeconds, account, key))
        data
    }

    fun removeDocuments(account: String) = locked {
        db.execSQL("DELETE FROM documents WHERE account=?", arrayOf<Any>(account))
    }

    fun purge(account: String) = transaction {
        db.execSQL("DELETE FROM outbox WHERE account=?", arrayOf<Any>(account))
        db.execSQL("DELETE FROM observation_documents WHERE account=?", arrayOf<Any>(account))
        removeDocuments(account)
    }

    fun pruneCache(maxBytes: Int, nowSeconds: Double = now()) = transaction {
        val predicate = "NOT EXISTS(SELECT 1 FROM outbox o WHERE o.account=documents.account AND o.document_key=documents.key)"
        db.execSQL("DELETE FROM documents WHERE expiry<=? AND $predicate", arrayOf<Any>(nowSeconds))
        val rows = db.rawQuery("SELECT account,key,length(payload) FROM documents WHERE $predicate ORDER BY accessed DESC", null).use {
            val out = mutableListOf<Triple<String, String, Long>>()
            while (it.moveToNext()) out += Triple(it.getString(0), it.getString(1), it.getLong(2))
            out
        }
        var used = 0L
        for ((account, key, size) in rows) {
            used += size
            if (used > maxOf(0, maxBytes)) db.execSQL("DELETE FROM documents WHERE account=? AND key=?", arrayOf<Any>(account, key))
        }
    }

    fun enqueue(operation: LocalOperation, documentKey: String? = null, document: ByteArray? = null) {
        requireAccount(operation.account)
        transaction { insertOperation(operation, documentKey, document) }
    }

    /** One durable commit per batch; a conflict rolls back the entire batch. */
    fun enqueue(operations: List<LocalOperation>) {
        if (operations.isEmpty()) return
        if (operations.any { it.account.isEmpty() }) throw Failure.InvalidOwner()
        transaction { operations.forEach { insertOperation(it) } }
    }

    private fun insertOperation(operation: LocalOperation, documentKey: String? = null, document: ByteArray? = null) {
        val existing = db.rawQuery("SELECT kind,payload FROM outbox WHERE account=? AND id=?",
            arrayOf(operation.account, operation.id)).use {
            if (it.moveToFirst()) it.getString(0) to it.getBlob(1) else null
        }
        if (existing != null) {
            if (existing.first != operation.kind || !existing.second.contentEquals(operation.payload)) throw Failure.ConflictingOperation()
            return
        }
        if (documentKey != null && document != null) writeDocument(operation.account, documentKey, document)
        val values = ContentValues().apply {
            put("id", operation.id); put("account", operation.account); put("kind", operation.kind)
            put("payload", operation.payload); put("document_key", documentKey)
        }
        db.insertOrThrow("outbox", null, values)
    }

    fun operations(account: String, kind: String): List<LocalOperation> = locked {
        db.rawQuery("SELECT id,payload FROM outbox WHERE account=? AND kind=? ORDER BY sequence", arrayOf(account, kind)).use {
            val out = mutableListOf<LocalOperation>()
            while (it.moveToNext()) out += LocalOperation(it.getString(0), account, kind, it.getBlob(1))
            out
        }
    }

    /** Compare-and-swap protects an accepted estimate from a stale concurrent response. */
    fun replaceOperation(expected: LocalOperation, payload: ByteArray, documentKey: String) = transaction {
        swap(expected, payload, documentKey)
    }

    /** Rebase a meal and all later references in one transaction, keeping FIFO sequence. */
    fun replaceOperations(changes: List<Triple<LocalOperation, ByteArray, String>>) = transaction {
        changes.forEach { (expected, payload, key) -> swap(expected, payload, key) }
    }

    private fun swap(expected: LocalOperation, payload: ByteArray, documentKey: String) {
        val current = db.rawQuery("SELECT payload FROM outbox WHERE account=? AND id=? AND kind=?",
            arrayOf(expected.account, expected.id, expected.kind)).use { if (it.moveToFirst()) it.getBlob(0) else null }
        if (current == null || !current.contentEquals(expected.payload)) throw Failure.ConflictingOperation()
        db.execSQL("UPDATE outbox SET payload=?,document_key=? WHERE account=? AND id=?",
            arrayOf<Any>(payload, documentKey, expected.account, expected.id))
        writeDocument(expected.account, documentKey, payload)
    }

    fun allOperations(kind: String): List<LocalOperation> = locked {
        db.rawQuery("SELECT id,account,payload FROM outbox WHERE kind=? ORDER BY sequence", arrayOf(kind)).use {
            val out = mutableListOf<LocalOperation>()
            while (it.moveToNext()) out += LocalOperation(it.getString(0), it.getString(1), kind, it.getBlob(2))
            out
        }
    }

    fun acknowledge(account: String, id: String) = locked {
        db.execSQL("DELETE FROM outbox WHERE account=? AND id=?", arrayOf<Any>(account, id))
    }

    /** Remove only confirmed observations, atomically and within their captured account. */
    fun acknowledge(account: String, ids: List<String>) {
        if (ids.isEmpty()) return
        transaction { ids.forEach { acknowledge(account, it) } }
    }

    /** Cache confirmations and retire their durable operations in the same commit. */
    fun acknowledge(account: String, ids: List<String>, documents: Map<String, ByteArray>) {
        requireAccount(account)
        transaction {
            val expiry = now() + 45 * 86400
            documents.forEach { (key, data) -> writeDocument(account, key, data, expiresAt = expiry) }
            ids.forEach { acknowledge(account, it) }
        }
    }

    private fun <T> transaction(body: () -> T): T = locked {
        db.beginTransaction()
        try {
            val result = body()
            db.setTransactionSuccessful()
            result
        } catch (e: android.database.SQLException) {
            throw Failure.Database(e.message ?: "database error")
        } finally {
            db.endTransaction()
        }
    }
}
