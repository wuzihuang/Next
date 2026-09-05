import XCTest
@testable import NextBodySyncCore

final class SessionBoundTransportTests: XCTestCase {
    actor Harness {
        var stamp = RequestSession(owner: "A", generation: UUID())
        let switchOnSend: Bool
        let switchOnRefresh: Bool
        let nextOwner: String
        init(switchOnSend: Bool = true, switchOnRefresh: Bool = false, nextOwner: String = "B") {
            self.nextOwner = nextOwner
            self.switchOnSend = switchOnSend; self.switchOnRefresh = switchOnRefresh
        }
        var idempotencyKeys: [String] = []
        var sends = 0
        var refreshes = 0
        func current() -> RequestSession { stamp }
        func send(_ request: URLRequest) -> (Data, URLResponse) {
            sends += 1
            idempotencyKeys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
            if switchOnSend { stamp = RequestSession(owner: nextOwner, generation: UUID()) }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: sends == 1 ? 401 : 200, httpVersion: nil, headerFields: nil)!)
        }
        func refresh() -> String? {
            refreshes += 1
            if switchOnRefresh { stamp = RequestSession(owner: nextOwner, generation: UUID()) }
            return "refreshed-token"
        }
    }
    func testAccountSwitchAfterUnauthorizedResponseNeverRetriesUnderNewUser() async throws {
        let h = Harness()
        let original = await h.current()
        do {
            _ = try await SessionBoundTransport.perform(URLRequest(url: URL(string: "https://example.test/write")!),
                session: original, current: { await h.current() }, send: { await h.send($0) }, refresh: { await h.refresh() })
            XCTFail("Old owner request must be cancelled")
        } catch { XCTAssertTrue(error is CancellationError) }
        let sends = await h.sends, refreshes = await h.refreshes
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(refreshes, 0)
    }
    func testAlreadySwitchedOwnerDoesNotSend() async {
        let h = Harness()
        do {
            _ = try await SessionBoundTransport.perform(URLRequest(url: URL(string: "https://example.test/write")!),
                session: RequestSession(owner: "old", generation: UUID()), current: { await h.current() },
                send: { await h.send($0) }, refresh: { await h.refresh() })
            XCTFail("Stale work must not send")
        } catch { XCTAssertTrue(error is CancellationError) }
        let sends = await h.sends
        XCTAssertEqual(sends, 0)
    }
    func testSwitchDuringRefreshDoesNotRetryOldPayload() async {
        let h = Harness(switchOnSend: false, switchOnRefresh: true)
        let original = await h.current()
        do {
            _ = try await SessionBoundTransport.perform(URLRequest(url: URL(string: "https://example.test/write")!),
                session: original, current: { await h.current() }, send: { await h.send($0) }, refresh: { await h.refresh() })
            XCTFail("Switched refresh cannot authorize old request")
        } catch { XCTAssertTrue(error is CancellationError) }
        let sends = await h.sends
        XCTAssertEqual(sends, 1)
    }
    func testSameSessionCanRefreshAndRetryOnce() async throws {
        let h = Harness(switchOnSend: false)
        let original = await h.current()
        let (_, response) = try await SessionBoundTransport.perform(URLRequest(url: URL(string: "https://example.test/write")!),
            session: original, current: { await h.current() }, send: { await h.send($0) }, refresh: { await h.refresh() })
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let sends = await h.sends, refreshes = await h.refreshes
        XCTAssertEqual(sends, 2)
        XCTAssertEqual(refreshes, 1)
    }

    func testSameAccountNewLoginStillInvalidatesOldSessionWork() async {
        let h = Harness(nextOwner: "A")
        let original = await h.current()
        do {
            _ = try await SessionBoundTransport.perform(URLRequest(url: URL(string: "https://example.test/write")!),
                session: original, current: { await h.current() }, send: { await h.send($0) }, refresh: { await h.refresh() })
            XCTFail("A new login is a new session even for the same account")
        } catch { XCTAssertTrue(error is CancellationError) }
        let refreshes = await h.refreshes
        XCTAssertEqual(refreshes, 0)
    }

    func testLogicalTurnKeepsIdAcrossLostResponseRetry() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let request = URLRequest(url: URL(string: "https://example.test/turn")!)
        let first = SessionBoundTransport.identifying(request, requestID: id)
        let retry = SessionBoundTransport.identifying(request, requestID: id)
        XCTAssertEqual(first.value(forHTTPHeaderField: "Idempotency-Key"), "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(retry.value(forHTTPHeaderField: "Idempotency-Key"), first.value(forHTTPHeaderField: "Idempotency-Key"))
    }

    func testUnauthorizedRetryPreservesLogicalTurnKey() async throws {
        let h = Harness(switchOnSend: false)
        let original = await h.current()
        let id = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let request = SessionBoundTransport.identifying(URLRequest(url: URL(string: "https://example.test/turn")!), requestID: id)
        _ = try await SessionBoundTransport.perform(request, session: original,
            current: { await h.current() }, send: { await h.send($0) }, refresh: { await h.refresh() })
        let keys = await h.idempotencyKeys
        XCTAssertEqual(keys, ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"])
    }

    actor LostResponseHarness {
        let stamp = RequestSession(owner: "A", generation: UUID())
        var keys: [String] = []
        func send(_ request: URLRequest) throws -> (Data, URLResponse) {
            keys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
            if keys.count == 1 { throw URLError(.networkConnectionLost) }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    func testReissuedLogicalTurnAfterLostResponseUsesOriginalKey() async throws {
        let h = LostResponseHarness()
        let id = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let original = h.stamp
        for attempt in 0...1 {
            let request = SessionBoundTransport.identifying(URLRequest(url: URL(string: "https://example.test/turn")!), requestID: id)
            do {
                _ = try await SessionBoundTransport.perform(request, session: original,
                    current: { h.stamp }, send: { try await h.send($0) }, refresh: { nil })
                XCTAssertEqual(attempt, 1)
            } catch { XCTAssertEqual(attempt, 0) }
        }
        let keys = await h.keys
        XCTAssertEqual(keys, ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"])
    }

}
