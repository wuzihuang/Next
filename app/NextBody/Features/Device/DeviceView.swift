import SwiftUI

/// 12X · 04 ACTION TILES. Lime identity slab (HOOP + SYNC + 2×2), then two
/// carbon bricks (Find HOOP / Alarms). No charge numeral on this card.
struct DeviceView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

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
    @State private var connectingForSync = false
    @State private var syncMessage: String?
    @State private var syncAfterConsent: (account: String, binding: String)?
    /// What Automatic measurement actually read — not a guess from capability bits.
    /// Kept outside DEBUG because Training can still open the sheet in Release.
    @State private var autoRead: AutoMonitoringRead?
    /// After the first new-alarm read. The Alarms brick shows this number, not a guess.
    @State private var alarmCount: Int?
    #if DEBUG
    /// The sport-mode probe sheet. Release builds carry neither the button nor the code.
    @State private var sportProbe = false
    @State private var healthLightProbe = false
    @State private var capabilitySweep = false
    #endif

    private var connected: Bool { data.band.connected }

    var body: some View {
        DetailScroll(glow: NB.lime1, title: L("DEVICE"), trailing: {
            HStack(spacing: 7) {
                Circle().fill(connected ? NB.lime1 : NB.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(connected ? L("CONNECTED") : L("DISCONNECTED"))
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(connected ? NB.lime1 : NB.text3Prod)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .overlay(connected ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
        }) {
            VStack(alignment: .leading, spacing: 14) {
                batteryCard
                limeHero
                actionTiles
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
                    DestructiveRow(title: L("Forget this HOOP"),
                                   detail: L("Removes it from this phone. Your history stays."),
                                   tint: NB.alert2, last: true) { sheet = .unbind }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.back()
        }
        .task {
            if DebugEdge.on("clamped") { clamped = ("Heart rate alarm", "50–140 BPM", "50–130 BPM") }
            if DebugEdge.on("busy") { busyQueued = true }
            if DebugEdge.on("otaunverified") { ota = .unverified }
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
            guard connected else { return }
            // Seeded BandState is already CONNECTED; the mock radio may still be idle.
            // Ask it to come up before the firmware identity rows stay dashes.
            if Band.live.state != .connected {
                await Band.live.reconnectIfBound()
            }
            if !DebugEdge.on("levelonly"), let fresh = try? await Band.live.readBattery() {
                data.applyBandObservation(battery: fresh)
            }
            identity = try? await Band.live.readIdentity()
            if let identity { data.applyBandObservation(identity: identity) }
            if let fresh = try? await Band.live.readCapabilities() {
                data.capabilities = fresh
                if let deviceId = Repository.shared.deviceId,
                   let userId = await SupabaseClient.shared.currentUserId {
                    await Repository.shared.saveCapabilities(fresh, deviceId: deviceId, userId: userId,
                                                             holdsDays: identity?.watchDataDayNumber)
                }
            }
            await checkForUpdate()
            if let list = try? await Band.live.readAlarms() {
                alarmCount = list.count
            }
            #if DEBUG
            if let s = ProcessInfo.processInfo.environment["NB_DEBUG_DEVICE_SHEET"] {
                switch s {
                case "findHoop": sheet = .findHoop
                case "bandAlarms": sheet = .bandAlarms
                default: break
                }
            }
            #endif
            await OriginDataSync.refreshNow(into: data)
            do {
                autoRead = try await Band.live.readAutoMonitoring()
                rememberOpticalSwitch(autoRead)
            } catch {
                autoRead = .failed(error)
            }
        }
        .onChange(of: connected) { _, on in
            guard on else { autoRead = nil; return }
            Task {
                if !DebugEdge.on("levelonly"), let fresh = try? await Band.live.readBattery() {
                    data.applyBandObservation(battery: fresh)
                }
                if identity == nil, let fresh = try? await Band.live.readIdentity() {
                    identity = fresh
                    data.applyBandObservation(identity: fresh)
                }
                if check == .idle { await checkForUpdate() }
                if let list = try? await Band.live.readAlarms() {
                    alarmCount = list.count
                }
                do {
                    autoRead = try await Band.live.readAutoMonitoring()
                    rememberOpticalSwitch(autoRead)
                } catch {
                    autoRead = .failed(error)
                }
            }
        }
        .onChange(of: router.takeover) { old, current in
            guard old == .consent, current == nil, let pending = syncAfterConsent else { return }
            syncAfterConsent = nil
            guard ConsentStore.shared.granted,
                  SupabaseClient.currentUserIdSnapshot() == pending.account,
                  BoundBand.identifier == pending.binding else { return }
            Task { @MainActor in
                // The app releases the takeover's native-operation gate on this same change.
                await Task.yield()
                guard router.takeover == nil, ConsentStore.shared.granted,
                      SupabaseClient.currentUserIdSnapshot() == pending.account,
                      BoundBand.identifier == pending.binding else { return }
                await pullBandNow()
            }
        }
        .sheet(item: $sheet) { r in
            Group {
                switch r {
                case .bandAutoMonitor: AutoMeasurementSheet(initial: autoRead) { autoRead = $0 }
                case .syncCadence:     SyncCadenceSheet(minutes: $cadence)
                case .unbind:          ForgetHoopSheet()
                case .disconnect:      DisconnectSheet()
                case .findBand:        WhyWontItConnectSheet()
                case .findHoop:        FindHoopSheet()
                case .bandAlarms:      AlarmsSheet { alarmCount = $0 }
                default:               WhyWontItConnectSheet()
                }
            }
            .presentationDetents([
                [.bandAutoMonitor, .findHoop, .bandAlarms].contains(r)
                    ? .fraction(0.78) : .fraction(0.62)
            ])
            .presentationDragIndicator(.visible)
            .presentationBackground(
                [.findHoop, .bandAlarms].contains(r) ? NB.carbon4 : NB.carbon2
            )
            .presentationCornerRadius(NB.R.panel)
        }
        #if DEBUG
        .sheet(isPresented: $healthLightProbe) {
            HealthLightDebugSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(NB.carbon2)
                .presentationCornerRadius(NB.R.panel)
        }
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

    /// Ask the update server. The card says "checking" while this runs, and afterwards one of
    /// three things: an offer, "up to date", or that the server could not be reached.
    private func checkForUpdate() async {
        guard connected, check != .checking else { return }
        check = .checking
        do {
            offer = try await Band.live.checkFirmwareUpdate()
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
                if syncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NB.lime1)
                }
                Text(syncing ? L(connectingForSync ? "CONNECTING" : "SYNCING…") : L("SYNC"))
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
        .accessibilityValue(syncing ? L(connectingForSync ? "CONNECTING" : "SYNCING…") : "")
    }

    /// Battery, identity, then today's origin pages — cadence throttle does not apply,
    /// because the button exists to ask again now.
    private func pullBandNow() async {
        guard BoundBand.identifier != nil, !syncing else { return }
        syncMessage = nil
        guard let account = SupabaseClient.currentUserIdSnapshot(),
              let binding = BoundBand.identifier else {
            syncMessage = L("Sign in to sync this HOOP.")
            return
        }
        guard ConsentStore.shared.granted else {
            syncAfterConsent = (account, binding)
            router.takeover = .consent
            return
        }
        guard LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else {
            syncMessage = L("Finish the current measurement or device operation, then sync again.")
            return
        }
        syncing = true
        connectingForSync = Band.live.state != .connected
        defer { syncing = false; connectingForSync = false }
        await Analytics.shared.track("DEV_SYNC_TAP", ["CONNECTED": connected])
        let ready = await BandReadiness.shared.ensureReady(into: data, reason: "device-sync")
        guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() == account,
              BoundBand.identifier == binding, !Task.isCancelled else { return }
        guard LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else {
            syncMessage = L("Finish the current measurement or device operation, then sync again.")
            return
        }
        guard ready else {
            syncMessage = L("Could not reach this HOOP. Keep it nearby, check Bluetooth, then tap Sync to try again.")
            return
        }
        connectingForSync = false
        if let snapshot = BandReadiness.shared.snapshot,
           snapshot.account == account, snapshot.binding == binding {
            identity = snapshot.identity
        }
        await OriginDataSync.refreshNow(into: data, minimumInterval: 0, fullHistory: true)
        guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() == account,
              BoundBand.identifier == binding, !Task.isCancelled else { return }
        if Band.live.state != .connected {
            syncMessage = L("The connection was lost during sync. Tap Sync to reconnect and try again.")
        }
    }

    private var bandBattery: BandBattery? { data.band.lastBattery }

    private var batteryReading: String {
        if let battery = bandBattery {
            if battery.isPercent { return battery.percent.map(String.init) ?? Fmt.dash }
            return battery.level.map { "\($0)/4" } ?? Fmt.dash
        }
        return data.band.batteryPercent.map(String.init) ?? Fmt.dash
    }

    private var batteryUnit: String {
        guard connected else { return L("LAST SEEN") }
        if let battery = bandBattery {
            return battery.isPercent ? L("PERCENT") : L("BARS")
        }
        return L("PERCENT")
    }

    private var displayedCharge: BandBattery.ChargeState {
        connected ? data.band.displayedCharge : .unknown
    }

    private var chargeLine: String? {
        guard connected else { return L("Still recording on your wrist") }
        switch displayedCharge {
        case .charging: return L("Charging")
        case .full:     return L("Charged")
        default:        return nil
        }
    }

    private var powerValue: String {
        guard connected else { return L("UNKNOWN") }
        switch displayedCharge {
        case .charging:  return L("CHARGING")
        case .full:      return L("FULL")
        case .unplugged: return L("UNPLUGGED")
        case .unknown:   return Fmt.dash
        }
    }

    private var leftValue: String {
        guard let left = BatteryDrainMath.left(in: data.batteryLog, now: Date()) else {
            return Fmt.dash
        }
        switch left {
        case .hours(let n): return "\(n) \(L("HRS"))"
        case .days(let n): return "\(n) \(L("DAYS"))"
        }
    }

    /// The ring is the number. TREND opens the chart page — the line is still there.
    private var batteryCard: some View {
        VStack(spacing: 16) {
            if let battery = bandBattery, !battery.isPercent {
                HStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 12) {
                        HStack(spacing: 5) {
                            ForEach(0..<4, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(i < (battery.level ?? 0) ? NB.lime1 : Color(hex: 0x2A2A32))
                                    .frame(width: 22, height: 34)
                            }
                        }
                        Text(L("%d OF 4 BARS", battery.level ?? 0))
                            .font(NBFont.dot(700, 14)).tracking(0.14 * 14)
                            .foregroundStyle(Color(hex: 0xB0B0BA))
                        Text(L("This firmware reports level, not percent."))
                            .font(NBFont.ui(300, 11.5)).tracking(0.03 * 11.5)
                            .foregroundStyle(NB.text3Prod)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().strokeBorder(NB.barTrack, lineWidth: 5).frame(width: 74, height: 74)
                        RingArc(from: 0, to: bandBattery?.ringFraction
                                ?? Double(data.band.batteryPercent ?? 0) / 100)
                            .stroke(connected ? NB.lime1 : NB.white.opacity(0.28),
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 69, height: 69)
                        VStack(spacing: 2) {
                            Text(batteryReading)
                                .font(NBFont.dot(700, 20))
                                .foregroundStyle(NB.text1)
                            Text(batteryUnit)
                                .font(NBFont.dot(500, 8)).tracking(0.16 * 8)
                                .foregroundStyle(NB.white.opacity(0.34))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(data.band.name)
                            .font(NBFont.ui(600, 18)).tracking(0.02 * 18)
                            .foregroundStyle(NB.text1)
                        Text(L("NEXTBODY HOOP"))
                            .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                            .foregroundStyle(NB.white.opacity(0.34))
                        if let chargeLine {
                            Text(chargeLine)
                                .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                                .foregroundStyle(connected ? NB.lime1 : NB.text2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Hairline()

            HStack(spacing: 0) {
                DeviceFact(label: L("POWER"), value: powerValue)
                DeviceFact(label: L("LEFT"), value: leftValue)
                Button { router.open(.battery, from: router.entry) } label: {
                    DeviceFact(label: L("TREND"), value: L("SEE"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("device.trend")
            }
        }
        .padding(18)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .accessibilityIdentifier("device.battery")
    }

    /// Name + SYNC, then WORN / WITH YOU / SYNCED / LAST POINT.
    private var limeHero: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(data.band.name)
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
            .padding(.bottom, 16)

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
        .background(NB.lime1, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.lime1, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
    }

    /// Two carbon bricks. PING is the only lime word — Find HOOP is not a lime flood.
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(L("CLOCK"))
                            .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                            .foregroundStyle(NB.white.opacity(0.38))
                        if let alarmCount {
                            Text("\(alarmCount)")
                                .font(NBFont.dot(700, 18))
                                .foregroundStyle(NB.text1)
                        }
                    }
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
            NavRow(title: L("Health light"),
                   detail: L("TEST THE FOUR LIGHT STATES"),
                   value: "",
                   valueTint: NB.ember1) { healthLightProbe = true }
            NavRow(title: L("Capability sweep"),
                   detail: L("READ WHAT THIS FIRMWARE ANSWERS"),
                   value: "",
                   valueTint: NB.ember1,
                   last: true) { capabilitySweep = true }
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

private struct DeviceFact: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.text3Prod)
            Text(value)
                .font(NBFont.dot(600, 11)).tracking(0.1 * 11)
                .foregroundStyle(NB.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// The only row on DEVICE that asks twice.
/// ⚠️ The SDK only offers disconnect(); "forget" is the app clearing its own device id.
/// "Forget this HOOP" is possible; "factory reset" is not, and the two must never blur.
struct ForgetHoopSheet: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Forget this HOOP?"))
                .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
                .foregroundStyle(NB.text1)
            Text(L("This phone stops pairing with it. Everything it has already sent you stays — 12 weeks of nights and every reading. Pairing it again takes about a minute."))
                .font(NBFont.brand(400, 14))
                .lineSpacing(7)
                .foregroundStyle(NB.text2)
            Spacer(minLength: 0)
            LimePillButton(title: L("Keep it paired")) { dismiss() }
            Button {
                // F3 · Forget writes unbound_at so the account is UNPAIRED. Clearing only
                // the local UUID left the server claiming a band and no way back to Connect.
                Task {
                    await Repository.shared.unbindBoundDevice()
                    BoundBand.forget()
                    await Band.live.disconnect()
                    data.band = .unknown
                    session.stage = .gateConnect
                    dismiss()
                }
            } label: {
                Text(L("FORGET THIS HOOP"))
                    .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                    .foregroundStyle(NB.alert2)
                    .frame(width: NB.Layout.contentWidth, height: 52)
                    .overlay(Capsule().stroke(NB.alert2.opacity(0.6), lineWidth: 1))
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
