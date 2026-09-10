import XCTest
@testable import NextBodySyncCore

final class BandHealthLightTests: XCTestCase {
    func testSDKStateValuesAndDisplayOrder() {
        XCTAssertEqual(BandHealthLightState.allCases.map(\.rawValue), [0, 1, 2, 3])
        XCTAssertEqual(BandHealthLightState.allCases.map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(BandHealthLightState.allCases.map(\.title), ["Off", "Slow flash", "Continuous flashing", "Stay on"])
    }

    func testSuccessfulAcknowledgmentUsesDeviceState() throws {
        for state in BandHealthLightState.allCases {
            XCTAssertEqual(try BandHealthLightState.confirmedState(success: true, rawValue: state.rawValue), state)
        }
    }

    func testRejectedAcknowledgmentDoesNotConfirmState() {
        XCTAssertThrowsError(try BandHealthLightState.confirmedState(success: false, rawValue: 0)) {
            XCTAssertEqual($0 as? BandHealthLightError, .rejected)
            XCTAssertEqual($0.localizedDescription, "The device rejected the health light setting.")
        }
    }

    func testUnknownDeviceStateIsRejected() {
        for rawValue in [-1, 4, Int.max] {
            XCTAssertNil(BandHealthLightState(rawValue: rawValue))
            XCTAssertThrowsError(try BandHealthLightState.confirmedState(success: true, rawValue: rawValue)) {
                XCTAssertEqual($0 as? BandHealthLightError, .unknownState)
                XCTAssertEqual($0.localizedDescription, "The device returned an unknown health light state.")
            }
        }
    }
}

final class BandHealthLightPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "nb.tests.healthLight"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testNothingChosenMeansNothingSent() {
        XCTAssertNil(BandHealthLightPreference.stored(in: defaults))
    }

    func testEveryStateRoundTrips() {
        for state in BandHealthLightState.allCases {
            BandHealthLightPreference.store(state, in: defaults)
            XCTAssertEqual(BandHealthLightPreference.stored(in: defaults), state)
        }
    }

    func testClearingReturnsToFirmwareDefault() {
        BandHealthLightPreference.store(.off, in: defaults)
        BandHealthLightPreference.store(nil, in: defaults)
        XCTAssertNil(BandHealthLightPreference.stored(in: defaults))
        XCTAssertNil(defaults.object(forKey: BandHealthLightPreference.key))
    }

    func testUnknownStoredValueIsNotAState() {
        defaults.set(7, forKey: BandHealthLightPreference.key)
        XCTAssertNil(BandHealthLightPreference.stored(in: defaults))
    }
}
