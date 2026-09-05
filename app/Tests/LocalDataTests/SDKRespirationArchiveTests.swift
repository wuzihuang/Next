import XCTest
import SQLite3
import NextBodyLocalData

final class SDKRespirationArchiveTests: XCTestCase {
    private let address = "AA:BB:CC:DD:EE:FF"
    private func fixture(_ sql: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private let schema = "CREATE TABLE oxygen_table(json TEXT,createdTime TEXT,accountUser TEXT);"

    func testReadsOnlyRequestedDeviceAndDayWithoutChangingSDKDatabase() throws {
        let url = try fixture(schema + """
        INSERT INTO oxygen_table VALUES('[{"Time":"03:59","RespirationRate":"17"},{"Time":"04:00","RespirationRate":"255"},{"Time":"04:01","RespirationRate":"0"}]','2026-09-05','AA:BB:CC:DD:EE:FF');
        INSERT INTO oxygen_table VALUES('[{"Time":"03:59","RespirationRate":"88"}]','2026-09-05','11:22:33:44:55:66');
        INSERT INTO oxygen_table VALUES('[{"Time":"03:59","RespirationRate":"99"}]','2026-09-04','AA:BB:CC:DD:EE:FF');
        """)
        let before = try Data(contentsOf: url)
        let rows = try SDKRespirationArchive.read(url: url, deviceAddress: address, day: "2026-09-05")
        XCTAssertEqual(rows, [.init(time: "03:59", rate: 17)])
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
    func testBooleanRespiratoryValueIsNotAMeasurement() throws {
        let url = try fixture(schema + """
        INSERT INTO oxygen_table VALUES('[{"Time":"03:59","RespirationRate":true},{"Time":"04:00","RespirationRate":false}]','2026-09-05','AA:BB:CC:DD:EE:FF');
        """)
        XCTAssertEqual(try SDKRespirationArchive.read(url: url, deviceAddress: address, day: "2026-09-05"), [])
    }

    func testPositiveRespirationWithMalformedTimeThrowsInsteadOfSilentlyDroppingIt() throws {
        let url = try fixture(schema + """
        INSERT INTO oxygen_table VALUES('[{"Time":"25:00","RespirationRate":17}]','2026-09-05','AA:BB:CC:DD:EE:FF');
        """)
        XCTAssertThrowsError(try SDKRespirationArchive.read(url: url, deviceAddress: address, day: "2026-09-05"))
    }

    func testNoMatchingPartitionReturnsNoMeasurements() throws {
        let url = try fixture(schema)
        XCTAssertEqual(try SDKRespirationArchive.read(url: url, deviceAddress: address, day: "2026-09-05"), [])
    }
    func testMissingTableThrowsExplicitError() throws {
        let url = try fixture("CREATE TABLE unrelated(value TEXT);")
        XCTAssertThrowsError(try SDKRespirationArchive.read(url: url, deviceAddress: address, day: "2026-09-05"))
    }
    func testInvalidJSONAndAmbiguousPartitionThrow() throws {
        let invalid = try fixture(schema + "INSERT INTO oxygen_table VALUES('bad','2026-09-05','AA:BB:CC:DD:EE:FF');")
        XCTAssertThrowsError(try SDKRespirationArchive.read(url: invalid, deviceAddress: address, day: "2026-09-05"))
        let duplicate = try fixture(schema + "INSERT INTO oxygen_table VALUES('[]','2026-09-05','AA:BB:CC:DD:EE:FF'),('[]','2026-09-05','AA:BB:CC:DD:EE:FF');")
        XCTAssertThrowsError(try SDKRespirationArchive.read(url: duplicate, deviceAddress: address, day: "2026-09-05"))
    }
    func testMissingFileIsNotCreatedAndInvalidSelectorsAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try SDKRespirationArchive.read(url: url, deviceAddress: address, day: "2026-09-05"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let existing = try fixture(schema)
        XCTAssertThrowsError(try SDKRespirationArchive.read(url: existing, deviceAddress: "' OR 1=1 --", day: "2026-09-05"))
        XCTAssertThrowsError(try SDKRespirationArchive.read(url: existing, deviceAddress: address, day: "2026-02-30"))
    }
}
