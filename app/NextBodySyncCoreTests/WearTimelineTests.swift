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
        let savedOwner = DeviceSlots.owner
        DeviceSlots.owner = "wear-timeline-tests"
        defer {
            DeviceSlots.forgetAll()
            DeviceSlots.owner = savedOwner
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

    /// One band, one account: a band one account bound is not there for the next account
    /// on the same phone, and comes back when its own account signs in again.
    func testBandsAreFiledPerAccount() {
        let savedOwner = DeviceSlots.owner
        defer {
            for account in ["account-a", "account-b"] { DeviceSlots.owner = account; DeviceSlots.forgetAll() }
            DeviceSlots.owner = savedOwner
        }
        DeviceSlots.owner = "account-a"
        DeviceSlots.set(SlotBinding(slot: .a, identifier: "band-of-a", boundAt: at(0)))
        DeviceSlots.transport = .a
        DeviceSlots.pendingOps = [WearEvent(slot: .a, effectiveAt: at(1), recordedAt: at(1), clientOpId: "op-a")]

        DeviceSlots.owner = nil
        XCTAssertTrue(DeviceSlots.bindings.isEmpty, "nobody signed in holds no band")
        DeviceSlots.set(SlotBinding(slot: .a, identifier: "written-while-signed-out"))
        XCTAssertTrue(DeviceSlots.bindings.isEmpty, "nothing is written without an account")

        DeviceSlots.owner = "account-b"
        XCTAssertTrue(DeviceSlots.bindings.isEmpty)
        XCTAssertTrue(DeviceSlots.pendingOps.isEmpty, "another account's offline declarations never replay")
        DeviceSlots.set(SlotBinding(slot: .a, identifier: "band-of-b"))

        DeviceSlots.owner = "account-a"
        XCTAssertEqual(DeviceSlots.binding(.a)?.identifier, "band-of-a")
        XCTAssertEqual(DeviceSlots.pendingOps.map(\.clientOpId), ["op-a"])
    }

    /// The set from before per-account filing belongs to whoever is signed in at the
    /// first launch of this build, or to no one.
    func testUnownedBindingsGoToTheSignedInAccountOrNowhere() {
        let savedOwner = DeviceSlots.owner
        let defaults = UserDefaults.standard
        let legacy = try! JSONEncoder().encode([SlotBinding(slot: .a, identifier: "legacy-band")])
        defer {
            defaults.removeObject(forKey: "nb.band.slots.v1")
            DeviceSlots.owner = "account-a"; DeviceSlots.forgetAll()
            DeviceSlots.owner = savedOwner
        }
        defaults.set(legacy, forKey: "nb.band.slots.v1")
        DeviceSlots.adoptUnownedBindings(owner: nil)
        XCTAssertNil(defaults.object(forKey: "nb.band.slots.v1"))
        DeviceSlots.owner = "account-a"
        XCTAssertTrue(DeviceSlots.bindings.isEmpty, "signed out at upgrade: no one inherits it")

        defaults.set(legacy, forKey: "nb.band.slots.v1")
        DeviceSlots.adoptUnownedBindings(owner: "account-a")
        XCTAssertNil(defaults.object(forKey: "nb.band.slots.v1"))
        XCTAssertEqual(DeviceSlots.binding(.a)?.identifier, "legacy-band")
    }
}
