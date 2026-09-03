import SwiftUI

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
    enum ScanEdge { case nothingFound, bluetoothOff }
    enum PairEdge { case stopped, taken }
    @State private var scanEdge: ScanEdge?
    @State private var pairEdge: PairEdge?
    @State private var pairFailures = 0
    /// 02 rule 05 · low battery never blocks pairing; one amber line on the success screen.
    @State private var lowBatteryLine: String?

    /// 04 · the percentage maps to four real steps; never a fake tween.
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
            case .connected: Connected(lowBattery: lowBatteryLine) { session.stage = .gateOnboarding }
            }
        }
        .carbonPage()
        // 02 edge 2 · the radio going off mid-search ends the search; coming back restarts it.
        .onReceive(BluetoothState.shared.$poweredOff.dropFirst()) { off in
            guard step == .searching else { return }
            if off { scanTask?.cancel(); Task { await Band.live.stopScan() }; scanEdge = .bluetoothOff }
            else if scanEdge == .bluetoothOff { runScan() }
        }
        .transaction { $0.animation = nil }
        #if DEBUG
        // `SIMCTL_CHILD_NB_DEBUG_CONNECT_STEP=3` opens the flow on that screen for a walk —
        // the screen only, none of the scan or pairing work behind it.
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["NB_DEBUG_CONNECT_STEP"],
               let n = Int(raw), let st = Step(rawValue: n) { step = st }
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

    /// 02 · 02 · the first band found ends the scan. One account owns one band, so a list
    /// would be a list of things you cannot choose between.
    private func runScan() {
        found = nil
        scanEdge = nil
        scanTask?.cancel()
        // DEBUG · 02 edges 1 and 2 on a simulator whose mock band always answers.
        if DebugEdge.on("nothingfound") { scanEdge = .nothingFound; return }
        BluetoothState.shared.start()
        if DebugEdge.on("btoff") || BluetoothState.shared.poweredOff { scanEdge = .bluetoothOff; return }
        scanTask = Task {
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
        Task {
            do {
                guard let device = found else { throw BandError.notConnected }

                // 02 rule 02 · four fixed segments: connect 0–35, authorise 35–60, capabilities
                // 60–85, version and battery 85–100. Whichever does not return, the bar stops there.
                await advance(to: 0.35, stage: 0)
                if DebugEdge.on("stopped") { throw BandError.timeout("connect") }
                if DebugEdge.on("taken") { throw BandError.rejected("paired elsewhere") }
                try await Band.live.connect(device)

                await advance(to: 0.60, stage: 1)
                let identity = try await Band.live.readIdentity()

                await advance(to: 0.85, stage: 2)
                // The capability table decides which measurement entries exist at all,
                // so it is read before the first screen that could offer one.
                let caps = try await Band.live.readCapabilities()

                await advance(to: 1.0, stage: 3)
                let battery = try await Band.live.readBattery()
                // 02 rule 05 · isPercent false → BATTERY LOW, never an invented percent.
                if DebugEdge.on("lowbattery") { lowBatteryLine = "BATTERY 8%" }
                else if !battery.isPercent { if (battery.level ?? 4) <= 1 { lowBatteryLine = "BATTERY LOW" } }
                else if let p = battery.percent, p < 10 { lowBatteryLine = "BATTERY \(p)%" }

                data.band = BandState(
                    connected: true, name: identity.name, mac: identity.bleIdentifier,
                    batteryPercent: battery.percent, firmware: identity.firmware,
                    lastSync: Date(),
                    capabilities: Self.capabilitySet(caps))
                step = .connected
            } catch {
                // Every failure degrades in place, on the screen it happened on. That rule
                // was set here in Connect, and this page is where it is enforced.
                BandLog.shared.record("pairing", error: error)
                // 02 edge 4 / 5 · the arms stop, the number freezes where it was, and the two
                // lines say what happened. TAKEN is the one failure with a named cause.
                pairFailures += 1
                if case BandError.rejected = error { pairEdge = .taken } else { pairEdge = .stopped }
                await Analytics.shared.track("PAIR_FAIL", ["REASON": pairEdge == .taken ? "TAKEN" : "STOPPED", "STEP": Self.stages[min(pairStage, 3)]])
            }
        }
    }

    private func advance(to target: Double, stage: Int) async {
        pairStage = stage
        while progress < target {
            try? await Task.sleep(for: .milliseconds(24))
            withAnimation(.linear(duration: 0.03)) { progress = min(target, progress + 0.01) }
        }
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
            Text(String(format: "PAIRING %02d / 05", index))
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
                PairTitle(title: "Turn it on",
                          sub: "Hold the button on the right edge for two seconds, until the band lights up.")
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            Text("HOLD 2S")
                .font(NBFont.dot(800, 13)).tracking(0.24 * 13)
                .foregroundStyle(NB.lime1)
                .frame(width: NB.Layout.screenWidth, alignment: .center)
                .offset(y: Chrome.boardY(608))

            // The only real dead end in the flow, answered on the screen it happens on.
            Text("Nothing lights up? It may be flat — charge it for ten minutes, then hold again.")
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .lineSpacing(20 - 13)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.text3Prod)
                .frame(width: NB.Layout.screenWidth - 64)
                .offset(x: 32, y: Chrome.boardY(640))

            LimePillButton(title: "It's on", action: onNext)
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
                PairTitle(title: "Searching",
                          sub: "Keep the band close to your phone. This usually takes a few seconds.")
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            switch edge {
            case .none:
                Text("SCANNING")
                    .font(NBFont.dot(600, 12)).tracking(0.34 * 12)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .frame(width: NB.Layout.screenWidth, alignment: .center)
                    .offset(y: Chrome.boardY(700))

                Text("Keep it within arm's reach.")
                    .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text3Prod)
                    .frame(width: NB.Layout.screenWidth, alignment: .center)
                    .offset(y: Chrome.boardY(750))

            case .nothingFound:
                // 02 edge 1 · NOTHING FOUND. Three checks in the most likely order, then the
                // outlined key. Not a new page — this is screen 02 itself.
                VStack(spacing: 14) {
                    Text("NOTHING FOUND")
                        .font(NBFont.dot(600, 12)).tracking(0.22 * 12)
                        .foregroundStyle(NB.white.opacity(0.48))
                    Text("· 手环亮起来了吗\n· 是不是超过一臂远\n· 是不是还连在别的手机上")
                        .font(NBFont.ui(300, 13)).lineSpacing(8)
                        .foregroundStyle(NB.white.opacity(0.50))
                        .frame(width: NB.Layout.contentWidth, alignment: .leading)
                    Button(action: onSearchAgain) {
                        Text("Search again")
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
                    Text("BLUETOOTH IS OFF")
                        .font(NBFont.dot(600, 12)).tracking(0.22 * 12)
                        .foregroundStyle(NB.ember1.opacity(0.85))
                    Text("I can’t look for the band without it.")
                        .font(NBFont.brand(400, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        Text("去打开蓝牙 →").font(NBFont.ui(500, 14)).tracking(0.04 * 14).foregroundStyle(NB.lime1)
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
                .position(x: 195, y: 252 + 210)

            BandPortrait(faceLit: true)
                .frame(width: NB.Layout.screenWidth, height: 470)
                .offset(y: Chrome.boardY(252))

            VStack(spacing: 0) {
                Color.clear.frame(height: Chrome.gateTopInset)
                PairHeader(index: 3, onBack: onBack)
                PairTitle(title: "Found it",
                          sub: "One band is in range. Tap connect and keep it near your phone.")
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            DeviceRow(band: band)
                .offset(x: 16, y: Chrome.boardY(600))

            LimePillButton(title: "Connect", action: onConnect)
                .offset(x: 16, y: Chrome.boardY(700))

            Button(action: onSearchAgain) {
                Text("Not your band? Search again")
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
                Text(band?.name.uppercased() ?? "NEXTBODY HOOP")
                    .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                    .foregroundStyle(NB.text1)
                Text("READY TO PAIR")
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

            // A collapse, not a supernova: five sparse arms, one event horizon, a black centre.
            TimelineView(.animation) { tl in
                // Edge 4 · the arms stop turning and the whole thing goes amber.
                Collapse(t: edge == nil ? tl.date.timeIntervalSinceReferenceDate : 0, progress: progress)
                    .frame(width: NB.Layout.screenWidth, height: 400)
                    .grayscale(edge == nil ? 0 : 1)
                    .colorMultiply(edge == nil ? .white : NB.ember1)
                    .offset(y: Chrome.boardY(260))
            }

            VStack(spacing: 0) {
                Color.clear.frame(height: Chrome.gateTopInset)
                PairHeader(index: 4)
                PairTitle(title: "Pairing", sub: "Keep it close — pulling everything into place.")
                    .padding(.top, 24)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(edge == nil ? "PAIRING" : "STOPPED")
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
                        Text("TAKEN BY ANOTHER PHONE")
                            .font(NBFont.dot(600, 12)).tracking(0.22 * 12)
                            .foregroundStyle(NB.ember1.opacity(0.85))
                        Text("This band is still paired somewhere else.")
                            .font(NBFont.brand(400, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                        Hairline()
                        Text("1 · 在那部手机上断开连接\n2 · 或者长按侧键，把手环重启一次")
                            .font(NBFont.ui(300, 13.5)).lineSpacing(8).foregroundStyle(NB.white.opacity(0.60))
                    } else {
                        Text("The band stopped answering. Nothing you did wrong.")
                            .font(NBFont.brand(400, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                    }
                    Button(action: onRetry) {
                        Text("Try again")
                            .font(NBFont.ui(500, 14)).tracking(0.06 * 14)
                            .foregroundStyle(NB.carbon)
                            .frame(width: NB.Layout.contentWidth, height: 44)
                            .background(NB.lime1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    // Only the second failure offers the way back to 02.
                    if failures >= 2 {
                        Button(action: onSearchAgain) {
                            Text("Search again")
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

                Text("Keep it within arm's reach.")
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

private struct DottedProgress: View {
    let progress: Double
    var body: some View {
        Canvas { ctx, size in
            let n = 60
            let pitch = size.width / CGFloat(n)
            for i in 0..<n {
                let lit = Double(i) / Double(n) < progress
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * pitch, y: 1,
                                                  width: pitch - 2, height: 4), cornerRadius: 1),
                         with: .color(lit ? NB.lime1 : NB.white.opacity(0.10)))
            }
        }
    }
}

private struct Collapse: View {
    let t: TimeInterval
    let progress: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2 - 40)
            // five sparse arms
            for arm in 0..<5 {
                let base = Double(arm) / 5 * 2 * .pi + t * 0.7
                var p = Path()
                var first = true
                var r: CGFloat = 26
                while r < 150 {
                    let a: Double = base + Double(r) * 0.022
                    let px: CGFloat = c.x + r * CGFloat(cos(a))
                    let py: CGFloat = c.y + r * CGFloat(sin(a)) * 0.92
                    let pt = CGPoint(x: px, y: py)
                    if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                    r += 3
                }
                ctx.stroke(p, with: .color(NB.lime1.opacity(0.55 - Double(arm) * 0.06)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 7]))
            }
            // event horizon
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68)),
                       with: .color(NB.lime1.opacity(0.85)), lineWidth: 3)
            // the centre stays black
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 30, y: c.y - 30, width: 60, height: 60)),
                     with: .color(NB.panelInk))
            // stray debris being pulled in
            for i in 0..<7 {
                let a: Double = Double(i) * 1.7 + t * 0.4
                let r: CGFloat = 150 + CGFloat((sin(t * 0.6 + Double(i)) + 1) * 26)
                let dx: CGFloat = c.x + r * CGFloat(cos(a)) - 2
                let dy: CGFloat = c.y + r * CGFloat(sin(a)) * 0.9 - 2
                ctx.fill(Path(CGRect(x: dx, y: dy, width: 4, height: 4)),
                         with: .color(NB.lime1.opacity(0.5)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: 05 · 连上 Connected

private struct Connected: View {
    var lowBattery: String? = nil
    let onNext: () -> Void
    @State private var burst: Double = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk

            Burst(progress: burst)
                .frame(width: NB.Layout.screenWidth, height: 560)
                .offset(y: Chrome.boardY(90))

            Text("CONNECTED")
                .font(NBFont.dot(700, 20)).tracking(0.34 * 20)
                .foregroundStyle(NB.lime1)
                .frame(width: NB.Layout.screenWidth, alignment: .center)
                .offset(y: Chrome.boardY(356))

            Text("LINK LOCKED · DOUBLE TAP")
                .font(NBFont.dot(500, 10.5)).tracking(0.24 * 10.5)
                .foregroundStyle(NB.white.opacity(0.40))
                .frame(width: NB.Layout.screenWidth, alignment: .center)
                .offset(y: Chrome.boardY(390))

            // 02 rule 05 · low battery does not block pairing; it gets one amber line here.
            if let lowBattery {
                Text(lowBattery)
                    .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.ember1)
                    .frame(width: NB.Layout.screenWidth, alignment: .center)
                    .offset(y: Chrome.boardY(414))
            }

            // No header, no back key, one button — pairing to profile is a straight line.
            LimePillButton(title: "Now let me get to know you", action: onNext)
                .offset(x: 16, y: Chrome.boardY(700))

        }
        .frame(width: NB.Layout.screenWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { burst = 1 } }
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
