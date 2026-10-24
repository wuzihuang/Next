import SwiftUI
import UIKit

/// 02 · Connect 手环配对. No back key out of the flow and no "later":
/// the success screen has exactly one button and it hands straight over to onboarding.
struct ConnectFlow: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var data: DataStore

    enum Step: Int, Hashable { case turnOn = 1, searching, found, pairing, connected }
    @State private var step: Step = .turnOn
    @State private var progress: Double = 0
    @State private var pairStage = 0
    @State private var found: DiscoveredBand?
    @State private var scanTask: Task<Void, Never>?
    /// 02 edges · every failure degrades on the screen it happened on: colour and two lines.
    enum ScanEdge { case nothingFound, bluetoothOff, permission }
    enum PairEdge { case stopped, taken, owned, unsaved }
    /// The band answered, but the server did not take it as this account's.
    private enum PairingRefusal: Error { case owned, unsaved }
    @State private var scanEdge: ScanEdge?
    @State private var pairEdge: PairEdge?
    @State private var pairFailures = 0
    /// 02 rule 05 · low battery never blocks pairing; one amber line on the success screen.
    @State private var lowBatteryLine: String?
    @State private var scanBegan: Date?

    /// 04 · the percentage maps to four real steps; the number moves when the band answers.
    private static let stages = ["CONNECT", "AUTHORISE", "READ CAPABILITIES", "READ FIRMWARE"]

    var body: some View {
        ZStack {
            switch step {
            case .turnOn:    TurnItOn { go(.searching) }
            case .searching: Searching(onBack: { go(.turnOn) }, found: found, edge: scanEdge,
                                       onSearchAgain: { go(.searching) }) { go(.found) }
            case .found:     FoundIt(band: found,
                                     onBack: { go(.searching) },
                                     onConnect: { go(.pairing) },
                                     onSearchAgain: { go(.searching) })
            case .pairing:   Pairing(progress: progress, stage: pairStage, edge: pairEdge, failures: pairFailures,
                                     onRetry: { go(.pairing) }, onSearchAgain: { go(.searching) })
            case .connected: Connected(lowBattery: lowBatteryLine) { handOffAfterPair() }
            }
        }
        .carbonPage()
        .animation(nil, value: step)
        // 02 edge 2 · the radio going off mid-search ends the search; coming back restarts it.
        .onReceive(BluetoothState.shared.$poweredOff.dropFirst()) { off in
            guard step == .searching else { return }
            if off { scanTask?.cancel(); Task { await Band.live.stopScan() }; scanEdge = .bluetoothOff }
            else if scanEdge == .bluetoothOff { runScan() }
        }
        .onReceive(BluetoothState.shared.$permissionDenied.dropFirst()) { denied in
            guard step == .searching else { return }
            if denied { scanTask?.cancel(); Task { await Band.live.stopScan() }; scanEdge = .permission }
            else if scanEdge == .permission { runScan() }
        }
        .task { await session.ensureSession() }
        #if DEBUG
        // `SIMCTL_CHILD_NB_DEBUG_CONNECT_STEP=3` opens the flow on that screen for a walk —
        // the screen only, none of the scan or pairing work behind it.
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["NB_DEBUG_CONNECT_STEP"],
               let n = Int(raw), let st = Step(rawValue: n) {
                step = st
                if st == .searching {
                    if DebugEdge.on("nothingfound") { scanEdge = .nothingFound }
                    else if DebugEdge.on("btoff") { scanEdge = .bluetoothOff }
                    else if DebugEdge.on("permission") { scanEdge = .permission }
                }
                if st == .found, found == nil {
                    found = DiscoveredBand(id: "debug-found", name: "NEXTBODY",
                                          rssi: -48, batteryPercent: 96)
                }
                if st == .pairing {
                    if let raw = ProcessInfo.processInfo.environment["NB_DEBUG_PAIR_PROGRESS"],
                       let pin = Double(raw) {
                        progress = min(1, max(0, pin))
                    } else {
                        progress = 0.60
                    }
                    pairStage = 2
                    if DebugEdge.on("stopped") { pairEdge = .stopped; pairFailures = 1 }
                    if DebugEdge.on("taken") { pairEdge = .taken }
                    if DebugEdge.on("owned") { pairEdge = .owned }
                }
                if st == .connected, DebugEdge.on("lowbattery") {
                    lowBatteryLine = "BATTERY 8%"
                }
            }
        }
        #endif
    }

    private func go(_ s: Step) {
        step = s
        switch s {
        case .searching: runScan()
        case .pairing:   runPairing()
        default:         scanTask?.cancel()
        }
    }

    /// UNPAIRED · a finished About You is not asked again. NEW / PROFILE GAP go to onboarding.
    private func handOffAfterPair() {
        #if DEBUG
        if FlowRehearsal.on { session.stage = .gateOnboarding; return }
        #endif
        Task {
            await session.ensureSession()
            let facts = await Repository.shared.fetchAccountGate()
            session.stage = facts.profileComplete ? .root : .gateOnboarding
        }
    }

    /// 02 · 02 · the first band found ends the scan. One account owns one band, so a list
    /// would be a list of things you cannot choose between.
    private func runScan() {
        found = nil
        scanEdge = nil
        scanTask?.cancel()
        // DEBUG · 02 edges 1 and 2 on a simulator whose mock band always answers.
        if DebugEdge.on("nothingfound") { scanEdge = .nothingFound; return }
        if DebugEdge.on("btoff") { scanEdge = .bluetoothOff; return }
        if DebugEdge.on("permission") { scanEdge = .permission; return }
        #if DEBUG
        if FlowRehearsal.on {
            scanTask = Task {
                await FlowRehearsal.pause(3.5)
                guard !Task.isCancelled, step == .searching else { return }
                found = FlowRehearsal.band
                go(.found)
            }
            return
        }
        #endif
        scanBegan = Date()
        Task { await Analytics.shared.track("PAIR_START", [:]) }
        scanTask = Task {
            await BluetoothState.shared.waitForState()
            guard !Task.isCancelled, step == .searching else { return }
            if BluetoothState.shared.poweredOff { scanEdge = .bluetoothOff; return }
            if BluetoothState.shared.permissionDenied { scanEdge = .permission; return }
            await Band.live.startScan()
            // 02 rule 01 · scan 15 s (provisional). Edge 1 · the ripples stop, the line changes,
            // the screen stays: 「空态不是新页面，就是 02 屏本身」.
            let timeout = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, found == nil, step == .searching else { return }
                await Band.live.stopScan()
                scanEdge = .nothingFound
                await Analytics.shared.track("PAIR_FAIL", ["REASON": "NOTHING_FOUND", "STEP": "SCAN"])
            }
            // Two Veepoo bands in one room both match the SDK's scan (a G70 and an R30 ECG
            // were seen side by side on the device). The first advertisement to arrive is
            // whichever radio ticked first, so after it the scan listens 1.5 s more and keeps
            // the strongest signal: the band on your wrist, next to the phone.
            var best: DiscoveredBand?
            var settle: Task<Void, Never>?
            for await event in Band.live.events {
                if Task.isCancelled { timeout.cancel(); settle?.cancel(); return }
                guard case .discovered(let device) = event else { continue }
                if best == nil || device.rssi > best!.rssi { best = device }
                if settle == nil {
                    timeout.cancel()
                    settle = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled, let pick = best, step == .searching else { return }
                        found = pick
                        await Band.live.stopScan()
                        let ms = Int((scanBegan.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
                        await Analytics.shared.track("PAIR_DEVICE_FOUND", ["MS": ms, "RSSI": pick.rssi])
                        go(.found)
                    }
                }
            }
        }
    }

    /// 02 · 04 · the percentage maps to four real steps — connect, authorise, read the
    /// capability table, read the firmware version. When it stalls it stalls on the number
    /// it reached: stopping is more honest than snapping back to zero.
    private func runPairing() {
        progress = 0; pairStage = 0; pairEdge = nil
        #if DEBUG
        if FlowRehearsal.on {
            Task {
                for (value, stage) in [(0.12, 0), (0.35, 1), (0.60, 2), (0.85, 3), (1.0, 3)] {
                    await FlowRehearsal.pause(1.1)
                    mark(value, stage: stage)
                }
                await FlowRehearsal.pause(0.6)
                step = .connected
            }
            return
        }
        #endif
        let began = Date()
        Task {
            do {
                guard let device = found else { throw BandError.notConnected }
                await session.ensureSession()

                // 02 rule 02 · four fixed segments: connect 0–35, authorise 35–60, capabilities
                // 60–85, version and battery 85–100. The number moves when the band answers.
                if DebugEdge.on("stopped") { throw BandError.timeout("connect") }
                if DebugEdge.on("taken") { throw BandError.rejected("paired elsewhere") }
                pairStage = 0
                try await Band.live.connect(device, progress: { p in
                    Task { @MainActor in mark(0.35 * p, stage: 0) }
                })
                mark(0.35, stage: 1)
                let identity = try await Band.live.readIdentity()

                mark(0.60, stage: 2)
                // The capability table decides which measurement entries exist at all,
                // so it is read before the first screen that could offer one.
                let caps = try await Band.live.readCapabilities()

                mark(0.85, stage: 3)
                let battery = try await Band.live.readBattery()
                mark(1.0, stage: 3)
                // 02 rule 05 · isPercent false → BATTERY LOW, never an invented percent.
                if DebugEdge.on("lowbattery") { lowBatteryLine = "BATTERY 8%" }
                else if !battery.isPercent { if (battery.level ?? 4) <= 1 { lowBatteryLine = "BATTERY LOW" } }
                else if let p = battery.percent, p < 10 { lowBatteryLine = "BATTERY \(p)%" }

                // A band is one account's (20261024150000). Only a binding the server took
                // counts: anything else leaves this phone holding nothing, link down.
                switch await Repository.shared.registerDevice(identity: identity, battery: battery, pairing: true) {
                case .saved: break
                case let refused:
                    BoundBand.identifier = nil
                    await Band.live.disconnect()
                    throw refused == .ownedElsewhere || refused == .alreadyInSet
                        ? PairingRefusal.owned : PairingRefusal.unsaved
                }

                data.band = BandState(
                    connected: true, name: identity.name, mac: identity.bleIdentifier,
                    batteryPercent: battery.percent, chargeState: battery.chargeState,
                    firmware: identity.firmware,
                    lastBattery: battery,
                    lastSync: Date(),
                    capabilities: Self.capabilitySet(caps))
                data.applyBandObservation(identity: identity, battery: battery)
                if let deviceId = Repository.shared.deviceId,
                   let userId = await SupabaseClient.shared.currentUserId {
                    await Repository.shared.saveCapabilities(caps, deviceId: deviceId, userId: userId,
                                                              holdsDays: identity.watchDataDayNumber)
                }
                let ms = Int(Date().timeIntervalSince(began) * 1000)
                await Analytics.shared.track("PAIR_SUCCESS", [
                    "MS": ms, "FW": identity.firmware, "BATTERY": battery.percent ?? -1,
                ])
                step = .connected
            } catch {
                // Every failure degrades in place, on the screen it happened on. That rule
                // was set here in Connect, and this page is where it is enforced.
                BandLog.shared.record("pairing", error: error)
                // 02 edge 4 / 5 · the arms stop, the number freezes where it was, and the two
                // lines say what happened. TAKEN is the one failure with a named cause.
                pairFailures += 1
                switch error {
                case PairingRefusal.owned: pairEdge = .owned
                case PairingRefusal.unsaved: pairEdge = .unsaved
                case BandError.rejected: pairEdge = .taken
                default: pairEdge = .stopped
                }
                let reason = switch pairEdge {
                case .taken: "TAKEN"
                case .owned: "OWNED"
                case .unsaved: "UNSAVED"
                default: "STOPPED"
                }
                await Analytics.shared.track("PAIR_FAIL", ["REASON": reason, "STEP": Self.stages[min(pairStage, 3)]])
            }
        }
    }

    private func mark(_ value: Double, stage: Int) {
        pairStage = stage
        withAnimation(.easeOut(duration: 0.2)) { progress = max(progress, min(1, value)) }
    }

    private static func capabilitySet(_ caps: BandCapabilities) -> Set<BandState.Capability> {
        var out: Set<BandState.Capability> = []
        if caps.bodyComponent == .support { out.insert(.bodyComponent) }
        if caps.ecg == .support { out.insert(.ecg) }
        if caps.hrv == .support || caps.functions["heart"] == .support { out.insert(.heartRate) }
        if caps.functions["temperature"] == .support { out.insert(.temperature) }
        if caps.autoMeasure == .support { out.insert(.alarms) }
        if caps.wearDetection == .support { out.insert(.wearDetection) }
        if caps.functions["spo2"] == .support { out.insert(.bloodOxygen) }
        if caps.functions["blood"] == .support { out.insert(.bloodPressure) }
        return out
    }
}

// MARK: shared chrome

private struct PairHeader: View {
    let index: Int
    var onBack: (() -> Void)?
    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    ZStack {
                        Circle().fill(NB.carbon4)
                        Circle().stroke(NB.hairline, lineWidth: 1)
                        ChevronGlyph()
                    }.frame(width: 44, height: 44)
                }.buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            Text(L("PAIRING %02d / 05", index))
                .font(NBFont.dot(600, 11)).tracking(0.3 * 11)
                .foregroundStyle(NB.text3Prod)
        }
        .frame(width: NB.Layout.contentWidth, height: 44)
    }
}

private struct PairTitle: View {
    let title: String
    let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(NBFont.ui(500, 32)).tracking(0.01 * 32)
                .foregroundStyle(NB.text1)
            Text(sub)
                .font(NBFont.ui(300, 15)).tracking(0.02 * 15)
                .lineSpacing(24 - 15)
                .foregroundStyle(NB.text2)
                .frame(width: 320, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 24)
    }
}

struct LimePillButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NBFont.ui(500, 15)).tracking(0.06 * 15)
                .foregroundStyle(NB.carbon)
                .frame(width: NB.Layout.contentWidth, height: 56)
                .background(NB.lime1, in: Capsule())
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: 01 · 开机 Turn it on

private struct TurnItOn: View {
    let onNext: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            BandPortrait(sideKeyLit: true, ripples: [34, 58, 82], rippleAlpha: [0.42, 0.20, 0.08])
                .frame(width: NB.Layout.screenWidth, height: 470)
                .offset(y: Chrome.boardY(252))

            VStack(spacing: 0) {
                Color.clear.frame(height: Chrome.gateTopInset)
                PairHeader(index: 1)
                PairTitle(title: L("Turn it on"),
                          sub: L("Hold the button on the right edge for two seconds, until the band lights up."))
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            Text(L("HOLD 2S"))
                .font(NBFont.dot(800, 13)).tracking(0.24 * 13)
                .foregroundStyle(NB.lime1)
                .frame(width: NB.Layout.screenWidth, alignment: .center)
                .offset(y: Chrome.boardY(608))

            // The only real dead end in the flow, answered on the screen it happens on.
            Text(L("Nothing lights up? It may be flat — charge it for ten minutes, then hold again."))
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .lineSpacing(20 - 13)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.text3Prod)
                .frame(width: NB.Layout.screenWidth - 64)
                .offset(x: 32, y: Chrome.boardY(640))

            LimePillButton(title: L("It's on"), action: onNext)
                .offset(x: 16, y: Chrome.boardY(708))

        }
        .frame(width: NB.Layout.screenWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The band seen head-on: strap fading top and bottom, case, dot-matrix face, lime side key.
struct BandPortrait: View {
    var sideKeyLit = false
    var faceLit = false
    var ripples: [CGFloat] = []
    var rippleAlpha: [Double] = []
    var scanRings: [CGFloat] = []

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 390, sy = size.height / 470
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy),
                     cornerRadius: rad * sx)
            }
            let strap = Color(hex: 0x15161A)
            ctx.fill(r(161, 0, 68, 118, 14),
                     with: .linearGradient(Gradient(colors: [strap.opacity(0), strap]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 118 * sy)))
            ctx.fill(r(161, 302, 68, 168, 14),
                     with: .linearGradient(Gradient(colors: [strap, strap.opacity(0)]),
                                           startPoint: CGPoint(x: 0, y: 302 * sy),
                                           endPoint: CGPoint(x: 0, y: 470 * sy)))
            ctx.fill(r(139, 112, 112, 196, 36), with: .color(Color(hex: 0x17181C)))
            ctx.stroke(r(139, 112, 112, 196, 36), with: .color(NB.white.opacity(0.07)), lineWidth: 1)

            // face · the LEDs light up, the panel behind them does not.
            // A solid lime block would read as a lamp; the band is a dot screen.
            let face = r(153, 126, 84, 168, 26)
            ctx.fill(face, with: .color(Color(hex: 0x0A0A0D)))
            ctx.clip(to: face)
            var dots = Path()
            var y: CGFloat = 127
            while y < 294 {
                var x: CGFloat = 154
                while x < 237 {
                    dots.addRoundedRect(in: CGRect(x: x * sx, y: y * sy, width: 3.2 * sx, height: 3.2 * sy),
                                        cornerSize: CGSize(width: 0.8 * sx, height: 0.8 * sx))
                    x += 4
                }
                y += 4
            }
            ctx.fill(dots, with: .color(faceLit ? NB.lime1 : Color(hex: 0x24252C)))
        }
        .overlay {
            Canvas { ctx, size in
                let sx = size.width / 390, sy = size.height / 470
                if sideKeyLit {
                    ctx.fill(Path(roundedRect: CGRect(x: 251 * sx, y: 186 * sy,
                                                      width: 8 * sx, height: 48 * sy), cornerRadius: 4 * sx),
                             with: .color(NB.lime1))
                }
                for (i, rad) in ripples.enumerated() {
                    let a = i < rippleAlpha.count ? rippleAlpha[i] : 0.2
                    ctx.stroke(Path(ellipseIn: CGRect(x: (255 - rad) * sx, y: (210 - rad) * sy,
                                                      width: rad * 2 * sx, height: rad * 2 * sy)),
                               with: .color(NB.lime1.opacity(a)), lineWidth: 3 * sx)
                }
                for rad in scanRings {
                    ctx.stroke(Path(ellipseIn: CGRect(x: (195 - rad) * sx, y: (210 - rad) * sy,
                                                      width: rad * 2 * sx, height: rad * 2 * sy)),
                               with: .color(NB.white.opacity(0.07)), lineWidth: 1.5 * sx)
                }
            }
        }
    }
}

// MARK: 02 · 搜索 Searching

private struct Searching: View {
    var onBack: (() -> Void)? = nil
    var found: DiscoveredBand?
    var edge: ConnectFlow.ScanEdge? = nil
    var onSearchAgain: () -> Void = {}
    let onFound: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            // The ripple is white and the screen has no green in it — success colour is
            // not allowed before there is a success.
            TimelineView(.animation) { tl in
                // Edge 1 · the ripples stop and go white 18%; edge 2 · the band drops to 20%.
                let t = edge == nil ? tl.date.timeIntervalSinceReferenceDate : 0
                BandPortrait(scanRings: (0..<4).map { i in
                    let p = (t * 0.35 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                    return 60 + CGFloat(p) * 130
                })
                .frame(width: NB.Layout.screenWidth, height: 470)
                .opacity(edge == nil ? 1 : edge == .bluetoothOff ? 0.2 : 0.18)
                .offset(y: Chrome.boardY(252))
            }

            VStack(spacing: 0) {
                Color.clear.frame(height: Chrome.gateTopInset)
                PairHeader(index: 2, onBack: onBack)
                PairTitle(title: L("Searching"),
                          sub: L("Keep the band close to your phone. This usually takes a few seconds."))
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            switch edge {
            case .none:
                Text(L("SCANNING"))
                    .font(NBFont.dot(600, 12)).tracking(0.34 * 12)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .frame(width: NB.Layout.screenWidth, alignment: .center)
                    .offset(y: Chrome.boardY(700))

                Text(L("Keep it within arm's reach."))
                    .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text3Prod)
                    .frame(width: NB.Layout.screenWidth, alignment: .center)
                    .offset(y: Chrome.boardY(750))

            case .nothingFound:
                // 02 edge 1 · NOTHING FOUND. Three checks in the most likely order, then the
                // outlined key. Not a new page — this is screen 02 itself.
                VStack(spacing: 14) {
                    Text(L("NOTHING FOUND"))
                        .font(NBFont.dot(600, 12)).tracking(0.22 * 12)
                        .foregroundStyle(NB.white.opacity(0.48))
                    Text(L("· Is the band lit up\n· Is it further than an arm away\n· Is it still linked to another phone"))
                        .font(NBFont.ui(300, 13)).lineSpacing(8)
                        .foregroundStyle(NB.white.opacity(0.50))
                        .frame(width: NB.Layout.contentWidth, alignment: .leading)
                    Button(action: onSearchAgain) {
                        Text(L("Search again"))
                            .font(NBFont.ui(500, 14)).tracking(0.04 * 14)
                            .foregroundStyle(NB.white)
                            .frame(width: NB.Layout.contentWidth, height: 44)
                            .overlay(Capsule().stroke(NB.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: NB.Layout.screenWidth)
                .offset(y: Chrome.boardY(604))

            case .bluetoothOff:
                // 02 edge 2 · only the status line turns amber; Settings, then rescan by itself.
                VStack(spacing: 14) {
                    Text(L("BLUETOOTH IS OFF"))
                        .font(NBFont.dot(600, 12)).tracking(0.22 * 12)
                        .foregroundStyle(NB.ember1.opacity(0.85))
                    Text(L("I can’t look for the band without it."))
                        .font(NBFont.brand(400, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        Text(L("Open Bluetooth →")).font(NBFont.ui(500, 14)).tracking(0.04 * 14).foregroundStyle(NB.lime1)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .frame(width: NB.Layout.screenWidth)
                .offset(y: Chrome.boardY(660))

            case .permission:
                VStack(spacing: 14) {
                    Text(L("PERMISSION NEEDED"))
                        .font(NBFont.dot(600, 12)).tracking(0.22 * 12)
                        .foregroundStyle(NB.ember1.opacity(0.85))
                    Text(L("Bluetooth access is off. I can’t look for the band without it."))
                        .font(NBFont.brand(400, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        Text(L("Open Settings →")).font(NBFont.ui(500, 14)).tracking(0.04 * 14).foregroundStyle(NB.lime1)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .frame(width: NB.Layout.screenWidth)
                .offset(y: Chrome.boardY(660))
            }

        }
        .frame(width: NB.Layout.screenWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

    }
}

// MARK: 03 · 找到 Found

private struct FoundIt: View {
    var band: DiscoveredBand?
    var onBack: (() -> Void)? = nil
    let onConnect: () -> Void
    let onSearchAgain: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            // The full ring only lights here: the watch is what lit up, not the app.
            Circle()
                .stroke(NB.lime1, lineWidth: 2)
                .frame(width: 232, height: 232)
                .shadow(color: NB.lime1.opacity(0.35), radius: 26)
                .position(x: NB.Layout.screenWidth / 2, y: Chrome.boardY(252) + 210)

            BandPortrait(faceLit: true)
                .frame(width: NB.Layout.screenWidth, height: 470)
                .offset(y: Chrome.boardY(252))

            VStack(spacing: 0) {
                Color.clear.frame(height: Chrome.gateTopInset)
                PairHeader(index: 3, onBack: onBack)
                PairTitle(title: L("Found it"),
                          sub: L("One band is in range. Tap connect and keep it near your phone."))
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            DeviceRow(band: band)
                .offset(x: 16, y: Chrome.boardY(600))

            LimePillButton(title: L("Connect"), action: onConnect)
                .offset(x: 16, y: Chrome.boardY(700))

            Button(action: onSearchAgain) {
                Text(L("Not your band? Search again"))
                    .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text3Prod)
                    .frame(width: NB.Layout.screenWidth)
            }
            .buttonStyle(.plain)
            .offset(y: Chrome.boardY(770))

        }
        .frame(width: NB.Layout.screenWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One found band. ⚠️ Never a serial number on this card — the SDK has no such field.
private struct DeviceRow: View {
    var band: DiscoveredBand?

    /// RSSI in dBm, not a percentage. −50 is on the desk, −90 is in the next room.
    static func bars(_ rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        switch rssi {
        case (-55)...:   return 4
        case (-67)..<(-55): return 3
        case (-80)..<(-67): return 2
        default:         return 1
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(NB.lime1.opacity(0.12))
                Circle().stroke(NB.lime1.opacity(0.35), lineWidth: 1)
                Circle().stroke(NB.lime1, lineWidth: 2).frame(width: 11, height: 11)
                Rectangle().fill(NB.lime1).frame(width: 2, height: 7).offset(y: -6)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(band?.name.uppercased() ?? "NEXTBODY")
                    .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                    .foregroundStyle(NB.text1)
                Text(L("READY TO PAIR"))
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.text3Prod)
            }
            Spacer(minLength: 0)
            // A band that has not told us its charge yet says so, rather than showing 96%.
            Text(band?.batteryPercent.map { "\($0)%" } ?? Fmt.dash)
                .font(NBFont.dot(600, 10)).tracking(0.1 * 10)
                .foregroundStyle(NB.text3Prod)
            SignalBars(level: Self.bars(band?.rssi))
        }
        .padding(.horizontal, 16)
        .frame(width: NB.Layout.contentWidth, height: 72)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.spec, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }
}

struct SignalBars: View {
    let level: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? NB.limePale : NB.white.opacity(0.18))
                    .frame(width: 3, height: 4 + CGFloat(i) * 3)
            }
        }
    }
}

// MARK: 04 · 配对 Pairing

private struct Pairing: View {
    let progress: Double
    let stage: Int
    var edge: ConnectFlow.PairEdge? = nil
    var failures = 0
    var onRetry: () -> Void = {}
    var onSearchAgain: () -> Void = {}

    private static let stages = ["CONNECT", "AUTHORISE", "READ CAPABILITIES", "READ FIRMWARE"]

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            // An ASCII planet turning in glyphs.
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { tl in
                // Edge 4 · the planet stops turning and the whole thing goes amber.
                AsciiPlanet(t: edge == nil ? tl.date.timeIntervalSinceReferenceDate : 0, progress: progress)
                    .frame(width: NB.Layout.screenWidth, height: 400)
                    .grayscale(edge == nil ? 0 : 1)
                    .colorMultiply(edge == nil ? .white : NB.ember1)
                    .offset(y: Chrome.boardY(260))
            }

            VStack(spacing: 0) {
                Color.clear.frame(height: Chrome.gateTopInset)
                PairHeader(index: 4)
                PairTitle(title: L("Pairing"), sub: L("Keep it close — pulling everything into place."))
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(edge == nil ? L("PAIRING") : L("STOPPED"))
                    .font(NBFont.dot(600, 11)).tracking(0.3 * 11)
                    .foregroundStyle(edge == nil ? NB.text3Prod : NB.ember1.opacity(0.85))
                Spacer(minLength: 0)
                // The number freezes where it was — zero would look like 「白干了」.
                Text("\(Int(progress * 100))%")
                    .font(NBFont.dot(700, 22)).tracking(0.02 * 22)
                    .foregroundStyle(edge == nil ? NB.lime1 : NB.ember1)
                    .contentTransition(.numericText())
            }
            .frame(width: NB.Layout.contentWidth)
            .offset(x: 16, y: Chrome.boardY(636))

            DottedProgress(progress: progress)
                .frame(width: NB.Layout.contentWidth, height: 6)
                .grayscale(edge == nil ? 0 : 1)
                .colorMultiply(edge == nil ? .white : NB.ember1)
                .offset(x: 16, y: Chrome.boardY(672))

            if let edge {
                VStack(alignment: .leading, spacing: 12) {
                    if edge == .taken {
                        // 02 edge 5 · the most common real reason an auth fails, named, with two steps.
                        Text(L("TAKEN BY ANOTHER PHONE"))
                            .font(NBFont.dot(600, 12)).tracking(0.22 * 12)
                            .foregroundStyle(NB.ember1.opacity(0.85))
                        Text(L("This band is still paired somewhere else."))
                            .font(NBFont.brand(400, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                        Hairline()
                        Text(L("1 · Disconnect it on that phone\n2 · Or hold the side button to restart the band"))
                            .font(NBFont.ui(300, 13.5)).lineSpacing(8).foregroundStyle(NB.white.opacity(0.60))
                    } else if edge == .owned {
                        // One band, one account: the only way through is the other account.
                        Text(L("BOUND TO ANOTHER ACCOUNT"))
                            .font(NBFont.dot(600, 12)).tracking(0.22 * 12)
                            .foregroundStyle(NB.ember1.opacity(0.85))
                        Text(L("This band belongs to another NEXTBODY account."))
                            .font(NBFont.brand(400, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                        Hairline()
                        Text(L("1 · Sign in to that account and remove it on the device page\n2 · Or pair a band of your own"))
                            .font(NBFont.ui(300, 13.5)).lineSpacing(8).foregroundStyle(NB.white.opacity(0.60))
                    } else if edge == .unsaved {
                        Text(L("Pairing could not be saved. Check your connection and try again."))
                            .font(NBFont.brand(400, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                    } else {
                        Text(L("The band stopped answering. Nothing you did wrong."))
                            .font(NBFont.brand(400, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                    }
                    Button(action: onRetry) {
                        Text(L("Try again"))
                            .font(NBFont.ui(500, 14)).tracking(0.06 * 14)
                            .foregroundStyle(NB.carbon)
                            .frame(width: NB.Layout.contentWidth, height: 44)
                            .background(NB.lime1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    // Only the second failure offers the way back to 02.
                    if failures >= 2 {
                        Button(action: onSearchAgain) {
                            Text(L("Search again"))
                                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                                .foregroundStyle(NB.text3Prod)
                                .frame(width: NB.Layout.contentWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: NB.Layout.contentWidth, alignment: .leading)
                .offset(x: 16, y: Chrome.boardY(690))
            } else {
                Text(Self.stages[min(stage, 3)])
                    .font(NBFont.dot(500, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.white.opacity(0.34))
                    .frame(width: NB.Layout.contentWidth, alignment: .leading)
                    .offset(x: 16, y: Chrome.boardY(690))

                Text(L("Keep it within arm's reach."))
                    .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text3Prod)
                    .frame(width: NB.Layout.screenWidth, alignment: .center)
                    .offset(y: Chrome.boardY(730))
            }

        }
        .frame(width: NB.Layout.screenWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct DottedProgress: View {
    let progress: Double
    /// The lime card needs a carbon bar; everywhere else the lime one is right.
    var lit: Color = NB.lime1
    var track: Color = NB.white.opacity(0.10)
    var body: some View {
        Canvas { ctx, size in
            let n = 60
            let pitch = size.width / CGFloat(n)
            for i in 0..<n {
                let on = Double(i) / Double(n) < progress
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * pitch, y: 1,
                                                  width: pitch - 2, height: 4), cornerRadius: 1),
                         with: .color(on ? lit : track))
            }
        }
    }
}

/// ASCII planet: a lit sphere of banded gas drawn in glyphs. Geometry is built once; each
/// frame only re-shades the cells. `t == 0` freezes it (edge states).
private struct AsciiPlanet: View {
    let t: TimeInterval
    let progress: Double

    private struct Cell {
        var x: CGFloat, y: CGFloat
        var u: Double, v: Double, z: Double
        var lat: Double, lon: Double
        var hash: Double
        var i: Int, j: Int
    }

    private static let diameter: CGFloat = 240
    #if DEBUG
    private static let columns = 32
    #else
    private static let columns = 51
    #endif
    private static let ramp: [String] = [" ", ".", ":", "-", "=", "+", "*", "%", "#", "@"]
    private static let cellW: CGFloat = diameter / CGFloat(columns)
    private static let cellH: CGFloat = cellW * 1.45

    private static let cells: [Cell] = {
        let R = Double(diameter / 2)
        let ni = Int(ceil(R / Double(cellW))) + 1
        let nj = Int(ceil(R / Double(cellH))) + 1
        let th = 20.0 * .pi / 180, ph = 14.0 * .pi / 180
        var out: [Cell] = []
        for j in -nj...nj {
            for i in -ni...ni {
                let dx = Double(i) * Double(cellW), dy = Double(j) * Double(cellH)
                let u = dx / R, v = dy / R
                let r2 = u * u + v * v
                if r2 > 1 { continue }
                let z = (1 - r2).squareRoot()
                let u1 = u * cos(th) - v * sin(th)
                let v1 = v * cos(th) + u * sin(th)
                let yy = -v1
                let y2 = yy * cos(ph) + z * sin(ph)
                let z2 = z * cos(ph) - yy * sin(ph)
                out.append(Cell(x: CGFloat(dx), y: CGFloat(dy), u: u, v: v, z: z,
                                lat: y2, lon: atan2(u1, z2), hash: hash3(i, j, 991), i: i, j: j))
            }
        }
        return out
    }()

    @_optimize(speed)
    private static func hash3(_ a: Int, _ b: Int, _ c: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: a &* 374761393 &+ b &* 668265263 &+ c &* 1274126177)
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Double(h) / 4294967296
    }

    @_optimize(speed)
    private static func noise(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y)), zi = Int(floor(z))
        let xf = x - Double(xi), yf = y - Double(yi), zf = z - Double(zi)
        let u = xf * xf * (3 - 2 * xf), w = yf * yf * (3 - 2 * yf), q = zf * zf * (3 - 2 * zf)
        func h(_ a: Int, _ b: Int, _ c: Int) -> Double { hash3(a &+ xi, b &+ yi, c &+ zi &+ 7) }
        let x00 = h(0, 0, 0) + (h(1, 0, 0) - h(0, 0, 0)) * u
        let x10 = h(0, 1, 0) + (h(1, 1, 0) - h(0, 1, 0)) * u
        let x01 = h(0, 0, 1) + (h(1, 0, 1) - h(0, 0, 1)) * u
        let x11 = h(0, 1, 1) + (h(1, 1, 1) - h(0, 1, 1)) * u
        let y0 = x00 + (x10 - x00) * w, y1 = x01 + (x11 - x01) * w
        return y0 + (y1 - y0) * q
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let k = clamp01((x - a) / (b - a)); return k * k * (3 - 2 * k)
    }

    var body: some View {
        Canvas { ctx, size in
            let fontSize = Self.cellH * 1.12
            let font = Font.system(size: fontSize, weight: .heavy, design: .monospaced)
            let primary = Color(hex: 0xDBE6FF), accent = NB.lime1
            var glyphs: [[GraphicsContext.ResolvedText]] = []
            for color in [primary, accent] {
                glyphs.append(Self.ramp.map { ctx.resolve(Text($0).font(font).foregroundColor(color)) })
            }

            let period = 24.0 / 1.06
            let rot = (t.truncatingRemainder(dividingBy: period) / period) * 2 * .pi
            let shearPhase = (t / (period / 4)) * 2 * .pi
            let shearA = 0.03 * 2 * .pi
            let tick = Int(floor(t * 10))
            let nb = 8.0, fill = 0.78, warp = 0.4, S = 1.4, cut = 0.15, sFloor = 0.4
            let det = 0.35, amb = 0.35, con = 1.7, empty = 0.05
            let atThr = 1 - 0.0075 * 22, shim = t == 0 ? 0 : 0.2 * 2 / 9, rimA = 0.2
            var lx = 0.2, ly = 0.2
            let lz = (max(0.05, 1 - lx * lx - ly * ly)).squareRoot()
            lx *= 1; ly *= 1
            let c = CGPoint(x: size.width / 2, y: size.height / 2)

            for cell in Self.cells {
                let y2 = cell.lat
                let lon = cell.lon - rot + shearA * sin(shearPhase + y2 * nb * 1.3)
                let cs = cos(lon), sn = sin(lon)
                let wn = Self.noise(cs * 2.2, sn * 2.2, y2 * 5 + 11) * 0.65
                    + Self.noise(cs * 4.4, sn * 4.4, y2 * 10 + 23) * 0.35 - 0.5
                let phase = (y2 + wn * warp * 0.25) * .pi * nb
                let cc = 0.5 + 0.5 * cos(phase)
                let stripe = Self.clamp01((cc - (1 - fill)) / fill)
                if stripe <= 0 { continue }

                var f = 0.0, amp = 0.5, fr = S
                for _ in 0..<3 {
                    f += Self.noise(cs * fr, sn * fr, (y2 * nb * 0.7 + 3) * (fr / S)) * amp
                    amp *= 0.5; fr *= 2
                }
                f /= 0.875
                let fs = (f - 0.5) * 2.2 + 0.5
                let streak = sFloor + (1 - sFloor) * Self.smooth(cut, cut + 0.55, fs)
                var band = pow(stripe, 0.5) * streak
                if band < 0.01 { continue }
                band *= 1 - det + det * 2 * Self.noise(cs * 14, sn * 14, y2 * 40 + 5)

                let lam = max(0, lx * cell.u + ly * cell.v + lz * cell.z)
                let rimK = 1 - rimA * (1 - Self.smooth(0, 0.45, cell.z))
                var b = band * (amb + (1 - amb) * lam) * con * rimK
                if shim > 0 { b += (Self.hash3(cell.i, cell.j, tick) - 0.5) * shim }
                if b < empty { continue }

                var idx = 1 + Int(floor((b - empty) / max(0.01, 1 - empty) * 8))
                if idx > 8 { idx = 8 }
                if band > 0.2 && Self.noise(cs * 24, sn * 24, y2 * 55 + 7) > atThr { idx = 9 }
                let isAccent = ((cell.u + cell.v + 2) / 4) * 0.85 + cell.hash * 0.15 < progress
                ctx.draw(glyphs[isAccent ? 1 : 0][idx], at: CGPoint(x: c.x + cell.x, y: c.y + cell.y), anchor: .center)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: 05 · 连上 Connected

private struct Connected: View {
    var lowBattery: String? = nil
    let onNext: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var began: Date?

    /// The picture is the board's width, 520 tall on the board — the asset's own 3:4.
    /// It is centred in the band it has: the safe area's top edge is board y = 62 and the
    /// first line sits at 592, so 530pt of room for a 520pt picture puts it at 67. At 40 it
    /// began above the status bar, which is what was cutting the upper arm off at the top.
    private static let handsTop: CGFloat = 67

    var body: some View {
        // F5 C11 · Reduce Motion gets the finished picture, not a paused one.
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let elapsed = began.map { tl.date.timeIntervalSince($0) } ?? 0
            #if DEBUG
            let t: Double = {
                if let raw = ProcessInfo.processInfo.environment["NB_DEBUG_LINK_T"],
                   let pin = Double(raw) { return pin }
                return reduceMotion ? LinkChoreo.finished : LinkChoreo.looped(elapsed)
            }()
            #else
            let t = reduceMotion ? LinkChoreo.finished : LinkChoreo.looped(elapsed)
            #endif
            stage(at: t)
                // A looped replay re-fires the score from its first beat.
                .onChange(of: LinkChoreo.cycle(elapsed)) { _, _ in
                    LinkHaptics.shared.play(still: reduceMotion)
                }
        }
        .onAppear {
            LinkHaptics.shared.prepare()
            began = Date()
            LinkHaptics.shared.play(still: reduceMotion)
        }
        .onDisappear { LinkHaptics.shared.stop() }
    }

    private func stage(at t: Double) -> some View {
        let w = NB.Layout.screenWidth
        let top = Chrome.boardY(Self.handsTop)
        // 520 on the board; compressed with the column on a short phone so the lines
        // under it keep their room.
        let h = Chrome.boardY(Self.handsTop + 520) - top
        let pictureHeight = w * 4 / 3
        let touch = CGPoint(x: w * LinkChoreo.touchUV.x,
                            y: pictureHeight * LinkChoreo.touchUV.y - (pictureHeight - h) / 2)
        let footer = LinkChoreo.footer(t)

        return ZStack(alignment: .topLeading) {
            NB.panelInk

            // The rays leave the point where the fingertips meet — one burst, one implementation.
            // They sit at the very back; the print above them is clear between its cells.
            Burst(progress: LinkChoreo.burst(t))
                .frame(width: w, height: 560)
                .offset(x: touch.x - w / 2, y: top + touch.y - 280)
                .opacity(LinkChoreo.burstAlpha(t) * 0.55)

            HandsLink(clock: t, size: CGSize(width: w, height: h))
                .frame(width: w, height: h)
                .offset(y: top)

            TypeIn(text: L("YOU'RE CONNECTED"), progress: LinkChoreo.title(t),
                   font: NBFont.dot(700, 20), tracking: 0.34 * 20, size: 20, color: NB.lime1)
                .frame(width: w, alignment: .center)
                .offset(y: Chrome.boardY(584))

            TypeIn(text: L("You're now linked to the future you."), progress: LinkChoreo.subtitle(t),
                   font: NBFont.ui(300, 14), tracking: 0.02 * 14, size: 14, color: NB.white.opacity(0.72))
                .frame(width: w, alignment: .center)
                .offset(y: Chrome.boardY(618))

            Text(L("LINK LOCKED · DOUBLE TAP"))
                .font(NBFont.dot(500, 10.5)).tracking(0.24 * 10.5)
                .foregroundStyle(NB.white.opacity(0.40))
                .frame(width: w, alignment: .center)
                .offset(y: Chrome.boardY(650))
                .opacity(footer)

            // 9-0 00B · the second NEXTBODY is not paired here. One line says where it goes;
            // Device › Add your second NEXTBODY does the work later.
            Text(L("KEEP WEARING. CHARGE THE OTHER.") + "\n" + L("Add your second NEXTBODY from the Device page."))
                .font(NBFont.dot(500, 10.5)).tracking(0.16 * 10.5)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .foregroundStyle(NB.white.opacity(0.28))
                .frame(width: w, alignment: .center)
                .offset(y: Chrome.boardY(lowBattery == nil ? 674 : 694))
                .opacity(footer)
                .accessibilityIdentifier("connect.secondHoopHint")

            // 02 rule 05 · low battery does not block pairing; it gets one amber line here.
            if let lowBattery {
                Text(lowBattery)
                    .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.ember1)
                    .frame(width: w, alignment: .center)
                    .offset(y: Chrome.boardY(672))
                    .opacity(footer)
            }

            // No header, no back key, one button — pairing to profile is a straight line.
            LimePillButton(title: L("Now let me get to know you"), action: onNext)
                .offset(x: 16, y: Chrome.boardY(lowBattery == nil ? 728 : 746) + 14 * (1 - footer))
                .opacity(footer)
                .allowsHitTesting(footer > 0.9)

        }
        .frame(width: w, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Hardware with no Taptic Engine keeps the blunt version: the score cannot be
        // carried by the canned generators, but the contact should not be silent either.
        .onChange(of: LinkChoreo.hapticStage(t)) { _, stage in
            guard !LinkHaptics.shared.isSupported else { return }
            switch stage {
            case 1: Haptics.impact(.rigid)
            case 2: Haptics.notification(.success)
            default: break
            }
        }
    }
}

/// The burst and the first-launch splash are one implementation, not two (MOTION SPEC · 01).
/// ⚠️ The two horizontal rays must be cut — they read as a strike-through on CONNECTED.
private struct Burst: View {
    let progress: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 150, y: c.y - 150, width: 300, height: 300)),
                     with: .radialGradient(
                        Gradient(colors: [NB.lime1.opacity(0.35 * progress), NB.lime1.opacity(0)]),
                        center: c, startRadius: 0, endRadius: 150))

            for i in 0..<16 {
                let a = Double(i) / 16 * 2 * .pi
                // cut the two horizontal rays
                if abs(cos(a)) > 0.985 { continue }
                let reach: CGFloat = 40 + 190 * CGFloat(progress)
                var r: CGFloat = 40
                while r < reach {
                    let dim: Double = 1 - Double(r - 40) / 190.0
                    let x: CGFloat = c.x + r * CGFloat(cos(a)) - 2.4
                    let y: CGFloat = c.y + r * CGFloat(sin(a)) - 2.4
                    let box = CGRect(x: x, y: y, width: 4.8, height: 4.8)
                    ctx.fill(Path(box), with: .color(NB.lime1.opacity(0.25 + 0.6 * dim)))
                    r += 7
                }
            }
        }
        .allowsHitTesting(false)
    }
}
