import Foundation

/// docs/plans/2026-09-12-dual-device-continuity.md §04.5 · two HOOPs, one wearer.
///
/// A slot is a fixed position in the account's device set. It is given when the band is
/// activated and never moves with wearing, preference or a new BLE alias. The app talks to
/// one band at a time (the SDK is a singleton); `transport` names that band, `wearing`
/// names the band the person declared on the wrist. The two agree except during a standby
/// sync, when the phone briefly reads the other band.
enum HoopSlot: String, Codable, CaseIterable, Sendable {
    case a = "A", b = "B"

    var other: HoopSlot { self == .a ? .b : .a }
    var displayName: String { "HOOP \(rawValue)" }
}

/// What this phone knows about one slot. `identifier` is the durable binding key the whole
/// sync lane is scoped by; `peripheralIdentifier` is this phone's CoreBluetooth alias.
struct SlotBinding: Codable, Equatable, Sendable {
    var slot: HoopSlot
    var identifier: String
    var peripheralIdentifier: String?
    var deviceId: String?
    var name: String?
    var boundAt: Date?
}

/// One wear declaration: from `effectiveAt` the person wore `slot`, until the next event.
struct WearEvent: Codable, Equatable, Sendable {
    var slot: HoopSlot
    var effectiveAt: Date
    var recordedAt: Date
    var clientOpId: String?
    /// `auto` · the app declared at the tap and let the band's evidence move the start.
    /// `manual` · a time the wearer pinned. Absent on events an older build stored.
    var source: String?

    var isPinned: Bool { source == "manual" }
}

/// Pure timeline math. The declaration is the only rule: whoever was declared worn at a
/// moment owns that moment. Before any declaration the sole bound band (slot A when both
/// exist) counts as worn since it was bound.
struct WearTimeline: Equatable, Sendable {
    var events: [WearEvent]
    var bindings: [SlotBinding]

    init(events: [WearEvent] = [], bindings: [SlotBinding] = []) {
        self.events = events.sorted { ($0.effectiveAt, $0.recordedAt) < ($1.effectiveAt, $1.recordedAt) }
        self.bindings = bindings
    }

    var isEmpty: Bool { bindings.isEmpty }

    func binding(_ slot: HoopSlot) -> SlotBinding? { bindings.first { $0.slot == slot } }

    /// The slot declared worn at `date`, or the default wearer when nothing was declared.
    func wearer(at date: Date) -> HoopSlot? {
        if let event = events.last(where: { $0.effectiveAt <= date }) { return event.slot }
        return bindings.sorted { $0.slot.rawValue < $1.slot.rawValue }.first?.slot
    }

    /// When the current wearer's segment began.
    func wearingSince(now: Date = Date()) -> Date? {
        if let event = events.last(where: { $0.effectiveAt <= now }) { return event.effectiveAt }
        return wearer(at: now).flatMap { binding($0)?.boundAt }
    }

    /// Appending a declaration. A later event with the same slot as the current wearer is
    /// still recorded: it may move the switch point earlier or later.
    func declaring(_ slot: HoopSlot, at date: Date, recordedAt: Date, opId: String,
                   source: String = "auto") -> WearTimeline {
        var next = events
        next.removeAll { $0.clientOpId == opId }
        next.append(WearEvent(slot: slot, effectiveAt: date, recordedAt: recordedAt,
                              clientOpId: opId, source: source))
        return WearTimeline(events: next, bindings: bindings)
    }

    /// The declaration in force at `date`, if the person has made one.
    func current(at date: Date = Date()) -> WearEvent? { events.last { $0.effectiveAt <= date } }

    /// Earliest moment a declaration for `slot` may take effect: the band cannot have been
    /// worn for this account before it was bound.
    func earliestSwitch(to slot: HoopSlot) -> Date? { binding(slot)?.boundAt }

    /// Whole user days the standby band has recorded since it was last read, capped by how
    /// many days the firmware keeps. Drives `PENDING n DAYS · SYNC BEFORE …`.
    static func pendingDays(lastSync: Date?, boundAt: Date?, now: Date, holdsDays: Int?) -> Int {
        guard let since = lastSync ?? boundAt else { return 0 }
        let days = Int(now.timeIntervalSince(since) / 86_400)
        return max(0, min(days, holdsDays ?? days))
    }

    /// The last calendar day on which the standby band can still be read before its oldest
    /// unsynced day rolls out of the firmware's retention.
    static func syncDeadline(lastSync: Date?, boundAt: Date?, holdsDays: Int?) -> Date? {
        guard let since = lastSync ?? boundAt, let holdsDays else { return nil }
        return since.addingTimeInterval(Double(holdsDays) * 86_400)
    }
}

/// UserDefaults-backed slot store. `BoundBand` reads the transport slot through here so the
/// thirty-odd call sites that key readiness, refresh scope and evidence by
/// `BoundBand.identifier` keep working unchanged.
enum DeviceSlots {
    private static let bindingsKey = "nb.band.slots.v1"
    private static let transportKey = "nb.band.transportSlot.v1"
    private static let wearingKey = "nb.band.wearingSlot.v1"
    private static let timelineKey = "nb.band.wearEvents.v1"
    private static let pendingOpsKey = "nb.band.wearEvents.pending.v1"

    static var bindings: [SlotBinding] {
        get {
            guard let data = UserDefaults.standard.data(forKey: bindingsKey) else { return [] }
            return (try? JSONDecoder().decode([SlotBinding].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: bindingsKey)
        }
    }

    static func binding(_ slot: HoopSlot) -> SlotBinding? { bindings.first { $0.slot == slot } }

    static func set(_ binding: SlotBinding) {
        var all = bindings.filter { $0.slot != binding.slot }
        all.append(binding)
        bindings = all.sorted { $0.slot.rawValue < $1.slot.rawValue }
    }

    static func remove(_ slot: HoopSlot) {
        bindings = bindings.filter { $0.slot != slot }
        if transport == slot { transport = bindings.first?.slot ?? .a }
        if wearing == slot { wearing = bindings.first?.slot ?? .a }
    }

    /// Which band the SDK link targets right now.
    static var transport: HoopSlot {
        get { HoopSlot(rawValue: UserDefaults.standard.string(forKey: transportKey) ?? "") ?? .a }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: transportKey) }
    }

    /// Which band the person declared on the wrist.
    static var wearing: HoopSlot {
        get { HoopSlot(rawValue: UserDefaults.standard.string(forKey: wearingKey) ?? "") ?? .a }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: wearingKey) }
    }

    static var events: [WearEvent] {
        get {
            guard let data = UserDefaults.standard.data(forKey: timelineKey) else { return [] }
            return (try? JSONDecoder().decode([WearEvent].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: timelineKey) }
    }

    /// Declarations made offline, replayed on the next successful network call.
    static var pendingOps: [WearEvent] {
        get {
            guard let data = UserDefaults.standard.data(forKey: pendingOpsKey) else { return [] }
            return (try? JSONDecoder().decode([WearEvent].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: pendingOpsKey) }
    }

    static var timeline: WearTimeline { WearTimeline(events: events, bindings: bindings) }

    static var hasSecond: Bool { bindings.count >= 2 }

    static func forgetAll() {
        for key in [bindingsKey, transportKey, wearingKey, timelineKey, pendingOpsKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
