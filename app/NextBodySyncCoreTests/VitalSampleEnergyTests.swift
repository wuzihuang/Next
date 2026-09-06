import XCTest
@testable import NextBodySyncCore

final class VitalSampleEnergyTests: XCTestCase {
    func testMETSurvivesAuxiliaryMergeAndCacheRoundTrip() throws {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let movement = VitalSample(ts: at, hr: nil, stress: nil, steps: 0, met: 6)
        let temperature = VitalSample(ts: at, hr: nil, stress: nil, temp: 33)
        let merged = VitalSample.merging([movement], with: [temperature])
        XCTAssertEqual(merged.first?.met, 6)
        let restored = try JSONDecoder().decode([VitalSample].self, from: JSONEncoder().encode(merged))
        XCTAssertEqual(restored, merged)
    }

    func testMETOnlyTickCountsAsAReadingAndLegacyCachesStillDecode() throws {
        XCTAssertTrue(VitalSample(ts: Date(), hr: nil, stress: nil, met: 6).hasReading)
        let legacy = Data("{\"ts\":0,\"steps\":500}".utf8)
        let sample = try JSONDecoder().decode(VitalSample.self, from: legacy)
        XCTAssertNil(sample.met)
        XCTAssertEqual(sample.steps, 500)
    }

    func testNewMETCorrectsAnExistingZeroWhileAnAuxiliaryReadCannotEraseIt() throws {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let old = VitalSample(ts: at, hr: 65, stress: nil, steps: 500, met: 0)
        let corrected = VitalSample(ts: at, hr: nil, stress: nil, met: 6)
        let auxiliary = VitalSample(ts: at, hr: nil, stress: nil, hrv: 50)
        let result = try XCTUnwrap(VitalSample.merging([old], with: [corrected, auxiliary]).first)
        XCTAssertEqual(result.met, 6)
        XCTAssertEqual(result.hr, 65)
        XCTAssertEqual(result.steps, 500)
        XCTAssertEqual(result.hrv, 50)
        XCTAssertEqual(try JSONDecoder().decode(VitalSample.self, from: JSONEncoder().encode(result)), result)
    }

    func testInvalidMETIsMissingAndCannotEraseAnArchivedValidValue() throws {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let old = VitalSample(ts: at, hr: nil, stress: nil, met: 6)
        for met in [Double.nan, Double.infinity, -1, 101] {
            let invalid = VitalSample(ts: at, hr: nil, stress: nil, met: met)
            XCTAssertNil(invalid.met)
            XCTAssertFalse(invalid.hasReading)
            XCTAssertEqual(VitalSample.merging([old], with: [invalid]).first?.met, 6)
            XCTAssertNoThrow(try JSONEncoder().encode(invalid))
        }
        let corrupted = Data("{\"ts\":0,\"met\":-1,\"steps\":500}".utf8)
        let restored = try JSONDecoder().decode(VitalSample.self, from: corrupted)
        XCTAssertNil(restored.met)
        XCTAssertEqual(restored.steps, 500)
    }

    func testExplicitHRVRevocationPersistsAndOlderCachedOrRemoteValuesCannotReviveIt() throws {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let before = at.addingTimeInterval(300)
        let after = at.addingTimeInterval(600)
        let legacy = VitalSample(ts: at, hr: 65, stress: nil, hrv: 200)
        let invalid = VitalSample(ts: at, hr: nil, stress: nil, hrvValid: false, hrvObservedAt: after)
        let merged = try XCTUnwrap(VitalSample.merging([legacy], with: [invalid]).first)
        let archived = try JSONDecoder().decode(VitalSample.self, from: JSONEncoder().encode(merged))
        XCTAssertNil(archived.hrv)
        XCTAssertEqual(archived.hrvValid, false)
        XCTAssertEqual(archived.hrvObservedAt, after)
        XCTAssertEqual(archived.hr, 65)
        let oldRemote = VitalSample(ts: at, hr: nil, stress: nil, hrv: 200,
                                    hrvValid: true, hrvObservedAt: before)
        for stale in [legacy, oldRemote] {
            XCTAssertNil(VitalSample.merging([archived], with: [stale]).first?.hrv)
            XCTAssertNil(VitalSample.merging([stale], with: [archived]).first?.hrv)
        }
        let newer = VitalSample(ts: at, hr: nil, stress: nil, hrv: 45,
                                hrvValid: true, hrvObservedAt: after.addingTimeInterval(300))
        XCTAssertEqual(VitalSample.merging([archived], with: [newer]).first?.hrv, 45)
        XCTAssertEqual(VitalSample.merging([newer], with: [archived]).first?.hrv, 45)
    }

    func testMissingHRVAndAuxiliaryUpdatesDoNotRevokeAValidReading() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let stored = VitalSample(ts: at, hr: nil, stress: nil, hrv: 45,
                                hrvValid: true, hrvObservedAt: at.addingTimeInterval(300))
        let missing = VitalSample(ts: at, hr: nil, stress: nil, temp: 33)
        XCTAssertEqual(VitalSample.merging([stored], with: [missing]).first?.hrv, 45)
        XCTAssertFalse(VitalSample(ts: at, hr: nil, stress: nil, hrvValid: false).hasReading)
    }

    func testConflictingHRVAtTheSameObservationClockKeepsTheStoredValue() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = at.addingTimeInterval(300)
        let stored = VitalSample(ts: at, hr: nil, stress: nil, hrv: 45,
                                 hrvValid: true, hrvObservedAt: clock)
        let conflict = VitalSample(ts: at, hr: nil, stress: 33, hrv: 200,
                                   hrvValid: true, hrvObservedAt: clock)
        let merged = VitalSample.merging([stored], with: [conflict]).first
        XCTAssertEqual(merged?.hrv, 45)
        XCTAssertEqual(merged?.stress, 33)
        XCTAssertEqual(VitalSample.merging([stored], with: [stored]).first, stored)
        let legacy = VitalSample(ts: at, hr: nil, stress: nil, hrv: 45)
        let freshLegacy = VitalSample(ts: at, hr: nil, stress: nil, hrv: 50)
        XCTAssertEqual(VitalSample.merging([legacy], with: [freshLegacy]).first?.hrv, 50)
    }

    func testSameClockCannotReviveARevocationOrRevokeAStoredValidValue() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = at.addingTimeInterval(300)
        let valid = VitalSample(ts: at, hr: nil, stress: nil, hrv: 45,
                                hrvValid: true, hrvObservedAt: clock)
        let invalid = VitalSample(ts: at, hr: nil, stress: nil, hrvValid: false, hrvObservedAt: clock)
        XCTAssertEqual(VitalSample.merging([invalid], with: [valid]).first, invalid)
        XCTAssertEqual(VitalSample.merging([valid], with: [invalid]).first, valid)
    }
}
