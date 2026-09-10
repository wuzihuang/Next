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

    private let domains = ["origin", "hrv", "temperature", "rr", "sleep", "oxygen", "response"]
    private let auditNow = Date(timeIntervalSince1970: 1_789_000_000)

    private func confirmedHistory(at: Date? = nil, end: Date? = nil) -> [BandDomainSyncState] {
        let today = Calendar.current.startOfDay(for: auditNow)
        let dayStart = Calendar.current.date(byAdding: .day, value: -3, to: today)!
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        return domains.map { domain in
            .init(domain: domain, status: .complete, attemptedAt: at ?? auditNow,
                  acknowledgedStart: dayStart, acknowledgedEnd: end ?? dayEnd,
                  repairStart: nil, repairEnd: nil)
        }
    }

    private func needsAudit(_ states: [BandDomainSyncState], outcome: BandRefreshResult.Status? = .success) -> Bool {
        let today = Calendar.current.startOfDay(for: auditNow)
        let dayStart = Calendar.current.date(byAdding: .day, value: -3, to: today)!
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        return BandSyncPolicy.needsHistorySync(states: states, outcome: outcome, start: dayStart, end: dayEnd, now: auditNow)
    }

    func testHistoryAuditSkipsOnlyConfirmedFullDaysCheckedToday() {
        XCTAssertFalse(needsAudit(confirmedHistory()))
        XCTAssertTrue(needsAudit([]), "first connection must recover available history")
        XCTAssertTrue(needsAudit(Array(confirmedHistory().dropLast())), "a missing domain is not a full-day success")
        XCTAssertTrue(needsAudit(confirmedHistory(at: auditNow.addingTimeInterval(-86_400))))
        XCTAssertTrue(needsAudit(confirmedHistory(at: auditNow.addingTimeInterval(60))), "future receipts are not current evidence")
        XCTAssertTrue(needsAudit(confirmedHistory(end: auditNow.addingTimeInterval(-4 * 86_400))),
                      "an earlier open-day read does not acknowledge a closed day")
    }

    func testFailedDomainRetainsRepairEvenWhenOtherDomainsAreCurrent() {
        var states = confirmedHistory()
        let prior = states.removeLast()
        states.append(.init(domain: prior.domain, status: .failed, attemptedAt: auditNow,
                            acknowledgedStart: prior.acknowledgedStart, acknowledgedEnd: prior.acknowledgedEnd,
                            repairStart: prior.acknowledgedStart, repairEnd: prior.acknowledgedEnd))
        XCTAssertTrue(needsAudit(states))
    }

    func testSleepOxygenCoverageKeepsItsRecordedNightWindow() {
        var states = confirmedHistory()
        let oxygen = states.remove(at: 5)
        states.append(.init(domain: oxygen.domain, status: .notCollected, attemptedAt: auditNow,
                            acknowledgedStart: oxygen.acknowledgedStart?.addingTimeInterval(-3600),
                            acknowledgedEnd: oxygen.acknowledgedStart?.addingTimeInterval(7 * 3600),
                            repairStart: nil, repairEnd: nil))
        XCTAssertFalse(needsAudit(states), "overnight oxygen acknowledges its night, not an artificial full-day range")
    }


    func testHistorySelectionReusesSuccessfulYesterdayAndRetriesOnlyUnfinishedDates() {
        var checked: [Int] = []
        let offsets = BandSyncPolicy.historyOffsetsToSync(available: [1, 2, 3, 4, 5, 6],
            recentDays: [0: .success, 1: .success]) { offset in
                checked.append(offset)
                return [3, 6].contains(offset)
            }
        XCTAssertEqual(offsets, [3, 6])
        XCTAssertEqual(checked, [2, 3, 4, 5, 6], "yesterday already completed in this refresh")
        let retry = BandSyncPolicy.historyOffsetsToSync(available: [1, 2, 3],
            recentDays: [0: .success, 1: .partial]) { _ in false }
        XCTAssertEqual(retry, [1], "an earlier receipt cannot suppress this refresh's failed yesterday")
    }

    func testHistoryOffsetSelectionKeepsCapturedDatesAcrossMidnight() {
        let offsets = BandSyncPolicy.historyOffsetsToSync(available: [1, 2, 3, 4, 5, 6],
            elapsedDays: 1, recentDays: [0: .success, 1: .success]) { _ in true }
        XCTAssertEqual(offsets, [2, 3, 4, 5], "SDK retention moved by one day while the refresh kept its dates")
    }


    func testWholeDayFailureCannotInheritSuccessfulDomainReceipts() {
        XCTAssertTrue(needsAudit(confirmedHistory(), outcome: .partial),
                      "respiration/archive or local persistence may fail outside the published domain receipts")
        XCTAssertTrue(needsAudit(confirmedHistory(), outcome: .failed))
        XCTAssertTrue(needsAudit(confirmedHistory(), outcome: nil), "missing overall outcome must be repaired")
    }

}
