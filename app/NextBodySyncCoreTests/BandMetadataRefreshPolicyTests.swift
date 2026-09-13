import XCTest
@testable import NextBodySyncCore

final class BandMetadataRefreshPolicyTests: XCTestCase {
    func testInitializationIsReusedOnlyAfterSuccessAndWithinItsOwnershipAndFirmware() {
        var policy = BandMetadataRefreshPolicy()
        let key = BandMetadataRefreshPolicy.Key(account: "alice", binding: "a", deviceID: "row1", firmware: "1")
        XCTAssertTrue(policy.needsRefresh(key))
        policy.complete(key, success: false)
        XCTAssertTrue(policy.needsRefresh(key))
        policy.complete(key, success: true)
        for _ in 0..<100 { XCTAssertFalse(policy.needsRefresh(key)) }
        XCTAssertTrue(policy.needsRefresh(nil))
        XCTAssertTrue(policy.needsRefresh(.init(account: "bob", binding: "a", deviceID: "row1", firmware: "1")))
        XCTAssertTrue(policy.needsRefresh(.init(account: "alice", binding: "b", deviceID: "row1", firmware: "1")))
        XCTAssertTrue(policy.needsRefresh(.init(account: "alice", binding: "a", deviceID: "row2", firmware: "1")))
        XCTAssertTrue(policy.needsRefresh(.init(account: "alice", binding: "a", deviceID: "row1", firmware: "2")))
        XCTAssertTrue(BandMetadataRefreshPolicy().needsRefresh(key), "a new app process initializes again")
    }
}
