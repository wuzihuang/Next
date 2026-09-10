import XCTest
@testable import NextBodySyncCore

final class BandLivePolicyTests: XCTestCase {
    private func run(_ phase: BandLivePolicy.Phase, wanted: Bool) -> Bool {
        BandLivePolicy.shouldRun(phase: phase, foregroundWanted: wanted,
            hasOwner: true, consent: true, connected: true, exclusive: false)
    }

    /// ADR 0023 · leaving the app ends the stream, whatever the panel was asking for.
    func testBackgroundNeverCollects() {
        XCTAssertFalse(run(.background, wanted: true))
        XCTAssertFalse(run(.background, wanted: false))
    }

    /// The panel's demand is the only thing that opens a stream; a brief `.inactive`
    /// (a call, Control Center) keeps one open rather than churning it.
    func testForegroundDemandOpensAndInactiveRetains() {
        XCTAssertTrue(run(.active, wanted: true))
        XCTAssertTrue(run(.inactive, wanted: true))
        XCTAssertFalse(run(.active, wanted: false))
        XCTAssertFalse(run(.inactive, wanted: false))
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

    /// active → inactive is one stream; background ends it; active again opens a new one.
    @MainActor func testInactiveKeepsOneStreamAndBackgroundEndsIt() async {
        let tasks = BandLiveTaskOwner()
        let binding = BandLivePolicy.Owner(account: "a", binding: "wrist")
        var starts = 0
        var stops = 0
        func drive(_ phase: BandLivePolicy.Phase) async {
            let allowed = BandLivePolicy.shouldRun(phase: phase, foregroundWanted: true,
                hasOwner: true, consent: true, connected: true, exclusive: false)
            tasks.update(owner: allowed ? binding : nil) {
                starts += 1
                do { try await Task.sleep(for: .seconds(60)) } catch {}
                stops += 1
            }
            for _ in 0..<100 { await Task.yield() }
        }
        await drive(.active)
        await drive(.inactive)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 0)
        await drive(.background)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 1)
        await drive(.active)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(stops, 1)
        tasks.update(owner: nil) {}
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(stops, 2)
    }
}
