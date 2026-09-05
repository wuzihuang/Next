import XCTest
@testable import NextBodySyncCore

final class BandSyncPolicyTests: XCTestCase {
    func testStatusPrioritizesConnectionAndTransferOverStandby() {
        XCTAssertEqual(BandSyncPolicy.header(activity: "connecting", connected: false, live: "off"), "CONNECTING")
        XCTAssertEqual(BandSyncPolicy.header(activity: "syncing", connected: true, live: "off"), "SYNCING…")
        XCTAssertEqual(BandSyncPolicy.header(activity: "idle", connected: true, live: "reaching"), "REACHING")
        XCTAssertEqual(BandSyncPolicy.header(activity: "idle", connected: false, live: "live"), "OFFLINE")
        XCTAssertEqual(BandSyncPolicy.header(activity: "idle", connected: true, live: "off"), "STANDBY")
    }

    func testReconnectSelectsOnlyTheBoundDeviceIgnoringUUIDCase() {
        XCTAssertTrue(BandSyncPolicy.matchesBoundDevice(discovered: "ABC-123", bound: "abc-123"))
        XCTAssertFalse(BandSyncPolicy.matchesBoundDevice(discovered: "other", bound: "abc-123"))
        XCTAssertFalse(BandSyncPolicy.matchesBoundDevice(discovered: "abc-123", bound: nil))
    }

    func testHistoryIncludesAllRetainedDaysWithSafeFallback() {
        XCTAssertEqual(BandSyncPolicy.historyDays(retained: 7), 6)
        XCTAssertEqual(BandSyncPolicy.historyDays(retained: 1), 0)
        XCTAssertEqual(BandSyncPolicy.historyDays(retained: 0), 6)
        XCTAssertEqual(BandSyncPolicy.historyDays(retained: nil), 6)
        XCTAssertEqual(BandSyncPolicy.historyDays(retained: 30), 29)
    }

    func testSDKCachedHistorySurvivesShorterHardwareRetentionWithoutProbingEmptyGaps() {
        XCTAssertEqual(BandSyncPolicy.historyDayOffsets(retained: 3, cachedOffsets: [3]), [1, 2, 3])
        XCTAssertEqual(BandSyncPolicy.historyDayOffsets(retained: 1, cachedOffsets: [6]), [6])
        XCTAssertEqual(BandSyncPolicy.historyDayOffsets(retained: 1, cachedOffsets: [-1, 0, 3, 3, 99]), [3])
        XCTAssertEqual(BandSyncPolicy.historyDayOffsets(retained: 3, cachedOffsets: []), [1, 2])
    }

    func testReconnectMatchesSDKAddressOrBoundPeripheralWithoutChangingBinding() {
        XCTAssertTrue(BandSyncPolicy.matchesBoundDevice(discovered: "uuid-1", sdkAddress: "AA:BB", bound: "aa:bb"))
        XCTAssertTrue(BandSyncPolicy.matchesBoundDevice(discovered: "UUID-1", sdkAddress: "changed", bound: "AA:BB", boundPeripheral: "uuid-1"))
        XCTAssertTrue(BandSyncPolicy.matchesBoundDevice(discovered: "UUID-1", sdkAddress: "changed", bound: "uuid-1"))
        XCTAssertFalse(BandSyncPolicy.matchesBoundDevice(discovered: "other", sdkAddress: "CC:DD", bound: "AA:BB", boundPeripheral: "uuid-1"))
        XCTAssertFalse(BandSyncPolicy.matchesBoundDevice(discovered: "uuid-1", bound: nil, boundPeripheral: "uuid-1"))
        XCTAssertFalse(BandSyncPolicy.matchesBoundDevice(discovered: "", sdkAddress: "", bound: "AA:BB", boundPeripheral: ""))
    }

    func testLegacyPeripheralMigrationRequiresExactRememberedDeviceAndValidUUID() {
        let uuid = "758F52C1-BF3E-45FE-9DF6-2F1D5509BF01"
        XCTAssertEqual(BandSyncPolicy.legacyPeripheralIdentifier(bound: "aa:bb", rememberedAddress: "AA:BB", rememberedPeripheral: uuid.lowercased()), uuid)
        XCTAssertNil(BandSyncPolicy.legacyPeripheralIdentifier(bound: "AA:BB", rememberedAddress: "CC:DD", rememberedPeripheral: uuid))
        XCTAssertNil(BandSyncPolicy.legacyPeripheralIdentifier(bound: nil, rememberedAddress: "AA:BB", rememberedPeripheral: uuid))
        XCTAssertNil(BandSyncPolicy.legacyPeripheralIdentifier(bound: "", rememberedAddress: "", rememberedPeripheral: uuid))
        XCTAssertNil(BandSyncPolicy.legacyPeripheralIdentifier(bound: "AA:BB", rememberedAddress: nil, rememberedPeripheral: uuid))
        XCTAssertNil(BandSyncPolicy.legacyPeripheralIdentifier(bound: "AA:BB", rememberedAddress: "AA:BB", rememberedPeripheral: "not-a-uuid"))
        XCTAssertNil(BandSyncPolicy.legacyPeripheralIdentifier(bound: "AA:BB", rememberedAddress: "AA:BB", rememberedPeripheral: nil))
    }
}
