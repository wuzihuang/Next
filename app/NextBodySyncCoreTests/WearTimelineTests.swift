import XCTest
@testable import NextBodySyncCore

/// docs/plans/2026-09-12-dual-device-continuity.md §04.5 · the declaration is the only rule.
final class WearTimelineTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private func at(_ hours: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + hours * 3600) }

    private var set: [SlotBinding] {
        [SlotBinding(slot: .a, identifier: "band-A", boundAt: at(0)),
         SlotBinding(slot: .b, identifier: "band-B", boundAt: at(6))]
    }

    func testSoleBandIsWornSinceItWasBound() {
        let t = WearTimeline(bindings: [SlotBinding(slot: .a, identifier: "band-A", boundAt: at(0))])
        XCTAssertEqual(t.wearer(at: at(3)), .a)
        XCTAssertEqual(t.wearingSince(now: at(3)), at(0))
    }

    func testSlotAIsTheDefaultWearerBeforeAnyDeclaration() {
        let t = WearTimeline(bindings: set)
        XCTAssertEqual(t.wearer(at: at(8)), .a, "activating B does not move the record")
    }

    func testDeclarationOwnsEveryMomentFromItsEffectiveTime() {
        let t = WearTimeline(bindings: set).declaring(.b, at: at(8.5), recordedAt: at(9), opId: "op-1")
        XCTAssertEqual(t.wearer(at: at(8)), .a)
        XCTAssertEqual(t.wearer(at: at(9)), .b)
        XCTAssertEqual(t.wearingSince(now: at(10)), at(8.5))
    }

    func testRetryingTheSameOperationDoesNotDuplicate() {
        let once = WearTimeline(bindings: set).declaring(.b, at: at(8.5), recordedAt: at(9), opId: "op-1")
        let twice = once.declaring(.b, at: at(7.5), recordedAt: at(9.5), opId: "op-1")
        XCTAssertEqual(twice.events.count, 1)
        XCTAssertEqual(twice.wearer(at: at(8)), .b, "the retry carries the corrected time")
    }

    func testEventsSortByEffectiveTimeNotArrival() {
        let t = WearTimeline(bindings: set)
            .declaring(.b, at: at(12), recordedAt: at(12), opId: "op-1")
            .declaring(.a, at: at(9), recordedAt: at(13), opId: "op-2")
        XCTAssertEqual(t.wearer(at: at(10)), .a)
        XCTAssertEqual(t.wearer(at: at(13)), .b)
    }

    func testEarliestSwitchIsTheBinding() {
        let t = WearTimeline(bindings: set)
        XCTAssertEqual(t.earliestSwitch(to: .b), at(6))
        XCTAssertNil(WearTimeline(bindings: []).earliestSwitch(to: .b))
    }

    func testPendingDaysAreCappedByWhatTheFirmwareHolds() {
        XCTAssertEqual(WearTimeline.pendingDays(lastSync: at(0), boundAt: nil, now: at(3 * 24), holdsDays: 7), 3)
        XCTAssertEqual(WearTimeline.pendingDays(lastSync: at(0), boundAt: nil, now: at(12 * 24), holdsDays: 7), 7)
        XCTAssertEqual(WearTimeline.pendingDays(lastSync: nil, boundAt: at(0), now: at(30), holdsDays: 7), 1)
        XCTAssertEqual(WearTimeline.pendingDays(lastSync: nil, boundAt: nil, now: at(30), holdsDays: 7), 0)
    }

    func testSyncDeadlineFollowsRetention() {
        XCTAssertEqual(WearTimeline.syncDeadline(lastSync: at(0), boundAt: nil, holdsDays: 7), at(7 * 24))
        XCTAssertNil(WearTimeline.syncDeadline(lastSync: at(0), boundAt: nil, holdsDays: nil))
    }

    func testRemovingEitherSlotPreservesTheOtherBindingAndCanRefillTheVacancy() {
        let savedBindings = DeviceSlots.bindings
        let savedTransport = DeviceSlots.transport
        let savedWearing = DeviceSlots.wearing
        defer {
            DeviceSlots.bindings = savedBindings
            DeviceSlots.transport = savedTransport
            DeviceSlots.wearing = savedWearing
        }
        for removed in HoopSlot.allCases {
            for worn in HoopSlot.allCases {
                DeviceSlots.bindings = set
                DeviceSlots.transport = worn
                DeviceSlots.wearing = worn
                let survivor = DeviceSlots.binding(removed.other)
                DeviceSlots.remove(removed)
                XCTAssertNil(DeviceSlots.binding(removed))
                XCTAssertEqual(DeviceSlots.binding(removed.other), survivor)
                XCTAssertEqual(DeviceSlots.transport, removed.other)
                XCTAssertEqual(DeviceSlots.wearing, removed.other)
                let replacement = SlotBinding(slot: removed, identifier: "replacement", boundAt: at(24))
                DeviceSlots.set(replacement)
                XCTAssertEqual(DeviceSlots.binding(removed), replacement)
                XCTAssertEqual(DeviceSlots.binding(removed.other), survivor)
                XCTAssertEqual(DeviceSlots.wearing, removed.other)
            }
        }
    }
}
