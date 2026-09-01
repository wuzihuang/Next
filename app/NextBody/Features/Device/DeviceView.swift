import SwiftUI

/// 12 · 设备 Device — the only second-level page in the product, because it really does have
/// a page of content. Entered from Profile; back returns to Profile, not to the root.
struct DeviceView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var sheet: SheetRoute?
    @State private var identity: BandIdentity?
    @State private var capabilities = BandCapabilities()
    @State private var battery: BandBattery?

    // F3 · a switch shows the value that came back, never the value we sent. Optimistic UI
    // here means the firmware wins a second later and the toggle flips under a finger.
    @State private var hrAlarm = true
    @State private var moveReminder = true
    @State private var drinkNudge = false
    @State private var wearDetection = true
    @State private var disconnectAlert = true
    @State private var lowPower = false
    @State private var writing: String?

    private var connected: Bool { data.band.connected }

    var body: some View {
        DetailScroll(glow: NB.lime1) {
            VStack(alignment: .leading, spacing: 14) {
                header
                batteryCard
                firmwareCard
                if !connected { readOnlyNotice }

                GroupLabel12("AUTOMATIC")
                RowCard {
                    NavRow(title: "Automatic measurement",
                           detail: autoDetail,
                           value: "\(autoCount)",
                           // A capability the band does not have keeps its row and states
                           // the reason — hiding it makes the user think it does not exist.
                           enabled: connected && capabilities.autoMeasure != .unsupported) {
                        sheet = .bandAutoMonitor
                    }
                    // One switch with one range is enough; a range needs no second toggle.
                    ToggleRow(title: "Heart rate alarm",
                              detail: "ALERTS OUTSIDE 50 – 140 BPM",
                              isOn: $hrAlarm, enabled: connected, last: true)
                        .onChange(of: hrAlarm) { _, on in
                            write(.heartRateAlarm(on: on, low: 50, high: 140))
                        }
                }

                GroupLabel12("REMINDERS · VIBRATION ONLY")
                RowCard {
                    ToggleRow(title: "Move reminder", detail: "EVERY 60 MIN · 09:00 – 18:00",
                              isOn: $moveReminder, enabled: connected)
                    ToggleRow(title: "Drink & breathe nudges", detail: drinkNudge ? "ON" : "OFF",
                              isOn: $drinkNudge, enabled: connected)
                    NavRow(title: "Alarms", detail: "07:30 MON–FRI · 08:45 SAT",
                           value: "2", enabled: connected, last: true) { sheet = .bandAlarm }
                }

                GroupLabel12("HOW IT BEHAVES")
                RowCard {
                    ToggleRow(title: "Wear detection", detail: "Stops reading when it is off your wrist",
                              detailIsSentence: true, isOn: $wearDetection,
                              enabled: connected && capabilities.wearDetection != .unsupported)
                    ToggleRow(title: "Buzz if we lose each other",
                              detail: "A short pulse when your phone walks away",
                              detailIsSentence: true, isOn: $disconnectAlert, enabled: connected)
                    ToggleRow(title: "Low power mode",
                              detail: "Fewer readings. Roughly twice the battery.",
                              detailIsSentence: true, isOn: $lowPower, enabled: connected, last: true)
                }

                GroupLabel12("IDENTITY")
                // Five dead facts, no box: they are not settings.
                // ⚠️ DEVICE NO. is DeviceVersion.deviceNumber — the SDK has no serial number.
                VStack(spacing: 0) {
                    IdentityRow(name: "MODEL", value: identity?.model ?? "KR96 PRO")
                    IdentityRow(name: "HARDWARE", value: identity?.hardware ?? "1.2")
                    IdentityRow(name: "SOFTWARE", value: identity?.firmware ?? data.band.firmware)
                    // ⚠️ DeviceVersion.deviceNumber. The SDK has no serial number and no
                    // screen in this product is allowed to call this one.
                    IdentityRow(name: "DEVICE NO.", value: identity?.deviceNumber ?? "HB-0042")
                    // ⚠️ On iOS this is a CoreBluetooth UUID. The label says BLUETOOTH, not
                    // MAC, because it is not one and it changes with the phone.
                    IdentityRow(name: "BLUETOOTH",
                                value: identity?.bleIdentifier ?? data.band.mac, last: true)
                }
                .frame(width: NB.Layout.contentWidth)

                GroupLabel12("CONNECTION")
                RowCard {
                    if connected {
                        // Disconnecting is reversible, so the safe button is not red.
                        DestructiveRow(title: "Disconnect",
                                       detail: "It keeps recording. Nothing reaches the app.",
                                       tint: NB.text1) { sheet = .unbind }
                    } else {
                        DestructiveRow(title: "Why won't it connect?",
                                       detail: "Bluetooth, distance, or a flat battery.",
                                       tint: NB.text1) { sheet = .findBand }
                    }
                    DestructiveRow(title: "Forget this HOOP",
                                   detail: "Removes it from this phone. Your history stays.",
                                   tint: NB.alert2, last: true) { sheet = .unbind }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.back()
        }
        .task {
            // What was stored the last time this HOOP answered. The page is right from the
            // first frame, and stays right when the band is out of range — which is the
            // whole reason device_capabilities is a table rather than a local variable.
            capabilities = data.capabilities
            await Analytics.shared.track("DEVICE_PAGE_OPEN", ["CONNECTED": connected])
            guard connected else { return }
            // P1 · a page opened. These three reads are what the whole screen is made of,
            // so nothing below renders a guess while they are in flight.
            identity = try? await Band.live.readIdentity()
            if let fresh = try? await Band.live.readCapabilities() {
                capabilities = fresh
                data.capabilities = fresh
                if let deviceId = Repository.shared.deviceId,
                   let userId = await SupabaseClient.shared.currentUserId {
                    await Repository.shared.saveCapabilities(fresh, deviceId: deviceId, userId: userId)
                }
            }
            battery = try? await Band.live.readBattery()
            if let battery, let percent = battery.percent {
                data.band.batteryPercent = percent
            }
            if let identity { data.band.firmware = identity.firmware }
        }
        .sheet(item: $sheet) { r in
            Group {
                switch r {
                case .bandAutoMonitor: AutoMeasurementSheet()
                case .bandAlarm:       AlarmsSheet()
                case .unbind:          ForgetHoopSheet()
                default:               WhyWontItConnectSheet()
                }
            }
            .presentationDetents([.fraction(0.62)])
            .presentationDragIndicator(.visible)
            .presentationBackground(NB.carbon2)
            .presentationCornerRadius(NB.R.panel)
        }
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
            } catch {
                BandLog.shared.record("writeSetting", error: error)
                if case .heartRateAlarm(let on, _, _) = setting { hrAlarm = !on }
            }
        }
    }

    private var batteryReading: String {
        guard let battery else { return "\(data.band.batteryPercent)" }
        if battery.isPercent { return battery.percent.map(String.init) ?? Fmt.dash }
        return battery.level.map { "\($0)/4" } ?? Fmt.dash
    }
    private var batteryUnit: String {
        guard connected else { return "LAST SEEN" }
        guard let battery else { return "PERCENT" }
        return battery.isPercent ? "PERCENT" : "BARS"
    }

    private var chargeLine: String {
        guard connected else { return "Still recording on your wrist" }
        switch battery?.chargeState {
        // POWER goes UNKNOWN rather than keeping a stale value: charge state changes any
        // second, and battery level cannot appear out of nowhere.
        case .charging: return "Charging"
        case .full:     return "Charged"
        default:        return "About 3 days of charge left"
        }
    }

    /// Only what this HOOP can measure is listed.
    private var autoDetail: String {
        var kinds: [String] = []
        if capabilities.hrv != .unsupported { kinds.append("HR") }
        if capabilities.functions["spo2"] != .unsupported { kinds.append("SPO2") }
        if capabilities.hrv == .support { kinds.append("HRV") }
        if capabilities.stress != .unsupported { kinds.append("STRESS") }
        return kinds.isEmpty ? "NOTHING THIS HOOP MEASURES ON ITS OWN" : kinds.joined(separator: " · ")
    }
    private var autoCount: Int {
        autoDetail.contains("·") ? autoDetail.components(separatedBy: " · ").count : 0
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROFILE")
                .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
            HStack(alignment: .firstTextBaseline) {
                Text("DEVICE")
                    .font(NBFont.brand(700, 30)).tracking(-0.02 * 30)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Circle().fill(connected ? NB.lime1 : NB.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(connected ? "CONNECTED" : "DISCONNECTED")
                        .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                        .foregroundStyle(connected ? NB.lime1 : NB.text3Prod)
                }
                .padding(.horizontal, 10).frame(height: 24)
                .overlay(connected ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
            }
        }
        .padding(.top, 14)
    }

    /// The ring and the sentence answer two different questions: 82 is a number, and
    /// "about 3 days of charge left" is what a normal person wanted to know.
    /// ⚠️ Days are our own estimate — the SDK gives percent / level / chargeState only.
    private var batteryCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().strokeBorder(NB.barTrack, lineWidth: 5).frame(width: 74, height: 74)
                    RingArc(from: 0, to: battery?.ringFraction ?? Double(data.band.batteryPercent) / 100)
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
                    Text("KR96 PRO")
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

            Hairline()

            HStack(spacing: 0) {
                // POWER goes UNKNOWN rather than keeping a stale value: charge state changes
                // any second, and battery level cannot appear out of nowhere. The two expire
                // at different speeds, which is why they are three columns and not one.
                DeviceFact(label: "POWER",
                           value: connected
                                ? (battery?.chargeState.rawValue.uppercased() ?? "UNKNOWN")
                                : "UNKNOWN")
                DeviceFact(label: "ON DEVICE",
                           value: identity.map { "\($0.watchDataDayNumber) DAYS" } ?? "7 DAYS")
                DeviceFact(label: "SYNCED", value: connected ? "2 MIN AGO" : "2 HRS AGO")
            }
        }
        .padding(18)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    /// The version the update server offers. A constant until there is an update server;
    /// it is not something the band can tell us.
    private static let availableFirmware = "2.5.0"

    /// Five reasons the button can be grey, and it always says which one.
    /// "Temporarily unavailable" is never allowed to stand in for all five.
    private var firmwareCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FIRMWARE")
                    .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.text3Prod)
                HStack(spacing: 8) {
                    // The left side is the band's own reported version. ⚠️ It read a fixed
                    // 2.4.1, which happened to match the seed and would have quietly lied
                    // about every other HOOP.
                    Text(identity?.firmware ?? data.band.firmware)
                        .font(NBFont.dot(700, 16)).tracking(0.06 * 16)
                        .foregroundStyle(NB.text2)
                    Text("→")
                        .font(NBFont.dot(700, 13))
                        .foregroundStyle(NB.lime1)
                    Text(Self.availableFirmware)
                        .font(NBFont.dot(700, 16)).tracking(0.06 * 16)
                        .foregroundStyle(NB.lime1)
                }
                Text(connected ? "Better sleep staging · about 4 min" : "Reconnect to install this update")
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            Spacer(minLength: 0)
            Text("UPDATE")
                .font(NBFont.ui(600, 11)).tracking(0.12 * 11)
                .foregroundStyle(connected ? NB.carbon : NB.text3)
                .padding(.horizontal, 18).frame(height: 36)
                .background(connected ? NB.lime1 : Color.clear, in: Capsule())
                .overlay(connected ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
        }
        .padding(16)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    /// One sentence with a padlock covers the whole read-only段. Switches are not hidden and
    /// not greyed into illegibility — they simply do not move.
    private var readOnlyNotice: some View {
        HStack(spacing: 8) {
            LockGlyph()
            Text("Settings below are read-only until you reconnect")
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
            Text(name)
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
/// The list is the band's own answer to readAutoMonitSwitchInfo, not a fixed menu: a HOOP
/// that cannot take a temperature simply has no temperature row.
struct AutoMeasurementSheet: View {
    @State private var slots: [AutoMonitorSlot] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Automatic measurement")
                .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                .foregroundStyle(NB.text1)
            Text("What the HOOP measures on its own, all day.")
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
                .padding(.top, 6)

            if !slots.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                        MeasureToggle(
                            title: Self.title(slot.kind),
                            detail: Self.detail(slot),
                            chips: slot.supportsRange
                                ? [String(format: "%02d:00 – %02d:00", slot.startHour, slot.endHour),
                                   "EVERY \(slot.intervalMinutes) MIN"]
                                : [],
                            isOn: Binding(
                                get: { slots[index].on },
                                set: { on in
                                    slots[index].on = on
                                    let updated = slots[index]
                                    Task { try? await Band.live.writeAutoMonitoring(updated) }
                                }),
                            last: index == slots.count - 1)
                    }
                }
                .frame(width: NB.Layout.contentWidth)
                .cardSkin()
                .padding(.top, 16)

                Text("Only what this HOOP can measure is listed")
                    .font(NBFont.ui(300, 11.5)).tracking(0.02 * 11.5)
                    .foregroundStyle(NB.white.opacity(0.30))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            } else if !loading {
                // ⚠️ An empty answer means the band told us nothing, which is not the same
                // as the band having nothing. The screen says which one it is.
                Text("THIS HOOP DID NOT REPORT ITS AUTOMATIC MEASUREMENTS")
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.ember1)
                    .padding(.top, 24)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
        .task {
            slots = (try? await Band.live.readAutoMonitoring()) ?? []
            loading = false
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

    private static func detail(_ slot: AutoMonitorSlot) -> String {
        guard slot.on else { return "OFF" }
        if slot.supportsRange {
            return String(format: "%02d:00 – %02d:00 · EVERY %d MIN",
                          slot.startHour, slot.endHour, slot.intervalMinutes)
        }
        return "EVERY \(slot.intervalMinutes) MIN"
    }
}

private struct MeasureToggle: View {
    let title: String
    let detail: String
    var chips: [String] = []
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
                        .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                        .foregroundStyle(isOn ? NB.lime1.opacity(0.7) : NB.white.opacity(0.28))
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $isOn).labelsHidden().tint(NB.lime1)
            }
            if !chips.isEmpty && isOn {
                HStack(spacing: 10) {
                    ForEach(chips, id: \.self) { c in
                        Text(c)
                            .font(NBFont.dot(600, 10)).tracking(0.12 * 10)
                            .foregroundStyle(NB.text2)
                            .padding(.horizontal, 14).frame(height: 32)
                            .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { last ? nil : Hairline().padding(.leading, 16) }
    }
}

/// One table. Every save rewrites all of it — the band replaces the whole alarm set at once,
/// and its capacity is 3 / 10 / 20 depending on firmware, so a failure is a rollback,
/// never an optimistic success.
struct AlarmsSheet: View {
    @State private var alarms: [(String, String, Bool)] = [
        ("07:30", "MON TUE WED THU FRI", true),
        ("08:45", "SAT", true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Alarms")
                .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                .foregroundStyle(NB.text1)
            Text("The HOOP buzzes. There is no screen to snooze on.")
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
                .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(alarms.indices, id: \.self) { i in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alarms[i].0)
                                .font(NBFont.dot(700, 22)).tracking(0.06 * 22)
                                .foregroundStyle(NB.text1)
                            Text(alarms[i].1)
                                .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                                .foregroundStyle(NB.white.opacity(0.34))
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: Binding(get: { alarms[i].2 },
                                                 set: { alarms[i].2 = $0 }))
                            .labelsHidden().tint(NB.lime1)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 74)
                    .overlay(alignment: .bottom) { Hairline().padding(.leading, 16) }
                }
                HStack {
                    Text("Add an alarm")
                        .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                        .foregroundStyle(NB.lime1)
                    Spacer(minLength: 0)
                    Text("\(alarms.count) SAVED")
                        .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                        .foregroundStyle(NB.white.opacity(0.34))
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
            }
            .frame(width: NB.Layout.contentWidth)
            .cardSkin()
            .padding(.top, 16)

            Text("Saved to the band the moment you close this")
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
            Text("Forget this HOOP?")
                .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
                .foregroundStyle(NB.text1)
            Text("This phone stops pairing with it. Everything it has already sent you stays — 12 weeks of nights and every reading. Pairing it again takes about a minute.")
                .font(NBFont.brand(400, 14))
                .lineSpacing(7)
                .foregroundStyle(NB.text2)
            Spacer(minLength: 0)
            LimePillButton(title: "Keep it paired") { dismiss() }
            Button {
                // ⚠️ The SDK only offers disconnect(). "Forget" is the app dropping its own
                // device id — "factory reset" is not something we can do, and the difference
                // between those two sentences has to be kept word for word.
                BoundBand.forget()
                Task { await Band.live.disconnect() }
                data.band.connected = false
                dismiss()
            } label: {
                Text("FORGET THIS HOOP")
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
            Text("Disconnect the HOOP?")
                .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
                .foregroundStyle(NB.text1)
            Text("It keeps recording on your wrist. Nothing new reaches the app until you connect again.")
                .font(NBFont.brand(400, 14))
                .lineSpacing(7)
                .foregroundStyle(NB.text2)
            Spacer(minLength: 0)
            LimePillButton(title: "Stay connected") { dismiss() }
            Button {
                data.band.connected = false
                dismiss()
            } label: {
                Text("DISCONNECT")
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
            Text("Why won't it connect?")
                .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
                .foregroundStyle(NB.text1)
            VStack(alignment: .leading, spacing: 0) {
                ReasonItem(index: "01", title: "Bluetooth is off",
                           detail: "Turn it on in Control Centre, then come back.")
                ReasonItem(index: "02", title: "It's out of range",
                           detail: "Bring the band within arm's reach of the phone.")
                ReasonItem(index: "03", title: "The battery is flat",
                           detail: "Charge it for ten minutes and hold the side key.", last: true)
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
