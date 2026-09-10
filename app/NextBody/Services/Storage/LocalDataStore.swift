import Foundation
import SQLite3

public struct LocalOperation: Sendable {
    public let id: String
    public let account: String
    public let kind: String
    public let payload: Data
    public init(id: String, account: String, kind: String, payload: Data) {
        self.id = id; self.account = account; self.kind = kind; self.payload = payload
    }
}

/// One account-scoped durable store. Pending documents are protected from cache eviction.
public final class LocalDataStore: @unchecked Sendable {
    public enum Failure: Error { case database(String), conflictingOperation, invalidOwner }
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var instance: LocalDataStore?
    public static func shared() throws -> LocalDataStore {
        sharedLock.lock(); defer { sharedLock.unlock() }
        if let instance { return instance }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true).appendingPathComponent("HOOP")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try LocalDataStore(url: directory.appendingPathComponent("local-data.sqlite"))
        instance = store
        return store
    }
    public init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; db = nil
            throw Failure.database("Cannot open local data")
        }
        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute("CREATE TABLE IF NOT EXISTS documents(account TEXT NOT NULL,key TEXT NOT NULL,payload BLOB NOT NULL,revision TEXT NOT NULL,expiry REAL,accessed REAL NOT NULL,PRIMARY KEY(account,key))")
        try execute("CREATE TABLE IF NOT EXISTS outbox(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL,account TEXT NOT NULL,kind TEXT NOT NULL,payload BLOB NOT NULL,document_key TEXT,UNIQUE(account,id))")
        try execute("CREATE TABLE IF NOT EXISTS observation_documents(account TEXT NOT NULL,key TEXT NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(account,key))")
    }
    deinit { sqlite3_close(db) }

    /// Received measurements remain available after cache eviction and upload acknowledgement.
    public func writeObservationDocument(account: String, key: String, data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard !account.isEmpty else { throw Failure.invalidOwner }
        try execute("INSERT INTO observation_documents(account,key,payload) VALUES(?,?,?) ON CONFLICT(account,key) DO UPDATE SET payload=excluded.payload",
                    [account, key, data])
    }

    public func readObservationDocument(account: String, key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard !account.isEmpty else { throw Failure.invalidOwner }
        return try query("SELECT payload FROM observation_documents WHERE account=? AND key=?", [account, key]).first?.first as? Data
    }

    public func observationDocuments(account: String) throws -> [Data] {
        lock.lock(); defer { lock.unlock() }
        guard !account.isEmpty else { throw Failure.invalidOwner }
        return try query("SELECT payload FROM observation_documents WHERE account=? ORDER BY key", [account]).compactMap { $0.first as? Data }
    }

    public func writeDocument(account: String, key: String, data: Data, revision: String = "1", expiresAt: Date? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        guard !account.isEmpty else { throw Failure.invalidOwner }
        try execute("INSERT INTO documents VALUES(?,?,?,?,?,?) ON CONFLICT(account,key) DO UPDATE SET payload=excluded.payload,revision=excluded.revision,expiry=excluded.expiry,accessed=excluded.accessed",
                    [account, key, data, revision, expiresAt?.timeIntervalSince1970, Date().timeIntervalSince1970])
    }
    public func readDocument(account: String, key: String, now: Date = Date()) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        let rows = try query("SELECT payload FROM documents WHERE account=? AND key=? AND (expiry IS NULL OR expiry>?)", [account,key,now.timeIntervalSince1970])
        if !rows.isEmpty { try execute("UPDATE documents SET accessed=? WHERE account=? AND key=?", [now.timeIntervalSince1970,account,key]) }
        return rows.first?.first as? Data
    }
    public func removeDocuments(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        try execute("DELETE FROM documents WHERE account=?", [account])
    }
    public func purge(account: String) throws {
        try transaction {
            try execute("DELETE FROM outbox WHERE account=?", [account])
            try execute("DELETE FROM observation_documents WHERE account=?", [account])
            try removeDocuments(account: account)
        }
    }
    public func pruneCache(maxBytes: Int, now: Date = Date()) throws {
        try transaction {
            let predicate = "NOT EXISTS(SELECT 1 FROM outbox o WHERE o.account=documents.account AND o.document_key=documents.key)"
            try execute("DELETE FROM documents WHERE expiry<=? AND \(predicate)", [now.timeIntervalSince1970])
            let rows = try query("SELECT account,key,length(payload) FROM documents WHERE \(predicate) ORDER BY accessed DESC")
            var used = 0
            for row in rows {
                used += Int(row[2] as? Int64 ?? 0)
                if used > max(0,maxBytes) { try execute("DELETE FROM documents WHERE account=? AND key=?", [row[0], row[1]]) }
            }
        }
    }
    public func enqueue(operation: LocalOperation, documentKey: String? = nil, document: Data? = nil) throws {
        guard !operation.account.isEmpty else { throw Failure.invalidOwner }
        try transaction {
            try insertOperation(operation, documentKey: documentKey, document: document)
        }
    }
    /// Preserve the same per-observation identity and durability with one durable commit per batch.
    /// A conflict rolls back the entire batch, so callers never mistake a partial write for success.
    public func enqueue(operations: [LocalOperation]) throws {
        guard !operations.isEmpty else { return }
        guard operations.allSatisfy({ !$0.account.isEmpty }) else { throw Failure.invalidOwner }
        try transaction {
            for operation in operations { try insertOperation(operation) }
        }
    }
    private func insertOperation(_ operation: LocalOperation, documentKey: String? = nil, document: Data? = nil) throws {
        let existing = try query("SELECT kind,payload FROM outbox WHERE account=? AND id=?", [operation.account, operation.id])
        if let first = existing.first {
            guard first[0] as? String == operation.kind, first[1] as? Data == operation.payload else { throw Failure.conflictingOperation }
            return
        }
        if let documentKey, let document { try writeDocument(account: operation.account, key: documentKey, data: document) }
        try execute("INSERT INTO outbox(id,account,kind,payload,document_key) VALUES(?,?,?,?,?)", [operation.id,operation.account,operation.kind,operation.payload,documentKey])
    }

    public func operations(account: String, kind: String) throws -> [LocalOperation] {
        lock.lock(); defer { lock.unlock() }
        return try query("SELECT id,payload FROM outbox WHERE account=? AND kind=? ORDER BY sequence", [account,kind]).compactMap {
            guard let id = $0[0] as? String, let payload = $0[1] as? Data else { return nil }
            return LocalOperation(id: id, account: account, kind: kind, payload: payload)
        }
    }
    /// Compare-and-swap protects an accepted estimate from a stale concurrent response.
    public func replaceOperation(_ expected: LocalOperation, payload: Data, documentKey: String) throws {
        try transaction {
            let existing = try query("SELECT payload FROM outbox WHERE account=? AND id=? AND kind=?", [expected.account, expected.id, expected.kind])
            guard existing.first?.first as? Data == expected.payload else { throw Failure.conflictingOperation }
            try execute("UPDATE outbox SET payload=?,document_key=? WHERE account=? AND id=?", [payload,documentKey,expected.account,expected.id])
            try writeDocument(account: expected.account, key: documentKey, data: payload)
        }
    }
    /// Rebase a meal and all later references in one transaction, keeping FIFO sequence.
    public func replaceOperations(_ changes: [(expected: LocalOperation, payload: Data, documentKey: String)]) throws {
        try transaction {
            for change in changes {
                let expected = change.expected
                let rows = try query("SELECT payload FROM outbox WHERE account=? AND id=? AND kind=?", [expected.account, expected.id, expected.kind])
                guard rows.first?.first as? Data == expected.payload else { throw Failure.conflictingOperation }
                try execute("UPDATE outbox SET payload=?,document_key=? WHERE account=? AND id=?", [change.payload,change.documentKey,expected.account,expected.id])
                try writeDocument(account: expected.account, key: change.documentKey, data: change.payload)
            }
        }
    }
    public func allOperations(kind: String) throws -> [LocalOperation] {
        lock.lock(); defer { lock.unlock() }
        return try query("SELECT id,account,payload FROM outbox WHERE kind=? ORDER BY sequence", [kind]).compactMap {
            guard let id = $0[0] as? String, let account = $0[1] as? String, let payload = $0[2] as? Data else { return nil }
            return LocalOperation(id: id, account: account, kind: kind, payload: payload)
        }
    }
    public func acknowledge(account: String, id: String) throws {
        lock.lock(); defer { lock.unlock() }
        try execute("DELETE FROM outbox WHERE account=? AND id=?", [account,id])
    }
    /// Remove only confirmed observations, atomically and within their captured account.
    public func acknowledge(account: String, ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try transaction {
            for id in ids { try acknowledge(account: account, id: id) }
        }
    }
    /// Cache confirmations and retire their durable operations in the same commit.
    /// Evicting a confirmation is safe: the next publication sends its full values again.
    public func acknowledge(account: String, ids: [String], documents: [String: Data]) throws {
        guard !account.isEmpty else { throw Failure.invalidOwner }
        try transaction {
            for (key, data) in documents {
                try writeDocument(account: account, key: key, data: data,
                                  expiresAt: Date().addingTimeInterval(45 * 86400))
            }
            for id in ids { try acknowledge(account: account, id: id) }
        }
    }
    private func transaction(_ body: () throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func execute(_ sql: String, _ values: [Any?] = []) throws { _ = try query(sql, values) }
    private func query(_ sql: String, _ values: [Any?] = []) throws -> [[Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil) == SQLITE_OK else { throw Failure.database(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index,value) in values.enumerated() {
            let position = Int32(index+1)
            switch value {
            case let data as Data:
                if data.isEmpty { sqlite3_bind_zeroblob(statement,position,0) }
                else { _ = data.withUnsafeBytes { sqlite3_bind_blob(statement,position,$0.baseAddress,Int32(data.count),transient) } }
            case let string as String: sqlite3_bind_text(statement,position,string,-1,transient)
            case let double as Double: sqlite3_bind_double(statement,position,double)
            default: sqlite3_bind_null(statement,position)
            }
        }
        var rows: [[Any]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw Failure.database(String(cString: sqlite3_errmsg(db))) }
            rows.append((0..<sqlite3_column_count(statement)).map { column -> Any in
                switch sqlite3_column_type(statement,column) {
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement,column))
                    guard count > 0, let bytes = sqlite3_column_blob(statement,column) else { return Data() }
                    return Data(bytes: bytes,count: count)
                case SQLITE_INTEGER: return sqlite3_column_int64(statement,column)
                case SQLITE_TEXT: return String(cString: sqlite3_column_text(statement,column))
                default: return NSNull()
                }
            })
        }
    }
}
