import SwiftUI
import os

private let sheetLog = Logger(subsystem: "com.nextbody.hoop", category: "deviceset")

// 9-0 A · the three sheets the two-HOOP set adds to DEVICE
// (docs/plans/2026-09-12-dual-device-continuity.md §04.5, §12).
//
// Activate the second (A·S1–S6: one sheet, four faces), `I'm wearing B` (A·S8) and Release
// both (A·S7). The activation faces are cut from Connect's own screens 02–05: the same
// scan rings, the same dotted progress that moves when the band answers, not on a timer.

// MARK: A·S1–S6 · activate the second HOOP

struct ActivateSecondSheet: View {
    @EnvironmentObject private var data: DataStore
    @ObservedObject private var hoops = DeviceSetStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Face: Equatable { case preparing, searching, nothingFound, found, pairing, paired, stopped(String) }
    @State private var face: Face = .searching
    @State private var nearby: [DiscoveredBand] = []
    @State private var picked: String?
    @State private var progress: Double = 0
    @State private var stage = 0
    @State private var scanTask: Task<Void, Never>?
    @State private var activated: DeviceSetStore.SlotSnapshot?
    @State private var activatedAt: Date?
    @State private var activationOwner = UUID()
    @State private var targetSlot: HoopSlot?

    private var slot: HoopSlot { targetSlot ?? hoops.openSlot ?? .b }
    private var worn: HoopSlot { slot.other }
    private var bound: Set<String> { Set(DeviceSlots.bindings.map(\.identifier)) }
    private var candidates: [DiscoveredBand] { nearby.filter { !bound.contains($0.id) }.sorted { $0.rssi > $1.rssi } }
    private var pick: DiscoveredBand? { candidates.first { $0.id == picked } ?? candidates.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch face {
            case .preparing:
                SheetHead(eyebrow: L("PREPARING"), title: L("Preparing to pair"),
                          body: L("Finishing the current HOOP command before searching. Your other HOOP stays paired."))
                ProgressView().tint(NB.lime1).padding(24)
                Spacer()
                OutlineKey(title: L("CANCEL"), tint: NB.lime1) { dismiss() }
                    .padding(.horizontal, 16).padding(.bottom, 28)
            case .searching, .nothingFound: searching
            case .found: found
            case .pairing: pairing
            case .paired: paired
            case .stopped(let why): stopped(why)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
        .interactiveDismissDisabled(face == .pairing)
        .onAppear { targetSlot = hoops.openSlot; startScan() }
        .onDisappear {
            scanTask?.cancel()
            let pending = scanTask
            Task {
                await pending?.value
                guard hoops.activationGate.owner == activationOwner else { return }
                await Band.live.stopScan()
                hoops.endActivation(owner: activationOwner)
            }
        }
    }

    // MARK: S1 · searching (02's rings, white — no green before there is a success)

    private var searching: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHead(eyebrow: L("SEARCHING · SLOT") + " \(slot.rawValue)",
                      title: L("Fill slot") + " \(slot.rawValue)",
                      body: face == .nothingFound
                        ? L("Nothing answered. Is it lit up, within an arm's reach, and not still linked to another phone?")
                        : L("Take the second HOOP off its charger and hold it near the phone. The one on your wrist steps off the link for a moment and comes back on its own."))
            TimelineView(.animation(paused: reduceMotion || face == .nothingFound)) { tl in
                let t = face == .nothingFound ? 0 : tl.date.timeIntervalSinceReferenceDate
                BandPortrait(scanRings: (0..<4).map { i in
                    let p = (t * 0.35 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                    return 60 + CGFloat(p) * 130
                })
                .frame(width: 190, height: 229)
                .opacity(face == .nothingFound ? 0.18 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            Text(face == .nothingFound ? L("NOTHING FOUND") : L("SCANNING"))
                .font(NBFont.dot(600, 12)).tracking(0.34 * 12)
                .foregroundStyle(NB.white.opacity(0.42))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            footerLine(wornLine)
                .padding(.top, 18)
            Spacer(minLength: 0)
            if face == .nothingFound {
                LimePillButton(title: L("Search again")) { startScan() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            OutlineKey(title: L("CANCEL"), tint: NB.lime1) { dismiss() }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
        }
    }

    // MARK: S2 · found (03's device card; the one already yours stays where it is)

    private var found: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHead(eyebrow: L("FOUND") + " · \(nearby.count) " + L("NEARBY"),
                      title: candidates.count == 1 ? L("Found one") : L("Found") + " \(candidates.count)",
                      body: L("The one that isn't already yours is picked. The HOOP you wear shows up too, but it stays where it is."))
            VStack(spacing: 10) {
                ForEach(candidates) { band in
                    NearbyCard(band: band, state: band.id == pick?.id ? .picked : .other) { picked = band.id }
                }
                ForEach(nearby.filter { bound.contains($0.id) }) { band in
                    NearbyCard(band: band, state: .inSet(DeviceSlots.bindings.first { $0.identifier == band.id }?.slot ?? worn)) {}
                }
            }
            .padding(.horizontal, 24)
            footerLine(wornLine)
                .padding(.top, 18)
            Spacer(minLength: 0)
            LimePillButton(title: L("PAIR AS") + " \(slot.rawValue)") { if let pick { activate(pick) } }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .disabled(pick == nil)
                .opacity(pick == nil ? 0.5 : 1)
        }
    }

    // MARK: S3 · pairing (04's number and dotted bar; four real steps)

    private static let stageNames = ["Connect", "Verify it's yours", "Read capabilities", "Activate"]

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHead(eyebrow: L("PAIRING"), title: L("Joining as") + " \(slot.rawValue)",
                      body: L("Keep it within arm's reach. Four real steps — the number moves when the band answers, not on a timer."),
                      trailing: percent)
            DottedProgress(progress: progress)
                .frame(width: NB.Layout.contentWidth - 16, height: 6)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            stageRows(current: stage, failed: false)
            footerLine(wornLine)
            Spacer(minLength: 0)
            Text(L("Keep it within arm's reach."))
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .foregroundStyle(NB.white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)
        }
    }

    private var percent: some View {
        Text("\(Int(progress * 100))%")
            .font(NBFont.dot(700, 22)).tracking(0.02 * 22)
            .foregroundStyle(face == .pairing ? NB.lime1 : NB.ember1)
            .contentTransition(.numericText())
    }

    private func stageRows(current: Int, failed: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                let name = i == 3 ? L("Activate") + " \(slot.rawValue)" : L(Self.stageNames[i])
                let done = i < current || face == .paired
                let now = i == current && !failed && face == .pairing
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                        .foregroundStyle(done ? NB.white.opacity(0.55) : now ? NB.white : NB.white.opacity(0.24))
                    Spacer(minLength: 0)
                    Text(done ? L("DONE") : now ? L("NOW") : (failed && i == current) ? L("STOPPED") : "—")
                        .font(NBFont.dot(done || now ? 600 : 500, 11)).tracking(0.12 * 11)
                        .foregroundStyle(done || now ? NB.lime1 : (failed && i == current) ? NB.ember1 : NB.white.opacity(0.24))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Hairline() }
            }
        }
    }

    // MARK: S4 · paired (12Y's figure rows)

    private var paired: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHead(eyebrow: L("PAIRED · SLOT") + " \(slot.rawValue)", title: "HOOP \(slot.rawValue) " + L("is in"),
                      body: L("When you swap, tell the app you're wearing it. Until then it just waits on the charger — nothing from it is counted."))
            FigureRow(name: L("Battery"), value: activated?.battery?.percent.map { "\($0)" } ?? Fmt.dash,
                      unit: activated?.battery?.percent == nil ? "" : "%")
            FigureRow(name: L("Firmware"), value: activated?.firmware ?? Fmt.dash, unit: "")
            FigureRow(name: L("Holds"), value: activated?.holdsDays.map { "\($0)" } ?? Fmt.dash,
                      unit: activated?.holdsDays == nil ? "" : L("DAYS"))
            footerLine(L("SLOT") + " \(slot.rawValue) · " + L("ACTIVE") + " " + (activatedAt.map(Self.clock) ?? "") + " · " + L("STILL ON") + " \(worn.rawValue)")
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                LimePillButton(title: L("DONE · STILL WEARING") + " \(worn.rawValue)") { dismiss() }
                Button {
                    let now = slot
                    dismiss()
                    Task { await DeviceSetStore.shared.declareWearing(now, store: data) }
                } label: {
                    Text(L("I'm wearing") + " \(slot.rawValue) " + L("now"))
                        .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                        .foregroundStyle(NB.lime1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activate.wearingNow")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    // MARK: S5/S6 · stopped (ember eyebrow, same skeleton; the number freezes where it was)

    private func stopped(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHead(eyebrow: L("STOPPED · SLOT") + " \(slot.rawValue)", title: L("Couldn't reach it"),
                      body: why + " " + L("Your other HOOP remains paired."),
                      trailing: percent, ember: true)
            DottedProgress(progress: progress)
                .frame(width: NB.Layout.contentWidth - 16, height: 6)
                .grayscale(1).colorMultiply(NB.ember1)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            stageRows(current: stage, failed: true)
            footerLine(wornLine)
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                LimePillButton(title: L("Try again")) { startScan() }
                Button { dismiss() } label: {
                    Text(L("Not now"))
                        .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                        .foregroundStyle(NB.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    // MARK: pieces

    /// `A · STILL RECORDING · 82%` — the worn band keeps recording on the wrist whatever
    /// the link does; its last known charge, never a guess.
    private var wornLine: String {
        let charge = data.band.batteryPercent.map { " · \($0)%" } ?? ""
        return "\(worn.rawValue) · " + L("STILL RECORDING") + charge
    }

    private func footerLine(_ text: String) -> some View {
        Text(text)
            .font(NBFont.dot(500, 11)).tracking(0.16 * 11)
            .foregroundStyle(NB.white.opacity(0.34))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .overlay(alignment: .top) { Hairline() }
    }

    private static func clock(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("HH:mm")
        return f.string(from: date)
    }

    // MARK: the work

    /// 02 rule 01 · scan 15 s. Every band in range is listed; the ones already in the set
    /// are shown greyed. The strongest new one is picked, 1.5 s after the first answers.
    private func startScan() {
        nearby = []; picked = nil; progress = 0; stage = 0
        face = .preparing
        scanTask?.cancel()
        scanTask = Task {
            do { try await hoops.prepareActivation(owner: activationOwner) }
            catch {
                guard !Task.isCancelled else { return }
                face = .stopped(L("The HOOP is switching or finishing a command. Try again shortly."))
                return
            }
            await BluetoothState.shared.waitForState()
            guard !Task.isCancelled else { return }
            if BluetoothState.shared.poweredOff { face = .stopped(L("Bluetooth is off.")); return }
            if BluetoothState.shared.permissionDenied { face = .stopped(L("Bluetooth permission is off for NextBody.")); return }
            face = .searching
            let timeout = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, candidates.isEmpty, face == .searching else { return }
                await Band.live.stopScan()
                face = .nothingFound
            }
            var settle: Task<Void, Never>?
            // Listen before the radio starts: the mock answers from inside startScan.
            let events = Band.live.events
            let scanning = Task { await Band.live.startScan() }
            defer { scanning.cancel() }
            sheetLog.notice("activate: scan started for slot \(slot.rawValue, privacy: .public)")
            for await event in events {
                if Task.isCancelled { timeout.cancel(); settle?.cancel(); return }
                guard case .discovered(let device) = event else { continue }
                sheetLog.notice("activate: discovered \(device.id, privacy: .public) rssi=\(device.rssi, privacy: .public) bound=\(bound.contains(device.id), privacy: .public)")
                if let i = nearby.firstIndex(where: { $0.id == device.id }) { nearby[i] = device } else { nearby.append(device) }
                if settle == nil, !bound.contains(device.id) {
                    timeout.cancel()
                    settle = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled, face == .searching else {
                            sheetLog.notice("activate: settle skipped, face=\(String(describing: face), privacy: .public)"); return
                        }
                        await Band.live.stopScan()
                        sheetLog.notice("activate: found \(candidates.count, privacy: .public) candidate(s)")
                        withAnimation(.easeOut(duration: 0.25)) { face = .found }
                    }
                }
            }
            timeout.cancel()
        }
    }

    /// 02 rule 02 · four fixed segments: connect 0–35, verify 35–60, capabilities 60–85,
    /// activate 85–100. Whichever does not return, the bar stops there.
    private func activate(_ device: DiscoveredBand) {
        scanTask?.cancel()
        progress = 0; stage = 0
        withAnimation(.easeOut(duration: 0.25)) { face = .pairing }
        Task {
            await Band.live.stopScan()
            do {
                activated = try await DeviceSetStore.shared.activateSecond(device, store: data, owner: activationOwner) { s in
                    stage = s.rawValue
                } progress: { p in
                    withAnimation(.easeOut(duration: 0.2)) { progress = max(progress, p) }
                }
                withAnimation(.easeOut(duration: 0.2)) { progress = 1; stage = 3 }
                activatedAt = Date()
                Haptics.notification(.success)
                withAnimation(.easeOut(duration: 0.3)) { face = .paired }
            } catch {
                face = .stopped(error.localizedDescription)
            }
        }
    }

}

/// Eyebrow · title · body, the sheet head every face shares (24pt gutters, 8pt gaps).
private struct SheetHead<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let copy: String
    var trailing: Trailing
    var ember = false

    init(eyebrow: String, title: String, body: String, trailing: Trailing, ember: Bool = false) {
        self.eyebrow = eyebrow; self.title = title; self.copy = body; self.trailing = trailing; self.ember = ember
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow)
                    .font(NBFont.dot(600, 11)).tracking(0.28 * 11)
                    .foregroundStyle(ember ? NB.ember1 : NB.lime1)
                Spacer(minLength: 0)
                trailing
            }
            Text(title)
                .font(NBFont.ui(700, 32)).tracking(-0.03 * 32)
                .foregroundStyle(NB.text1)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(copy)
                .font(NBFont.ui(300, 14))
                .lineSpacing(22 - 14)
                .foregroundStyle(NB.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }
}

extension SheetHead where Trailing == EmptyView {
    init(eyebrow: String, title: String, body: String) {
        self.init(eyebrow: eyebrow, title: title, body: body, trailing: EmptyView())
    }
}

/// 03's found card: lime-edged when it is the pick, greyed when it is already in the set.
private struct NearbyCard: View {
    enum State: Equatable { case picked, other, inSet(HoopSlot) }
    let band: DiscoveredBand
    let state: State
    let action: () -> Void

    private var inSet: Bool { if case .inSet = state { return true } else { return false } }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    if state == .picked { Circle().fill(NB.lime1.opacity(0.12)) }
                    Circle().stroke(state == .picked ? NB.lime1.opacity(0.35) : NB.white.opacity(0.25), lineWidth: 1)
                    Circle().stroke(state == .picked ? NB.lime1 : NB.white.opacity(0.55), lineWidth: 2).frame(width: 11, height: 11)
                    Rectangle().fill(state == .picked ? NB.lime1 : NB.white.opacity(0.55)).frame(width: 2, height: 7).offset(y: -6)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(band.name.uppercased())
                        .font(NBFont.ui(500, 15)).tracking(0.02 * 15)
                        .foregroundStyle(NB.text1)
                    Text(word)
                        .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                        .foregroundStyle(state == .picked ? NB.lime1 : NB.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Text(band.batteryPercent.map { "\($0)%" } ?? Fmt.dash)
                    .font(NBFont.dot(600, 10)).tracking(0.1 * 10)
                    .foregroundStyle(NB.white.opacity(0.55))
                SignalBars(level: Self.bars(band.rssi))
                    .grayscale(state == .picked ? 0 : 1)
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
            .frame(maxWidth: .infinity)
            .background(Color(hex: 0x15151A), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(state == .picked ? NB.lime1.opacity(0.55) : NB.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(inSet ? 0.42 : 1)
        .disabled(inSet)
    }

    private var word: String {
        switch state {
        case .picked: return L("READY TO PAIR")
        case .other: return L("NEARBY")
        case .inSet(let slot): return L("ALREADY IN SLOT") + " \(slot.rawValue)"
        }
    }

    /// RSSI in dBm, not a percentage. −50 is on the desk, −90 is in the next room.
    private static func bars(_ rssi: Int) -> Int {
        switch rssi {
        case (-55)...: return 4
        case (-67)..<(-55): return 3
        case (-80)..<(-67): return 2
        default: return 1
        }
    }
}

/// 12Y's figure row: name left, 28pt dot numeral, a 36pt unit column.
private struct FigureRow: View {
    let name: String
    let value: String
    let unit: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(name)
                .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                .foregroundStyle(NB.text1)
            Spacer(minLength: 0)
            Text(value)
                .font(NBFont.dot(700, 28)).tracking(-0.02 * 28)
                .foregroundStyle(NB.text1)
            Text(unit)
                .font(NBFont.dot(500, 12)).tracking(0.12 * 12)
                .foregroundStyle(NB.white.opacity(0.42))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: A·S8 · the switch, and the one line that can correct its start

/// There are only two HOOPs, so tapping the other one's card is the choice; this sheet
/// only confirms it. No picker, no time: the band itself says when it went on the wrist
/// and the server moves the start once the phone has read it (§04.5 W2).
struct WearSwitchSheet: View {
    @EnvironmentObject private var data: DataStore
    @ObservedObject private var hoops = DeviceSetStore.shared
    @Environment(\.dismiss) private var dismiss
    let to: HoopSlot
    /// Two taps land before the sheet is gone; the second must not file a second switch.
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle(L("Switch to HOOP") + " \(to.rawValue)?")
            SheetBody(L("From now on your record comes from this one. The app works out when you put it on from the HOOP itself, so there is nothing to set."))
            if hoops.snapshot(to)?.isFlat == true {
                Text(L("It was out of charge when the app last read it. Say you are wearing it anyway — your record follows your wrist, not the link — but charge it or it records nothing."))
                    .font(NBFont.ui(400, 13)).tracking(0.01 * 13)
                    .lineSpacing(6)
                    .foregroundStyle(NB.ember1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let snap = hoops.snapshot(to) {
                HStack(spacing: 12) {
                    HoopKeyGlyph(letter: to.rawValue, lit: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snap.name)
                            .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                            .foregroundStyle(NB.text1)
                        Text(hoops.snapshot(to.other).map { _ in L("HOOP") + " \(to.other.rawValue) " + L("goes on the charger") } ?? "")
                            .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                            .foregroundStyle(NB.white.opacity(0.34))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 66)
                .frame(width: NB.Layout.contentWidth)
                .cardSkin()
            }
            Spacer(minLength: 0)
            LimePillButton(title: L("I'm wearing HOOP") + " \(to.rawValue)") {
                guard !sent else { return }
                sent = true
                let slot = to
                dismiss()
                Task { await DeviceSetStore.shared.declareWearing(slot, store: data) }
            }
            .accessibilityIdentifier("wearSwitch.confirm")
            OutlineKey(title: L("NOT NOW"), tint: NB.text2) { dismiss() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
    }
}

/// Behind the `Counted from …` line, and nowhere else. The app already worked the start
/// out from the band; this is the wearer saying otherwise.
struct WearCorrectSheet: View {
    @EnvironmentObject private var data: DataStore
    @ObservedObject private var hoops = DeviceSetStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var since = Date()
    @State private var loaded = false

    private var slot: HoopSlot { hoops.wearing }
    private var floor: Date {
        let bound = hoops.timeline.earliestSwitch(to: slot) ?? Date().addingTimeInterval(-14 * 86_400)
        return max(bound, Date().addingTimeInterval(-14 * 86_400))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle(L("When did you put it on?"))
            SheetBody(hoops.wearingInferred
                      ? L("HOOP") + " \(slot.rawValue) " + L("said it went on your wrist at this time. Set another one and your record counts from there instead.")
                      : L("Your record counts from this time. Set another one to move it."))
            DatePicker("", selection: $since, in: floor...Date(), displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(height: 196)
                .clipped()
            Spacer(minLength: 0)
            LimePillButton(title: L("Count from this time")) {
                let slot = self.slot, at = since
                dismiss()
                Task { await DeviceSetStore.shared.declareWearing(slot, since: at, store: data) }
            }
            OutlineKey(title: L("LEAVE IT"), tint: NB.text2) { dismiss() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            since = min(max(hoops.wearingSince ?? Date(), floor), Date())
        }
    }
}

// MARK: Remove one binding, keeping the other slot and account history.
struct ReleaseSetSheet: View {
    var initialSlot: HoopSlot? = nil
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hoops = DeviceSetStore.shared
    @State private var selected: HoopSlot?
    @State private var removing = false
    @State private var failureMessage: String?
    @State private var removed: HoopSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let removed {
                SheetTitle(L("%@ removed", removed.displayName))
                SheetBody(L("Pairing removed successfully. All synced history is still in your account."))
                Spacer(minLength: 0)
                LimePillButton(title: L("Done")) {
                    if hoops.slots.isEmpty { session.stage = .gateConnect }
                    dismiss()
                }
            } else {
            SheetTitle(selected.map { L("Remove %@?", $0.displayName) } ?? L("Remove a HOOP"))
            if hoops.hasSecond {
                ForEach(HoopSlot.allCases, id: \.self) { slot in
                    OutlineKey(title: slot.displayName + (selected == slot ? " ✓" : ""),
                               tint: selected == slot ? NB.lime1 : NB.text2) {
                        selected = slot
                        failureMessage = nil
                    }
                }
                SheetBody(L("Only the selected HOOP is removed. Your other HOOP stays paired and becomes the active HOOP. All synced history stays."))
            } else {
                SheetBody(L("This HOOP will be unpaired. All synced history stays. You can pair a HOOP again anytime."))
            }
            if let failureMessage {
                Text(L(failureMessage))
                    .font(NBFont.brand(400, 14)).foregroundStyle(NB.alert2)
            }
            if removing {
                HStack(spacing: 10) {
                    ProgressView().tint(NB.lime1)
                    Text(L("Confirming removal…"))
                        .font(NBFont.brand(400, 14)).foregroundStyle(NB.text2)
                }
            }
            Spacer(minLength: 0)
            LimePillButton(title: L("Keep it paired")) { dismiss() }
            OutlineKey(title: removing ? L("REMOVING…") : selected.map { L("REMOVE %@", $0.displayName) } ?? L("SELECT A HOOP"), tint: NB.alert2) {
                guard let selected, !removing else { return }
                removing = true
                failureMessage = nil
                Task {
                    do {
                        try await hoops.release(selected, store: data)
                        removed = selected
                        removing = false
                    } catch {
                        failureMessage = DeviceReleaseError.message(for: error)
                        removing = false
                    }
                }
            }
            .disabled(selected == nil)
            }
        }
        .disabled(removing)
        .interactiveDismissDisabled(removing || removed != nil)
        .onAppear { selected = initialSlot }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
    }
}

// MARK: shared pieces

private struct SheetTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
            .foregroundStyle(NB.text1)
    }
}

private struct SheetBody: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(NBFont.brand(400, 14))
            .lineSpacing(7)
            .foregroundStyle(NB.text2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OutlineKey: View {
    let title: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NBFont.dot(700, 13)).tracking(0.2 * 13)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .overlay(Capsule().stroke(tint == NB.text2 ? NB.hairline : tint.opacity(0.55), lineWidth: 1))
                // ⚠️ A plain button around an outlined label is hit-tested on the glyphs
                // alone: without this the middle of the key does nothing.
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The slot letter in a 28pt ring — lit when it is the one being named; carbon on lime.
struct HoopKeyGlyph: View {
    let letter: String
    var lit = false
    var onLime = false
    var body: some View {
        Text(letter)
            .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
            .foregroundStyle(onLime ? NB.lime1 : lit ? NB.carbon4 : NB.text1)
            .frame(width: 28, height: 28)
            .background(onLime ? NB.carbon4 : lit ? NB.lime1 : NB.white.opacity(0.08), in: Circle())
    }
}
