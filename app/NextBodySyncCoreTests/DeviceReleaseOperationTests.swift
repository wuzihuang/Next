import XCTest
@testable import NextBodySyncCore

final class DeviceReleaseOperationTests: XCTestCase {
    @MainActor
    func testSuccessfulRemovalReturnsWhileTheRadioIsStillBusy() async throws {
        let (radio, gate) = AsyncStream<Void>.makeStream()
        var published = false
        var cleanedUp = false
        let cleanup = try await DeviceReleaseOperation.run(request: { true }, publish: {
            published = $0
        }, cleanup: {
            for await _ in radio { break }
            cleanedUp = true
        })
        XCTAssertTrue(published, "Server acknowledgment is visible before radio cleanup")
        await Task.yield()
        XCTAssertFalse(cleanedUp, "A busy SDK must not block confirmation")
        gate.finish()
        await cleanup.value
        XCTAssertTrue(cleanedUp)
    }

    @MainActor
    func testServerFailureDoesNotPublishRemovalOrDisconnect() async {
        var published = false
        var cleanedUp = false
        do {
            _ = try await DeviceReleaseOperation.run(request: { () -> Bool in
                throw SupabaseFailure.http(404, "PGRST202")
            }, publish: { _ in published = true }, cleanup: { cleanedUp = true })
            XCTFail("Missing RPC must fail")
        } catch {
            XCTAssertEqual(DeviceReleaseError.message(for: error),
                           "HOOP removal is temporarily unavailable. Please try again later.")
        }
        await Task.yield()
        XCTAssertFalse(published)
        XCTAssertFalse(cleanedUp)
    }

    func testTimeoutIsUnconfirmedInsteadOfClaimingNothingChanged() {
        XCTAssertEqual(DeviceReleaseError.message(for: URLError(.timedOut)),
                       "Removal could not be confirmed in time. Retry to check; your history is safe.")
        XCTAssertNotEqual(DeviceReleaseError.message(for: DeviceReleaseError.bindingUnavailable),
                          DeviceReleaseError.message(for: URLError(.notConnectedToInternet)))
    }
}
