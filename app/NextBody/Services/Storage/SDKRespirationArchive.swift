import Foundation
import CoreFoundation
import SQLite3

/// Isolated read-only access to fields that the vendor's public getters discard.
public enum SDKRespirationArchive {
    public struct Reading: Equatable, Sendable {
        public let time: String
        public let rate: Double
        public init(time: String, rate: Double) { self.time = time; self.rate = rate }
    }
    public enum Failure: Error, LocalizedError {
        case invalidSelector, unavailable, incompatibleSchema, readFailed, invalidJSON, ambiguousPartition
        public var errorDescription: String? {
            switch self {
            case .invalidSelector: return "Invalid SDK respiratory history selector"
            case .unavailable: return "SDK respiratory archive is unavailable"
            case .incompatibleSchema: return "SDK respiratory archive schema is unsupported"
            case .readFailed: return "SDK respiratory archive could not be read"
            case .invalidJSON: return "SDK respiratory archive contains invalid data"
            case .ambiguousPartition: return "SDK respiratory archive contains ambiguous device/day records"
            }
        }
    }

    /// Never opens another device's partition or creates/modifies the SDK database.
    public static func read(url: URL, deviceAddress: String, day: String) throws -> [Reading] {
        guard deviceAddress.range(of: #"^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$"#,
                                  options: .regularExpression) != nil, validDay(day) else { throw Failure.invalidSelector }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw Failure.unavailable
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1500)
        var statement: OpaquePointer?
        let sql = "SELECT json FROM oxygen_table WHERE accountUser = ? AND createdTime = ? LIMIT 2"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.incompatibleSchema
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, deviceAddress, -1, transient) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, day, -1, transient) == SQLITE_OK else { throw Failure.readFailed }
        let first = sqlite3_step(statement)
        if first == SQLITE_DONE { return [] }
        guard first == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw Failure.readFailed }
        let data = Data(String(cString: text).utf8)
        let next = sqlite3_step(statement)
        if next == SQLITE_ROW { throw Failure.ambiguousPartition }
        guard next == SQLITE_DONE else { throw Failure.readFailed }
        return try readings(data)
    }

    private static func validDay(_ day: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: day) else { return false }
        return formatter.string(from: date) == day
    }

    private static func readings(_ data: Data) throws -> [Reading] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let rows = object as? [[String: Any]] else { throw Failure.invalidJSON }
        return try rows.compactMap { row -> Reading? in
            let rate: Double?
            if let value = row["RespirationRate"] as? NSNumber {
                guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
                rate = value.doubleValue
            }
            else if let value = row["RespirationRate"] as? String { rate = Double(value) }
            else { rate = nil }
            // 0/255 are empty SDK slots. This is an encoding boundary, not a health range.
            guard let rate, rate.isFinite, rate > 0, rate < 255 else { return nil }
            guard let time = row["Time"] as? String,
                  time.range(of: #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil else {
                throw Failure.invalidJSON
            }
            return Reading(time: time, rate: rate)
        }.sorted { $0.time < $1.time }
    }
}
