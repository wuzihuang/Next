import XCTest
@testable import NextBodySyncCore

/// ADR 0003 · one band, one account. How a registration reads the server's refusal and what
/// it may write about the band on the link.
final class DeviceRegistrationTests: XCTestCase {
    private let seed = "C4-2E-8F-1A-73-9D"

    private func postgrest(_ message: String, hint: String? = nil) -> SupabaseFailure {
        let body: [String: Any] = ["code": "23505", "details": NSNull(), "hint": hint ?? NSNull(), "message": message]
        let data = try! JSONSerialization.data(withJSONObject: body)
        return .http(409, String(decoding: data, as: UTF8.self))
    }

    func testTheTriggerNamesAreReadFromTheErrorBody() {
        XCTAssertEqual(DeviceRegistration.refusal(postgrest("DEVICE_OWNED_ELSEWHERE",
            hint: "The band is bound to another account. It has to be released there first.")), .ownedElsewhere)
        XCTAssertEqual(DeviceRegistration.refusal(postgrest("DEVICE_ALREADY_IN_SET")), .alreadyInSet)
    }

    func testTheNameAnywhereElseIsNotARefusal() {
        XCTAssertEqual(DeviceRegistration.refusal(postgrest("duplicate key value violates unique constraint",
            hint: "DEVICE_OWNED_ELSEWHERE")), .failed, "only the raised message counts")
        XCTAssertEqual(DeviceRegistration.refusal(SupabaseFailure.http(502, "DEVICE_OWNED_ELSEWHERE")), .failed,
                       "a body that is not PostgREST's error object says nothing")
        XCTAssertEqual(DeviceRegistration.refusal(postgrest("device_owned_elsewhere")), .failed)
        XCTAssertEqual(DeviceRegistration.refusal(SupabaseFailure.http(409,
            #"{"message":null,"hint":"DEVICE_OWNED_ELSEWHERE"}"#)), .failed)
    }

    func testTransportAndOtherErrorsFail() {
        XCTAssertEqual(DeviceRegistration.refusal(SupabaseFailure.transport(URLError(.timedOut))), .failed)
        XCTAssertEqual(DeviceRegistration.refusal(CancellationError()), .failed)
        XCTAssertNil(SupabaseFailure.transport(URLError(.notConnectedToInternet)).serverMessage)
    }

    func testARefreshNeverPointsTheRowAtAnotherBand() {
        // An old row's CoreBluetooth alias stays: nothing proves the linked band is that band.
        XCTAssertNil(DeviceRegistration.bleIdentifierWrite(pairing: false,
            existing: "6F1C2C9E-3A4B-4C5D-8E9F-0A1B2C3D4E5F", linked: "AA:BB:CC:DD:EE:01", seed: seed))
        XCTAssertNil(DeviceRegistration.bleIdentifierWrite(pairing: false,
            existing: "AA:BB:CC:DD:EE:01", linked: "AA:BB:CC:DD:EE:02", seed: seed))
        XCTAssertNil(DeviceRegistration.bleIdentifierWrite(pairing: false,
            existing: nil, linked: "AA:BB:CC:DD:EE:01", seed: seed))
    }

    func testPairingPointsTheRowAtTheChosenBand() {
        XCTAssertEqual(DeviceRegistration.bleIdentifierWrite(pairing: true,
            existing: "AA:BB:CC:DD:EE:01", linked: "AA:BB:CC:DD:EE:02", seed: seed), "AA:BB:CC:DD:EE:02")
        XCTAssertNil(DeviceRegistration.bleIdentifierWrite(pairing: true,
            existing: "AA:BB:CC:DD:EE:01", linked: "AA:BB:CC:DD:EE:01", seed: seed), "the same band writes nothing")
        XCTAssertNil(DeviceRegistration.bleIdentifierWrite(pairing: true,
            existing: "AA:BB:CC:DD:EE:01", linked: seed, seed: seed), "the simulator seed never replaces a binding")
        XCTAssertNil(DeviceRegistration.bleIdentifierWrite(pairing: true,
            existing: "AA:BB:CC:DD:EE:01", linked: nil, seed: seed))
    }
}
