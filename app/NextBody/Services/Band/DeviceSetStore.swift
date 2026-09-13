import Foundation
import os

/// docs/plans/2026-09-12-dual-device-continuity.md §04.5 · the phone's view of the set.
///
/// One HOOP is worn; the other charges. The person says which (`I'm wearing B`), and that
/// declaration is the only rule the server uses to pick a source. This store keeps both
/// slots' last-known facts, the wear timeline, and drives the two link moves the manual
/// model needs: the handover (transport follows the declaration) and the standby sync
/// (transport briefly visits the other band, then comes back).
@MainActor
final class DeviceSetStore: ObservableObject {
    static let shared = DeviceSetStore()
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "deviceset")

    /// Last-known facts about one slot. Off-link values are what the server or the last
    /// visit reported, with the time they were read — never a guess.
    struct SlotSnapshot: Equatable {
        var slot: HoopSlot
        var deviceId: String?
        var identifier: String?
        var name: String
        var firmware: String?
        var battery: BandBattery?
        var batteryReadAt: Date?
        var lastSync: Date?
        var boundAt: Date?
        var holdsDays: Int?
        var standbySamples: Int = 0

        var isBound: Bool { identifier != nil }

        /// A band at the bottom of its pack has stopped recording. Level-only firmware
        /// reports 0–4 bars instead of a percent, so both shapes count.
        var isFlat: Bool {
            guard let battery, battery.chargeState != .charging, battery.chargeState != .full else { return false }
            if battery.isPercent, let percent = battery.percent { return percent <= 2 }
            if let level = battery.level { return level <= 0 }
            return false
        }

        /// Low enough that it will not last the day, but still recording.
        var isLow: Bool {
            guard let battery, !isFlat, battery.chargeState != .charging, battery.chargeState != .full else { return false }
            if battery.isPercent, let percent = battery.percent { return percent <= 15 }
            if let level = battery.level { return level <= 1 }
            return false
        }
    }

    enum Phase: Equatable {
        case idle
        /// The band being left is finishing the command it is on. The SDK has no stop, so
        /// this wait is real — but it is one day's read, not the rest of a week's history.
        case finishing(HoopSlot)
        /// The declaration is recorded; the link is moving to the declared band.
        case switching(HoopSlot)
        /// The second band is being verified and given its slot.
        case activating(HoopSlot)
    }

    @Published private(set) var slots: [HoopSlot: SlotSnapshot] = [:]
    @Published private(set) var timeline = DeviceSlots.timeline
    @Published private(set) var wearing = DeviceSlots.wearing
    @Published private(set) var transport = DeviceSlots.transport
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var isReleasing = false
    private var bindingRevision = 0
    private var replaying = false
    let activationGate = DeviceActivationGate()

    func prepareActivation(owner: UUID) async throws {
        guard !isReleasing, phase == .idle || activationGate.owner == owner,
              openSlot != nil else { throw DeviceActivationGate.Failure.busy }
        // Close admission synchronously before the first suspension/scan. Existing pulls
        // stop at their next scope check instead of finishing a week of history.
        do {
            try await activationGate.prepare(owner: owner, acquired: {
                bindingRevision += 1
                BandLiveLifecycle.shared.refreshEligibility()
            }) {
                OriginDataSync.isIdle && BandReadiness.shared.isNativeIdle
            }
            await LiveReadout.shared.standDown { }
            BandLiveLifecycle.shared.refreshEligibility()
            try Task.checkCancellation()
            guard let slot = openSlot else { throw DeviceActivationGate.Failure.busy }
            phase = .activating(slot)
            Self.log.notice("activate: radio ready for scan")
        } catch {
            endActivation(owner: owner)
            BandLiveLifecycle.shared.refreshEligibility()
            throw error
        }
    }

    func endActivation(owner: UUID) {
        guard activationGate.owner == owner else { return }
        activationGate.release(owner: owner)
        phase = .idle
        BandLiveLifecycle.shared.refreshEligibility()
    }

    var hasSecond: Bool { slots.count >= 2 }
    var standbySlot: HoopSlot? { hasSecond ? wearing.other : nil }
    /// What the last read said about a band's charge. Off-link this is the last known
    /// value, never a live one, so the card says when it was read.
    func isFlat(_ slot: HoopSlot) -> Bool { slots[slot]?.isFlat ?? false }
    func snapshot(_ slot: HoopSlot) -> SlotSnapshot? { slots[slot] }
    var wearingSince: Date? { timeline.wearingSince() }
    /// True when the start came from the band's own evidence rather than a time the
    /// wearer pinned — the `Counted from …` line says so, and offers to change it.
    var wearingInferred: Bool { timeline.current()?.source != "manual" }

    /// The empty slot the next activation fills, if the set has room.
    var openSlot: HoopSlot? {
        guard slots.count == 1, let bound = slots.keys.first else { return slots.isEmpty ? .a : nil }
        return bound.other
    }

    /// One handover at a time. A second tap does not start a second link move; it changes
    /// where the one in flight is headed.
    private var handover: Task<Void, Never>?
    private var releaseCleanup: Task<Void, Never>?
    /// Where the last move ended and when. A second tap on the HOOP the link just landed
    /// on is not a reason to read it again.
    private var landed: (slot: HoopSlot, at: Date)?

    private init() {
        hydrateFromLocal()
    }

    // MARK: loading

    /// Local first, so the page draws without a network round trip; then the server's set.
    func hydrateFromLocal() {
        var next: [HoopSlot: SlotSnapshot] = [:]
        for binding in DeviceSlots.bindings {
            var snap = slots[binding.slot] ?? SlotSnapshot(slot: binding.slot, name: binding.name ?? "NEXTBODY HOOP")
            snap.deviceId = binding.deviceId
            snap.identifier = binding.identifier
            snap.boundAt = binding.boundAt ?? snap.boundAt
            if let name = binding.name { snap.name = name }
            next[binding.slot] = snap
        }
        slots = next
        timeline = DeviceSlots.timeline
        wearing = DeviceSlots.wearing
        transport = DeviceSlots.transport
        applyDebugCharge()
    }

    /// `NB_DEBUG_STANDBY=flat|low|pending|risk` puts the band on the charger into a state
    /// that otherwise needs a week and a drained pack to reach.
    private func applyDebugCharge() {
        #if DEBUG
        guard let edge = ProcessInfo.processInfo.environment["NB_DEBUG_STANDBY"],
              var snap = slots[wearing.other] else { return }
        switch edge {
        case "flat":
            snap.battery = BandBattery(isPercent: true, percent: 0, level: nil, chargeState: .unplugged)
        case "low":
            snap.battery = BandBattery(isPercent: true, percent: 9, level: nil, chargeState: .unplugged)
        case "pending", "risk":
            snap.battery = BandBattery(isPercent: true, percent: 64, level: nil, chargeState: .unplugged)
            snap.holdsDays = 7
            snap.lastSync = Date().addingTimeInterval(edge == "risk" ? -6.6 * 86_400 : -2.4 * 86_400)
        default: return
        }
        snap.batteryReadAt = Date().addingTimeInterval(-3600)
        slots[wearing.other] = snap
        #endif
    }

    func load() async {
        guard !isReleasing, !activationGate.isHeld else { return }
        hydrateFromLocal()
        #if DEBUG
        // The explicit two-band simulator fixture has no server bindings.
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_SECOND_HOOP"] != nil
            || ProcessInfo.processInfo.environment["NB_DEBUG_RELEASED_SLOT"] != nil { return }
        #endif
        let revision = bindingRevision
        await replayPending()
        guard let set = try? await Repository.shared.loadDeviceSet() else {
            if !activationGate.isHeld, revision == bindingRevision { hydrateFromLocal() }
            return
        }
        guard !isReleasing, !activationGate.isHeld, revision == bindingRevision else { return }
        apply(set)
        // A switch settles once the band has been read, but that read can still be
        // draining when the handover finishes. Finishing the job here costs one call and
        // makes the start right the next time the page is opened.
        if phase == .idle, let current = timeline.current(), current.source == "auto",
           Date().timeIntervalSince(current.recordedAt) < 6 * 3600,
           let settled = try? await Repository.shared.settleWearStart(), !settled.isEmpty {
            if !isReleasing, revision == bindingRevision { apply(settled) }
        }
    }

    private func apply(_ set: [String: Any]) {
        let devices = set["devices"] as? [[String: Any]] ?? []
        var next: [HoopSlot: SlotSnapshot] = [:]
        var claims: [(String, String)] = []
        for row in devices {
            guard let raw = row["slot"] as? String, let slot = HoopSlot(rawValue: raw),
                  let key = row["device_key"] as? String else { continue }
            var binding = DeviceSlots.binding(slot) ?? SlotBinding(slot: slot, identifier: key)
            binding.deviceId = row["id"] as? String
            binding.boundAt = (row["bound_at"] as? String).flatMap(Self.timestamp) ?? binding.boundAt
            DeviceSlots.set(binding)
            // The server must know the key this phone files evidence under, or the wearer
            // rule holds the worn band's own ticks (found on the first device walk).
            if let id = binding.deviceId, row["client_key"] as? String != binding.identifier,
               binding.identifier != BoundBand.seedIdentifier {
                claims.append((id, binding.identifier))
            }
            var snap = slots[slot] ?? SlotSnapshot(slot: slot, name: binding.name ?? "NEXTBODY HOOP")
            snap.deviceId = binding.deviceId
            snap.identifier = binding.identifier
            snap.boundAt = binding.boundAt
            snap.firmware = row["firmware_version"] as? String ?? snap.firmware
            snap.lastSync = (row["last_origin_sync_at"] as? String).flatMap(Self.timestamp) ?? snap.lastSync
            snap.standbySamples = Self.int(row["standby_samples"]) ?? 0
            if snap.battery == nil, let percent = Self.int(row["battery_percent"]) {
                snap.battery = BandBattery(isPercent: (row["battery_is_percent"] as? Bool) ?? true,
                                           percent: percent, level: Self.int(row["battery_level"]),
                                           chargeState: .unknown)
                snap.batteryReadAt = snap.lastSync
            }
            next[slot] = snap
        }
        // A slot the server no longer has is gone here too (released on another phone).
        for slot in HoopSlot.allCases where next[slot] == nil { DeviceSlots.remove(slot) }
        slots = next
        var events: [WearEvent] = []
        for row in set["events"] as? [[String: Any]] ?? [] {
            guard let raw = row["slot"] as? String, let slot = HoopSlot(rawValue: raw),
                  let at = (row["effective_at"] as? String).flatMap(Self.timestamp) else { continue }
            events.append(WearEvent(slot: slot, effectiveAt: at,
                                    recordedAt: (row["recorded_at"] as? String).flatMap(Self.timestamp) ?? at,
                                    clientOpId: nil, source: row["source"] as? String))
        }
        // Local declarations that have not reached the server yet still count.
        events.append(contentsOf: DeviceSlots.pendingOps)
        DeviceSlots.events = events
        timeline = DeviceSlots.timeline
        if let worn = timeline.wearer(at: Date()), DeviceSlots.binding(worn) != nil {
            DeviceSlots.wearing = worn
        }
        wearing = DeviceSlots.wearing
        transport = DeviceSlots.transport
        if !claims.isEmpty {
            let revision = bindingRevision
            Task { [claims] in
                for (id, key) in claims {
                    guard !isReleasing, revision == bindingRevision else { return }
                    if let set = try? await Repository.shared.claimDeviceKey(deviceId: id, clientKey: key), !set.isEmpty {
                        guard !isReleasing, revision == bindingRevision else { return }
                        apply(set)
                    }
                }
            }
        }
    }

    /// The transport band's live facts, as the sync lane learns them.
    func noteTransportObservation(from state: BandState, lastSync: Date?) {
        let slot = DeviceSlots.transport
        guard var snap = slots[slot] else { return }
        if !state.name.isEmpty { snap.name = state.name }
        snap.firmware = state.firmware.isEmpty ? snap.firmware : state.firmware
        if let packet = state.lastBattery {
            snap.battery = packet
            snap.batteryReadAt = Date()
        }
        if let lastSync { snap.lastSync = lastSync }
        slots[slot] = snap
        var binding = DeviceSlots.binding(slot)
        binding?.name = snap.name
        if let binding { DeviceSlots.set(binding) }
    }

    func noteHoldsDays(_ days: Int?, slot: HoopSlot) {
        guard let days, var snap = slots[slot] else { return }
        snap.holdsDays = days
        slots[slot] = snap
    }

    // MARK: declarations

    /// `I'm wearing this one`. Recorded locally first, sent to the server, then the link
    /// follows. The declaration stands whatever the link does afterwards (§04.5 W3).
    ///
    /// `since` is nil on the switching path: the app files the declaration at the tap and
    /// the band's own wrist evidence moves the start back once the phone has read it. A
    /// date is a time the wearer pinned on the correction sheet and is never second-guessed.
    @discardableResult
    func declareWearing(_ slot: HoopSlot, since: Date? = nil, store: DataStore) async -> Bool {
        guard !isReleasing, !activationGate.isHeld, slots[slot] != nil else { return false }
        let now = Date()
        let floor = timeline.earliestSwitch(to: slot) ?? .distantPast
        let effective = max(min(since ?? now, now), floor)
        let opId = UUID().uuidString
        let source = since == nil ? "auto" : "manual"
        let event = WearEvent(slot: slot, effectiveAt: effective, recordedAt: now, clientOpId: opId, source: source)
        DeviceSlots.events = timeline.declaring(slot, at: effective, recordedAt: now, opId: opId, source: source).events
        DeviceSlots.pendingOps.append(event)
        DeviceSlots.wearing = slot
        timeline = DeviceSlots.timeline
        wearing = slot
        Task { await Analytics.shared.track("WEAR_SWITCH_REQUESTED", ["TO": slot.rawValue, "PINNED": since != nil]) }
        // The declaration is the whole answer to the tap, and it is already stored. The
        // network and the radio follow on their own: no signal, a flat band or a link that
        // will not come up can delay them, but none of them can take the declaration back.
        Task { await replayPending() }
        scheduleHandover(store: store, settling: source == "auto" ? opId : nil)
        return true
    }

    /// Move the link to whichever band is declared worn, one move at a time. Tapping
    /// A → B → A in quick succession runs at most one extra move and always ends on the
    /// band named last; it never runs two link moves at once.
    private func scheduleHandover(store: DataStore, settling opId: String?) {
        let previous = handover
        handover = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            // A burst of taps is one intention, not four. Letting it settle for less time
            // than the sheet takes to close turns A → B → A into no link move at all.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            var target = DeviceSlots.wearing
            while !Task.isCancelled {
                guard !activationGate.isHeld else { return }
                if DeviceSlots.transport == target, let landed, landed.slot == target,
                   Date().timeIntervalSince(landed.at) < 5 {
                    Self.log.notice("handover skip target=\(target.rawValue, privacy: .public) · just landed")
                    break
                }
                Self.log.notice("handover run target=\(target.rawValue, privacy: .public)")
                await moveTransport(to: target, store: store, phase: .switching(target))
                target = DeviceSlots.wearing
                if target == DeviceSlots.transport { break }
            }
            guard !Task.isCancelled, let opId else { return }
            await settleStart(opId: opId)
        }
    }

    /// Let the evidence move the start of the declaration this phone just filed.
    private func settleStart(opId: String) async {
        guard !isReleasing else { return }
        let revision = bindingRevision
        guard !DeviceSlots.pendingOps.contains(where: { $0.clientOpId == opId }) else { return }
        guard let set = try? await Repository.shared.settleWearStart(opId: opId), !set.isEmpty else { return }
        guard !isReleasing, revision == bindingRevision else { return }
        let before = timeline.current()?.effectiveAt
        apply(set)
        if let after = timeline.current()?.effectiveAt, before == nil || after < before! - 60 {
            Task { await Analytics.shared.track("WEAR_START_SETTLED", ["MINUTES": Int(Date().timeIntervalSince(after) / 60)]) }
        }
    }

    /// Declarations made offline go up in order on the next chance.
    func replayPending() async {
        guard !isReleasing, !replaying else { return }
        replaying = true
        defer { replaying = false }
        let revision = bindingRevision
        let pending = DeviceSlots.pendingOps
        guard !pending.isEmpty else { return }
        var remaining = pending
        for event in pending {
            guard let deviceId = DeviceSlots.binding(event.slot)?.deviceId, let opId = event.clientOpId else {
                remaining.removeAll { $0.clientOpId == event.clientOpId }
                continue
            }
            do {
                let set = try await Repository.shared.recordWearEvent(
                    deviceId: deviceId, effectiveAt: event.isPinned ? event.effectiveAt : nil, opId: opId)
                guard !isReleasing, revision == bindingRevision else { return }
                remaining.removeAll { $0.clientOpId == opId }
                DeviceSlots.pendingOps.removeAll { $0.clientOpId == opId }
                if !set.isEmpty { apply(set) }
            } catch {
                Self.log.error("wear event not recorded: \(String(describing: error), privacy: .public)")
                break
            }
        }
        // Preserve declarations appended while this request was in flight.
        let completed = Set(pending.compactMap(\.clientOpId)).subtracting(remaining.compactMap(\.clientOpId))
        DeviceSlots.pendingOps.removeAll { $0.clientOpId.map(completed.contains) ?? false }
    }

    // MARK: the link

    /// Point the link at `slot`: finish the pull in flight (never a hard stop), drop the
    /// old link, retarget, reconnect and read. The wearer's declaration is already stored,
    /// so a failure here leaves `WEARING · NOT CONNECTED`, not a reverted declaration.
    private func moveTransport(to slot: HoopSlot, store: DataStore, phase: Phase) async {
        guard DeviceSlots.binding(slot) != nil else { return }
        let began = Date()
        self.phase = phase
        defer { self.phase = .idle; transport = DeviceSlots.transport }
        if DeviceSlots.transport != slot {
            let leaving = DeviceSlots.transport
            noteTransportObservation(from: store.band, lastSync: store.lastSync)
            // A pull already walking the old band's week would otherwise hold the switch
            // for minutes. Pointing the app at the new band first makes that pull see a
            // scope it no longer owns, so it stops at its next day boundary — the wait
            // below is one day's read, not the rest of the history. A measurement is not
            // interruptible that way, so when nothing is pulling we wait first instead.
            Self.log.notice("move begin from=\(leaving.rawValue, privacy: .public) to=\(slot.rawValue, privacy: .public)")
            let pulling = BandSyncActivity.shared.phase != "idle"
            if !pulling { await BandReadiness.shared.awaitNativeIdle() }
            guard !Task.isCancelled else { return }
            BoundBand.switchTransport(to: slot)
            BandReadiness.shared.invalidateSnapshot()
            transport = slot
            if pulling {
                self.phase = .finishing(leaving)
                await OriginDataSync.waitForCurrentPull()
                await BandReadiness.shared.awaitNativeIdle()
                guard !Task.isCancelled else { return }
                self.phase = phase
            }
            await Band.live.disconnect()
            guard !Task.isCancelled else { return }
            var fresh = BandState.unknown
            fresh.name = slots[slot]?.name ?? "NEXTBODY HOOP"
            store.band = fresh
            store.lastSync = slots[slot]?.lastSync
            Repository.shared.adoptTransportDevice(id: slots[slot]?.deviceId)
        }
        // One pull reads the link, today and everything the band still holds. Splitting it
        // in two made the page connect and sync twice for a single tap, and the second pass
        // re-read the days the first had just finished.
        //
        // The handover itself is over as soon as the link is up, so the phase is released
        // there rather than at the end of the read: the strip stops saying CONNECTING and
        // the bar carries the rest.
        let releasing = Task { @MainActor [weak self] in
            for _ in 0..<300 {
                if Task.isCancelled { return }
                if BandSyncActivity.shared.phase == "syncing" { self?.phase = .idle; return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        let result = await OriginDataSync.refreshNow(into: store, request: .fullHistory)
        releasing.cancel()
        guard !Task.isCancelled else { return }
        noteTransportObservation(from: store.band, lastSync: store.lastSync)
        Self.log.notice("move done to=\(slot.rawValue, privacy: .public) result=\(result.status.rawValue, privacy: .public) ms=\(Int(Date().timeIntervalSince(began) * 1000), privacy: .public)")
        Task { [ms = Int(Date().timeIntervalSince(began) * 1000)] in
            await Analytics.shared.track("WEAR_SWITCH_CONNECTED",
                ["SLOT": slot.rawValue, "RESULT": result.status.rawValue, "MS": ms])
        }
        landed = (slot, Date())
    }

    /// If the link is not on the worn band — a handover that failed halfway, an activation
    /// that was interrupted — bring it back. The app talks to the band on your wrist and
    /// nothing else: the other one is read when you next put it on.
    func reconcileTransport(store: DataStore) async {
        guard !isReleasing, !activationGate.isHeld, phase == .idle, handover == nil || handover?.isCancelled == true,
              DeviceSlots.transport != DeviceSlots.wearing,
              DeviceSlots.binding(DeviceSlots.wearing) != nil else { return }
        scheduleHandover(store: store, settling: nil)
        await handover?.value
    }

    // MARK: activation

    enum ActivationStage: Int { case connect = 0, verify, capabilities, activate }

    /// Give the second band its slot: connect, verify, read what it can do, register the
    /// row. The worn band's link is borrowed for the duration and handed back afterwards.
    /// Nothing the new band recorded before this moment enters the timeline.
    func activateSecond(_ device: DiscoveredBand, store: DataStore, owner: UUID,
                        stage: @escaping @MainActor (ActivationStage) -> Void,
                        progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> SlotSnapshot {
        guard !isReleasing, activationGate.owner == owner, let slot = openSlot,
              !DeviceSlots.bindings.contains(where: { $0.identifier == device.id }) else {
            throw DeviceActivationGate.Failure.busy
        }
        let previous = DeviceSlots.transport
        phase = .activating(slot)
        defer { endActivation(owner: owner) }
        // Preparation already drained the old link before scanning began.
        noteTransportObservation(from: store.band, lastSync: store.lastSync)
        await Band.live.disconnect()
        DeviceSlots.set(SlotBinding(slot: slot, identifier: device.id, name: device.name))
        BoundBand.switchTransport(to: slot)
        BandReadiness.shared.invalidateSnapshot()
        transport = slot
        do {
            stage(.connect)
            try await Band.live.connect(device, progress: { p in
                Task { @MainActor in progress(0.35 * p) }
            })
            progress(0.35)
            stage(.verify)
            let identity = try await Band.live.readIdentity()
            progress(0.60)
            stage(.capabilities)
            let caps = try await Band.live.readCapabilities()
            progress(0.85)
            stage(.activate)
            let battery = try await Band.live.readBattery()
            guard await Repository.shared.registerDevice(identity: identity, battery: battery, slot: slot),
                  DeviceSlots.binding(slot)?.deviceId != nil else {
                throw BandError.rejected(L("Pairing could not be saved. Check your connection and try again."))
            }
            if let deviceId = DeviceSlots.binding(slot)?.deviceId,
               let userId = await SupabaseClient.shared.currentUserId {
                await Repository.shared.saveCapabilities(caps, deviceId: deviceId, userId: userId,
                                                          holdsDays: identity.watchDataDayNumber)
            }
            var snap = SlotSnapshot(slot: slot, name: identity.name)
            snap.deviceId = DeviceSlots.binding(slot)?.deviceId
            snap.identifier = device.id
            snap.firmware = identity.firmware
            snap.battery = battery
            snap.batteryReadAt = Date()
            snap.boundAt = DeviceSlots.binding(slot)?.boundAt ?? Date()
            snap.holdsDays = identity.watchDataDayNumber
            slots[slot] = snap
            progress(1.0)
            Task { await Analytics.shared.track("DEVICE_MEMBER_ACTIVATED", ["SLOT": slot.rawValue]) }
        } catch {
            DeviceSlots.remove(slot)
            slots[slot] = nil
            await Band.live.disconnect()
            BoundBand.switchTransport(to: previous)
            BandReadiness.shared.invalidateSnapshot()
            transport = previous
            Repository.shared.adoptTransportDevice(id: slots[previous]?.deviceId)
            Task { await OriginDataSync.refreshNow(into: store, request: .latest) }
            throw error
        }
        // Hand the link back to the worn band. The new band waits on its charger.
        await Band.live.disconnect()
        BoundBand.switchTransport(to: previous)
        BandReadiness.shared.invalidateSnapshot()
        transport = previous
        Repository.shared.adoptTransportDevice(id: slots[previous]?.deviceId)
        timeline = DeviceSlots.timeline
        Task { await OriginDataSync.refreshNow(into: store, request: .latest) }
        return slots[slot]!
    }

    /// The server closes one binding before any local state is removed. A surviving slot
    /// keeps its identity; removing A must not rename B or prevent filling A again.
    func release(_ slot: HoopSlot, store: DataStore) async throws {
        guard !isReleasing, !activationGate.isHeld, phase == .idle else { throw DeviceReleaseError.busy }
        guard !replaying, DeviceSlots.pendingOps.isEmpty else {
            Task { await replayPending() }
            throw DeviceReleaseError.pendingChanges
        }
        guard let id = DeviceSlots.binding(slot)?.deviceId else { throw DeviceReleaseError.bindingUnavailable }
        isReleasing = true
        bindingRevision += 1
        let previous = handover
        var removingTransport = false
        var remainingKey: String?
        do {
            releaseCleanup = try await DeviceReleaseOperation.run(request: {
                try await Repository.shared.releaseDevice(id: id)
            }, publish: { set in
                previous?.cancel()
                handover = nil
                removingTransport = DeviceSlots.transport == slot
                DeviceSlots.remove(slot)
                apply(set)
                remainingKey = BoundBand.identifier
                Repository.shared.adoptTransportDevice(id: slots[DeviceSlots.transport]?.deviceId)
                if removingTransport {
                    BandReadiness.shared.invalidateSnapshot()
                    store.band = .unknown
                    store.lastSync = slots[DeviceSlots.transport]?.lastSync
                }
                if slots.isEmpty {
                    BoundBand.forget()
                    hydrateFromLocal()
                }
                bindingRevision += 1
            }, cleanup: {
                await previous?.value
                if removingTransport {
                    await OriginDataSync.waitForCurrentPull()
                    await BandReadiness.shared.awaitNativeIdle()
                    // A new onboarding pairing may already own the radio.
                    if BoundBand.identifier == remainingKey {
                        await Band.live.disconnect()
                        if !self.slots.isEmpty {
                            self.landed = nil
                            self.scheduleHandover(store: store, settling: nil)
                        }
                    }
                }
                self.isReleasing = false
            })
        } catch {
            isReleasing = false
            bindingRevision += 1
            throw error
        }
    }

    // MARK: helpers

    private static func timestamp(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    private static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }
}
