import XCTest
@testable import NextBodySyncCore

final class BandPersonalInfoPolicyTests: XCTestCase {
    func testOnlyDocumentedSuccessIsAccepted() {
        XCTAssertFalse(BandPersonalInfoPolicy.acknowledged(0))
        XCTAssertTrue(BandPersonalInfoPolicy.acknowledged(1))
        XCTAssertFalse(BandPersonalInfoPolicy.acknowledged(2))
        XCTAssertFalse(BandPersonalInfoPolicy.acknowledged(UInt.max))
    }

    func testQueuedWriteCannotCrossAccountBindingOrConsentChange() {
        XCTAssertTrue(BandPersonalInfoPolicy.owns(expectedAccount: "a", expectedBinding: "band",
                                                account: "a", binding: "band", consent: true))
        XCTAssertFalse(BandPersonalInfoPolicy.owns(expectedAccount: "a", expectedBinding: "band",
                                                 account: "b", binding: "band", consent: true))
        XCTAssertFalse(BandPersonalInfoPolicy.owns(expectedAccount: "a", expectedBinding: "band",
                                                 account: "a", binding: "other", consent: true))
        XCTAssertFalse(BandPersonalInfoPolicy.owns(expectedAccount: "a", expectedBinding: "band",
                                                 account: "a", binding: "band", consent: false))
        XCTAssertFalse(BandPersonalInfoPolicy.owns(expectedAccount: "a", expectedBinding: nil,
                                                 account: "a", binding: nil, consent: true))
    }
}
