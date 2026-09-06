import SwiftUI

/// Paper 12Y · 02 仪器 LED (KLF-0 / LFQ-0 live, KXX-0 timeout).
/// Opens READY with START. The wrist only rings after START.
/// STOP is a 0.12s hold (tap also works) and must paint instantly.
struct FindHoopSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var beat: Beat = .ready
    @State private var rssi: Int?
    @State private var message: String?
    @State private var starting = false
    @State private var rssiFrozen = false

    private enum Beat: Equatable {
        case ready, ringing, timeout
    }

    private var distance: FindDistance? {
        rssi.map(FindDistance.from(rssi:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if beat == .timeout {
                timeoutFace
            } else {
                liveFace
            }

            if let message, beat != .timeout {
                Text(message)
                    .font(NBFont.ui(400, 12))
                    .foregroundStyle(NB.ember1)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)

            actionButton
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon4)
        .task { await listen() }
        .onDisappear {
            rssiFrozen = true
            Task { await Band.live.stopFindHoop() }
        }
    }

    private var liveFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(statusLine)
                    .font(NBFont.dot(600, 11))
                    .tracking(0.28 * 11)
                    .foregroundStyle(NB.lime1)
                    .accessibilityIdentifier("find.status")

                HStack(alignment: .bottom, spacing: 8) {
                    Text(rssi.map(FindDistance.glyph) ?? Fmt.dash)
                        .font(NBFont.dot(700, 88))
                        .tracking(-0.06 * 88)
                        .foregroundStyle(NB.lime1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .accessibilityIdentifier("find.rssi")
                    Text(L("dBm"))
                        .font(NBFont.dot(500, 14))
                        .tracking(0.12 * 14)
                        .foregroundStyle(NB.white.opacity(0.42))
                        .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                ForEach(FindDistance.allCases, id: \.self) { lamp in
                    lampCell(lamp)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    /// Paper KXX-0. Last RSSI freezes. DONE is ember, not lime.
    private var timeoutFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("TIMEOUT"))
                    .font(NBFont.dot(600, 11))
                    .tracking(0.28 * 11)
                    .foregroundStyle(NB.ember1)
                    .accessibilityIdentifier("find.status")
                Text(L("Timed out"))
                    .font(NBFont.ui(700, 32))
                    .tracking(-0.03 * 32)
                    .foregroundStyle(NB.text1)
                Text(timeoutSentence)
                    .font(NBFont.ui(300, 14))
                    .lineSpacing(8)
                    .foregroundStyle(NB.white.opacity(0.50))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("RSSI"))
                    .font(NBFont.ui(500, 14))
                    .tracking(0.02 * 14)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                Text(rssi.map(FindDistance.glyph) ?? Fmt.dash)
                    .font(NBFont.dot(700, 28))
                    .tracking(-0.02 * 28)
                    .foregroundStyle(NB.text1)
                    .accessibilityIdentifier("find.rssi")
                Text(L("dBm"))
                    .font(NBFont.dot(500, 12))
                    .tracking(0.12 * 12)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .overlay(alignment: .top) { Hairline().frame(maxWidth: .infinity) }

            HStack(spacing: 8) {
                Text(L("Range"))
                    .font(NBFont.ui(500, 14))
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                rangePips
                Text(distance.map { L($0.label) } ?? Fmt.dash)
                    .font(NBFont.dot(600, 11))
                    .tracking(0.14 * 11)
                    .foregroundStyle(NB.lime1)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Hairline().frame(maxWidth: .infinity) }

            Text(L("LAST") + " · " + L("NOT LIVE"))
                .font(NBFont.dot(500, 11))
                .tracking(0.16 * 11)
                .foregroundStyle(NB.white.opacity(0.34))
                .padding(.horizontal, 24)
                .padding(.top, 12)
        }
    }

    private var timeoutSentence: String {
        if let rssi {
            return L("The band stopped on its own. Last heard %@ dBm.", FindDistance.glyph(rssi))
        }
        return L("The band stopped on its own.")
    }

    private var rangePips: some View {
        let lit = distance?.barsLit ?? 0
        let heights: [CGFloat] = [6, 9, 12, 16]
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(index < lit ? NB.lime1 : NB.white.opacity(0.14))
                    .frame(width: 12, height: heights[index])
            }
        }
        .frame(width: 72, height: 16, alignment: .bottom)
    }

    private var statusLine: String {
        switch beat {
        case .ready:   return L("READY") + " · " + L("LIVE")
        case .ringing: return L("ENTER") + " · " + L("RINGING")
        case .timeout: return L("LAST") + " · " + L("NOT LIVE")
        }
    }

    private var actionTitle: String {
        switch beat {
        case .ready:   return L("START")
        case .ringing: return L("STOP")
        case .timeout: return L("DONE")
        }
    }

    private var actionID: String {
        switch beat {
        case .ready:   return "find.start"
        case .ringing: return "find.stop"
        case .timeout: return "find.done"
        }
    }

    private var actionFill: Color {
        beat == .timeout ? NB.ember1 : NB.lime1
    }

    private var actionButton: some View {
        Button(action: tapAction) {
            Text(actionTitle)
                .font(NBFont.dot(700, 13))
                .tracking(0.2 * 13)
                .foregroundStyle(NB.carbon4)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(actionFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(starting && beat == .ready)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.12, maximumDistance: 64)
                .onEnded { _ in
                    if beat == .ringing { stopRing() }
                }
        )
        .accessibilityIdentifier(actionID)
    }

    private func lampCell(_ lamp: FindDistance) -> some View {
        let glow = FindDistance.glow(of: lamp, current: distance)
        return Text(L(lamp.label))
            .font(NBFont.dot(700, 10))
            .tracking(0.12 * 10)
            .foregroundStyle(lampInk(glow))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(8)
            .frame(height: 64)
            .background(lampFill(glow))
            .accessibilityIdentifier("find.lamp.\(lamp.label)")
            .accessibilityAddTraits(glow == .hot ? .isSelected : [])
    }

    private func lampFill(_ glow: FindLampGlow) -> Color {
        switch glow {
        case .hot:  NB.lime1
        case .warm: NB.lime1.opacity(0.40)
        case .off:  NB.hairline
        }
    }

    private func lampInk(_ glow: FindLampGlow) -> Color {
        switch glow {
        case .hot:  NB.carbon4
        case .warm: NB.white.opacity(0.60)
        case .off:  NB.white.opacity(0.33)
        }
    }

    private func tapAction() {
        switch beat {
        case .ready:
            Task { await startRing() }
        case .ringing:
            stopRing()
        case .timeout:
            dismiss()
        }
    }

    private func startRing() async {
        starting = true
        message = nil
        rssiFrozen = false
        defer { starting = false }
        do {
            try await Band.live.startFindHoop()
            if beat != .timeout { beat = .ringing }
        } catch {
            message = hoopMessage(error)
        }
    }

    /// Paint READY now. The band command is fire-and-forget — never wait 6s.
    /// RSSI stays live on READY; only Timeout / dismiss freeze the last number.
    private func stopRing() {
        beat = .ready
        message = nil
        Task { await Band.live.stopFindHoop() }
    }

    private func listen() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in Band.live.events {
                    if case .findHoop(let phase) = event {
                        await MainActor.run { apply(phase) }
                    }
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    let frozen = await MainActor.run { rssiFrozen }
                    if !frozen, let value = try? await Band.live.readConnectedRSSI() {
                        await MainActor.run {
                            if !rssiFrozen { rssi = value }
                        }
                    }
                    if await MainActor.run(body: { rssiFrozen }) { return }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            await group.waitForAll()
        }
    }

    private func apply(_ phase: FindHoopPhase) {
        switch phase {
        case .enter:
            beat = .ringing
        case .exit:
            if beat == .ringing { beat = .ready }
        case .timeout:
            guard beat == .ringing else { return }
            rssiFrozen = true
            beat = .timeout
        case .unsupported:
            message = BandError.unsupported("Find HOOP").localizedDescription
            beat = .ready
        }
    }

    private func hoopMessage(_ error: Error) -> String {
        if let band = error as? BandError, case .busy = band { return L("DEVICE BUSY") }
        return error.localizedDescription
    }
}
