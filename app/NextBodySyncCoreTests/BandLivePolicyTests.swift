import XCTest
@testable import NextBodySyncCore

final class BandLivePolicyTests: XCTestCase {
    func testBackgroundKeepsCollectionWithoutForegroundDemand() {
        XCTAssertTrue(BandLivePolicy.shouldRun(phase: .background, foregroundWanted: false,
            hasOwner: true, consent: true, connected: true, exclusive: false))
        XCTAssertFalse(BandLivePolicy.shouldRun(phase: .active, foregroundWanted: false,
            hasOwner: true, consent: true, connected: true, exclusive: false))
    }

    func testEverySafetyGateStopsCollection() {
        for phase in [BandLivePolicy.Phase.active, .inactive, .background] {
            for gates in [(false, true, true, false), (true, false, true, false),
                          (true, true, false, false), (true, true, true, true)] {
                XCTAssertFalse(BandLivePolicy.shouldRun(phase: phase, foregroundWanted: true,
                    hasOwner: gates.0, consent: gates.1, connected: gates.2, exclusive: gates.3))
            }
        }
    }

    @MainActor func testActiveInactiveBackgroundActiveUsesOneStream() async {
        let tasks = BandLiveTaskOwner()
        let binding = BandLivePolicy.Owner(account: "a", binding: "wrist")
        var starts = 0
        var stops = 0
        for phase in [BandLivePolicy.Phase.active, .inactive, .background, .active] {
            let allowed = BandLivePolicy.shouldRun(phase: phase, foregroundWanted: true,
                hasOwner: true, consent: true, connected: true, exclusive: false)
            tasks.update(owner: allowed ? binding : nil) {
                starts += 1
                do { try await Task.sleep(for: .seconds(60)) } catch {}
                stops += 1
            }
            for _ in 0..<10 { await Task.yield() }
        }
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 0)
        tasks.update(owner: nil) {}
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(stops, 1)
    }

    @MainActor func testRebindingCancelsOldStreamBeforeNewOneStarts() async {
        let tasks = BandLiveTaskOwner()
        var events: [String] = []
        for wrist in ["old", "new"] {
            tasks.update(owner: .init(account: "a", binding: wrist)) {
                events.append("start-" + wrist)
                do { try await Task.sleep(for: .seconds(60)) } catch {}
                events.append("stop-" + wrist)
            }
            for _ in 0..<100 { await Task.yield() }
        }
        XCTAssertEqual(events, ["start-old", "stop-old", "start-new"])
        tasks.update(owner: nil) {}
        for _ in 0..<100 { await Task.yield() }
    }

    @MainActor func testSameOwnerRetainedAndReplacementWaitsForStop() async {
        let owner = BandLiveTaskOwner()
        var events: [String] = []
        let a = BandLivePolicy.Owner(account: "a", binding: "wrist")
        let b = BandLivePolicy.Owner(account: "b", binding: "wrist")
        owner.update(owner: a) {
            events.append("a-start")
            do { try await Task.sleep(for: .seconds(60)) } catch {}
            await Task.yield()
            events.append("a-end")
        }
        for _ in 0..<10 { await Task.yield() }
        owner.update(owner: a) { XCTFail("same owner must reuse task") }
        owner.update(owner: nil) {}
        owner.update(owner: b) {
            events.append("b-start")
            do { try await Task.sleep(for: .seconds(60)) } catch {}
            events.append("b-end")
        }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(events, ["a-start", "a-end", "b-start"])
        owner.update(owner: nil) {}
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(events.last, "b-end")
    }
}
