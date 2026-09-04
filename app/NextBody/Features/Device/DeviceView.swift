import SwiftUI

/// 12 · 设备 Device — the only second-level page in the product, because it really does have
/// a page of content. Entered from Profile; back returns to Profile, not to the root.
struct DeviceView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var sheet: SheetRoute?
    @State private var identity: BandIdentity?
    @State private var battery: BandBattery?

    // F3 · a switch shows the value that came back, never the value we sent. Optimistic UI
    // here means the firmware wins a second later and the toggle flips under a finger.
    @State private var hrAlarm = true
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
    @State private var writing: String?
    /// How often this phone asks the band for the day. Mirrors SyncCadence so the row
    /// re-renders when the sheet changes it.
    @State private var cadence = SyncCadence.minutes
    /// What Automatic measurement actually read — not a guess from capability bits.
    @State private var autoRead: AutoMonitoringRead?
    #if DEBUG
    /// The sport-mode probe sheet. Release builds carry neither the button nor the code.
    @State private var sportProbe = false
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
                liveCard
                firmwareCard
                if !connected { readOnlyNotice }
                if busyQueued { busyCard }
                if let clamped { clampCard(clamped) }

                GroupLabel12(L("AUTOMATIC"))
                RowCard {
                    NavRow(title: L("Automatic measurement"),
                           detail: autoDetail,
                           value: autoValue,
                           // The sheet itself states the verdict: empty, switch-only, or
                           // a read that never came back. The row stays tappable while
                           // connected so that explanation is one tap away.
                           enabled: connected) {
                        sheet = .bandAutoMonitor
                    }
                    // One switch with one range is enough; a range needs no second toggle.
                    ToggleRow(title: L("Heart rate alarm"),
                              detail: L("ALERTS OUTSIDE 50 – 140 BPM"),
                              isOn: $hrAlarm, enabled: connected, last: true)
                        .onChange(of: hrAlarm) { _, on in
                            write(.heartRateAlarm(on: on, low: 50, high: 140))
                        }
                }

                GroupLabel12(L("SYNC"))
                RowCard {
                    // The band records every five minutes regardless; this is only how often
                    // the phone collects. It is a phone setting, so it stays live off-band.
                    NavRow(title: L("Read the band"),
                           detail: L("HOW OFTEN THE DAY IS PULLED"),
                           value: SyncCadence.label(cadence), last: true) { sheet = .syncCadence }
                }

                GroupLabel12(L("IDENTITY"))
                // Five dead facts, no box: they are not settings.
                // ⚠️ DEVICE NO. is DeviceVersion.deviceNumber — the SDK has no serial number.
                VStack(spacing: 0) {
                    IdentityRow(name: "MODEL", value: identity?.model ?? "KR96 PRO")
                    IdentityRow(name: "HARDWARE", value: identity?.hardware ?? "1.2")
                    IdentityRow(name: "SOFTWARE", value: identity?.firmware ?? data.band.firmware)
                    // ⚠️ DeviceVersion.deviceNumber. The SDK has no serial number and no
                    // screen in this product is allowed to call this one.
                    IdentityRow(name: "DEVICE NO.", value: identity?.deviceNumber ?? "HB-0042")
                    #if DEBUG
                    // A diagnostic, not product copy: the band's sport-mode tier, straight
                    // from the SDK's model. The row below the card opens the probe, because
                    // the SDK has no query for the list itself — and a screenless band has
                    // no workout list to read either.
                    IdentityRow(name: "SPORT MODE", value: identity?.sportMode ?? "—")
                    #endif
                    // ⚠️ On iOS this is a CoreBluetooth UUID. The label says BLUETOOTH, not
                    // MAC, because it is not one and it changes with the phone.
                    IdentityRow(name: "BLUETOOTH",
                                value: identity?.bleIdentifier ?? data.band.mac, last: true)
                }
                .frame(width: NB.Layout.contentWidth)

                #if DEBUG
                GroupLabel12(L("DEBUG"))
                RowCard {
                    NavRow(title: L("Sport mode probe"),
                           detail: L("TAP A TYPE · THE BAND OPENS IT, THEN CLOSES IT"),
                           value: identity?.sportMode ?? "—", last: true) { sportProbe = true }
                }
                #endif

                GroupLabel12(L("CONNECTION"))
                RowCard {
                    if connected {
                        // Disconnecting is reversible, so the safe button is not red.
                        DestructiveRow(title: L("Disconnect"),
                                       detail: L("It keeps recording. Nothing reaches the app."),
                                       tint: NB.text1) { sheet = .unbind }
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
            // DEBUG · 12 edges on a simulator that would never produce them.
            if DebugEdge.on("clamped") { clamped = ("Heart rate alarm", "50–140 BPM", "50–130 BPM") }
            if DebugEdge.on("busy") { busyQueued = true }
            if DebugEdge.on("otaunverified") { ota = .unverified }
            if DebugEdge.on("levelonly") { battery = BandBattery(isPercent: false, percent: nil, level: 3, chargeState: .unplugged) }
            await Analytics.shared.track("DEVICE_PAGE_OPEN", ["CONNECTED": connected])
            guard connected else { return }
            // Battery first: POWER used to wait behind identity and capabilities, so a
            // known charging band flashed UNKNOWN for a second. The store already holds
            // the last charge state; this write refreshes it without wiping the card.
            if !DebugEdge.on("levelonly"), let fresh = try? await Band.live.readBattery() {
                battery = fresh
                data.band.applyBattery(fresh)
            }
            identity = try? await Band.live.readIdentity()
            if let fresh = try? await Band.live.readCapabilities() {
                data.capabilities = fresh
                if let deviceId = Repository.shared.deviceId,
                   let userId = await SupabaseClient.shared.currentUserId {
                    await Repository.shared.saveCapabilities(fresh, deviceId: deviceId, userId: userId,
                                                             holdsDays: identity?.watchDataDayNumber)
                }
            }
            if let identity { data.band.firmware = identity.firmware }
            await checkForUpdate()
            // The page now shows what the band recorded, so it asks for it. Throttled and
            // shared with the home screen's pull: opening this page a second time inside a
            // tick reads nothing off the band.
            await OriginDataSync.refreshNow(into: data)
            if connected {
                do { autoRead = try await Band.live.readAutoMonitoring() }
                catch { autoRead = .failed(error) }
            }
        }
        // The band came back while the page was open (a reconnect, or the page was opened
        // before the link was up): read what the task above could not, and ask the server.
        .onChange(of: connected) { _, on in
            guard on else { autoRead = nil; return }
            Task {
                if !DebugEdge.on("levelonly"), let fresh = try? await Band.live.readBattery() {
                    battery = fresh
                    data.band.applyBattery(fresh)
                }
                if identity == nil, let fresh = try? await Band.live.readIdentity() {
                    identity = fresh; data.band.firmware = fresh.firmware
                }
                if check == .idle { await checkForUpdate() }
                do { autoRead = try await Band.live.readAutoMonitoring() }
                catch { autoRead = .failed(error) }
            }
        }
        .sheet(item: $sheet) { r in
            Group {
                switch r {
                case .bandAutoMonitor: AutoMeasurementSheet(initial: autoRead) { autoRead = $0 }
                case .syncCadence:     SyncCadenceSheet(minutes: $cadence)
                case .unbind:          ForgetHoopSheet()
                default:               WhyWontItConnectSheet()
                }
            }
            .presentationDetents([r == .bandAutoMonitor ? .fraction(0.78) : .fraction(0.62)])
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
        #endif
    }

    /// Every write goes through the queue at P0 and the switch is re-rendered from the
    /// value the band echoed back. A refusal puts the switch back where it was.
    private func write(_ setting: BandSetting) {
        Task {
            writing = String(describing: setting)
            defer { writing = nil }
            do {
                let back = try await Band.live.writeSetting(setting)
                if case .heartRateAlarm(let on, _, _) = back { hrAlarm = on }
                // 12 edge 3 · render the readback, and say when it differs from what was asked.
                let asked = Self.label(setting), got = Self.label(back)
                clamped = asked.value == got.value ? nil : (asked.name, asked.value, got.value)
                if clamped != nil {
                    await Analytics.shared.track("DEV_SETTING_WRITE", ["KEY": asked.name, "OK": true, "CLAMPED": true])
                }
            } catch BandError.busy {
                // 12 edge 4 · queue, don't fail: the switch springs back with the reason, and
                // the write goes again once the measurement has had its ~12 s.
                if case .heartRateAlarm(let on, _, _) = setting { hrAlarm = !on }
                busyQueued = true
                try? await Task.sleep(for: .seconds(12))
                busyQueued = false
                if case .heartRateAlarm = setting { write(setting) }
            } catch {
                BandLog.shared.record("writeSetting", error: error)
                if case .heartRateAlarm(let on, _, _) = setting { hrAlarm = !on }
            }
        }
    }

    /// One short label per setting, so a clamped write can be read as 「45 MIN · YOU ASKED FOR 60」.
    private static func label(_ s: BandSetting) -> (name: String, value: String) {
        switch s {
        case .heartRateAlarm(let on, let low, let high):
            return ("Heart rate alarm", on ? "\(low)–\(high) BPM" : "OFF")
        }
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
        // The page's task and the reconnect hook can both arrive within a frame of each
        // other; one request to the server at a time, like every other band call.
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
            }
            catch { result = .failed(reason: "\(error)") }
            switch result {
            case .completed(let v):
                ota = .completed; data.band.firmware = v
                if let refreshed = try? await Band.live.readIdentity() { identity = refreshed }
            case .failed(let why):    ota = .failed(why)
            case .versionUnverified:  ota = .unverified
            }
            await Analytics.shared.track("DEV_OTA_END", ["RESULT": "\(result)", "MS": Int(Date().timeIntervalSince(t0) * 1000)])
        }
    }

    private var batteryReading: String {
        guard let battery else { return data.band.batteryPercent.map(String.init) ?? Fmt.dash }
        if battery.isPercent { return battery.percent.map(String.init) ?? Fmt.dash }
        return battery.level.map { "\($0)/4" } ?? Fmt.dash
    }
    private var batteryUnit: String {
        guard connected else { return L("LAST SEEN") }
        guard let battery else { return L("PERCENT") }
        return battery.isPercent ? L("PERCENT") : L("BARS")
    }

    /// Last fact the band reported, including the one already sitting on `data.band`
    /// from BandPresence — so opening this page does not start from UNKNOWN.
    private var displayedCharge: BandBattery.ChargeState {
        if data.band.chargeState != .unknown { return data.band.chargeState }
        return battery?.chargeState ?? .unknown
    }

    private var chargeLine: String {
        guard connected else { return L("Still recording on your wrist") }
        switch displayedCharge {
        case .charging: return L("Charging")
        case .full:     return L("Charged")
        default:        return L("About 3 days of charge left")
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

    /// Only what this HOOP actually reported for automatic measurement.
    private var autoDetail: String {
        guard connected else { return L("CONNECT TO READ") }
        guard let autoRead else { return L("ASKING THIS HOOP") }
        let slots = autoRead.slots
        if !slots.isEmpty {
            return slots.map { Self.autoShort($0.kind) }.joined(separator: " · ")
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
        case .bloodGlucose:    "GLU"
        case .stress:          "STRESS"
        case .bloodOxygen:     "SPO2"
        case .temperature:     "TEMP"
        case .lorentz:         "LORENTZ"
        case .hrv:             "HRV"
        case .bloodComponents: "BLOOD"
        }
    }

    /// The ring and the sentence answer two different questions: 82 is a number, and
    /// "about 3 days of charge left" is what a normal person wanted to know.
    /// ⚠️ Days are our own estimate — the SDK gives percent / level / chargeState only.
    private var batteryCard: some View {
        VStack(spacing: 16) {
            if let battery, !battery.isPercent {
                // 12 edge 1 · LEVEL ONLY · NO PERCENT TO SHOW. Four bars, and the days line is
                // not rendered — a bar count × 25 is a percentage nobody measured.
                VStack(spacing: 12) {
                    HStack(spacing: 5) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(i < (battery.level ?? 0) ? NB.lime1 : Color(hex: 0x2A2A32))
                                .frame(width: 22, height: 34)
                        }
                    }
                    Text(L("%d OF 4 BARS", battery.level ?? 0))
                        .font(NBFont.dot(700, 14)).tracking(0.14 * 14).foregroundStyle(Color(hex: 0xB0B0BA))
                    Text(L("This firmware reports level, not percent."))
                        .font(NBFont.ui(300, 11.5)).tracking(0.03 * 11.5).foregroundStyle(NB.text3Prod)
                }
                .frame(maxWidth: .infinity)
            } else {
            HStack(spacing: 18) {
                ZStack {
                    Circle().strokeBorder(NB.barTrack, lineWidth: 5).frame(width: 74, height: 74)
                    RingArc(from: 0, to: battery?.ringFraction ?? Double(data.band.batteryPercent ?? 0) / 100)
                        .stroke(connected ? NB.lime1 : NB.white.opacity(0.28),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 69, height: 69)
                    VStack(spacing: 2) {
                        // ⚠️ Firmware with isPercent = false reports 0–4 bars. Those are
                        // shown as bars; a bar count never gets a % sign put on it.
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
                    Text(L("KR96 PRO"))
                        .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.white.opacity(0.34))
                    // The ring gives a number; this line gives what a person wanted to know.
                    // ⚠️ Days are our own estimate — the SDK reports percent / level / chargeState.
                    Text(chargeLine)
                        .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                        .foregroundStyle(connected ? NB.lime1 : NB.text2)
                }
                Spacer(minLength: 0)
            }
            }

            Hairline()

            HStack(spacing: 0) {
                // POWER holds the last charge the band reported. UNKNOWN is only for a
                // disconnected band — a connected band that has not answered yet is a dash,
                // never a flash of UNKNOWN over a known CHARGING.
                DeviceFact(label: L("POWER"),
                           value: powerValue)
                // ⚠️ F3 rule 11 · 「代码里出现字面量 7 即为 bug」. This fell back to "7 DAYS"
                // when identity had not been read, so the page stated how much the band holds
                // using a number the app made up — and 7 is exactly the value rule 11 names,
                // because it is the one every HOOP is assumed to have until it says otherwise.
                DeviceFact(label: L("ON DEVICE"),
                           value: identity.map { "\($0.watchDataDayNumber) DAYS" } ?? Fmt.dash)
                // ⚠️ F3 rule 09 · SYNCED is the moment of the last readOriginComplete that
                // succeeded, and `store.lastSync` is written on exactly that. This column
                // printed "2 MIN AGO" whenever the band was connected and "2 HRS AGO" when it
                // was not — two constants, true only by coincidence, on the one page a user
                // opens to find out whether syncing is working.
                DeviceFact(label: L("SYNCED"), value: syncedAgo)
            }
        }
        .padding(18)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    /// 12 · what actually came off the wrist, on the page about the thing that measured it.
    /// The device page could say SYNCED 2 MIN AGO and show nothing that was synced — the only
    /// way to tell a working link from a silent one was to leave for the home screen.
    ///
    /// ⚠️ These are the last five-minute tick, not an average and not a live feed: the band
    /// records every five minutes and the app reads what it recorded. 13 · past six hours the
    /// numbers are —— rather than dimmed, because a six-hour-old heart rate is not a reading
    /// of anything, and a band off the wrist reports no heart rate at all.
    private var liveCard: some View {
        let vitals = data.vitals
        let stale = vitals.freshness == .stale
        let gone = vitals.freshness == .gone
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("LAST TICK"))
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.white.opacity(0.34))
                Spacer(minLength: 0)
                Text(vitals.at.map(Fmt.clock) ?? "NO TICK")
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(gone ? NB.text3Prod : NB.lime1)
            }

            HStack(spacing: 0) {
                LiveReading(label: L("HEART"), value: gone ? nil : vitals.hr.map(String.init),
                            unit: "BPM", dim: stale)
                LiveReading(label: L("STRESS"), value: gone ? nil : vitals.stress.map(String.init),
                            unit: L("INDEX"), dim: stale)
                // Steps are the day's own total off the all-day segment, not a tick, so they
                // do not dim with the tick's age — a step taken this morning is still a step.
                LiveReading(label: L("STEPS"), value: data.today.steps.map(String.init),
                            unit: L("TODAY"), dim: false)
            }

            Hairline()

            // One sentence, and it names which of the three states the numbers above are in.
            Text(liveLine)
                .font(NBFont.ui(400, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(gone ? NB.text3Prod : NB.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    private var liveLine: String {
        guard data.vitals.at != nil else {
            return connected
                ? "Nothing has come off this HOOP yet."
                : "Connect the HOOP to see what it has been recording."
        }
        switch data.vitals.freshness {
        case .fresh: return L("The HOOP is recording every five minutes.")
        case .stale: return L("Nothing new for a while. It may be off your wrist.")
        case .gone:  return L("Nothing for over six hours. These are not old numbers, they are no numbers.")
        }
    }

    /// Same shape the panel uses, off the same timestamp, so the two pages cannot disagree
    /// about when the last sync was.
    private var syncedAgo: String {
        // A phone that has never pulled a page says so; it does not count from a made-up time.
        guard let at = data.lastSync else { return L("NEVER") }
        let mins = max(0, Int(Date().timeIntervalSince(at) / 60))
        if mins < 1 { return L("JUST NOW") }
        if mins < 60 { return L("%d MIN AGO", mins) }
        return L("%d HR AGO", mins / 60)
    }

    /// Five reasons the button can be grey, and it always says which one.
    /// "Temporarily unavailable" is never allowed to stand in for all five.
    private var firmwareCard: some View {
        Group {
        if ota == .unverified {
            // 12 edge 5 · OTA UNVERIFIED · NOT SUCCESS, NOT FAILURE.
            VStack(alignment: .leading, spacing: 10) {
                Text(L("VERSION UNCONFIRMED")).font(NBFont.dot(700, 11)).tracking(0.14 * 11).foregroundStyle(NB.ember1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(identity?.firmware ?? data.band.firmware).font(NBFont.dot(700, 18)).tracking(0.02 * 18).foregroundStyle(Color(hex: 0xB0B0BA))
                    Text(L("?")).font(NBFont.dot(500, 14)).foregroundStyle(Color(hex: 0x8A8A96))
                    Text(offer?.version ?? Fmt.dash).font(NBFont.dot(700, 18)).tracking(0.02 * 18).foregroundStyle(Color(hex: 0xB0B0BA))
                }
                Text(L("The update finished but we could not read the new version back. Check the band before trying again."))
                    .font(NBFont.ui(300, 11.5)).tracking(0.02 * 11.5).lineSpacing(4).foregroundStyle(NB.white.opacity(0.70))
            }
            .padding(14)
            .frame(width: NB.Layout.contentWidth, alignment: .leading)
            .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous).stroke(NB.ember1.opacity(0.25), lineWidth: 1))
        } else {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("FIRMWARE"))
                    .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.text3Prod)
                HStack(spacing: 8) {
                    // The left side is the band's own reported version. ⚠️ It read a fixed
                    // 2.4.1, which happened to match the seed and would have quietly lied
                    // about every other HOOP.
                    Text(identity?.firmware ?? data.band.firmware)
                        .font(NBFont.dot(700, 16)).tracking(0.06 * 16)
                        .foregroundStyle(NB.text2)
                    // The right side is what the update server offered. ⚠️ It used to be a
                    // constant 2.5.0, so every HOOP was told it had an update forever.
                    if let offer, ota != .completed {
                        Text(L("→"))
                            .font(NBFont.dot(700, 13))
                            .foregroundStyle(NB.lime1)
                        Text(offer.version)
                            .font(NBFont.dot(700, 16)).tracking(0.06 * 16)
                            .foregroundStyle(NB.lime1)
                    }
                }
                Text(otaLine)
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(ota == .completed ? NB.lime1 : NB.text3Prod)
            }
            Spacer(minLength: 0)
            if offer != nil || (connected && check != .checking && ota != .completed) {
                // With an offer the button installs it. Without one (current, or the server
                // could not be asked) it asks again — the card is never a dead end.
                Button(action: { if offer != nil { runUpdate() } else { Task { await checkForUpdate() } } }) {
                    Text(otaButton)
                        .font(NBFont.ui(600, 11)).tracking(0.12 * 11)
                        .foregroundStyle(connected && offer != nil ? NB.carbon : NB.text3Prod)
                        .padding(.horizontal, 18).frame(height: 36)
                        .background(connected && offer != nil ? NB.lime1 : Color.clear, in: Capsule())
                        .overlay(connected && offer != nil ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!connected || ota == .running || ota == .completed)
            }
        }
        .padding(16)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        }
        }
    }

    private var otaLine: String {
        switch ota {
        case .running:          return L("Installing · keep the band close")
        case .completed:        return L("Installed · %@ is on the band", identity?.firmware ?? data.band.firmware)
        case .failed(let why):  return L(why)
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
        return offer != nil ? L("UPDATE") : L("CHECK")
    }

    /// One sentence with a padlock covers the whole read-only段. Switches are not hidden and
    /// not greyed into illegibility — they simply do not move.
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

/// One reading off the last tick. `nil` is ——, never a zero and never the tick before it.
private struct LiveReading: View {
    let label: String
    let value: String?
    let unit: String
    var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.text3Prod)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? Fmt.dash)
                    .font(NBFont.dot(700, 22)).tracking(0.02 * 22)
                    .foregroundStyle(value == nil ? NB.text3Prod
                                     : (dim ? NB.text2 : NB.text1))
                Text(unit)
                    .font(NBFont.dot(500, 8)).tracking(0.16 * 8)
                    .foregroundStyle(NB.white.opacity(0.34))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct ToggleRow: View {
    let title: String
    let detail: String
    var detailIsSentence = false
    @Binding var isOn: Bool
    var enabled = true
    var last = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                    .foregroundStyle(enabled ? NB.text1 : NB.text2)
                Text(detail)
                    .font(detailIsSentence ? NBFont.ui(400, 11.5) : NBFont.dot(500, 10))
                    .tracking(detailIsSentence ? 0.02 * 11.5 : 0.14 * 10)
                    .foregroundStyle(NB.white.opacity(0.34))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn).labelsHidden().tint(NB.lime1).disabled(!enabled)
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .opacity(enabled ? 1 : 0.55)
        .overlay(alignment: .bottom) { last ? nil : Hairline().padding(.leading, 16) }
    }
}

private struct NavRow: View {
    let title: String
    let detail: String
    let value: String
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
                    .font(NBFont.dot(500, 11))
                    .foregroundStyle(NB.text3Prod)
                Chevron()
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
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
        HStack {
            Text(L(name))
                .font(NBFont.ui(500, 11)).tracking(0.16 * 11)
                .foregroundStyle(NB.text3Prod)
            Spacer(minLength: 0)
            Text(value)
                .font(NBFont.dot(500, 11)).tracking(0.06 * 11)
                .foregroundStyle(NB.text2)
        }
        .frame(height: 38)
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
                                title: Self.title(slot.kind),
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
                                detailIsLime: firmwareOwnsInterval
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
        firmwareOwnsInterval
            ? "This HOOP only lets you turn each sensor on or off. How often it measures is decided by the firmware."
            : "Choose each sensor's own interval. Shorter intervals use more battery."
    }

    private var footer: String {
        firmwareOwnsInterval
            ? L("The interval itself is not a setting on this firmware.")
            : L("Only what this HOOP can measure is listed")
    }

    @ViewBuilder
    private var emptyState: some View {
        switch read {
        case .failed(let headline, let sentence):
            EdgeNote(line: headline, text: sentence)
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
        case .bloodGlucose:    "Blood glucose"
        case .stress:          "Stress"
        case .bloodOxygen:     "Blood oxygen"
        case .temperature:     "Skin temperature"
        case .lorentz:         "Lorentz"
        case .hrv:             "HRV"
        case .bloodComponents: "Blood components"
        }
    }

    private static func detail(_ slot: AutoMonitorSlot, firmwareOwnsInterval: Bool) -> String {
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
                // ⚠️ The SDK only offers disconnect(). "Forget" is the app dropping its own
                // device id — "factory reset" is not something we can do, and the difference
                // between those two sentences has to be kept word for word.
                BoundBand.forget()
                Task { await Band.live.disconnect() }
                data.band.connected = false
                dismiss()
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
                data.band.connected = false
                dismiss()
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
#endif
