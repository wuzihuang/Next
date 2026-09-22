import SwiftUI

/// 12X · 04 ACTION TILES. Lime identity slab (HOOP + SYNC + 2×2), then two
/// carbon bricks (Find HOOP / Alarms). No charge numeral on this card.
struct DeviceView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router
    @ObservedObject private var syncActivity = BandSyncActivity.shared
    /// 9-0 A · the two-HOOP set: both slots, the wear timeline, the link moves.
    @ObservedObject private var hoops = DeviceSetStore.shared
    /// The lime ground is one shape that slides between the slots on a declaration.
    @Namespace private var limeSlot

    @State private var sheet: SheetRoute?
    @State private var identity: BandIdentity?

    /// 12 edge 3 · the band clamped a write: what was asked, what it kept.
    @State private var clamped: (name: String, asked: String, got: String)?
    /// 12 edge 4 · a write answered DEVICE_BUSY and is queued behind the measurement.
    @State private var busyQueued = false
    /// 12 edge 5 · the OTA result, three-state.
    @State private var ota: OTAState?
    enum OTAState: Equatable { case running, completed, failed(String), unverified }
    /// What the update server said when the page asked. `offer` nil with `check` settled
    /// means the band is current; a failed check is its own line, never "up to date".
    @State private var offer: FirmwareOffer?
    @State private var check: OTACheck = .idle
    enum OTACheck: Equatable { case idle, checking, done, failed(String) }
    /// 0…1 from the SDK while the file crosses.
    @State private var otaProgress: Double = 0
    /// How often this phone asks the band for the day. Mirrors SyncCadence so the row
    /// re-renders when the sheet changes it.
    @State private var cadence = SyncCadence.minutes
    /// Device SYNC is in flight — the capsule holds a spinner until battery, identity,
    /// and today's origin pull have all come back.
    @State private var syncing = false
    @State private var syncMessage: String?
    /// What Automatic measurement actually read — not a guess from capability bits.
    /// Kept outside DEBUG because Training can still open the sheet in Release.
    @State private var autoRead: AutoMonitoringRead?
    /// After the first new-alarm read. The Alarms brick shows this number, not a guess.
    @State private var alarmCount: Int?
    #if DEBUG
    /// The sport-mode probe sheet. Release builds carry neither the button nor the code.
    @State private var sportProbe = false
    @State private var capabilitySweep = false
    #endif

    private var connected: Bool { data.band.connected }
    /// The state chosen on the sheet, mirrored here so the row follows the sheet's writes.
    @AppStorage(BandHealthLightPreference.key) private var healthLightRaw: Int = -1
    private var syncInProgress: Bool { syncing || syncActivity.phase != "idle" }
    private var connectingForSync: Bool { syncActivity.phase == "connecting" }

    var body: some View {
        DetailScroll(glow: NB.lime1, title: L("DEVICE"), trailing: {
            HStack(spacing: 7) {
                Circle().fill(connected ? NB.lime1 : NB.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                // The pill names the band on the link (A/B); the lime slab names the worn one.
                Text(connected ? L("CONNECTED") + (hoops.hasSecond ? " · \(hoops.transport.rawValue)" : "")
                               : L("DISCONNECTED"))
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(connected ? NB.lime1 : NB.text3Prod)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .overlay(connected ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // 9-0 A · slots never move: A above, B below. The lime moves with the
                // declaration — that is the only thing that changes places.
                VStack(alignment: .leading, spacing: 18) {
                    slotSlab(.a)
                    if hoops.hasSecond { slotSlab(.b) } else { emptySlotSlab }
                }
                .animation(.spring(duration: 0.65, bounce: 0.12), value: hoops.wearing)
                actionTiles
                if hoops.hasSecond {
                    GroupLabel12(L("WEARING"))
                    RowCard {
                        DestructiveRow(title: countedFromTitle, detail: countedFromDetail,
                                       tint: NB.text1, last: true) { sheet = .wearCorrect }
                    }
                }
                if let syncMessage {
                    Text(syncMessage)
                        .font(NBFont.ui(400, 12))
                        .foregroundStyle(NB.ember1)
                        .accessibilityIdentifier("device-sync-message")
                }
                if !connected { readOnlyNotice }
                if busyQueued { busyCard }
                if let clamped { clampCard(clamped) }

                GroupLabel12(L("FIRMWARE"))
                RowCard { firmwareSection }

                #if DEBUG
                debugHeader
                debugCard
                #endif

                GroupLabel12(L("CONNECTION"))
                RowCard {
                    if connected {
                        DestructiveRow(title: L("Disconnect"),
                                       detail: L("It keeps recording. Nothing reaches the app."),
                                       tint: NB.text1) { sheet = .disconnect }
                    } else {
                        DestructiveRow(title: L("Why won't it connect?"),
                                       detail: L("Bluetooth, distance, or a flat battery."),
                                       tint: NB.text1) { sheet = .findBand }
                    }
                    if hoops.hasSecond {
                        DestructiveRow(title: L("Remove a HOOP"),
                                       detail: L("Choose one to remove. Your other HOOP and history stay."),
                                       tint: NB.alert2, last: true) { sheet = .releaseSet }
                            .accessibilityIdentifier("device.removeHoop")
                    } else {
                        DestructiveRow(title: L("Forget this HOOP"),
                                       detail: L("Removes it from this phone. Your history stays."),
                                       tint: NB.alert2, last: true) { sheet = .unbind }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.back()
        }
        .task {
            #if DEBUG
            if Band.allowsSeed, let raw = ProcessInfo.processInfo.environment["NB_DEBUG_SYNC_STAGE"],
               let stage = BandSyncProgress.Stage(rawValue: raw) {
                syncActivity.beginCounting()
                syncActivity.phase = "connecting"
                if stage == .reading || stage == .updating || stage == .complete {
                    syncActivity.phase = "syncing"
                    syncActivity.reportRead(day: 3, of: 3, percent: 100)
                }
                if stage == .complete { syncActivity.complete(success: true) }
                else if stage == .updating { syncActivity.updatingResults() }
                else { syncActivity.show(stage) }
                return
            }
            if let raw = ProcessInfo.processInfo.environment["NB_DEBUG_SYNC_PROGRESS"] {
                syncing = true
                if let n = Int(raw) {
                    BandSyncActivity.shared.debugShow(done: n, total: 9)
                } else if raw.contains(":"), let n = Int(raw.split(separator: ":")[0]),
                          let within = Int(raw.split(separator: ":")[1]) {
                    // `=3:50` · half way through the fourth day, the movement a pull now
                    // makes between one day and the next.
                    BandSyncActivity.shared.debugShow(done: n, total: 9)
                    BandSyncActivity.shared.within(percent: within)
                } else {
                    // `=connecting` · no size yet, which is the state the bar used to draw
                    // as a stuck zero.
                    BandSyncActivity.shared.beginCounting()
                    BandSyncActivity.shared.phase = "connecting"
                }
            }
            #endif
            await hoops.load()
            #if DEBUG
            // `NB_DEBUG_SWITCH=B,A,B` taps the switch for you, 1.2 s apart, so the rapid
            // case can be walked and read back from the log.
            if let script = ProcessInfo.processInfo.environment["NB_DEBUG_SWITCH"] {
                let slots = script.split(separator: ",").compactMap { HoopSlot(rawValue: String($0)) }
                Task { @MainActor in
                    let gap = ProcessInfo.processInfo.environment["NB_DEBUG_SWITCH_MS"].flatMap(Int.init) ?? 1200
                    for slot in slots {
                        try? await Task.sleep(for: .milliseconds(gap))
                        await hoops.declareWearing(slot, store: data)
                    }
                }
            }
            #endif
            hoops.noteTransportObservation(from: data.band, lastSync: data.lastSync)
            hoops.noteHoldsDays(identity?.watchDataDayNumber, slot: hoops.transport)
            await hoops.reconcileTransport(store: data)
        }
        .onChange(of: data.band) { _, band in
            hoops.noteTransportObservation(from: band, lastSync: data.lastSync)
        }
        .onChange(of: identity?.watchDataDayNumber) { _, days in
            hoops.noteHoldsDays(days, slot: hoops.transport)
        }
        .onReceive(router.$deviceSheetRequest) { request in
            guard let request else { return }
            sheet = request
            router.deviceSheetRequest = nil
        }
        #if DEBUG
        .onAppear {
            if let s = ProcessInfo.processInfo.environment["NB_DEBUG_DEVICE_SHEET"] {
                switch s {
                case "findHoop": sheet = .findHoop
                case "bandAlarms": sheet = .bandAlarms
                case "bandAutoMonitor": sheet = .bandAutoMonitor
                case "healthLight": sheet = .healthLight
                case "activateSecond": sheet = .activateSecond
                case "wearSwitch": sheet = .wearSwitch(hoops.wearing.other.rawValue)
                case "wearCorrect": sheet = .wearCorrect
                case "releaseSet": sheet = .releaseSet
                default: break
                }
            }
        }
        #endif
        .task {
            if DebugEdge.on("disconnected") {
                data.band.connected = false
            }
            if DebugEdge.on("clamped") { clamped = ("Heart rate alarm", "50–140 BPM", "50–130 BPM") }
            if DebugEdge.on("busy") { busyQueued = true }
            if DebugEdge.on("otaunverified") { ota = .unverified }
            if DebugEdge.on("otarunning") {
                ota = .running
                otaProgress = 0.42
            }
            if DebugEdge.on("otacompleted") { ota = .completed }
            if DebugEdge.on("otafailed") { ota = .failed("The band moved out of range") }
            if DebugEdge.on("levelonly") {
                data.applyBandObservation(battery: BandBattery(isPercent: false, percent: nil, level: 3, chargeState: .unplugged))
            }
            if router.path.last == .deviceAutoMonitor {
                sheet = .bandAutoMonitor
            }
            await Analytics.shared.track("DEVICE_PAGE_OPEN", ["CONNECTED": connected])
            // WITH YOU reads the earliest bind or wrist tick, not firmware saveDays
            // and not the latest devices row after a radio swap. Refresh even when
            // the radio is down — companionship does not need a live link.
            await Repository.shared.loadLastSync(into: data)
            guard connected, !BandLiveLifecycle.shared.hasExclusiveOperation else { return }
            // Seeded BandState is already CONNECTED; the mock radio may still be idle.
            // Ask it to come up before the firmware identity rows stay dashes.
            if Band.live.state != .connected {
                guard await BandReadiness.shared.ensureReady(into: data, reason: "device-page") else { return }
            }
            if !DebugEdge.on("levelonly"), let fresh = try? await readDevice({ try await Band.live.readBattery() }) {
                data.applyBandObservation(battery: fresh)
            }
            identity = try? await readDevice { try await Band.live.readIdentity() }
            if let identity { data.applyBandObservation(identity: identity) }
            if let fresh = try? await readDevice({ try await Band.live.readCapabilities() }) {
                data.capabilities = fresh
                if let deviceId = Repository.shared.deviceId,
                   let userId = await SupabaseClient.shared.currentUserId {
                    await Repository.shared.saveCapabilities(fresh, deviceId: deviceId, userId: userId,
                                                             holdsDays: identity?.watchDataDayNumber)
                }
            }
            await checkForUpdate()
            if let list = try? await readDevice({ try await Band.live.readAlarms() }) {
                alarmCount = list.count
                PhoneToolRunner.shared.remember(list)
            }
            #if DEBUG
            if let s = ProcessInfo.processInfo.environment["NB_DEBUG_DEVICE_SHEET"] {
                switch s {
                case "findHoop": sheet = .findHoop
                case "bandAlarms": sheet = .bandAlarms
                case "bandAutoMonitor": sheet = .bandAutoMonitor
                case "healthLight": sheet = .healthLight
                case "activateSecond": sheet = .activateSecond
                case "wearSwitch": sheet = .wearSwitch(hoops.wearing.other.rawValue)
                case "wearCorrect": sheet = .wearCorrect
                case "releaseSet": sheet = .releaseSet
                default: break
                }
            }
            #endif
            await OriginDataSync.refreshNow(into: data)
            do {
                autoRead = try await readDevice { try await Band.live.readAutoMonitoring() }
                rememberOpticalSwitch(autoRead)
                if let autoRead { PhoneToolRunner.shared.remember(read: autoRead) }
            } catch {
                autoRead = .failed(error)
            }
            #if DEBUG
            if DebugEdge.on("otarunning") {
                ota = .running
                otaProgress = 0.42
            }
            if DebugEdge.on("otacompleted") { ota = .completed }
            if DebugEdge.on("otafailed") { ota = .failed("The band moved out of range") }
            #endif
        }
        .onChange(of: connected) { _, on in
            guard on else { autoRead = nil; return }
            guard !BandLiveLifecycle.shared.hasExclusiveOperation else { return }
            Task {
                if !DebugEdge.on("levelonly"), let fresh = try? await readDevice({ try await Band.live.readBattery() }) {
                    data.applyBandObservation(battery: fresh)
                }
                if identity == nil, let fresh = try? await readDevice({ try await Band.live.readIdentity() }) {
                    identity = fresh
                    data.applyBandObservation(identity: fresh)
                }
                if check == .idle { await checkForUpdate() }
                if let list = try? await readDevice({ try await Band.live.readAlarms() }) {
                    alarmCount = list.count
                }
                do {
                    autoRead = try await readDevice { try await Band.live.readAutoMonitoring() }
                    rememberOpticalSwitch(autoRead)
                } catch {
                    autoRead = .failed(error)
                }
            }
        }
        .sheet(item: $sheet) { r in
            Group {
                switch r {
                case .bandAutoMonitor: AutoMeasurementSheet(initial: autoRead) { autoRead = $0 }
                case .syncCadence:     SyncCadenceSheet(minutes: $cadence)
                case .unbind:          ReleaseSetSheet(initialSlot: hoops.wearing)
                case .disconnect:      DisconnectSheet()
                case .findBand:        WhyWontItConnectSheet()
                case .findHoop:        FindHoopSheet()
                case .activateSecond:  ActivateSecondSheet()
                case .wearSwitch(let raw):
                    WearSwitchSheet(to: HoopSlot(rawValue: raw) ?? hoops.wearing.other)
                case .wearCorrect:     WearCorrectSheet()
                case .releaseSet:      ReleaseSetSheet()
                case .bandAlarms:      AlarmsSheet { alarmCount = $0 }
                #if DEBUG
                case .healthLight:     HealthLightSheet()
                #endif
                default:               WhyWontItConnectSheet()
                }
            }
            .presentationDetents([.fraction(Self.sheetFraction(r))])
            .presentationDragIndicator(.visible)
            .presentationBackground(NB.carbon2)
            .presentationCornerRadius(NB.R.panel)
        }
        #if DEBUG
        .sheet(isPresented: $sportProbe) {
            SportProbeSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(NB.carbon2)
                .presentationCornerRadius(NB.R.panel)
        }
        .sheet(isPresented: $capabilitySweep) {
            CapabilitySweepSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(NB.carbon2)
                .presentationCornerRadius(NB.R.panel)
        }
        #endif
    }

    /// 12 edge 3 · WRITE CLAMPED · RENDER THE READBACK.
    private func clampCard(_ c: (name: String, asked: String, got: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(c.name).font(NBFont.ui(500, 14)).foregroundStyle(NB.text1)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(c.got).font(NBFont.dot(700, 22)).tracking(0.02 * 22).foregroundStyle(NB.text1)
                Text(L("YOU ASKED FOR %@", c.asked)).font(NBFont.dot(500, 11)).tracking(0.06 * 11)
                    .foregroundStyle(NB.ember1.opacity(0.85))
            }
            Text(L("THE BAND SET WHAT IT COULD. THIS IS ITS ANSWER, NOT OURS."))
                .font(NBFont.ui(300, 11)).tracking(0.04 * 11).foregroundStyle(NB.text3Prod)
        }
        .padding(14)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    /// 12 edge 4 · DEVICE BUSY · QUEUE, DON'T FAIL.
    private var busyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("DEVICE BUSY")).font(NBFont.dot(700, 11)).tracking(0.14 * 11).foregroundStyle(NB.ember1)
            Text(L("A measurement is running. Your change is queued and will go through when it finishes."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5).lineSpacing(5).foregroundStyle(NB.white.opacity(0.70))
        }
        .padding(14)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous).stroke(NB.ember1.opacity(0.25), lineWidth: 1))
    }

    /// Page reads participate in the same drain as sync. A page task resumed after a
    /// pairing sheet opens cannot enqueue a stale command against the borrowed link.
    private func readDevice<T>(_ work: () async throws -> T) async throws -> T {
        guard let account = SupabaseClient.currentUserIdSnapshot(), let binding = BoundBand.identifier else {
            throw CancellationError()
        }
        return try await BandReadiness.read(account: account, binding: binding, work: work)
    }

    /// Ask the update server; a failed check never promises an up-to-date band.
    private func checkForUpdate() async {
        guard connected, check != .checking else { return }
        check = .checking
        do {
            offer = try await readDevice { try await Band.live.checkFirmwareUpdate() }
            check = .done
        } catch {
            offer = nil
            check = .failed(error.localizedDescription)
        }
        await Analytics.shared.track("DEV_OTA_CHECK", ["OFFER": offer?.version ?? "none", "OK": check == .done])
    }

    /// 12 rule 08 · the update runs, and the result is one of three.
    private func runUpdate() {
        guard let offer else { return }
        Task {
            ota = .running
            otaProgress = 0
            await Analytics.shared.track("DEV_OTA_START", ["FROM": identity?.firmware ?? data.band.firmware, "TO": offer.version])
            let t0 = Date()
            let result: FirmwareUpdateResult
            do {
                result = try await Band.live.updateFirmware(to: offer.version) { p in
                    Task { @MainActor in otaProgress = p }
                }
            } catch {
                result = .failed(reason: "\(error)")
            }
            switch result {
            case .completed(let v):
                ota = .completed
                data.band.firmware = v
                if let refreshed = try? await Band.live.readIdentity() {
                    identity = refreshed
                    data.applyBandObservation(identity: refreshed)
                }
            case .failed(let why):    ota = .failed(why)
            case .versionUnverified:  ota = .unverified
            }
            await Analytics.shared.track("DEV_OTA_END", ["RESULT": "\(result)", "MS": Int(Date().timeIntervalSince(t0) * 1000)])
        }
    }

    /// Only what this HOOP actually reported for automatic measurement.
    private var autoDetail: String {
        guard connected else { return L("CONNECT TO READ") }
        guard let autoRead else { return L("ASKING THIS HOOP") }
        let slots = autoRead.slots
        if !slots.isEmpty {
            return slots.map { L(Self.autoShort($0.kind)) }.joined(separator: " · ")
        }
        switch autoRead {
        case .interval:
            return L("NOT REPORTED")
        case .switches:
            return L("INTERVAL IS FIRMWARE-OWNED")
        case .failed:
            return L("COULD NOT READ")
        }
    }
    private var autoValue: String {
        guard let autoRead else { return "—" }
        let n = autoRead.slots.count
        return n == 0 ? "—" : "\(n)"
    }
    private static func autoShort(_ kind: AutoMonitorSlot.Kind) -> String {
        switch kind {
        case .heartRate:       "HR"
        case .bloodPressure:   "BP"
        case .bloodGlucose:    "RESP"
        case .stress:          "STRESS"
        case .bloodOxygen:     "SPO2"
        case .temperature:     "TEMP"
        case .lorentz:         "LORENTZ"
        case .hrv:             "HRV"
        case .scientificSleep: "SLEEP"
        case .bloodComponents: "BLOOD"
        }
    }

    /// SYNC stays actionable off-link: it first reconnects the bound HOOP.
    private var deviceSyncButton: some View {
        Button {
            Task { await pullBandNow() }
        } label: {
            HStack(spacing: 6) {
                if syncActivity.workflow.active {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NB.lime1)
                }
                Text(syncActivity.workflow.active ? L(syncActivity.workflow.stage.buttonLabel) : L("SYNC"))
                    .font(NBFont.ui(600, 11)).tracking(0.12 * 11)
                    .foregroundStyle(NB.lime1)
            }
            .frame(minWidth: 40)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(NB.carbon4, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .layoutPriority(1)
        .disabled(BoundBand.identifier == nil || syncing)
        .accessibilityLabel(L("Sync now"))
        .accessibilityHint(L("Connect this HOOP if needed, then pull the latest readings."))
        .accessibilityValue(syncActivity.workflow.active ? L(syncActivity.workflow.stage.label) : "")
    }

    /// The shared refresh owns readiness, admission, history and the actual completion.
    private func pullBandNow() async {
        guard !syncing else { return }
        syncMessage = nil
        syncing = true
        defer { syncing = false }
        Task { await Analytics.shared.track("DEV_SYNC_TAP", ["CONNECTED": connected]) }
        let result = await OriginDataSync.refreshNow(into: data, request: .fullHistory)
        guard !Task.isCancelled else { return }
        switch result.status {
        case .success:
            identity = BandReadiness.shared.snapshot?.identity
        case .consentRequired:
            router.takeover = .consent
        case .signedOut:
            syncMessage = L("Sign in to sync this HOOP.")
        case .busy:
            syncMessage = L("Finish the current measurement or device operation, then sync again.")
        case .disconnected, .unbound:
            let snap = hoops.snapshot(hoops.wearing)
            syncMessage = (snap?.isFlat == true || snap?.isLow == true)
                ? L("Could not reach this HOOP. It was nearly out of charge when last read — put it on its charger, then tap Sync.")
                : L("Could not reach this HOOP. Keep it nearby, check Bluetooth, then tap Sync to try again.")
        case .partial:
            syncMessage = syncActivity.failureLine ?? L("Some readings could not sync. Tap Sync to try again.")
        case .failed:
            syncMessage = syncActivity.failureLine ?? L("Sync did not complete. Tap Sync to try again.")
        case .cancelled, .throttled:
            break
        }
    }

    private var leftParts: (value: String, unit: String)? {
        guard let left = BatteryDrainMath.left(in: data.batteryLog, now: Date()) else {
            return nil
        }
        switch left {
        case .hours(let n): return ("\(n)", L(n == 1 ? "HR LEFT" : "HRS LEFT"))
        case .days(let n): return ("\(n)", L(n == 1 ? "DAY LEFT" : "DAYS LEFT"))
        }
    }

    private var glancePlot: BatteryPlot {
        let window = BatteryLog.window(endingAt: Date(), days: 7)
        return BatteryLog.plot(data.batteryLog, from: window.start, to: window.end)
    }

    // MARK: 9-0 A · the set

    /// What the record counts from, and who decided it. The switch itself is the other
    /// HOOP's card; this row exists only to correct a start the app worked out.
    private var countedFromTitle: String {
        guard let since = hoops.wearingSince else { return L("Tap the other HOOP to switch") }
        return L("Counted from") + " " + Self.stamp(since)
    }

    private var countedFromDetail: String {
        guard hoops.wearingSince != nil else { return L("Your record follows the one you name.") }
        return hoops.wearingInferred
            ? L("HOOP") + " \(hoops.wearing.rawValue) " + L("worked this out. Tap if you put it on earlier.")
            : L("You set this time. Tap to change it.")
    }

    /// A deadline in a sentence carries its day: `today 13:52`, `tomorrow 09:00`, `Sep 17`.
    private static func dayStamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("today") + " " + stamp(date) }
        if calendar.isDateInTomorrow(date) { return L("tomorrow") + " " + stamp(date) }
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: date)
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(date) ? "HH:mm" : "MMM d HH:mm")
        return f.string(from: date)
    }

    /// One slot: lime when it is the declared wearer, carbon otherwise. Same position
    /// either way — only the colour and the strip word change.
    @ViewBuilder private func slotSlab(_ slot: HoopSlot) -> some View {
        if slot == hoops.wearing {
            limeHero(slot)
                .transition(.opacity)
        } else {
            standbySlab(slot)
                .transition(.opacity)
        }
    }

    /// The state line at the top of a slab: the slot letter, the strip word, since when.
    /// The link's whereabouts is the pill; this strip is the declaration. 50pt, not 34:
    /// a 28pt key inside 34 left three points of air and read as a seam.
    private func slotStrip(_ slot: HoopSlot, onLime: Bool) -> some View {
        HStack(spacing: 10) {
            HoopKeyGlyph(letter: slot.rawValue, onLime: onLime)
            Text(onLime ? stripWord : standbyWord(hoops.snapshot(slot), pending: pendingDays(slot)))
                .font(NBFont.dot(600, 10.5)).tracking(0.2 * 10.5)
                .foregroundStyle(onLime ? NB.carbon4 : (pendingDays(slot) > 0 ? NB.ember1 : NB.white.opacity(0.55)))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if onLime, syncActivity.total > 0 {
                Text("\(syncActivity.done) / \(syncActivity.total) " + L("DAYS"))
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.carbon4.opacity(0.7))
                    .contentTransition(.numericText())
            } else if onLime, let since = hoops.wearingSince {
                Text(L("SINCE") + " " + Self.stamp(since).uppercased())
                    .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.carbon4.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .overlay(alignment: .bottom) {
            Rectangle().fill(onLime ? NB.carbon4.opacity(0.15) : NB.white.opacity(0.08)).frame(height: 1)
        }
        .accessibilityIdentifier("device.slotStrip.\(slot.rawValue)")
    }

    /// What the bar is doing. Connecting has no count yet; a day count only appears once
    /// the band has said how many days it still holds.
    private var syncProgressWord: String {
        syncActivity.progressLine
    }

    private func pendingDays(_ slot: HoopSlot) -> Int {
        let snap = hoops.snapshot(slot)
        return WearTimeline.pendingDays(lastSync: snap?.lastSync, boundAt: snap?.boundAt,
                                        now: Date(), holdsDays: snap?.holdsDays)
    }

    /// The strip and the chrome pill must never contradict each other: the pill is the
    /// link, so once it says CONNECTED the strip stops saying CONNECTING and names what
    /// the link is actually doing.
    private var stripWord: String {
        switch hoops.phase {
        // PRD W2 · the band being left finishes the command it is on. Saying CONNECTING
        // here would be a lie: the link is still on the other HOOP.
        case .finishing(let s):
            return L("FINISHING") + " \(s.rawValue) · " + L("THEN") + " \(hoops.wearing.rawValue)"
        case .switching(let s) where s == hoops.wearing:
            return connected ? L("WEARING · SYNCING") : L("WEARING · CONNECTING")
        case .activating:
            return L("WEARING · LINK AWAY")
        default:
            if connected && hoops.transport == hoops.wearing {
                // The bar under this strip says CONNECTING while the link is being
                // prepared; the strip must not claim reading has started.
                if connectingForSync { return L("WEARING · CONNECTING") }
                return syncInProgress ? L("WEARING · SYNCING") : L("WEARING")
            }
            // A flat band is not a Bluetooth problem, and saying so sends people to
            // the wrong fix.
            if hoops.isFlat(hoops.wearing) { return L("WEARING · FLAT") }
            return L("WEARING · NOT CONNECTED")
        }
    }

    /// The other HOOP: what it last said, when it was last read, and its own SYNC key.
    /// Nothing here is live — the app talks to one band at a time.
    private func standbySlab(_ slot: HoopSlot) -> some View {
        let snap = hoops.snapshot(slot)
        let deadline = WearTimeline.syncDeadline(lastSync: snap?.lastSync, boundAt: snap?.boundAt,
                                                 holdsDays: snap?.holdsDays)
        // The whole card is the switch. It carries no SYNC key of its own: the app talks
        // to the band on your wrist, and this one is read when you put it on.
        return Button { sheet = .wearSwitch(slot.rawValue) } label: {
          VStack(alignment: .leading, spacing: 0) {
            slotStrip(slot, onLime: false)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snap?.name ?? "NEXTBODY HOOP")
                        .font(NBFont.ui(600, 22)).tracking(-0.03 * 22)
                        .foregroundStyle(NB.text1)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(standbyPlan(snap, pending: pendingDays(slot), deadline: deadline))
                        .font(NBFont.ui(400, 12)).tracking(0.01 * 12)
                        .foregroundStyle(standbyAtRisk(pending: pendingDays(slot), deadline: deadline)
                                         ? NB.ember1 : NB.white.opacity(0.42))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Chevron()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 17)
            Hairline().padding(.horizontal, 16)
            HStack(spacing: 0) {
                standbyCell(L("BATTERY"), standbyBattery(snap))
                Rectangle().fill(NB.white.opacity(0.08)).frame(width: 1)
                standbyCell(L("LAST SYNC"), snap?.lastSync.map { Self.stamp($0).uppercased() } ?? L("NEVER"))
                Rectangle().fill(NB.white.opacity(0.08)).frame(width: 1)
                standbyCell(L("SYNC BEFORE"), deadline.map { Self.stamp($0).uppercased() } ?? Fmt.dash)
            }
            .frame(height: 56)
          }
          .frame(width: NB.Layout.contentWidth)
          .cardSkin()
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("device.standbySlab")
    }

    private func standbyWord(_ snap: DeviceSetStore.SlotSnapshot?, pending: Int) -> String {
        if case .activating = hoops.phase { return L("ACTIVATING") }
        if snap?.isFlat == true { return L("FLAT") }
        if pending > 0 { return L("PENDING") + " \(pending) " + L(pending == 1 ? "DAY" : "DAYS") }
        if snap?.isLow == true { return L("LOW") }
        switch snap?.battery?.chargeState {
        case .charging?: return L("CHARGING")
        case .full?: return L("CHARGED · READY")
        default: return L("READY")
        }
    }

    /// One sentence under the name: what happens to this band's days, and by when.
    /// 4 · a band that has gone flat records nothing, so "wear it" is not the answer.
    private func standbyPlan(_ snap: DeviceSetStore.SlotSnapshot?, pending: Int, deadline: Date?) -> String {
        if snap?.isFlat == true { return L("It is out of charge and recording nothing. Charge it.") }
        if standbyAtRisk(pending: pending, deadline: deadline), let deadline {
            return L("Wear it before") + " " + Self.dayStamp(deadline) + " " + L("or its oldest days are gone.")
        }
        if pending > 0 { return L("What it recorded syncs when you put it on.") }
        if snap?.isLow == true { return L("Nearly out of charge. Top it up before you swap.") }
        return L("Waiting on its charger. Tap to wear it instead.")
    }

    /// The firmware only keeps so many days. Inside the last day of that window the
    /// oldest unsynced day is about to be overwritten.
    private func standbyAtRisk(pending: Int, deadline: Date?) -> Bool {
        guard pending > 0, let deadline else { return false }
        return Date() > deadline.addingTimeInterval(-86_400)
    }

    private func standbyBattery(_ snap: DeviceSetStore.SlotSnapshot?) -> String {
        guard let battery = snap?.battery else { return Fmt.dash }
        if let p = battery.percent, battery.isPercent { return "\(p)%" }
        if let level = battery.level { return L("LEVEL") + " \(level)" }
        return Fmt.dash
    }

    private func standbyCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(NBFont.dot(500, 9)).tracking(0.2 * 9)
                .foregroundStyle(NB.white.opacity(0.34))
            Text(value)
                .font(NBFont.dot(600, 12)).tracking(0.06 * 12)
                .foregroundStyle(NB.text1)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The only entry for the second HOOP (§03.3 step 5): a dashed empty slot on DEVICE.
    private var emptySlotSlab: some View {
        Button { sheet = .activateSecond } label: {
            HStack(spacing: 12) {
                HoopKeyGlyph(letter: hoops.openSlot?.rawValue ?? "B")
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Add your second HOOP"))
                        .font(NBFont.ui(600, 16)).tracking(-0.02 * 16)
                        .foregroundStyle(NB.text1)
                    Text(L("KEEP WEARING. CHARGE THE OTHER."))
                        .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.white.opacity(0.4))
                }
                Spacer(minLength: 0)
                Chevron()
            }
            .padding(16)
            .frame(minHeight: 72)
            .frame(width: NB.Layout.contentWidth, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(NB.white.opacity(0.22)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(BoundBand.identifier == nil)
        .accessibilityIdentifier("device.addSecond")
    }

    /// Name + SYNC, 12 BRIDGE TREND lead corridor, then WORN / WITH YOU / SYNCED / LAST POINT.
    private func limeHero(_ slot: HoopSlot) -> some View {
        VStack(spacing: 0) {
            if hoops.hasSecond { slotStrip(slot, onLime: true) }
            HStack(alignment: .center, spacing: 12) {
                Text(hoops.hasSecond ? (hoops.snapshot(slot)?.name ?? data.band.name) : data.band.name)
                    .font(NBFont.ui(600, 26))
                    .tracking(-0.03 * 26)
                    .foregroundStyle(NB.carbon4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                deviceSyncButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)

            // The band answers one day at a time and the SDK sets that pace, so the honest
            // thing to show is how far the read has got, not a speed.
            if syncActivity.showsProgress {
                VStack(alignment: .leading, spacing: 6) {
                    DottedProgress(progress: syncActivity.fraction,
                                   lit: NB.carbon4, track: NB.carbon4.opacity(0.18))
                        .frame(height: 6)
                        .animation(.linear(duration: 0.15), value: syncActivity.fraction)
                    Text(syncProgressWord)
                        .font(NBFont.dot(600, 9.5)).tracking(0.18 * 9.5)
                        .foregroundStyle(NB.carbon4.opacity(0.62))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.opacity)
                .accessibilityIdentifier("device.syncProgress")
            }

            Button {
                router.open(.battery, from: router.entry)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(L("TREND"))
                                .font(NBFont.dot(700, 11))
                                .tracking(0.20 * 11)
                                .foregroundStyle(NB.carbon4)
                            Text("· " + L("7D DRAIN CURVE"))
                                .font(NBFont.ui(600, 11))
                                .tracking(0.04 * 11)
                                .foregroundStyle(NB.carbon4.opacity(0.62))
                        }
                        Spacer(minLength: 0)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if let leftParts {
                                Text(leftParts.value)
                                    .font(NBFont.dot(700, 15))
                                    .foregroundStyle(NB.carbon4)
                                Text(leftParts.unit)
                                    .font(NBFont.dot(600, 10))
                                    .tracking(0.08 * 10)
                                    .foregroundStyle(NB.carbon4.opacity(0.65))
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(NB.carbon4.opacity(0.50))
                                .padding(.leading, 2)
                        }
                    }
                    LimeTrendLead(plot: glancePlot)
                        .frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("device.trend")
            .accessibilityLabel(L("TREND"))
            .accessibilityValue(leftParts.map { "\($0.value) \($0.unit)" } ?? "")

            Rectangle().fill(NB.carbon4.opacity(0.15)).frame(height: 1)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    LimeMetric(label: L("WORN"), value: wornParts.value, unit: wornParts.unit)
                    Rectangle().fill(NB.carbon4.opacity(0.15)).frame(width: 1)
                    LimeMetric(label: L("WITH YOU"), value: companionParts.value, unit: companionParts.unit)
                }
                Rectangle().fill(NB.carbon4.opacity(0.15)).frame(height: 1)
                HStack(spacing: 0) {
                    LimeMetric(label: L("SYNCED"), value: syncedParts.value, unit: syncedParts.unit)
                    Rectangle().fill(NB.carbon4.opacity(0.15)).frame(width: 1)
                    LimeMetric(label: L("LAST POINT"), value: lastPointValue)
                }
            }
        }
        .frame(width: NB.Layout.contentWidth)
        .background {
            RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
                .fill(NB.lime1)
                .matchedGeometryEffect(id: "wearingLime", in: limeSlot)
        }
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.lime1, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
    }

    /// Two carbon bricks cut from one die: lime eyebrow, 18pt title, the same 14pt gap.
    /// The alarm count rides the eyebrow (`CLOCK · 2`) so both bricks keep one height.
    private var actionTiles: some View {
        HStack(spacing: 10) {
            Button { sheet = .findHoop } label: {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("PING"))
                        .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.lime1)
                    Text(L("Find HOOP"))
                        .font(NBFont.ui(600, 18))
                        .tracking(-0.02 * 18)
                        .foregroundStyle(NB.text1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cardSkin()
            .accessibilityIdentifier("device.findHoop")

            Button { sheet = .bandAlarms } label: {
                VStack(alignment: .leading, spacing: 14) {
                    Text(alarmCount.map { L("CLOCK") + " · \($0)" } ?? L("CLOCK"))
                        .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.lime1)
                    Text(L("Alarms"))
                        .font(NBFont.ui(600, 18))
                        .tracking(-0.02 * 18)
                        .foregroundStyle(NB.text1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cardSkin()
            .accessibilityIdentifier("device.alarms")
        }
        .frame(width: NB.Layout.contentWidth)
    }

    /// How much of the screen a sheet takes. A table or a picture wants the tall detent,
    /// a confirmation wants only the room its own sentence needs.
    private static func sheetFraction(_ route: SheetRoute) -> CGFloat {
        switch route {
        case .bandAutoMonitor, .findHoop, .bandAlarms, .healthLight, .activateSecond: return 0.78
        case .wearCorrect:  return 0.74
        case .releaseSet:   return 0.82
        // 9-0 A·S8 · a question, the HOOP it names, and one key.
        case .wearSwitch:   return 0.55
        default:            return 0.62
        }
    }

    /// Consecutive worn days from the same flame the home header uses. Amber / gray
    /// is a miss, not a zero.
    private var wornParts: (value: String, unit: String?) {
        switch data.wearFlame {
        case .live(let n): return ("\(n)", L("DAYS"))
        case .amber, .gray: return (Fmt.dash, nil)
        }
    }

    /// Inclusive user days from the earliest bind or wrist tick. Firmware saveDays never land here.
    private var companionParts: (value: String, unit: String?) {
        guard let n = DeviceCompanionMath.days(boundAt: data.boundAt, now: Date()) else {
            return (Fmt.dash, nil)
        }
        return ("\(n)", L("DAYS"))
    }

    /// Same timestamp as the home panel. The lime cell splits the number from the unit
    /// the way the board does — NEVER / JUST NOW stay a single value.
    private var syncedParts: (value: String, unit: String?) {
        guard let at = data.lastSync else { return (L("NEVER"), nil) }
        let mins = max(0, Int(Date().timeIntervalSince(at) / 60))
        if mins < 1 { return (L("JUST NOW"), nil) }
        if mins < 60 { return ("\(mins)", L("MIN")) }
        return ("\(mins / 60)", L("HRS"))
    }

    private var lastPointValue: String {
        data.vitals.at.map(Fmt.clock) ?? Fmt.dash
    }

    /// Version, offer, CHECK / UPDATE, then the identity rows the board lists.
    /// DEVICE NO. is not a firmware fact — it stays in DEBUG.
    private var firmwareSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ota == .unverified ? L("VERSION UNCONFIRMED") : L("VERSION"))
                        .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                        .foregroundStyle(ota == .unverified ? NB.ember1 : NB.text3Prod)
                    HStack(spacing: 8) {
                        Text(reportedFirmware)
                            .font(NBFont.dot(700, 22)).tracking(0.04 * 22)
                            .foregroundStyle(NB.text1)
                        if let offer, ota != .completed {
                            Text(ota == .unverified ? L("?") : L("→"))
                                .font(NBFont.dot(700, 13))
                                .foregroundStyle(ota == .unverified ? NB.ember1 : NB.lime1)
                            Text(offer.version)
                                .font(NBFont.dot(700, 22)).tracking(0.04 * 22)
                                .foregroundStyle(ota == .unverified ? NB.macroValue : NB.lime1)
                        }
                    }
                    Text(otaLine)
                        .font(NBFont.ui(400, 12)).tracking(0.02 * 12).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(ota == .completed ? NB.lime1 : NB.text3Prod)
                }
                Spacer(minLength: 0)
                if offer != nil || (connected && check != .checking && ota != .completed) {
                    Button(action: { if offerInstallable { runUpdate() } else { Task { await checkForUpdate() } } }) {
                        Text(otaButton)
                            .font(NBFont.ui(600, 11)).tracking(0.12 * 11)
                            .foregroundStyle(connected && offerInstallable ? NB.carbon : NB.text2)
                            .padding(.horizontal, 18).frame(height: 36)
                            .background(connected && offerInstallable ? NB.lime1 : Color.clear, in: Capsule())
                            .overlay(connected && offerInstallable ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!connected || ota == .running || ota == .completed)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            if ota == .running {
                ZStack(alignment: .leading) {
                    Capsule().fill(NB.barTrack)
                    Capsule().fill(NB.lime1)
                        .frame(width: max(0, min(1, otaProgress)) * (NB.Layout.contentWidth - 32))
                }
                .frame(height: 3)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .animation(.easeOut(duration: 0.25), value: otaProgress)
            }

            Hairline()
            IdentityRow(name: "MODEL", value: identityValue(\.model))
            IdentityRow(name: "HARDWARE", value: identityValue(\.hardware))
            IdentityRow(name: "BLUETOOTH", value: bluetoothValue)
            IdentityRow(name: "LAST PLUG", value: eventStamp(BatteryLog.lastPlug(in: data.batteryLog)))
            IdentityRow(name: "LAST LINK", value: eventStamp(BatteryLog.lastLink(in: data.batteryLog)))
            IdentityRow(name: "SPORT", value: identityValue(\.sportMode), last: true)
        }
    }

    private func identityValue(_ key: KeyPath<BandIdentity, String>) -> String {
        let raw = identity?[keyPath: key] ?? ""
        return raw.isEmpty ? Fmt.dash : raw
    }

    /// Six hex pairs are a MAC and use colons. Anything else (an iOS BLE UUID) stays as
    /// the identifier the phone actually has — it is not relabelled as a MAC.
    private var bluetoothValue: String {
        let raw = identity?.bleIdentifier ?? data.band.mac
        guard !raw.isEmpty else { return Fmt.dash }
        let parts = raw.split(separator: "-")
        if parts.count == 6 { return parts.joined(separator: ":") }
        return raw
    }

    private func eventStamp(_ date: Date?) -> String {
        guard let date else { return L("NEVER") }
        let clock = Fmt.clock(date)
        if Calendar.current.isDateInToday(date) { return L("TODAY %@", clock) }
        if Calendar.current.isDateInYesterday(date) { return L("YDAY %@", clock) }
        return clock
    }

    #if DEBUG
    /// 12S · the light on the side of the band. ADR 0023 · this firmware answers
    /// `healthLightType=0`, so the SDK light is not addressable and the side light the
    /// wearer sees is the measurement LED. The row stays as a probe, inside DEBUG, and
    /// never as a page of its own. The value is the phone's saved choice; "band default"
    /// means nothing has been chosen and nothing is sent.
    private var healthLightRow: some View {
        NavRow(title: L("Health light"),
               detail: L("THE LIGHT ON THE SIDE · WRITTEN BACK ON EVERY CONNECT"),
               value: BandHealthLightState(rawValue: healthLightRaw).map { L($0.title) } ?? L("BAND DEFAULT"),
               valueTint: NB.ember1,
               enabled: connected,
               last: true) { sheet = .healthLight }
    }

    private var debugHeader: some View {
        HStack(spacing: 8) {
            Text(L("DEBUG"))
                .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.ember1)
            Text(L("BUILD ONLY"))
                .font(NBFont.dot(600, 9)).tracking(0.14 * 9)
                .foregroundStyle(NB.ember1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.top, 8)
    }

    private var debugCard: some View {
        VStack(spacing: 0) {
            IdentityRow(name: "MODEL", value: identityValue(\.model))
            IdentityRow(name: "HARDWARE", value: identityValue(\.hardware))
            IdentityRow(name: "SOFTWARE", value: reportedFirmware)
            IdentityRow(name: "DEVICE NO.", value: identityValue(\.deviceNumber))
            IdentityRow(name: "SPORT MODE", value: identityValue(\.sportMode))
            IdentityRow(name: "BLUETOOTH", value: bluetoothValue, last: true)
            NavRow(title: L("Automatic measurement"),
                   detail: autoDetail,
                   value: autoValue,
                   valueTint: NB.ember1,
                   enabled: connected) {
                sheet = .bandAutoMonitor
            }
            NavRow(title: L("Read the band"),
                   detail: L("HOW OFTEN THE DAY IS PULLED"),
                   value: SyncCadence.label(cadence),
                   valueTint: NB.ember1) { sheet = .syncCadence }
            NavRow(title: L("Sport mode probe"),
                   detail: L("TAP A TYPE · THE BAND OPENS IT, THEN CLOSES IT"),
                   value: identity?.sportMode ?? "—",
                   valueTint: NB.ember1) { sportProbe = true }
            NavRow(title: L("Capability sweep"),
                   detail: L("READ WHAT THIS FIRMWARE ANSWERS"),
                   value: "",
                   valueTint: NB.ember1) { capabilitySweep = true }
            healthLightRow
        }
        .frame(width: NB.Layout.contentWidth)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.ember1.opacity(0.33), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
    }
    #endif

    /// The version the band itself reports, never a seed constant.
    private var reportedFirmware: String {
        data.band.firmware.isEmpty ? (identity?.firmware ?? Fmt.dash) : data.band.firmware
    }

    /// An offer is only installable while the last attempt is not sitting unverified —
    /// pushing the same file again over a version we could not read is how a band bricks.
    private var offerInstallable: Bool { offer != nil && ota != .unverified }

    private var otaLine: String {
        switch ota {
        case .running:          return L("Installing · keep the band close")
        case .completed:        return L("Installed · %@ is on the band", reportedFirmware)
        case .failed(let why):  return L(why)
        case .unverified:       return L("The update finished but we could not read the new version back. Check the band before trying again.")
        default: break
        }
        guard connected else { return offer == nil ? L("Reconnect to check for updates") : L("Reconnect to install this update") }
        switch check {
        case .idle, .checking:  return L("Checking for updates…")
        case .failed(let why):  return L("Could not reach the update server · %@", L(why))
        case .done:             return offer.map { $0.notes.first ?? L("Update available") } ?? L("Up to date")
        }
    }

    private var otaButton: String {
        if ota == .running { return otaProgress > 0 ? L("UPDATING %d %%", Int(otaProgress * 100)) : L("UPDATING…") }
        if ota == .completed { return L("DONE") }
        return offerInstallable ? L("UPDATE") : L("CHECK")
    }

    /// One sentence with a padlock covers the whole read-only stretch. Switches are not
    /// hidden and not greyed into illegibility — they simply do not move.
    private var readOnlyNotice: some View {
        HStack(spacing: 8) {
            LockGlyph()
            Text(L("Settings below are read-only until you reconnect"))
                .font(NBFont.ui(400, 12)).tracking(0.02 * 12)
                .foregroundStyle(NB.text3Prod)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }
}

private func rememberOpticalSwitch(_ read: AutoMonitoringRead?) {
    if let slot = read?.slots.first(where: { $0.kind == .bloodGlucose }) {
        OpticalAutoSwitch.record(on: slot.on)
    }
}

private struct LockGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 14
            ctx.stroke(Path(roundedRect: CGRect(x: 3 * s, y: 6 * s, width: 8 * s, height: 7 * s),
                            cornerRadius: 1.6 * s), with: .color(NB.text3Prod), lineWidth: 1.2 * s)
            var arc = Path()
            arc.addArc(center: CGPoint(x: 7 * s, y: 6 * s), radius: 2.6 * s,
                       startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            ctx.stroke(arc, with: .color(NB.text3Prod), lineWidth: 1.2 * s)
        }
        .frame(width: 14, height: 14)
    }
}

private struct GroupLabel12: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
            .foregroundStyle(Color(hex: 0x8A8A96))
            .padding(.leading, 2)
            .padding(.top, 8)
    }
}

private struct RowCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .frame(width: NB.Layout.contentWidth)
            .cardSkin()
    }
}

/// 12 BRIDGE lead corridor sparkline on the lime slab.
/// Carbon line tracing 7-day drain points across the lime width, ending on a live terminal dot.
private struct LimeTrendLead: View {
    let plot: BatteryPlot

    var body: some View {
        Canvas { ctx, size in
            let spanY = max(0.001, plot.yMax)
            let spanX = max(0.001, plot.end.timeIntervalSince(plot.start))
            let inset: CGFloat = 1
            func y(_ v: Double) -> CGFloat {
                let clamped = min(plot.yMax, max(0, v))
                return size.height - 2 - CGFloat(clamped / spanY) * (size.height - 4)
            }
            func x(_ date: Date) -> CGFloat {
                inset + CGFloat(date.timeIntervalSince(plot.start) / spanX) * (size.width - inset * 2)
            }
            func point(_ p: BatteryPoint) -> CGPoint {
                CGPoint(x: x(p.at), y: y(p.value))
            }

            var hasPoints = false
            for (i, run) in plot.runs.enumerated() {
                guard let first = run.first else { continue }
                hasPoints = true
                var heard = Path()
                var guess = Path()
                var prev = first
                if run.count == 1 {
                    heard.move(to: point(first))
                    heard.addLine(to: CGPoint(x: point(first).x + 0.5, y: point(first).y))
                }
                for p in run.dropFirst() {
                    var segment = Path()
                    segment.move(to: point(prev))
                    segment.addLine(to: point(p))
                    if prev.estimated || p.estimated { guess.addPath(segment) }
                    else { heard.addPath(segment) }
                    prev = p
                }
                ctx.stroke(heard, with: .color(NB.carbon4),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter))
                ctx.stroke(guess, with: .color(NB.carbon4.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .square, lineJoin: .miter, dash: [2, 3]))
                if i + 1 < plot.runs.count,
                   let next = plot.runs[i + 1].first,
                   let last = run.last,
                   last.estimated || next.estimated {
                    var join = Path()
                    join.move(to: point(last))
                    join.addLine(to: point(next))
                    ctx.stroke(join, with: .color(NB.carbon4.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                }
            }

            if let end = plot.runs.last?.last {
                let at = point(end)
                ctx.fill(Path(ellipseIn: CGRect(x: at.x - 2, y: at.y - 2, width: 4, height: 4)),
                         with: .color(NB.carbon4))
            } else if !hasPoints {
                var lead = Path()
                lead.move(to: CGPoint(x: 0, y: size.height / 2))
                lead.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(lead, with: .color(NB.carbon4.opacity(0.20)),
                           style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
            }
        }
        .accessibilityHidden(true)
    }
}

/// One cell on the lime slab. Carbon type on lime, number + unit split the way the board does.
private struct LimeMetric: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.carbon4.opacity(0.6))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(NBFont.dot(700, 20))
                    .foregroundStyle(NB.carbon4)
                if let unit {
                    Text(unit)
                        .font(NBFont.dot(500, 10))
                        .foregroundStyle(NB.carbon4.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NavRow: View {
    let title: String
    let detail: String
    let value: String
    var valueTint: Color = NB.text3Prod
    var enabled = true
    var last = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                        .foregroundStyle(enabled ? NB.text1 : NB.text2)
                    Text(detail)
                        .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                        .foregroundStyle(NB.white.opacity(0.34))
                }
                Spacer(minLength: 0)
                Text(value)
                    .font(NBFont.dot(600, 11))
                    .tracking(0.08 * 11)
                    .foregroundStyle(valueTint)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44, alignment: .trailing)
                Chevron()
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .overlay(alignment: .bottom) { last ? nil : Hairline().padding(.leading, 16) }
    }
}

private struct IdentityRow: View {
    let name: String
    let value: String
    var last = false
    var body: some View {
        HStack(spacing: 10) {
            Text(L(name))
                .font(NBFont.ui(500, 13)).tracking(0.06 * 13)
                .foregroundStyle(NB.text1)
            Spacer(minLength: 0)
            Text(value)
                .font(NBFont.dot(500, 11)).tracking(0.08 * 11)
                .foregroundStyle(NB.white.opacity(0.34))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .overlay(alignment: .bottom) { last ? nil : Hairline() }
    }
}

private struct DestructiveRow: View {
    let title: String
    let detail: String
    let tint: Color
    var last = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                        .foregroundStyle(tint)
                    Text(detail)
                        .font(NBFont.ui(400, 11.5)).tracking(0.02 * 11.5)
                        .foregroundStyle(NB.white.opacity(0.34))
                }
                Spacer(minLength: 0)
                Chevron()
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { last ? nil : Hairline().padding(.leading, 16) }
    }
}

// MARK: 12S · the two device sheets

/// One row per thing the band can measure — only what this HOOP reports is listed.
/// Interval firmware answers `readAutoMonitSwitchInfo`. Older firmware answers the
/// base-function switches, with no interval to set.
struct AutoMeasurementSheet: View {
    let initial: AutoMonitoringRead?
    let onRead: (AutoMonitoringRead) -> Void

    @State private var read: AutoMonitoringRead?
    @State private var loading = true
    @State private var writeError: String?
    @State private var writingKinds: Set<AutoMonitorSlot.Kind> = []

    init(initial: AutoMonitoringRead?, onRead: @escaping (AutoMonitoringRead) -> Void) {
        self.initial = initial
        self.onRead = onRead
        _read = State(initialValue: initial)
        _loading = State(initialValue: initial == nil)
    }

    private var slots: [AutoMonitorSlot] { read?.slots ?? [] }
    private var firmwareOwnsInterval: Bool {
        if case .switches = read { return true }
        return false
    }
    private var hasScientificSleep: Bool {
        slots.contains { $0.kind == .scientificSleep }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Automatic measurement"))
                    .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                    .foregroundStyle(NB.text1)
                Text(subtitle)
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .padding(.top, 6)

                if loading && slots.isEmpty {
                    Text(L("ASKING THIS HOOP…"))
                        .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.white.opacity(0.38))
                        .padding(.top, 24)
                }

                if !slots.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                            MeasureToggle(
                                title: L(Self.title(slot.kind)),
                                detail: Self.detail(slot, firmwareOwnsInterval: firmwareOwnsInterval),
                                // 12S decision 2 · isSlotModify / isIntervalModify: a chip the firmware
                                // will not let you change is not rendered — a read-only grey chip gets
                                // tapped over and over. Both false leaves only the switch.
                                chips: slot.supportsRange && slot.slotModifiable
                                    ? [String(format: "%02d:00 – %02d:00", slot.startHour, slot.endHour)]
                                    : [],
                                selectedInterval: slot.intervalModifiable ? slot.intervalMinutes : nil,
                                intervalOptions: slot.intervalModifiable ? slot.allowedIntervals : [],
                                onIntervalSelected: { interval in
                                    update(slot, interval: interval)
                                },
                                isWriting: writingKinds.contains(slot.kind),
                                detailIsLime: slot.kind == .scientificSleep
                                    ? slot.on
                                    : firmwareOwnsInterval
                                    ? slot.on
                                    : slot.on && slot.supportsRange && slot.slotModifiable && slot.intervalModifiable,
                                isOn: Binding(
                                    get: { slots.first(where: { $0.id == slot.id })?.on ?? slot.on },
                                    set: { on in
                                        update(slot, on: on)
                                    }),
                                last: index == slots.count - 1)
                        }
                    }
                    .frame(width: NB.Layout.contentWidth)
                    .cardSkin()
                    .padding(.top, 16)

                    Text(footer)
                        .font(NBFont.ui(300, 11.5)).tracking(0.02 * 11.5)
                        .foregroundStyle(NB.white.opacity(0.30))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                    if let writeError {
                        Text(writeError)
                            .font(NBFont.dot(600, 10)).tracking(0.12 * 10)
                            .foregroundStyle(NB.ember1)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                } else if !loading {
                    emptyState.padding(.top, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(NB.carbon2)
        .task { await refresh() }
    }

    private var subtitle: String {
        if firmwareOwnsInterval {
            return hasScientificSleep
                ? L("This HOOP lets you turn each sensor or sleep mode on or off. How often it measures is decided by the firmware.")
                : L("This HOOP only lets you turn each sensor on or off. How often it measures is decided by the firmware.")
        }
        return hasScientificSleep
            ? L("Choose each sensor's own interval. Scientific sleep uses automatic PPG.")
            : L("Choose each sensor's own interval. Shorter intervals use more battery.")
    }

    private var footer: String {
        if hasScientificSleep {
            return L("Scientific sleep applies to future nights and may use more battery.")
        }
        return firmwareOwnsInterval
            ? L("The interval itself is not a setting on this firmware.")
            : L("Only what this HOOP can measure is listed")
    }

    @ViewBuilder
    private var emptyState: some View {
        switch read {
        case .failed(let headline, let sentence):
            EdgeNote(line: L(headline), text: L(sentence))
        case .switches:
            EdgeNote(
                line: L("THIS FIRMWARE HAS NO AUTOMATIC-MEASUREMENT SWITCHES"),
                text: L("How often it measures is decided on the band. This app cannot change that interval."))
        case .interval, .none:
            EdgeNote(
                line: L("THIS HOOP DID NOT REPORT ITS AUTOMATIC MEASUREMENTS"),
                text: L("The interval API is on this firmware, but the band sent no rows. Try again while it is on your wrist."))
        }
    }

    private func refresh() async {
        defer { loading = false }
        do {
            let result = try await Band.live.readAutoMonitoring()
            read = result
            rememberOpticalSwitch(result)
            onRead(result)
        } catch {
            let result = AutoMonitoringRead.failed(error)
            read = result
            onRead(result)
        }
    }

    private func update(_ original: AutoMonitorSlot, on: Bool? = nil, interval: Int? = nil) {
        guard !writingKinds.contains(original.kind) else { return }
        var updated = original
        if let on { updated.on = on }
        if let interval {
            guard updated.allowedIntervals.contains(interval) else { return }
            updated.intervalMinutes = interval
            updated.on = true
        }
        apply(updated)
        writeError = nil
        writingKinds = writingKinds.union([updated.kind])
        Task {
            defer { writingKinds = writingKinds.subtracting([updated.kind]) }
            do {
                try await Band.live.writeAutoMonitoring(updated)
                await refresh()
            } catch {
                apply(original)
                writeError = error.localizedDescription
            }
        }
    }

    private func apply(_ slot: AutoMonitorSlot) {
        if slot.kind == .bloodGlucose { OpticalAutoSwitch.record(on: slot.on) }
        switch read {
        case .interval(let slots):
            read = .interval(slots.map { $0.id == slot.id ? slot : $0 })
        case .switches(let slots):
            read = .switches(slots.map { $0.id == slot.id ? slot : $0 })
        case .failed, nil:
            break
        }
    }

    private static func title(_ kind: AutoMonitorSlot.Kind) -> String {
        switch kind {
        case .heartRate:       "Heart rate"
        case .bloodPressure:   "Blood pressure"
        case .bloodGlucose:    "Meal response"
        case .stress:          "Stress"
        case .bloodOxygen:     "Blood oxygen"
        case .temperature:     "Skin temperature"
        case .lorentz:         "Lorentz"
        case .hrv:             "HRV"
        case .scientificSleep: "Scientific sleep"
        case .bloodComponents: "Blood components"
        }
    }

    private static func detail(_ slot: AutoMonitorSlot, firmwareOwnsInterval: Bool) -> String {
        if slot.kind == .scientificSleep {
            return slot.on ? L("REM STAGING · AUTOMATIC PPG ON") : L("DEEP AND LIGHT ONLY")
        }
        guard slot.on else { return L("OFF") }
        if firmwareOwnsInterval { return L("FIRMWARE INTERVAL") }
        if slot.supportsRange {
            if slot.slotModifiable && slot.intervalModifiable { return L("WINDOW AND INTERVAL, BOTH YOURS") }
            return L("%02d:00 – %02d:00 · %@",
                     slot.startHour, slot.endHour, intervalLabel(slot.intervalMinutes))
        }
        return intervalLabel(slot.intervalMinutes)
    }

    private static func intervalLabel(_ minutes: Int) -> String {
        minutes == 0 ? L("CONTINUOUS") : L("EVERY %d MIN", minutes)
    }
}

private struct MeasureToggle: View {
    let title: String
    let detail: String
    var chips: [String] = []
    var selectedInterval: Int?
    var intervalOptions: [Int] = []
    var onIntervalSelected: (Int) -> Void = { _ in }
    var isWriting = false
    var detailIsLime = false
    @Binding var isOn: Bool
    var last = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                        .foregroundStyle(NB.text1)
                    Text(detail)
                        .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                        .foregroundStyle(detailIsLime ? NB.lime1 : isOn ? NB.text3Prod : NB.white.opacity(0.28))
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $isOn).labelsHidden().tint(NB.lime1).disabled(isWriting)
            }
            if !chips.isEmpty && isOn {
                HStack(spacing: 10) {
                    ForEach(chips, id: \.self) { c in
                        Text(c)
                            .font(NBFont.dot(600, 11)).tracking(0.14 * 11)
                            .foregroundStyle(NB.lime1)
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background(Color(hex: 0x17171B), in: Capsule())
                            .overlay(Capsule().stroke(NB.lime1.opacity(0.24), lineWidth: 1))
                    }
                    intervalMenu
                }
            } else if selectedInterval != nil && isOn {
                intervalMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { last ? nil : Hairline().padding(.leading, 16) }
    }

    @ViewBuilder
    private var intervalMenu: some View {
        if let selectedInterval, !intervalOptions.isEmpty {
            Menu {
                Picker("Measurement interval", selection: Binding(
                    get: { selectedInterval },
                    set: onIntervalSelected
                )) {
                    ForEach(intervalOptions, id: \.self) { minutes in
                        Text(label(minutes)).tag(minutes)
                    }
                }
            } label: {
                Text(label(selectedInterval))
                    .font(NBFont.dot(600, 11)).tracking(0.14 * 11)
                    .foregroundStyle(NB.lime1)
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(Color(hex: 0x17171B), in: Capsule())
                    .overlay(Capsule().stroke(NB.lime1.opacity(0.24), lineWidth: 1))
            }
            .disabled(isWriting)
        }
    }

    private func label(_ minutes: Int) -> String {
        minutes == 0 ? "Continuous" : "\(minutes) min"
    }
}

/// 12 · how often the phone reads the band. One row per cadence, the current one marked.
/// The choice is written the moment it is tapped — there is nothing to confirm, and the
/// home screen's loop picks it up within thirty seconds.
struct SyncCadenceSheet: View {
    @Binding var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Read the band"))
                .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                .foregroundStyle(NB.text1)
            Text(L("This controls how often your phone collects stored readings. Sensor intervals are set under Automatic measurement."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
                .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(Array(SyncCadence.options.enumerated()), id: \.element) { index, option in
                    Button {
                        minutes = option
                        SyncCadence.minutes = option
                        Task { await Analytics.shared.track("SYNC_CADENCE_SET", ["MINUTES": option]) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(SyncCadence.label(option))
                                .font(NBFont.dot(500, 12)).tracking(0.14 * 12)
                                .foregroundStyle(option == minutes ? NB.lime1 : NB.text1)
                            Spacer(minLength: 0)
                            if option == minutes {
                                Circle().fill(NB.lime1).frame(width: 8, height: 8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        index == SyncCadence.options.count - 1 ? nil : Hairline().padding(.leading, 16)
                    }
                }
            }
            .frame(width: NB.Layout.contentWidth)
            .cardSkin()
            .padding(.top, 16)

            Text(L("Some stored history, including temperature, still arrives in five-minute points. Faster reads do not create extra samples."))
                .font(NBFont.ui(300, 11.5)).tracking(0.02 * 11.5)
                .foregroundStyle(NB.white.opacity(0.30))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
    }
}


/// Reversible, so the safe button is not red.
struct DisconnectSheet: View {
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Disconnect the HOOP?"))
                .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
                .foregroundStyle(NB.text1)
            Text(L("It keeps recording on your wrist. Nothing new reaches the app until you connect again."))
                .font(NBFont.brand(400, 14))
                .lineSpacing(7)
                .foregroundStyle(NB.text2)
            Spacer(minLength: 0)
            LimePillButton(title: L("Stay connected")) { dismiss() }
            Button {
                Task {
                    await Band.live.disconnect()
                    data.band.connected = false
                    dismiss()
                }
            } label: {
                Text(L("DISCONNECT"))
                    .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                    .foregroundStyle(NB.text2)
                    .frame(width: NB.Layout.contentWidth, height: 52)
                    .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
    }
}

/// Three reasons, in the order they actually happen: Bluetooth, distance, a flat battery.
struct WhyWontItConnectSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Why won't it connect?"))
                .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
                .foregroundStyle(NB.text1)
            VStack(alignment: .leading, spacing: 0) {
                ReasonItem(index: "01", title: L("Bluetooth is off"),
                           detail: L("Turn it on in Control Centre, then come back."))
                ReasonItem(index: "02", title: L("It's out of range"),
                           detail: L("Bring the band within arm's reach of the phone."))
                ReasonItem(index: "03", title: L("The battery is flat"),
                           detail: L("Charge it for ten minutes and hold the side key."), last: true)
            }
            .frame(width: NB.Layout.contentWidth)
            .cardSkin()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
    }
}

private struct ReasonItem: View {
    let index: String
    let title: String
    let detail: String
    var last = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(index)
                .font(NBFont.dot(600, 11)).tracking(0.16 * 11)
                .foregroundStyle(NB.lime1)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                    .foregroundStyle(NB.text1)
                Text(detail)
                    .font(NBFont.ui(400, 12)).tracking(0.02 * 12)
                    .foregroundStyle(NB.white.opacity(0.42))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .overlay(alignment: .bottom) { last ? nil : Hairline().padding(.leading, 16) }
    }
}

#if DEBUG
/// One type per row. Tap one: the band opens that sport and closes it again — a success
/// means this firmware carries it. The SDK has no query for its own list, and a screenless
/// band has no workout menu either, so the probe is the only way to enumerate it.
/// Names and ordinals come from `SportModeCatalog`.
private struct SportProbeSheet: View {
    @State private var results: [Int: Bool] = [:]
    @State private var probing: Int?
    @State private var probeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("SPORT MODE PROBE"))
                .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                .foregroundStyle(NB.text1)
            Text(L("Each tap opens the sport on the band and closes it again. A check means this firmware carries it. The SDK cannot query its own list, so this is the only way to enumerate it."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
                .padding(.top, 6)
            if let probeError {
                Text(probeError)
                    .font(NBFont.dot(600, 10.5)).tracking(0.12 * 10.5)
                    .foregroundStyle(NB.ember1)
                    .padding(.top, 8)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(SportModeCatalog.modes.enumerated()), id: \.element.id) { index, mode in
                        Button { probe(mode.rawValue) } label: {
                            HStack(spacing: 10) {
                                Text(mode.name)
                                    .font(NBFont.dot(500, 12)).tracking(0.1 * 12)
                                    .foregroundStyle(NB.text1)
                                Text("#\(mode.rawValue)")
                                    .font(NBFont.dot(400, 10)).tracking(0.1 * 10)
                                    .foregroundStyle(NB.white.opacity(0.3))
                                Spacer(minLength: 0)
                                if probing == mode.rawValue {
                                    ProgressView().tint(NB.lime1)
                                } else {
                                    Text(results[mode.rawValue] == true ? "YES"
                                        : results[mode.rawValue] == false ? "NO" : "TAP")
                                        .font(NBFont.dot(600, 10.5)).tracking(0.12 * 10.5)
                                        .foregroundStyle(results[mode.rawValue] == true ? NB.lime1
                                            : results[mode.rawValue] == false ? NB.ember1
                                            : NB.white.opacity(0.3))
                                }
                            }
                            .padding(.horizontal, 16).frame(height: 46)
                        }
                        .disabled(probing != nil)
                        .buttonStyle(.plain)
                        if index < SportModeCatalog.modes.count - 1 {
                            Hairline().padding(.leading, 16)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .cardSkin()
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    private func probe(_ raw: Int) {
        probing = raw
        probeError = nil
        Task {
            defer { probing = nil }
            do { results[raw] = try await Band.live.probeSportMode(raw) }
            catch { probeError = error.localizedDescription }
        }
    }
}

/// One tap: capability bits, female-health read, six seconds of GSensor, then ADC.
/// Lines are the band's own words. Nothing here becomes a product row.
private struct CapabilitySweepSheet: View {
    @State private var lines: [String] = []
    @State private var running = false
    @State private var probeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("CAPABILITY SWEEP"))
                .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                .foregroundStyle(NB.text1)
            Text(L("Reads the band's own capability bits, the female-health register, and six seconds of GSensor. Long optical tests stay off."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
                .padding(.top, 6)
            Button(action: run) {
                HStack {
                    Text(running ? L("READING…") : L("RUN SWEEP"))
                        .font(NBFont.dot(600, 12)).tracking(0.12 * 12)
                        .foregroundStyle(NB.lime1)
                    Spacer(minLength: 0)
                    if running { ProgressView().tint(NB.lime1) }
                }
                .padding(.horizontal, 16).frame(height: 46)
            }
            .disabled(running)
            .buttonStyle(.plain)
            .cardSkin()
            .padding(.top, 16)
            if let probeError {
                Text(probeError)
                    .font(NBFont.dot(600, 10.5)).tracking(0.12 * 10.5)
                    .foregroundStyle(NB.ember1)
                    .padding(.top, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(NBFont.dot(400, 10)).tracking(0.04 * 10)
                            .foregroundStyle(NB.text1)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .cardSkin()
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    private func run() {
        running = true
        probeError = nil
        Task {
            defer { running = false }
            await LiveReadout.shared.standDown {
                do { lines = try await Band.live.probeCapabilitySweep() }
                catch { probeError = error.localizedDescription }
            }
        }
    }
}
#endif
